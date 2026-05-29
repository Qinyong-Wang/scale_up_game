extends GutTest

## HiringSystem v1 — hire/fire/lock/release/assign/unassign + staff,
## salaries on upkeep, lead_pool refresh on action.
## Per design/招聘系统设计.md.


func before_each() -> void:
	GameState.reset()

func _make_pool_lead(specialty: StringName = &"chief_scientist", level: StringName = &"A") -> Lead:
	var l := Lead.new()
	l.id = &"lead_test_001"
	l.display_name = "Test Lead"
	l.specialty = specialty
	l.level = level
	l.ability = 78.0
	l.signing_fee = 1_000_000
	l.weekly_salary = 96_150
	GameState.lead_pool.append(l)
	return l

# ---- hire / fire --------------------------------------------------------

func test_hire_lead_unknown_pool_lead_returns_error() -> void:
	var r: Dictionary = CommandBus.send(&"hiring.hire_lead", {pool_lead_id = &"no_such"})
	assert_false(r.ok)
	assert_eq(r.error, &"unknown_pool_lead")

func test_hire_lead_moves_from_pool_to_leads() -> void:
	var l := _make_pool_lead()
	var r: Dictionary = CommandBus.send(&"hiring.hire_lead", {pool_lead_id = l.id})
	assert_true(r.ok)
	assert_eq(GameState.leads.size(), 1)
	assert_eq(GameState.lead_pool.size(), 0)

func test_hire_lead_charges_signing_fee() -> void:
	var l := _make_pool_lead()
	var before: int = GameState.cash
	CommandBus.send(&"hiring.hire_lead", {pool_lead_id = l.id})
	assert_eq(GameState.cash, before - l.signing_fee)

func test_hire_lead_emits_lead_hired() -> void:
	var l := _make_pool_lead()
	watch_signals(EventBus)
	CommandBus.send(&"hiring.hire_lead", {pool_lead_id = l.id})
	assert_signal_emitted(EventBus, "lead_hired")

func test_fire_lead_unknown_returns_error() -> void:
	var r: Dictionary = CommandBus.send(&"hiring.fire_lead", {lead_id = &"none"})
	assert_false(r.ok)
	assert_eq(r.error, &"unknown_lead")

func test_fire_busy_lead_rejected() -> void:
	var l := _make_pool_lead()
	CommandBus.send(&"hiring.hire_lead", {pool_lead_id = l.id})
	CommandBus.send(&"hiring.lock_lead", {lead_id = l.id, task_id = &"task_xyz"})
	var r: Dictionary = CommandBus.send(&"hiring.fire_lead", {lead_id = l.id})
	assert_false(r.ok)
	assert_eq(r.error, &"lead_busy")

func test_fire_idle_lead_removes_from_leads() -> void:
	var l := _make_pool_lead()
	CommandBus.send(&"hiring.hire_lead", {pool_lead_id = l.id})
	var r: Dictionary = CommandBus.send(&"hiring.fire_lead", {lead_id = l.id})
	assert_true(r.ok)
	assert_eq(GameState.leads.size(), 0)

# ---- lock / release -----------------------------------------------------

func test_lock_lead_sets_locked_by_task_id() -> void:
	var l := _make_pool_lead()
	CommandBus.send(&"hiring.hire_lead", {pool_lead_id = l.id})
	var r: Dictionary = CommandBus.send(&"hiring.lock_lead", {lead_id = l.id, task_id = &"task_a"})
	assert_true(r.ok)
	assert_eq(HiringSystem.find_lead(l.id).locked_by_task_id, &"task_a")

func test_lock_already_locked_lead_returns_error() -> void:
	var l := _make_pool_lead()
	CommandBus.send(&"hiring.hire_lead", {pool_lead_id = l.id})
	CommandBus.send(&"hiring.lock_lead", {lead_id = l.id, task_id = &"task_a"})
	var r: Dictionary = CommandBus.send(&"hiring.lock_lead", {lead_id = l.id, task_id = &"task_b"})
	assert_false(r.ok)
	assert_eq(r.error, &"already_locked")

func test_lock_assigned_lead_returns_error() -> void:
	var l := _make_pool_lead(&"chief_engineer")
	CommandBus.send(&"hiring.hire_lead", {pool_lead_id = l.id})
	CommandBus.send(&"hiring.assign_lead", {lead_id = l.id, product_id = &"p1"})
	var r: Dictionary = CommandBus.send(&"hiring.lock_lead", {lead_id = l.id, task_id = &"t"})
	assert_false(r.ok)
	assert_eq(r.error, &"already_assigned")

