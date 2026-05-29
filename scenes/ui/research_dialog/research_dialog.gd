extends ConfirmationDialog

## ResearchDialog v6 (PR-D) — 启动 tech_research task 对话框.
## Per design/科技树系统设计.md §5.2.
##
## 流程:
##   1. 科技 tab 上一个节点的「研究」按钮 → 创建本对话框 → setup(tree, node_id) → popup_centered.
##   2. 玩家选 Lead (可选, 仅 chief_scientist 给加速) + 研究员/工程师人数 + datacenter.
##   3. 任意控件变化触发 task.preview 刷新时长预览.
##   4. 点「开始研究」→ tech.start_research 发送; 失败时把错误码贴到警告区.
##
## 资源最小值来自 TechNode.min_researchers / min_engineers / min_gpu_count;
## SpinBox.min_value 在 _setup 里写死, max_value 跟 staff_pool 实时联动.

signal task_started_via_dialog(result: Dictionary)


# 入参 (在 _ready 之前由 setup() 写入).
var _tree: StringName = &""
var _node_id: StringName = &""
var _node: TechNode = null

# 控件
var _info_label: Label
var _lead_dropdown: OptionButton
var _ml_eng_spin: SpinBox
var _ml_eng_hint: Label
var _infra_eng_spin: SpinBox
var _infra_eng_hint: Label
var _dc_dropdown: OptionButton
var _duration_label: Label
var _warning_label: Label
var _built: bool = false

func setup(tree: StringName, node_id: StringName) -> void:
	_tree = tree
	_node_id = node_id

func _ready() -> void:
	title = tr("RESEARCH_START")
	min_size = Vector2i(720, 540)
	max_size = Vector2i(960, 680)
	dialog_hide_on_ok = false
	get_ok_button().text = tr("RESEARCH_START")
	get_cancel_button().text = tr("ACTION_CANCEL")
	get_ok_button().pressed.connect(_on_start_pressed)

	if TechTreeSystem != null:
		_node = TechTreeSystem.get_node_template(_node_id)
	if _node == null:
		# Fall back to direct load when registered NODES table didn't include
		# this id (e.g. test setups using ad-hoc nodes).
		push_warning("ResearchDialog: node %s not in TechTreeSystem.NODES" % [_node_id])

	if title:
		title = tr("RESEARCH_NODE_TITLE") % [(tr(_node.display_name) if _node != null else String(_node_id))]

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(690, 480)
	add_child(scroll)

	var root := VBoxContainer.new()
	root.add_theme_constant_override(&"separation", 8)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(root)

	_build_info_block(root)
	root.add_child(HSeparator.new())
	_build_form_rows(root)
	root.add_child(HSeparator.new())
	_build_preview_block(root)

	_built = true
	refresh()
	Log.info(&"ui", "ResearchDialog ready", {tree = _tree, node = _node_id})

func refresh() -> void:
	if not _built or _node == null:
		return
	_populate_lead_dropdown()
	_populate_staff_spins()
	_populate_dc_dropdown()
	_refresh_preview()

# ---- info / form / preview blocks --------------------------------------

func _build_info_block(root: VBoxContainer) -> void:
	_info_label = Label.new()
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_label.add_theme_color_override(&"font_color", UITheme.ACCENT_INFO)
	root.add_child(_info_label)
	var effects := Label.new()
	effects.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	effects.add_theme_color_override(&"font_color", UITheme.ACCENT_WARNING)
	effects.text = tr("RESEARCH_EFFECTS") % [(tr(_node.effects_summary) if _node != null else "")]
	root.add_child(effects)
	var desc := Label.new()
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_color_override(&"font_color", UITheme.TEXT_SECONDARY)
	desc.text = (tr(_node.description) if _node != null else "")
	root.add_child(desc)
	# Refresh info text once we know min_* values.
	if _node != null:
		_info_label.text = tr("RESEARCH_INFO") % [
			_format_prereqs(),
			_node.research_months,
			_node.min_researchers,
			_node.min_engineers,
			_node.min_gpu_count,
		]

