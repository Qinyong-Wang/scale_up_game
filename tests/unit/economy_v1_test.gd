extends GutTest

## EconomySystem v1 — loans, funding, bankruptcy (extends v0 spend/award).
## Per design/经济系统设计.md.

func before_each() -> void:
	GameState.reset()

# ---- loans --------------------------------------------------------------

func test_take_loan_zero_amount_returns_error() -> void:
	var r: Dictionary = CommandBus.send(&"economy.take_loan", {amount = 0, term_weeks = 12})
	assert_false(r.ok)

func test_take_loan_credits_cash_and_records_loan() -> void:
	var before: int = GameState.cash
	var r: Dictionary = CommandBus.send(&"economy.take_loan", {amount = 100000, term_weeks = 12})
	assert_true(r.ok)
	assert_eq(GameState.cash, before + 100000)
	assert_eq(GameState.loans.size(), 1)
	assert_eq(GameState.debt, 100000)

func test_repay_unknown_loan_returns_error() -> void:
	var r: Dictionary = CommandBus.send(&"economy.repay_loan", {
		loan_id = &"nope", amount = 1000})
	assert_false(r.ok)
	assert_eq(r.error, &"unknown_loan")

func test_repay_partial_decreases_debt() -> void:
	var t: Dictionary = CommandBus.send(&"economy.take_loan", {amount = 100000, term_weeks = 12})
	CommandBus.send(&"economy.repay_loan", {loan_id = t.loan_id, amount = 30000})
	assert_eq(GameState.debt, 70000)

func test_take_loan_above_credit_limit_rejected() -> void:
	# fame = 0 cash = STARTING (1m) so max_loan = 5_000_000
	var r: Dictionary = CommandBus.send(&"economy.take_loan", {
		amount = 100_000_000, term_weeks = 12})
	assert_false(r.ok)
	assert_eq(r.error, &"credit_limit_exceeded")

func test_upkeep_charges_interest_and_principal() -> void:
	CommandBus.send(&"economy.take_loan", {amount = 120000, term_weeks = 12})
	var before: int = GameState.cash
	EventBus.phase_started.emit(&"upkeep", 1)
	# principal_due = 120000/12 = 10000. interest at base rate ≤ 1.5%.
	assert_gt(before - GameState.cash, 9000)

# ---- funding (player-initiated, sequential 8 rounds; see 经济系统设计 §4.6)

func test_pre_seed_credits_cash_and_dilutes() -> void:
	var before: int = GameState.cash
	var r: Dictionary = CommandBus.send(&"economy.start_funding_round", {round = &"pre_seed"})
	assert_true(r.ok)
	assert_lt(float(GameState.equity.founder), 1.0)
	assert_eq(GameState.cash, before + int(r.amount))

func test_preview_credit_returns_max_and_rate() -> void:
	var r: Dictionary = CommandBus.send(&"economy.preview_credit", {})
	assert_true(r.ok)
	assert_gt(int(r.max_loan), 0)

# ---- bankruptcy ---------------------------------------------------------

func test_resolve_phase_clears_streak_when_cash_positive() -> void:
	GameState.bankruptcy_streak = 5
	EventBus.phase_started.emit(&"resolve", 1)
	assert_eq(GameState.bankruptcy_streak, 0)

func test_resolve_phase_increments_streak_when_cash_negative() -> void:
	GameState.cash = -1
	EventBus.phase_started.emit(&"resolve", 1)
	assert_eq(GameState.bankruptcy_streak, 1)
