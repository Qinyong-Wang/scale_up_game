extends GutTest

## StaffView 单测 — 招聘界面拆分后的「在册」一半。
##
## 覆盖: 创始人状态行 + 已签约 Lead 卡片 + 普通员工 staff 增减 + 周工资合计。
## 「招新」一半 (候选池) 见 hiring_view_test.gd。
## View 只接 data dict (pre-computed bonus_text / status_text 已在调用方算好),
## 不访问 GameState / HiringSystem; 信号反向通知调用方动业务命令。

const StaffViewScene := preload("res://scenes/ui/views/staff_view/staff_view.tscn")

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
	var v: Control = StaffViewScene.instantiate()
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

func _founder_lead() -> Lead:
	var l := _lead(&"player_scientist", "创始人", &"founder", 100.0)
	l.level = &"founder"
	l.signing_fee = 0
	l.weekly_salary = 0
	l.is_player_scientist = true
	return l

func _default_data() -> Dictionary:
	return {
		"has_founder": false,
		"hired": [],
		"specialty_order": SPECIALTY_ORDER,
		"specialty_labels": SPECIALTY_LABELS,
		"bonus_text": {},   # lead_id → "预训练加速 +30%"
		"status_text": {},  # lead_id → "idle" / "锁定 task_xyz" / ...
		"staff_rows": [],
		"weekly_totals": {"lead": 0, "staff": 0, "total": 0},
	}

# ─── 创始人状态行 ─────────────────────────────────────────────

func test_founder_section_shows_joined_label_when_has_founder() -> void:
	var v := _make()
	var data := _default_data()
	data["has_founder"] = true
	data["hired"] = [_founder_lead()]
	v.refresh(data)
	await get_tree().process_frame
	var labels: PackedStringArray = v.all_label_texts_for_test()
	var found := false
	for t in labels:
		if String(t).find("创始人已加入") != -1:
			found = true
	assert_true(found, "已创建 founder 后员工 tab 应有 '创始人已加入' 提示")

func test_founder_section_renders_founder_as_card() -> void:
	# 招聘系统设计 §5.4: founder 已创建时, 员工 tab 顶部展示玩家自己的卡片,
	# 而不是只有一行状态提示。
	var v := _make()
	var data := _default_data()
	data["has_founder"] = true
	data["hired"] = [_founder_lead()]
	data["status_text"][&"player_scientist"] = "创始人 (万能 lead)"
	v.refresh(data)
	await get_tree().process_frame
	assert_eq(v.get_founder_card_count_for_test(), 1,
		"员工 tab 顶部应渲染一张 founder card")
	assert_false(v.get_card_actions_for_test(&"player_scientist").has(&"fire"),
		"founder card 不应出现解雇按钮")

func test_founder_section_shows_hint_when_no_founder() -> void:
	var v := _make()
	v.refresh(_default_data())
	await get_tree().process_frame
	var labels: PackedStringArray = v.all_label_texts_for_test()
	var has_auto_hint := false
	var has_old_founder_cta_hint := false
	for t in labels:
		if String(t).find("开局会自动加入团队") != -1:
			has_auto_hint = true
		if String(t).find("还不是创始研究员") != -1 or String(t).find("选择下场") != -1:
			has_old_founder_cta_hint = true
	assert_true(has_auto_hint, "缺 founder 的旧档/测试数据应说明会自动加入团队")
	assert_false(has_old_founder_cta_hint, "不应再提示玩家去招聘页手动下场")

# ─── 已签约卡片 ─────────────────────────────────────────────

func test_hired_renders_cards() -> void:
	var v := _make()
	var data := _default_data()
	data["hired"] = [_lead(&"a", "Alice", &"chief_scientist")]
	data["status_text"][&"a"] = "idle"
	v.refresh(data)
	await get_tree().process_frame
	assert_eq(v.get_hired_card_count(), 1)

func test_hired_card_has_fire_action_when_idle() -> void:
	var v := _make()
	var data := _default_data()
	var l := _lead(&"a", "Alice", &"chief_scientist")
	data["hired"] = [l]
	data["status_text"][&"a"] = "idle"
	v.refresh(data)
	await get_tree().process_frame
	assert_true(v.get_card_actions_for_test(&"a").has(&"fire"))

func test_hired_card_no_fire_action_when_founder() -> void:
	var v := _make()
	var data := _default_data()
	var l := _lead(&"f", "Founder", &"chief_scientist")
	l.is_player_scientist = true
	data["hired"] = [l]
	data["status_text"][&"f"] = "创始人 (万能 lead)"
	v.refresh(data)
	await get_tree().process_frame
	assert_false(v.get_card_actions_for_test(&"f").has(&"fire"),
		"founder lead 不能被解雇, fire action 应当不存在")

func test_hired_card_no_fire_action_when_locked() -> void:
	var v := _make()
	var data := _default_data()
	var l := _lead(&"a", "Alice", &"chief_scientist")
	l.locked_by_task_id = &"task_xyz"
	data["hired"] = [l]
	data["status_text"][&"a"] = "锁定 task_xyz"
	v.refresh(data)
	await get_tree().process_frame
	assert_false(v.get_card_actions_for_test(&"a").has(&"fire"),
		"locked lead 不能解雇")

func test_hired_card_click_fire_emits_lead_action() -> void:
	var v := _make()
	var data := _default_data()
	data["hired"] = [_lead(&"a", "Alice", &"chief_scientist")]
	data["status_text"][&"a"] = "idle"
	v.refresh(data)
	await get_tree().process_frame
	watch_signals(v)
	v.click_card_action_for_test(&"a", &"fire")
	await get_tree().process_frame
	assert_signal_emitted_with_parameters(v, "lead_action", [&"a", &"fire"])