func test_release_with_wrong_task_id_returns_error() -> void:
	var l := _make_pool_lead()
	CommandBus.send(&"hiring.hire_lead", {pool_lead_id = l.id})
	CommandBus.send(&"hiring.lock_lead", {lead_id = l.id, task_id = &"task_a"})
	var r: Dictionary = CommandBus.send(&"hiring.release_lead", {lead_id = l.id, task_id = &"task_b"})
	assert_false(r.ok)
	assert_eq(r.error, &"not_locked_by_this_task")

func test_release_clears_locked_by() -> void:
	var l := _make_pool_lead()
	CommandBus.send(&"hiring.hire_lead", {pool_lead_id = l.id})
	CommandBus.send(&"hiring.lock_lead", {lead_id = l.id, task_id = &"task_a"})
	CommandBus.send(&"hiring.release_lead", {lead_id = l.id, task_id = &"task_a"})
	assert_eq(HiringSystem.find_lead(l.id).locked_by_task_id, &"")

# ---- assign / unassign --------------------------------------------------

func test_assign_locked_lead_returns_error() -> void:
	var l := _make_pool_lead()
	CommandBus.send(&"hiring.hire_lead", {pool_lead_id = l.id})
	CommandBus.send(&"hiring.lock_lead", {lead_id = l.id, task_id = &"task_a"})
	var r: Dictionary = CommandBus.send(&"hiring.assign_lead", {lead_id = l.id, product_id = &"p"})
	assert_false(r.ok)
	assert_eq(r.error, &"already_locked")

func test_unassign_idle_lead_returns_error() -> void:
	var l := _make_pool_lead()
	CommandBus.send(&"hiring.hire_lead", {pool_lead_id = l.id})
	var r: Dictionary = CommandBus.send(&"hiring.unassign_lead", {lead_id = l.id})
	assert_false(r.ok)
	assert_eq(r.error, &"not_assigned")

# ---- staff --------------------------------------------------------------

func test_adjust_staff_unknown_role_returns_error() -> void:
	var r: Dictionary = CommandBus.send(&"hiring.adjust_staff", {role = &"foo", delta = 1})
	assert_false(r.ok)
	assert_eq(r.error, &"unknown_role")

func test_adjust_staff_increases_pool_and_charges_first_week() -> void:
	var before: int = GameState.cash
	var r: Dictionary = CommandBus.send(&"hiring.adjust_staff", {role = &"ml_eng", delta = 3})
	assert_true(r.ok)
	assert_eq(GameState.staff_pool[&"ml_eng"], 3)
	# ml_eng weekly_salary = 6730 (350k/year); first-week charge on hire.
	assert_eq(GameState.cash, before - 3 * 6730)

func test_adjust_staff_negative_below_zero_rejected() -> void:
	var r: Dictionary = CommandBus.send(&"hiring.adjust_staff", {role = &"ml_eng", delta = -1})
	assert_false(r.ok)
	assert_eq(r.error, &"would_go_negative")

func test_adjust_staff_would_fire_busy_rejected() -> void:
	CommandBus.send(&"hiring.adjust_staff", {role = &"ml_eng", delta = 3})
	CommandBus.send(&"hiring.lock_staff", {role = &"ml_eng", count = 2, holder_id = &"task_a"})
	# Trying to drop pool to 1 while 2 are busy must be rejected.
	var r: Dictionary = CommandBus.send(&"hiring.adjust_staff", {role = &"ml_eng", delta = -2})
	assert_false(r.ok)
	assert_eq(r.error, &"would_fire_busy")

func test_lock_staff_insufficient_returns_error() -> void:
	var r: Dictionary = CommandBus.send(&"hiring.lock_staff", {role = &"ml_eng", count = 2, holder_id = &"x"})
	assert_false(r.ok)
	assert_eq(r.error, &"insufficient_idle")

func test_release_staff_over_release_returns_error() -> void:
	CommandBus.send(&"hiring.adjust_staff", {role = &"ml_eng", delta = 3})
	CommandBus.send(&"hiring.lock_staff", {role = &"ml_eng", count = 2, holder_id = &"x"})
	var r: Dictionary = CommandBus.send(&"hiring.release_staff", {role = &"ml_eng", count = 5, holder_id = &"x"})
	assert_false(r.ok)
	assert_eq(r.error, &"over_release")

