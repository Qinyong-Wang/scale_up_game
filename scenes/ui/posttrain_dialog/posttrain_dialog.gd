extends ConfirmationDialog

## PosttrainDialog — 启动后训练对话框 (v2).
## Per design/研究系统设计.md §5.3 (v2).
##
## 流程:
##   1. 模型 tab 上某个 evaluated/posttrained/pretrained 模型卡片点「后训练...」.
##   2. 调用 .set_base_model_id(...) + popup_centered.
##   3. 玩家选 DC + 一个或多个 posttrain dataset + 可选 lead → 任意变化触发预览.
##   4. 「启动」→ task.start({template_id=&"posttrain_model", ...}).
##
## 不持有任何系统状态; refresh() 每次从 GameState 重读。

signal task_started_via_dialog(result: Dictionary)


const TEMPLATE_ID := &"posttrain_model"
const AXES: Array[StringName] = [&"general", &"code", &"reasoning", &"multimodal", &"agent"]
# 值为 i18n key (const 不能调 tr); 取用处 tr()。
const AXIS_LABELS: Dictionary = {
	&"general": "CAP_GENERAL", &"code": "CAP_CODE", &"reasoning": "CAP_REASONING",
	&"multimodal": "CAP_MULTIMODAL", &"agent": "CAP_AGENT",
}
# 数据集来源 → i18n key (与 dataset_view 对齐, const 不能调 tr; 取用处 tr)。
const SOURCE_LABELS: Dictionary = {
	&"open_source": "DATASET_SRC_OPEN", &"purchased": "DATASET_SRC_PURCHASED",
	&"collected": "DATASET_SRC_COLLECTED",
}

# v12: token-volume duration surcharge (mirror TaskSystem.POSTTRAIN_TOKENS_PER_WEEK_B).
# Actual capability gains come from ResearchSystem.simulate_posttrain (aggregated +
# saturated), so the dialog no longer mirrors the per-dataset gain/forget constants.
const POSTTRAIN_TOKENS_PER_WEEK_B: float = 1.0

# Posttrain tier table (mirror TaskSystem so preview matches start duration).
const TIER_TABLE: Array = [
	{cap_m = 10_000.0,  min_gpu = 8,    weeks = 1, label = "S"},
	{cap_m = 100_000.0, min_gpu = 72,   weeks = 2, label = "M"},
	{cap_m = 500_000.0, min_gpu = 500,  weeks = 4, label = "L"},
	{cap_m = INF,       min_gpu = 1000, weeks = 8, label = "XL"},
]

var _base_model_id: StringName = &""

# Form widgets
var _model_label: Label
var _capability_before_label: Label
var _dc_dropdown: OptionButton
var _dc_warning_label: Label
var _dataset_box: VBoxContainer
var _dataset_checkboxes: Array = []  # [{box: CheckBox, id: StringName, ds: Dataset}]
var _lead_dropdown: OptionButton

# Preview widgets
var _duration_label: Label
var _tier_label: Label
var _per_dataset_label: Label
var _delta_total_label: Label
var _net_label: Label
var _predicted_capability_label: Label
var _lead_bonus_label: Label
var _warning_label: Label

