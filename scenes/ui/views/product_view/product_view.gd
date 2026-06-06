extends VBoxContainer

## ProductView — 产品 tab 试点视图 (§10 step 6 第三批扩展)。
##
## 布局:
##   SectionHeader  创建新产品   [+ 创建产品...] (无 published 模型时按钮缺省, 显示提示)
##   SectionHeader  算力池 (按模型)
##     每模型一行: CapacityPie 饼图 (订阅/API/空闲三档, 饱和红边)
##       + header label "容量 X | 需求 Y [util Z%]" (capacity=0 红, util>80% 黄, util>100% 红)
##       + detail label "订阅 X · API Y"
##       + 警告行 (capacity=0 或 util>100%)
##   SectionHeader  已上线产品
##   HFlow of product cards (api vs subscription 字段集不同)
##
## 信号:
##   new_product_pressed
##   product_action(product_id, action_id)  # edit / delete

signal new_product_pressed
signal product_action(product_id: StringName, action_id: StringName)
# U-2: 算力警告点击 → 切到基建 tab. 由 main.gd 连接到 sidebar 导航。
signal infra_shortcut_pressed

const SectionHeaderScene := preload("res://scenes/ui/components/section_header/section_header.tscn")
const CardScene := preload("res://scenes/ui/components/card/card.tscn")
const CapacityPieScene := preload("res://scenes/ui/components/capacity_pie/capacity_pie.tscn")
const ProductCard := preload("res://scenes/ui/views/product_view/product_card.gd")

# pool header 颜色 (与老 _apply_util_color 行为一致)。
const _POOL_RED := Color(1.0, 0.5, 0.5)
const _POOL_YELLOW := Color(1.0, 0.85, 0.4)

var _create_section: Control
var _create_body: VBoxContainer
var _create_btn: Button          # 创建产品按钮 (测试 introspection 用)

var _pool_section: Control
var _pool_body: VBoxContainer

var _products_section: Control
var _products_grid: HFlowContainer
var _products_empty: Label

var _cards_by_id: Dictionary = {}
var _pool_headers_by_id: Dictionary = {}   # model_id → Label, 测试 introspection 用
var _pool_pies_by_id: Dictionary = {}      # model_id → CapacityPie, 测试 introspection 用

func _ready() -> void:
	add_theme_constant_override(&"separation", UITheme.S_4)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	# SectionHeader.set_data 必须在 add_child 之后调用 (内部节点要 _ready 后才建)。
	_create_section = SectionHeaderScene.instantiate()
	add_child(_create_section)
	_create_section.set_data(tr("PRODUCT_CREATE_SECTION"), -1, "", &"")
	_create_body = VBoxContainer.new()
	_create_body.add_theme_constant_override(&"separation", UITheme.S_2)
	add_child(_create_body)

	# 算力池 section + body 按 pool_rows 状态动态进出树; 进树时再 set_data。
	_pool_section = SectionHeaderScene.instantiate()
	_pool_body = VBoxContainer.new()
	_pool_body.add_theme_constant_override(&"separation", UITheme.S_2)

	_products_section = SectionHeaderScene.instantiate()
	add_child(_products_section)
	_products_section.set_data(tr("PRODUCT_LIVE_SECTION"), -1, "", &"")

	_products_grid = HFlowContainer.new()
	_products_grid.add_theme_constant_override(&"h_separation", UITheme.S_3)
	_products_grid.add_theme_constant_override(&"v_separation", UITheme.S_3)
	add_child(_products_grid)

	_products_empty = Label.new()
	_products_empty.text = tr("MSG_NONE")
	_products_empty.add_theme_color_override(&"font_color", UITheme.TEXT_SECONDARY)
	_products_empty.visible = false
	add_child(_products_empty)

func _exit_tree() -> void:
	# Detached pool nodes are not children of this view when pool_rows is empty.
	# Free synchronously so GUT does not count them as orphans during teardown.
	if _pool_section != null and _pool_section.get_parent() == null:
		_pool_section.free()
		_pool_section = null
	if _pool_body != null and _pool_body.get_parent() == null:
		_pool_body.free()
		_pool_body = null

func refresh(data: Dictionary) -> void:
	_refresh_create(bool(data.get("has_published_model", false)))
	_refresh_pool(data.get("pool_rows", []))
	_refresh_products(data.get("products", []), data)

