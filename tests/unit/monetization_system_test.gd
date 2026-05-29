extends GutTest

## MonetizationSystem v1 — pure settlement of API + subscription revenue.
## Per design/营收系统设计.md.
##
## Triggered by `users_resolved`; reads token_demand × dc capacity × price.
## Awards total to economy and writes a per-source breakdown into
## GameState.last_revenue_breakdown. These tests pin the breakdown shape,
## §6.1–§6.4 algorithm, and the side-effects on cash / signals.
##
## Capacity formula (§6.2, post-Infra-v3 — model-aware serving capacity is
## already baked into dc.serving_tokens_per_sec at deploy_model time):
##   capacity_tokens_per_week
##     = dc.serving_tokens_per_sec
##       × arch_inference_coef
##       × engineering_throughput_multiplier
##       × product_throughput_multiplier (chief_engineer lead)
##       × SECONDS_PER_WEEK (= 604_800)
##
## Tests directly set `serving_tokens_per_sec` on dcs (skipping deploy_model)
## so capacity is just `dc_tps × SECONDS_PER_WEEK` for the unit math.
## Model-size sensitivity (flops_per_token → t/s scaling) is covered in
## infra_system_test, not here — Monetization no longer reads flops_per_token.


const SECONDS_PER_WEEK: int = 604_800
const BASELINE_FLOPS_PER_TOKEN: float = 1.4e10

var _saved_engineering_coefs_handler: Variant = null

func before_each() -> void:
	GameState.reset()
	# Snapshot the real TechTreeSystem handler so per-test stubs can restore it.
	_saved_engineering_coefs_handler = CommandBus._handlers.get(&"tech.get_engineering_coefs")

func after_each() -> void:
	# Restore the snapshotted handler (or remove if there wasn't one originally).
	if _saved_engineering_coefs_handler != null:
		CommandBus._handlers[&"tech.get_engineering_coefs"] = _saved_engineering_coefs_handler
	elif CommandBus._handlers.has(&"tech.get_engineering_coefs"):
		CommandBus._handlers.erase(&"tech.get_engineering_coefs")

# ---- fixtures -----------------------------------------------------------

func _make_published_model(id: StringName, price: float, is_open_source: bool = false,
		capability: Dictionary = {&"general": 50.0}, arch: StringName = &"ant_v1",
		flops_per_token: float = BASELINE_FLOPS_PER_TOKEN) -> Model:
	var m := Model.new()
	m.id = id
	m.display_name = String(id)
	m.arch = arch
	m.capability = capability
	m.status = &"published"
	m.is_open_source = is_open_source
	m.per_token_price = price
	m.flops_per_token = flops_per_token
	GameState.models.append(m)
	return m

# `capacity_tokens_per_week` is the desired single-dc capacity (assuming
# arch_coef=1, eng_mult=1, no chief-engineer bonus). The fixture back-solves
# `serving_tokens_per_sec` from that — InfraSystem normally would compute it
# inside `infra.deploy_model` from `inference_tflops × 1e12 / model.flops_per_token`,
# but unit tests skip that and write the field directly for arithmetic clarity.
func _make_serving_dc(id: StringName, model_id: StringName,
		capacity_tokens_per_week: float) -> Datacenter:
	var dc := Datacenter.new()
	dc.id = id
	dc.facility_spec_id = &"facility_solo"
	dc.status = &"serving"
	dc.deployed_model_id = model_id
	dc.serving_target_kind = &"owned_model"
	dc.serving_target_id = model_id
	dc.serving_tokens_per_sec = capacity_tokens_per_week / float(SECONDS_PER_WEEK)
	GameState.datacenters.append(dc)
	return dc

func _make_product(id: StringName, type: StringName, price: int, subs: int,
		bound_model: StringName = &"") -> Product:
	var p := Product.new()
	p.id = id
	p.display_name = String(id)
	p.type = type
	p.subscription_price = price
	p.subscribers = subs
	p.bound_model_id = bound_model
	GameState.products.append(p)
	return p

# §0bis: api 产品是 API 营收的开关. 单元测试需要的话用这个 helper 直接造一个,
# 跳过 ProductSystem 的 publish-触发自动 create 流程 (那是 product_system_test
# 的范围).
func _make_api_product(model_id: StringName) -> Product:
	var p := Product.new()
	p.id = StringName("product_api_" + String(model_id))
	p.display_name = "API for " + String(model_id)
	p.type = &"api"
	p.subscription_price = 0
	p.subscribers = 0
	p.bound_model_id = model_id
	p.auto_track_latest = false
	GameState.products.append(p)
	return p

# Stub `tech.get_engineering_coefs` for a single test. Replace=true so we
# don't error on "duplicate handler".
func _stub_engineering_coefs(throughput_multiplier: float) -> void:
	CommandBus.register(&"tech.get_engineering_coefs", func(_p: Dictionary) -> Dictionary:
		return {ok = true, throughput_multiplier = throughput_multiplier}, true)

