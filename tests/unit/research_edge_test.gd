extends GutTest

## ResearchSystem v2 — 边界 / 失败路径补测.
## Per design/研究系统设计.md (4-state lifecycle).


func before_each() -> void:
	GameState.reset()

func _add_pretrained_model(arch: StringName = &"ant_v1") -> StringName:
	var r: Dictionary = CommandBus.send(&"research.add_model", {
		capability = {&"general": 50.0}, arch = arch, dataset_ids = []})
	return r.model_id

func _add_evaluated_model(cap: Dictionary = {&"general": 50.0}) -> StringName:
	var mid := _add_pretrained_model()
	CommandBus.send(&"research.evaluate_apply", {
		model_id = mid, capability_measured = cap})
	return mid

func _add_published_model(open: bool = false, price: float = 0.001) -> StringName:
	var mid: StringName = _add_evaluated_model()
	CommandBus.send(&"research.publish_model", {
		model_id = mid, is_open_source = open, per_token_price = price})
	return mid

# v6 PR-E (2026-05): hard clamp removed. See pricing_test.gd for new contract.

# ---- add_model ---------------------------------------------------------

func test_add_model_emits_model_added() -> void:
	watch_signals(EventBus)
	var r: Dictionary = CommandBus.send(&"research.add_model", {
		capability = {&"general": 30.0}, arch = &"ant_v1", dataset_ids = []})
	assert_true(r.ok)
	assert_signal_emitted(EventBus, "model_added")
	var p: Array = get_signal_parameters(EventBus, "model_added")
	assert_eq(p[0], r.model_id)
	# Per 公共枚举表.md §6bis: trained-by-player models carry &"trained" provenance.
	assert_eq(StringName(p[1]), &"trained")

func test_add_model_assigns_unique_id() -> void:
	var a: Dictionary = CommandBus.send(&"research.add_model", {
		capability = {}, arch = &"ant_v1", dataset_ids = []})
	var b: Dictionary = CommandBus.send(&"research.add_model", {
		capability = {}, arch = &"ant_v1", dataset_ids = []})
	assert_ne(a.model_id, b.model_id)

func test_add_model_stamps_trained_at_turn() -> void:
	GameState.turn = 9
	var r: Dictionary = CommandBus.send(&"research.add_model", {
		capability = {}, arch = &"ant_v1", dataset_ids = []})
	assert_eq(GameState.models[0].trained_at_turn, 9)

func test_add_model_default_status_pretrained() -> void:
	# §1: 训完 model.status = &"pretrained" (capability 隐藏直到 evaluate).
	_add_pretrained_model()
	assert_eq(GameState.models[0].status, &"pretrained")
	assert_false(GameState.models[0].capability_revealed)

# ---- posttrain ---------------------------------------------------------

func test_posttrain_unknown_model_returns_error() -> void:
	var r: Dictionary = CommandBus.send(&"research.posttrain_apply", {
		model_id = &"nope", dataset_id = &"x"})
	assert_false(r.ok)
	assert_eq(r.error, &"unknown_model")

func test_posttrain_does_not_mutate_capability() -> void:
	# §6.2: posttrain 不再叠加 delta. 真实变化在 evaluate.
	var mid: StringName = _add_evaluated_model({&"general": 50.0})
	CommandBus.send(&"research.posttrain_apply", {
		model_id = mid, dataset_id = &"ft_v1"})
	# evaluate 写入的 50.0 在 posttrain 后保持不变 (只是被标记 stale).
	assert_almost_eq(float(GameState.models[0].capability[&"general"]), 50.0, 0.001)
	assert_true(GameState.models[0].capability_stale)

func test_posttrain_appends_dataset_id_when_provided() -> void:
	var mid: StringName = _add_pretrained_model()
	CommandBus.send(&"research.posttrain_apply", {
		model_id = mid, dataset_id = &"ft_corpus_v1"})
	assert_true(GameState.models[0].dataset_ids.has(StringName("ft_corpus_v1")))

func test_posttrain_emits_model_updated() -> void:
	var mid: StringName = _add_pretrained_model()
	watch_signals(EventBus)
	CommandBus.send(&"research.posttrain_apply", {
		model_id = mid, dataset_id = &"x"})
	assert_signal_emitted(EventBus, "model_updated")

func test_posttrain_published_rejected() -> void:
	# §6.0: published 模型禁止 posttrain (除非先 unpublish).
	var mid: StringName = _add_published_model()
	var r: Dictionary = CommandBus.send(&"research.posttrain_apply", {
		model_id = mid, dataset_id = &"x"})
	assert_false(r.ok)
	assert_eq(r.error, &"already_published")

