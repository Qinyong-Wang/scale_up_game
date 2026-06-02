extends GutTest

## PretrainDialog instantiation + happy-path smoke. Per design/任务系统设计.md §5.1.1.
## We don't simulate clicks — that's hard in headless GUT — but we do verify:
##   - the script parses and instantiates
##   - refresh() reads GameState slices without crashing
##   - _build_payload() produces a payload that task.start accepts
##   - the start signal fires when launched programmatically

const PretrainDialog := preload("res://scenes/ui/pretrain_dialog/pretrain_dialog.gd")

var _dlg

func before_each() -> void:
	GameState.reset()
	# Per design/招聘系统设计.md §5.4: pretrain_model 现在强制 chief_scientist.
	# 给每个 dialog 测试 seed 一个零能力 chief_scientist, 让填好表单的 happy-path
	# 能通过校验 (而不影响时长计算)。
	_seed_zero_chief_scientist()

func after_each() -> void:
	if _dlg != null:
		_dlg.queue_free()
		_dlg = null

func _seed_zero_chief_scientist() -> StringName:
	var l := Lead.new()
	l.id = &"lead_cs_zero_dlg"
	l.specialty = &"chief_scientist"
	l.level = &"C"
	l.ability = 0.0
	l.signing_fee = 0
	l.weekly_salary = 0
	GameState.leads.append(l)
	return l.id

func _make_dialog():
	_dlg = PretrainDialog.new()
	add_child_autofree(_dlg)
	return _dlg

func test_dialog_instantiates_and_refresh_does_not_crash() -> void:
	var dlg = _make_dialog()
	dlg.refresh()
	# Dialog should expose the new free-form size controls and an arch dropdown.
	assert_true(dlg._arch_dropdown.item_count >= 1)
	assert_not_null(dlg._size_spin)
	assert_not_null(dlg._size_unit_dropdown)
	assert_not_null(dlg._name_input)

func test_dialog_separates_architecture_and_size_controls() -> void:
	# Architecture stays as a dropdown; size becomes free-form SpinBox + M/B
	# selector per design 任务系统设计.md §5.1.1 (revised).
	GameState.unlocks[&"arch"][&"ant_v2"] = true
	var dlg = _make_dialog()
	dlg.refresh()
	assert_not_null(dlg._arch_dropdown)
	assert_not_null(dlg._size_spin)
	assert_not_null(dlg._size_unit_dropdown)
	assert_true(dlg._arch_dropdown.item_count >= 2)
	# Unit dropdown has M & B.
	assert_eq(dlg._size_unit_dropdown.item_count, 2)

func test_size_spin_supports_up_to_100T() -> void:
	# 2026-05: 旧上限 999B 太死, 玩家做到后期需要 100T 量级。SpinBox max 必须
	# 允许 100_000 (B 单位 → 100T)。
	var dlg = _make_dialog()
	dlg.refresh()
	assert_gt(int(dlg._size_spin.max_value), 99_999,
		"size_spin.max_value 应至少能写到 100_000B (100T), 实际: %d"
			% int(dlg._size_spin.max_value))
	dlg._size_spin.value = 100_000.0
	assert_almost_eq(dlg._size_spin.value, 100_000.0, 0.001,
		"赋值 100_000 不应被 clamp, 实际: %.1f" % dlg._size_spin.value)

func test_context_dropdown_formats_unlocked_agent_bonus() -> void:
	# design/任务系统设计.md §4.1.1: context labels use GDScript-supported
	# fixed-decimal formatting, never unsupported "%g".
	GameState.unlocks[&"context"][&"ctx_32k"] = true
	var dlg = _make_dialog()
	dlg.refresh()
	var found := false
	for i in range(dlg._context_dropdown.item_count):
		if int(dlg._context_dropdown.get_item_metadata(i)) != 32768:
			continue
		found = true
		var text: String = dlg._context_dropdown.get_item_text(i)
		assert_true(text.find("agent +2.00") != -1,
			"ctx_32k label should show fixed agent bonus (got: %s)" % text)
		assert_true(text.find("训练 ×1.10") != -1,
			"ctx_32k label should show fixed train penalty (got: %s)" % text)
	assert_true(found, "ctx_32k should appear after unlock")

