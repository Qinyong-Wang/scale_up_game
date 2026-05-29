extends AcceptDialog

## SettingsDialog — 通用设置对话框 (语言 + 自动存档)。Per design/国际化设计.md §11.0。
##
## 设置入口有两个、共用此对话框, 避免两处各写一份:
##   - 起始页菜单「设置」(开局前);
##   - 游戏内顶栏「设置」按钮 (中途切换, 不必退回起始页)。
##
## 语言切换走 Preferences.set_locale(): 既持久化 (user://preferences.cfg) 又发
## EventBus.locale_changed 让全局界面实时刷新。对话框自身也订阅 locale_changed,
## 所以开着对话框切语言, 它的 title / 标签 / 关闭按钮也即时跟随。
##
## 「返回主菜单」入口仅游戏内可见 (allow_return_to_menu, 由 main.gd 在 open() 前置
## true; 起始页保持 false 故隐藏)。点击先弹确认框, 确认后只 emit
## return_to_menu_requested —— 真正的「存档 + 切回起始页」由 main.gd 处理, 本组件不
## 碰 Save / 场景, 与导航解耦 (见 design/出身系统设计.md §1 / 国际化设计.md §11.0)。

## 玩家在确认框确认返回主菜单。订阅方 (main.gd) 负责存档 + 切场景。
signal return_to_menu_requested

## 是否显示「返回主菜单」按钮。起始页打开时 false (已在菜单), 游戏内顶栏置 true。
var allow_return_to_menu: bool = false

## 界面缩放下拉的取值映射 (index → ui_scale)。第 0 档 = 自动 (0.0)。
const _UI_SCALE_VALUES: Array[float] = [0.0, 1.0, 1.25, 1.5, 1.75, 2.0]

var _lang_label: Label
var _zh_btn: Button
var _en_btn: Button
var _fullscreen_check: CheckButton
var _ui_scale_label: Label
var _ui_scale_option: OptionButton
var _autosave_check: CheckButton
var _music_check: CheckButton
var _volume_label: Label
var _volume_slider: HSlider
var _sfx_check: CheckButton
var _content_scroll: ScrollContainer
var _display_section: PanelContainer
var _audio_section: PanelContainer
var _system_section: PanelContainer
var _display_title_label: Label
var _audio_title_label: Label
var _system_title_label: Label
var _return_box: VBoxContainer
var _return_btn: Button
var _confirm_dialog: ConfirmationDialog

