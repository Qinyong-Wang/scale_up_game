extends PanelContainer

## Card — 通用卡片骨架。
##
## 布局:
##   ┌─ PanelContainer (CARD_MIN_W × CARD_MIN_H, BG_SURFACE, R_MD) ─┐
##   │ Header  [avatar][title / subtitle]          [status badge]   │
##   │ ──────────────────────────────────────────────────────────── │
##   │ Body    label : value                                        │
##   │         label : value                                        │
##   │ ──────────────────────────────────────────────────────────── │
##   │ Footer  [action1] [action2] [action3] [⋯]                    │
##   └──────────────────────────────────────────────────────────────┘
##
## set_data() 接 dict, 各部分按 key 存在 / 内容判断是否显示。
## 调用方传已翻译字符串 (i18n), 组件本身不调 tr()。

const AvatarScene := preload("res://scenes/ui/components/avatar/avatar.tscn")
const BadgeScene  := preload("res://scenes/ui/components/badge/badge.tscn")

signal action_pressed(action_id: StringName)
signal card_clicked

const _ACCENT_H := 4
const _CAUTION_ACTIONS := {
	&"delete": true,
	&"fire": true,
	&"terminate": true,
	&"cancel": true,
	&"unpublish": true,
	&"undeploy": true,
	&"stop_rent_out": true,
}

var _accent_bar: ColorRect
var _avatar: Control                # Avatar 实例 (隐藏即不显示)
var _title_label: Label
var _subtitle_label: Label
var _status_badge: Control          # Badge 实例
var _fields_panel: PanelContainer
var _fields_container: VBoxContainer
var _footer: HBoxContainer
var _separator_body: HSeparator
var _separator_footer: HSeparator

var _normal_sb: StyleBoxFlat
var _hover_sb: StyleBoxFlat
var _fields_sb: StyleBoxFlat
var _hovered: bool = false

# 当前注册的 action id → 按钮; 重置时清空, 避免点旧 id 触发。
var _action_buttons: Dictionary = {}

func _ready() -> void:
	custom_minimum_size = Vector2(UITheme.CARD_MIN_W, UITheme.CARD_MIN_H)
	# Card 在父 HFlow 里应当紧凑到 min_size, 别拉伸成宽条。
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(func():
		_hovered = true
		_apply_panel_style())
	mouse_exited.connect(func():
		_hovered = false
		_apply_panel_style())
	_normal_sb = _make_card_style(UITheme.BORDER_SUBTLE)
	_hover_sb = _make_card_style(UITheme.BORDER_STRONG)
	_apply_panel_style()

	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", UITheme.S_2)
	add_child(v)

	_accent_bar = ColorRect.new()
	_accent_bar.custom_minimum_size = Vector2(0, _ACCENT_H)
	_accent_bar.color = UITheme.ACCENT_INFO
	_accent_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_accent_bar)

	# ─── Header: avatar + (title+subtitle) + status ────────
	var header := HBoxContainer.new()
	header.add_theme_constant_override(&"separation", UITheme.S_2)
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(header)

	_avatar = AvatarScene.instantiate()
	# 紧凑缩略图: 保留视觉锚点, 把空间还给标题 / 副标题 / 状态信息。
	_avatar.custom_minimum_size = Vector2(UITheme.CARD_AVATAR_SIZE, UITheme.CARD_AVATAR_SIZE)
	# 头像高, 标题列顶对齐贴在图片右侧 (而非垂直居中拉空)。
	_avatar.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_avatar.visible = false
	header.add_child(_avatar)

	var title_col := VBoxContainer.new()
	title_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_col.size_flags_vertical = Control.SIZE_SHRINK_BEGIN   # 标题贴大图顶部
	title_col.custom_minimum_size = Vector2(120, 0)
	title_col.add_theme_constant_override(&"separation", 0)
	header.add_child(title_col)

	_title_label = Label.new()
	# 标题用 bold 字重强调 (主次层级靠字重 + 灰度, 见 design §8.3)。
	_title_label.add_theme_font_override(&"font", UITheme.get_ui_font_bold())
	_title_label.add_theme_font_size_override(&"font_size", UITheme.FS_MD)
	_title_label.add_theme_color_override(&"font_color", UITheme.TEXT_PRIMARY)
	_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title_label.max_lines_visible = 3
	_title_label.custom_minimum_size = Vector2(120, 0)
	title_col.add_child(_title_label)

	_subtitle_label = Label.new()
	_subtitle_label.add_theme_font_size_override(&"font_size", UITheme.FS_SM)
	_subtitle_label.add_theme_color_override(&"font_color", UITheme.TEXT_SECONDARY)
	_subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle_label.max_lines_visible = 3
	_subtitle_label.custom_minimum_size = Vector2(120, 0)
	_subtitle_label.visible = false
	title_col.add_child(_subtitle_label)

	_status_badge = BadgeScene.instantiate()
	_status_badge.size_flags_vertical = Control.SIZE_SHRINK_BEGIN   # 徽章贴顶, 不随大图拉伸
	_status_badge.visible = false
	header.add_child(_status_badge)

	# ─── Body separator + field list ────────────────────────
	_separator_body = HSeparator.new()
	_separator_body.visible = false
	v.add_child(_separator_body)

	_fields_panel = PanelContainer.new()
	_fields_panel.visible = false
	_fields_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fields_sb = _make_fields_style()
	_fields_panel.add_theme_stylebox_override(&"panel", _fields_sb)
	v.add_child(_fields_panel)

	_fields_container = VBoxContainer.new()
	_fields_container.add_theme_constant_override(&"separation", UITheme.S_1)
	_fields_panel.add_child(_fields_container)

	# ─── Footer separator + action row ──────────────────────
	_separator_footer = HSeparator.new()
	_separator_footer.visible = false
	v.add_child(_separator_footer)

	_footer = HBoxContainer.new()
	_footer.add_theme_constant_override(&"separation", UITheme.S_2)
	_footer.visible = false
	v.add_child(_footer)

	# 整卡可点 (除按钮外的区域走 card_clicked)。
	gui_input.connect(_on_card_gui_input)

