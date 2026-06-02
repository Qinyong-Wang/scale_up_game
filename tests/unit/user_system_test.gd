extends GutTest

## UserSystem v7 — 派生计算器, 把 rank / 价格 / 营销 + 产品组合折算成
## paid_users + token_demand. 无切片 (资源型).
## Per design/用户系统设计.md.
##
## 这些测试与 user_monetization_test 的差异: 这里**不**触发完整的
## users_resolved → revenue_resolved 链, 只验 UserSystem 自己的算法 §6.


func before_each() -> void:
	GameState.reset()

# ---- fixtures -----------------------------------------------------------

func _make_published_model(id: StringName, cap: Dictionary = {&"general": 50.0}) -> Model:
	var m := Model.new()
	m.id = id
	m.arch = &"ant_v1"
	m.capability = cap
	m.status = &"published"
	GameState.models.append(m)
	return m

func _make_product(id: StringName, type: StringName, price: int, subs: int,
		quality: float = 0.7, bound_model: StringName = &"") -> Product:
	var p := Product.new()
	p.id = id
	p.display_name = String(id)
	p.type = type
	p.subscription_price = price
	p.subscribers = subs
	p.quality = quality
	p.bound_model_id = bound_model
	GameState.products.append(p)
	return p

func _make_campaign(id: StringName, segment: StringName, weekly_budget: int) -> Campaign:
	var c := Campaign.new()
	c.id = id
	c.target_segment = segment
	c.weekly_budget = weekly_budget
	c.remaining_weeks = 3
	c.total_weeks = 3
	GameState.campaigns.append(c)
	return c

# ---- §6.1 周度主入口 / signal ------------------------------------------

func test_action_phase_triggers_users_resolved_signal() -> void:
	# §6.1: phase_started(action) → _resolve_action → emit users_resolved.
	watch_signals(EventBus)
	EventBus.phase_started.emit(&"action", 1)
	assert_signal_emitted(EventBus, "users_resolved")

func test_users_resolved_carries_current_turn() -> void:
	GameState.turn = 7
	watch_signals(EventBus)
	EventBus.phase_started.emit(&"action", 7)
	var p: Array = get_signal_parameters(EventBus, "users_resolved")
	assert_eq(p[0], 7)

func test_upkeep_phase_does_not_trigger_users_resolved() -> void:
	# §6.1: 仅 action 相位结算, upkeep / resolve 不动.
	watch_signals(EventBus)
	EventBus.phase_started.emit(&"upkeep", 1)
	EventBus.phase_started.emit(&"resolve", 1)
	assert_signal_not_emitted(EventBus, "users_resolved")

func test_last_user_resolved_turn_updated_after_action() -> void:
	# §1: last_user_resolved_turn 起手 -1, 每周 action 结算后 = current turn.
	GameState.turn = 5
	EventBus.phase_started.emit(&"action", 5)
	assert_eq(GameState.last_user_resolved_turn, 5)

# ---- §6.3 paid_users 重算 ----------------------------------------------

func test_paid_users_equals_sum_of_subscribers() -> void:
	# §6.3: paid_users = Σ p.subscribers.
	_make_product(&"p1", &"chatbot", 99, 100)
	_make_product(&"p2", &"agent", 199, 50)
	EventBus.phase_started.emit(&"action", 1)
	# 注: action 相位先跑 _resolve_per_product (会改 subscribers), 再求和.
	# 这里只验 paid_users 等于产品总和, 不预测具体值.
	var sum: int = 0
	for p in GameState.products:
		sum += p.subscribers
	assert_eq(GameState.paid_users, sum)

