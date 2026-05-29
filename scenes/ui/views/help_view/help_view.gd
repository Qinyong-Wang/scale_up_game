extends VBoxContainer

## HelpView — 右侧导航「帮助」视图。Per design/教程与帮助系统设计.md §2。
##
## master-detail: 顶部「重新查看新手引导」按钮 + 左系统话题列表 + 右说明面板 (RichTextLabel,
## 自动换行, 溢出交给外层 tab 的 ScrollContainer, 不嵌套滚动)。
##
## 视图不读 GameState; TOPICS 是内置静态话题 (核心循环优先), refresh() 即重建文案,
## 让语言切换 (_on_locale_changed → _refresh → refresh) 即时生效。

signal replay_tutorial_pressed

# 话题: 覆盖全部玩家面向系统, 按游玩流程排序。文案在 strings.csv (HELP_*)。
const TOPICS: Array = [
	{id = &"turn",        title = "HELP_TURN_TITLE",        body = "HELP_TURN_BODY"},
	{id = &"training",    title = "HELP_TRAINING_TITLE",    body = "HELP_TRAINING_BODY"},
	{id = &"product",     title = "HELP_PRODUCT_TITLE",     body = "HELP_PRODUCT_BODY"},
	{id = &"marketing",   title = "HELP_MARKETING_TITLE",   body = "HELP_MARKETING_BODY"},
	{id = &"competitors", title = "HELP_COMPETITORS_TITLE", body = "HELP_COMPETITORS_BODY"},
	{id = &"economy",     title = "HELP_ECONOMY_TITLE",     body = "HELP_ECONOMY_BODY"},
	{id = &"hiring",      title = "HELP_HIRING_TITLE",      body = "HELP_HIRING_BODY"},
	{id = &"infra",       title = "HELP_INFRA_TITLE",       body = "HELP_INFRA_BODY"},
	{id = &"dataset",     title = "HELP_DATASET_TITLE",     body = "HELP_DATASET_BODY"},
	{id = &"tech",        title = "HELP_TECH_TITLE",        body = "HELP_TECH_BODY"},
	{id = &"tasks",       title = "HELP_TASKS_TITLE",       body = "HELP_TASKS_BODY"},
	{id = &"events",      title = "HELP_EVENTS_TITLE",      body = "HELP_EVENTS_BODY"},
	{id = &"charity",     title = "HELP_CHARITY_TITLE",     body = "HELP_CHARITY_BODY"},
	{id = &"collection",  title = "HELP_COLLECTION_TITLE",  body = "HELP_COLLECTION_BODY"},
]

const SectionHeaderScene := preload("res://scenes/ui/components/section_header/section_header.tscn")

var _replay_btn: Button
var _topic_list: VBoxContainer
var _detail_title: Label
var _detail_body: RichTextLabel
var _topic_buttons: Dictionary = {}   # id → Button
var _selected: StringName = &""

func _ready() -> void:
	add_theme_constant_override(&"separation", UITheme.S_4)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	var section: Control = SectionHeaderScene.instantiate()
	add_child(section)
	section.set_data(tr("NAV_HELP"), -1, "", &"")

	_replay_btn = Button.new()
	_replay_btn.text = tr("HELP_REPLAY_TUTORIAL")
	_replay_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_replay_btn.pressed.connect(func(): replay_tutorial_pressed.emit())
	add_child(_replay_btn)

	# master-detail: 左话题列表 + 右说明。
	var split := HBoxContainer.new()
	split.add_theme_constant_override(&"separation", UITheme.S_4)
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(split)

	_topic_list = VBoxContainer.new()
	_topic_list.add_theme_constant_override(&"separation", UITheme.S_1)
	_topic_list.custom_minimum_size = Vector2(220, 0)
	split.add_child(_topic_list)

	var detail := VBoxContainer.new()
	detail.add_theme_constant_override(&"separation", UITheme.S_3)
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(detail)

	_detail_title = Label.new()
	_detail_title.add_theme_font_override(&"font", UITheme.get_ui_font_bold())
	_detail_title.add_theme_font_size_override(&"font_size", UITheme.FS_LG)
	_detail_title.add_theme_color_override(&"font_color", UITheme.TEXT_PRIMARY)
	detail.add_child(_detail_title)

	_detail_body = RichTextLabel.new()
	_detail_body.bbcode_enabled = false
	_detail_body.fit_content = true
	_detail_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_body.add_theme_font_size_override(&"normal_font_size", UITheme.FS_MD)
	_detail_body.add_theme_color_override(&"default_color", UITheme.TEXT_PRIMARY)
	detail.add_child(_detail_body)

	_build_topic_buttons()
	if not TOPICS.is_empty():
		_select(StringName(TOPICS[0].id))

func _build_topic_buttons() -> void:
	for child in _topic_list.get_children():
		_topic_list.remove_child(child)
		child.queue_free()
	_topic_buttons.clear()
	for topic in TOPICS:
		var tid: StringName = StringName(topic.id)
		var btn := Button.new()
		btn.text = tr(String(topic.title))
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.toggle_mode = true
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(func(): _select(tid))
		_topic_list.add_child(btn)
		_topic_buttons[tid] = btn

func _select(id: StringName) -> void:
	var topic := _topic_by_id(id)
	if topic.is_empty():
		return
	_selected = id
	_detail_title.text = tr(String(topic.title))
	_detail_body.text = tr(String(topic.body))
	for tid in _topic_buttons:
		(_topic_buttons[tid] as Button).button_pressed = (tid == id)

func _topic_by_id(id: StringName) -> Dictionary:
	for topic in TOPICS:
		if StringName(topic.id) == id:
			return topic
	return {}

func refresh(_data: Dictionary = {}) -> void:
	# 语言切换时重建按钮文案 + 当前详情 (拉静态内容, 不依赖外部 data)。
	for topic in TOPICS:
		var tid: StringName = StringName(topic.id)
		if _topic_buttons.has(tid):
			(_topic_buttons[tid] as Button).text = tr(String(topic.title))
	if _selected == &"" and not TOPICS.is_empty():
		_selected = StringName(TOPICS[0].id)
	if _selected != &"":
		_select(_selected)

# ─── 测试 introspection ───────────────────────────────────────

func topic_count() -> int:
	return TOPICS.size()

func topic_ids_for_test() -> Array:
	var out: Array = []
	for topic in TOPICS:
		out.append(StringName(topic.id))
	return out

func select_topic_for_test(id: StringName) -> void:
	_select(id)

func current_detail_title_for_test() -> String:
	return _detail_title.text if _detail_title != null else ""

func current_detail_body_for_test() -> String:
	return _detail_body.text if _detail_body != null else ""

func click_replay_for_test() -> void:
	if _replay_btn != null:
		_replay_btn.pressed.emit()
