extends VBoxContainer

## RevenueView — 营收 tab 视图 (营收系统设计 §6bis)。
##
## 布局 (从上到下):
##   SectionHeader 上周营收
##   [总营收 / API / 订阅] 三块 StatChip
##   结算信息 dim 行 (回合 N · 丢失 API 需求 X)
##   来源占比: [来源占比] [ShareBar api/sub 两段] [API x% · 订阅 y%]
##   SectionHeader 营收明细 (按模型)
##     每模型一个可折叠分组:
##       header (整行可点): [▾/▸] 模型名 …… $总额 [ShareBar] x%
##       body  (展开时):    每产品一行 [· 类型] 名称 …… $额 [ShareBar]
##   可折叠「算力需求」section (默认收起): 每模型一行 token 需求
##
## 交互 = 点击分组头 / 算力需求头 切换展开; 展开态跨 refresh 记忆 (回合推进重渲
## 不丢)。纯展示, 不发业务信号。数据由 main._build_revenue_view_data() 拉取喂入。

const SectionHeaderScene := preload("res://scenes/ui/components/section_header/section_header.tscn")
const StatChipScene := preload("res://scenes/ui/components/stat_chip/stat_chip.tscn")
const ShareBarScene := preload("res://scenes/ui/components/share_bar/share_bar.tscn")

const SECONDS_PER_WEEK: int = 604_800
# ▼/▶ (U+25BC/B6): cjk.ttf 含这对; 小三角 ▾▸ (U+25BE/B8) 不在子集里会渲成豆腐。
const _CARET_OPEN := "▼"
const _CARET_CLOSED := "▶"
const _DEMAND_KEY := &"__demand__"

# 内容固定宽度: 营收页是表格式信息, 不该铺满整屏 (否则名字在最左、金额在最右,
# 中间空一大片)。收窄成紧凑面板, 左对齐。
const _CONTENT_W := 560.0
const _SHARE_W := 132.0
const _AMOUNT_W := 88.0
const _PCT_W := 44.0
const _CARET_W := 14.0

# 持久节点 (在 _ready 建一次, refresh 只改内容)。
var _summary_section: Control
var _empty_label: Label
var _chip_row: HBoxContainer
var _chips: Array = []
var _settle_label: Label
var _source_row: HBoxContainer
var _source_bar: Control
var _source_value: Label
var _dynamic: VBoxContainer            # 明细分组 + 算力需求, 每次 refresh 重建

# header 两种底色 (normal 透明 / hover 浅灰)。
var _style_normal: StyleBoxFlat
var _style_hover: StyleBoxFlat

# 展开态记忆 (model_id / _DEMAND_KEY → bool)。跨 refresh 不清。
var _expanded: Dictionary = {}

# refresh 重建时刷新的引用 (测试 introspection 用)。
var _carets: Dictionary = {}
var _bodies: Dictionary = {}
var _group_amounts: Dictionary = {}
var _group_pcts: Dictionary = {}
var _group_bars: Dictionary = {}
var _group_ids: Array = []