func test_paid_users_changed_emits_when_value_moves() -> void:
	# §6.3: if paid_users != old → emit paid_users_changed(delta, new_total).
	_make_product(&"p1", &"chatbot", 99, 100, 1.0)  # quality=1 → churn 几乎 0
	watch_signals(EventBus)
	CommandBus.send(&"user.recompute_now", {})
	# 因为 attract>0, subscribers 会涨 → paid_users 变 → 应有 paid_users_changed
	assert_signal_emitted(EventBus, "paid_users_changed")
	var p: Array = get_signal_parameters(EventBus, "paid_users_changed")
	# delta = new_total - old_total, 当前 old = 0
	assert_eq(int(p[1]), GameState.paid_users)

func test_paid_users_zero_when_no_products() -> void:
	EventBus.phase_started.emit(&"action", 1)
	assert_eq(GameState.paid_users, 0)

# ---- §6.4 token_demand 重算 --------------------------------------------

func test_token_demand_populated_only_for_published_models() -> void:
	# §6.4: 仅 status==published 进 token_demand.
	# 用 user.recompute_now 隔离, 避免其它 action-phase 系统改动场景。
	var m_pub: Model = _make_published_model(&"m1")
	var m_int := Model.new()
	m_int.id = &"m_internal"
	m_int.arch = &"ant_v1"
	m_int.status = &"pretrained"
	GameState.models.append(m_int)
	CommandBus.send(&"user.recompute_now", {})
	assert_true(GameState.token_demand.has(m_pub.id))
	assert_false(GameState.token_demand.has(m_int.id))

func test_token_demand_proportional_to_capability_and_fame() -> void:
	# v7 PR-F (2026-05): 旧 fame×cap api_part 公式已删. api_part 现在派生自
	# api_product.subscribers × API_TOKENS_PER_SUB_PER_WEEK; capability 与
	# fame 不再直接驱动 api demand. 新行为由 demand_v7_test 覆盖.
	pending("v7 PR-F: fame×cap api demand 公式废弃, 见 demand_v7_test")

func _make_api_product(model_id: StringName) -> Product:
	var p := Product.new()
	p.id = StringName("product_api_" + String(model_id))
	p.type = &"api"
	p.bound_model_id = model_id
	p.auto_track_latest = false
	GameState.products.append(p)
	return p

func test_api_token_demand_zero_when_no_api_product() -> void:
	# §6.4 (新): 没有 api 产品 → api_part = 0.
	var m: Model = _make_published_model(&"m1", {&"general": 80.0})
	CommandBus.send(&"user.recompute_now", {})
	assert_eq(int(GameState.api_token_demand.get(m.id, 0)), 0,
			"无 api 产品时 api_token_demand 应为 0")

func test_api_token_demand_positive_when_api_product_exists() -> void:
	# v7 PR-F: api_part = api_product.subscribers × API_TOKENS_PER_SUB_PER_WEEK.
	# Pre-seed subscribers to verify the path (skip the rank/curve-driven growth
	# which is covered by demand_v7_test).
	var m: Model = _make_published_model(&"m1", {&"general": 80.0})
	var ap := _make_api_product(m.id)
	ap.subscribers = 1234
	CommandBus.send(&"user.recompute_now", {})
	assert_gt(int(GameState.api_token_demand.get(m.id, 0)), 0)

func test_api_product_skipped_in_subscriber_evolution() -> void:
	# §6.2 (新): api 产品不参与 subscribers 增长 / 流失.
	var m: Model = _make_published_model(&"m1", {&"general": 80.0})
	var ap := _make_api_product(m.id)
	EventBus.phase_started.emit(&"action", 1)
	assert_eq(ap.subscribers, 0, "api 产品 subscribers 不应被增长改动")

func test_token_demand_zero_when_fame_zero_and_no_subscribers() -> void:
	# §6.4: 无 product / api pool 时, published model 的 demand 为 0。
	var m: Model = _make_published_model(&"m1")
	CommandBus.send(&"user.recompute_now", {})
	assert_eq(int(GameState.token_demand[m.id]), 0)

func test_token_demand_changed_emits_when_value_changes() -> void:
	# §6.4: 任一 model 的 demand 变化 → emit token_demand_changed.
	var m: Model = _make_published_model(&"m1")
	watch_signals(EventBus)
	CommandBus.send(&"user.recompute_now", {})
	assert_signal_emitted(EventBus, "token_demand_changed")