func test_dialog_has_name_input() -> void:
	var dlg = _make_dialog()
	dlg.refresh()
	assert_not_null(dlg._name_input)
	assert_true(dlg._name_input is LineEdit)

func test_size_unit_b_converts_to_M_in_payload() -> void:
	var dlg = _make_dialog()
	dlg.refresh()
	dlg._name_input.text = "TestModel"
	dlg._size_spin.value = 5
	# select "B" — index 1
	dlg._size_unit_dropdown.select(1)
	var payload: Dictionary = dlg._build_payload()
	assert_eq(int(payload.get(&"size_params", 0.0)), 5000,
		"5 B should serialize to 5000 M in size_params")

func test_size_unit_m_passes_through_in_payload() -> void:
	var dlg = _make_dialog()
	dlg.refresh()
	dlg._name_input.text = "TestModel2"
	dlg._size_spin.value = 800
	dlg._size_unit_dropdown.select(0) # M
	var payload: Dictionary = dlg._build_payload()
	assert_eq(int(payload.get(&"size_params", 0.0)), 800)

func test_empty_name_disables_start_button() -> void:
	var dlg = _make_dialog()
	dlg.refresh()
	dlg._name_input.text = ""
	dlg._refresh_preview()
	assert_true(dlg.get_ok_button().disabled,
		"empty name must disable the start button")
	assert_true(dlg._warning_label.text.find("名字") != -1
		or dlg._warning_label.text.find("命名") != -1,
		"warning should mention naming")

func test_duplicate_name_against_existing_model_disables_start() -> void:
	var m := preload("res://scripts/resources/model.gd").new()
	m.id = &"DupName"
	m.display_name = "DupName"
	m.arch = &"ant_v1"
	GameState.models.append(m)

	var dlg = _make_dialog()
	dlg.refresh()
	dlg._name_input.text = "DupName"
	dlg._refresh_preview()
	assert_true(dlg.get_ok_button().disabled,
		"duplicate name must disable the start button")

func test_started_pretrain_uses_player_name_as_model_id_on_completion() -> void:
	# DC + dataset so scaling_law produces a real (short) duration.
	CommandBus.send(&"dataset.acquire_open", {template_id = &"web_corpus_v1"})
	CommandBus.send(&"infra.debug_instant_owned_dc", {facility_spec_id = &"facility_room", gpu_id = &"cypress_t0"})
	var dlg = _make_dialog()
	dlg.refresh()
	dlg._name_input.text = "Sparrow-Mine"
	dlg._size_spin.value = 100
	dlg._size_unit_dropdown.select(0) # M
	if dlg._dataset_checkboxes.size() > 0:
		dlg._dataset_checkboxes[0].box.button_pressed = true
	dlg._refresh_preview()
	assert_false(dlg.get_ok_button().disabled,
		"start button should be enabled once name+size+dataset are set")
	dlg._on_start_pressed()
	assert_eq(GameState.active_tasks.size(), 1)
	# Run task to completion. Advance up to a generous bound so a stochastic
	# error-rate delay can't break the assertion (template currently 0.0, but
	# stay defensive).
	for _i in range(40):
		if GameState.active_tasks.is_empty():
			break
		TurnManager.advance()
	assert_eq(GameState.active_tasks.size(), 0,
		"pretrain task should have completed")
	assert_eq(GameState.models.size(), 1)
	assert_eq(String(GameState.models[0].id), "Sparrow-Mine",
		"model.id should equal the player-entered name")
	assert_eq(GameState.models[0].display_name, "Sparrow-Mine")

