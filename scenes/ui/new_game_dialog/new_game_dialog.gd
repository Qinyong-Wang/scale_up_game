extends AcceptDialog

## NewGameDialog — 新游戏: 给自己和公司取名 + 选择「出身」+ 公司标志 + 创始人头像.
## Per design/出身系统设计.md §2.
##
## 脚本型对话框 (与 SaveLoadDialog 同构), 用 `NewGameDialog.new()` 实例化。
## 三栏布局 (做大): 左 = 取名 + 出身, 中 = 头像网格, 右 = 标志网格 + 实时预览卡。
## 确认后发出 `start_requested`, 由 StartScreen 写入 GameState 并切场景。
## headless GUT 不能模拟点击, 测试直接调 _set_names / _select_origin /
## _select_logo / _select_avatar / _on_start_pressed, 并读 _preview_* 校验预览。

signal start_requested(player_name: String, company_name: String, origin: StringName,
		company_logo: StringName, founder_avatar: StringName)

const DEFAULT_PLAYER_NAME := "创始人"
const DEFAULT_COMPANY_NAME := "Scaling Up"
const _AvatarScene := preload("res://scenes/ui/components/avatar/avatar.tscn")
const _TILE_SIDE := 68        # 标志瓦片边长
const _AVATAR_TILE := 110     # 头像瓦片更大 (玩家的脸, 2 列画廊式更醒目)
const _PREVIEW_SIDE := 96

var _player_input: LineEdit
var _company_input: LineEdit
var _selected_origin: StringName = &""
var _origin_cards: Dictionary = {}    # origin_id(StringName) -> PanelContainer
var _origin_title_labels: Dictionary = {}
var _origin_body_labels: Array[Label] = []
var _specs_by_id: Dictionary = {}     # origin_id(StringName) -> FounderOriginSpec
# 公司标志网格: 默认 A (&"") + IconRegistry.company_logo_keys(); 头像网格: 创始人专属头像 key。
var _selected_logo: StringName = &""
var _selected_avatar: StringName = &""
var _logo_cards: Dictionary = {}      # logo_id(StringName) -> PanelContainer
var _avatar_cards: Dictionary = {}    # avatar_key(StringName) -> PanelContainer

# Layout nodes used by tests and screenshot QA.
var _shell_panel: PanelContainer
var _identity_section: PanelContainer
var _avatar_section: PanelContainer
var _brand_section: PanelContainer
var _preview_panel: PanelContainer
var _name_error_label: Label
var _start_btn: Button
var _section_title_labels: Array[Label] = []

# 右栏实时预览卡部件。
var _preview_company_lbl: Label
var _preview_sub_lbl: Label
var _preview_logo_tile: Control
var _preview_avatar: Control
var _preview_avatar_key: StringName = &""

func _ready() -> void:
	title = tr("MENU_NEW_GAME")
	min_size = Vector2i(1240, 700)
	dialog_hide_on_ok = true
	_start_btn = get_ok_button()
	_start_btn.text = tr("NEWGAME_START")
	UITheme.apply_button_variant(_start_btn, &"create")
	var cancel_btn := add_cancel_button(tr("NEWGAME_BACK"))
	UITheme.apply_button_variant(cancel_btn, &"secondary")
	confirmed.connect(_on_start_pressed)

	for spec in FounderSystem.all_specs():
		_specs_by_id[spec.id] = spec

	var outer := MarginContainer.new()
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_theme_constant_override(&"margin_left", UITheme.S_1)
	outer.add_theme_constant_override(&"margin_right", UITheme.S_1)
	outer.add_theme_constant_override(&"margin_top", UITheme.S_1)
	outer.add_theme_constant_override(&"margin_bottom", UITheme.S_1)
	add_child(outer)

	_shell_panel = PanelContainer.new()
	_shell_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_shell_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_shell_panel.add_theme_stylebox_override(&"panel",
		_box(UITheme.BG_BASE, UITheme.BORDER_SUBTLE, UITheme.R_LG, UITheme.S_3))
	outer.add_child(_shell_panel)

	var root := HBoxContainer.new()
	root.add_theme_constant_override(&"separation", UITheme.S_3)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_shell_panel.add_child(root)

	root.add_child(_build_left_column())
	root.add_child(_build_middle_column())
	root.add_child(_build_right_column())

	# 改名即时反映到预览卡 (text_changed 只在用户输入时触发, _set_names 另行刷新)。
	if _player_input != null:
		_player_input.text_changed.connect(func(_t): _on_name_text_changed())
	if _company_input != null:
		_company_input.text_changed.connect(func(_t): _on_name_text_changed())

	# 默认选中第一种出身, 保证「开始游戏」永远是合法状态。
	var specs: Array = FounderSystem.all_specs()
	if not specs.is_empty():
		_select_origin(specs[0].id)
	# 默认标志 = 经典 A (&""); 默认头像 = 第一个可选 key。
	_select_logo(&"")
	var avatar_keys: Array = IconRegistry.founder_avatar_keys()
	if not avatar_keys.is_empty():
		_select_avatar(avatar_keys[0])
	_update_preview()
	_refresh_name_validation()

