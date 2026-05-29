extends GutTest

## v7 PR-F (2026-05) — UserSystem demand mechanics covering rank bonuses,
## base demand curve, and api product subscriber → token demand conversion.
## Per design/用户系统设计.md §5-6 + design/平衡参数.md §UserSystem.
##
## Companion to demand_elasticity_test.gd (which covers price elasticity +
## the api cliff). Here we focus on:
##   - total/sub rank bonus → weekly subscriber pool rate
##   - base_demand_curve(turn) interpolation + rank-factor scaling
##   - api_product.subscribers → api_token_demand conversion
##   - paid_users excludes api products


func before_each() -> void:
	GameState.reset()
	GameState.turn = 0

# ---- helpers ------------------------------------------------------------

## Adds a published model with given capability. Auto-creates the api product
## via ProductSystem._on_model_published listener.
func _publish_model(mid: StringName, cap: Dictionary, is_open: bool = false) -> Model:
	var m := Model.new()
	m.id = mid
	m.arch = &"ant_v1"
	m.status = &"published"
	m.capability = cap
	m.is_open_source = is_open
	m.flops_per_token = 1.4e10  # 7B baseline
	GameState.models.append(m)
	# Manually emit so ProductSystem auto-creates the api product.
	EventBus.model_published.emit(m.id, is_open)
	return m

func _api_product_for(model_id: StringName) -> Product:
	for p in GameState.products:
		if p.bound_model_id == model_id and "type" in p and p.type == &"api":
			return p
	return null

func _resolve_leaderboards() -> void:
	# Force a leaderboard recompute so get_rank reflects current capabilities.
	# Triggering action phase rebuilds all 8 boards.
	EventBus.phase_started.emit(&"action", GameState.turn)

# ---- §5.2 rank-rate piecewise (pure-function pin-down) -----------------

func test_total_rank_rate_pin_values() -> void:
	# Per design/用户系统设计.md §5.2 (v11 ×0.5): total #1 = +1%/wk, top 3 = 0,
	# below = -2%/wk (incl. rank 0 = "not on board").
	assert_almost_eq(UserSystem._total_rank_rate(1), 0.01, 1e-9)
	assert_almost_eq(UserSystem._total_rank_rate(2), 0.0, 1e-9)
	assert_almost_eq(UserSystem._total_rank_rate(3), 0.0, 1e-9)
	assert_almost_eq(UserSystem._total_rank_rate(4), -0.02, 1e-9)
	assert_almost_eq(UserSystem._total_rank_rate(99), -0.02, 1e-9)
	assert_almost_eq(UserSystem._total_rank_rate(0), -0.02, 1e-9,
			"rank=0 (not on board) maps to BELOW rate")

func test_sub_rank_rate_pin_values() -> void:
	# Per §5.2: sub #1 = +0.5%/wk, top 3 = 0, below = -5%/wk.
	# Map chatbot → sub_general so the function has a real sub board id.
	# We have to fabricate a model that returns specific ranks; instead use
	# a different approach: directly check the formula by emulating ranks.
	# Easier: trust _total_rank_rate's piecewise (already pinned above) and
	# call _sub_rank_rate via product-type plumbing using a Model whose
	# capability we tune to land at the desired sub_general rank.
	#
	# But we don't need that here — the sub piecewise is constants:
	# the _sub_rank_rate function returns SUB_RANK_1_RATE / TOP3 / BELOW
	# directly based on the rank int it derives from MarketSystem. The
	# values themselves are what we want to pin:
	# v11 ×0.5: sub #1 = +0.25%/wk, below = -2.5%/wk.
	assert_almost_eq(UserSystem.SUB_RANK_1_RATE, 0.0025, 1e-9)
	assert_almost_eq(UserSystem.SUB_RANK_TOP3_RATE, 0.0, 1e-9)
	assert_almost_eq(UserSystem.SUB_RANK_BELOW_RATE, -0.025, 1e-9)

func test_sub_board_mapping_for_product_types() -> void:
	# Per design/平衡参数.md §UserSystem: chatbot→general, agent→agent,
	# multimodal_assistant→multimodal, coding_agent→code, api→general default.
	var m: Dictionary = MarketSystem.SUB_BOARD_FOR_PRODUCT_TYPE
	assert_eq(StringName(m.get(&"chatbot", &"")), &"sub_general")
	assert_eq(StringName(m.get(&"agent", &"")), &"sub_agent")
	assert_eq(StringName(m.get(&"multimodal_assistant", &"")), &"sub_multimodal")
	assert_eq(StringName(m.get(&"coding_agent", &"")), &"sub_code")
	assert_eq(StringName(m.get(&"api", &"")), &"sub_general")

