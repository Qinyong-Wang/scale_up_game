extends ConfirmationDialog

## DatasetCollectionDialog (v2.1) — 启动自采数据集 task.
## Per design/数据集系统设计.md §5.1ter.
##
## 流程:
##   1. 「数据」tab pretrain/posttrain sub-tab 点「自行采集...」 → popup_centered.
##   2. 玩家选 kind / size / (target_capability if posttrain) / lead → 任意变化触发预览.
##   3. 「启动采集」→ task.start({template_id=&"data_collection_dynamic", ...}).
##
## 不持有任何系统状态; refresh() 每次从 GameState 重读.

signal task_started_via_dialog(result: Dictionary)

const TEMPLATE_ID := &"data_collection_dynamic"

# Kind labels (UI) ↔ payload values.
const _KIND_PRETRAIN := &"pretrain"
const _KIND_POSTTRAIN := &"posttrain"

# Posttrain-only target_capability axis options.
const _AXES: Array[StringName] = [&"general", &"code", &"reasoning", &"multimodal", &"agent"]
# 值为 i18n key (const 不能调 tr); 取用处 tr()。
const _AXIS_LABELS: Dictionary = {
	&"general": "CAP_GENERAL", &"code": "CAP_CODE", &"reasoning": "CAP_REASONING",
	&"multimodal": "CAP_MULTIMODAL", &"agent": "CAP_AGENT",
}

# Posttrain-only quality tier (labor grade). Each maps to a target_quality;
# task_system prices posttrain self-collect by EFFECTIVE quality (target + lead
# bonus) tier — cost rises steeply (crowd → domain → expert → PhD). Per
# design/数据集系统设计.md §5. `label` is an i18n key (const can't call tr()).
const _QUALITY_TIERS: Array = [
	{label = "COLLECT_TIER_T1", q = 0.65},
	{label = "COLLECT_TIER_T2", q = 0.80},
	{label = "COLLECT_TIER_T3", q = 0.90},
	{label = "COLLECT_TIER_T4", q = 0.95},
]

# v9 (2026-05): player picks up to 2 tags from this menu. Default selection is
# [web] only. Replaces the v8 "auto 5-tag balanced" preset which combined with
# count-based tag_ratio let one self-collected dataset cover every axis.
const _PRETRAIN_TAG_OPTIONS: Array[StringName] = [
	&"web", &"code", &"reasoning", &"chat", &"books", &"agent", &"multimodal",
]
const _PRETRAIN_TAG_LABELS: Dictionary = {
	&"web": "COLLECT_TAG_WEB", &"code": "COLLECT_TAG_CODE", &"reasoning": "COLLECT_TAG_REASONING",
	&"chat": "COLLECT_TAG_CHAT", &"books": "COLLECT_TAG_BOOKS",
	&"agent": "COLLECT_TAG_AGENT", &"multimodal": "COLLECT_TAG_MULTIMODAL",
}
const _PRETRAIN_TAG_DEFAULT: Array[StringName] = [&"web"]
const _PRETRAIN_TAG_MAX: int = 2

# v7 PR-G — single-modality enum exposed to player. `code` is expressed through
# pretrain coverage_tags, not as a standalone modality.
const _MODALITIES: Array[StringName] = [&"text", &"image", &"audio", &"video"]
const _MODALITY_LABELS: Dictionary = {
	&"text": "DATASET_MOD_TEXT", &"image": "DATASET_MOD_IMAGE", &"audio": "COLLECT_MOD_AUDIO",
	&"video": "COLLECT_MOD_VIDEO",
}

var _kind: StringName = _KIND_PRETRAIN

# Form widgets
var _name_input: LineEdit
var _kind_pretrain_btn: CheckBox
var _kind_posttrain_btn: CheckBox
var _size_spin: SpinBox
var _size_unit_label: Label
var _size_hint: Label
var _modality_dropdown: OptionButton    # v7 PR-G
var _pretrain_tags_row: Control          # v9 (2026-05)
var _pretrain_tag_checkboxes: Array = []  # Array[{tag: StringName, box: CheckBox}]
var _target_cap_row: Control
var _target_cap_dropdown: OptionButton
var _quality_tier_row: Control          # posttrain-only labor-grade selector
var _quality_tier_dropdown: OptionButton
var _employee_monitor_row: Control      # posttrain-only internal work-data option
var _employee_monitor_checkbox: CheckBox
var _lead_dropdown: OptionButton
var _staff_label: Label

