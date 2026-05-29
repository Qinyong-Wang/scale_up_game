extends GutTest

## SettingsDialog — 设置对话框 (语言 + 自动存档)。Per design/国际化设计.md §11.0。
##
## 注意: 切 locale 是全局副作用, before/after_each 钉回 zh_CN 并恢复原值,
## 防止泄漏导致其它测试顺序相关 flaky (i18n 测试约束 §7)。

const SettingsDialog := preload("res://scenes/ui/settings_dialog/settings_dialog.gd")

const TEST_CONFIG_PATH := "user://test_settings_prefs.cfg"

var _saved_locale: String
var _saved_ts_locale: String
var _saved_autosave: bool
var _saved_music_enabled: bool
var _saved_music_volume: float
var _saved_sfx_enabled: bool
var _saved_fullscreen: bool
var _saved_ui_scale: float
var _saved_config_path: String

func before_each() -> void:
	_saved_locale = Preferences.locale
	_saved_ts_locale = TranslationServer.get_locale()
	_saved_autosave = TurnManager.autosave_enabled
	_saved_music_enabled = Preferences.music_enabled
	_saved_music_volume = Preferences.music_volume
	_saved_sfx_enabled = Preferences.sfx_enabled
	_saved_fullscreen = Preferences.fullscreen
	_saved_ui_scale = Preferences.ui_scale
	# 背景音乐开关测试会写偏好 → 重定向到临时文件, 不碰真实 preferences.cfg。
	_saved_config_path = Preferences._config_path
	Preferences._config_path = TEST_CONFIG_PATH
	Preferences.locale = "zh_CN"
	TranslationServer.set_locale("zh_CN")

func after_each() -> void:
	Preferences.locale = _saved_locale
	TranslationServer.set_locale(_saved_ts_locale)
	TurnManager.autosave_enabled = _saved_autosave
	# 停掉可能被开关打开的 autoload 播放, 并恢复偏好与路径。
	MusicPlayer.stop_music()
	Preferences.music_enabled = _saved_music_enabled
	Preferences.music_volume = _saved_music_volume
	Preferences.sfx_enabled = _saved_sfx_enabled
	Preferences.fullscreen = _saved_fullscreen
	Preferences.ui_scale = _saved_ui_scale
	Preferences._config_path = _saved_config_path
	if FileAccess.file_exists(TEST_CONFIG_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_CONFIG_PATH))

func _make_dialog():
	var dlg = SettingsDialog.new()
	add_child_autofree(dlg)
	return dlg

# ---- 结构 ---------------------------------------------------------------

func test_dialog_title_uses_settings_key() -> void:
	var dlg = _make_dialog()
	assert_eq(dlg.title, tr("SETTINGS_TITLE"))

func test_dialog_has_language_buttons() -> void:
	var dlg = _make_dialog()
	assert_not_null(dlg._zh_btn, "对话框应有中文按钮")
	assert_not_null(dlg._en_btn, "对话框应有 English 按钮")
	assert_eq(dlg._zh_btn.text, "中文")
	assert_eq(dlg._en_btn.text, "English")

func test_dialog_has_autosave_toggle() -> void:
	var dlg = _make_dialog()
	assert_not_null(dlg._autosave_check, "对话框应有自动存档开关")

func test_dialog_uses_sectioned_preference_panels() -> void:
	# SettingsDialog 是偏好面板, 不再是裸 VBox 表单
	# (design/国际化设计.md §11.0 / UI视觉系统设计.md §7.3)。
	var dlg = _make_dialog()
	assert_not_null(dlg._content_scroll, "设置内容应放入 ScrollContainer")
	assert_not_null(dlg._display_section, "设置应有「显示」分区面板")
	assert_not_null(dlg._audio_section, "设置应有「音频」分区面板")
	assert_not_null(dlg._system_section, "设置应有「系统」分区面板")
	assert_true(dlg._display_section is PanelContainer)
	assert_true(dlg._audio_section is PanelContainer)
	assert_true(dlg._system_section is PanelContainer)