func test_piecewise_price_rate_pin_values() -> void:
	# Per design/用户系统设计.md §5.3 (v11 ×0.5): r ≤ 0.6 → +2%;
	# r ≤ 1.0 → 0.05 - 0.05×r; r ≤ 2.5 → -0.10 × (r-1); r > 2.5 → cap at -25%.
	assert_almost_eq(UserSystem._piecewise_price_rate(0.0), 0.02, 1e-9)
	assert_almost_eq(UserSystem._piecewise_price_rate(0.6), 0.02, 1e-9)
	assert_almost_eq(UserSystem._piecewise_price_rate(0.8), 0.01, 1e-9)
	assert_almost_eq(UserSystem._piecewise_price_rate(0.9), 0.005, 1e-9)
	assert_almost_eq(UserSystem._piecewise_price_rate(1.0), 0.0, 1e-9)
	assert_almost_eq(UserSystem._piecewise_price_rate(1.5), -0.05, 1e-9)
	assert_almost_eq(UserSystem._piecewise_price_rate(2.0), -0.10, 1e-9)
	assert_almost_eq(UserSystem._piecewise_price_rate(2.5), -0.15, 1e-9)
	assert_almost_eq(UserSystem._piecewise_price_rate(5.0), -0.25, 1e-9,
			"runaway overprice caps at -25%/wk for subscription products")

func test_product_type_guidance_prices() -> void:
	# Per design/产品系统设计.md §3: chatbot ¥5/wk, coding ¥50/wk.
	var chatbot = load("res://resources/data/products/types/chatbot.tres")
	var coding = load("res://resources/data/products/types/coding_agent.tres")
	assert_eq(int(chatbot.subscription_price_guidance), 5)
	assert_eq(int(coding.subscription_price_guidance), 50)

# ---- §5.2 total_rank_rate ----------------------------------------------

func test_total_rank_1_grows_pool_by_2pct() -> void:
	# Massive capability → guaranteed #1 on `total` board.
	var m: Model = _publish_model(&"m_top", {
		&"general": 1e6, &"code": 1e6, &"reasoning": 1e6,
		&"multimodal": 1e6, &"agent": 1e6,
	})
	var ap: Product = _api_product_for(m.id)
	assert_not_null(ap, "ProductSystem should auto-create the api product")
	ap.subscribers = 1000
	# Set price below guidance so price_rate doesn't muddy the rank assertion.
	m.per_token_price = 0.0
	GameState.turn = 1
	EventBus.phase_started.emit(&"action", 1)
	# v11 Rate = max(+0.01 total #1, +0.0025 sub #1) + 0.02 (price 0 vs guidance) = +0.03
	# Pool delta = 1000 × 0.03 = 30. Plus base_attraction at turn=1 (~1).
	# Expected ~1031. Allow generous bounds.
	assert_gt(ap.subscribers, 1020, "rank #1 + 0-price should grow pool")
	assert_lt(ap.subscribers, 1060)

func test_no_rank_decays_pool() -> void:
	# Weak model: rank ≥4 on every board. v11 rank rate = max(-2% total,
	# -2.5% sub) = -2%/wk (×0.5 from v10). api product → no capability
	# penalty. At guidance price (price_rate = 0) the pool decays -2%/wk.
	# v10: UserSystem ranks vs NPC competitors only — seed 4 dominant NPCs so
	# m_low sits at rank ≥5 on every board (player fillers no longer count).
	for i in range(4):
		_seed_npc_competitor(StringName("npc_comp_%d" % i), {
			general = 1e6, code = 1e6, reasoning = 1e6,
			multimodal = 1e6, agent = 1e6,
		})
	var m: Model = _publish_model(&"m_low", {&"general": 0.01})
	var ap: Product = _api_product_for(m.id)
	assert_not_null(ap)
	ap.subscribers = 1000
	# Pin price at guidance so the price contribution is exactly 0.
	m.per_token_price = ResearchSystem.guidance_price_per_token(m)
	GameState.turn = 1
	EventBus.phase_started.emit(&"action", 1)
	# Rate = max(-0.02, -0.025) + 0 = -0.02 → ~980 (no base because rank > 3).
	assert_gt(ap.subscribers, 960)
	assert_lt(ap.subscribers, 995)

# ---- §5.5 base_demand_curve --------------------------------------------

