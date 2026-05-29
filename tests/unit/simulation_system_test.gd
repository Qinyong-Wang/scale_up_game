extends GutTest

## 宇宙模拟工程 — SimulationStageSpec / SimulationSystem: 启动每一级要选一座
## 自有空闲未出租数据中心永久捐出去 (门槛 = 该 DC 的 train_tflops ≥ min_train_tflops)
## + 现金门槛 + 完成推进 + 终局授奖杯 + 存档。Per design/宇宙模拟工程设计.md。

func before_each() -> void:
	GameState.reset()

func after_each() -> void:
	GameState.reset()

# 造一座可捐 DC。门槛只看 train_tflops, 直接给定。默认自有空闲未出租。
func _make_dc(train_tflops: float, id: StringName = &"dc_test",
		ownership: StringName = &"owned", status: StringName = &"idle") -> Datacenter:
	var dc := Datacenter.new()
	dc.id = id
	dc.ownership = ownership
	dc.status = status
	dc.train_tflops = train_tflops
	dc.gpu_count = 1000
	GameState.datacenters.append(dc)
	return dc

func _drive_tasks_to_completion(max_iters: int = 120) -> void:
	var i: int = 0
	while not GameState.active_tasks.is_empty() and i < max_iters:
		TaskSystem._on_phase(&"action", GameState.turn)
		i += 1

# weather 门槛 2e7: 用 5e7 (清门槛) / 1e7 (不够) 落区间内部, 避免阈值边界翻车。
const WEATHER_OK_TFLOPS: float = 5.0e7
const WEATHER_LOW_TFLOPS: float = 1.0e7

# ---- specs + 阶梯顺序 ---------------------------------------------------

func test_five_stages_load_in_order() -> void:
	var stages: Array = SimulationSystem.all_stages()
	assert_eq(stages.size(), 5)
	assert_eq(stages[0].id, &"weather")
	assert_eq(stages[4].id, &"universe")
	for i in range(stages.size()):
		assert_eq(int(stages[i].order), i, "按 order 升序")

func test_stage_flops_gates_ascending_and_universe_endgame() -> void:
	var stages: Array = SimulationSystem.all_stages()
	for i in range(1, stages.size()):
		assert_gt(float(stages[i].min_train_tflops), float(stages[i - 1].min_train_tflops),
				"算力门槛逐级递增")
	var universe := SimulationSystem.spec_for(&"universe")
	assert_gt(float(universe.min_train_tflops), 1.0e11, "宇宙级门槛为终局体量 (>1e11 TFLOPs)")
	assert_eq(int(universe.cost), 1_000_000_000_000, "宇宙级捐助资金 ¥1T")

func test_next_stage_index_starts_at_zero() -> void:
	assert_eq(SimulationSystem.next_stage_index(), 0)
	assert_false(SimulationSystem.universe_revealed())

# ---- start_stage 门槛: 选 DC + FLOPs + 自有 + 空闲 + 现金 ---------------

func test_start_rejects_unknown_dc() -> void:
	GameState.cash = 2_000_000_000
	var r: Dictionary = CommandBus.send(&"simulation.start_stage", {dc_id = &"nope"})
	assert_eq(r.get(&"error", &""), &"unknown_dc")

func test_start_rejects_dc_not_owned() -> void:
	GameState.cash = 2_000_000_000
	var dc := _make_dc(WEATHER_OK_TFLOPS, &"dc_rent", &"rented")
	var r: Dictionary = CommandBus.send(&"simulation.start_stage", {dc_id = dc.id})
	assert_eq(r.get(&"error", &""), &"dc_not_owned")

func test_start_rejects_dc_busy() -> void:
	GameState.cash = 2_000_000_000
	var dc := _make_dc(WEATHER_OK_TFLOPS, &"dc_busy", &"owned", &"training")
	var r: Dictionary = CommandBus.send(&"simulation.start_stage", {dc_id = dc.id})
	assert_eq(r.get(&"error", &""), &"dc_busy")

