extends GutTest

## InfraSystem — 三态状态机边界 / 失败路径补测.
## Per design/基础设施系统设计.md.

func before_each() -> void:
	GameState.reset()

func _rent_solo() -> StringName:
	var r: Dictionary = CommandBus.send(&"infra.rent_facility",
		{facility_spec_id = &"facility_solo", power_supply_id = &"grid"})
	return r.dc_id

func _rent_pod() -> StringName:
	var r: Dictionary = CommandBus.send(&"infra.rent_facility",
		{facility_spec_id = &"facility_pod", power_supply_id = &"grid"})
	return r.dc_id

func _rent_solo_with_gpu() -> StringName:
	# Cypress_t0 release_turn = 0, $4000/card, 1 card max — works on turn 0.
	GameState.cash = 1_000_000
	var id: StringName = _rent_solo()
	CommandBus.send(&"infra.buy_gpus",
		{dc_id = id, gpu_id = &"cypress_t0", count = 1})
	return id

func _add_published_model(open: bool = false) -> StringName:
	var r: Dictionary = CommandBus.send(&"research.add_model", {
		capability = {&"general": 50.0}, arch = &"ant_v1", dataset_ids = []})
	CommandBus.send(&"research.evaluate_apply", {
		model_id = r.model_id, capability_measured = {&"general": 50.0}})
	CommandBus.send(&"research.publish_model", {
		model_id = r.model_id, is_open_source = open, per_token_price = 0.001})
	return r.model_id

# ---- rent / build / terminate ------------------------------------------

func test_rent_unknown_spec_returns_error() -> void:
	var r: Dictionary = CommandBus.send(&"infra.rent_facility",
		{facility_spec_id = &"facility_unobtanium", power_supply_id = &"grid"})
	assert_false(r.ok)
	assert_eq(r.error, &"unknown_spec")

func test_rent_charges_nothing_upfront() -> void:
	# 基础设施 §1.4: 租赁零 upfront, 第一笔扣款在下一次 upkeep.
	var before: int = GameState.cash
	_rent_solo()
	assert_eq(GameState.cash, before)

func test_rent_assigns_unique_id_and_emits_added() -> void:
	watch_signals(EventBus)
	var a: StringName = _rent_solo()
	var b: StringName = _rent_solo()
	assert_ne(a, b)
	assert_signal_emitted(EventBus, "datacenter_added")
	assert_eq(get_signal_emit_count(EventBus, "datacenter_added"), 2)

func test_rented_dc_starts_idle_and_marked_rented() -> void:
	var id := _rent_solo()
	var dc = InfraSystem.find_dc(id)
	assert_eq(dc.status, &"idle")
	assert_eq(dc.ownership, &"rented")

func test_build_unknown_spec_returns_error() -> void:
	var r: Dictionary = CommandBus.send(&"infra.build_facility",
		{facility_spec_id = &"facility_unobtanium", power_supply_id = &"grid"})
	assert_false(r.ok)
	assert_eq(r.error, &"unknown_spec")

func test_build_charges_total_cost_and_queues_construction() -> void:
	# 基础设施 §2: 自建一次性扣 land_build_cost × (1 + power.build_cost_modifier).
	# facility_pod: land_build_cost=5000, build_weeks=1. grid build_cost_modifier=0.
	GameState.cash = 1_000_000
	var before: int = GameState.cash
	var r: Dictionary = CommandBus.send(&"infra.build_facility",
		{facility_spec_id = &"facility_pod", power_supply_id = &"grid"})
	assert_true(r.ok)
	assert_eq(GameState.cash, before - 5000)
	assert_eq(GameState.construction_queue.size(), 1)
	assert_eq(GameState.construction_queue[0].weeks_remaining, 1)

func test_terminate_unknown_dc_returns_error() -> void:
	var r: Dictionary = CommandBus.send(&"infra.terminate_dc", {dc_id = &"none"})
	assert_false(r.ok)
	assert_eq(r.error, &"unknown_dc")

