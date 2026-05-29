extends PanelContainer

## SidebarItem — 侧栏导航项。
##
## 直接继承 PanelContainer 而非 Control + 内部 Button: 让最小尺寸从子节点
## 冒泡到父 VBox; PanelContainer 自带 StyleBox 切换 (active vs inactive)。
##
## 布局: [3px active 竖条][28px icon tile][label]──[badge]
## 点击通过 gui_input 接住 (PanelContainer 本身可接事件)。

signal nav_pressed(nav_id: StringName)

var _active_bar: ColorRect
var _icon_slot: PanelContainer
var _icon_label: Label
var _text_label: Label
var _badge_pill: PanelContainer
var _badge_label: Label
var _row: HBoxContainer

var _normal_sb: StyleBoxFlat
var _hover_sb: StyleBoxFlat
var _active_sb: StyleBoxFlat
var _icon_normal_sb: StyleBoxFlat
var _icon_hover_sb: StyleBoxFlat
var _icon_active_sb: StyleBoxFlat
var _badge_sb: StyleBoxFlat

var _nav_id: StringName = &""
var _active: bool = false
var _hovered: bool = false
var _collapsed: bool = false

# 在 _ready 前调 set_data: 存参数延迟 apply。
var _pending_data: Array = []  # [icon, label, nav_id, badge_count]

func _ready() -> void:
	custom_minimum_size.y = max(custom_minimum_size.y, UITheme.SIDEBAR_ITEM_H)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(func():
		_hovered = true
		_apply_visual_state())
	mouse_exited.connect(func():
		_hovered = false
		_apply_visual_state())

	_normal_sb = _make_item_style(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0)
	_hover_sb = _make_item_style(UITheme.BG_SURFACE, UITheme.BORDER_SUBTLE, 1)
	_active_sb = _make_item_style(UITheme.ACCENT_INFO_SUBTLE, UITheme.BORDER_SUBTLE, 1)
	_icon_normal_sb = _make_icon_style(UITheme.BG_SURFACE, UITheme.BORDER_SUBTLE)
	_icon_hover_sb = _make_icon_style(UITheme.BG_ELEVATED, UITheme.BORDER_SUBTLE)
	_icon_active_sb = _make_icon_style(UITheme.ACCENT_INFO, UITheme.ACCENT_INFO)
	_badge_sb = _make_badge_style()
	add_theme_stylebox_override(&"panel", _normal_sb)

	_row = HBoxContainer.new()
	_row.add_theme_constant_override(&"separation", UITheme.S_2)
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_row)

	_active_bar = ColorRect.new()
	_active_bar.custom_minimum_size = Vector2(UITheme.SIDEBAR_ACTIVE_BAR_W, 22)
	_active_bar.color = Color(0, 0, 0, 0)
	_active_bar.visible = true
	_active_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_active_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_child(_active_bar)

	_icon_slot = PanelContainer.new()
	_icon_slot.custom_minimum_size = Vector2(UITheme.SIDEBAR_ICON_TILE, UITheme.SIDEBAR_ICON_TILE)
	_icon_slot.add_theme_stylebox_override(&"panel", _icon_normal_sb)
	_icon_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_child(_icon_slot)

	var icon_center := CenterContainer.new()
	icon_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon_slot.add_child(icon_center)

	_icon_label = Label.new()
	_icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_icon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_icon_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 图标用 Material Icons 字体 (码点字符); 缺字体时静默退化为普通字形。
	var icon_font := UITheme.get_icon_font()
	if icon_font != null:
		_icon_label.add_theme_font_override(&"font", icon_font)
	_icon_label.add_theme_font_size_override(&"font_size", UITheme.SIDEBAR_ICON_GLYPH_SIZE)
	icon_center.add_child(_icon_label)

	_text_label = Label.new()
	_text_label.add_theme_font_size_override(&"font_size", UITheme.FS_BASE)
	_text_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_text_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_child(_text_label)

	_badge_pill = PanelContainer.new()
	_badge_pill.add_theme_stylebox_override(&"panel", _badge_sb)
	_badge_pill.visible = false
	_badge_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_child(_badge_pill)

	_badge_label = Label.new()
	_badge_label.add_theme_font_size_override(&"font_size", UITheme.FS_XS)
	_badge_label.add_theme_color_override(&"font_color", UITheme.BG_SURFACE)
	_badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_badge_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_badge_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge_pill.add_child(_badge_label)

	_apply_visual_state()

	if not _pending_data.is_empty():
		var d := _pending_data
		_pending_data = []
		set_data(d[0], d[1], d[2], d[3])

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			nav_pressed.emit(_nav_id)
			accept_event()

func set_data(icon_glyph: String, label_text: String, nav_id: StringName, badge_count: int) -> void:
	if _text_label == null:
		_pending_data = [icon_glyph, label_text, nav_id, badge_count]
		return
	_nav_id = nav_id
	_icon_label.text = icon_glyph
	_text_label.text = label_text
	tooltip_text = label_text
	_apply_badge(badge_count)