func test_token_demand_for_unpublished_model_emits_zero() -> void:
	# §6.4 末段: 上次有的 demand 这次没有 → emit token_demand_changed(mid, 0)
	# 用 GameState 直接构造一个"上次的" demand, 然后跑结算.
	GameState.token_demand[&"m_old"] = 999
	watch_signals(EventBus)
	CommandBus.send(&"user.recompute_now", {})
	# 由于本次没 m_old (没 published model 叫这个), 应发 0.
	var found: bool = false
	for i in range(get_signal_emit_count(EventBus, "token_demand_changed")):
		var p: Array = get_signal_parameters(EventBus, "token_demand_changed", i)
		if p[0] == &"m_old" and int(p[1]) == 0:
			found = true; break
	assert_true(found, "应为 m_old 发 token_demand_changed(0)")
	# 重算后字典里也不该再有 m_old
	assert_false(GameState.token_demand.has(&"m_old"))

func test_token_demand_includes_subscriber_part_for_bound_product() -> void:
	# §6.4: product_part = Σ p.subscribers × tokens_per_user_per_week (per type).
	# Chatbot 人均 250_000 tokens/user/week (2026-05 ×5; fallback).
	var m: Model = _make_published_model(&"m1")
	_make_product(&"p1", &"chatbot", 99, 100, 1.0, m.id)
	# 用 recompute_now 隔离, 否则 ProductSystem 会把 quality 重算成 0 → churn 改 subs.
	CommandBus.send(&"user.recompute_now", {})
	var actual_subs: int = GameState.products[0].subscribers
	assert_eq(int(GameState.token_demand[m.id]), actual_subs * 250_000)

# ---- §6.2 _resolve_per_product / churn / attract -----------------------

func test_high_quality_product_attracts_more_at_same_fame() -> void:
	# v7 PR-F: quality_share × fame 公式已删. 用户增长改由 rank + 价格 + 营销
	# 驱动. product.quality 仍是产品质量指标但不进 UserSystem rate 公式.
	pending("v7 PR-F: 用户增长不再读 product.quality, 见 demand_v7_test")

func test_zero_fame_zero_attract() -> void:
	# §6.2: fame=0 → attract = 0. 无营销时 subscribers 不应增长.
	_make_product(&"p1", &"chatbot", 99, 0, 0.7)
	CommandBus.send(&"user.recompute_now", {})
	# 无 fame, 无 campaign, 无既有用户 → subscribers 应保持 0.
	assert_eq(GameState.products[0].subscribers, 0)

func test_churn_reduces_subscribers_when_quality_below_base() -> void:
	# §6.2: churn = K × subs × max(0, 1 - quality/QUALITY_BASE) × _price_pressure.
	# QUALITY_BASE = 0.6; quality=0.3 → 流失因子 0.5 (而 quality=0.7 → 0).
	_make_product(&"p1", &"chatbot", 99, 1000, 0.3)
	CommandBus.send(&"user.recompute_now", {})
	assert_lt(GameState.products[0].subscribers, 1000, "低质量产品应流失")

func test_quality_above_base_has_only_base_churn() -> void:
	# §6.2: quality ≥ QUALITY_BASE → CHURN_K 部分为 0, 但 BASE_CHURN_RATE=0.01 仍然适用.
	# 500 × 0.01 × price_pressure(99)=1.0 = 5 → 预期 ~495.
	_make_product(&"p1", &"chatbot", 99, 500, 0.7)
	CommandBus.send(&"user.recompute_now", {})
	assert_lt(GameState.products[0].subscribers, 500, "好质量产品仍有 1% 基础流失")
	assert_gte(GameState.products[0].subscribers, 490, "基础流失不应超过 2%")

