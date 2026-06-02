extends GutTest

## InfraView 单测 — §10 step 6 第二批扩展 (基建)。
##
## View 只接 data dict (调用方已把 facility/gpu/power 的 display_name 翻好),
## 不访问 GameState / InfraSystem。

const InfraViewScene := preload("res://scenes/ui/views/infra_view/infra_view.tscn")

func _make() -> Control:
	var v: Control = InfraViewScene.instantiate()
	add_child_autofree(v)
	return v

func _dc(id: StringName, display_name: String, status: StringName = &"idle",
		ownership: StringName = &"rented") -> Datacenter:
	var d := Datacenter.new()
	d.id = id
	d.display_name = display_name
	d.facility_spec_id = &"facility_solo"
	d.gpu_id = &"cypress_t0"
	d.gpu_count = 1
	d.max_gpu_count = 1
	d.train_tflops = 12.0
	d.inference_tflops = 8.0
	d.facility_weekly_cost = 5_000
	d.status = status
	d.ownership = ownership
	d.power_supply = &"grid"
	return d

func _default_data() -> Dictionary:
	return {
		"datacenters": [],
		"facility_labels": {&"facility_solo": "单卡桌面"},
		"gpu_labels":      {&"cypress_t0": "Cypress T0"},
		"power_labels":    {&"grid": "电网"},
		"construction_queue": [],
	}

# ─── 创建入口 ────────────────────────────────────────────────

func test_new_dc_button_renders_in_header() -> void:
	var v := _make()
	v.refresh(_default_data())
	await get_tree().process_frame
	var btns: PackedStringArray = v.all_button_texts_for_test()
	var found := false
	for t in btns:
		if String(t).find("新建数据中心") != -1:
			found = true
	assert_true(found, "应当有 '新建数据中心' 按钮, 实际: %s" % str(btns))

func test_new_dc_button_click_emits_signal() -> void:
	var v := _make()
	v.refresh(_default_data())
	await get_tree().process_frame
	watch_signals(v)
	v.click_new_dc_for_test()
	await get_tree().process_frame
	assert_signal_emitted(v, "new_dc_pressed")

# ─── 建筑图标头像 (图片素材生成流程.md §8) ──────────────────

func test_card_avatar_shows_facility_icon() -> void:
	var v := _make()
	var data := _default_data()
	data["datacenters"] = [_dc(&"dc1", "DC One")]   # facility_spec_id = facility_solo
	data["facility_icons"] = {&"facility_solo": "res://assets/sprites/ui/infra/facility-solo.png"}
	v.refresh(data)
	await get_tree().process_frame
	assert_true(v.is_card_avatar_texture_visible_for_test(&"dc1"),
		"配了 facility_icons 时卡片头像应走贴图层")

func test_card_avatar_falls_back_without_icon() -> void:
	var v := _make()
	var data := _default_data()
	data["datacenters"] = [_dc(&"dc1", "DC One")]
	# 不提供 facility_icons → 回退 seed/glyph, 不走贴图。
	v.refresh(data)
	await get_tree().process_frame
	assert_false(v.is_card_avatar_texture_visible_for_test(&"dc1"),
		"无 facility_icons 时卡片头像应回退, 不走贴图")

# ─── 空状态 ─────────────────────────────────────────────────

func test_no_datacenters_shows_empty_hint() -> void:
	var v := _make()
	v.refresh(_default_data())
	await get_tree().process_frame
	var labels: PackedStringArray = v.all_label_texts_for_test()
	var found := false
	for t in labels:
		if String(t).find("还没有机房") != -1:
			found = true
	assert_true(found, "无 dc 时显示提示")

# ─── DC 卡片 ────────────────────────────────────────────────

func test_renders_one_card_per_dc() -> void:
	var v := _make()
	var data := _default_data()
	data["datacenters"] = [_dc(&"dc1", "alpha"), _dc(&"dc2", "beta")]
	v.refresh(data)
	await get_tree().process_frame
	assert_eq(v.get_card_count(), 2)

