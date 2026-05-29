extends VBoxContainer

## MarketingView — 营销 tab 试点视图 (v7 PR-F2)。
## Per design/营销系统设计.md §7。
##
## 视图不读 GameState。调用方 (main.gd) 从 GameState.campaigns 转好 dict 后
## 调 refresh(data)。布局: + 新建活动按钮 + 进行中 campaign 卡片墙。
##
## 信号:
##   new_campaign_pressed()
##   terminate_campaign_pressed(campaign_id)

signal new_campaign_pressed
signal terminate_campaign_pressed(campaign_id: StringName)

const SectionHeaderScene := preload("res://scenes/ui/components/section_header/section_header.tscn")
const CardScene := preload("res://scenes/ui/components/card/card.tscn")

# 顶部「启动新活动」section.
var _create_section: Control
var _create_body: VBoxContainer
var _create_btn: Button
var _create_hint: Label
# 创始人出身加成提示 (网红: 用户增长 ×1.3); 仅在加成 ≠ 1 时显示。
var _founder_note: Label

# 进行中 section.
var _active_section: Control
var _active_body: HFlowContainer
var _active_empty: Label

# id → Card, 测试 introspection 用。
var _cards_by_id: Dictionary = {}

func _ready() -> void:
	add_theme_constant_override(&"separation", UITheme.S_4)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	_create_section = SectionHeaderScene.instantiate()
	add_child(_create_section)
	_create_section.set_data(tr("MARKETING_CREATE_SECTION"), -1, "", &"")

	_create_body = VBoxContainer.new()
	_create_body.add_theme_constant_override(&"separation", UITheme.S_2)
	add_child(_create_body)
	_create_btn = Button.new()
	_create_btn.text = tr("MARKETING_CREATE_BTN")
	# 收紧到内容宽并左对齐, 不占满整屏 (见 design §9)。
	_create_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	UITheme.apply_button_variant(_create_btn, &"create")
	_create_btn.pressed.connect(_on_new_pressed)
	_create_body.add_child(_create_btn)
	_create_hint = Label.new()
	_create_hint.add_theme_color_override(&"font_color", UITheme.TEXT_SECONDARY)
	_create_hint.visible = false
	_create_body.add_child(_create_hint)

	_founder_note = Label.new()
	_founder_note.add_theme_color_override(&"font_color", UITheme.ACCENT_INFO)
	_founder_note.visible = false
	_create_body.add_child(_founder_note)

	_active_section = SectionHeaderScene.instantiate()
	add_child(_active_section)
	_active_section.set_data(tr("STATUS_IN_PROGRESS"), 0, "", &"")
	# 卡片墙: HFlowContainer 横向流式排布 (与 hiring / tasks 视图一致), 否则
	# 卡片会竖成一条 (见 design/营销系统设计.md §7)。
	_active_body = HFlowContainer.new()
	_active_body.add_theme_constant_override(&"h_separation", UITheme.S_3)
	_active_body.add_theme_constant_override(&"v_separation", UITheme.S_3)
	_active_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_active_body)
	_active_empty = Label.new()
	_active_empty.text = tr("MSG_NONE")
	_active_empty.add_theme_color_override(&"font_color", UITheme.TEXT_SECONDARY)
	_active_body.add_child(_active_empty)

func refresh(data: Dictionary) -> void:
	var cap: int = int(data.get("cap", 5))
	var active_count: int = int(data.get("active_count", 0))
	var can_create: bool = bool(data.get("can_create", true))
	var reason: String = String(data.get("create_disabled_reason", ""))

	_create_section.set_data(tr("MARKETING_CREATE_SECTION_COUNT") % [active_count, cap],
			-1, "", &"")
	_create_btn.disabled = not can_create
	_create_hint.visible = not reason.is_empty()
	_create_hint.text = reason

	# 创始人加成 (网红: 新增用户 ×1.3) — 放大营销拉新与自然增长, 在此明示。
	var founder_mult: float = float(data.get("founder_mult", 1.0))
	_founder_note.visible = not is_equal_approx(founder_mult, 1.0)
	if _founder_note.visible:
		_founder_note.text = tr("MARKETING_FOUNDER_BONUS") % founder_mult

	_active_section.set_data(tr("STATUS_IN_PROGRESS"), active_count, "", &"")
	_refresh_campaigns(data.get("campaigns", []))

func _refresh_campaigns(campaigns: Array) -> void:
	# 清掉旧卡 (保留 _active_empty 占位以便没卡时显示「(无)」)。
	for child in _active_body.get_children():
		if child == _active_empty:
			continue
		_active_body.remove_child(child)
		child.queue_free()
	_cards_by_id.clear()

	_active_empty.visible = campaigns.is_empty()
	for c in campaigns:
		var card: Control = CardScene.instantiate()
		_active_body.add_child(card)
		_populate_card(card, c)
		_cards_by_id[StringName(c.get("id", &""))] = card