# Preview widgets
var _duration_label: Label
var _cost_label: Label
var _quality_label: Label
var _tags_label: Label
var _summary_label: Label
var _warning_label: Label

func _ready() -> void:
	title = tr("COLLECT_TITLE")
	min_size = Vector2i(810, 660)
	max_size = Vector2i(1020, 680)
	dialog_hide_on_ok = false
	get_ok_button().text = tr("COLLECT_START")
	get_cancel_button().text = tr("ACTION_CANCEL")
	get_ok_button().pressed.connect(_on_start_pressed)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(780, 540)
	add_child(scroll)

	var root := VBoxContainer.new()
	root.add_theme_constant_override(&"separation", 8)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(root)

	_build_form(root)
	root.add_child(HSeparator.new())
	_build_preview(root)

	Log.info(&"ui", "DatasetCollectionDialog ready")

# ---- public --------------------------------------------------------------

## Optional: caller can pre-select pretrain or posttrain (matches the active
## sub-tab on the dataset panel).
func set_initial_kind(kind: StringName) -> void:
	if kind == _KIND_POSTTRAIN:
		_kind = _KIND_POSTTRAIN
	else:
		_kind = _KIND_PRETRAIN

func refresh() -> void:
	_apply_kind_to_widgets()
	_populate_lead_dropdown()
	_refresh_preview()

# ---- form construction ---------------------------------------------------