func test_start_rejects_rent_out_enabled_dc() -> void:
	GameState.cash = 2_000_000_000
	var dc := _make_dc(WEATHER_OK_TFLOPS, &"dc_renting")
	dc.rent_out_enabled = true
	var r: Dictionary = CommandBus.send(&"simulation.start_stage", {dc_id = dc.id})
	assert_eq(r.get(&"error", &""), &"dc_rented_out")
	assert_eq(GameState.datacenters.size(), 1, "失败不消耗正在出租的 DC")
	assert_eq(GameState.active_tasks.size(), 0, "失败不创建 simulation 任务")

func test_start_rejects_compute_too_small() -> void:
	GameState.cash = 2_000_000_000
	var dc := _make_dc(WEATHER_LOW_TFLOPS)
	var r: Dictionary = CommandBus.send(&"simulation.start_stage", {dc_id = dc.id})
	assert_eq(r.get(&"error", &""), &"compute_too_small")

func test_start_rejects_insufficient_cash() -> void:
	var dc := _make_dc(WEATHER_OK_TFLOPS)
	GameState.cash = 5_000_000   # << weather 1B cost
	var r: Dictionary = CommandBus.send(&"simulation.start_stage", {dc_id = dc.id})
	assert_eq(r.get(&"error", &""), &"insufficient_cash")
	assert_eq(GameState.datacenters.size(), 1, "失败不消耗 DC")

func test_start_succeeds_consumes_dc_and_charges() -> void:
	var dc := _make_dc(WEATHER_OK_TFLOPS)
	GameState.cash = 2_000_000_000
	var r: Dictionary = CommandBus.send(&"simulation.start_stage", {dc_id = dc.id})
	assert_true(r.get(&"ok", false))
	assert_eq(StringName(r.stage_id), &"weather")
	assert_eq(StringName(r.donated_dc_id), &"dc_test")
	assert_eq(GameState.cash, 2_000_000_000 - 1_000_000_000, "启动当周扣 weather cost ¥1B")
	assert_eq(GameState.datacenters.size(), 0, "捐出的 DC 被永久移除")
	assert_eq(GameState.active_tasks.size(), 1)
	assert_eq(GameState.active_tasks[0].subtype, &"simulation")

func test_start_rejects_already_running() -> void:
	var dc1 := _make_dc(WEATHER_OK_TFLOPS, &"dc1")
	var dc2 := _make_dc(WEATHER_OK_TFLOPS, &"dc2")
	GameState.cash = 5_000_000_000
	CommandBus.send(&"simulation.start_stage", {dc_id = dc1.id})
	var r: Dictionary = CommandBus.send(&"simulation.start_stage", {dc_id = dc2.id})
	assert_eq(r.get(&"error", &""), &"already_running")
	assert_eq(GameState.datacenters.size(), 1, "第二次被拒, dc2 未被消耗")

func test_start_rejects_all_done() -> void:
	GameState.simulation_stages_done = 5
	var dc := _make_dc(1.0e12)
	GameState.cash = 999_999_999_999
	var r: Dictionary = CommandBus.send(&"simulation.start_stage", {dc_id = dc.id})
	assert_eq(r.get(&"error", &""), &"all_done")

# ---- eligible_datacenters 过滤 -----------------------------------------

func test_eligible_datacenters_filters_owned_idle_qualifying() -> void:
	_make_dc(WEATHER_OK_TFLOPS, &"good")                          # 合格
	_make_dc(WEATHER_LOW_TFLOPS, &"too_small")                    # 算力不够
	_make_dc(WEATHER_OK_TFLOPS, &"rent", &"rented")               # 非自有
	_make_dc(WEATHER_OK_TFLOPS, &"busy", &"owned", &"serving")    # 非空闲
	var renting := _make_dc(WEATHER_OK_TFLOPS, &"rent_out")       # 正在对外出租
	renting.rent_out_enabled = true
	var weather := SimulationSystem.spec_for(&"weather")
	var eligible: Array = SimulationSystem.eligible_datacenters(weather)
	assert_eq(eligible.size(), 1)
	assert_eq(eligible[0].id, &"good")

# ---- 完成推进 -----------------------------------------------------------

