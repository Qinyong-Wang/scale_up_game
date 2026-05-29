extends Node

## ProductSystem v2 — owns products. Per design/产品系统设计.md.
##
## Each product binds 1 published model + (optional) 1 chief_engineer lead +
## (optional) staff. Capability thresholds gate types via ProductTypeSpec.
## Quality is a derived float recomputed on action phase or when a bound
## model updates. UserSystem writes back subscribers via
## `product.update_subscribers`.


const OWNED_SLICES: Array[StringName] = [&"products"]

## Quality §6.2 constants (kept here, see 平衡参数.md for tuning).
const STAFF_BONUS_PER_ML_ENG: float = 0.05
## Per design/招聘系统设计.md §1.1 + 平衡参数.md §LEAD_BONUS_TABLE (2026-05 rev):
## mirrors chief_engineer.product_throughput coefficient. Quality-side
## bonus uses the same coef as throughput-side bonus, so they move together.
const LEAD_BONUS_FRACTION: float = 0.22
const QUALITY_CAP: float = 1.5

## Product type registry — keys here are accepted by `product.create`. Adding
## a new .tres template? Register it here.
const TYPE_PATHS: Dictionary = {
	&"chatbot": "res://resources/data/products/types/chatbot.tres",
	&"agent": "res://resources/data/products/types/agent.tres",
	&"multimodal_assistant": "res://resources/data/products/types/multimodal_assistant.tres",
	&"coding_agent": "res://resources/data/products/types/coding_agent.tres",
	&"api": "res://resources/data/products/types/api.tres",
}

## type_id → strings.csv 短标签 key。UI 下拉 tr() 它显示本地化类型名 (spec.display_name
## 是英文字面, 不走翻译)。key 后缀与 type_id 不完全一致 (历史命名), 故显式映射。
const TYPE_LABEL_KEY: Dictionary = {
	&"chatbot": "PRODUCT_TYPE_CHATBOT",
	&"agent": "PRODUCT_TYPE_AGENT",
	&"multimodal_assistant": "PRODUCT_TYPE_MULTIMODAL",
	&"coding_agent": "PRODUCT_TYPE_CODING",
	&"api": "PRODUCT_TYPE_API_SHORT",
}

var _next_product_seq: int = 1
var _type_cache: Dictionary = {}  # StringName -> ProductTypeSpec

func _ready() -> void:
	CommandBus.register(&"product.create", _on_create)
	CommandBus.register(&"product.update", _on_update)
	CommandBus.register(&"product.delete", _on_delete)
	CommandBus.register(&"product.update_subscribers", _on_update_subscribers)
	CommandBus.register(&"product.recompute_quality", _on_recompute_quality)
	CommandBus.register(&"product.list_unlocked_types", _on_list_unlocked_types)
	EventBus.phase_started.connect(_on_phase)
	EventBus.save_loaded.connect(_on_save_loaded)
	EventBus.model_updated.connect(func(_id, _delta): _recompute_all_quality())
	EventBus.model_published.connect(_on_model_published)
	EventBus.model_unpublished.connect(_on_model_unpublished)
	EventBus.lead_released.connect(_on_lead_released)

func _gen_product_id() -> StringName:
	var id := StringName("product_%04d" % _next_product_seq)
	_next_product_seq += 1
	return id

## _next_product_seq 是会话计数器, 不入存档。读档后恢复它 + 修旧档已有的重复
## product ID, 否则读档后新建的产品会和档里的撞 ID (find 取首个 → 营收 / 派单 /
## 删除解析到错的产品)。详见 design/数据集系统设计.md §3 同类病。
func _on_save_loaded() -> void:
	_next_product_seq = GameState.max_seq_for_prefix([GameState.products], "product_") + 1
	for ch in GameState.dedup_ids([GameState.products], _gen_product_id):
		Log.warn(&"product", "save_loaded_duplicate_product_id_repaired",
				{old_id = ch.old_id, new_id = ch.new_id})
	_recompute_all_quality()

# ---- create / update / delete -------------------------------------------

