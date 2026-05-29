extends GutTest

## v7 PR-F (2026-05): API demand pool elasticity tests. Under v7 the demand
## pool lives on the auto-created `api` Product (subscribers field), not on
## Model.demand_multiplier (v6 — removed). Drives the full UserSystem.
## phase_started → _resolve_action pipeline and inspects api product
## subscribers + api_token_demand week-over-week.
##
## Per design/用户系统设计.md §5 + design/研究系统设计.md §4.4.


# 7B-equivalent fpt — pins the ResearchSystem base/guidance price so we can
# hit known r values in test_*.
const _FPT_7B: float = 1.4e10

func before_each() -> void:
	GameState.reset()
	GameState.turn = 0
	# Yearly baseline depends on GameState.turn; force a cache miss.
	if "_baseline_cache" in ResearchSystem:
		ResearchSystem._baseline_cache = {year = -1, value = 0.0}

func _publish_at_ratio(ratio: float, is_open_source: bool = true) -> Dictionary:
	# Construct and publish a model so an api Product is auto-created
	# (ProductSystem._on_model_published handles that). Then set its API price
	# such that price / guidance_price = ratio. Returns {model, api_product}.
	var m := Model.new()
	m.id = &"m_demand"
	m.arch = &"ant_v1"
	m.status = &"published"
	m.capability = {&"general": 50.0}
	m.is_open_source = is_open_source
	m.flops_per_token = _FPT_7B
	m.per_token_price = 0.0
	GameState.models.append(m)
	# Manually emit model_published so ProductSystem auto-creates the api product.
	EventBus.model_published.emit(m.id, is_open_source)
	# Find the auto-created api product.
	var ap: Product = null
	for prod in GameState.products:
		if prod.bound_model_id == m.id and "type" in prod and prod.type == &"api":
			ap = prod
			break
	assert_not_null(ap, "ProductSystem should auto-create an api product on publish")
	# Now set per_token_price s.t. r = ratio.
	var guidance: float = ResearchSystem.guidance_price_per_token(m)
	m.per_token_price = guidance * ratio
	return {model = m, api_product = ap}

func _tick() -> void:
	GameState.turn += 1
	EventBus.phase_started.emit(&"action", GameState.turn)

# ---- API cliff: r >= 2.5 zeros subscribers this week --------------------

func test_api_cliff_zeros_subscribers_when_overpriced() -> void:
	# v7 PR-F: r >= 2.5 → api_product.subscribers forced to 0 this week.
	# Use 2.5001 not 2.5: guidance×ratio/guidance round-trips just under 2.5 on
	# some base prices (float knife-edge); stay inside the cliff zone.
	var ctx: Dictionary = _publish_at_ratio(2.5001)
	var ap: Product = ctx.api_product
	# Pre-seed the pool so we can observe it crashing to 0.
	ap.subscribers = 1000
	_tick()
	assert_eq(ap.subscribers, 0, "r ≥ 2.5 should immediately zero the api pool")

func test_api_cliff_keeps_zero_while_overpriced() -> void:
	# Stays at 0 as long as the price is above cliff.
	var ctx: Dictionary = _publish_at_ratio(3.0)
	var ap: Product = ctx.api_product
	ap.subscribers = 1000
	_tick()
	assert_eq(ap.subscribers, 0)
	_tick()
	assert_eq(ap.subscribers, 0)

func test_api_pool_can_recover_after_price_drop() -> void:
	# Cliff this week → 0. Drop price below guidance next week + bring model
	# onto leaderboard top-3 so base_attraction can re-seed.
	var ctx: Dictionary = _publish_at_ratio(3.0)
	var m: Model = ctx.model
	var ap: Product = ctx.api_product
	ap.subscribers = 1000
	# Boost capability so the model is total #1 (NPCs have ~5-200 totals;
	# 5000 dominates everyone).
	m.capability = {&"general": 5000.0, &"code": 5000.0,
			&"reasoning": 5000.0, &"multimodal": 5000.0, &"agent": 5000.0}
	# Move into the curve range where base_attraction is non-zero.
	GameState.turn = 300
	_tick()
	assert_eq(ap.subscribers, 0, "cliff still active when price too high")
	# Drop to 0.5× guidance and wait for base_attraction to seed.
	var guidance: float = ResearchSystem.guidance_price_per_token(m)
	m.per_token_price = guidance * 0.5
	_tick()
	assert_gt(ap.subscribers, 0, "after dropping below cliff, pool grows back via base attraction")

# ---- Price elasticity for subscription products -------------------------

func test_chatbot_subscription_price_above_guidance_decays() -> void:
	# chatbot guidance = 5¥/week. At 10¥ (r=2.0) price rate = -0.10/week (v11 ×0.5).
	# Pin the model to rank ≥4 on every board with filler models — NPCs have no
	# releases yet at turn 1 so we have to seed the boards ourselves.
	_seed_filler_models()
	var m := Model.new()
	m.id = &"m_chat"
	m.arch = &"ant_v1"
	m.status = &"published"
	m.capability = {&"general": 0.01}  # so weak it loses to every filler
	m.is_open_source = false
	GameState.models.append(m)
	var p := Product.new()
	p.id = &"p_chat"
	p.type = &"chatbot"
	p.bound_model_id = m.id
	p.subscription_price = 10
	p.subscribers = 1000
	GameState.products.append(p)
	_tick()
	# v11 Rate = rank max(-0.02,-0.025)=-0.02 + price (-0.10)
	#          + capability_penalty (-0.025, general 0.01 < 50) = -0.145
	# Expected ~855. Allow generous bounds for rounding + base curve at turn 1 ≈ 1.
	assert_lt(p.subscribers, 900)
	assert_gt(p.subscribers, 800)

