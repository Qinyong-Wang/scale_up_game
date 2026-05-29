extends Object

## LeadCard helper — 把 Lead resource 翻译成 Card.set_data 字典。
##
## 用法:
##   var card := CardScene.instantiate()
##   container.add_child(card)
##   LeadCard.populate_pool(card, lead, bonus_text)        # 候选池, hire action
##   LeadCard.populate_hired(card, lead, bonus_text, status_text)  # 已签约, fire action (除非 founder/locked)

static func populate_pool(card: Control, lead, bonus_text: String, specialty_label: String) -> void:
	var data := _common_data(lead, bonus_text, specialty_label)
	data["fields"].append({"label": _t("LEAD_SIGNING_FEE"), "value": _money(int(lead.signing_fee))})
	data["fields"].append({"label": _t("LEAD_WEEKLY_SALARY"), "value": _money(int(lead.weekly_salary)) + _t("SUFFIX_PER_WEEK")})
	data["actions"] = [{"id": &"hire", "label": _t("LEAD_SIGN")}]
	card.set_data(data)

static func populate_hired(card: Control, lead, bonus_text: String, specialty_label: String, status_text: String) -> void:
	var data := _common_data(lead, bonus_text, specialty_label)
	data["fields"].append({"label": _t("LEAD_WEEKLY_SALARY"), "value": _money(int(lead.weekly_salary)) + _t("SUFFIX_PER_WEEK")})
	data["fields"].append({"label": _t("FIELD_STATUS"), "value": status_text})
	data["status"] = _hired_status_badge(lead)
	# Founder / 锁定 / 运营中 不能解雇 — 不放 fire action。
	var can_fire: bool = not bool(lead.is_player_scientist) \
			and StringName(lead.locked_by_task_id) == &"" \
			and StringName(lead.assigned_to_product_id) == &""
	if can_fire:
		data["actions"] = [{"id": &"fire", "label": _t("LEAD_FIRE")}]
	else:
		data["actions"] = []
	card.set_data(data)

# ─── 共用 ────────────────────────────────────────────────────

static func _common_data(lead, bonus_text: String, specialty_label: String) -> Dictionary:
	# 中文真名在非 zh locale 下转拼音 (见 design/国际化设计.md §12)。
	var shown_name: String = NameRomanizer.localized(String(lead.display_name))
	return {
		"title": shown_name,
		# 不再露出 raw `lead.specialty` 枚举 (chief_scientist ...) — specialty_label
		# 已是中文; level "S/A/B/C" 加 "级" 后缀, 不再像内部 id。
		"subtitle": _t("LEAD_SUBTITLE") % [
			specialty_label, String(lead.level), float(lead.ability)],
		"avatar": {
			# 玩家创始人带 avatar_id → 创始人专属头像; 其余 lead 走按 id 哈希的多元肖像池
			# (同公司里人人不同, 性别/族裔多样)。
			"texture": IconRegistry.lead_texture(StringName(lead.id), StringName(lead.avatar_id)),
			"fallback_text": shown_name,
			"seed_id": StringName(lead.id),
			"kind": &"lead",
		},
		# 关键: "加成:" 前缀必须存在 (老集成测试断这点)。
		"fields": [
			{"label": _t("LEAD_BONUS_LABEL"), "value": bonus_text if not bonus_text.is_empty() else _t("LEAD_NO_BONUS")},
		],
		"actions": [],
	}

static func _hired_status_badge(lead) -> Dictionary:
	# 状态徽章按状态着色。
	if bool(lead.is_player_scientist):
		return {"label": _t("LEAD_FOUNDER"), "kind": &"info"}
	if StringName(lead.locked_by_task_id) != &"":
		return {"label": _t("DATASET_STATUS_LOCKED"), "kind": &"warning"}
	if StringName(lead.assigned_to_product_id) != &"":
		return {"label": _t("LEAD_STATUS_BUSY"), "kind": &"info"}
	return {"label": _t("INFRA_STATUS_IDLE"), "kind": &"neutral"}

# static 上下文没有 self, 不能调 tr(); 走 TranslationServer (同样含 fallback)。
static func _t(key: String) -> String:
	return TranslationServer.translate(key)

static func _money(n: int) -> String:
	# 简单千分位; 与 main.gd _format_money 一致行为不必完全相同, 视图只显示。
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
	return "$" + out