func _ready() -> void:
	title = tr("SETTINGS_TITLE")
	min_size = Vector2i(720, 560)
	dialog_hide_on_ok = true
	get_ok_button().text = tr("ACTION_CLOSE")

	_content_scroll = ScrollContainer.new()
	_content_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content_scroll.custom_minimum_size = Vector2(660, 430)
	add_child(_content_scroll)

	var content_margin := MarginContainer.new()
	content_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_margin.add_theme_constant_override(&"margin_left", UITheme.S_1)
	content_margin.add_theme_constant_override(&"margin_right", UITheme.S_1)
	content_margin.add_theme_constant_override(&"margin_top", UITheme.S_1)
	content_margin.add_theme_constant_override(&"margin_bottom", UITheme.S_1)
	_content_scroll.add_child(content_margin)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override(&"separation", UITheme.S_3)
	content_margin.add_child(col)

	var display := _make_section("SETTINGS_SECTION_DISPLAY", &"display")
	_display_section = display["panel"] as PanelContainer
	_display_title_label = display["title"] as Label
	var display_body := display["body"] as VBoxContainer
	col.add_child(_display_section)

	# ---- 语言 ------------------------------------------------------------
	_lang_label = Label.new()
	_lang_label.text = tr("SETTINGS_LANGUAGE")
	_style_field_label(_lang_label)

	var lang_row := HBoxContainer.new()
	lang_row.add_theme_constant_override(&"separation", UITheme.S_2)
	# codename 同理, 语言名保持各自母语写法, 不走 tr()。
	_zh_btn = Button.new()
	_zh_btn.text = "中文"
	_zh_btn.pressed.connect(func(): _select_locale("zh_CN"))
	_en_btn = Button.new()
	_en_btn.text = "English"
	_en_btn.pressed.connect(func(): _select_locale("en"))
	UITheme.apply_button_variant(_zh_btn, &"toolbar")
	UITheme.apply_button_variant(_en_btn, &"toolbar")
	lang_row.add_child(_zh_btn)
	lang_row.add_child(_en_btn)
	_add_labeled_control(display_body, _lang_label, lang_row)

	# ---- 全屏 ------------------------------------------------------------
	_fullscreen_check = CheckButton.new()
	_fullscreen_check.text = tr("SETTINGS_FULLSCREEN")
	_fullscreen_check.button_pressed = Preferences.fullscreen
	_fullscreen_check.toggled.connect(func(on): UITheme.set_fullscreen(on))
	display_body.add_child(_fullscreen_check)

	# ---- 界面缩放 --------------------------------------------------------
	# 自动 (按显示器分辨率) + 若干手动倍率档; 见 design/UI视觉系统设计.md §9bis。
	_ui_scale_label = Label.new()
	_ui_scale_label.text = tr("SETTINGS_UI_SCALE")
	_style_field_label(_ui_scale_label)
	_ui_scale_option = OptionButton.new()
	_ui_scale_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rebuild_ui_scale_items()
	_ui_scale_option.item_selected.connect(_on_ui_scale_selected)
	_add_labeled_control(display_body, _ui_scale_label, _ui_scale_option)

	var audio := _make_section("SETTINGS_SECTION_AUDIO", &"audio")
	_audio_section = audio["panel"] as PanelContainer
	_audio_title_label = audio["title"] as Label
	var audio_body := audio["body"] as VBoxContainer
	col.add_child(_audio_section)


	# ---- 背景音乐 --------------------------------------------------------
	# 单消费者, 直接调 MusicPlayer.set_enabled (持久化 + 起 / 停播)。
	_music_check = CheckButton.new()
	_music_check.text = tr("SETTINGS_MUSIC")
	_music_check.button_pressed = MusicPlayer.is_enabled()
	_music_check.toggled.connect(func(on): MusicPlayer.set_enabled(on))
	audio_body.add_child(_music_check)

	# ---- 音乐音量 (0..1 滑块) -------------------------------------------
	_volume_label = Label.new()
	_volume_label.text = tr("SETTINGS_MUSIC_VOLUME")
	_style_field_label(_volume_label)
	_volume_slider = HSlider.new()
	_volume_slider.min_value = 0.0
	_volume_slider.max_value = 1.0
	_volume_slider.step = 0.05
	_volume_slider.value = MusicPlayer.get_volume()
	_volume_slider.custom_minimum_size = Vector2(320, 0)
	_volume_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_volume_slider.value_changed.connect(func(v): MusicPlayer.set_volume(v))
	_add_labeled_control(audio_body, _volume_label, _volume_slider)

	# ---- 界面音效 --------------------------------------------------------
	_sfx_check = CheckButton.new()
	_sfx_check.text = tr("SETTINGS_SFX")
	_sfx_check.button_pressed = SfxPlayer.is_enabled()
	_sfx_check.toggled.connect(func(on): SfxPlayer.set_enabled(on))
	audio_body.add_child(_sfx_check)

	var system := _make_section("SETTINGS_SECTION_SYSTEM", &"system")
	_system_section = system["panel"] as PanelContainer
	_system_title_label = system["title"] as Label
	var system_body := system["body"] as VBoxContainer
	col.add_child(_system_section)

	# ---- 自动存档 --------------------------------------------------------
	_autosave_check = CheckButton.new()
	_autosave_check.text = tr("SETTINGS_AUTOSAVE")
	_autosave_check.button_pressed = TurnManager.autosave_enabled
	_autosave_check.toggled.connect(func(on): TurnManager.autosave_enabled = on)
	system_body.add_child(_autosave_check)

	# ---- 返回主菜单 (仅游戏内) ------------------------------------------
	# 默认隐藏; open() 时按 allow_return_to_menu 决定是否显示。
	_return_box = VBoxContainer.new()
	_return_box.add_theme_constant_override(&"separation", UITheme.S_2)
	_return_box.add_child(HSeparator.new())
	_return_btn = Button.new()
	_return_btn.text = tr("SETTINGS_RETURN_TO_MENU")
	_return_btn.pressed.connect(_on_return_pressed)
	UITheme.apply_button_variant(_return_btn, &"danger")
	_return_box.add_child(_return_btn)
	_return_box.visible = false
	system_body.add_child(_return_box)

	_sync_lang_buttons()
	# 开着对话框切语言时, 自身文案也实时刷新 (§11.0)。
	EventBus.locale_changed.connect(_on_locale_changed)

