extends GutTest

## 出身系统 — FounderOriginSpec / FounderSystem / GameState 字段 +
## 三个系统钩子 (招聘 S 级权重 / 经济估值与融资 / 用户增长)。
## Per design/出身系统设计.md.

func before_each() -> void:
	GameState.reset()

func after_each() -> void:
	GameState.reset()

# ---- spec + FounderSystem 访问器 ---------------------------------------

func test_three_origin_specs_load() -> void:
	var ids: Array = []
	for s in FounderSystem.all_specs():
		ids.append(s.id)
	assert_eq(FounderSystem.all_specs().size(), 3)
	assert_true(ids.has(&"scientist"))
	assert_true(ids.has(&"entrepreneur"))
	assert_true(ids.has(&"influencer"))

func test_empty_origin_is_fully_neutral() -> void:
	GameState.founder_origin = &""
	assert_eq(FounderSystem.s_tier_weight_bonus(), 0.0)
	assert_eq(FounderSystem.funding_multiplier(), 1.0)
	assert_eq(FounderSystem.user_growth_multiplier(), 1.0)
	assert_false(FounderSystem.seed_round_unlocked())

func test_unknown_origin_is_neutral() -> void:
	GameState.founder_origin = &"nonsense"
	assert_eq(FounderSystem.funding_multiplier(), 1.0)
	assert_eq(FounderSystem.s_tier_weight_bonus(), 0.0)

func test_scientist_origin_accessors() -> void:
	GameState.founder_origin = &"scientist"
	assert_gt(FounderSystem.s_tier_weight_bonus(), 0.0)
	assert_lt(FounderSystem.funding_multiplier(), 1.0)

func test_entrepreneur_origin_accessors() -> void:
	GameState.founder_origin = &"entrepreneur"
	assert_eq(FounderSystem.funding_multiplier(), 2.0)
	assert_true(FounderSystem.seed_round_unlocked())
	assert_lt(FounderSystem.s_tier_weight_bonus(), 0.0)

func test_influencer_origin_accessors() -> void:
	GameState.founder_origin = &"influencer"
	assert_gt(FounderSystem.user_growth_multiplier(), 1.0)
	assert_lt(FounderSystem.funding_multiplier(), 1.0)

# ---- GameState 字段 + 序列化 -------------------------------------------

func test_reset_clears_founder_profile() -> void:
	GameState.player_name = "X"
	GameState.company_name = "Y"
	GameState.founder_origin = &"scientist"
	GameState.reset()
	assert_eq(GameState.player_name, "")
	assert_eq(GameState.company_name, "")
	assert_eq(GameState.founder_origin, &"")

func test_founder_profile_round_trips_through_dict() -> void:
	GameState.player_name = "阿黄"
	GameState.company_name = "蚂蚁智算"
	GameState.founder_origin = &"entrepreneur"
	var d: Dictionary = GameState.to_dict()
	GameState.reset()
	GameState.from_dict(d)
	assert_eq(GameState.player_name, "阿黄")
	assert_eq(GameState.company_name, "蚂蚁智算")
	assert_eq(GameState.founder_origin, &"entrepreneur")

func test_legacy_save_without_founder_keys_defaults_empty() -> void:
	GameState.from_dict({turn = 3})
	assert_eq(GameState.founder_origin, &"")
	assert_eq(GameState.company_name, "")
	assert_eq(GameState.player_name, "")

# ---- 招聘: S 级抽取权重 -------------------------------------------------

func _count_s_draws(origin: StringName, draws: int, cash: int) -> int:
	GameState.founder_origin = origin
	GameState.rng_seed = 12345
	GameState.rng_state = 0
	GameState._rng = null
	var n: int = 0
	for i in range(draws):
		if HiringSystem._draw_level(cash) == &"S":
			n += 1
	return n

