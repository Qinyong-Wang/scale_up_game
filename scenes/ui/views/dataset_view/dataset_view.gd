extends VBoxContainer

## DatasetView — 数据 tab 试点视图。
##
## 接 dict {active_kind, market_templates: Array[DatasetTemplate],
##   owned_datasets: Array[Dataset]}。 view 内不访问 GameState/CommandBus。
##
## 信号:
##   kind_switched(kind: StringName)            — pretrain / posttrain
##   template_action(template_id, action)        — acquire / purchase
##   dataset_action(dataset_id, action)          — delete
##   collect_pressed                              — 启动自采

signal kind_switched(kind: StringName)
signal template_action(template_id: StringName, action_id: StringName)
signal dataset_action(dataset_id: StringName, action_id: StringName)
signal collect_pressed

const SectionHeaderScene := preload("res://scenes/ui/components/section_header/section_header.tscn")
const CardScene := preload("res://scenes/ui/components/card/card.tscn")
const FilterBarScene := preload("res://scenes/ui/components/filter_bar/filter_bar.tscn")

# 与老 _DATASET_KIND_COLOR_* 一致。
const _COLOR_PRE  := Color(0.45, 0.70, 1.00)
const _COLOR_POST := Color(1.00, 0.65, 0.30)

# 来源筛选 pills — 第一个 "全部" 互斥其余 (FilterBar 语义)。市场模板只有
# open_source / purchased; collected (自采) 只出现在"我的"里。
# pill label 为 i18n key (const 不能调 tr); set_pills 前用 _localize_options() 翻。
const _SOURCE_PILLS: Array = [
	{"id": &"all",         "label": "FILTER_ALL"},
	{"id": &"open_source", "label": "DATASET_SRC_OPEN"},
	{"id": &"purchased",   "label": "DATASET_SRC_PURCHASED"},
	{"id": &"collected",   "label": "DATASET_SRC_COLLECTED"},
]
# 数据集规模筛选 pills — 按 B tokens 分三档 (阈值见 _size_bucket_of)。
# ≤10B 等量级标签语言中性, 不进 CSV; _localize_options 对非 key 原样返回。
const _SIZE_PILLS: Array = [
	{"id": &"all",   "label": "FILTER_ALL"},
	{"id": &"small", "label": "≤10B"},
	{"id": &"mid",   "label": "≤1000B"},
	{"id": &"large", "label": ">1000B"},
]

## const pill 表里的 label 是 i18n key, 渲染前翻成当前 locale 文案。
func _localize_options(opts: Array) -> Array:
	var out: Array = []
	for o in opts:
		out.append({"id": o.id, "label": tr(String(o.label))})
	return out

var _kind_pre_btn: Button
var _kind_post_btn: Button
var _kind_header: Label
var _source_filter: Control        # FilterBar — 来源筛选
var _size_filter: Control          # FilterBar — 规模筛选
var _market_grid: HFlowContainer   # 模板卡片墙 (含 acquire/purchase 按钮)
var _market_empty: Label
var _collect_btn: Button
var _owned_section: Control
var _owned_grid: HFlowContainer
var _owned_empty: Label

# 测试用 introspection。
var _template_buttons: Dictionary = {}   # template_id → Button
var _dataset_buttons: Dictionary = {}    # dataset_id → Button
var _template_cards: Dictionary = {}     # template_id → Card
var _dataset_cards: Dictionary = {}      # dataset_id → Card
var _template_meta: Dictionary = {}      # template_id → {source, size_bucket}
var _dataset_meta: Dictionary = {}       # dataset_id → {source, size_bucket}
var _active_kind: StringName = &"pretrain"
var _source_filter_state: Dictionary = {}
var _size_filter_state: Dictionary = {}

