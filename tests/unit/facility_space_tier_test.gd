extends GutTest

## Space datacenter tiers (facility_space_s/m/l) — 6M/12M/20M cards.
## Per design/基础设施系统设计.md §0: deployment cost (land_build_cost) doubled
## per-card vs metropolis baseline ($16K/card); weekly rent/land scale linearly.


func before_each() -> void:
	GameState.reset()


# ---- spec loading ------------------------------------------------------

func test_space_specs_load_with_expected_capacity() -> void:
	var s: FacilitySpec = load("res://resources/data/infra/facilities/facility_space_s.tres")
	var m: FacilitySpec = load("res://resources/data/infra/facilities/facility_space_m.tres")
	var l: FacilitySpec = load("res://resources/data/infra/facilities/facility_space_l.tres")
	assert_not_null(s, "facility_space_s should load")
	assert_not_null(m, "facility_space_m should load")
	assert_not_null(l, "facility_space_l should load")
	assert_eq(s.max_gpu_count, 6_000_000)
	assert_eq(m.max_gpu_count, 12_000_000)
	assert_eq(l.max_gpu_count, 20_000_000)
	# tier_index keeps space tiers strictly above metropolis (15).
	assert_gt(s.tier_index, 15)
	assert_gt(m.tier_index, s.tier_index)
	assert_gt(l.tier_index, m.tier_index)


func test_space_build_cost_is_double_metropolis_per_card() -> void:
	# metropolis baseline: $24B / 3M = $8000/card.
	# space tiers: $16000/card (deployment cost doubled).
	var metro: FacilitySpec = load("res://resources/data/infra/facilities/facility_metropolis.tres")
	var per_card_metro: float = float(metro.land_build_cost) / float(metro.max_gpu_count)
	var paths := [
		"res://resources/data/infra/facilities/facility_space_s.tres",
		"res://resources/data/infra/facilities/facility_space_m.tres",
		"res://resources/data/infra/facilities/facility_space_l.tres",
		"res://resources/data/infra/facilities/facility_planet.tres",
	]
	for p in paths:
		var s: FacilitySpec = load(p)
		var per_card: float = float(s.land_build_cost) / float(s.max_gpu_count)
		assert_almost_eq(per_card, per_card_metro * 2.0, 1.0,
			"%s build cost per card should be 2x metropolis ($16K)" % p)


# ---- space training speed bonus ----------------------------------------

func test_space_tiers_carry_train_speed_bonus() -> void:
	# 真空辐射散热 → 无热降频, 训练吞吐 +10~20% (按档递增)。
	var s: FacilitySpec = load("res://resources/data/infra/facilities/facility_space_s.tres")
	var m: FacilitySpec = load("res://resources/data/infra/facilities/facility_space_m.tres")
	var l: FacilitySpec = load("res://resources/data/infra/facilities/facility_space_l.tres")
	var p: FacilitySpec = load("res://resources/data/infra/facilities/facility_planet.tres")
	assert_almost_eq(s.train_speed_bonus, 0.10, 0.0001)
	assert_almost_eq(m.train_speed_bonus, 0.15, 0.0001)
	assert_almost_eq(l.train_speed_bonus, 0.20, 0.0001)
	assert_almost_eq(p.train_speed_bonus, 0.20, 0.0001)


func test_ground_tiers_have_no_train_speed_bonus() -> void:
	# 地面档 (metropolis 及以下) 无训练加成。
	var metro: FacilitySpec = load("res://resources/data/infra/facilities/facility_metropolis.tres")
	var solo: FacilitySpec = load("res://resources/data/infra/facilities/facility_solo.tres")
	assert_eq(metro.train_speed_bonus, 0.0)
	assert_eq(solo.train_speed_bonus, 0.0)


func test_facility_train_bonus_accessor() -> void:
	# InfraSystem.facility_train_bonus 给 UI 单独取加成; 云 DC (空 id) → 0。
	assert_almost_eq(InfraSystem.facility_train_bonus(&"facility_space_l"), 0.20, 0.0001)
	assert_eq(InfraSystem.facility_train_bonus(&"facility_solo"), 0.0)
	assert_eq(InfraSystem.facility_train_bonus(&""), 0.0)