func _build_form(root: VBoxContainer) -> void:
	# Display name (optional).
	_name_input = LineEdit.new()
	_name_input.placeholder_text = tr("COLLECT_NAME_PLACEHOLDER")
	_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_input.text_changed.connect(func(_t): _refresh_preview())
	root.add_child(_label_row(tr("PRETRAIN_NAME"), _name_input))

	# Kind selector — ButtonGroup gives radio-button semantics (one always on).
	var kind_row := HBoxContainer.new()
	kind_row.add_theme_constant_override(&"separation", 8)
	var kind_group := ButtonGroup.new()
	_kind_pretrain_btn = CheckBox.new()
	_kind_pretrain_btn.text = tr("COLLECT_KIND_PRE")
	_kind_pretrain_btn.button_group = kind_group
	_kind_pretrain_btn.tooltip_text = tr("COLLECT_PRE_TOOLTIP")
	_kind_pretrain_btn.toggled.connect(func(pressed): if pressed: _set_kind(_KIND_PRETRAIN))
	kind_row.add_child(_kind_pretrain_btn)
	_kind_posttrain_btn = CheckBox.new()
	_kind_posttrain_btn.text = tr("COLLECT_KIND_POST")
	_kind_posttrain_btn.button_group = kind_group
	_kind_posttrain_btn.tooltip_text = tr("COLLECT_POST_TOOLTIP")
	_kind_posttrain_btn.toggled.connect(func(pressed): if pressed: _set_kind(_KIND_POSTTRAIN))
	kind_row.add_child(_kind_posttrain_btn)
	root.add_child(_label_row("kind", kind_row))

	# Size: SpinBox + B-tokens unit. Range/step adjusted by kind.
	var size_row := HBoxContainer.new()
	size_row.add_theme_constant_override(&"separation", 6)
	var size_l := Label.new()
	size_l.text = tr("PRETRAIN_SIZE")
	size_l.custom_minimum_size = Vector2(80, 0)
	size_row.add_child(size_l)
	_size_spin = SpinBox.new()
	_size_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_size_spin.value_changed.connect(func(_v): _refresh_preview())
	size_row.add_child(_size_spin)
	_size_unit_label = Label.new()
	_size_unit_label.text = "B tokens"
	_size_unit_label.custom_minimum_size = Vector2(60, 0)
	size_row.add_child(_size_unit_label)
	root.add_child(size_row)
	_size_hint = Label.new()
	_size_hint.add_theme_color_override(&"font_color", UITheme.TEXT_SECONDARY)
	root.add_child(_size_hint)

	# v7 PR-G — modality (single select). Default text. The dataset's modality
	# constrains which models can use it during pretrain (see
	# 数据集系统设计.md §1 校验).
	_modality_dropdown = OptionButton.new()
	_modality_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for m in _MODALITIES:
		_modality_dropdown.add_item(tr(String(_MODALITY_LABELS.get(m, String(m)))) + " (" + String(m) + ")")
		_modality_dropdown.set_item_metadata(_modality_dropdown.item_count - 1, m)
	_modality_dropdown.select(0)
	_modality_dropdown.item_selected.connect(func(_i): _refresh_preview())
	_modality_dropdown.tooltip_text = tr("COLLECT_MOD_TOOLTIP")
	root.add_child(_label_row(tr("FIELD_MODALITY"), _modality_dropdown))

	# v9 (2026-05) — pretrain coverage_tags picker (multi-select, max 2).
	# Hidden in posttrain mode. Default [web]. Payload passes via `target_tags`.
	var tag_box := VBoxContainer.new()
	tag_box.add_theme_constant_override(&"separation", 2)
	var tag_hint := Label.new()
	tag_hint.text = tr("COLLECT_TAG_HINT")
	tag_hint.add_theme_color_override(&"font_color", UITheme.TEXT_SECONDARY)
	tag_box.add_child(tag_hint)
	var tag_grid := HFlowContainer.new()
	tag_grid.add_theme_constant_override(&"h_separation", 8)
	tag_grid.add_theme_constant_override(&"v_separation", 2)
	for tag in _PRETRAIN_TAG_OPTIONS:
		var cb := CheckBox.new()
		cb.text = tr(String(_PRETRAIN_TAG_LABELS.get(tag, String(tag))))
		cb.button_pressed = _PRETRAIN_TAG_DEFAULT.has(tag)
		cb.toggled.connect(func(_p): _on_pretrain_tag_toggled())
		_pretrain_tag_checkboxes.append({tag = tag, box = cb})
		tag_grid.add_child(cb)
	tag_box.add_child(tag_grid)
	_pretrain_tags_row = _label_row(tr("FIELD_TAGS"), tag_box)
	root.add_child(_pretrain_tags_row)

	# target_capability — only meaningful for posttrain.
	_target_cap_dropdown = OptionButton.new()
	_target_cap_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for axis in _AXES:
		_target_cap_dropdown.add_item(tr(String(_AXIS_LABELS[axis])))
		_target_cap_dropdown.set_item_metadata(_target_cap_dropdown.item_count - 1, axis)
	_target_cap_dropdown.select(0)
	_target_cap_dropdown.item_selected.connect(func(_i): _refresh_preview())
	_target_cap_row = _label_row(tr("COLLECT_TARGET_AXIS"), _target_cap_dropdown)
	root.add_child(_target_cap_row)

	# Posttrain-only quality tier (labor grade). Sets target_quality; cost rises
	# steeply with quality (crowd → PhD). Per design/数据集系统设计.md §5.
	_quality_tier_dropdown = OptionButton.new()
	_quality_tier_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for tier in _QUALITY_TIERS:
		_quality_tier_dropdown.add_item(tr(String(tier.label)))
		_quality_tier_dropdown.set_item_metadata(
				_quality_tier_dropdown.item_count - 1, float(tier.q))
	_quality_tier_dropdown.select(0)
	_quality_tier_dropdown.item_selected.connect(func(_i): _refresh_preview())
	_quality_tier_dropdown.tooltip_text = tr("COLLECT_TIER_TOOLTIP")
	_quality_tier_row = _label_row(tr("COLLECT_QUALITY_TIER"), _quality_tier_dropdown)
	root.add_child(_quality_tier_row)

	# Posttrain-only internal signal: employee daily work traces provide a small
	# quality bump without changing the annotation labor pricing curve.
	_employee_monitor_checkbox = CheckBox.new()
	_employee_monitor_checkbox.text = tr("COLLECT_EMPLOYEE_MONITOR")
	_employee_monitor_checkbox.tooltip_text = tr("COLLECT_EMPLOYEE_MONITOR_TOOLTIP")
	_employee_monitor_checkbox.toggled.connect(func(_p): _refresh_preview())
	_employee_monitor_row = _label_row(tr("COLLECT_EXTRA_DATA"), _employee_monitor_checkbox)
	root.add_child(_employee_monitor_row)

	# Lead — optional, data_scientist boosts quality.
	_lead_dropdown = OptionButton.new()
	_lead_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lead_dropdown.item_selected.connect(func(_i): _refresh_preview())
	root.add_child(_label_row("Lead", _lead_dropdown))

	# v8: 自采数据集硬性占用数据工程师 — 展示需求 + 空闲数。
	_staff_label = Label.new()
	_staff_label.add_theme_color_override(&"font_color", UITheme.TEXT_SECONDARY)
	root.add_child(_staff_label)

