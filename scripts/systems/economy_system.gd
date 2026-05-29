extends Node

## EconomySystem v2 — owns cash, debt, loans, equity, bankruptcy_streak +
## weekly_ledger / ledger_history (财务报表). Per design/经济系统设计.md.
##
## Spend & award never fail (cash may go negative — bankruptcy gate at resolve
## phase handles persistent negativity). Every spend/award/loan tick records to
## the weekly ledger by category, rolled into history at resolve phase.
##
## Funding is player-initiated 8 rounds (pre_seed→seed→a-f); v9.1 removed the
## sequential lock so any round whose conditions are met can be accepted, even
## without first accepting earlier rounds. The old EventSystem-pushed funding
## offers and the custom-amount `economy.start_funding` command have both been
## removed.


const OWNED_SLICES: Array[StringName] = [
	&"cash", &"debt", &"equity", &"loans", &"bankruptcy_streak",
	&"weekly_burn_rate", &"quarterly_revenue", &"tax_loss_carryforward",
	&"weekly_ledger", &"ledger_history",
]

# ---- Tunables (table-driven, see 经济系统设计.md §5) -----------------------
# Authoritative source: resources/data/economy/tuning.tres +
# resources/data/economy/funding_rounds/*.tres. Loaded by _load_tables() at
# _ready into these instance vars (kept by their original UPPERCASE names so
# external callers like main.gd:EconomySystem.BANKRUPTCY_STREAK_LIMIT still
# work). Defaults below are pre-load fallbacks only.
const TUNING_PATH: String = "res://resources/data/economy/tuning.tres"
# 8 rounds (design §4.6). v9.1: no sequential lock — any round whose
# conditions are met can be accepted. Order here is only the display order
# for preview_funding_rounds.
const FUNDING_ROUND_ORDER: Array[StringName] = [
	&"pre_seed", &"seed", &"a", &"b", &"c", &"d", &"e", &"f",
]
const FUNDING_ROUND_PATHS: Dictionary = {
	&"pre_seed": "res://resources/data/economy/funding_rounds/pre_seed.tres",
	&"seed":     "res://resources/data/economy/funding_rounds/seed.tres",
	&"a":        "res://resources/data/economy/funding_rounds/a.tres",
	&"b":        "res://resources/data/economy/funding_rounds/b.tres",
	&"c":        "res://resources/data/economy/funding_rounds/c.tres",
	&"d":        "res://resources/data/economy/funding_rounds/d.tres",
	&"e":        "res://resources/data/economy/funding_rounds/e.tres",
	&"f":        "res://resources/data/economy/funding_rounds/f.tres",
}

# Weekly ledger history cap. Per design §4.8 — UI 表格显示最近 12 周。
const LEDGER_HISTORY_WEEKS: int = 12

# Bankruptcy
var BANKRUPTCY_STREAK_LIMIT: int = 12
# 预警阈值 (< limit): UI 用来把「轻度赤字」与「濒临破产」分开提示。见 §4.2。
var BANKRUPTCY_WARN_STREAK: int = 8
var BANKRUPTCY_DEPTH_FLOOR: int = -1_000_000
var BANKRUPTCY_DEPTH_K: float = 3.0
var BANKRUPTCY_DEPTH_L: float = 0.5

# Loans / credit. BASE = B-grade weekly rate. Multipliers in _current_rate.
# v9.2: max 0.5%/周 (D=2.5×), min 0.05%/周 (S=0.25×) — design §4.3.
var BASE_INTEREST_RATE: float = 0.002
var MAX_LOAN_BETA: float = 2.0
var MAX_LOAN_GAMMA: float = 3.0
# Hard ceiling regardless of β/γ formula. See 经济系统设计.md §4.1.
var MAX_LOAN_ABSOLUTE_CAP: int = 20_000_000_000
var MAX_LOAN_TERM_WEEKS: int = 156
var LOAN_ID_START_YEAR: int = 2026

# Funding valuation
var VALUATION_BASE: int = 500_000
var VALUATION_MULTIPLIER: float = 2.0
var VALUATION_CASH_COEF: float = 0.3
var RANK_PREMIUM_RANK_1: float = 0.50
var RANK_PREMIUM_RANK_TOP3: float = 0.25
var RANK_PREMIUM_RANK_TOP10: float = 0.10
var PORTFOLIO_BONUS_PER_MODEL: float = 0.05
var FOUNDER_MIN_STAKE: float = 0.5

# Burn / revenue rolling buffers (per-week — 1 turn = 1 week).
var BURN_WINDOW_WEEKS: int = 3
var REVENUE_WINDOW_WEEKS: int = 12

# Taxation (经济系统设计.md §4.9). Settled weekly at resolve on operating profit.
var CORP_TAX_RATE: float = 0.25
var CORP_TAX_EXEMPTION: int = 1_000_000
var AI_TAX_RATE: float = 0.20
var AI_TAX_THRESHOLD: int = 1_000_000_000

# Funding round table — assembled at _ready from funding_rounds/*.tres.
# Shape: { round_id: { amin, amax, dmin, dmax, display_name, unlock_summary } }.
var FUNDING_ROUND_TABLE: Dictionary = {}

