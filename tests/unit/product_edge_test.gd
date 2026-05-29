extends GutTest

## ProductSystem v1 — 边界与 update / 信号补测.
## Per design/产品系统设计.md.


func before_each() -> void:
	GameState.reset()

func _add_chief_engineer() -> StringName:
	var lead := Lead.new()
	lead.id = &"lead_ce_01"
	lead.specialty = &"chief_engineer"
	lead.level = &"A"
	lead.ability = 80.0
	GameState.leads.append(lead)
	return lead.id

func _add_published_model() -> StringName:
	var r: Dictionary = CommandBus.send(&"research.add_model", {
		capability = {}, arch = &"ant_v1", dataset_ids = []})
	CommandBus.send(&"research.evaluate_apply", {
		model_id = r.model_id, capability_measured = {&"general": 50.0}})
	CommandBus.send(&"research.publish_model", {
		model_id = r.model_id, is_open_source = false, per_token_price = 0.001})
	return r.model_id

func _create_product(staff: Dictionary = {}) -> Dictionary:
	var lid := _add_chief_engineer()
	var mid := _add_published_model()
	for role in staff.keys():
		CommandBus.send(&"hiring.adjust_staff",
				{role = role, delta = int(staff[role])})
	return CommandBus.send(&"product.create", {
		type = &"chatbot", lead_id = lid, bound_model_id = mid,
		subscription_price = 99, staff = staff,
	})

# ---- create 信号 -------------------------------------------------------

func test_create_emits_product_created() -> void:
	watch_signals(EventBus)
	var r: Dictionary = _create_product()
	assert_signal_emitted(EventBus, "product_created")
	var p: Array = get_signal_parameters(EventBus, "product_created")
	assert_eq(p[0], r.product_id)

func test_create_locks_assigned_staff() -> void:
	# §产品 §1: assigned_staff 反映 product 占用的人头.
	_create_product({&"ml_eng": 2})
	# staff_busy 应记 2
	assert_eq(int(GameState.staff_busy[&"ml_eng"]), 2)

func test_create_initial_subscribers_is_zero() -> void:
	var r: Dictionary = _create_product()
	for prod in GameState.products:
		if prod.id == r.product_id:
			assert_eq(prod.subscribers, 0)

func test_create_records_launched_at_turn() -> void:
	GameState.turn = 6
	var r: Dictionary = _create_product()
	for prod in GameState.products:
		if prod.id == r.product_id:
			assert_eq(prod.launched_at_turn, 6)

# ---- update -----------------------------------------------------------

func test_update_unknown_product_returns_error() -> void:
	var r: Dictionary = CommandBus.send(&"product.update",
			{product_id = &"nope", fields = {&"price": 199}})
	assert_false(r.ok)
	assert_eq(r.error, &"unknown_product")

func test_update_price_persists_and_emits_product_updated() -> void:
	var c: Dictionary = _create_product()
	watch_signals(EventBus)
	CommandBus.send(&"product.update",
			{product_id = c.product_id, fields = {&"price": 199}})
	var prod = ProductSystem.find_product(c.product_id)
	assert_eq(prod.subscription_price, 199)
	assert_signal_emitted(EventBus, "product_updated")
	var p: Array = get_signal_parameters(EventBus, "product_updated")
	assert_true((p[1] as Array).has(&"price"))

func test_update_display_name_persists() -> void:
	var c: Dictionary = _create_product()
	CommandBus.send(&"product.update",
			{product_id = c.product_id, fields = {&"display_name": "ChatBot Plus"}})
	var prod = ProductSystem.find_product(c.product_id)
	assert_eq(prod.display_name, "ChatBot Plus")

func test_update_bound_model_to_unpublished_rejected() -> void:
	# §产品 §6: 改绑 model 必须 published.
	var c: Dictionary = _create_product()
	var rm: Dictionary = CommandBus.send(&"research.add_model", {
		capability = {}, arch = &"ant_v1", dataset_ids = []})
	# 这个 model 是 internal, 不能绑.
	var r: Dictionary = CommandBus.send(&"product.update",
			{product_id = c.product_id,
			 fields = {&"bound_model_id": rm.model_id}})
	assert_false(r.ok)
	assert_eq(r.error, &"model_not_published")

func test_update_bound_model_to_unknown_rejected() -> void:
	var c: Dictionary = _create_product()
	var r: Dictionary = CommandBus.send(&"product.update",
			{product_id = c.product_id,
			 fields = {&"bound_model_id": &"nope"}})
	assert_false(r.ok)
	assert_eq(r.error, &"unknown_model")

