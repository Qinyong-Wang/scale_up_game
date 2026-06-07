extends Node

## UserSystem v7 PR-F (2026-05) — owns paid_users + token_demand. Per
## design/用户系统设计.md.
##
## Pure derived calculator. Every action phase, evolves each Product's
## `subscribers` pool with additive weekly rates (rank bonus + price
## elasticity) plus marketing attract and base demand curve attraction.
## Then derives paid_users (= Σ non-api subscribers) and token_demand
## (subscription_part = Σ subs × tokens_per_user_per_week; api_part =
## api_product.subscribers × API_TOKENS_PER_SUB_PER_WEEK). Emits
## `users_resolved` so MonetizationSystem can settle revenue immediately.
##
## v7 PR-F replaces the fame-driven attract/churn from v6. The fame field
## and signal were deleted; this system reads rank, price and marketing
## state instead.


# Table-driven, see design/用户系统设计.md §6. Authoritative source:
# resources/data/user/tuning.tres; loaded into the vars below.
const TUNING_PATH: String = "res://resources/data/user/tuning.tres"

# v7 PR-F: rank bonus rates (additive per-week). v11 (2026-05): 全部 ×0.5。
var TOTAL_RANK_1_RATE: float = 0.01
var TOTAL_RANK_TOP3_RATE: float = 0.0
var TOTAL_RANK_BELOW_RATE: float = -0.02
var SUB_RANK_1_RATE: float = 0.0025
var SUB_RANK_TOP3_RATE: float = 0.0
var SUB_RANK_BELOW_RATE: float = -0.025

# v7 PR-F: piecewise-linear base demand curve.
var BASE_CURVE_KNOT_TURNS: Array[int] = [0, 100, 280, 400]
var BASE_CURVE_KNOT_VALUES: Array[int] = [0, 100, 10_000, 100_000]
var BASE_ATTRACTION_RANK_1: float = 1.0
var BASE_ATTRACTION_RANK_2: float = 0.5
var BASE_ATTRACTION_RANK_3: float = 0.25
var BASE_ATTRACTION_RANK_ELSE: float = 0.0

# API product token unit conversion. Authoritative value is loaded from
# user/tuning.tres; this fallback matches the current 2026-05 x5 rebalance.
var API_TOKENS_PER_SUB_PER_WEEK: int = 10_000_000

# v7 PR-F: orphan product churn (bound model is unpublished or missing).
var ORPHAN_PRODUCT_CHURN: int = 5

# CAC marketing conversion. v12: 0.025 → 0.0125 (CAC $40 → $80, ×2);
# 订阅产品与 API 共用此率。权威源 user/tuning.tres, 这里只是 .tres 缺失时的兜底.
var MARKETING_CONVERSION_RATE: float = 0.0125

# Campaign fake performance-score claim knobs. See design/营销系统设计.md §5.2.
const FAKE_SCORE_CONVERSION_MULT: Dictionary = {
	&"none": 1.0,
	&"low": 1.05,
	&"medium": 1.12,
	&"high": 1.25,
}
const FAKE_SCORE_RETENTION_PENALTY: Dictionary = {
	&"none": 0.0,
	&"low": -0.10,
	&"medium": -0.40,
	&"high": -1.0,
}

# v7 PR-F: API cliff threshold (price-vs-guidance ratio at which API demand
# is zero this week). Matches ResearchSystem.weekly_growth_rate's sentinel.
const API_PRICE_CLIFF_RATIO: float = 2.5

# Per-product-type token usage fallback (used when .tres absent in tests).
# Values reinterpreted as per-week under v6's "1 turn = 1 week" convention.
const TOKENS_PER_USER_FALLBACK: Dictionary = {
	&"chatbot": 250_000,
	&"agent": 10_000_000,
	&"multimodal_assistant": 1_250_000,
	&"coding_agent": 1_000_000_000,
}

# Caches populated lazily.
var _tokens_per_user_cache: Dictionary = {}
var _product_type_spec_cache: Dictionary = {}

func _ready() -> void:
	_load_tables()
	CommandBus.register(&"user.preview_demand", _on_preview_demand)
	CommandBus.register(&"user.recompute_now", _on_recompute_now)
	EventBus.phase_started.connect(_on_phase)