func test_base_curve_returns_zero_at_turn_0() -> void:
	# Curve knot (0, 0). Empty pool, rank 1 → still 0 from the curve at turn 0.
	var m: Model = _publish_model(&"m_top0", {
		&"general": 1e6, &"code": 1e6, &"reasoning": 1e6,
		&"multimodal": 1e6, &"agent": 1e6,
	})
	var ap: Product = _api_product_for(m.id)
	ap.subscribers = 0
	m.per_token_price = ResearchSystem.guidance_price_per_token(m)  # price_rate = 0
	GameState.turn = 0
	EventBus.phase_started.emit(&"action", 0)
	# Pool stays at 0 (no rate effect, no base seed).
	assert_eq(ap.subscribers, 0)

func test_base_demand_curve_interpolation() -> void:
	# Pure-function test of the piecewise-linear curve. Defaults from
	# UserTuning: knots (0, 0) → (100, 100) → (280, 10_000) → (400, 100_000).
	# Below first knot and above last knot saturate at the edge values.
	assert_almost_eq(UserSystem._base_demand_curve(0), 0.0, 1.0)
	assert_almost_eq(UserSystem._base_demand_curve(50), 50.0, 1.0,
			"midway between knots 0 and 100 → 50")
	assert_almost_eq(UserSystem._base_demand_curve(100), 100.0, 1.0)
	assert_almost_eq(UserSystem._base_demand_curve(280), 10_000.0, 1.0)
	assert_almost_eq(UserSystem._base_demand_curve(400), 100_000.0, 1.0)
	assert_almost_eq(UserSystem._base_demand_curve(500), 100_000.0, 1.0,
			"above last knot saturates at 100_000")

func test_base_attraction_rank_factors() -> void:
	# rank=1 → full curve; rank=2 → 0.5×; rank=3 → 0.25×; rank ≥4 → 0.
	# Pick turn 280 (curve value 10_000) and check the four ranks.
	var v: float = UserSystem._base_demand_curve(280)
	assert_almost_eq(UserSystem._base_attraction(280, 1), v, 2.0)
	assert_almost_eq(UserSystem._base_attraction(280, 2), v * 0.5, 2.0)
	assert_almost_eq(UserSystem._base_attraction(280, 3), v * 0.25, 2.0)
	assert_eq(UserSystem._base_attraction(280, 4), 0)
	assert_eq(UserSystem._base_attraction(280, 0), 0,
			"rank=0 (not on board) maps to else factor = 0")

func test_base_curve_no_seed_for_rank_below_3() -> void:
	# Even at turn = 280 (curve = 10K), a #4+ model gets factor 0.0 → no base.
	var m: Model = _publish_model(&"m_low_late", {&"general": 0.01})
	var ap: Product = _api_product_for(m.id)
	ap.subscribers = 0
	m.per_token_price = ResearchSystem.guidance_price_per_token(m)
	GameState.turn = 280
	EventBus.phase_started.emit(&"action", 280)
	# Pool stays 0: rate × 0 = 0 (no existing subs), base × 0 (rank factor) = 0.
	assert_eq(ap.subscribers, 0)

# ---- §5.7 api_token_demand conversion ----------------------------------

func test_api_token_demand_proportional_to_api_subscribers() -> void:
	# api_token_demand[m] = api_product.subscribers × API_TOKENS_PER_SUB_PER_WEEK.
	# Note: user.recompute_now drives _resolve_per_product first (evolving
	# subscribers via rate), then _recompute_token_demand. The demand
	# reflects the POST-evolution subscriber count.
	var m: Model = _publish_model(&"m_api", {&"general": 50.0})
	var ap: Product = _api_product_for(m.id)
	ap.subscribers = 250
	CommandBus.send(&"user.recompute_now", {})
	# Verify the ratio holds, regardless of exact subscriber count after evolution.
	var subs_after: int = ap.subscribers
	assert_eq(int(GameState.api_token_demand.get(m.id, 0)),
			subs_after * UserSystem.API_TOKENS_PER_SUB_PER_WEEK)

func test_api_token_demand_zero_when_api_product_pool_empty() -> void:
	var m: Model = _publish_model(&"m_empty", {&"general": 50.0})
	var ap: Product = _api_product_for(m.id)
	ap.subscribers = 0
	CommandBus.send(&"user.recompute_now", {})
	assert_eq(int(GameState.api_token_demand.get(m.id, 0)), 0)

# ---- §5.6 paid_users excludes api product subscribers ------------------

