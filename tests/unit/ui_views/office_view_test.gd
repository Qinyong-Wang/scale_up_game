extends GutTest

## OfficeView 第一人称房间测试: earned 奖章(form=medal)摆桌面、奖杯(form=trophy)摆茶几;
## 点电脑 → computer_pressed; 点奖章/奖杯 → honor_pressed(id)。
## 视图不读 GameState; refresh(data) 接 dict。Per design/办公室与收藏系统设计.md §8.1。

const OfficeViewScene := preload("res://scenes/ui/views/office/office_view.tscn")

var _view: Control

func before_each() -> void:
	GameState.reset()
	_view = OfficeViewScene.instantiate()
	add_child_autofree(_view)

func _honor(id: String, form: StringName, earned: bool) -> Dictionary:
	return {id = StringName(id), display_name = "荣誉", description = "描述",
			flavor = "故事", form = form, earned = earned}

func _data(trophies: Array) -> Dictionary:
	return {trophies = trophies}

# ---- 按 form 分桌面/茶几, 只摆 earned ---------------------------------

func test_medals_on_desk_trophies_on_table_by_form() -> void:
	_view.refresh(_data([
		_honor("m1", &"medal", true),
		_honor("t1", &"trophy", true),
		_honor("t2", &"trophy", true),
		_honor("locked", &"trophy", false),
	]))
	assert_eq(_view.get_desk_medal_count_for_test(), 1)
	assert_eq(_view.get_table_trophy_count_for_test(), 2)
	assert_eq(_view.get_honor_count_for_test(), 3)

func test_answer_box_has_dedicated_office_object() -> void:
	_view.size = Vector2(1280, 731)
	_view.refresh(_data([
		_honor("universe_answer", &"answer_box", true),
	]))
	assert_eq(_view.get_answer_box_count_for_test(), 1)
	assert_eq(_view.get_desk_medal_count_for_test(), 0)
	assert_eq(_view.get_table_trophy_count_for_test(), 0)
	var anchor: Vector2 = _view.get_honor_bottom_anchor_normalized_for_test(&"universe_answer")
	assert_gt(anchor.x, 0.42, "终极答案盒应落在近处桌面中央区域")
	assert_lt(anchor.x, 0.58, "终极答案盒不应混到远处茶几奖杯锚点")
	assert_gt(anchor.y, 0.82, "终极答案盒应摆在显示器下方的桌面上")
	assert_lt(anchor.y, 0.90, "终极答案盒不应落到桌面最前缘")

func test_no_honors_when_none_earned() -> void:
	_view.refresh(_data([_honor("t1", &"trophy", false)]))
	assert_eq(_view.get_honor_count_for_test(), 0)

func test_refresh_replaces_previous_honors() -> void:
	_view.refresh(_data([_honor("t1", &"trophy", true), _honor("t2", &"trophy", true)]))
	_view.refresh(_data([_honor("t1", &"trophy", true)]))
	assert_eq(_view.get_honor_count_for_test(), 1)

# ---- Computer entry visual contract -------------------------------------

func test_computer_hotspot_is_screen_sized_and_contains_dashboard_surface() -> void:
	_view.size = Vector2(1280, 731)
	var hotspot: Rect2 = _view.get_computer_hotspot_rect_for_test()
	var screen: Rect2 = _view.get_computer_screen_rect_for_test()
	var screen_end := screen.position + screen.size - Vector2.ONE
	assert_true(hotspot.has_point(screen.position))
	assert_true(hotspot.has_point(screen_end))
	assert_lt(hotspot.size.y / _view.size.y, 0.30)
	assert_lt(screen.size.y, hotspot.size.y)
	assert_gt(screen.size.y / hotspot.size.y, 0.80,
			"dashboard 应覆盖显示器大部分黑屏, 不应像上半块悬浮贴片")

func test_computer_hover_state_drives_visual_highlight() -> void:
	assert_false(_view.is_computer_hovered_for_test())
	_view.set_computer_hover_for_test(true)
	assert_true(_view.is_computer_hovered_for_test())

func test_table_trophy_anchor_lands_on_coffee_table_band() -> void:
	_view.size = Vector2(1280, 731)
	_view.refresh(_data([_honor("t1", &"trophy", true)]))
	var anchor: Vector2 = _view.get_honor_bottom_anchor_normalized_for_test(&"t1")
	assert_gt(anchor.y, 0.72, "茶几奖杯底部应落在远处茶几桌面带")
	assert_lt(anchor.y, 0.80, "茶几奖杯不能飘到地面或前景桌面")
	assert_lt(anchor.x, 0.30, "远处茶几在画面左侧, 奖杯不能偏到窗边空处之外")

func test_table_trophy_scale_respects_room_perspective() -> void:
	_view.size = Vector2(1280, 731)
	_view.refresh(_data([_honor("t1", &"trophy", true)]))
	var trophy_size: Vector2 = _view.get_honor_size_for_test(&"t1")
	var stage: Rect2 = _view.get_stage_rect_for_test()
	assert_lt(trophy_size.y / stage.size.y, 0.11,
			"远处茶几奖杯要比近处桌面物件更小, 保持房间透视")

# ---- 交互 ---------------------------------------------------------------

func test_click_computer_emits_signal() -> void:
	watch_signals(_view)
	_view.click_computer_for_test()
	assert_signal_emitted(_view, "computer_pressed")

func test_click_honor_emits_signal_with_id() -> void:
	_view.refresh(_data([_honor("t1", &"trophy", true)]))
	watch_signals(_view)
	_view.click_honor_for_test(&"t1")
	assert_signal_emitted_with_parameters(_view, "honor_pressed", [&"t1"])

func test_click_answer_box_emits_honor_signal() -> void:
	_view.refresh(_data([_honor("universe_answer", &"answer_box", true)]))
	watch_signals(_view)
	_view.click_honor_for_test(&"universe_answer")
	assert_signal_emitted_with_parameters(_view, "honor_pressed", [&"universe_answer"])
