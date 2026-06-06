extends GutTest

## EconomySystem v1 — 边界与失败路径补测.
## Per design/经济系统设计.md (loans / funding / bankruptcy / credit rating).


func before_each() -> void:
	GameState.reset()

# ---- §loans 边界 -------------------------------------------------------

func test_take_loan_negative_amount_returns_credit_limit_exceeded() -> void:
	# 实现把 amount<=0 与超额合并为同一 error.
	var r: Dictionary = CommandBus.send(&"economy.take_loan",
			{amount = -100, term_weeks = 12})
	assert_false(r.ok)
	assert_eq(r.error, &"credit_limit_exceeded")

func test_take_loan_zero_term_rejected() -> void:
	var r: Dictionary = CommandBus.send(&"economy.take_loan",
			{amount = 100, term_weeks = 0})
	assert_false(r.ok)
	assert_eq(r.error, &"credit_limit_exceeded")

func test_take_loan_accepts_three_year_term() -> void:
	var r: Dictionary = CommandBus.send(&"economy.take_loan",
			{amount = 10_000, term_weeks = 156})
	assert_true(r.ok, "3 年期 (156 周) 是当前最长允许期限")
	assert_eq(GameState.loans[0].weeks_remaining, 156)

func test_take_loan_rejects_term_longer_than_three_years() -> void:
	var r: Dictionary = CommandBus.send(&"economy.take_loan",
			{amount = 10_000, term_weeks = 157})
	assert_false(r.ok)
	assert_eq(r.error, &"loan_term_exceeded")

func test_take_loan_emits_loan_taken_and_debt_changed() -> void:
	# 经济 §3 信号: loan_taken / debt_changed / cash_changed 都要发.
	watch_signals(EventBus)
	CommandBus.send(&"economy.take_loan", {amount = 50_000, term_weeks = 12})
	assert_signal_emitted(EventBus, "loan_taken")
	assert_signal_emitted(EventBus, "debt_changed")
	assert_signal_emitted(EventBus, "cash_changed")

func test_take_loan_assigns_unique_id_per_call() -> void:
	var a: Dictionary = CommandBus.send(&"economy.take_loan",
			{amount = 10_000, term_weeks = 12})
	var b: Dictionary = CommandBus.send(&"economy.take_loan",
			{amount = 10_000, term_weeks = 12})
	assert_ne(a.loan_id, b.loan_id)

func test_take_loan_id_uses_turn_month_and_sequence() -> void:
	# 经济系统设计 §1: loan id 形如 loan_2026_03_001, 方便从存档/debug
	# 直接看出发生年月和当月序号. turn=2 对应 2026-03.
	GameState.turn = 2
	var a: Dictionary = CommandBus.send(&"economy.take_loan",
			{amount = 10_000, term_weeks = 12})
	var b: Dictionary = CommandBus.send(&"economy.take_loan",
			{amount = 10_000, term_weeks = 12})
	assert_eq(a.loan_id, &"loan_2026_03_001")
	assert_eq(b.loan_id, &"loan_2026_03_002")

func test_take_loan_interest_rate_reflects_rating() -> void:
	# §4.3: rate = base × multiplier(rating). 新档 revenue=0 → C → 1.25×;
	# BASE = 0.002, 所以 C 档实际 0.0025/周 (= 0.25%).
	var r: Dictionary = CommandBus.send(&"economy.take_loan",
			{amount = 10_000, term_weeks = 12})
	var loan: Loan = GameState.loans[0]
	assert_almost_eq(loan.weekly_interest_rate, 0.0025, 0.0001)

func test_take_loan_high_revenue_lowers_rate() -> void:
	# §4.3: credit rating is revenue/debt driven. High revenue + no debt → S,
	# so a newly signed loan should get the S-rate discount.
	GameState.quarterly_revenue = 30_000_000
	GameState.debt = 0
	var r: Dictionary = CommandBus.send(&"economy.take_loan",
			{amount = 10_000, term_weeks = 12})
	assert_true(r.ok)
	var loan: Loan = GameState.loans[0]
	assert_almost_eq(loan.weekly_interest_rate,
			EconomySystem.BASE_INTEREST_RATE * 0.25, 0.000001)

