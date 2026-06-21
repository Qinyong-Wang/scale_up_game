extends VBoxContainer

## CharityView — 慈善 tab 试点视图。Per design/慈善系统设计.md §8。
##
## 视图不读 GameState。调用方 (main.gd) 把 CharitySystem 的 spec + 当前累计 +
## 进行中的 charity 任务转成 dict 后调 refresh(data)。每个公益方向一张卡: 当前
## 加成 / 累计已捐 / 下一档 / 进行中, 底部每档一个捐助按钮 (买不起则禁用)。
##
## 信号:
##   donate_pressed(cause_id, tier_index) — 玩家点某档捐助按钮。

signal donate_pressed(cause_id: StringName, tier_index: int)
signal sim_start_pressed(stage_id: StringName)

const SectionHeaderScene := preload("res://scenes/ui/components/section_header/section_header.tscn")
const CardScene := preload("res://scenes/ui/components/card/card.tscn")

var _section: Control
var _tax_note: Label
var _body: HFlowContainer
var _empty: Label

# 宇宙模拟工程段 (慈善三期, design/宇宙模拟工程设计.md)。
var _sim_section: Control
var _sim_answer: Label
var _sim_body: HFlowContainer

# id → Card, 测试 introspection 用。
var _cards_by_id: Dictionary = {}
var _sim_cards: Dictionary = {}

func _ready() -> void:
	add_theme_constant_override(&"separation", UITheme.S_4)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	_section = SectionHeaderScene.instantiate()
	add_child(_section)
	_section.set_data(tr("CHARITY_SECTION"), -1, "", &"")

	_tax_note = Label.new()
	_tax_note.text = tr("CHARITY_TAX_NOTE")
	_tax_note.add_theme_color_override(&"font_color", UITheme.ACCENT_INFO)
	_tax_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_tax_note)

	_body = HFlowContainer.new()
	_body.add_theme_constant_override(&"h_separation", UITheme.S_3)
	_body.add_theme_constant_override(&"v_separation", UITheme.S_3)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_body)
	_empty = Label.new()
	_empty.text = tr("MSG_NONE")
	_empty.add_theme_color_override(&"font_color", UITheme.TEXT_SECONDARY)
	_body.add_child(_empty)

	# ─── 宇宙模拟工程段 ───
	_sim_section = SectionHeaderScene.instantiate()
	add_child(_sim_section)
	_sim_section.set_data(tr("SIM_SECTION"), -1, "", &"")
	_sim_answer = Label.new()
	_sim_answer.add_theme_font_override(&"font", UITheme.get_ui_font_bold())
	_sim_answer.add_theme_font_size_override(&"font_size", UITheme.FS_HERO if "FS_HERO" in UITheme else 32)
	_sim_answer.add_theme_color_override(&"font_color", UITheme.ACCENT_INFO)
	_sim_answer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sim_answer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sim_answer.visible = false
	add_child(_sim_answer)
	_sim_body = HFlowContainer.new()
	_sim_body.add_theme_constant_override(&"h_separation", UITheme.S_3)
	_sim_body.add_theme_constant_override(&"v_separation", UITheme.S_3)
	_sim_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_sim_body)

func refresh(data: Dictionary) -> void:
	_tax_note.text = tr("CHARITY_TAX_NOTE")
	var causes: Array = data.get("causes", [])
	var cash: int = int(data.get("cash", 0))

	for child in _body.get_children():
		if child == _empty:
			continue
		_body.remove_child(child)
		child.queue_free()
	_cards_by_id.clear()

	_empty.visible = causes.is_empty()
	_section.set_data(tr("CHARITY_SECTION"), causes.size(), "", &"")
	for c in causes:
		var card: Control = CardScene.instantiate()
		_body.add_child(card)
		_populate_card(card, c, cash)
		_cards_by_id[StringName(c.get("id", &""))] = card

	_render_simulation(data.get("simulation", {}))

func _render_simulation(sim: Dictionary) -> void:
	for child in _sim_body.get_children():
		_sim_body.remove_child(child)
		child.queue_free()
	_sim_cards.clear()
	var stages: Array = sim.get("stages", [])
	var done: int = int(sim.get("stages_done", 0))
	var total: int = int(sim.get("total", stages.size()))
	_sim_section.set_data(tr("SIM_SECTION"), done, "", &"")
	# 终极答案揭晓。
	_sim_answer.visible = bool(sim.get("revealed", false))
	if _sim_answer.visible:
		_sim_answer.text = tr("SIM_ANSWER")
	for s in stages:
		var card: Control = CardScene.instantiate()
		_sim_body.add_child(card)
		_populate_sim_card(card, s)
		_sim_cards[StringName(s.get("id", &""))] = card