func _ready() -> void:
	title = tr("POST_TITLE")
	min_size = Vector2i(1120, 660)
	dialog_hide_on_ok = false
	get_ok_button().text = tr("POST_TITLE")
	get_cancel_button().text = tr("ACTION_CANCEL")
	UITheme.apply_button_variant(get_ok_button(), &"create")
	UITheme.apply_button_variant(get_cancel_button(), &"secondary")
	get_ok_button().pressed.connect(_on_start_pressed)

	var outer := HBoxContainer.new()
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_theme_constant_override(&"separation", UITheme.S_3)
	add_child(outer)

	var form_panel := _make_main_panel(Vector2(570, 540), 1.05)
	outer.add_child(form_panel)
	var form_panel_root := _make_panel_root(form_panel)
	_add_panel_title(form_panel_root, tr("POST_TITLE"))

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	form_panel_root.add_child(scroll)
	var root := VBoxContainer.new()
	root.add_theme_constant_override(&"separation", UITheme.S_3)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(root)
	_build_form(root)

	outer.add_child(VSeparator.new())

	var preview_panel := _make_main_panel(Vector2(470, 540), 0.95)
	outer.add_child(preview_panel)
	var preview_panel_root := _make_panel_root(preview_panel)
	_add_panel_title(preview_panel_root, tr("FIELD_PREVIEW"))

	var preview_scroll := ScrollContainer.new()
	preview_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	preview_panel_root.add_child(preview_scroll)
	var preview_root := VBoxContainer.new()
	preview_root.add_theme_constant_override(&"separation", UITheme.S_3)
	preview_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_scroll.add_child(preview_root)
	_build_preview(preview_root)

	Log.info(&"ui", "PosttrainDialog ready")

# ---- public --------------------------------------------------------------

func set_base_model_id(model_id: StringName) -> void:
	_base_model_id = model_id

func refresh() -> void:
	_populate_model_header()
	_populate_dc_dropdown()
	_populate_dataset_checkboxes()
	_populate_lead_dropdown()
	_refresh_preview()

# ---- form construction ---------------------------------------------------

func _build_form(root: VBoxContainer) -> void:
	_model_label = Label.new()
	_model_label.add_theme_font_override(&"font", UITheme.get_ui_font_bold())
	_model_label.add_theme_font_size_override(&"font_size", UITheme.FS_MD)
	_model_label.add_theme_color_override(&"font_color", UITheme.TEXT_PRIMARY)
	_model_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_model_label)
	_capability_before_label = Label.new()
	_capability_before_label.add_theme_color_override(&"font_color", UITheme.TEXT_SECONDARY)
	_capability_before_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_capability_before_label)

	_dc_dropdown = OptionButton.new()
	_dc_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dc_dropdown.item_selected.connect(func(_i): _refresh_preview())
	root.add_child(_form_row(tr("FIELD_DATACENTER"), _dc_dropdown))
	_dc_warning_label = Label.new()
	_dc_warning_label.add_theme_color_override(&"font_color", UITheme.ACCENT_DANGER)
	_dc_warning_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_dc_warning_label)

	var ds_section := Label.new()
	ds_section.text = tr("POST_DS_SECTION")
	ds_section.add_theme_font_override(&"font", UITheme.get_ui_font_bold())
	ds_section.add_theme_color_override(&"font_color", UITheme.TEXT_PRIMARY)
	root.add_child(ds_section)
	_dataset_box = VBoxContainer.new()
	_dataset_box.add_theme_constant_override(&"separation", UITheme.S_1)
	root.add_child(_dataset_box)

	_lead_dropdown = OptionButton.new()
	_lead_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lead_dropdown.item_selected.connect(func(_i): _refresh_preview())
	root.add_child(_form_row(tr("POST_LEAD"), _lead_dropdown))

func _build_preview(root: VBoxContainer) -> void:
	var resource_box := _add_subpanel(root)
	_duration_label = Label.new()
	_duration_label.add_theme_color_override(&"font_color", UITheme.ACCENT_INFO)
	resource_box.add_child(_duration_label)
	_tier_label = Label.new()
	_tier_label.add_theme_color_override(&"font_color", UITheme.TEXT_PRIMARY)
	resource_box.add_child(_tier_label)

	var dataset_box := _add_subpanel(root)
	_per_dataset_label = Label.new()
	_per_dataset_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_per_dataset_label.add_theme_color_override(&"font_color", UITheme.TEXT_SECONDARY)
	dataset_box.add_child(_per_dataset_label)

	var outcome_box := _add_subpanel(root)
	_delta_total_label = Label.new()
	_delta_total_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_delta_total_label.add_theme_color_override(&"font_color", UITheme.ACCENT_INFO)
	outcome_box.add_child(_delta_total_label)
	_net_label = Label.new()
	_net_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	outcome_box.add_child(_net_label)
	_predicted_capability_label = Label.new()
	_predicted_capability_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_predicted_capability_label.add_theme_color_override(&"font_color", UITheme.ACCENT_PRIMARY)
	outcome_box.add_child(_predicted_capability_label)
	_lead_bonus_label = Label.new()
	_lead_bonus_label.add_theme_color_override(&"font_color", UITheme.ACCENT_INFO)
	outcome_box.add_child(_lead_bonus_label)

	var warning_box := _add_subpanel(root)
	_warning_label = Label.new()
	_warning_label.add_theme_color_override(&"font_color", UITheme.ACCENT_DANGER)
	_warning_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warning_box.add_child(_warning_label)