func test_refresh_fills_dc_dropdown_with_idle_dcs_only() -> void:
	# Rent two small DCs, lock one to a task → only the idle one should appear.
	var rdc1: Dictionary = CommandBus.send(&"infra.debug_instant_owned_dc", {facility_spec_id = &"facility_room", gpu_id = &"cypress_t0"})
	var rdc2: Dictionary = CommandBus.send(&"infra.debug_instant_owned_dc", {facility_spec_id = &"facility_room", gpu_id = &"cypress_t0"})
	# Tie up rdc2 with a small pretrain.
	CommandBus.send(&"task.start", {
		template_id = &"train_sparrow_s",
		datacenter_id = rdc2.dc_id,
	})
	var dlg = _make_dialog()
	dlg.refresh()
	# The dc dropdown has "(无)" + idle DCs. So count should be 2 (the idle one).
	assert_eq(dlg._dc_dropdown.item_count, 2,
		"only the idle DC and the (无) placeholder should appear")

func test_space_dc_dropdown_shows_train_bonus_suffix() -> void:
	# 太空数据中心 (space_l +20%) 的下拉选项应带 "太空 +20%" 后缀, 让玩家在
	# 预训练面板直接看到训练加速。见 design/基础设施系统设计.md §4.1。
	CommandBus.send(&"infra.debug_instant_owned_dc",
		{facility_spec_id = &"facility_space_l", gpu_id = &"cypress_t0"})
	var dlg = _make_dialog()
	dlg.refresh()
	var found := false
	for i in range(dlg._dc_dropdown.item_count):
		var t: String = dlg._dc_dropdown.get_item_text(i)
		if t.find("太空") != -1 and t.find("+20%") != -1:
			found = true
	assert_true(found, "太空 DC 下拉项应含 '太空 +20%' 后缀")

func test_refresh_skips_locked_datasets() -> void:
	# Buy a dataset and acquire another, lock one, ensure only the unlocked one
	# shows up as a checkbox.
	CommandBus.send(&"dataset.acquire_open", {template_id = &"web_corpus_v1"})
	CommandBus.send(&"dataset.purchase", {template_id = &"codebase_v1"})
	var rdc: Dictionary = CommandBus.send(&"infra.debug_instant_owned_dc", {facility_spec_id = &"facility_room", gpu_id = &"cypress_t0"})
	# Start a task that locks one dataset (web_corpus_v1).
	CommandBus.send(&"task.start", {
		template_id = &"train_otter_m",
		datacenter_id = rdc.dc_id,
		dataset_ids = [&"web_corpus_v1"],
	})
	var dlg = _make_dialog()
	dlg.refresh()
	assert_eq(dlg._dataset_checkboxes.size(), 1,
		"only the unlocked dataset should be offered")
	assert_eq(StringName(dlg._dataset_checkboxes[0].id), &"codebase_v1")

func test_start_emits_signal_and_creates_active_task() -> void:
	var dlg = _make_dialog()
	dlg.refresh()
	dlg._name_input.text = "SmokeModel"
	dlg._size_spin.value = 100
	dlg._size_unit_dropdown.select(0) # M
	# Trigger the OK handler directly.
	watch_signals(dlg)
	dlg._on_start_pressed()
	assert_signal_emitted(dlg, "task_started_via_dialog")
	assert_eq(GameState.active_tasks.size(), 1)
	assert_eq(GameState.active_tasks[0].subtype, &"pretrain")

# ---- founder fallback (设计 §2 / §5.4 v2026-05) ----------------------------

