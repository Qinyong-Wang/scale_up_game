extends GutTest

## Drawer 组件契约 — 右抽屉。
## 对应 design/UI视觉系统设计.md §7 + §4 (抽屉浮于主区右侧, 不遮挡侧栏)。

const DrawerScene := preload("res://scenes/ui/components/drawer/drawer.tscn")

func _make() -> Control:
	var d: Control = DrawerScene.instantiate()
	add_child_autofree(d)
	return d

func _content() -> Control:
	var c := Label.new()
	c.text = "form goes here"
	return c

# ─── 初始状态 ────────────────────────────────────────────────

func test_starts_hidden() -> void:
	var d := _make()
	await get_tree().process_frame
	assert_false(d.visible, "Drawer 默认隐藏, 等 open() 才显示")

func test_drawer_width_matches_design_token() -> void:
	var d := _make()
	await get_tree().process_frame
	assert_eq(int(d.custom_minimum_size.x), UITheme.DRAWER_W)

# ─── open / close ───────────────────────────────────────────

func test_open_makes_visible() -> void:
	var d := _make()
	d.open({"title": "新建模型", "content": _content()})
	await get_tree().process_frame
	assert_true(d.visible)

func test_close_makes_invisible() -> void:
	var d := _make()
	d.open({"title": "x", "content": _content()})
	await get_tree().process_frame
	d.close()
	assert_false(d.visible)

func test_close_emits_closed_signal() -> void:
	var d := _make()
	d.open({"title": "x", "content": _content()})
	await get_tree().process_frame
	watch_signals(d)
	d.close()
	assert_signal_emitted(d, "closed")

func test_clicking_x_button_closes() -> void:
	var d := _make()
	d.open({"title": "x", "content": _content()})
	await get_tree().process_frame
	watch_signals(d)
	d.click_close_for_test()
	assert_false(d.visible)
	assert_signal_emitted(d, "closed")

# ─── 内容 ──────────────────────────────────────────────────

func test_title_renders() -> void:
	var d := _make()
	d.open({"title": "新建模型", "content": _content()})
	await get_tree().process_frame
	assert_eq(d.get_title_text(), "新建模型")

func test_content_node_added_to_scroll() -> void:
	var d := _make()
	var c := _content()
	d.open({"title": "x", "content": c})
	await get_tree().process_frame
	# content 应当是 drawer 的后代节点。
	assert_true(c.is_inside_tree())
	assert_true(d.is_ancestor_of(c))

func test_reopen_with_new_content_replaces_old() -> void:
	var d := _make()
	var c1 := _content()
	d.open({"title": "A", "content": c1})
	await get_tree().process_frame
	var c2 := _content()
	d.open({"title": "B", "content": c2})
	await get_tree().process_frame
	assert_eq(d.get_title_text(), "B")
	# 旧 content 应当被剥离 (queue_free); 新 content 在树里。
	assert_true(c2.is_inside_tree())

# ─── 底部按钮 ─────────────────────────────────────────────────

func test_empty_primary_action_hides_button() -> void:
	var d := _make()
	d.open({"title": "x", "content": _content()})
	await get_tree().process_frame
	assert_false(d.is_primary_visible())

func test_primary_button_renders_when_provided() -> void:
	var d := _make()
	d.open({
		"title": "x",
		"content": _content(),
		"primary": {"label": "确认", "action_id": &"submit"},
	})
	await get_tree().process_frame
	assert_true(d.is_primary_visible())

func test_primary_press_emits_signal() -> void:
	var d := _make()
	d.open({
		"title": "x",
		"content": _content(),
		"primary": {"label": "确认", "action_id": &"submit_form"},
	})
	await get_tree().process_frame
	watch_signals(d)
	d.click_primary_for_test()
	assert_signal_emitted_with_parameters(d, "primary_pressed", [&"submit_form"])

func test_secondary_press_emits_signal() -> void:
	var d := _make()
	d.open({
		"title": "x",
		"content": _content(),
		"secondary": {"label": "取消", "action_id": &"cancel_form"},
	})
	await get_tree().process_frame
	watch_signals(d)
	d.click_secondary_for_test()
	assert_signal_emitted_with_parameters(d, "secondary_pressed", [&"cancel_form"])