## 单独刷新 badge 数 (≤0 隐藏)。set_data 之后随时可调, 不必重传 icon/label。
func set_badge(count: int) -> void:
	if _badge_label == null:
		# _ready 前调: 落到 _pending_data, 等 _ready 时 set_data 一并 apply。
		if _pending_data.size() == 4:
			_pending_data[3] = count
		return
	_apply_badge(count)

func set_active(active: bool) -> void:
	_active = active
	_apply_visual_state()

func is_active() -> bool:
	return _active

func set_collapsed(collapsed: bool) -> void:
	_collapsed = collapsed
	if _text_label != null:
		_text_label.visible = not collapsed

func _apply_visual_state() -> void:
	if _normal_sb == null:
		return
	add_theme_stylebox_override(&"panel", _active_sb if _active else (_hover_sb if _hovered else _normal_sb))
	if _active_bar != null:
		_active_bar.color = UITheme.ACCENT_INFO if _active else Color(0, 0, 0, 0)
	if _icon_slot != null:
		_icon_slot.add_theme_stylebox_override(&"panel",
			_icon_active_sb if _active else (_icon_hover_sb if _hovered else _icon_normal_sb))
	var label_fg: Color = UITheme.TEXT_PRIMARY if (_active or _hovered) else UITheme.TEXT_SECONDARY
	var icon_fg: Color = UITheme.BG_SURFACE if _active else label_fg
	if _text_label != null:
		_text_label.add_theme_color_override(&"font_color", label_fg)
		if _active:
			_text_label.add_theme_font_override(&"font", UITheme.get_ui_font_bold())
		else:
			_text_label.remove_theme_font_override(&"font")
	if _icon_label != null:
		_icon_label.add_theme_color_override(&"font_color", icon_fg)

func _apply_badge(count: int) -> void:
	if _badge_label == null:
		return
	if count > 0:
		_badge_label.text = str(count)
		_badge_pill.visible = true
	else:
		_badge_label.text = ""
		_badge_pill.visible = false

func _make_item_style(bg: Color, border: Color, border_w: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(UITheme.R_MD)
	sb.content_margin_left = UITheme.S_1
	sb.content_margin_right = UITheme.S_2
	sb.content_margin_top = UITheme.S_1
	sb.content_margin_bottom = UITheme.S_1
	return sb

func _make_icon_style(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(UITheme.R_MD)
	return sb

func _make_badge_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = UITheme.TEXT_PRIMARY
	sb.border_color = UITheme.TEXT_PRIMARY
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(UITheme.R_SM)
	sb.content_margin_left = UITheme.S_2
	sb.content_margin_right = UITheme.S_2
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	return sb

# ─── 测试 introspection ──────────────────────────────────────

func get_label_text() -> String:
	return _text_label.text if _text_label != null else ""

func get_icon_glyph() -> String:
	return _icon_label.text if _icon_label != null else ""

func is_label_visible() -> bool:
	return _text_label != null and _text_label.visible

func is_icon_visible() -> bool:
	return _icon_label != null and _icon_label.visible

func is_badge_visible() -> bool:
	return _badge_pill != null and _badge_pill.visible

func get_badge_text() -> String:
	return _badge_label.text if _badge_label != null else ""

func get_badge_bg_color_for_test() -> Color:
	return _flat_bg(_badge_pill)

func get_badge_label_color_for_test() -> Color:
	return _badge_label.get_theme_color(&"font_color") if _badge_label != null else Color.MAGENTA

func click_for_test() -> void:
	nav_pressed.emit(_nav_id)

func get_minimum_height_for_test() -> int:
	return int(custom_minimum_size.y)

func get_icon_slot_min_size() -> Vector2:
	return _icon_slot.custom_minimum_size if _icon_slot != null else Vector2.ZERO

func get_icon_font_size() -> int:
	return _icon_label.get_theme_font_size(&"font_size") if _icon_label != null else 0

func get_icon_tile_bg_color() -> Color:
	return _flat_bg(_icon_slot)

func get_icon_tile_border_color() -> Color:
	return _flat_border(_icon_slot)

func get_icon_color() -> Color:
	return _icon_label.get_theme_color(&"font_color") if _icon_label != null else Color.MAGENTA

func get_label_color() -> Color:
	return _text_label.get_theme_color(&"font_color") if _text_label != null else Color.MAGENTA

func get_active_bar_width_for_test() -> int:
	return int(_active_bar.custom_minimum_size.x) if _active_bar != null else 0

func get_active_bar_color_for_test() -> Color:
	return _active_bar.color if _active_bar != null else Color.MAGENTA

func _flat_bg(control: Control) -> Color:
	if control == null:
		return Color.MAGENTA
	var sb := control.get_theme_stylebox(&"panel")
	if sb is StyleBoxFlat:
		return (sb as StyleBoxFlat).bg_color
	return Color.MAGENTA

func _flat_border(control: Control) -> Color:
	if control == null:
		return Color.MAGENTA
	var sb := control.get_theme_stylebox(&"panel")
	if sb is StyleBoxFlat:
		return (sb as StyleBoxFlat).border_color
	return Color.MAGENTA
