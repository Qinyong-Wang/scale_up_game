extends Object

## ProductCard helper — 把 Product resource 翻译成 Card.set_data 字典。
##
## api vs subscription 字段集不同, 但都有 编辑 + 下架 actions。

# 值为 i18n key (const 不能调 tr); "API" 非 key, _t 原样返回。取用处 _t()。
const _TYPE_LABELS: Dictionary = {
	&"chatbot": "PRODUCT_TYPE_CHATBOT",
	&"agent": "PRODUCT_TYPE_AGENT",
	&"api": "API",
	&"multimodal_assistant": "PRODUCT_TYPE_MULTIMODAL",
	&"coding_agent": "PRODUCT_TYPE_CODING",
}

# static 上下文没有 self, 不能调 tr(); 走 TranslationServer (同样含 fallback)。
static func _t(key: String) -> String:
	return TranslationServer.translate(key)

## v8 PR-I: 可选 `pricing` Dictionary 传入定价上下文 — API 卡片含
##   {base_price, guidance_price}; 订阅卡片含 {sub_guidance}。
## v7 PR-F3+: 可选 `rate` Dictionary (UserSystem.compute_rate_breakdown 输出)
## — 展示每周增长率分项 + 营销/基础引流。
## 见 design/产品系统设计.md ProductCard 显示契约。
static func populate(card: Control, p, api_price_per_token: float, api_demand_per_week: int, last_revenue: int, sub_tokens_per_sec: int, pricing: Dictionary = {}, rate: Dictionary = {}, model_label: String = "") -> void:
	card.set_data(_build(p, api_price_per_token, api_demand_per_week, last_revenue, sub_tokens_per_sec, pricing, rate, model_label))

static func _build(p, api_price_per_token: float, api_demand_per_week: int, last_revenue: int, sub_tokens_per_sec: int, pricing: Dictionary, rate: Dictionary = {}, model_label: String = "") -> Dictionary:
	var type: StringName = StringName(p.type)
	var is_api := type == &"api"
	var bound_label: String = model_label if model_label != "" else String(p.bound_model_id)
	# api 卡片标题保留 [API] 前缀 — 老集成测试 _has_text_containing(labels, "[API]") 依赖。
	var display_name := String(p.display_name)
	if is_api and String(p.bound_model_id) != "" and display_name.find(String(p.bound_model_id)) != -1:
		display_name = "%s API" % bound_label
	var title: String = ("%s [API]" if is_api else "%s") % display_name
	return {
		"title": title,
		"subtitle": _t("PRODUCT_SUBTITLE") % [_t(_TYPE_LABELS.get(type, String(type))), bound_label],
		"avatar": {
			"texture": IconRegistry.get_icon(&"product", type),
			"fallback_text": String(p.display_name),
			"seed_id": StringName(p.id),
			"kind": &"model",   # 缺图回退仍复用 model glyph (◉)
		},
		"status": {"label": _t(_TYPE_LABELS.get(type, String(type))), "kind": _status_kind(type)},
		"fields": _fields(p, is_api, api_price_per_token, api_demand_per_week, last_revenue, sub_tokens_per_sec, pricing, rate),
		"actions": [
			{"id": &"edit",   "label": _t("PRODUCT_EDIT")},
			{"id": &"delete", "label": _t("MODEL_UNPUBLISH")},
		],
	}

static func _status_kind(type: StringName) -> StringName:
	if type == &"api":
		return &"info"
	return &"published"

static func _fields(p, is_api: bool, api_price: float, api_demand: int, last_rev: int, sub_tps: int, pricing: Dictionary, rate: Dictionary = {}) -> Array:
	var rows: Array = []
	if is_api:
		rows.append({"label": _t("MODEL_UNIT_PRICE"), "value": _format_per_token_price(api_price)})
		# v8 PR-I — 推理成本 + 指导价 (来自绑定 model, view 层算好传入)。
		if pricing.has(&"base_price") or pricing.has("base_price"):
			rows.append({"label": _t("MODEL_INFER_COST"), "value": _format_per_token_price(
					float(pricing.get(&"base_price", pricing.get("base_price", 0.0))))})
		if pricing.has(&"guidance_price") or pricing.has("guidance_price"):
			rows.append({"label": _t("MODEL_GUIDE_PRICE"), "value": _format_per_token_price(
					float(pricing.get(&"guidance_price", pricing.get("guidance_price", 0.0))))})
		rows.append({"label": _t("FIELD_DEMAND"), "value": _format_tps_compact(api_demand)})
		rows.append({"label": _t("PRODUCT_LAST_REV"), "value": "$%s" % _comma(last_rev)})
	else:
		rows.append({"label": _t("PRODUCT_SUB_PRICE_SHORT"), "value": "$%d" % int(p.subscription_price) + _t("SUFFIX_PER_WEEK")})
		# v8 PR-I — 参考订阅价 (ProductTypeSpec.subscription_price_guidance)。
		if pricing.has(&"sub_guidance") or pricing.has("sub_guidance"):
			var g: int = int(pricing.get(&"sub_guidance", pricing.get("sub_guidance", 0)))
			rows.append({"label": _t("PRODUCT_REF_SUB"), "value": "$%d" % g + _t("SUFFIX_PER_WEEK")})
		rows.append({"label": _t("PRODUCT_SUBS"), "value": _comma(int(p.subscribers))})
		rows.append({"label": _t("FIELD_QUALITY"), "value": "%.2f" % float(p.quality)})
		rows.append({"label": _t("PRODUCT_TS_USE"), "value": _format_tps_compact(sub_tps)})
	# v7 PR-F3: 增长率分解 (UserSystem.compute_rate_breakdown). 让玩家秒懂为啥涨/跌。
	if not rate.is_empty():
		_append_rate_rows(rows, p, is_api, rate)
	return rows