# ---- 三栏 ---------------------------------------------------------------

func _build_left_column() -> Control:
	var section: Dictionary = _make_section_panel("NEWGAME_SECTION_IDENTITY", &"identity", 414)
	_identity_section = section["panel"] as PanelContainer
	var col := section["body"] as VBoxContainer

	col.add_child(_make_field(tr("NEWGAME_YOUR_NAME"), tr("NEWGAME_PLAYER_PLACEHOLDER"), func(le): _player_input = le))
	col.add_child(_make_field(tr("NEWGAME_COMPANY_NAME"), tr("NEWGAME_COMPANY_PLACEHOLDER"), func(le): _company_input = le))
	_name_error_label = _make_required_label()
	col.add_child(_name_error_label)
	col.add_child(_make_subhead_label(tr("NEWGAME_CHOOSE_ORIGIN")))

	# 出身卡可能比左栏高 → 只滚左栏, 保证「开始游戏」与中右栏始终可见。
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var cards := VBoxContainer.new()
	cards.add_theme_constant_override(&"separation", UITheme.S_2)
	cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for spec in FounderSystem.all_specs():
		var card := _make_origin_card(spec)
		_origin_cards[spec.id] = card
		cards.add_child(card)
	scroll.add_child(cards)
	col.add_child(scroll)
	return _identity_section

func _build_middle_column() -> Control:
	var section: Dictionary = _make_section_panel("NEWGAME_CHOOSE_AVATAR", &"avatar", 284)
	_avatar_section = section["panel"] as PanelContainer
	var col := section["body"] as VBoxContainer
	col.add_child(_make_scroll_wrap(_make_avatar_grid()))
	return _avatar_section

func _build_right_column() -> Control:
	var section: Dictionary = _make_section_panel("NEWGAME_SECTION_BRAND", &"brand", 430)
	_brand_section = section["panel"] as PanelContainer
	var col := section["body"] as VBoxContainer
	col.add_child(_make_subhead_label(tr("NEWGAME_CHOOSE_LOGO")))
	col.add_child(_make_logo_grid())
	col.add_child(_build_preview_card())
	return _brand_section

# ---- UI builders --------------------------------------------------------

func _make_section_panel(title_key: String, icon_kind: StringName, min_width: float) -> Dictionary:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = min_width
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override(&"panel",
		_box(UITheme.BG_SURFACE, UITheme.BORDER_SUBTLE, UITheme.R_MD, UITheme.S_4))

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override(&"separation", UITheme.S_3)
	panel.add_child(col)

	var header := HBoxContainer.new()
	header.add_theme_constant_override(&"separation", UITheme.S_2)
	col.add_child(header)

	var icon := _SectionIcon.new()
	icon.kind = icon_kind
	icon.custom_minimum_size = Vector2(30, 30)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(icon)

	var title_lbl := Label.new()
	title_lbl.text = tr(title_key)
	title_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_override(&"font", UITheme.get_ui_font_bold())
	title_lbl.add_theme_font_size_override(&"font_size", UITheme.FS_LG)
	title_lbl.add_theme_color_override(&"font_color", UITheme.TEXT_PRIMARY)
	header.add_child(title_lbl)
	_section_title_labels.append(title_lbl)
	return {panel = panel, body = col, title = title_lbl}