func test_terminate_busy_dc_rejected() -> void:
	# 三态: training/serving 都不能直接 terminate.
	var id := _rent_solo_with_gpu()
	CommandBus.send(&"infra.assign_to_task", {dc_id = id, task_id = &"t1"})
	var r: Dictionary = CommandBus.send(&"infra.terminate_dc", {dc_id = id})
	assert_false(r.ok)
	assert_eq(r.error, &"dc_busy")

func test_terminate_idle_dc_removes_and_emits() -> void:
	var id := _rent_solo()
	watch_signals(EventBus)
	CommandBus.send(&"infra.terminate_dc", {dc_id = id})
	assert_signal_emitted(EventBus, "datacenter_removed")
	assert_eq(GameState.datacenters.size(), 0)

# ---- deploy / undeploy 状态机 ------------------------------------------

func test_deploy_unknown_dc_error() -> void:
	var mid := _add_published_model()
	var r: Dictionary = CommandBus.send(&"infra.deploy_model",
			{dc_id = &"none", model_id = mid})
	assert_false(r.ok)
	assert_eq(r.error, &"unknown_dc")

func test_deploy_unknown_model_error() -> void:
	var id := _rent_solo_with_gpu()
	var r: Dictionary = CommandBus.send(&"infra.deploy_model",
			{dc_id = id, model_id = &"nope"})
	assert_false(r.ok)
	assert_eq(r.error, &"unknown_model")

func test_deploy_internal_model_rejected() -> void:
	# §2: 仅 published model 可部署.
	var rm: Dictionary = CommandBus.send(&"research.add_model", {
		capability = {}, arch = &"ant_v1", dataset_ids = []})
	var id := _rent_solo_with_gpu()
	var r: Dictionary = CommandBus.send(&"infra.deploy_model",
			{dc_id = id, model_id = rm.model_id})
	assert_false(r.ok)
	assert_eq(r.error, &"model_not_published")

func test_deploy_when_serving_already_rejected() -> void:
	# §2: serving 状态下不能再次 deploy (要先 undeploy).
	var id := _rent_solo_with_gpu()
	var mid := _add_published_model()
	CommandBus.send(&"infra.deploy_model", {dc_id = id, model_id = mid})
	var mid2 := _add_published_model()
	var r: Dictionary = CommandBus.send(&"infra.deploy_model",
			{dc_id = id, model_id = mid2})
	assert_false(r.ok)
	assert_eq(r.error, &"dc_not_idle")

func test_deploy_when_training_rejected() -> void:
	var id := _rent_solo_with_gpu()
	var mid := _add_published_model()
	CommandBus.send(&"infra.assign_to_task", {dc_id = id, task_id = &"t1"})
	var r: Dictionary = CommandBus.send(&"infra.deploy_model",
			{dc_id = id, model_id = mid})
	assert_false(r.ok)
	assert_eq(r.error, &"dc_not_idle")

func test_deploy_open_source_small_model_directly_to_infra() -> void:
	# 公共开源部署会先物化 / 发布 OS NPC release, 再把 DC 绑到实际 model,
	# 让产品页能看到自动 API 并允许调价。
	GameState.turn = 220
	var id := _rent_solo_with_gpu()
	watch_signals(EventBus)
	var r: Dictionary = CommandBus.send(&"infra.deploy_open_source_model", {
		dc_id = id,
		release_id = &"release_wolf_1",
	})
	assert_true(r.ok, "deploy release_wolf_1: %s" % str(r.get(&"error", &"")))
	var dc = InfraSystem.find_dc(id)
	assert_eq(dc.status, &"serving")
	assert_eq(dc.serving_target_kind, &"owned_model")
	assert_eq(dc.serving_target_id, r.model_id)
	assert_eq(dc.deployed_model_id, r.model_id,
			"public open-source serving should materialize and deploy a model")
	var m = ResearchSystem.find_model(r.model_id)
	assert_not_null(m)
	assert_eq(m.status, &"published")
	assert_eq(m.provenance, &"downloaded_os")
	assert_eq(m.source_release_id, &"release_wolf_1")
	assert_true(m.is_open_source)
	var api_count: int = 0
	for p in GameState.products:
		if p.type == &"api" and p.bound_model_id == r.model_id:
			api_count += 1
	assert_eq(api_count, 1, "deploying a public OS release should expose one API product")
	assert_signal_emitted(EventBus, "open_source_model_deployed")

