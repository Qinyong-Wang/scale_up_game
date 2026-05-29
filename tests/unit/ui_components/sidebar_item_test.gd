extends GutTest

## SidebarItem 组件契约 — 侧栏导航项。
## 对应 design/UI视觉系统设计.md §6 + §7。

const SidebarItemScene := preload("res://scenes/ui/components/sidebar_item/sidebar_item.tscn")

func _make() -> Control:
	var i: Control = SidebarItemScene.instantiate()
	add_child_autofree(i)
	return i

func test_label_and_icon_render() -> void:
	var i := _make()
	i.set_data("◉", "模型", &"models", -1)
	await get_tree().process_frame
	assert_eq(i.get_label_text(), "模型")
	assert_eq(i.get_icon_glyph(), "◉")

func test_icon_tile_uses_sidebar_tokens() -> void:
	var i := _make()
	i.set_data(char(0xe871), "概览", &"overview", -1)
	await get_tree().process_frame
	assert_eq(i.get_minimum_height_for_test(), UITheme.SIDEBAR_ITEM_H,
		"导航项高度应走 sidebar token, 保持点击目标稳定")
	assert_eq(i.get_icon_slot_min_size(), Vector2(UITheme.SIDEBAR_ICON_TILE, UITheme.SIDEBAR_ICON_TILE),
		"icon 必须有独立正方形 tile, 不应只是裸字形")
	assert_eq(i.get_icon_font_size(), UITheme.SIDEBAR_ICON_GLYPH_SIZE,
		"Material Icons glyph 字号必须固定, 防止每项视觉重量不一")

func test_icon_tile_defaults_to_surface_with_border() -> void:
	var i := _make()
	i.set_data(char(0xe871), "概览", &"overview", -1)
	await get_tree().process_frame
	assert_true(i.get_icon_tile_bg_color().is_equal_approx(UITheme.BG_SURFACE),
		"默认 icon tile 应是白底")
	assert_true(i.get_icon_tile_border_color().is_equal_approx(UITheme.BORDER_SUBTLE),
		"默认 icon tile 应有浅边框, 在白色侧栏里仍能读出形状")
	assert_true(i.get_icon_color().is_equal_approx(UITheme.TEXT_SECONDARY),
		"默认 icon glyph 用次级文字色")

func test_active_item_reverses_icon_and_emphasizes_label() -> void:
	var i := _make()
	i.set_data(char(0xe871), "概览", &"overview", -1)
	await get_tree().process_frame
	i.set_active(true)
	assert_true(i.get_icon_tile_bg_color().is_equal_approx(UITheme.ACCENT_INFO),
		"选中项 icon tile 应使用炭黑底")
	assert_true(i.get_icon_color().is_equal_approx(UITheme.BG_SURFACE),
		"选中项 icon glyph 应反白")
	assert_true(i.get_label_color().is_equal_approx(UITheme.TEXT_PRIMARY),
		"选中项 label 应回到主文字色")

func test_active_bar_keeps_width_when_inactive() -> void:
	var i := _make()
	i.set_data(char(0xe871), "概览", &"overview", -1)
	await get_tree().process_frame
	assert_eq(i.get_active_bar_width_for_test(), UITheme.SIDEBAR_ACTIVE_BAR_W,
		"active rail 未选中时也要占位, 避免切换 tab 时 label 横向跳动")
	assert_almost_eq(i.get_active_bar_color_for_test().a, 0.0, 0.001,
		"未选中 rail 应透明而不是隐藏")
	i.set_active(true)
	assert_true(i.get_active_bar_color_for_test().is_equal_approx(UITheme.ACCENT_INFO),
		"选中 rail 应显示交互主调")

func test_negative_badge_hidden() -> void:
	var i := _make()
	i.set_data("◉", "模型", &"models", -1)
	await get_tree().process_frame
	assert_false(i.is_badge_visible())

func test_zero_badge_hidden() -> void:
	# 0 件未读 / 进行中 不显示数字, 避免噪音 (区别于 SectionHeader 的计数)。
	var i := _make()
	i.set_data("📋", "任务", &"tasks", 0)
	await get_tree().process_frame
	assert_false(i.is_badge_visible())

func test_positive_badge_visible() -> void:
	var i := _make()
	i.set_data("📋", "任务", &"tasks", 3)
	await get_tree().process_frame
	assert_true(i.is_badge_visible())
	assert_eq(i.get_badge_text(), "3")

func test_positive_badge_uses_monochrome_pill() -> void:
	var i := _make()
	i.set_data("📋", "任务", &"tasks", 3)
	await get_tree().process_frame
	assert_true(i.get_badge_bg_color_for_test().is_equal_approx(UITheme.TEXT_PRIMARY),
		"侧栏任务/事件数字应为炭黑底, 不使用黄色 warning badge")
	assert_true(i.get_badge_label_color_for_test().is_equal_approx(UITheme.BG_SURFACE),
		"侧栏数字应为白字, 保持黑白灰基调")

func test_initially_inactive() -> void:
	var i := _make()
	i.set_data("◉", "模型", &"models", -1)
	await get_tree().process_frame
	assert_false(i.is_active())

func test_set_active_toggles_state() -> void:
	var i := _make()
	i.set_data("◉", "模型", &"models", -1)
	await get_tree().process_frame
	i.set_active(true)
	assert_true(i.is_active())
	i.set_active(false)
	assert_false(i.is_active())

func test_press_emits_signal_with_nav_id() -> void:
	var i := _make()
	i.set_data("◉", "模型", &"models", -1)
	await get_tree().process_frame
	watch_signals(i)
	i.click_for_test()
	assert_signal_emitted_with_parameters(i, "nav_pressed", [&"models"])

func test_collapsed_hides_label_keeps_icon() -> void:
	# 折叠态: label 隐藏, icon 与 badge 仍可见。
	var i := _make()
	i.set_data("📋", "任务", &"tasks", 3)
	await get_tree().process_frame
	i.set_collapsed(true)
	assert_false(i.is_label_visible())
	assert_true(i.is_icon_visible())

func test_expanded_shows_label() -> void:
	var i := _make()
	i.set_data("◉", "模型", &"models", -1)
	i.set_collapsed(true)
	await get_tree().process_frame
	i.set_collapsed(false)
	assert_true(i.is_label_visible())