# ---- phase --------------------------------------------------------------

func test_upkeep_phase_pays_total_salary() -> void:
	# 2 ml_eng × 6730 = 13_460 (first-week charged immediately)
	# 1 A-lead × 96_150 (per upkeep)
	# Per design/平衡参数.md §HiringSystem (2026-05 rev).
	CommandBus.send(&"hiring.adjust_staff", {role = &"ml_eng", delta = 2})
	var hire_l := _make_pool_lead()
	hire_l.weekly_salary = 96_150
	CommandBus.send(&"hiring.hire_lead", {pool_lead_id = hire_l.id})  # signing fee
	var before: int = GameState.cash
	EventBus.phase_started.emit(&"upkeep", 1)
	assert_eq(GameState.cash, before - (2 * 6730 + 96_150))

func test_action_phase_refreshes_lead_pool() -> void:
	GameState.lead_pool = []
	EventBus.phase_started.emit(&"action", 1)
	assert_gt(GameState.lead_pool.size(), 0)

func test_action_phase_emits_lead_pool_refreshed() -> void:
	watch_signals(EventBus)
	EventBus.phase_started.emit(&"action", 1)
	assert_signal_emitted(EventBus, "lead_pool_refreshed")

# ---- specialties --------------------------------------------------------

func test_specialties_contain_six_roles() -> void:
	# Per design/招聘系统设计.md §1.1: 6 specialties, including the
	# new ml_research_lead and eval_lead.
	var s: Array = HiringSystem.SPECIALTIES
	assert_eq(s.size(), 6, "expected 6 specialties, got %s" % [s])
	for needed in [
		&"chief_scientist", &"ml_research_lead", &"eval_lead",
		&"chief_engineer", &"data_scientist", &"marketing_lead",
	]:
		assert_true(s.has(needed), "missing specialty %s" % needed)

func test_lead_pool_can_draw_new_specialties() -> void:
	# Force a deterministic seed and refresh enough times that all 6 specialties
	# get drawn at least once across the pool. With 6 specialties, 6 slots,
	# and a few refreshes, coverage is essentially guaranteed.
	GameState.rng_seed = 42
	var seen := {}
	for _i in range(20):
		EventBus.phase_started.emit(&"action", 1)
		for l in GameState.lead_pool:
			seen[l.specialty] = true
	assert_true(seen.has(&"ml_research_lead"), "ml_research_lead never drawn")
	assert_true(seen.has(&"eval_lead"), "eval_lead never drawn")

# ---- LEAD_BONUS_TABLE ---------------------------------------------------

func test_lead_bonus_table_has_all_specialties() -> void:
	var t: Dictionary = HiringSystem.LEAD_BONUS_TABLE
	for sp in [
		&"chief_scientist", &"ml_research_lead", &"eval_lead",
		&"chief_engineer", &"data_scientist", &"marketing_lead",
	]:
		assert_true(t.has(sp), "LEAD_BONUS_TABLE missing %s" % sp)
		assert_true(t[sp] is Dictionary, "%s entry must be a Dictionary" % sp)

func test_lead_bonus_table_values_match_balance_params() -> void:
	var t: Dictionary = HiringSystem.LEAD_BONUS_TABLE
	# Values per design/平衡参数.md §LEAD_BONUS_TABLE (2026-05 rev, 4 象限).
	# Pretrain quadrant: chief_scientist
	assert_almost_eq(float(t[&"chief_scientist"][&"pretrain_speed"]), 0.22, 0.001)
	assert_almost_eq(float(t[&"chief_scientist"][&"pretrain_score_bonus"]), 0.06, 0.001)
	assert_almost_eq(float(t[&"chief_scientist"][&"posttrain_speed"]), 0.11, 0.001)
	# Research quadrant: chief_scientist
	assert_almost_eq(float(t[&"chief_scientist"][&"research_speed"]), 0.55, 0.001)
	# Posttrain quadrant: ml_research_lead
	assert_almost_eq(float(t[&"ml_research_lead"][&"posttrain_speed"]), 0.28, 0.001)
	assert_almost_eq(float(t[&"ml_research_lead"][&"posttrain_score_bonus"]), 0.06, 0.001)
	assert_almost_eq(float(t[&"ml_research_lead"][&"evaluate_score_bonus"]), 0.11, 0.001)
	# Eval (post posttrain) speed
	assert_almost_eq(float(t[&"eval_lead"][&"evaluate_speed"]), 0.33, 0.001)
	# Infra
	assert_almost_eq(float(t[&"chief_engineer"][&"cluster_eff_add"]), 0.06, 0.001)
	assert_almost_eq(float(t[&"chief_engineer"][&"product_throughput"]), 0.22, 0.001)
	# Data
	assert_almost_eq(float(t[&"data_scientist"][&"data_collection_speed"]), 0.44, 0.001)
	assert_almost_eq(float(t[&"data_scientist"][&"data_quality_add"]), 0.22, 0.001)
	# Marketing quadrant (CAC reduction via campaign efficiency)
	assert_almost_eq(float(t[&"marketing_lead"][&"campaign_efficiency"]), 0.55, 0.001)