# 周度账本: reason → 显示类目. 前缀匹配 event:* / campaign:* 见 _categorize.
# reason → 账本分类。值是 strings.csv 语义 key (UI 显示处 tr(key) 翻译, 见
# design/国际化设计.md §6ter); 同时作为 weekly_ledger 的分组 key (locale 无关, 稳定)。
const REASON_CATEGORY: Dictionary = {
	# income
	&"monetization": "ECO_CAT_REVENUE",
	&"funding_round": "ECO_CAT_FUNDING",
	&"gpu_resale": "ECO_CAT_GPU_RESALE",
	&"gpu_resale_on_terminate": "ECO_CAT_GPU_RESALE",
	&"gpu_rental_income": "ECO_CAT_GPU_RENTAL",
	&"loan_taken": "ECO_CAT_LOAN_IN",
	&"task_cancel_refund": "ECO_CAT_TASK_REFUND",
	# expense
	&"gpu_rental_platform_fee": "ECO_CAT_RENTAL_FEE",
	&"salaries": "ECO_CAT_SALARIES",
	&"hire_lead": "ECO_CAT_HIRE_FEE",
	&"hire_staff": "ECO_CAT_HIRE_FEE",
	&"facility_costs": "ECO_CAT_FACILITY_RENT",
	&"facility_build": "ECO_CAT_FACILITY_BUILD",
	&"gpu_runtime_costs": "ECO_CAT_GPU_RUNTIME",
	&"cloud_gpu_costs": "ECO_CAT_CLOUD_GPU",
	&"gpu_purchase": "ECO_CAT_GPU_PURCHASE",
	&"loan_payment_interest": "ECO_CAT_LOAN_INTEREST",
	&"loan_payment_principal": "ECO_CAT_LOAN_PRINCIPAL",
	&"loan_repaid": "ECO_CAT_LOAN_REPAID",
	&"task_start": "ECO_CAT_TASK_START",
	&"task_weekly": "ECO_CAT_TASK_WEEKLY",
	&"dataset_purchase": "ECO_CAT_DATASET_PURCHASE",
	# 慈善捐助单列 (design/慈善系统设计.md §5)。不在 NON_TAXABLE_REASONS 里 → 全额可抵。
	&"charity_donation": "ECO_CAT_CHARITY",
	# 收藏品买卖 (design/办公室与收藏系统设计.md §3)。资产负债表科目, 不进应税损益
	# (见下方 NON_TAXABLE_REASONS), 避免"买名画抵税"漏洞。
	&"collectible_purchase": "ECO_CAT_COLLECTIBLE_BUY",
	&"collectible_sale": "ECO_CAT_COLLECTIBLE_SELL",
	# 宇宙模拟工程捐助 (design/宇宙模拟工程设计.md §5)。不在 NON_TAXABLE_REASONS → 可抵税。
	&"simulation_funding": "ECO_CAT_SIMULATION",
	# 税 (resolve 结算, design §4.9)
	&"corporate_tax": "ECO_CAT_CORP_TAX",
	&"ai_ubi_tax": "ECO_CAT_AI_UBI_TAX",
}

# 不计入应税利润的 reason: 股权融资 + 债务本金 (资产负债表科目, 非损益) 以及税
# 本身。贷款利息 (loan_payment_interest) 仍算可抵费用。见 design §4.9。经 _ready
# 把这些 reason 映射成类目集合 _non_taxable_categories, 供 _compute_taxable_profit
# 从 weekly_ledger 过滤。
const NON_TAXABLE_REASONS: Array[StringName] = [
	&"funding_round", &"loan_taken",
	&"loan_payment_principal", &"loan_repaid",
	&"collectible_purchase", &"collectible_sale",
	&"corporate_tax", &"ai_ubi_tax",
]
var _non_taxable_categories: Dictionary = {}

var _loan_seq_by_month: Dictionary = {}

# Weekly buffers — index 0 is the *current* week (in-progress), shifted on upkeep.
var _spend_history: Array[int] = []   # absolute outflow values per week
var _revenue_history: Array[int] = [] # inflow values per week
var _current_spend: int = 0
var _current_revenue: int = 0

func _ready() -> void:
	_load_tables()
	_build_non_taxable_categories()
	_ensure_ledger_initialized()
	CommandBus.register(&"economy.spend", _on_spend)
	CommandBus.register(&"economy.award", _on_award)
	CommandBus.register(&"economy.take_loan", _on_take_loan)
	CommandBus.register(&"economy.repay_loan", _on_repay_loan)
	CommandBus.register(&"economy.start_funding_round", _on_start_funding_round)
	CommandBus.register(&"economy.preview_funding_rounds", _on_preview_funding_rounds)
	CommandBus.register(&"economy.preview_credit", _on_preview_credit)
	EventBus.phase_started.connect(_on_phase)
	EventBus.state_reset.connect(_on_state_reset)

func _on_state_reset() -> void:
	_loan_seq_by_month.clear()
	_spend_history.clear()
	_revenue_history.clear()
	_current_spend = 0
	_current_revenue = 0
	_ensure_ledger_initialized(true)

# ---- spend / award ------------------------------------------------------

