extends GutTest

## HiringView 单测 — 招聘界面拆分后的「招新」一半 (候选 Lead 池 + 创始人入口)。
##
## 「在册」一半 (已签约 lead / staff / 工资合计) 见 staff_view_test.gd。
## View 只接 data dict (pre-computed bonus_text 已在调用方算好), 不访问
## GameState / HiringSystem; 信号反向通知调用方动业务命令。

const HiringViewScene := preload("res://scenes/ui/views/hiring_view/hiring_view.tscn")

const SPECIALTY_ORDER: Array = [
	&"chief_scientist", &"ml_research_lead", &"eval_lead",
	&"chief_engineer", &"data_scientist", &"marketing_lead",
]
const SPECIALTY_LABELS: Dictionary = {
	&"chief_scientist":  "预训练",
	&"ml_research_lead": "后训练",
	&"eval_lead":        "评估",
	&"chief_engineer":   "基建",
	&"data_scientist":   "数据采集",
	&"marketing_lead":   "营销",
}

func _make() -> Control:
	var v: Control = HiringViewScene.instantiate()
	add_child_autofree(v)
	return v

func _lead(id: StringName, display_name: String, spec: StringName, ability: float = 75.0) -> Lead:
	var l := Lead.new()
	l.id = id
	l.display_name = display_name
	l.specialty = spec
	l.level = &"A"
	l.ability = ability
	l.signing_fee = 50_000
	l.weekly_salary = 1_500
	return l

func _default_data() -> Dictionary:
	return {
		"has_founder": false,
		"pool": [],
		"specialty_order": SPECIALTY_ORDER,
		"specialty_labels": SPECIALTY_LABELS,
		"bonus_text": {},   # lead_id → "预训练加速 +30%"
	}

# ─── 创始人入口 ───────────────────────────────────────────────

func test_founder_section_shows_cta_when_no_founder() -> void:
	var v := _make()
	var data := _default_data()
	v.refresh(data)
	await get_tree().process_frame
	# 测试期望 "成为创始研究员" 按钮存在 (集成测试也要)。
	var btns: PackedStringArray = v.all_button_texts_for_test()
	var found := false
	for t in btns:
		if String(t).find("成为创始研究员") != -1:
			found = true
	assert_true(found, "未创建 founder 时应有按钮, 实际按钮: %s" % str(btns))

func test_founder_cta_is_shrink_not_full_width() -> void:
	# 成为创始研究员按钮应收紧, 不占满整屏 (design §9)。
	var v := _make()
	v.refresh(_default_data())  # has_founder = false
	await get_tree().process_frame
	assert_eq(v._founder_cta_btn.size_flags_horizontal, Control.SIZE_SHRINK_BEGIN,
		"创始研究员 CTA 不应 SIZE_FILL 铺满整屏")

func test_founder_cta_hidden_when_has_founder() -> void:
	# 创始人下场后, 招聘 tab 不再展示创始人区 (在册状态去「员工」tab 看)。
	var v := _make()
	var data := _default_data()
	data["has_founder"] = true
	v.refresh(data)
	await get_tree().process_frame
	var btns: PackedStringArray = v.all_button_texts_for_test()
	for t in btns:
		assert_true(String(t).find("成为创始研究员") == -1,
			"已有 founder 时招聘 tab 不应再有创建按钮")

func test_founder_cta_click_emits_become_founder_pressed() -> void:
	var v := _make()
	v.refresh(_default_data())
	await get_tree().process_frame
	watch_signals(v)
	v.click_become_founder_for_test()
	assert_signal_emitted(v, "become_founder_pressed")

# ─── 候选池卡片 ──────────────────────────────────────────────

func test_pool_renders_one_card_per_lead() -> void:
	var v := _make()
	var data := _default_data()
	data["pool"] = [
		_lead(&"a", "Alice", &"chief_scientist"),
		_lead(&"b", "Bob",   &"ml_research_lead"),
		_lead(&"c", "Cathy", &"data_scientist"),
	]
	data["bonus_text"][&"a"] = "预训练加速 +30%"
	data["bonus_text"][&"b"] = "后训练加速 +20%"
	data["bonus_text"][&"c"] = "数据质量 +15%"
	v.refresh(data)
	await get_tree().process_frame
	assert_eq(v.get_pool_card_count(), 3)

func test_pool_card_has_hire_action() -> void:
	var v := _make()
	var data := _default_data()
	data["pool"] = [_lead(&"a", "Alice", &"chief_scientist")]
	v.refresh(data)
	await get_tree().process_frame
	var actions: Array = v.get_card_actions_for_test(&"a")
	assert_true(actions.has(&"hire"), "pool card 应当有 hire action")

func test_pool_card_bonus_line_contains_prefix() -> void:
	# 关键: 老测试 _has_text_containing(labels, "加成:") 必须仍能匹配 — view 必须
	# 在卡片里有一个含 "加成:" 子串的 Label。
	var v := _make()
	var data := _default_data()
	data["pool"] = [_lead(&"a", "Alice", &"chief_scientist")]
	data["bonus_text"][&"a"] = "预训练加速 +30%"
	v.refresh(data)
	await get_tree().process_frame
	var labels: PackedStringArray = v.all_label_texts_for_test()
	var has_prefix := false
	for t in labels:
		if String(t).find("加成:") != -1:
			has_prefix = true
	assert_true(has_prefix, "pool card 至少有一处 Label 含 '加成:' 前缀")

func test_pool_specialty_subsection_labels_render() -> void:
	# 老集成测试期望 "后训练" / "数据采集" 等 specialty 标签在 tab 子树里出现。
	# view 用 SectionHeader / subsection label 实现分组。
	var v := _make()
	var data := _default_data()
	data["pool"] = [
		_lead(&"a", "Alice", &"ml_research_lead"),
		_lead(&"b", "Bob", &"data_scientist"),
	]
	v.refresh(data)
	await get_tree().process_frame
	var labels: PackedStringArray = v.all_label_texts_for_test()
	var has_pt := false
	var has_dc := false
	for t in labels:
		if String(t).find("后训练") != -1:
			has_pt = true
		if String(t).find("数据采集") != -1:
			has_dc = true
	assert_true(has_pt, "ml_research_lead 应当在 '后训练' 分组下")
	assert_true(has_dc, "data_scientist 应当在 '数据采集' 分组下")

func test_pool_card_click_hire_emits_lead_action() -> void:
	var v := _make()
	var data := _default_data()
	data["pool"] = [_lead(&"alice_lead", "Alice", &"chief_scientist")]
	v.refresh(data)
	await get_tree().process_frame
	watch_signals(v)
	v.click_card_action_for_test(&"alice_lead", &"hire")
	assert_signal_emitted_with_parameters(v, "lead_action",
		[&"alice_lead", &"hire"])