# ---- lead_speedup_for() -------------------------------------------------

func _new_lead(specialty: StringName, ability: float) -> Lead:
	var l := Lead.new()
	l.id = &"l1"
	l.specialty = specialty
	l.ability = ability
	return l

func test_speedup_for_chief_scientist_pretrain() -> void:
	var l := _new_lead(&"chief_scientist", 100.0)
	# 1 + 1.0 * 0.22 = 1.22
	assert_almost_eq(HiringSystem.lead_speedup_for(l, &"pretrain"), 1.22, 0.001)

func test_speedup_for_chief_scientist_posttrain() -> void:
	var l := _new_lead(&"chief_scientist", 50.0)
	# 1 + 0.5 * 0.11 = 1.055
	assert_almost_eq(HiringSystem.lead_speedup_for(l, &"posttrain"), 1.055, 0.001)

func test_speedup_for_ml_research_lead_posttrain() -> void:
	var l := _new_lead(&"ml_research_lead", 80.0)
	# 1 + 0.8 * 0.28 = 1.224
	assert_almost_eq(HiringSystem.lead_speedup_for(l, &"posttrain"), 1.224, 0.001)

func test_speedup_for_eval_lead_evaluate() -> void:
	var l := _new_lead(&"eval_lead", 75.0)
	# 1 + 0.75 * 0.33 = 1.2475
	assert_almost_eq(HiringSystem.lead_speedup_for(l, &"evaluate"), 1.2475, 0.001)

func test_speedup_for_data_scientist_data_collection() -> void:
	var l := _new_lead(&"data_scientist", 60.0)
	# 1 + 0.6 * 0.44 = 1.264
	assert_almost_eq(HiringSystem.lead_speedup_for(l, &"data_collection"), 1.264, 0.001)

func test_speedup_for_specialty_mismatch_returns_one() -> void:
	# marketing_lead has no task-speed bonus on pretrain.
	var l := _new_lead(&"marketing_lead", 100.0)
	assert_almost_eq(HiringSystem.lead_speedup_for(l, &"pretrain"), 1.0, 0.001)

func test_speedup_for_unknown_subtype_returns_one() -> void:
	var l := _new_lead(&"chief_scientist", 100.0)
	assert_almost_eq(HiringSystem.lead_speedup_for(l, &"nonsense"), 1.0, 0.001)

func test_speedup_for_tech_research_chief_scientist() -> void:
	# Per design/招聘系统设计.md §1.1 (2026-05 rev): chief_scientist now
	# carries the Research-quadrant `research_speed` bonus (coef 0.55).
	# 1 + 1.0 * 0.55 = 1.55 → tech_research duration ÷ 1.55 ≈ -35%.
	var l := _new_lead(&"chief_scientist", 100.0)
	assert_almost_eq(HiringSystem.lead_speedup_for(l, &"tech_research"), 1.55, 0.001)

func test_speedup_for_tech_research_other_specialty_returns_one() -> void:
	# Specialties without `research_speed` (e.g. data_scientist) still return 1.0.
	var l := _new_lead(&"data_scientist", 100.0)
	assert_almost_eq(HiringSystem.lead_speedup_for(l, &"tech_research"), 1.0, 0.001)

func test_speedup_for_null_lead_returns_one() -> void:
	assert_almost_eq(HiringSystem.lead_speedup_for(null, &"pretrain"), 1.0, 0.001)

