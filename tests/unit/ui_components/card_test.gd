extends GutTest

## Card 组件契约 — 通用卡片骨架。
## 对应 design/UI视觉系统设计.md §7 + §8.3。

const CardScene := preload("res://scenes/ui/components/card/card.tscn")

func _make() -> Control:
	var c: Control = CardScene.instantiate()
	add_child_autofree(c)
	return c

func _minimal_data() -> Dictionary:
	return {"title": "sparrow-7B"}

# ─── header ─────────────────────────────────────────────────

func test_title_renders() -> void:
	var c := _make()
	c.set_data({"title": "sparrow-7B"})
	await get_tree().process_frame
	assert_eq(c.get_title_text(), "sparrow-7B")

func test_long_title_can_wrap_to_three_lines() -> void:
	var c := _make()
	c.set_data({"title": "CommonCrawl Raw 2017 News Archive 2017 Q2"})
	await get_tree().process_frame
	assert_ne(c.get_title_autowrap_for_test(), TextServer.AUTOWRAP_OFF,
		"长标题应允许换行, 避免 1080p 卡片标题被单行省略")
	assert_eq(c.get_title_max_lines_for_test(), 3)

func test_empty_subtitle_is_hidden() -> void:
	var c := _make()
	c.set_data({"title": "sparrow-7B"})
	await get_tree().process_frame
	assert_false(c.is_subtitle_visible(),
		"未提供 subtitle 时 subtitle 标签应隐藏")

func test_subtitle_renders_when_provided() -> void:
	var c := _make()
	c.set_data({"title": "sparrow-7B", "subtitle": "ant_v2 · 7B"})
	await get_tree().process_frame
	assert_true(c.is_subtitle_visible())
	assert_eq(c.get_subtitle_text(), "ant_v2 · 7B")
	assert_eq(c.get_subtitle_max_lines_for_test(), 3,
		"副标题最多显示 3 行, 让长资源名/部署目标多露出来")

# ─── avatar ─────────────────────────────────────────────────

func test_no_avatar_key_hides_avatar_slot() -> void:
	var c := _make()
	c.set_data({"title": "无头像卡"})
	await get_tree().process_frame
	assert_false(c.is_avatar_visible())

func test_avatar_dict_makes_avatar_visible() -> void:
	var c := _make()
	c.set_data({
		"title": "梧桐机房",
		"avatar": {
			"texture": null,
			"fallback_text": "梧桐机房",
			"seed_id": &"dc_wutong",
			"kind": &"datacenter",
		},
	})
	await get_tree().process_frame
	assert_true(c.is_avatar_visible())

# 紧凑缩略图: 头像槽 112×112, 保留视觉锚点但把空间还给文字。
func test_avatar_slot_is_compact() -> void:
	var c := _make()
	c.set_data({"title": "梧桐机房", "avatar": {"fallback_text": "梧桐机房", "seed_id": &"dc_x"}})
	await get_tree().process_frame
	assert_eq(c.get_avatar_min_size_for_test(), Vector2(UITheme.CARD_AVATAR_SIZE, UITheme.CARD_AVATAR_SIZE))
	assert_eq(int(UITheme.CARD_AVATAR_SIZE), 112)

func test_card_panel_uses_compact_surface_style() -> void:
	var c := _make()
	var sb: StyleBox = c.get_card_panel_style_for_test()
	assert_true(sb is StyleBoxFlat, "卡片 panel stylebox 应为 StyleBoxFlat")
	if sb is StyleBoxFlat:
		var flat := sb as StyleBoxFlat
		assert_true(flat.bg_color.is_equal_approx(UITheme.BG_SURFACE))
		assert_true(flat.border_color.is_equal_approx(UITheme.BORDER_SUBTLE))
		assert_eq(int(flat.content_margin_left), UITheme.S_3)
		assert_eq(flat.corner_radius_top_left, UITheme.R_MD)

func test_card_has_top_accent_rail() -> void:
	var c := _make()
	c.set_data({
		"title": "sparrow",
		"status": {"label": "已发布", "kind": &"published"},
	})
	await get_tree().process_frame
	assert_eq(c.get_accent_height_for_test(), 4,
		"卡片顶部应有 4px 资产锚点, 让卡片不像裸白盒")
	assert_true(c.get_accent_color_for_test().is_equal_approx(UITheme.ACCENT_INFO),
		"Card 默认不按 status 染色, published 也应保持炭黑单色锚点")