func _form_row(label_text: String, widget: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(96, 0)
	lbl.add_theme_color_override(&"font_color", UITheme.TEXT_SECONDARY)
	row.add_child(lbl)
	row.add_child(widget)
	return row

func _make_main_panel(minimum: Vector2, stretch_ratio: float) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = stretch_ratio
	panel.custom_minimum_size = minimum
	panel.add_theme_stylebox_override(&"panel",
			_make_panel_style(UITheme.BG_SURFACE, UITheme.R_LG, UITheme.S_4))
	return panel

func _make_panel_root(panel: PanelContainer) -> VBoxContainer:
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override(&"separation", UITheme.S_3)
	panel.add_child(root)
	return root

func _add_panel_title(root: VBoxContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override(&"font", UITheme.get_ui_font_bold())
	label.add_theme_font_size_override(&"font_size", UITheme.FS_MD)
	label.add_theme_color_override(&"font_color", UITheme.TEXT_PRIMARY)
	root.add_child(label)

func _add_subpanel(root: VBoxContainer) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override(&"panel",
			_make_panel_style(UITheme.BG_BASE, UITheme.R_MD, UITheme.S_3))
	root.add_child(panel)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override(&"separation", UITheme.S_1)
	panel.add_child(box)
	return box

func _make_panel_style(bg: Color, radius: int, padding: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = UITheme.BORDER_SUBTLE
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = padding
	sb.content_margin_right = padding
	sb.content_margin_top = padding
	sb.content_margin_bottom = padding
	return sb

# ---- populate widgets ----------------------------------------------------

func _populate_model_header() -> void:
	var m = ResearchSystem.find_model(_base_model_id)
	if m == null:
		_model_label.text = tr("POST_MODEL_NOTFOUND") % String(_base_model_id)
		_capability_before_label.text = ""
		return
	_model_label.text = tr("POST_MODEL") % [
		m.display_name, String(m.arch), float(m.size_params)]
	var caps_text: String = tr("POST_CURRENT_CAP")
	if not m.capability_revealed:
		caps_text += tr("POST_UNEVALUATED")
	else:
		var parts: Array = []
		for ax in AXES:
			parts.append("%s %.1f" % [tr(AXIS_LABELS[ax]), float(m.capability.get(ax, 0.0))])
		caps_text += " / ".join(parts)
		if m.capability_stale:
			caps_text += tr("POST_EVAL_STALE")
	_capability_before_label.text = caps_text

func _populate_dc_dropdown() -> void:
	_dc_dropdown.clear()
	_dc_dropdown.add_item(tr("MSG_NONE"))
	_dc_dropdown.set_item_metadata(0, &"")
	for dc in GameState.datacenters:
		if dc.status != &"idle":
			continue
		var gpu_count: int = int(dc.gpu_count) if "gpu_count" in dc else 0
		var label: String = tr("POST_DC_ITEM") % [dc.display_label(), gpu_count]
		var idx := _dc_dropdown.item_count
		_dc_dropdown.add_item(label)
		_dc_dropdown.set_item_metadata(idx, dc.id)

func _populate_dataset_checkboxes() -> void:
	for c in _dataset_box.get_children():
		c.queue_free()
	_dataset_checkboxes.clear()
	var any_added := false
	for ds in GameState.datasets:
		if ds.locked_by_task_id != &"":
			continue
		# v2: only posttrain-kind datasets are listed.
		if ds.kind != &"posttrain":
			continue
		any_added = true
		var box := CheckBox.new()
		var axis_label: String = tr(AXIS_LABELS.get(ds.target_capability, String(ds.target_capability)))
		# v12: 同一目标轴的数据集先聚合 (token 加权质量) 再朝软天花板饱和, 所以
		# "单份 target_gain" 不再有意义。checkbox 只展示该份对聚合的输入: 目标轴 /
		# token 量 / 质量。真实(聚合+封顶后)结果见下方预览。Per 研究系统设计 §4.2。
		var q: float = clampf(float(ds.quality), 0.0, 1.0)
		var size_b: float = max(0.0, float(ds.size))
		box.text = tr("POST_DS_ITEM") % [
			ds.display_name, tr(SOURCE_LABELS.get(ds.source, String(ds.source))), axis_label, size_b, q]
		box.tooltip_text = tr("POST_DS_TOOLTIP") % [axis_label, size_b * 1000.0, q]
		box.toggled.connect(func(_p): _refresh_preview())
		_dataset_box.add_child(box)
		_dataset_checkboxes.append({box = box, id = ds.id, ds = ds})
	if not any_added:
		var dim := Label.new()
		dim.text = tr("POST_NO_DS")
		dim.add_theme_color_override(&"font_color", UITheme.TEXT_SECONDARY)
		_dataset_box.add_child(dim)

func _populate_lead_dropdown() -> void:
	# Per design/招聘系统设计.md §5.4: posttrain 强制 ml_research_lead.
	# 只列匹配 specialty 的 idle lead (含创始人), 默认选第一个真正 ml_research_lead,
	# 没有时退到创始人。
	_lead_dropdown.clear()
	var first_match: int = -1
	var founder_index: int = -1
	for lead in GameState.leads:
		if lead.locked_by_task_id != &"" or lead.assigned_to_product_id != &"":
			continue
		if not HiringSystem.lead_matches_specialty(lead, &"ml_research_lead"):
			continue
		var suffix: String = tr("CAMPAIGN_FOUNDER_SUFFIX") if lead.is_player_scientist else ""
		var idx := _lead_dropdown.item_count
		# 下拉已按 specialty 过滤 (ml_research_lead), 不再露出 raw 枚举。
		_lead_dropdown.add_item(tr("POST_LEAD_ITEM") % [
			NameRomanizer.localized(lead.display_name), String(lead.level), lead.ability, suffix])
		_lead_dropdown.set_item_metadata(idx, lead.id)
		if lead.is_player_scientist:
			if founder_index < 0:
				founder_index = idx
		else:
			if first_match < 0:
				first_match = idx
	if _lead_dropdown.item_count == 0:
		_lead_dropdown.add_item(tr("POST_NO_LEAD"))
		_lead_dropdown.set_item_metadata(0, &"")
		_lead_dropdown.select(0)
	else:
		_lead_dropdown.select(first_match if first_match >= 0 else founder_index)

# ---- preview math --------------------------------------------------------

func _selected_dc_id() -> StringName:
	var i := _dc_dropdown.selected
	if i < 0:
		return &""
	return _dc_dropdown.get_item_metadata(i)

func _selected_lead_id() -> StringName:
	var i := _lead_dropdown.selected
	if i < 0:
		return &""
	return _lead_dropdown.get_item_metadata(i)

func _selected_dataset_ids() -> Array:
	var out: Array = []
	for entry in _dataset_checkboxes:
		if entry.box.button_pressed:
			out.append(entry.id)
	return out

func _tier_for(size_m: float) -> Dictionary:
	for t in TIER_TABLE:
		if size_m <= t.cap_m:
			return t
	return TIER_TABLE[-1]

func _refresh_preview() -> void:
	var m = ResearchSystem.find_model(_base_model_id)
	if m == null:
		_warning_label.text = tr("POST_MODEL_MISSING")
		get_ok_button().disabled = true
		return

	# Tier from base model size + v12 token-volume surcharge (每 POSTTRAIN_TOKENS_
	# PER_WEEK_B 后训练 token 多占 1 周; 与 TaskSystem._posttrain_fixed_tier 一致)。
	var tier := _tier_for(float(m.size_params))
	var total_tokens_b: float = 0.0
	for ds_id in _selected_dataset_ids():
		var dsx = DatasetSystem.find_dataset(StringName(ds_id))
		if dsx != null and dsx.kind == &"posttrain":
			total_tokens_b += max(0.0, float(dsx.size))
	var extra_weeks: int = int(floor(total_tokens_b / POSTTRAIN_TOKENS_PER_WEEK_B))
	var total_weeks: int = int(tier.weeks) + extra_weeks
	if extra_weeks > 0:
		_duration_label.text = tr("POST_DURATION_FULL") % [
				total_weeks, String(tier.label), int(tier.weeks), extra_weeks]
	else:
		_duration_label.text = tr("POST_DURATION") % [total_weeks, String(tier.label)]
	_tier_label.text = tr("POST_GPU_REQ") % int(tier.min_gpu)

	# DC check.
	var dc_id := _selected_dc_id()
	var dc_ok: bool = false
	var dc_msg: String = ""
	if dc_id == &"":
		dc_msg = tr("POST_SELECT_DC")
	else:
		var dc = InfraSystem.find_dc(dc_id)
		if dc == null:
			dc_msg = tr("POST_DC_MISSING")
		else:
			var have_gpu: int = int(dc.gpu_count) if "gpu_count" in dc else 0
			var have_tflops: float = float(dc.train_tflops) if "train_tflops" in dc else 0.0
			if have_gpu > 0 and have_gpu < int(tier.min_gpu):
				dc_msg = tr("POST_DC_SHORT") % [
						have_gpu, int(tier.min_gpu), String(tier.label)]
			elif have_gpu == 0 and have_tflops <= 0.0:
				dc_msg = tr("POST_DC_NO_COMPUTE")
			else:
				dc_ok = true
	_dc_warning_label.text = dc_msg

	# Per-dataset preview lines. Show each dataset's nominal target_gain/forget
	# coefficients (for player education on dataset properties) — the actual
	# totals below use ResearchSystem.simulate_posttrain so clamp-to-0 on already-
	# zero axes is honored, matching what apply will produce.
	# Per 研究系统设计.md §5.3 (v2.1 preview-apply consistency clause).
	var dataset_ids := _selected_dataset_ids()
	var resolved_datasets: Array = []
	var lines: Array = []
	# v12: gains are aggregated per axis (token-weighted) then saturated toward the
	# soft ceiling, so a per-dataset "+X" is no longer meaningful. Show each set's
	# aggregation inputs (target axis / tokens / quality); the real capped totals
	# appear below from simulate_posttrain.
	for ds_id in dataset_ids:
		var ds = DatasetSystem.find_dataset(StringName(ds_id))
		if ds == null:
			continue
		resolved_datasets.append(ds)
		var axis: StringName = ds.target_capability
		lines.append(tr("POST_PER_DS") % [
				ds.display_name, tr(AXIS_LABELS.get(axis, String(axis))),
				max(0.0, float(ds.size)), clampf(float(ds.quality), 0.0, 1.0)])
	if lines.is_empty():
		_per_dataset_label.text = tr("POST_PREVIEW_HINT")
	else:
		_per_dataset_label.text = "\n".join(lines)

	# Build initial capability snapshot for the simulator. Unrevealed models
	# (just-pretrained) are treated as zero baseline, matching apply: it reads
	# m.capability.get(ax, 0.0) which is whatever's been stamped (zero for
	# pretrained models from research.add_model).
	var initial_caps: Dictionary = {}
	for ax in AXES:
		initial_caps[ax] = float(m.capability.get(ax, 0.0)) if m.capability_revealed else 0.0
	# v12: pass the same base_power apply uses so preview == apply (v2.1 契约).
	# The soft ceiling = base_power × CEILING_MULT bounds the per-axis gain.
	var base_power: float = ResearchSystem.posttrain_base_power(m)
	# 后训练科学家加分: 选中 lead 的 posttrain_score_bonus 抬高 ceiling。预览与 apply
	# 共用同一倍率, 保证一致 (§5.3 v2.1 契约)。
	var lead = HiringSystem.find_lead(_selected_lead_id())
	var score_mult: float = HiringSystem.lead_score_mult(lead, &"posttrain_score_bonus")
	var sim: Dictionary = ResearchSystem.simulate_posttrain(
			initial_caps, resolved_datasets, base_power, score_mult)
	if score_mult > 1.0:
		_lead_bonus_label.text = tr("POST_LEAD_BONUS") % ((score_mult - 1.0) * 100.0)
	else:
		_lead_bonus_label.text = ""
	var delta: Dictionary = sim.delta
	var predicted: Dictionary = sim.capability
	var has_any_dataset: bool = not resolved_datasets.is_empty()

	# 没勾数据集时不显示假的 "+0.0 / +0.0 / ..." 累加行 + 预估行 — 否则像
	# 已经算完的预览结果, 误导玩家。给个 placeholder 提示先选数据集。
	if not has_any_dataset:
		_delta_total_label.text = tr("POST_DELTA_HINT")
		_net_label.text = tr("POST_NET_DASH")
		_net_label.add_theme_color_override(&"font_color",
				Color(0.6, 0.6, 0.6))   # neutral grey
		_predicted_capability_label.text = tr("POST_PRED_HINT")
	else:
		var delta_parts: Array = []
		var net: float = 0.0
		for ax in AXES:
			var d: float = float(delta[ax])
			net += d
			var sign: String = "+" if d >= 0 else ""
			delta_parts.append("%s %s%.1f" % [tr(AXIS_LABELS[ax]), sign, d])
		_delta_total_label.text = tr("POST_DELTA") + " / ".join(delta_parts)

		var net_str: String = "+%.1f" % net if net >= 0 else "%.1f" % net
		if net < 0:
			# 设计 §5.3: 净分 < 0 显示红字"净分将下降 X, 是否继续?",
			# 染色 + 文字双保险, 玩家不会忽视。
			_net_label.text = tr("POST_NET_WARN") % [net_str, -net]
			_net_label.add_theme_color_override(&"font_color", UITheme.ACCENT_DANGER)
		else:
			_net_label.text = tr("POST_NET") % net_str
			_net_label.add_theme_color_override(&"font_color", UITheme.ACCENT_PRIMARY)

		# Predicted capability after — already clamped to ≥ 0 inside simulate_posttrain.
		var pred_parts: Array = []
		for ax in AXES:
			pred_parts.append("%s %.1f" % [tr(AXIS_LABELS[ax]), float(predicted[ax])])
		_predicted_capability_label.text = tr("POST_PRED") + " / ".join(pred_parts)

	# Validation + start button enable.
	var warn: String = ""
	if not dc_ok:
		warn = dc_msg
	elif dataset_ids.is_empty():
		warn = tr("POST_ERR_DS")
	elif _selected_lead_id() == &"":
		warn = tr("POST_ERR_LEAD")
	_warning_label.text = warn
	get_ok_button().disabled = (warn != "")

# ---- start ---------------------------------------------------------------

func _on_start_pressed() -> void:
	var dataset_ids := _selected_dataset_ids()
	var payload := {
		template_id = TEMPLATE_ID,
		base_model_id = _base_model_id,
		datacenter_id = _selected_dc_id(),
		dataset_ids = dataset_ids,
		lead_ids = [],
		staff = {},
	}
	var lid := _selected_lead_id()
	if lid != &"":
		payload[&"lead_ids"] = [lid]
	var r: Dictionary = CommandBus.send(&"task.start", payload)
	task_started_via_dialog.emit(r)
	if r.ok:
		hide()
	else:
		_warning_label.text = tr("CAMPAIGN_START_FAILED") % String(r.get(&"error", &""))