func _build_preview(root: VBoxContainer) -> void:
	var sec := Label.new()
	sec.text = tr("FIELD_PREVIEW")
	sec.add_theme_color_override(&"font_color", UITheme.ACCENT_INFO)
	root.add_child(sec)
	_duration_label = Label.new()
	root.add_child(_duration_label)
	_cost_label = Label.new()
	root.add_child(_cost_label)
	_quality_label = Label.new()
	root.add_child(_quality_label)
	_tags_label = Label.new()
	_tags_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_tags_label)
	_summary_label = Label.new()
	_summary_label.add_theme_color_override(&"font_color", UITheme.ACCENT_PRIMARY)
	_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_summary_label)
	_warning_label = Label.new()
	_warning_label.add_theme_color_override(&"font_color", UITheme.ACCENT_DANGER)
	_warning_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_warning_label)

func _label_row(label_text: String, control: Control) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 6)
	var l := Label.new()
	l.text = label_text
	l.custom_minimum_size = Vector2(80, 0)
	row.add_child(l)
	row.add_child(control)
	return row

# ---- kind switch ---------------------------------------------------------

func _set_kind(new_kind: StringName) -> void:
	if _kind == new_kind:
		# Keep at least one checkbox checked even if the user clicks the same
		# one to deselect.
		_apply_kind_to_widgets()
		return
	_kind = new_kind
	_apply_kind_to_widgets()
	_refresh_preview()

# Sync checkbox visual state, size range, target-cap visibility from _kind.
func _apply_kind_to_widgets() -> void:
	# Block toggled signals while we set state to avoid recursive _set_kind.
	_kind_pretrain_btn.set_block_signals(true)
	_kind_posttrain_btn.set_block_signals(true)
	_kind_pretrain_btn.button_pressed = (_kind == _KIND_PRETRAIN)
	_kind_posttrain_btn.button_pressed = (_kind == _KIND_POSTTRAIN)
	_kind_pretrain_btn.set_block_signals(false)
	_kind_posttrain_btn.set_block_signals(false)
	_target_cap_row.visible = (_kind == _KIND_POSTTRAIN)
	if _quality_tier_row != null:
		_quality_tier_row.visible = (_kind == _KIND_POSTTRAIN)
	if _employee_monitor_row != null:
		_employee_monitor_row.visible = (_kind == _KIND_POSTTRAIN)
	if _pretrain_tags_row != null:
		_pretrain_tags_row.visible = (_kind == _KIND_PRETRAIN)
	_size_spin.set_block_signals(true)
	if _kind == _KIND_POSTTRAIN:
		_size_spin.min_value = 0.01
		_size_spin.max_value = 0.5
		_size_spin.step = 0.01
		if _size_spin.value < 0.01 or _size_spin.value > 0.5:
			_size_spin.value = 0.05
		_size_hint.text = tr("COLLECT_SIZE_HINT_POST")
	else:
		# pretrain 自采: 上限 100,000 B tokens = 100T, 覆盖到后期超大规模语料采集
		# (FineWeb ≈ 15T 只占 1/7)。pricing/duration 公式 (size/100 周, 5k+5k×size)
		# 不变, 走到 100T 时自然按比例放大 — player 自己取舍。
		_size_spin.min_value = 1
		_size_spin.max_value = 100000
		_size_spin.step = 1
		if _size_spin.value < 1 or _size_spin.value > 100000:
			_size_spin.value = 10
		_size_hint.text = tr("COLLECT_SIZE_HINT_PRE")
	_size_spin.set_block_signals(false)

