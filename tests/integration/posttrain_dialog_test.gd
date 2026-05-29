extends GutTest

## PosttrainDialog v2 — multi-select posttrain datasets, capability delta
## preview, dc gpu validation. Per design/研究系统设计.md §5.3 (v2).

const PosttrainDialog := preload("res://scenes/ui/posttrain_dialog/posttrain_dialog.gd")

var _dlg = null

func before_each() -> void:
	GameState.reset()
	# Per design/招聘系统设计.md §5.4: posttrain_model 强制 ml_research_lead.
	# 给 happy-path 测试 seed 一个零能力 ml_research_lead.
	_seed_zero_ml_research_lead()

func _seed_zero_ml_research_lead() -> StringName:
	var l := Lead.new()
	l.id = &"lead_ml_zero_pt_dlg"
	l.specialty = &"ml_research_lead"
	l.level = &"C"
	l.ability = 0.0
	l.signing_fee = 0
	l.weekly_salary = 0
	GameState.leads.append(l)
	return l.id

func after_each() -> void:
	if _dlg != null and is_instance_valid(_dlg):
		_dlg.queue_free()
		_dlg = null

func _make_dialog(base_model_id: StringName):
	var d = PosttrainDialog.new()
	d.set_base_model_id(base_model_id)
	add_child_autofree(d)
	_dlg = d
	return d

func _seed_evaluated_model(size_m: float = 800.0) -> StringName:
	var r: Dictionary = CommandBus.send(&"research.add_model", {
		capability = {}, arch = &"ant_v1",
		size_params = size_m, dataset_ids = [], display_name = "M_pt"})
	var m = ResearchSystem.find_model(r.model_id)
	m.capability = {
		&"general": 50.0, &"code": 30.0, &"reasoning": 30.0,
		&"multimodal": 0.0, &"agent": 0.0,
	}
	m.capability_revealed = true
	m.status = &"evaluated"
	return r.model_id

func _seed_posttrain_ds(id: StringName, axis: StringName, quality: float,
		size_b: float = 0.05) -> StringName:
	var ds := Dataset.new()
	ds.id = id
	ds.kind = &"posttrain"
	ds.source = &"purchased"
	ds.size = size_b
	ds.quality = quality
	ds.target_capability = axis
	GameState.datasets.append(ds)
	return id

# ---- list / filter -------------------------------------------------------

func test_dataset_list_only_includes_posttrain_kind() -> void:
	# Seed a posttrain ds AND a pretrain ds — only the posttrain should appear.
	_seed_posttrain_ds(&"d_pt", &"code", 0.80)
	var pre := Dataset.new()
	pre.id = &"d_pre"
	pre.kind = &"pretrain"
	pre.source = &"open_source"
	pre.size = 10.0
	pre.quality = 0.6
	GameState.datasets.append(pre)
	var mid := _seed_evaluated_model()
	var dlg = _make_dialog(mid)
	dlg.refresh()
	assert_eq(dlg._dataset_checkboxes.size(), 1,
			"only posttrain-kind datasets should be listed")
	assert_eq(StringName(dlg._dataset_checkboxes[0].id), &"d_pt")

func test_dataset_list_skips_locked() -> void:
	_seed_posttrain_ds(&"d_locked", &"code", 0.80)
	_seed_posttrain_ds(&"d_idle", &"reasoning", 0.80)
	var locked := DatasetSystem.find_dataset(&"d_locked")
	locked.locked_by_task_id = &"task_X"
	var mid := _seed_evaluated_model()
	var dlg = _make_dialog(mid)
	dlg.refresh()
	assert_eq(dlg._dataset_checkboxes.size(), 1)
	assert_eq(StringName(dlg._dataset_checkboxes[0].id), &"d_idle")

