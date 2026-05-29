extends VBoxContainer

## EventView — 事件 tab 试点视图。
##
## 接 dict {pending: Array, history: Array} (调用方从 EventCard resource +
## GameState.event_history 转好)。视图不访问 GameState。
##
## 信号:
##   option_selected(event_id, option_id)
##   flavor_dismissed(event_id)

signal option_selected(event_id: StringName, option_id: StringName)
signal flavor_dismissed(event_id: StringName)

const SectionHeaderScene := preload("res://scenes/ui/components/section_header/section_header.tscn")
const CardScene := preload("res://scenes/ui/components/card/card.tscn")

var _pending_section: Control
var _pending_body: VBoxContainer
var _history_section: Control
var _history_body: VBoxContainer

# 测试 introspection: event_id → {dismiss_btn, option_id → btn}
var _event_buttons: Dictionary = {}

func _ready() -> void:
	add_theme_constant_override(&"separation", UITheme.S_4)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_pending_section = SectionHeaderScene.instantiate()
	add_child(_pending_section)
	_pending_section.set_data(tr("EVENT_PENDING"), -1, "", &"")
	_pending_body = VBoxContainer.new()
	_pending_body.add_theme_constant_override(&"separation", UITheme.S_3)
	add_child(_pending_body)

	_history_section = SectionHeaderScene.instantiate()
	add_child(_history_section)
	_history_section.set_data(tr("EVENT_HISTORY"), -1, "", &"")
	_history_body = VBoxContainer.new()
	_history_body.add_theme_constant_override(&"separation", 2)
	add_child(_history_body)

func refresh(data: Dictionary) -> void:
	_refresh_pending(data.get("pending", []))
	_refresh_history(data.get("history", []))

func _refresh_pending(pending: Array) -> void:
	_clear_children(_pending_body)
	_event_buttons.clear()
	if pending.is_empty():
		var l := Label.new()
		l.text = tr("MSG_NONE")
		l.add_theme_color_override(&"font_color", UITheme.TEXT_SECONDARY)
		_pending_body.add_child(l)
		_pending_section.set_data(tr("EVENT_PENDING"), 0, "", &"")
		return
	_pending_section.set_data(tr("EVENT_PENDING"), pending.size(), "", &"")
	for ev in pending:
		var card: Control = CardScene.instantiate()
		_pending_body.add_child(card)
		_populate_event_card(card, ev)

func _populate_event_card(card: Control, ev: Dictionary) -> void:
	var eid: StringName = StringName(ev.get("id", &""))
	var category: StringName = StringName(ev.get("category", &"flavor"))
	var category_label: String = _category_label(category)
	var actions: Array = []
	var ev_btns: Dictionary = {"options": {}}
	if category == &"flavor":
		var dismiss_label: String = tr("EVENT_DISMISS")
		var consequence: String = String(ev.get("dismiss_consequence", ""))
		if consequence != "":
			dismiss_label += "  —  " + consequence
		actions.append({"id": &"_dismiss", "label": dismiss_label})
	else:
		for opt in ev.get("options", []):
			# 先翻译裸 label (内容层 content.csv), 再追加已翻译的后果预览 (UI 层),
			# 不能整条复合串过 tr (见 国际化设计.md §6bis)。
			var opt_label: String = tr(String(opt.label))
			var consequence: String = String(opt.get("consequence", ""))
			if consequence != "":
				opt_label += "  —  " + consequence
			actions.append({"id": StringName(opt.id), "label": opt_label})
	card.set_data({
		"title": tr(String(ev.get("title", ""))),
		"subtitle": category_label,
		"avatar": {
			"texture": IconRegistry.get_icon(&"event", category),
			"fallback_text": String(ev.get("title", "")),
			"seed_id": eid,
			"kind": &"dataset",  # 缺图回退仍用 ▸ glyph
		},
		"status": {"label": category_label, "kind": _category_kind(category)},
		"fields": [{
			"label": tr("EVENT_FIELD_BODY"),
			"value": tr(String(ev.get("body", ""))),
			"max_lines": -1,
		}],
		"actions": actions,
	})
	card.action_pressed.connect(_on_event_action.bind(eid, category))
	# 把 actions 收集起来给测试用。
	var card_btns: Dictionary = card.get(&"_action_buttons")
	if card_btns != null:
		ev_btns["all"] = card_btns
	_event_buttons[eid] = ev_btns

func _category_kind(cat: StringName) -> StringName:
	match cat:
		&"opportunity": return &"published"
		&"crisis":      return &"danger"
		_:              return &"neutral"

func _category_label(cat: StringName) -> String:
	match cat:
		&"opportunity": return tr("EVENT_CAT_OPPORTUNITY")
		&"crisis":      return tr("EVENT_CAT_CRISIS")
		&"routine":     return tr("EVENT_CAT_ROUTINE")
		&"flavor":      return tr("EVENT_CAT_FLAVOR")
		&"debug":       return tr("EVENT_CAT_DEBUG")
		_:              return String(cat).replace("_", " ")

func _on_event_action(action_id: StringName, event_id: StringName, _category: StringName) -> void:
	if action_id == &"_dismiss":
		flavor_dismissed.emit(event_id)
	else:
		option_selected.emit(event_id, action_id)

func _refresh_history(history: Array) -> void:
	_clear_children(_history_body)
	_history_section.set_data(tr("EVENT_HISTORY_RECENT") % history.size(), -1, "", &"")
	for inst in history:
		var title: String = tr(String(inst.get("title", "")))
		if title == "":
			title = String(inst.get("template_id", &""))
		var chosen: String = tr(String(inst.get("chosen_label", "")))
		if chosen == "":
			chosen = String(inst.get("chosen_option_id", &""))
		var l := Label.new()
		if chosen == "":
			l.text = "  T%d  %s" % [int(inst.get("resolved_at_turn", 0)), title]
		else:
			l.text = "  T%d  %s  → %s" % [
				int(inst.get("resolved_at_turn", 0)),
				title,
				chosen,
			]
		l.add_theme_color_override(&"font_color", UITheme.TEXT_SECONDARY)
		_history_body.add_child(l)

func _clear_children(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()

# ─── 测试 introspection ──────────────────────────────────────

func click_option_for_test(event_id: StringName, option_id: StringName) -> void:
	var ev_btns: Dictionary = _event_buttons.get(event_id, {})
	var all: Dictionary = ev_btns.get("all", {})
	if all.has(option_id):
		(all[option_id] as Button).pressed.emit()

func click_dismiss_for_test(event_id: StringName) -> void:
	var ev_btns: Dictionary = _event_buttons.get(event_id, {})
	var all: Dictionary = ev_btns.get("all", {})
	if all.has(&"_dismiss"):
		(all[&"_dismiss"] as Button).pressed.emit()

func all_button_texts_for_test() -> PackedStringArray:
	var out := PackedStringArray()
	_collect_text(self, true, out)
	return out

func all_label_texts_for_test() -> PackedStringArray:
	var out := PackedStringArray()
	_collect_text(self, false, out)
	return out

func first_pending_body_max_lines_for_test() -> int:
	for child in _pending_body.get_children():
		if child.has_method("get_field_value_max_lines_for_test"):
			return int(child.get_field_value_max_lines_for_test(0))
	return 0

func _collect_text(node: Node, want_button: bool, out: PackedStringArray) -> void:
	for child in node.get_children():
		if want_button and child is Button:
			out.append((child as Button).text)
		elif (not want_button) and child is Label:
			out.append((child as Label).text)
		_collect_text(child, want_button, out)
