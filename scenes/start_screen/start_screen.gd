extends Control

## StartScreen — 游戏起始页. Per design/出身系统设计.md §1.
##
## 工程的 run/main_scene。提供 新游戏 / 继续游戏 / 读取存档 / 设置 / 退出。
## 进入游戏统一走 _enter_game() 切到 main.tscn (幂等)。
##
## AGI_AUTOPLAY / AGI_SCREENSHOT 环境变量存在时跳过菜单, 用默认开局直接进
## 游戏, 使端到端截图与自动演练流程不受影响。

const NewGameDialog := preload("res://scenes/ui/new_game_dialog/new_game_dialog.gd")
const SaveLoadDialog := preload("res://scenes/ui/save_load_dialog/save_load_dialog.gd")
const SettingsDialog := preload("res://scenes/ui/settings_dialog/settings_dialog.gd")
const MAIN_SCENE := "res://scenes/main/main.tscn"

## 菜单按钮视觉权重: 主操作 / 次操作 / 幽灵 (设置·退出)。见 design/出身系统设计.md §1。
enum _BtnVariant { PRIMARY, SECONDARY, GHOST }

var _new_game_btn: Button
var _continue_btn: Button
var _load_btn: Button
var _settings_btn: Button
var _quit_btn: Button
var _hero_card: PanelContainer
var _showcase_panel: Control
var _title_label: Label
var _subtitle_label: Label
var _status_label: Label
var _entering: bool = false

func _ready() -> void:
	if OS.has_environment("AGI_AUTOPLAY") or OS.has_environment("AGI_SCREENSHOT"):
		_start_default_game()
		return
	_apply_theme()
	_build_ui()
	EventBus.save_loaded.connect(_enter_game)
	# 在设置弹窗里切语言 → 实时刷新起始页文案 (国际化设计 §11.2)。
	EventBus.locale_changed.connect(func(_loc): _refresh_menu_text())
	# AGI_SHOT_MENU: 截「起始页」本身 (AGI_SCREENSHOT 那条路径会跳过菜单, 截不到),
	# 用于主菜单视觉验收。渲染几帧让布局/字体落定后存 PNG 退出。
	if OS.has_environment("AGI_SHOT_MENU"):
		_capture_menu_shot.call_deferred()
	# AGI_SHOT_NEWGAME: 打开新游戏对话框并截图, 用于三栏布局视觉验收。
	if OS.has_environment("AGI_SHOT_NEWGAME"):
		_capture_newgame_shot.call_deferred()
	# AGI_SHOT_SETTINGS: 打开设置对话框并截图, 用于偏好面板视觉验收。
	if OS.has_environment("AGI_SHOT_SETTINGS"):
		_capture_settings_shot.call_deferred()
	# AGI_SHOT_SAVELOAD: 打开存档对话框并截图, 用于存档面板视觉验收。
	if OS.has_environment("AGI_SHOT_SAVELOAD"):
		_capture_saveload_shot.call_deferred()

# ---- theme --------------------------------------------------------------

func _apply_theme() -> void:
	UITheme.install()
	var t := Theme.new()
	var font: Font = UITheme.get_ui_font()
	if font != null:
		t.default_font = font
		t.default_font_size = UITheme.DEFAULT_FONT_SIZE
		UITheme.apply_font_to_theme(t, font)
	theme = t

# ---- UI -----------------------------------------------------------------