# ---- player scientist ---------------------------------------------------

func test_create_player_scientist_returns_lead_id() -> void:
	# Per design/招聘系统设计.md §2: creates a free lead representing the
	# player (founder-as-scientist). Joins GameState.leads directly with
	# zero salary, zero signing fee, zero equity grant, is_player_scientist=true.
	var before_cash: int = GameState.cash
	var r: Dictionary = CommandBus.send(&"hiring.create_player_scientist",
			{specialty = &"chief_scientist", display_name = "Founder"})
	assert_true(r.ok)
	assert_true(GameState.leads.size() > 0)
	# Founder is free.
	assert_eq(GameState.cash, before_cash)
	var l = HiringSystem.find_lead(StringName(r.lead_id))
	assert_not_null(l)
	assert_true(l.is_player_scientist)
	assert_eq(l.weekly_salary, 0)
	assert_eq(l.signing_fee, 0)
	assert_eq(l.level, &"founder")

func test_create_player_scientist_adopts_gamestate_founder_avatar() -> void:
	# 出身系统设计 §3: 新游戏选的头像写在 GameState.founder_avatar,
	# 创建「玩家自己」这位 lead 时拷到 Lead.avatar_id。
	GameState.founder_avatar = &"avatar-07"
	var r: Dictionary = CommandBus.send(&"hiring.create_player_scientist",
			{specialty = &"chief_scientist"})
	var l = HiringSystem.find_lead(StringName(r.lead_id))
	assert_eq(l.avatar_id, &"avatar-07")

func test_create_player_scientist_explicit_avatar_id_param_wins() -> void:
	GameState.founder_avatar = &"avatar-01"
	var r: Dictionary = CommandBus.send(&"hiring.create_player_scientist",
			{specialty = &"chief_scientist", avatar_id = &"avatar-09"})
	var l = HiringSystem.find_lead(StringName(r.lead_id))
	assert_eq(l.avatar_id, &"avatar-09")

func test_create_player_scientist_emits_signal() -> void:
	watch_signals(EventBus)
	CommandBus.send(&"hiring.create_player_scientist", {specialty = &"chief_scientist"})
	assert_signal_emitted(EventBus, "player_scientist_created")

func test_create_player_scientist_only_once() -> void:
	CommandBus.send(&"hiring.create_player_scientist", {specialty = &"chief_scientist"})
	var r: Dictionary = CommandBus.send(&"hiring.create_player_scientist",
			{specialty = &"ml_research_lead"})
	assert_false(r.ok)
	assert_eq(r.error, &"already_created")

func test_create_player_scientist_unknown_specialty_rejected() -> void:
	var r: Dictionary = CommandBus.send(&"hiring.create_player_scientist",
			{specialty = &"nonsense"})
	assert_false(r.ok)
	assert_eq(r.error, &"unknown_specialty")

func test_fire_player_scientist_rejected() -> void:
	# Founder cannot be fired (per design §2 约定).
	var r: Dictionary = CommandBus.send(&"hiring.create_player_scientist",
			{specialty = &"chief_scientist"})
	assert_true(r.ok)
	var fire: Dictionary = CommandBus.send(&"hiring.fire_lead", {lead_id = StringName(r.lead_id)})
	assert_false(fire.ok)
	assert_eq(fire.error, &"player_scientist_unfireable")

func test_player_scientist_excluded_from_salaries() -> void:
	CommandBus.send(&"hiring.create_player_scientist", {specialty = &"chief_scientist"})
	var before: int = GameState.cash
	EventBus.phase_started.emit(&"upkeep", 1)
	# Founder weekly_salary is 0, so no salary is paid for them.
	assert_eq(GameState.cash, before)

func test_player_scientist_provides_no_speedup() -> void:
	# Per 招聘系统设计 §2 (2026-05 rev): 创始人是"万能 lead", 通过任何 specialty
	# 校验但**不提供任何 bonus**。lead_speedup_for 一律返回 1.0, 无论 specialty/ability。
	var r: Dictionary = CommandBus.send(&"hiring.create_player_scientist",
			{specialty = &"chief_scientist", ability = 100.0})
	var l = HiringSystem.find_lead(StringName(r.lead_id))
	assert_almost_eq(HiringSystem.lead_speedup_for(l, &"pretrain"), 1.0, 0.001,
			"player_scientist 应不给 pretrain 加速")
	assert_almost_eq(HiringSystem.lead_speedup_for(l, &"posttrain"), 1.0, 0.001,
			"player_scientist 应不给 posttrain 加速")
	assert_almost_eq(HiringSystem.lead_speedup_for(l, &"data_collection"), 1.0, 0.001,
			"player_scientist 应不给 data_collection 加速")

