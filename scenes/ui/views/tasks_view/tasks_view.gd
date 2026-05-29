extends VBoxContainer

## TasksView — 任务 tab 试点视图。
##
## 只显示进行中任务 + 进度条 + 取消按钮; 不含 launcher (设计要求, 启动入口在
## 模型/数据/科技 tab)。

signal task_action(task_id: StringName, action_id: StringName)

const SectionHeaderScene := preload("res://scenes/ui/components/section_header/section_header.tscn")
const CardScene := preload("res://scenes/ui/components/card/card.tscn")
const EmptyStateScene := preload("res://scenes/ui/components/empty_state/empty_state.tscn")

var _section: Control
var _grid: HFlowContainer
# U-11: 空状态从纯 Label "(...)" 改成 EmptyState 组件 (icon + 标题 + 提示)。
var _empty_state: Control
var _cards_by_id: Dictionary = {}
# task_id → ProgressBar; 测试 introspection 用。
var _progress_by_id: Dictionary = {}

func _ready() -> void:
	add_theme_constant_override(&"separation", UITheme.S_3)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_section = SectionHeaderScene.instantiate()
	add_child(_section)
	_section.set_data(tr("TASKS_IN_PROGRESS"), -1, "", &"")

	_grid = HFlowContainer.new()
	_grid.add_theme_constant_override(&"h_separation", UITheme.S_3)
	_grid.add_theme_constant_override(&"v_separation", UITheme.S_3)
	add_child(_grid)

	_empty_state = EmptyStateScene.instantiate()
	add_child(_empty_state)
	# CTA 留空 — 任务启动入口在「模型」「数据」「科技」tab, 这里不直开对话框。
	_empty_state.set_data(
			"▸",
			tr("TASKS_EMPTY_TITLE"),
			tr("TASKS_EMPTY_HINT"),
			"", &"")
	_empty_state.visible = false

func refresh(tasks: Array) -> void:
	_clear_children(_grid)
	_cards_by_id.clear()
	_progress_by_id.clear()
	_empty_state.visible = tasks.is_empty()
	_section.set_data(tr("TASKS_IN_PROGRESS"), tasks.size(), "", &"")
	for t in tasks:
		var card: Control = CardScene.instantiate()
		_grid.add_child(card)
		_populate_task_card(card, t)
		card.action_pressed.connect(_on_card_action.bind(StringName(t.id)))
		_cards_by_id[StringName(t.id)] = card

func _populate_task_card(card: Control, t) -> void:
	# 卡片字段把进度做成 "elapsed / total 周"; 进度条另外用 Card 的 fields 不便,
	# 这里曲折点: set_data 完事后再把 ProgressBar 拼进 card 的 body (通过私有 _fields_container).
	var subtype_label: String = _subtype_label(StringName(t.subtype))
	var fields: Array = [
		{"label": tr("FIELD_PROGRESS"), "value": tr("TASKS_PROGRESS_VALUE") % [int(t.elapsed_weeks), int(t.total_weeks)]},
	]
	for row in _resource_fields(t):
		fields.append(row)
	card.set_data({
		"title": subtype_label,
		"subtitle": _task_detail_text(t),
		"avatar": {
			"texture": IconRegistry.get_icon(&"task", StringName(t.subtype)),
			"fallback_text": subtype_label,
			"seed_id": StringName(t.id),
			"kind": &"dataset",  # 缺图回退仍复用 ▸ glyph
		},
		"status": {"label": tr("STATUS_IN_PROGRESS"), "kind": &"training"},
		"fields": fields,
		"actions": [{"id": &"cancel", "label": tr("ACTION_CANCEL")}],
	})
	# 进度条插入到 card 的 fields container 末尾。
	var fc: VBoxContainer = card.get(&"_fields_container")
	if fc != null:
		var bar := ProgressBar.new()
		bar.min_value = 0
		bar.max_value = max(1, int(t.total_weeks))
		bar.value = int(t.elapsed_weeks)
		bar.show_percentage = false
		bar.custom_minimum_size.y = 8
		fc.add_child(bar)
		_progress_by_id[StringName(t.id)] = bar

# 值为 i18n key (const 不能调 tr); _subtype_label() 翻成当前 locale。
const _SUBTYPE_LABELS := {
	&"pretrain": "TASK_SUBTYPE_PRETRAIN",
	&"posttrain": "TASK_SUBTYPE_POSTTRAIN",
	&"evaluate": "TASK_SUBTYPE_EVALUATE",
	&"data_collection": "TASK_SUBTYPE_DATA_COLLECTION",
	&"tech_research": "TASK_SUBTYPE_TECH_RESEARCH",
	&"charity": "TASK_SUBTYPE_CHARITY",
	&"simulation": "TASK_SUBTYPE_SIMULATION",
}

func _subtype_label(subtype: StringName) -> String:
	return tr(_SUBTYPE_LABELS.get(subtype, String(subtype)))