func test_chatbot_subscription_price_at_guidance_no_price_pressure() -> void:
	# At guidance, price_rate = 0. Pool decays only from rank penalty when
	# the model isn't top-3 on any board.
	_seed_filler_models()
	var m := Model.new()
	m.id = &"m_chat2"
	m.arch = &"ant_v1"
	m.status = &"published"
	m.capability = {&"general": 0.01}  # weakest possible vs fillers
	GameState.models.append(m)
	var p := Product.new()
	p.id = &"p_chat2"
	p.type = &"chatbot"
	p.bound_model_id = m.id
	p.subscription_price = 5  # at guidance
	p.subscribers = 1000
	GameState.products.append(p)
	_tick()
	# v11: rank max(-0.02,-0.025)=-0.02 + price (0)
	#    + capability_penalty (-0.025, general 0.01 < 50) = -0.045 → ~955.
	assert_lt(p.subscribers, 980)
	assert_gt(p.subscribers, 930)

# v10: UserSystem ranks player models vs NPC COMPETITORS only — player filler
# models no longer affect rank. Seed 4 dominating NPC competitors (present on
# every board from turn 0) so a weak player model lands at rank ≥5 (BELOW rate
# path) on every board.
func _seed_filler_models() -> void:
	for i in range(4):
		var npc := NpcCompany.new()
		npc.id = StringName("npc_filler_%d" % i)
		npc.display_name = String(npc.id)
		npc.board_membership = [&"closed_source", &"sub_general", &"sub_code",
				&"sub_reasoning", &"sub_multimodal", &"sub_agent"]
		var rel := NpcModelRelease.new()
		rel.id = StringName("rel_filler_%d" % i)
		rel.display_name = String(rel.id)
		rel.release_turn = 0
		rel.capability = {
			general = 1e6, code = 1e6, reasoning = 1e6,
			multimodal = 1e6, agent = 1e6,
		}
		rel.release_kind = &"pretrain"
		npc.model_releases = [rel]
		GameState.npc_companies.append(npc)

# ---- Base attraction curve ----------------------------------------------

func test_no_base_attraction_at_turn_zero_even_for_rank_1() -> void:
	# Curve knot (0, 0). Even being #1 yields 0 base attraction at turn 0.
	var m := Model.new()
	m.id = &"m_top"
	m.arch = &"ant_v1"
	m.status = &"published"
	# Massive capability → guaranteed total #1.
	m.capability = {&"general": 10000.0, &"code": 10000.0,
			&"reasoning": 10000.0, &"multimodal": 10000.0, &"agent": 10000.0}
	GameState.models.append(m)
	EventBus.model_published.emit(m.id, false)
	var ap: Product = null
	for prod in GameState.products:
		if prod.bound_model_id == m.id and prod.type == &"api":
			ap = prod
			break
	assert_not_null(ap)
	ap.subscribers = 0
	GameState.turn = 0
	_tick()
	# +rank bonuses but × 0 = 0; base_attraction(turn=1) ≈ 1 (lerp 0→100 over 100 turns).
	# At turn 1 we expect ~1 from base. Tolerate the rounding.
	assert_lte(ap.subscribers, 5)

func test_base_attraction_grows_late_game_for_top_models() -> void:
	# Around turn 280 (ChatGPT knot), base curve = 10K/week for #1 model.
	var m := Model.new()
	m.id = &"m_top_late"
	m.arch = &"ant_v1"
	m.status = &"published"
	m.capability = {&"general": 10000.0, &"code": 10000.0,
			&"reasoning": 10000.0, &"multimodal": 10000.0, &"agent": 10000.0}
	GameState.models.append(m)
	EventBus.model_published.emit(m.id, false)
	var ap: Product = null
	for prod in GameState.products:
		if prod.bound_model_id == m.id and prod.type == &"api":
			ap = prod
			break
	assert_not_null(ap)
	ap.subscribers = 0
	GameState.turn = 280
	_tick()
	# At turn 281, curve is just above the 280 knot (10_000). #1 factor = 1.0.
	# Expect ~10_000 added this week (modulo small lerp).
	assert_gt(ap.subscribers, 5000)
	assert_lt(ap.subscribers, 20000)

# ---- Rank-based growth/decay --------------------------------------------

func test_no_rank_no_growth_even_with_subscribers() -> void:
	# Model with low capability has rank 0 on every board → all rates negative.
	var m := Model.new()
	m.id = &"m_low"
	m.arch = &"ant_v1"
	m.status = &"published"
	m.capability = {&"general": 1.0}
	GameState.models.append(m)
	EventBus.model_published.emit(m.id, false)
	var ap: Product = null
	for prod in GameState.products:
		if prod.bound_model_id == m.id and prod.type == &"api":
			ap = prod
			break
	assert_not_null(ap)
	ap.subscribers = 1000
	# Move into the curve, but with no rank only the orphan / decay path applies.
	GameState.turn = 300
	_tick()
	# v11: rank rate is max(total_below -2%, sub_below -2.5%) = -2%/wk (×0.5 from v10).
	# api product → no capability penalty. → -20 sub change.
	assert_lt(ap.subscribers, 995)
	assert_gt(ap.subscribers, 960)
