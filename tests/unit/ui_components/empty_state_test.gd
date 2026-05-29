extends GutTest

## EmptyState 组件契约 — 空状态占位。
## 对应 design/UI视觉系统设计.md §7 + §8.2 (卡片数 0 时替换为 EmptyState)。

const EmptyStateScene := preload("res://scenes/ui/components/empty_state/empty_state.tscn")

func _make() -> Control:
	var e: Control = EmptyStateScene.instantiate()
	add_child_autofree(e)
	return e

func test_title_renders() -> void:
	var e := _make()
	e.set_data("◉", "还没有模型", "", "", &"")
	await get_tree().process_frame
	assert_eq(e.get_title_text(), "还没有模型")

func test_icon_glyph_renders() -> void:
	var e := _make()
	e.set_data("◉", "无模型", "", "", &"")
	await get_tree().process_frame
	assert_eq(e.get_icon_glyph(), "◉")

func test_hint_renders_when_provided() -> void:
	var e := _make()
	e.set_data("◉", "无模型", "立即训练第一个模型 →", "", &"")
	await get_tree().process_frame
	assert_true(e.is_hint_visible())
	assert_eq(e.get_hint_text(), "立即训练第一个模型 →")

func test_empty_hint_hidden() -> void:
	var e := _make()
	e.set_data("◉", "无模型", "", "", &"")
	await get_tree().process_frame
	assert_false(e.is_hint_visible())

func test_empty_action_text_hides_cta() -> void:
	var e := _make()
	e.set_data("◉", "无模型", "提示", "", &"")
	await get_tree().process_frame
	assert_false(e.is_action_visible())

func test_action_renders_when_provided() -> void:
	var e := _make()
	e.set_data("◉", "无模型", "提示", "+ 训练新模型", &"new_model")
	await get_tree().process_frame
	assert_true(e.is_action_visible())

func test_action_uses_create_cta_style() -> void:
	var e := _make()
	e.set_data("◉", "无模型", "提示", "+ 训练新模型", &"new_model")
	await get_tree().process_frame
	var btn := _first_button(e)
	assert_not_null(btn, "EmptyState 有 action_text 时应渲染 CTA")
	if btn == null:
		return
	assert_gte(int(btn.custom_minimum_size.y), 40,
		"空状态创建入口应使用更醒目的 create CTA 高度")
	var normal := btn.get_theme_stylebox(&"normal")
	assert_true(normal is StyleBoxFlat)
	if normal is StyleBoxFlat:
		assert_true((normal as StyleBoxFlat).bg_color.is_equal_approx(UITheme.ACCENT_INFO),
			"空状态创建入口应是炭黑实心主按钮")

func test_action_click_emits_signal_with_id() -> void:
	var e := _make()
	e.set_data("◉", "无模型", "", "+ 新建", &"new_model")
	await get_tree().process_frame
	watch_signals(e)
	e.click_action_for_test()
	assert_signal_emitted_with_parameters(e, "action_pressed", [&"new_model"])

func _first_button(node: Node) -> Button:
	if node is Button:
		return node as Button
	for child in node.get_children():
		var found := _first_button(child)
		if found != null:
			return found
	return null
