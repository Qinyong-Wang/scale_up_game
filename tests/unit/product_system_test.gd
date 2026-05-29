extends GutTest

## ProductSystem v1 — create, update, delete, subscribers, quality.
## Per design/产品系统设计.md.


func before_each() -> void:
	GameState.reset()

func _make_chief_engineer() -> StringName:
	var l := Lead.new()
	l.id = &"lead_ce_01"
	l.display_name = "CE"
	l.specialty = &"chief_engineer"
	l.level = &"A"
	l.ability = 75.0
	l.signing_fee = 0
	l.weekly_salary = 1150
	GameState.leads.append(l)
	return l.id

func _make_published_model() -> StringName:
	var r: Dictionary = CommandBus.send(&"research.add_model", {
		capability = {}, arch = &"ant_v1", dataset_ids = []})
	# Evaluate first so publish_model accepts it (research.publish_model requires
	# status==evaluated + !capability_stale).
	CommandBus.send(&"research.evaluate_apply", {
		model_id = r.model_id,
		capability_measured = {&"general": 60.0, &"code": 30.0}})
	CommandBus.send(&"research.publish_model", {
		model_id = r.model_id, is_open_source = false, per_token_price = 0.001})
	return r.model_id

# ---- create -------------------------------------------------------------

func test_create_unknown_lead_returns_error() -> void:
	var r: Dictionary = CommandBus.send(&"product.create", {
		type = &"chatbot", lead_id = &"none", bound_model_id = &"x",
		subscription_price = 99, staff = {}})
	assert_false(r.ok)
	assert_eq(r.error, &"unknown_lead")

func test_create_lead_specialty_mismatch_returns_error() -> void:
	# Use a chief_scientist where chief_engineer is required.
	var l := Lead.new()
	l.id = &"l1"; l.specialty = &"chief_scientist"; l.level = &"A"; l.ability = 70.0
	GameState.leads.append(l)
	var mid := _make_published_model()
	var r: Dictionary = CommandBus.send(&"product.create", {
		type = &"chatbot", lead_id = l.id, bound_model_id = mid,
		subscription_price = 99, staff = {}})
	assert_false(r.ok)
	assert_eq(r.error, &"lead_specialty_mismatch")

func test_create_unpublished_model_returns_error() -> void:
	var lid := _make_chief_engineer()
	var rm: Dictionary = CommandBus.send(&"research.add_model", {
		capability = {&"general": 60.0}, arch = &"ant_v1", dataset_ids = []})
	var r: Dictionary = CommandBus.send(&"product.create", {
		type = &"chatbot", lead_id = lid, bound_model_id = rm.model_id,
		subscription_price = 99, staff = {}})
	assert_false(r.ok)
	assert_eq(r.error, &"model_not_published")

func test_create_agent_without_unlock_returns_error() -> void:
	# §6.1 + 公共枚举表 §9: agent type requires application/tool_use unlocked.
	var lid := _make_chief_engineer()
	var mid := _make_published_model()
	var r: Dictionary = CommandBus.send(&"product.create", {
		type = &"agent", lead_id = lid, bound_model_id = mid,
		subscription_price = 99, staff = {}})
	assert_false(r.ok)
	assert_eq(r.error, &"application_node_locked")

func test_create_with_insufficient_staff_returns_error() -> void:
	var lid := _make_chief_engineer()
	var mid := _make_published_model()
	var r: Dictionary = CommandBus.send(&"product.create", {
		type = &"chatbot", lead_id = lid, bound_model_id = mid,
		subscription_price = 99, staff = {&"ml_eng": 5}})
	assert_false(r.ok)
	assert_eq(r.error, &"insufficient_staff")