func test_dialog_uses_panelized_two_column_layout() -> void:
	# design/UI视觉系统设计.md §7.2: 后训练 Dialog 与预训练同构, 左配置右预览,
	# 两侧独立滚动, 预览分组进子面板, 启动按钮使用 create CTA。
	var mid := _seed_evaluated_model()
	_seed_posttrain_ds(&"d_layout", &"code", 0.80)
	var dlg = _make_dialog(mid)
	dlg.refresh()
	assert_gte(_count_descendants_of_type(dlg, ScrollContainer), 2,
			"PosttrainDialog 应有配置和预览两个独立 ScrollContainer")
	assert_gte(_count_descendants_of_type(dlg, PanelContainer), 4,
			"PosttrainDialog 应有左右主面板 + 预览子面板")
	assert_gte(int(dlg.get_ok_button().custom_minimum_size.y), UITheme.CREATE_BUTTON_H,
			"启动后训练按钮应使用 create CTA 高度")
	var normal: StyleBox = dlg.get_ok_button().get_theme_stylebox(&"normal")
	assert_true(normal is StyleBoxFlat, "create CTA normal style 应是 StyleBoxFlat")
	if normal is StyleBoxFlat:
		assert_true((normal as StyleBoxFlat).bg_color.is_equal_approx(UITheme.ACCENT_INFO),
				"启动后训练按钮应是实心炭黑 CTA")

func _count_descendants_of_type(root: Node, type) -> int:
	var count := 0
	for c in root.get_children():
		if is_instance_of(c, type):
			count += 1
		count += _count_descendants_of_type(c, type)
	return count

# ---- preview ------------------------------------------------------------

func test_preview_shows_target_axis_gain_in_predicted_capability() -> void:
	var mid := _seed_evaluated_model()
	_seed_posttrain_ds(&"d_code_premium", &"code", 0.93, 0.10)
	# Need a dc available so the dropdown has a real entry.
	CommandBus.send(&"infra.debug_instant_owned_dc", {facility_spec_id = &"facility_room", gpu_id = &"cypress_t0"})
	var dlg = _make_dialog(mid)
	dlg.refresh()
	# Pick the only available DC and the only dataset.
	dlg._dc_dropdown.select(1)
	dlg._dataset_checkboxes[0].box.button_pressed = true
	dlg._refresh_preview()
	# Predicted capability should mention "代码" + a value clearly > 30 (start).
	# v12: base_power=50 → ceiling 70; code 30 饱和到 ≈59 (< 旧版无上限的 76).
	assert_string_contains(dlg._predicted_capability_label.text, "代码")
	# Net should be positive (delta_total_label has parts; net_label has summary).
	assert_string_contains(dlg._net_label.text, "+")

func test_preview_warns_on_net_negative() -> void:
	# Low-quality dataset → net negative. Need to start from a model whose axes
	# actually have headroom to forget (otherwise the clamp-to-0 — correct per
	# §5.3 v2.1 — turns the net positive). A fully-positive baseline gives the
	# forget terms room to subtract.
	var mid := _seed_evaluated_model()
	var m = ResearchSystem.find_model(mid)
	m.capability = {
		&"general": 50.0, &"code": 50.0, &"reasoning": 50.0,
		&"multimodal": 50.0, &"agent": 50.0,
	}
	_seed_posttrain_ds(&"d_bad", &"code", 0.30, 0.02)
	CommandBus.send(&"infra.debug_instant_owned_dc", {facility_spec_id = &"facility_room", gpu_id = &"cypress_t0"})
	var dlg = _make_dialog(mid)
	dlg.refresh()
	dlg._dc_dropdown.select(1)
	dlg._dataset_checkboxes[0].box.button_pressed = true
	dlg._refresh_preview()
	assert_string_contains(dlg._net_label.text, "-",
			"low quality dataset should produce negative net")