func _on_spend(p: Dictionary) -> Dictionary:
	var cost: Dictionary = p.get(&"cost", {})
	var reason: StringName = p.get(&"reason", &"")
	var delta: Dictionary = {}
	for key in cost.keys():
		var amount: int = int(cost[key])
		_apply_resource_delta(key, -amount)
		delta[key] = -amount
		if _is_cash_key(key):
			_current_spend += amount
			_ledger_track(-amount, reason)
	Log.debug(&"economy", "spend", {delta = delta, reason = reason})
	EventBus.resources_changed.emit(delta, reason)
	if delta.has(&"money") or delta.has(&"cash"):
		var d: int = int(delta.get(&"money", 0)) + int(delta.get(&"cash", 0))
		EventBus.cash_changed.emit(d, reason)
	return {ok = true}

func _on_award(p: Dictionary) -> Dictionary:
	var amount: int = int(p.get(&"amount", 0))
	var reason: StringName = p.get(&"reason", &"")
	_apply_resource_delta(&"money", amount)
	if amount > 0:
		_current_revenue += amount
	if amount != 0:
		_ledger_track(amount, reason)
	var delta := {&"money": amount}
	Log.debug(&"economy", "award", {delta = delta, reason = reason})
	EventBus.resources_changed.emit(delta, reason)
	EventBus.cash_changed.emit(amount, reason)
	return {ok = true}

func _is_cash_key(key) -> bool:
	return key == &"money" or key == &"cash"

# Updates both the structured `cash` field and the legacy `resources` bucket
# so existing tests + design contract stay in sync.
func _apply_resource_delta(key: StringName, amount: int) -> void:
	if _is_cash_key(key):
		GameState.cash += amount
		GameState.resources[&"money"] = GameState.cash
	else:
		GameState.resources[key] = int(GameState.resources.get(key, 0)) + amount

# ---- loans --------------------------------------------------------------

func _on_take_loan(p: Dictionary) -> Dictionary:
	var amount: int = int(p.get(&"amount", 0))
	var term: int = int(p.get(&"term_weeks", 12))
	if amount <= 0 or term <= 0:
		return {ok = false, error = &"credit_limit_exceeded"}
	if term > MAX_LOAN_TERM_WEEKS:
		Log.info(&"economy", "loan_rejected",
				{reason = &"loan_term_exceeded", amount = amount, term = term,
				 max_term = MAX_LOAN_TERM_WEEKS})
		return {ok = false, error = &"loan_term_exceeded"}
	if amount > _max_loan():
		return {ok = false, error = &"credit_limit_exceeded"}
	var loan := Loan.new()
	loan.id = _make_loan_id()
	loan.principal_initial = amount
	loan.principal_remaining = amount
	loan.weekly_interest_rate = _current_rate()
	loan.weeks_remaining = term
	loan.taken_at_turn = GameState.turn
	GameState.loans.append(loan)
	GameState.debt += amount
	_apply_resource_delta(&"cash", amount)
	# Loan proceeds are NOT counted as recurring revenue (they are debt) but the
	# ledger does track them so the cash inflow shows up on the financial report.
	_ledger_track(amount, &"loan_taken")
	Log.info(&"economy", "loan_taken", {loan_id = loan.id, amount = amount, term = term})
	EventBus.loan_taken.emit(loan.id)
	EventBus.debt_changed.emit(amount, &"loan_taken")
	EventBus.cash_changed.emit(amount, &"loan_taken")
	return {ok = true, loan_id = loan.id}

func _make_loan_id() -> StringName:
	var month_index: int = maxi(0, GameState.turn)
	var year: int = LOAN_ID_START_YEAR + floori(float(month_index) / 12.0)
	var month: int = (month_index % 12) + 1
	var key := "%04d_%02d" % [year, month]
	var seq: int = int(_loan_seq_by_month.get(key, 0)) + 1
	var prefix := "loan_%s_" % key
	for existing in GameState.loans:
		var id_text := String(existing.id)
		if id_text.begins_with(prefix):
			seq = maxi(seq, int(id_text.substr(prefix.length())) + 1)
	_loan_seq_by_month[key] = seq
	return StringName("%s%03d" % [prefix, seq])

func _on_repay_loan(p: Dictionary) -> Dictionary:
	var loan_id: StringName = p.get(&"loan_id", &"")
	var amount: int = int(p.get(&"amount", 0))
	var loan := _find_loan(loan_id)
	if loan == null:
		return {ok = false, error = &"unknown_loan"}
	var paid: int = mini(amount, loan.principal_remaining)
	loan.principal_remaining -= paid
	GameState.debt -= paid
	_apply_resource_delta(&"cash", -paid)
	_current_spend += paid
	_ledger_track(-paid, &"loan_repaid")
	var fully := loan.principal_remaining == 0
	if fully:
		GameState.loans.erase(loan)
	Log.info(&"economy", "loan_repaid", {loan_id = loan_id, amount = paid, fully = fully})
	# 经济系统设计 §3 contract: cash_changed AND debt_changed AND
	# resources_changed must all fire on a balance-affecting event so HUD,
	# financial panel and burn-rate ledgers stay in sync.
	EventBus.resources_changed.emit({&"money": -paid}, &"loan_repaid")
	EventBus.cash_changed.emit(-paid, &"loan_repaid")
	EventBus.debt_changed.emit(-paid, &"loan_repaid")
	EventBus.loan_repaid.emit(loan_id, fully)
	return {ok = true}

