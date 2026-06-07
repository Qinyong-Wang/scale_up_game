extends GutTest

## Wave 5 alignment tests (v7 PR-F3 rewrite):
## - UserSystem._marketing_attract matches campaign.target_product_id == product.id.
## - tokens_per_user_per_week from .tres matches design table.


func before_each() -> void:
	GameState.reset()

func _make_published_model(id: StringName = &"m_test",
		modalities: Array = [&"text"]) -> Model:
	var m := Model.new()
	m.id = id
	m.arch = &"ant_v1"
	m.size_params = 800.0
	var typed: Array[StringName] = []
	for x in modalities:
		typed.append(StringName(x))
	m.input_modalities = typed
	m.capability = {&"general": 60.0, &"reasoning": 60.0, &"code": 60.0, &"multimodal": 60.0}
	m.capability_revealed = true
	m.status = &"published"
	m.is_open_source = false
	m.per_token_price = 0.001
	GameState.models.append(m)
	return m

func _make_product(id: StringName, type: StringName, model_id: StringName,
		subs: int = 100) -> Product:
	var p := Product.new()
	p.id = id
	p.type = type
	p.bound_model_id = model_id
	p.subscription_price = 99
	p.subscribers = subs
	p.quality = 1.0
	GameState.products.append(p)
	return p

func _make_campaign(target_product_id: StringName, budget: int,
		fake_score_level: StringName = &"none") -> Campaign:
	var c := Campaign.new()
	c.id = StringName("camp_%d" % GameState.campaigns.size())
	c.display_name = "Test"
	c.weekly_budget = budget
	c.total_weeks = 6
	c.remaining_weeks = 6
	c.target_product_id = target_product_id
	c.fake_score_level = fake_score_level
	GameState.campaigns.append(c)
	return c

# ---- target_product_id is the matching surface ----------------------

func test_campaign_only_boosts_its_target_product() -> void:
	# 营销系统设计 §5.2: campaign.target_product_id matches product.id (1对1).
	var m := _make_published_model(&"m1")
	_make_product(&"p_chat", &"chatbot", m.id, 0)
	_make_product(&"p_agent", &"agent", m.id, 0)
	# Campaign 锁 p_chat: p_agent 完全不应受益。
	_make_campaign(&"p_chat", 5_000_000)
	CommandBus.send(&"user.recompute_now", {})
	var chatbot_subs: int = ProductSystem.find_product(&"p_chat").subscribers
	var agent_subs: int = ProductSystem.find_product(&"p_agent").subscribers
	assert_gt(chatbot_subs, 0, "目标产品应获得 subscribers")
	assert_eq(agent_subs, 0, "非目标产品不应受 campaign 影响")

func test_campaign_targeting_coding_agent_product() -> void:
	GameState.unlocks[&"application"][&"fox_code_specialist"] = true
	var m := _make_published_model(&"m1")
	m.capability[&"code"] = 80.0
	_make_product(&"p_ca", &"coding_agent", m.id, 0)
	_make_campaign(&"p_ca", 5_000_000)
	CommandBus.send(&"user.recompute_now", {})
	assert_gt(ProductSystem.find_product(&"p_ca").subscribers, 0,
			"coding_agent 类型 product 应被 campaign 推上去")

func test_campaign_targeting_api_product_boosts_api_demand_pool() -> void:
	# v7 PR-F3: api product 也走 product-id 匹配; subscribers 是 demand 池单位。
	var m := _make_published_model(&"m1")
	var p := _make_product(&"p_api", &"api", m.id, 0)
	# v12: CAC=$80/单位; budget=$400k → 5000 units demand/周.
	_make_campaign(p.id, 400_000)
	CommandBus.send(&"user.recompute_now", {})
	assert_gt(ProductSystem.find_product(&"p_api").subscribers, 0,
			"api product subscribers (= demand 池单位) 应被 campaign 推上去")

func test_campaign_target_survives_product_rebinding() -> void:
	# v7 PR-F3 核心保证: 玩家把 product 重绑到新 model, campaign / 池仍指向同一
	# product, demand 应自动跟到新 model。
	var m1 := _make_published_model(&"m_old")
	var m2 := _make_published_model(&"m_new")
	var p := _make_product(&"p_api", &"api", m1.id, 0)
	_make_campaign(p.id, 400_000)
	CommandBus.send(&"user.recompute_now", {})
	var subs_after_first: int = ProductSystem.find_product(&"p_api").subscribers
	assert_gt(subs_after_first, 0)
	# 重绑.
	p.bound_model_id = m2.id
	CommandBus.send(&"user.recompute_now", {})
	# Subscribers 池跟着 product 走 (没清零), demand 现在汇到 m_new。
	var subs_after_rebind: int = ProductSystem.find_product(&"p_api").subscribers
	assert_gte(subs_after_rebind, subs_after_first,
			"重绑 model 不应清零 subscribers 池")
	assert_gt(int(GameState.api_token_demand.get(m2.id, 0)), 0,
			"demand 应已汇到新 model")

