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
