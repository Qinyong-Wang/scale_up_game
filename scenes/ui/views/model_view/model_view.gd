extends VBoxContainer

## ModelCardView — 模型 tab 试点视图 (UI视觉系统设计.md §10 step 5)。
##
## 布局:
##   SectionHeader  我的模型 (N)            [+ 训练新模型...]
##   FilterBar      [全部][训练中][后训][已评估][已发布]  🔍  排序▾
##   ScrollContainer
##     HFlowContainer
##       Card  Card  Card  Card  Card  ...
##   EmptyState (卡片数 0 时显示)
##
## 信号:
##   new_model_pressed              — header 右侧按钮
##   model_action(id, action_id)    — 卡片底部按钮 (evaluate/posttrain/publish_*/price_*/unpublish/delete)
##
## refresh(models: Array) 调用方传入模型列表; view 内部不访问 GameState。

signal new_model_pressed
signal model_action(model_id: StringName, action_id: StringName)

const SectionHeaderScene := preload("res://scenes/ui/components/section_header/section_header.tscn")
const FilterBarScene := preload("res://scenes/ui/components/filter_bar/filter_bar.tscn")
const CardScene := preload("res://scenes/ui/components/card/card.tscn")
const EmptyStateScene := preload("res://scenes/ui/components/empty_state/empty_state.tscn")
const ModelCard := preload("res://scenes/ui/views/model_view/model_card.gd")

# label 是 i18n key (const 里不能调 tr), 在 set_pills 前用 _localize_options() 翻。
const _PILLS: Array = [
	{"id": &"all",         "label": "FILTER_ALL"},
	{"id": &"pretrained",  "label": "MODEL_FILTER_PRETRAINED"},
	{"id": &"posttrained", "label": "MODEL_FILTER_POSTTRAINED"},
	{"id": &"evaluated",   "label": "MODEL_FILTER_EVALUATED"},
	{"id": &"published",   "label": "MODEL_FILTER_PUBLISHED"},
]

const _SORT_OPTIONS: Array = [
	{"id": &"created_desc", "label": "MODEL_SORT_RECENT"},
	{"id": &"name_asc",     "label": "MODEL_SORT_NAME"},
	{"id": &"size_desc",    "label": "MODEL_SORT_SIZE"},
]

## const pill/sort 表里的 label 是 i18n key, 渲染前翻成当前 locale 文案。
func _localize_options(opts: Array) -> Array:
	var out: Array = []
	for o in opts:
		out.append({"id": o.id, "label": tr(String(o.label))})
	return out

var _section: Control            # SectionHeader
var _filter_bar: Control         # FilterBar
var _scroll: ScrollContainer
var _grid: HFlowContainer
var _empty_state: Control        # EmptyState

var _models: Array = []           # 当前 refresh 拿到的全量
var _cards_by_id: Dictionary = {}  # model_id -> Card 实例
var _filter_state: Dictionary = {} # 上次 FilterBar 状态

func _ready() -> void:
	add_theme_constant_override(&"separation", UITheme.S_3)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	_section = SectionHeaderScene.instantiate()
	add_child(_section)
	_section.set_data(tr("MODEL_SECTION"), -1, tr("MODEL_NEW"), &"new_model")
	_section.action_pressed.connect(_on_section_action)

	_filter_bar = FilterBarScene.instantiate()
	add_child(_filter_bar)
	_filter_bar.set_pills(_localize_options(_PILLS))
	_filter_bar.set_sort_options(_localize_options(_SORT_OPTIONS))
	_filter_bar.set_search_placeholder(tr("MODEL_SEARCH_PLACEHOLDER"))
	_filter_bar.state_changed.connect(_on_filter_changed)
	_filter_state = _filter_bar.get_state()

	# 外层 _make_tab 已经有 ScrollContainer 包住 _tab_research, 这里再嵌一层
	# 会让内层 scroll 被压成 0 高度, 卡片显示不出来。直接放 HFlow 即可。
	_grid = HFlowContainer.new()
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override(&"h_separation", UITheme.S_3)
	_grid.add_theme_constant_override(&"v_separation", UITheme.S_3)
	add_child(_grid)
	# 保留 _scroll 字段引用为 null 兼容 (refresh 里只 toggle visible)。
	_scroll = null

	_empty_state = EmptyStateScene.instantiate()
	_empty_state.set_data("◉", tr("MODEL_EMPTY_TITLE"), tr("MODEL_EMPTY_HINT"), tr("MODEL_NEW"), &"new_model")
	_empty_state.action_pressed.connect(func(_id: StringName): new_model_pressed.emit())
	_empty_state.visible = false
	add_child(_empty_state)

## 调用方传入模型列表; view 重新装配卡片墙。
func refresh(models: Array) -> void:
	_models = models.duplicate()
	_rebuild_cards()
	_apply_filter()

func _rebuild_cards() -> void:
	# 清旧卡片。简单粗暴重建; 数量不大 (设计上限百量级)。
	for child in _grid.get_children():
		child.queue_free()
	_cards_by_id.clear()
	for m in _models:
		var card: Control = CardScene.instantiate()
		_grid.add_child(card)
		ModelCard.populate(card, m, _pricing_for(m))
		card.action_pressed.connect(_on_card_action.bind(StringName(m.id)))
		_cards_by_id[StringName(m.id)] = card