func test_create_locks_lead_and_appends_product() -> void:
	var lid := _make_chief_engineer()
	var mid := _make_published_model()  # also auto-creates api product (§0bis)
	CommandBus.send(&"hiring.adjust_staff", {role = &"ml_eng", delta = 2})
	var r: Dictionary = CommandBus.send(&"product.create", {
		type = &"chatbot", lead_id = lid, bound_model_id = mid,
		subscription_price = 99, staff = {&"ml_eng": 1}})
	assert_true(r.ok)
	# 1 chatbot + 1 auto-created api = 2.
	assert_eq(GameState.products.size(), 2)
	var non_api: int = 0
	for p in GameState.products:
		if p.type != &"api":
			non_api += 1
	assert_eq(non_api, 1, "玩家显式 create 的非 api 产品恰好 1 个")
	assert_eq(HiringSystem.find_lead(lid).assigned_to_product_id, r.product_id)
	assert_eq(GameState.staff_busy[&"ml_eng"], 1)

# ---- update / delete / subscribers --------------------------------------

func test_update_subscribers_unknown_returns_error() -> void:
	var r: Dictionary = CommandBus.send(&"product.update_subscribers", {
		product_id = &"x", delta = 10})
	assert_false(r.ok)
	assert_eq(r.error, &"unknown_product")

func test_update_subscribers_clamps_at_zero() -> void:
	var lid := _make_chief_engineer()
	var mid := _make_published_model()
	var r1: Dictionary = CommandBus.send(&"product.create", {
		type = &"chatbot", lead_id = lid, bound_model_id = mid,
		subscription_price = 99, staff = {}})
	CommandBus.send(&"product.update_subscribers", {product_id = r1.product_id, delta = -100})
	assert_eq(ProductSystem.find_product(r1.product_id).subscribers, 0)

## ProductTypeSpec.max_subscribers: 订阅类产品有用户数硬上限 (chatbot 2B,
## agent / multimodal 1B, coding 200M). update_subscribers 写入时夹住, 即使
## UserSystem 或事件卡试图加超过上限的 delta 也只会落到 cap 上。
func test_update_subscribers_clamps_at_type_cap_chatbot() -> void:
	var lid := _make_chief_engineer()
	var mid := _make_published_model()
	var r1: Dictionary = CommandBus.send(&"product.create", {
		type = &"chatbot", lead_id = lid, bound_model_id = mid,
		subscription_price = 99, staff = {}})
	# Chatbot cap = 2B. 试图加 3B → 实际落到 2B.
	CommandBus.send(&"product.update_subscribers", {
		product_id = r1.product_id, delta = 3_000_000_000})
	assert_eq(ProductSystem.find_product(r1.product_id).subscribers, 2_000_000_000,
			"chatbot subscribers 应被夹到 max_subscribers (2B)")
	# 再加任何正数都应保持上限.
	CommandBus.send(&"product.update_subscribers", {
		product_id = r1.product_id, delta = 1_000_000})
	assert_eq(ProductSystem.find_product(r1.product_id).subscribers, 2_000_000_000)
	# 下降仍生效.
	CommandBus.send(&"product.update_subscribers", {
		product_id = r1.product_id, delta = -500_000_000})
	assert_eq(ProductSystem.find_product(r1.product_id).subscribers, 1_500_000_000)

## API 产品 max_subscribers = 0 → 不夹 (api.subscribers 是需求池单位, 不是真实用户).
func test_update_subscribers_api_has_no_cap() -> void:
	var mid := _make_published_model()  # 自动建 api 产品
	var ap = null
	for p in GameState.products:
		if p.type == &"api" and p.bound_model_id == mid:
			ap = p
			break
	assert_not_null(ap)
	CommandBus.send(&"product.update_subscribers", {
		product_id = ap.id, delta = 5_000_000_000})
	assert_eq(ProductSystem.find_product(ap.id).subscribers, 5_000_000_000,
			"api 产品不应被 cap 夹")

func test_delete_releases_lead_and_staff() -> void:
	var lid := _make_chief_engineer()
	var mid := _make_published_model()  # auto-creates 1 api product
	CommandBus.send(&"hiring.adjust_staff", {role = &"ml_eng", delta = 2})
	var r1: Dictionary = CommandBus.send(&"product.create", {
		type = &"chatbot", lead_id = lid, bound_model_id = mid,
		subscription_price = 99, staff = {&"ml_eng": 1}})
	CommandBus.send(&"product.delete", {product_id = r1.product_id})
	# 仅 chatbot 删了, api 产品仍在.
	assert_eq(GameState.products.size(), 1)
	assert_eq(GameState.products[0].type, &"api")
	assert_eq(HiringSystem.find_lead(lid).assigned_to_product_id, &"")
	assert_eq(GameState.staff_busy[&"ml_eng"], 0)

