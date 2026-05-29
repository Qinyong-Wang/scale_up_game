extends VBoxContainer

## TechView — 科技 tab 视图。树状 DAG 布局 (取代旧卡片墙)。
##
## 接 dict {trees: Array of {tree, display, nodes}}, 每个 node 是 dict:
##   id / display_name / effects_summary / prerequisites: Array[StringName] /
##   state (unlocked|researching|available|locked) / research_months
##
## 布局: 每棵树一段 = section_header + TreeCanvas。节点按"同树前置链最长深度"
## 分列, 列内纵向堆叠; 画布 _draw 在节点间画前置连线。四态着色见 design/科技树系统设计.md §3bis。
##
## 信号: research_requested(tree, node_id)

signal research_requested(tree: StringName, node_id: StringName)

const SectionHeaderScene := preload("res://scenes/ui/components/section_header/section_header.tscn")

const NODE_W := 208
const NODE_H := 126
const H_GAP := 64    # 1080p 优先: 加宽节点但收窄列距, 横向跨度基本不变
const V_GAP := 34    # 列内行间距
const _STATE_ORDER := [&"unlocked", &"available", &"researching", &"locked"]

# tree → { node_id → {panel, research_btn, state} } — 测试 introspection。
var _nodes: Dictionary = {}
var _sections_root: VBoxContainer

func _ready() -> void:
	add_theme_constant_override(&"separation", UITheme.S_5)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_sections_root = VBoxContainer.new()
	_sections_root.add_theme_constant_override(&"separation", UITheme.S_5)
	add_child(_sections_root)

func refresh(data: Dictionary) -> void:
	_clear_children(_sections_root)
	_nodes.clear()
	var trees: Array = data.get("trees", [])
	for tree_spec in trees:
		var tree_id: StringName = StringName(tree_spec.get("tree", &""))
		var display: String = String(tree_spec.get("display", String(tree_id)))
		var nodes: Array = tree_spec.get("nodes", [])
		var block := VBoxContainer.new()
		block.add_theme_constant_override(&"separation", UITheme.S_2)
		block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_sections_root.add_child(block)
		var section: Control = SectionHeaderScene.instantiate()
		# 每棵树标题前放一个 tree 图标 (缺图则只显标题)。
		var icon_tex: Texture2D = IconRegistry.get_icon(&"tech", tree_id)
		if icon_tex != null:
			var row := HBoxContainer.new()
			row.add_theme_constant_override(&"separation", UITheme.S_2)
			row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var ico := TextureRect.new()
			ico.custom_minimum_size = Vector2(40, 40)
			ico.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			ico.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			ico.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			ico.texture = icon_tex
			row.add_child(ico)
			section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(section)
			block.add_child(row)
		else:
			block.add_child(section)
		section.set_data(tr("TECH_TREE_LABEL") % display, nodes.size(), "", &"")
		_nodes[tree_id] = {}
		if not nodes.is_empty():
			block.add_child(_make_tree_summary(nodes))
		block.add_child(_build_tree_canvas(tree_id, nodes))

func _make_tree_summary(nodes: Array) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", UITheme.S_2)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var counts: Dictionary = _count_states(nodes)
	for state in _STATE_ORDER:
		var label: String = tr(_state_summary_key(state)) % int(counts.get(state, 0))
		row.add_child(_make_state_chip(label, state))
	return row

func _count_states(nodes: Array) -> Dictionary:
	var counts := {}
	for state in _STATE_ORDER:
		counts[state] = 0
	for n in nodes:
		var state: StringName = StringName(n.get("state", &"available"))
		counts[state] = int(counts.get(state, 0)) + 1
	return counts

# ─── 树状画布 ─────────────────────────────────────────────────