func _make_field(label_text: String, placeholder: String, sink: Callable) -> Control:
	var row := VBoxContainer.new()
	row.add_theme_constant_override(&"separation", UITheme.S_1)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_override(&"font", UITheme.get_ui_font_bold())
	lbl.add_theme_font_size_override(&"font_size", UITheme.FS_BASE)
	lbl.add_theme_color_override(&"font_color", UITheme.TEXT_PRIMARY)
	row.add_child(lbl)
	var le := LineEdit.new()
	le.placeholder_text = placeholder
	le.max_length = 24
	le.custom_minimum_size.y = UITheme.CREATE_BUTTON_H
	le.add_theme_font_size_override(&"font_size", UITheme.FS_BASE)
	le.add_theme_color_override(&"font_color", UITheme.TEXT_PRIMARY)
	le.add_theme_color_override(&"font_placeholder_color", UITheme.TEXT_SECONDARY)
	le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(le)
	sink.call(le)
	return row

func _make_subhead_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_override(&"font", UITheme.get_ui_font_bold())
	lbl.add_theme_font_size_override(&"font_size", UITheme.FS_MD)
	lbl.add_theme_color_override(&"font_color", UITheme.TEXT_PRIMARY)
	return lbl

func _make_required_label() -> Label:
	var lbl := Label.new()
	lbl.text = tr("NEWGAME_NAMES_REQUIRED")
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_font_size_override(&"font_size", UITheme.FS_BASE)
	lbl.add_theme_color_override(&"font_color", UITheme.ACCENT_DANGER)
	return lbl

func _make_scroll_wrap(child: Control) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(child)
	return scroll

func _make_origin_card(spec) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override(&"panel", _card_stylebox(false))
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	# 整卡可点选 (与标志/头像瓦片一致, 省掉每卡一个「选择」按钮, 三张卡才放得下)。
	# 子控件设 IGNORE 让点击落到 PanelContainer 的 gui_input。
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", UITheme.S_3)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)

	var icon := _OriginIcon.new()
	icon.origin_id = spec.id
	icon.custom_minimum_size = Vector2(46, 46)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override(&"separation", UITheme.S_1)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)

	var name_lbl := Label.new()
	name_lbl.text = tr(spec.display_name)
	name_lbl.add_theme_font_override(&"font", UITheme.get_ui_font_bold())
	name_lbl.add_theme_font_size_override(&"font_size", UITheme.FS_LG)
	name_lbl.add_theme_color_override(&"font_color", UITheme.TEXT_PRIMARY)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(name_lbl)
	_origin_title_labels[spec.id] = name_lbl

	var desc_lbl := Label.new()
	desc_lbl.text = tr(spec.description)
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.add_theme_font_size_override(&"font_size", UITheme.FS_BASE)
	desc_lbl.add_theme_color_override(&"font_color", UITheme.TEXT_SECONDARY)
	desc_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(desc_lbl)
	_origin_body_labels.append(desc_lbl)

	var perk_lbl := Label.new()
	perk_lbl.text = "+ %s" % tr(spec.perk_summary)
	perk_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	perk_lbl.add_theme_font_size_override(&"font_size", UITheme.FS_BASE)
	perk_lbl.add_theme_color_override(&"font_color", UITheme.ACCENT_PRIMARY)
	perk_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(perk_lbl)
	_origin_body_labels.append(perk_lbl)

	var draw_lbl := Label.new()
	draw_lbl.text = "- %s" % tr(spec.drawback_summary)
	draw_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	draw_lbl.add_theme_font_size_override(&"font_size", UITheme.FS_BASE)
	draw_lbl.add_theme_color_override(&"font_color", UITheme.ACCENT_DANGER)
	draw_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(draw_lbl)
	_origin_body_labels.append(draw_lbl)

	panel.gui_input.connect(_on_tile_input.bind(_select_origin, spec.id))
	return panel