func _on_create(p: Dictionary) -> Dictionary:
	var type_id: StringName = p.get(&"type", &"chatbot")
	var spec := _get_type_spec(type_id)
	if spec == null:
		return {ok = false, error = &"unknown_type"}

	# §0bis api 分支: 跳过 capability 阈值 / application 节点 / lead 强制 / staff
	# 强制. 仅校验 model 存在 + published + 同 model 已存在 api 的限制.
	if type_id == &"api":
		return _create_api_product(p)

	# §6.1 application node prereq.
	if spec.application_node_required != &"":
		var u: Dictionary = CommandBus.send(&"tech.is_unlocked", {
			tree = &"application", node_id = spec.application_node_required,
		})
		if not bool(u.get(&"unlocked", false)):
			return {ok = false, error = &"application_node_locked"}

	var lead_id: StringName = p.get(&"lead_id", &"")
	var lead = null
	if lead_id != &"":
		lead = HiringSystem.find_lead(lead_id)
		if lead == null:
			return {ok = false, error = &"unknown_lead"}
		if not HiringSystem.lead_matches_specialty(lead, &"chief_engineer"):
			return {ok = false, error = &"lead_specialty_mismatch"}

	var bound_model_id: StringName = p.get(&"bound_model_id", &"")
	var m = ResearchSystem.find_model(bound_model_id)
	if m == null:
		return {ok = false, error = &"unknown_model"}
	if m.status != &"published":
		return {ok = false, error = &"model_not_published"}

	# §6.1 capability threshold check (after model is known).
	if not _meets_thresholds(m, spec):
		return {ok = false, error = &"capability_below_threshold"}

	var product_id: StringName = _gen_product_id()

	if lead_id != &"":
		var lock_r: Dictionary = CommandBus.send(&"hiring.assign_lead", {
			lead_id = lead_id, product_id = product_id,
		})
		if not lock_r.ok:
			return lock_r

	var staff: Dictionary = p.get(&"staff", {})
	var staff_locked: Array = []
	for role in staff.keys():
		var count: int = int(staff[role])
		var rs: Dictionary = CommandBus.send(&"hiring.lock_staff", {
			role = role, count = count, holder_id = product_id,
		})
		if not rs.ok:
			for entry in staff_locked:
				CommandBus.send(&"hiring.release_staff", {
					role = entry.role, count = entry.count, holder_id = product_id,
				})
			if lead_id != &"":
				CommandBus.send(&"hiring.unassign_lead", {lead_id = lead_id})
			return {ok = false, error = &"insufficient_staff"}
		staff_locked.append({role = role, count = count})

	var prod := Product.new()
	prod.id = product_id
	prod.display_name = p.get(&"display_name", String(product_id))
	prod.type = type_id
	prod.bound_model_id = bound_model_id
	prod.auto_track_latest = bool(p.get(&"auto_track_latest", true))
	prod.is_open_source = m.is_open_source
	prod.subscription_price = int(p.get(&"subscription_price", spec.default_subscription_price))
	prod.lead_id = lead_id
	prod.assigned_staff = staff.duplicate()
	prod.subscribers = 0
	prod.launched_at_turn = GameState.turn
	prod.quality = _compute_quality(prod)
	GameState.products.append(prod)
	Log.info(&"product", "created", {id = prod.id, type = type_id})
	EventBus.product_created.emit(prod.id)
	return {ok = true, product_id = prod.id}