func set_data(data: Dictionary) -> void:
	_title_label.text = String(data.get("title", ""))
	var accent_kind: StringName = &""

	# subtitle
	var subtitle: String = String(data.get("subtitle", ""))
	_subtitle_label.text = subtitle
	_subtitle_label.max_lines_visible = int(data.get("subtitle_max_lines", 3))
	_subtitle_label.visible = not subtitle.is_empty()

	# avatar
	if data.has("avatar"):
		var av: Dictionary = data["avatar"]
		_avatar.set_data(
			av.get("texture", null),
			String(av.get("fallback_text", "")),
			StringName(av.get("seed_id", &"")),
			StringName(av.get("kind", &"")),
		)
		_avatar.visible = true
	else:
		_avatar.visible = false

	# status badge
	if data.has("status"):
		var st: Dictionary = data["status"]
		accent_kind = StringName(st.get("kind", &""))
		_status_badge.set_data(
			String(st.get("label", "")),
			_card_badge_kind(accent_kind),
		)
		_status_badge.visible = true
	else:
		_status_badge.visible = false
	_accent_bar.color = _accent_color(accent_kind)

	# fields
	for child in _fields_container.get_children():
		child.queue_free()
	var fields: Array = data.get("fields", [])
	for spec in fields:
		var row := _make_field_row(
				String(spec["label"]),
				String(spec["value"]),
				int(spec.get("max_lines", 3)))
		_fields_container.add_child(row)
	_fields_panel.visible = not fields.is_empty()
	_separator_body.visible = false

	# actions
	for child in _footer.get_children():
		child.queue_free()
	_action_buttons.clear()
	var actions: Array = data.get("actions", [])
	var promoted_primary := false
	for spec in actions:
		var id: StringName = StringName(spec["id"])
		var label: String = String(spec["label"])
		var btn := Button.new()
		btn.text = label
		var kind := _action_kind(spec, id, promoted_primary)
		if kind == &"primary":
			promoted_primary = true
		UITheme.apply_button_variant(btn, kind)
		# Optional per-action disabled flag (default false → unchanged for callers
		# that don't set it). Used e.g. by the charity view to grey out tiers the
		# player can't afford.
		btn.disabled = bool(spec.get("disabled", false))
		btn.pressed.connect(_on_action_pressed.bind(id))
		_footer.add_child(btn)
		_action_buttons[id] = btn
	_footer.visible = not actions.is_empty()
	_separator_footer.visible = not actions.is_empty()