func test_repay_full_amount_marks_loan_repaid_fully() -> void:
	var t: Dictionary = CommandBus.send(&"economy.take_loan",
			{amount = 100_000, term_weeks = 12})
	watch_signals(EventBus)
	CommandBus.send(&"economy.repay_loan", {loan_id = t.loan_id, amount = 100_000})
	# loan_repaid(loan_id, fully=true)
	assert_signal_emitted(EventBus, "loan_repaid")
	var p: Array = get_signal_parameters(EventBus, "loan_repaid")
	assert_eq(p[0], t.loan_id)
	assert_true(bool(p[1]), "应标记 fully=true")
	assert_eq(GameState.loans.size(), 0)
	assert_eq(GameState.debt, 0)

func test_repay_more_than_remaining_caps_at_remaining() -> void:
	# 实现: paid = mini(amount, principal_remaining).
	var t: Dictionary = CommandBus.send(&"economy.take_loan",
			{amount = 1000, term_weeks = 6})
	var before_cash: int = GameState.cash
	CommandBus.send(&"economy.repay_loan", {loan_id = t.loan_id, amount = 100_000})
	assert_eq(GameState.cash, before_cash - 1000, "应只扣 1000, 不应扣 100k")
	assert_eq(GameState.debt, 0)

func test_repay_partial_keeps_loan_in_array() -> void:
	var t: Dictionary = CommandBus.send(&"economy.take_loan",
			{amount = 100_000, term_weeks = 12})
	CommandBus.send(&"economy.repay_loan", {loan_id = t.loan_id, amount = 30_000})
	assert_eq(GameState.loans.size(), 1, "未还清的 loan 不应被 erase")
	assert_eq(GameState.loans[0].principal_remaining, 70_000)

# ---- upkeep charge_loans -----------------------------------------------

func test_upkeep_emits_loan_repaid_when_loan_naturally_finishes() -> void:
	# §4.1: weeks_remaining 到 0 → loans.erase + emit loan_repaid(fully=true).
	CommandBus.send(&"economy.take_loan", {amount = 12_000, term_weeks = 1})
	watch_signals(EventBus)
	EventBus.phase_started.emit(&"upkeep", 1)
	# 1 周 term, 单次扣全部本金 + 利息, 应清空.
	assert_eq(GameState.loans.size(), 0)
	assert_signal_emitted(EventBus, "loan_repaid")

func test_upkeep_with_no_loans_charges_nothing() -> void:
	var before: int = GameState.cash
	EventBus.phase_started.emit(&"upkeep", 1)
	# 没 loan 时, EconomySystem 应该不动 cash. (其他系统可能影响, 这里只看 EconomySystem 的 OWNED 行为)
	# 注: InfraSystem 也在 upkeep 里扣 dc 月费, 但我们没建 dc, 应不变.
	assert_eq(GameState.cash, before)

# ---- funding 边界: 自定义 start_funding 已删除, 改为 8 轮顺序 start_funding_round
# 详细 round-by-round 测试见 economy_funding_rounds_test.gd; 这里只放跨多轮的边界.

func test_repeated_rounds_compound_dilution() -> void:
	# 完成两个相邻轮次后 founder 持续下降, 且 founder + investors 守恒.
	CommandBus.send(&"economy.start_funding_round", {round = &"pre_seed"})
	var f1: float = float(GameState.equity.founder)
	# 满足 seed 条件 (≥1 evaluated 模型).
	var add: Dictionary = CommandBus.send(&"research.add_model",
			{arch = &"ant_v1", dataset_ids = []})
	CommandBus.send(&"research.evaluate_apply", {
		model_id = add.model_id,
		capability_measured = {&"general": 50.0}})
	CommandBus.send(&"economy.start_funding_round", {round = &"seed"})
	var f2: float = float(GameState.equity.founder)
	assert_lt(f2, f1)
	assert_almost_eq(f2 + float(GameState.equity.investors), 1.0, 0.0001)

# ---- preview_credit 边界 -----------------------------------------------

func test_preview_credit_returns_rating_string() -> void:
	var r: Dictionary = CommandBus.send(&"economy.preview_credit", {})
	assert_true(r.ok)
	assert_eq(r.rating, &"C")

func test_preview_credit_S_rating_at_high_revenue_low_debt() -> void:
	GameState.quarterly_revenue = 30_000_000
	GameState.debt = 0
	var r: Dictionary = CommandBus.send(&"economy.preview_credit", {})
	assert_eq(r.rating, &"S")
	assert_almost_eq(float(r.rate), EconomySystem.BASE_INTEREST_RATE * 0.25, 0.000001)