func test_card_without_status_uses_info_accent() -> void:
	var c := _make()
	c.set_data({"title": "plain"})
	await get_tree().process_frame
	assert_true(c.get_accent_color_for_test().is_equal_approx(UITheme.ACCENT_INFO),
		"无 status 时卡片仍应有炭黑细色带, 保持资产卡风格")

func test_card_hover_deepens_border_without_shadow() -> void:
	var c := _make()
	c.set_data({"title": "hover"})
	await get_tree().process_frame
	c.set_hovered_for_test(true)
	var sb: StyleBox = c.get_card_panel_style_for_test()
	assert_true(sb is StyleBoxFlat)
	if sb is StyleBoxFlat:
		var flat := sb as StyleBoxFlat
		assert_true(flat.border_color.is_equal_approx(UITheme.BORDER_STRONG),
			"hover 只加深边框, 不引入阴影")

# ─── 主次层级 (字重 + 灰度, design §8.3) ─────────────────────

func test_title_uses_bold_font() -> void:
	var c := _make()
	c.set_data({"title": "sparrow-7B"})
	await get_tree().process_frame
	assert_eq(c.get_title_font_for_test(), UITheme.get_ui_font_bold(),
		"卡片标题应用 bold 字重强调")

func test_field_label_is_secondary_gray_value_is_bold_primary() -> void:
	var c := _make()
	c.set_data({"title": "x", "fields": [{"label": "能力", "value": "42"}]})
	await get_tree().process_frame
	assert_eq(c.get_field_label_color_for_test(0), UITheme.TEXT_SECONDARY,
		"字段 label 应为次级灰, 弱化")
	assert_eq(c.get_field_value_color_for_test(0), UITheme.TEXT_PRIMARY,
		"字段 value 应为主色, 强调")
	assert_eq(c.get_field_value_font_for_test(0), UITheme.get_ui_font_bold(),
		"字段 value 应用 bold 字重强调")

func test_fields_are_grouped_in_subtle_panel() -> void:
	var c := _make()
	c.set_data({"title": "x", "fields": [{"label": "能力", "value": "42"}]})
	await get_tree().process_frame
	assert_true(c.is_fields_panel_visible_for_test(),
		"字段区应包在浅灰信息面里, 不再是裸 label 堆叠")
	assert_true(c.get_fields_panel_bg_for_test().is_equal_approx(UITheme.BG_BASE),
		"字段信息面的背景应为 BG_BASE, 和卡片白底拉开层级")

func test_field_value_wraps_to_three_left_aligned_lines() -> void:
	var c := _make()
	c.set_data({"title": "x", "fields": [{
		"label": "覆盖",
		"value": "文本 / 代码 / 图像 / 多模态长覆盖范围"
	}]})
	await get_tree().process_frame
	assert_eq(c.get_field_value_autowrap_for_test(0), TextServer.AUTOWRAP_WORD_SMART)
	assert_eq(c.get_field_value_max_lines_for_test(0), 3)
	assert_eq(c.get_field_value_alignment_for_test(0), HORIZONTAL_ALIGNMENT_LEFT)

func test_field_value_can_request_unlimited_lines() -> void:
	var c := _make()
	c.set_data({"title": "x", "fields": [{
		"label": "正文",
		"value": "第一句。第二句。第三句。第四句。第五句。",
		"max_lines": -1,
	}]})
	await get_tree().process_frame
	assert_eq(c.get_field_value_max_lines_for_test(0), -1,
			"事件正文这类长文应能显式取消 3 行截断")

# ─── status badge ───────────────────────────────────────────

func test_no_status_hides_badge() -> void:
	var c := _make()
	c.set_data({"title": "无状态卡"})
	await get_tree().process_frame
	assert_false(c.is_status_visible())

func test_status_dict_renders_badge() -> void:
	var c := _make()
	c.set_data({
		"title": "sparrow",
		"status": {"label": "已发布", "kind": &"published"},
	})
	await get_tree().process_frame
	assert_true(c.is_status_visible())
	assert_eq(c.get_status_label_text(), "已发布")

