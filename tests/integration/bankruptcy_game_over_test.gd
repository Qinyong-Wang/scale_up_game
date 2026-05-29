extends GutTest

## 破产终局 + 资金为负提示的端到端契约。Per design/经济系统设计.md §4.2。
##
## 约定:
##   - 资金为负时, 概览「下一步」提示绝不显示"运营顺畅", 而是给削减赤字的提示;
##     连续为负跨过预警阈值后升级为"本局将结束"。
##   - bankruptcy_warning 跨过预警阈值 (8) 弹一次预警弹窗。
##   - bankruptcy_triggered 弹 Game Over 弹窗; 确认后删 autosave (死局不可"继续")。
##   - 测试运行下 (_is_test_run) 跳过真正切场景, 只验证弹窗与存档副作用。

const Main := preload("res://scenes/main/main.gd")
const TEST_SAVE_DIR := "user://test_saves_game_over"

var _hud
var _saved_dir: String
var _saved_locale: String

func before_each() -> void:
	_saved_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("zh_CN")
	_saved_dir = Save.save_dir
	Save.save_dir = TEST_SAVE_DIR
	_clear_test_saves()
	GameState.reset()
	_hud = Main.new()
	add_child_autofree(_hud)
	await get_tree().process_frame

func after_each() -> void:
	_clear_test_saves()
	Save.save_dir = _saved_dir
	TranslationServer.set_locale(_saved_locale)

func _autosave_path() -> String:
	return "%s/%s.json" % [Save.save_dir, String(Save.AUTOSAVE_SLOT)]

func _clear_test_saves() -> void:
	var p := _autosave_path()
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(p)

func _find_dialog_by_title(title: String) -> AcceptDialog:
	for c in _hud.get_children():
		if c is AcceptDialog and c.title == title:
			return c
	return null

# ─── 资金为负的下一步提示 (问题2) ────────────────────────────

func test_negative_cash_hint_replaces_smooth() -> void:
	GameState.cash = -1
	GameState.bankruptcy_streak = 2
	var hints: Array = _hud._build_next_step_hints()
	assert_true(hints.has(tr("OV_HINT_CASH_NEGATIVE")),
			"资金为负应给出削减赤字的提示")
	assert_false(hints.has(tr("OV_HINT_SMOOTH")),
			"资金为负时绝不能显示'运营顺畅'")

func test_critical_hint_at_warn_streak() -> void:
	GameState.cash = -1
	GameState.bankruptcy_streak = EconomySystem.BANKRUPTCY_WARN_STREAK
	var hints: Array = _hud._build_next_step_hints()
	var expected: String = tr("OV_HINT_BANKRUPTCY_CRITICAL") % [
		GameState.bankruptcy_streak, EconomySystem.BANKRUPTCY_STREAK_LIMIT]
	assert_true(hints.has(expected),
			"连续为负跨过预警阈值应升级为'本局将结束'提示")
	assert_false(hints.has(tr("OV_HINT_SMOOTH")), "不能落到'运营顺畅'")

# ─── 预警弹窗 ────────────────────────────────────────────────

func test_warning_dialog_pops_at_warn_streak() -> void:
	EventBus.bankruptcy_warning.emit(&"cash_negative",
			EconomySystem.BANKRUPTCY_WARN_STREAK, EconomySystem.BANKRUPTCY_STREAK_LIMIT)
	await get_tree().process_frame
	assert_not_null(_find_dialog_by_title(tr("BANKRUPTCY_WARN_TITLE")),
			"跨过预警阈值应弹破产预警弹窗")

func test_no_warning_dialog_below_warn_streak() -> void:
	EventBus.bankruptcy_warning.emit(&"cash_negative", 3,
			EconomySystem.BANKRUPTCY_STREAK_LIMIT)
	await get_tree().process_frame
	assert_null(_find_dialog_by_title(tr("BANKRUPTCY_WARN_TITLE")),
			"轻度赤字 (streak<8) 不应弹预警弹窗")

# ─── Game Over 终局 ──────────────────────────────────────────

func test_bankruptcy_triggered_shows_game_over_dialog() -> void:
	EventBus.bankruptcy_triggered.emit(&"cash_negative_too_long")
	await get_tree().process_frame
	assert_not_null(_find_dialog_by_title(tr("GAMEOVER_TITLE")),
			"破产触发应弹 Game Over 弹窗")

func test_game_over_dialog_shown_only_once() -> void:
	EventBus.bankruptcy_triggered.emit(&"cash_too_deep")
	EventBus.bankruptcy_triggered.emit(&"cash_too_deep")
	await get_tree().process_frame
	var count: int = 0
	for c in _hud.get_children():
		if c is AcceptDialog and c.title == tr("GAMEOVER_TITLE"):
			count += 1
	assert_eq(count, 1, "Game Over 弹窗只能弹一次 (深度线可能每周重复触发)")

func test_game_over_confirm_deletes_autosave() -> void:
	# 先写一份 autosave (模拟回合推进时落下的存档)。
	GameState.turn = 9
	Save.write(Save.AUTOSAVE_SLOT)
	assert_true(FileAccess.file_exists(_autosave_path()), "前置: autosave 应存在")
	EventBus.bankruptcy_triggered.emit(&"cash_negative_too_long")
	await get_tree().process_frame
	var dlg := _find_dialog_by_title(tr("GAMEOVER_TITLE"))
	assert_not_null(dlg, "应有 Game Over 弹窗")
	dlg.confirmed.emit()
	assert_false(FileAccess.file_exists(_autosave_path()),
			"确认 Game Over 后应删除 autosave, 死局不可'继续'")