func test_dialog_uses_founder_when_no_real_chief_scientist() -> void:
	# 把 before_each 里 seed 的零能力 chief_scientist 清掉, 只留创始人。
	# Dialog 应在下拉列出创始人, 默认选中, OK 可点。
	GameState.leads.clear()
	var founder_r: Dictionary = CommandBus.send(&"hiring.create_player_scientist", {})
	assert_true(founder_r.ok)
	# 需要 DC + dataset 才能让 preview 拿到正分 (start 也需要)。
	CommandBus.send(&"dataset.acquire_open", {template_id = &"web_corpus_v1"})
	CommandBus.send(&"infra.debug_instant_owned_dc", {facility_spec_id = &"facility_room", gpu_id = &"cypress_t0"})
	var dlg = _make_dialog()
	dlg.refresh()
	dlg._name_input.text = "FounderRun"
	dlg._size_spin.value = 100
	dlg._size_unit_dropdown.select(0)
	if dlg._dataset_checkboxes.size() > 0:
		dlg._dataset_checkboxes[0].box.button_pressed = true
	dlg._refresh_preview()
	# 下拉至少有 1 项 (创始人), 不应是 "(无 chief_scientist 可用)" 占位。
	assert_gt(dlg._lead_dropdown.item_count, 0)
	var label_text: String = dlg._lead_dropdown.get_item_text(dlg._lead_dropdown.selected)
	assert_true(label_text.find("创始人") != -1,
			"下拉应展示创始人, 实际: %s" % label_text)
	assert_false(dlg.get_ok_button().disabled,
			"创始人在场时 OK 应可点; warning: %s" % dlg._warning_label.text)
	# 真正启动确认 task.start 通过校验 (founder 是 universal lead)。
	watch_signals(dlg)
	dlg._on_start_pressed()
	assert_signal_emitted(dlg, "task_started_via_dialog")
	assert_eq(GameState.active_tasks.size(), 1)

func test_dialog_content_is_in_scroll_container() -> void:
	# Per design §5.1.1 + D-1: 表单走 ScrollContainer 可滚, 预览块在外层固定
	# 底部不滚动。这里只断言存在一个 ScrollContainer (深度搜) + 预览块不在它内部。
	var dlg = _make_dialog()
	var found_scroll: ScrollContainer = _find_first_descendant(dlg, ScrollContainer)
	assert_not_null(found_scroll, "PretrainDialog 必须有 ScrollContainer 包表单")
	# Scroll container 内应当有一个 VBoxContainer 作为 form root。
	var has_vbox := false
	for c in found_scroll.get_children():
		if c is VBoxContainer:
			has_vbox = true
			break
	assert_true(has_vbox, "ScrollContainer 内必须有 VBoxContainer 容纳表单")
	# D-1: 预览 Label 应该在 ScrollContainer 外 (固定底部), 不在表单滚动区域里。
	assert_false(_is_descendant_of(dlg._spec_label, found_scroll),
			"D-1: 预览块 (_spec_label) 应在 ScrollContainer 之外, 保证调整字段时不被卷走")

func test_dialog_uses_panelized_training_surfaces() -> void:
	# design/UI视觉系统设计.md §7.2: 训练类 Dialog 必须是配置 / 预览双面板,
	# 预览内容再按语义分成子面板, 启动按钮使用 create CTA。
	var dlg = _make_dialog()
	dlg.refresh()
	assert_gte(_count_descendants_of_type(dlg, PanelContainer), 4,
			"PretrainDialog 应有左右主面板 + 预览子面板, 不应是裸 Label 堆叠")
	assert_gte(_count_descendants_of_type(dlg, ScrollContainer), 2,
			"配置和预览应各有独立滚动区")
	assert_gte(int(dlg.get_ok_button().custom_minimum_size.y), UITheme.CREATE_BUTTON_H,
			"启动训练按钮应使用 create CTA 高度")
	var normal: StyleBox = dlg.get_ok_button().get_theme_stylebox(&"normal")
	assert_true(normal is StyleBoxFlat, "create CTA normal style 应是 StyleBoxFlat")
	if normal is StyleBoxFlat:
		assert_true((normal as StyleBoxFlat).bg_color.is_equal_approx(UITheme.ACCENT_INFO),
				"启动训练按钮应是实心炭黑 CTA")