func test_delete_unknown_returns_error() -> void:
	var r: Dictionary = CommandBus.send(&"product.delete", {product_id = &"x"})
	assert_false(r.ok)
	assert_eq(r.error, &"unknown_product")

# ---- new: type validation + thresholds + list_unlocked_types ------------

func test_create_unknown_type_returns_error() -> void:
	var lid := _make_chief_engineer()
	var mid := _make_published_model()
	var r: Dictionary = CommandBus.send(&"product.create", {
		type = &"banana_bot", lead_id = lid, bound_model_id = mid,
		subscription_price = 99, staff = {}})
	assert_false(r.ok)
	assert_eq(r.error, &"unknown_type")

func test_create_capability_below_threshold_returns_error() -> void:
	# coding_agent now requires fox_code_specialist (application tree) AND
	# code >= 70 (公共枚举表 §9). Unlock the node first so we exercise the
	# threshold check rather than the application-node check.
	GameState.unlocks[&"application"][&"fox_code_specialist"] = true
	var lid := _make_chief_engineer()
	var mid := _make_published_model()  # code = 30, below 70
	var r: Dictionary = CommandBus.send(&"product.create", {
		type = &"coding_agent", lead_id = lid, bound_model_id = mid,
		subscription_price = 99, staff = {}})
	assert_false(r.ok)
	assert_eq(r.error, &"capability_below_threshold")

func test_create_agent_with_application_unlock_and_capability_succeeds() -> void:
	# Per 公共枚举表 §9 + agent.tres: agent requires application/tool_use
	# unlocked AND reasoning >= 50 on the bound model.
	GameState.unlocks[&"application"][&"tool_use"] = true
	var lid := _make_chief_engineer()
	var rm: Dictionary = CommandBus.send(&"research.add_model", {
		capability = {}, arch = &"ant_v1", dataset_ids = []})
	CommandBus.send(&"research.evaluate_apply", {
		model_id = rm.model_id,
		capability_measured = {&"general": 80.0, &"reasoning": 60.0}})
	CommandBus.send(&"research.publish_model", {
		model_id = rm.model_id, is_open_source = false, per_token_price = 0.001})
	var r: Dictionary = CommandBus.send(&"product.create", {
		type = &"agent", lead_id = lid, bound_model_id = rm.model_id,
		subscription_price = 199, staff = {}})
	assert_true(r.ok, "agent create should succeed once unlocked & capable: %s" % r)

func test_list_unlocked_types_with_no_models_is_empty() -> void:
	var r: Dictionary = CommandBus.send(&"product.list_unlocked_types", {})
	assert_true(r.ok)
	assert_eq((r.types as Array).size(), 0)

func test_list_unlocked_types_includes_chatbot_when_model_meets_threshold() -> void:
	_make_published_model()  # general=60 → meets chatbot threshold (general=30)
	var r: Dictionary = CommandBus.send(&"product.list_unlocked_types", {})
	assert_true(r.ok)
	assert_true((r.types as Array).has(&"chatbot"))
	# agent requires tool_use (locked) → excluded.
	assert_false((r.types as Array).has(&"agent"))

func test_list_unlocked_types_filters_application_node() -> void:
	# Model meets agent thresholds but tool_use is locked → excluded.
	var rm: Dictionary = CommandBus.send(&"research.add_model", {
		capability = {}, arch = &"ant_v1", dataset_ids = []})
	CommandBus.send(&"research.evaluate_apply", {
		model_id = rm.model_id,
		capability_measured = {&"general": 80.0, &"reasoning": 60.0}})
	CommandBus.send(&"research.publish_model", {
		model_id = rm.model_id, is_open_source = false, per_token_price = 0.001})
	var r1: Dictionary = CommandBus.send(&"product.list_unlocked_types", {})
	assert_false((r1.types as Array).has(&"agent"))
	GameState.unlocks[&"application"][&"tool_use"] = true
	var r2: Dictionary = CommandBus.send(&"product.list_unlocked_types", {})
	assert_true((r2.types as Array).has(&"agent"))