func _card_stylebox(selected: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = UITheme.BG_ELEVATED if selected else UITheme.BG_SURFACE
	sb.border_color = UITheme.ACCENT_INFO if selected else UITheme.BORDER_SUBTLE
	var w: int = 2 if selected else 1
	sb.border_width_left = w
	sb.border_width_right = w
	sb.border_width_top = w
	sb.border_width_bottom = w
	sb.content_margin_left = UITheme.S_3
	sb.content_margin_right = UITheme.S_3
	sb.content_margin_top = UITheme.S_3
	sb.content_margin_bottom = UITheme.S_3
	sb.set_corner_radius_all(UITheme.R_MD)
	return sb

func _tile_stylebox(selected: bool) -> StyleBoxFlat:
	# 紧凑选项瓦片描边 (比出身卡 content_margin 小, 给图形让位)。
	var sb := _card_stylebox(selected)
	sb.content_margin_left = UITheme.S_1
	sb.content_margin_right = UITheme.S_1
	sb.content_margin_top = UITheme.S_1
	sb.content_margin_bottom = UITheme.S_1
	return sb

func _box(bg: Color, border: Color, radius: int, margin: int, border_w: int = 1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = margin
	sb.content_margin_right = margin
	sb.content_margin_top = margin
	sb.content_margin_bottom = margin
	return sb

# ---- logo / avatar pickers ----------------------------------------------

func _make_logo_grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 4
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override(&"h_separation", UITheme.S_2)
	grid.add_theme_constant_override(&"v_separation", UITheme.S_2)
	# 第一格 = 默认抽象 A (id &""); 其余 = 确定性生成的品牌标记 (brand-NN)。
	var ids: Array = [&""]
	ids.append_array(IconRegistry.company_logo_keys())
	for logo_id in ids:
		var tile := _LogoTile.new()
		tile.logo_id = logo_id
		tile.custom_minimum_size = Vector2(_TILE_SIDE, _TILE_SIDE)
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override(&"panel", _tile_stylebox(false))
		panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		panel.add_child(tile)
		panel.gui_input.connect(_on_tile_input.bind(_select_logo, logo_id))
		_logo_cards[logo_id] = panel
		grid.add_child(panel)
	return grid

func _make_avatar_grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.add_theme_constant_override(&"h_separation", UITheme.S_2)
	grid.add_theme_constant_override(&"v_separation", UITheme.S_2)
	for key in IconRegistry.founder_avatar_keys():
		var av := _AvatarScene.instantiate()
		av.custom_minimum_size = Vector2(_AVATAR_TILE, _AVATAR_TILE)
		av.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# 美术未就位 → texture 为 null, Avatar 自走 seed 配色 + glyph 回退。
		av.set_data(IconRegistry.founder_avatar(key), "", key, &"lead")
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override(&"panel", _tile_stylebox(false))
		panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		panel.add_child(av)
		panel.gui_input.connect(_on_tile_input.bind(_select_avatar, key))
		_avatar_cards[key] = panel
		grid.add_child(panel)
	return grid

func _on_tile_input(event: InputEvent, sink: Callable, value: StringName) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		sink.call(value)

class _LogoTile extends Control:
	var logo_id: StringName = &""
	func _ready() -> void:
		resized.connect(queue_redraw)
	func _draw() -> void:
		UITheme.draw_company_logo(self, Rect2(Vector2.ZERO, size), logo_id, true)

class _SectionIcon extends Control:
	var kind: StringName = &"identity"

	func _ready() -> void:
		resized.connect(queue_redraw)

	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, size)
		var bg := StyleBoxFlat.new()
		bg.bg_color = UITheme.ACCENT_INFO_SUBTLE
		bg.border_color = UITheme.BORDER_SUBTLE
		bg.set_border_width_all(1)
		bg.set_corner_radius_all(UITheme.R_SM)
		draw_style_box(bg, rect)
		var col := Color(UITheme.TEXT_PRIMARY, 0.74)
		var c := size * 0.5
		match kind:
			&"avatar":
				draw_circle(Vector2(c.x, c.y - 4), 5.0, col)
				draw_arc(Vector2(c.x, c.y + 10), 9.0, PI, TAU, 18, col, 2.0)
			&"brand":
				draw_circle(c, 8.0, Color(UITheme.TEXT_PRIMARY, 0.10))
				draw_line(Vector2(c.x - 8, c.y + 7), Vector2(c.x, c.y - 8), col, 2.0)
				draw_line(Vector2(c.x, c.y - 8), Vector2(c.x + 8, c.y + 7), col, 2.0)
			_:
				draw_rect(Rect2(c.x - 8, c.y - 8, 16, 16), Color(UITheme.TEXT_PRIMARY, 0.10))
				draw_line(Vector2(c.x - 8, c.y + 5), Vector2(c.x + 8, c.y + 5), col, 2.0)
				draw_line(Vector2(c.x - 4, c.y - 2), Vector2(c.x + 4, c.y - 2), col, 2.0)

class _OriginIcon extends Control:
	var origin_id: StringName = &""

	func _ready() -> void:
		resized.connect(queue_redraw)

	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, size)
		var bg := StyleBoxFlat.new()
		bg.bg_color = UITheme.BG_BASE
		bg.border_color = UITheme.BORDER_SUBTLE
		bg.set_border_width_all(1)
		bg.set_corner_radius_all(UITheme.R_MD)
		draw_style_box(bg, rect)
		var col := Color(UITheme.TEXT_PRIMARY, 0.70)
		var accent := UITheme.ACCENT_PRIMARY if origin_id == &"scientist" else UITheme.ACCENT_INFO
		if origin_id == &"influencer":
			accent = UITheme.ACCENT_WARNING
		var c := size * 0.5
		match origin_id:
			&"entrepreneur":
				draw_rect(Rect2(c.x - 11, c.y - 6, 22, 16), Color(accent, 0.16))
				draw_rect(Rect2(c.x - 10, c.y - 5, 20, 14), col, false, 2.0)
				draw_line(Vector2(c.x - 5, c.y - 8), Vector2(c.x + 5, c.y - 8), col, 2.0)
			&"influencer":
				draw_circle(c, 12.0, Color(accent, 0.16))
				draw_arc(c, 12.0, -0.7, 0.7, 18, col, 2.0)
				draw_circle(Vector2(c.x + 13, c.y), 3.0, accent)
			_:
				draw_circle(Vector2(c.x - 8, c.y - 4), 4.0, accent)
				draw_circle(Vector2(c.x + 8, c.y - 4), 4.0, accent)
				draw_circle(Vector2(c.x, c.y + 9), 4.0, accent)
				draw_line(Vector2(c.x - 5, c.y - 2), Vector2(c.x, c.y + 6), col, 2.0)
				draw_line(Vector2(c.x + 5, c.y - 2), Vector2(c.x, c.y + 6), col, 2.0)

