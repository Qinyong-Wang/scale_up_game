extends GutTest

## Preferences 单例契约测试。对应 design/国际化设计.md §11 + §7。
##
## 覆盖:
##   - set_locale 改 TranslationServer locale 并 emit EventBus.locale_changed。
##   - locale 选择持久化往返 (写盘 → 重新 _load 读回)。
##   - locale 未变时不重复 emit。
##   - 写盘不抹掉其它无关偏好。

const TEST_CONFIG_PATH := "user://test_preferences.cfg"

var _saved_locale: String = ""
var _saved_config_path: String = ""
var _saved_music_enabled: bool = true
var _saved_music_volume: float = 0.5
var _saved_sfx_enabled: bool = true
var _saved_fullscreen: bool = false
var _saved_ui_scale: float = 0.0
var _saved_skip_intro: bool = false

func before_each() -> void:
	_saved_locale = TranslationServer.get_locale()
	_saved_config_path = Preferences._config_path
	_saved_music_enabled = Preferences.music_enabled
	_saved_music_volume = Preferences.music_volume
	_saved_sfx_enabled = Preferences.sfx_enabled
	_saved_fullscreen = Preferences.fullscreen
	_saved_ui_scale = Preferences.ui_scale
	_saved_skip_intro = Preferences.skip_intro
	Preferences._config_path = TEST_CONFIG_PATH
	_remove_test_config()
	# 配置已删 → 把内存偏好钉回默认基线, 否则 set_*(同值) 早退不写盘, 往返断言依赖
	# 前一个测试残留 (跨测试泄漏导致顺序相关 flaky)。
	Preferences.music_enabled = Preferences.DEFAULT_MUSIC_ENABLED
	Preferences.music_volume = Preferences.DEFAULT_MUSIC_VOLUME
	Preferences.sfx_enabled = Preferences.DEFAULT_SFX_ENABLED
	Preferences.fullscreen = Preferences.DEFAULT_FULLSCREEN
	Preferences.ui_scale = Preferences.DEFAULT_UI_SCALE
	Preferences.skip_intro = Preferences.DEFAULT_SKIP_INTRO

func after_each() -> void:
	Preferences._config_path = _saved_config_path
	Preferences.locale = _saved_locale
	Preferences.music_enabled = _saved_music_enabled
	Preferences.music_volume = _saved_music_volume
	Preferences.sfx_enabled = _saved_sfx_enabled
	Preferences.fullscreen = _saved_fullscreen
	Preferences.ui_scale = _saved_ui_scale
	Preferences.skip_intro = _saved_skip_intro
	# 恢复到测试基线 zh_CN (gut_cjk_font_hook 钉的值), 而不是 _saved_locale —
	# UI 文案接 tr() 后, 任何切 locale 的测试若泄漏 en, 下游 UI 测试会 flaky。
	TranslationServer.set_locale("zh_CN")
	_remove_test_config()

func _remove_test_config() -> void:
	if FileAccess.file_exists(TEST_CONFIG_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_CONFIG_PATH))

# ─── set_locale ───────────────────────────────────────────────

func test_set_locale_updates_translation_server() -> void:
	Preferences.set_locale("en")
	assert_eq(TranslationServer.get_locale(), "en",
		"set_locale 应把 TranslationServer 切到 en")

func test_set_locale_emits_locale_changed() -> void:
	TranslationServer.set_locale("zh_CN")
	Preferences.locale = "zh_CN"
	watch_signals(EventBus)
	Preferences.set_locale("en")
	assert_signal_emitted_with_parameters(EventBus, "locale_changed", ["en"])

func test_set_same_locale_does_not_reemit() -> void:
	Preferences.set_locale("en")
	watch_signals(EventBus)
	Preferences.set_locale("en")
	assert_signal_not_emitted(EventBus, "locale_changed",
		"locale 未变不应重复 emit")

# ─── 持久化往返 ───────────────────────────────────────────────

func test_locale_persists_round_trip() -> void:
	Preferences.set_locale("en")  # 写盘到 TEST_CONFIG_PATH
	# 模拟下次启动: 改掉内存值, 再从盘读回。
	Preferences.locale = "zh_CN"
	Preferences._load()
	assert_eq(Preferences.locale, "en", "保存的 locale 应从盘读回")

func test_save_does_not_clobber_other_keys() -> void:
	# 预置一个无关偏好, set_locale 后应仍在 (不全量覆盖 cfg)。
	var cfg := ConfigFile.new()
	cfg.set_value("misc", "foo", 42)
	cfg.save(TEST_CONFIG_PATH)
	Preferences.set_locale("en")
	var check := ConfigFile.new()
	check.load(TEST_CONFIG_PATH)
	assert_eq(check.get_value("misc", "foo", 0), 42,
		"set_locale 不应抹掉其它偏好")

# ─── music_enabled (背景音乐开关) ─────────────────────────────

func test_music_enabled_defaults_true_when_section_absent() -> void:
	# 配置文件存在但无 [audio] 段 (老存档 / 只设过语言) 时, 读回应回落默认 true。
	var cfg := ConfigFile.new()
	cfg.set_value("i18n", "locale", "zh_CN")
	cfg.save(TEST_CONFIG_PATH)
	Preferences.music_enabled = false
	Preferences._load()
	assert_true(Preferences.music_enabled, "无 [audio] 段时 music_enabled 应回落默认 true")

func test_set_music_enabled_persists_round_trip() -> void:
	Preferences.set_music_enabled(false)  # 写盘
	Preferences.music_enabled = true       # 模拟下次启动前改掉内存值
	Preferences._load()
	assert_false(Preferences.music_enabled, "保存的 music_enabled 应从盘读回")