func test_card_subtitle_contains_facility_and_gpu_display_names() -> void:
	# 老集成测试要求 "单卡桌面" 与 "Cypress T0" 出现在 infra tab 子树。
	var v := _make()
	var data := _default_data()
	data["datacenters"] = [_dc(&"dc1", "alpha")]
	v.refresh(data)
	await get_tree().process_frame
	var labels: PackedStringArray = v.all_label_texts_for_test()
	var has_facility := false
	var has_gpu := false
	for t in labels:
		if String(t).find("单卡桌面") != -1:
			has_facility = true
		if String(t).find("Cypress T0") != -1:
			has_gpu = true
	assert_true(has_facility, "DC 卡片应当含 facility display_name '单卡桌面'")
	assert_true(has_gpu, "DC 卡片应当含 GPU display_name 'Cypress T0'")

func test_idle_dc_has_deploy_and_terminate_actions() -> void:
	var v := _make()
	var data := _default_data()
	data["datacenters"] = [_dc(&"dc1", "alpha", &"idle")]
	v.refresh(data)
	await get_tree().process_frame
	var actions: Array = v.get_card_actions_for_test(&"dc1")
	assert_true(actions.has(&"deploy"), "idle DC 应当含 deploy action")
	assert_true(actions.has(&"terminate"), "idle DC 应当含 terminate action")

func test_serving_dc_has_undeploy_action() -> void:
	var v := _make()
	var data := _default_data()
	data["datacenters"] = [_dc(&"dc1", "alpha", &"serving")]
	v.refresh(data)
	await get_tree().process_frame
	var actions: Array = v.get_card_actions_for_test(&"dc1")
	assert_true(actions.has(&"undeploy"), "serving DC 应当含 undeploy action")
	assert_false(actions.has(&"deploy"), "serving DC 不能再 deploy")

func test_training_dc_has_no_actions() -> void:
	var v := _make()
	var data := _default_data()
	data["datacenters"] = [_dc(&"dc1", "alpha", &"training")]
	v.refresh(data)
	await get_tree().process_frame
	var actions: Array = v.get_card_actions_for_test(&"dc1")
	assert_eq(actions.size(), 0,
		"training DC 不能操作 (任务进行中), 实际 actions: %s" % str(actions))

func test_card_action_click_emits_dc_action_signal() -> void:
	var v := _make()
	var data := _default_data()
	data["datacenters"] = [_dc(&"dc1", "alpha", &"idle")]
	v.refresh(data)
	await get_tree().process_frame
	watch_signals(v)
	v.click_card_action_for_test(&"dc1", &"deploy")
	await get_tree().process_frame
	assert_signal_emitted_with_parameters(v, "dc_action", [&"dc1", &"deploy"])

# ─── 自建队列 ────────────────────────────────────────────────

func test_empty_construction_queue_no_section() -> void:
	var v := _make()
	v.refresh(_default_data())
	await get_tree().process_frame
	var labels: PackedStringArray = v.all_label_texts_for_test()
	var found := false
	for t in labels:
		if String(t).find("自建中") != -1:
			found = true
	assert_false(found, "空队列时 '自建中' section 不显示")

func test_construction_queue_renders_rows() -> void:
	var v := _make()
	var data := _default_data()
	data["construction_queue"] = [
		{"id": &"build1", "facility_label": "单卡桌面", "months_remaining": 2, "total_months": 4},
	]
	v.refresh(data)
	await get_tree().process_frame
	var labels: PackedStringArray = v.all_label_texts_for_test()
	var found_section := false
	var found_row := false
	for t in labels:
		if String(t).find("自建中") != -1:
			found_section = true
		if String(t).find("2 / 4") != -1 or String(t).find("剩余 2") != -1:
			found_row = true
	assert_true(found_section, "有队列时显示 '自建中' section")
	assert_true(found_row, "队列行显示进度")