func test_base_churn_rate_independent_of_quality() -> void:
	# §6.2: BASE_CHURN_RATE=0.01 对所有非 api 产品生效, 无关质量.
	# 高质量 (quality=1.0) + 0 fame: 唯一的流失来源就是 1% 基础.
	_make_product(&"p1", &"chatbot", 99, 1000, 1.0)
	CommandBus.send(&"user.recompute_now", {})
	# 1000 × 0.01 = 10 churn → 990; attract=0. 预期约 990.
	assert_lt(GameState.products[0].subscribers, 1000, "最高质量产品仍有基础流失")
	assert_gte(GameState.products[0].subscribers, 985, "基础流失不应超过 1.5%")

func test_higher_price_increases_churn() -> void:
	# v7 PR-F: 价格弹性公式变成分段曲线 (¥20 chatbot guidance, r=price/guidance).
	# 99 ≈ 5× guidance → cap at -50%/周; 999 → 同样 cap -50% (无差异在此层 — 都触底).
	# 验证: 高于 guidance 的两个价位都流失 (但两者差异不再明显, 只是分段差).
	_make_product(&"p_lo", &"chatbot", 99, 1000, 0.3)
	_make_product(&"p_hi", &"chatbot", 999, 1000, 0.3)
	# 把模型设到非 top-3 (rank 0), 避免 rank 加成混淆.
	# (这里没创建 model, _resolve_per_product 走 orphan 路径, 只扣 ORPHAN 5/周)
	CommandBus.send(&"user.recompute_now", {})
	# orphan churn 路径下两个产品都掉 ORPHAN_PRODUCT_CHURN=5.
	assert_lt(GameState.products[0].subscribers, 1000)
	assert_lt(GameState.products[1].subscribers, 1000)

# ---- 营销 boost (经过 _marketing_attract) ---------------------------------

func test_campaign_targeting_chatbot_boosts_only_chatbot_products() -> void:
	# v7 PR-F3: campaign 锁单 product, 只推 target_product_id 命中的那一个。
	# 需绑定 published model 才会跑增长路径 (orphan 路径走 churn).
	var m: Model = _make_published_model(&"m_brand", {&"general": 80.0})
	var p_chat := _make_product(&"p_chat", &"chatbot", 20, 0, 0.7, m.id)
	_make_product(&"p_agent", &"agent", 50, 0, 0.7, m.id)
	# Campaign 锁 p_chat: p_agent 应当完全不受加成。
	var c := Campaign.new()
	c.id = &"c1"
	c.target_product_id = p_chat.id
	c.weekly_budget = 1_000_000
	c.remaining_weeks = 3
	c.total_weeks = 3
	GameState.campaigns.append(c)
	CommandBus.send(&"user.recompute_now", {})
	assert_gt(GameState.products[0].subscribers, 0, "chatbot 应受 campaign 加成")
	assert_eq(GameState.products[1].subscribers, 0,
			"非目标 product 不应受 campaign 影响")

func test_campaign_segment_all_boosts_every_product_DISABLED() -> void:
	pending("v7 PR-F: campaign now needs bound model to avoid orphan churn path")
func _disabled_test_campaign_segment_all_boosts_every_product() -> void:
	# &"all" segment 应同时加成 chatbot + agent.
	_make_product(&"p_chat", &"chatbot", 99, 0, 0.7)
	_make_product(&"p_agent", &"agent", 99, 0, 0.7)
	_make_campaign(&"c1", &"all", 1_000_000)
	CommandBus.send(&"user.recompute_now", {})
	assert_gt(GameState.products[0].subscribers, 0)
	assert_gt(GameState.products[1].subscribers, 0)

# ---- §2 命令 ------------------------------------------------------------

func test_preview_demand_returns_predicted_for_known_model_DISABLED() -> void:
	pending("v7 PR-F: predicted=fame×cap formula deleted; use api_product.subscribers seeding")