func test_player_scientist_matches_any_specialty() -> void:
	# Per 招聘系统设计 §5.4 (2026-05 rev): is_player_scientist=true 在任意
	# needs_lead_specialty 校验中都应放行。
	var r: Dictionary = CommandBus.send(&"hiring.create_player_scientist", {})
	var l = HiringSystem.find_lead(StringName(r.lead_id))
	for spec in [&"chief_scientist", &"ml_research_lead", &"eval_lead",
			&"chief_engineer", &"data_scientist", &"marketing_lead"]:
		assert_true(HiringSystem.lead_matches_specialty(l, spec),
				"player_scientist 应匹配 %s" % String(spec))

func test_create_player_scientist_with_empty_specialty_uses_founder_sentinel() -> void:
	# specialty 现在是 optional, 留空 → &"founder" 占位。
	var r: Dictionary = CommandBus.send(&"hiring.create_player_scientist", {})
	assert_true(r.ok)
	var l = HiringSystem.find_lead(StringName(r.lead_id))
	assert_eq(l.specialty, &"founder")

func test_lead_bonus_coef_returns_zero_for_player_scientist() -> void:
	var r: Dictionary = CommandBus.send(&"hiring.create_player_scientist",
			{specialty = &"data_scientist", ability = 100.0})
	var l = HiringSystem.find_lead(StringName(r.lead_id))
	assert_almost_eq(HiringSystem.lead_bonus_coef(l, &"data_quality_add"), 0.0, 0.001,
			"player_scientist 即便 specialty 看起来匹配, bonus 系数也应为 0")

func test_lead_matches_specialty_handles_null_and_normal_leads() -> void:
	# null → false, 普通 lead 严格比对, player_scientist 始终 true.
	assert_false(HiringSystem.lead_matches_specialty(null, &"chief_scientist"))
	var n := Lead.new()
	n.specialty = &"chief_scientist"
	assert_true(HiringSystem.lead_matches_specialty(n, &"chief_scientist"))
	assert_false(HiringSystem.lead_matches_specialty(n, &"ml_research_lead"))
	var founder := Lead.new()
	founder.specialty = &"founder"
	founder.is_player_scientist = true
	assert_true(HiringSystem.lead_matches_specialty(founder, &"chief_scientist"))
	assert_true(HiringSystem.lead_matches_specialty(founder, &"data_scientist"))

# ---- v7 PR-F: cash probability brackets ---------------------------------
# Cash-based bracket distribution per resources/data/hiring/pool_config.tres:
#   cash >= 50_000_000:  S 0.20, A 0.40, B 0.30, C 0.10
#   cash >= 10_000_000:  S 0.05, A 0.25, B 0.45, C 0.25
#   cash >=  1_000_000:  S 0.00, A 0.10, B 0.40, C 0.50
#   cash >=          0:  S 0.00, A 0.00, B 0.30, C 0.70

func _draw_levels(cash: int, n: int, seed_value: int) -> Dictionary:
	GameState.cash = cash
	GameState.rng_seed = seed_value
	GameState._rng = null
	var counts := {&"S": 0, &"A": 0, &"B": 0, &"C": 0}
	for _i in range(n):
		var lvl: StringName = HiringSystem._draw_level(cash, 0.0)
		counts[lvl] = int(counts.get(lvl, 0)) + 1
	return counts

func test_draw_level_starting_cash_no_S() -> void:
	# starting cash 1M lands in cash >= 1M bracket: S 0%.
	var c := _draw_levels(1_000_000, 2000, 1)
	assert_eq(int(c[&"S"]), 0, "S should be impossible at starting cash: %s" % c)

func test_draw_level_starting_cash_distribution() -> void:
	# 1M ≤ cash < 10M: S 0, A 10%, B 40%, C 50%.
	var n := 4000
	var c := _draw_levels(1_000_000, n, 7)
	var fa: float = float(c[&"A"]) / n
	var fb: float = float(c[&"B"]) / n
	var fcc: float = float(c[&"C"]) / n
	assert_almost_eq(fa, 0.10, 0.04)
	assert_almost_eq(fb, 0.40, 0.05)
	assert_almost_eq(fcc, 0.50, 0.05)

