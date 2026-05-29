extends GutTest

## ResearchSystem v2 — publish/unpublish/posttrain/evaluate/pricing/delete/rename.
## Per design/研究系统设计.md (4-state lifecycle).

func before_each() -> void:
	GameState.reset()

func _add_pretrained_model() -> StringName:
	var r: Dictionary = CommandBus.send(&"research.add_model", {
		capability = {&"general": 60.0}, arch = &"ant_v1", dataset_ids = []})
	return r.model_id

func _add_evaluated_model(cap: Dictionary = {&"general": 60.0}) -> StringName:
	var mid: StringName = _add_pretrained_model()
	# Drive evaluate directly — TaskSystem normally fans out into this.
	CommandBus.send(&"research.evaluate_apply", {
		model_id = mid, capability_measured = cap})
	return mid

# v6 PR-E (2026-05): hard clamp removed. Tests below verify the new contract:
# any non-negative price passes through unchanged; the market reaction lives
# on the auto-created api product's subscriber pool.

# ---- publish ------------------------------------------------------------

func test_publish_unknown_model_returns_error() -> void:
	var r: Dictionary = CommandBus.send(&"research.publish_model", {
		model_id = &"x", is_open_source = false, per_token_price = 0.001})
	assert_false(r.ok)
	assert_eq(r.error, &"unknown_model")

func test_publish_pretrained_returns_not_evaluated() -> void:
	# §6.4: must evaluate first.
	var mid := _add_pretrained_model()
	var r: Dictionary = CommandBus.send(&"research.publish_model", {
		model_id = mid, is_open_source = false, per_token_price = 0.001})
	assert_false(r.ok)
	assert_eq(r.error, &"not_evaluated")

func test_publish_evaluated_succeeds() -> void:
	var mid := _add_evaluated_model()
	var r: Dictionary = CommandBus.send(&"research.publish_model", {
		model_id = mid, is_open_source = false, per_token_price = 0.001})
	assert_true(r.ok)
	assert_eq(ResearchSystem.find_model(mid).status, &"published")

func test_publish_already_published_returns_error() -> void:
	var mid := _add_evaluated_model()
	CommandBus.send(&"research.publish_model", {
		model_id = mid, is_open_source = false, per_token_price = 0.001})
	var r: Dictionary = CommandBus.send(&"research.publish_model", {
		model_id = mid, is_open_source = false, per_token_price = 0.001})
	assert_false(r.ok)
	assert_eq(r.error, &"already_published")

func test_publish_after_posttrain_returns_not_evaluated() -> void:
	# §6.4: evaluated → posttrain → status = posttrained → publish forbidden.
	# (not_evaluated short-circuits before stale check fires.)
	var mid := _add_evaluated_model()
	CommandBus.send(&"research.posttrain_apply", {
		model_id = mid, dataset_id = &"foo"})
	var r: Dictionary = CommandBus.send(&"research.publish_model", {
		model_id = mid, is_open_source = false, per_token_price = 0.001})
	assert_false(r.ok)
	assert_eq(r.error, &"not_evaluated")
	# Sanity: the model IS stale.
	assert_true(ResearchSystem.find_model(mid).capability_stale)

func test_publish_blocked_while_posttrain_running() -> void:
	# Bug fix 2026-05: 玩家在 posttrain 任务进行中点 publish, 旧版会通过,
	# 然后 posttrain 完成时 _on_posttrain_apply 拒 already_published, 算力白花。
	# 现在 publish 必须先检测 active_tasks 里有没有这个模型的 posttrain。
	var mid := _add_evaluated_model()
	var t := TaskInstance.new()
	t.id = &"task_test_posttrain"
	t.subtype = &"posttrain"
	t.base_model_id = mid
	GameState.active_tasks.append(t)
	var r: Dictionary = CommandBus.send(&"research.publish_model", {
		model_id = mid, is_open_source = false, per_token_price = 0.001})
	assert_false(r.ok)
	assert_eq(r.error, &"posttrain_in_progress")
	# 状态没被改成 published, 任务结束后还能正常结算。
	assert_eq(ResearchSystem.find_model(mid).status, &"evaluated")

func test_publish_capability_stale_rejected_when_status_evaluated() -> void:
	# Hand-construct the corner case: status=evaluated AND stale=true. In
	# real flow, posttrain bumps status away from evaluated — but a future
	# system or save-game artifact could land here, so we still guard it.
	var mid := _add_evaluated_model()
	var m = ResearchSystem.find_model(mid)
	m.capability_stale = true
	var r: Dictionary = CommandBus.send(&"research.publish_model", {
		model_id = mid, is_open_source = false, per_token_price = 0.001})
	assert_false(r.ok)
	assert_eq(r.error, &"capability_stale")