# Preview must equal apply for every supported scenario; this is the
# §5.3 v2.1 contract — they share ResearchSystem.simulate_posttrain.
func test_preview_net_matches_apply_for_zero_baseline_model() -> void:
	# Just-pretrained model (caps all 0). One mid-quality posttrain dataset.
	# Old buggy preview: subtracted forget × 4 from net even though those axes
	# clamp to 0 on apply. Post-fix: preview net == apply net.
	var mid := _seed_evaluated_model()
	var m = ResearchSystem.find_model(mid)
	m.capability = {
		&"general": 0.0, &"code": 0.0, &"reasoning": 0.0,
		&"multimodal": 0.0, &"agent": 0.0,
	}
	_seed_posttrain_ds(&"d_zero_baseline", &"code", 0.85, 0.05)
	CommandBus.send(&"infra.debug_instant_owned_dc", {facility_spec_id = &"facility_room", gpu_id = &"cypress_t0"})
	var dlg = _make_dialog(mid)
	dlg.refresh()
	dlg._dc_dropdown.select(1)
	dlg._dataset_checkboxes[0].box.button_pressed = true
	dlg._refresh_preview()
	# v12: zero-baseline 800M 模型 base_power=size头≈30.84 → ceiling≈43.17.
	# code 从 0 饱和到 ≈26.2; general/reasoning/multimodal/agent clamp 在 0.0.
	var pred_text: String = dlg._predicted_capability_label.text
	assert_string_contains(pred_text, "代码 26.")
	assert_string_contains(pred_text, "通用 0.0")
	assert_string_contains(pred_text, "多模 0.0")
	# Net must be positive (no fake forget reduction).
	assert_string_contains(dlg._net_label.text, "+")
	# Now actually apply and compare to preview's predicted state.
	CommandBus.send(&"research.posttrain_apply", {
		model_id = mid, dataset_ids = [&"d_zero_baseline"]})
	var m_after = ResearchSystem.find_model(mid)
	# code apply outcome ≈ 26.2; preview said the same (同一 base_power).
	assert_almost_eq(float(m_after.capability[&"code"]), 26.2, 1.0)
	# Other axes really did clamp to 0, matching preview.
	for ax in [&"general", &"reasoning", &"multimodal", &"agent"]:
		assert_almost_eq(float(m_after.capability[ax]), 0.0, 0.001,
				"axis %s should be clamped to 0 by apply" % String(ax))

func test_preview_predicted_matches_apply_capability_per_axis() -> void:
	# Three datasets on a mixed-baseline model, then compare preview's
	# predicted_capability label to the actual model.capability after apply.
	var mid := _seed_evaluated_model()
	var m = ResearchSystem.find_model(mid)
	m.capability = {
		&"general": 40.0, &"code": 20.0, &"reasoning": 5.0,
		&"multimodal": 0.0, &"agent": 0.0,
	}
	_seed_posttrain_ds(&"d_a", &"code", 0.85, 0.05)
	_seed_posttrain_ds(&"d_b", &"reasoning", 0.70, 0.04)
	_seed_posttrain_ds(&"d_c", &"general", 0.60, 0.03)
	CommandBus.send(&"infra.debug_instant_owned_dc", {facility_spec_id = &"facility_room", gpu_id = &"cypress_t0"})
	var dlg = _make_dialog(mid)
	dlg.refresh()
	dlg._dc_dropdown.select(1)
	for entry in dlg._dataset_checkboxes:
		entry.box.button_pressed = true
	dlg._refresh_preview()
	# Capture preview's predicted text so we can sanity-check vs apply.
	var pred_text: String = dlg._predicted_capability_label.text
	# Apply and read the actual model.
	CommandBus.send(&"research.posttrain_apply", {
		model_id = mid,
		dataset_ids = [&"d_a", &"d_b", &"d_c"],
	})
	var labels: Dictionary = {
		&"general": "通用", &"code": "代码", &"reasoning": "推理",
		&"multimodal": "多模", &"agent": "Agent",
	}
	for ax in [&"general", &"code", &"reasoning", &"multimodal", &"agent"]:
		var actual: float = float(m.capability.get(ax, 0.0))
		var fragment: String = "%s %.1f" % [labels[ax], actual]
		assert_string_contains(pred_text, fragment)

# ---- UI display 显示文案 (玩家预期对齐) ----------------------------------
# 这一组测试守护"玩家看到什么"的细节, 而不是底层算法. 一旦 UI 显示让玩家形成
# 错误预期 (例如 "增益 ×0.72" 让人以为最终就是 +0.72), 这里应该抓得到.