func test_draw_level_mid_cash_distribution() -> void:
	# 10M ≤ cash < 50M: S 5%, A 25%, B 45%, C 25%.
	var n := 4000
	var c := _draw_levels(10_000_000, n, 13)
	assert_almost_eq(float(c[&"S"]) / n, 0.05, 0.03)
	assert_almost_eq(float(c[&"A"]) / n, 0.25, 0.05)
	assert_almost_eq(float(c[&"B"]) / n, 0.45, 0.05)
	assert_almost_eq(float(c[&"C"]) / n, 0.25, 0.05)

func test_draw_level_high_cash_distribution() -> void:
	# cash >= 50M: S 20%, A 40%, B 30%, C 10%.
	var n := 4000
	var c := _draw_levels(100_000_000, n, 21)
	assert_almost_eq(float(c[&"S"]) / n, 0.20, 0.04)
	assert_almost_eq(float(c[&"A"]) / n, 0.40, 0.05)
	assert_almost_eq(float(c[&"B"]) / n, 0.30, 0.05)
	assert_almost_eq(float(c[&"C"]) / n, 0.10, 0.04)

# ---- save_loaded: lead ID 计数器恢复 + 重复修复 (读档撞 ID 防御) ---------

func _seed_lead(id: StringName, locked: StringName = &"") -> Lead:
	var l := Lead.new()
	l.id = id
	l.specialty = &"chief_scientist"
	l.level = &"B"
	l.locked_by_task_id = locked
	return l

func test_save_loaded_restores_lead_id_counter() -> void:
	GameState.leads.append(_seed_lead(&"lead_0007"))
	EventBus.save_loaded.emit()
	var new_id := HiringSystem._gen_lead_id()
	assert_gt(String(new_id).trim_prefix("lead_").to_int(), 7,
			"读档后新发的 lead ID 不能复用 ≤0007 (实际 %s)" % new_id)

func test_save_loaded_repairs_duplicate_lead_ids() -> void:
	GameState.leads.append(_seed_lead(&"lead_0001"))
	GameState.leads.append(_seed_lead(&"lead_0001", &"stale_task"))
	EventBus.save_loaded.emit()
	var seen := {}
	for l in GameState.leads:
		assert_false(seen.has(l.id), "lead id %s 读档后仍重复" % l.id)
		seen[l.id] = true
	assert_eq(GameState.leads[1].locked_by_task_id, &"",
			"被重发 ID 的影子副本残留锁必须清掉")

# ---- 真名生成 (员工系统不出戏): 名跟随肖像 (族裔/性别一致) ----------
# 见 design/招聘系统设计.md §1.3。display_name 必须和 lead 头像的族裔/性别一致:
# 东亚脸 → 中文 "姓名"; 其余 → 拉丁 "Given Surname"。

# 校验 lead 的 display_name 与其头像 (IconRegistry.lead_demographics) 一致。
func _name_matches_portrait(l) -> bool:
	var demo: Dictionary = IconRegistry.lead_demographics(l.id)
	var region: StringName = demo.get(&"region", &"east_asian")
	var gender: StringName = demo.get(&"gender", &"female")
	var nm: String = String(l.display_name)
	if region == &"east_asian":
		return PersonName.EAST_ASIAN_SURNAMES.has(nm.substr(0, 1))
	var parts := nm.split(" ", false)
	if parts.size() != 2:
		return false
	return PersonName.surnames_for(region).has(parts[1]) \
			and PersonName.given_for(region, gender).has(parts[0])

func test_generated_lead_name_matches_portrait() -> void:
	# 名字必须是真名 (跟随头像族裔/性别), 不能是历史上的 "Lead <id>" 占位。
	# 否则员工卡 / 下拉框看起来全是 ID, 或白人的脸配中文名, 出戏。
	GameState.rng_seed = 42
	GameState._rng = null
	EventBus.phase_started.emit(&"action", 1)
	assert_gt(GameState.lead_pool.size(), 0)
	for l in GameState.lead_pool:
		assert_false(l.display_name.begins_with("Lead "),
				"lead 名字不能是 'Lead xxxx' 形式, 实际 %s" % l.display_name)
		assert_false(l.display_name == "",
				"lead 名字不能为空")
		assert_true(_name_matches_portrait(l),
				"lead 名字应与头像族裔/性别一致 (id=%s, demo=%s, name=%s)"
				% [l.id, IconRegistry.lead_demographics(l.id), l.display_name])