func test_publish_open_source_no_hard_clamp() -> void:
	# v6 PR-E (2026-05): the old hard cap is gone. Any non-negative price is
	# accepted as-is; market reaction is via the api product elsewhere.
	var mid := _add_evaluated_model()
	CommandBus.send(&"research.publish_model", {
		model_id = mid, is_open_source = true, per_token_price = 999.0})
	var m = ResearchSystem.find_model(mid)
	assert_almost_eq(m.per_token_price, 999.0, 0.0001)
	assert_true(m.is_open_source)
	var api_count: int = 0
	for p in GameState.products:
		if p.type == &"api" and p.bound_model_id == mid:
			api_count += 1
	assert_eq(api_count, 1)

func test_publish_emits_signal() -> void:
	var mid := _add_evaluated_model()
	watch_signals(EventBus)
	CommandBus.send(&"research.publish_model", {
		model_id = mid, is_open_source = false, per_token_price = 0.001})
	assert_signal_emitted(EventBus, "model_published")

# ---- unpublish ----------------------------------------------------------

func test_unpublish_pretrained_returns_error() -> void:
	var mid := _add_pretrained_model()
	var r: Dictionary = CommandBus.send(&"research.unpublish_model", {model_id = mid})
	assert_false(r.ok)
	assert_eq(r.error, &"not_published")

func test_unpublish_drops_back_to_evaluated() -> void:
	# §6.5: capability stays revealed; status returns to evaluated.
	var mid := _add_evaluated_model()
	CommandBus.send(&"research.publish_model", {
		model_id = mid, is_open_source = false, per_token_price = 0.001})
	CommandBus.send(&"research.unpublish_model", {model_id = mid})
	var m = ResearchSystem.find_model(mid)
	assert_eq(m.status, &"evaluated")
	assert_true(m.capability_revealed)

# ---- posttrain ----------------------------------------------------------

func test_posttrain_unknown_model_returns_error() -> void:
	var r: Dictionary = CommandBus.send(&"research.posttrain_apply", {
		model_id = &"x", dataset_id = &""})
	assert_false(r.ok)
	assert_eq(r.error, &"unknown_model")

func test_posttrain_records_dataset_and_marks_posttrained() -> void:
	# §6.2: posttrain stamps dataset + flips status, NO capability mutation.
	var mid := _add_pretrained_model()
	# capture the pre-posttrain capability snapshot.
	var snapshot: Dictionary = ResearchSystem.find_model(mid).capability.duplicate()
	CommandBus.send(&"research.posttrain_apply", {
		model_id = mid, dataset_id = &"ft_corpus_v1"})
	var m = ResearchSystem.find_model(mid)
	assert_eq(m.status, &"posttrained")
	assert_true(m.dataset_ids.has(StringName("ft_corpus_v1")))
	# Capability dict didn't move (still all zeros from pretrain).
	assert_eq(m.capability, snapshot)

func test_posttrain_after_evaluate_marks_capability_stale() -> void:
	# §6.2: capability_stale flag flips on so publish gets blocked.
	var mid := _add_evaluated_model({&"general": 60.0})
	CommandBus.send(&"research.posttrain_apply", {
		model_id = mid, dataset_id = &"ft_v1"})
	var m = ResearchSystem.find_model(mid)
	assert_true(m.capability_stale)
	assert_eq(m.status, &"posttrained")

func test_posttrain_pretrained_does_not_set_stale() -> void:
	# Never-evaluated model: capability_revealed=false, no stale flag.
	var mid := _add_pretrained_model()
	CommandBus.send(&"research.posttrain_apply", {
		model_id = mid, dataset_id = &"ft_v1"})
	var m = ResearchSystem.find_model(mid)
	assert_false(m.capability_stale)

# ---- evaluate -----------------------------------------------------------

func test_evaluate_writes_capability_and_reveals() -> void:
	var mid := _add_pretrained_model()
	CommandBus.send(&"research.evaluate_apply", {
		model_id = mid,
		capability_measured = {&"general": 70.0, &"code": 55.0}})
	var m = ResearchSystem.find_model(mid)
	assert_eq(m.status, &"evaluated")
	assert_true(m.capability_revealed)
	assert_false(m.capability_stale)
	assert_almost_eq(float(m.capability[&"general"]), 70.0, 0.001)

