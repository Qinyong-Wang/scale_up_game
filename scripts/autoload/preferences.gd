extends Node

## Preferences — 用户偏好持久化单例。Per design/国际化设计.md §11。
##
## 独立于游戏存档: `Save` 管游戏状态 (per slot), `Preferences` 管跨存档的
## 玩家偏好 (UI 语言 + 背景音乐开关)。落盘到 user://preferences.cfg。
##
## 语言切换统一走 set_locale(): 改 TranslationServer + 写盘 +
## EventBus.locale_changed 广播, 让 main.gd 实时重渲染 (§11.2)。
##
## 背景音乐开关 music_enabled 只有 MusicPlayer 一个消费者, 故 set_music_enabled
## 只持久化、不广播 (见 design/音频系统设计.md §4)。

const CONFIG_PATH := "user://preferences.cfg"
const DEFAULT_LOCALE := "zh_CN"
const SECTION := "i18n"
const AUDIO_SECTION := "audio"
const DISPLAY_SECTION := "display"
const TUTORIAL_SECTION := "tutorial"
const DEFAULT_MUSIC_ENABLED := true
const DEFAULT_MUSIC_VOLUME := 0.5    ## 线性 0..1, ≈ -6 dB (见 design/音频系统设计.md §3)。
const DEFAULT_SFX_ENABLED := true
const DEFAULT_FULLSCREEN := false
const DEFAULT_UI_SCALE := 0.0        ## 0 = 自动 (按显示器高度); >0 = 手动档 (见 UI视觉系统设计.md §9bis)。
const DEFAULT_SKIP_INTRO := false    ## 新手引导「不再显示」开关 (见 教程与帮助系统设计.md §1)。

## 当前 UI 语言 (Godot locale code, e.g. "zh_CN" / "en")。
var locale: String = DEFAULT_LOCALE

## 背景音乐总开关 (MusicPlayer 据此起 / 停)。
var music_enabled: bool = DEFAULT_MUSIC_ENABLED

## 背景音乐线性音量 (0..1); MusicPlayer 据此算播放 dB。
var music_volume: float = DEFAULT_MUSIC_VOLUME

## 界面音效开关 (SfxPlayer 据此播放按钮 click)。
var sfx_enabled: bool = DEFAULT_SFX_ENABLED

## 全屏开关 (UITheme.apply_window_mode 据此切 DisplayServer 窗口模式)。
var fullscreen: bool = DEFAULT_FULLSCREEN

## 界面缩放档 (0 = 自动按显示器高度; >0 = 手动倍率)。
var ui_scale: float = DEFAULT_UI_SCALE

## 新游戏开局新手引导「不再显示」开关 (TutorialDialog 勾选后由 main 写回)。
var skip_intro: bool = DEFAULT_SKIP_INTRO

## 落盘路径; 测试可重定向到临时文件以保持 hermetic。
var _config_path: String = CONFIG_PATH

func _ready() -> void:
	_load()
	# 测试运行下不自动套用磁盘 locale, 避免污染各测试的 locale 断言。
	if not _is_test_run():
		_apply_locale()

## 切换 UI 语言。locale 未变且 TranslationServer 已一致时早退, 不重复刷。
func set_locale(loc: String) -> void:
	if loc == locale and TranslationServer.get_locale() == loc:
		return
	locale = loc
	TranslationServer.set_locale(loc)
	_save()
	Log.info(&"prefs", "set_locale", {locale = loc})
	EventBus.locale_changed.emit(loc)

func _apply_locale() -> void:
	if locale != "":
		TranslationServer.set_locale(locale)

## 切背景音乐开关。值未变早退; 变了仅持久化 (无广播, 单消费者 MusicPlayer)。
func set_music_enabled(enabled: bool) -> void:
	if enabled == music_enabled:
		return
	music_enabled = enabled
	_save()
	Log.info(&"prefs", "set_music_enabled", {enabled = enabled})