# ---- populate widgets ----------------------------------------------------

## Per design/招聘系统设计.md §5.4: data_collection_dynamic 强制 data_scientist.
## 只列匹配 specialty 的 idle lead (含创始人), 默认选第一位真正 data_scientist;
## 没有时退到创始人。
func _populate_lead_dropdown() -> void:
	_lead_dropdown.clear()
	var first_match: int = -1
	var founder_index: int = -1
	for lead in GameState.leads:
		if not lead.is_idle():
			continue
		if not HiringSystem.lead_matches_specialty(lead, &"data_scientist"):
			continue
		var suffix: String = tr("CAMPAIGN_FOUNDER_SUFFIX") if lead.is_player_scientist else ""
		var idx := _lead_dropdown.item_count
		# 下拉已按 specialty 过滤 (data_scientist), 不再露出 raw 枚举。
		_lead_dropdown.add_item(tr("CAMPAIGN_LEAD_ITEM") % [
				NameRomanizer.localized(lead.display_name), String(lead.level),
				float(lead.ability), suffix])
		_lead_dropdown.set_item_metadata(idx, lead.id)
		if lead.is_player_scientist:
			if founder_index < 0:
				founder_index = idx
		else:
			if first_match < 0:
				first_match = idx
	if _lead_dropdown.item_count == 0:
		_lead_dropdown.add_item(tr("COLLECT_NO_LEAD"))
		_lead_dropdown.set_item_metadata(0, &"")
		_lead_dropdown.select(0)
	else:
		_lead_dropdown.select(first_match if first_match >= 0 else founder_index)

# ---- preview math --------------------------------------------------------

func _selected_lead_id() -> StringName:
	var i := _lead_dropdown.selected
	if i < 0:
		return &""
	var lid = _lead_dropdown.get_item_metadata(i)
	if lid == null:
		return &""
	return lid

func _selected_target_capability() -> StringName:
	if _kind != _KIND_POSTTRAIN:
		return &""
	var i := _target_cap_dropdown.selected
	if i < 0:
		return _AXES[0]
	return _target_cap_dropdown.get_item_metadata(i)

# Posttrain quality tier → target_quality. Pretrain has no labor grade (web
# scrape, fixed 0.55 base).
func _selected_target_quality() -> float:
	if _kind != _KIND_POSTTRAIN or _quality_tier_dropdown == null:
		return 0.55
	var i := _quality_tier_dropdown.selected
	if i < 0:
		return 0.65
	return float(_quality_tier_dropdown.get_item_metadata(i))

func _uses_employee_work_monitoring() -> bool:
	return _kind == _KIND_POSTTRAIN \
			and _employee_monitor_checkbox != null \
			and _employee_monitor_checkbox.button_pressed

func _employee_work_monitoring_bonus() -> float:
	if not _uses_employee_work_monitoring():
		return 0.0
	return TaskSystem.POSTTRAIN_EMPLOYEE_WORK_DATA_QUALITY_ADD

func _selected_pretrain_tags() -> Array[StringName]:
	var out: Array[StringName] = []
	for entry in _pretrain_tag_checkboxes:
		var cb: CheckBox = entry.box
		if cb.button_pressed:
			out.append(entry.tag)
	if out.is_empty():
		out = _PRETRAIN_TAG_DEFAULT.duplicate()
	return out

# v9: enforce max-2 by auto-disabling further checks. Triggered on every toggle.
func _on_pretrain_tag_toggled() -> void:
	var checked: int = 0
	for entry in _pretrain_tag_checkboxes:
		if (entry.box as CheckBox).button_pressed:
			checked += 1
	for entry in _pretrain_tag_checkboxes:
		var cb: CheckBox = entry.box
		cb.disabled = (not cb.button_pressed) and (checked >= _PRETRAIN_TAG_MAX)
	_refresh_preview()