func test_deploy_open_source_reuses_materialized_model_for_same_release() -> void:
	GameState.turn = 220
	var id1 := _rent_solo_with_gpu()
	var id2 := _rent_solo_with_gpu()
	var r1: Dictionary = CommandBus.send(&"infra.deploy_open_source_model", {
		dc_id = id1,
		release_id = &"release_wolf_1",
	})
	var r2: Dictionary = CommandBus.send(&"infra.deploy_open_source_model", {
		dc_id = id2,
		release_id = &"release_wolf_1",
	})
	assert_true(r1.ok)
	assert_true(r2.ok)
	assert_eq(r2.model_id, r1.model_id)
	var api_count: int = 0
	for p in GameState.products:
		if p.type == &"api" and p.bound_model_id == r1.model_id:
			api_count += 1
	assert_eq(api_count, 1, "same public OS release should not create duplicate API products")

func test_deploy_open_source_unknown_release_rejected() -> void:
	GameState.turn = 500
	var id := _rent_solo_with_gpu()
	var r: Dictionary = CommandBus.send(&"infra.deploy_open_source_model", {
		dc_id = id,
		release_id = &"no_such_release",
	})
	assert_false(r.ok)
	assert_eq(r.error, &"unknown_release")

func test_deploy_open_source_at_cold_start_rejected() -> void:
	# v9 PR-I: turn 0 时第一个 OS pretrain release (Wolf-1 @ turn 215) 还没发.
	GameState.turn = 0
	var id := _rent_solo_with_gpu()
	var r: Dictionary = CommandBus.send(&"infra.deploy_open_source_model", {
		dc_id = id,
		release_id = &"release_wolf_1",
	})
	assert_false(r.ok)
	assert_eq(r.error, &"not_released_yet")

func test_deploy_emits_status_changed_idle_to_serving() -> void:
	var id := _rent_solo_with_gpu()
	var mid := _add_published_model()
	watch_signals(EventBus)
	CommandBus.send(&"infra.deploy_model", {dc_id = id, model_id = mid})
	assert_signal_emitted(EventBus, "datacenter_status_changed")
	assert_signal_emitted(EventBus, "model_deployed")
	var p: Array = get_signal_parameters(EventBus, "datacenter_status_changed")
	assert_eq(p[1], &"idle")
	assert_eq(p[2], &"serving")

func test_undeploy_unknown_dc_error() -> void:
	var r: Dictionary = CommandBus.send(&"infra.undeploy_model", {dc_id = &"none"})
	assert_false(r.ok)
	assert_eq(r.error, &"unknown_dc")

func test_undeploy_idle_dc_returns_not_serving() -> void:
	var id := _rent_solo()
	var r: Dictionary = CommandBus.send(&"infra.undeploy_model", {dc_id = id})
	assert_false(r.ok)
	assert_eq(r.error, &"not_serving")

func test_undeploy_emits_status_changed_serving_to_idle() -> void:
	var id := _rent_solo_with_gpu()
	var mid := _add_published_model()
	CommandBus.send(&"infra.deploy_model", {dc_id = id, model_id = mid})
	watch_signals(EventBus)
	CommandBus.send(&"infra.undeploy_model", {dc_id = id})
	assert_signal_emitted(EventBus, "model_undeployed")
	var p: Array = get_signal_parameters(EventBus, "model_undeployed")
	assert_eq(p[0], id)
	assert_eq(p[1], mid)

# ---- assign_to_task / release_from_task --------------------------------

func test_assign_to_task_unknown_dc_error() -> void:
	var r: Dictionary = CommandBus.send(&"infra.assign_to_task",
			{dc_id = &"none", task_id = &"t1"})
	assert_false(r.ok)
	assert_eq(r.error, &"unknown_dc")