func _ready() -> void:
	add_theme_constant_override(&"separation", UITheme.S_4)
	# 固定宽度 + 左对齐, 不随窗口铺满 (见 _CONTENT_W 注释)。
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	custom_minimum_size.x = _CONTENT_W
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_style_normal = _make_header_style(Color(0.0, 0.0, 0.0, 0.0))
	_style_hover = _make_header_style(UITheme.BG_ELEVATED)

	_summary_section = SectionHeaderScene.instantiate()
	add_child(_summary_section)
	_summary_section.set_data(tr("SECTION_REVENUE_LAST_WEEK"), -1, "", &"")

	_empty_label = Label.new()
	_empty_label.text = tr("REV_NOT_SETTLED")
	_empty_label.add_theme_color_override(&"font_color", UITheme.TEXT_SECONDARY)
	_empty_label.visible = false
	add_child(_empty_label)

	_chip_row = HBoxContainer.new()
	_chip_row.add_theme_constant_override(&"separation", UITheme.S_3)
	add_child(_chip_row)
	for _i in range(3):
		var chip: Control = StatChipScene.instantiate()
		chip.custom_minimum_size = Vector2(160.0, 0.0)
		_chip_row.add_child(chip)
		_chips.append(chip)

	_settle_label = Label.new()
	_settle_label.add_theme_color_override(&"font_color", UITheme.TEXT_SECONDARY)
	add_child(_settle_label)

	_source_row = HBoxContainer.new()
	_source_row.add_theme_constant_override(&"separation", UITheme.S_3)
	add_child(_source_row)
	var src_label := Label.new()
	src_label.text = tr("REV_SOURCE_LABEL")
	src_label.add_theme_color_override(&"font_color", UITheme.TEXT_SECONDARY)
	src_label.custom_minimum_size = Vector2(72.0, 0.0)
	src_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_source_row.add_child(src_label)
	_source_bar = ShareBarScene.instantiate()
	_source_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_source_bar.custom_minimum_size = Vector2(0.0, 10.0)
	_source_row.add_child(_source_bar)
	_source_value = Label.new()
	_source_value.add_theme_color_override(&"font_color", UITheme.TEXT_SECONDARY)
	_source_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_source_value.custom_minimum_size = Vector2(180.0, 0.0)
	_source_value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_source_row.add_child(_source_value)

	_dynamic = VBoxContainer.new()
	_dynamic.add_theme_constant_override(&"separation", UITheme.S_2)
	add_child(_dynamic)

func refresh(data: Dictionary) -> void:
	var settled: bool = bool(data.get("settled", false))
	_empty_label.visible = not settled
	_chip_row.visible = settled
	_settle_label.visible = settled
	_source_row.visible = settled
	_dynamic.visible = settled
	if not settled:
		_clear_children(_dynamic)
		_reset_dynamic_refs()
		return
	var api_total: int = int(data.get("api_total", 0))
	var sub_total: int = int(data.get("sub_total", 0))
	var grand: int = int(data.get("grand_total", api_total + sub_total))
	_chips[0].set_data(tr("REV_CHIP_TOTAL"), _money(grand), NAN, "")
	_chips[1].set_data(tr("REV_CHIP_API"), _money(api_total), NAN, "")
	_chips[2].set_data(tr("REV_CHIP_SUB"), _money(sub_total), NAN, "")
	_settle_label.text = tr("REV_SETTLE_INFO") % [
		int(data.get("turn", -1)), _format_tps(int(data.get("api_demand_lost", 0)))]
	_source_bar.set_segments([
		{value = float(api_total), color = UITheme.ACCENT_INFO},
		{value = float(sub_total), color = UITheme.ACCENT_PRIMARY},
	], float(grand))
	_source_value.text = tr("REV_SOURCE_VALUE") % [_pct(api_total, grand), _pct(sub_total, grand)]
	_rebuild_dynamic(data, grand)

# ─── 明细分组 + 算力需求 ─────────────────────────────────────

func _rebuild_dynamic(data: Dictionary, grand: int) -> void:
	_clear_children(_dynamic)
	_reset_dynamic_refs()
	var groups: Array = data.get("groups", [])
	var sh: Control = SectionHeaderScene.instantiate()
	_dynamic.add_child(sh)
	sh.set_data(tr("SECTION_REVENUE_DETAIL"), groups.size(), "", &"")
	if groups.is_empty():
		_dynamic.add_child(_dim(tr("MSG_NONE")))
	for g in groups:
		_add_group(g, grand)
	_add_demand_section(data.get("demand_rows", []))