# ---- publish / unpublish 边界 ------------------------------------------

func test_publish_unknown_model_returns_error() -> void:
	var r: Dictionary = CommandBus.send(&"research.publish_model", {
		model_id = &"nope", is_open_source = false, per_token_price = 0.001})
	assert_false(r.ok)
	assert_eq(r.error, &"unknown_model")

func test_publish_already_published_rejected() -> void:
	var mid: StringName = _add_published_model()
	var r: Dictionary = CommandBus.send(&"research.publish_model", {
		model_id = mid, is_open_source = false, per_token_price = 0.002})
	assert_false(r.ok)
	assert_eq(r.error, &"already_published")

func test_publish_open_source_no_hard_clamp() -> void:
	# v6 PR-E (2026-05): OS price not clamped to a GPU-derived cap — accepted
	# as-is; demand_multiplier (UserSystem) does the soft punishment.
	var mid: StringName = _add_evaluated_model()
	CommandBus.send(&"research.publish_model", {
		model_id = mid, is_open_source = true, per_token_price = 0.999})
	assert_almost_eq(GameState.models[0].per_token_price, 0.999, 0.0001)

func test_unpublish_unknown_model_returns_error() -> void:
	var r: Dictionary = CommandBus.send(&"research.unpublish_model", {model_id = &"nope"})
	assert_false(r.ok)
	assert_eq(r.error, &"unknown_model")

func test_unpublish_pretrained_returns_not_published() -> void:
	var mid: StringName = _add_pretrained_model()
	var r: Dictionary = CommandBus.send(&"research.unpublish_model", {model_id = mid})
	assert_false(r.ok)
	assert_eq(r.error, &"not_published")

func test_unpublish_with_product_binding_returns_error() -> void:
	# §引用完整性: 若有 product 绑定该 model, 不许 unpublish.
	var mid: StringName = _add_published_model()
	var lead := Lead.new()
	lead.id = &"l1"; lead.specialty = &"chief_engineer"; lead.level = &"A"
	GameState.leads.append(lead)
	CommandBus.send(&"product.create", {
		type = &"chatbot", lead_id = lead.id, bound_model_id = mid,
		subscription_price = 99, staff = {}})
	var r: Dictionary = CommandBus.send(&"research.unpublish_model", {model_id = mid})
	assert_false(r.ok)
	assert_eq(r.error, &"in_use_by_product")

func test_unpublish_auto_undeploys_from_dcs() -> void:
	# §6.5: unpublish 应自动从所有 dc 移除部署.
	var mid: StringName = _add_published_model()
	var rdc: Dictionary = CommandBus.send(&"infra.debug_instant_owned_dc", {facility_spec_id = &"facility_solo", gpu_id = &"cypress_t0"})
	CommandBus.send(&"infra.deploy_model", {dc_id = rdc.dc_id, model_id = mid})
	CommandBus.send(&"research.unpublish_model", {model_id = mid})
	# dc 应回到 idle 且 deployed_model_id 清空.
	for dc in GameState.datacenters:
		if dc.id == rdc.dc_id:
			assert_eq(dc.status, &"idle")
			assert_eq(dc.deployed_model_id, &"")

func test_unpublish_records_unpublished_at_turn() -> void:
	var mid: StringName = _add_published_model()
	GameState.turn = 4
	CommandBus.send(&"research.unpublish_model", {model_id = mid})
	assert_eq(GameState.models[0].unpublished_at_turn, 4)

func test_unpublish_returns_to_evaluated() -> void:
	# §6.5: unpublish 把 status 拨回 evaluated, capability 不重置.
	var mid: StringName = _add_published_model()
	CommandBus.send(&"research.unpublish_model", {model_id = mid})
	var m = GameState.models[0]
	assert_eq(m.status, &"evaluated")
	assert_true(m.capability_revealed)

# ---- set_api_price -----------------------------------------------------

func test_set_api_price_unknown_model_error() -> void:
	var r: Dictionary = CommandBus.send(&"research.set_api_price", {
		model_id = &"nope", per_token_price = 0.005})
	assert_false(r.ok)
	assert_eq(r.error, &"unknown_model")