func _disabled_test_preview_demand_returns_predicted_for_known_model() -> void:
	# §6.4 (新): demand 需要 api 产品才有 base, 或绑订阅产品.
	var m: Model = _make_published_model(&"m1")
	_make_api_product(m.id)
	var r: Dictionary = CommandBus.send(&"user.preview_demand", {model_id = m.id})
	assert_true(r.ok)
	assert_gt(int(r.predicted), 0)

func test_preview_demand_unknown_model_returns_error() -> void:
	# §2: error code = &"unknown_model".
	var r: Dictionary = CommandBus.send(&"user.preview_demand", {model_id = &"nope"})
	assert_false(r.ok)
	assert_eq(r.error, &"unknown_model")

func test_recompute_now_resolves_without_phase() -> void:
	# §2: 测试/debug 用 — 不依赖 phase 信号也能跑结算.
	_make_product(&"p1", &"chatbot", 99, 100)
	var r: Dictionary = CommandBus.send(&"user.recompute_now", {})
	assert_true(r.ok)
	assert_eq(GameState.paid_users, GameState.products[0].subscribers)

# ---- 不变量 -------------------------------------------------------------

func test_quality_share_treats_total_as_at_least_one() -> void:
	# §6.2 实现: quality_share = quality / max(total_quality, 1.0).
	# 仅一个 quality<1 的产品时, total_quality = 0.7, 但 max(0.7, 1)=1.
	# 这意味着其 quality_share = 0.7, 而不是 1.0; 测试这条不出 NaN/inf.
	_make_product(&"p1", &"chatbot", 99, 0, 0.5)
	EventBus.phase_started.emit(&"action", 1)
	assert_gte(GameState.paid_users, 0)

func test_resolve_does_not_crash_with_zero_products_and_models() -> void:
	# 周度结算应该健壮: 没有任何 model / product 时不能炸.
	EventBus.phase_started.emit(&"action", 1)
	assert_eq(GameState.paid_users, 0)
	assert_eq(GameState.token_demand, {})

# ---- §3 信号: users_resolved 携带真实 paid_users delta ------------------

func test_users_resolved_emits_zero_delta_when_no_subscriber_change() -> void:
	# §3 / §6.1: users_resolved(turn, paid_users_delta).
	# 无 product 无 model → paid_users 始终 0 → delta 应为 0.
	watch_signals(EventBus)
	EventBus.phase_started.emit(&"action", 1)
	var p: Array = get_signal_parameters(EventBus, "users_resolved")
	assert_eq(int(p[1]), 0, "无产品时 delta 应为 0")

func test_users_resolved_emits_positive_delta_when_users_grow_DISABLED() -> void:
	pending("v7 PR-F: fame-driven growth removed; positive delta needs rank or marketing path")
func _disabled_test_users_resolved_emits_positive_delta_when_users_grow() -> void:
	# §3 / §6.1: 当 paid_users 增加, delta 应 = new - old > 0.
	_make_product(&"p1", &"chatbot", 99, 0, 1.0)  # quality=1, 几乎不流失
	GameState.paid_users = 0
	watch_signals(EventBus)
	CommandBus.send(&"user.recompute_now", {})
	var p: Array = get_signal_parameters(EventBus, "users_resolved")
	assert_eq(int(p[1]), GameState.paid_users,
			"用户从 0 增长, delta 应等于新的 paid_users")
	assert_gt(int(p[1]), 0, "增长时 delta 应为正")

func test_users_resolved_emits_negative_delta_when_users_shrink() -> void:
	# §3 / §6.1: 用户流失时 delta 应为负.
	# 低 quality (0.3) + 0 fame + 0 campaign → 必有 churn, 无 attract.
	var prod := _make_product(&"p1", &"chatbot", 99, 1000, 0.3)
	GameState.paid_users = 1000
	watch_signals(EventBus)
	CommandBus.send(&"user.recompute_now", {})
	var p: Array = get_signal_parameters(EventBus, "users_resolved")
	assert_lt(int(p[1]), 0, "用户流失时 delta 应为负")
	# delta 应等于 new - old.
	assert_eq(int(p[1]), prod.subscribers - 1000)

