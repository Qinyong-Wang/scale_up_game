extends Object

## ModelCard helper — 把 Model resource 翻译成 Card.set_data 字典。
##
## 用法:
##   var card: Control = CardScene.instantiate()
##   container.add_child(card)
##   ModelCard.populate(card, model)
##
## 这是纯静态函数集合, 不持有状态 / 不订阅事件。

# 值为 i18n key (const 不能调 tr); 取用处 _t()。
const _STATUS_LABELS: Dictionary = {
	&"pretrained":  "MODEL_STATUS_PRETRAINED",
	&"posttrained": "MODEL_STATUS_POSTTRAINED",
	&"evaluated":   "MODEL_FILTER_EVALUATED",
	&"published":   "MODEL_FILTER_PUBLISHED",
}

# static 上下文没有 self, 不能调 tr(); 走 TranslationServer (同样含 fallback)。
static func _t(key: String) -> String:
	return TranslationServer.translate(key)

## v8 PR-I: pricing context is optional but recommended — pass keys
##   {base_price, guidance_open, guidance_closed, ratio_to_guidance, weekly_growth}
## to surface 推理成本 / 指导价 / 定价比 / 周需求增长 in the card. View layer
## computes via ResearchSystem before calling populate, keeping this translator
## stateless. See design/研究系统设计.md §4.8.
static func populate(card: Control, m, pricing: Dictionary = {}) -> void:
	card.set_data(_build_data(m, pricing))

static func _build_data(m, pricing: Dictionary) -> Dictionary:
	var status: StringName = StringName(m.status)
	var data: Dictionary = {
		"title": String(m.display_name),
		"subtitle": _subtitle(m),
		"avatar": {
			"texture": IconRegistry.model_icon(StringName(m.arch)),   # 按架构族取图
			"fallback_text": String(m.display_name),
			"seed_id": StringName(m.id),
			"kind": &"model",
		},
		"status": {
			"label": _t(_STATUS_LABELS.get(status, String(status))),
			"kind": status,
		},
		"fields": _fields(m, pricing),
		"actions": _actions(m, status),
	}
	return data

static func _subtitle(m) -> String:
	# 例: "ant_v2 · 7B"
	return "%s · %s" % [String(m.arch), _format_param_count(float(m.size_params))]

static func _fields(m, pricing: Dictionary) -> Array:
	var rows: Array = []
	rows.append({"label": _t("MODEL_CAPABILITY"), "value": _capability_text(m)})
	# v7 PR-G: 显示 D 轴 (context_length_tokens) + E 轴 (multimodal_method) — 训练完
	# 冻结的属性, 玩家想知道这个模型当时选了什么.
	rows.append({"label": _t("MODEL_CONTEXT"), "value": _format_context_tokens(
			int(m.context_length_tokens) if "context_length_tokens" in m else 4096)})
	var mm: StringName = StringName(m.multimodal_method) if "multimodal_method" in m else &"none"
	if mm != &"" and mm != &"none":
		rows.append({"label": _t("MODEL_MM_METHOD"), "value": String(mm)})
	# v8 PR-I — 推理成本 / 指导价常显; published 加 定价比 + 周需求增长。
	var status: StringName = StringName(m.status)
	if pricing.has(&"base_price") or pricing.has("base_price"):
		var base: float = float(pricing.get(&"base_price", pricing.get("base_price", 0.0)))
		rows.append({"label": _t("MODEL_INFER_COST"), "value": _format_price(base)})
		rows.append({"label": _t("MODEL_GUIDE_PRICE"), "value": _format_guidance_text(m, pricing, status)})
	if status == &"published":
		rows.append({"label": _t("MODEL_UNIT_PRICE"), "value": _format_price(float(m.per_token_price))})
		if pricing.has(&"ratio_to_guidance") or pricing.has("ratio_to_guidance"):
			var ratio: float = float(pricing.get(&"ratio_to_guidance",
					pricing.get("ratio_to_guidance", 0.0)))
			rows.append({"label": _t("MODEL_PRICE_RATIO"), "value": "%d%%" % int(round(ratio * 100.0))})
		if pricing.has(&"weekly_growth") or pricing.has("weekly_growth"):
			var growth: float = float(pricing.get(&"weekly_growth",
					pricing.get("weekly_growth", 0.0)))
			rows.append({"label": _t("MODEL_DEMAND_GROWTH"), "value": _format_growth_rate(growth)})
	rows.append({"label": _t("FIELD_TURN"), "value": _t("WEEK_N") % int(m.trained_at_turn)})
	return rows