func test_set_api_price_open_source_no_hard_clamp() -> void:
	# v6 PR-E (2026-05): OS 模型 API 单价不再被硬市场参考价封顶, 任意 ≥0 都接受;
	# 经济压力靠 Model.demand_multiplier 在 UserSystem 每周衰减 (软上限).
	var mid: StringName = _add_published_model(true)
	var r: Dictionary = CommandBus.send(&"research.set_api_price", {
		model_id = mid, per_token_price = 999.0})
	assert_true(r.ok)
	assert_almost_eq(GameState.models[0].per_token_price, 999.0, 0.0001)

func test_set_api_price_emits_model_price_changed() -> void:
	var mid: StringName = _add_published_model(false, 0.001)
	watch_signals(EventBus)
	CommandBus.send(&"research.set_api_price", {model_id = mid, per_token_price = 0.005})
	assert_signal_emitted(EventBus, "model_price_changed")
	var p: Array = get_signal_parameters(EventBus, "model_price_changed")
	assert_eq(p[0], mid)
	assert_almost_eq(float(p[1]), 0.005, 0.0001)

# ---- set_open_source ---------------------------------------------------

func test_set_open_source_already_published_rejected() -> void:
	# §6: 已 publish 的 model 不能改开闭源.
	var mid: StringName = _add_published_model(false)
	var r: Dictionary = CommandBus.send(&"research.set_open_source",
			{model_id = mid, is_open_source = true})
	assert_false(r.ok)
	assert_eq(r.error, &"already_published")

func test_set_open_source_pre_publish_does_not_clamp_existing_price() -> void:
	# v6 PR-E (2026-05): set_open_source doesn't re-clamp price (no hard cap).
	# Player can leave a high stored price; market elasticity activates only
	# once the model is actually published.
	var mid: StringName = _add_pretrained_model()
	GameState.models[0].per_token_price = 5.0
	CommandBus.send(&"research.set_open_source",
			{model_id = mid, is_open_source = true})
	assert_almost_eq(GameState.models[0].per_token_price, 5.0, 0.0001)
	assert_true(GameState.models[0].is_open_source)

# ---- delete -----------------------------------------------------------

func test_delete_unknown_model_error() -> void:
	var r: Dictionary = CommandBus.send(&"research.delete_model", {model_id = &"nope"})
	assert_false(r.ok)
	assert_eq(r.error, &"unknown_model")

func test_delete_with_dc_serving_returns_in_use() -> void:
	var mid: StringName = _add_published_model()
	var rdc: Dictionary = CommandBus.send(&"infra.debug_instant_owned_dc", {facility_spec_id = &"facility_solo", gpu_id = &"cypress_t0"})
	CommandBus.send(&"infra.deploy_model", {dc_id = rdc.dc_id, model_id = mid})
	var r: Dictionary = CommandBus.send(&"research.delete_model", {model_id = mid})
	assert_false(r.ok)
	assert_eq(r.error, &"in_use")

func test_delete_published_model_requires_unpublish_first() -> void:
	# 研究系统设计 §6.7: published 模型必须先走 unpublish 清理链, 不能直接删.
	var mid: StringName = _add_published_model()
	var r: Dictionary = CommandBus.send(&"research.delete_model", {model_id = mid})
	assert_false(r.ok)
	assert_eq(r.error, &"already_published")
	assert_not_null(ResearchSystem.find_model(mid))

func test_delete_pretrained_model_succeeds() -> void:
	var mid: StringName = _add_pretrained_model()
	var r: Dictionary = CommandBus.send(&"research.delete_model", {model_id = mid})
	assert_true(r.ok)
	assert_eq(GameState.models.size(), 0)

func test_delete_emits_model_deleted() -> void:
	var mid: StringName = _add_pretrained_model()
	watch_signals(EventBus)
	CommandBus.send(&"research.delete_model", {model_id = mid})
	assert_signal_emitted(EventBus, "model_deleted")

# ---- rename -----------------------------------------------------------

func test_rename_changes_display_name() -> void:
	var mid: StringName = _add_pretrained_model()
	CommandBus.send(&"research.rename_model", {model_id = mid, display_name = "Sparrow Neo"})
	assert_eq(GameState.models[0].display_name, "Sparrow Neo")

func test_rename_unknown_model_error() -> void:
	var r: Dictionary = CommandBus.send(&"research.rename_model", {
		model_id = &"nope", display_name = "x"})
	assert_false(r.ok)
	assert_eq(r.error, &"unknown_model")