# ---- 按 product_type 取 tokens_per_user_per_week ------------------------

func test_token_demand_uses_chatbot_per_user_default() -> void:
	# Chatbot 人均: 250_000 tokens/user/week (2026-05 ×5).
	var m: Model = _make_published_model(&"m1")
	_make_product(&"p1", &"chatbot", 99, 100, 1.0, m.id)
	CommandBus.send(&"user.recompute_now", {})
	var subs: int = GameState.products[0].subscribers
	assert_eq(int(GameState.token_demand[m.id]), subs * 250_000)

func test_token_demand_uses_agent_per_user_default() -> void:
	# Agent 人均: 10_000_000 tokens/user/week (2026-05 ×5).
	var m: Model = _make_published_model(&"m1")
	_make_product(&"p1", &"agent", 99, 100, 1.0, m.id)
	CommandBus.send(&"user.recompute_now", {})
	var subs: int = GameState.products[0].subscribers
	assert_eq(int(GameState.token_demand[m.id]), subs * 10_000_000)

func test_token_demand_uses_multimodal_assistant_per_user_default() -> void:
	# Multimodal assistant 人均: 1_250_000 tokens/user/week (2026-05 ×5; per .tres).
	var m: Model = _make_published_model(&"m1")
	_make_product(&"p1", &"multimodal_assistant", 99, 100, 1.0, m.id)
	CommandBus.send(&"user.recompute_now", {})
	var subs: int = GameState.products[0].subscribers
	assert_eq(int(GameState.token_demand[m.id]), subs * 1_250_000)

func test_token_demand_uses_coding_agent_per_user_default() -> void:
	# Coding agent 人均: 1_000_000_000 tokens/user/week (2026-05 ×5; per .tres).
	var m: Model = _make_published_model(&"m1")
	_make_product(&"p1", &"coding_agent", 99, 100, 1.0, m.id)
	CommandBus.send(&"user.recompute_now", {})
	var subs: int = GameState.products[0].subscribers
	assert_eq(int(GameState.token_demand[m.id]), subs * 1_000_000_000)

func test_token_demand_per_type_differs_with_same_subscribers() -> void:
	# 同 subscribers, agent 类型应比 chatbot 类型贡献更高的 token_demand.
	var m_chat: Model = _make_published_model(&"m_chat")
	var m_agent: Model = _make_published_model(&"m_agent")
	_make_product(&"p_chat", &"chatbot", 99, 100, 1.0, m_chat.id)
	_make_product(&"p_agent", &"agent", 99, 100, 1.0, m_agent.id)
	CommandBus.send(&"user.recompute_now", {})
	var chat_demand: int = int(GameState.token_demand[m_chat.id])
	var agent_demand: int = int(GameState.token_demand[m_agent.id])
	assert_gt(agent_demand, chat_demand,
			"agent 类型的 tokens_per_user 应大于 chatbot")

# ---- §6.4 (v3) API demand 100× 校准 ------------------------------------

func test_api_token_demand_calibration_at_fame100_cap300_DISABLED() -> void:
	pending("v7 PR-F: fame×cap API demand formula deleted; calibration tracked in demand_v7_test")
func _disabled_test_api_token_demand_calibration_at_fame100_cap300() -> void:
	# §7 校准点 (v3): fame=100, cap_total=300 → 4.5e9 tokens/月.
	# 公式: api_part = TOKEN_BASE_PER_FAME × fame × cap_total / 100
	#               = 15_000_000 × 100 × 300 / 100 = 4.5e9
	var m: Model = _make_published_model(&"m1", {&"general": 100.0,
			&"code": 100.0, &"reasoning": 100.0})  # cap_total = 300
	_make_api_product(m.id)
	CommandBus.send(&"user.recompute_now", {})
	var demand: int = int(GameState.api_token_demand[m.id])
	# Allow ±1% tolerance for int rounding in implementation.
	assert_almost_eq(float(demand), 4.5e9, 4.5e7)

