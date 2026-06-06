extends ConfirmationDialog

## SimulationDonationDialog — 捐建数据中心对话框 (宇宙模拟阶梯, 慈善三期)。
## Per design/宇宙模拟工程设计.md §8。
##
## 不读 GameState: 调用方 (main.gd) 把当前阶段门槛 + 满足门槛的自有空闲未出租 DC 列表转 dict
## 后调 open_for_stage(stage, dcs)。玩家从单选列表里选一座 DC 捐出 (永久消耗), 确认 →
## 发 confirmed_dc(dc_id)。无可捐 DC 时显示空状态并禁用确认。popup 由调用方负责 (便于测试)。
##
## 信号:
##   confirmed_dc(dc_id) — 玩家确认捐出选中的数据中心。

signal confirmed_dc(dc_id: StringName)

var _summary: Label
var _warn: Label
var _pick: Label
var _list: VBoxContainer
var _empty: Label
var _group: ButtonGroup
var _dc_ids: Array[StringName] = []
var _selected: StringName = &""

func _ready() -> void:
	min_size = Vector2i(720, 0)
	dialog_hide_on_ok = false
	get_ok_button().text = tr("SIM_DONATE_CONFIRM")
	get_cancel_button().text = tr("SIM_DONATE_CANCEL")
	get_ok_button().pressed.connect(_on_confirm)

	# 内容收进定高 ScrollContainer (仿 funding_dialog), 否则 ConfirmationDialog 会
	# 随内容撑高, 把 OK/Cancel 按钮顶出窗口外。
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(700, 300)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	var root := VBoxContainer.new()
	root.add_theme_constant_override(&"separation", 10)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(root)

	_summary = Label.new()
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_summary)

	_warn = Label.new()
	_warn.modulate = Color(1.0, 0.7, 0.4)
	_warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_warn)

	root.add_child(HSeparator.new())

	_pick = Label.new()
	root.add_child(_pick)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override(&"separation", 4)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(_list)

	_empty = Label.new()
	_empty.modulate = Color(0.7, 0.7, 0.7)
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty.visible = false
	root.add_child(_empty)

## stage: {display_name, min_train_tflops, cost, weeks}
## dcs:   [{id, display_name, gpu_count, train_tflops, gpu_id}, ...]
func open_for_stage(stage: Dictionary, dcs: Array) -> void:
	title = tr("SIM_DONATE_TITLE") % tr(String(stage.get("display_name", "")))
	_summary.text = tr("SIM_DONATE_REQ") % [
		_format_flops(float(stage.get("min_train_tflops", 0.0))),
		_money(int(stage.get("cost", 0))),
		int(stage.get("weeks", 0))]
	_warn.text = tr("SIM_DONATE_WARN")
	_pick.text = tr("SIM_DONATE_PICK")
	_rebuild_list(dcs)

func _rebuild_list(dcs: Array) -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.free()
	_dc_ids.clear()
	_selected = &""
	_group = ButtonGroup.new()
	for d in dcs:
		var did: StringName = StringName(d.get("id", &""))
		var cb := CheckBox.new()
		cb.button_group = _group
		cb.text = tr("SIM_DONATE_DC_FMT") % [
			tr(String(d.get("display_name", String(did)))),
			_money(int(d.get("gpu_count", 0))),
			_format_flops(float(d.get("train_tflops", 0.0)))]
		cb.toggled.connect(func(on: bool): if on: _selected = did)
		_list.add_child(cb)
		_dc_ids.append(did)
	_empty.text = tr("SIM_DONATE_NONE")
	_empty.visible = dcs.is_empty()
	# 默认选中第一座, 让确认直接可用。
	if not _dc_ids.is_empty():
		(_list.get_child(0) as CheckBox).button_pressed = true
		_selected = _dc_ids[0]
	get_ok_button().disabled = _dc_ids.is_empty()

func _on_confirm() -> void:
	if _selected == &"":
		return
	Log.info(&"ui", "sim_donation_confirmed", {dc_id = _selected})
	confirmed_dc.emit(_selected)
	hide()

# ─── format helpers ────────────────────────────────────────────────

## train_tflops (单位 1e12 FLOPs) → 可读单位。1 PFLOP=1e3 / EFLOP=1e6 /
## ZFLOP=1e9 / YFLOP=1e12 TFLOPs。终局体量落在 EFLOPs ~ ZFLOPs。
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
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	out = s + out
	return ("-" + out) if n < 0 else out

# ─── 测试 introspection ──────────────────────────────────────

func get_dc_option_count_for_test() -> int:
	return _dc_ids.size()

func is_confirm_disabled_for_test() -> bool:
	return get_ok_button().disabled

func selected_dc_id_for_test() -> StringName:
	return _selected

func select_dc_for_test(dc_id: StringName) -> void:
	var i: int = _dc_ids.find(dc_id)
	if i >= 0:
		(_list.get_child(i) as CheckBox).button_pressed = true

func click_confirm_for_test() -> void:
	_on_confirm()