func test_status_badge_is_monochrome_inside_card() -> void:
	var c := _make()
	c.set_data({
		"title": "sparrow",
		"status": {"label": "已发布", "kind": &"published"},
	})
	await get_tree().process_frame
	assert_true(c.get_status_bg_color_for_test().is_equal_approx(UITheme.BG_ELEVATED),
		"Card 内 status badge 默认压成 neutral 灰阶, 不把卡片墙染成绿色")

# ─── fields ─────────────────────────────────────────────────

func test_empty_fields_no_body() -> void:
	var c := _make()
	c.set_data({"title": "x"})
	await get_tree().process_frame
	assert_eq(c.get_field_count(), 0)

func test_fields_render_as_label_value_rows() -> void:
	var c := _make()
	c.set_data({
		"title": "x",
		"fields": [
			{"label": "能力", "value": "42"},
			{"label": "t/s", "value": "18k"},
			{"label": "机房", "value": "梧桐-1"},
		],
	})
	await get_tree().process_frame
	assert_eq(c.get_field_count(), 3)
	var row0: Dictionary = c.get_field_row_for_test(0)
	assert_eq(row0.label, "能力")
	assert_eq(row0.value, "42")

# ─── actions ────────────────────────────────────────────────

func test_empty_actions_no_footer() -> void:
	var c := _make()
	c.set_data({"title": "x"})
	await get_tree().process_frame
	assert_eq(c.get_action_count(), 0)
	assert_false(c.is_footer_visible())

func test_actions_render_as_buttons() -> void:
	var c := _make()
	c.set_data({
		"title": "x",
		"actions": [
			{"id": &"evaluate", "label": "评估"},
			{"id": &"posttrain", "label": "后训"},
			{"id": &"publish",   "label": "发布"},
		],
	})
	await get_tree().process_frame
	assert_eq(c.get_action_count(), 3)
	assert_true(c.is_footer_visible())

func test_first_safe_action_defaults_to_primary() -> void:
	var c := _make()
	c.set_data({
		"title": "x",
		"actions": [
			{"id": &"evaluate", "label": "评估"},
			{"id": &"delete", "label": "删除"},
		],
	})
	await get_tree().process_frame
	assert_true(c.get_action_normal_bg_for_test(&"evaluate").is_equal_approx(UITheme.ACCENT_INFO),
		"第一个非破坏性 action 默认应成为 primary, 让主操作更明确")

func test_destructive_action_defaults_to_secondary_monochrome() -> void:
	var c := _make()
	c.set_data({
		"title": "x",
		"actions": [{"id": &"delete", "label": "删除"}],
	})
	await get_tree().process_frame
	assert_true(c.get_action_normal_bg_for_test(&"delete").is_equal_approx(UITheme.BG_SURFACE),
		"delete/fire/terminate/cancel 等默认应是 secondary 单色描边, 不在卡片墙里铺红色")

func test_action_click_emits_signal_with_id_on_next_frame() -> void:
	var c := _make()
	c.set_data({
		"title": "x",
		"actions": [
			{"id": &"publish", "label": "发布"},
		],
	})
	await get_tree().process_frame
	watch_signals(c)
	c.click_action_for_test(&"publish")
	assert_signal_emit_count(c, "action_pressed", 0,
		"Card action 必须延迟发出, 避免 pressed 回调栈内刷新并释放当前卡片")
	await get_tree().process_frame
	assert_signal_emitted_with_parameters(c, "action_pressed", [&"publish"])

# ─── 重置语义 ─────────────────────────────────────────────────

func test_set_data_twice_replaces_actions_and_fields() -> void:
	var c := _make()
	c.set_data({
		"title": "A",
		"fields": [{"label": "x", "value": "1"}, {"label": "y", "value": "2"}],
		"actions": [{"id": &"a1", "label": "动作 A"}],
	})
	await get_tree().process_frame
	c.set_data({
		"title": "B",
		"fields": [{"label": "z", "value": "3"}],
		"actions": [{"id": &"b1", "label": "动作 B"}, {"id": &"b2", "label": "动作 B2"}],
	})
	await get_tree().process_frame
	assert_eq(c.get_title_text(), "B")
	assert_eq(c.get_field_count(), 1)
	assert_eq(c.get_action_count(), 2)
	# 旧 action 的 id 不能残留 — 点 a1 应当无效果。
	watch_signals(c)
	c.click_action_for_test(&"a1")
	await get_tree().process_frame
	assert_signal_emit_count(c, "action_pressed", 0,
		"重置后旧 action_id 已被丢弃, 不应能触发")