func test_evaluate_emits_signal_with_capability() -> void:
	var mid := _add_pretrained_model()
	watch_signals(EventBus)
	CommandBus.send(&"research.evaluate_apply", {
		model_id = mid, capability_measured = {&"general": 80.0}})
	assert_signal_emitted(EventBus, "model_evaluated")
	var p: Array = get_signal_parameters(EventBus, "model_evaluated")
	assert_eq(p[0], mid)
	assert_almost_eq(float((p[1] as Dictionary).get(&"general", 0.0)), 80.0, 0.001)

func test_evaluate_clears_stale_flag() -> void:
	# evaluate → posttrain (stale) → evaluate again → fresh.
	var mid := _add_evaluated_model({&"general": 50.0})
	CommandBus.send(&"research.posttrain_apply", {
		model_id = mid, dataset_id = &"ft_v1"})
	assert_true(ResearchSystem.find_model(mid).capability_stale)
	CommandBus.send(&"research.evaluate_apply", {
		model_id = mid, capability_measured = {&"general": 75.0}})
	var m = ResearchSystem.find_model(mid)
	assert_false(m.capability_stale)
	assert_almost_eq(float(m.capability[&"general"]), 75.0, 0.001)

func test_evaluate_unknown_model_returns_error() -> void:
	var r: Dictionary = CommandBus.send(&"research.evaluate_apply", {
		model_id = &"nope", capability_measured = {}})
	assert_false(r.ok)
	assert_eq(r.error, &"unknown_model")

func test_evaluate_published_model_rejected() -> void:
	# §6.0: published models can't re-evaluate without unpublish.
	var mid := _add_evaluated_model()
	CommandBus.send(&"research.publish_model", {
		model_id = mid, is_open_source = false, per_token_price = 0.001})
	var r: Dictionary = CommandBus.send(&"research.evaluate_apply", {
		model_id = mid, capability_measured = {&"general": 50.0}})
	assert_false(r.ok)
	assert_eq(r.error, &"already_published")

# ---- download_open_source (v9 PR-I: release_id from OS NPC pretrain releases) ----

# Wolf-3 (turn 330) is the canonical "test OS download" — Wolf Research is open-source,
# release_kind = pretrain, params 405B dense, capability {g=65,c=52,r=55,m=35,a=15}.
const _OS_TEST_RELEASE: StringName = &"release_wolf_3"
const _OS_TEST_TURN: int = 335

func _seed_turn_for_os_download() -> void:
	GameState.turn = _OS_TEST_TURN

func test_download_unknown_release_returns_error() -> void:
	_seed_turn_for_os_download()
	var r: Dictionary = CommandBus.send(&"research.download_open_source", {
		release_id = &"does_not_exist"})
	assert_false(r.ok)
	assert_eq(r.error, &"unknown_release")

func test_download_creates_evaluated_model_with_provenance() -> void:
	_seed_turn_for_os_download()
	var r: Dictionary = CommandBus.send(&"research.download_open_source", {
		release_id = _OS_TEST_RELEASE})
	assert_true(r.ok, "download release_wolf_3: %s" % str(r.get(&"error", &"")))
	var m = ResearchSystem.find_model(r.model_id)
	assert_eq(m.status, &"evaluated")
	assert_eq(m.provenance, &"downloaded_os")
	assert_true(m.capability_revealed)
	assert_false(m.capability_stale)
	assert_eq(m.source_release_id, _OS_TEST_RELEASE)
	# Capability copied from release (release_wolf_3: general=65).
	assert_almost_eq(float(m.capability[&"general"]), 65.0, 0.001)

func test_download_emits_added_then_evaluated() -> void:
	_seed_turn_for_os_download()
	watch_signals(EventBus)
	CommandBus.send(&"research.download_open_source", {release_id = _OS_TEST_RELEASE})
	assert_signal_emitted(EventBus, "model_added")
	assert_signal_emitted(EventBus, "model_evaluated")

func test_downloaded_model_is_publishable_immediately() -> void:
	_seed_turn_for_os_download()
	var r: Dictionary = CommandBus.send(&"research.download_open_source", {
		release_id = _OS_TEST_RELEASE})
	var pub: Dictionary = CommandBus.send(&"research.publish_model", {
		model_id = r.model_id, is_open_source = true, per_token_price = 0.001})
	assert_true(pub.ok)
	assert_eq(ResearchSystem.find_model(r.model_id).status, &"published")