func _build_ui() -> void:
	# 程序化办公室 / 数据中心背景, 让首屏题材感比纯灰底更强。
	var backdrop := _HeroBackdrop.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var stage := HBoxContainer.new()
	stage.alignment = BoxContainer.ALIGNMENT_CENTER
	stage.add_theme_constant_override(&"separation", UITheme.S_8)
	center.add_child(stage)

	# 左侧主操作面板 — 半透明 surface + 投影, 更像欢迎页主控台。
	_hero_card = PanelContainer.new()
	_hero_card.custom_minimum_size.x = 480
	_hero_card.add_theme_stylebox_override(&"panel", _card_stylebox())
	stage.add_child(_hero_card)

	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", UITheme.S_3)
	_hero_card.add_child(col)

	# ─── 品牌标记: 圆角蓝方块 + 抽象节点网络 ───────────────
	var logo_wrap := CenterContainer.new()
	col.add_child(logo_wrap)
	var logo := _LogoMark.new()
	logo.custom_minimum_size = Vector2(88, 88)
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	logo_wrap.add_child(logo)

	# ─── 双色字标 "Scaling Up" (hero 大字号, "Scaling" 炭黑 / "Up" 取灰, 黑灰白) ──
	var title_row := HBoxContainer.new()
	title_row.alignment = BoxContainer.ALIGNMENT_CENTER
	title_row.add_theme_constant_override(&"separation", 0)
	col.add_child(title_row)
	_title_label = _make_title_part("Scaling ", UITheme.TEXT_PRIMARY)
	title_row.add_child(_title_label)
	title_row.add_child(_make_title_part("Up", UITheme.TEXT_SECONDARY))

	_subtitle_label = Label.new()
	_subtitle_label.text = tr("APP_SUBTITLE")
	_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_subtitle_label.add_theme_font_size_override(&"font_size", UITheme.FS_HERO_SUB)
	_subtitle_label.add_theme_color_override(&"font_color", UITheme.TEXT_SECONDARY)
	col.add_child(_subtitle_label)

	var spacer := Control.new()
	spacer.custom_minimum_size.y = UITheme.S_5
	col.add_child(spacer)

	# ─── 菜单按钮: 主 / 次 / 幽灵三档视觉权重 ─────────────
	_new_game_btn = _make_menu_button(tr("MENU_NEW_GAME"), _on_new_game, _BtnVariant.PRIMARY)
	_continue_btn = _make_menu_button(tr("MENU_CONTINUE"), _on_continue, _BtnVariant.SECONDARY)
	_load_btn = _make_menu_button(tr("MENU_LOAD"), _on_load, _BtnVariant.SECONDARY)
	col.add_child(_new_game_btn)
	col.add_child(_continue_btn)
	col.add_child(_load_btn)

	# 设置 / 退出是辅助操作, 并排一行用幽灵按钮淡化。
	var aux_row := HBoxContainer.new()
	aux_row.add_theme_constant_override(&"separation", UITheme.S_3)
	col.add_child(aux_row)
	_settings_btn = _make_menu_button(tr("SETTINGS_TITLE"), _on_settings, _BtnVariant.GHOST)
	_quit_btn = _make_menu_button(tr("MENU_QUIT"), _on_quit, _BtnVariant.GHOST)
	aux_row.add_child(_settings_btn)
	aux_row.add_child(_quit_btn)

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_font_size_override(&"font_size", UITheme.FS_BASE)
	_status_label.add_theme_color_override(&"font_color", UITheme.ACCENT_DANGER)
	# 无错误文案时不占行, 避免按钮和版本号之间留一道空隙。
	_status_label.visible = false
	col.add_child(_status_label)

	var version := Label.new()
	version.text = "v%s" % String(ProjectSettings.get_setting("application/config/version", ""))
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	version.add_theme_font_size_override(&"font_size", UITheme.FS_XS)
	version.add_theme_color_override(&"font_color", UITheme.TEXT_DISABLED)
	col.add_child(version)

	_showcase_panel = _ShowcasePanel.new()
	_showcase_panel.custom_minimum_size = Vector2(396, 520)
	_showcase_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(_showcase_panel)

	_refresh_continue_state()