func _find_loan(loan_id: StringName) -> Loan:
	for l in GameState.loans:
		if l.id == loan_id:
			return l
	return null

# ---- funding (player-initiated 8-round sequential, design §4.6) ----------

func _on_start_funding_round(p: Dictionary) -> Dictionary:
	var round_name: StringName = p.get(&"round", &"")
	if not FUNDING_ROUND_TABLE.has(round_name):
		return {ok = false, error = &"unknown_round"}
	if bool(GameState.funding_rounds_accepted.get(round_name, false)):
		return {ok = false, error = &"already_accepted"}
	# v9.1: no sequential lock. Skipping to a later round is allowed as long
	# as that round's conditions are met. pre_seed has no conditions, so it
	# remains accept-able even after later rounds have been taken.
	if not _funding_round_conditions_met(round_name):
		return {ok = false, error = &"conditions_not_met"}
	var spec: Dictionary = FUNDING_ROUND_TABLE[round_name]
	# Caller may pass explicit amount/dilution (testing / CLI). Otherwise roll
	# each missing field independently.
	var amount: int = int(p.get(&"amount", 0))
	var amount_explicit: bool = amount > 0
	var dilution: float = float(p.get(&"dilution", 0.0))
	var rng := GameState.rng()
	if amount <= 0:
		amount = rng.randi_range(int(spec.amin), int(spec.amax))
	if dilution <= 0.0:
		dilution = rng.randf_range(float(spec.dmin), float(spec.dmax))
	# Defensively clamp inputs into the per-round legal envelope.
	amount = clampi(amount, int(spec.amin), int(spec.amax))
	dilution = clampf(dilution, float(spec.dmin), float(spec.dmax))
	# 出身系统设计 §5: founder origin scales the rolled funding amount
	# (entrepreneur ×2). An explicitly passed amount (tests / CLI) is honored
	# as-is so existing economy tests stay deterministic.
	if not amount_explicit:
		amount = int(round(float(amount) * FounderSystem.funding_multiplier()))
	# §4.5 founder stake floor — boundary is strict (≤ 50% rejects).
	var new_founder: float = float(GameState.equity.founder) * (1.0 - dilution)
	if new_founder <= FOUNDER_MIN_STAKE:
		Log.info(&"economy", "start_funding_round_rejected",
				{round = round_name, dilution = dilution, new_founder = new_founder})
		return {ok = false, error = &"founder_stake_below_50"}
	var valuation: int = _compute_valuation()
	# If the round's amount/dilution implies its own valuation, use the larger
	# of the two so the displayed valuation never undersells the round.
	var implied: int = int(round(float(amount) / max(dilution, 1e-9)))
	if implied > valuation:
		valuation = implied
	GameState.equity.founder = new_founder
	GameState.equity.investors = 1.0 - new_founder
	_apply_resource_delta(&"cash", amount)
	_ledger_track(amount, &"funding_round")
	GameState.funding_rounds_accepted[round_name] = true
	Log.info(&"economy", "start_funding_round",
			{round = round_name, amount = amount, dilution = dilution,
			 valuation = valuation})
	EventBus.equity_changed.emit(dilution)
	EventBus.funding_completed.emit(amount, dilution, valuation)
	EventBus.cash_changed.emit(amount, &"funding_round")
	return {ok = true, amount = amount, dilution = dilution, valuation = valuation}

func _on_preview_funding_rounds(_p: Dictionary) -> Dictionary:
	var out: Array = []
	for round_id in FUNDING_ROUND_ORDER:
		var spec: Dictionary = FUNDING_ROUND_TABLE.get(round_id, {})
		if spec.is_empty():
			continue
		var status: StringName = _round_status(round_id)
		out.append({
			round = round_id,
			display_name = String(spec.get("display_name", String(round_id))),
			unlock_summary = String(spec.get("unlock_summary", "")),
			amount_min = int(spec.amin),
			amount_max = int(spec.amax),
			dilution_min = float(spec.dmin),
			dilution_max = float(spec.dmax),
			status = status,
		})
	return {ok = true, rounds = out}

## v9.1: a round is `available` iff (a) it is not already accepted and (b)
## its conditions are met. No predecessor check — earlier rounds may stay
## un-accepted and the player can skip directly to any qualifying round.
func _round_status(round_id: StringName) -> StringName:
	if bool(GameState.funding_rounds_accepted.get(round_id, false)):
		return &"accepted"
	if not _funding_round_conditions_met(round_id):
		return &"locked"
	return &"available"

func _on_preview_credit(_p: Dictionary) -> Dictionary:
	return {ok = true, max_loan = _max_loan(), rate = _current_rate(), rating = _rating()}

