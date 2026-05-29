extends ConfirmationDialog

## FundingDialog — 接受指定融资轮 (8 轮玩家自发, conditions 满足即可跳轮).
## Per design/经济系统设计.md §4.6.
##
## 弹出前调用 open_for_round(round_id) 把目标轮号传入, 内部读取
## EconomySystem.FUNDING_ROUND_TABLE 取金额/稀释区间 + 估值预估展示.
## 玩家可在区间内拖动滑条调节金额, 内部根据 (amount / valuation) 反推稀释.


signal funding_accepted(round_id: StringName, amount: int, dilution: float)


const FOUNDER_FLOOR: float = 0.5

var _round_id: StringName = &""
var _spec: Dictionary = {}
var _valuation: int = 0
var _founder_before: float = 1.0

var _summary_label: Label
var _amount_spin: SpinBox
var _amount_echo: Label    # D-6: 实时显示千分位 "$1,300,000" — SpinBox 自身不支持。
var _valuation_label: Label
var _dilution_label: Label
var _new_founder_label: Label
var _warning_label: Label

func _ready() -> void:
	title = tr("FUNDING_DLG_TITLE")
	min_size = Vector2i(810, 0)
	dialog_hide_on_ok = false
	get_ok_button().text = tr("FUNDING_CONFIRM")
	get_cancel_button().text = tr("FUNDING_RECONSIDER")
	get_ok_button().pressed.connect(_on_confirm_pressed)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(810, 420)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	var root := VBoxContainer.new()
	root.add_theme_constant_override(&"separation", 10)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(root)

	_summary_label = Label.new()
	_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_summary_label)

	root.add_child(HSeparator.new())

	var amt_row := HBoxContainer.new()
	amt_row.add_theme_constant_override(&"separation", 8)
	var amt_lbl := Label.new()
	amt_lbl.text = tr("FIELD_AMOUNT")
	amt_lbl.custom_minimum_size = Vector2(70, 0)
	amt_row.add_child(amt_lbl)
	_amount_spin = SpinBox.new()
	_amount_spin.step = 100000
	_amount_spin.allow_greater = false
	_amount_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_amount_spin.value_changed.connect(func(_v): _refresh_preview())
	amt_row.add_child(_amount_spin)
	_amount_echo = Label.new()
	_amount_echo.custom_minimum_size = Vector2(140, 0)
	amt_row.add_child(_amount_echo)
	root.add_child(amt_row)

	_valuation_label = Label.new()
	_dilution_label = Label.new()
	_new_founder_label = Label.new()
	root.add_child(_valuation_label)
	root.add_child(_dilution_label)
	root.add_child(_new_founder_label)
	root.add_child(HSeparator.new())
	_warning_label = Label.new()
	_warning_label.modulate = Color(1, 0.55, 0.55)
	_warning_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_warning_label)

func open_for_round(round_id: StringName) -> void:
	_round_id = round_id
	_spec = EconomySystem.FUNDING_ROUND_TABLE.get(round_id, {})
	if _spec.is_empty():
		Log.warn(&"ui", "funding_dialog_unknown_round", {round = round_id})
		return
	_founder_before = float(GameState.equity.founder)
	# 估值近似 = amount_mid / dilution_mid. 这是 UI 用的展示值, 实际接受时
	# EconomySystem._compute_valuation 会用真实公式再算一次 (rank/portfolio
	# bonus 等). 真实值与展示值有偏差, 但 UI 不会泄露 → 接受后日志里看真值.
	var amount_mid: int = int((int(_spec.amin) + int(_spec.amax)) / 2)
	var dilution_mid: float = (float(_spec.dmin) + float(_spec.dmax)) / 2.0
	_valuation = int(round(float(amount_mid) / max(dilution_mid, 1e-9)))

	title = tr("FUNDING_ACCEPT_TITLE") % tr(String(_spec.get("display_name", String(round_id))))
	_summary_label.text = tr("FUNDING_SUMMARY") % [
		tr(String(_spec.get("display_name", String(round_id)))),
		_format_money(int(_spec.amin)), _format_money(int(_spec.amax)),
		float(_spec.dmin) * 100.0, float(_spec.dmax) * 100.0,
		_format_money(_valuation), _founder_before * 100.0]
	_amount_spin.min_value = float(_spec.amin)
	_amount_spin.max_value = float(_spec.amax)
	_amount_spin.value = float(amount_mid)
	_refresh_preview()
	popup_centered()

func _refresh_preview() -> void:
	if _spec.is_empty():
		return
	var amount: int = int(_amount_spin.value)
	if _amount_echo != null:
		_amount_echo.text = "= $%s" % _format_money(amount)
	# 把 amount 投影到 dilution 区间. amount 大 → dilution 大 (锚到 spec 范围).
	var span_amount: int = int(_spec.amax) - int(_spec.amin)
	var t: float = 0.5
	if span_amount > 0:
		t = float(amount - int(_spec.amin)) / float(span_amount)
	var dilution: float = lerpf(float(_spec.dmin), float(_spec.dmax), t)
	var new_founder: float = _founder_before * (1.0 - dilution)
	_valuation_label.text = tr("FUNDING_VALUATION") % _format_money(_valuation)
	_dilution_label.text = tr("FUNDING_DILUTION") % (dilution * 100.0)
	_new_founder_label.text = tr("FUNDING_FOUNDER_AFTER") % [
			new_founder * 100.0, _founder_before * 100.0]
	var warning := ""
	if new_founder <= FOUNDER_FLOOR:
		warning = tr("FUNDING_WARN_50")
	get_ok_button().disabled = warning != ""
	_warning_label.text = warning

func _on_confirm_pressed() -> void:
	if _spec.is_empty():
		return
	var amount: int = int(_amount_spin.value)
	var span_amount: int = int(_spec.amax) - int(_spec.amin)
	var t: float = 0.5
	if span_amount > 0:
		t = float(amount - int(_spec.amin)) / float(span_amount)
	var dilution: float = lerpf(float(_spec.dmin), float(_spec.dmax), t)
	var r: Dictionary = CommandBus.send(&"economy.start_funding_round", {
		round = _round_id,
		amount = amount,
		dilution = dilution,
	})
	if r.get(&"ok", false):
		Log.info(&"ui", "funding_dialog_confirmed",
				{round = _round_id, amount = int(r.amount), dilution = float(r.dilution),
				 valuation = int(r.valuation)})
		funding_accepted.emit(_round_id, int(r.amount), float(r.dilution))
		hide()
	else:
		_warning_label.text = tr("FUNDING_FAILED") % String(r.get(&"error", &""))

func _format_money(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	out = s + out
	return ("-" + out) if n < 0 else out
