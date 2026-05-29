extends VBoxContainer

## HiringView — 招聘 tab 视图 (招聘界面拆分后的「招新」一半)。
##
## 布局:
##   [Section "创始人 (你自己)"]   ← 创始人已下场后整区隐藏
##     ↳ CTA "+ 成为创始研究员"
##   [Section "候选 Lead 池 (本周, 月底刷新)"]
##     ↳ 按 specialty 分组的 subsection 标签 + HFlow of pool cards
##
## 信号:
##   become_founder_pressed
##   lead_action(lead_id: StringName, action_id: StringName)   # hire
##
## refresh(data: Dictionary) 接 main.gd 组装好的完整 data dict (与 StaffView 同一份),
## view 内部不访问 GameState。「在册」一半 (已签约 lead / staff / 工资合计) 在 StaffView。

signal become_founder_pressed
signal lead_action(lead_id: StringName, action_id: StringName)

const SectionHeaderScene := preload("res://scenes/ui/components/section_header/section_header.tscn")
const CardScene := preload("res://scenes/ui/components/card/card.tscn")
const LeadCard := preload("res://scenes/ui/views/hiring_view/lead_card.gd")

# 招聘 tab 不需要 FilterBar; 分组少 (6 specialty), 卡片数量在控制范围内。

var _founder_section: Control
var _founder_body: VBoxContainer   # 装 CTA 按钮, refresh 时重建
var _founder_cta_btn: Button       # 当前活的按钮 (founder 未加入时); 否则 null

var _pool_section: Control
var _pool_grid_root: VBoxContainer

# lead_id -> Card 实例, 测试 introspection 用。
var _cards_by_id: Dictionary = {}

func _ready() -> void:
	add_theme_constant_override(&"separation", UITheme.S_4)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	# 创始人区。
	_founder_section = SectionHeaderScene.instantiate()
	add_child(_founder_section)
	_founder_section.set_data(tr("HIRING_FOUNDER"), -1, "", &"")

	_founder_body = VBoxContainer.new()
	_founder_body.add_theme_constant_override(&"separation", UITheme.S_2)
	add_child(_founder_body)

	# 候选池区。
	_pool_section = SectionHeaderScene.instantiate()
	add_child(_pool_section)
	_pool_section.set_data(tr("HIRING_POOL"), -1, "", &"")

	_pool_grid_root = VBoxContainer.new()
	_pool_grid_root.add_theme_constant_override(&"separation", UITheme.S_3)
	add_child(_pool_grid_root)

func refresh(data: Dictionary) -> void:
	_cards_by_id.clear()
	_refresh_founder(bool(data.get("has_founder", false)))
	_refresh_pool(data)

func _refresh_founder(has_founder: bool) -> void:
	# 每次刷新重建; 老集成测试用 _all_button_texts 不过滤 visible, 必须真正把
	# 按钮从树里摘掉, 文案才不被搜集到。
	_clear_children(_founder_body)
	_founder_cta_btn = null
	# 创始人已下场后, 招聘 tab 不再展示创始人区 — 在册状态去「员工」tab 看。
	var show_section: bool = not has_founder
	_founder_section.visible = show_section
	_founder_body.visible = show_section
	if not has_founder:
		var btn := Button.new()
		btn.text = tr("HIRING_BECOME_FOUNDER_RESEARCHER")
		# 收紧到内容宽并左对齐, 不占满整屏 (见 design §9)。
		btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		btn.pressed.connect(_on_founder_cta_pressed)
		_founder_body.add_child(btn)
		_founder_cta_btn = btn

func _refresh_pool(data: Dictionary) -> void:
	_clear_children(_pool_grid_root)
	var pool: Array = data.get("pool", [])
	var order: Array = data.get("specialty_order", [])
	var labels: Dictionary = data.get("specialty_labels", {})
	var bonus_text: Dictionary = data.get("bonus_text", {})
	var grouped := _group_by_specialty(pool)
	var any := false
	for spec in order:
		var leads: Array = grouped.get(spec, [])
		if leads.is_empty():
			continue
		any = true
		var subhead := _make_subsection_label("── %s ──" % String(labels.get(spec, String(spec))))
		_pool_grid_root.add_child(subhead)
		var grid := HFlowContainer.new()
		grid.add_theme_constant_override(&"h_separation", UITheme.S_3)
		grid.add_theme_constant_override(&"v_separation", UITheme.S_3)
		_pool_grid_root.add_child(grid)
		for l in leads:
			var card: Control = CardScene.instantiate()
			grid.add_child(card)
			LeadCard.populate_pool(card, l, String(bonus_text.get(l.id, "")),
				String(labels.get(l.specialty, String(l.specialty))))
			card.action_pressed.connect(_on_card_action.bind(StringName(l.id)))
			_cards_by_id[StringName(l.id)] = card
	if not any:
		_pool_grid_root.add_child(_make_dim_label(tr("HIRING_POOL_EMPTY")))

# ─── helper ────────────────────────────────────────────────

func _group_by_specialty(leads: Array) -> Dictionary:
	var out: Dictionary = {}
	for l in leads:
		var k: StringName = StringName(l.specialty)
		out[k] = out.get(k, [])
		out[k].append(l)
	return out

func _clear_children(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()

func _make_subsection_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override(&"font_color", UITheme.TEXT_SECONDARY)
	l.add_theme_font_size_override(&"font_size", UITheme.FS_SM)
	return l

func _make_dim_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override(&"font_color", UITheme.TEXT_SECONDARY)
	return l

# ─── 信号 ──────────────────────────────────────────────────

func _on_founder_cta_pressed() -> void:
	become_founder_pressed.emit()

func _on_card_action(action_id: StringName, lead_id: StringName) -> void:
	lead_action.emit(lead_id, action_id)

# ─── 测试 introspection ──────────────────────────────────────

func get_pool_card_count() -> int:
	var n := 0
	for child in _pool_grid_root.get_children():
		if child is HFlowContainer:
			n += child.get_child_count()
	return n

func get_card_actions_for_test(lead_id: StringName) -> Array:
	var c: Control = _cards_by_id.get(lead_id, null)
	if c == null:
		return []
	var btns: Dictionary = c.get(&"_action_buttons")
	if btns == null:
		return []
	return btns.keys()

func click_card_action_for_test(lead_id: StringName, action_id: StringName) -> void:
	var c: Control = _cards_by_id.get(lead_id, null)
	if c != null and c.has_method(&"click_action_for_test"):
		c.click_action_for_test(action_id)

func click_become_founder_for_test() -> void:
	if _founder_cta_btn != null and _founder_cta_btn.visible:
		_founder_cta_btn.pressed.emit()

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
