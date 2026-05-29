extends GutTest

## Regression test: 1 turn = 1 week, every upkeep phase charges exactly one
## week worth of facility / GPU / power / salary costs. Per design/平衡参数.md
## §0bis (time unit) + design/基础设施系统设计.md §6.2.
##
## Catches the pre-rebalance bug where *_monthly_* fields were sized as months
## but charged each turn (= 4.3× overcharge).


func before_each() -> void:
	GameState.reset()
	GameState.cash = 10_000_000

# ---- facility rent has zero upfront -------------------------------------

func test_rent_facility_solo_charges_nothing_at_creation() -> void:
	# facility_solo.rent_weekly_cost = 500; should NOT be charged at rent time.
	var before: int = GameState.cash
	var r: Dictionary = CommandBus.send(&"infra.rent_facility",
		{facility_spec_id = &"facility_solo", power_supply_id = &"grid"})
	assert_true(r.ok)
	assert_eq(GameState.cash, before)

func test_debug_instant_owned_dc_charges_nothing() -> void:
	# Debug command also has zero upfront cost.
	var before: int = GameState.cash
	CommandBus.send(&"infra.debug_instant_owned_dc",
		{facility_spec_id = &"facility_solo", gpu_id = &"cypress_t0"})
	assert_eq(GameState.cash, before)

# ---- one upkeep == one week charge --------------------------------------

func test_solo_rented_charges_exactly_one_week_per_upkeep() -> void:
	CommandBus.send(&"infra.rent_facility",
		{facility_spec_id = &"facility_solo", power_supply_id = &"grid"})
	# 4 upkeep phases = 4 weeks of rent.
	var before: int = GameState.cash
	for _i in range(4):
		EventBus.phase_started.emit(&"upkeep", 1)
	# 4 × rent_weekly_cost(500) = 2000.
	assert_eq(GameState.cash, before - 4 * 500)

# ---- solo/pod/rack have zero facility upkeep ----------------------------

func test_solo_has_zero_land_weekly_cost() -> void:
	var spec: FacilitySpec = load("res://resources/data/infra/facilities/facility_solo.tres")
	assert_eq(spec.land_weekly_cost, 0)

func test_pod_has_zero_land_weekly_cost() -> void:
	var spec: FacilitySpec = load("res://resources/data/infra/facilities/facility_pod.tres")
	assert_eq(spec.land_weekly_cost, 0)

func test_rack_has_zero_land_weekly_cost() -> void:
	var spec: FacilitySpec = load("res://resources/data/infra/facilities/facility_rack.tres")
	assert_eq(spec.land_weekly_cost, 0)

# ---- GPU = 60% of build cost rule (room and above) ----------------------

func test_room_build_cost_implies_gpu_60_percent_share() -> void:
	# Rule: land_build_cost is 40% of total; GPU (at baseline $12k/card) is 60%.
	# For room (500 cards): GPU = 500×$12k = $6M; land = $4M = 40% of $10M.
	var spec: FacilitySpec = load("res://resources/data/infra/facilities/facility_room.tres")
	var gpu_baseline_per_card: int = 12000
	var gpu_total: int = spec.max_gpu_count * gpu_baseline_per_card
	var total: int = gpu_total + spec.land_build_cost
	var gpu_share: float = float(gpu_total) / float(total)
	assert_almost_eq(gpu_share, 0.60, 0.02)

# ---- cloud GPU rental: per-card per-week, no upfront --------------------

func test_create_cloud_dc_zero_upfront() -> void:
	var before: int = GameState.cash
	# cypress_t0 (V100-era) is the only GPU available at turn 0 after PR-A.
	var r: Dictionary = CommandBus.send(&"infra.create_cloud_dc",
		{gpu_id = &"cypress_t0", count = 8})
	assert_true(r.ok)
	assert_eq(GameState.cash, before, "cloud GPU rental must have zero upfront")

func test_cloud_dc_charges_weekly_per_card_on_upkeep() -> void:
	var r: Dictionary = CommandBus.send(&"infra.create_cloud_dc",
		{gpu_id = &"cypress_t0", count = 8})
	assert_true(r.ok)
	# cypress_t0.rent_weekly_cost = 130 (2026-05 砍半到 40 周回本); 8 cards = 1040/week.
	var before: int = GameState.cash
	EventBus.phase_started.emit(&"upkeep", 1)
	assert_eq(GameState.cash, before - 8 * 130)

func test_cloud_dc_cached_weekly_cost_matches_actual_charge() -> void:
	# UI (dc_card 周成本) reads dc.facility_weekly_cost; it must match the actual
	# upkeep deduction. For cloud DCs that means rent_weekly_cost × gpu_count, not
	# the on-prem maintenance + electricity formula.
	var r: Dictionary = CommandBus.send(&"infra.create_cloud_dc",
		{gpu_id = &"cypress_t0", count = 8})
	assert_true(r.ok)
	var dc: Datacenter = null
	for d in GameState.datacenters:
		if d.id == StringName(r.dc_id):
			dc = d
			break
	assert_not_null(dc)
	# cypress_t0.rent_weekly_cost = 130 (2026-05 砍半到 40 周回本).
	assert_eq(int(dc.facility_weekly_cost), 8 * 130)

# ---- salary is weekly ---------------------------------------------------

func test_staff_upkeep_charges_weekly_salary_per_turn() -> void:
	# ml_eng weekly_salary = 6730 (350k¥/year per 2026-05 rev). Add 2; first
	# week charged immediately at the adjust_staff call.
	CommandBus.send(&"hiring.adjust_staff", {role = &"ml_eng", delta = 2})
	var before: int = GameState.cash
	EventBus.phase_started.emit(&"upkeep", 1)
	# 2 × 6730 = 13_460 per week.
	assert_eq(GameState.cash, before - 13_460)

# ---- power supply weekly cost -------------------------------------------

func test_grid_power_weekly_cost_per_card_is_24() -> void:
	# 2026-05: grid 基准电费 14→24 (cypress_t1 锚点; 真实全口径机房功耗含整机+散热)。
	var spec: PowerSupplySpec = load("res://resources/data/infra/power/grid.tres")
	assert_eq(spec.weekly_cost_per_card, 24)
