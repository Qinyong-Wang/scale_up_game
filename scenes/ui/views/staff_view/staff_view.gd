extends VBoxContainer

## StaffView — 员工 tab 视图 (招聘界面拆分后的「在册」一半)。
##
## 布局:
##   [Section "创始人 (你自己)"]
##     ↳ Founder Card + note OR Label "(尚未下场, 去招聘 tab)"
##   [Section "员工 (按职能)"]
##     ↳ 每个 role 一行 (总数 / 忙碌 / 空闲 / 周薪 + +1/-1 buttons)
##   [Label "本周总工资: $X (lead $Y + staff $Z)"]
##   [Section "已签约 Lead"]
##     ↳ 按 specialty 分组的 subsection 标签 + HFlow of hired cards
##
## 信号:
##   lead_action(lead_id: StringName, action_id: StringName)   # fire
##   staff_adjust(role: StringName, delta: int)
##
## refresh(data: Dictionary) 接 main.gd 组装好的完整 data dict (与 HiringView 同一份),
## view 内部不访问 GameState。「招新」一半 (候选池) 在 HiringView。

signal lead_action(lead_id: StringName, action_id: StringName)
signal staff_adjust(role: StringName, delta: int)

const SectionHeaderScene := preload("res://scenes/ui/components/section_header/section_header.tscn")
const CardScene := preload("res://scenes/ui/components/card/card.tscn")
const LeadCard := preload("res://scenes/ui/views/hiring_view/lead_card.gd")

## 员工行信息列固定宽 — 各 role 行的 +1/-1 按钮据此对齐成一列, 不撑满整屏。
const STAFF_INFO_W := 300

var _founder_section: Control
var _founder_body: VBoxContainer
var _founder_card: Control

var _hired_section: Control
var _hired_grid_root: VBoxContainer

var _staff_section: Control
var _staff_rows_root: VBoxContainer

var _total_label: Label

# role -> {plus_btn, minus_btn}, 测试 introspection 用。
var _staff_buttons: Dictionary = {}
# lead_id -> Card 实例, 测试 introspection 用。
var _cards_by_id: Dictionary = {}

func _ready() -> void:
	add_theme_constant_override(&"separation", UITheme.S_4)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	# 创始人区。
	_founder_section = SectionHeaderScene.instantiate()
	add_child(_founder_section)
	_founder_section.set_data(tr("HIRING_FOUNDER"), -1, "", &"")
	_founder_section.set_meta(&"section_key", "HIRING_FOUNDER")

	_founder_body = VBoxContainer.new()
	_founder_body.add_theme_constant_override(&"separation", UITheme.S_2)
	add_child(_founder_body)

	# 员工区。
	_staff_section = SectionHeaderScene.instantiate()
	add_child(_staff_section)
	_staff_section.set_data(tr("STAFF_BY_ROLE"), -1, "", &"")
	_staff_section.set_meta(&"section_key", "STAFF_BY_ROLE")

	_staff_rows_root = VBoxContainer.new()
	_staff_rows_root.add_theme_constant_override(&"separation", UITheme.S_2)
	add_child(_staff_rows_root)

	# 周工资合计。
	_total_label = Label.new()
	_total_label.add_theme_color_override(&"font_color", UITheme.TEXT_PRIMARY)
	add_child(_total_label)

	# 已签约区。
	_hired_section = SectionHeaderScene.instantiate()
	add_child(_hired_section)
	_hired_section.set_data(tr("STAFF_HIRED_LEADS"), -1, "", &"")
	_hired_section.set_meta(&"section_key", "STAFF_HIRED_LEADS")

	_hired_grid_root = VBoxContainer.new()
	_hired_grid_root.add_theme_constant_override(&"separation", UITheme.S_3)
	add_child(_hired_grid_root)

func refresh(data: Dictionary) -> void:
	_cards_by_id.clear()
	_founder_card = null
	_refresh_founder(data)
	_refresh_staff(data.get("staff_rows", []))
	_refresh_totals(data.get("weekly_totals", {"lead": 0, "staff": 0, "total": 0}))
	_refresh_hired(data)