func _build_tree_canvas(tree_id: StringName, nodes: Array) -> Control:
	var canvas := TreeCanvas.new()
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if nodes.is_empty():
		return canvas

	# 1. 每个节点的前置链深度 → 决定列。
	var depths: Dictionary = _compute_depths(nodes)
	var name_by_id: Dictionary = _node_names_by_id(nodes)
	var columns: Dictionary = {}  # depth -> Array of node dict
	var max_depth: int = 0
	for n in nodes:
		var d: int = int(depths.get(StringName(n.get("id", &"")), 0))
		max_depth = maxi(max_depth, d)
		if not columns.has(d):
			columns[d] = []
		columns[d].append(n)

	# 2. 算坐标。逐列 (深度 0→N) 放置: 子节点对齐到前置节点的纵向重心,
	#    再贪心下推消除重叠 → 子节点尽量挨着父节点, 大幅减少连线交叉。
	var positions: Dictionary = {}   # node_id -> Vector2
	var state_by_id: Dictionary = {}
	var row_step: float = NODE_H + V_GAP
	var max_x: float = 0.0
	var max_y: float = 0.0
	for d in range(max_depth + 1):
		if not columns.has(d):
			continue
		var col: Array = columns[d]
		var col_x: float = d * (NODE_W + H_GAP)
		# 每个节点算一个期望 y (前置节点 y 的平均; 根节点按注册顺序铺开)。
		var items: Array = []
		for idx in col.size():
			var cn: Dictionary = col[idx]
			var parent_ys: Array = []
			for pre in cn.get("prerequisites", []):
				var pid: StringName = StringName(pre)
				if positions.has(pid):
					parent_ys.append(positions[pid].y)
			var desired: float = idx * row_step
			if not parent_ys.is_empty():
				var sum_y: float = 0.0
				for py in parent_ys:
					sum_y += py
				desired = sum_y / parent_ys.size()
			items.append({"node": cn, "desired": desired})
		items.sort_custom(func(a, b): return a["desired"] < b["desired"])
		# 贪心: 按期望 y 升序逐个放下, 不够间距就下推。
		var cursor: float = 0.0
		for it in items:
			var pn: Dictionary = it["node"]
			var nid: StringName = StringName(pn.get("id", &""))
			var y: float = maxf(float(it["desired"]), cursor)
			positions[nid] = Vector2(col_x, y)
			state_by_id[nid] = StringName(pn.get("state", &"available"))
			cursor = y + row_step
			max_x = maxf(max_x, col_x + NODE_W)
			max_y = maxf(max_y, y + NODE_H)

	# 3. 前置连线。
	var edges: Array = []
	for n in nodes:
		var nid: StringName = StringName(n.get("id", &""))
		var to_pos: Vector2 = positions[nid]
		for pre in n.get("prerequisites", []):
			var pid: StringName = StringName(pre)
			if not positions.has(pid):
				continue
			var from_pos: Vector2 = positions[pid]
			edges.append({
				"from": from_pos + Vector2(NODE_W, NODE_H * 0.5),
				"to": to_pos + Vector2(0, NODE_H * 0.5),
				"lit": state_by_id.get(pid, &"") == &"unlocked",
			})
	canvas.edges = edges
	canvas.custom_minimum_size = Vector2(max_x, max_y)

	# 4. 节点面板 (绝对定位)。
	for n in nodes:
		var nid: StringName = StringName(n.get("id", &""))
		var panel: Control = _make_node_panel(tree_id, n, name_by_id)
		canvas.add_child(panel)
		panel.position = positions[nid]
		panel.size = Vector2(NODE_W, NODE_H)
	return canvas

func _compute_depths(nodes: Array) -> Dictionary:
	var by_id: Dictionary = {}
	for n in nodes:
		by_id[StringName(n.get("id", &""))] = n
	var depth: Dictionary = {}
	for n in nodes:
		_node_depth(StringName(n.get("id", &"")), by_id, depth, {})
	return depth

func _node_depth(nid: StringName, by_id: Dictionary, depth: Dictionary, resolving: Dictionary) -> int:
	if depth.has(nid):
		return depth[nid]
	if resolving.has(nid):  # 环保护 (理论上 DAG 无环)
		return 0
	resolving[nid] = true
	var d: int = 0
	var n: Variant = by_id.get(nid, null)
	if n != null:
		for pre in n.get("prerequisites", []):
			var pid: StringName = StringName(pre)
			if by_id.has(pid):
				d = maxi(d, _node_depth(pid, by_id, depth, resolving) + 1)
	resolving.erase(nid)
	depth[nid] = d
	return d