func _load_tables() -> void:
	var t := load(TUNING_PATH)
	if not (t is UserTuning):
		Log.warn(&"user", "tuning_missing", {path = TUNING_PATH})
		return
	# v7 PR-F new knobs (guard each field; old .tres won't have them).
	if "total_rank_1_rate" in t: TOTAL_RANK_1_RATE = float(t.total_rank_1_rate)
	if "total_rank_top3_rate" in t: TOTAL_RANK_TOP3_RATE = float(t.total_rank_top3_rate)
	if "total_rank_below_rate" in t: TOTAL_RANK_BELOW_RATE = float(t.total_rank_below_rate)
	if "sub_rank_1_rate" in t: SUB_RANK_1_RATE = float(t.sub_rank_1_rate)
	if "sub_rank_top3_rate" in t: SUB_RANK_TOP3_RATE = float(t.sub_rank_top3_rate)
	if "sub_rank_below_rate" in t: SUB_RANK_BELOW_RATE = float(t.sub_rank_below_rate)
	if "base_curve_knot_turns" in t and (t.base_curve_knot_turns as Array).size() > 0:
		BASE_CURVE_KNOT_TURNS = (t.base_curve_knot_turns as Array[int]).duplicate()
	if "base_curve_knot_values" in t and (t.base_curve_knot_values as Array).size() > 0:
		BASE_CURVE_KNOT_VALUES = (t.base_curve_knot_values as Array[int]).duplicate()
	if "base_attraction_rank_1" in t: BASE_ATTRACTION_RANK_1 = float(t.base_attraction_rank_1)
	if "base_attraction_rank_2" in t: BASE_ATTRACTION_RANK_2 = float(t.base_attraction_rank_2)
	if "base_attraction_rank_3" in t: BASE_ATTRACTION_RANK_3 = float(t.base_attraction_rank_3)
	if "base_attraction_rank_else" in t: BASE_ATTRACTION_RANK_ELSE = float(t.base_attraction_rank_else)
	if "api_tokens_per_sub_per_week" in t: API_TOKENS_PER_SUB_PER_WEEK = int(t.api_tokens_per_sub_per_week)
	if "orphan_product_churn" in t: ORPHAN_PRODUCT_CHURN = int(t.orphan_product_churn)
	MARKETING_CONVERSION_RATE = float(t.marketing_conversion_rate)

# ---- commands -----------------------------------------------------------

func _on_preview_demand(p: Dictionary) -> Dictionary:
	var model_id: StringName = p.get(&"model_id", &"")
	var m = _find_model(model_id)
	if m == null:
		return {ok = false, error = &"unknown_model"}
	return {ok = true, predicted = _compute_demand_for_model(m)}

func _on_recompute_now(_p: Dictionary) -> Dictionary:
	_resolve_action()
	return {ok = true}

# ---- phase --------------------------------------------------------------

func _on_phase(phase: StringName, _turn: int) -> void:
	if phase == &"action":
		_resolve_action()

func _resolve_action() -> void:
	var old_paid_users: int = GameState.paid_users
	_resolve_per_product()
	_recompute_paid_users()
	_recompute_token_demand()
	GameState.last_user_resolved_turn = GameState.turn
	var delta: int = GameState.paid_users - old_paid_users
	EventBus.users_resolved.emit(GameState.turn, delta)

## v7 PR-F core: every product (incl. api) evolves its subscribers pool
## via additive weekly rates (rank + price) + marketing + base attraction.
## API products with price ≥ 2.5× guidance hit a hard cliff: subscribers
## drop to 0 for that week, with no base/marketing recovery added — the
## price has to come back down before the pool can grow again.
func _resolve_per_product() -> void:
	for p in GameState.products:
		var m = _find_model(p.bound_model_id)
		if m == null or m.status != &"published":
			# Orphan: slowly churn down so the UI eventually clears.
			if p.subscribers > 0:
				var orphan_delta: int = -min(p.subscribers, ORPHAN_PRODUCT_CHURN)
				CommandBus.send(&"product.update_subscribers", {
					product_id = p.id, delta = orphan_delta,
				})
			continue

		var total_rank: int = _market_rank(m, &"total")

		# API cliff: price ≥ 2.5 × guidance → zero out this week.
		if "type" in p and p.type == &"api" and _api_price_ratio(m) >= API_PRICE_CLIFF_RATIO:
			if p.subscribers > 0:
				CommandBus.send(&"product.update_subscribers", {
					product_id = p.id, delta = -p.subscribers,
				})
			continue

		var rate: float = _rank_rate(m, total_rank, p.type) \
				+ _price_rate(p, m) \
				+ _capability_penalty(m, p.type) \
				+ _fake_score_retention_penalty_for_product(p)
		var pool_delta: int = int(round(float(p.subscribers) * rate))
		var attract: int = _marketing_attract(p)
		var base: int = _base_attraction(GameState.turn, total_rank)
		var delta: int = pool_delta + attract + base
		# 出身系统设计 §5: influencer founder accelerates positive growth
		# only — a shrinking pool is never amplified.
		if delta > 0:
			delta = int(round(float(delta) * FounderSystem.user_growth_multiplier()))
		# Pool floored at 0 (never negative).
		if p.subscribers + delta < 0:
			delta = -p.subscribers
		if delta != 0:
			CommandBus.send(&"product.update_subscribers", {
				product_id = p.id, delta = delta,
			})

