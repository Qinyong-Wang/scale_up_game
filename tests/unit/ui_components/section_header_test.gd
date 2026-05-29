extends GutTest

## SectionHeader 组件契约 — 主区标题 + 计数 + 操作按钮。
## 对应 design/UI视觉系统设计.md §7。

const SectionHeaderScene := preload("res://scenes/ui/components/section_header/section_header.tscn")

func _make() -> Control:
	var h: Control = SectionHeaderScene.instantiate()
	add_child_autofree(h)
	return h

func test_title_renders() -> void:
	var h := _make()
	h.set_data("我的模型", -1, "", &"")
	await get_tree().process_frame
	assert_eq(h.get_title_text(), "我的模型")

func test_negative_count_hides_count_label() -> void:
	var h := _make()
	h.set_data("我的模型", -1, "", &"")
	await get_tree().process_frame
	assert_false(h.is_count_visible())

func test_non_negative_count_shows_count() -> void:
	var h := _make()
	h.set_data("我的模型", 7, "", &"")
	await get_tree().process_frame
	assert_true(h.is_count_visible())
	assert_eq(h.get_count_text(), "7")

func test_zero_count_still_shows() -> void:
	# 0 是合法的计数, 应当显示而不是被当成 \"没有计数信息\" 隐藏。
	var h := _make()
	h.set_data("已发布", 0, "", &"")
	await get_tree().process_frame
	assert_true(h.is_count_visible())
	assert_eq(h.get_count_text(), "0")

func test_empty_action_text_hides_action_button() -> void:
	var h := _make()
	h.set_data("数据集", -1, "", &"")
	await get_tree().process_frame
	assert_false(h.is_action_visible())

func test_action_button_emits_signal_with_id() -> void:
	var h := _make()
	h.set_data("我的模型", -1, "+ 训练新模型", &"new_model")
	await get_tree().process_frame
	assert_true(h.is_action_visible())
	watch_signals(h)
	h.click_action_for_test()
	assert_signal_not_emitted(h, "action_pressed",
		"SectionHeader should defer action_pressed until input dispatch has settled")
	await get_tree().process_frame
	assert_signal_emitted_with_parameters(h, "action_pressed", [&"new_model"])

func test_action_button_uses_create_cta_style() -> void:
	var h := _make()
	h.set_data("我的模型", -1, "+ 训练新模型", &"new_model")
	await get_tree().process_frame
	var btn := _first_button(h)
	assert_not_null(btn, "SectionHeader 有 action_text 时应渲染按钮")
	if btn == null:
		return
	assert_gte(int(btn.custom_minimum_size.y), 40,
		"标题栏新建入口应使用更醒目的 create CTA 高度")
	assert_eq(btn.get_theme_font_size(&"font_size"), UITheme.FS_MD,
		"标题栏新建入口应使用更醒目的 CTA 字号")
	var normal := btn.get_theme_stylebox(&"normal")
	assert_true(normal is StyleBoxFlat)
	if normal is StyleBoxFlat:
		assert_true((normal as StyleBoxFlat).bg_color.is_equal_approx(UITheme.ACCENT_INFO),
			"标题栏新建入口应是炭黑实心主按钮")

func test_repeated_set_data_updates_action_id() -> void:
	var h := _make()
	h.set_data("A", -1, "做 A", &"action_a")
	await get_tree().process_frame
	h.set_data("B", 3, "做 B", &"action_b")
	await get_tree().process_frame
	watch_signals(h)
	h.click_action_for_test()
	await get_tree().process_frame
	assert_signal_emitted_with_parameters(h, "action_pressed", [&"action_b"])

func _first_button(node: Node) -> Button:
	if node is Button:
		return node as Button
	for child in node.get_children():
		var found := _first_button(child)
		if found != null:
			return found
	return null