func test_update_bound_model_recomputes_quality() -> void:
	# 绑到一个能力更高的 model, quality 应变. 必须给 staff, 否则 quality 永远 0.
	var c: Dictionary = _create_product({&"ml_eng": 2})
	var prod_before = ProductSystem.find_product(c.product_id)
	var q_before: float = prod_before.quality
	# 加一个超强 model 并 publish.
	var rs: Dictionary = CommandBus.send(&"research.add_model", {
		capability = {}, arch = &"ant_v1", dataset_ids = []})
	CommandBus.send(&"research.evaluate_apply", {
		model_id = rs.model_id,
		capability_measured = {&"general": 100.0, &"code": 100.0}})
	CommandBus.send(&"research.publish_model", {
		model_id = rs.model_id, is_open_source = false, per_token_price = 0.001})
	CommandBus.send(&"product.update",
			{product_id = c.product_id,
			 fields = {&"bound_model_id": rs.model_id}})
	var prod_after = ProductSystem.find_product(c.product_id)
	assert_gt(prod_after.quality, q_before)

func test_update_staff_releases_old_locks_total_count_changes() -> void:
	# 初 staff = {ml_eng: 2}, 改成 {ml_eng: 4} → staff_busy 由 2 → 4.
	CommandBus.send(&"hiring.adjust_staff", {role = &"ml_eng", delta = 6})
	var lid := _add_chief_engineer()
	var mid := _add_published_model()
	var c: Dictionary = CommandBus.send(&"product.create", {
		type = &"chatbot", lead_id = lid, bound_model_id = mid,
		subscription_price = 99, staff = {&"ml_eng": 2},
	})
	assert_eq(int(GameState.staff_busy[&"ml_eng"]), 2)
	var r: Dictionary = CommandBus.send(&"product.update",
			{product_id = c.product_id, fields = {&"staff": {&"ml_eng": 4}}})
	assert_true(r.ok)
	assert_eq(int(GameState.staff_busy[&"ml_eng"]), 4)

# ---- update_subscribers ------------------------------------------------

func test_update_subscribers_emits_subscribers_changed() -> void:
	var c: Dictionary = _create_product()
	watch_signals(EventBus)
	CommandBus.send(&"product.update_subscribers",
			{product_id = c.product_id, delta = 100})
	assert_signal_emitted(EventBus, "subscribers_changed")
	var p: Array = get_signal_parameters(EventBus, "subscribers_changed")
	assert_eq(p[0], c.product_id)
	assert_eq(int(p[1]), 100)
	assert_eq(int(p[2]), 100)

func test_update_subscribers_negative_delta_caps_at_zero() -> void:
	# §6: subscribers = max(0, old + delta). 不能跌破 0.
	var c: Dictionary = _create_product()
	CommandBus.send(&"product.update_subscribers",
			{product_id = c.product_id, delta = 50})
	CommandBus.send(&"product.update_subscribers",
			{product_id = c.product_id, delta = -1000})
	var prod = ProductSystem.find_product(c.product_id)
	assert_eq(prod.subscribers, 0)

# ---- delete ------------------------------------------------------------

func test_delete_emits_product_deleted() -> void:
	var c: Dictionary = _create_product()
	watch_signals(EventBus)
	CommandBus.send(&"product.delete", {product_id = c.product_id})
	assert_signal_emitted(EventBus, "product_deleted")

func test_delete_returns_lead_to_idle() -> void:
	var c: Dictionary = _create_product()
	var lead = HiringSystem.find_lead(&"lead_ce_01")
	assert_eq(lead.assigned_to_product_id, c.product_id)
	CommandBus.send(&"product.delete", {product_id = c.product_id})
	assert_true(lead.is_idle())

# ---- recompute_quality 命令 --------------------------------------------

func test_recompute_quality_unknown_returns_error() -> void:
	var r: Dictionary = CommandBus.send(&"product.recompute_quality",
			{product_id = &"nope"})
	assert_false(r.ok)
	assert_eq(r.error, &"unknown_product")

func test_recompute_quality_emits_signal() -> void:
	var c: Dictionary = _create_product()
	watch_signals(EventBus)
	CommandBus.send(&"product.recompute_quality", {product_id = c.product_id})
	assert_signal_emitted(EventBus, "quality_recomputed")

# ---- model_updated → recompute quality 链 ------------------------------

func test_model_updated_signal_recomputes_quality() -> void:
	# §4 订阅: model_updated → ProductSystem 重算所有 product 的 quality.
	# 必须给 staff, 否则 quality 永远 0 (staff_factor=0).
	# Bound model is already 'published' (immutable via posttrain/evaluate); we
	# mutate capability directly and emit the signal a posttrain/evaluate would.
	var c: Dictionary = _create_product({&"ml_eng": 3})
	var prod = ProductSystem.find_product(c.product_id)
	var q_before: float = prod.quality
	assert_gt(q_before, 0.0, "fixture 应给出非零 quality")
	var m = ResearchSystem.find_model(prod.bound_model_id)
	m.capability[&"general"] = 100.0
	m.capability[&"code"] = 100.0
	m.capability[&"reasoning"] = 100.0
	EventBus.model_updated.emit(m.id, {})
	assert_gt(prod.quality, q_before)
