extends GutTest

## 钉住产品 tab 算力池的 capacity / util_pct 与 MonetizationSystem 实际结算一致。
##
## 历史 bug: main.gd `_capacity_for_model` 用 SECONDS_PER_MONTH 算 capacity (单位
## tokens/月), 但 `GameState.token_demand` 单位是 tokens/周, 而且还又乘了一次
## engineering 树乘数 (v4 PR-B 已下沉到 dc.serving_tokens_per_sec)。结果显示的
## util_pct 大概是真实值的 1/4, 玩家看到的池子永远不满, 实际营收按算力截断丢了。
##
## 这组测试钉两点:
##   1. UI capacity == MonetizationSystem.compute_capacity_for_model (单一来源)。
##   2. 算力饱和时 (demand ≥ capacity) util_pct ≥ 100, 触发产品 tab 的警告行。

const Main := preload("res://scenes/main/main.gd")

const SECONDS_PER_WEEK: int = 604_800

var _hud

func before_each() -> void:
	GameState.reset()
	_hud = Main.new()
	add_child_autofree(_hud)
	await get_tree().process_frame

func _make_published_model(id: StringName) -> Model:
	var m := Model.new()
	m.id = id
	m.display_name = String(id)
	m.arch = &"ant_v1"
	m.capability = {&"general": 60.0}
	m.status = &"published"
	m.is_open_source = false
	m.per_token_price = 0.0001
	m.flops_per_token = 1.4e10
	GameState.models.append(m)
	return m

func _make_serving_dc(model_id: StringName, capacity_per_week: float) -> Datacenter:
	var dc := Datacenter.new()
	dc.id = StringName("dc_" + String(model_id))
	dc.facility_spec_id = &"facility_solo"
	dc.status = &"serving"
	dc.deployed_model_id = model_id
	dc.serving_target_kind = &"owned_model"
	dc.serving_target_id = model_id
	dc.serving_tokens_per_sec = capacity_per_week / float(SECONDS_PER_WEEK)
	GameState.datacenters.append(dc)
	return dc

func _make_subscription_product(id: StringName, model_id: StringName, subs: int) -> Product:
	var p := Product.new()
	p.id = id
	p.display_name = String(id)
	p.type = &"chatbot"
	p.subscribers = subs
	p.subscription_price = 99
	p.bound_model_id = model_id
	GameState.products.append(p)
	return p

func _make_api_product(model_id: StringName) -> Product:
	var p := Product.new()
	p.id = StringName("api_" + String(model_id))
	p.display_name = "API"
	p.type = &"api"
	p.subscribers = 0
	p.bound_model_id = model_id
	GameState.products.append(p)
	return p

func test_pool_row_capacity_matches_monetization_settlement() -> void:
	# 同一个 model: UI 报的 capacity 必须 = 结算时用的 capacity。
	var m: Model = _make_published_model(&"m_consistency")
	_make_serving_dc(m.id, 1_000_000.0)  # 1M tokens/周
	_make_subscription_product(&"p_sub", m.id, 1)

	var data: Dictionary = _hud._build_product_view_data()
	var rows: Array = data.get("pool_rows", [])
	assert_eq(rows.size(), 1, "应有 1 行算力池 (有绑定 product 的 published 模型)")
	var ui_cap: int = int(rows[0]["capacity"])
	var settle_cap: float = MonetizationSystem.compute_capacity_for_model(m)
	assert_eq(ui_cap, int(settle_cap),
			"UI 报的 capacity (%d) 必须等于结算用的 capacity (%d)" % [ui_cap, int(settle_cap)])

func test_pool_util_pct_reaches_100_when_demand_saturates_capacity() -> void:
	# capacity 设到 1M tokens/周, demand 注入到 5M tokens/周 → util 应 ≈ 500%。
	# 钉死的是 _build_product_view_data 里 demand/capacity 的单位一致 (都按周),
	# 不走 UserSystem 演化 (那是另一组测试的事), 直接写 token_demand。
	var m: Model = _make_published_model(&"m_sat")
	_make_serving_dc(m.id, 1_000_000.0)
	_make_subscription_product(&"p_sat", m.id, 1)
	GameState.token_demand[m.id] = 5_000_000     # tokens/周
	GameState.api_token_demand[m.id] = 0

	var data: Dictionary = _hud._build_product_view_data()
	var rows: Array = data.get("pool_rows", [])
	assert_eq(rows.size(), 1, "应有 1 行 (m_sat + 绑定产品)")
	if rows.size() < 1: return
	var cap: int = int(rows[0]["capacity"])
	var dem: int = int(rows[0]["demand"])
	var util: float = float(rows[0]["util_pct"])
	assert_gt(util, 100.0,
			"demand 是 capacity 的 5× 时 util_pct 应 > 100%% (实际 util=%f, cap=%d, dem=%d)"
			% [util, cap, dem])