func test_dialog_min_size_matches_preference_panel_design() -> void:
	var dlg = _make_dialog()
	assert_gte(dlg.min_size.x, 680, "设置弹窗宽度应足够容纳分区面板")
	assert_gte(dlg.min_size.y, 480, "设置弹窗高度应足够容纳分区面板")

func test_section_titles_are_localized() -> void:
	var dlg = _make_dialog()
	assert_eq(dlg._display_title_label.text, tr("SETTINGS_SECTION_DISPLAY"))
	assert_eq(dlg._audio_title_label.text, tr("SETTINGS_SECTION_AUDIO"))
	assert_eq(dlg._system_title_label.text, tr("SETTINGS_SECTION_SYSTEM"))
	dlg._en_btn.pressed.emit()
	assert_eq(dlg._display_title_label.text, tr("SETTINGS_SECTION_DISPLAY"),
		"切语言后显示分区标题应实时刷新")
	assert_eq(dlg._audio_title_label.text, tr("SETTINGS_SECTION_AUDIO"),
		"切语言后音频分区标题应实时刷新")
	assert_eq(dlg._system_title_label.text, tr("SETTINGS_SECTION_SYSTEM"),
		"切语言后系统分区标题应实时刷新")

# ---- 背景音乐开关 -------------------------------------------------------
# 设置对话框直接调 MusicPlayer.set_enabled (单消费者, 不走 EventBus,
# 见 design/音频系统设计.md §4)。

func test_dialog_has_music_toggle() -> void:
	var dlg = _make_dialog()
	assert_not_null(dlg._music_check, "对话框应有背景音乐开关")

func test_music_check_reflects_music_player() -> void:
	MusicPlayer.set_enabled(true)
	var dlg = _make_dialog()
	assert_true(dlg._music_check.button_pressed,
		"开关初值应读 MusicPlayer.is_enabled()")

func test_toggling_music_writes_music_player() -> void:
	var dlg = _make_dialog()
	dlg._music_check.toggled.emit(false)
	assert_false(MusicPlayer.is_enabled(), "关掉开关应写回 MusicPlayer")
	dlg._music_check.toggled.emit(true)
	assert_true(MusicPlayer.is_enabled(), "打开开关应写回 MusicPlayer")

func test_music_toggle_text_localized() -> void:
	var dlg = _make_dialog()
	assert_eq(dlg._music_check.text, tr("SETTINGS_MUSIC"))
	dlg._en_btn.pressed.emit()
	assert_eq(dlg._music_check.text, tr("SETTINGS_MUSIC"),
		"切语言后背景音乐开关文案应实时刷新")

# ---- 界面音效开关 -------------------------------------------------------

func test_dialog_has_sfx_toggle() -> void:
	var dlg = _make_dialog()
	assert_not_null(dlg._sfx_check, "对话框应有界面音效开关")

func test_sfx_check_reflects_sfx_player() -> void:
	SfxPlayer.set_enabled(true)
	var dlg = _make_dialog()
	assert_true(dlg._sfx_check.button_pressed,
		"开关初值应读 SfxPlayer.is_enabled()")

func test_toggling_sfx_writes_sfx_player() -> void:
	var dlg = _make_dialog()
	dlg._sfx_check.toggled.emit(false)
	assert_false(SfxPlayer.is_enabled(), "关掉界面音效应写回 SfxPlayer")
	dlg._sfx_check.toggled.emit(true)
	assert_true(SfxPlayer.is_enabled(), "打开界面音效应写回 SfxPlayer")

func test_sfx_toggle_text_localized() -> void:
	var dlg = _make_dialog()
	assert_eq(dlg._sfx_check.text, tr("SETTINGS_SFX"))
	dlg._en_btn.pressed.emit()
	assert_eq(dlg._sfx_check.text, tr("SETTINGS_SFX"),
		"切语言后界面音效开关文案应实时刷新")