func test_construction_queue_renders_visual_cards_with_progress() -> void:
	var v := _make()
	var data := _default_data()
	data["construction_queue"] = [
		{
			"id": &"build1",
			"facility_label": "单卡桌面",
			"facility_icon": "res://assets/sprites/ui/infra/facility-solo.png",
			"power_label": "电网",
			"gpu_label": "Cypress T0",
			"weeks_remaining": 2,
			"total_weeks": 4,
		},
	]
	v.refresh(data)
	await get_tree().process_frame
	assert_eq(v.get_construction_card_count_for_test(), 1, "自建队列应渲染为视觉卡片")
	assert_true(v.is_construction_avatar_texture_visible_for_test(&"build1"),
		"自建卡片应复用机房建筑图标")
	assert_eq(v.get_construction_progress_value_for_test(&"build1"), 50,
		"2/4 周剩余意味着完成 50%")
	var fields: Dictionary = v.get_construction_fields_for_test(&"build1")
	assert_eq(String(fields.get("供电", "")), "电网")
	assert_eq(String(fields.get("预装 GPU", "")), "Cypress T0")
	assert_eq(String(fields.get("工期", "")), "剩余 2 / 4 周")

# ─── card 字段 ──────────────────────────────────────────────

func test_idle_dc_card_shows_capacity_and_cost() -> void:
	var v := _make()
	var data := _default_data()
	var dc := _dc(&"dc1", "alpha", &"idle")
	dc.gpu_count = 2
	dc.max_gpu_count = 4
	data["datacenters"] = [dc]
	v.refresh(data)
	await get_tree().process_frame
	var fields: Dictionary = v.get_card_fields_for_test(&"dc1")
	# 至少有 容量 / 周成本 字段。
	assert_true(fields.has("容量") or fields.has("GPU"),
		"DC 卡片应当含容量字段, 实际: %s" % str(fields))

func test_dc_card_shows_gpu_power_and_capacity_fields() -> void:
	# 信息不再塞进会被截断的副标题: GPU 型号×卡数 / 供电 / 容量 都各占字段行。
	var v := _make()
	var data := _default_data()
	var dc := _dc(&"dc1", "alpha", &"idle")
	dc.gpu_count = 2
	dc.max_gpu_count = 4
	data["datacenters"] = [dc]
	v.refresh(data)
	await get_tree().process_frame
	var fields: Dictionary = v.get_card_fields_for_test(&"dc1")
	assert_true(fields.has("GPU"), "应有 GPU 字段, 实际: %s" % str(fields))
	assert_string_contains(String(fields.get("GPU", "")), "Cypress T0")
	assert_string_contains(String(fields.get("GPU", "")), "2")
	assert_true(fields.has("供电"), "应有供电字段, 实际: %s" % str(fields))
	assert_eq(String(fields.get("容量", "")), "2 / 4 GPU")

func test_space_dc_card_shows_train_bonus_field() -> void:
	# 太空 DC 卡片多一行「太空加成 +N%」(由 facility_train_bonuses 提供)。
	var v := _make()
	var data := _default_data()
	var dc := _dc(&"sp", "space-dc", &"idle")
	dc.facility_spec_id = &"facility_space_s"
	data["datacenters"] = [dc]
	data["facility_labels"] = {&"facility_space_s": "6M 卡太空 (S)"}
	data["facility_train_bonuses"] = {&"facility_space_s": 0.10}
	v.refresh(data)
	await get_tree().process_frame
	var fields: Dictionary = v.get_card_fields_for_test(&"sp")
	assert_true(fields.has("太空加成"), "太空 DC 卡片应含训练加成字段, 实际: %s" % str(fields))
	assert_string_contains(String(fields.get("太空加成", "")), "10%")

func test_non_space_dc_card_has_no_train_bonus_field() -> void:
	# 地面 DC (无 bonus 或未提供) 不显示太空加成行。
	var v := _make()
	var data := _default_data()
	data["datacenters"] = [_dc(&"dc1", "alpha")]  # facility_solo, 无加成
	v.refresh(data)
	await get_tree().process_frame
	var fields: Dictionary = v.get_card_fields_for_test(&"dc1")
	assert_false(fields.has("太空加成"), "非太空 DC 不应有训练加成字段, 实际: %s" % str(fields))

