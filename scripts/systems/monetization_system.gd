extends Node

## MonetizationSystem v1 — pure settlement of API + subscription revenue.
## Per design/营收系统设计.md.
##
## Triggered by `users_resolved` (UserSystem → MonetizationSystem chain).
## Reads token_demand, datacenter capacity, model price, products. Awards
## the total to economy and writes a per-source breakdown into
## GameState.last_revenue_breakdown.
##
## §6.2 capacity formula (weekly, 2026-05): 1 turn = 1 week. 所有"_per_month"
## 字段在 weekly tick 下隐式重解读为 "_per_week" (字段名保留兼容旧存档与外部文
## 案, 实际为 per-turn 量). 见 design/营收系统设计.md §6.2.
##   dc_capacity_tokens_per_week = dc.serving_tokens_per_sec
##                               × arch_inference_coef
##                               × product_throughput_multiplier
##                               × SECONDS_PER_WEEK
##   subscription_demand = Σ subscribers × tokens_per_user_per_week
##   api_demand          = api_token_demand[m]                        # UserSystem 写入
##
## Engineering tree multipliers are already baked into dc.serving_tokens_per_sec
## by InfraSystem (v4 PR-B).


const SECONDS_PER_WEEK: int = 604_800   # 7 × 24 × 3600

func _ready() -> void:
	CommandBus.register(&"monetization.preview", _on_preview)
	EventBus.users_resolved.connect(_on_users_resolved)

func _on_preview(_p: Dictionary) -> Dictionary:
	return {ok = true, breakdown = GameState.last_revenue_breakdown}

func _on_users_resolved(turn: int, _delta: int) -> void:
	var breakdown := {
		turn = turn,
		api_total = 0,
		api_per_model = {},
		api_per_product = {},
		subscription_total = 0,
		subscription_per_product = {},
		api_demand_lost = 0,
	}
	_settle_api(breakdown)
	_settle_subscription(breakdown)
	var total: int = int(breakdown.api_total) + int(breakdown.subscription_total)
	if total > 0:
		CommandBus.send(&"economy.award", {
			amount = total, reason = &"monetization",
		})
	GameState.last_revenue_breakdown = breakdown
	EventBus.revenue_resolved.emit(turn, breakdown)
	Log.info(&"monetization", "revenue_resolved", {
		turn = turn,
		api_total = breakdown.api_total,
		sub_total = breakdown.subscription_total,
		demand_lost = breakdown.api_demand_lost,
	})

## §0bis 算力池 + §5.1/§5.2 (v9): 订阅 demand 先占 capacity, 剩余给 api;
## 订阅营收也按 capacity 截断 (新版, 见 _settle_subscription).
## v4 (PR-B): engineering 树乘数 (throughput_multiplier + flops_per_token_reduction)
## 已下沉到 InfraSystem.serving_tokens_per_sec, 本系统不再二次乘 eng_mult.
func _settle_api(breakdown: Dictionary) -> void:
	for m in GameState.models:
		if m.status != &"published":
			continue
		# 2026-05: 玩家开源发布的自训模型 (is_open_source=true) 与公共开源
		# downloaded_os 物化模型都可在玩家机房 serving 并产生 API 营收;
		# 价格不再硬钳, demand 由 api product.subscribers 在 UserSystem 软约束。

		# 1. 找出绑 m 的 api 产品; 没有则跳过 (无 API 营收路径).
		var api_products: Array = []
		var subscription_demand: int = 0
		for prod in GameState.products:
			if prod.bound_model_id != m.id:
				continue
			if "type" in prod and prod.type == &"api":
				api_products.append(prod)
			else:
				subscription_demand += prod.subscribers * _tokens_per_user_for(prod.type)
		if api_products.is_empty():
			continue

		# 2. 算 capacity (tokens/周). v4 (PR-B): dc.serving_tokens_per_sec 已含
		# 模型 flops_per_token + engineering 乘数. 这里只补 arch + product/lead.
		var capacity: float = compute_capacity_for_model(m)

		# 3. 订阅先占 capacity, 剩余给 api. 订阅营收不算 lost.
		var api_capacity: float = maxf(0.0, capacity - float(subscription_demand))

		# 4. api_demand 按周隐式语义读 UserSystem 写入的字段.
		var total_api_demand: float = float(GameState.api_token_demand.get(m.id, 0))
		var n: int = api_products.size()
		var per_api_demand: float = total_api_demand / float(n)
		var ratio: float = 1.0
		if total_api_demand > api_capacity and total_api_demand > 0.0:
			ratio = api_capacity / total_api_demand

		# §5.1bis: 单个 api 产品营收硬封顶 (TAM 天花板). cap <= 0 表示无上限.
		# 封顶是营收侧的市场饱和, 超出部分不计入 api_demand_lost (那是算力短缺桶).
		var cap: int = _revenue_cap_for(&"api")
		var model_api_rev_total: int = 0
		for ap in api_products:
			var served: float = per_api_demand * ratio
			var lost: float = per_api_demand - served
			var rev: int = int(round(served * float(m.per_token_price)))
			if cap > 0 and rev > cap:
				Log.info(&"monetization", "api_revenue_capped", {
					product = ap.id, model = m.id, raw = rev, cap = cap,
				})
				rev = cap
			breakdown.api_per_product[ap.id] = rev
			model_api_rev_total += rev
			breakdown.api_demand_lost = int(breakdown.api_demand_lost) + int(round(lost))
		breakdown.api_per_model[m.id] = model_api_rev_total
		breakdown.api_total = int(breakdown.api_total) + model_api_rev_total

