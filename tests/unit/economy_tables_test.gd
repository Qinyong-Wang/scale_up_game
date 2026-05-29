extends GutTest

## EconomySystem table-driven loading.
## Per design/经济系统设计.md §7 + design/平衡参数.md §EconomySystem:
## tunables live in resources/data/economy/tuning.tres and
## funding_rounds/*.tres; EconomySystem assembles them at _ready and
## exposes them on the autoload instance.


# ---- resource files load --------------------------------------------------

func test_economy_tuning_tres_loads() -> void:
	var r := load("res://resources/data/economy/tuning.tres")
	assert_true(r is EconomyTuning, "tuning.tres did not load as EconomyTuning")

func test_funding_round_tres_files_load() -> void:
	for rid in [&"pre_seed", &"seed", &"a", &"b", &"c", &"d", &"e", &"f"]:
		var path := "res://resources/data/economy/funding_rounds/%s.tres" % String(rid)
		var r := load(path)
		assert_true(r is FundingRoundSpec, "%s did not load as FundingRoundSpec" % path)

# ---- table values match balance doc --------------------------------------

func test_economy_tuning_values_match_balance_doc() -> void:
	var t: EconomyTuning = load("res://resources/data/economy/tuning.tres")
	assert_eq(int(t.starting_cash), 80_000)
	assert_eq(int(t.bankruptcy_streak_limit), 12)
	assert_eq(int(t.bankruptcy_depth_floor), -1_000_000)
	assert_almost_eq(float(t.bankruptcy_depth_k), 3.0, 0.001)
	assert_almost_eq(float(t.bankruptcy_depth_l), 0.5, 0.001)
	assert_almost_eq(float(t.base_interest_rate), 0.002, 0.0001)
	assert_almost_eq(float(t.max_loan_beta), 2.0, 0.001)
	assert_almost_eq(float(t.max_loan_gamma), 3.0, 0.001)
	assert_eq(int(t.max_loan_term_weeks), 156)
	assert_eq(int(t.loan_id_start_year), 2026)
	assert_eq(int(t.valuation_base), 500_000)
	assert_almost_eq(float(t.valuation_multiplier), 2.0, 0.001)
	assert_almost_eq(float(t.valuation_cash_coef), 0.3, 0.001)
	assert_almost_eq(float(t.portfolio_bonus_per_model), 0.05, 0.001)
	assert_almost_eq(float(t.founder_min_stake), 0.5, 0.001)
	assert_eq(int(t.burn_window_weeks), 3)
	assert_eq(int(t.revenue_window_weeks), 12)

func test_funding_round_pre_seed_values() -> void:
	var r: FundingRoundSpec = load("res://resources/data/economy/funding_rounds/pre_seed.tres")
	assert_eq(r.id, &"pre_seed")
	# pre_seed 是开局可接的小额轮: 数值见 design/经济系统设计.md §4.6.
	assert_gt(int(r.amount_min), 0)
	assert_gt(int(r.amount_max), int(r.amount_min))
	assert_true(r.display_name != "")
	assert_true(r.unlock_summary != "")

func test_funding_round_f_values() -> void:
	var r: FundingRoundSpec = load("res://resources/data/economy/funding_rounds/f.tres")
	assert_eq(r.id, &"f")
	# F 轮: 后期巨额, 应该是 8 轮中最大金额.
	assert_gt(int(r.amount_min), 1_000_000_000)
	assert_almost_eq(float(r.dilution_min), 0.22, 0.001)
	assert_almost_eq(float(r.dilution_max), 0.30, 0.001)

# ---- runtime caches populated from tables --------------------------------

func test_runtime_bankruptcy_streak_limit_from_table() -> void:
	assert_eq(int(EconomySystem.BANKRUPTCY_STREAK_LIMIT), 12)

func test_runtime_base_interest_rate_from_table() -> void:
	assert_almost_eq(float(EconomySystem.BASE_INTEREST_RATE), 0.002, 0.0001)

func test_runtime_max_loan_term_from_table() -> void:
	assert_eq(int(EconomySystem.MAX_LOAN_TERM_WEEKS), 156)

func test_credit_rate_endpoints_match_design() -> void:
	# §4.3 v9.2: max 0.5%/周 (D=2.5×), min 0.05%/周 (S=0.25×).
	# 直接通过场景化 GameState 走 _rating + _current_rate 校验端点.
	GameState.reset()
	GameState.quarterly_revenue = 30_000_000
	GameState.debt = 0  # ratio < 0.5 → S
	var s: Dictionary = CommandBus.send(&"economy.preview_credit", {})
	assert_eq(s.rating, &"S")
	assert_almost_eq(float(s.rate), 0.0005, 1e-6, "S 档应为 0.05%%/周")
	# D: 设置一个高 debt/revenue, 强制走 D.
	GameState.quarterly_revenue = 1_000_000
	GameState.debt = 10_000_000  # ratio 10 → D
	var d: Dictionary = CommandBus.send(&"economy.preview_credit", {})
	assert_eq(d.rating, &"D")
	assert_almost_eq(float(d.rate), 0.005, 1e-6, "D 档应为 0.5%%/周")

func test_credit_rate_c_rating_is_025_percent_weekly() -> void:
	GameState.reset()
	GameState.quarterly_revenue = 0
	GameState.debt = 0
	var c: Dictionary = CommandBus.send(&"economy.preview_credit", {})
	assert_eq(c.rating, &"C")
	assert_almost_eq(float(c.rate), 0.0025, 1e-6, "C 档应为 0.25%%/周")

func test_runtime_funding_round_table_populated() -> void:
	var t: Dictionary = EconomySystem.FUNDING_ROUND_TABLE
	for rid in [&"pre_seed", &"seed", &"a", &"b", &"c", &"d", &"e", &"f"]:
		assert_true(t.has(rid), "FUNDING_ROUND_TABLE missing %s" % rid)
	# pre_seed 最小, F 最大 — 验证 8 轮规模递增是合理的.
	assert_lt(int(t[&"pre_seed"].amax), int(t[&"f"].amin),
			"pre_seed max should be far below F round min")

func test_game_state_starting_cash_from_table() -> void:
	assert_eq(int(GameState.STARTING_CASH), 80_000)