func _max_loan() -> int:
	# β × quarterly_revenue + γ × net_cash − debt, clamped at 0.
	# net_cash = max(cash − debt, 0): loan proceeds raise cash AND debt by the
	# same amount, so net_cash is unchanged by borrowing — taking a loan can
	# never inflate the credit ceiling. Each $1 borrowed lowers the remaining
	# headroom by exactly $1. The old `γ × cash` term (cash incl. borrowed
	# money) made every loan push the limit up ~2×, an infinite-borrow exploit.
	# See design/经济系统设计.md §4.1.
	var by_revenue: float = MAX_LOAN_BETA * float(maxi(GameState.quarterly_revenue, 0))
	var net_cash: int = maxi(GameState.cash - GameState.debt, 0)
	var by_cash: float = MAX_LOAN_GAMMA * float(net_cash)
	var formula_remaining: int = maxi(0, int(by_revenue + by_cash) - GameState.debt)
	# 设计 §4.1: 银行对单家公司总敞口硬上限 $20B (默认)。已有 debt 占用敞口,
	# 剩余可贷 = cap − debt。两条 (公式 / 敞口) 取较小, 都夹到 0。
	var cap_remaining: int = maxi(0, MAX_LOAN_ABSOLUTE_CAP - GameState.debt)
	return mini(formula_remaining, cap_remaining)

func _current_rate() -> float:
	match _rating():
		&"S": return BASE_INTEREST_RATE * 0.25
		&"A": return BASE_INTEREST_RATE * 0.5
		&"B": return BASE_INTEREST_RATE
		&"C": return BASE_INTEREST_RATE * 1.25
		_: return BASE_INTEREST_RATE * 2.5

func _rating() -> StringName:
	# Per design/经济系统设计.md §4.3 — ratio AND revenue absolute both gate.
	var revenue_floor: int = maxi(GameState.quarterly_revenue, 1)
	var ratio: float = float(GameState.debt) / float(revenue_floor)
	var revenue: int = GameState.quarterly_revenue
	if ratio < 0.5 and revenue >= 30_000_000: return &"S"
	if ratio < 1.0 and revenue >= 10_000_000: return &"A"
	if ratio < 2.0 and revenue >= 1_000_000:  return &"B"
	if ratio < 4.0:                            return &"C"
	return &"D"

func _compute_valuation() -> int:
	# Per 经济系统设计.md §4.4: VALUATION_BASE is the floor (protects brand-new
	# companies). Rank premium replaces the old fame multiplier.
	var revenue: int = maxi(GameState.quarterly_revenue, 0)
	var cash_term: float = VALUATION_CASH_COEF * float(maxi(GameState.cash, 0))
	var rank_mult: float = 1.0 + _rank_premium()
	var portfolio_mult: float = 1.0 + PORTFOLIO_BONUS_PER_MODEL * float(_published_models_count())
	var mult_value: float = VALUATION_MULTIPLIER * (float(revenue) + cash_term) * rank_mult * portfolio_mult
	var base_val: int = maxi(VALUATION_BASE, int(round(mult_value)))
	# 出身系统设计 §5: founder origin scales the final valuation (incl. floor)
	# — entrepreneur ×2, scientist/influencer < 1.
	# 慈善系统设计 §6: fundamental_compute 捐助再乘一个 ≥1 的封顶估值乘子 (中性 1.0)。
	return int(round(float(base_val)
			* FounderSystem.funding_multiplier()
			* CharitySystem.valuation_multiplier()))

## Highest player rank on the unified `total` board. Top-1 gets +50%, top-3
## +25%, top-10 +10%, otherwise nothing.
func _rank_premium() -> float:
	var best: int = 0
	for m in GameState.models:
		if m == null or m.status != &"published":
			continue
		var rank: int = MarketSystem.get_rank_for_model(m.id, &"total")
		if rank <= 0:
			continue
		if best == 0 or rank < best:
			best = rank
	if best == 1: return RANK_PREMIUM_RANK_1
	if best <= 3 and best > 0: return RANK_PREMIUM_RANK_TOP3
	if best <= 10 and best > 0: return RANK_PREMIUM_RANK_TOP10
	return 0.0

func _published_models_count() -> int:
	var n: int = 0
	for m in GameState.models:
		if m and m.status == &"published":
			n += 1
	return n

# ---- phase hooks --------------------------------------------------------

func _on_phase(phase: StringName, _turn: int) -> void:
	match phase:
		&"upkeep":
			_charge_loans()
			_roll_burn_revenue_window()
		&"resolve":
			_settle_taxes()
			_check_bankruptcy()
			_roll_ledger()