func test_legacy_lead_names_renamed_on_save_loaded() -> void:
	# 老存档 / 老会话: 已签约 lead 的 display_name 还是 "Lead 0001" 这种 ID 占位。
	# save_loaded 后必须自动重命名, 否则玩家看不到中文真名。
	var l1 := Lead.new()
	l1.id = &"lead_0007"
	l1.display_name = "Lead 0007"
	l1.specialty = &"chief_scientist"
	l1.level = &"B"
	GameState.leads.append(l1)
	var l2 := Lead.new()
	l2.id = &"lead_0008"
	l2.display_name = ""  # 空名字也是 legacy
	l2.specialty = &"data_scientist"
	l2.level = &"C"
	GameState.leads.append(l2)
	EventBus.save_loaded.emit()
	assert_false(GameState.leads[0].display_name == "Lead 0007",
			"legacy 名字 'Lead 0007' 必须被替换")
	assert_false(GameState.leads[0].display_name.is_empty(),
			"重命名后不能为空")
	assert_false(GameState.leads[1].display_name.is_empty(),
			"空 display_name 也要补成真名")
	# 验证是真名且跟随头像族裔/性别。
	for l in GameState.leads:
		assert_true(_name_matches_portrait(l),
				"重命名后 lead 名字应与头像一致 (id=%s, demo=%s, name=%s)"
				% [l.id, IconRegistry.lead_demographics(l.id), l.display_name])

func test_legacy_lead_names_renamed_on_action_phase() -> void:
	# 没 save+load 的活会话 (玩家正在玩): 推一回合也要触发 migration, 旧 lead
	# 1 周内自动拿到名字。
	var l := Lead.new()
	l.id = &"lead_legacy"
	l.display_name = "Lead 9999"
	l.specialty = &"chief_engineer"
	l.level = &"A"
	GameState.leads.append(l)
	EventBus.phase_started.emit(&"action", 1)
	assert_false(GameState.leads[0].display_name == "Lead 9999",
			"action phase 推进时, legacy 名字应被替换")

func test_player_scientist_name_preserved_during_migration() -> void:
	# Founder 名字是玩家自己定的, migration 不能覆盖。
	CommandBus.send(&"hiring.create_player_scientist",
			{display_name = "马斯克"})
	EventBus.save_loaded.emit()
	var founder = GameState.leads[0]
	assert_true(founder.is_player_scientist)
	assert_eq(founder.display_name, "马斯克",
			"founder 自定义名字必须保留, 不能被 migration 改成中文随机名")

func test_chinese_lead_name_not_re_migrated() -> void:
	# 幂等: 已是中文真名的 lead 不会被 migration 再换一次。
	var l := Lead.new()
	l.id = &"lead_already_named"
	l.display_name = "张三"
	l.specialty = &"chief_scientist"
	l.level = &"B"
	GameState.leads.append(l)
	EventBus.save_loaded.emit()
	assert_eq(GameState.leads[0].display_name, "张三",
			"中文真名不应被 migration 修改")

func test_generated_lead_name_deterministic_under_same_seed() -> void:
	# 名字 = f(lead.id 的肖像族裔/性别, rng)。同 seed + 同 id 序列 → 同名 →
	# 存读档名字不会换 (display_name 已持久化, 不重算)、测试可重现。
	# _next_lead_seq 是会话计数器, GameState.reset 不归零, 故测试里显式对齐两次运行的 id 序列。
	HiringSystem._next_lead_seq = 1
	GameState.rng_seed = 100
	GameState._rng = null
	EventBus.phase_started.emit(&"action", 1)
	var first_run: Array = []
	for l in GameState.lead_pool:
		first_run.append(l.display_name)

	GameState.reset()
	HiringSystem._next_lead_seq = 1
	GameState.rng_seed = 100
	GameState._rng = null
	EventBus.phase_started.emit(&"action", 1)
	var second_run: Array = []
	for l in GameState.lead_pool:
		second_run.append(l.display_name)

	assert_eq(first_run, second_run, "同 seed + 同 id 序列下名字必须重现")