# ---- §6.1 主入口: 触发与签名 -------------------------------------------

func test_listens_to_users_resolved_and_emits_revenue_resolved() -> void:
	# §4: 订阅 users_resolved, 不订阅 phase_started.
	watch_signals(EventBus)
	EventBus.users_resolved.emit(7, 0)
	assert_signal_emitted(EventBus, "revenue_resolved")
	var params: Array = get_signal_parameters(EventBus, "revenue_resolved")
	assert_eq(params[0], 7, "revenue_resolved 第一参数应为 turn")
	var br: Dictionary = params[1]
	assert_true(br is Dictionary)

func test_breakdown_has_all_seven_keys_per_design() -> void:
	# §1: breakdown 字典应包含 turn / api_total / api_per_model / api_per_product /
	# subscription_total / subscription_per_product / api_demand_lost.
	EventBus.users_resolved.emit(3, 0)
	var br: Dictionary = GameState.last_revenue_breakdown
	for k in [&"turn", &"api_total", &"api_per_model", &"api_per_product",
			&"subscription_total", &"subscription_per_product", &"api_demand_lost"]:
		assert_true(br.has(k), "breakdown 缺少键 %s" % k)

func test_breakdown_turn_matches_users_resolved_turn() -> void:
	EventBus.users_resolved.emit(42, 0)
	assert_eq(int(GameState.last_revenue_breakdown.turn), 42)

func test_zero_state_emits_zero_breakdown_and_no_award() -> void:
	# 没有 model / product / dc, 不应调 economy.award (total == 0).
	var before: int = GameState.cash
	EventBus.users_resolved.emit(1, 0)
	var br: Dictionary = GameState.last_revenue_breakdown
	assert_eq(int(br.api_total), 0)
	assert_eq(int(br.subscription_total), 0)
	assert_eq(GameState.cash, before, "零营收时不应触发 award")

# ---- §6.2 API 营收 -----------------------------------------------------

func test_api_revenue_equals_demand_times_price_when_capacity_sufficient() -> void:
	# §6.2: api 产品 demand 满足 → served = demand, rev = served × price.
	# baseline model + capacity 1e9 tokens/月, demand 10k, 单 api 产品.
	var m: Model = _make_published_model(&"m1", 0.01)
	_make_serving_dc(&"dc1", m.id, 1_000_000_000.0)
	_make_api_product(m.id)
	GameState.api_token_demand[m.id] = 10_000   # 无订阅产品, 全是 api demand
	EventBus.users_resolved.emit(1, 0)
	var br: Dictionary = GameState.last_revenue_breakdown
	# 10000 × 0.01 = 100
	assert_eq(int(br.api_per_model[m.id]), 100)
	assert_eq(int(br.api_total), 100)
	assert_eq(int(br.api_demand_lost), 0)

func test_api_revenue_capped_by_capacity_records_lost_demand() -> void:
	# §6.2: lost = max(0, api_demand - api_capacity); 算力不足时丢 api 需求.
	var m: Model = _make_published_model(&"m1", 0.01)
	_make_serving_dc(&"dc1", m.id, 1_000.0)   # capacity = 1000 tokens/月
	_make_api_product(m.id)
	GameState.api_token_demand[m.id] = 5_000   # api demand > capacity
	EventBus.users_resolved.emit(1, 0)
	var br: Dictionary = GameState.last_revenue_breakdown
	# served = 1000 → rev = 1000 × 0.01 = 10; lost = 4000.
	assert_eq(int(br.api_per_model[m.id]), 10)
	assert_eq(int(br.api_demand_lost), 4_000)

func test_api_capacity_sums_across_multiple_dcs_for_same_model() -> void:
	# §6.2: 累加所有 deployed_model_id == m.id 的 dc; 多 dc 容量相加.
	var m: Model = _make_published_model(&"m1", 0.001)
	_make_serving_dc(&"dc1", m.id, 30_000.0)
	_make_serving_dc(&"dc2", m.id, 20_000.0)
	_make_api_product(m.id)
	GameState.api_token_demand[m.id] = 60_000   # cap = 50000
	EventBus.users_resolved.emit(1, 0)
	var br: Dictionary = GameState.last_revenue_breakdown
	# served = 50000 → rev = 50.0 → round → 50
	assert_eq(int(br.api_per_model[m.id]), 50)
	assert_eq(int(br.api_demand_lost), 10_000)

func test_published_model_without_api_product_yields_zero_api_revenue() -> void:
	# §0bis: api 是产品 — 没建 api 产品时该 model 没 API 营收, 也不计 lost.
	var m: Model = _make_published_model(&"m1", 0.01)
	_make_serving_dc(&"dc1", m.id, 1_000_000_000.0)
	# 不调 _make_api_product
	GameState.api_token_demand[m.id] = 10_000
	EventBus.users_resolved.emit(1, 0)
	var br: Dictionary = GameState.last_revenue_breakdown
	assert_eq(int(br.api_total), 0)
	assert_eq(int(br.api_demand_lost), 0,
			"无 api 产品时不应有 lost demand: 玩家压根没在卖 API")
	assert_false(br.api_per_model.has(m.id),
			"无 api 产品时不应在 api_per_model 出现")