# §6.2: monetization 需要复用 UserSystem 的 tokens-per-user 表来算订阅 demand;
# 直接载入 ProductTypeSpec.tres 取每周 token 用量. Cached per type.
var _tokens_per_user_cache: Dictionary = {}
const _TOKENS_PER_USER_FALLBACK: Dictionary = {
	&"chatbot": 250_000,
	&"agent": 10_000_000,
	&"multimodal_assistant": 1_250_000,
	&"coding_agent": 1_000_000_000,
}
func _tokens_per_user_for(product_type: StringName) -> int:
	if _tokens_per_user_cache.has(product_type):
		return int(_tokens_per_user_cache[product_type])
	var value: int = 0
	var path := "res://resources/data/products/types/%s.tres" % String(product_type)
	if ResourceLoader.exists(path):
		var res := load(path)
		if res is ProductTypeSpec:
			value = (res as ProductTypeSpec).tokens_per_week()
		elif res != null and "tokens_per_user_per_week" in res:
			value = int(res.tokens_per_user_per_week)
		elif res != null and "tokens_per_user_per_month" in res:
			value = int(res.tokens_per_user_per_month)
	if value <= 0 and _TOKENS_PER_USER_FALLBACK.has(product_type):
		value = int(_TOKENS_PER_USER_FALLBACK[product_type])
	_tokens_per_user_cache[product_type] = value
	return value

# §5.1bis: 读 ProductTypeSpec.revenue_cap_per_week (单产品当周营收硬上限).
# 0 / 缺失 = 无上限. Cached per type. 数据单一来源是 .tres, 不在代码里写死.
var _revenue_cap_cache: Dictionary = {}
func _revenue_cap_for(product_type: StringName) -> int:
	if _revenue_cap_cache.has(product_type):
		return int(_revenue_cap_cache[product_type])
	var value: int = 0
	var path := "res://resources/data/products/types/%s.tres" % String(product_type)
	if ResourceLoader.exists(path):
		var res := load(path)
		if res != null and "revenue_cap_per_week" in res:
			value = int(res.revenue_cap_per_week)
	_revenue_cap_cache[product_type] = value
	return value

## §5.2 (v9, 2026-05): 订阅营收按 capacity 截断. 与同 model 上的其他订阅产品
## 共享 ratio = min(1, capacity / total_sub_demand). bound_model 未 published
## 或不存在 → ratio = 0, 订阅营收清零 (orphan 产品).
func _settle_subscription(breakdown: Dictionary) -> void:
	# 1. 按 bound_model 分组所有非 api 订阅产品.
	var sub_by_model: Dictionary = {}   # bound_model_id -> Array[Product]
	for p in GameState.products:
		if "type" in p and p.type == &"api":
			continue
		var bm: StringName = p.bound_model_id
		if not sub_by_model.has(bm):
			sub_by_model[bm] = []
		sub_by_model[bm].append(p)
	# 2. 每组算 ratio 并写营收.
	for bm in sub_by_model.keys():
		var products: Array = sub_by_model[bm]
		var m = _find_published_model(bm)
		if m == null:
			# bound_model 不存在或未 published → 营收清零.
			for p in products:
				breakdown.subscription_per_product[p.id] = 0
			continue
		var capacity: float = compute_capacity_for_model(m)
		var sub_demand: float = 0.0
		for p in products:
			sub_demand += float(p.subscribers) * float(_tokens_per_user_for(p.type))
		var ratio: float = 1.0
		if sub_demand > 0.0:
			ratio = clampf(capacity / sub_demand, 0.0, 1.0)
		else:
			ratio = 0.0 if capacity <= 0.0 else 1.0
		for p in products:
			var raw_rev: float = float(p.subscribers) * float(p.subscription_price) * ratio
			var rev: int = int(round(raw_rev))
			breakdown.subscription_per_product[p.id] = rev
			breakdown.subscription_total = int(breakdown.subscription_total) + rev