func _populate_sim_card(card: Control, s: Dictionary) -> void:
	var sid: StringName = StringName(s.get("id", &""))
	var status: String = String(s.get("status", "locked"))
	var status_label: String = tr("SIM_STATUS_LOCKED")
	var status_kind: StringName = &"neutral"
	match status:
		"done":
			status_label = tr("SIM_STATUS_DONE"); status_kind = &"published"
		"running":
			status_label = tr("SIM_STATUS_RUNNING"); status_kind = &"in_progress"
		"available":
			status_label = tr("SIM_STATUS_AVAILABLE"); status_kind = &"draft"
	var fields: Array = [
		{"label": tr("SIM_FIELD_COMPUTE"), "value": _format_flops(float(s.get("min_tflops", 0.0)))},
		{"label": tr("SIM_FIELD_TIME"), "value": tr("SIM_WEEKS_FMT") % int(s.get("weeks", 0))},
		{"label": tr("SIM_FIELD_COST"), "value": "$" + _money(int(s.get("cost", 0)))},
	]
	if status == "running":
		fields.append({"label": tr("SIM_FIELD_REMAINING"),
				"value": tr("SIM_WEEKS_FMT") % int(s.get("remaining_weeks", 0))})
	elif status == "available" and not bool(s.get("can_start", false)):
		fields.append({
			"label": tr("OFFICE_FIELD_HINT"),
			"value": String(s.get("gate_reason", "")),
			"max_lines": -1,
		})
	var actions: Array = []
	if status == "available":
		actions.append({
			"id": &"start",
			"label": tr("SIM_START_BTN"),
			"disabled": not bool(s.get("can_start", false)),
		})
	card.set_data({
		"title": tr(String(s.get("display_name", String(sid)))),
		"subtitle": tr(String(s.get("description", ""))),
		"subtitle_max_lines": -1,
		"avatar": {"texture": IconRegistry.simulation_icon(sid), "fallback_text": String(sid), "seed_id": sid, "kind": &"simulation"},
		"status": {"label": status_label, "kind": status_kind},
		"fields": fields,
		"actions": actions,
	})
	card.action_pressed.connect(func(action_id: StringName):
		if action_id == &"start":
			sim_start_pressed.emit(sid))

func _populate_card(card: Control, c: Dictionary, cash: int) -> void:
	var cid: StringName = StringName(c.get("id", &""))
	var effect: StringName = StringName(c.get("effect_kind", &""))
	var tier_idx: int = int(c.get("current_tier_index", -1))
	var bonus: float = float(c.get("current_bonus", 0.0))
	var donated: int = int(c.get("donated", 0))
	var tier_amounts: Array = c.get("tier_amounts", [])
	var tier_labels: Array = c.get("tier_labels", [])
	var in_progress: Array = c.get("in_progress", [])
	# 顺序爬梯: 已完成档数 + 该方向是否有进行中的捐助 (一次只捐一档)。
	var tier_done: int = int(c.get("tier_done", maxi(0, tier_idx + 1)))
	var donating: bool = bool(c.get("donating", false))

	# 状态徽章: 当前所在档 (tr 内容标签) 或「未捐助」。
	var status_label: String = tr("CHARITY_STATUS_NONE")
	var status_kind: StringName = &"neutral"
	if tier_idx >= 0 and tier_idx < tier_labels.size():
		status_label = tr(String(tier_labels[tier_idx]))
		status_kind = &"published"

	var fields: Array = []
	fields.append({"label": tr("CHARITY_FIELD_BONUS"), "value": _bonus_label(effect, tier_idx, bonus)})
	fields.append({"label": tr("CHARITY_FIELD_DONATED"), "value": "$" + _money(donated)})
	# 下一档: 下一可捐档的捐助额; 已全完成则提示封顶。
	var next_idx: int = tier_done
	if next_idx < tier_amounts.size():
		fields.append({"label": tr("CHARITY_FIELD_NEXT"), "value": tr("CHARITY_NEXT_FMT") % _money(int(tier_amounts[next_idx]))})
	else:
		fields.append({"label": tr("CHARITY_FIELD_NEXT"), "value": tr("CHARITY_NEXT_CAPPED")})
	# 进行中的捐助任务。
	if not in_progress.is_empty():
		fields.append({"label": tr("CHARITY_FIELD_IN_PROGRESS"), "value": _in_progress_label(in_progress)})

	# 每档一个按钮 (顺序爬梯, 每档一次): 已完成档显示「已完成」禁用; 下一可捐档可点
	# (买不起 / 该方向有进行中捐助则禁用); 更高档显示「未解锁」禁用。
	var actions: Array = []
	for i in range(tier_amounts.size()):
		var amount: int = int(tier_amounts[i])
		var label_str: String = tr(String(tier_labels[i])) if i < tier_labels.size() else str(i)
		var btn_label: String
		var disabled: bool
		if i < tier_done:
			btn_label = tr("CHARITY_TIER_DONE_FMT") % label_str
			disabled = true
		elif i == tier_done:
			btn_label = tr("CHARITY_TIER_BTN_FMT") % [label_str, _money(amount)]
			disabled = amount > cash or donating
		else:
			btn_label = tr("CHARITY_TIER_LOCKED_FMT") % label_str
			disabled = true
		actions.append({
			"id": StringName("donate_%d" % i),
			"label": btn_label,
			"disabled": disabled,
		})

	card.set_data({
		"title": tr(String(c.get("display_name", String(cid)))),
		"subtitle": tr(String(c.get("description", ""))),
		"avatar": {"texture": IconRegistry.charity_icon(cid), "fallback_text": String(cid), "seed_id": cid, "kind": &"charity"},
		"status": {"label": status_label, "kind": status_kind},
		"fields": fields,
		"actions": actions,
	})
	card.action_pressed.connect(_on_card_action.bind(cid))

