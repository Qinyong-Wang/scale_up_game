extends GutTest

## 终局 42 提示: 宇宙模拟完成后 main 收到 universe_answer_revealed,
## 弹窗提示玩家去办公室，并在确认后切到办公室让玩家亲手打开答案盒。
## Per design/宇宙模拟工程设计.md §8 + 办公室与收藏系统设计.md §8.1。

const Main := preload("res://scenes/main/main.gd")

var _hud
var _saved_locale: String

func before_each() -> void:
	_saved_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("zh_CN")
	GameState.reset()
	_hud = Main.new()
	add_child_autofree(_hud)
	await get_tree().process_frame

func after_each() -> void:
	TranslationServer.set_locale(_saved_locale)
	GameState.reset()

func _find_dialog_by_title(title: String) -> AcceptDialog:
	for c in _hud.get_children():
		if c is AcceptDialog and c.title == title:
			return c
	return null

func test_universe_answer_signal_shows_office_prompt() -> void:
	EventBus.universe_answer_revealed.emit()
	await get_tree().process_frame
	var dlg := _find_dialog_by_title(tr("SIM_REVEAL_TITLE"))
	assert_not_null(dlg, "终局完成应弹出提示玩家查看答案盒的弹窗")
	assert_eq(dlg.dialog_text, tr("SIM_REVEAL_BODY"))
	assert_eq(dlg.get_ok_button().text, tr("SIM_REVEAL_OK"))

func test_prompt_confirm_switches_to_office() -> void:
	EventBus.universe_answer_revealed.emit()
	await get_tree().process_frame
	var dlg := _find_dialog_by_title(tr("SIM_REVEAL_TITLE"))
	assert_not_null(dlg)
	dlg.confirmed.emit()
	await get_tree().process_frame
	assert_eq(_hud._active_nav, &"office", "确认提示后应切到办公室")
	assert_not_null(_hud._office_view, "办公室视图应已渲染, 玩家能点击答案盒")

func test_universe_answer_prompt_shown_once() -> void:
	EventBus.universe_answer_revealed.emit()
	EventBus.universe_answer_revealed.emit()
	await get_tree().process_frame
	var count: int = 0
	for c in _hud.get_children():
		if c is AcceptDialog and c.title == tr("SIM_REVEAL_TITLE"):
			count += 1
	assert_eq(count, 1, "终局提示只应弹一次")