func test_paid_users_excludes_api_product_subscribers() -> void:
	# Even with a huge api product pool, paid_users only counts non-api subs.
	# Note: user.recompute_now runs _resolve_per_product so the chatbot
	# subscriber count may evolve slightly via rank+price rate; the key
	# invariant is that paid_users is in the chatbot's order of magnitude,
	# NOT in the api pool's (which is 99_999).
	var m: Model = _publish_model(&"m_x", {&"general": 50.0})
	var ap: Product = _api_product_for(m.id)
	ap.subscribers = 99_999
	# Add a real subscription product with a few subs.
	var p := Product.new()
	p.id = &"p_chat"
	p.type = &"chatbot"
	p.bound_model_id = m.id
	p.subscription_price = 5  # at guidance, so price_rate = 0
	p.subscribers = 42
	GameState.products.append(p)
	CommandBus.send(&"user.recompute_now", {})
	# Should be near 42 (the chatbot subscribers), nowhere near the api pool.
	assert_lt(GameState.paid_users, 100,
			"paid_users must NOT include api product subscribers")
	assert_eq(GameState.paid_users, p.subscribers,
			"paid_users equals the chatbot's post-tick subscriber count")

# ---- §5.6 orphan product churn -----------------------------------------

func test_orphan_product_churns_when_model_unpublished() -> void:
	# Product bound to a model that doesn't exist → orphan path: -5/wk.
	var p := Product.new()
	p.id = &"p_orphan"
	p.type = &"chatbot"
	p.bound_model_id = &"no_such_model"
	p.subscribers = 100
	GameState.products.append(p)
	EventBus.phase_started.emit(&"action", 1)
	assert_eq(p.subscribers, 95, "orphan churn = ORPHAN_PRODUCT_CHURN per week")

func test_orphan_product_never_goes_below_zero() -> void:
	var p := Product.new()
	p.id = &"p_orphan2"
	p.type = &"chatbot"
	p.bound_model_id = &"none"
	p.subscribers = 3
	GameState.products.append(p)
	EventBus.phase_started.emit(&"action", 1)
	assert_eq(p.subscribers, 0, "orphan churn clamps at 0")

# ---- §5.4 marketing attract --------------------------------------------

func test_marketing_attract_grows_chatbot_pool() -> void:
	# v7 PR-F3: campaign 锁单 product。rank 0 → -4.5% rate (v11 ×0.5); with $40k/wk × 0.0125
	# = 500 attract (v12 CAC ×2), pool gains net.
	var m: Model = _publish_model(&"m_market", {&"general": 0.01})
	var p := Product.new()
	p.id = &"p_chat_marketed"
	p.type = &"chatbot"
	p.bound_model_id = m.id
	p.subscription_price = 5  # at guidance
	p.subscribers = 0
	GameState.products.append(p)
	GameState.campaigns.append(_make_campaign(40_000, p.id))
	EventBus.phase_started.emit(&"action", 1)
	# Empty pool × any rate = 0, but marketing adds 40k × 0.0125 = 500 subs.
	assert_gt(p.subscribers, 450)
	assert_lt(p.subscribers, 550)

func _make_campaign(weekly_budget: int, target_product_id: StringName) -> Resource:
	var Campaign = preload("res://scripts/resources/campaign.gd")
	var c := Campaign.new()
	c.id = &"c_test"
	c.weekly_budget = weekly_budget
	c.total_weeks = 4
	c.remaining_weeks = 4
	c.target_product_id = target_product_id
	return c

## v10: add an NPC competitor present on every board from turn 0. UserSystem
## ranks player models vs NPC competitors only, so giving a player model real
## competition means seeding NPCs (player filler models no longer affect rank).
func _seed_npc_competitor(npc_id: StringName, caps: Dictionary) -> void:
	var npc := NpcCompany.new()
	npc.id = npc_id
	npc.display_name = String(npc_id)
	npc.board_membership = [&"closed_source", &"sub_general", &"sub_code",
			&"sub_reasoning", &"sub_multimodal", &"sub_agent"]
	var rel := NpcModelRelease.new()
	rel.id = StringName("rel_%s" % String(npc_id))
	rel.display_name = String(npc_id)
	rel.release_turn = 0
	rel.capability = caps
	rel.release_kind = &"pretrain"
	npc.model_releases = [rel]
	GameState.npc_companies.append(npc)

# ---- v10 §5.2 rank rate: best-of, not summed ---------------------------