func _bonus_label(effect: StringName, tier_idx: int, bonus: float) -> String:
	if tier_idx < 0:
		return "—"
	match effect:
		&"s_tier_weight":
			return tr("CHARITY_BONUS_S") % bonus
		&"valuation_mult":
			return tr("CHARITY_BONUS_VALUATION") % int(round(bonus * 100.0))
		&"conversion_mult":
			return tr("CHARITY_BONUS_CONVERSION") % int(round(bonus * 100.0))
		_:
			return "+%.2f" % bonus

func _in_progress_label(in_progress: Array) -> String:
	var first: Dictionary = in_progress[0]
	var amount: int = int(first.get("amount", 0))
	var remaining: int = int(first.get("remaining", 0))
	var total: int = int(first.get("total", 0))
	var s: String = tr("CHARITY_IN_PROGRESS_FMT") % [_money(amount), remaining, total]
	if in_progress.size() > 1:
		s += tr("CHARITY_IN_PROGRESS_MORE") % (in_progress.size() - 1)
	return s

func _on_card_action(action_id: StringName, cause_id: StringName) -> void:
	var s: String = String(action_id)
	if s.begins_with("donate_"):
		var tier_index: int = s.trim_prefix("donate_").to_int()
		donate_pressed.emit(cause_id, tier_index)

# ─── format helpers ────────────────────────────────────────────────

## train_tflops (单位 1e12 FLOPs) → 可读单位 (PFLOPs / EFLOPs / ZFLOPs / YFLOPs)。
func _format_flops(tflops: float) -> String:
	if tflops >= 1.0e12:
		return "%s YFLOPs" % _trim_num(tflops / 1.0e12)
	if tflops >= 1.0e9:
		return "%s ZFLOPs" % _trim_num(tflops / 1.0e9)
	if tflops >= 1.0e6:
		return "%s EFLOPs" % _trim_num(tflops / 1.0e6)
	if tflops >= 1.0e3:
		return "%s PFLOPs" % _trim_num(tflops / 1.0e3)
	return "%s TFLOPs" % _trim_num(tflops)

func _trim_num(v: float) -> String:
	if absf(v - round(v)) < 0.05:
		return str(int(round(v)))
	return "%.1f" % v

func _money(n: int) -> String:
	var v: int = absi(n)
	var s: String = str(v)
	var out: String = ""
	var i: int = s.length()
	while i > 3:
		out = "," + s.substr(i - 3, 3) + out
		i -= 3
	out = s.substr(0, i) + out
	return ("-" + out) if n < 0 else out

# ─── 测试 introspection ──────────────────────────────────────

func get_card_count_for_test() -> int:
	return _cards_by_id.size()

func get_card_for_test(cause_id: StringName) -> Control:
	return _cards_by_id.get(cause_id, null)

func get_sim_card_count_for_test() -> int:
	return _sim_cards.size()

func get_sim_card_for_test(stage_id: StringName) -> Control:
	return _sim_cards.get(stage_id, null)

func is_answer_revealed_for_test() -> bool:
	return _sim_answer != null and _sim_answer.visible

func click_sim_start_for_test(stage_id: StringName) -> void:
	var c: Control = _sim_cards.get(stage_id, null)
	if c != null and c.has_method(&"click_action_for_test"):
		c.click_action_for_test(&"start")

func click_donate_for_test(cause_id: StringName, tier_index: int) -> void:
	var c: Control = _cards_by_id.get(cause_id, null)
	if c != null and c.has_method(&"click_action_for_test"):
		c.click_action_for_test(StringName("donate_%d" % tier_index))

func all_button_texts_for_test() -> PackedStringArray:
	var out := PackedStringArray()
	_collect_text(self, true, out)
	return out

func _collect_text(node: Node, want_button: bool, out: PackedStringArray) -> void:
	for child in node.get_children():
		if want_button and child is Button:
			out.append((child as Button).text)
		_collect_text(child, want_button, out)
