extends GutTest

## EconomySystem 周度账本 (weekly_ledger + ledger_history).
## Per design/经济系统设计.md §4.8.

func before_each() -> void:
	GameState.reset()

# ---- 当周累计 -------------------------------------------------------------

func test_spend_records_to_expense_under_category() -> void:
	CommandBus.send(&"economy.spend",
			{cost = {&"cash": 500}, reason = &"salaries"})
	var ledger: Dictionary = GameState.weekly_ledger
	assert_true(ledger.has(&"expense"))
	# 工资 类目下应累计 500.
	assert_eq(int(ledger.expense.get("ECO_CAT_SALARIES", 0)), 500)
	assert_eq(int(ledger.gross_out), 500)

func test_award_records_to_income_under_category() -> void:
	CommandBus.send(&"economy.award",
			{amount = 1000, reason = &"monetization"})
	var ledger: Dictionary = GameState.weekly_ledger
	assert_eq(int(ledger.income.get("ECO_CAT_REVENUE", 0)), 1000)
	assert_eq(int(ledger.gross_in), 1000)

func test_event_prefix_reason_maps_to_event_category() -> void:
	# `event:<id>` reasons all bucket into 「事件」.
	CommandBus.send(&"economy.spend",
			{cost = {&"cash": 200}, reason = &"event:abc"})
	CommandBus.send(&"economy.award",
			{amount = 300, reason = &"event:xyz"})
	var ledger: Dictionary = GameState.weekly_ledger
	assert_eq(int(ledger.expense.get("ECO_CAT_EVENT", 0)), 200)
	assert_eq(int(ledger.income.get("ECO_CAT_EVENT", 0)), 300)

func test_campaign_prefix_reason_maps_to_marketing_category() -> void:
	CommandBus.send(&"economy.spend",
			{cost = {&"cash": 4000}, reason = &"campaign:c1"})
	var ledger: Dictionary = GameState.weekly_ledger
	assert_eq(int(ledger.expense.get("ECO_CAT_CAMPAIGN", 0)), 4000)

func test_unknown_reason_maps_to_other_bucket() -> void:
	CommandBus.send(&"economy.spend",
			{cost = {&"cash": 75}, reason = &"some_unknown_thing"})
	var ledger: Dictionary = GameState.weekly_ledger
	assert_eq(int(ledger.expense.get("ECO_CAT_OTHER_EXPENSE", 0)), 75)

func test_category_keys_are_translatable() -> void:
	# 账本分类值是 strings.csv 语义 key (ECO_CAT_*), 显示处 tr() 翻译 (国际化设计.md §6ter)。
	# 钉死: 每个 reason 映射到的 key 在 en 下能翻成非 key 文案 (不漏翻)。
	TranslationServer.set_locale("en")
	var seen: Dictionary = {}
	for reason in EconomySystem.REASON_CATEGORY:
		var key: String = String(EconomySystem.REASON_CATEGORY[reason])
		seen[key] = true
	for key in ["ECO_CAT_EVENT", "ECO_CAT_CAMPAIGN", "ECO_CAT_OTHER_EXPENSE"]:
		seen[key] = true
	var missing: Array = []
	for key in seen:
		var en: String = tr(key)
		if en == key or en.strip_edges().is_empty():
			missing.append(key)
	TranslationServer.set_locale("zh_CN")  # 恢复基线
	assert_eq(missing.size(), 0, "这些账本分类 key 在 en 下未翻译: %s" % str(missing))

func test_multiple_same_category_entries_accumulate() -> void:
	CommandBus.send(&"economy.spend", {cost = {&"cash": 100}, reason = &"salaries"})
	CommandBus.send(&"economy.spend", {cost = {&"cash": 250}, reason = &"salaries"})
	var ledger: Dictionary = GameState.weekly_ledger
	assert_eq(int(ledger.expense.get("ECO_CAT_SALARIES", 0)), 350)