func test_api_skips_unpublished_models() -> void:
	# §6.2: 仅 status == &"published" 计入.
	var m: Model = _make_published_model(&"m1", 0.01)
	m.status = &"pretrained"
	_make_serving_dc(&"dc1", m.id, 1_000_000_000.0)
	_make_api_product(m.id)
	GameState.api_token_demand[m.id] = 10_000
	EventBus.users_resolved.emit(1, 0)
	var br: Dictionary = GameState.last_revenue_breakdown
	assert_false(br.api_per_model.has(m.id), "internal model 不应进 breakdown")
	assert_eq(int(br.api_total), 0)

func test_open_source_model_produces_api_revenue() -> void:
	# §6.2 (v6 PR-E, 2026-05): 玩家开源发布的自训模型仍可在自己机房 serving
	# 并产生 API 营收, 价格不再硬钳 — 改由 Model.demand_multiplier 软上限.
	var m: Model = _make_published_model(&"m_oss", 0.01, true)
	_make_serving_dc(&"dc1", m.id, 1_000_000_000.0)
	_make_api_product(m.id)
	GameState.api_token_demand[m.id] = 10_000
	EventBus.users_resolved.emit(1, 0)
	var br: Dictionary = GameState.last_revenue_breakdown
	assert_eq(int(br.api_per_model[m.id]), 100,
			"open-source published model 仍参与 API 结算 (10000 × 0.01 = 100)")

func test_downloaded_os_published_model_produces_api_revenue() -> void:
	# 公共开源 release 物化成 downloaded_os published model 后, 与玩家开源模型
	# 走同一 API 产品 / 需求 / 营收管道。
	var m: Model = _make_published_model(&"m_downloaded_os", 0.01, true)
	m.provenance = &"downloaded_os"
	m.source_release_id = &"release_wolf_1"
	_make_serving_dc(&"dc1", m.id, 1_000_000_000.0)
	_make_api_product(m.id)
	GameState.api_token_demand[m.id] = 10_000
	EventBus.users_resolved.emit(1, 0)
	var br: Dictionary = GameState.last_revenue_breakdown
	assert_eq(int(br.api_per_model[m.id]), 100,
			"downloaded_os published model 应参与 API 结算 (10000 × 0.01 = 100)")

func test_api_no_dc_deployed_means_zero_capacity_full_loss() -> void:
	# §6.2 边界: 无对应 dc → capacity = 0 → 全部丢.
	var m: Model = _make_published_model(&"m1", 0.01)
	_make_api_product(m.id)
	GameState.api_token_demand[m.id] = 5_000
	EventBus.users_resolved.emit(1, 0)
	var br: Dictionary = GameState.last_revenue_breakdown
	assert_eq(int(br.api_per_model[m.id]), 0)
	assert_eq(int(br.api_demand_lost), 5_000)

func test_api_demand_zero_means_zero_revenue_zero_loss() -> void:
	var m: Model = _make_published_model(&"m1", 0.01)
	_make_serving_dc(&"dc1", m.id, 1_000_000_000.0)
	_make_api_product(m.id)
	# token_demand 没设过 (默认 0)
	EventBus.users_resolved.emit(1, 0)
	var br: Dictionary = GameState.last_revenue_breakdown
	assert_eq(int(br.api_per_model[m.id]), 0)
	assert_eq(int(br.api_demand_lost), 0)

func test_api_total_sums_across_models() -> void:
	# 多 model 的 api_total 是 per_model 之和.
	var m1: Model = _make_published_model(&"m1", 0.01)
	var m2: Model = _make_published_model(&"m2", 0.02)
	_make_serving_dc(&"dc1", m1.id, 1_000_000_000.0)
	_make_serving_dc(&"dc2", m2.id, 1_000_000_000.0)
	_make_api_product(m1.id)
	_make_api_product(m2.id)
	GameState.api_token_demand[m1.id] = 1000  # 1000×0.01 = 10
	GameState.api_token_demand[m2.id] = 500   # 500×0.02 = 10
	EventBus.users_resolved.emit(1, 0)
	var br: Dictionary = GameState.last_revenue_breakdown
	assert_eq(int(br.api_per_model[m1.id]), 10)
	assert_eq(int(br.api_per_model[m2.id]), 10)
	assert_eq(int(br.api_total), 20)

func test_dc_pointing_at_undeployed_model_is_ignored_for_capacity() -> void:
	# §6.2: 只看 deployed_model_id == m.id 的 dc.
	var m1: Model = _make_published_model(&"m1", 0.01)
	var m2: Model = _make_published_model(&"m2", 0.01)
	_make_serving_dc(&"dc1", m2.id, 1_000_000_000.0)  # 不属于 m1
	_make_api_product(m1.id)
	GameState.api_token_demand[m1.id] = 5_000
	EventBus.users_resolved.emit(1, 0)
	var br: Dictionary = GameState.last_revenue_breakdown
	# m1 没有 dc → 全丢
	assert_eq(int(br.api_per_model[m1.id]), 0)
	assert_eq(int(br.api_demand_lost), 5_000)