# ---- 预览卡 -------------------------------------------------------------

func _build_preview_card() -> PanelContainer:
	_preview_panel = PanelContainer.new()
	_preview_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview_panel.add_theme_stylebox_override(&"panel",
		_box(UITheme.BG_BASE, UITheme.BORDER_SUBTLE, UITheme.R_MD, UITheme.S_4))

	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", UITheme.S_3)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview_panel.add_child(col)

	var title_lbl := _make_subhead_label(tr("NEWGAME_PREVIEW"))
	col.add_child(title_lbl)

	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", UITheme.S_4)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(row)

	_preview_logo_tile = _LogoTile.new()
	_preview_logo_tile.logo_id = _selected_logo
	_preview_logo_tile.custom_minimum_size = Vector2(_PREVIEW_SIDE, _PREVIEW_SIDE)
	_preview_logo_tile.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_preview_logo_tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_preview_logo_tile)

	var txt := VBoxContainer.new()
	txt.add_theme_constant_override(&"separation", UITheme.S_1)
	txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	txt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_preview_company_lbl = Label.new()
	_preview_company_lbl.add_theme_font_override(&"font", UITheme.get_ui_font_bold())
	_preview_company_lbl.add_theme_font_size_override(&"font_size", UITheme.FS_XL)
	_preview_company_lbl.add_theme_color_override(&"font_color", UITheme.TEXT_PRIMARY)
	_preview_company_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	txt.add_child(_preview_company_lbl)
	_preview_sub_lbl = Label.new()
	_preview_sub_lbl.add_theme_font_size_override(&"font_size", UITheme.FS_BASE)
	_preview_sub_lbl.add_theme_color_override(&"font_color", UITheme.TEXT_SECONDARY)
	_preview_sub_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	txt.add_child(_preview_sub_lbl)
	row.add_child(txt)

	_preview_avatar = _AvatarScene.instantiate()
	_preview_avatar.custom_minimum_size = Vector2(_PREVIEW_SIDE, _PREVIEW_SIDE)
	_preview_avatar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_preview_avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_preview_avatar)

	return _preview_panel