func _ready() -> void:
	add_theme_constant_override(&"separation", UITheme.S_3)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Kind selector.
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", UITheme.S_2)
	add_child(row)
	_kind_pre_btn = Button.new()
	_kind_pre_btn.text = tr("TASK_SUBTYPE_PRETRAIN")
	_kind_pre_btn.add_theme_color_override(&"font_color", _COLOR_PRE)
	_kind_pre_btn.pressed.connect(func(): kind_switched.emit(&"pretrain"))
	row.add_child(_kind_pre_btn)
	_kind_post_btn = Button.new()
	_kind_post_btn.text = tr("TASK_SUBTYPE_POSTTRAIN")
	_kind_post_btn.add_theme_color_override(&"font_color", _COLOR_POST)
	_kind_post_btn.pressed.connect(func(): kind_switched.emit(&"posttrain"))
	row.add_child(_kind_post_btn)

	_kind_header = Label.new()
	add_child(_kind_header)

	# 来源 + 规模两条筛选条 — 只用 pills, 取交集后作用到市场 + 我的两个网格。
	# 连接 state_changed 必须在 set_pills 之后, 否则 set_pills 内部的首次
	# emit 会在网格还没建好时触发 _apply_filter。
	_source_filter = FilterBarScene.instantiate()
	add_child(_source_filter)
	_source_filter.set_pills(_localize_options(_SOURCE_PILLS))
	_source_filter.set_search_visible(false)
	_source_filter.state_changed.connect(_on_source_filter_changed)
	_source_filter_state = _source_filter.get_state()

	_size_filter = FilterBarScene.instantiate()
	add_child(_size_filter)
	_size_filter.set_pills(_localize_options(_SIZE_PILLS))
	_size_filter.set_search_visible(false)
	_size_filter.state_changed.connect(_on_size_filter_changed)
	_size_filter_state = _size_filter.get_state()

	_market_grid = HFlowContainer.new()
	_market_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_market_grid.add_theme_constant_override(&"h_separation", UITheme.S_3)
	_market_grid.add_theme_constant_override(&"v_separation", UITheme.S_3)
	add_child(_market_grid)
	_market_empty = Label.new()
	_market_empty.add_theme_color_override(&"font_color", UITheme.TEXT_SECONDARY)
	_market_empty.visible = false
	add_child(_market_empty)

	# 自采按钮。
	var collect_section: Control = SectionHeaderScene.instantiate()
	add_child(collect_section)
	collect_section.set_data(tr("DATASET_COLLECT_SECTION"), -1, "", &"")
	_collect_btn = Button.new()
	_collect_btn.text = tr("DATASET_COLLECT_BTN")
	# 收紧到内容宽并左对齐, 不占满整屏 (见 design §9)。
	_collect_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	UITheme.apply_button_variant(_collect_btn, &"create")
	_collect_btn.pressed.connect(func(): collect_pressed.emit())
	add_child(_collect_btn)

	# 我的 section + grid。
	_owned_section = SectionHeaderScene.instantiate()
	add_child(_owned_section)
	_owned_section.set_data(tr("DATASET_OWNED"), -1, "", &"")
	_owned_grid = HFlowContainer.new()
	_owned_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_owned_grid.add_theme_constant_override(&"h_separation", UITheme.S_3)
	_owned_grid.add_theme_constant_override(&"v_separation", UITheme.S_3)
	add_child(_owned_grid)
	_owned_empty = Label.new()
	_owned_empty.add_theme_color_override(&"font_color", UITheme.TEXT_SECONDARY)
	_owned_empty.visible = false
	add_child(_owned_empty)

func refresh(data: Dictionary) -> void:
	_active_kind = StringName(data.get("active_kind", &"pretrain"))
	_refresh_kind_selector()
	_refresh_market(data.get("market_templates", []))
	_refresh_collect_label()
	_refresh_owned(data.get("owned_datasets", []))
	_apply_filter()

func _refresh_kind_selector() -> void:
	var pre_mark: String = "◉ " if _active_kind == &"pretrain" else "  "
	var post_mark: String = "◉ " if _active_kind == &"posttrain" else "  "
	_kind_pre_btn.text = pre_mark + tr("TASK_SUBTYPE_PRETRAIN")
	_kind_post_btn.text = post_mark + tr("TASK_SUBTYPE_POSTTRAIN")
	var color: Color = _COLOR_PRE if _active_kind == &"pretrain" else _COLOR_POST
	var text: String = (tr("DATASET_KIND_HEADER_PRE") if _active_kind == &"pretrain"
			else tr("DATASET_KIND_HEADER_POST"))
	_kind_header.text = text
	_kind_header.add_theme_color_override(&"font_color", color)