func test_ensure_open_source_release_published_materializes_publishes_and_creates_api() -> void:
	_seed_turn_for_os_download()
	var r: Dictionary = CommandBus.send(&"research.ensure_open_source_release_published", {
		release_id = _OS_TEST_RELEASE})
	assert_true(r.ok, "ensure release_wolf_3: %s" % str(r.get(&"error", &"")))
	assert_true(bool(r.get(&"created", false)))
	assert_true(bool(r.get(&"published", false)))
	var m = ResearchSystem.find_model(r.model_id)
	assert_not_null(m)
	assert_eq(m.status, &"published")
	assert_eq(m.provenance, &"downloaded_os")
	assert_eq(m.source_release_id, _OS_TEST_RELEASE)
	assert_true(m.is_open_source)
	assert_gt(float(m.per_token_price), 0.0, "auto-publish should apply a non-zero guidance price")
	var api_count: int = 0
	for p in GameState.products:
		if p.type == &"api" and p.bound_model_id == m.id:
			api_count += 1
	assert_eq(api_count, 1, "ensure publish should trigger exactly one API product")

func test_ensure_open_source_release_published_is_idempotent() -> void:
	_seed_turn_for_os_download()
	var r1: Dictionary = CommandBus.send(&"research.ensure_open_source_release_published", {
		release_id = _OS_TEST_RELEASE})
	var r2: Dictionary = CommandBus.send(&"research.ensure_open_source_release_published", {
		release_id = _OS_TEST_RELEASE})
	assert_true(r1.ok)
	assert_true(r2.ok)
	assert_eq(r2.model_id, r1.model_id)
	assert_false(bool(r2.get(&"created", true)), "second ensure should reuse existing model")
	var api_count: int = 0
	for p in GameState.products:
		if p.type == &"api" and p.bound_model_id == r1.model_id:
			api_count += 1
	assert_eq(api_count, 1, "idempotent ensure must not duplicate API product")

func test_download_at_cold_start_returns_not_released_yet() -> void:
	# v9 PR-I: turn 0 时所有 OS NPC 都未首发, 第一个 OS pretrain (Wolf-1) 在 turn 215.
	GameState.turn = 0
	var r: Dictionary = CommandBus.send(&"research.download_open_source", {
		release_id = _OS_TEST_RELEASE})
	assert_false(r.ok)
	assert_eq(r.error, &"not_released_yet")

func test_download_non_pretrain_release_rejected() -> void:
	# release_wolf_1_5 是 rlhf release_kind, 不能 download.
	GameState.turn = 500
	var r: Dictionary = CommandBus.send(&"research.download_open_source", {
		release_id = &"release_wolf_1_5"})
	assert_false(r.ok)
	assert_eq(r.error, &"not_pretrain")

func test_download_closed_source_release_rejected() -> void:
	# release_orca_4 来自 npc_orca_lab (闭源), 不能 download.
	GameState.turn = 500
	var r: Dictionary = CommandBus.send(&"research.download_open_source", {
		release_id = &"release_orca_4"})
	assert_false(r.ok)
	assert_eq(r.error, &"not_open_source")

func test_download_derives_flops_per_token_from_release_params() -> void:
	# v9 PR-I: fpt 由 release.params_b/active_params_b 派生, 与玩家自训同公式.
	_seed_turn_for_os_download()
	var r: Dictionary = CommandBus.send(&"research.download_open_source", {
		release_id = _OS_TEST_RELEASE})
	assert_true(r.ok)
	var m = ResearchSystem.find_model(r.model_id)
	# Wolf-3: params_b=405 (dense), active_params_b=405 → size_params=405000M, active_ratio=1.0
	# fpt = 2 × 405000 × 1.0 × 1e6 = 8.1e11
	var expected_size_m: float = 405.0 * 1000.0
	var expected_fpt: float = 2.0 * expected_size_m * 1.0 * 1.0e6
	assert_almost_eq(float(m.size_params), expected_size_m, 0.1)
	assert_almost_eq(float(m.active_param_ratio), 1.0, 0.001)
	assert_almost_eq(float(m.flops_per_token), expected_fpt, expected_fpt * 0.001)

func test_download_moe_release_derives_active_ratio() -> void:
	# release_wolf_4 (turn 410, params_b=1000, active_params_b=150, octopus_v2 MoE)
	GameState.turn = 415
	var r: Dictionary = CommandBus.send(&"research.download_open_source", {
		release_id = &"release_wolf_4"})
	assert_true(r.ok)
	var m = ResearchSystem.find_model(r.model_id)
	# size = 1000 * 1000 = 1e6 M; active_ratio = 150 / 1000 = 0.15
	# fpt = 2 × 1e6 × 0.15 × 1e6 = 3e11
	assert_almost_eq(float(m.active_param_ratio), 0.15, 0.001)
	assert_almost_eq(float(m.flops_per_token), 2.0 * 1.0e6 * 0.15 * 1.0e6, 1.0e8)

# ---- price / open-source ------------------------------------------------

