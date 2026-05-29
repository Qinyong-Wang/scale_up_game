extends GutTest

## SfxPlayer 单例契约测试。对应 design/音频系统设计.md §4bis + §6。
##
## 不依赖真实音频设备: 只测 click stream 生成、按钮注册、开关写回与静音逻辑。

const SfxPlayerScript := preload("res://scripts/autoload/sfx_player.gd")
const TEST_CONFIG_PATH := "user://test_sfx_prefs.cfg"

var _saved_sfx_enabled: bool
var _saved_config_path: String

func before_each() -> void:
	_saved_sfx_enabled = Preferences.sfx_enabled
	_saved_config_path = Preferences._config_path
	Preferences._config_path = TEST_CONFIG_PATH
	Preferences.sfx_enabled = Preferences.DEFAULT_SFX_ENABLED
	_remove_test_config()

func after_each() -> void:
	Preferences._config_path = _saved_config_path
	Preferences.sfx_enabled = _saved_sfx_enabled
	_remove_test_config()

func _remove_test_config() -> void:
	if FileAccess.file_exists(TEST_CONFIG_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_CONFIG_PATH))

func _make_player():
	var sp = SfxPlayerScript.new()
	add_child_autofree(sp)
	return sp

func test_has_audio_stream_player_pool() -> void:
	var sp = _make_player()
	assert_gte(sp._players.size(), 1, "应至少内建一个 AudioStreamPlayer")
	assert_true(sp._players[0] is AudioStreamPlayer, "player pool 元素应为 AudioStreamPlayer")

func test_button_click_stream_is_generated() -> void:
	var sp = _make_player()
	assert_not_null(sp._button_click_stream, "应生成按钮 click AudioStreamWAV")
	assert_true(sp._button_click_stream is AudioStreamWAV)
	assert_gt(sp._button_click_stream.data.size(), 0, "click stream 应有 PCM 数据")

func test_is_enabled_reflects_preferences() -> void:
	var sp = _make_player()
	Preferences.sfx_enabled = true
	assert_true(sp.is_enabled())
	Preferences.sfx_enabled = false
	assert_false(sp.is_enabled())

func test_set_enabled_writes_preferences() -> void:
	var sp = _make_player()
	sp.set_enabled(false)
	assert_false(Preferences.sfx_enabled, "关界面音效应写回 Preferences")
	sp.set_enabled(true)
	assert_true(Preferences.sfx_enabled, "开界面音效应写回 Preferences")

func test_register_button_sets_cursor_and_click_plays_when_enabled() -> void:
	var sp = _make_player()
	Preferences.sfx_enabled = true
	var b := Button.new()
	add_child_autofree(b)
	sp.register_button(b)
	assert_eq(b.mouse_default_cursor_shape, Control.CURSOR_POINTING_HAND,
		"注册按钮后鼠标应显示手型")
	b.pressed.emit()
	assert_eq(sp._clicks_played_for_test, 1,
		"开关开启时 pressed 应播放一次 click")

func test_disabled_sfx_mutes_registered_button_click() -> void:
	var sp = _make_player()
	Preferences.sfx_enabled = false
	var b := Button.new()
	add_child_autofree(b)
	sp.register_button(b)
	b.pressed.emit()
	assert_eq(sp._clicks_played_for_test, 0,
		"界面音效关闭时 pressed 不应播放 click")

func test_button_tree_exit_disconnects_sfx_signals_for_reuse() -> void:
	var sp = _make_player()
	var b := Button.new()
	add_child_autofree(b)
	sp.register_button(b)
	var id := b.get_instance_id()

	assert_connected(b, sp, "pressed")
	assert_connected(b, sp, "button_down")
	assert_connected(b, sp, "button_up")
	assert_connected(b, sp, "mouse_exited")
	assert_connected(b, sp, "tree_exiting")

	sp._on_button_exiting(id)

	assert_false(sp._registered_buttons.has(id), "按钮退出后应清掉注册表")
	assert_not_connected(b, sp, "pressed")
	assert_not_connected(b, sp, "button_down")
	assert_not_connected(b, sp, "button_up")
	assert_not_connected(b, sp, "mouse_exited")
	assert_not_connected(b, sp, "tree_exiting")

	sp.register_button(b)
	assert_connected(b, sp, "pressed")
	assert_connected(b, sp, "button_down")
	assert_connected(b, sp, "button_up")
	assert_connected(b, sp, "mouse_exited")
	assert_connected(b, sp, "tree_exiting")