func _selected_modality() -> StringName:
	if _modality_dropdown == null:
		return &"text"
	var i := _modality_dropdown.selected
	if i < 0:
		return &"text"
	return _modality_dropdown.get_item_metadata(i)

func _build_payload() -> Dictionary:
	var lead_ids: Array = []
	var lid := _selected_lead_id()
	if lid != &"":
		lead_ids.append(lid)
	var payload: Dictionary = {
		template_id = TEMPLATE_ID,
		kind = _kind,
		target_size = float(_size_spin.value),
		lead_ids = lead_ids,
		# task_system 按 size 自算并锁定 data_eng (2..8), payload 不必指定。
		staff = {},
		# v7 PR-G: chosen single modality (text default). task_system forwards it
		# to dataset.add at completion time so the new Dataset carries it.
		modality = _selected_modality(),
	}
	if _kind == _KIND_POSTTRAIN:
		payload[&"target_capability"] = _selected_target_capability()
		# Labor-grade tier → target_quality; task_system prices by effective q.
		payload[&"target_quality"] = _selected_target_quality()
		if _uses_employee_work_monitoring():
			payload[&"monitor_employee_work_data"] = true
	else:
		# v9: pretrain coverage_tags chosen by player (1-2 of the menu).
		# task_system reads `target_tags` and writes into the new Dataset.
		payload[&"target_tags"] = _selected_pretrain_tags()
	var disp: String = _name_input.text.strip_edges()
	if disp != "":
		payload[&"display_name"] = disp
	return payload

func _refresh_preview() -> void:
	var payload := _build_payload()
	var r: Dictionary = CommandBus.send(&"task.preview", payload)
	if not r.ok:
		_warning_label.text = tr("PRETRAIN_PREVIEW_FAILED") % String(r.get(&"error", &"unknown"))
		_duration_label.text = ""
		_cost_label.text = ""
		_quality_label.text = ""
		_tags_label.text = ""
		_summary_label.text = ""
		get_ok_button().disabled = true
		return

	var size_b: float = float(payload.get(&"target_size", 0.0))
	var weeks: int = int(r.get(&"total_weeks", 0))
	var base_cost: int = int(r.get(&"total_cost", 0))
	var weekly: int = int(r.get(&"weekly_cost", 0))
	_duration_label.text = tr("COLLECT_DURATION") % weeks
	if weekly > 0:
		_cost_label.text = tr("COLLECT_COST_RECUR") % [
				_money(base_cost), _money(weekly),
				_money(base_cost + weekly * weeks)]
	else:
		_cost_label.text = tr("COLLECT_COST") % _money(base_cost)

	# Mirror task_system._data_collection_quality for the quality preview.
	# Posttrain base = selected labor-grade tier; pretrain fixed 0.55.
	var base_q: float = (_selected_target_quality() if _kind == _KIND_POSTTRAIN else 0.55)
	var quality: float = _preview_quality(
			base_q, _selected_lead_id(), _employee_work_monitoring_bonus())
	_quality_label.text = tr("COLLECT_QUALITY") % [
			quality, base_q, _quality_bonus_hint()]

	var tags: Array
	if _kind == _KIND_POSTTRAIN:
		tags = [_selected_target_capability(), &"instruction"]
	else:
		tags = _selected_pretrain_tags()
	var tag_strs: Array = []
	for t in tags:
		tag_strs.append(String(t))
	_tags_label.text = tr("COLLECT_TAGS") % ", ".join(tag_strs)

	var name_for_preview: String = _name_input.text.strip_edges()
	if name_for_preview == "":
		name_for_preview = tr("COLLECT_AUTO_NAME")
	if _kind == _KIND_POSTTRAIN:
		var axis_label: String = tr(String(_AXIS_LABELS.get(_selected_target_capability(), "?")))
		_summary_label.text = tr("COLLECT_SUMMARY_POST") % [
				name_for_preview, size_b, quality, axis_label]
	else:
		var tag_summary: Array = []
		for t in _selected_pretrain_tags():
			tag_summary.append(String(t))
		_summary_label.text = tr("COLLECT_SUMMARY_PRE") % [
				name_for_preview, size_b, quality, ", ".join(tag_summary)]

	# v8: 数据工程师硬性要求, 数量随数据集 size 缩放 (2..8) — 展示需求/空闲, 不足则拦截。
	var need_staff: int = TaskSystem.data_collection_staff_count(_kind, size_b)
	var idle_staff: int = int(GameState.staff_pool.get(&"data_eng", 0)) \
			- int(GameState.staff_busy.get(&"data_eng", 0))
	_staff_label.text = tr("COLLECT_STAFF_REQ") % [need_staff, idle_staff]

	# Cash check + button enable.
	var problems: Array = []
	if size_b <= 0.0:
		problems.append(tr("COLLECT_ERR_SIZE"))
	if base_cost > GameState.cash:
		problems.append(tr("DC_WARN_CASH") % [
				_money(base_cost), _money(GameState.cash)])
	# Per design/招聘系统设计.md §5.4: data_collection_dynamic 强制 data_scientist.
	if _selected_lead_id() == &"":
		problems.append(tr("COLLECT_ERR_LEAD"))
	if need_staff > 0 and idle_staff < need_staff:
		problems.append(tr("COLLECT_ERR_STAFF") % [need_staff, idle_staff])
	if problems.is_empty():
		_warning_label.text = ""
		get_ok_button().disabled = false
	else:
		_warning_label.text = tr("WARN_PREFIX") + " · ".join(problems)
		get_ok_button().disabled = true