func _refresh_create(has_pub: bool) -> void:
	_clear_children(_create_body)
	if has_pub:
		var btn := Button.new()
		btn.text = tr("PRODUCT_CREATE_BTN")
		# 收紧到内容宽并左对齐, 不占满整屏 (见 design §9)。
		btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		UITheme.apply_button_variant(btn, &"create")
		btn.pressed.connect(_on_create_pressed)
		_create_body.add_child(btn)
		_create_btn = btn
		var hint := Label.new()
		hint.text = tr("PRODUCT_CREATE_HINT")
		hint.add_theme_color_override(&"font_color", UITheme.TEXT_SECONDARY)
		_create_body.add_child(hint)
	else:
		var hint := Label.new()
		hint.text = tr("PRODUCT_NEED_MODEL")
		hint.add_theme_color_override(&"font_color", UITheme.TEXT_SECONDARY)
		_create_body.add_child(hint)

func _refresh_pool(rows: Array) -> void:
	_clear_children(_pool_body)
	_pool_headers_by_id.clear()
	_pool_pies_by_id.clear()
	var section_in_tree: bool = _pool_section.get_parent() != null
	var body_in_tree: bool = _pool_body.get_parent() != null
	if rows.is_empty():
		if section_in_tree:
			remove_child(_pool_section)
		if body_in_tree:
			remove_child(_pool_body)
		return
	# 把 section + body 插在 _create_body 之后, _products_section 之前。
	var insert_pos: int = _products_section.get_index()
	if not section_in_tree:
		add_child(_pool_section)
		move_child(_pool_section, insert_pos)
		_pool_section.set_data(tr("PRODUCT_COMPUTE_POOL"), rows.size(), "", &"")
		insert_pos += 1
	else:
		_pool_section.set_data(tr("PRODUCT_COMPUTE_POOL"), rows.size(), "", &"")
	if not body_in_tree:
		add_child(_pool_body)
		move_child(_pool_body, insert_pos)

	for row in rows:
		var model_id: StringName = StringName(row.get("model_id", &""))
		var name: String = String(row.get("display_name", String(model_id)))
		var capacity: int = int(row.get("capacity", 0))
		var demand: int = int(row.get("demand", 0))
		var sub_demand: int = int(row.get("sub_demand", 0))
		var api_demand: int = int(row.get("api_demand", 0))
		var util: float = float(row.get("util_pct", 0.0))

		# 每模型一行 = HBox(pie + VBox(header + detail))。pie 直观, 文字给精确值。
		var hrow := HBoxContainer.new()
		hrow.add_theme_constant_override(&"separation", UITheme.S_3)
		_pool_body.add_child(hrow)

		var pie: Control = CapacityPieScene.instantiate()
		hrow.add_child(pie)
		pie.set_data(capacity, sub_demand, api_demand)
		_pool_pies_by_id[model_id] = pie

		var vbox := VBoxContainer.new()
		vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hrow.add_child(vbox)

		var header := Label.new()
		header.text = tr("PRODUCT_POOL_HEADER") % [
			name, _format_tps_compact(capacity), _format_tps_compact(demand),
			_format_util_label(util)]
		_apply_util_color(header, util, capacity)
		vbox.add_child(header)
		_pool_headers_by_id[model_id] = header

		var detail := Label.new()
		detail.text = tr("PRODUCT_POOL_DETAIL") % [
			_format_tps_compact(sub_demand), _format_tps_compact(api_demand)]
		detail.add_theme_color_override(&"font_color", UITheme.TEXT_SECONDARY)
		vbox.add_child(detail)

		if capacity <= 0:
			vbox.add_child(_make_warn_row(
					tr("PRODUCT_WARN_NOT_DEPLOYED")))
		elif util > 100.0:
			vbox.add_child(_make_warn_row(
					tr("PRODUCT_WARN_CAPACITY")))