func test_hired_specialty_subsection_labels_render() -> void:
	var v := _make()
	var data := _default_data()
	data["hired"] = [
		_lead(&"a", "Alice", &"ml_research_lead"),
		_lead(&"b", "Bob", &"data_scientist"),
	]
	data["status_text"][&"a"] = "idle"
	data["status_text"][&"b"] = "idle"
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

# ─── 员工区块 ────────────────────────────────────────────────

func test_staff_rows_render_with_plus_minus_buttons() -> void:
	var v := _make()
	var data := _default_data()
	data["staff_rows"] = [
		{"role": &"ml_eng", "label": "ml_eng", "pool": 4, "busy": 2, "per_week": 2_000},
	]
	v.refresh(data)
	await get_tree().process_frame
	var btns: PackedStringArray = v.all_button_texts_for_test()
	var has_plus := false
	for t in btns:
		if String(t).find("+1 (+$") != -1:
			has_plus = true
	assert_true(has_plus, "staff +1 按钮应当含 '+1 (+$X/周)' 文案, 实际: %s" % str(btns))

func test_staff_row_shows_idle_count() -> void:
	# 普通员工区提到上方后, 单行需要能扫到总数 / 忙碌 / 空闲三种水位。
	var v := _make()
	var data := _default_data()
	data["staff_rows"] = [
		{"role": &"ml_eng", "label": "ML 工程师", "pool": 4, "busy": 2, "per_week": 2_000},
	]
	v.refresh(data)
	await get_tree().process_frame
	var labels: PackedStringArray = v.all_label_texts_for_test()
	var has_idle := false
	for t in labels:
		if String(t).find("空闲 2") != -1:
			has_idle = true
	assert_true(has_idle, "普通员工行应显示空闲人数, 实际 labels=%s" % str(labels))

func test_staff_section_is_above_hired_leads_section() -> void:
	# 招聘系统设计 §5.4: 普通员工是高频水位入口, 在员工 tab 中应位于已签约 Lead 上方。
	var v := _make()
	var data := _default_data()
	data["staff_rows"] = [
		{"role": &"ml_eng", "label": "ML 工程师", "pool": 1, "busy": 0, "per_week": 2_000},
	]
	data["hired"] = [_lead(&"a", "Alice", &"chief_scientist")]
	data["status_text"][&"a"] = "idle"
	v.refresh(data)
	await get_tree().process_frame
	var order: PackedStringArray = v.section_order_for_test()
	assert_true(order.find("STAFF_BY_ROLE") != -1, "section order 应包含普通员工区")
	assert_true(order.find("STAFF_HIRED_LEADS") != -1, "section order 应包含已签约 Lead 区")
	assert_lt(order.find("STAFF_BY_ROLE"), order.find("STAFF_HIRED_LEADS"),
		"普通员工区应位于已签约 Lead 区上方, 实际: %s" % str(order))

func test_staff_plus_button_emits_staff_adjust() -> void:
	var v := _make()
	var data := _default_data()
	data["staff_rows"] = [
		{"role": &"ml_eng", "label": "ml_eng", "pool": 4, "busy": 2, "per_week": 2_000},
	]
	v.refresh(data)
	await get_tree().process_frame
	watch_signals(v)
	v.click_staff_plus_for_test(&"ml_eng")
	assert_signal_emitted_with_parameters(v, "staff_adjust", [&"ml_eng", 1])

func test_staff_minus_button_disabled_when_all_busy() -> void:
	# pool <= busy 时 -1 按钮 disabled。
	var v := _make()
	var data := _default_data()
	data["staff_rows"] = [
		{"role": &"ml_eng", "label": "ml_eng", "pool": 2, "busy": 2, "per_week": 2_000},
	]
	v.refresh(data)
	await get_tree().process_frame
	assert_true(v.is_staff_minus_disabled_for_test(&"ml_eng"))

# ─── 周工资合计 ─────────────────────────────────────────────

func test_weekly_total_label_renders() -> void:
	var v := _make()
	var data := _default_data()
	data["weekly_totals"] = {"lead": 5_000, "staff": 8_000, "total": 13_000}
	v.refresh(data)
	await get_tree().process_frame
	var labels: PackedStringArray = v.all_label_texts_for_test()
	var has_total := false
	for t in labels:
		if String(t).find("本周总工资") != -1:
			has_total = true
	assert_true(has_total, "周工资合计行应当含 '本周总工资'")

# ─── 行收紧: +1/-1 紧跟信息, 不被推到屏幕另一端 (design §9) ───

func test_staff_row_keeps_buttons_close_to_info() -> void:
	var v := _make()
	var data := _default_data()
	data["staff_rows"] = [
		{"role": &"ml_eng", "label": "ml_eng", "pool": 4, "busy": 2, "per_week": 2_000},
	]
	v.refresh(data)
	await get_tree().process_frame
	var info: Label = v.get_staff_info_for_test(&"ml_eng")
	assert_not_null(info, "应能取到员工行信息列")
	assert_ne(info.size_flags_horizontal, Control.SIZE_EXPAND_FILL,
		"信息列不应 EXPAND_FILL, 否则 +1/-1 被推到行尾远离信息")
	var row: HBoxContainer = v.get_staff_row_for_test(&"ml_eng")
	assert_not_null(row, "应能取到员工行容器")
	assert_eq(row.size_flags_horizontal, Control.SIZE_SHRINK_BEGIN,
		"员工行应收紧到内容宽并左对齐, 不铺满整屏")