func test_one_time_expense_reasons_record_to_expected_categories() -> void:
	CommandBus.send(&"economy.spend", {cost = {&"cash": 100}, reason = &"facility_build"})
	CommandBus.send(&"economy.spend", {cost = {&"cash": 200}, reason = &"gpu_purchase"})
	CommandBus.send(&"economy.spend", {cost = {&"cash": 300}, reason = &"dataset_purchase"})
	CommandBus.send(&"economy.spend", {cost = {&"cash": 400}, reason = &"task_start"})
	CommandBus.send(&"economy.spend", {cost = {&"cash": 500}, reason = &"hire_lead"})
	var ledger: Dictionary = GameState.weekly_ledger
	assert_eq(int(ledger.expense.get("ECO_CAT_FACILITY_BUILD", 0)), 100)
	assert_eq(int(ledger.expense.get("ECO_CAT_GPU_PURCHASE", 0)), 200)
	assert_eq(int(ledger.expense.get("ECO_CAT_DATASET_PURCHASE", 0)), 300)
	assert_eq(int(ledger.expense.get("ECO_CAT_TASK_START", 0)), 400)
	assert_eq(int(ledger.expense.get("ECO_CAT_HIRE_FEE", 0)), 500)

# ---- resolve 滚动 ---------------------------------------------------------

func test_resolve_phase_rolls_current_into_history_with_turn_and_cash() -> void:
	GameState.turn = 5
	CommandBus.send(&"economy.spend", {cost = {&"cash": 1000}, reason = &"salaries"})
	CommandBus.send(&"economy.award", {amount = 3000, reason = &"monetization"})
	EventBus.phase_started.emit(&"resolve", 5)
	var history: Array = GameState.ledger_history
	assert_eq(history.size(), 1)
	var entry: Dictionary = history[0]
	assert_eq(int(entry.turn), 5)
	assert_eq(int(entry.gross_in), 3000)
	assert_eq(int(entry.gross_out), 1000)
	assert_eq(int(entry.income.get("ECO_CAT_REVENUE", 0)), 3000)
	assert_eq(int(entry.expense.get("ECO_CAT_SALARIES", 0)), 1000)
	# ending_cash snapshot equals current cash at roll time.
	assert_eq(int(entry.ending_cash), GameState.cash)

func test_resolve_phase_clears_current_ledger() -> void:
	CommandBus.send(&"economy.spend", {cost = {&"cash": 100}, reason = &"salaries"})
	EventBus.phase_started.emit(&"resolve", 1)
	var ledger: Dictionary = GameState.weekly_ledger
	assert_eq(int(ledger.gross_in), 0)
	assert_eq(int(ledger.gross_out), 0)
	assert_eq((ledger.expense as Dictionary).size(), 0)

func test_history_capped_at_twelve_weeks() -> void:
	for i in range(20):
		CommandBus.send(&"economy.award", {amount = 100, reason = &"monetization"})
		GameState.turn = i + 1
		EventBus.phase_started.emit(&"resolve", GameState.turn)
	# Cap = 12 (LEDGER_HISTORY_WEEKS in design §5).
	assert_eq(GameState.ledger_history.size(), 12)
	# Newest entry is turn 20 (we pushed 1..20).
	assert_eq(int(GameState.ledger_history[0].turn), 20,
			"newest entry should be at index 0")
	assert_eq(int(GameState.ledger_history[11].turn), 9,
			"oldest kept entry should be turn 9 (20 - 12 + 1)")

func test_loan_payment_splits_interest_and_principal_into_separate_categories() -> void:
	# Take a loan, then run upkeep — ledger should show 贷款利息 and 贷款还本
	# as two distinct entries (not a single "loan_payment" bucket).
	CommandBus.send(&"economy.take_loan", {amount = 120_000, term_weeks = 12})
	# Clear ledger of the loan_taken inflow so we only check upkeep effect.
	EventBus.phase_started.emit(&"resolve", 0)  # roll-over to flush current week
	GameState.turn = 1
	EventBus.phase_started.emit(&"upkeep", 1)
	var ledger: Dictionary = GameState.weekly_ledger
	assert_gt(int(ledger.expense.get("ECO_CAT_LOAN_INTEREST", 0)), 0,
			"expected loan-interest entry from upkeep loan charge")
	assert_gt(int(ledger.expense.get("ECO_CAT_LOAN_PRINCIPAL", 0)), 0,
			"expected loan-principal entry from upkeep loan charge")