func _populate_card(card: Control, c: Dictionary) -> void:
	# v7 PR-F3: 单产品锁定, 渲染 target_product_label + expected_per_week。
	var cid: StringName = StringName(c.get("id", &""))
	var name: String = String(c.get("display_name", String(cid)))
	var budget: int = int(c.get("weekly_budget", 0))
	var remaining: int = int(c.get("remaining_weeks", 0))
	var total: int = int(c.get("total_weeks", 0))
	var target_label: String = String(c.get("target_product_label", tr("MARKETING_UNKNOWN_PRODUCT")))
	var is_api: bool = bool(c.get("target_is_api", false))
	var lead_label: String = String(c.get("lead_label", tr("MSG_NONE")))
	var lead_mult: float = float(c.get("lead_mult", 1.0))
	var per_week: int = int(c.get("expected_per_week", 0))

	var fields: Array = []
	var done_weeks: int = clamp(total - remaining, 0, max(total, 0))
	fields.append({"label": tr("FIELD_WEEKLY_BUDGET"), "value": tr("MARKETING_BUDGET_VALUE") % _money(budget)})
	fields.append({"label": tr("FIELD_PROGRESS"),
		"value": tr("MARKETING_PROGRESS_VALUE") % [_progress_percent(remaining, total), done_weeks, total]})
	fields.append({"label": tr("FIELD_TARGET"), "value": target_label})
	var lead_value: String = lead_label
	if lead_mult > 1.0:
		lead_value += "  (×%.2f)" % lead_mult
	fields.append({"label": "Lead", "value": lead_value})
	if is_api:
		var tokens: int = per_week * UserSystem.API_TOKENS_PER_SUB_PER_WEEK
		fields.append({"label": tr("FIELD_WEEKLY_API_DEMAND"),
			"value": tr("MARKETING_API_DEMAND_VALUE") % _format_tokens(tokens)})
	else:
		fields.append({"label": tr("FIELD_WEEKLY_NEW_USERS"), "value": tr("MARKETING_NEW_USERS_VALUE") % _money(per_week)})

	card.set_data({
		"title": name,
		"subtitle": tr("MARKETING_SUBTITLE") % [_money(budget), total],
		"avatar": {
			"texture": IconRegistry.marketing_icon(&"campaign"),
			"fallback_text": name,
			"seed_id": cid,
			"kind": &"campaign",
		},
		"status": {"label": tr("STATUS_IN_PROGRESS"), "kind": &"published"},
		"fields": fields,
		"actions": [{"id": &"terminate", "label": tr("MARKETING_TERMINATE")}],
	})
	card.action_pressed.connect(_on_card_action.bind(cid))

func _on_new_pressed() -> void:
	new_campaign_pressed.emit()

func _on_card_action(action_id: StringName, campaign_id: StringName) -> void:
	if action_id == &"terminate":
		terminate_campaign_pressed.emit(campaign_id)

# ─── format helpers ────────────────────────────────────────────────

func _progress_percent(remaining: int, total: int) -> int:
	if total > 0:
		var done: int = clamp(total - remaining, 0, total)
		return clampi(int(round(float(done) / float(total) * 100.0)), 0, 100)
	return 0

func _money(n: int) -> String:
	var v: int = abs(n)
	var s: String = str(v)
	var out: String = ""
	var i: int = s.length()
	while i > 3:
		out = "," + s.substr(i - 3, 3) + out
		i -= 3
	out = s.substr(0, i) + out
	return ("-" + out) if n < 0 else out

func _format_tokens(n: int) -> String:
	var v: int = abs(n)
	if v >= 1_000_000_000_000:
		return "%.2fT" % (float(n) / 1_000_000_000_000.0)
	if v >= 1_000_000_000:
		return "%.2fB" % (float(n) / 1_000_000_000.0)
	if v >= 1_000_000:
		return "%.2fM" % (float(n) / 1_000_000.0)
	if v >= 1_000:
		return "%.1fK" % (float(n) / 1_000.0)
	return str(n)

# ─── 测试 introspection ──────────────────────────────────────

func get_card_count_for_test() -> int:
	return _cards_by_id.size()

func is_card_avatar_texture_visible_for_test(campaign_id: StringName) -> bool:
	var c: Control = _cards_by_id.get(campaign_id, null)
	return c != null and c.has_method(&"is_avatar_texture_visible_for_test") \
		and c.is_avatar_texture_visible_for_test()

func click_terminate_for_test(campaign_id: StringName) -> void:
	var c: Control = _cards_by_id.get(campaign_id, null)
	if c != null and c.has_method(&"click_action_for_test"):
		c.click_action_for_test(&"terminate")

func click_new_for_test() -> void:
	_create_btn.pressed.emit()

func all_button_texts_for_test() -> PackedStringArray:
	var out := PackedStringArray()
	_collect_text(self, true, out)
	return out

func all_label_texts_for_test() -> PackedStringArray:
	var out := PackedStringArray()
	_collect_text(self, false, out)
	return out

func _collect_text(node: Node, want_button: bool, out: PackedStringArray) -> void:
	for child in node.get_children():
		if want_button and child is Button:
			out.append((child as Button).text)
		elif (not want_button) and child is Label:
			out.append((child as Label).text)
		_collect_text(child, want_button, out)