func test_rank_rate_takes_best_not_sum() -> void:
	# 用户场景: 通用细分榜 #1 但总榜 #5 → 取较优 +0.5%/周, 不再 0.5%+(-4%)=-3.5%.
	# Subject: huge `general`, zero elsewhere → #1 on sub_general. v10 ranks vs
	# NPCs only — seed 4 NPCs huge on every axis EXCEPT general, so they outrank
	# m_subgen on the summed `total` board but lose to it on sub_general.
	for i in range(4):
		_seed_npc_competitor(StringName("npc_x_%d" % i), {
			general = 0.0, code = 1e6, reasoning = 1e6,
			multimodal = 1e6, agent = 1e6,
		})
	var m: Model = _publish_model(&"m_subgen", {&"general": 1e6})
	var ap: Product = _api_product_for(m.id)
	assert_not_null(ap)
	ap.subscribers = 1000
	# Pin price at guidance so price_rate = 0 — isolate the rank contribution.
	m.per_token_price = ResearchSystem.guidance_price_per_token(m)
	GameState.turn = 1
	EventBus.phase_started.emit(&"action", 1)
	# v11 rate = max(total#5 -0.02, sub#1 +0.0025) = +0.0025 → pool grows.
	# Old (pre-v10) summing would give -0.0175 → pool shrinks.
	assert_gt(ap.subscribers, 1000,
			"sub-board #1 should grow the pool even when the total board is low")

func test_rank_ignores_players_own_other_models() -> void:
	# 用户场景: 产品绑定一个便宜的中等模型; 公司同时发布了一个强得多 (但服务
	# 成本高) 的前沿模型。前沿模型不能把产品在用的模型挤下一名 —— 公司不和
	# 自己竞争。无 NPC 竞品 → 产品的模型仍是竞品榜 #1。
	var weak: Model = _publish_model(&"m_prod", {&"general": 60.0})
	var _frontier: Model = _publish_model(&"m_frontier", {
		&"general": 1e6, &"code": 1e6, &"reasoning": 1e6,
		&"multimodal": 1e6, &"agent": 1e6,
	})
	var ap: Product = _api_product_for(weak.id)
	assert_not_null(ap)
	ap.subscribers = 1000
	weak.per_token_price = ResearchSystem.guidance_price_per_token(weak)  # price_rate 0
	GameState.turn = 1
	EventBus.phase_started.emit(&"action", 1)
	# m_prod global rank would be #2 (m_frontier above it), but vs NPCs it's #1.
	assert_eq(MarketSystem.get_rank_for_model(&"m_prod", &"total"), 2,
			"global leaderboard still ranks the company's own models against each other")
	assert_eq(MarketSystem.get_rank_vs_npcs(&"m_prod", &"total"), 1,
			"vs-NPC rank ignores the company's own stronger model")
	# rank_rate = max(+0.01, +0.0025) = +0.01 → pool grows despite the frontier model.
	assert_gt(ap.subscribers, 1000,
			"the company's own stronger model must not drag the product down")

# ---- v10 §5.2bis capability penalty ------------------------------------

func test_chatbot_capability_penalty_tiers() -> void:
	# chatbot.tres (v11 ×0.5): general < 50 → -2.5%/wk, < 70 → -1.5%/wk, ≥ 70 → 0.
	assert_almost_eq(UserSystem._capability_penalty_for(&"chatbot", 30.0), -0.025, 1e-9)
	assert_almost_eq(UserSystem._capability_penalty_for(&"chatbot", 49.9), -0.025, 1e-9)
	assert_almost_eq(UserSystem._capability_penalty_for(&"chatbot", 50.0), -0.015, 1e-9)
	assert_almost_eq(UserSystem._capability_penalty_for(&"chatbot", 69.9), -0.015, 1e-9)
	assert_almost_eq(UserSystem._capability_penalty_for(&"chatbot", 70.0), 0.0, 1e-9)
	assert_almost_eq(UserSystem._capability_penalty_for(&"chatbot", 85.0), 0.0, 1e-9)
	# api has no capability gate → always 0.
	assert_almost_eq(UserSystem._capability_penalty_for(&"api", 0.0), 0.0, 1e-9)