func test_complete_advances_ladder() -> void:
	watch_signals(EventBus)
	var r: Dictionary = CommandBus.send(&"simulation.complete_stage", {stage_id = &"weather"})
	assert_true(r.get(&"ok", false))
	assert_eq(SimulationSystem.stages_done(), 1)
	assert_signal_emitted(EventBus, "simulation_stage_completed")

func test_complete_unknown_stage_rejected() -> void:
	var r: Dictionary = CommandBus.send(&"simulation.complete_stage", {stage_id = &"nope"})
	assert_false(r.get(&"ok", false))

func test_universe_completion_awards_trophy_and_reveals() -> void:
	watch_signals(EventBus)
	GameState.simulation_stages_done = 4   # 前四级已完成
	var r: Dictionary = CommandBus.send(&"simulation.complete_stage", {stage_id = &"universe"})
	assert_true(r.get(&"ok", false))
	assert_eq(SimulationSystem.stages_done(), 5)
	assert_true(SimulationSystem.universe_revealed())
	assert_true(GameState.trophies.has(&"universe_answer"), "应点亮终极答案奖杯")
	assert_signal_emitted(EventBus, "universe_answer_revealed")
	assert_signal_emitted(EventBus, "trophy_awarded")

# ---- 端到端: 启动 → 跑满 → 推进 ---------------------------------------

func test_stage_task_runs_to_completion_and_advances() -> void:
	var dc := _make_dc(WEATHER_OK_TFLOPS)
	GameState.cash = 2_000_000_000
	CommandBus.send(&"simulation.start_stage", {dc_id = dc.id})   # weather, 8 周
	assert_eq(SimulationSystem.stages_done(), 0, "进行中尚未推进")
	_drive_tasks_to_completion()
	assert_eq(GameState.active_tasks.size(), 0)
	assert_eq(SimulationSystem.stages_done(), 1, "跑满后阶梯推进一级")

# ---- 真实算力对标: 微型星球 + Cypress T3 清宇宙门槛, 低一档清不了 -------

func _real_train_tflops(facility_id: StringName, gpu_count: int) -> float:
	# 走 InfraSystem 真实派生公式 (单卡算力 × 卡数 × 集群效率 × 生态 × 太空加速)。
	var dc := Datacenter.new()
	dc.id = &"dc_bal"
	dc.facility_spec_id = facility_id
	dc.ownership = &"owned"
	dc.power_supply = &"grid"
	dc.gpu_id = &"cypress_t3"
	dc.gpu_count = gpu_count
	dc.max_gpu_count = gpu_count
	InfraSystem._recompute_compute(dc)
	return dc.train_tflops

func test_planet_cypress_clears_universe_smaller_does_not() -> void:
	var universe := SimulationSystem.spec_for(&"universe")
	var solar := SimulationSystem.spec_for(&"solar_system")
	# 微型星球 (100M 卡) 装满 Cypress T3 → 清宇宙门槛。
	var planet: float = _real_train_tflops(&"facility_planet", 100_000_000)
	assert_gt(planet, float(universe.min_train_tflops), "微型星球+CypressT3 单座 DC 应清宇宙门槛")
	# 低一档太空 (20M 卡) → 清太阳系但清不了宇宙。
	var space_l: float = _real_train_tflops(&"facility_space_l", 20_000_000)
	assert_gt(space_l, float(solar.min_train_tflops), "2000 万卡太空应清太阳系门槛")
	assert_lt(space_l, float(universe.min_train_tflops), "但清不了宇宙门槛, 终局必须微型星球")

# ---- 存档 + 抵税 --------------------------------------------------------

func test_stages_done_round_trips() -> void:
	GameState.simulation_stages_done = 3
	var d: Dictionary = GameState.to_dict()
	GameState.reset()
	assert_eq(SimulationSystem.stages_done(), 0)
	GameState.from_dict(d)
	assert_eq(SimulationSystem.stages_done(), 3)

func test_funding_reason_is_tax_deductible() -> void:
	assert_false(EconomySystem.NON_TAXABLE_REASONS.has(&"simulation_funding"),
			"宇宙模拟捐助应可抵税")