func test_space_dc_train_tflops_includes_speed_bonus() -> void:
	# space_s (+10%) 的 train_tflops 应比纯 per_card×count×ce×ecosystem 高 10%;
	# inference_tflops 不受影响 (只加训练)。
	GameState.cash = 50_000_000_000  # > space_s 10B unlock
	var r: Dictionary = CommandBus.send(&"infra.rent_facility",
		{facility_spec_id = &"facility_space_s", power_supply_id = &"grid"})
	assert_true(r.ok, "rent space_s failed: %s" % str(r.get(&"error", &"")))
	var b: Dictionary = CommandBus.send(&"infra.buy_gpus",
		{dc_id = r.dc_id, gpu_id = &"cypress_t0", count = 100})
	assert_true(b.ok, "buy_gpus failed: %s" % str(b.get(&"error", &"")))
	var dc = InfraSystem.find_dc(r.dc_id)
	# cypress_t0: per_card_tflops 125, per_card_inference 37.5, ecosystem 1.0.
	var base: float = 125.0 * 100.0 * dc.cluster_efficiency * 1.0
	assert_almost_eq(dc.train_tflops, base * 1.10, base * 0.001,
		"太空 DC 训练算力应含 +10% 加成")
	assert_almost_eq(dc.inference_tflops, 37.5 * 100.0 * dc.cluster_efficiency, 1.0,
		"推理算力不受太空训练加成影响")


# ---- planet tier (100M cards, top space tier) --------------------------

func test_planet_spec_loads_with_100m_capacity() -> void:
	var p: FacilitySpec = load("res://resources/data/infra/facilities/facility_planet.tres")
	assert_not_null(p, "facility_planet should load")
	if p == null:
		return
	assert_eq(p.max_gpu_count, 100_000_000)
	# planet sits strictly above space_l (top of the orbital tiers).
	var l: FacilitySpec = load("res://resources/data/infra/facilities/facility_space_l.tres")
	assert_gt(p.tier_index, l.tier_index)
	# linear extension of the space baseline: $16K/card build, $15/card/wk land,
	# $75/card/wk rent, ~$175B cash gate.
	assert_eq(p.land_build_cost, 1_600_000_000_000)
	assert_eq(p.land_weekly_cost, 1_500_000_000)
	assert_eq(p.rent_weekly_cost, 7_500_000_000)
	assert_eq(p.unlock_cash_required, 175_000_000_000)


func test_planet_registered_in_facility_specs() -> void:
	assert_true(InfraSystem.FACILITY_SPECS.has(&"facility_planet"),
		"facility_planet should be registered in InfraSystem.FACILITY_SPECS")


func test_rent_planet_blocked_without_unlock_cash() -> void:
	# unlock_cash_required = 175B; starting cash is far below.
	var r: Dictionary = CommandBus.send(&"infra.rent_facility",
		{facility_spec_id = &"facility_planet", power_supply_id = &"grid"})
	assert_false(r.ok)
	assert_eq(r.error, &"facility_unlock_required")


func test_rent_planet_succeeds_with_unlock_cash() -> void:
	GameState.cash = 200_000_000_000  # > 175B unlock for planet
	var r: Dictionary = CommandBus.send(&"infra.rent_facility",
		{facility_spec_id = &"facility_planet", power_supply_id = &"grid"})
	assert_true(r.ok, "rent planet failed: %s" % str(r.get(&"error", &"")))
	var dc = InfraSystem.find_dc(r.dc_id)
	assert_eq(dc.max_gpu_count, 100_000_000)
	assert_eq(dc.status, &"idle")


# ---- unlock gate -------------------------------------------------------

func test_rent_space_l_blocked_without_unlock_cash() -> void:
	# unlock_cash_required = 35B; starting cash is 80K.
	var r: Dictionary = CommandBus.send(&"infra.rent_facility",
		{facility_spec_id = &"facility_space_l", power_supply_id = &"grid"})
	assert_false(r.ok)
	assert_eq(r.error, &"facility_unlock_required")


func test_rent_space_s_succeeds_with_unlock_cash() -> void:
	GameState.cash = 15_000_000_000  # > 10B unlock for space_s
	var r: Dictionary = CommandBus.send(&"infra.rent_facility",
		{facility_spec_id = &"facility_space_s", power_supply_id = &"grid"})
	assert_true(r.ok, "rent space_s failed: %s" % str(r.get(&"error", &"")))
	var dc = InfraSystem.find_dc(r.dc_id)
	assert_eq(dc.max_gpu_count, 6_000_000)
	assert_eq(dc.status, &"idle")


# ---- build cost ledger -------------------------------------------------

func test_build_space_s_charges_full_land_build_cost() -> void:
	# grid power → no per-card install cost. land_build_cost = $96B.
	GameState.cash = 200_000_000_000
	var before: int = GameState.cash
	var r: Dictionary = CommandBus.send(&"infra.build_facility",
		{facility_spec_id = &"facility_space_s", power_supply_id = &"grid"})
	assert_true(r.ok, "build space_s failed: %s" % str(r.get(&"error", &"")))
	assert_eq(GameState.cash, before - 96_000_000_000)