# ---- 产品系统设计 §0bis: API as product 类型 ----------------------------

func _find_api_product_for(model_id: StringName):
	for p in GameState.products:
		if p.type == &"api" and p.bound_model_id == model_id:
			return p
	return null

func test_publish_model_auto_creates_api_product() -> void:
	# §0bis + §2 约定: research.publish_model 成功后, ProductSystem 监听
	# model_published 信号, 自动给该 model 建一个 type=api 的产品.
	var mid := _make_published_model()
	var ap = _find_api_product_for(mid)
	assert_not_null(ap, "publish_model 后应有自动创建的 api 产品")
	assert_eq(ap.type, &"api")
	assert_eq(ap.bound_model_id, mid)
	assert_eq(ap.subscribers, 0)
	assert_eq(ap.subscription_price, 0)
	assert_false(ap.auto_track_latest)

func test_create_api_product_without_lead_or_staff_succeeds() -> void:
	# §0bis: api 产品不要求 lead / staff / capability 阈值.
	# 先把 auto-create 的删掉, 再玩家手动 create 一次.
	var mid := _make_published_model()
	var auto_ap = _find_api_product_for(mid)
	CommandBus.send(&"product.delete", {product_id = auto_ap.id})
	var r: Dictionary = CommandBus.send(&"product.create", {
		type = &"api", bound_model_id = mid})
	assert_true(r.ok, "api create no lead/staff: %s" % r)
	var p = ProductSystem.find_product(r.product_id)
	assert_eq(p.type, &"api")
	assert_eq(p.subscription_price, 0, "api 产品 subscription_price 强制 0")
	assert_false(p.auto_track_latest, "api 产品 auto_track_latest 强制 false")

func test_create_api_product_duplicate_returns_error() -> void:
	# §2 约束: 同一个 model 只允许一个 api 产品.
	var mid := _make_published_model()
	# auto-create 已经放一个了; 再 create 应该报 duplicate_api_product.
	var r: Dictionary = CommandBus.send(&"product.create", {
		type = &"api", bound_model_id = mid})
	assert_false(r.ok)
	assert_eq(r.error, &"duplicate_api_product")

func test_create_api_product_with_unpublished_model_errors() -> void:
	var rm: Dictionary = CommandBus.send(&"research.add_model", {
		capability = {}, arch = &"ant_v1", dataset_ids = []})
	var r: Dictionary = CommandBus.send(&"product.create", {
		type = &"api", bound_model_id = rm.model_id})
	assert_false(r.ok)
	assert_eq(r.error, &"model_not_published")

func test_create_api_product_unknown_model_errors() -> void:
	var r: Dictionary = CommandBus.send(&"product.create", {
		type = &"api", bound_model_id = &"nonexistent"})
	assert_false(r.ok)
	assert_eq(r.error, &"unknown_model")

func test_create_api_product_ignores_capability_thresholds() -> void:
	# §0bis: api 产品任何 published 模型都能开, 没 capability 阈值.
	# 用一个极弱的模型 (general=1, code=0, ...) — 远低于其他 type 的阈值.
	var rm: Dictionary = CommandBus.send(&"research.add_model", {
		capability = {}, arch = &"ant_v1", dataset_ids = []})
	CommandBus.send(&"research.evaluate_apply", {
		model_id = rm.model_id,
		capability_measured = {&"general": 1.0}})  # too weak for chatbot threshold
	CommandBus.send(&"research.publish_model", {
		model_id = rm.model_id, is_open_source = false, per_token_price = 0.001})
	# auto-create 已经做过, 删了再玩家试.
	var auto_ap = _find_api_product_for(rm.model_id)
	if auto_ap != null:
		CommandBus.send(&"product.delete", {product_id = auto_ap.id})
	var r: Dictionary = CommandBus.send(&"product.create", {
		type = &"api", bound_model_id = rm.model_id})
	assert_true(r.ok, "弱模型 api 应当能开, got: %s" % r)