func test_marketing_lead_campaign_efficiency_increases_attract() -> void:
	var m := _make_published_model(&"m1")
	var p := _make_product(&"p_chat", &"chatbot", m.id, 0)
	var lead := Lead.new()
	lead.id = &"lead_marketing_100"
	lead.specialty = &"marketing_lead"
	lead.ability = 100.0
	GameState.leads.append(lead)
	var c := _make_campaign(p.id, 1_000_000)
	c.lead_id = lead.id
	var boosted: int = UserSystem._marketing_attract(p)
	c.lead_id = &""
	var baseline: int = UserSystem._marketing_attract(p)
	# Per 平衡参数.md §LEAD_BONUS_TABLE: marketing_lead.campaign_efficiency = 0.55;
	# ability=100 → 1 + 1.0 × 0.55 = 1.55 (CAC ÷ 1.55 ≈ -35%).
	assert_almost_eq(float(boosted), float(baseline) * 1.55, float(baseline) * 0.001)

func test_fake_score_level_increases_campaign_attract() -> void:
	var m := _make_published_model(&"m1")
	var p := _make_product(&"p_chat", &"chatbot", m.id, 0)
	var c := _make_campaign(p.id, 800_000)
	var baseline: int = UserSystem._marketing_attract(p)
	c.fake_score_level = &"high"
	var boosted: int = UserSystem._marketing_attract(p)
	assert_almost_eq(float(boosted), float(baseline) * 1.25, 1.0,
			"high fake score claim should lift conversion by 25%")

func test_fake_score_level_reduces_retention_rate_for_target_product() -> void:
	var m := _make_published_model(&"m1")
	var p := _make_product(&"p_chat", &"chatbot", m.id, 1000)
	var baseline: Dictionary = UserSystem.compute_rate_breakdown(p)
	_make_campaign(p.id, 1_000, &"high")
	var penalized: Dictionary = UserSystem.compute_rate_breakdown(p)
	assert_almost_eq(float(penalized.fake_score_retention_penalty), -0.01, 0.000001)
	assert_almost_eq(float(penalized.total_rate),
			float(baseline.total_rate) - 0.01, 0.000001)

func test_fake_score_retention_penalty_clamps_when_multiple_campaigns_stack() -> void:
	var m := _make_published_model(&"m1")
	var p := _make_product(&"p_chat", &"chatbot", m.id, 1000)
	_make_campaign(p.id, 1_000, &"high")
	_make_campaign(p.id, 1_000, &"high")
	var breakdown: Dictionary = UserSystem.compute_rate_breakdown(p)
	assert_almost_eq(float(breakdown.fake_score_retention_penalty), -0.01, 0.000001,
			"multiple fake campaigns should not push retention below -1%/week")

# ---- tokens_per_user defaults match design table -----------------------

# 2026-05: 人均 token ×5 (chatbot 250k / agent 10M / multimodal 1.25M / coding 1B).
func test_chatbot_tokens_per_user_per_week_is_250k() -> void:
	var m := _make_published_model(&"m1")
	_make_product(&"p1", &"chatbot", m.id, 100)
	CommandBus.send(&"user.recompute_now", {})
	var subs: int = GameState.products[0].subscribers
	assert_eq(int(GameState.token_demand[m.id]), subs * 250_000)

func test_agent_tokens_per_user_per_week_is_10M() -> void:
	var m := _make_published_model(&"m1")
	_make_product(&"p1", &"agent", m.id, 100)
	CommandBus.send(&"user.recompute_now", {})
	var subs: int = GameState.products[0].subscribers
	assert_eq(int(GameState.token_demand[m.id]), subs * 10_000_000)

func test_multimodal_tokens_per_user_per_week_is_1_25M() -> void:
	var m := _make_published_model(&"m1", [&"text", &"image"])
	_make_product(&"p1", &"multimodal_assistant", m.id, 100)
	CommandBus.send(&"user.recompute_now", {})
	var subs: int = GameState.products[0].subscribers
	assert_eq(int(GameState.token_demand[m.id]), subs * 1_250_000)

func test_coding_agent_tokens_per_user_per_week_is_1B() -> void:
	var m := _make_published_model(&"m1")
	m.capability[&"code"] = 80.0
	_make_product(&"p1", &"coding_agent", m.id, 100)
	CommandBus.send(&"user.recompute_now", {})
	var subs: int = GameState.products[0].subscribers
	assert_eq(int(GameState.token_demand[m.id]), subs * 1_000_000_000)
