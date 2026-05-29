extends GutTest

## TechView 单测 — §10 step 6 (科技 tab)。

const TechViewScene := preload("res://scenes/ui/views/tech_view/tech_view.tscn")

func _make() -> Control:
	var v: Control = TechViewScene.instantiate()
	add_child_autofree(v)
	return v

func _node_info(id: StringName, display: String, summary: String, state: StringName, weeks: int = 24, cost: int = 0, prereqs: Array = []) -> Dictionary:
	return {
		"id": id,
		"display_name": display,
		"effects_summary": summary,
		"state": state,  # &"unlocked" / &"researching" / &"available" / &"locked"
		"research_months": weeks,
		"research_cost": cost,
		"prerequisites": prereqs,
		"researching_task_id": &"",
	}

func _default_data() -> Dictionary:
	return {
		"trees": [
			{"tree": &"arch", "display": "arch", "nodes": []},
			{"tree": &"engineering", "display": "engineering", "nodes": []},
		],
	}

func test_empty_trees_render_section_headers() -> void:
	var v := _make()
	v.refresh(_default_data())
	await get_tree().process_frame
	var labels: PackedStringArray = v.all_label_texts_for_test()
	var has_arch := false
	for t in labels:
		if String(t).find("arch") != -1:
			has_arch = true
	assert_true(has_arch, "arch 树 section header 应出现")

func test_unlocked_node_renders_with_checkmark() -> void:
	var v := _make()
	var data := _default_data()
	data["trees"][0]["nodes"] = [_node_info(&"ant_v1", "Ant v1", "训练 +20%", &"unlocked")]
	v.refresh(data)
	await get_tree().process_frame
	var labels: PackedStringArray = v.all_label_texts_for_test()
	var has_check := false
	var has_effect := false
	for t in labels:
		if String(t).find("✓") != -1 and String(t).find("Ant v1") != -1:
			has_check = true
		if String(t).find("训练 +20%") != -1:
			has_effect = true
	assert_true(has_check, "已解锁节点应当带 ✓ 标记")
	assert_true(has_effect, "effects_summary 文案应当显示, 老集成测试要求 '训练 +20%'")

func test_available_node_has_research_button() -> void:
	var v := _make()
	var data := _default_data()
	data["trees"][0]["nodes"] = [_node_info(&"ant_v2", "Ant v2", "训练 +10%", &"available")]
	v.refresh(data)
	await get_tree().process_frame
	var btns: PackedStringArray = v.all_button_texts_for_test()
	var found := false
	for t in btns:
		if String(t).find("研究") != -1:
			found = true
	assert_true(found, "available 节点应有 '研究' 按钮")

func test_researching_node_has_no_research_button() -> void:
	var v := _make()
	var data := _default_data()
	data["trees"][0]["nodes"] = [_node_info(&"x", "X", "训练 +X%", &"researching")]
	v.refresh(data)
	await get_tree().process_frame
	var actions: Array = v.get_card_actions_for_test(&"arch", &"x")
	assert_false(actions.has(&"research"), "researching 节点不应有 research action")

func test_research_button_emits_signal() -> void:
	var v := _make()
	var data := _default_data()
	data["trees"][0]["nodes"] = [_node_info(&"ant_v2", "Ant v2", "训练 +10%", &"available")]
	v.refresh(data)
	await get_tree().process_frame
	watch_signals(v)
	v.click_research_for_test(&"arch", &"ant_v2")
	assert_signal_emitted_with_parameters(v, "research_requested", [&"arch", &"ant_v2"])

func test_locked_node_has_no_research_button() -> void:
	var v := _make()
	var data := _default_data()
	data["trees"][0]["nodes"] = [
		_node_info(&"ant_v1", "Ant v1", "(基线)", &"unlocked"),
		_node_info(&"ant_v3", "Ant v3", "训练 +30%", &"locked", 24, 0, [&"ant_v2"]),
	]
	v.refresh(data)
	await get_tree().process_frame
	var actions: Array = v.get_card_actions_for_test(&"arch", &"ant_v3")
	assert_false(actions.has(&"research"), "locked 节点不应有 research action")

func test_locked_node_renders_grayed_with_lock_marker() -> void:
	var v := _make()
	var data := _default_data()
	data["trees"][0]["nodes"] = [
		_node_info(&"ant_v3", "Ant v3", "训练 +30%", &"locked", 24, 0, [&"ant_v2"]),
	]
	v.refresh(data)
	await get_tree().process_frame
	var labels: PackedStringArray = v.all_label_texts_for_test()
	var has_lock := false
	for t in labels:
		if String(t).find("锁定") != -1 and String(t).find("Ant v3") != -1:
			has_lock = true
		assert_eq(String(t).find("🔒"), -1, "1080p UI 不依赖 emoji 锁图标")
	assert_true(has_lock, "locked 节点应带文字锁定标记")

func test_node_state_introspection() -> void:
	var v := _make()
	var data := _default_data()
	data["trees"][0]["nodes"] = [
		_node_info(&"a", "A", "x", &"unlocked"),
		_node_info(&"b", "B", "x", &"available"),
		_node_info(&"c", "C", "x", &"locked", 24, 0, [&"b"]),
	]
	v.refresh(data)
	await get_tree().process_frame
	assert_eq(v.get_node_state_for_test(&"arch", &"a"), &"unlocked")
	assert_eq(v.get_node_state_for_test(&"arch", &"b"), &"available")
	assert_eq(v.get_node_state_for_test(&"arch", &"c"), &"locked")

func test_tree_summary_counts_render() -> void:
	var v := _make()
	var data := _default_data()
	data["trees"][0]["nodes"] = [
		_node_info(&"a", "A", "x", &"unlocked"),
		_node_info(&"b", "B", "x", &"available"),
		_node_info(&"c", "C", "x", &"researching"),
		_node_info(&"d", "D", "x", &"locked", 24, 0, [&"b"]),
	]
	v.refresh(data)
	await get_tree().process_frame
	var labels: PackedStringArray = v.all_label_texts_for_test()
	assert_true(_labels_contain(labels, "已解锁 1"), "树摘要应显示已解锁计数")
	assert_true(_labels_contain(labels, "可研究 1"), "树摘要应显示可研究计数")
	assert_true(_labels_contain(labels, "研究中 1"), "树摘要应显示研究中计数")
	assert_true(_labels_contain(labels, "锁定 1"), "树摘要应显示锁定计数")

func test_node_status_pills_render() -> void:
	var v := _make()
	var data := _default_data()
	data["trees"][0]["nodes"] = [
		_node_info(&"ant_v2", "Ant v2", "训练 +10%", &"available"),
	]
	v.refresh(data)
	await get_tree().process_frame
	assert_true(_labels_contain(v.all_label_texts_for_test(), "可研究"),
			"available 节点应显示状态胶囊")

func test_locked_node_shows_missing_prerequisite_name() -> void:
	var v := _make()
	var data := _default_data()
	data["trees"][0]["nodes"] = [
		_node_info(&"ant_v2", "Ant v2", "训练 +10%", &"locked"),
		_node_info(&"ant_v3", "Ant v3", "训练 +30%", &"locked", 24, 0, [&"ant_v2"]),
	]
	v.refresh(data)
	await get_tree().process_frame
	assert_true(_labels_contain(v.all_label_texts_for_test(), "需要: Ant v2"),
			"locked 节点应显示缺失前置的玩家可读名称")

func _labels_contain(labels: PackedStringArray, needle: String) -> bool:
	for t in labels:
		if String(t).find(needle) != -1:
			return true
	return false
