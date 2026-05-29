extends GutTest

## 端到端: 税务通过真实回合机器 (TurnManager.advance → upkeep/action/resolve)
## 正确在 resolve 阶段结算。Per design/经济系统设计.md §4.9。
## 注: 空公司推进时工资/基建/营收均为 0, 注入的 award/spend 是唯一账目。

const CORP := "ECO_CAT_CORP_TAX"
const AI := "ECO_CAT_AI_UBI_TAX"

func before_each() -> void:
	GameState.reset()

func _last() -> Dictionary:
	return GameState.ledger_history[0]

func _expense(cat: String) -> int:
	return int((_last().expense as Dictionary).get(cat, 0))

# 注入本周收支后推进一周; advance() 在 resolve 结税并滚动账本。
func _award(amount: int, reason: StringName) -> void:
	CommandBus.send(&"economy.award", {amount = amount, reason = reason})

func _spend(amount: int, reason: StringName) -> void:
	CommandBus.send(&"economy.spend", {cost = {&"cash": amount}, reason = reason})

func test_profitable_week_settles_corp_tax_through_advance() -> void:
	var cash0: int = GameState.cash
	_award(3_000_000, &"monetization")
	TurnManager.advance()
	# (300w − 100w) × 25% = 50w，在真实 resolve 阶段扣掉。
	assert_eq(_expense(CORP), 500_000)
	assert_eq(GameState.cash, cash0 + 3_000_000 - 500_000, "税后现金")
	var e: Dictionary = _last()
	assert_eq(int(e.gross_in) - int(e.gross_out), 2_500_000, "账本净额为税后")

func test_below_exemption_week_pays_no_tax() -> void:
	_award(800_000, &"monetization")
	TurnManager.advance()
	assert_eq(_expense(CORP), 0)
	assert_eq(_expense(AI), 0)

func test_funding_round_week_is_not_taxed_through_advance() -> void:
	var cash0: int = GameState.cash
	_award(50_000_000, &"funding_round")
	TurnManager.advance()
	assert_eq(_expense(CORP), 0, "融资不是利润, 不计税")
	assert_eq(GameState.cash, cash0 + 50_000_000)

func test_capex_loss_carries_forward_across_advances() -> void:
	# 第 1 周: 营收 100w − GPU 400w = 亏 300w → 不交税, 结转池 +300w。
	_award(1_000_000, &"monetization")
	_spend(4_000_000, &"gpu_purchase")
	TurnManager.advance()
	assert_eq(_expense(CORP), 0, "亏损周不交税")
	assert_eq(GameState.tax_loss_carryforward, 3_000_000)
	# 第 2 周: 营收 600w → 抵 300w → 应税 300w → 企业税 50w。
	_award(6_000_000, &"monetization")
	TurnManager.advance()
	assert_eq(_expense(CORP), 500_000, "(600w − 300w 结转 − 100w 免征) × 25%")
	assert_eq(GameState.tax_loss_carryforward, 0)

func test_billion_dollar_week_triggers_ai_tax_through_advance() -> void:
	_award(2_000_000_000, &"monetization")
	TurnManager.advance()
	assert_eq(_expense(CORP), 499_750_000, "(2e9 − 1e6) × 25%")
	assert_eq(_expense(AI), 200_000_000, "(2e9 − 1e9) × 20%")