## 设背景音乐音量 (clamp 到 0..1)。值未变早退; 变了仅持久化。
func set_music_volume(v: float) -> void:
	var clamped: float = clampf(v, 0.0, 1.0)
	if is_equal_approx(clamped, music_volume):
		return
	music_volume = clamped
	_save()
	Log.info(&"prefs", "set_music_volume", {volume = clamped})

## 切界面音效开关。值未变早退; 变了仅持久化 (无广播, 单消费者 SfxPlayer)。
func set_sfx_enabled(enabled: bool) -> void:
	if enabled == sfx_enabled:
		return
	sfx_enabled = enabled
	_save()
	Log.info(&"prefs", "set_sfx_enabled", {enabled = enabled})

## 切全屏开关。值未变早退; 变了仅持久化 (窗口模式应用由 UITheme 负责)。
func set_fullscreen(on: bool) -> void:
	if on == fullscreen:
		return
	fullscreen = on
	_save()
	Log.info(&"prefs", "set_fullscreen", {fullscreen = on})

## 设界面缩放档 (0 = 自动)。值未变早退; 变了仅持久化 (应用由 UITheme 负责)。
func set_ui_scale(v: float) -> void:
	var clamped: float = maxf(v, 0.0)
	if is_equal_approx(clamped, ui_scale):
		return
	ui_scale = clamped
	_save()
	Log.info(&"prefs", "set_ui_scale", {ui_scale = clamped})

## 切新手引导「不再显示」开关。值未变早退; 变了仅持久化 (无消费者广播)。
func set_skip_intro(on: bool) -> void:
	if on == skip_intro:
		return
	skip_intro = on
	_save()
	Log.info(&"prefs", "set_skip_intro", {skip_intro = on})

# ─── 持久化 ───────────────────────────────────────────────────

func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(_config_path) == OK:
		locale = String(cfg.get_value(SECTION, "locale", DEFAULT_LOCALE))
		music_enabled = bool(cfg.get_value(AUDIO_SECTION, "music_enabled", DEFAULT_MUSIC_ENABLED))
		music_volume = float(cfg.get_value(AUDIO_SECTION, "music_volume", DEFAULT_MUSIC_VOLUME))
		sfx_enabled = bool(cfg.get_value(AUDIO_SECTION, "sfx_enabled", DEFAULT_SFX_ENABLED))
		fullscreen = bool(cfg.get_value(DISPLAY_SECTION, "fullscreen", DEFAULT_FULLSCREEN))
		ui_scale = float(cfg.get_value(DISPLAY_SECTION, "ui_scale", DEFAULT_UI_SCALE))
		skip_intro = bool(cfg.get_value(TUTORIAL_SECTION, "skip_intro", DEFAULT_SKIP_INTRO))

func _save() -> void:
	# 先 load 再 set, 不全量覆盖 — 保留其它 section 的偏好。
	var cfg := ConfigFile.new()
	cfg.load(_config_path)  # 文件不存在时 err 忽略, 继续写新文件
	cfg.set_value(SECTION, "locale", locale)
	cfg.set_value(AUDIO_SECTION, "music_enabled", music_enabled)
	cfg.set_value(AUDIO_SECTION, "music_volume", music_volume)
	cfg.set_value(AUDIO_SECTION, "sfx_enabled", sfx_enabled)
	cfg.set_value(DISPLAY_SECTION, "fullscreen", fullscreen)
	cfg.set_value(DISPLAY_SECTION, "ui_scale", ui_scale)
	cfg.set_value(TUTORIAL_SECTION, "skip_intro", skip_intro)
	var err := cfg.save(_config_path)
	if err != OK:
		Log.warn(&"prefs", "save failed", {err = err, path = _config_path})

func _is_test_run() -> bool:
	for arg in OS.get_cmdline_args():
		if arg.begins_with("-gtest") or arg.begins_with("-gdir") \
				or arg == "--test" or arg.find("gut_cmdln.gd") != -1:
			return true
	return false
