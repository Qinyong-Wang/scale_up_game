extends GutTest

## StatChip 组件契约 — 顶栏指标块。
## 对应 design/UI视觉系统设计.md §5 + §7。

const StatChipScene := preload("res://scenes/ui/components/stat_chip/stat_chip.tscn")

func _make() -> Control:
	var c: Control = StatChipScene.instantiate()
	add_child_autofree(c)
	return c

func test_displays_label_and_value() -> void:
	var c := _make()
	c.set_data("现金", "$52M", NAN, "")
	await get_tree().process_frame
	assert_eq(c.get_label_text(), "现金")
	assert_eq(c.get_value_text(), "$52M")

func test_uses_gcp_console_surface_panel() -> void:
	var c := _make()
	await get_tree().process_frame
	assert_true(c is PanelContainer,
		"StatChip 应是带描边和内边距的 PanelContainer, 而不是裸文本 HBox")
	assert_true(c.custom_minimum_size.x >= 96.0,
		"StatChip 需要稳定最小宽度, 避免顶栏指标刷新时抖动")
	assert_true(c.custom_minimum_size.y >= 36.0,
		"StatChip 需要 36px 左右的紧凑高度, 贴合 48px app bar")
	if not (c is PanelContainer):
		return
	var sb := c.get_theme_stylebox(&"panel")
	assert_true(sb is StyleBoxFlat,
		"StatChip panel stylebox 应使用 StyleBoxFlat")
	if sb is StyleBoxFlat:
		var flat := sb as StyleBoxFlat
		assert_true(flat.bg_color.is_equal_approx(UITheme.BG_SURFACE),
			"StatChip 背景应为白色 surface, 实际 %s" % flat.bg_color)
		assert_true(flat.border_color.is_equal_approx(UITheme.BORDER_SUBTLE),
			"StatChip 边框应为 subtle border, 实际 %s" % flat.border_color)
		assert_eq(flat.border_width_left, 1)
		assert_eq(flat.corner_radius_top_left, UITheme.R_SM)

func test_nan_delta_hides_delta_widget() -> void:
	var c := _make()
	c.set_data("回合", "24 周", NAN, "")
	await get_tree().process_frame
	assert_false(c.is_delta_visible(), "NAN delta 时 widget 应隐藏")

func test_positive_delta_uses_accent_primary() -> void:
	var c := _make()
	c.set_data("周净流", "$8M", 8.0, "+$8M")
	await get_tree().process_frame
	assert_true(c.is_delta_visible())
	assert_eq(c.get_delta_text(), "+$8M")
	assert_true(c.get_delta_color().is_equal_approx(UITheme.ACCENT_PRIMARY),
		"正 delta 必须用 ACCENT_PRIMARY, 实际 %s" % c.get_delta_color())

func test_negative_delta_uses_accent_danger() -> void:
	var c := _make()
	c.set_data("周净流", "-$3M", -3.0, "-$3M")
	await get_tree().process_frame
	assert_true(c.is_delta_visible())
	assert_true(c.get_delta_color().is_equal_approx(UITheme.ACCENT_DANGER),
		"负 delta 必须用 ACCENT_DANGER, 实际 %s" % c.get_delta_color())

func test_zero_delta_uses_secondary_text_color() -> void:
	# delta == 0 是中性变化 (无涨跌), 用 TEXT_SECONDARY 而不是红绿。
	var c := _make()
	c.set_data("付费用户", "8.0k", 0.0, "±0")
	await get_tree().process_frame
	assert_true(c.is_delta_visible())
	assert_true(c.get_delta_color().is_equal_approx(UITheme.TEXT_SECONDARY),
		"零 delta 用 TEXT_SECONDARY, 实际 %s" % c.get_delta_color())

func test_flat_variant_drops_border_and_fill() -> void:
	# 顶栏仪表簇: flat 变体去掉每块的描边/底色, 改靠块间竖线分隔。
	# 默认 (非 flat) 仍是白底描边卡 (见 test_uses_gcp_console_surface_panel)。
	var c := _make()
	c.set_flat(true)
	await get_tree().process_frame
	var sb := c.get_theme_stylebox(&"panel")
	assert_true(sb is StyleBoxFlat, "flat 变体 panel 仍应为 StyleBoxFlat")
	if sb is StyleBoxFlat:
		var flat := sb as StyleBoxFlat
		assert_eq(flat.border_width_left, 0, "flat 变体不应有边框")
		assert_almost_eq(flat.bg_color.a, 0.0, 0.001,
			"flat 变体应透明底, 融进顶栏仪表带")

func test_flat_variant_uses_md_value_font() -> void:
	# flat 变体把 value 提到 FS_MD (15) 当主读数; label 仍 FS_XS。
	var c := _make()
	c.set_flat(true)
	c.set_data("现金", "$1.2M", NAN, "")
	await get_tree().process_frame
	var v: Label = c.get_value_label()
	assert_eq(v.get_theme_font_size(&"font_size"), UITheme.FS_MD,
		"flat 变体 value 字号应提到 FS_MD")

func test_repeated_set_data_updates_in_place() -> void:
	var c := _make()
	c.set_data("现金", "$52M", NAN, "")
	await get_tree().process_frame
	c.set_data("现金", "$48M", -4.0, "-$4M")
	await get_tree().process_frame
	assert_eq(c.get_value_text(), "$48M")
	assert_true(c.is_delta_visible())
	assert_true(c.get_delta_color().is_equal_approx(UITheme.ACCENT_DANGER))
