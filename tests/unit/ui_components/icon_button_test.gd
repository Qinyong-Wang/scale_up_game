extends GutTest

## IconButton 组件契约。
## 对应 design/UI视觉系统设计.md §7。

const IconButtonScene := preload("res://scenes/ui/components/icon_button/icon_button.tscn")

func _make() -> Control:
	var b: Control = IconButtonScene.instantiate()
	add_child_autofree(b)
	return b

func test_glyph_icon_renders() -> void:
	var b := _make()
	b.set_data("⋯", "", &"more", &"default")
	await get_tree().process_frame
	assert_eq(b.get_icon_glyph(), "⋯")

func test_label_renders_when_provided() -> void:
	var b := _make()
	b.set_data("", "推进回合", &"advance", &"primary")
	await get_tree().process_frame
	assert_eq(b.get_label_text(), "推进回合")

func test_icon_only_when_label_empty() -> void:
	var b := _make()
	b.set_data("✕", "", &"close", &"ghost")
	await get_tree().process_frame
	assert_false(b.is_label_visible())

func test_icon_plus_label_both_visible() -> void:
	var b := _make()
	b.set_data("+", "新建", &"new", &"primary")
	await get_tree().process_frame
	assert_true(b.is_label_visible())
	assert_eq(b.get_icon_glyph(), "+")

func test_kind_primary_uses_accent_primary_bg() -> void:
	var b := _make()
	b.set_data("", "推进", &"advance", &"primary")
	await get_tree().process_frame
	assert_true(b.get_background_color().is_equal_approx(UITheme.ACCENT_PRIMARY),
		"primary kind 必须用 ACCENT_PRIMARY 背景, 实际 %s" % b.get_background_color())

func test_kind_danger_uses_accent_danger_bg() -> void:
	var b := _make()
	b.set_data("", "删除", &"delete", &"danger")
	await get_tree().process_frame
	assert_true(b.get_background_color().is_equal_approx(UITheme.ACCENT_DANGER))

func test_kind_default_uses_bg_surface() -> void:
	var b := _make()
	b.set_data("⋯", "", &"more", &"default")
	await get_tree().process_frame
	assert_true(b.get_background_color().is_equal_approx(UITheme.BG_SURFACE))

func test_kind_ghost_uses_transparent_bg() -> void:
	# ghost = 无背景, 仅图标/文字, 适合放在 header / 抽屉关闭按钮。
	var b := _make()
	b.set_data("✕", "", &"close", &"ghost")
	await get_tree().process_frame
	var c: Color = b.get_background_color()
	assert_eq(c.a, 0.0, "ghost 背景应当完全透明, 实际 alpha=%f" % c.a)

func test_unknown_kind_falls_back_to_default() -> void:
	var b_default := _make()
	b_default.set_data("?", "", &"x", &"default")
	var b_unknown := _make()
	b_unknown.set_data("?", "", &"x", &"some_unknown_kind")
	await get_tree().process_frame
	assert_true(b_default.get_background_color().is_equal_approx(b_unknown.get_background_color()))

func test_press_emits_signal_with_action_id() -> void:
	var b := _make()
	b.set_data("", "推进", &"advance_turn", &"primary")
	await get_tree().process_frame
	watch_signals(b)
	b.click_for_test()
	assert_signal_emitted_with_parameters(b, "pressed_with_id", [&"advance_turn"])