func _on_update(p: Dictionary) -> Dictionary:
	var prod := find_product(p.get(&"product_id", &""))
	if prod == null:
		return {ok = false, error = &"unknown_product"}
	var fields: Dictionary = p.get(&"fields", {})
	var changed: Array = []
	if fields.has(&"price"):
		prod.subscription_price = int(fields[&"price"])
		changed.append(&"price")
	if fields.has(&"display_name"):
		prod.display_name = String(fields[&"display_name"])
		changed.append(&"display_name")
	if fields.has(&"auto_track_latest"):
		prod.auto_track_latest = bool(fields[&"auto_track_latest"])
		changed.append(&"auto_track_latest")
	if fields.has(&"bound_model_id"):
		var new_model_id: StringName = fields[&"bound_model_id"]
		var m = ResearchSystem.find_model(new_model_id)
		if m == null:
			return {ok = false, error = &"unknown_model"}
		if m.status != &"published":
			return {ok = false, error = &"model_not_published"}
		prod.bound_model_id = new_model_id
		prod.is_open_source = m.is_open_source
		changed.append(&"bound_model_id")
		prod.quality = _compute_quality(prod)
	if fields.has(&"staff"):
		var new_staff: Dictionary = fields[&"staff"]
		# Naive diff: release old, lock new — abort on lock failure.
		for role in prod.assigned_staff.keys():
			CommandBus.send(&"hiring.release_staff", {
				role = role, count = int(prod.assigned_staff[role]),
				holder_id = prod.id,
			})
		var locked: Array = []
		for role in new_staff.keys():
			var rs: Dictionary = CommandBus.send(&"hiring.lock_staff", {
				role = role, count = int(new_staff[role]), holder_id = prod.id,
			})
			if not rs.ok:
				# Revert: release what we locked, restore the old assignment.
				for entry in locked:
					CommandBus.send(&"hiring.release_staff", {
						role = entry.role, count = entry.count, holder_id = prod.id,
					})
				for role2 in prod.assigned_staff.keys():
					CommandBus.send(&"hiring.lock_staff", {
						role = role2, count = int(prod.assigned_staff[role2]),
						holder_id = prod.id,
					})
				return {ok = false, error = &"insufficient_staff"}
			locked.append({role = role, count = int(new_staff[role])})
		prod.assigned_staff = new_staff.duplicate()
		changed.append(&"staff")
		prod.quality = _compute_quality(prod)
	EventBus.product_updated.emit(prod.id, changed)
	return {ok = true}

func _on_delete(p: Dictionary) -> Dictionary:
	var prod := find_product(p.get(&"product_id", &""))
	if prod == null:
		return {ok = false, error = &"unknown_product"}
	if prod.lead_id != &"":
		CommandBus.send(&"hiring.unassign_lead", {lead_id = prod.lead_id})
	for role in prod.assigned_staff.keys():
		CommandBus.send(&"hiring.release_staff", {
			role = role, count = int(prod.assigned_staff[role]), holder_id = prod.id,
		})
	GameState.products.erase(prod)
	EventBus.product_deleted.emit(prod.id)
	return {ok = true}

func _on_update_subscribers(p: Dictionary) -> Dictionary:
	var prod := find_product(p.get(&"product_id", &""))
	if prod == null:
		return {ok = false, error = &"unknown_product"}
	var delta: int = int(p.get(&"delta", 0))
	var old: int = prod.subscribers
	var new_value: int = maxi(0, old + delta)
	# ProductTypeSpec.max_subscribers — 0 means no cap (api uses this).
	var spec := _get_type_spec(prod.type)
	if spec != null and spec.max_subscribers > 0 and new_value > spec.max_subscribers:
		new_value = spec.max_subscribers
	prod.subscribers = new_value
	EventBus.subscribers_changed.emit(prod.id, prod.subscribers - old, prod.subscribers)
	return {ok = true, new_subscribers = prod.subscribers}

func _on_recompute_quality(p: Dictionary) -> Dictionary:
	var prod := find_product(p.get(&"product_id", &""))
	if prod == null:
		return {ok = false, error = &"unknown_product"}
	prod.quality = _compute_quality(prod)
	EventBus.quality_recomputed.emit(prod.id, prod.quality)
	return {ok = true, quality = prod.quality}