static func _format_guidance_text(m, pricing: Dictionary, status: StringName) -> String:
	var go: float = float(pricing.get(&"guidance_open", pricing.get("guidance_open", 0.0)))
	var gc: float = float(pricing.get(&"guidance_closed", pricing.get("guidance_closed", 0.0)))
	# Published: open/closed already decided — show just the relevant one.
	if status == &"published":
		if bool(m.is_open_source) or StringName(m.provenance) == &"downloaded_os":
			return _format_price(go)
		return _format_price(gc)
	# Pre-publish: show both so player sees the post-publish pricing space.
	return _t("MODEL_GUIDE_OC") % [_format_price(go), _format_price(gc)]

static func _format_growth_rate(rate: float) -> String:
	# -1.0 sentinel from ResearchSystem.weekly_growth_rate — 价格 ≥ 2.5× 指导价
	# 时当周需求归零。玩家友好的文案, 不再泄露 "cliff" 内部术语。
	if rate <= -0.999:
		return _t("MODEL_DEMAND_ZERO")
	var pct: float = rate * 100.0
	if pct >= 0.0:
		return _t("PRICE_GROWTH_POS") % pct
	return _t("PRICE_GROWTH") % pct

static func _format_context_tokens(tokens: int) -> String:
	if tokens >= 1000000:
		return "%dM" % floori(float(tokens) / 1000000.0)
	if tokens >= 1000:
		return "%dk" % floori(float(tokens) / 1000.0)
	return str(tokens)

static func _capability_text(m) -> String:
	# 评估前用 ?? ; 评估后显示总分 + 五轴细分 (通/码/推/多/Agent)。
	if not bool(m.capability_revealed):
		return _t("MODEL_CAP_UNKNOWN")
	var cap: Dictionary = m.capability
	var gen: float = float(cap.get(&"general", 0.0))
	var code: float = float(cap.get(&"code", 0.0))
	var reason: float = float(cap.get(&"reasoning", 0.0))
	var multi: float = float(cap.get(&"multimodal", 0.0))
	var agent: float = float(cap.get(&"agent", 0.0))
	var total: float = gen + code + reason + multi + agent
	var stale := _t("MODEL_STALE") if bool(m.capability_stale) else ""
	return _t("MODEL_CAP_LINE") % [
		int(total), int(gen), int(code), int(reason), int(multi), int(agent), stale]

static func _actions(_m, status: StringName) -> Array:
	var out: Array = []
	match status:
		&"pretrained", &"posttrained":
			out.append({"id": &"evaluate", "label": _t("MODEL_EVALUATE")})
			out.append({"id": &"posttrain", "label": _t("TASK_SUBTYPE_POSTTRAIN")})
		&"evaluated":
			out.append({"id": &"publish_closed", "label": _t("MODEL_PUBLISH_CLOSED")})
			out.append({"id": &"publish_open",   "label": _t("MODEL_PUBLISH_OPEN")})
			out.append({"id": &"posttrain",      "label": _t("TASK_SUBTYPE_POSTTRAIN")})
		&"published":
			out.append({"id": &"price_edit", "label": _t("MODEL_PRICE_EDIT")})
			out.append({"id": &"unpublish",  "label": _t("MODEL_UNPUBLISH")})
	out.append({"id": &"delete", "label": _t("ACTION_DELETE")})
	return out

static func _format_param_count(size_params_m: float) -> String:
	# size_params 单位是 M (百万参数); 取整到 1B / 10B 显示。
	if size_params_m >= 1000.0:
		return "%.0fB" % (size_params_m / 1000.0)
	return "%.0fM" % size_params_m

static func _format_price(per_token: float) -> String:
	# per_token 是单 token 价格 (美元); 转 $/M tok 显示。base_price 可能小到
	# 1e-9 $/tok (= $0.001/M), 所以低端用更高精度避免显示成 "$0.00/M"。
	var per_m: float = per_token * 1_000_000.0
	if per_m < 0.01:
		return "$%.4f/M" % per_m
	if per_m < 1.0:
		return "$%.2f/M" % per_m
	return "$%.1f/M" % per_m