func test_dataset_checkbox_shows_aggregation_inputs() -> void:
	# v12: 同轴数据集先聚合再朝天花板饱和, 单份 target_gain 已无意义。checkbox
	# 改为展示该份对聚合的输入: 目标轴 / token 量 / 质量 (真实结果见下方预览)。
	var mid := _seed_evaluated_model()
	_seed_posttrain_ds(&"d_real_gain", &"code", 0.85, 0.05)
	var dlg = _make_dialog(mid)
	dlg.refresh()
	var box_text: String = dlg._dataset_checkboxes[0].box.text
	# 目标轴 (代码) + token 量 (0.050B) + 质量 (0.85) 都要可见.
	assert_string_contains(box_text, "代码",
			"checkbox label should display the target axis")
	assert_string_contains(box_text, "0.050",
			"checkbox label should display the dataset token volume in B")
	assert_string_contains(box_text, "0.85",
			"checkbox label should display the dataset quality")

func test_dataset_checkbox_size_shows_in_label() -> void:
	# 同 q, size 不同, 文案应明显不同 — 让玩家看出 token 量 (聚合输入) 的区别.
	var mid := _seed_evaluated_model()
	_seed_posttrain_ds(&"d_small", &"code", 0.85, 0.01)
	_seed_posttrain_ds(&"d_big",   &"code", 0.85, 0.10)
	var dlg = _make_dialog(mid)
	dlg.refresh()
	var small_text: String = dlg._dataset_checkboxes[0].box.text
	var big_text:   String = dlg._dataset_checkboxes[1].box.text
	# 防止两份显示完全一样导致玩家误以为 size 不影响.
	assert_false(small_text == big_text,
			"two datasets with same q but different size must produce different labels")

func test_predicted_capability_hides_question_marks_for_unrevealed_model() -> void:
	# Just-pretrained model (capability_revealed=false). 当前能力应显示 "??",
	# 预估完成后应该正常显示数字 (因为 simulate 用 0 基线).
	var r: Dictionary = CommandBus.send(&"research.add_model", {
		capability = {}, arch = &"ant_v1",
		size_params = 800.0, dataset_ids = [], display_name = "M_unrevealed"})
	# Do NOT call evaluate. Keep capability_revealed=false.
	_seed_posttrain_ds(&"d_unr", &"code", 0.85, 0.05)
	CommandBus.send(&"infra.debug_instant_owned_dc", {facility_spec_id = &"facility_room", gpu_id = &"cypress_t0"})
	var dlg = _make_dialog(r.model_id)
	dlg.refresh()
	dlg._dc_dropdown.select(1)
	dlg._dataset_checkboxes[0].box.button_pressed = true
	dlg._refresh_preview()
	assert_string_contains(dlg._capability_before_label.text, "??",
			"unrevealed model header should show '??'")
	# v12: 0 基线 + 800M 模型 base_power≈30.84 → ceiling≈43.17, code 饱和到 ≈26.2.
	assert_string_contains(dlg._predicted_capability_label.text, "代码 26.")
	# Non-target axes should stay at 0 (clamped), not show fake -X.X.
	assert_string_contains(dlg._predicted_capability_label.text, "通用 0.0")

func test_net_zero_is_not_green() -> void:
	# 净分 == 0 (无数据集 / 数据集全跳过) 不应该用 "positive 绿" 颜色误导.
	# 期望: net=0 时不染绿色 (改用 neutral 灰).
	var mid := _seed_evaluated_model()
	_seed_posttrain_ds(&"d_unused", &"code", 0.85, 0.05)
	CommandBus.send(&"infra.debug_instant_owned_dc", {facility_spec_id = &"facility_room", gpu_id = &"cypress_t0"})
	var dlg = _make_dialog(mid)
	dlg.refresh()
	dlg._dc_dropdown.select(1)
	# Do NOT tick any dataset → net = 0.
	dlg._refresh_preview()
	var net_color: Color = dlg._net_label.get_theme_color(&"font_color")
	# Green is around (0.4, 0.85, 0.5). Neutral should be clearly different.
	assert_lt(net_color.g, 0.8,
			"net=0 should not be rendered in the positive green color")