func test_create_api_product_ignores_subscription_price_input() -> void:
	# §0bis: api 产品 subscription_price 入参被忽略, 强制 0.
	var mid := _make_published_model()
	var auto_ap = _find_api_product_for(mid)
	CommandBus.send(&"product.delete", {product_id = auto_ap.id})
	var r: Dictionary = CommandBus.send(&"product.create", {
		type = &"api", bound_model_id = mid, subscription_price = 9999})
	assert_true(r.ok)
	var p = ProductSystem.find_product(r.product_id)
	assert_eq(p.subscription_price, 0)

func test_unpublish_model_auto_deletes_api_product_only() -> void:
	# §2 约定: unpublish 时 api 产品静默删, 非 api 产品仍然阻止 unpublish.
	GameState.unlocks[&"application"][&"tool_use"] = true
	var lid := _make_chief_engineer()
	# 注意 _make_published_model 给 capability {general=60, code=30}; 不够 agent (需 reasoning>=50).
	# 单独造一个 published model 满足 agent 阈值, 配 chatbot product 测试.
	var mid := _make_published_model()
	# auto-created api product exists.
	var auto_ap = _find_api_product_for(mid)
	assert_not_null(auto_ap)
	# 加一个 chatbot 产品也绑这个 model.
	var chat_r: Dictionary = CommandBus.send(&"product.create", {
		type = &"chatbot", lead_id = lid, bound_model_id = mid,
		subscription_price = 99, staff = {}})
	assert_true(chat_r.ok)
	# unpublish 应失败 (in_use_by_product).
	var unpub: Dictionary = CommandBus.send(&"research.unpublish_model", {model_id = mid})
	assert_false(unpub.ok)
	assert_eq(unpub.error, &"in_use_by_product")
	# 删除 chatbot 产品, 再 unpublish.
	CommandBus.send(&"product.delete", {product_id = chat_r.product_id})
	unpub = CommandBus.send(&"research.unpublish_model", {model_id = mid})
	assert_true(unpub.ok, "无非 api 产品阻挡时 unpublish 应成功: %s" % unpub)
	# api 产品应已被静默删掉.
	assert_null(_find_api_product_for(mid), "unpublish 后 api 产品应被清掉")

# ---- new: auto_track_latest rebind on model_published -------------------

func _publish_extra_model(general: float, is_open_source: bool) -> StringName:
	var rm: Dictionary = CommandBus.send(&"research.add_model", {
		capability = {}, arch = &"ant_v1", dataset_ids = []})
	CommandBus.send(&"research.evaluate_apply", {
		model_id = rm.model_id,
		capability_measured = {&"general": general}})
	CommandBus.send(&"research.publish_model", {
		model_id = rm.model_id, is_open_source = is_open_source,
		per_token_price = 0.0 if is_open_source else 0.001})
	return rm.model_id

func test_auto_track_latest_rebinds_to_new_published_closed_model() -> void:
	var lid := _make_chief_engineer()
	var mid1 := _make_published_model()  # closed, general=60
	var c: Dictionary = CommandBus.send(&"product.create", {
		type = &"chatbot", lead_id = lid, bound_model_id = mid1,
		subscription_price = 99, staff = {}, auto_track_latest = true})
	assert_true(c.ok)
	# Publish a second closed model meeting chatbot threshold.
	var mid2 := _publish_extra_model(90.0, false)
	var prod = ProductSystem.find_product(c.product_id)
	assert_eq(prod.bound_model_id, mid2)

func test_auto_track_latest_does_not_cross_open_closed_kind() -> void:
	var lid := _make_chief_engineer()
	var mid1 := _make_published_model()  # closed
	var c: Dictionary = CommandBus.send(&"product.create", {
		type = &"chatbot", lead_id = lid, bound_model_id = mid1,
		subscription_price = 99, staff = {}, auto_track_latest = true})
	# Publish an OPEN model — closed product should NOT switch to it.
	_publish_extra_model(90.0, true)
	var prod = ProductSystem.find_product(c.product_id)
	assert_eq(prod.bound_model_id, mid1)