func _refresh_market(templates: Array) -> void:
	_clear_children(_market_grid)
	_template_buttons.clear()
	_template_cards.clear()
	_template_meta.clear()
	for t in templates:
		if StringName(t.kind) != _active_kind:
			continue
		var tid: StringName = StringName(t.id)
		var action_id: StringName
		if StringName(t.source) == &"open_source":
			action_id = &"acquire"
		elif StringName(t.source) == &"purchased":
			action_id = &"purchase"
		else:
			continue
		var card: Control = CardScene.instantiate()
		_market_grid.add_child(card)
		card.set_data(_template_card_data(t, action_id))
		card.action_pressed.connect(func(pressed_action: StringName): template_action.emit(tid, pressed_action))
		_template_cards[tid] = card
		_template_buttons[tid] = _card_button(card, action_id)
		_template_meta[tid] = {
			"source": StringName(t.source),
			"size_bucket": _size_bucket_of(float(t.size)),
		}

func _refresh_collect_label() -> void:
	_collect_btn.text = (tr("DATASET_COLLECT_PRE") if _active_kind == &"pretrain"
			else tr("DATASET_COLLECT_POST"))

func _refresh_owned(owned: Array) -> void:
	_clear_children(_owned_grid)
	_dataset_buttons.clear()
	_dataset_cards.clear()
	_dataset_meta.clear()
	var kind_text: String = tr("TASK_SUBTYPE_PRETRAIN") if _active_kind == &"pretrain" else tr("TASK_SUBTYPE_POSTTRAIN")
	_owned_section.set_data(tr("DATASET_OWNED_COUNT") % kind_text, -1, "", &"")
	for ds in owned:
		if StringName(ds.kind) != _active_kind:
			continue
		var did: StringName = StringName(ds.id)
		var card: Control = CardScene.instantiate()
		_owned_grid.add_child(card)
		card.set_data(_owned_card_data(ds))
		if StringName(ds.locked_by_task_id) == &"":
			card.action_pressed.connect(func(pressed_action: StringName): dataset_action.emit(did, pressed_action))
			_dataset_buttons[did] = _card_button(card, &"delete")
		_dataset_cards[did] = card
		_dataset_meta[did] = {
			"source": StringName(ds.source),
			"size_bucket": _size_bucket_of(float(ds.size)),
		}

# ─── 筛选 (来源 × 规模, 取交集) ──────────────────────────────

# 数据集按 B tokens 归一化为 small (≤10) / mid (≤1000) / large (>1000)。
func _size_bucket_of(size_b: float) -> StringName:
	if size_b <= 10.0:
		return &"small"
	if size_b <= 1000.0:
		return &"mid"
	return &"large"

func _on_source_filter_changed(state: Dictionary) -> void:
	_source_filter_state = state
	_apply_filter()

func _on_size_filter_changed(state: Dictionary) -> void:
	_size_filter_state = state
	_apply_filter()