func _on_list_unlocked_types(_p: Dictionary) -> Dictionary:
	var unlocked: Array = []
	for type_id in TYPE_PATHS.keys():
		var spec := _get_type_spec(type_id)
		if spec == null:
			continue
		# Application-tree gate.
		if spec.application_node_required != &"":
			var u: Dictionary = CommandBus.send(&"tech.is_unlocked", {
				tree = &"application", node_id = spec.application_node_required,
			})
			if not bool(u.get(&"unlocked", false)):
				continue
		# Need at least one published model meeting all axes.
		var any_match: bool = false
		for m in GameState.models:
			if m.status != &"published":
				continue
			if _meets_thresholds(m, spec):
				any_match = true
				break
		if any_match:
			unlocked.append(type_id)
	return {ok = true, types = unlocked}

# ---- phase --------------------------------------------------------------

func _on_phase(phase: StringName, _turn: int) -> void:
	if phase == &"action":
		_recompute_all_quality()

func _recompute_all_quality() -> void:
	for prod in GameState.products:
		var old: float = prod.quality
		prod.quality = _compute_quality(prod)
		if absf(prod.quality - old) > 0.001:
			EventBus.quality_recomputed.emit(prod.id, prod.quality)

func _on_lead_released(lead_id: StringName) -> void:
	# Defensive: if a product's lead was somehow released, drop the product.
	for prod in GameState.products.duplicate():
		if prod.lead_id == lead_id:
			_on_delete({product_id = prod.id})

func _on_model_published(model_id: StringName, is_open_source: bool) -> void:
	# §3 auto_track_latest: rebind any product that follows the latest of the
	# matching kind (open vs closed) and whose type thresholds are met by the
	# newly published model.
	var m = ResearchSystem.find_model(model_id)
	if m == null:
		return
	for prod in GameState.products:
		if not prod.auto_track_latest:
			continue
		if prod.is_open_source != is_open_source:
			continue
		var spec := _get_type_spec(prod.type)
		if spec == null:
			continue
		if not _meets_thresholds(m, spec):
			continue
		if prod.bound_model_id == model_id:
			continue
		prod.bound_model_id = model_id
		prod.is_open_source = m.is_open_source
		prod.quality = _compute_quality(prod)
		EventBus.product_updated.emit(prod.id, [&"bound_model_id"])
	# §0bis: auto-create api 产品, 给玩家一个默认 API 开关.
	_auto_create_api_product_for(model_id)

func _on_model_unpublished(model_id: StringName) -> void:
	# §0bis: model 下架时, 静默删掉对应 api 产品. 其它 (订阅) 产品仍可阻止
	# unpublish — ResearchSystem 已在 _has_product_binding 检查里这么做了.
	for prod in GameState.products.duplicate():
		if prod.type == &"api" and prod.bound_model_id == model_id:
			_on_delete({product_id = prod.id})

func _auto_create_api_product_for(model_id: StringName) -> void:
	# Idempotent: 若该 model 已有 api 产品 (例如 unpublish→republish 路径)
	# 就什么也不做.
	for prod in GameState.products:
		if prod.type == &"api" and prod.bound_model_id == model_id:
			return
	var r: Dictionary = _create_api_product({
		bound_model_id = model_id,
	})
	if not r.get(&"ok", false):
		Log.warn(&"product", "auto_create_api_failed", {model_id = model_id, error = r.get(&"error", &"")})