func _refresh_founder(data: Dictionary) -> void:
	_clear_children(_founder_body)
	var has_founder: bool = bool(data.get("has_founder", false))
	if has_founder:
		var founder = _find_founder(data.get("hired", []))
		if founder != null:
			var grid := HFlowContainer.new()
			grid.add_theme_constant_override(&"h_separation", UITheme.S_3)
			grid.add_theme_constant_override(&"v_separation", UITheme.S_3)
			_founder_body.add_child(grid)
			var card: Control = CardScene.instantiate()
			grid.add_child(card)
			var bonus_text: Dictionary = data.get("bonus_text", {})
			var status_text: Dictionary = data.get("status_text", {})
			LeadCard.populate_hired(card, founder,
				String(bonus_text.get(founder.id, tr("LEAD_NO_BONUS"))),
				tr("LEAD_FOUNDER_FULL"),
				String(status_text.get(founder.id, tr("LEAD_FOUNDER_FULL"))))
			card.action_pressed.connect(_on_card_action.bind(StringName(founder.id)))
			_founder_card = card
			_cards_by_id[StringName(founder.id)] = card
		var note := _make_dim_label(tr("STAFF_FOUNDER_NOTE"))
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.custom_minimum_size = Vector2(UITheme.LIST_MAX_W, 0)
		_founder_body.add_child(note)
	else:
		_founder_body.add_child(_make_dim_label(tr("STAFF_NOT_FOUNDER")))

func _refresh_hired(data: Dictionary) -> void:
	_clear_children(_hired_grid_root)
	var hired: Array = data.get("hired", [])
	var order: Array = data.get("specialty_order", [])
	var labels: Dictionary = data.get("specialty_labels", {})
	var bonus_text: Dictionary = data.get("bonus_text", {})
	var status_text: Dictionary = data.get("status_text", {})
	var grouped := _group_by_specialty(hired)
	var any := false
	for spec in order:
		var leads: Array = grouped.get(spec, [])
		if leads.is_empty():
			continue
		any = true
		var subhead := _make_subsection_label("── %s ──" % String(labels.get(spec, String(spec))))
		_hired_grid_root.add_child(subhead)
		var grid := HFlowContainer.new()
		grid.add_theme_constant_override(&"h_separation", UITheme.S_3)
		grid.add_theme_constant_override(&"v_separation", UITheme.S_3)
		_hired_grid_root.add_child(grid)
		for l in leads:
			var card: Control = CardScene.instantiate()
			grid.add_child(card)
			LeadCard.populate_hired(card, l, String(bonus_text.get(l.id, "")),
				String(labels.get(l.specialty, String(l.specialty))),
				String(status_text.get(l.id, "")))
			card.action_pressed.connect(_on_card_action.bind(StringName(l.id)))
			_cards_by_id[StringName(l.id)] = card
	if not any:
		_hired_grid_root.add_child(_make_dim_label(tr("STAFF_NO_LEADS")))

func _refresh_staff(staff_rows: Array) -> void:
	_clear_children(_staff_rows_root)
	_staff_buttons.clear()
	for row_data in staff_rows:
		var role: StringName = StringName(row_data.get("role", &""))
		var label: String = String(row_data.get("label", String(role)))
		var pool: int = int(row_data.get("pool", 0))
		var busy: int = int(row_data.get("busy", 0))
		var idle: int = max(0, pool - busy)
		var per_week: int = int(row_data.get("per_week", 0))

		var panel := PanelContainer.new()
		panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		panel.add_theme_stylebox_override(&"panel", _make_staff_row_style())
		_staff_rows_root.add_child(panel)

		# 行收紧到内容宽并左对齐: 信息列不 EXPAND_FILL, +1/-1 紧跟其后 (见 design §9)。
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", UITheme.S_3)
		row.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		panel.add_child(row)
		var info := Label.new()
		var row_text := tr("STAFF_ROLE_ROW") % [
			label, pool, busy, LeadCard._money(per_week).trim_prefix("$")]
		info.text = "%s / %s %d" % [row_text, tr("INFRA_STATUS_IDLE"), idle]
		info.add_theme_color_override(&"font_color", UITheme.TEXT_PRIMARY)
		info.add_theme_font_override(&"font", UITheme.get_ui_font_bold())
		# 固定信息列宽 → 各 role 行的按钮对齐成一列; 不撑满整屏。
		info.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		info.custom_minimum_size = Vector2(STAFF_INFO_W, 0)
		row.add_child(info)
		var plus_btn := Button.new()
		plus_btn.text = tr("STAFF_PLUS_ONE") % LeadCard._money(per_week)
		UITheme.apply_button_variant(plus_btn, &"primary")
		plus_btn.pressed.connect(_on_staff_plus.bind(role))
		row.add_child(plus_btn)
		var minus_btn := Button.new()
		minus_btn.text = "-1"
		UITheme.apply_button_variant(minus_btn, &"secondary")
		if pool <= busy:
			minus_btn.disabled = true
			minus_btn.tooltip_text = tr("STAFF_CANT_FIRE_BUSY")
		minus_btn.pressed.connect(_on_staff_minus.bind(role))
		row.add_child(minus_btn)
		_staff_buttons[role] = {"plus": plus_btn, "minus": minus_btn, "row": row, "info": info}