# ---- §6.2 capacity formula invariants ----------------------------------

func test_seconds_per_week_constant_value() -> void:
	# §6.2: SECONDS_PER_WEEK = 30 × 24 × 3600.
	const MS = preload("res://scripts/systems/monetization_system.gd")
	assert_eq(MS.SECONDS_PER_WEEK, 604_800)

func test_monetization_does_not_rescale_by_flops_per_token() -> void:
	# §6.2 (v3): model 大小已经在 deploy_model 时折进 serving_tokens_per_sec, 营收
	# 系统不再二次缩放. 同一个 dc 容量, 不论 model.flops_per_token 是多少,
	# capacity 只看 serving_tokens_per_sec.
	var m_small: Model = _make_published_model(&"m_small", 0.01, false,
			{&"general": 50.0}, &"ant_v1", BASELINE_FLOPS_PER_TOKEN)
	var m_large: Model = _make_published_model(&"m_large", 0.01, false,
			{&"general": 50.0}, &"ant_v1", BASELINE_FLOPS_PER_TOKEN * 10.0)
	# 两个 dc 都被 fixture 写成同样的 serving_tokens_per_sec → 容量 1000 t/月.
	_make_serving_dc(&"dc1", m_small.id, 1_000.0)
	_make_serving_dc(&"dc2", m_large.id, 1_000.0)
	_make_api_product(m_small.id)
	_make_api_product(m_large.id)
	GameState.api_token_demand[m_small.id] = 1_000
	GameState.api_token_demand[m_large.id] = 1_000
	EventBus.users_resolved.emit(1, 0)
	var br: Dictionary = GameState.last_revenue_breakdown
	# 关键不变量: 两 model 都被 100% 满足, 因为容量都 ≥ demand.
	# 旧实现里大模型 capacity 会缩 10×, 现在不缩.
	assert_eq(int(br.api_per_model[m_small.id]), 10)
	assert_eq(int(br.api_per_model[m_large.id]), 10)
	assert_eq(int(br.api_demand_lost), 0,
			"v3 不再做 BASELINE/flops_per_token 缩放, 大模型不会再被吃掉容量")

func test_engineering_throughput_multiplier_no_longer_double_counted_in_monetization() -> void:
	# v4 (PR-B): engineering throughput multiplier moved INTO dc.serving_tokens_per_sec
	# (computed by InfraSystem). MonetizationSystem must NOT multiply by it again.
	# This test stubs eng_mult=1.5 but constructs the dc with serving_t/s already
	# at 1000 (as if engineering hadn't been baked in yet) — monetization should
	# treat 1000 as the source of truth, NOT scale to 1500.
	_stub_engineering_coefs(1.5)
	var m: Model = _make_published_model(&"m1", 0.01)
	_make_serving_dc(&"dc1", m.id, 1_000.0)
	_make_api_product(m.id)
	GameState.api_token_demand[m.id] = 2_000
	EventBus.users_resolved.emit(1, 0)
	var br: Dictionary = GameState.last_revenue_breakdown
	# v4: capacity = 1000 (no second multiply) → served = 1000 → rev = 10
	assert_eq(int(br.api_per_model[m.id]), 10)
	assert_eq(int(br.api_demand_lost), 1000)

func test_chief_engineer_product_throughput_scales_bound_model_capacity() -> void:
	# 2026-05 rev: chief_engineer.product_throughput = 0.22; ability=100 → ×1.22.
	# capacity 1000 × 1.22 = 1220 → served = min(1220, 1500) = 1220, lost = 280.
	var m: Model = _make_published_model(&"m_prod", 0.01)
	_make_serving_dc(&"dc1", m.id, 1_000.0)
	var lead := Lead.new()
	lead.id = &"lead_ce_prod"
	lead.specialty = &"chief_engineer"
	lead.ability = 100.0
	GameState.leads.append(lead)
	# product_throughput bonus 仍由 chatbot/agent 上的 lead 提供, 不限 api 产品.
	# 但 api 产品自己也可以挂 lead, 等价行为. 用 api 产品 + lead.
	var ap := _make_api_product(m.id)
	ap.lead_id = lead.id
	GameState.api_token_demand[m.id] = 1_500
	EventBus.users_resolved.emit(1, 0)
	var br: Dictionary = GameState.last_revenue_breakdown
	assert_eq(int(br.api_per_model[m.id]), 12)
	assert_eq(int(br.api_demand_lost), 280)