func _format_prereqs() -> String:
	if _node == null or _node.prerequisites.is_empty():
		return tr("MSG_NONE")
	var parts: PackedStringArray = []
	for p in _node.prerequisites:
		parts.append(String(p))
	return ", ".join(parts)

func _build_form_rows(root: VBoxContainer) -> void:
	# Lead (optional; chief_scientist gives research_speed bonus).
	_lead_dropdown = OptionButton.new()
	_lead_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lead_dropdown.item_selected.connect(func(_i): _refresh_preview())
	root.add_child(_label_row("Lead", _lead_dropdown))

	# Researchers (ml_eng).
	var ml_row := HBoxContainer.new()
	ml_row.add_theme_constant_override(&"separation", 6)
	var ml_label := Label.new()
	ml_label.text = tr("ROLE_RESEARCHER")
	ml_label.custom_minimum_size = Vector2(80, 0)
	ml_row.add_child(ml_label)
	_ml_eng_spin = SpinBox.new()
	_ml_eng_spin.step = 1
	_ml_eng_spin.value_changed.connect(func(_v): _refresh_preview())
	ml_row.add_child(_ml_eng_spin)
	_ml_eng_hint = Label.new()
	_ml_eng_hint.add_theme_color_override(&"font_color", UITheme.TEXT_SECONDARY)
	ml_row.add_child(_ml_eng_hint)
	root.add_child(ml_row)

	# Engineers (infra_eng).
	var ie_row := HBoxContainer.new()
	ie_row.add_theme_constant_override(&"separation", 6)
	var ie_label := Label.new()
	ie_label.text = tr("ROLE_ENGINEER")
	ie_label.custom_minimum_size = Vector2(80, 0)
	ie_row.add_child(ie_label)
	_infra_eng_spin = SpinBox.new()
	_infra_eng_spin.step = 1
	_infra_eng_spin.value_changed.connect(func(_v): _refresh_preview())
	ie_row.add_child(_infra_eng_spin)
	_infra_eng_hint = Label.new()
	_infra_eng_hint.add_theme_color_override(&"font_color", UITheme.TEXT_SECONDARY)
	ie_row.add_child(_infra_eng_hint)
	root.add_child(ie_row)

	# Datacenter (idle + gpu_count >= min_gpu_count).
	_dc_dropdown = OptionButton.new()
	_dc_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dc_dropdown.item_selected.connect(func(_i): _refresh_preview())
	root.add_child(_label_row(tr("FIELD_DATACENTER"), _dc_dropdown))

func _label_row(label_text: String, control: Control) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 6)
	var l := Label.new()
	l.text = label_text
	l.custom_minimum_size = Vector2(80, 0)
	row.add_child(l)
	row.add_child(control)
	return row

func _build_preview_block(root: VBoxContainer) -> void:
	_duration_label = Label.new()
	_duration_label.add_theme_color_override(&"font_color", UITheme.ACCENT_PRIMARY)
	root.add_child(_duration_label)
	_warning_label = Label.new()
	_warning_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_warning_label.add_theme_color_override(&"font_color", UITheme.ACCENT_WARNING)
	root.add_child(_warning_label)

# ---- populate -----------------------------------------------------------

## 只列对研究有意义的 idle lead — 即带 research_speed 加成的 specialty
## (当前仅 chief_scientist), 外加创始人 (player_scientist 万能但无加成)。
## 其他方向 (ml_research_lead / eval / 工程 / 数据 / 营销) 的 lead 对
## tech_research 不给任何加速, 列出来只会误导玩家选错人, 故直接过滤掉。
## 判定走 HiringSystem.lead_bonus_coef 数据驱动, 加成表变了无需改这里。
## Per design/科技树系统设计.md §5.2。
func _populate_lead_dropdown() -> void:
	_lead_dropdown.clear()
	_lead_dropdown.add_item(tr("RESEARCH_NO_LEAD"))
	_lead_dropdown.set_item_metadata(0, &"")
	var first_cs_index: int = -1
	for l in GameState.leads:
		if not l.is_idle():
			continue
		# 数据驱动判定: 带 research_speed bonus 的 specialty 才是研究方向。
		var is_research: bool = HiringSystem.lead_bonus_coef(l, &"research_speed") > 0.0
		if not l.is_player_scientist and not is_research:
			continue
		var suffix: String = tr("CAMPAIGN_FOUNDER_SUFFIX") if l.is_player_scientist else ""
		# 研究下拉本就限定带 research_speed 的 specialty (chief_scientist + 创始人),
		# 不必再露出 raw 枚举。
		var label := tr("CAMPAIGN_LEAD_ITEM") % [
			NameRomanizer.localized(l.display_name), String(l.level), l.ability, suffix]
		_lead_dropdown.add_item(label)
		_lead_dropdown.set_item_metadata(_lead_dropdown.item_count - 1, l.id)
		if l.specialty == &"chief_scientist" and first_cs_index < 0:
			first_cs_index = _lead_dropdown.item_count - 1
	_lead_dropdown.select(first_cs_index if first_cs_index > 0 else 0)