func test_preview_credit_max_loan_responds_to_debt_after_cash_spent() -> void:
	# 取贷后即便把借来的钱花掉, debt 仍在 → max_loan 应低于"借之前".
	var r1: Dictionary = CommandBus.send(&"economy.preview_credit", {})
	CommandBus.send(&"economy.take_loan", {amount = 1_000_000, term_weeks = 12})
	# 把借来的钱完全花掉
	CommandBus.send(&"economy.spend",
			{cost = {&"cash": 1_000_000}, reason = &"test"})
	var r2: Dictionary = CommandBus.send(&"economy.preview_credit", {})
	# 现在 cash 同初始, 但 debt = 1_000_000 → max_loan 应少于初始.
	assert_lt(int(r2.max_loan), int(r1.max_loan))

func test_max_loan_does_not_snowball_after_taking_loan() -> void:
	# Bug 修复: 取贷本身不应抬高信用上限。旧公式 γ×cash−debt 把借来的现金
	# 算进 cash, 每次借款都把额度推高约 2×, 形成「借一次翻一倍」的无限借钱。
	# 新公式用净现金 max(cash−debt,0): 借 X 元后剩余可贷额正好减 X 元。
	GameState.cash = 1_000_000
	GameState.debt = 0
	GameState.quarterly_revenue = 0
	var before: int = int(CommandBus.send(&"economy.preview_credit", {}).max_loan)
	# 借 50 万 (远小于上限 γ×100 万 = 300 万)。
	var loan: Dictionary = CommandBus.send(&"economy.take_loan",
			{amount = 500_000, term_weeks = 12})
	assert_true(loan.ok, "50 万应在信用上限内, 能借出")
	var after: int = int(CommandBus.send(&"economy.preview_credit", {}).max_loan)
	assert_true(after <= before, "取贷后信用上限绝不能上升 (before=%d after=%d)" % [before, after])
	assert_almost_eq(after, before - 500_000, 2,
			"借 50 万后剩余可贷额应正好下降 50 万")

# ---- bankruptcy ---------------------------------------------------------

func test_resolve_phase_emits_warning_when_cash_negative() -> void:
	GameState.cash = -1
	watch_signals(EventBus)
	EventBus.phase_started.emit(&"resolve", 1)
	assert_signal_emitted(EventBus, "bankruptcy_warning")
	var p: Array = get_signal_parameters(EventBus, "bankruptcy_warning")
	# bankruptcy_warning(reason: StringName, streak: int, threshold: int).
	assert_eq(StringName(p[0]), &"cash_negative")
	assert_eq(int(p[1]), 1)
	assert_eq(int(p[2]), 12)

func test_bankruptcy_warn_streak_loaded_below_limit() -> void:
	# §4.2: 预警阈值 (默认 8) 从 tuning 加载, 且必须严格小于终局上限 (默认 12)。
	assert_eq(EconomySystem.BANKRUPTCY_WARN_STREAK, 8,
			"bankruptcy_warn_streak 应从 tuning.tres 读出 8")
	assert_lt(EconomySystem.BANKRUPTCY_WARN_STREAK, EconomySystem.BANKRUPTCY_STREAK_LIMIT,
			"预警阈值必须早于终局上限")

func test_resolve_phase_triggers_bankruptcy_at_streak_limit() -> void:
	# §bankruptcy: streak 达到 12 → emit bankruptcy_triggered.
	GameState.cash = -1
	GameState.bankruptcy_streak = 11
	watch_signals(EventBus)
	EventBus.phase_started.emit(&"resolve", 1)
	assert_signal_emitted(EventBus, "bankruptcy_triggered")
	var p: Array = get_signal_parameters(EventBus, "bankruptcy_triggered")
	assert_eq(p[0], &"cash_negative_too_long")

func test_resolve_phase_cash_too_deep_triggers_bankruptcy_immediately() -> void:
	# §4.2 线 B: cash < BANKRUPTCY_DEPTH_FLOOR (-1_000_000) 直接触发.
	GameState.cash = -2_000_000
	watch_signals(EventBus)
	EventBus.phase_started.emit(&"resolve", 1)
	assert_signal_emitted(EventBus, "bankruptcy_triggered")
	var p: Array = get_signal_parameters(EventBus, "bankruptcy_triggered")
	assert_eq(p[0], &"cash_too_deep")

func test_streak_reset_to_zero_when_cash_recovers() -> void:
	GameState.bankruptcy_streak = 7
	GameState.cash = 1000  # positive
	EventBus.phase_started.emit(&"resolve", 1)
	assert_eq(GameState.bankruptcy_streak, 0)

# ---- spend / award 与 cash_changed 信号 --------------------------------

func test_spend_with_cash_key_uses_cash_field() -> void:
	# 实现把 &"cash" 与 &"money" 都映射到 GameState.cash.
	var before: int = GameState.cash
	CommandBus.send(&"economy.spend", {cost = {&"cash": 100}, reason = &"test"})
	assert_eq(GameState.cash, before - 100)