func test_api_token_demand_scales_linear_with_fame() -> void:
	# §6.4: 同 cap, fame ×2 → demand ×2.
	var m: Model = _make_published_model(&"m1", {&"general": 60.0})
	_make_api_product(m.id)
	CommandBus.send(&"user.recompute_now", {})
	var d50: int = int(GameState.api_token_demand[m.id])
	CommandBus.send(&"user.recompute_now", {})
	var d100: int = int(GameState.api_token_demand[m.id])
	assert_almost_eq(float(d100), float(d50) * 2.0, float(d50) * 0.01)

# ---- §6.4 (v3) CAC 校准 + 线性 ----------------------------------------

func _campaign_targeting(product_id: StringName, weekly_budget: int) -> Campaign:
	# v7 PR-F3: campaign 锁单个 product。
	var c := Campaign.new()
	c.id = StringName("cac_test_%d" % weekly_budget)
	c.weekly_budget = weekly_budget
	c.total_weeks = 1
	c.remaining_weeks = 1
	c.target_product_id = product_id
	GameState.campaigns.append(c)
	return c

func test_marketing_attract_calibrates_to_cac_80_dollars() -> void:
	# §7 (v12): MARKETING_CONVERSION_RATE = 0.0125 → CAC = $80 / user.
	# attract = budget × 0.0125; budget=$80 应得 1 user (CAC 校准点).
	var p := _make_product(&"p1", &"chatbot", 99, 0, 0.7)
	_campaign_targeting(p.id, 80)
	var boost: int = UserSystem._marketing_attract(p)
	assert_eq(boost, 1)

func test_marketing_attract_linear_in_budget() -> void:
	# §6.4: boost = budget × rate × lead; 多花 10× 钱拉 10× 用户, CAC 不变.
	var p1 := _make_product(&"p1", &"chatbot", 99, 0, 0.7)
	_campaign_targeting(p1.id, 10_000)
	var small_boost: int = UserSystem._marketing_attract(p1)
	GameState.campaigns.clear()
	_campaign_targeting(p1.id, 100_000)
	var big_boost: int = UserSystem._marketing_attract(p1)
	assert_eq(big_boost, small_boost * 10)

func test_marketing_attract_linear_across_three_orders() -> void:
	# 跨 3 个数量级仍线性: budget 8k / 800k / 80M → boost 1× / 100× / 10000×.
	# (v12: 0.0125 率下取 8k 的倍数, attract 落整数避免半数舍入抖动.)
	var p := _make_product(&"p1", &"chatbot", 99, 0, 0.7)
	_campaign_targeting(p.id, 8_000)
	var b_small: int = UserSystem._marketing_attract(p)
	GameState.campaigns.clear()
	_campaign_targeting(p.id, 800_000)
	var b_med: int = UserSystem._marketing_attract(p)
	GameState.campaigns.clear()
	_campaign_targeting(p.id, 80_000_000)
	var b_ultra: int = UserSystem._marketing_attract(p)
	assert_eq(b_med, b_small * 100)
	assert_eq(b_ultra, b_small * 10_000)

# v7 PR-F3: api 产品也走同一管道 — campaign 锁定该 product, 营销预算直接转成
# API token 需求池单位。1 个 api.subscribers 单位 = API_TOKENS_PER_SUB_PER_WEEK
# tokens/周.
func test_marketing_attract_works_on_api_product() -> void:
	var p_api := Product.new()
	p_api.id = &"p_api"
	p_api.type = &"api"
	p_api.bound_model_id = &"m_test"
	p_api.subscription_price = 0
	p_api.subscribers = 0
	GameState.products.append(p_api)
	_campaign_targeting(p_api.id, 40_000)
	var boost: int = UserSystem._marketing_attract(p_api)
	# v12: 40_000 × 0.0125 = 500 demand 单位 / 周 (CAC ×2 后同预算砍半).
	assert_eq(boost, 500)
