extends VBoxContainer

## LeaderboardView — 竞争对手"荣耀榜单"视图 (design/竞争对手系统设计.md §8)。
##
## 取代 main.gd 旧的 _render_market_tab 纯文本渲染。布局:
##   SectionHeader  hero 标题 (含玩家总榜最佳名次)
##   picker         8 棵榜 toggle 按钮组 (当前榜按下态) → board_selected
##   rule_label     该榜规则说明 (dim)
##   rows           LeaderboardRow 列表 或 空榜提示
##
## 纯渲染 — 不调 tr(), 文案由 main.gd::_build_leaderboard_view_data() 翻译后经
## refresh(data) 传入 (与 ProductView 同 pull 模型, 见 §8.2 数据契约)。

signal board_selected(board_id: StringName)

const SectionHeaderScene := preload("res://scenes/ui/components/section_header/section_header.tscn")
const LeaderboardRow := preload("res://scenes/ui/views/leaderboard_view/leaderboard_row.gd")

var _header: Control
var _picker: HFlowContainer
var _rule_label: Label
var _rows_box: VBoxContainer
var _empty_label: Label

var _rows: Array = []                 # 测试 introspection: 当前 LeaderboardRow 列表
var _picker_buttons: Dictionary = {}  # board_id → Button

func _ready() -> void:
	add_theme_constant_override(&"separation", UITheme.S_3)
	# 竖排榜单宽度收口到 LIST_MAX_W 并左对齐, 不随窗口铺满整屏 (见 design §9)。
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size.x = float(UITheme.LIST_MAX_W)

	_header = SectionHeaderScene.instantiate()
	add_child(_header)
	_header.set_data("", -1, "", &"")

	_picker = HFlowContainer.new()
	_picker.add_theme_constant_override(&"h_separation", 6)
	_picker.add_theme_constant_override(&"v_separation", 4)
	add_child(_picker)

	_rule_label = Label.new()
	_rule_label.add_theme_color_override(&"font_color", UITheme.TEXT_SECONDARY)
	_rule_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_rule_label)

	_rows_box = VBoxContainer.new()
	_rows_box.add_theme_constant_override(&"separation", UITheme.S_1)
	_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_rows_box)

	_empty_label = Label.new()
	_empty_label.add_theme_color_override(&"font_color", UITheme.TEXT_SECONDARY)
	_empty_label.visible = false
	add_child(_empty_label)

func refresh(data: Dictionary) -> void:
	_header.set_data(String(data.get("header_title", "")), -1, "", &"")

	_build_picker(data.get("boards", []), StringName(data.get("active_board", &"")))

	_rule_label.text = String(data.get("rule_text", ""))
	_rule_label.visible = not _rule_label.text.is_empty()

	_clear(_rows_box)
	_rows.clear()
	var entries: Array = data.get("entries", [])
	_empty_label.text = String(data.get("empty_hint", ""))
	_empty_label.visible = entries.is_empty()
	for e in entries:
		var row: PanelContainer = LeaderboardRow.new()
		_rows_box.add_child(row)
		row.set_data(e)
		_rows.append(row)

func _build_picker(boards: Array, active: StringName) -> void:
	_clear(_picker)
	_picker_buttons.clear()
	for b in boards:
		var bid: StringName = StringName(b.get("id", &""))
		var btn := Button.new()
		btn.text = String(b.get("title", String(bid)))
		btn.toggle_mode = true
		btn.button_pressed = (bid == active)
		btn.pressed.connect(func(): board_selected.emit(bid))
		_picker.add_child(btn)
		_picker_buttons[bid] = btn

func _clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()

# ─── 测试 introspection ──────────────────────────────────────

func get_row_count() -> int:
	return _rows.size()

func get_row_for_test(idx: int) -> Node:
	if idx < 0 or idx >= _rows.size():
		return null
	return _rows[idx]

func get_rows_for_test() -> Array:
	return _rows.duplicate()

func get_header_title_for_test() -> String:
	if _header == null or not _header.has_method(&"get_title_text"):
		return ""
	return _header.get_title_text()

func get_rule_text_for_test() -> String:
	return _rule_label.text if _rule_label != null else ""

func is_empty_hint_visible() -> bool:
	return _empty_label != null and _empty_label.visible

func picker_board_ids_for_test() -> Array:
	return _picker_buttons.keys()

func picker_button_texts_for_test() -> PackedStringArray:
	var out := PackedStringArray()
	for bid in _picker_buttons:
		out.append((_picker_buttons[bid] as Button).text)
	return out

func active_board_for_test() -> StringName:
	for bid in _picker_buttons:
		if (_picker_buttons[bid] as Button).button_pressed:
			return bid
	return &""

func click_board_for_test(board_id: StringName) -> void:
	if _picker_buttons.has(board_id):
		(_picker_buttons[board_id] as Button).pressed.emit()