func test_auto_track_latest_false_keeps_old_binding() -> void:
	var lid := _make_chief_engineer()
	var mid1 := _make_published_model()
	var c: Dictionary = CommandBus.send(&"product.create", {
		type = &"chatbot", lead_id = lid, bound_model_id = mid1,
		subscription_price = 99, staff = {}, auto_track_latest = false})
	_publish_extra_model(90.0, false)
	var prod = ProductSystem.find_product(c.product_id)
	assert_eq(prod.bound_model_id, mid1)

# ---- new: quality formula §6.2 ------------------------------------------

func test_quality_formula_baseline_zero_ability_no_staff() -> void:
	# CE with ability 0 → lead_factor = 1 + 0 = 1; no staff → staff_factor = 1.
	# model_factor = (60+30)/100 = 0.9 ⇒ quality = 0.9.
	var mid := _make_published_model()
	var l2 := Lead.new()
	l2.id = &"l_ce_q0"; l2.specialty = &"chief_engineer"; l2.level = &"A"; l2.ability = 0.0
	GameState.leads.append(l2)
	var c: Dictionary = CommandBus.send(&"product.create", {
		type = &"chatbot", lead_id = l2.id, bound_model_id = mid,
		subscription_price = 99, staff = {}})
	assert_true(c.ok)
	var prod = ProductSystem.find_product(c.product_id)
	assert_almost_eq(prod.quality, 0.9, 0.001)

func test_quality_formula_lead_bonus_applies_only_for_matching_specialty() -> void:
	# 2026-05 rev: chief_engineer.product_throughput = 0.22.
	# chatbot expects chief_engineer for bonus. ability=75 → 1 + 0.75*0.22 = 1.165.
	var lid := _make_chief_engineer()  # ability 75
	var mid := _make_published_model()  # cap_total = 90
	var c: Dictionary = CommandBus.send(&"product.create", {
		type = &"chatbot", lead_id = lid, bound_model_id = mid,
		subscription_price = 99, staff = {}})
	var prod = ProductSystem.find_product(c.product_id)
	# 0.9 * 1.165 = 1.0485
	assert_almost_eq(prod.quality, 1.0485, 0.001)

# ---- save_loaded: product ID 计数器恢复 + 重复修复 (读档撞 ID 防御) -----

func _seed_product(id: StringName) -> Product:
	var prod := Product.new()
	prod.id = id
	return prod

func test_save_loaded_restores_product_id_counter() -> void:
	GameState.products.append(_seed_product(&"product_0006"))
	EventBus.save_loaded.emit()
	var new_id := ProductSystem._gen_product_id()
	assert_gt(String(new_id).trim_prefix("product_").to_int(), 6,
			"读档后新发的 product ID 不能复用 ≤0006 (实际 %s)" % new_id)

func test_save_loaded_repairs_duplicate_product_ids() -> void:
	GameState.products.append(_seed_product(&"product_0001"))
	GameState.products.append(_seed_product(&"product_0001"))
	EventBus.save_loaded.emit()
	var seen := {}
	for prod in GameState.products:
		assert_false(seen.has(prod.id), "product id %s 读档后仍重复" % prod.id)
		seen[prod.id] = true

func test_quality_formula_staff_bonus_per_ml_eng() -> void:
	# 0.9 * 1.165 * (1 + 0.05*2) = 0.9 * 1.165 * 1.1 = 1.15335
	var lid := _make_chief_engineer()
	var mid := _make_published_model()
	CommandBus.send(&"hiring.adjust_staff", {role = &"ml_eng", delta = 2})
	var c: Dictionary = CommandBus.send(&"product.create", {
		type = &"chatbot", lead_id = lid, bound_model_id = mid,
		subscription_price = 99, staff = {&"ml_eng": 2}})
	var prod = ProductSystem.find_product(c.product_id)
	assert_almost_eq(prod.quality, 1.15335, 0.001)