func _charge_loans() -> void:
	for l in GameState.loans.duplicate():
		var interest: int = int(round(float(l.principal_remaining) * l.weekly_interest_rate))
		var principal_due: int = 0
		if l.weeks_remaining > 0:
			principal_due = int(round(float(l.principal_remaining) / float(l.weeks_remaining)))
		# Charge interest and principal as two separate ledger entries so the
		# financial report can show them on distinct lines (design §4.1 + §4.8).
		if interest > 0:
			_apply_resource_delta(&"cash", -interest)
			_current_spend += interest
			_ledger_track(-interest, &"loan_payment_interest")
			EventBus.resources_changed.emit({&"money": -interest}, &"loan_payment_interest")
			EventBus.cash_changed.emit(-interest, &"loan_payment_interest")
		if principal_due > 0:
			_apply_resource_delta(&"cash", -principal_due)
			_current_spend += principal_due
			_ledger_track(-principal_due, &"loan_payment_principal")
			EventBus.resources_changed.emit({&"money": -principal_due}, &"loan_payment_principal")
			EventBus.cash_changed.emit(-principal_due, &"loan_payment_principal")
		l.principal_remaining = maxi(0, l.principal_remaining - principal_due)
		GameState.debt = maxi(0, GameState.debt - principal_due)
		# Per 事件总线信号表 §EconomySystem: debt_changed fires on weekly
		# principal payments too, not only on take/repay/funding round.
		if principal_due > 0:
			EventBus.debt_changed.emit(-principal_due, &"loan_payment_principal")
		l.weeks_remaining -= 1
		if l.weeks_remaining <= 0 or l.principal_remaining <= 0:
			GameState.loans.erase(l)
			EventBus.loan_repaid.emit(l.id, true)

func _roll_burn_revenue_window() -> void:
	# Push the in-progress week into history, recompute snapshots, reset accumulators.
	_spend_history.push_front(_current_spend)
	_revenue_history.push_front(_current_revenue)
	while _spend_history.size() > BURN_WINDOW_WEEKS:
		_spend_history.pop_back()
	while _revenue_history.size() > REVENUE_WINDOW_WEEKS:
		_revenue_history.pop_back()
	_current_spend = 0
	_current_revenue = 0

	# weekly_burn_rate = rolling average of recent weekly spend.
	var burn_sum: int = 0
	for v in _spend_history:
		burn_sum += int(v)
	var burn_n: int = _spend_history.size()
	GameState.weekly_burn_rate = int(burn_sum / float(burn_n)) if burn_n > 0 else 0

	# quarterly_revenue: prefer full-window sum; if short history, extrapolate.
	var rev_sum: int = 0
	for v in _revenue_history:
		rev_sum += int(v)
	var rev_n: int = _revenue_history.size()
	if rev_n >= REVENUE_WINDOW_WEEKS:
		GameState.quarterly_revenue = rev_sum
	elif rev_n > 0:
		GameState.quarterly_revenue = int(round(float(rev_sum) / float(rev_n) * float(REVENUE_WINDOW_WEEKS)))
	else:
		GameState.quarterly_revenue = 0

## Funding-round trigger conditions, see 经济系统设计.md §4.6.
## Re-checked at accept-time so a player who lost rank or shipped no model
## between offer-push and accept is denied with `conditions_not_met`.
func _funding_round_conditions_met(round_name: StringName) -> bool:
	match round_name:
		&"pre_seed":
			# Always available at game start — pre-seed is the "founder pitches
			# her idea" round. No external gates.
			return true
		&"seed":
			# 出身系统设计 §5: entrepreneur founder unlocks seed from turn 0.
			return FounderSystem.seed_round_unlocked() or _has_evaluated_model()
		&"a":
			return _player_in_top_n_any_sub_board(3) and _has_published_model() \
					and _has_active_product()
		&"b":
			return _player_first_on_any_sub_board() \
					and _avg_recent_weekly_revenue(3) > 10_000_000
		&"c":
			return _player_in_top_n_any_main_board(3) \
					and _avg_recent_weekly_revenue(3) > 50_000_000
		&"d":
			return _player_in_top_n_any_main_board(3) \
					and _avg_recent_weekly_revenue(3) > 200_000_000
		&"e":
			return _player_first_on_any_main_board() \
					and _avg_recent_weekly_revenue(3) > 1_000_000_000
		&"f":
			return _player_first_on_any_main_board() \
					and _avg_recent_weekly_revenue(3) > 5_000_000_000
	return false

func _player_in_top_n_any_sub_board(n: int) -> bool:
	for board_id in [&"sub_general", &"sub_code", &"sub_reasoning",
			&"sub_multimodal", &"sub_agent"]:
		if _player_in_top_n(GameState.leaderboard.get(board_id, []), n):
			return true
	return false

func _player_first_on_any_sub_board() -> bool:
	return _player_in_top_n_any_sub_board(1)

func _player_in_top_n_any_main_board(n: int) -> bool:
	for board_id in [&"closed_source", &"open_source"]:
		if _player_in_top_n(GameState.leaderboard.get(board_id, []), n):
			return true
	return false

func _player_first_on_any_main_board() -> bool:
	return _player_in_top_n_any_main_board(1)

func _player_in_top_n(entries: Array, n: int) -> bool:
	for entry in entries:
		if entry.entity_type == &"player_model" and int(entry.rank) <= n:
			return true
	return false

func _has_evaluated_model() -> bool:
	for m in GameState.models:
		if m.status == &"evaluated" or m.status == &"published":
			return true
	return false

func _has_published_model() -> bool:
	for m in GameState.models:
		if m.status == &"published":
			return true
	return false

func _has_active_product() -> bool:
	return GameState.products.size() > 0

func _avg_recent_weekly_revenue(weeks: int) -> int:
	if _revenue_history.is_empty():
		return 0
	var n: int = mini(weeks, _revenue_history.size())
	var s: int = 0
	for i in range(n):
		s += int(_revenue_history[i])
	return int(s / max(n, 1))