func test_dc_card_subtitle_shows_ownership() -> void:
	# 副标题含 租用/自建 而非把 GPU 信息塞进去。
	var v := _make()
	var data := _default_data()
	data["datacenters"] = [_dc(&"dc1", "alpha", &"idle", &"owned")]
	v.refresh(data)
	await get_tree().process_frame
	var labels: PackedStringArray = v.all_label_texts_for_test()
	var found := false
	for t in labels:
		if String(t).find("自建") != -1:
			found = true
	assert_true(found, "自建 DC 副标题应含 '自建', 实际 labels: %s" % str(labels))

func test_dc_card_uses_serving_target_display_label() -> void:
	var v := _make()
	var data := _default_data()
	var dc := _dc(&"dc1", "alpha", &"serving")
	dc.serving_target_kind = &"owned_model"
	dc.serving_target_id = &"model_0001"
	dc.deployed_model_id = &"model_0001"
	data["datacenters"] = [dc]
	data["serving_target_labels"] = {&"dc1": "Pine Prime"}
	v.refresh(data)
	await get_tree().process_frame
	var fields: Dictionary = v.get_card_fields_for_test(&"dc1")
	assert_eq(String(fields.get("在跑", "")), "Pine Prime")
	assert_eq(str(fields).find("model_0001"), -1, "DC 卡片不应显示内部 model id")

# ─── 运行状态筛选 ────────────────────────────────────────────

func _status_data() -> Dictionary:
	# 2 空闲 + 1 训练 + 1 推理。
	var data := _default_data()
	data["datacenters"] = [
		_dc(&"i1", "idle-a",  &"idle"),
		_dc(&"i2", "idle-b",  &"idle"),
		_dc(&"t1", "train-a", &"training"),
		_dc(&"s1", "serve-a", &"serving"),
	]
	return data

func test_status_filter_bar_renders_four_pills() -> void:
	var v := _make()
	v.refresh(_status_data())
	await get_tree().process_frame
	assert_eq(v.get_status_filter_pill_count(), 4, "运行状态筛选应有 4 枚 pill")

func test_status_filter_pills_show_datacenter_counts() -> void:
	var v := _make()
	v.refresh(_status_data())
	await get_tree().process_frame
	assert_string_contains(v.get_status_filter_pill_text_for_test(&"all"), "(4)")
	assert_string_contains(v.get_status_filter_pill_text_for_test(&"idle"), "(2)")
	assert_string_contains(v.get_status_filter_pill_text_for_test(&"training"), "(1)")
	assert_string_contains(v.get_status_filter_pill_text_for_test(&"serving"), "(1)")

func test_status_filter_default_all_shows_every_card() -> void:
	var v := _make()
	v.refresh(_status_data())
	await get_tree().process_frame
	assert_eq(v.get_visible_card_count(), 4, "默认 '全部' 显示所有卡片")

func test_status_filter_idle_only_shows_idle_dcs() -> void:
	var v := _make()
	v.refresh(_status_data())
	await get_tree().process_frame
	v.click_status_filter_pill_for_test(&"idle")
	await get_tree().process_frame
	assert_eq(v.get_visible_card_count(), 2, "'空闲' 只显示 2 张空闲卡")
	assert_true(v.is_card_visible_for_test(&"i1"))
	assert_false(v.is_card_visible_for_test(&"t1"), "训练卡应被筛掉")
	assert_false(v.is_card_visible_for_test(&"s1"), "推理卡应被筛掉")

func test_status_filter_serving_only_shows_serving_dcs() -> void:
	var v := _make()
	v.refresh(_status_data())
	await get_tree().process_frame
	v.click_status_filter_pill_for_test(&"serving")
	await get_tree().process_frame
	assert_eq(v.get_visible_card_count(), 1, "'推理中' 只显示 1 张推理卡")
	assert_true(v.is_card_visible_for_test(&"s1"))

