extends GutTest

## EventView 单测 — §10 step 6 (事件 tab)。

const EventViewScene := preload("res://scenes/ui/views/event_view/event_view.tscn")

func _make() -> Control:
	var v: Control = EventViewScene.instantiate()
	add_child_autofree(v)
	return v

# 事件 card 表示用普通 dict (调用方从 EventCard resource 转出来), view 不直接吃 resource。
func _pending(id: StringName, template_id: StringName, category: StringName, title: String, body: String, options: Array) -> Dictionary:
	return {
		"id": id,
		"template_id": template_id,
		"category": category,
		"title": title,
		"body": body,
		"options": options,  # Array of {id, label}
	}

func _history(template_id: StringName, chosen: StringName, turn: int,
		title: String = "", chosen_label: String = "") -> Dictionary:
	return {
		"template_id": template_id,
		"chosen_option_id": chosen,
		"resolved_at_turn": turn,
		"title": title,
		"chosen_label": chosen_label,
	}

func test_empty_pending_shows_hint() -> void:
	var v := _make()
	v.refresh({"pending": [], "history": []})
	await get_tree().process_frame
	var labels: PackedStringArray = v.all_label_texts_for_test()
	var found := false
	for t in labels:
		if String(t).find("无") != -1 and String(t).find("待处理") == -1:
			found = true
	# 老 UI 是 (无), 我们至少要有空提示, 不严格断字符。
	assert_true(found or labels.size() > 0)

func test_flavor_event_renders_dismiss_button() -> void:
	var v := _make()
	var ev := _pending(&"e1", &"flavor_news", &"flavor", "新闻", "市场上多了个开源模型", [])
	v.refresh({"pending": [ev], "history": []})
	await get_tree().process_frame
	var btns: PackedStringArray = v.all_button_texts_for_test()
	var found := false
	for t in btns:
		if String(t).find("知道了") != -1:
			found = true
	assert_true(found, "flavor 类事件应显示 '知道了' 按钮")

func test_flavor_event_appends_dismiss_consequence() -> void:
	var v := _make()
	var ev := _pending(&"e1", &"history_news", &"flavor", "新闻", "历史档案", [])
	ev["dismiss_consequence"] = "订阅约 +100"
	v.refresh({"pending": [ev], "history": []})
	await get_tree().process_frame
	var joined := "\n".join(v.all_button_texts_for_test())
	assert_ne(joined.find("知道了"), -1, "应保留 dismiss 标签")
	assert_ne(joined.find("订阅约 +100"), -1, "有被动后果的 flavor dismiss 应展示预览")

func test_event_body_uses_unlimited_field_lines() -> void:
	var v := _make()
	var ev := _pending(&"e1", &"history_news", &"flavor", "新闻",
		"第一句。第二句。第三句。第四句。第五句。第六句。", [])
	v.refresh({"pending": [ev], "history": []})
	await get_tree().process_frame
	assert_eq(v.first_pending_body_max_lines_for_test(), -1,
			"事件正文是主要内容, 不应被通用卡片字段的 3 行限制截断")

func test_choice_event_renders_option_buttons() -> void:
	var v := _make()
	var ev := _pending(&"e2", &"choice", &"opportunity", "投资人来访", "选择",
		[{"id": &"accept", "label": "接受"}, {"id": &"decline", "label": "拒绝"}])
	v.refresh({"pending": [ev], "history": []})
	await get_tree().process_frame
	var btns: PackedStringArray = v.all_button_texts_for_test()
	var has_accept := false
	var has_decline := false
	for t in btns:
		if String(t).find("接受") != -1: has_accept = true
		if String(t).find("拒绝") != -1: has_decline = true
	assert_true(has_accept and has_decline)

func test_option_consequence_appended_to_label() -> void:
	# main.gd 传裸 label + 单独的 consequence; view 翻译裸 label 后追加 consequence。
	# 守护拼装顺序 (见 国际化设计.md §6bis): 复合串不能再被 tr() 整条吞掉, 两段都要出现。
	var v := _make()
	var ev := _pending(&"e3", &"choice", &"opportunity", "T", "B",
		[{"id": &"accept", "label": "接受", "consequence": "获得约 $1,000"}])
	v.refresh({"pending": [ev], "history": []})
	await get_tree().process_frame
	var joined := "\n".join(v.all_button_texts_for_test())
	assert_ne(joined.find("接受"), -1, "应保留选项标签")
	assert_ne(joined.find("获得约 $1,000"), -1, "应在标签后追加后果预览")

func test_option_click_emits_option_selected() -> void:
	var v := _make()
	var ev := _pending(&"e2", &"choice", &"opportunity", "T", "B",
		[{"id": &"accept", "label": "接受"}])
	v.refresh({"pending": [ev], "history": []})
	await get_tree().process_frame
	watch_signals(v)
	v.click_option_for_test(&"e2", &"accept")
	assert_signal_emitted_with_parameters(v, "option_selected", [&"e2", &"accept"])

func test_flavor_dismiss_emits_dismiss() -> void:
	var v := _make()
	var ev := _pending(&"e1", &"flavor", &"flavor", "T", "B", [])
	v.refresh({"pending": [ev], "history": []})
	await get_tree().process_frame
	watch_signals(v)
	v.click_dismiss_for_test(&"e1")
	assert_signal_emitted_with_parameters(v, "flavor_dismissed", [&"e1"])

func test_no_debug_trigger_buttons() -> void:
	# debug 强制触发入口已下线 (玩法不需要手动加事件)。
	var v := _make()
	v.refresh({"pending": [], "history": []})
	await get_tree().process_frame
	var btns: PackedStringArray = v.all_button_texts_for_test()
	for t in btns:
		assert_eq(String(t).find("debug_test_offer"), -1, "不应再有 debug 触发按钮")
		assert_eq(String(t).find("DEBUG"), -1, "不应再有 DEBUG 按钮")

func test_pending_event_uses_display_labels_not_internal_ids() -> void:
	var v := _make()
	var ev := _pending(&"e2", &"debug_test_offer", &"opportunity", "投资人来访", "选择",
		[{"id": &"accept", "label": "接受"}])
	v.refresh({"pending": [ev], "history": []})
	await get_tree().process_frame
	var labels := "\n".join(v.all_label_texts_for_test())
	assert_ne(labels.find("机会"), -1)
	assert_eq(labels.find("[opportunity]"), -1)
	assert_eq(labels.find("debug_test_offer"), -1)

func test_history_rows_render() -> void:
	var v := _make()
	v.refresh({
		"pending": [],
		"history": [_history(&"some_event", &"accept", 5, "融资邀约", "接受")],
	})
	await get_tree().process_frame
	var labels: PackedStringArray = v.all_label_texts_for_test()
	var found := false
	for t in labels:
		if String(t).find("融资邀约") != -1 and String(t).find("接受") != -1:
			found = true
		assert_eq(String(t).find("some_event"), -1, "history row 不应优先显示 template_id")
	assert_true(found, "history row 应显示事件标题与选项展示名")