func _find_first_descendant(root: Node, type) -> Node:
	for c in root.get_children():
		if is_instance_of(c, type):
			return c
		var found := _find_first_descendant(c, type)
		if found != null:
			return found
	return null

func _is_descendant_of(node: Node, ancestor: Node) -> bool:
	var cur: Node = node
	while cur != null:
		if cur == ancestor:
			return true
		cur = cur.get_parent()
	return false

func _count_descendants_of_type(root: Node, type) -> int:
	var count := 0
	for c in root.get_children():
		if is_instance_of(c, type):
			count += 1
		count += _count_descendants_of_type(c, type)
	return count

func test_dialog_min_size_fits_within_min_viewport() -> void:
	# Per design/任务系统设计.md §5.1.1: 两栏布局后不再用 max_size 截断, 实际
	# 尺寸由 main 的 popup_centered_ratio(0.82) 控制。这里断言 min_size 不超出
	# 最小窗口 (1280×720), 保证窄窗下表单 + OK 按钮仍完整可见。
	# 制造 12 个空闲数据集, 模拟内容溢出场景 (表单走 ScrollContainer 自滚)。
	for i in range(12):
		var ds := Dataset.new()
		ds.id = StringName("synthetic_%d" % i)
		ds.display_name = "Synthetic %d" % i
		ds.source = &"open_source"
		ds.size = 50.0
		ds.quality = 0.5
		GameState.datasets.append(ds)
	var dlg = _make_dialog()
	dlg.refresh()
	assert_true(dlg.min_size.x > 0 and dlg.min_size.x <= 1280,
		"对话框 min_size.x 必须 ≤ 1280 (实际 %d)" % dlg.min_size.x)
	assert_true(dlg.min_size.y > 0 and dlg.min_size.y <= 720,
		"对话框 min_size.y 必须 ≤ 720 (实际 %d), 否则启动按钮会被挤出最小视口" % dlg.min_size.y)

func test_dialog_shows_preview_modifier_breakdown() -> void:
	var l := Lead.new()
	l.id = &"l_cs_100"
	l.display_name = "Chief Seed"
	l.specialty = &"chief_scientist"
	l.level = &"S"
	l.ability = 100.0
	GameState.leads.append(l)
	CommandBus.send(&"dataset.acquire_open", {template_id = &"web_corpus_v1"})
	CommandBus.send(&"infra.debug_instant_owned_dc", {facility_spec_id = &"facility_room", gpu_id = &"cypress_t0"})
	CommandBus.send(&"hiring.adjust_staff", {role = &"ml_eng", delta = 2})
	var dlg = _make_dialog()
	dlg.refresh()
	if dlg._dataset_checkboxes.size() > 0:
		dlg._dataset_checkboxes[0].box.button_pressed = true
	if dlg._lead_dropdown.item_count > 1:
		dlg._lead_dropdown.select(1)
	dlg._ml_eng_spin.value = 2
	dlg._refresh_preview()
	# 训练加速区：包含 Lead 加速条目 + 总计行
	assert_true(dlg._speed_modifier_label.text.find("Lead") != -1,
		"训练加速区应显示 Lead 加速条目")
	assert_true(dlg._speed_total_label.text.find("训练加速总计") != -1,
		"训练加速区应显示总计行")
	# 性能分数区：包含数据质量条目 + 总计行
	assert_true(dlg._score_modifier_label.text.find("数据质量") != -1,
		"性能分数区应显示数据质量条目")
	assert_true(dlg._score_total_label.text.find("性能分数总计") != -1,
		"性能分数区应显示总计行")