## v7 PR-F: paid_users counts only non-api subscribers. API product
## subscribers are demand-pool units, not real users.
func _recompute_paid_users() -> void:
	var old: int = GameState.paid_users
	var total: int = 0
	for p in GameState.products:
		if "type" in p and p.type == &"api":
			continue
		total += p.subscribers
	GameState.paid_users = total
	if total != old:
		EventBus.paid_users_changed.emit(total - old, total)

## v7 PR-F: token_demand split:
##   subscription_part = Σ over non-api products bound to m:  subs × tokens_per_week(type)
##   api_part           = Σ over api products bound to m:      subs × API_TOKENS_PER_SUB_PER_WEEK
func _recompute_token_demand() -> void:
	var new_total: Dictionary = {}
	var new_api: Dictionary = {}
	for m in GameState.models:
		if m.status != &"published":
			continue
		var split: Dictionary = _compute_demand_split_for_model(m)
		new_total[m.id] = int(split.total)
		new_api[m.id] = int(split.api)
	for mid in new_total.keys():
		if int(GameState.token_demand.get(mid, -1)) != int(new_total[mid]):
			EventBus.token_demand_changed.emit(mid, int(new_total[mid]))
	for mid in GameState.token_demand.keys():
		if not new_total.has(mid):
			EventBus.token_demand_changed.emit(mid, 0)
	GameState.token_demand = new_total
	GameState.api_token_demand = new_api

## Pure derivation: splits the published model's token demand into
## subscription vs api parts (both from product.subscribers, NOT fame).
## v7 PR-F: trailing args kept for back-compat with v6 callers but ignored.
func _compute_demand_split_for_model(m, _fame: float = -1.0, _mutate: bool = false) -> Dictionary:
	var subscription_part: int = 0
	var api_part: int = 0
	for prod in GameState.products:
		if prod.bound_model_id != m.id:
			continue
		if "type" in prod and prod.type == &"api":
			api_part += prod.subscribers * API_TOKENS_PER_SUB_PER_WEEK
		else:
			subscription_part += prod.subscribers * _tokens_per_user_for(prod.type)
	return {
		total = subscription_part + api_part,
		api = api_part,
		subscription = subscription_part,
	}

## Backward-compat: legacy callers (preview, tests) that just want total.
func _compute_demand_for_model(m, _fame: float = -1.0) -> int:
	return int(_compute_demand_split_for_model(m).total)

# ---- v7 PR-F3 public introspection -------------------------------------