# 来源 + 规模两条筛选取交集, 作用到市场 + 我的两个网格; 0 卡可见时显示
# 对应的空提示。基建 tab 的双 FilterBar 模式同构。
func _apply_filter() -> void:
	var src_sel: Array = _source_filter_state.get("selected_pills", [&"all"])
	var src_all: bool = src_sel.has(&"all")
	var size_sel: Array = _size_filter_state.get("selected_pills", [&"all"])
	var size_all: bool = size_sel.has(&"all")

	var market_vis: int = 0
	for tid in _template_cards:
		var meta: Dictionary = _template_meta.get(tid, {})
		var ok: bool = (src_all or src_sel.has(meta.get("source", &""))) \
				and (size_all or size_sel.has(meta.get("size_bucket", &"")))
		(_template_cards[tid] as Control).visible = ok
		if ok:
			market_vis += 1
	var owned_vis: int = 0
	for did in _dataset_cards:
		var meta2: Dictionary = _dataset_meta.get(did, {})
		var ok2: bool = (src_all or src_sel.has(meta2.get("source", &""))) \
				and (size_all or size_sel.has(meta2.get("size_bucket", &"")))
		(_dataset_cards[did] as Control).visible = ok2
		if ok2:
			owned_vis += 1

	_market_empty.visible = (market_vis == 0)
	_market_empty.text = (tr("DATASET_MARKET_EMPTY") if _template_cards.is_empty()
			else tr("DATASET_MARKET_EMPTY_FILTERED"))
	_owned_empty.visible = (owned_vis == 0)
	_owned_empty.text = (tr("DATASET_OWNED_EMPTY") if _dataset_cards.is_empty()
			else tr("DATASET_OWNED_EMPTY_FILTERED"))
	_update_pill_counts()

# pill 计数 = 市场 + 我的全部卡按各自维度计数 (两维独立)。
func _update_pill_counts() -> void:
	var src_counts: Dictionary = {}
	var size_counts: Dictionary = {}
	var total: int = 0
	for meta in (_template_meta.values() + _dataset_meta.values()):
		total += 1
		var s: StringName = meta.get("source", &"")
		src_counts[s] = int(src_counts.get(s, 0)) + 1
		var b: StringName = meta.get("size_bucket", &"")
		size_counts[b] = int(size_counts.get(b, 0)) + 1
	src_counts[&"all"] = total
	size_counts[&"all"] = total
	if _source_filter != null:
		_source_filter.update_pill_counts(src_counts)
	if _size_filter != null:
		_size_filter.update_pill_counts(size_counts)

func _template_card_data(t: Variant, action_id: StringName) -> Dictionary:
	var mod_str: String = _modality_label(StringName(t.modality) if "modality" in t else &"text")
	var source := StringName(t.source)
	var source_label := _source_label(source)
	var fields: Array = [
		{"label": tr("FIELD_SOURCE"), "value": source_label},
		{"label": tr("FIELD_MODALITY"), "value": mod_str},
		{"label": tr("FIELD_SIZE"), "value": "%.3fB tokens" % float(t.size)},
	]
	var tags_str: String = _fmt_tags(t.get("coverage_tags") if "coverage_tags" in t else [])
	if tags_str != "":
		fields.append({"label": tr("FIELD_TAGS"), "value": tags_str})
	if _active_kind == &"pretrain":
		var mult: float = (1.05 if source == &"purchased"
				else (0.9 if source == &"open_source" else 1.0))
		fields.append({"label": tr("FIELD_MULTIPLIER"), "value": "×%.2f" % mult})
	else:
		var q: float = float(t.quality) if "quality" in t else 0.0
		fields.append({"label": tr("FIELD_QUALITY"), "value": "%.2f" % q})
	if source == &"purchased":
		fields.append({"label": tr("FIELD_PRICE"), "value": "$%s" % _comma(int(t.price))})
	var action_label := ""
	if action_id == &"acquire":
		action_label = tr("DATASET_ACQUIRE")
	else:
		action_label = tr("DATASET_PURCHASE") % _comma(int(t.price))
	return {
		"title": tr(String(t.display_name)),
		"subtitle": "%s · %s" % [source_label, mod_str],
		"avatar": _dataset_avatar(tr(String(t.display_name)), StringName(t.id),
			StringName(t.modality) if "modality" in t and String(t.modality) != "" else &"text"),
		"status": _dataset_status(source),
		"fields": fields,
		"actions": [{"id": action_id, "label": action_label}],
	}