func _make_section(title_key: String, icon_kind: StringName) -> Dictionary:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override(&"panel", _section_stylebox())

	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override(&"separation", UITheme.S_3)
	panel.add_child(box)

	var header := HBoxContainer.new()
	header.alignment = BoxContainer.ALIGNMENT_BEGIN
	header.add_theme_constant_override(&"separation", UITheme.S_2)
	box.add_child(header)

	var icon := _SectionIcon.new()
	icon.kind = icon_kind
	icon.custom_minimum_size = Vector2(28, 28)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(icon)

	var title_label := Label.new()
	title_label.text = tr(title_key)
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.add_theme_font_override(&"font", UITheme.get_ui_font_bold())
	title_label.add_theme_font_size_override(&"font_size", UITheme.FS_MD)
	title_label.add_theme_color_override(&"font_color", UITheme.TEXT_PRIMARY)
	header.add_child(title_label)

	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override(&"separation", UITheme.S_2)
	box.add_child(body)

	return {panel = panel, title = title_label, body = body}

func _section_stylebox() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = UITheme.BG_SURFACE
	sb.border_color = UITheme.BORDER_SUBTLE
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(UITheme.R_MD)
	sb.content_margin_left = UITheme.S_4
	sb.content_margin_right = UITheme.S_4
	sb.content_margin_top = UITheme.S_4
	sb.content_margin_bottom = UITheme.S_4
	return sb

func _style_field_label(label: Label) -> void:
	label.add_theme_font_size_override(&"font_size", UITheme.FS_SM)
	label.add_theme_color_override(&"font_color", UITheme.TEXT_SECONDARY)

func _add_labeled_control(parent: VBoxContainer, label: Label, control: Control) -> void:
	var row := GridContainer.new()
	row.columns = 2
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override(&"h_separation", UITheme.S_4)
	row.add_theme_constant_override(&"v_separation", UITheme.S_1)
	label.custom_minimum_size.x = 140
	label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	row.add_child(control)
	parent.add_child(row)

## 复用入口: 每次打开同步当前 locale / autosave 状态后居中弹出。
func open() -> void:
	_sync_lang_buttons()
	if _autosave_check != null:
		_autosave_check.button_pressed = TurnManager.autosave_enabled
	if _music_check != null:
		_music_check.button_pressed = MusicPlayer.is_enabled()
	if _volume_slider != null:
		_volume_slider.set_value_no_signal(MusicPlayer.get_volume())
	if _sfx_check != null:
		_sfx_check.button_pressed = SfxPlayer.is_enabled()
	if _fullscreen_check != null:
		_fullscreen_check.set_pressed_no_signal(Preferences.fullscreen)
	if _ui_scale_option != null:
		_sync_ui_scale_selection()
	# 起始页 (allow_return_to_menu=false) 隐藏返回入口, 游戏内顶栏显示。
	if _return_box != null:
		_return_box.visible = allow_return_to_menu
	popup_centered()

## 重建界面缩放下拉项 (locale 变时「自动」文案要跟着刷)。
func _rebuild_ui_scale_items() -> void:
	if _ui_scale_option == null:
		return
	_ui_scale_option.clear()
	_ui_scale_option.add_item(tr("SETTINGS_UI_SCALE_AUTO"))  # index 0 = 自动
	for i in range(1, _UI_SCALE_VALUES.size()):
		_ui_scale_option.add_item("%d%%" % int(round(_UI_SCALE_VALUES[i] * 100.0)))
	_sync_ui_scale_selection()

## 选中与当前 Preferences.ui_scale 对应的档 (找不到则回落自动)。
func _sync_ui_scale_selection() -> void:
	if _ui_scale_option == null:
		return
	var idx := 0
	for i in _UI_SCALE_VALUES.size():
		if is_equal_approx(_UI_SCALE_VALUES[i], Preferences.ui_scale):
			idx = i
			break
	_ui_scale_option.select(idx)

func _on_ui_scale_selected(idx: int) -> void:
	if idx < 0 or idx >= _UI_SCALE_VALUES.size():
		return
	UITheme.set_ui_scale(_UI_SCALE_VALUES[idx])

## 点「返回主菜单」: 先弹确认框, 确认才对外发信号 (避免误点丢局)。
func _on_return_pressed() -> void:
	if _confirm_dialog == null:
		_confirm_dialog = ConfirmationDialog.new()
		_confirm_dialog.confirmed.connect(_on_return_confirmed)
		add_child(_confirm_dialog)
	_confirm_dialog.title = tr("RETURN_TO_MENU_CONFIRM_TITLE")
	_confirm_dialog.dialog_text = tr("RETURN_TO_MENU_CONFIRM_BODY")
	_confirm_dialog.get_ok_button().text = tr("RETURN_TO_MENU_CONFIRM_OK")
	_confirm_dialog.get_cancel_button().text = tr("ACTION_CANCEL")
	_confirm_dialog.popup_centered()