## UI helper: breakdown of a product's weekly evolution into its component
## rates + absolute external boosts. Used by product_view 卡片 to show why a
## product is growing or shrinking. Mirrors _resolve_per_product()'s math.
##
## Returns:
## ```
## {
##   total_rate: float,           # 总加法率 (rank_rate + price_rate + capability_penalty)
##   total_rank: int,             # 0 = 不在榜 (treat as #4+)
##   total_rank_rate: float,      # 总榜单独贡献 (仅展示)
##   sub_board: StringName,       # &"" 表示无对应子榜
##   sub_rank: int,
##   sub_rank_rate: float,        # 子榜单独贡献 (仅展示)
##   rank_rate: float,            # v10 实际采用值 = max(total_rank_rate, sub_rank_rate)
##   price_rate: float,
##   capability_penalty: float,   # v10 能力门槛惩罚 (≤ 0)
##   marketing_attract: int,      # 绝对每周新增 (subscribers / demand 单位)
##   base_attraction: int,        # 绝对每周新增 (subscribers / demand 单位)
##   is_orphan: bool,             # bound model 缺失 → orphan churn
##   is_api_cliff: bool,          # api 价格 ≥ 2.5× guidance → 本周清零
## }
## ```
func compute_rate_breakdown(p) -> Dictionary:
	var out: Dictionary = {
		total_rate = 0.0,
		total_rank = 0,
		total_rank_rate = 0.0,
		sub_board = &"",
		sub_rank = 0,
		sub_rank_rate = 0.0,
		rank_rate = 0.0,
		price_rate = 0.0,
		capability_penalty = 0.0,
		fake_score_retention_penalty = 0.0,
		marketing_attract = 0,
		base_attraction = 0,
		is_orphan = false,
		is_api_cliff = false,
	}
	var m = _find_model(p.bound_model_id) if "bound_model_id" in p else null
	if m == null or m.status != &"published":
		out.is_orphan = true
		return out
	out.total_rank = _market_rank(m, &"total")
	out.total_rank_rate = _total_rank_rate(out.total_rank)
	out.sub_board = MarketSystem.SUB_BOARD_FOR_PRODUCT_TYPE.get(p.type, &"")
	if out.sub_board != &"":
		out.sub_rank = _market_rank(m, out.sub_board)
		out.sub_rank_rate = _sub_rank_rate(m, p.type)
	# v10: 实际采用的 rank rate = 总榜/子榜较优 (不叠加)。
	out.rank_rate = _rank_rate(m, out.total_rank, p.type)
	# API cliff: 价格 ≥ 2.5× guidance → 强制 0, 不进 rate。
	if "type" in p and p.type == &"api" and _api_price_ratio(m) >= API_PRICE_CLIFF_RATIO:
		out.is_api_cliff = true
		return out
	out.price_rate = _price_rate(p, m)
	out.capability_penalty = _capability_penalty(m, p.type)
	out.fake_score_retention_penalty = _fake_score_retention_penalty_for_product(p)
	out.total_rate = out.rank_rate + out.price_rate + out.capability_penalty \
			+ out.fake_score_retention_penalty
	out.marketing_attract = _marketing_attract(p)
	out.base_attraction = _base_attraction(GameState.turn, out.total_rank)
	return out

# ---- v7 PR-F helpers ----------------------------------------------------

## 1-based rank on a leaderboard, COUNTING NPC competitors only (v10): the
## player's own other published models don't push this one down — a company
## doesn't compete with itself. 0 when not on board (treated like rank ≥ 4).
func _market_rank(m, board_id: StringName) -> int:
	return MarketSystem.get_rank_vs_npcs(m.id, board_id)

func _total_rank_rate(rank: int) -> float:
	if rank == 1:
		return TOTAL_RANK_1_RATE
	if rank == 2 or rank == 3:
		return TOTAL_RANK_TOP3_RATE
	return TOTAL_RANK_BELOW_RATE

func _sub_rank_rate(m, product_type: StringName) -> float:
	var sub_board: StringName = MarketSystem.SUB_BOARD_FOR_PRODUCT_TYPE.get(product_type, &"")
	if sub_board == &"":
		return 0.0
	var rank: int = _market_rank(m, sub_board)
	if rank == 1:
		return SUB_RANK_1_RATE
	if rank == 2 or rank == 3:
		return SUB_RANK_TOP3_RATE
	return SUB_RANK_BELOW_RATE

## v10 §5.2: rank rate is the BETTER of total-board vs sub-board, not the sum.
## A model that's #1 on its sub-board but #5 overall keeps the sub-board's
## +0.5%, instead of being dragged to +0.5% − 4% = −3.5%.
func _rank_rate(m, total_rank: int, product_type: StringName) -> float:
	var total_rate: float = _total_rank_rate(total_rank)
	var sub_board: StringName = MarketSystem.SUB_BOARD_FOR_PRODUCT_TYPE.get(product_type, &"")
	if sub_board == &"":
		return total_rate
	return maxf(total_rate, _sub_rank_rate(m, product_type))