func test_preview_returns_predicted_capability_dict() -> void:
	# task.preview should expose a 4-axis predicted_capability dict that
	# matches what _compute_capability_measured would produce for the same
	# inputs (with posttrain_count=0 + eval_lead=null assumptions).
	CommandBus.send(&"dataset.acquire_open", {template_id = &"web_corpus_v1"})
	CommandBus.send(&"infra.debug_instant_owned_dc", {facility_spec_id = &"facility_room", gpu_id = &"cypress_t0"})
	var rdc_id: StringName = GameState.datacenters[0].id
	var preview: Dictionary = CommandBus.send(&"task.preview", {
		template_id = &"pretrain_model",
		size_params = 800.0,
		arch_id = &"ant_v1",
		datacenter_id = rdc_id,
		dataset_ids = [&"web_corpus_v1"],
		display_name = "PreviewModel",
	})
	assert_true(preview.ok)
	assert_true(preview.has(&"predicted_capability"),
		"preview should expose predicted_capability")
	var caps: Dictionary = preview.predicted_capability
	for axis in [&"general", &"code", &"reasoning", &"multimodal"]:
		assert_true(caps.has(axis), "axis %s missing" % String(axis))
		assert_true(float(caps[axis]) >= 0.0, "%s should be non-negative" % String(axis))
	# General axis should be positive (we have a dataset + non-trivial size).
	assert_gt(float(caps.get(&"general", 0.0)), 0.0)
	# multimodal should be 0 because no image modality is requested by default.
	assert_eq(float(caps.get(&"multimodal", -1.0)), 0.0)

func test_dialog_renders_predicted_capability_block() -> void:
	# PretrainDialog should surface predicted_capability via a 4-line block
	# under the score-modifier section.
	CommandBus.send(&"dataset.acquire_open", {template_id = &"web_corpus_v1"})
	CommandBus.send(&"infra.debug_instant_owned_dc", {facility_spec_id = &"facility_room", gpu_id = &"cypress_t0"})
	var dlg = _make_dialog()
	dlg.refresh()
	dlg._name_input.text = "Forecast"
	dlg._size_spin.value = 800
	dlg._size_unit_dropdown.select(0)
	if dlg._dataset_checkboxes.size() > 0:
		dlg._dataset_checkboxes[0].box.button_pressed = true
	dlg._refresh_preview()
	assert_not_null(dlg._capability_label,
		"dialog should hold a _capability_label for predicted capability")
	var text: String = dlg._capability_label.text
	# 能力轴现在显示翻译后的标签 (CAP_*), 不再是 raw id; 用 tr 取当前 locale 的标签断言。
	for key in ["CAP_GENERAL", "CAP_CODE", "CAP_REASONING", "CAP_MULTIMODAL"]:
		var axis_label: String = tr(key)
		assert_true(text.findn(axis_label) != -1,
			"predicted capability text should mention %s (got: %s)" % [axis_label, text])

func test_dc_with_no_gpus_shows_no_gpu_label_in_dropdown() -> void:
	# rent_facility creates a DC immediately but with 0 GPUs — GPU must be purchased
	# separately. The dropdown should label it "无GPU" not "训0".
	var r: Dictionary = CommandBus.send(&"infra.rent_facility", {
		facility_spec_id = &"facility_pod", power_supply_id = &"grid"})
	assert_true(r.ok, "rent_facility pod should succeed")
	var dlg = _make_dialog()
	dlg.refresh()
	var found_no_gpu := false
	for i in range(dlg._dc_dropdown.item_count):
		if dlg._dc_dropdown.get_item_text(i).find("无GPU") != -1:
			found_no_gpu = true
			break
	assert_true(found_no_gpu, "DC with 0 GPUs should display '无GPU' in dropdown (not '训0')")

