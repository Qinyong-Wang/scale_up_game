extends GutTest

## SidebarGroup 组件契约 — 侧栏分组容器。
## 对应 design/UI视觉系统设计.md §6 + §7。

const SidebarGroupScene := preload("res://scenes/ui/components/sidebar_group/sidebar_group.tscn")
const SidebarItemScene := preload("res://scenes/ui/components/sidebar_item/sidebar_item.tscn")

func _make_group() -> Control:
	var g: Control = SidebarGroupScene.instantiate()
	add_child_autofree(g)
	return g

func _make_item(label: String, nav_id: StringName) -> Control:
	var i: Control = SidebarItemScene.instantiate()
	i.set_data("◉", label, nav_id, -1)
	return i

func test_title_renders() -> void:
	var g := _make_group()
	g.set_title("运营")
	await get_tree().process_frame
	assert_eq(g.get_title_text(), "运营")

func test_starts_expanded() -> void:
	var g := _make_group()
	g.set_title("运营")
	await get_tree().process_frame
	assert_false(g.is_collapsed())

func test_set_collapsed_hides_children() -> void:
	var g := _make_group()
	g.set_title("运营")
	var i1 := _make_item("概览", &"overview")
	var i2 := _make_item("经济", &"economy")
	g.add_item(i1)
	g.add_item(i2)
	await get_tree().process_frame
	assert_true(i1.is_visible_in_tree())
	assert_true(i2.is_visible_in_tree())
	g.set_collapsed(true)
	await get_tree().process_frame
	assert_false(i1.is_visible_in_tree(), "折叠时子项 i1 应隐藏 (经父节点)")
	assert_false(i2.is_visible_in_tree(), "折叠时子项 i2 应隐藏 (经父节点)")

func test_set_collapsed_false_restores_visibility() -> void:
	var g := _make_group()
	g.set_title("研发")
	var i := _make_item("模型", &"models")
	g.add_item(i)
	await get_tree().process_frame
	g.set_collapsed(true)
	await get_tree().process_frame
	g.set_collapsed(false)
	await get_tree().process_frame
	assert_true(i.is_visible_in_tree())

func test_toggle_emits_collapsed_changed() -> void:
	var g := _make_group()
	g.set_title("研发")
	await get_tree().process_frame
	watch_signals(g)
	g.set_collapsed(true)
	assert_signal_emitted_with_parameters(g, "collapsed_changed", [true])
	g.set_collapsed(false)
	assert_signal_emitted_with_parameters(g, "collapsed_changed", [false])

func test_clicking_header_toggles_collapsed() -> void:
	# 玩家点击标题条 (而不是调 set_collapsed) 也能触发折叠。
	var g := _make_group()
	g.set_title("研发")
	await get_tree().process_frame
	assert_false(g.is_collapsed())
	g.click_header_for_test()
	assert_true(g.is_collapsed())
	g.click_header_for_test()
	assert_false(g.is_collapsed())