## v10 §5.2bis: per-product-type capability gate. A product bound to a model
## whose relevant capability axis is below the type's thresholds suffers a flat
## weekly subscriber penalty — stops the "tiny weak model + huge ad spend" hack.
func _capability_penalty(m, product_type: StringName) -> float:
	var spec: ProductTypeSpec = _product_type_spec(product_type)
	if spec == null or not ("capability_penalty_axis" in spec):
		return 0.0
	var axis: StringName = spec.capability_penalty_axis
	if axis == &"":
		return 0.0
	var cap_value: float = float(m.capability.get(axis, 0.0))
	return _penalty_from_tiers(spec.capability_penalty_tiers, cap_value)

## Pure helper (also used by tests / UI preview): resolves the penalty rate for
## a given product type at a given capability value. Picks the most negative
## (worst) applicable tier.
func _capability_penalty_for(product_type: StringName, cap_value: float) -> float:
	var spec: ProductTypeSpec = _product_type_spec(product_type)
	if spec == null or not ("capability_penalty_axis" in spec) \
			or spec.capability_penalty_axis == &"":
		return 0.0
	return _penalty_from_tiers(spec.capability_penalty_tiers, cap_value)

func _penalty_from_tiers(tiers, cap_value: float) -> float:
	if not (tiers is Array):
		return 0.0
	var penalty: float = 0.0
	for tier in tiers:
		if not (tier is Dictionary):
			continue
		if cap_value < float(tier.get("below", 0.0)):
			penalty = minf(penalty, float(tier.get("rate", 0.0)))
	return penalty

func _price_rate(p, m) -> float:
	if "type" in p and p.type == &"api":
		# guidance_price_per_token returns 0 only when the model has no
		# computable fpt (defensive). In that case skip elasticity entirely.
		if ResearchSystem.guidance_price_per_token(m) <= 0.0:
			return 0.0
		# r = price / guidance; r=0 (giving it away) is a valid +4% growth case
		# and must hit the piecewise function, not be early-returned to 0.
		return _piecewise_price_rate(_api_price_ratio(m))
	# Subscription product: r = subscription_price / subscription_price_guidance.
	var spec: ProductTypeSpec = _product_type_spec(p.type)
	if spec == null:
		return 0.0
	var guidance: float = 0.0
	if "subscription_price_guidance" in spec:
		guidance = float(spec.subscription_price_guidance)
	if guidance <= 0.0:
		return 0.0
	var r2: float = float(p.subscription_price) / guidance
	return _piecewise_price_rate(r2)

func _api_price_ratio(m) -> float:
	# ResearchSystem owns the base/guidance computation.
	var guidance: float = ResearchSystem.guidance_price_per_token(m)
	if guidance <= 0.0:
		return 0.0
	return float(m.per_token_price) / guidance

## v7 PR-F piecewise price elasticity. v11 (2026-05): 各档百分比 ×0.5。
##   r ≤ 0.6:   +2% (cap)
##   r ≤ 1.0:   linear 0.05 − 0.05·r  (0.6→+2%, 1.0→0)
##   r ≤ 2.5:   linear -0.10·(r−1.0)  (1.0→0, 1.5→−5%, 2.0→−10%)
##   r >  2.5:  −25% (cap; api cliff in _resolve_per_product overrides this)
func _piecewise_price_rate(r: float) -> float:
	if r <= 0.6:
		return 0.02
	if r <= 1.0:
		return 0.05 - 0.05 * r
	if r <= 2.5:
		return -0.10 * (r - 1.0)
	return -0.25

func _marketing_attract(p) -> int:
	var boost: float = 0.0
	for c in GameState.campaigns:
		if _campaign_targets_product(c, p):
			boost += float(c.weekly_budget) * MARKETING_CONVERSION_RATE \
					* _campaign_efficiency_multiplier(c) \
					* fake_score_conversion_multiplier(_campaign_fake_score_level(c))
	# 慈善系统设计 §6: social_welfare 捐助直接抬高营销转化率 (中性 1.0)。这条同时
	# 进实际拉新与预览 (out.marketing_attract 复用本函数), 显示与实际一致。
	return int(round(boost * CharitySystem.conversion_multiplier()))

func fake_score_conversion_multiplier(level: StringName) -> float:
	return float(FAKE_SCORE_CONVERSION_MULT.get(
			Campaign.normalize_fake_score_level(level), 1.0))

func fake_score_retention_penalty(level: StringName) -> float:
	return float(FAKE_SCORE_RETENTION_PENALTY.get(
			Campaign.normalize_fake_score_level(level), 0.0))