func test_capacity_unaffected_when_engineering_command_missing() -> void:
	# v4 (PR-B): with the engineering multiplier removed from monetization,
	# whether tech.get_engineering_coefs is registered or not has no effect on
	# api capacity here — the only thing that matters is dc.serving_tokens_per_sec.
	if CommandBus._handlers.has(&"tech.get_engineering_coefs"):
		CommandBus._handlers.erase(&"tech.get_engineering_coefs")
	assert_false(CommandBus._handlers.has(&"tech.get_engineering_coefs"))
	var m: Model = _make_published_model(&"m1", 0.01)
	_make_serving_dc(&"dc1", m.id, 1_000.0)
	_make_api_product(m.id)
	GameState.api_token_demand[m.id] = 2_000
	EventBus.users_resolved.emit(1, 0)
	var br: Dictionary = GameState.last_revenue_breakdown
	# capacity = 1000 (from dc.serving_tokens_per_sec) → served = 1000, lost = 1000
	assert_eq(int(br.api_per_model[m.id]), 10)
	assert_eq(int(br.api_demand_lost), 1000)

func test_capacity_uses_serving_tokens_per_sec_field() -> void:
	# §6.2 (v3): 容量字段是 dc.serving_tokens_per_sec (deploy_model 写, 月度 settle 读).
	var m: Model = _make_published_model(&"m1", 0.0)
	var dc := Datacenter.new()
	dc.id = &"dc1"
	dc.facility_spec_id = &"facility_solo"
	dc.status = &"serving"
	dc.deployed_model_id = m.id
	dc.serving_tokens_per_sec = 1.0   # 1 token/sec → 604_800 tokens/月
	GameState.datacenters.append(dc)
	_make_api_product(m.id)
	GameState.api_token_demand[m.id] = 3_000_000
	EventBus.users_resolved.emit(1, 0)
	# capacity = 604_800; served = 604_800; lost = 408_000.
	var br: Dictionary = GameState.last_revenue_breakdown
	assert_eq(int(br.api_demand_lost), 3_000_000 - SECONDS_PER_WEEK)

# ---- §6.3 订阅营收 ------------------------------------------------------

func test_subscription_revenue_is_subscribers_times_price_when_capacity_sufficient() -> void:
	# §5.2 (v9): capacity 充足时 rev = subscribers × subscription_price.
	# 给 p1 绑定一个充足容量的 dc 才能拿全订阅营收。
	var m: Model = _make_published_model(&"m1", 0.01)
	_make_serving_dc(&"dc1", m.id, 1.0e15)  # 远大于 1000 用户的 chatbot demand
	_make_product(&"p1", &"chatbot", 99, 1000, m.id)
	EventBus.users_resolved.emit(1, 0)
	var br: Dictionary = GameState.last_revenue_breakdown
	assert_eq(int(br.subscription_per_product[&"p1"]), 99_000)
	assert_eq(int(br.subscription_total), 99_000)

func test_subscription_total_sums_across_products() -> void:
	# §5.2 (v9): 多产品时仍按各自 ratio 截断, 此处 capacity 充足 → ratio = 1.
	var m: Model = _make_published_model(&"m1", 0.01)
	_make_serving_dc(&"dc1", m.id, 1.0e15)
	_make_product(&"p1", &"chatbot", 99, 100, m.id)   # 9900
	_make_product(&"p2", &"agent", 199, 50, m.id)     # 9950
	EventBus.users_resolved.emit(1, 0)
	var br: Dictionary = GameState.last_revenue_breakdown
	assert_eq(int(br.subscription_per_product[&"p1"]), 9_900)
	assert_eq(int(br.subscription_per_product[&"p2"]), 9_950)
	assert_eq(int(br.subscription_total), 19_850)

func test_subscription_zero_subscribers_yields_zero_per_product() -> void:
	var m: Model = _make_published_model(&"m1", 0.01)
	_make_serving_dc(&"dc1", m.id, 1.0e15)
	_make_product(&"p1", &"chatbot", 99, 0, m.id)
	EventBus.users_resolved.emit(1, 0)
	var br: Dictionary = GameState.last_revenue_breakdown
	assert_eq(int(br.subscription_per_product[&"p1"]), 0)
	assert_eq(int(br.subscription_total), 0)

func test_subscription_revenue_capped_by_capacity() -> void:
	# §5.2 (v9): capacity < sub_demand → revenue × (capacity / sub_demand).
	# 设置: chatbot 每用户 250K tok/周 (2026-05 ×5), 500 用户 → demand = 125M tok/周.
	# Capacity = 62.5M tok/周 → ratio = 0.5 → revenue 砍半.
	var m: Model = _make_published_model(&"m1", 0.01)
	_make_serving_dc(&"dc1", m.id, 62_500_000.0)
	_make_product(&"p1", &"chatbot", 99, 500, m.id)
	EventBus.users_resolved.emit(1, 0)
	var br: Dictionary = GameState.last_revenue_breakdown
	# 500 × 99 = 49,500; ratio = 0.5 → 24,750.
	assert_eq(int(br.subscription_per_product[&"p1"]), 24_750,
			"算力 50% → 订阅营收应砍半")
	assert_eq(int(br.subscription_total), 24_750)

