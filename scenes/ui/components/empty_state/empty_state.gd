extends Control

## EmptyState — 空状态占位。
##
## 卡片墙数据为空时替换显示, icon + 标题 + 提示 + 行动号召按钮。
## 文案均为已翻译字符串。

signal action_pressed(action_id: StringName)

var _icon_label: Label
var _title_label: Label
var _hint_label: Label
var _action_button: Button
var _action_id: StringName = &""

func _ready() -> void:
	custom_minimum_size = Vector2(0, 160)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override(&"separation", UITheme.S_3)
	add_child(v)

	_icon_label = Label.new()
	_icon_label.add_theme_font_size_override(&"font_size", UITheme.FS_XXL)
	_icon_label.add_theme_color_override(&"font_color", UITheme.TEXT_DISABLED)
	_icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_icon_label)

	_title_label = Label.new()
	_title_label.add_theme_font_size_override(&"font_size", UITheme.FS_MD)
	_title_label.add_theme_color_override(&"font_color", UITheme.TEXT_PRIMARY)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_title_label)

	_hint_label = Label.new()
	_hint_label.add_theme_font_size_override(&"font_size", UITheme.FS_SM)
	_hint_label.add_theme_color_override(&"font_color", UITheme.TEXT_SECONDARY)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.visible = false
	v.add_child(_hint_label)

	# CTA 按钮独占一行, 居中。
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(btn_row)

	_action_button = Button.new()
	_action_button.visible = false
	UITheme.apply_button_variant(_action_button, &"create")
	_action_button.pressed.connect(_on_action_pressed)
	btn_row.add_child(_action_button)

func set_data(icon_glyph: String, title: String, hint: String, action_text: String, action_id: StringName) -> void:
	if _icon_label != null:
		_icon_label.text = icon_glyph
	if _title_label != null:
		_title_label.text = title
	if _hint_label != null:
		_hint_label.text = hint
		_hint_label.visible = not hint.is_empty()
	_action_id = action_id
	if _action_button != null:
		_action_button.text = action_text
		_action_button.visible = not action_text.is_empty()

func _on_action_pressed() -> void:
	action_pressed.emit(_action_id)

# ─── 测试 introspection ──────────────────────────────────────

func get_icon_glyph() -> String:
	return _icon_label.text if _icon_label != null else ""

func get_title_text() -> String:
	return _title_label.text if _title_label != null else ""

func get_hint_text() -> String:
	return _hint_label.text if _hint_label != null else ""

func is_hint_visible() -> bool:
	return _hint_label != null and _hint_label.visible

func is_action_visible() -> bool:
	return _action_button != null and _action_button.visible

func click_action_for_test() -> void:
	if _action_button != null and _action_button.visible:
		_action_button.pressed.emit()