func _origin_display_name(origin: StringName) -> String:
	if _specs_by_id.has(origin):
		return tr(_specs_by_id[origin].display_name)
	return ""

func _update_preview() -> void:
	_preview_avatar_key = _selected_avatar
	if _preview_company_lbl != null:
		_preview_company_lbl.text = _resolved_company_name()
	if _preview_sub_lbl != null:
		var origin_name := _origin_display_name(_selected_origin)
		if origin_name.is_empty():
			_preview_sub_lbl.text = _resolved_player_name()
		else:
			_preview_sub_lbl.text = "%s · %s" % [_resolved_player_name(), origin_name]
	if _preview_logo_tile != null:
		_preview_logo_tile.logo_id = _selected_logo
		_preview_logo_tile.queue_redraw()
	if _preview_avatar != null:
		_preview_avatar.set_data(IconRegistry.founder_avatar(_selected_avatar), "", _selected_avatar, &"lead")

func _on_name_text_changed() -> void:
	_update_preview()
	_refresh_name_validation()

func _typed_player_name() -> String:
	return _player_input.text.strip_edges() if _player_input != null else ""

func _typed_company_name() -> String:
	return _company_input.text.strip_edges() if _company_input != null else ""

func _names_valid() -> bool:
	return not _typed_player_name().is_empty() and not _typed_company_name().is_empty()

func _refresh_name_validation() -> void:
	var valid := _names_valid()
	if _start_btn != null:
		_start_btn.disabled = not valid
	if _name_error_label != null:
		_name_error_label.text = tr("NEWGAME_NAMES_REQUIRED")
		_name_error_label.visible = not valid

# ---- selection / confirm ------------------------------------------------

func _select_origin(origin: StringName) -> void:
	_selected_origin = origin
	for id in _origin_cards.keys():
		var card: PanelContainer = _origin_cards[id]
		card.add_theme_stylebox_override(&"panel", _card_stylebox(id == origin))
	_update_preview()

func _select_logo(logo_id: StringName) -> void:
	_selected_logo = logo_id
	for id in _logo_cards.keys():
		var card: PanelContainer = _logo_cards[id]
		card.add_theme_stylebox_override(&"panel", _tile_stylebox(id == logo_id))
	_update_preview()

func _select_avatar(avatar_key: StringName) -> void:
	_selected_avatar = avatar_key
	for key in _avatar_cards.keys():
		var card: PanelContainer = _avatar_cards[key]
		card.add_theme_stylebox_override(&"panel", _tile_stylebox(key == avatar_key))
	_update_preview()

func open() -> void:
	popup_centered(min_size)

func _resolved_player_name() -> String:
	var v := _typed_player_name()
	return v if not v.is_empty() else tr("NEWGAME_PREVIEW_PLAYER_PLACEHOLDER")

func _resolved_company_name() -> String:
	var v := _typed_company_name()
	return v if not v.is_empty() else tr("NEWGAME_PREVIEW_COMPANY_PLACEHOLDER")

func _on_start_pressed() -> void:
	if not _names_valid():
		_refresh_name_validation()
		return
	var pname: String = _typed_player_name()
	var cname: String = _typed_company_name()
	Log.info(&"start", "new_game_requested",
			{player = pname, company = cname, origin = _selected_origin,
			logo = _selected_logo, avatar = _selected_avatar})
	start_requested.emit(pname, cname, _selected_origin, _selected_logo, _selected_avatar)

# ---- test helpers -------------------------------------------------------

func _set_names(player: String, company: String) -> void:
	if _player_input != null:
		_player_input.text = player
	if _company_input != null:
		_company_input.text = company
	_on_name_text_changed()