# v8 PR-I — collect pricing context for ModelCard. ResearchSystem is an autoload;
# we evaluate base/guidance once per model and feed it into the (stateless)
# translator. See design/研究系统设计.md §4.8.
func _pricing_for(m) -> Dictionary:
	if float(m.flops_per_token) <= 0.0:
		return {}
	var base: float = ResearchSystem.base_price_per_token(m)
	var pricing: Dictionary = {
		&"base_price": base,
		&"guidance_open": base * ResearchSystem.OS_GUIDANCE_MULT,
		&"guidance_closed": base * ResearchSystem.CLOSED_GUIDANCE_MULT,
	}
	if StringName(m.status) == &"published":
		var guidance: float = ResearchSystem.guidance_price_per_token(m)
		pricing[&"ratio_to_guidance"] = (
				0.0 if guidance <= 0.0 else float(m.per_token_price) / guidance)
		pricing[&"weekly_growth"] = ResearchSystem.weekly_growth_rate(m)
	return pricing

func _apply_filter() -> void:
	var selected_pills: Array = _filter_state.get("selected_pills", [&"all"])
	var search_text: String = String(_filter_state.get("search", "")).to_lower()
	var sort_id: StringName = StringName(_filter_state.get("sort", &"created_desc"))

	# pill 过滤集合: 包含 &"all" 即不限 status。
	var status_set: Dictionary = {}
	var unrestricted := selected_pills.has(&"all")
	for p in selected_pills:
		if p != &"all":
			status_set[p] = true

	var visible_models: Array = []
	for m in _models:
		if not unrestricted and not status_set.has(StringName(m.status)):
			_set_card_visible(StringName(m.id), false)
			continue
		if not search_text.is_empty():
			var name_lc: String = String(m.display_name).to_lower()
			var id_lc: String = String(m.id).to_lower()
			if name_lc.find(search_text) == -1 and id_lc.find(search_text) == -1:
				_set_card_visible(StringName(m.id), false)
				continue
		_set_card_visible(StringName(m.id), true)
		visible_models.append(m)

	_apply_sort(visible_models, sort_id)
	_update_section_count(visible_models.size())
	_empty_state.visible = visible_models.is_empty()
	_grid.visible = not visible_models.is_empty()

func _apply_sort(visible_models: Array, sort_id: StringName) -> void:
	# 按选项重排卡片在 grid 中的顺序; queue_free 没用上 (我们只是 move)。
	var sorted_models := visible_models.duplicate()
	match sort_id:
		&"created_desc":
			sorted_models.sort_custom(func(a, b): return int(b.trained_at_turn) < int(a.trained_at_turn))
		&"name_asc":
			sorted_models.sort_custom(func(a, b): return String(a.display_name) < String(b.display_name))
		&"size_desc":
			sorted_models.sort_custom(func(a, b): return float(b.size_params) < float(a.size_params))
		_:
			pass
	for i in range(sorted_models.size()):
		var id := StringName(sorted_models[i].id)
		var card: Control = _cards_by_id.get(id, null)
		if card != null:
			_grid.move_child(card, i)

func _set_card_visible(id: StringName, vis: bool) -> void:
	var card: Control = _cards_by_id.get(id, null)
	if card != null:
		card.visible = vis

func _update_section_count(count: int) -> void:
	if _section != null:
		_section.set_data(tr("MODEL_SECTION"), count, tr("MODEL_NEW"), &"new_model")

# ─── 信号 ────────────────────────────────────────────────────

func _on_section_action(_id: StringName) -> void:
	new_model_pressed.emit()

func _on_filter_changed(state: Dictionary) -> void:
	_filter_state = state
	_apply_filter()

func _on_card_action(action_id: StringName, model_id: StringName) -> void:
	model_action.emit(model_id, action_id)

# ─── 测试 introspection ──────────────────────────────────────

func is_empty_state_visible() -> bool:
	return _empty_state != null and _empty_state.visible

func get_visible_card_count() -> int:
	var n := 0
	for card in _cards_by_id.values():
		if card != null and card.visible:
			n += 1
	return n

func is_card_visible_for_test(model_id: StringName) -> bool:
	var c: Control = _cards_by_id.get(model_id, null)
	return c != null and c.visible

func get_card_action_ids_for_test(model_id: StringName) -> Array:
	var c: Control = _cards_by_id.get(model_id, null)
	if c == null or not c.has_method(&"get_card_action_ids"):
		# Card.gd 没暴露这个 — 通过内部 dictionary 查。
		return _card_action_ids(c)
	return c.get_card_action_ids()

func _card_action_ids(card: Control) -> Array:
	# Card 没暴露 action 列表 API, 直接读其内部 _action_buttons。
	if card == null:
		return []
	var buttons: Dictionary = card.get(&"_action_buttons")
	if buttons == null:
		return []
	return buttons.keys()

func get_card_fields_for_test(model_id: StringName) -> Dictionary:
	var c: Control = _cards_by_id.get(model_id, null)
	if c == null:
		return {}
	var fields: Dictionary = {}
	var count: int = c.get_field_count()
	for i in range(count):
		var row: Dictionary = c.get_field_row_for_test(i)
		if row.has("label"):
			fields[row.label] = row.value
	return fields

func set_filter_pill_for_test(pill_id: StringName) -> void:
	if _filter_bar != null:
		_filter_bar.click_pill_for_test(pill_id)

func set_search_text_for_test(s: String) -> void:
	if _filter_bar != null:
		_filter_bar.set_search_text_for_test(s)

func click_card_action_for_test(model_id: StringName, action_id: StringName) -> void:
	var c: Control = _cards_by_id.get(model_id, null)
	if c != null and c.has_method(&"click_action_for_test"):
		c.click_action_for_test(action_id)

func click_new_model_for_test() -> void:
	if _section != null and _section.has_method(&"click_action_for_test"):
		_section.click_action_for_test()