func test_scientist_lifts_s_tier_draw_rate() -> void:
	# 低现金段基础 S 权重为 0 → 无出身永远抽不到 S；科学家 +0.30 后能抽到。
	var base_s: int = _count_s_draws(&"", 200, 80_000)
	var sci_s: int = _count_s_draws(&"scientist", 200, 80_000)
	assert_eq(base_s, 0, "无出身在低现金段不应抽到 S")
	assert_gt(sci_s, 0, "科学家出身应能在低现金段抽到 S")

func test_entrepreneur_lowers_s_tier_draw_rate() -> void:
	# 高现金段基础 S 权重 0.20 → 创业者 -0.15 后明显更少 (同 rng 流对比)。
	var base_s: int = _count_s_draws(&"", 400, 100_000_000)
	var ent_s: int = _count_s_draws(&"entrepreneur", 400, 100_000_000)
	assert_lt(ent_s, base_s, "创业者出身应降低 S 出现率")

# ---- 经济: 估值 / 融资额 / seed 解锁 -----------------------------------

func test_funding_multiplier_scales_valuation() -> void:
	GameState.reset()
	var base_v: int = EconomySystem._compute_valuation()
	GameState.founder_origin = &"entrepreneur"
	assert_eq(EconomySystem._compute_valuation(), base_v * 2,
			"创业者估值应翻倍")
	GameState.founder_origin = &"scientist"
	assert_eq(EconomySystem._compute_valuation(), int(round(float(base_v) * 0.85)),
			"科学家估值应打 85 折")

func test_entrepreneur_doubles_rolled_funding_amount() -> void:
	GameState.reset()
	GameState.rng_seed = 42
	GameState.rng_state = 0
	GameState._rng = null
	var base: Dictionary = CommandBus.send(&"economy.start_funding_round",
			{round = &"pre_seed"})
	GameState.reset()
	GameState.founder_origin = &"entrepreneur"
	GameState.rng_seed = 42
	GameState.rng_state = 0
	GameState._rng = null
	var ent: Dictionary = CommandBus.send(&"economy.start_funding_round",
			{round = &"pre_seed"})
	assert_true(base.get(&"ok", false) and ent.get(&"ok", false))
	assert_eq(int(ent.amount), int(base.amount) * 2,
			"创业者融资额应为同 rng 流下无出身的 2 倍")

func test_entrepreneur_unlocks_seed_round_from_turn_0() -> void:
	GameState.reset()
	var locked: Dictionary = CommandBus.send(&"economy.start_funding_round",
			{round = &"seed"})
	assert_eq(locked.get(&"error", &""), &"conditions_not_met",
			"无出身、无模型时 seed 轮应锁定")
	GameState.reset()
	GameState.founder_origin = &"entrepreneur"
	var r: Dictionary = CommandBus.send(&"economy.start_funding_round",
			{round = &"seed"})
	assert_ne(r.get(&"error", &""), &"conditions_not_met",
			"创业者出身应开局解锁 seed 轮")

# ---- 用户: 产品增长倍率 ------------------------------------------------

func _run_growth(origin: StringName) -> int:
	GameState.reset()
	GameState.founder_origin = origin
	var m := Model.new()
	m.id = &"m1"
	m.arch = &"ant_v1"
	m.status = &"published"
	GameState.models.append(m)
	var p := Product.new()
	p.id = &"p1"
	p.type = &"chatbot"
	p.bound_model_id = &"m1"
	p.subscribers = 0
	GameState.products.append(p)
	var c := Campaign.new()
	c.id = &"c1"
	c.target_product_id = &"p1"
	c.weekly_budget = 100_000
	c.remaining_weeks = 4
	c.total_weeks = 4
	GameState.campaigns.append(c)
	CommandBus.send(&"user.recompute_now", {})
	return p.subscribers

func test_influencer_accelerates_user_growth() -> void:
	var base: int = _run_growth(&"")
	var infl: int = _run_growth(&"influencer")
	assert_gt(base, 0, "营销预算应带来基础用户增长")
	assert_gt(infl, base, "网红出身应带来更快的用户增长")
	assert_almost_eq(float(infl), float(base) * 1.3, float(base) * 0.05)
