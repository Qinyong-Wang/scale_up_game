extends Control

## FilterBar — 状态 pills + 搜索 + 排序。
##
## 设计:
##   - pills 第一个是 "all-pill" (在调用方语义里通常叫"全部"), 互斥其余。
##   - 点 all-pill: 清空其他选择, 仅留 all。
##   - 点其他 pill: 切换选中, 同时取消 all。
##   - 切换后若无任何 pill 选中, 自动回到 all (避免"全空"无意义态)。
##   - 搜索框 / 排序下拉的任何变化都触发 state_changed。
##
## 调用方文案均为已翻译字符串 (国际化设计.md §6); 组件不调 tr()。

signal state_changed(state: Dictionary)

var _pills: Array = []  # 拷贝的 pills 配置, 每项含 id / label / count?
var _selected: Dictionary = {}  # StringName -> bool
var _all_id: StringName = &""    # 第一个 pill 的 id, 互斥参考
var _sort_options: Array = []
var _selected_sort: StringName = &""

var _pill_row: HBoxContainer
var _pill_buttons: Dictionary = {}  # StringName -> Button
var _search_input: LineEdit
var _sort_button: OptionButton

func _ready() -> void:
	custom_minimum_size.y = max(custom_minimum_size.y, 36)

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override(&"separation", UITheme.S_3)
	add_child(row)

	_pill_row = HBoxContainer.new()
	_pill_row.add_theme_constant_override(&"separation", UITheme.S_1)
	row.add_child(_pill_row)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	_search_input = LineEdit.new()
	_search_input.custom_minimum_size.x = 160
	_search_input.text_changed.connect(_on_search_changed)
	row.add_child(_search_input)

	_sort_button = OptionButton.new()
	_sort_button.item_selected.connect(_on_sort_item_selected)
	_sort_button.visible = false  # 没注入 sort_options 之前隐藏
	row.add_child(_sort_button)

## pills: Array[Dictionary], 每项 {id: StringName, label: String, count: int (可选)}
## 第一项为 all-pill, 互斥其余。
func set_pills(pills: Array) -> void:
	_pills = pills.duplicate(true)
	_selected.clear()
	for child in _pill_row.get_children():
		child.queue_free()
	_pill_buttons.clear()
	if pills.is_empty():
		_all_id = &""
		_emit_state()
		return
	_all_id = StringName(pills[0]["id"])
	for spec in pills:
		var id: StringName = StringName(spec["id"])
		var label: String = spec["label"]
		var count: int = spec.get("count", -1)
		var btn := Button.new()
		btn.toggle_mode = true
		btn.text = "%s (%d)" % [label, count] if count >= 0 else label
		btn.pressed.connect(_on_pill_pressed.bind(id))
		_pill_row.add_child(btn)
		_pill_buttons[id] = btn
	# 默认 all-pill 选中。
	_set_selected_internal({_all_id: true})
	_emit_state()

## sort_options: Array[Dictionary], 每项 {id: StringName, label: String}
func set_sort_options(opts: Array) -> void:
	_sort_options = opts.duplicate(true)
	_sort_button.clear()
	if opts.is_empty():
		_sort_button.visible = false
		_selected_sort = &""
		return
	for spec in opts:
		_sort_button.add_item(spec["label"])
	_sort_button.visible = true
	_sort_button.select(0)
	_selected_sort = StringName(opts[0]["id"])

func set_search_placeholder(s: String) -> void:
	if _search_input != null:
		_search_input.placeholder_text = s

## 收起 / 展开搜索框 (基建等只筛 pill 的 tab 不需要搜索)。
func set_search_visible(v: bool) -> void:
	if _search_input != null:
		_search_input.visible = v

## 仅刷新 pill 计数文案, 不重置选中态 (refresh 时调用)。
## counts: StringName -> int; 缺省的 pill 退回纯 label。
func update_pill_counts(counts: Dictionary) -> void:
	for spec in _pills:
		var id: StringName = StringName(spec["id"])
		if not _pill_buttons.has(id):
			continue
		var label: String = spec["label"]
		var btn: Button = _pill_buttons[id]
		if counts.has(id):
			btn.text = "%s (%d)" % [label, int(counts[id])]
		else:
			btn.text = label

func get_state() -> Dictionary:
	var sel: Array = []
	for id in _selected.keys():
		if _selected[id]:
			sel.append(id)
	return {
		"selected_pills": sel,
		"search": _search_input.text if _search_input != null else "",
		"sort": _selected_sort,
	}

# ─── 内部 ────────────────────────────────────────────────────

func _on_pill_pressed(id: StringName) -> void:
	if id == _all_id:
		# 点 all → 互斥所有其他, 仅留 all。
		_set_selected_internal({_all_id: true})
	else:
		# 点具体 pill: toggle, 同时取消 all。
		var new_sel := _selected.duplicate()
		new_sel.erase(_all_id)
		if new_sel.get(id, false):
			new_sel.erase(id)
		else:
			new_sel[id] = true
		# 取消后全空 → 回到 all。
		if new_sel.is_empty():
			new_sel[_all_id] = true
		_set_selected_internal(new_sel)
	_emit_state()

func _set_selected_internal(new_sel: Dictionary) -> void:
	_selected = new_sel
	for id in _pill_buttons.keys():
		var btn: Button = _pill_buttons[id]
		btn.button_pressed = _selected.get(id, false)

func _on_search_changed(_text: String) -> void:
	_emit_state()

func _on_sort_item_selected(idx: int) -> void:
	if idx < 0 or idx >= _sort_options.size():
		return
	_selected_sort = StringName(_sort_options[idx]["id"])
	_emit_state()

func _emit_state() -> void:
	state_changed.emit(get_state())

# ─── 测试 introspection ──────────────────────────────────────

func get_pill_count() -> int:
	return _pill_buttons.size()

func get_pill_text_for_test(id: StringName) -> String:
	var btn: Button = _pill_buttons.get(id, null)
	return btn.text if btn != null else ""

func click_pill_for_test(id: StringName) -> void:
	if not _pill_buttons.has(id):
		push_error("FilterBar: pill not found %s" % id)
		return
	_on_pill_pressed(id)

func set_search_text_for_test(s: String) -> void:
	if _search_input != null:
		_search_input.text = s
		_on_search_changed(s)

func select_sort_for_test(id: StringName) -> void:
	for i in range(_sort_options.size()):
		if StringName(_sort_options[i]["id"]) == id:
			_sort_button.select(i)
			_on_sort_item_selected(i)
			return

func get_search_placeholder() -> String:
	return _search_input.placeholder_text if _search_input != null else ""