# §0bis: 创建 type=api 的产品. lead/staff 可选; subscription_price 强制 0;
# 同 model 已有 api 产品时报 duplicate_api_product.
func _create_api_product(p: Dictionary) -> Dictionary:
	var bound_model_id: StringName = p.get(&"bound_model_id", &"")
	var m = ResearchSystem.find_model(bound_model_id)
	if m == null:
		return {ok = false, error = &"unknown_model"}
	if m.status != &"published":
		return {ok = false, error = &"model_not_published"}
	for existing in GameState.products:
		if existing.type == &"api" and existing.bound_model_id == bound_model_id:
			return {ok = false, error = &"duplicate_api_product"}

	var product_id: StringName = StringName("product_api_%s" % String(bound_model_id))
	# 防 id 冲突: 若已存在同名记录 (理论不应), fallback 到 seq.
	for existing in GameState.products:
		if existing.id == product_id:
			product_id = _gen_product_id()
			break

	var lead_id: StringName = p.get(&"lead_id", &"")
	if lead_id != &"":
		var lead = HiringSystem.find_lead(lead_id)
		if lead == null:
			return {ok = false, error = &"unknown_lead"}
		var lock_r: Dictionary = CommandBus.send(&"hiring.assign_lead", {
			lead_id = lead_id, product_id = product_id,
		})
		if not lock_r.ok:
			return lock_r

	var staff: Dictionary = p.get(&"staff", {})
	var staff_locked: Array = []
	for role in staff.keys():
		var count: int = int(staff[role])
		var rs: Dictionary = CommandBus.send(&"hiring.lock_staff", {
			role = role, count = count, holder_id = product_id,
		})
		if not rs.ok:
			for entry in staff_locked:
				CommandBus.send(&"hiring.release_staff", {
					role = entry.role, count = entry.count, holder_id = product_id,
				})
			if lead_id != &"":
				CommandBus.send(&"hiring.unassign_lead", {lead_id = lead_id})
			return {ok = false, error = &"insufficient_staff"}
		staff_locked.append({role = role, count = count})

	var prod := Product.new()
	prod.id = product_id
	prod.display_name = "API for " + String(bound_model_id)
	prod.type = &"api"
	prod.bound_model_id = bound_model_id
	prod.auto_track_latest = false
	prod.is_open_source = m.is_open_source
	prod.subscription_price = 0
	prod.lead_id = lead_id
	prod.assigned_staff = staff.duplicate()
	prod.subscribers = 0
	prod.launched_at_turn = GameState.turn
	prod.quality = 0.0
	GameState.products.append(prod)
	Log.info(&"product", "api_created", {id = prod.id, model = bound_model_id})
	EventBus.product_created.emit(prod.id)
	return {ok = true, product_id = prod.id}

# ---- helpers ------------------------------------------------------------

func find_product(product_id: StringName) -> Product:
	for p in GameState.products:
		if p.id == product_id:
			return p
	return null

func get_type_spec(type_id: StringName) -> ProductTypeSpec:
	return _get_type_spec(type_id)

func _get_type_spec(type_id: StringName) -> ProductTypeSpec:
	if _type_cache.has(type_id):
		return _type_cache[type_id]
	var path: String = TYPE_PATHS.get(type_id, "")
	if path == "":
		return null
	var res = load(path)
	if res == null:
		return null
	_type_cache[type_id] = res
	return res

func _meets_thresholds(model, spec: ProductTypeSpec) -> bool:
	for axis in spec.unlock_thresholds.keys():
		var need: float = float(spec.unlock_thresholds[axis])
		var have: float = float(model.capability.get(axis, 0.0))
		if have < need:
			return false
	return true

## §6.2 quality formula:
##   model_factor = capability_total / 100
##   lead_factor  = 1 + (ability/100) * LEAD_BONUS_FRACTION (0.22) if specialty matches
##   staff_factor = 1 + STAFF_BONUS_PER_ML_ENG * ml_eng_count
##   quality      = clamp(model_factor * lead_factor * staff_factor, 0, 1.5)
func _compute_quality(prod: Product) -> float:
	var m = ResearchSystem.find_model(prod.bound_model_id)
	if m == null:
		return 0.0
	var cap_total: float = 0.0
	for v in m.capability.values():
		cap_total += float(v)
	var model_factor: float = cap_total / 100.0
	var lead_factor: float = 1.0
	var spec := _get_type_spec(prod.type)
	if prod.lead_id != &"" and spec != null and spec.lead_specialty_bonus != &"":
		var lead = HiringSystem.find_lead(prod.lead_id)
		if lead != null and lead.specialty == spec.lead_specialty_bonus:
			lead_factor = 1.0 + (float(lead.ability) / 100.0) * LEAD_BONUS_FRACTION
	var ml_eng: int = int(prod.assigned_staff.get(&"ml_eng", 0))
	var staff_factor: float = 1.0 + STAFF_BONUS_PER_ML_ENG * float(ml_eng)
	return clampf(model_factor * lead_factor * staff_factor, 0.0, QUALITY_CAP)