func test_set_music_enabled_does_not_clobber_locale() -> void:
	Preferences.set_locale("en")          # locale 写进 [i18n]
	Preferences.set_music_enabled(false)  # music_enabled 写进 [audio]
	var check := ConfigFile.new()
	check.load(TEST_CONFIG_PATH)
	assert_eq(String(check.get_value("i18n", "locale", "")), "en",
		"set_music_enabled 不应抹掉 locale 偏好")

# ─── music_volume (背景音乐音量) ──────────────────────────────

func test_music_volume_defaults_when_section_absent() -> void:
	# 只设过语言的老配置, 读回 music_volume 应回落到默认 (非 0)。
	var cfg := ConfigFile.new()
	cfg.set_value("i18n", "locale", "zh_CN")
	cfg.save(TEST_CONFIG_PATH)
	Preferences.music_volume = -1.0
	Preferences._load()
	assert_eq(Preferences.music_volume, Preferences.DEFAULT_MUSIC_VOLUME,
		"无 [audio] music_volume 时应回落默认音量")

func test_set_music_volume_persists_round_trip() -> void:
	Preferences.set_music_volume(0.3)
	Preferences.music_volume = 1.0       # 模拟下次启动前改掉内存值
	Preferences._load()
	assert_almost_eq(Preferences.music_volume, 0.3, 0.0001,
		"保存的 music_volume 应从盘读回")

func test_set_music_volume_clamps_to_unit_range() -> void:
	Preferences.set_music_volume(5.0)
	assert_almost_eq(Preferences.music_volume, 1.0, 0.0001, "音量上限 1.0")
	Preferences.set_music_volume(-2.0)
	assert_almost_eq(Preferences.music_volume, 0.0, 0.0001, "音量下限 0.0")

# ─── sfx_enabled (界面音效开关) ──────────────────────────────

func test_sfx_enabled_defaults_true_when_absent() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("i18n", "locale", "zh_CN")
	cfg.save(TEST_CONFIG_PATH)
	Preferences.sfx_enabled = false
	Preferences._load()
	assert_true(Preferences.sfx_enabled, "无 [audio] sfx_enabled 时应回落默认 true")

func test_set_sfx_enabled_persists_round_trip() -> void:
	Preferences.set_sfx_enabled(false)
	Preferences.sfx_enabled = true
	Preferences._load()
	assert_false(Preferences.sfx_enabled, "保存的 sfx_enabled 应从盘读回")

func test_set_sfx_enabled_does_not_clobber_music_volume() -> void:
	Preferences.set_music_volume(0.35)
	Preferences.set_sfx_enabled(false)
	var check := ConfigFile.new()
	check.load(TEST_CONFIG_PATH)
	assert_almost_eq(float(check.get_value("audio", "music_volume", -1.0)), 0.35, 0.0001,
		"set_sfx_enabled 不应抹掉 music_volume")

# ─── fullscreen + ui_scale (显示偏好, [display] 段) ───────────

func test_fullscreen_defaults_false_when_absent() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("i18n", "locale", "zh_CN")
	cfg.save(TEST_CONFIG_PATH)
	Preferences.fullscreen = true
	Preferences._load()
	assert_false(Preferences.fullscreen, "无 [display] 段时 fullscreen 应回落 false")

func test_set_fullscreen_persists_round_trip() -> void:
	Preferences.set_fullscreen(true)
	Preferences.fullscreen = false
	Preferences._load()
	assert_true(Preferences.fullscreen, "保存的 fullscreen 应从盘读回")

func test_ui_scale_defaults_auto_when_absent() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("i18n", "locale", "zh_CN")
	cfg.save(TEST_CONFIG_PATH)
	Preferences.ui_scale = 1.5
	Preferences._load()
	assert_eq(Preferences.ui_scale, 0.0, "无 [display] ui_scale 时应回落 0.0 (自动)")

func test_set_ui_scale_persists_round_trip() -> void:
	Preferences.set_ui_scale(1.5)
	Preferences.ui_scale = 0.0
	Preferences._load()
	assert_almost_eq(Preferences.ui_scale, 1.5, 0.0001, "保存的 ui_scale 应从盘读回")

func test_display_prefs_do_not_clobber_locale() -> void:
	Preferences.set_locale("en")
	Preferences.set_fullscreen(true)
	Preferences.set_ui_scale(2.0)
	var check := ConfigFile.new()
	check.load(TEST_CONFIG_PATH)
	assert_eq(String(check.get_value("i18n", "locale", "")), "en",
		"写显示偏好不应抹掉 locale")

# ─── skip_intro (新手引导「不再显示」, [tutorial] 段) ──────────

func test_skip_intro_defaults_false_when_absent() -> void:
	# 只设过语言的老配置, 读回 skip_intro 应回落 false (默认弹引导)。
	var cfg := ConfigFile.new()
	cfg.set_value("i18n", "locale", "zh_CN")
	cfg.save(TEST_CONFIG_PATH)
	Preferences.skip_intro = true
	Preferences._load()
	assert_false(Preferences.skip_intro, "无 [tutorial] 段时 skip_intro 应回落 false")

func test_set_skip_intro_persists_round_trip() -> void:
	Preferences.set_skip_intro(true)  # 写盘
	Preferences.skip_intro = false     # 模拟下次启动前改掉内存值
	Preferences._load()
	assert_true(Preferences.skip_intro, "保存的 skip_intro 应从盘读回")

func test_set_skip_intro_does_not_clobber_locale() -> void:
	Preferences.set_locale("en")
	Preferences.set_skip_intro(true)
	var check := ConfigFile.new()
	check.load(TEST_CONFIG_PATH)
	assert_eq(String(check.get_value("i18n", "locale", "")), "en",
		"set_skip_intro 不应抹掉 locale 偏好")