func _refresh_totals(totals: Dictionary) -> void:
	var lead_n: int = int(totals.get("lead", 0))
	var staff_n: int = int(totals.get("staff", 0))
	var total_n: int = int(totals.get("total", lead_n + staff_n))
	_total_label.text = tr("STAFF_TOTAL_SALARY") % [
		LeadCard._money(total_n), LeadCard._money(lead_n), LeadCard._money(staff_n)]

# ─── helper ────────────────────────────────────────────────

func _group_by_specialty(leads: Array) -> Dictionary:
	var out: Dictionary = {}
	for l in leads:
		var k: StringName = StringName(l.specialty)
		out[k] = out.get(k, [])
		out[k].append(l)
	return out

func _clear_children(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()

func _find_founder(leads: Array):
	for l in leads:
		if bool(l.is_player_scientist):
			return l
	return null

func _make_staff_row_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = UITheme.BG_SURFACE
	sb.border_color = UITheme.BORDER_SUBTLE
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(UITheme.R_MD)
	sb.content_margin_left = UITheme.S_3
	sb.content_margin_right = UITheme.S_3
	sb.content_margin_top = UITheme.S_2
	sb.content_margin_bottom = UITheme.S_2
	return sb

func _make_subsection_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override(&"font_color", UITheme.TEXT_SECONDARY)
	l.add_theme_font_size_override(&"font_size", UITheme.FS_SM)
	return l

func _make_dim_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override(&"font_color", UITheme.TEXT_SECONDARY)
	return l

# ─── 信号 ──────────────────────────────────────────────────

func _on_card_action(action_id: StringName, lead_id: StringName) -> void:
	lead_action.emit(lead_id, action_id)

func _on_staff_plus(role: StringName) -> void:
	staff_adjust.emit(role, 1)

func _on_staff_minus(role: StringName) -> void:
	staff_adjust.emit(role, -1)

# ─── 测试 introspection ──────────────────────────────────────

func get_hired_card_count() -> int:
	var n := 0
	for child in _hired_grid_root.get_children():
		if child is HFlowContainer:
			n += child.get_child_count()
	return n

func get_founder_card_count_for_test() -> int:
	return 1 if _founder_card != null else 0

func get_card_actions_for_test(lead_id: StringName) -> Array:
	var c: Control = _cards_by_id.get(lead_id, null)
	if c == null:
		return []
	var btns: Dictionary = c.get(&"_action_buttons")
	if btns == null:
		return []
	return btns.keys()

func click_card_action_for_test(lead_id: StringName, action_id: StringName) -> void:
	var c: Control = _cards_by_id.get(lead_id, null)
	if c != null and c.has_method(&"click_action_for_test"):
		c.click_action_for_test(action_id)

func click_staff_plus_for_test(role: StringName) -> void:
	var pair: Dictionary = _staff_buttons.get(role, {})
	var btn: Button = pair.get("plus", null)
	if btn != null:
		btn.pressed.emit()

func is_staff_minus_disabled_for_test(role: StringName) -> bool:
	var pair: Dictionary = _staff_buttons.get(role, {})
	var btn: Button = pair.get("minus", null)
	return btn != null and btn.disabled

func get_staff_row_for_test(role: StringName) -> HBoxContainer:
	var pair: Dictionary = _staff_buttons.get(role, {})
	return pair.get("row", null)

func get_staff_info_for_test(role: StringName) -> Label:
	var pair: Dictionary = _staff_buttons.get(role, {})
	return pair.get("info", null)

func section_order_for_test() -> PackedStringArray:
	var out := PackedStringArray()
	for child in get_children():
		if child.has_meta(&"section_key"):
			out.append(String(child.get_meta(&"section_key")))
	return out

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