func test_set_api_price_open_source_no_hard_clamp() -> void:
	# v6 PR-E (2026-05): OS price no longer clamped — any non-negative passes
	# through. Player gets soft punishment via api subscriber demand decay.
	var mid := _add_evaluated_model()
	CommandBus.send(&"research.publish_model", {
		model_id = mid, is_open_source = true, per_token_price = 0.0})
	var r: Dictionary = CommandBus.send(&"research.set_api_price", {
		model_id = mid, per_token_price = 999.0})
	assert_true(r.ok)
	assert_almost_eq(ResearchSystem.find_model(mid).per_token_price, 999.0, 0.0001)
	assert_almost_eq(float(r.applied_price), 999.0, 0.0001)


func test_set_api_price_closed_source_unconstrained() -> void:
	# Closed source can charge whatever; only floor at 0.
	var mid := _add_evaluated_model()
	CommandBus.send(&"research.publish_model", {
		model_id = mid, is_open_source = false, per_token_price = 0.001})
	CommandBus.send(&"research.set_api_price", {
		model_id = mid, per_token_price = 5.0})
	assert_almost_eq(ResearchSystem.find_model(mid).per_token_price, 5.0, 0.0001)

func test_set_api_price_negative_clamped_to_zero() -> void:
	var mid := _add_evaluated_model()
	CommandBus.send(&"research.publish_model", {
		model_id = mid, is_open_source = false, per_token_price = 0.001})
	CommandBus.send(&"research.set_api_price", {
		model_id = mid, per_token_price = -10.0})
	assert_almost_eq(ResearchSystem.find_model(mid).per_token_price, 0.0, 0.0001)

func test_set_open_source_after_publish_returns_error() -> void:
	var mid := _add_evaluated_model()
	CommandBus.send(&"research.publish_model", {
		model_id = mid, is_open_source = false, per_token_price = 0.001})
	var r: Dictionary = CommandBus.send(&"research.set_open_source", {
		model_id = mid, is_open_source = true})
	assert_false(r.ok)
	assert_eq(r.error, &"already_published")

# ---- delete -------------------------------------------------------------

func test_delete_serving_model_returns_error() -> void:
	var mid := _add_evaluated_model()
	CommandBus.send(&"research.publish_model", {
		model_id = mid, is_open_source = false, per_token_price = 0.001})
	var rdc: Dictionary = CommandBus.send(&"infra.debug_instant_owned_dc", {facility_spec_id = &"facility_solo", gpu_id = &"cypress_t0"})
	CommandBus.send(&"infra.deploy_model", {dc_id = rdc.dc_id, model_id = mid})
	var r: Dictionary = CommandBus.send(&"research.delete_model", {model_id = mid})
	assert_false(r.ok)
	assert_eq(r.error, &"in_use")

func test_delete_idle_model_succeeds() -> void:
	var mid := _add_pretrained_model()
	var r: Dictionary = CommandBus.send(&"research.delete_model", {model_id = mid})
	assert_true(r.ok)
	assert_eq(GameState.models.size(), 0)

# ---- rename -------------------------------------------------------------

func test_rename_unknown_returns_error() -> void:
	var r: Dictionary = CommandBus.send(&"research.rename_model", {
		model_id = &"x", display_name = "New"})
	assert_false(r.ok)
	assert_eq(r.error, &"unknown_model")

func test_rename_changes_display_name() -> void:
	var mid := _add_pretrained_model()
	CommandBus.send(&"research.rename_model", {model_id = mid, display_name = "Renamed"})
	assert_eq(ResearchSystem.find_model(mid).display_name, "Renamed")

# ---- helpers / model methods -------------------------------------------

func test_displayable_capability_hides_when_unrevealed() -> void:
	var mid := _add_pretrained_model()
	var m = ResearchSystem.find_model(mid)
	assert_eq(m.displayable_capability(), {})

func test_displayable_capability_returns_dict_when_revealed() -> void:
	var mid := _add_evaluated_model({&"general": 70.0})
	var m = ResearchSystem.find_model(mid)
	var d: Dictionary = m.displayable_capability()
	assert_almost_eq(float(d[&"general"]), 70.0, 0.001)

func test_is_publishable_only_evaluated_and_fresh() -> void:
	var mid := _add_pretrained_model()
	var m = ResearchSystem.find_model(mid)
	assert_false(m.is_publishable())
	# Evaluated → publishable.
	CommandBus.send(&"research.evaluate_apply", {
		model_id = mid, capability_measured = {&"general": 50.0}})
	assert_true(m.is_publishable())
	# Posttrain again → stale → not publishable.
	CommandBus.send(&"research.posttrain_apply", {model_id = mid, dataset_id = &"x"})
	assert_false(m.is_publishable())