func _owned_card_data(ds: Variant) -> Dictionary:
	var locked_task := StringName(ds.locked_by_task_id)
	var source := StringName(ds.source)
	var source_label := _source_label(source)
	var ds_mod: String = _modality_label(StringName(ds.modality)) \
			if "modality" in ds and String(ds.modality) != "" else _modality_label(&"text")
	var fields: Array = [
		{"label": tr("FIELD_SOURCE"), "value": source_label},
		{"label": tr("FIELD_MODALITY"), "value": ds_mod},
		{"label": tr("FIELD_SIZE"), "value": "%.3fB tokens" % float(ds.size)},
		{"label": tr("FIELD_QUALITY"), "value": "%.2f" % float(ds.quality)},
	]
	var ds_tags: String = _fmt_tags(ds.get("coverage_tags") if "coverage_tags" in ds else [])
	if ds_tags != "":
		fields.append({"label": tr("FIELD_TAGS"), "value": ds_tags})
	var actions: Array = []
	if locked_task == &"":
		actions.append({"id": &"delete", "label": tr("ACTION_DELETE")})
	else:
		fields.append({"label": tr("FIELD_LOCKED"), "value": String(locked_task)})
	return {
		"title": String(ds.display_name),
		"subtitle": "%s · %s" % [source_label, ds_mod],
		"avatar": _dataset_avatar(String(ds.display_name), StringName(ds.id),
			StringName(ds.modality) if "modality" in ds and String(ds.modality) != "" else &"text"),
		"status": {"label": tr("DATASET_STATUS_AVAILABLE"), "kind": &"published"} if locked_task == &"" else {"label": tr("DATASET_STATUS_LOCKED"), "kind": &"warning"},
		"fields": fields,
		"actions": actions,
	}

func _dataset_avatar(display_name: String, seed_id: StringName, modality: StringName = &"text") -> Dictionary:
	return {
		"texture": IconRegistry.get_icon(&"dataset", modality),
		"fallback_text": display_name,
		"seed_id": seed_id,
		"kind": &"dataset",
	}

func _dataset_status(source: StringName) -> Dictionary:
	if source == &"open_source":
		return {"label": tr("DATASET_SRC_OPEN"), "kind": &"info"}
	if source == &"purchased":
		return {"label": tr("DATASET_SRC_PURCHASED"), "kind": &"warning"}
	if source == &"collected":
		return {"label": tr("DATASET_SRC_COLLECTED"), "kind": &"published"}
	return {"label": _source_label(source), "kind": &"neutral"}

func _card_button(card: Control, action_id: StringName) -> Button:
	if card == null:
		return null
	var btns: Dictionary = card.get(&"_action_buttons")
	return btns.get(action_id, null) if btns != null else null

func _fmt_tags(tags) -> String:
	if tags == null or not (tags is Array):
		return ""
	var parts := PackedStringArray()
	for t in tags:
		if _is_hidden_tag(StringName(t)):
			continue
		parts.append(_tag_label(StringName(t)))
	return ", ".join(parts)

func _is_hidden_tag(tag: StringName) -> bool:
	return tag == &"business_analysis"

func _source_label(source: StringName) -> String:
	match source:
		&"open_source":
			return tr("DATASET_SRC_OPEN")
		&"purchased":
			return tr("DATASET_SRC_PURCHASED")
		&"collected":
			return tr("DATASET_SRC_COLLECTED")
		_:
			return String(source).replace("_", " ")

func _modality_label(modality: StringName) -> String:
	match modality:
		&"text":
			return tr("DATASET_MOD_TEXT")
		&"image":
			return tr("DATASET_MOD_IMAGE")
		&"multimodal":
			return tr("DATASET_MOD_MULTIMODAL")
		&"code":
			return tr("DATASET_MOD_CODE")
		_:
			return String(modality).replace("_", " ")