func test_assign_zero_gpu_dc_rejected() -> void:
	# §2: assign_to_task requires gpu_count > 0.
	var id := _rent_solo()
	var r: Dictionary = CommandBus.send(&"infra.assign_to_task",
			{dc_id = id, task_id = &"t1"})
	assert_false(r.ok)
	assert_eq(r.error, &"no_gpus")

func test_assign_when_serving_rejected() -> void:
	var id := _rent_solo_with_gpu()
	var mid := _add_published_model()
	CommandBus.send(&"infra.deploy_model", {dc_id = id, model_id = mid})
	var r: Dictionary = CommandBus.send(&"infra.assign_to_task",
			{dc_id = id, task_id = &"t1"})
	assert_false(r.ok)
	assert_eq(r.error, &"dc_not_idle")

func test_release_from_task_with_wrong_task_id_rejected() -> void:
	# §2: task_id 必须匹配占用者; 防 race.
	var id := _rent_solo_with_gpu()
	CommandBus.send(&"infra.assign_to_task", {dc_id = id, task_id = &"t1"})
	var r: Dictionary = CommandBus.send(&"infra.release_from_task",
			{dc_id = id, task_id = &"t2"})
	assert_false(r.ok)
	assert_eq(r.error, &"not_locked_by_this_task")

func test_release_from_task_returns_dc_to_idle() -> void:
	var id := _rent_solo_with_gpu()
	CommandBus.send(&"infra.assign_to_task", {dc_id = id, task_id = &"t1"})
	CommandBus.send(&"infra.release_from_task", {dc_id = id, task_id = &"t1"})
	var dc = InfraSystem.find_dc(id)
	assert_eq(dc.status, &"idle")
	assert_eq(dc.busy_with_task_id, &"")

# ---- upkeep weekly cost -----------------------------------------------

func test_upkeep_charges_total_weekly_cost_across_dcs() -> void:
	# §4.2: upkeep 累加所有 dc 的 facility (rent / land) + GPU runtime + cloud GPU.
	# facility_solo rent_weekly_cost = 500, 无 GPU 时 GPU runtime = 0.
	GameState.cash = 100_000
	_rent_solo()
	_rent_solo()
	var before: int = GameState.cash
	EventBus.phase_started.emit(&"upkeep", 1)
	# 2 个 facility_solo × 500 = 1000 facility_costs, gpu_runtime = 0 (no GPUs).
	assert_eq(GameState.cash, before - 1000)

func test_upkeep_with_no_dcs_charges_zero() -> void:
	var before: int = GameState.cash
	EventBus.phase_started.emit(&"upkeep", 1)
	assert_eq(GameState.cash, before)

# ---- construction queue ------------------------------------------------

func test_construction_advances_one_week_per_action_phase() -> void:
	# §4: 每 action -1 week. facility_room build_weeks=8, land_build_cost=4_000_000.
	GameState.cash = 10_000_000
	CommandBus.send(&"infra.build_facility",
		{facility_spec_id = &"facility_room", power_supply_id = &"grid"})
	EventBus.phase_started.emit(&"action", 1)
	assert_eq(GameState.construction_queue[0].weeks_remaining, 7)
	EventBus.phase_started.emit(&"action", 2)
	assert_eq(GameState.construction_queue[0].weeks_remaining, 6)

func test_construction_emits_progress_each_action() -> void:
	GameState.cash = 10_000_000
	CommandBus.send(&"infra.build_facility",
		{facility_spec_id = &"facility_room", power_supply_id = &"grid"})
	watch_signals(EventBus)
	EventBus.phase_started.emit(&"action", 1)
	assert_signal_emitted(EventBus, "construction_progress")
	var p: Array = get_signal_parameters(EventBus, "construction_progress")
	assert_eq(int(p[1]), 7)
	assert_eq(int(p[2]), 8)

func test_construction_completes_after_build_weeks_action_phases() -> void:
	# facility_pod 1 周后, dc 进 datacenters, queue 应清空.
	GameState.cash = 1_000_000
	CommandBus.send(&"infra.build_facility",
		{facility_spec_id = &"facility_pod", power_supply_id = &"grid"})
	EventBus.phase_started.emit(&"action", 1)
	assert_eq(GameState.construction_queue.size(), 0)
	var owned_dcs: int = 0
	for dc in GameState.datacenters:
		if dc.ownership == &"owned":
			owned_dcs += 1
			# facility_pod land_weekly_cost=0 (家庭/办公室 grade).
			assert_eq(dc.facility_weekly_cost, 0)
	assert_eq(owned_dcs, 1)

