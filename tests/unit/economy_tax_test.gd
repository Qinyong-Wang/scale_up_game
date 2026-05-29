extends GutTest

## EconomySystem 周度税务结算 (_settle_taxes).
## Per design/经济系统设计.md §4.9.
## 税基 = 当周经营性净利润 (融资 / 债务本金排除, 利息可抵); 亏损结转;
## 两档: 企业所得税 25% (免征 100w) + AI 税 20% (门槛 1B)。

const CORP := "ECO_CAT_CORP_TAX"
const AI := "ECO_CAT_AI_UBI_TAX"

func before_each() -> void:
	GameState.reset()

# ---- helpers --------------------------------------------------------------

func _last_history_expense(cat: String) -> int:
	var h: Array = GameState.ledger_history
	if h.is_empty():
		return 0
	return int((h[0].expense as Dictionary).get(cat, 0))

func _resolve(turn: int) -> void:
	GameState.turn = turn
	EventBus.phase_started.emit(&"resolve", turn)

# ---- 免征额 ---------------------------------------------------------------

func test_no_tax_at_or_below_exemption() -> void:
	# 利润 50w ≤ 100w 免征额 → 不交税。
	CommandBus.send(&"economy.award", {amount = 500_000, reason = &"monetization"})
	_resolve(1)
	assert_eq(_last_history_expense(CORP), 0, "profit below exemption pays no corp tax")
	assert_eq(_last_history_expense(AI), 0)

func test_corp_tax_on_profit_above_exemption() -> void:
	# 利润 300w → (300w − 100w) × 25% = 50w。
	CommandBus.send(&"economy.award", {amount = 3_000_000, reason = &"monetization"})
	_resolve(1)
	assert_eq(_last_history_expense(CORP), 500_000)
	assert_eq(_last_history_expense(AI), 0, "below 1B → no AI tax")

func test_tax_base_is_income_minus_expense() -> void:
	# 营收 500w − 工资 100w = 利润 400w → (400w − 100w) × 25% = 75w。
	CommandBus.send(&"economy.award", {amount = 5_000_000, reason = &"monetization"})
	CommandBus.send(&"economy.spend", {cost = {&"cash": 1_000_000}, reason = &"salaries"})
	_resolve(1)
	assert_eq(_last_history_expense(CORP), 750_000)

# ---- 融资 / 债务排除 ------------------------------------------------------

func test_funding_round_excluded_from_tax_base() -> void:
	# 融资 1000w 不是利润 → 完全不计税。
	var before: int = GameState.cash
	CommandBus.send(&"economy.award", {amount = 10_000_000, reason = &"funding_round"})
	_resolve(1)
	assert_eq(_last_history_expense(CORP), 0, "funding is not taxable income")
	assert_eq(_last_history_expense(AI), 0)
	assert_eq(GameState.cash, before + 10_000_000, "no tax deducted from a funding inflow")

func test_loan_proceeds_excluded_from_tax_base() -> void:
	# 贷款进账 1000w 是负债不是利润 → 不计税。
	CommandBus.send(&"economy.award", {amount = 10_000_000, reason = &"loan_taken"})
	_resolve(1)
	assert_eq(_last_history_expense(CORP), 0, "loan proceeds are not taxable income")

func test_loan_principal_not_deductible() -> void:
	# 营收 500w, 还本金 200w (不可抵) → 税基仍是 500w → (500w − 100w) × 25% = 100w。
	CommandBus.send(&"economy.award", {amount = 5_000_000, reason = &"monetization"})
	CommandBus.send(&"economy.spend", {cost = {&"cash": 2_000_000}, reason = &"loan_payment_principal"})
	_resolve(1)
	assert_eq(_last_history_expense(CORP), 1_000_000,
			"principal repayment must NOT reduce the tax base")

func test_loan_interest_is_deductible() -> void:
	# 营收 500w, 利息 200w (可抵) → 税基 300w → (300w − 100w) × 25% = 50w。
	CommandBus.send(&"economy.award", {amount = 5_000_000, reason = &"monetization"})
	CommandBus.send(&"economy.spend", {cost = {&"cash": 2_000_000}, reason = &"loan_payment_interest"})
	_resolve(1)
	assert_eq(_last_history_expense(CORP), 500_000,
			"loan interest IS a deductible expense")