func _populate_staff_spins() -> void:
	if _node == null:
		return
	# D-4: 可用 < 最少时, hint 标红 + 显示 "当前不足"。
	# ml_eng
	var ml_pool: int = int(GameState.staff_pool.get(&"ml_eng", 0))
	var ml_busy: int = int(GameState.staff_busy.get(&"ml_eng", 0))
	var ml_avail: int = max(0, ml_pool - ml_busy)
	_ml_eng_spin.min_value = _node.min_researchers
	_ml_eng_spin.max_value = max(_node.min_researchers, ml_avail)
	_ml_eng_spin.value = _node.min_researchers
	if ml_avail < _node.min_researchers:
		_ml_eng_hint.text = tr("RESEARCH_HINT_SHORT") % [
				_node.min_researchers, ml_avail, _node.min_researchers - ml_avail]
		_ml_eng_hint.add_theme_color_override(&"font_color", UITheme.ACCENT_DANGER)
	else:
		_ml_eng_hint.text = tr("RESEARCH_HINT") % [_node.min_researchers, ml_avail]
		_ml_eng_hint.add_theme_color_override(&"font_color", UITheme.TEXT_SECONDARY)
	# infra_eng
	var ie_pool: int = int(GameState.staff_pool.get(&"infra_eng", 0))
	var ie_busy: int = int(GameState.staff_busy.get(&"infra_eng", 0))
	var ie_avail: int = max(0, ie_pool - ie_busy)
	_infra_eng_spin.min_value = _node.min_engineers
	_infra_eng_spin.max_value = max(_node.min_engineers, ie_avail)
	_infra_eng_spin.value = _node.min_engineers
	if ie_avail < _node.min_engineers:
		_infra_eng_hint.text = tr("RESEARCH_HINT_SHORT") % [
				_node.min_engineers, ie_avail, _node.min_engineers - ie_avail]
		_infra_eng_hint.add_theme_color_override(&"font_color", UITheme.ACCENT_DANGER)
	else:
		_infra_eng_hint.text = tr("RESEARCH_HINT") % [_node.min_engineers, ie_avail]
		_infra_eng_hint.add_theme_color_override(&"font_color", UITheme.TEXT_SECONDARY)

func _populate_dc_dropdown() -> void:
	_dc_dropdown.clear()
	_dc_dropdown.add_item(tr("RESEARCH_NO_DC"))
	_dc_dropdown.set_item_metadata(0, &"")
	var first_idx: int = -1
	if _node == null:
		return
	for dc in GameState.datacenters:
		if dc.status != &"idle":
			continue
		var have_gpu: int = int(dc.gpu_count) if "gpu_count" in dc else 0
		if have_gpu < _node.min_gpu_count:
			continue
		var label := tr("RESEARCH_DC_ITEM") % [dc.display_label(), have_gpu]
		_dc_dropdown.add_item(label)
		_dc_dropdown.set_item_metadata(_dc_dropdown.item_count - 1, dc.id)
		if first_idx < 0:
			first_idx = _dc_dropdown.item_count - 1
	if first_idx >= 0:
		_dc_dropdown.select(first_idx)
	else:
		_dc_dropdown.select(0)