# ---- 音乐音量滑块 -------------------------------------------------------

func test_dialog_has_music_volume_slider() -> void:
	var dlg = _make_dialog()
	assert_not_null(dlg._volume_slider, "对话框应有音乐音量滑块")

func test_volume_slider_reflects_music_player() -> void:
	Preferences.music_volume = 0.3
	var dlg = _make_dialog()
	assert_almost_eq(dlg._volume_slider.value, 0.3, 0.0001,
		"滑块初值应读 MusicPlayer.get_volume()")

func test_dragging_volume_writes_music_player() -> void:
	var dlg = _make_dialog()
	dlg._volume_slider.value_changed.emit(0.2)
	assert_almost_eq(MusicPlayer.get_volume(), 0.2, 0.0001,
		"拖动滑块应写回 MusicPlayer / Preferences")

# ---- 全屏开关 -----------------------------------------------------------

func test_dialog_has_fullscreen_toggle() -> void:
	var dlg = _make_dialog()
	assert_not_null(dlg._fullscreen_check, "对话框应有全屏开关")

func test_fullscreen_check_reflects_preferences() -> void:
	Preferences.fullscreen = true
	var dlg = _make_dialog()
	assert_true(dlg._fullscreen_check.button_pressed,
		"开关初值应读 Preferences.fullscreen")

func test_toggling_fullscreen_writes_preferences() -> void:
	var dlg = _make_dialog()
	dlg._fullscreen_check.toggled.emit(true)
	assert_true(Preferences.fullscreen, "打开全屏应写回 Preferences")
	dlg._fullscreen_check.toggled.emit(false)
	assert_false(Preferences.fullscreen, "关闭全屏应写回 Preferences")

func test_fullscreen_text_localized() -> void:
	var dlg = _make_dialog()
	assert_eq(dlg._fullscreen_check.text, tr("SETTINGS_FULLSCREEN"))
	dlg._en_btn.pressed.emit()
	assert_eq(dlg._fullscreen_check.text, tr("SETTINGS_FULLSCREEN"),
		"切语言后全屏开关文案应实时刷新")

# ---- 界面缩放档 ---------------------------------------------------------

func test_dialog_has_ui_scale_option() -> void:
	var dlg = _make_dialog()
	assert_not_null(dlg._ui_scale_option, "对话框应有界面缩放下拉")
	assert_gt(dlg._ui_scale_option.item_count, 1, "缩放下拉应有自动+若干档")

func test_selecting_ui_scale_writes_preferences() -> void:
	var dlg = _make_dialog()
	# 找到映射为 1.5 的档并选中。
	var idx: int = dlg._UI_SCALE_VALUES.find(1.5)
	assert_gt(idx, 0, "缩放档应含 150%")
	dlg._ui_scale_option.item_selected.emit(idx)
	assert_almost_eq(Preferences.ui_scale, 1.5, 0.0001, "选 150% 应写回 ui_scale")
	# 第 0 档 = 自动 → ui_scale 归 0。
	dlg._ui_scale_option.item_selected.emit(0)
	assert_eq(Preferences.ui_scale, 0.0, "选自动应把 ui_scale 归 0")

func test_ui_scale_label_localized() -> void:
	var dlg = _make_dialog()
	assert_eq(dlg._ui_scale_label.text, tr("SETTINGS_UI_SCALE"))
	dlg._en_btn.pressed.emit()
	assert_eq(dlg._ui_scale_label.text, tr("SETTINGS_UI_SCALE"),
		"切语言后界面缩放标签应实时刷新")

# ---- 语言切换 -----------------------------------------------------------

func test_current_locale_button_disabled() -> void:
	var dlg = _make_dialog()
	# locale 钉在 zh_CN → 中文按钮置灰 (选中态), English 可点。
	assert_true(dlg._zh_btn.disabled, "当前语言 (中文) 按钮应置灰")
	assert_false(dlg._en_btn.disabled, "非当前语言 (English) 按钮应可点")