func _tag_label(tag: StringName) -> String:
	match tag:
		&"web":
			return tr("DATASET_TAG_WEB")
		&"books":
			return tr("DATASET_TAG_BOOKS")
		&"code":
			return tr("DATASET_TAG_CODE")
		&"languages":
			return tr("DATASET_TAG_LANGUAGES")
		&"math":
			return tr("DATASET_TAG_MATH")
		&"reasoning":
			return tr("DATASET_TAG_REASONING")
		&"science":
			return tr("DATASET_TAG_SCIENCE")
		&"image":
			return tr("DATASET_TAG_IMAGE")
		&"multimodal":
			return tr("DATASET_TAG_MULTIMODAL")
		&"arxiv":
			return tr("DATASET_TAG_ARXIV")
		&"reviews":
			return tr("DATASET_TAG_REVIEWS")
		&"textbook":
			return tr("DATASET_TAG_TEXTBOOK")
		&"edu":
			return tr("DATASET_TAG_EDU")
		&"news":
			return tr("DATASET_TAG_NEWS")
		&"chat":
			return tr("DATASET_TAG_CHAT")
		&"agent":
			return tr("DATASET_TAG_AGENT")
		&"safety":
			return tr("DATASET_TAG_SAFETY")
		_:
			return String(tag).replace("_", " ")

func _comma(n: int) -> String:
	var s := str(abs(n))
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return out if n >= 0 else "-" + out

func _clear_children(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()

# ─── 测试 introspection ──────────────────────────────────────

func click_kind_for_test(kind: StringName) -> void:
	if kind == &"pretrain":
		_kind_pre_btn.pressed.emit()
	elif kind == &"posttrain":
		_kind_post_btn.pressed.emit()

func click_template_action_for_test(template_id: StringName, _action: StringName) -> void:
	if _template_buttons.has(template_id):
		(_template_buttons[template_id] as Button).pressed.emit()

func click_dataset_action_for_test(dataset_id: StringName, _action: StringName) -> void:
	if _dataset_buttons.has(dataset_id):
		(_dataset_buttons[dataset_id] as Button).pressed.emit()

func click_collect_for_test() -> void:
	_collect_btn.pressed.emit()

func all_button_texts_for_test() -> PackedStringArray:
	var out := PackedStringArray()
	_collect_text(self, true, out)
	return out

func all_label_texts_for_test() -> PackedStringArray:
	var out := PackedStringArray()
	_collect_text(self, false, out)
	return out

func get_market_card_count_for_test() -> int:
	return _template_cards.size()

func get_market_card_actions_for_test(template_id: StringName) -> Array:
	return _card_action_ids(_template_cards.get(template_id, null))

func get_market_card_fields_for_test(template_id: StringName) -> Dictionary:
	return _card_fields(_template_cards.get(template_id, null))

func get_owned_card_count_for_test() -> int:
	return _dataset_cards.size()

func get_owned_card_fields_for_test(dataset_id: StringName) -> Dictionary:
	return _card_fields(_dataset_cards.get(dataset_id, null))

func click_source_filter_for_test(id: StringName) -> void:
	if _source_filter != null:
		_source_filter.click_pill_for_test(id)

func click_size_filter_for_test(id: StringName) -> void:
	if _size_filter != null:
		_size_filter.click_pill_for_test(id)

func get_visible_market_count_for_test() -> int:
	var n: int = 0
	for tid in _template_cards:
		if (_template_cards[tid] as Control).visible:
			n += 1
	return n

func get_visible_owned_count_for_test() -> int:
	var n: int = 0
	for did in _dataset_cards:
		if (_dataset_cards[did] as Control).visible:
			n += 1
	return n

func get_owned_card_actions_for_test(dataset_id: StringName) -> Array:
	return _card_action_ids(_dataset_cards.get(dataset_id, null))

func _card_action_ids(card: Control) -> Array:
	if card == null:
		return []
	var btns: Dictionary = card.get(&"_action_buttons")
	return btns.keys() if btns != null else []

func _card_fields(card: Control) -> Dictionary:
	if card == null:
		return {}
	var fields: Dictionary = {}
	var count: int = card.get_field_count()
	for i in range(count):
		var row: Dictionary = card.get_field_row_for_test(i)
		if row.has("label"):
			fields[row.label] = row.value
	return fields

func _collect_text(node: Node, want_button: bool, out: PackedStringArray) -> void:
	for child in node.get_children():
		if want_button and child is Button:
			out.append((child as Button).text)
		elif (not want_button) and child is Label:
			out.append((child as Label).text)
		_collect_text(child, want_button, out)