# ---- preview ------------------------------------------------------------

func _refresh_preview() -> void:
	if _node == null:
		_duration_label.text = ""
		_warning_label.text = tr("RESEARCH_UNKNOWN_NODE") % [_node_id]
		get_ok_button().disabled = true
		return
	var payload := _build_payload()
	# Use task.preview to apply lead_speedup against the node-defined duration.
	var preview_payload := payload.duplicate(true)
	preview_payload[&"template_id"] = &"tech_research_default"
	var r: Dictionary = CommandBus.send(&"task.preview", preview_payload)
	var base: int = _node.research_months
	var weeks: int = base
	if r.ok:
		weeks = int(r.total_weeks)
	var lead_label: String = tr("RESEARCH_NO_SPEEDUP")
	if base > 0 and weeks < base:
		lead_label = "Lead ×%.2f" % (float(base) / float(weeks))
	_duration_label.text = tr("RESEARCH_DURATION") % [weeks, base, lead_label]

	# Validate selection locally so we can disable the Start button with a
	# helpful message before TaskSystem rejects it.
	var msg := _validate_local(payload)
	_warning_label.text = msg
	get_ok_button().disabled = (msg != "")

func _validate_local(payload: Dictionary) -> String:
	if _node == null:
		return tr("RESEARCH_UNKNOWN")
	var staff: Dictionary = payload.get(&"staff", {})
	if int(staff.get(&"ml_eng", 0)) < _node.min_researchers:
		return tr("RESEARCH_NEED_RESEARCHERS") % [_node.min_researchers]
	if int(staff.get(&"infra_eng", 0)) < _node.min_engineers:
		return tr("RESEARCH_NEED_ENGINEERS") % [_node.min_engineers]
	var dc_id: StringName = payload.get(&"datacenter_id", &"")
	if dc_id == &"":
		# D-5: 告诉玩家当前最大 DC 多少卡, 差多少, 避免他自己去 infra tab 倒算。
		return tr("RESEARCH_NEED_DC") % [
				_node.min_gpu_count, _largest_dc_summary()]
	return ""

# D-5: 取 idle DC 中卡数最多的, 给出差距摘要。"当前最大 X 卡, 差 Y 卡" 或
# "尚无空闲数据中心"。
func _largest_dc_summary() -> String:
	var best: int = -1
	for dc in GameState.datacenters:
		if dc.status != &"idle":
			continue
		var n: int = int(dc.gpu_count) if "gpu_count" in dc else 0
		if n > best:
			best = n
	if best < 0:
		return tr("RESEARCH_NO_IDLE_DC")
	if _node == null:
		return tr("RESEARCH_DC_MAX") % best
	var need: int = _node.min_gpu_count
	if best >= need:
		return tr("RESEARCH_DC_MAX_OK") % best
	return tr("RESEARCH_DC_SHORT") % [best, need - best]

func _build_payload() -> Dictionary:
	var lead_id: StringName = _lead_dropdown.get_selected_metadata() if _lead_dropdown.item_count > 0 else &""
	var lead_ids: Array = []
	if lead_id != &"":
		lead_ids.append(lead_id)
	var dc_id: StringName = _dc_dropdown.get_selected_metadata() if _dc_dropdown.item_count > 0 else &""
	return {
		tree = _tree,
		node_id = _node_id,
		target_node_id = _node_id,    # for task.preview / task.start downstream
		lead_ids = lead_ids,
		staff = {
			&"ml_eng": int(_ml_eng_spin.value),
			&"infra_eng": int(_infra_eng_spin.value),
		},
		datacenter_id = dc_id,
	}

# ---- start --------------------------------------------------------------

func _on_start_pressed() -> void:
	var payload := _build_payload()
	var r: Dictionary = CommandBus.send(&"tech.start_research", payload)
	if not r.ok:
		_warning_label.text = tr("CAMPAIGN_START_FAILED") % String(r.get(&"error", &"unknown"))
		Log.warn(&"ui", "ResearchDialog start failed", r)
		return
	task_started_via_dialog.emit(r)
	hide()
	queue_free()