func _bankruptcy_depth_threshold() -> int:
	var raw: int = -int(round(
			BANKRUPTCY_DEPTH_K * float(maxi(GameState.weekly_burn_rate, 0))
			+ BANKRUPTCY_DEPTH_L * float(maxi(GameState.quarterly_revenue, 0))))
	# raw is <= 0; floor is the more permissive (less negative) of the two so
	# brand-new companies (raw == 0) still tolerate up to -1M.
	return mini(raw, BANKRUPTCY_DEPTH_FLOOR)

func _check_bankruptcy() -> void:
	if GameState.cash < 0:
		GameState.bankruptcy_streak += 1
		EventBus.bankruptcy_warning.emit(&"cash_negative",
				GameState.bankruptcy_streak, BANKRUPTCY_STREAK_LIMIT)
		if GameState.bankruptcy_streak >= BANKRUPTCY_STREAK_LIMIT:
			Log.warn(&"economy", "bankruptcy_triggered", {reason = "cash_negative_too_long"})
			EventBus.bankruptcy_triggered.emit(&"cash_negative_too_long")
			return
	else:
		GameState.bankruptcy_streak = 0
	var threshold: int = _bankruptcy_depth_threshold()
	if GameState.cash < threshold:
		# Per 经济系统设计.md §4.2: depth-too-deep also fires a warning before
		# the trigger, so UI can flash the alert one frame before the run ends.
		EventBus.bankruptcy_warning.emit(&"cash_too_deep",
				GameState.cash, threshold)
		Log.warn(&"economy", "bankruptcy_triggered",
				{reason = "cash_too_deep", cash = GameState.cash, threshold = threshold})
		EventBus.bankruptcy_triggered.emit(&"cash_too_deep")

# ---- taxation (design §4.9) ---------------------------------------------

func _build_non_taxable_categories() -> void:
	_non_taxable_categories.clear()
	for r in NON_TAXABLE_REASONS:
		_non_taxable_categories[_categorize(r)] = true

## 当周经营性净利润 = Σ(应税收入类目) − Σ(可抵扣支出类目)。直接读 weekly_ledger
## (已落账数据), 故写存档安全 — 中途读档不会丢本周已发生的利润。融资 / 债务本金
## 等类目由 _non_taxable_categories 过滤掉。
func _compute_taxable_profit() -> int:
	_ensure_ledger_initialized()
	var ledger: Dictionary = GameState.weekly_ledger
	var income: Dictionary = ledger.get(&"income", {})
	var expense: Dictionary = ledger.get(&"expense", {})
	var profit: int = 0
	for cat in income:
		if not _non_taxable_categories.has(cat):
			profit += int(income[cat])
	for cat in expense:
		if not _non_taxable_categories.has(cat):
			profit -= int(expense[cat])
	return profit

## resolve 阶段、滚动账本之前结税。亏损周累加进结转池且不交税; 盈利周先用结转池
## 抵减, 再按企业税 (免征额上 25%) + AI 税 (1B 门槛上再 20%) 两档征。两档分别落账
## 为支出类目并 emit cash_changed, 财务页自动展示。
func _settle_taxes() -> void:
	var profit: int = _compute_taxable_profit()
	if profit < 0:
		GameState.tax_loss_carryforward += -profit
		Log.debug(&"economy", "tax_loss_accrued",
				{loss = -profit, pool = GameState.tax_loss_carryforward})
		return
	var offset: int = mini(GameState.tax_loss_carryforward, profit)
	GameState.tax_loss_carryforward -= offset
	var net_taxable: int = profit - offset
	var corp_tax: int = 0
	var ai_tax: int = 0
	if net_taxable > CORP_TAX_EXEMPTION:
		corp_tax = int(round(float(net_taxable - CORP_TAX_EXEMPTION) * CORP_TAX_RATE))
	if net_taxable > AI_TAX_THRESHOLD:
		ai_tax = int(round(float(net_taxable - AI_TAX_THRESHOLD) * AI_TAX_RATE))
	if corp_tax > 0:
		_charge_tax(corp_tax, &"corporate_tax")
	if ai_tax > 0:
		_charge_tax(ai_tax, &"ai_ubi_tax")
	if corp_tax > 0 or ai_tax > 0:
		Log.info(&"economy", "taxes_settled",
				{profit = profit, offset = offset, net_taxable = net_taxable,
				 corp_tax = corp_tax, ai_tax = ai_tax})

func _charge_tax(amount: int, reason: StringName) -> void:
	_apply_resource_delta(&"cash", -amount)
	# 记入当周账本 (滚动前), 作为支出类目。reason 在 NON_TAXABLE_REASONS 中,
	# 不会反向影响税基。
	_ledger_track(-amount, reason)
	EventBus.resources_changed.emit({&"money": -amount}, reason)
	EventBus.cash_changed.emit(-amount, reason)

# ---- weekly ledger (design §4.8) ----------------------------------------

func _ensure_ledger_initialized(force_reset: bool = false) -> void:
	if force_reset or not (GameState.weekly_ledger is Dictionary) \
			or not GameState.weekly_ledger.has(&"income"):
		GameState.weekly_ledger = _new_empty_ledger()
	if not (GameState.ledger_history is Array):
		GameState.ledger_history = []