func test_rename_emits_model_updated_with_empty_delta() -> void:
	var mid: StringName = _add_pretrained_model()
	watch_signals(EventBus)
	CommandBus.send(&"research.rename_model", {model_id = mid, display_name = "x"})
	assert_signal_emitted(EventBus, "model_updated")

# ---- evaluate ---------------------------------------------------------

func test_evaluate_unknown_model_error() -> void:
	var r: Dictionary = CommandBus.send(&"research.evaluate_apply", {
		model_id = &"nope", capability_measured = {}})
	assert_false(r.ok)
	assert_eq(r.error, &"unknown_model")

func test_evaluate_replaces_capability_not_merges() -> void:
	# §6.3 (Bug B fix 2026-05): evaluate writes a full 5-axis result computed
	# from `capability_measured + model.posttrain_delta` (clamp ≥ 0). It does
	# NOT merge with whatever ad-hoc axes were on m.capability before evaluate
	# — pre-evaluate `general=50` is wiped because measured.get("general", 0) = 0
	# and posttrain_delta general = 0.
	var mid: StringName = _add_pretrained_model()
	# capability 起手 {general: 50.0}; evaluate 给 {code: 80.0}, general 应该归零.
	CommandBus.send(&"research.evaluate_apply", {
		model_id = mid, capability_measured = {&"code": 80.0}})
	var m = GameState.models[0]
	assert_almost_eq(float(m.capability.get(&"general", -1.0)), 0.0, 0.001,
			"pre-evaluate general=50 must NOT survive evaluate (no merge)")
	assert_almost_eq(float(m.capability[&"code"]), 80.0, 0.001)

func test_evaluate_emits_model_evaluated_signal() -> void:
	var mid: StringName = _add_pretrained_model()
	watch_signals(EventBus)
	CommandBus.send(&"research.evaluate_apply", {
		model_id = mid, capability_measured = {&"general": 70.0}})
	assert_signal_emitted(EventBus, "model_evaluated")

# ---- download_open_source (v9 PR-I: release_id from OS NPC pretrain releases) --

func test_download_unknown_release() -> void:
	GameState.turn = 500
	var r: Dictionary = CommandBus.send(&"research.download_open_source", {
		release_id = &"definitely_nope"})
	assert_false(r.ok)
	assert_eq(r.error, &"unknown_release")

func test_download_creates_evaluated_downloaded_os_model() -> void:
	# release_wolf_3 (Wolf Research, open, pretrain, turn 330)
	GameState.turn = 335
	var r: Dictionary = CommandBus.send(&"research.download_open_source", {
		release_id = &"release_wolf_3"})
	assert_true(r.ok)
	var m = ResearchSystem.find_model(r.model_id)
	assert_eq(m.status, &"evaluated")
	assert_eq(m.provenance, &"downloaded_os")
	assert_true(m.capability_revealed)

func test_download_emits_added_and_evaluated_signals() -> void:
	# release_owl_2 (Owl Open, open, pretrain, turn 395)
	GameState.turn = 400
	watch_signals(EventBus)
	CommandBus.send(&"research.download_open_source", {release_id = &"release_owl_2"})
	assert_signal_emitted(EventBus, "model_added")
	assert_signal_emitted(EventBus, "model_evaluated")

# ---- OS price clamp ---------------------------------------------------

func test_publish_closed_source_unclamped() -> void:
	# Closed source should not be clamped; only floored to 0.
	var mid: StringName = _add_evaluated_model()
	CommandBus.send(&"research.publish_model", {
		model_id = mid, is_open_source = false, per_token_price = 5.0})
	assert_almost_eq(GameState.models[0].per_token_price, 5.0, 0.0001)

func test_downloaded_os_model_publish_no_hard_clamp() -> void:
	# v6 PR-E (2026-05): downloaded_os provenance no longer triggers a hard
	# price clamp on publish. Guidance price is still computed as 2 × base
	# (per provenance check in guidance_price_per_token), and the player's
	# demand_multiplier will decay above that — but publish itself doesn't
	# silently lower their requested price anymore.
	# release_crow_1 (Crow Labs, open, pretrain, turn 430)
	GameState.turn = 435
	var r: Dictionary = CommandBus.send(&"research.download_open_source", {
		release_id = &"release_crow_1"})
	var pub: Dictionary = CommandBus.send(&"research.publish_model", {
		model_id = r.model_id, is_open_source = false, per_token_price = 999.0})
	assert_true(pub.ok)
	assert_almost_eq(ResearchSystem.find_model(r.model_id).per_token_price, 999.0, 0.0001)