func test_clicking_english_switches_locale() -> void:
	var dlg = _make_dialog()
	dlg._en_btn.pressed.emit()
	assert_eq(Preferences.locale, "en", "点 English 应通过 Preferences 切到 en")
	assert_eq(TranslationServer.get_locale(), "en", "TranslationServer 应同步到 en")
	# 切换后置灰态翻转。
	assert_true(dlg._en_btn.disabled, "切到 en 后 English 按钮置灰")
	assert_false(dlg._zh_btn.disabled, "切到 en 后中文按钮恢复可点")

func test_locale_change_refreshes_dialog_text() -> void:
	var dlg = _make_dialog()
	dlg._en_btn.pressed.emit()
	# 对话框订阅 locale_changed, title 应实时跟随到 en 文案。
	assert_eq(dlg.title, tr("SETTINGS_TITLE"),
		"切语言后对话框 title 应实时刷新")

# ---- 自动存档 -----------------------------------------------------------

func test_autosave_check_reflects_turn_manager() -> void:
	TurnManager.autosave_enabled = true
	var dlg = _make_dialog()
	assert_true(dlg._autosave_check.button_pressed,
		"开关初值应读 TurnManager.autosave_enabled")

func test_toggling_autosave_writes_turn_manager() -> void:
	var dlg = _make_dialog()
	dlg._autosave_check.toggled.emit(false)
	assert_false(TurnManager.autosave_enabled, "关掉开关应写回 TurnManager")
	dlg._autosave_check.toggled.emit(true)
	assert_true(TurnManager.autosave_enabled, "打开开关应写回 TurnManager")

# ---- 返回主菜单 (仅游戏内) -----------------------------------------------
# 起始页与游戏内共用此对话框, allow_return_to_menu 控制「返回主菜单」按钮可见性:
# 起始页不显示 (已在菜单), 游戏内顶栏置 true。点击先弹确认框, 确认才 emit
# return_to_menu_requested (真正的存档+切场景由 main.gd 处理, §11.0)。

func test_return_button_hidden_by_default() -> void:
	var dlg = _make_dialog()
	dlg.open()
	assert_not_null(dlg._return_btn, "对话框应有返回主菜单按钮")
	# 整段 (分隔线 + 按钮) 由 _return_box 控制显隐, 按钮自身 visible 恒 true。
	assert_false(dlg._return_box.visible,
		"allow_return_to_menu 默认 false (起始页), 返回主菜单区应隐藏")

func test_return_button_visible_when_allowed() -> void:
	var dlg = _make_dialog()
	dlg.allow_return_to_menu = true
	dlg.open()
	assert_true(dlg._return_box.visible,
		"allow_return_to_menu=true (游戏内) 时返回主菜单区应显示")

func test_clicking_return_pops_confirm() -> void:
	var dlg = _make_dialog()
	dlg.allow_return_to_menu = true
	dlg.open()
	dlg._return_btn.pressed.emit()
	assert_not_null(dlg._confirm_dialog,
		"点返回主菜单应先弹确认框, 而非直接退出")

func test_confirming_return_emits_signal() -> void:
	var dlg = _make_dialog()
	dlg.allow_return_to_menu = true
	dlg.open()
	watch_signals(dlg)
	dlg._return_btn.pressed.emit()
	# 在确认框点「返回」才真正发信号。
	dlg._confirm_dialog.confirmed.emit()
	assert_signal_emitted(dlg, "return_to_menu_requested",
		"确认返回主菜单后应 emit return_to_menu_requested")

func test_return_button_text_localized() -> void:
	var dlg = _make_dialog()
	assert_eq(dlg._return_btn.text, tr("SETTINGS_RETURN_TO_MENU"))
	dlg._en_btn.pressed.emit()
	assert_eq(dlg._return_btn.text, tr("SETTINGS_RETURN_TO_MENU"),
		"切语言后返回主菜单按钮文案应实时刷新")