# U-2: 算力警告行 = Label + "→ 去基建扩容" 按钮; 点击 emit infra_shortcut_pressed,
# 上层 main.gd 接到后切换 sidebar 到基建 tab。
func _make_warn_row(text: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override(&"font_color", _POOL_RED)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	var btn := Button.new()
	btn.text = tr("PRODUCT_GOTO_INFRA")
	btn.pressed.connect(func(): infra_shortcut_pressed.emit())
	row.add_child(btn)
	return row

func _apply_util_color(lbl: Label, util_pct: float, capacity: int) -> void:
	if capacity <= 0 or util_pct > 100.0:
		lbl.add_theme_color_override(&"font_color", _POOL_RED)
	elif util_pct > 80.0:
		lbl.add_theme_color_override(&"font_color", _POOL_YELLOW)

func _refresh_products(products: Array, data: Dictionary) -> void:
	_clear_children(_products_grid)
	_cards_by_id.clear()
	_products_empty.visible = products.is_empty()
	var api_prices: Dictionary = data.get("api_price_by_model", {})
	var api_demands: Dictionary = data.get("api_demand_per_product", {})
	var last_revenues: Dictionary = data.get("last_revenue_per_product", {})
	var sub_tps_map: Dictionary = data.get("sub_tps_per_product", {})
	# v8 PR-I — 定价上下文: API 卡的 base/guidance, 订阅卡的参考订阅价。
	var api_pricing: Dictionary = data.get("api_pricing_per_product", {})
	var sub_guidance: Dictionary = data.get("sub_guidance_per_product", {})
	var model_labels: Dictionary = data.get("model_labels", {})
	# v7 PR-F3+ — 每周增长率分解, 由 UserSystem.compute_rate_breakdown 算好。
	var rate_breakdown_map: Dictionary = data.get("rate_breakdown_per_product", {})
	for p in products:
		var card: Control = CardScene.instantiate()
		_products_grid.add_child(card)
		var pricing: Dictionary = {}
		if p.type == &"api":
			pricing = api_pricing.get(p.id, {})
		elif sub_guidance.has(p.id):
			pricing = {&"sub_guidance": int(sub_guidance[p.id])}
		var rate: Dictionary = rate_breakdown_map.get(p.id, {})
		ProductCard.populate(
			card, p,
			float(api_prices.get(p.bound_model_id, 0.0)),
			int(api_demands.get(p.id, 0)),
			int(last_revenues.get(p.id, 0)),
			int(sub_tps_map.get(p.id, 0)),
			pricing,
			rate,
			String(model_labels.get(p.bound_model_id, String(p.bound_model_id))),
		)
		card.action_pressed.connect(_on_card_action.bind(StringName(p.id)))
		_cards_by_id[StringName(p.id)] = card
	_products_section.set_data(tr("PRODUCT_LIVE_SECTION"), products.size(), "", &"")

# ─── 信号 ────────────────────────────────────────────────────

func _on_create_pressed() -> void:
	new_product_pressed.emit()

func _on_card_action(action_id: StringName, product_id: StringName) -> void:
	product_action.emit(product_id, action_id)

# ─── helpers ─────────────────────────────────────────────────

func _clear_children(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()

# 上游传进来的 capacity / demand / sub_tps 都是 tokens/周 (1 turn = 1 week,
# 见 design/营收系统设计.md §4)。除回 SECONDS_PER_WEEK 才是 t/s。和
# main._format_tps 同源, 不让产品页与营收页对同一份数据显示不同的量级。
const _SECONDS_PER_WEEK: int = 604_800

func _format_tps_compact(tokens_per_week: int) -> String:
	# 走 UITheme 统一格式化, 自动升档 k → M → G (与营收 / 顶栏一致)。
	return UITheme.format_tps(float(tokens_per_week) / float(_SECONDS_PER_WEEK))

func _format_util_label(util_pct: float) -> String:
	if util_pct > 999.0:
		return ">999%"
	return "%.0f%%" % util_pct

# ─── 测试 introspection ──────────────────────────────────────

func get_card_actions_for_test(product_id: StringName) -> Array:
	var c: Control = _cards_by_id.get(product_id, null)
	if c == null:
		return []
	var btns: Dictionary = c.get(&"_action_buttons")
	return btns.keys() if btns != null else []

func get_card_fields_for_test(product_id: StringName) -> Dictionary:
	var c: Control = _cards_by_id.get(product_id, null)
	if c == null:
		return {}
	var fields: Dictionary = {}
	var count: int = c.get_field_count()
	for i in range(count):
		var row: Dictionary = c.get_field_row_for_test(i)
		if row.has("label"):
			fields[row.label] = row.value
	return fields

func click_card_action_for_test(product_id: StringName, action_id: StringName) -> void:
	var c: Control = _cards_by_id.get(product_id, null)
	if c != null and c.has_method(&"click_action_for_test"):
		c.click_action_for_test(action_id)

func click_new_product_for_test() -> void:
	# 直接找 _create_body 里的按钮。
	for ch in _create_body.get_children():
		if ch is Button:
			(ch as Button).pressed.emit()
			return

func find_pool_header_for_test(model_id: StringName) -> Label:
	return _pool_headers_by_id.get(model_id, null)

func find_pool_pie_for_test(model_id: StringName) -> Control:
	return _pool_pies_by_id.get(model_id, null)

func get_card_subtitle_for_test(product_id: StringName) -> String:
	var c: Control = _cards_by_id.get(product_id, null)
	if c == null or not c.has_method(&"get_subtitle_text"):
		return ""
	return c.get_subtitle_text()

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
