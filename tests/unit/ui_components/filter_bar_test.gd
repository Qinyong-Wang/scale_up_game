extends GutTest

## FilterBar 组件契约 — 状态 pills (多选, 第一个互斥) + 搜索 + 排序。
## 对应 design/UI视觉系统设计.md §8.1。

const FilterBarScene := preload("res://scenes/ui/components/filter_bar/filter_bar.tscn")

func _make() -> Control:
	var b: Control = FilterBarScene.instantiate()
	add_child_autofree(b)
	return b

func _model_pills() -> Array:
	# 第一个 "全部" 是 all-pill, 互斥其余。
	return [
		{"id": &"all",         "label": "全部"},
		{"id": &"pretrained",  "label": "已预训练"},
		{"id": &"posttrained", "label": "已后训"},
		{"id": &"evaluated",   "label": "已评估"},
		{"id": &"published",   "label": "已发布"},
	]

# ─── 初始化 ──────────────────────────────────────────────────

func test_no_pills_no_buttons() -> void:
	var b := _make()
	await get_tree().process_frame
	assert_eq(b.get_pill_count(), 0)

func test_set_pills_renders_buttons() -> void:
	var b := _make()
	b.set_pills(_model_pills())
	await get_tree().process_frame
	assert_eq(b.get_pill_count(), 5)

func test_initial_state_selects_all_pill() -> void:
	var b := _make()
	b.set_pills(_model_pills())
	await get_tree().process_frame
	var state: Dictionary = b.get_state()
	var selected: Array = state.selected_pills
	assert_eq(selected.size(), 1)
	assert_eq(selected[0], &"all", "初始默认选中第一个 (全部) pill")

# ─── 互斥逻辑 ─────────────────────────────────────────────────

func test_clicking_non_all_pill_deselects_all() -> void:
	var b := _make()
	b.set_pills(_model_pills())
	await get_tree().process_frame
	b.click_pill_for_test(&"published")
	var state: Dictionary = b.get_state()
	assert_false((state.selected_pills as Array).has(&"all"),
		"点了具体 pill 后 all 应当被取消")
	assert_true((state.selected_pills as Array).has(&"published"))

func test_clicking_all_clears_other_selections() -> void:
	var b := _make()
	b.set_pills(_model_pills())
	await get_tree().process_frame
	b.click_pill_for_test(&"published")
	b.click_pill_for_test(&"evaluated")
	b.click_pill_for_test(&"all")
	var state: Dictionary = b.get_state()
	assert_eq((state.selected_pills as Array).size(), 1)
	assert_eq((state.selected_pills as Array)[0], &"all")

func test_multi_select_non_all_pills() -> void:
	var b := _make()
	b.set_pills(_model_pills())
	await get_tree().process_frame
	b.click_pill_for_test(&"published")
	b.click_pill_for_test(&"evaluated")
	var state: Dictionary = b.get_state()
	assert_true((state.selected_pills as Array).has(&"published"))
	assert_true((state.selected_pills as Array).has(&"evaluated"))
	assert_false((state.selected_pills as Array).has(&"all"))

func test_toggling_off_last_non_all_reverts_to_all() -> void:
	# 取消选中最后一个具体 pill 时, 自动选回 all, 避免出现"全空"无意义状态。
	var b := _make()
	b.set_pills(_model_pills())
	await get_tree().process_frame
	b.click_pill_for_test(&"published")  # 选中
	b.click_pill_for_test(&"published")  # 再点 -> 取消
	var state: Dictionary = b.get_state()
	assert_eq((state.selected_pills as Array).size(), 1)
	assert_eq((state.selected_pills as Array)[0], &"all")

# ─── 信号 ────────────────────────────────────────────────────

func test_pill_click_emits_state_changed() -> void:
	var b := _make()
	b.set_pills(_model_pills())
	await get_tree().process_frame
	watch_signals(b)
	b.click_pill_for_test(&"published")
	assert_signal_emitted(b, "state_changed")

func test_search_input_emits_state_changed_with_text() -> void:
	var b := _make()
	b.set_pills(_model_pills())
	await get_tree().process_frame
	watch_signals(b)
	b.set_search_text_for_test("sparrow")
	assert_signal_emitted(b, "state_changed")
	assert_eq(b.get_state().search, "sparrow")

func test_sort_change_emits_state_changed() -> void:
	var b := _make()
	b.set_pills(_model_pills())
	b.set_sort_options([
		{"id": &"created_desc", "label": "最近创建"},
		{"id": &"capability",   "label": "按能力"},
	])
	await get_tree().process_frame
	watch_signals(b)
	b.select_sort_for_test(&"capability")
	assert_signal_emitted(b, "state_changed")
	assert_eq(b.get_state().sort, &"capability")

# ─── placeholder 与多次 set_pills ────────────────────────────

func test_set_search_placeholder_updates_input() -> void:
	var b := _make()
	b.set_search_placeholder("搜索化名")
	await get_tree().process_frame
	assert_eq(b.get_search_placeholder(), "搜索化名")

func test_set_pills_again_replaces_buttons() -> void:
	var b := _make()
	b.set_pills(_model_pills())
	await get_tree().process_frame
	b.set_pills([
		{"id": &"all",    "label": "全部"},
		{"id": &"online", "label": "在线"},
	])
	await get_tree().process_frame
	assert_eq(b.get_pill_count(), 2)
	# 重置后状态回到默认 all-selected。
	var sel: Array = b.get_state().selected_pills
	assert_eq(sel.size(), 1)
	assert_eq(sel[0], &"all")