func test_subscription_revenue_zero_when_no_capacity() -> void:
	# §5.2 (v9): 没 dc 部署 → 订阅营收清零 (而不是全收).
	var m: Model = _make_published_model(&"m1", 0.01)
	# 故意不部署 dc.
	_make_product(&"p1", &"chatbot", 99, 500, m.id)
	EventBus.users_resolved.emit(1, 0)
	var br: Dictionary = GameState.last_revenue_breakdown
	assert_eq(int(br.subscription_per_product[&"p1"]), 0,
			"无 dc → 订阅营收清零, 不再白嫖")
	assert_eq(int(br.subscription_total), 0)

func test_subscription_ratio_shared_across_products_on_same_model() -> void:
	# §5.2 (v9): 同 model 多个订阅产品共享 ratio. 总 sub_demand 与 capacity 算 ratio,
	# 然后每个 product 都按这个 ratio 砍.
	var m: Model = _make_published_model(&"m1", 0.01)
	# p1: chatbot × 200 → 200 × 250K = 50M; p2: chatbot × 200 → 50M; total 100M
	# (2026-05 ×5). capacity 50M → ratio = 0.5
	_make_serving_dc(&"dc1", m.id, 50_000_000.0)
	_make_product(&"p1", &"chatbot", 100, 200, m.id)  # 20,000 × 0.5 = 10,000
	_make_product(&"p2", &"chatbot", 50,  200, m.id)  # 10,000 × 0.5 = 5,000
	EventBus.users_resolved.emit(1, 0)
	var br: Dictionary = GameState.last_revenue_breakdown
	assert_eq(int(br.subscription_per_product[&"p1"]), 10_000)
	assert_eq(int(br.subscription_per_product[&"p2"]), 5_000)
	assert_eq(int(br.subscription_total), 15_000)

# ---- §6.1 总入账 + 信号 ------------------------------------------------

func test_total_revenue_credited_to_cash_via_economy_award() -> void:
	# §6.1: total > 0 → economy.award({reason: monetization})
	GameState.cash = 0
	GameState.resources[&"money"] = 0
	var m: Model = _make_published_model(&"m1", 0.01)
	_make_serving_dc(&"dc1", m.id, 1.0e15)
	_make_product(&"p1", &"chatbot", 99, 1000, m.id)
	EventBus.users_resolved.emit(1, 0)
	assert_eq(GameState.cash, 99_000, "subscription 应进 cash")
	assert_eq(GameState.resources[&"money"], 99_000)

func test_award_reason_is_monetization() -> void:
	var m: Model = _make_published_model(&"m1", 0.01)
	_make_serving_dc(&"dc1", m.id, 1.0e15)
	_make_product(&"p1", &"chatbot", 99, 100, m.id)
	watch_signals(EventBus)
	EventBus.users_resolved.emit(1, 0)
	# resources_changed(delta, reason) — 期望 reason == &"monetization"
	var emitted_with_correct_reason: bool = false
	for i in range(get_signal_emit_count(EventBus, "resources_changed")):
		var p: Array = get_signal_parameters(EventBus, "resources_changed", i)
		if p[1] == &"monetization":
			emitted_with_correct_reason = true
			break
	assert_true(emitted_with_correct_reason, "应有 reason=monetization 的 resources_changed")

func test_no_award_when_total_is_zero() -> void:
	# §6.1: if total > 0; 否则不调 award.
	var before: int = GameState.cash
	# 只放 internal model + 0 用户
	var m: Model = _make_published_model(&"m1", 0.01)
	m.status = &"pretrained"
	EventBus.users_resolved.emit(1, 0)
	assert_eq(GameState.cash, before, "全零状态不应增加 cash")

func test_revenue_resolved_payload_matches_breakdown_in_state() -> void:
	# §3 信号: revenue_resolved(turn, breakdown) — 和 GameState.last_revenue_breakdown 同源.
	_make_product(&"p1", &"chatbot", 99, 100)
	watch_signals(EventBus)
	EventBus.users_resolved.emit(5, 0)
	var p: Array = get_signal_parameters(EventBus, "revenue_resolved")
	var emitted_breakdown: Dictionary = p[1]
	assert_eq(int(emitted_breakdown.subscription_total),
			int(GameState.last_revenue_breakdown.subscription_total))

# ---- §6.4 推理 / 工程优化乘数 (legacy fallback) -------------------------

func test_unlocks_dict_does_not_retroactively_change_monetization() -> void:
	# v4 (PR-B): flipping GameState.unlocks[&"engineering"][&"owl_cache"] = true
	# does NOT change monetization capacity directly — the unlock must flow
	# through tech.unlock_node → tech_unlocked signal → InfraSystem recomputes
	# dc.serving_tokens_per_sec. Setting the dict alone leaves serving_t/s stale
	# and so monetization sees the original 1000 t/s.
	var m: Model = _make_published_model(&"m1", 0.0)
	_make_serving_dc(&"dc1", m.id, 1_000.0)
	_make_api_product(m.id)
	GameState.api_token_demand[m.id] = 1_300
	EventBus.users_resolved.emit(1, 0)
	assert_eq(int(GameState.last_revenue_breakdown.api_demand_lost), 300)
	# Mutate the dict directly (bypasses InfraSystem's recompute path).
	GameState.unlocks[&"engineering"][&"owl_cache"] = true
	EventBus.users_resolved.emit(2, 0)
	# Monetization still sees the cached 1000 t/s — boost is the proper unlock
	# path's job (covered by infra_system_test's tech_unlocked test).
	assert_eq(int(GameState.last_revenue_breakdown.api_demand_lost), 300)