func _on_return_confirmed() -> void:
	# 真正的存档 + 切回起始页由 main.gd 在 return_to_menu_requested 上处理。
	hide()
	return_to_menu_requested.emit()

func _select_locale(loc: String) -> void:
	# set_locale 内部会 emit locale_changed → _on_locale_changed 同步置灰态,
	# 但 locale 未变时它早退不发信号, 这里再同步一次兜底。
	Preferences.set_locale(loc)
	_sync_lang_buttons()

## 当前语言对应的按钮置灰, 让玩家看出选中项。
func _sync_lang_buttons() -> void:
	if _zh_btn != null:
		_zh_btn.disabled = Preferences.locale == "zh_CN"
	if _en_btn != null:
		_en_btn.disabled = Preferences.locale == "en"

func _on_locale_changed(_loc: String) -> void:
	title = tr("SETTINGS_TITLE")
	get_ok_button().text = tr("ACTION_CLOSE")
	if _display_title_label != null:
		_display_title_label.text = tr("SETTINGS_SECTION_DISPLAY")
	if _audio_title_label != null:
		_audio_title_label.text = tr("SETTINGS_SECTION_AUDIO")
	if _system_title_label != null:
		_system_title_label.text = tr("SETTINGS_SECTION_SYSTEM")
	if _lang_label != null:
		_lang_label.text = tr("SETTINGS_LANGUAGE")
	if _autosave_check != null:
		_autosave_check.text = tr("SETTINGS_AUTOSAVE")
	if _music_check != null:
		_music_check.text = tr("SETTINGS_MUSIC")
	if _volume_label != null:
		_volume_label.text = tr("SETTINGS_MUSIC_VOLUME")
	if _sfx_check != null:
		_sfx_check.text = tr("SETTINGS_SFX")
	if _fullscreen_check != null:
		_fullscreen_check.text = tr("SETTINGS_FULLSCREEN")
	if _ui_scale_label != null:
		_ui_scale_label.text = tr("SETTINGS_UI_SCALE")
	_rebuild_ui_scale_items()
	if _return_btn != null:
		_return_btn.text = tr("SETTINGS_RETURN_TO_MENU")
	_sync_lang_buttons()

class _SectionIcon extends Control:
	var kind: StringName = &"display"

	func _ready() -> void:
		resized.connect(queue_redraw)

	func _draw() -> void:
		var bg := StyleBoxFlat.new()
		bg.bg_color = UITheme.ACCENT_INFO_SUBTLE
		bg.border_color = UITheme.BORDER_SUBTLE
		bg.set_border_width_all(1)
		bg.set_corner_radius_all(UITheme.R_SM)
		draw_style_box(bg, Rect2(Vector2.ZERO, size))
		var col := Color(UITheme.TEXT_PRIMARY, 0.72)
		var pad := 7.0
		match kind:
			&"audio":
				draw_line(Vector2(pad, size.y * 0.35), Vector2(size.x - pad, size.y * 0.35), col, 2.0)
				draw_circle(Vector2(size.x * 0.42, size.y * 0.35), 3.0, col)
				draw_line(Vector2(pad, size.y * 0.62), Vector2(size.x - pad, size.y * 0.62), col, 2.0)
				draw_circle(Vector2(size.x * 0.66, size.y * 0.62), 3.0, col)
			&"system":
				draw_circle(size * 0.5, 7.0, Color(UITheme.TEXT_PRIMARY, 0.10))
				draw_arc(size * 0.5, 7.0, 0.2, TAU * 0.86, 18, col, 2.0)
				draw_circle(size * 0.5, 2.8, col)
			_:
				var rect := Rect2(pad, pad + 1.0, size.x - pad * 2.0, size.y - pad * 2.0 - 2.0)
				draw_rect(rect, Color(UITheme.TEXT_PRIMARY, 0.09))
				draw_rect(Rect2(rect.position, Vector2(rect.size.x, 2.0)), col)
				draw_line(Vector2(size.x * 0.5, rect.end.y), Vector2(size.x * 0.5, rect.end.y + 3.0), col, 1.5)
				draw_line(Vector2(size.x * 0.35, rect.end.y + 4.0), Vector2(size.x * 0.65, rect.end.y + 4.0), col, 1.5)
