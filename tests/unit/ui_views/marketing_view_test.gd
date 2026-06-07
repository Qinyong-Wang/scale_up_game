extends GutTest

## MarketingView 试点视图测试 — 仿 product_view_test 模式。
## 视图自身不读 GameState; 通过 refresh(data) 接 dict。
## Per design/营销系统设计.md §7 (UI). v7 PR-F3: target_product_label 替代
## target_product_types。

const MarketingViewScene := preload("res://scenes/ui/views/marketing_view/marketing_view.tscn")


var _view: Control

func before_each() -> void:
	GameState.reset()
	_view = MarketingViewScene.instantiate()
	add_child_autofree(_view)

func _data(campaigns: Array = []) -> Dictionary:
	return {
		cap = MarketingSystem.MAX_CONCURRENT_CAMPAIGNS,
		active_count = campaigns.size(),
		can_create = true,
		create_disabled_reason = "",
		campaigns = campaigns,
	}

func _campaign_row(id: String, target_label: String, is_api: bool,
		per_week: int) -> Dictionary:
	return {
		id = StringName(id),
		display_name = "Test " + id,
		weekly_budget = 5000,
		remaining_weeks = 8,
		total_weeks = 13,
		target_product_id = StringName("p_" + id),
		target_product_label = target_label,
		target_is_api = is_api,
		lead_label = "(无)",
		lead_mult = 1.0,
		fake_score_label = "真实表述",
		fake_score_conversion_mult = 1.0,
		fake_score_retention_penalty = 0.0,
		expected_per_week = per_week,
	}

# ---- 空状态 -----------------------------------------------------------

func test_empty_state_renders_no_card() -> void:
	_view.refresh(_data([]))
	assert_eq(_view.get_card_count_for_test(), 0)

func test_create_button_is_shrink_not_full_width() -> void:
	# 新建活动按钮应收紧到内容宽, 不占满整屏 (design §9)。
	assert_eq(_view._create_btn.size_flags_horizontal, Control.SIZE_SHRINK_BEGIN,
		"新建活动按钮不应 SIZE_FILL 铺满整屏")

func test_create_button_uses_prominent_cta_style() -> void:
	assert_gte(int(_view._create_btn.custom_minimum_size.y), 40,
		"新建活动按钮应使用更醒目的 create CTA 高度")
	var normal: StyleBox = _view._create_btn.get_theme_stylebox(&"normal")
	assert_true(normal is StyleBoxFlat)
	if normal is StyleBoxFlat:
		assert_true((normal as StyleBoxFlat).bg_color.is_equal_approx(UITheme.ACCENT_INFO),
			"新建活动按钮应是炭黑实心主按钮")

func test_create_button_present_in_empty_state() -> void:
	_view.refresh(_data([]))
	var labels: PackedStringArray = _view.all_button_texts_for_test()
	var found_new := false
	for t in labels:
		if "新建" in t:
			found_new = true
	assert_true(found_new, "应当有「新建活动」按钮")

# ---- 卡片渲染 ---------------------------------------------------------

func test_active_campaign_renders_card() -> void:
	_view.refresh(_data([_campaign_row("c1", "MyBot (chatbot · m1)", false, 125)]))
	assert_eq(_view.get_card_count_for_test(), 1)

func test_campaign_card_uses_marketing_texture() -> void:
	_view.refresh(_data([_campaign_row("c1", "MyBot (chatbot · m1)", false, 125)]))
	assert_true(_view.has_method(&"is_card_avatar_texture_visible_for_test"),
		"MarketingView 应暴露卡片头像贴图测试入口")
	if not _view.has_method(&"is_card_avatar_texture_visible_for_test"):
		return
	assert_true(_view.is_card_avatar_texture_visible_for_test(&"c1"),
		"campaign 卡片头像应使用营销图片素材, 不再只显示文字占位")