# ---- §0bis 算力池: subscription-priority + 多 api 比例分配 -------------

func test_subscription_priority_eats_capacity_first_api_gets_remainder() -> void:
	# §0bis: 订阅产品 demand 先占 capacity, api 拿剩下的.
	# 2026-05 ×5: chatbot 1 user × 2.5e5 tokens/周 = 2.5e5 sub demand;
	# capacity = 3e5; api_capacity = 3e5 - 2.5e5 = 5e4;
	# api_demand 注入 8e4 → api_served = 5e4, lost = 3e4. price ×1000 保持 rev=50.
	var m: Model = _make_published_model(&"m1", 1e-3)
	_make_serving_dc(&"dc1", m.id, 3e5)         # cap 3e5 tokens/周
	_make_product(&"p_chat", &"chatbot", 99, 1, m.id)  # 1 user × 2.5e5
	_make_api_product(m.id)
	GameState.api_token_demand[m.id] = 8e4      # 超过剩余 5e4
	EventBus.users_resolved.emit(1, 0)
	var br: Dictionary = GameState.last_revenue_breakdown
	# api_served = 5e4, rev = 5e4 × 1e-3 = 50; lost = 3e4;
	# 订阅 rev = 1 × 99 = 99, 不受算力影响.
	assert_eq(int(br.api_per_model[m.id]), 50)
	assert_eq(int(br.api_demand_lost), 30_000)
	assert_eq(int(br.subscription_total), 99)

func test_subscription_demand_exceeds_capacity_revenue_scales_down() -> void:
	# §5.2 (v9): 订阅 demand 超 capacity → 营收按 ratio 缩减.
	# 准备: chatbot 1000 用户 × 5e4 = 5e7 tokens/周; capacity = 1000 tok/周;
	# ratio = 1000 / 5e7 = 2e-5 → revenue ≈ 1000 × 99 × 2e-5 ≈ 2 (round).
	# api demand 0 → lost = 0.
	var m: Model = _make_published_model(&"m1", 1.0)
	_make_serving_dc(&"dc1", m.id, 1_000.0)
	_make_product(&"p_chat", &"chatbot", 99, 1000, m.id)
	_make_api_product(m.id)
	EventBus.users_resolved.emit(1, 0)
	var br: Dictionary = GameState.last_revenue_breakdown
	# 极度算力短缺 → 营收基本清零 (而不是 99_000).
	assert_lt(int(br.subscription_total), 100,
			"算力远不够时, 订阅营收应被 ratio 砍到接近 0; 旧版的 99_000 已废.")
	assert_eq(int(br.api_demand_lost), 0, "无 api demand 时 lost = 0")

func test_two_api_products_split_capacity_proportionally() -> void:
	# §0bis: 多个 api 产品绑同一 model 时按 demand 比例分配 (单 api/model 是默认
	# 约束, 但 monetization 算法仍要正确处理多 api 边界 — 单元测试绕过
	# ProductSystem 直接塞两个 api 产品).
	# token_demand[m.id] 是该 model 的总 api demand; 多 api 产品按 1/N 等分需求.
	var m: Model = _make_published_model(&"m1", 1.0)
	_make_serving_dc(&"dc1", m.id, 1_000.0)
	var a1 := Product.new()
	a1.id = &"api_1"; a1.type = &"api"; a1.bound_model_id = m.id
	GameState.products.append(a1)
	var a2 := Product.new()
	a2.id = &"api_2"; a2.type = &"api"; a2.bound_model_id = m.id
	GameState.products.append(a2)
	GameState.api_token_demand[m.id] = 1_600   # 总 api demand = 1600, cap = 1000
	EventBus.users_resolved.emit(1, 0)
	var br: Dictionary = GameState.last_revenue_breakdown
	# total_served = min(1600, 1000) = 1000; lost = 600.
	# per-api demand = 800 each; per-api served = 800 × (1000/1600) = 500;
	# per-api rev = 500 × 1.0 = 500.
	assert_eq(int(br.api_per_model[m.id]), 1000)
	assert_eq(int(br.api_demand_lost), 600)
	var rev1: int = int(br.api_per_product.get(&"api_1", 0))
	var rev2: int = int(br.api_per_product.get(&"api_2", 0))
	assert_almost_eq(rev1, 500, 1)
	assert_almost_eq(rev2, 500, 1)