func _find_published_model(model_id: StringName):
	if model_id == &"":
		return null
	for m in GameState.models:
		if m.id == model_id and m.status == &"published":
			return m
	return null

## 顶栏「算力」chip 用的"实效总算力 (t/s)" — 把每个 published owned 模型的当周
## capacity 折回 t/s 求和, 再叠加没绑到任何 published owned 模型的 dc 的原始 t/s
## (e.g. 公共 OS 部署、未知 deployed_model)。这是 capacity 的**单一来源**之顶层
## 汇总, 避免 UI 自己 Σ dc.serving_tokens_per_sec 漏掉 arch + chief_engineer 乘数。
## 见 design/营收系统设计.md §3.1。
func total_effective_serving_tps() -> float:
	var total: float = 0.0
	var counted_dc_ids: Dictionary = {}
	for m in GameState.models:
		if m.status != &"published":
			continue
		total += compute_capacity_for_model(m) / float(SECONDS_PER_WEEK)
		for dc in GameState.datacenters:
			if dc.deployed_model_id == m.id:
				counted_dc_ids[dc.id] = true
	for dc in GameState.datacenters:
		if counted_dc_ids.has(dc.id):
			continue
		total += float(dc.serving_tokens_per_sec)
	return total

## 算单个 model 的当周 capacity (tokens/周). 抽公因子: arch.inference_coef ×
## product_throughput_multiplier × Σ dc.serving_tokens_per_sec × SECONDS_PER_WEEK.
## InfraSystem 已经把 engineering 树乘数烤进 dc.serving_tokens_per_sec.
func compute_capacity_for_model(m) -> float:
	var coefs: Dictionary = CommandBus.send(&"tech.get_arch_coefs", {arch_id = m.arch})
	var arch_coef: float = 1.0
	if coefs.get(&"ok", false):
		arch_coef = float(coefs.get(&"inference_coef", 1.0))
	var product_throughput_mult: float = _product_throughput_multiplier(m.id)
	var capacity: float = 0.0
	for dc in GameState.datacenters:
		if dc.deployed_model_id != m.id:
			continue
		var dc_tps: float = _dc_serving_tokens_per_sec(dc)
		capacity += dc_tps * arch_coef * product_throughput_mult * float(SECONDS_PER_WEEK)
	return capacity

# Read the dc's per-deployed-model t/s capacity. `serving_tokens_per_sec`
# is the canonical field, set by infra.deploy_model and kept fresh by
# infra_system._refresh_serving_capacity (buy/sell, engineering unlocks).
func _dc_serving_tokens_per_sec(dc) -> float:
	return float(dc.serving_tokens_per_sec)

func _product_throughput_multiplier(model_id: StringName) -> float:
	var best: float = 1.0
	var table: Dictionary = HiringSystem.LEAD_BONUS_TABLE.get(&"chief_engineer", {})
	var coef: float = float(table.get(&"product_throughput", 0.0))
	if coef <= 0.0:
		return best
	for prod in GameState.products:
		if prod.bound_model_id != model_id or prod.lead_id == &"":
			continue
		var lead = HiringSystem.find_lead(prod.lead_id)
		if lead == null or lead.specialty != &"chief_engineer":
			continue
		var mult: float = 1.0 + (float(lead.ability) / 100.0) * coef
		best = maxf(best, mult)
	return best

# v4 (PR-B, 2026-05): the engineering throughput multiplier moved into
# InfraSystem._refresh_serving_capacity, which bakes it directly into
# dc.serving_tokens_per_sec. MonetizationSystem just reads the dc field now,
# so the legacy _engineering_throughput_multiplier() helper is removed to
# guarantee there's no chance of a second multiplication slipping back in.