func test_progress_text_uses_portable_ascii() -> void:
	# 剩余 8 / 总 13 => 已完成 5 周, 约 38%。不要用块状字符模拟进度条,
	# 这些 glyph 在部分平台字体下会显示成方块。
	_view.refresh(_data([_campaign_row("c1", "MyBot (chatbot · m1)", false, 125)]))
	var labels: PackedStringArray = _view.all_label_texts_for_test()
	assert_true(_has_label_containing(labels, "38% (5 / 13 周)"),
		"进度应显示为稳定 ASCII 文案, 实际: %s" % str(labels))
	assert_false(_has_label_containing(labels, "█"),
		"进度不应包含块状字符 █, 实际: %s" % str(labels))
	assert_false(_has_label_containing(labels, "░"),
		"进度不应包含块状字符 ░, 实际: %s" % str(labels))

func test_subscription_campaign_shows_users_per_week() -> void:
	_view.refresh(_data([_campaign_row("c1", "MyBot (chatbot · m1)", false, 125)]))
	var labels: PackedStringArray = _view.all_label_texts_for_test()
	# 期望同时找到「125」(数值) 和「用户」(中文标签)。
	var has_value := false
	var has_label := false
	for t in labels:
		if "125" in t:
			has_value = true
		if "用户" in t or "人" in t:
			has_label = true
	assert_true(has_value and has_label,
			"订阅 campaign 应显示每周新增用户数")

func test_api_campaign_shows_tokens_demand() -> void:
	_view.refresh(_data([_campaign_row("c_api", "Ant API (api · ant_v1)", true, 1_000_000)]))
	var labels: PackedStringArray = _view.all_label_texts_for_test()
	var found := false
	for t in labels:
		if "token" in t.to_lower() or "需求" in t:
			found = true
	assert_true(found, "API campaign 应显示每周新增 token 需求")

func test_card_shows_target_product_label() -> void:
	# v7 PR-F3: target 行应显示完整产品标识 "产品名 (type · bound_model)"。
	_view.refresh(_data([_campaign_row("c1", "Ant API (api · ant_v1)", true, 500_000)]))
	var labels: PackedStringArray = _view.all_label_texts_for_test()
	var found := false
	for t in labels:
		if "Ant API" in t:
			found = true
	assert_true(found, "卡片应显示目标产品名")

func test_card_shows_fake_score_strategy() -> void:
	var row := _campaign_row("c_fake", "MyBot (chatbot · m1)", false, 125)
	row.fake_score_label = "高度夸大"
	row.fake_score_conversion_mult = 1.25
	row.fake_score_retention_penalty = -1.0
	_view.refresh(_data([row]))
	var labels: PackedStringArray = _view.all_label_texts_for_test()
	assert_true(_has_label_containing(labels, "高度夸大"),
			"campaign 卡片应显示性能分数表述档位")
	assert_true(_has_label_containing(labels, "-100%"),
			"campaign 卡片应显示留存惩罚")

func test_terminate_action_emits_signal() -> void:
	_view.refresh(_data([_campaign_row("c_kill", "MyBot (chatbot · m1)", false, 100)]))
	watch_signals(_view)
	_view.click_terminate_for_test(&"c_kill")
	await get_tree().process_frame
	assert_signal_emitted_with_parameters(
			_view, "terminate_campaign_pressed", [&"c_kill"])

func test_new_campaign_button_emits_signal() -> void:
	_view.refresh(_data([]))
	watch_signals(_view)
	_view.click_new_for_test()
	assert_signal_emitted(_view, "new_campaign_pressed")

# ---- 创始人出身加成提示 (bug: 网红营销加成不显示在 UI) ------------------

func test_founder_bonus_note_hidden_when_neutral() -> void:
	var d := _data([])
	d["founder_mult"] = 1.0
	_view.refresh(d)
	assert_false(_view._founder_note.visible, "无加成时不应显示创始人提示")

func test_founder_bonus_note_shown_when_influencer() -> void:
	var d := _data([])
	d["founder_mult"] = 1.3
	_view.refresh(d)
	assert_true(_view._founder_note.visible, "网红加成应在营销 tab 显示提示")
	assert_true(_view._founder_note.text.contains("1.30"),
		"提示应含倍率 1.30, 实际: %s" % _view._founder_note.text)

func test_founder_mult_absent_defaults_hidden() -> void:
	# 旧 data 不含 founder_mult key 时不崩, 提示隐藏。
	_view.refresh(_data([]))
	assert_false(_view._founder_note.visible)

func _has_label_containing(labels: PackedStringArray, needle: String) -> bool:
	for t in labels:
		if String(t).find(needle) != -1:
			return true
	return false