func test_net_negative_shows_explicit_warning_text() -> void:
	# 设计 §5.3: 净分 < 0 时显示红字 "净分将下降 X, 是否继续?".
	# 当前只染色没文字, 玩家可能忽略.
	var mid := _seed_evaluated_model()
	var m = ResearchSystem.find_model(mid)
	m.capability = {
		&"general": 50.0, &"code": 50.0, &"reasoning": 50.0,
		&"multimodal": 50.0, &"agent": 50.0,
	}
	_seed_posttrain_ds(&"d_neg", &"code", 0.30, 0.02)
	CommandBus.send(&"infra.debug_instant_owned_dc", {facility_spec_id = &"facility_room", gpu_id = &"cypress_t0"})
	var dlg = _make_dialog(mid)
	dlg.refresh()
	dlg._dc_dropdown.select(1)
	dlg._dataset_checkboxes[0].box.button_pressed = true
	dlg._refresh_preview()
	# net_label or warning label should mention "下降" / "是否继续".
	var combined: String = dlg._net_label.text + " " + dlg._warning_label.text
	assert_true(
			combined.find("下降") >= 0 or combined.find("继续") >= 0 \
				or combined.find("劣质") >= 0,
			"net-negative should show explicit warning text, not just color")

func test_no_datasets_hides_per_axis_delta_noise() -> void:
	# 没勾选数据集时, "累加 delta" 不应该堆一行 "通用 +0.0 / 代码 +0.0 / ..."
	# 假装是已经算出来的结果. 期望: 显示空 / placeholder, 不是 5 个 +0.0.
	var mid := _seed_evaluated_model()
	_seed_posttrain_ds(&"d_noise", &"code", 0.85, 0.05)
	CommandBus.send(&"infra.debug_instant_owned_dc", {facility_spec_id = &"facility_room", gpu_id = &"cypress_t0"})
	var dlg = _make_dialog(mid)
	dlg.refresh()
	dlg._dc_dropdown.select(1)
	# Don't tick any.
	dlg._refresh_preview()
	# We allow either empty text or an explicit placeholder, but NOT a fake
	# "通用 +0.0 / 代码 +0.0 / ..." that looks like a real preview result.
	# Detect the bad pattern: any of the axis labels appearing as a +0.0 line.
	var bad: String = dlg._delta_total_label.text
	assert_false(bad.find("通用 +0.0") >= 0 and bad.find("代码 +0.0") >= 0,
			"empty selection should not render a fake per-axis +0.0 line")

# ---- start button gates -------------------------------------------------

func test_start_button_disabled_without_dataset() -> void:
	var mid := _seed_evaluated_model()
	_seed_posttrain_ds(&"d_x", &"code", 0.80)
	CommandBus.send(&"infra.debug_instant_owned_dc", {facility_spec_id = &"facility_room", gpu_id = &"cypress_t0"})
	var dlg = _make_dialog(mid)
	dlg.refresh()
	dlg._dc_dropdown.select(1)
	# Don't tick any dataset.
	dlg._refresh_preview()
	assert_true(dlg.get_ok_button().disabled,
			"start should be disabled until ≥1 dataset is selected")

func test_start_button_disabled_without_dc() -> void:
	var mid := _seed_evaluated_model()
	_seed_posttrain_ds(&"d_y", &"code", 0.80)
	var dlg = _make_dialog(mid)
	dlg.refresh()
	# Default DC dropdown is "(无)" at index 0.
	dlg._dataset_checkboxes[0].box.button_pressed = true
	dlg._refresh_preview()
	assert_true(dlg.get_ok_button().disabled,
			"start should be disabled until a DC is picked")

# ---- start flow ---------------------------------------------------------

func test_start_creates_posttrain_active_task() -> void:
	var mid := _seed_evaluated_model()
	_seed_posttrain_ds(&"d_go", &"code", 0.80)
	CommandBus.send(&"infra.debug_instant_owned_dc", {facility_spec_id = &"facility_room", gpu_id = &"cypress_t0"})
	var dlg = _make_dialog(mid)
	dlg.refresh()
	dlg._dc_dropdown.select(1)
	dlg._dataset_checkboxes[0].box.button_pressed = true
	dlg._refresh_preview()
	assert_false(dlg.get_ok_button().disabled)
	dlg._on_start_pressed()
	assert_eq(GameState.active_tasks.size(), 1)
	var t = GameState.active_tasks[0]
	assert_eq(t.subtype, &"posttrain")
	assert_eq(t.locked_dataset_ids.size(), 1)