# ---- §5.1bis API 营收硬上限 (TAM 天花板) -------------------------------

# api.tres 配置的单产品营收上限 (数据单一来源). 0 = 无上限.
func _api_revenue_cap() -> int:
	var spec = load("res://resources/data/products/types/api.tres")
	return int(spec.revenue_cap_per_week)

func test_api_revenue_hard_capped_per_product() -> void:
	# §5.1bis: served × price 超过 cap 时硬封顶在 cap; 不计入 api_demand_lost
	# (封顶是营收侧的市场饱和, 不是算力短缺).
	var cap: int = _api_revenue_cap()
	assert_gt(cap, 0, "api.tres 应配置 revenue_cap_per_week > 0")
	var m: Model = _make_published_model(&"m1", 1.0)   # 单价 1.0/token
	# 容量与需求都给到 2×cap 个 token → 原始营收 = 2×cap, 应被砍到 cap.
	_make_serving_dc(&"dc1", m.id, float(cap) * 2.0)
	_make_api_product(m.id)
	GameState.api_token_demand[m.id] = cap * 2
	EventBus.users_resolved.emit(1, 0)
	var br: Dictionary = GameState.last_revenue_breakdown
	assert_eq(int(br.api_per_model[m.id]), cap, "单个 api 产品营收应硬封顶在 cap")
	assert_eq(int(br.api_total), cap)
	assert_eq(int(br.api_demand_lost), 0,
			"营收封顶不是算力短缺, 不应计入 api_demand_lost")

func test_api_revenue_below_cap_unaffected() -> void:
	# §5.1bis: 低于 cap 的营收原样保留, 封顶不影响正常路径.
	var cap: int = _api_revenue_cap()
	var amt: int = cap / 2
	var m: Model = _make_published_model(&"m1", 1.0)
	_make_serving_dc(&"dc1", m.id, float(amt))
	_make_api_product(m.id)
	GameState.api_token_demand[m.id] = amt
	EventBus.users_resolved.emit(1, 0)
	var br: Dictionary = GameState.last_revenue_breakdown
	assert_eq(int(br.api_per_model[m.id]), amt, "低于 cap 的 api 营收不受封顶影响")

func test_api_cap_is_per_product_not_global() -> void:
	# §5.1bis: cap 是 per-product (= per-model) 粒度; 两个模型各自封顶在 cap,
	# 总 API 营收 = 2×cap, 随模型数量线性叠加.
	var cap: int = _api_revenue_cap()
	var m1: Model = _make_published_model(&"m1", 1.0)
	var m2: Model = _make_published_model(&"m2", 1.0)
	_make_serving_dc(&"dc1", m1.id, float(cap) * 2.0)
	_make_serving_dc(&"dc2", m2.id, float(cap) * 2.0)
	_make_api_product(m1.id)
	_make_api_product(m2.id)
	GameState.api_token_demand[m1.id] = cap * 2
	GameState.api_token_demand[m2.id] = cap * 2
	EventBus.users_resolved.emit(1, 0)
	var br: Dictionary = GameState.last_revenue_breakdown
	assert_eq(int(br.api_per_model[m1.id]), cap)
	assert_eq(int(br.api_per_model[m2.id]), cap)
	assert_eq(int(br.api_total), cap * 2,
			"cap 是 per-product, 总 API 营收随模型数线性增长")

func test_api_per_product_breakdown_populated() -> void:
	# §1: breakdown.api_per_product 是新字段, 列出每个 api 产品的营收.
	var m: Model = _make_published_model(&"m1", 0.01)
	_make_serving_dc(&"dc1", m.id, 1_000_000.0)
	var ap := _make_api_product(m.id)
	GameState.api_token_demand[m.id] = 5_000
	EventBus.users_resolved.emit(1, 0)
	var br: Dictionary = GameState.last_revenue_breakdown
	assert_true(br.has(&"api_per_product"))
	assert_true(br.api_per_product.has(ap.id))
	assert_eq(int(br.api_per_product[ap.id]), 50)  # 5000 × 0.01 = 50

# ---- §2 monetization.preview --------------------------------------------

func test_preview_returns_current_breakdown() -> void:
	# §2: monetization.preview 是纯读, 返回 last_revenue_breakdown.
	var m: Model = _make_published_model(&"m1", 0.01)
	_make_serving_dc(&"dc1", m.id, 1.0e15)
	_make_product(&"p1", &"chatbot", 99, 100, m.id)
	EventBus.users_resolved.emit(8, 0)
	var r: Dictionary = CommandBus.send(&"monetization.preview", {})
	assert_true(r.ok)
	assert_eq(int(r.breakdown.subscription_total), 9_900)
	assert_eq(int(r.breakdown.turn), 8)

func test_preview_before_any_resolve_returns_empty() -> void:
	# 没跑过结算前, last_revenue_breakdown 是 {}.
	var r: Dictionary = CommandBus.send(&"monetization.preview", {})
	assert_true(r.ok)
	assert_true((r.breakdown as Dictionary).is_empty())