func test_status_filter_intersects_with_ownership_filter() -> void:
	# 自建训练 + 租用训练; 选 自建 ∩ 训练中 → 只剩自建训练那张。
	var v := _make()
	var data := _default_data()
	data["datacenters"] = [
		_dc(&"ot", "own-train",  &"training", &"owned"),
		_dc(&"rt", "rent-train", &"training", &"rented"),
		_dc(&"oi", "own-idle",   &"idle",     &"owned"),
	]
	v.refresh(data)
	await get_tree().process_frame
	v.click_filter_pill_for_test(&"owned")
	v.click_status_filter_pill_for_test(&"training")
	await get_tree().process_frame
	assert_eq(v.get_visible_card_count(), 1, "ownership ∩ 运行状态 取交集")
	assert_true(v.is_card_visible_for_test(&"ot"))
	assert_false(v.is_card_visible_for_test(&"rt"), "租用训练不满足交集")
	assert_false(v.is_card_visible_for_test(&"oi"), "自建空闲不满足交集")

# ─── ownership 筛选 ──────────────────────────────────────────

func _mixed_data() -> Dictionary:
	# 2 租用 + 1 自建。
	var data := _default_data()
	data["datacenters"] = [
		_dc(&"r1", "rent-a", &"idle", &"rented"),
		_dc(&"r2", "rent-b", &"idle", &"rented"),
		_dc(&"o1", "own-a",  &"idle", &"owned"),
	]
	return data

func test_filter_bar_renders_ownership_pills() -> void:
	var v := _make()
	v.refresh(_mixed_data())
	await get_tree().process_frame
	# 全部 / 租用 / 自建 三枚 pill。
	assert_eq(v.get_filter_pill_count(), 3, "infra view 应有 3 枚 ownership pill")

func test_filter_pills_show_datacenter_counts() -> void:
	var v := _make()
	v.refresh(_mixed_data())
	await get_tree().process_frame
	assert_string_contains(v.get_filter_pill_text_for_test(&"all"), "(3)")
	assert_string_contains(v.get_filter_pill_text_for_test(&"rented"), "(2)")
	assert_string_contains(v.get_filter_pill_text_for_test(&"owned"), "(1)")

func test_filter_default_all_shows_every_card() -> void:
	var v := _make()
	v.refresh(_mixed_data())
	await get_tree().process_frame
	assert_eq(v.get_visible_card_count(), 3, "默认 '全部' 显示所有卡片")

func test_filter_rented_hides_owned_cards() -> void:
	var v := _make()
	v.refresh(_mixed_data())
	await get_tree().process_frame
	v.click_filter_pill_for_test(&"rented")
	await get_tree().process_frame
	assert_eq(v.get_visible_card_count(), 2, "'租用' 只显示 2 张租用卡")
	assert_true(v.is_card_visible_for_test(&"r1"))
	assert_false(v.is_card_visible_for_test(&"o1"), "自建卡应被筛掉")

func test_filter_owned_hides_rented_cards() -> void:
	var v := _make()
	v.refresh(_mixed_data())
	await get_tree().process_frame
	v.click_filter_pill_for_test(&"owned")
	await get_tree().process_frame
	assert_eq(v.get_visible_card_count(), 1, "'自建' 只显示 1 张自建卡")
	assert_true(v.is_card_visible_for_test(&"o1"))
	assert_false(v.is_card_visible_for_test(&"r1"), "租用卡应被筛掉")

func test_filter_back_to_all_restores_all_cards() -> void:
	var v := _make()
	v.refresh(_mixed_data())
	await get_tree().process_frame
	v.click_filter_pill_for_test(&"owned")
	await get_tree().process_frame
	v.click_filter_pill_for_test(&"all")
	await get_tree().process_frame
	assert_eq(v.get_visible_card_count(), 3, "切回 '全部' 恢复全部卡片")

func test_filter_no_match_shows_hint() -> void:
	# 全是租用, 切到 '自建' → 0 匹配 → 提示文案。
	var v := _make()
	var data := _default_data()
	data["datacenters"] = [_dc(&"r1", "rent-a", &"idle", &"rented")]
	v.refresh(data)
	await get_tree().process_frame
	v.click_filter_pill_for_test(&"owned")
	await get_tree().process_frame
	var labels: PackedStringArray = v.all_label_texts_for_test()
	var found := false
	for t in labels:
		if String(t).find("筛选") != -1:
			found = true
	assert_true(found, "无匹配时显示筛选提示, 实际 labels: %s" % str(labels))

# ─── 卡数量筛选 ──────────────────────────────────────────────