func test_spend_emits_cash_changed_when_money_in_cost() -> void:
	# 实现: spend 检查 cost 是否包含 money/cash, 是则 emit cash_changed.
	watch_signals(EventBus)
	CommandBus.send(&"economy.spend", {cost = {&"money": 100}, reason = &"r"})
	assert_signal_emitted(EventBus, "cash_changed")

func test_spend_does_not_emit_cash_changed_when_cost_has_only_other_keys() -> void:
	# 仅 compute / datasets 不应触发 cash_changed.
	watch_signals(EventBus)
	CommandBus.send(&"economy.spend", {cost = {&"compute": 5}, reason = &"r"})
	assert_signal_not_emitted(EventBus, "cash_changed")

func test_award_emits_both_resources_changed_and_cash_changed() -> void:
	watch_signals(EventBus)
	CommandBus.send(&"economy.award", {amount = 1000, reason = &"r"})
	assert_signal_emitted(EventBus, "resources_changed")
	assert_signal_emitted(EventBus, "cash_changed")

# ---- §6.4 破产深度 (随公司规模缩放) ------------------------------------

func test_bankruptcy_depth_scales_with_burn_rate() -> void:
	# threshold = -(3 × burn + 0.5 × revenue), 带 -1M floor.
	# burn_rate 10M → threshold = -30M (远低于 floor), 应触发 cash_too_deep.
	GameState.weekly_burn_rate = 10_000_000
	GameState.quarterly_revenue = 0
	GameState.cash = -25_000_000  # 比 -30M 高, 不应破产
	watch_signals(EventBus)
	EventBus.phase_started.emit(&"resolve", 1)
	assert_signal_not_emitted(EventBus, "bankruptcy_triggered",
			"-25M 仍在 -30M 阈值之内, 不应破产")

func test_bankruptcy_depth_triggers_when_burn_scaled_threshold_exceeded() -> void:
	GameState.weekly_burn_rate = 10_000_000
	GameState.quarterly_revenue = 0
	GameState.cash = -50_000_000  # 低于 -30M, 应破产
	watch_signals(EventBus)
	EventBus.phase_started.emit(&"resolve", 1)
	assert_signal_emitted(EventBus, "bankruptcy_triggered")

func test_bankruptcy_depth_floor_protects_brand_new_company() -> void:
	# 新档: burn=0 revenue=0, 公式给 0; 必须有 floor (-1M) 防止任何赤字直接破产.
	GameState.weekly_burn_rate = 0
	GameState.quarterly_revenue = 0
	GameState.cash = -500_000  # 比 -1M 高, 即在 floor 之内
	watch_signals(EventBus)
	EventBus.phase_started.emit(&"resolve", 1)
	assert_signal_not_emitted(EventBus, "bankruptcy_triggered",
			"小公司有 -1M 安全网, 不应在 -500k 就破产")

# ---- §6.5 信用评级 (考虑 debt/revenue, 不再 fame-only) ------------------

func test_credit_rating_S_requires_low_debt_and_high_revenue() -> void:
	# S requires both ratio < 0.5 and quarterly_revenue >= 30M.
	GameState.quarterly_revenue = 30_000_000
	GameState.debt = 0
	var s: Dictionary = CommandBus.send(&"economy.preview_credit", {})
	assert_eq(s.rating, &"S")

	GameState.quarterly_revenue = 29_999_999
	var below_revenue: Dictionary = CommandBus.send(&"economy.preview_credit", {})
	assert_ne(below_revenue.rating, &"S")

	GameState.quarterly_revenue = 30_000_000
	GameState.debt = 15_000_000
	var high_debt: Dictionary = CommandBus.send(&"economy.preview_credit", {})
	assert_ne(high_debt.rating, &"S")

func test_credit_rating_drops_to_C_when_debt_ratio_is_high() -> void:
	# debt/revenue 比值大时不能给 S/A/B.
	GameState.quarterly_revenue = 1_000_000
	GameState.debt = 3_000_000  # ratio 3 → 既不 < 0.5/1/2, 但 < 4 → C
	var r: Dictionary = CommandBus.send(&"economy.preview_credit", {})
	assert_eq(r.rating, &"C")

func test_credit_rating_D_when_debt_ratio_extreme() -> void:
	GameState.quarterly_revenue = 1_000_000
	GameState.debt = 5_000_000  # ratio 5 ≥ 4 → D
	var r: Dictionary = CommandBus.send(&"economy.preview_credit", {})
	assert_eq(r.rating, &"D")