func _fake_score_retention_penalty_for_product(p) -> float:
	var penalty: float = 0.0
	for c in GameState.campaigns:
		if _campaign_targets_product(c, p):
			penalty += fake_score_retention_penalty(_campaign_fake_score_level(c))
	return clampf(penalty, -1.0, 0.0)

func _campaign_fake_score_level(c) -> StringName:
	var level: StringName = c.fake_score_level if "fake_score_level" in c else &"none"
	return Campaign.normalize_fake_score_level(level)

func _campaign_efficiency_multiplier(c) -> float:
	if not ("lead_id" in c) or c.lead_id == &"":
		return 1.0
	var lead = HiringSystem.find_lead(c.lead_id)
	if lead == null or lead.specialty != &"marketing_lead":
		return 1.0
	var table: Dictionary = HiringSystem.LEAD_BONUS_TABLE.get(&"marketing_lead", {})
	var coef: float = float(table.get(&"campaign_efficiency", 0.0))
	return 1.0 + (float(lead.ability) / 100.0) * coef

## v7 PR-F3: campaign 一对一锁 product。匹配条件就是 target_product_id == p.id。
## 旧存档没 target_product_id 的 campaign 会被 MarketingSystem 在 upkeep 扫到时
## 当孤儿终止, 这里不再走 types / segment fallback。
func _campaign_targets_product(c, prod) -> bool:
	var target: StringName = c.target_product_id if "target_product_id" in c else &""
	if target == &"":
		return false
	return target == prod.id

func _base_attraction(turn: int, total_rank: int) -> int:
	var factor: float = _base_attraction_rank_factor(total_rank)
	if factor <= 0.0:
		return 0
	return int(round(_base_demand_curve(turn) * factor))

func _base_attraction_rank_factor(rank: int) -> float:
	if rank == 1:
		return BASE_ATTRACTION_RANK_1
	if rank == 2:
		return BASE_ATTRACTION_RANK_2
	if rank == 3:
		return BASE_ATTRACTION_RANK_3
	return BASE_ATTRACTION_RANK_ELSE

## Piecewise-linear base demand curve. Below the first knot returns the
## first value; above the last knot returns the last value (saturation).
func _base_demand_curve(turn: int) -> float:
	var turns: Array = BASE_CURVE_KNOT_TURNS
	var values: Array = BASE_CURVE_KNOT_VALUES
	if turns.is_empty() or values.is_empty():
		return 0.0
	if turn <= int(turns[0]):
		return float(values[0])
	var last_idx: int = turns.size() - 1
	if turn >= int(turns[last_idx]):
		return float(values[last_idx])
	for i in range(last_idx):
		var t0: int = int(turns[i])
		var t1: int = int(turns[i + 1])
		if t0 <= turn and turn < t1:
			var frac: float = float(turn - t0) / float(t1 - t0)
			return lerp(float(values[i]), float(values[i + 1]), frac)
	return 0.0

func _product_type_spec(product_type: StringName):
	if _product_type_spec_cache.has(product_type):
		return _product_type_spec_cache[product_type]
	var path: String = "res://resources/data/products/types/%s.tres" % String(product_type)
	var spec = null
	if ResourceLoader.exists(path):
		var res := load(path)
		if res is ProductTypeSpec:
			spec = res
	_product_type_spec_cache[product_type] = spec
	return spec

## v7 PR-F: prefers `tokens_per_user_per_week` field; falls back to legacy
## `tokens_per_user_per_month` (v6 already reinterpreted that field as
## per-week under "1 turn = 1 week"). Final fallback to hard-coded table.
func _tokens_per_user_for(product_type: StringName) -> int:
	if _tokens_per_user_cache.has(product_type):
		return int(_tokens_per_user_cache[product_type])
	var value: int = 0
	var spec: ProductTypeSpec = _product_type_spec(product_type)
	if spec != null:
		var per_week: int = int(spec.tokens_per_user_per_week) if "tokens_per_user_per_week" in spec else 0
		if per_week > 0:
			value = per_week
		else:
			value = int(spec.tokens_per_user_per_month)
	if value <= 0 and TOKENS_PER_USER_FALLBACK.has(product_type):
		value = int(TOKENS_PER_USER_FALLBACK[product_type])
	_tokens_per_user_cache[product_type] = value
	return value

func _find_model(model_id: StringName):
	for m in GameState.models:
		if m.id == model_id:
			return m
	return null