func _dc_sized(id: StringName, gpu_count: int, ownership: StringName = &"rented") -> Datacenter:
	var d := _dc(id, String(id), &"idle", ownership)
	d.gpu_count = gpu_count
	d.max_gpu_count = maxi(gpu_count, 1)
	return d

func _sized_data() -> Dictionary:
	# 3 张不同卡数的 DC: 小 (8 卡) / 中 (500 卡) / 大 (16000 卡)。
	var data := _default_data()
	data["datacenters"] = [
		_dc_sized(&"s1", 8),
		_dc_sized(&"m1", 500),
		_dc_sized(&"l1", 16000),
	]
	return data

func test_size_filter_bar_renders_four_pills() -> void:
	var v := _make()
	v.refresh(_sized_data())
	await get_tree().process_frame
	assert_eq(v.get_size_filter_pill_count(), 4, "卡数量筛选应有 4 枚 pill")

func test_size_filter_pills_show_datacenter_counts() -> void:
	var v := _make()
	v.refresh(_sized_data())
	await get_tree().process_frame
	assert_string_contains(v.get_size_filter_pill_text_for_test(&"all"), "(3)")
	assert_string_contains(v.get_size_filter_pill_text_for_test(&"small"), "(1)")
	assert_string_contains(v.get_size_filter_pill_text_for_test(&"mid"), "(1)")
	assert_string_contains(v.get_size_filter_pill_text_for_test(&"large"), "(1)")

func test_size_filter_default_all_shows_every_card() -> void:
	var v := _make()
	v.refresh(_sized_data())
	await get_tree().process_frame
	assert_eq(v.get_visible_card_count(), 3, "默认 '全部' 显示所有卡片")

func test_size_filter_small_only_shows_small_dcs() -> void:
	var v := _make()
	v.refresh(_sized_data())
	await get_tree().process_frame
	v.click_size_filter_pill_for_test(&"small")
	await get_tree().process_frame
	assert_eq(v.get_visible_card_count(), 1, "'≤72 卡' 只显示 1 张小型 DC")
	assert_true(v.is_card_visible_for_test(&"s1"))
	assert_false(v.is_card_visible_for_test(&"l1"), "大型 DC 应被筛掉")

func test_size_filter_large_only_shows_large_dcs() -> void:
	var v := _make()
	v.refresh(_sized_data())
	await get_tree().process_frame
	v.click_size_filter_pill_for_test(&"large")
	await get_tree().process_frame
	assert_eq(v.get_visible_card_count(), 1, "'>8k 卡' 只显示 1 张大型 DC")
	assert_true(v.is_card_visible_for_test(&"l1"))

func test_size_filter_boundary_72_is_small() -> void:
	# 阈值边界: 恰好 72 卡归 small, 73 卡归 mid。
	var v := _make()
	var data := _default_data()
	data["datacenters"] = [_dc_sized(&"b72", 72), _dc_sized(&"b73", 73)]
	v.refresh(data)
	await get_tree().process_frame
	v.click_size_filter_pill_for_test(&"small")
	await get_tree().process_frame
	assert_true(v.is_card_visible_for_test(&"b72"), "72 卡应归 ≤72")
	assert_false(v.is_card_visible_for_test(&"b73"), "73 卡不属于 ≤72")

func test_size_filter_intersects_with_ownership_filter() -> void:
	# 自建大型 + 租用小型; 选 自建 ∩ 大型 → 只剩自建大型那张。
	var v := _make()
	var data := _default_data()
	data["datacenters"] = [
		_dc_sized(&"ol", 16000, &"owned"),
		_dc_sized(&"rs", 8, &"rented"),
	]
	v.refresh(data)
	await get_tree().process_frame
	v.click_filter_pill_for_test(&"owned")
	v.click_size_filter_pill_for_test(&"large")
	await get_tree().process_frame
	assert_eq(v.get_visible_card_count(), 1, "ownership ∩ 卡数量 取交集")
	assert_true(v.is_card_visible_for_test(&"ol"))
	assert_false(v.is_card_visible_for_test(&"rs"), "租用小型不满足交集")