# Mirror task_system._data_collection_quality so preview matches apply.
func _preview_quality(base: float, lead_id: StringName, option_bonus: float = 0.0) -> float:
	if lead_id == &"":
		return clampf(base + option_bonus, 0.0, 1.0)
	var lead = HiringSystem.find_lead(lead_id)
	if lead == null or lead.specialty != &"data_scientist":
		return clampf(base + option_bonus, 0.0, 1.0)
	var table: Dictionary = HiringSystem.LEAD_BONUS_TABLE.get(&"data_scientist", {})
	var coef: float = float(table.get(&"data_quality_add", 0.0))
	var bonus: float = (float(lead.ability) / 100.0) * coef
	return clampf(base + bonus + option_bonus, 0.0, 1.0)

func _quality_bonus_hint() -> String:
	var hint: String = _lead_quality_hint()
	if _uses_employee_work_monitoring():
		hint += tr("COLLECT_EMPLOYEE_MONITOR_HINT") \
				% TaskSystem.POSTTRAIN_EMPLOYEE_WORK_DATA_QUALITY_ADD
	return hint

func _lead_quality_hint() -> String:
	var lid := _selected_lead_id()
	if lid == &"":
		return tr("COLLECT_LEAD_HINT1")
	var lead = HiringSystem.find_lead(lid)
	if lead == null:
		return ""
	if lead.specialty != &"data_scientist":
		return tr("COLLECT_LEAD_HINT2")
	return tr("COLLECT_LEAD_HINT3")

# ---- start ---------------------------------------------------------------

func _on_start_pressed() -> void:
	var payload := _build_payload()
	var r: Dictionary = CommandBus.send(&"task.start", payload)
	if r.ok:
		Log.info(&"ui", "DatasetCollectionDialog launched task", {
				task_id = r.get(&"task_id", &""), kind = _kind,
				size = payload.get(&"target_size", 0.0),
				monitor_employee_work_data = payload.get(&"monitor_employee_work_data", false)})
		task_started_via_dialog.emit(r)
		hide()
	else:
		var err: String = String(r.get(&"error", &"unknown"))
		Log.warn(&"ui", "DatasetCollectionDialog start failed", {error = err})
		_warning_label.text = tr("CAMPAIGN_START_FAILED") % err
		get_ok_button().disabled = true

# ---- formatting ---------------------------------------------------------

func _money(n) -> String:
	var v: int = int(n)
	var s: String = str(absi(v))
	var out: String = ""
	var i: int = s.length()
	while i > 3:
		out = "," + s.substr(i - 3, 3) + out
		i -= 3
	out = s.substr(0, i) + out
	return ("-" + out) if v < 0 else out