# ---- AI 税 (UBI) ----------------------------------------------------------

func test_ai_tax_above_1b_threshold() -> void:
	# 利润 20 亿 → corp = (2e9 − 1e6) × 25% = 499_750_000; ai = (2e9 − 1e9) × 20% = 2e8。
	CommandBus.send(&"economy.award", {amount = 2_000_000_000, reason = &"monetization"})
	_resolve(1)
	assert_eq(_last_history_expense(CORP), 499_750_000)
	assert_eq(_last_history_expense(AI), 200_000_000)

func test_no_ai_tax_just_below_threshold() -> void:
	# 利润 5 亿 < 1B → 只有企业税。
	CommandBus.send(&"economy.award", {amount = 500_000_000, reason = &"monetization"})
	_resolve(1)
	assert_eq(_last_history_expense(CORP), 124_750_000)
	assert_eq(_last_history_expense(AI), 0)

# ---- 亏损 / 结转 ----------------------------------------------------------

func test_no_tax_on_loss_week() -> void:
	CommandBus.send(&"economy.spend", {cost = {&"cash": 2_000_000}, reason = &"salaries"})
	_resolve(1)
	assert_eq(_last_history_expense(CORP), 0, "a loss week pays no tax")
	assert_eq(GameState.tax_loss_carryforward, 2_000_000, "loss accrues to carryforward pool")

func test_loss_carryforward_offsets_future_profit() -> void:
	# 第 1 周亏 200w → 池 = 200w。
	CommandBus.send(&"economy.spend", {cost = {&"cash": 2_000_000}, reason = &"salaries"})
	_resolve(1)
	assert_eq(GameState.tax_loss_carryforward, 2_000_000)
	# 第 2 周赚 500w → 先抵 200w → 应税 300w → (300w − 100w) × 25% = 50w。
	CommandBus.send(&"economy.award", {amount = 5_000_000, reason = &"monetization"})
	_resolve(2)
	assert_eq(_last_history_expense(CORP), 500_000,
			"corp tax on (5M − 2M carryforward − 1M exemption) × 25%")
	assert_eq(GameState.tax_loss_carryforward, 0, "carryforward fully consumed")

func test_partial_carryforward_remainder_kept() -> void:
	# 亏 200w, 次周赚 150w → 全被抵, 不交税, 池剩 50w。
	CommandBus.send(&"economy.spend", {cost = {&"cash": 2_000_000}, reason = &"salaries"})
	_resolve(1)
	CommandBus.send(&"economy.award", {amount = 1_500_000, reason = &"monetization"})
	_resolve(2)
	assert_eq(_last_history_expense(CORP), 0, "offset profit fully → no tax")
	assert_eq(GameState.tax_loss_carryforward, 500_000, "unused loss stays in the pool")

# ---- 落账 / 信号 ----------------------------------------------------------

func test_tax_recorded_before_roll_and_reflected_in_net() -> void:
	CommandBus.send(&"economy.award", {amount = 3_000_000, reason = &"monetization"})
	_resolve(1)
	var entry: Dictionary = GameState.ledger_history[0]
	assert_eq(int(entry.gross_in), 3_000_000, "income unchanged")
	assert_eq(int(entry.gross_out), 500_000, "tax shows as expense in the same week")
	assert_eq(int(entry.gross_in) - int(entry.gross_out), 2_500_000, "net is after-tax")

func test_tax_emits_cash_changed_with_reason() -> void:
	watch_signals(EventBus)
	CommandBus.send(&"economy.award", {amount = 3_000_000, reason = &"monetization"})
	_resolve(1)
	assert_signal_emitted_with_parameters(EventBus, "cash_changed", [-500_000, &"corporate_tax"])

func test_tax_reduces_cash() -> void:
	CommandBus.send(&"economy.award", {amount = 3_000_000, reason = &"monetization"})
	var before: int = GameState.cash
	_resolve(1)
	assert_eq(GameState.cash, before - 500_000, "cash drops by the settled tax")