func _node_names_by_id(nodes: Array) -> Dictionary:
	var names := {}
	for n in nodes:
		var nid: StringName = StringName(n.get("id", &""))
		var display := String(n.get("display_name", ""))
		names[nid] = display if not display.is_empty() else String(nid)
	return names

# ─── 节点面板 ─────────────────────────────────────────────────

func _make_node_panel(tree_id: StringName, n: Dictionary, name_by_id: Dictionary) -> Control:
	var state: StringName = StringName(n.get("state", &"available"))
	var node_id: StringName = StringName(n.get("id", &""))
	var dim: bool = state == &"locked"

	var panel := PanelContainer.new()
	panel.clip_contents = true
	panel.custom_minimum_size = Vector2(NODE_W, NODE_H)

	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(UITheme.S_3)
	sb.set_border_width_all(1)
	var accent: Color
	match state:
		&"unlocked":
			sb.bg_color = Color("#e6f4ea")
			accent = UITheme.ACCENT_PRIMARY
		&"researching":
			sb.bg_color = UITheme.ACCENT_INFO_SUBTLE
			accent = UITheme.ACCENT_INFO
		&"locked":
			sb.bg_color = UITheme.BG_ELEVATED
			accent = UITheme.BORDER_SUBTLE
		_:  # available
			sb.bg_color = UITheme.BG_SURFACE
			accent = UITheme.BORDER_STRONG
	sb.border_color = accent
	panel.add_theme_stylebox_override(&"panel", sb)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override(&"separation", UITheme.S_1)
	panel.add_child(vb)

	# 标题 + 状态胶囊。
	var prefix: String = ""
	if state == &"unlocked":
		prefix = "✓ "
	elif state == &"locked":
		prefix = tr("TECH_LOCKED_PREFIX") + " "
	var head := HBoxContainer.new()
	head.add_theme_constant_override(&"separation", UITheme.S_2)
	vb.add_child(head)
	var title := Label.new()
	title.text = "%s%s" % [prefix, String(n.get("display_name", ""))]
	title.add_theme_font_size_override(&"font_size", UITheme.FS_SM)
	title.add_theme_color_override(&"font_color",
		UITheme.TEXT_DISABLED if dim else UITheme.TEXT_PRIMARY)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(_make_state_chip(_state_label(state), state))

	# 效果摘要。
	var eff := Label.new()
	eff.text = String(n.get("effects_summary", ""))
	eff.add_theme_font_size_override(&"font_size", UITheme.FS_XS)
	eff.add_theme_color_override(&"font_color",
		UITheme.TEXT_DISABLED if dim else UITheme.TEXT_SECONDARY)
	eff.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	eff.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(eff)

	# 底部: available 给按钮, 其余给状态文字。
	var research_btn: Button = null
	match state:
		&"available":
			research_btn = Button.new()
			research_btn.text = tr("TECH_RESEARCH_BTN") % int(n.get("research_months", 0))
			research_btn.add_theme_font_size_override(&"font_size", UITheme.FS_XS)
			UITheme.apply_button_variant(research_btn, &"primary")
			research_btn.pressed.connect(
				func() -> void: research_requested.emit(tree_id, node_id))
			vb.add_child(research_btn)
		&"researching":
			vb.add_child(_status_label(tr("TECH_RESEARCHING"), UITheme.ACCENT_INFO))
		&"locked":
			vb.add_child(_status_label(_locked_prereq_label(n, name_by_id), UITheme.TEXT_DISABLED))
		_:  # unlocked — 不加底部控件
			pass

	_nodes[tree_id][node_id] = {
		"panel": panel,
		"research_btn": research_btn,
		"state": state,
	}
	return panel