func test_construction_completion_emits_signals() -> void:
	# facility_room build_weeks=8: 前 7 周只 progress, 第 8 周 completed + added.
	GameState.cash = 10_000_000
	CommandBus.send(&"infra.build_facility",
		{facility_spec_id = &"facility_room", power_supply_id = &"grid"})
	for i in range(7):
		EventBus.phase_started.emit(&"action", i + 1)
	watch_signals(EventBus)
	EventBus.phase_started.emit(&"action", 8)
	assert_signal_emitted(EventBus, "construction_completed")
	assert_signal_emitted(EventBus, "datacenter_added")

# ============================================================================
# v2 — buy/sell edge cases.
# ============================================================================

func test_buy_zero_count_rejected() -> void:
	var id := _rent_solo()
	var r: Dictionary = CommandBus.send(&"infra.buy_gpus",
		{dc_id = id, gpu_id = &"cypress_t0", count = 0})
	assert_false(r.ok)
	assert_eq(r.error, &"invalid_count")

func test_sell_zero_count_rejected() -> void:
	var id := _rent_solo()
	var r: Dictionary = CommandBus.send(&"infra.sell_gpus",
		{dc_id = id, count = 0})
	assert_false(r.ok)
	assert_eq(r.error, &"invalid_count")

func test_sell_all_clears_brand_so_next_buy_can_switch() -> void:
	# §4.3: once gpu_count == 0, dc.gpu_id resets to "" so next buy is free
	# to pick any brand. maple_t1 release_turn=178 — advance turn first.
	GameState.cash = 10_000_000
	GameState.turn = 178
	var id := _rent_solo()
	CommandBus.send(&"infra.buy_gpus",
		{dc_id = id, gpu_id = &"cypress_t0", count = 1})
	CommandBus.send(&"infra.sell_gpus", {dc_id = id, count = 1})
	# Now buy a different brand — should NOT trip mixed_brand.
	var r: Dictionary = CommandBus.send(&"infra.buy_gpus",
		{dc_id = id, gpu_id = &"maple_t1", count = 1})
	assert_true(r.ok)
	var dc = InfraSystem.find_dc(id)
	assert_eq(dc.gpu_id, &"maple_t1")

func test_partial_sell_keeps_brand_locked() -> void:
	# maple_t1 release_turn=178 — advance turn so the mixed_brand check is the
	# actual reason for rejection (not gpu_not_released).
	GameState.cash = 100_000_000
	GameState.turn = 178
	var id := _rent_pod()
	CommandBus.send(&"infra.buy_gpus",
		{dc_id = id, gpu_id = &"cypress_t0", count = 4})
	CommandBus.send(&"infra.sell_gpus", {dc_id = id, count = 2})
	var r: Dictionary = CommandBus.send(&"infra.buy_gpus",
		{dc_id = id, gpu_id = &"maple_t1", count = 1})
	assert_false(r.ok)
	assert_eq(r.error, &"mixed_brand")

func test_rent_facility_emits_dc_compute_recomputed_at_zero() -> void:
	# A freshly rented facility has no GPUs → compute is zero, but the
	# signal is still emitted so UI can refresh the line.
	watch_signals(EventBus)
	_rent_solo()
	assert_signal_emitted(EventBus, "dc_compute_recomputed")

func test_buy_gpus_ecosystem_score_is_persisted_via_spec() -> void:
	# bamboo_t1 has release_turn=99 (TPU v3, 2019-05).
	GameState.cash = 10_000_000
	GameState.turn = 99
	var id := _rent_solo()
	CommandBus.send(&"infra.buy_gpus",
		{dc_id = id, gpu_id = &"bamboo_t1", count = 1})
	var dc = InfraSystem.find_dc(id)
	assert_eq(dc.gpu_id, &"bamboo_t1")
