extends GutTest

## MusicPlayer 单例契约测试。对应 design/音频系统设计.md §6。
##
## 不依赖真实音频设备: 重点测 enabled↔Preferences 往返 + 歌单下标推进逻辑。
## 起播只在曲目资源存在时校验 stream 赋值; 不断言 is_playing (headless 哑音频驱动
## 易 flaky)。改 Preferences 是全局副作用 → before/after_each 重定向 cfg 到临时文件
## 并恢复 music_enabled, 保持 hermetic。

const MusicPlayerScript := preload("res://scripts/autoload/music_player.gd")
const TEST_CONFIG_PATH := "user://test_music_prefs.cfg"

var _saved_music_enabled: bool
var _saved_music_volume: float
var _saved_config_path: String

func before_each() -> void:
	_saved_music_enabled = Preferences.music_enabled
	_saved_music_volume = Preferences.music_volume
	_saved_config_path = Preferences._config_path
	Preferences._config_path = TEST_CONFIG_PATH
	_remove_test_config()

func after_each() -> void:
	Preferences._config_path = _saved_config_path
	Preferences.music_enabled = _saved_music_enabled
	Preferences.music_volume = _saved_music_volume
	_remove_test_config()

func _remove_test_config() -> void:
	if FileAccess.file_exists(TEST_CONFIG_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_CONFIG_PATH))

func _make_player():
	var mp = MusicPlayerScript.new()
	add_child_autofree(mp)
	return mp

# ---- 结构 ---------------------------------------------------------------

func test_has_audio_stream_player() -> void:
	var mp = _make_player()
	assert_not_null(mp._player, "应内建一个 AudioStreamPlayer")
	assert_true(mp._player is AudioStreamPlayer, "_player 应为 AudioStreamPlayer")

func test_track_list_nonempty() -> void:
	var mp = _make_player()
	assert_gt(mp.TRACKS.size(), 0, "应至少有一首曲目")

# ---- enabled ↔ Preferences ----------------------------------------------

func test_is_enabled_reflects_preferences() -> void:
	var mp = _make_player()
	Preferences.music_enabled = true
	assert_true(mp.is_enabled(), "is_enabled 应跟随 Preferences.music_enabled")
	Preferences.music_enabled = false
	assert_false(mp.is_enabled())

func test_set_enabled_writes_preferences() -> void:
	var mp = _make_player()
	mp.set_enabled(false)
	assert_false(Preferences.music_enabled, "关开关应写回 Preferences")
	mp.set_enabled(true)
	assert_true(Preferences.music_enabled, "开开关应写回 Preferences")

func test_set_enabled_false_stops_playback() -> void:
	var mp = _make_player()
	mp.set_enabled(true)
	mp.set_enabled(false)
	# 测试运行下 _use_fades()=false → 同步 stop, playing 立即为 false。
	assert_false(mp._player.playing, "关掉背景音乐后不应在播放")

# ---- music_volume ↔ Preferences -----------------------------------------
# 音量与开关正交: 开关管起/停, 音量管响度 (design/音频系统设计.md §3+§4)。

func test_get_volume_reflects_preferences() -> void:
	var mp = _make_player()
	Preferences.music_volume = 0.42
	assert_almost_eq(mp.get_volume(), 0.42, 0.0001,
		"get_volume 应跟随 Preferences.music_volume")

func test_set_volume_writes_preferences() -> void:
	var mp = _make_player()
	mp.set_volume(0.25)
	assert_almost_eq(Preferences.music_volume, 0.25, 0.0001,
		"set_volume 应写回 Preferences")

func test_set_volume_clamps_to_unit_range() -> void:
	var mp = _make_player()
	mp.set_volume(3.0)
	assert_almost_eq(mp.get_volume(), 1.0, 0.0001, "音量上限 1.0")
	mp.set_volume(-1.0)
	assert_almost_eq(mp.get_volume(), 0.0, 0.0001, "音量下限 0.0")

func test_target_db_tracks_volume_monotonically() -> void:
	var mp = _make_player()
	Preferences.music_volume = 1.0
	var loud := mp._target_db()
	Preferences.music_volume = 0.3
	var quiet := mp._target_db()
	assert_gt(loud, quiet, "音量大时目标 dB 应更高 (更响)")
	# 满档不超过 MAX_VOLUME_DB; 任何档不低于 SILENT_DB。
	assert_true(loud <= mp.MAX_VOLUME_DB + 0.001, "满档不应超过 MAX_VOLUME_DB")
	assert_true(quiet >= mp.SILENT_DB - 0.001, "任何档不应低于 SILENT_DB")

func test_target_db_zero_volume_is_silent() -> void:
	var mp = _make_player()
	Preferences.music_volume = 0.0
	assert_almost_eq(mp._target_db(), mp.SILENT_DB, 0.001,
		"音量 0 应回静音 dB")

# ---- 渐入渐出 -----------------------------------------------------------

func test_fade_to_creates_volume_tween() -> void:
	var mp = _make_player()
	mp._fade_to(mp.VOLUME_DB)
	assert_not_null(mp._fade_tween, "_fade_to 应创建音量渐变 Tween")
	assert_true(mp._fade_tween.is_valid(), "渐变 Tween 应有效")

# ---- 歌单循环 -----------------------------------------------------------

func test_track_finished_advances_index() -> void:
	var mp = _make_player()
	mp._index = 0
	mp._on_track_finished()
	assert_eq(mp._index, 1 % mp.TRACKS.size(), "曲目结束应推进到下一首")

func test_track_index_wraps() -> void:
	var mp = _make_player()
	mp._index = mp.TRACKS.size() - 1
	mp._on_track_finished()
	assert_eq(mp._index, 0, "末尾曲目结束后应回头第一首 (歌单循环)")

# ---- 起播赋流 (曲目已导入时) --------------------------------------------

func test_play_music_assigns_stream_when_track_exists() -> void:
	var mp = _make_player()
	if mp.TRACKS.is_empty() or not ResourceLoader.exists(mp.TRACKS[0]):
		pass_test("曲目资源未导入, 跳过赋流校验")
		return
	mp._index = 0
	mp.play_music()
	assert_not_null(mp._player.stream, "起播应给 AudioStreamPlayer 赋上曲目流")
