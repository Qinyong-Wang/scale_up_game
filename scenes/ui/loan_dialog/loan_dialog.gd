extends ConfirmationDialog

## LoanDialog — 申请贷款 (金额 + 期数, 实时预览每周还款).
## Per design/经济系统设计.md §4.1.
##
## 流程:
##   1. 展示当前信用评级 / 利率 / 最高可贷.
##   2. 玩家输入金额 (受 max_loan 限制) + 选期数 (12 / 26 / 52 / 104 / 156 周).
##   3. 实时显示每周还款 = 利息 + 等额本金.
##   4. 确认 → economy.take_loan.


signal loan_taken(loan_id: StringName)


const TERMS: Array[int] = [12, 26, 52, 104, 156]

var _rating_label: Label
var _rate_label: Label
var _max_loan_label: Label
var _amount_spin: SpinBox
var _amount_echo: Label    # D-6: 实时显示千分位 "$1,000,000" — SpinBox 自身不支持。
var _term_dropdown: OptionButton
var _preview_label: Label
var _warning_label: Label

var _max_loan: int = 0
var _rate: float = 0.0
var _rating: StringName = &"D"

func _ready() -> void:
	title = tr("LOAN_DLG_TITLE")
	min_size = Vector2i(780, 0)
	dialog_hide_on_ok = false
	get_ok_button().text = tr("LOAN_CONFIRM")
	get_cancel_button().text = tr("ACTION_CANCEL")
	get_ok_button().pressed.connect(_on_confirm_pressed)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(780, 390)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	var root := VBoxContainer.new()
	root.add_theme_constant_override(&"separation", 10)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(root)

	_build_credit_panel(root)
	root.add_child(HSeparator.new())
	_build_form(root)
	root.add_child(HSeparator.new())
	_build_preview(root)

func refresh() -> void:
	var preview: Dictionary = CommandBus.send(&"economy.preview_credit", {})
	_max_loan = int(preview.get(&"max_loan", 0))
	_rate = float(preview.get(&"rate", 0.0))
	_rating = preview.get(&"rating", &"D")
	_rating_label.text = tr("LOAN_RATING") % String(_rating)
	_rate_label.text = tr("LOAN_RATE") % (_rate * 100.0)
	_max_loan_label.text = tr("LOAN_MAX") % _format_money(_max_loan)
	_amount_spin.min_value = 0
	_amount_spin.max_value = maxi(_max_loan, 0)
	if _amount_spin.value <= 0 and _max_loan > 0:
		# 默认 50% 上限.
		_amount_spin.value = float(_max_loan) / 2.0
	_refresh_preview()

func _build_credit_panel(root: VBoxContainer) -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override(&"h_separation", 16)
	grid.add_theme_constant_override(&"v_separation", 4)
	_rating_label = Label.new()
	_rate_label = Label.new()
	_max_loan_label = Label.new()
	grid.add_child(_rating_label)
	grid.add_child(_rate_label)
	grid.add_child(_max_loan_label)
	grid.add_child(Label.new())
	root.add_child(grid)

func _build_form(root: VBoxContainer) -> void:
	var amt_row := HBoxContainer.new()
	amt_row.add_theme_constant_override(&"separation", 8)
	var amt_lbl := Label.new()
	amt_lbl.text = tr("FIELD_AMOUNT")
	amt_lbl.custom_minimum_size = Vector2(70, 0)
	amt_row.add_child(amt_lbl)
	_amount_spin = SpinBox.new()
	_amount_spin.step = 10000
	_amount_spin.allow_greater = false
	_amount_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_amount_spin.value_changed.connect(func(_v): _refresh_preview())
	amt_row.add_child(_amount_spin)
	_amount_echo = Label.new()
	_amount_echo.custom_minimum_size = Vector2(120, 0)
	amt_row.add_child(_amount_echo)
	root.add_child(amt_row)

	var term_row := HBoxContainer.new()
	term_row.add_theme_constant_override(&"separation", 8)
	var term_lbl := Label.new()
	term_lbl.text = tr("FIELD_TERM")
	term_lbl.custom_minimum_size = Vector2(70, 0)
	term_row.add_child(term_lbl)
	_term_dropdown = OptionButton.new()
	_term_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for t in TERMS:
		_term_dropdown.add_item(tr("COUNT_WEEKS") % t)
	_term_dropdown.selected = 0
	_term_dropdown.item_selected.connect(func(_i): _refresh_preview())
	term_row.add_child(_term_dropdown)
	root.add_child(term_row)

func _build_preview(root: VBoxContainer) -> void:
	_preview_label = Label.new()
	_preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_preview_label)
	_warning_label = Label.new()
	_warning_label.modulate = Color(1, 0.55, 0.55)
	_warning_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_warning_label)

func _refresh_preview() -> void:
	var amount: int = int(_amount_spin.value)
	if _amount_echo != null:
		_amount_echo.text = "= $%s" % _format_money(amount)
	var term: int = TERMS[_term_dropdown.selected]
	var weekly_interest: int = int(round(float(amount) * _rate))
	var weekly_principal: int = int(round(float(amount) / float(maxi(term, 1))))
	var weekly_total: int = weekly_interest + weekly_principal
	var total_interest: int = weekly_interest * term
	_preview_label.text = tr("LOAN_PREVIEW") % [
		_format_money(amount), term, _format_money(weekly_total),
		_format_money(weekly_interest), _format_money(weekly_principal),
		_rate * 100.0, _format_money(total_interest)]
	var warning := ""
	if amount <= 0:
		warning = tr("LOAN_WARN_GT0")
	elif amount > _max_loan:
		warning = tr("LOAN_WARN_OVER") % _format_money(_max_loan)
	get_ok_button().disabled = warning != ""
	_warning_label.text = warning

func _on_confirm_pressed() -> void:
	var amount: int = int(_amount_spin.value)
	var term: int = TERMS[_term_dropdown.selected]
	var r: Dictionary = CommandBus.send(&"economy.take_loan",
			{amount = amount, term_weeks = term})
	if r.get(&"ok", false):
		Log.info(&"ui", "loan_dialog_confirmed", {amount = amount, term = term})
		loan_taken.emit(r.loan_id)
		hide()
	else:
		_warning_label.text = tr("LOAN_FAILED") % String(r.get(&"error", &""))

func _format_money(n: int) -> String:
	# 6 位以上加千分位; -1234567 → -1,234,567.
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	out = s + out
	return ("-" + out) if n < 0 else out