func _add_group(g: Dictionary, grand: int) -> void:
	var mid: StringName = StringName(g.get("model_id", &""))
	_group_ids.append(mid)
	var expanded: bool = _is_expanded(mid)
	var total: int = int(g.get("total", 0))
	var api: int = int(g.get("api", 0))
	var sub: int = int(g.get("sub", 0))

	var caret := Label.new()
	caret.text = _CARET_OPEN if expanded else _CARET_CLOSED
	caret.custom_minimum_size = Vector2(_CARET_W, 0.0)
	var title := Label.new()
	title.text = String(g.get("display_name", String(mid)))
	title.add_theme_font_override(&"font", UITheme.get_ui_font_bold())
	title.add_theme_font_size_override(&"font_size", UITheme.FS_MD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var amount := Label.new()
	amount.text = _money(total)
	amount.add_theme_font_override(&"font", UITheme.get_ui_font_bold())
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	amount.custom_minimum_size = Vector2(_AMOUNT_W, 0.0)
	var bar: Control = ShareBarScene.instantiate()
	bar.custom_minimum_size = Vector2(_SHARE_W, 0.0)
	var pct := Label.new()
	pct.text = "%d%%" % _pct(total, grand)
	pct.add_theme_color_override(&"font_color", UITheme.TEXT_SECONDARY)
	pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pct.custom_minimum_size = Vector2(_PCT_W, 0.0)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override(&"separation", UITheme.S_2)
	hb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(caret)
	hb.add_child(title)
	hb.add_child(amount)
	hb.add_child(bar)
	hb.add_child(pct)

	var header := _make_clickable(_toggle.bind(mid))
	header.add_child(hb)
	_set_ignore_recursive(hb)
	_dynamic.add_child(header)
	# bar 此时已进 tree (_ready 跑过), set_segments 生效。
	bar.set_segments([
		{value = float(api), color = UITheme.ACCENT_INFO},
		{value = float(sub), color = UITheme.ACCENT_PRIMARY},
	], float(grand))

	var body := VBoxContainer.new()
	body.add_theme_constant_override(&"separation", UITheme.S_1)
	body.visible = expanded
	for p in g.get("products", []):
		body.add_child(_make_product_row(p, grand))
	_dynamic.add_child(body)

	_carets[mid] = caret
	_bodies[mid] = body
	_group_amounts[mid] = amount
	_group_pcts[mid] = pct
	_group_bars[mid] = bar

func _make_product_row(p: Dictionary, grand: int) -> Control:
	var kind: StringName = StringName(p.get("kind", &"api"))
	var amount: int = int(p.get("amount", 0))
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", UITheme.S_2)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(UITheme.S_4, 0.0)
	row.add_child(pad)
	var tag := Label.new()
	tag.text = tr("REV_KIND_API") if kind == &"api" else tr("REV_KIND_SUB")
	tag.add_theme_font_size_override(&"font_size", UITheme.FS_XS)
	tag.add_theme_color_override(&"font_color", UITheme.TEXT_SECONDARY)
	tag.custom_minimum_size = Vector2(40.0, 0.0)
	row.add_child(tag)
	var name_lbl := Label.new()
	name_lbl.text = String(p.get("name", ""))
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_color_override(&"font_color", UITheme.TEXT_SECONDARY)
	row.add_child(name_lbl)
	var amt := Label.new()
	amt.text = _money(amount)
	amt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	amt.custom_minimum_size = Vector2(_AMOUNT_W, 0.0)
	amt.add_theme_color_override(&"font_color", UITheme.TEXT_SECONDARY)
	row.add_child(amt)
	var bar: Control = ShareBarScene.instantiate()
	bar.custom_minimum_size = Vector2(_SHARE_W, 0.0)
	row.add_child(bar)
	bar.set_segments([{value = float(amount), color = _kind_color(kind)}], float(grand))
	# 右侧补一个与分组头 pct 列等宽的占位, 让产品行金额/条与分组头对齐。
	var pct_pad := Control.new()
	pct_pad.custom_minimum_size = Vector2(_PCT_W, 0.0)
	row.add_child(pct_pad)
	return row

func _add_demand_section(rows: Array) -> void:
	var expanded: bool = _is_expanded(_DEMAND_KEY)
	var caret := Label.new()
	caret.text = _CARET_OPEN if expanded else _CARET_CLOSED
	caret.custom_minimum_size = Vector2(_CARET_W, 0.0)
	var title := Label.new()
	title.text = tr("SECTION_REVENUE_TOKEN_DEMAND")
	title.add_theme_font_override(&"font", UITheme.get_ui_font_bold())
	title.add_theme_font_size_override(&"font_size", UITheme.FS_LG)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override(&"separation", UITheme.S_2)
	hb.add_child(caret)
	hb.add_child(title)

	var header := _make_clickable(_toggle.bind(_DEMAND_KEY))
	header.add_child(hb)
	_set_ignore_recursive(hb)
	_dynamic.add_child(header)

	var body := VBoxContainer.new()
	body.add_theme_constant_override(&"separation", UITheme.S_2)
	body.visible = expanded
	if rows.is_empty():
		body.add_child(_dim(tr("MSG_NONE")))
	for r in rows:
		body.add_child(_make_demand_row(r))
	_dynamic.add_child(body)

	_carets[_DEMAND_KEY] = caret
	_bodies[_DEMAND_KEY] = body

func _make_demand_row(r: Dictionary) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 2)
	var top := HBoxContainer.new()
	top.add_theme_constant_override(&"separation", UITheme.S_3)
	top.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_lbl := Label.new()
	name_lbl.text = "· " + String(r.get("display_name", ""))
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name_lbl)
	var total_lbl := Label.new()
	total_lbl.text = _format_tps(int(r.get("total", 0)))
	total_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	total_lbl.custom_minimum_size = Vector2(240.0, 0.0)
	top.add_child(total_lbl)
	col.add_child(top)
	var sub_part: int = int(r.get("sub", 0))
	var api_part: int = int(r.get("api", 0))
	if sub_part > 0 or api_part > 0:
		var detail := Label.new()
		detail.text = tr("REV_DEMAND_DETAIL") % [_format_tps(sub_part), _format_tps(api_part)]
		detail.add_theme_color_override(&"font_color", UITheme.TEXT_SECONDARY)
		col.add_child(detail)
	return col