static func _append_rate_rows(rows: Array, _p, is_api: bool, rate: Dictionary) -> void:
	if bool(rate.get("is_orphan", false)):
		rows.append({"label": _t("PRODUCT_WEEKLY_RATE"), "value": _t("PRODUCT_ORPHAN") % 5})
		return
	if bool(rate.get("is_api_cliff", false)):
		rows.append({"label": _t("PRODUCT_WEEKLY_RATE"), "value": _t("PRODUCT_PRICE_CLIFF")})
		return
	var total: float = float(rate.get("total_rate", 0.0))
	rows.append({"label": _t("PRODUCT_WEEKLY_RATE"), "value": _t("SUFFIX_RATE_PER_WEEK") % _format_pct_signed(total)})
	# v10: 每项加成各占一行 (旧版挤在「分项」一行太密)。名次只与竞品 (NPC) 比 —
	# 公司自己其它模型不计入。总榜/子榜各显示名次 + 该榜单独 rate; 实际只采用
	# 较优的一项 (见「排名增长」行)。
	var total_rank: int = int(rate.get("total_rank", 0))
	rows.append({"label": _t("PRODUCT_RANK_TOTAL"), "value": "#%s (%s)" % [
		_rank_label(total_rank), _format_pct_signed(float(rate.get("total_rank_rate", 0.0)))]})
	if rate.get("sub_board", &"") != &"":
		var sub_rank: int = int(rate.get("sub_rank", 0))
		rows.append({"label": _t("PRODUCT_RANK_SUB"), "value": "#%s (%s)" % [
			_rank_label(sub_rank), _format_pct_signed(float(rate.get("sub_rank_rate", 0.0)))]})
	rows.append({"label": _t("PRODUCT_RANK_GROWTH_LABEL"), "value": _t("PRODUCT_RANK_GROWTH") % \
		_format_pct_signed(float(rate.get("rank_rate", 0.0)))})
	rows.append({"label": _t("PRODUCT_PRICE_ELASTIC"), "value": _format_pct_signed(float(rate.get("price_rate", 0.0)))})
	# 能力门槛惩罚 — 仅在非零时显示 (模型对应能力轴低于产品要求)。
	var cap_pen: float = float(rate.get("capability_penalty", 0.0))
	if cap_pen != 0.0:
		rows.append({"label": _t("PRODUCT_CAP_GATE"), "value": _t("PRODUCT_CAP_LOW") % _format_pct_signed(cap_pen)})
	# 外部绝对引流 — marketing / base 各占一行, 仅在非零时显示。
	var unit: String = _t("PRODUCT_UNIT_API") if is_api else _t("PRODUCT_UNIT_SUB")
	var mk: int = int(rate.get("marketing_attract", 0))
	if mk > 0:
		rows.append({"label": _t("PRODUCT_MARKETING_DRAW"), "value": _t("PRODUCT_INFLOW") % [_comma(mk), unit]})
	var ba: int = int(rate.get("base_attraction", 0))
	if ba > 0:
		rows.append({"label": _t("PRODUCT_BASE_DRAW"), "value": _t("PRODUCT_INFLOW") % [_comma(ba), unit]})

static func _format_pct_signed(r: float) -> String:
	# +2% / -4% / 0%; 用 %.1f 但去尾 .0 (玩家友好)。
	var pct: float = r * 100.0
	var sign_str: String = ""
	if pct > 0.0:
		sign_str = "+"
	elif pct == 0.0:
		return "0%"
	var formatted: String = "%.1f" % pct
	if formatted.ends_with(".0"):
		formatted = formatted.substr(0, formatted.length() - 2)
	return sign_str + formatted + "%"

static func _rank_label(rank: int) -> String:
	if rank <= 0:
		return "—"
	return str(rank)

static func _format_per_token_price(per_token: float) -> String:
	var per_m: float = per_token * 1_000_000.0
	if per_m < 1.0:
		return "$%.2f/M" % per_m
	return "$%.1f/M" % per_m

# 上游传 tokens/周 (1 turn = 1 week), 先转 t/s 再展示, 与产品池 / 营收 tab 同源。
const _SECONDS_PER_WEEK: int = 604_800

static func _format_tps_compact(tokens_per_week: int) -> String:
	# 走 UITheme 统一格式化, 自动升档 k → M → G (与营收 / 顶栏一致)。
	return UITheme.format_tps(float(tokens_per_week) / float(_SECONDS_PER_WEEK))

static func _comma(n: int) -> String:
	var s := str(abs(n))
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	if n < 0:
		out = "-" + out
	return out
