extends GutTest

## TasksView 单测 — §10 step 6 (任务 tab)。

const TasksViewScene := preload("res://scenes/ui/views/tasks_view/tasks_view.tscn")
const TasksViewScript := preload("res://scenes/ui/views/tasks_view/tasks_view.gd")

var _saved_locale: String

func before_each() -> void:
	_saved_locale = TranslationServer.get_locale()
	GameState.leads.clear()

func after_each() -> void:
	# 切 locale 不还原会让顺序相关用例 flaky (见 i18n-tests-pin-zh-locale)。
	TranslationServer.set_locale(_saved_locale)

func _make() -> Control:
	var v: Control = TasksViewScene.instantiate()
	add_child_autofree(v)
	return v

func _add_lead(id: StringName, display_name: String) -> void:
	var lead := Lead.new()
	lead.id = id
	lead.display_name = display_name
	GameState.leads.append(lead)

func _task(id: StringName, subtype: StringName, elapsed: int = 1, total: int = 4) -> TaskInstance:
	var t := TaskInstance.new()
	t.id = id
	t.subtype = subtype
	t.template_id = &"some_template"
	t.elapsed_weeks = elapsed
	t.total_weeks = total
	return t

func test_empty_shows_hint() -> void:
	# U-11: 空状态用 EmptyState 组件 (icon ▸ + 标题 + 提示行), 不再是裸 Label。
	var v := _make()
	v.refresh([])
	await get_tree().process_frame
	var labels: PackedStringArray = v.all_label_texts_for_test()
	var found := false
	for t in labels:
		if String(t).find("暂无进行中") != -1:
			found = true
	assert_true(found, "空状态应包含'暂无进行中'标题, 实际 labels: %s" % str(labels))

func test_empty_state_uses_component_with_glyph_icon() -> void:
	# U-11: 验证 EmptyState 组件而非旧的纯文字 hint。
	var v := _make()
	v.refresh([])
	await get_tree().process_frame
	assert_true(v._empty_state.visible)
	assert_eq(v._empty_state.get_icon_glyph(), "▸")
	assert_true(v._empty_state.get_hint_text().find("模型") != -1,
			"hint 应引导玩家去模型/数据/科技 tab, 实际: %s" % v._empty_state.get_hint_text())

func test_renders_one_card_per_task() -> void:
	var v := _make()
	v.refresh([_task(&"t1", &"pretrain"), _task(&"t2", &"evaluate")])
	await get_tree().process_frame
	assert_eq(v.get_card_count(), 2)

func test_charity_and_simulation_subtypes_translate_in_zh() -> void:
	TranslationServer.set_locale("zh_CN")
	var v := _make()
	v.refresh([_task(&"t_charity", &"charity"), _task(&"t_sim", &"simulation")])
	await get_tree().process_frame
	assert_eq(v._cards_by_id[&"t_charity"].get_title_text(), "公益捐助")
	assert_eq(v._cards_by_id[&"t_sim"].get_title_text(), "宇宙模拟")

func test_charity_and_simulation_subtypes_translate_in_en() -> void:
	TranslationServer.set_locale("en")
	var v := _make()
	v.refresh([_task(&"t_charity", &"charity"), _task(&"t_sim", &"simulation")])
	await get_tree().process_frame
	assert_eq(v._cards_by_id[&"t_charity"].get_title_text(), "Philanthropy donation")
	assert_eq(v._cards_by_id[&"t_sim"].get_title_text(), "Universe simulation")

func test_card_has_cancel_action() -> void:
	var v := _make()
	v.refresh([_task(&"t1", &"pretrain")])
	await get_tree().process_frame
	var actions: Array = v.get_card_actions_for_test(&"t1")
	assert_true(actions.has(&"cancel"))

func test_no_launcher_buttons() -> void:
	# 老集成测试 test_tasks_tab_has_no_launch_section: 不能有 启动预训练/训练新模型/数据采集/后训练。
	var v := _make()
	v.refresh([_task(&"t1", &"pretrain")])
	await get_tree().process_frame
	var btns: PackedStringArray = v.all_button_texts_for_test()
	for s in btns:
		var st := String(s)
		assert_false(st.find("启动预训练") != -1, "不应有 '启动预训练' 按钮: %s" % st)
		assert_false(st.find("训练新模型") != -1)
		assert_false(st.find("数据采集") != -1)
		assert_false(st.find("后训练") != -1)

func test_cancel_action_emits_signal() -> void:
	var v := _make()
	v.refresh([_task(&"t1", &"pretrain")])
	await get_tree().process_frame
	watch_signals(v)
	v.click_card_action_for_test(&"t1", &"cancel")
	assert_signal_emitted_with_parameters(v, "task_action", [&"t1", &"cancel"])

func test_progress_shown() -> void:
	var v := _make()
	v.refresh([_task(&"t1", &"pretrain", 2, 5)])
	await get_tree().process_frame
	var fields: Dictionary = v.get_card_fields_for_test(&"t1")
	# 至少含进度字段。
	var has_progress := false
	for vs in fields.values():
		if String(vs).find("2") != -1 and String(vs).find("5") != -1:
			has_progress = true
	assert_true(has_progress, "进度字段应当显示 2/5 或类似; 实际: %s" % str(fields))

# ─── lead 真名解析 (bug: Lead 字段显示内部 id "player_self") ───────────

func test_lead_field_shows_real_name_not_internal_id() -> void:
	TranslationServer.set_locale("zh_CN")
	_add_lead(&"player_self", "王伟")
	var v := _make()
	var t := _task(&"t1", &"pretrain")
	t.locked_lead_ids.append(&"player_self")
	v.refresh([t])
	await get_tree().process_frame
	var joined := str(v.get_card_fields_for_test(&"t1").values())
	assert_true(joined.contains("王伟"), "Lead 字段应显示真名, 实际: %s" % joined)
	assert_false(joined.contains("player_self"), "不应泄露内部 id, 实际: %s" % joined)

func test_lead_names_resolves_player_self() -> void:
	TranslationServer.set_locale("zh_CN")
	_add_lead(&"player_self", "王伟")
	assert_eq(TasksViewScript._lead_names([&"player_self"]), "王伟")

func test_lead_names_joins_multiple() -> void:
	TranslationServer.set_locale("zh_CN")
	_add_lead(&"player_self", "王伟")
	_add_lead(&"lead_0001", "李娜")
	assert_eq(TasksViewScript._lead_names([&"player_self", &"lead_0001"]), "王伟, 李娜")

func test_lead_names_romanizes_in_non_zh_locale() -> void:
	TranslationServer.set_locale("en")
	_add_lead(&"player_self", "王伟")
	assert_eq(TasksViewScript._lead_names([&"player_self"]), "Wang Wei")

func test_lead_names_unknown_id_falls_back_to_id() -> void:
	assert_eq(TasksViewScript._lead_names([&"ghost_lead"]), "ghost_lead")