func _status_label(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override(&"font_size", UITheme.FS_XS)
	l.add_theme_color_override(&"font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

func _locked_prereq_label(n: Dictionary, name_by_id: Dictionary) -> String:
	var parts: Array = []
	for pre in n.get("prerequisites", []):
		var pid: StringName = StringName(pre)
		parts.append(String(name_by_id.get(pid, String(pid))))
	if parts.is_empty():
		return tr("STATUS_LOCKED")
	return tr("TECH_PREREQ_LABEL") % " / ".join(parts)

func _make_state_chip(text: String, state: StringName) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(UITheme.R_SM)
	sb.set_border_width_all(1)
	sb.set_content_margin(SIDE_LEFT, UITheme.S_2)
	sb.set_content_margin(SIDE_RIGHT, UITheme.S_2)
	sb.set_content_margin(SIDE_TOP, 2)
	sb.set_content_margin(SIDE_BOTTOM, 2)
	var palette: Dictionary = _state_palette(state)
	sb.bg_color = palette.bg
	sb.border_color = palette.border
	chip.add_theme_stylebox_override(&"panel", sb)

	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", UITheme.FS_XS)
	label.add_theme_color_override(&"font_color", palette.fg)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	chip.add_child(label)
	return chip

func _state_label(state: StringName) -> String:
	match state:
		&"unlocked":
			return tr("TECH_STATUS_UNLOCKED")
		&"researching":
			return tr("TECH_STATUS_RESEARCHING")
		&"locked":
			return tr("TECH_STATUS_LOCKED")
		_:
			return tr("TECH_STATUS_AVAILABLE")

func _state_summary_key(state: StringName) -> StringName:
	match state:
		&"unlocked":
			return &"TECH_SUMMARY_UNLOCKED"
		&"researching":
			return &"TECH_SUMMARY_RESEARCHING"
		&"locked":
			return &"TECH_SUMMARY_LOCKED"
		_:
			return &"TECH_SUMMARY_AVAILABLE"

func _state_palette(state: StringName) -> Dictionary:
	match state:
		&"unlocked":
			return {bg = Color("#e6f4ea"), border = UITheme.ACCENT_PRIMARY, fg = UITheme.ACCENT_PRIMARY}
		&"researching":
			return {bg = UITheme.ACCENT_INFO_SUBTLE, border = UITheme.ACCENT_INFO, fg = UITheme.ACCENT_INFO}
		&"locked":
			return {bg = UITheme.BG_ELEVATED, border = UITheme.BORDER_SUBTLE, fg = UITheme.TEXT_DISABLED}
		_:
			return {bg = UITheme.BG_SURFACE, border = UITheme.BORDER_STRONG, fg = UITheme.TEXT_PRIMARY}

func _clear_children(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()

# ─── 内部类: 画前置连线的画布 ──────────────────────────────────

class TreeCanvas extends Control:
	# Array of {from: Vector2, to: Vector2, lit: bool}
	var edges: Array = []

	func _draw() -> void:
		for e in edges:
			var lit: bool = bool(e.get("lit", false))
			var c: Color = UITheme.ACCENT_PRIMARY if lit else UITheme.BORDER_SUBTLE
			var from: Vector2 = e.get("from", Vector2.ZERO)
			var to: Vector2 = e.get("to", Vector2.ZERO)
			var mid_x: float = (from.x + to.x) * 0.5
			# 正交三段折线: 横 → 竖 → 横。
			draw_line(from, Vector2(mid_x, from.y), c, 2.0)
			draw_line(Vector2(mid_x, from.y), Vector2(mid_x, to.y), c, 2.0)
			draw_line(Vector2(mid_x, to.y), to, c, 2.0)

# ─── 测试 introspection ──────────────────────────────────────

func get_card_actions_for_test(tree_id: StringName, node_id: StringName) -> Array:
	var rec: Dictionary = _nodes.get(tree_id, {}).get(node_id, {})
	if rec.is_empty() or rec.get("research_btn", null) == null:
		return []
	return [&"research"]

func get_node_state_for_test(tree_id: StringName, node_id: StringName) -> StringName:
	var rec: Dictionary = _nodes.get(tree_id, {}).get(node_id, {})
	return StringName(rec.get("state", &""))

func click_research_for_test(tree_id: StringName, node_id: StringName) -> void:
	var rec: Dictionary = _nodes.get(tree_id, {}).get(node_id, {})
	var btn: Button = rec.get("research_btn", null)
	if btn != null:
		btn.pressed.emit()

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