func _new_empty_ledger() -> Dictionary:
	return {income = {}, expense = {}, gross_in = 0, gross_out = 0}

func _ledger_track(delta: int, reason: StringName) -> void:
	if delta == 0:
		return
	_ensure_ledger_initialized()
	var category: String = _categorize(reason)
	var ledger: Dictionary = GameState.weekly_ledger
	if delta > 0:
		var income: Dictionary = ledger.income
		income[category] = int(income.get(category, 0)) + delta
		ledger.gross_in = int(ledger.gross_in) + delta
	else:
		var expense: Dictionary = ledger.expense
		var amount: int = -delta
		expense[category] = int(expense.get(category, 0)) + amount
		ledger.gross_out = int(ledger.gross_out) + amount

func _categorize(reason: StringName) -> String:
	if REASON_CATEGORY.has(reason):
		return String(REASON_CATEGORY[reason])
	var text := String(reason)
	if text.begins_with("event:"):
		return "ECO_CAT_EVENT"
	if text.begins_with("campaign:"):
		return "ECO_CAT_CAMPAIGN"
	return "ECO_CAT_OTHER_EXPENSE"

func _roll_ledger() -> void:
	_ensure_ledger_initialized()
	var snapshot: Dictionary = GameState.weekly_ledger.duplicate(true)
	snapshot[&"turn"] = GameState.turn
	snapshot[&"ending_cash"] = GameState.cash
	GameState.ledger_history.push_front(snapshot)
	while GameState.ledger_history.size() > LEDGER_HISTORY_WEEKS:
		GameState.ledger_history.pop_back()
	GameState.weekly_ledger = _new_empty_ledger()
	EventBus.ledger_rolled.emit(int(snapshot[&"turn"]), snapshot)

# ---- table loading ------------------------------------------------------

func _load_tables() -> void:
	var t := load(TUNING_PATH)
	if t is EconomyTuning:
		BANKRUPTCY_STREAK_LIMIT = int(t.bankruptcy_streak_limit)
		BANKRUPTCY_WARN_STREAK = int(t.bankruptcy_warn_streak)
		BANKRUPTCY_DEPTH_FLOOR = int(t.bankruptcy_depth_floor)
		BANKRUPTCY_DEPTH_K = float(t.bankruptcy_depth_k)
		BANKRUPTCY_DEPTH_L = float(t.bankruptcy_depth_l)
		BASE_INTEREST_RATE = float(t.base_interest_rate)
		MAX_LOAN_BETA = float(t.max_loan_beta)
		MAX_LOAN_GAMMA = float(t.max_loan_gamma)
		if "max_loan_absolute_cap" in t:
			MAX_LOAN_ABSOLUTE_CAP = int(t.max_loan_absolute_cap)
		if "max_loan_term_weeks" in t:
			MAX_LOAN_TERM_WEEKS = int(t.max_loan_term_weeks)
		LOAN_ID_START_YEAR = int(t.loan_id_start_year)
		VALUATION_BASE = int(t.valuation_base)
		VALUATION_MULTIPLIER = float(t.valuation_multiplier)
		VALUATION_CASH_COEF = float(t.valuation_cash_coef)
		if "rank_premium_rank_1" in t: RANK_PREMIUM_RANK_1 = float(t.rank_premium_rank_1)
		if "rank_premium_rank_top3" in t: RANK_PREMIUM_RANK_TOP3 = float(t.rank_premium_rank_top3)
		if "rank_premium_rank_top10" in t: RANK_PREMIUM_RANK_TOP10 = float(t.rank_premium_rank_top10)
		PORTFOLIO_BONUS_PER_MODEL = float(t.portfolio_bonus_per_model)
		FOUNDER_MIN_STAKE = float(t.founder_min_stake)
		BURN_WINDOW_WEEKS = int(t.burn_window_weeks)
		REVENUE_WINDOW_WEEKS = int(t.revenue_window_weeks)
		if "corp_tax_rate" in t: CORP_TAX_RATE = float(t.corp_tax_rate)
		if "corp_tax_exemption" in t: CORP_TAX_EXEMPTION = int(t.corp_tax_exemption)
		if "ai_tax_rate" in t: AI_TAX_RATE = float(t.ai_tax_rate)
		if "ai_tax_threshold" in t: AI_TAX_THRESHOLD = int(t.ai_tax_threshold)
	else:
		Log.warn(&"economy", "tuning_missing", {path = TUNING_PATH})

	FUNDING_ROUND_TABLE.clear()
	for rid in FUNDING_ROUND_ORDER:
		var path: String = FUNDING_ROUND_PATHS.get(rid, "")
		var spec := load(path) if path != "" else null
		if spec is FundingRoundSpec:
			FUNDING_ROUND_TABLE[rid] = {
				amin = int(spec.amount_min),
				amax = int(spec.amount_max),
				dmin = float(spec.dilution_min),
				dmax = float(spec.dilution_max),
				display_name = String(spec.display_name),
				unlock_summary = String(spec.unlock_summary),
			}
		else:
			Log.warn(&"economy", "funding_round_missing", {round = rid})