func test_other_product_types_capability_penalty_tiers() -> void:
	# v11 ×0.5. agent: reasoning < 65 → -2.5%, < 80 → -1.5%, ≥ 80 → 0.
	assert_almost_eq(UserSystem._capability_penalty_for(&"agent", 64.0), -0.025, 1e-9)
	assert_almost_eq(UserSystem._capability_penalty_for(&"agent", 70.0), -0.015, 1e-9)
	assert_almost_eq(UserSystem._capability_penalty_for(&"agent", 80.0), 0.0, 1e-9)
	# coding_agent: code < 80 → -2.5%, < 90 → -1.5%, ≥ 90 → 0.
	assert_almost_eq(UserSystem._capability_penalty_for(&"coding_agent", 75.0), -0.025, 1e-9)
	assert_almost_eq(UserSystem._capability_penalty_for(&"coding_agent", 85.0), -0.015, 1e-9)
	assert_almost_eq(UserSystem._capability_penalty_for(&"coding_agent", 90.0), 0.0, 1e-9)
	# multimodal_assistant: multimodal < 55 → -2.5%, < 70 → -1.5%, ≥ 70 → 0.
	assert_almost_eq(UserSystem._capability_penalty_for(&"multimodal_assistant", 50.0), -0.025, 1e-9)
	assert_almost_eq(UserSystem._capability_penalty_for(&"multimodal_assistant", 60.0), -0.015, 1e-9)
	assert_almost_eq(UserSystem._capability_penalty_for(&"multimodal_assistant", 75.0), 0.0, 1e-9)

func test_product_type_capability_penalty_axes() -> void:
	# Each gated type reads the axis aligned with its unlock_thresholds; api ungated.
	assert_eq(StringName(load(
		"res://resources/data/products/types/chatbot.tres").capability_penalty_axis), &"general")
	assert_eq(StringName(load(
		"res://resources/data/products/types/agent.tres").capability_penalty_axis), &"reasoning")
	assert_eq(StringName(load(
		"res://resources/data/products/types/coding_agent.tres").capability_penalty_axis), &"code")
	assert_eq(StringName(load(
		"res://resources/data/products/types/multimodal_assistant.tres").capability_penalty_axis), &"multimodal")
	assert_eq(StringName(load(
		"res://resources/data/products/types/api.tres").capability_penalty_axis), &"")

func test_chatbot_weak_model_suffers_capability_penalty() -> void:
	# Single published model → #1 on total + sub_general → rank_rate +0.01 (v11).
	# general 40 < 50 → capability_penalty -0.025 → net -0.015 → pool shrinks.
	var m: Model = _publish_model(&"m_weak_chat", {&"general": 40.0})
	var p := Product.new()
	p.id = &"p_weak_chat"
	p.type = &"chatbot"
	p.bound_model_id = m.id
	p.subscription_price = 5  # guidance → price_rate 0
	p.subscribers = 1000
	GameState.products.append(p)
	GameState.turn = 1
	EventBus.phase_started.emit(&"action", 1)
	assert_lt(p.subscribers, 1000,
			"general 40 chatbot: -2.5% capability penalty outweighs the rank bonus")

func test_chatbot_strong_model_no_capability_penalty() -> void:
	# Same setup but general 80 ≥ 70 → no penalty → rank +0.01 (v11) → pool grows.
	var m: Model = _publish_model(&"m_strong_chat", {&"general": 80.0})
	var p := Product.new()
	p.id = &"p_strong_chat"
	p.type = &"chatbot"
	p.bound_model_id = m.id
	p.subscription_price = 5
	p.subscribers = 1000
	GameState.products.append(p)
	GameState.turn = 1
	EventBus.phase_started.emit(&"action", 1)
	assert_gt(p.subscribers, 1000,
			"general 80 chatbot: no capability penalty → rank bonus grows pool")

func test_rate_breakdown_exposes_v10_fields() -> void:
	# compute_rate_breakdown must surface the applied rank_rate + the new
	# capability_penalty, and total_rate must be their sum with price_rate.
	var m: Model = _publish_model(&"m_bd", {&"general": 40.0})
	var p := Product.new()
	p.id = &"p_bd"
	p.type = &"chatbot"
	p.bound_model_id = m.id
	p.subscription_price = 5
	p.subscribers = 100
	GameState.products.append(p)
	GameState.turn = 1
	EventBus.phase_started.emit(&"action", 1)
	var bd: Dictionary = UserSystem.compute_rate_breakdown(p)
	assert_true(bd.has("capability_penalty"), "breakdown exposes capability_penalty")
	assert_almost_eq(float(bd.capability_penalty), -0.025, 1e-9)
	assert_true(bd.has("rank_rate"), "breakdown exposes the applied rank_rate")
	assert_almost_eq(float(bd.total_rate),
			float(bd.rank_rate) + float(bd.price_rate) + float(bd.capability_penalty), 1e-9)