# 卡片副标题 — 优先取 completion_payload 里的目标 (模型名 / 数据集名 / 科技节点),
# 没有就回退到 base_model_id, 再没有就返回空 (Card 会自动隐藏).
func _task_detail_text(t) -> String:
	var payload: Dictionary = t.completion_payload if t.completion_payload != null else {}
	match StringName(t.subtype):
		&"pretrain":
			return String(payload.get(&"display_name", payload.get("display_name", "")))
		&"posttrain", &"evaluate":
			var mid: String = String(payload.get(&"model_id", payload.get("model_id", "")))
			if mid == "":
				mid = String(t.base_model_id)
			return mid
		&"data_collection":
			return String(payload.get(&"display_name", payload.get("display_name", "")))
		&"tech_research":
			return String(payload.get(&"node_id", payload.get("node_id", "")))
	return ""

# 资源字段拆成多行 (lead / 数据中心 / 数据集); 数据集 ≥ 3 个只显示数量, 避免挤压.
func _resource_fields(t) -> Array:
	var rows: Array = []
	if t.locked_lead_ids.size() > 0:
		var lead_text: String
		if t.locked_lead_ids.size() <= 2:
			lead_text = _lead_names(t.locked_lead_ids)
		else:
			lead_text = tr("COUNT_PEOPLE") % t.locked_lead_ids.size()
		rows.append({"label": "Lead", "value": lead_text})
	if StringName(t.locked_datacenter_id) != &"":
		rows.append({"label": tr("FIELD_DATACENTER"), "value": _dc_name(StringName(t.locked_datacenter_id))})
	if t.locked_dataset_ids.size() > 0:
		var ds_text: String
		if t.locked_dataset_ids.size() <= 2:
			ds_text = _sn_join(t.locked_dataset_ids)
		else:
			ds_text = tr("COUNT_ITEMS") % t.locked_dataset_ids.size()
		rows.append({"label": tr("FIELD_DATASET"), "value": ds_text})
	return rows

# 查 GameState 拿数据中心 display_name; 找不到回退到 id.
# 旧存档的 display_name 末尾带 " [dc_NNNN]", 沿用 dc_card 的清洗策略.
func _dc_name(dc_id: StringName) -> String:
	for dc in GameState.datacenters:
		if StringName(dc.id) == dc_id:
			return dc.display_label()  # locale 感知 (含云租名 + 旧档 id 后缀裁剪)
	return String(dc_id)

# locked_lead_ids 存内部 id (含创始人的 &"player_self"); 卡片显示 lead 真名,
# 查不到的 id 才回退原值。非 zh locale 经 NameRomanizer 转拼音 (同 lead_card.gd,
# 见 design/国际化设计.md §12)。
static func _lead_names(arr: Array) -> String:
	var parts: Array[String] = []
	for id in arr:
		var lead := HiringSystem.find_lead(StringName(id))
		if lead != null:
			parts.append(NameRomanizer.localized(String(lead.display_name)))
		else:
			parts.append(String(id))
	return ", ".join(parts)

func _sn_join(arr: Array) -> String:
	var parts: Array[String] = []
	for s in arr:
		parts.append(String(s))
	return ",".join(parts)

func _on_card_action(action_id: StringName, task_id: StringName) -> void:
	task_action.emit(task_id, action_id)

func _clear_children(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()

# ─── 测试 introspection ──────────────────────────────────────

func get_card_count() -> int:
	return _cards_by_id.size()

func get_card_actions_for_test(task_id: StringName) -> Array:
	var c: Control = _cards_by_id.get(task_id, null)
	if c == null:
		return []
	var btns: Dictionary = c.get(&"_action_buttons")
	return btns.keys() if btns != null else []

func get_card_fields_for_test(task_id: StringName) -> Dictionary:
	var c: Control = _cards_by_id.get(task_id, null)
	if c == null:
		return {}
	var fields: Dictionary = {}
	var count: int = c.get_field_count()
	for i in range(count):
		var row: Dictionary = c.get_field_row_for_test(i)
		if row.has("label"):
			fields[row.label] = row.value
	return fields

func click_card_action_for_test(task_id: StringName, action_id: StringName) -> void:
	var c: Control = _cards_by_id.get(task_id, null)
	if c != null and c.has_method(&"click_action_for_test"):
		c.click_action_for_test(action_id)

func all_button_texts_for_test() -> PackedStringArray:
	var out := PackedStringArray()
	_collect_text(self, true, out)
	return out

func all_label_texts_for_test() -> PackedStringArray:
	var out := PackedStringArray()
	_collect_text(self, false, out)
	return out

func _collect_text(node: Node, want_button: bool, out: PackedStringArray) -> void:
	for child in node.get_children():
		if want_button and child is Button:
			out.append((child as Button).text)
		elif (not want_button) and child is Label:
			out.append((child as Label).text)
		_collect_text(child, want_button, out)
