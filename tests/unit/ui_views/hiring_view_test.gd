extends GutTest

## HiringView 单测 — 招聘界面拆分后的「招新」一半 (候选 Lead 池)。
##
## 「在册」一半 (创始人 / 已签约 lead / staff / 工资合计) 见 staff_view_test.gd。
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

# ─── 创始人入口已移除 ─────────────────────────────────────────

func test_founder_section_stays_hidden_when_no_founder() -> void:
	var v := _make()
	var data := _default_data()
	v.refresh(data)
	await get_tree().process_frame
	var btns: PackedStringArray = v.all_button_texts_for_test()
	for t in btns:
		assert_true(String(t).find("成为创始研究员") == -1,
			"开局自动加入 founder 后, 招聘页不应再出现手动 CTA")
	assert_false(v._founder_section.visible,
		"招聘页不再承载 founder CTA, founder section 应隐藏")

func test_founder_section_stays_hidden_when_has_founder() -> void:
	var v := _make()
	var data := _default_data()
	data["has_founder"] = true
	v.refresh(data)
	await get_tree().process_frame
	var btns: PackedStringArray = v.all_button_texts_for_test()
	for t in btns:
		assert_true(String(t).find("成为创始研究员") == -1,
			"已有 founder 时招聘 tab 不应再有创建按钮")
	assert_false(v._founder_section.visible,
		"已有 founder 时 founder section 也应隐藏")

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
	await get_tree().process_frame
	assert_signal_emitted_with_parameters(v, "lead_action",
		[&"alice_lead", &"hire"])
