extends GutTest

## HiringSystem table-driven loading.
## Per design/招聘系统设计.md §7 + design/平衡参数.md §HiringSystem:
## the authoritative numeric source is resources/data/hiring/*.tres.
## HiringSystem populates its runtime caches (LEAD_BONUS_TABLE,
## SALARY_PER_ROLE, LEAD_POOL_BASE_SIZE, fame brackets, lead level
## defaults) from those tables at _ready.


# ---- resource files load --------------------------------------------------

func test_lead_level_tres_files_load() -> void:
	for level in [&"s", &"a", &"b", &"c"]:
		var path := "res://resources/data/hiring/lead_levels/%s.tres" % String(level)
		var r := load(path)
		assert_true(r is LeadLevelSpec, "%s did not load as LeadLevelSpec" % path)

func test_staff_salary_tres_files_load() -> void:
	for role in [&"ml_eng", &"infra_eng", &"data_eng", &"marketing", &"ops"]:
		var path := "res://resources/data/hiring/staff_salaries/%s.tres" % String(role)
		var r := load(path)
		assert_true(r is StaffRoleSpec, "%s did not load as StaffRoleSpec" % path)

func test_lead_bonus_tres_files_load() -> void:
	for sp in [
		&"chief_scientist", &"ml_research_lead", &"eval_lead",
		&"chief_engineer", &"data_scientist", &"marketing_lead",
	]:
		var path := "res://resources/data/hiring/lead_bonus/%s.tres" % String(sp)
		var r := load(path)
		assert_true(r is LeadBonusSpec, "%s did not load as LeadBonusSpec" % path)

func test_lead_pool_config_loads() -> void:
	var r := load("res://resources/data/hiring/pool_config.tres")
	assert_true(r is LeadPoolConfig, "pool_config.tres did not load as LeadPoolConfig")

# ---- table values match balance doc --------------------------------------

func test_lead_level_s_values() -> void:
	# Per design/平衡参数.md §HiringSystem (2026-05 rev):
	# S-tier ≈ 12M¥/year → 230_770 ¥/week, ability 92.
	var s: LeadLevelSpec = load("res://resources/data/hiring/lead_levels/s.tres")
	assert_eq(s.id, &"S")
	assert_almost_eq(s.ability, 92.0, 0.001)
	assert_eq(s.signing_fee, 5_000_000)
	assert_eq(s.weekly_salary, 230_770)

func test_lead_level_c_values() -> void:
	# C-tier ≈ 1M¥/year → 19_230 ¥/week, ability 40.
	var c: LeadLevelSpec = load("res://resources/data/hiring/lead_levels/c.tres")
	assert_eq(c.id, &"C")
	assert_almost_eq(c.ability, 40.0, 0.001)
	assert_eq(c.signing_fee, 50_000)
	assert_eq(c.weekly_salary, 19_230)

func test_staff_salary_ml_eng() -> void:
	# ml_eng: 350k¥/year = 6_730 ¥/week.
	var r: StaffRoleSpec = load("res://resources/data/hiring/staff_salaries/ml_eng.tres")
	assert_eq(r.id, &"ml_eng")
	assert_eq(r.weekly_salary, 6_730)

# ---- HiringSystem runtime caches come from tables ------------------------

func test_runtime_salary_per_role_populated_from_tables() -> void:
	# Per design/招聘系统设计.md §7 + 平衡参数.md §HiringSystem (2026-05 rev):
	# SALARY_PER_ROLE is built from resources/data/hiring/staff_salaries/*.tres
	# at HiringSystem._ready. Values are ¥/week (1 turn = 1 week).
	# Calibration: ml_eng 350k/year, infra_eng 300k/year, etc.
	var t: Dictionary = HiringSystem.SALARY_PER_ROLE
	assert_eq(int(t[&"ml_eng"]), 6_730)
	assert_eq(int(t[&"infra_eng"]), 5_770)
	assert_eq(int(t[&"data_eng"]), 4_810)
	assert_eq(int(t[&"marketing"]), 2_880)
	assert_eq(int(t[&"ops"]), 1_920)

func test_runtime_lead_pool_base_size_from_table() -> void:
	assert_eq(HiringSystem.LEAD_POOL_BASE_SIZE, 6)

func test_runtime_lead_bonus_table_chief_scientist_from_tres() -> void:
	# 2026-05: chief_scientist now also carries pretrain_score_bonus and
	# research_speed (the Research-quadrant bonus, per design §1.1).
	var t: Dictionary = HiringSystem.LEAD_BONUS_TABLE
	assert_almost_eq(float(t[&"chief_scientist"][&"pretrain_speed"]), 0.22, 0.001)
	assert_almost_eq(float(t[&"chief_scientist"][&"pretrain_score_bonus"]), 0.06, 0.001)
	assert_almost_eq(float(t[&"chief_scientist"][&"posttrain_speed"]), 0.11, 0.001)
	assert_almost_eq(float(t[&"chief_scientist"][&"research_speed"]), 0.55, 0.001)

func test_gen_lead_uses_table_defaults_for_S() -> void:
	# _gen_lead reads ability / signing_fee / weekly_salary
	# from resources/data/hiring/lead_levels/s.tres.
	var lead = HiringSystem._gen_lead(&"S", &"chief_scientist")
	assert_almost_eq(float(lead.ability), 92.0, 0.001)
	assert_eq(int(lead.signing_fee), 5_000_000)
	assert_eq(int(lead.weekly_salary), 230_770)