func _make_field_row(label_text: String, value_text: String, max_lines: int = 3) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", UITheme.S_2)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lab := Label.new()
	# label 弱化为次级灰 (主次层级, 见 design §8.3); 收窄最小宽。
	lab.add_theme_font_size_override(&"font_size", UITheme.FS_SM)
	lab.add_theme_color_override(&"font_color", UITheme.TEXT_SECONDARY)
	lab.text = label_text
	lab.custom_minimum_size = Vector2(52, 0)
	lab.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	row.add_child(lab)
	var val := Label.new()
	# value 是玩家要读的数 → bold 字重 + 主色强调。
	val.add_theme_font_override(&"font", UITheme.get_ui_font_bold())
	val.add_theme_font_size_override(&"font_size", UITheme.FS_SM)
	val.add_theme_color_override(&"font_color", UITheme.TEXT_PRIMARY)
	val.text = value_text
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	val.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	val.max_lines_visible = max_lines
	val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	val.custom_minimum_size = Vector2(128, 0)
	row.add_child(val)
	return row

func _make_card_style(border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = UITheme.BG_SURFACE
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(UITheme.R_MD)
	sb.content_margin_left = UITheme.S_3
	sb.content_margin_right = UITheme.S_3
	sb.content_margin_top = UITheme.S_2
	sb.content_margin_bottom = UITheme.S_3
	return sb

func _make_fields_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = UITheme.BG_BASE
	sb.border_color = UITheme.BORDER_SUBTLE
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(UITheme.R_SM)
	sb.content_margin_left = UITheme.S_2
	sb.content_margin_right = UITheme.S_2
	sb.content_margin_top = UITheme.S_2
	sb.content_margin_bottom = UITheme.S_2
	return sb

func _apply_panel_style() -> void:
	if _normal_sb == null:
		return
	add_theme_stylebox_override(&"panel", _hover_sb if _hovered else _normal_sb)

func _accent_color(_kind: StringName) -> Color:
	return UITheme.ACCENT_INFO

func _card_badge_kind(_kind: StringName) -> StringName:
	return &"neutral"

func _action_kind(spec: Dictionary, id: StringName, primary_already_used: bool) -> StringName:
	if spec.has("kind"):
		return StringName(spec.get("kind", &"secondary"))
	if _CAUTION_ACTIONS.has(id):
		return &"secondary"
	return &"secondary" if primary_already_used else &"primary"

func _on_action_pressed(action_id: StringName) -> void:
	call_deferred(&"_emit_action_pressed_deferred", action_id)

func _emit_action_pressed_deferred(action_id: StringName) -> void:
	if not _action_buttons.has(action_id):
		return
	action_pressed.emit(action_id)

func _on_card_gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			card_clicked.emit()

# ─── 测试 introspection ──────────────────────────────────────

func get_title_text() -> String:
	return _title_label.text if _title_label != null else ""

func get_title_autowrap_for_test() -> int:
	return _title_label.autowrap_mode if _title_label != null else TextServer.AUTOWRAP_OFF

func get_title_max_lines_for_test() -> int:
	return _title_label.max_lines_visible if _title_label != null else 0

func get_subtitle_text() -> String:
	return _subtitle_label.text if _subtitle_label != null else ""

func get_subtitle_max_lines_for_test() -> int:
	return _subtitle_label.max_lines_visible if _subtitle_label != null else 0

func get_card_panel_style_for_test() -> StyleBox:
	return get_theme_stylebox(&"panel")

func get_accent_height_for_test() -> int:
	return int(_accent_bar.custom_minimum_size.y) if _accent_bar != null else 0

func get_accent_color_for_test() -> Color:
	return _accent_bar.color if _accent_bar != null else Color.MAGENTA

func set_hovered_for_test(hovered: bool) -> void:
	_hovered = hovered
	_apply_panel_style()

# 主次层级 introspection: 标题字体 / 字段 label·value 颜色与字体 (验证字重 + 灰度)。
func get_title_font_for_test() -> Font:
	return _title_label.get_theme_font(&"font") if _title_label != null else null

func is_fields_panel_visible_for_test() -> bool:
	return _fields_panel != null and _fields_panel.visible

func get_fields_panel_bg_for_test() -> Color:
	if _fields_panel == null:
		return Color.MAGENTA
	var sb := _fields_panel.get_theme_stylebox(&"panel")
	if sb is StyleBoxFlat:
		return (sb as StyleBoxFlat).bg_color
	return Color.MAGENTA

func get_field_label_color_for_test(idx: int) -> Color:
	var labels := _field_labels_for_test(idx)
	return labels[0].get_theme_color(&"font_color") if labels.size() >= 1 else Color.MAGENTA

func get_field_value_color_for_test(idx: int) -> Color:
	var labels := _field_labels_for_test(idx)
	return labels[1].get_theme_color(&"font_color") if labels.size() >= 2 else Color.MAGENTA

func get_field_value_font_for_test(idx: int) -> Font:
	var labels := _field_labels_for_test(idx)
	return labels[1].get_theme_font(&"font") if labels.size() >= 2 else null

func get_field_value_autowrap_for_test(idx: int) -> int:
	var labels := _field_labels_for_test(idx)
	return labels[1].autowrap_mode if labels.size() >= 2 else TextServer.AUTOWRAP_OFF

func get_field_value_max_lines_for_test(idx: int) -> int:
	var labels := _field_labels_for_test(idx)
	return labels[1].max_lines_visible if labels.size() >= 2 else 0

func get_field_value_alignment_for_test(idx: int) -> HorizontalAlignment:
	var labels := _field_labels_for_test(idx)
	return labels[1].horizontal_alignment if labels.size() >= 2 else HORIZONTAL_ALIGNMENT_LEFT

func _field_labels_for_test(idx: int) -> Array:
	if _fields_container == null or idx < 0 or idx >= _fields_container.get_child_count():
		return []
	var out: Array = []
	for child in _fields_container.get_child(idx).get_children():
		if child is Label:
			out.append(child)
	return out

func is_subtitle_visible() -> bool:
	return _subtitle_label != null and _subtitle_label.visible

func is_avatar_visible() -> bool:
	return _avatar != null and _avatar.visible

func get_avatar_min_size_for_test() -> Vector2:
	return _avatar.custom_minimum_size if _avatar != null else Vector2.ZERO

# 头像是否走了贴图层 (有 texture) 而非 seed/glyph 回退 — 供 view 测试断言图标接入。
func is_avatar_texture_visible_for_test() -> bool:
	return _avatar != null and _avatar.has_method(&"is_texture_layer_visible") \
		and _avatar.is_texture_layer_visible()

func is_status_visible() -> bool:
	return _status_badge != null and _status_badge.visible

func get_status_label_text() -> String:
	if _status_badge == null or not _status_badge.has_method(&"get_label_text"):
		return ""
	return _status_badge.get_label_text()

func get_status_bg_color_for_test() -> Color:
	if _status_badge == null or not _status_badge.has_method(&"get_background_color"):
		return Color.MAGENTA
	return _status_badge.get_background_color()

func get_field_count() -> int:
	return _fields_container.get_child_count() if _fields_container != null else 0

func get_field_row_for_test(idx: int) -> Dictionary:
	if _fields_container == null or idx < 0 or idx >= _fields_container.get_child_count():
		return {}
	var row := _fields_container.get_child(idx)
	var labels: Array[Label] = []
	for child in row.get_children():
		if child is Label:
			labels.append(child as Label)
	if labels.size() < 2:
		return {}
	return {"label": labels[0].text, "value": labels[1].text}

func get_action_count() -> int:
	return _action_buttons.size()

func is_footer_visible() -> bool:
	return _footer != null and _footer.visible

func get_action_normal_bg_for_test(action_id: StringName) -> Color:
	if not _action_buttons.has(action_id):
		return Color.MAGENTA
	var btn: Button = _action_buttons[action_id]
	var sb := btn.get_theme_stylebox(&"normal")
	if sb is StyleBoxFlat:
		return (sb as StyleBoxFlat).bg_color
	return Color.MAGENTA

func click_action_for_test(action_id: StringName) -> void:
	if _action_buttons.has(action_id):
		(_action_buttons[action_id] as Button).pressed.emit()