## hero 字标的一段 (双色字标拆成两个 Label, 颜色不同)。
func _make_title_part(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override(&"font", UITheme.get_ui_font_bold())
	l.add_theme_font_size_override(&"font_size", UITheme.FS_HERO)
	l.add_theme_color_override(&"font_color", color)
	return l

func _make_menu_button(text: String, handler: Callable, variant: int) -> Button:
	var b := Button.new()
	b.text = text
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bold := variant == _BtnVariant.PRIMARY
	b.add_theme_font_override(&"font",
		UITheme.get_ui_font_bold() if bold else UITheme.get_ui_font())
	b.add_theme_font_size_override(&"font_size",
		UITheme.FS_HERO_SUB if variant != _BtnVariant.GHOST else UITheme.FS_MD)
	_style_button(b, variant)
	b.pressed.connect(handler)
	return b

## 按变体给按钮装 normal/hover/pressed/disabled/focus 状态箱 + 字色。
## 颜色全部取 UITheme token, hover/pressed 派生 (不写颜色字面量)。交互主调炭黑后,
## 深色按钮的 hover/pressed 用 lightened() 提亮才有可见反馈 (darken 近黑→看不出)。
func _style_button(b: Button, variant: int) -> void:
	var transparent := Color(0, 0, 0, 0)
	match variant:
		_BtnVariant.PRIMARY:
			var base := UITheme.ACCENT_INFO
			b.add_theme_stylebox_override(&"normal", _btn_box(base, base, 0))
			b.add_theme_stylebox_override(&"hover", _btn_box(base.lightened(0.12), base.lightened(0.12), 0))
			var pressed := _btn_box(base.lightened(0.22), base.lightened(0.22), 0)
			b.add_theme_stylebox_override(&"pressed", pressed)
			b.add_theme_stylebox_override(&"focus", _btn_box(base.lightened(0.12), base.lightened(0.12), 0))
			b.add_theme_stylebox_override(&"disabled", _btn_box(UITheme.BORDER_SUBTLE, UITheme.BORDER_SUBTLE, 0))
			for c in [&"font_color", &"font_hover_color", &"font_pressed_color",
					&"font_hover_pressed_color", &"font_focus_color"]:
				b.add_theme_color_override(c, UITheme.BG_SURFACE)
			b.add_theme_color_override(&"font_disabled_color", UITheme.TEXT_SECONDARY)
		_BtnVariant.SECONDARY:
			b.add_theme_stylebox_override(&"normal", _btn_box(UITheme.BG_SURFACE, UITheme.BORDER_SUBTLE, 1))
			var hover := _btn_box(UITheme.BG_ELEVATED, UITheme.BORDER_STRONG, 1)
			b.add_theme_stylebox_override(&"hover", hover)
			b.add_theme_stylebox_override(&"focus", hover.duplicate())
			b.add_theme_stylebox_override(&"pressed", _btn_box(UITheme.ACCENT_INFO_SUBTLE, UITheme.ACCENT_INFO, 1))
			b.add_theme_stylebox_override(&"disabled", _btn_box(UITheme.BG_SURFACE, UITheme.BORDER_SUBTLE, 1))
			b.add_theme_color_override(&"font_color", UITheme.TEXT_PRIMARY)
			b.add_theme_color_override(&"font_hover_color", UITheme.TEXT_PRIMARY)
			b.add_theme_color_override(&"font_focus_color", UITheme.TEXT_PRIMARY)
			b.add_theme_color_override(&"font_pressed_color", UITheme.ACCENT_INFO)
			b.add_theme_color_override(&"font_hover_pressed_color", UITheme.ACCENT_INFO)
			b.add_theme_color_override(&"font_disabled_color", UITheme.TEXT_DISABLED)
		_:  # GHOST — 设置 / 退出
			b.add_theme_stylebox_override(&"normal", _btn_box(transparent, transparent, 0))
			var hover := _btn_box(UITheme.BG_ELEVATED, transparent, 0)
			b.add_theme_stylebox_override(&"hover", hover)
			b.add_theme_stylebox_override(&"focus", hover.duplicate())
			b.add_theme_stylebox_override(&"pressed", _btn_box(UITheme.ACCENT_INFO_SUBTLE, transparent, 0))
			b.add_theme_stylebox_override(&"disabled", _btn_box(transparent, transparent, 0))
			b.add_theme_color_override(&"font_color", UITheme.TEXT_SECONDARY)
			b.add_theme_color_override(&"font_hover_color", UITheme.TEXT_PRIMARY)
			b.add_theme_color_override(&"font_focus_color", UITheme.TEXT_PRIMARY)
			b.add_theme_color_override(&"font_pressed_color", UITheme.ACCENT_INFO)

## 圆角按钮状态箱; 高度由内容边距 (上下 S_4) + hero 字号自然撑出, 不用矮按钮。
func _btn_box(bg: Color, border: Color, border_w: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(UITheme.R_MD)
	sb.content_margin_left = UITheme.S_5
	sb.content_margin_right = UITheme.S_5
	sb.content_margin_top = UITheme.S_4
	sb.content_margin_bottom = UITheme.S_4
	return sb

## 中央悬浮卡: 纯白 + R_LG 圆角 + 1px 描边 + 柔和投影 + 大内边距。
func _card_stylebox() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(UITheme.BG_SURFACE, 0.92)
	sb.border_color = Color(UITheme.BORDER_SUBTLE, 0.82)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(UITheme.R_LG)
	sb.content_margin_left = UITheme.S_10
	sb.content_margin_right = UITheme.S_10
	sb.content_margin_top = UITheme.S_10
	sb.content_margin_bottom = UITheme.S_6
	sb.shadow_color = Color(0, 0, 0, 0.10)
	sb.shadow_size = 24
	sb.shadow_offset = Vector2(0, 8)
	return sb

func _refresh_continue_state() -> void:
	if _continue_btn != null:
		_continue_btn.disabled = not _has_any_save()

## 语言切换后重设起始页所有文案 (标题 "Scaling Up" 中英相同, 不必刷)。
func _refresh_menu_text() -> void:
	if _subtitle_label != null:
		_subtitle_label.text = tr("APP_SUBTITLE")
	if _new_game_btn != null:
		_new_game_btn.text = tr("MENU_NEW_GAME")
	if _continue_btn != null:
		_continue_btn.text = tr("MENU_CONTINUE")
	if _load_btn != null:
		_load_btn.text = tr("MENU_LOAD")
	if _settings_btn != null:
		_settings_btn.text = tr("SETTINGS_TITLE")
	if _quit_btn != null:
		_quit_btn.text = tr("MENU_QUIT")

# ---- menu handlers ------------------------------------------------------

func _on_new_game() -> void:
	var dlg: NewGameDialog = NewGameDialog.new()
	add_child(dlg)
	dlg.start_requested.connect(_on_new_game_confirmed)
	dlg.canceled.connect(func(): dlg.queue_free())
	dlg.confirmed.connect(func(): dlg.queue_free())
	dlg.close_requested.connect(func(): dlg.queue_free())
	dlg.open()

func _on_new_game_confirmed(player_name: String, company_name: String,
		origin: StringName, company_logo: StringName = &"",
		founder_avatar: StringName = &"") -> void:
	GameState.reset()
	GameState.player_name = player_name
	GameState.company_name = company_name
	GameState.founder_origin = origin
	GameState.company_logo = company_logo
	GameState.founder_avatar = founder_avatar
	# 会话态标志: 进入 main 后弹一次新手引导 (读档 / 继续游戏不置)。见 教程与帮助系统设计.md §1。
	GameState.pending_intro = true
	Log.info(&"start", "new_game",
			{company = company_name, origin = origin, logo = company_logo,
			avatar = founder_avatar})
	_enter_game()

func _on_continue() -> void:
	var slot: StringName = _latest_slot()
	if slot == &"":
		_set_status(tr("MENU_NO_SAVE"))
		return
	var r: Dictionary = Save.read(slot)
	# 成功时 Save.read 触发 EventBus.save_loaded → _enter_game。
	if not r.get(&"ok", false):
		_set_status(tr("MENU_LOAD_FAILED") % String(r.get(&"error", &"unknown")))

func _on_load() -> void:
	var dlg: SaveLoadDialog = SaveLoadDialog.new()
	add_child(dlg)
	dlg.confirmed.connect(func(): dlg.queue_free())
	dlg.canceled.connect(func(): dlg.queue_free())
	dlg.close_requested.connect(func(): dlg.queue_free())
	# 读档成功 → Save.read 发 save_loaded → _enter_game 切场景。
	dlg.open()

func _on_settings() -> void:
	# 设置面板抽成可复用组件, 与游戏内顶栏共用 (国际化设计 §11.0)。
	var dlg: SettingsDialog = SettingsDialog.new()
	add_child(dlg)
	dlg.confirmed.connect(func(): dlg.queue_free())
	dlg.canceled.connect(func(): dlg.queue_free())
	dlg.close_requested.connect(func(): dlg.queue_free())
	dlg.open()

func _on_quit() -> void:
	get_tree().quit()

# ---- game entry ---------------------------------------------------------

func _enter_game(_arg = null) -> void:
	if _entering:
		return
	_entering = true
	Log.info(&"start", "enter_game", {turn = GameState.turn})
	# 在 GUT 测试里不真正切场景 (会卸载测试 runner 场景)。
	if _is_test_run():
		return
	# 延迟到下一空闲帧再切场景: _enter_game 是从对话框 confirmed / save_loaded
	# 回调里调的, 此时触发它的那次输入事件 (OK 点击 / 回车) 还在派发中。若同帧
	# 同步切场景, StartScreen 连同它内嵌的对话框 Window 被拆除, 队列里仍指向旧
	# viewport 的输入事件会触发引擎报错:
	#   _push_unhandled_input_internal: Condition "!is_inside_tree()" is true.
	# 推迟一帧让输入彻底排空后再换场景即可消除该报错。
	get_tree().change_scene_to_file.call_deferred(MAIN_SCENE)

func _is_test_run() -> bool:
	for arg in OS.get_cmdline_args():
		if arg.begins_with("-gtest") or arg.begins_with("-gdir") \
				or arg == "--test" or arg.find("gut_cmdln.gd") != -1:
			return true
	return false

func _start_default_game() -> void:
	GameState.reset()
	GameState.player_name = "创始人"
	GameState.company_name = "Scaling Up"
	GameState.founder_origin = &""
	_enter_game()

# ---- save slot helpers --------------------------------------------------

func _has_any_save() -> bool:
	return not Save.list_slots().is_empty()

## 最近一次存档: 优先 autosave, 否则按 saved_at 取最新。无存档返回 &""。
func _latest_slot() -> StringName:
	var slots: Array = Save.list_slots()
	if slots.is_empty():
		return &""
	if slots.has(Save.AUTOSAVE_SLOT):
		return Save.AUTOSAVE_SLOT
	var best: StringName = slots[0]
	var best_at: String = _slot_saved_at(best)
	for s in slots:
		var at: String = _slot_saved_at(s)
		if at > best_at:
			best_at = at
			best = s
	return best

func _slot_saved_at(slot: StringName) -> String:
	var path: String = "%s/%s.json" % [Save.save_dir, String(slot)]
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var raw: String = f.get_as_text()
	f.close()
	var json := JSON.new()
	if json.parse(raw) != OK or not (json.data is Dictionary):
		return ""
	return String((json.data as Dictionary).get("saved_at", ""))

func _set_status(text: String) -> void:
	if _status_label != null:
		_status_label.text = text
		_status_label.visible = not text.is_empty()

## AGI_SHOT_MENU 验收用: 等布局/字体落定后截 viewport 存 user://start_screen_shot.png。
func _capture_menu_shot() -> void:
	for _i in 8:
		await get_tree().process_frame
	await get_tree().create_timer(0.4).timeout
	var img: Image = get_viewport().get_texture().get_image()
	var path := "user://start_screen_shot.png"
	if img.save_png(path) == OK:
		Log.info(&"start", "menu_shot_saved", {path = ProjectSettings.globalize_path(path)})
	get_tree().quit()

## AGI_SHOT_NEWGAME 验收用: 打开新游戏对话框, 等布局落定后截 viewport 存 PNG。
func _capture_newgame_shot() -> void:
	_on_new_game()
	for _i in 12:
		await get_tree().process_frame
	await get_tree().create_timer(0.4).timeout
	var img: Image = get_viewport().get_texture().get_image()
	var path := "user://newgame_shot.png"
	if img.save_png(path) == OK:
		Log.info(&"start", "newgame_shot_saved", {path = ProjectSettings.globalize_path(path)})
	get_tree().quit()

## AGI_SHOT_SETTINGS 验收用: 打开设置对话框, 等布局落定后截 viewport 存 PNG。
func _capture_settings_shot() -> void:
	_on_settings()
	for _i in 12:
		await get_tree().process_frame
	await get_tree().create_timer(0.4).timeout
	var img: Image = get_viewport().get_texture().get_image()
	var path := "user://settings_dialog_shot.png"
	if img.save_png(path) == OK:
		Log.info(&"start", "settings_shot_saved", {path = ProjectSettings.globalize_path(path)})
	get_tree().quit()

## AGI_SHOT_SAVELOAD 验收用: 打开存档对话框, 等布局落定后截 viewport 存 PNG。
func _capture_saveload_shot() -> void:
	_on_load()
	for _i in 12:
		await get_tree().process_frame
	await get_tree().create_timer(0.4).timeout
	var img: Image = get_viewport().get_texture().get_image()
	var path := "user://save_load_dialog_shot.png"
	if img.save_png(path) == OK:
		Log.info(&"start", "saveload_shot_saved", {path = ProjectSettings.globalize_path(path)})
	get_tree().quit()

# ---- 装饰用内部控件 ------------------------------------------------------

## 全屏背景: 浅灰底 + 几块大半径低透明度中性灰柔光, 给欢迎页柔和现代质感。
## 品牌走黑灰白, 这里不用蓝/绿色块; 颜色取 UITheme 中性灰 token, 仅叠低 alpha。
class _HeroBackdrop extends Control:
	func _ready() -> void:
		resized.connect(queue_redraw)

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), UITheme.BG_BASE)
		if size.x <= 0.0 or size.y <= 0.0:
			return
		var base_y := size.y * 0.66
		draw_rect(Rect2(0, base_y, size.x, size.y - base_y),
			Color(UITheme.TEXT_PRIMARY, 0.035))
		_draw_circuit_lines(base_y)
		_draw_skyline(base_y)

	func _draw_circuit_lines(base_y: float) -> void:
		var line_col := Color(UITheme.BORDER_STRONG, 0.22)
		var active_col := Color(UITheme.ACCENT_PRIMARY, 0.22)
		var y1 := size.y * 0.30
		var y2 := size.y * 0.44
		var pts1 := PackedVector2Array([
			Vector2(size.x * 0.06, y1),
			Vector2(size.x * 0.22, y1),
			Vector2(size.x * 0.29, y1 + UITheme.S_8),
			Vector2(size.x * 0.44, y1 + UITheme.S_8),
		])
		var pts2 := PackedVector2Array([
			Vector2(size.x * 0.64, y2),
			Vector2(size.x * 0.72, y2 - UITheme.S_6),
			Vector2(size.x * 0.88, y2 - UITheme.S_6),
			Vector2(size.x * 0.94, base_y - UITheme.S_8),
		])
		draw_polyline(pts1, line_col, 1.4, true)
		draw_polyline(pts2, line_col, 1.4, true)
		for p in pts1:
			draw_circle(p, 3.0, active_col)
		for p in pts2:
			draw_circle(p, 3.0, line_col)

	func _draw_skyline(base_y: float) -> void:
		var building_col := Color(UITheme.TEXT_PRIMARY, 0.08)
		var building_alt := Color(UITheme.TEXT_PRIMARY, 0.055)
		var window_col := Color(UITheme.BG_SURFACE, 0.34)
		for i in range(12):
			var w := 74.0 + float((i * 17) % 38)
			var x := float(i) * size.x / 11.0 - w * 0.55
			var h := size.y * (0.16 + float((i * 19) % 11) / 100.0)
			var rect := Rect2(x, base_y - h, w, h)
			draw_rect(rect, building_col if i % 2 == 0 else building_alt)
			var cols: int = max(2, int(w / 18.0))
			var rows: int = max(2, int(h / 22.0))
			for c in range(cols):
				for r in range(rows):
					if (c + r + i) % 3 == 0:
						continue
					var wx := rect.position.x + 10.0 + float(c) * 16.0
					var wy := rect.position.y + 12.0 + float(r) * 18.0
					draw_rect(Rect2(wx, wy, 7, 4), window_col)