# ---- §6.5 max_loan 公式 (revenue 也是杠杆) -----------------------------

func test_max_loan_includes_quarterly_revenue_term() -> void:
	# max_loan = β × revenue + γ × cash − debt
	# revenue=0 vs revenue=1M, 高的 max_loan 应明显更大.
	GameState.cash = 100_000
	GameState.debt = 0
	GameState.quarterly_revenue = 0
	var r0: Dictionary = CommandBus.send(&"economy.preview_credit", {})
	GameState.quarterly_revenue = 1_000_000
	var r1: Dictionary = CommandBus.send(&"economy.preview_credit", {})
	assert_gt(int(r1.max_loan), int(r0.max_loan),
			"quarterly_revenue 上升 → max_loan 应上升")

## 设计 §4.1: 单一银行可贷额硬上限 $20B。后期 $10B/周营收 + 高净现金会让
## β/γ 公式算到 $500B+, 偏离"银行能给多少"现实直觉。
func test_max_loan_caps_at_20b_absolute() -> void:
	GameState.cash = 200_000_000_000      # $200B 净现金
	GameState.debt = 0
	GameState.quarterly_revenue = 130_000_000_000  # ≈ $10B/周 × 13 周
	var r: Dictionary = CommandBus.send(&"economy.preview_credit", {})
	assert_eq(int(r.max_loan), 20_000_000_000,
			"max_loan 应被硬夹到 $20B; β/γ 公式裸算会到 ~$860B")
	# 借满 $20B 后, take_loan 再借 1 元也该被拒.
	var ok: Dictionary = CommandBus.send(&"economy.take_loan",
			{amount = 20_000_000_000, term_weeks = 52})
	assert_true(ok.ok, "20B 整额贷款应被接受")
	var over: Dictionary = CommandBus.send(&"economy.take_loan",
			{amount = 1, term_weeks = 52})
	assert_false(over.ok, "20B cap 已满, 再借 1 元应被拒")
	assert_eq(over.error, &"credit_limit_exceeded")

# ---- §4.7 weekly_burn_rate / quarterly_revenue 维护 ---------------------

func test_upkeep_updates_weekly_burn_rate_from_recent_spends() -> void:
	# 推 3 个 upkeep, 每次伴随一笔花费, weekly_burn_rate 应反映滑动均值.
	# 借助 economy.spend 生成支出, 再触发 upkeep 关账.
	for i in range(3):
		CommandBus.send(&"economy.spend", {cost = {&"cash": 100_000}, reason = &"test"})
		EventBus.phase_started.emit(&"upkeep", i + 1)
	assert_gt(GameState.weekly_burn_rate, 0,
			"upkeep 后 weekly_burn_rate 应被填上正值")

func test_upkeep_updates_quarterly_revenue_from_awards() -> void:
	for i in range(3):
		CommandBus.send(&"economy.award", {amount = 50_000, reason = &"api"})
		EventBus.phase_started.emit(&"upkeep", i + 1)
	assert_gt(GameState.quarterly_revenue, 0,
			"upkeep 后 quarterly_revenue 应被填上正值")

# ---- §4.4 估值公式 (乘法 + portfolio_bonus) ----------------------------

func test_valuation_grows_with_published_models_count() -> void:
	# 估值在 start_funding_round 内部由 _compute_valuation 算出, 受 published
	# 模型数 portfolio bonus 影响. 用 spec 下限 (小 amount + 大 dilution) 让
	# implied valuation (= amount / dilution) 被 _compute_valuation 主导.
	var Model := load("res://scripts/resources/model.gd")
	GameState.cash = 50_000_000
	GameState.quarterly_revenue = 50_000_000
	GameState.last_revenue_breakdown = {}
	var r0: Dictionary = CommandBus.send(&"economy.start_funding_round",
			{round = &"pre_seed", amount = 500_000, dilution = 0.10})
	assert_true(r0.ok)
	var v0: int = int(r0.valuation)
	GameState.reset()
	GameState.cash = 50_000_000
	GameState.quarterly_revenue = 50_000_000
	for i in range(3):
		var m = Model.new()
		m.id = StringName("m_%d" % i)
		m.status = &"published"
		GameState.models.append(m)
	var r3: Dictionary = CommandBus.send(&"economy.start_funding_round",
			{round = &"pre_seed", amount = 500_000, dilution = 0.10})
	assert_gt(int(r3.valuation), v0, "published_models 多 → valuation 高")