func test_dc_with_no_gpus_disables_start_with_helpful_warning() -> void:
	# A DC that completed construction with 0 GPUs must not allow training to start.
	# The dialog should show a clear "购买 GPU" hint before the user even clicks start.
	var r: Dictionary = CommandBus.send(&"infra.rent_facility", {
		facility_spec_id = &"facility_pod", power_supply_id = &"grid"})
	assert_true(r.ok, "rent_facility pod should succeed")
	CommandBus.send(&"dataset.acquire_open", {template_id = &"web_corpus_v1"})
	var dlg = _make_dialog()
	dlg.refresh()
	# Select the no-GPU DC in the dropdown
	for i in range(dlg._dc_dropdown.item_count):
		if dlg._dc_dropdown.get_item_text(i).find("无GPU") != -1:
			dlg._dc_dropdown.select(i)
			break
	dlg._name_input.text = "ZeroGpuModel"
	dlg._size_spin.value = 100
	dlg._size_unit_dropdown.select(0)
	if dlg._dataset_checkboxes.size() > 0:
		dlg._dataset_checkboxes[0].box.button_pressed = true
	dlg._refresh_preview()
	assert_true(dlg.get_ok_button().disabled,
		"start button must be disabled when DC has 0 GPUs")
	assert_true(dlg._warning_label.text.find("无算力") != -1,
		"warning label must mention '无算力' so the player knows to buy GPUs (got: %s)" \
		% dlg._warning_label.text)

func test_modifier_sections_show_separately_without_cross_contamination() -> void:
	# Lead 加速不应出现在性能分数区；数据质量不应出现在训练加速区。
	var l := Lead.new()
	l.id = &"l_cs_80"
	l.display_name = "Fast Chief"
	l.specialty = &"chief_scientist"
	l.level = &"A"
	l.ability = 80.0
	GameState.leads.append(l)
	CommandBus.send(&"dataset.acquire_open", {template_id = &"web_corpus_v1"})
	CommandBus.send(&"infra.debug_instant_owned_dc", {facility_spec_id = &"facility_room", gpu_id = &"cypress_t0"})
	var dlg = _make_dialog()
	dlg.refresh()
	if dlg._dataset_checkboxes.size() > 0:
		dlg._dataset_checkboxes[0].box.button_pressed = true
	if dlg._lead_dropdown.item_count > 1:
		dlg._lead_dropdown.select(1)
	dlg._refresh_preview()
	assert_true(dlg._score_modifier_label.text.find("Lead") == -1,
		"Lead 加速不应出现在性能分数区")
	assert_true(dlg._speed_modifier_label.text.find("数据质量") == -1,
		"数据质量不应出现在训练加速区")

# ---- v8 PR-I 定价预览 (design/研究系统设计.md §4.8) -----------------------

func test_preview_shows_inference_cost_and_guidance_labels() -> void:
	var dlg = _make_dialog()
	dlg.refresh()
	dlg._name_input.text = "PriceCheck"
	dlg._size_spin.value = 100
	dlg._size_unit_dropdown.select(0) # M
	dlg._refresh_preview()
	# 推理成本 + 指导价 (开源 / 闭源) 应在 pricing label 中.
	var text: String = dlg._pricing_label.text
	assert_true(text.find("推理成本") != -1,
			"PretrainDialog 预览块应显示推理成本, 实际: %s" % text)
	assert_true(text.find("开源") != -1 and text.find("闭源") != -1,
			"指导价应同时显示开源与闭源两档, 实际: %s" % text)

func test_preview_pricing_grows_with_size() -> void:
	# size 100M → 1000M (10×) → flops_per_token 10× → 价格随动 10×。
	# 简单检验 pricing 文本因 size 变化而变化 (不要求精确数值, 留给单测覆盖)。
	var dlg = _make_dialog()
	dlg.refresh()
	dlg._name_input.text = "PriceScale"
	dlg._size_spin.value = 100
	dlg._size_unit_dropdown.select(0)
	dlg._refresh_preview()
	var small_text: String = dlg._pricing_label.text
	dlg._size_spin.value = 1000
	dlg._refresh_preview()
	var large_text: String = dlg._pricing_label.text
	assert_ne(small_text, large_text,
			"size 变化时 pricing 文本应随之改变 (small=%s, large=%s)"
				% [small_text, large_text])