## 品牌标记: 炭黑圆角方块上画"上升的 A" (白色山峰 + 灰色增长横杠), 与 app 图标一致。
## 几何与黑灰白配色统一走 UITheme.draw_brand_mark, 不在这里重复硬编码。
class _LogoMark extends Control:
	func _ready() -> void:
		resized.connect(queue_redraw)

	func _draw() -> void:
		UITheme.draw_brand_mark(self, Rect2(Vector2.ZERO, size), true)

## 右侧装饰仪表: 小型算力曲线 / 任务轨道 / 排名线框。纯视觉, 不承载真实状态。
class _ShowcasePanel extends Control:
	const _COMPANY_LOGO_KEY := &"brand-01"
	const _TASK_ICON_KEYS := [
		&"pretrain",
		&"posttrain",
		&"evaluate",
		&"data_collection",
		&"tech_research",
	]

	var _company_logo_texture: Texture2D
	var _task_icons: Array[Texture2D] = []

	func _ready() -> void:
		_load_showcase_assets()
		resized.connect(queue_redraw)

	func loaded_company_logo_for_test() -> bool:
		return _company_logo_texture != null

	func loaded_task_icon_count_for_test() -> int:
		var count := 0
		for tex in _task_icons:
			if tex != null:
				count += 1
		return count

	func _draw() -> void:
		if size.x <= 0.0 or size.y <= 0.0:
			return
		var panel := _box(Color(UITheme.BG_SURFACE, 0.78),
			Color(UITheme.BORDER_SUBTLE, 0.76), UITheme.R_LG, UITheme.S_6)
		var outer := Rect2(Vector2.ZERO, size)
		draw_style_box(panel, outer)
		_draw_header()
		_draw_curve()
		_draw_ranks()
		_draw_tracks()

	func _load_showcase_assets() -> void:
		var missing: Array[String] = []
		_company_logo_texture = IconRegistry.company_logo_texture(_COMPANY_LOGO_KEY)
		if _company_logo_texture == null:
			missing.append("brand/%s" % String(_COMPANY_LOGO_KEY))
		_task_icons.clear()
		for key in _TASK_ICON_KEYS:
			var tex: Texture2D = IconRegistry.get_icon(&"task", key)
			_task_icons.append(tex)
			if tex == null:
				missing.append("task/%s" % String(key))
		if not missing.is_empty():
			Log.warn(&"ui", "start_screen_showcase_assets_missing", {missing = missing})

	func _draw_header() -> void:
		var logo_rect := Rect2(UITheme.S_6, UITheme.S_5, 48, 48)
		UITheme.draw_company_logo(self, logo_rect, _COMPANY_LOGO_KEY, true)
		var label_x := logo_rect.end.x + UITheme.S_4
		var chip_col := Color(UITheme.TEXT_PRIMARY, 0.74)
		draw_rect(Rect2(label_x, UITheme.S_6 + 4, 86, 8), chip_col)
		draw_rect(Rect2(label_x, UITheme.S_6 + 22, 138, 5),
			Color(UITheme.BORDER_STRONG, 0.38))
		for i in range(3):
			var x := size.x - UITheme.S_6 - 18 - float(i) * 26.0
			draw_circle(Vector2(x, UITheme.S_6 + 7), 5.0,
				Color(UITheme.ACCENT_PRIMARY, 0.28 + float(i) * 0.08))

	func _draw_curve() -> void:
		var chart := Rect2(UITheme.S_6, 86, size.x - UITheme.S_6 * 2, 128)
		draw_style_box(_box(Color(UITheme.BG_BASE, 0.72),
			Color(UITheme.BORDER_SUBTLE, 0.70), UITheme.R_MD, UITheme.S_3), chart)
		for i in range(4):
			var y := chart.position.y + 24.0 + float(i) * 24.0
			draw_line(Vector2(chart.position.x + 16, y),
				Vector2(chart.end.x - 16, y), Color(UITheme.BORDER_SUBTLE, 0.52), 1.0)
		var pts := PackedVector2Array()
		for i in range(7):
			var t := float(i) / 6.0
			var x := chart.position.x + 18.0 + t * (chart.size.x - 36.0)
			var y := chart.end.y - 28.0 - pow(t, 1.45) * 70.0 + sin(t * 9.0) * 7.0
			pts.append(Vector2(x, y))
		draw_polyline(pts, Color(UITheme.ACCENT_PRIMARY, 0.78), 3.0, true)
		for p in pts:
			draw_circle(p, 4.2, Color(UITheme.BG_SURFACE, 0.95))
			draw_circle(p, 2.3, Color(UITheme.ACCENT_PRIMARY, 0.88))

	func _draw_ranks() -> void:
		var left := UITheme.S_6
		var top := 244.0
		for i in range(4):
			var y := top + float(i) * 36.0
			draw_rect(Rect2(left, y, size.x - UITheme.S_6 * 2, 1),
				Color(UITheme.BORDER_SUBTLE, 0.58))
			_draw_icon_tile(Rect2(left + 4, y + 6, 24, 24), _task_icon(i), i)
			draw_rect(Rect2(left + 42, y + 12, 84 + float(3 - i) * 16.0, 7),
				Color(UITheme.TEXT_PRIMARY, 0.42))
			draw_rect(Rect2(size.x - UITheme.S_6 - 72, y + 10, 54, 8),
				Color(UITheme.ACCENT_INFO, 0.18 + float(i) * 0.035))

	func _draw_tracks() -> void:
		var top := size.y - 118.0
		var left := UITheme.S_6
		for i in range(3):
			var y := top + float(i) * 30.0
			_draw_icon_tile(Rect2(left + 2, y - 8, 24, 24), _task_icon(i + 2), i + 2)
			var rail_left := left + 36.0
			var rail := Rect2(rail_left, y, size.x - UITheme.S_6 - rail_left, 10)
			draw_rect(rail, Color(UITheme.BORDER_SUBTLE, 0.56))
			var fill_w := rail.size.x * (0.28 + float(i) * 0.22)
			draw_rect(Rect2(rail.position, Vector2(fill_w, rail.size.y)),
				Color(UITheme.TEXT_PRIMARY, 0.42))

	func _task_icon(index: int) -> Texture2D:
		if _task_icons.is_empty():
			return null
		return _task_icons[index % _task_icons.size()]

	func _draw_icon_tile(rect: Rect2, tex: Texture2D, seed: int) -> void:
		draw_style_box(_box(Color(UITheme.BG_ELEVATED, 0.96),
			Color(UITheme.BORDER_SUBTLE, 0.78), UITheme.R_SM, 0), rect)
		var inset: float = maxf(3.0, rect.size.x * 0.16)
		var icon_rect := rect.grow(-inset)
		if tex != null:
			draw_texture_rect(tex, icon_rect, false)
			return
		var center := rect.get_center()
		var radius: float = minf(rect.size.x, rect.size.y) * 0.22
		var alpha := 0.18 + float(seed % 3) * 0.04
		draw_circle(center, radius, Color(UITheme.TEXT_PRIMARY, alpha))
		draw_line(center + Vector2(-radius * 0.9, radius * 0.2),
			center + Vector2(radius * 0.9, -radius * 0.2),
			Color(UITheme.ACCENT_PRIMARY, 0.34), maxf(1.0, radius * 0.22), true)

	func _box(bg: Color, border: Color, radius: int, margin: int) -> StyleBoxFlat:
		var sb := StyleBoxFlat.new()
		sb.bg_color = bg
		sb.border_color = border
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(radius)
		sb.content_margin_left = margin
		sb.content_margin_right = margin
		sb.content_margin_top = margin
		sb.content_margin_bottom = margin
		return sb
