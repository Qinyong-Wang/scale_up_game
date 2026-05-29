extends GutTest

## 游戏内「返回主菜单」端到端契约。Per design/出身系统设计.md §1 + 国际化设计.md §11.0。
##
## 约定:
##   - 游戏内顶栏「设置」弹窗的 allow_return_to_menu = true, 暴露「返回主菜单」入口。
##   - 玩家确认返回时 (SettingsDialog emit return_to_menu_requested), main.gd 先把
##     当前进度写入 autosave slot, 再切回起始页。
##   - 测试运行下 (_is_test_run) 跳过真正切场景, 但存档照写, 所以这里只验证存档落地。

const Main := preload("res://scenes/main/main.gd")
const SettingsDialog := preload("res://scenes/ui/settings_dialog/settings_dialog.gd")
const TEST_SAVE_DIR := "user://test_saves_return_menu"

var _hud
var _saved_dir: String

func before_each() -> void:
	TranslationServer.set_locale("zh_CN")
	_saved_dir = Save.save_dir
	Save.save_dir = TEST_SAVE_DIR
	_clear_test_saves()
	GameState.reset()
	_seed_eval_lead()
	_hud = Main.new()
	add_child_autofree(_hud)
	await get_tree().process_frame

func after_each() -> void:
	_clear_test_saves()
	Save.save_dir = _saved_dir

func _seed_eval_lead() -> void:
	var l := Lead.new()
	l.id = &"lead_eval_zero_return"
	l.specialty = &"eval_lead"
	l.level = &"C"
	l.ability = 0.0
	l.signing_fee = 0
	l.weekly_salary = 0
	GameState.leads.append(l)

func _autosave_path() -> String:
	return "%s/%s.json" % [Save.save_dir, String(Save.AUTOSAVE_SLOT)]

func _clear_test_saves() -> void:
	var p := _autosave_path()
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(p)

func _find_settings_dialog() -> SettingsDialog:
	for c in _hud.get_children():
		if c is SettingsDialog:
			return c
	return null

# ─── 顶栏设置弹窗开放返回入口 ────────────────────────────────

func test_ingame_settings_allows_return_to_menu() -> void:
	_hud._on_open_settings_dialog()
	var dlg := _find_settings_dialog()
	assert_not_null(dlg, "顶栏设置按钮应打开 SettingsDialog")
	assert_true(dlg.allow_return_to_menu,
		"游戏内打开的设置弹窗应允许返回主菜单")

# ─── 确认返回 → 写 autosave (不真正切场景) ───────────────────

func test_return_to_menu_writes_autosave() -> void:
	GameState.turn = 7
	assert_false(FileAccess.file_exists(_autosave_path()),
		"前置: autosave 应不存在")
	_hud._on_open_settings_dialog()
	var dlg := _find_settings_dialog()
	# 模拟玩家在确认框点「返回」: 对话框对外只发这一个信号。
	dlg.return_to_menu_requested.emit()
	assert_true(FileAccess.file_exists(_autosave_path()),
		"确认返回主菜单后应把当前进度写入 autosave")
