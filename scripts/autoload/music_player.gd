extends Node

## MusicPlayer — 背景音乐播放器单例。Per design/音频系统设计.md。
##
## 持有一个 AudioStreamPlayer, 启动时打乱曲序后顺序循环播放纯乐器 BGM (23 首, 每首
## 约 3.5 分钟; 含电子科技 / 原声有机 / 磅礴混合三类): 单曲 finished → 切下一首,
## 末尾回头 (歌单循环)。
##
## 渐入渐出: 起播 / 续播时音量从 SILENT_DB 用 Tween 渐入到 VOLUME_DB; 停播 (关开关)
## 时渐出到 SILENT_DB 再 stop。曲目文件本身也烘焙了首尾淡化 (见生成工具), 故曲目切换
## 平滑。测试运行下跳过 Tween 即时起 / 停, 保持确定性。
##
## 开关状态由 Preferences.music_enabled 持久化。只有本单例一个消费者, 故设置对话框
## 直接调 set_enabled(), 不走 EventBus 广播。
##
## 曲目为 tools/generate_music.py 用 Vertex AI 离线生成的资产; 真实模型名只在该工具
## 里, 不进运行时 (化名规范)。

## 曲目清单 (顺序循环)。用显式路径而非运行时扫目录, 兼容导出包。
const TRACKS: Array[String] = [
	"res://assets/audio/music/bgm_04.mp3",
	"res://assets/audio/music/bgm_06.mp3",
	"res://assets/audio/music/bgm_09.mp3",
	"res://assets/audio/music/bgm_10.mp3",
	"res://assets/audio/music/bgm_13.mp3",
	"res://assets/audio/music/bgm_14.mp3",
	"res://assets/audio/music/bgm_15.mp3",
	"res://assets/audio/music/bgm_16.mp3",
	"res://assets/audio/music/bgm_17.mp3",
	"res://assets/audio/music/bgm_18.mp3",
	"res://assets/audio/music/bgm_19.mp3",
	"res://assets/audio/music/bgm_20.mp3",
	"res://assets/audio/music/bgm_21.mp3",
	"res://assets/audio/music/bgm_22.mp3",
	"res://assets/audio/music/bgm_23.mp3",
	"res://assets/audio/music/bgm_24.mp3",
	"res://assets/audio/music/bgm_25.mp3",
	"res://assets/audio/music/bgm_26.mp3",
	"res://assets/audio/music/bgm_27.mp3",
	"res://assets/audio/music/bgm_28.mp3",
	"res://assets/audio/music/bgm_29.mp3",
	"res://assets/audio/music/bgm_30.mp3",
	"res://assets/audio/music/bgm_31.mp3",
]

const VOLUME_DB := -8.0    ## 旧固定档, 仅留作参考; 实际播放走 _target_db()。
const MAX_VOLUME_DB := -2.0  ## 满档 (music_volume=1.0) 上限, 仍压一点不抢前景。
const SILENT_DB := -40.0   ## 淡化端点 (近静音)。
const FADE_SEC := 1.5      ## 渐入 / 渐出时长。

var _player: AudioStreamPlayer
var _index := 0
var _fade_tween: Tween
## 实际播放顺序 (TRACKS 的副本); 启动时打乱, 不每局都从同一首开始。
var _playlist: Array[String] = []

func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.volume_db = _target_db()
	_player.bus = &"Master"
	_player.finished.connect(_on_track_finished)
	add_child(_player)
	_playlist = TRACKS.duplicate()
	# 测试运行下保持原序 + 不自动起播, 保持 hermetic (镜像 Preferences._is_test_run)。
	if not _is_test_run():
		_playlist.shuffle()
		if Preferences.music_enabled:
			play_music()

## 背景音乐是否开启 (读 Preferences, 单一真相源)。
func is_enabled() -> bool:
	return Preferences.music_enabled

## 当前线性音量 (读 Preferences, 单一真相源)。
func get_volume() -> float:
	return Preferences.music_volume

## 开 / 关背景音乐: 持久化偏好 + 渐入起播 / 渐出停播。设置对话框的开关调这里。
func set_enabled(enabled: bool) -> void:
	Preferences.set_music_enabled(enabled)
	if enabled:
		play_music()
	else:
		stop_music()

## 设音乐音量 (0..1): 持久化偏好 + 在播时把音量调到新目标 dB。设置滑块调这里。
## 与开关正交 — 音量管响度, 不起 / 停播放 (见 design/音频系统设计.md §4)。
func set_volume(v: float) -> void:
	Preferences.set_music_volume(v)
	if _player == null or not _player.playing:
		return
	var target := _target_db()
	if _use_fades():
		_fade_to(target)
	else:
		_kill_fade()
		_player.volume_db = target

## 播放目标音量 (dB): 由线性 music_volume 换算, clamp 到 [SILENT_DB, MAX_VOLUME_DB]。
## music_volume≈0 视作静音。
func _target_db() -> float:
	var v: float = Preferences.music_volume
	if v <= 0.001:
		return SILENT_DB
	return clampf(linear_to_db(v), SILENT_DB, MAX_VOLUME_DB)

## 播放当前下标的曲目 (渐入)。曲目缺失 (未导入 / 路径错) 时静默早退, 不崩。
func play_music() -> void:
	var stream := _load_track(_index)
	if stream == null:
		return
	_player.stream = stream
	if _use_fades():
		_player.volume_db = SILENT_DB
		_player.play()
		_fade_to(_target_db())
	else:
		_player.volume_db = _target_db()
		_player.play()

## 停播 (渐出后 stop)。
func stop_music() -> void:
	if _player == null:
		return
	if _use_fades() and _player.playing:
		_fade_to(SILENT_DB, func(): _player.stop())
	else:
		_kill_fade()
		_player.stop()

## 歌单循环: 推进到下一首, 末尾回头; 仍开启则续播 (渐入)。
func _on_track_finished() -> void:
	if _playlist.is_empty():
		return
	_index = (_index + 1) % _playlist.size()
	if is_enabled():
		play_music()

## Tween 渐变 volume_db 到 target_db; 完成后可选回调 (用于渐出后 stop)。
func _fade_to(target_db: float, on_done := Callable()) -> void:
	_kill_fade()
	_fade_tween = create_tween()
	_fade_tween.tween_property(_player, "volume_db", target_db, FADE_SEC)
	if on_done.is_valid():
		_fade_tween.tween_callback(on_done)

func _kill_fade() -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = null

## 测试运行下关掉淡化, 让起 / 停同步发生 (Tween 需逐帧推进, 测试里不可靠)。
func _use_fades() -> bool:
	return not _is_test_run()

func _load_track(i: int) -> AudioStream:
	if i < 0 or i >= _playlist.size():
		return null
	var path := _playlist[i]
	if not ResourceLoader.exists(path):
		Log.warn(&"music", "track missing", {path = path})
		return null
	return load(path) as AudioStream

func _is_test_run() -> bool:
	for arg in OS.get_cmdline_args():
		if arg.begins_with("-gtest") or arg.begins_with("-gdir") \
				or arg == "--test" or arg.find("gut_cmdln.gd") != -1:
			return true
	return false
