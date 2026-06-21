extends GutTest

## HonorDialog 测试: 名(标题)/描述/flavor 渲染; flavor 空时隐藏。
## dialog 不读 GameState; refresh({name, description, flavor}) 接已翻译串。Per design §8.1。

const HonorDialog := preload("res://scenes/ui/honor_dialog/honor_dialog.gd")

var _dlg

func before_each() -> void:
	_dlg = HonorDialog.new()
	add_child_autofree(_dlg)

func test_shows_name_description_flavor() -> void:
	_dlg.refresh({name = "登顶总榜", description = "力压所有对手", flavor = "深夜的微光"})
	assert_eq(_dlg.get_title_for_test(), "登顶总榜")
	assert_eq(_dlg.get_description_text_for_test(), "力压所有对手")
	assert_eq(_dlg.get_flavor_text_for_test(), "深夜的微光")

func test_empty_flavor_ok() -> void:
	_dlg.refresh({name = "X", description = "Y", flavor = ""})
	assert_eq(_dlg.get_flavor_text_for_test(), "")

func test_answer_box_shows_big_centered_42() -> void:
	_dlg.refresh({
		name = "终极答案",
		description = "捐建太空数据中心，算出宇宙、生命与万物的终极答案——42。",
		flavor = "你曾以为终点是利润。",
		answer = "42",
	})
	assert_true(_dlg.has_method(&"get_answer_text_for_test"), "HonorDialog 应暴露 answer 测试接口")
	if not _dlg.has_method(&"get_answer_text_for_test"):
		return
	assert_eq(_dlg.get_answer_text_for_test(), "42")
	assert_true(_dlg.is_answer_visible_for_test())
	assert_eq(_dlg.get_answer_alignment_for_test(), HORIZONTAL_ALIGNMENT_CENTER)
	assert_gte(_dlg.get_answer_font_size_for_test(), 72,
			"打开答案盒时 42 必须是 dialog 中央的大号主视觉")