# ─── 折叠交互 ────────────────────────────────────────────────

func _toggle(key: StringName) -> void:
	var now: bool = not _is_expanded(key)
	_expanded[key] = now
	var caret: Label = _carets.get(key, null)
	var body: Control = _bodies.get(key, null)
	if caret != null:
		caret.text = _CARET_OPEN if now else _CARET_CLOSED
	if body != null:
		body.visible = now

# 默认: 模型分组展开, 算力需求 section 收起。
func _is_expanded(key: StringName) -> bool:
	if _expanded.has(key):
		return bool(_expanded[key])
	return key != _DEMAND_KEY

# ─── helpers ─────────────────────────────────────────────────

func _make_clickable(on_click: Callable) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	panel.add_theme_stylebox_override(&"panel", _style_normal)
	panel.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed \
				and ev.button_index == MOUSE_BUTTON_LEFT:
			on_click.call())
	panel.mouse_entered.connect(func() -> void:
		panel.add_theme_stylebox_override(&"panel", _style_hover))
	panel.mouse_exited.connect(func() -> void:
		panel.add_theme_stylebox_override(&"panel", _style_normal))
	return panel

func _make_header_style(bg: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.corner_radius_top_left = UITheme.R_SM
	sb.corner_radius_top_right = UITheme.R_SM
	sb.corner_radius_bottom_left = UITheme.R_SM
	sb.corner_radius_bottom_right = UITheme.R_SM
	sb.content_margin_left = UITheme.S_2
	sb.content_margin_right = UITheme.S_2
	sb.content_margin_top = UITheme.S_1
	sb.content_margin_bottom = UITheme.S_1
	return sb

func _set_ignore_recursive(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in node.get_children():
		_set_ignore_recursive(c)

func _kind_color(kind: StringName) -> Color:
	return UITheme.ACCENT_INFO if kind == &"api" else UITheme.ACCENT_PRIMARY

func _dim(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override(&"font_color", UITheme.TEXT_SECONDARY)
	return l

func _pct(part: int, whole: int) -> int:
	if whole <= 0:
		return 0
	return int(round(100.0 * float(part) / float(whole)))

# 紧凑金额: $640k / $1.2M / $4.2B / $1.2T。钱用 k/M/B/T (十亿是 B 不是 G — token
# 量纲才用 G)。营收页要一眼对比, 不显示逗号长整数。
func _money(n: int) -> String:
	var v: int = absi(n)
	var sign_str: String = "-" if n < 0 else ""
	if v >= 1_000_000_000_000:
		return "%s$%.1fT" % [sign_str, float(v) / 1.0e12]
	if v >= 1_000_000_000:
		return "%s$%.1fB" % [sign_str, float(v) / 1.0e9]
	if v >= 1_000_000:
		return "%s$%.1fM" % [sign_str, float(v) / 1.0e6]
	if v >= 1_000:
		return "%s$%.0fk" % [sign_str, float(v) / 1.0e3]
	return "%s$%d" % [sign_str, v]

# 与 main._format_tps / product_view 同源: tokens/周 → "t/s (周量)"。
func _format_tps(tokens_per_week: int) -> String:
	if tokens_per_week <= 0:
		return "0 t/s"
	var tps: float = float(tokens_per_week) / float(SECONDS_PER_WEEK)
	return tr("FMT_TPS") % [UITheme.format_tps(tps), UITheme.format_tokens(tokens_per_week)]

func _clear_children(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()

func _reset_dynamic_refs() -> void:
	_carets.clear()
	_bodies.clear()
	_group_amounts.clear()
	_group_pcts.clear()
	_group_bars.clear()
	_group_ids.clear()

# ─── 测试 introspection ──────────────────────────────────────

func is_settled_for_test() -> bool:
	return not _empty_label.visible

func get_chip_value_for_test(index: int) -> String:
	if index < 0 or index >= _chips.size():
		return ""
	return _chips[index].get_value_text()

func get_source_bar_for_test() -> Control:
	return _source_bar

func get_source_value_text_for_test() -> String:
	return _source_value.text

func group_ids_for_test() -> Array:
	return _group_ids.duplicate()

func is_group_expanded_for_test(mid: StringName) -> bool:
	var body: Control = _bodies.get(mid, null)
	return body != null and body.visible

func toggle_group_for_test(mid: StringName) -> void:
	_toggle(mid)

func get_group_caret_for_test(mid: StringName) -> String:
	var c: Label = _carets.get(mid, null)
	return c.text if c != null else ""

func get_group_amount_text_for_test(mid: StringName) -> String:
	var l: Label = _group_amounts.get(mid, null)
	return l.text if l != null else ""

func get_group_pct_text_for_test(mid: StringName) -> String:
	var l: Label = _group_pcts.get(mid, null)
	return l.text if l != null else ""

func find_group_bar_for_test(mid: StringName) -> Control:
	return _group_bars.get(mid, null)

func is_demand_expanded_for_test() -> bool:
	var body: Control = _bodies.get(_DEMAND_KEY, null)
	return body != null and body.visible

func toggle_demand_for_test() -> void:
	_toggle(_DEMAND_KEY)

func all_label_texts_for_test() -> PackedStringArray:
	var out := PackedStringArray()
	_collect_labels(self, out)
	return out

func _collect_labels(node: Node, out: PackedStringArray) -> void:
	for c in node.get_children():
		if c is Label:
			out.append((c as Label).text)
		_collect_labels(c, out)
