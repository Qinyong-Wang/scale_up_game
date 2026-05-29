extends Control

## IconButton — 图标按钮 (可带文字)。
##
## 用在顶栏 (推进回合 / 存档)、抽屉关闭、卡片 ⋯ 菜单等地方。
## icon 接 Variant: Texture2D 走 TextureRect, String 走 Label glyph。
##
## kind:
##   default — BG_SURFACE 底, TEXT_PRIMARY 字
##   primary — ACCENT_PRIMARY 底, 白字
##   danger  — ACCENT_DANGER 底, 白字
##   ghost   — 透明底, TEXT_PRIMARY 字

# 信号名不用 `pressed` 避免与 Button 自带的同名冲突。
signal pressed_with_id(action_id: StringName)

# 注: 这些表用 var (不是 const) 因为 UITheme.XXX 是 autoload 常量,
# 编译期不能内联进 const dict。运行时一次初始化, 不影响性能。
var _KIND_BG: Dictionary = {}
var _KIND_FG: Dictionary = {}

func _init_kind_tables() -> void:
	if not _KIND_BG.is_empty():
		return
	_KIND_BG = {
		&"default": UITheme.BG_SURFACE,
		&"primary": UITheme.ACCENT_PRIMARY,
		&"danger":  UITheme.ACCENT_DANGER,
		&"ghost":   Color(0, 0, 0, 0),
	}
	_KIND_FG = {
		&"default": UITheme.TEXT_PRIMARY,
		&"primary": Color.WHITE,
		&"danger":  Color.WHITE,
		&"ghost":   UITheme.TEXT_PRIMARY,
	}

var _action_id: StringName = &""
var _button: Button
var _bg: StyleBoxFlat
var _icon_label: Label        # glyph 模式
var _icon_tex: TextureRect    # 贴图模式
var _label_node: Label
var _kind: StringName = &"default"
var _icon_value: Variant = null

func _ready() -> void:
	_init_kind_tables()
	custom_minimum_size.y = max(custom_minimum_size.y, UITheme.BUTTON_H)

	_button = Button.new()
	_button.set_anchors_preset(Control.PRESET_FULL_RECT)
	_button.focus_mode = Control.FOCUS_NONE
	_button.flat = false
	_button.pressed.connect(_on_button_pressed)
	add_child(_button)

	# 自绘背景, 不受全局 Button theme 干扰。
	_bg = StyleBoxFlat.new()
	_bg.corner_radius_top_left = UITheme.R_SM
	_bg.corner_radius_top_right = UITheme.R_SM
	_bg.corner_radius_bottom_left = UITheme.R_SM
	_bg.corner_radius_bottom_right = UITheme.R_SM
	_bg.content_margin_left = UITheme.S_3
	_bg.content_margin_right = UITheme.S_3
	_bg.content_margin_top = UITheme.S_2
	_bg.content_margin_bottom = UITheme.S_2
	_button.add_theme_stylebox_override(&"normal", _bg)
	_button.add_theme_stylebox_override(&"hover", _bg)
	_button.add_theme_stylebox_override(&"pressed", _bg)
	_button.add_theme_stylebox_override(&"focus", _bg)
	# 用 row HBox 承载 icon + label, 而不是用 Button 自带 text/icon (它们不支持 glyph)。
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override(&"separation", UITheme.S_2)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_button.add_child(row)

	_icon_tex = TextureRect.new()
	_icon_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon_tex.custom_minimum_size = Vector2(16, 16)
	_icon_tex.visible = false
	row.add_child(_icon_tex)

	_icon_label = Label.new()
	_icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_icon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_icon_label.visible = false
	row.add_child(_icon_label)

	_label_node = Label.new()
	_label_node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label_node.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label_node.visible = false
	row.add_child(_label_node)

	_apply_kind(_kind)

func set_data(icon: Variant, label_text: String, action_id: StringName, kind: StringName) -> void:
	_action_id = action_id
	_icon_value = icon
	_kind = kind
	# 装 icon。
	if icon is Texture2D:
		_icon_tex.texture = icon
		_icon_tex.visible = true
		_icon_label.text = ""
		_icon_label.visible = false
	elif typeof(icon) == TYPE_STRING and not (icon as String).is_empty():
		_icon_label.text = icon
		_icon_label.visible = true
		_icon_tex.texture = null
		_icon_tex.visible = false
	else:
		_icon_label.text = ""
		_icon_label.visible = false
		_icon_tex.texture = null
		_icon_tex.visible = false
	# label
	_label_node.text = label_text
	_label_node.visible = not label_text.is_empty()
	_apply_kind(kind)

func _apply_kind(kind: StringName) -> void:
	var resolved: StringName = kind if _KIND_BG.has(kind) else &"default"
	_bg.bg_color = _KIND_BG[resolved]
	var fg: Color = _KIND_FG[resolved]
	_icon_label.add_theme_color_override(&"font_color", fg)
	_label_node.add_theme_color_override(&"font_color", fg)

func _on_button_pressed() -> void:
	pressed_with_id.emit(_action_id)

# ─── 测试 introspection ──────────────────────────────────────

func get_icon_glyph() -> String:
	return _icon_label.text if _icon_label != null else ""

func get_label_text() -> String:
	return _label_node.text if _label_node != null else ""

func is_label_visible() -> bool:
	return _label_node != null and _label_node.visible

func get_background_color() -> Color:
	return _bg.bg_color if _bg != null else Color.MAGENTA

func click_for_test() -> void:
	if _button != null:
		_button.pressed.emit()
