extends ConfirmationDialog

## PriceEditDialog — 改 published 模型 API 价格 (v8 PR-I).
##
## 取代 ModelCard 旧的「改价 +25% / -20%」两个按钮:
##   1. 显示当前 per_token_price (单位 $/M tok)、推理成本、指导价。
##   2. 玩家在输入框敲新价 ($/M tok)。
##   3. 实时计算 ratio_to_guidance 与 weekly_growth_rate, 渲染
##      「+4%/周 (增益区)」/「-15%/周」/「⚠ 0 需求 (cliff)」三档反馈,
##      让玩家在按确认前看到定价后果。
##   4. 确认 → research.set_api_price.
##
## 单位约定: 内部 ResearchSystem 用 $/tok (per_token_price), 玩家面板用
## $/M tok (× 1e6) — 大众理解的 GPT/Claude 定价单位。

signal price_updated(model_id: StringName, applied_price: float)

const _PRICE_PER_M_MIN: float = 0.0
const _PRICE_PER_M_MAX: float = 10000.0
const _PRICE_PER_M_STEP: float = 0.01

var _model: Model = null

var _title_label: Label
var _current_label: Label  # 当前单价 (左) + 成本/指导价 (右) 合一行
var _price_spin: SpinBox
var _preview_label: Label
var _warning_label: Label

func _ready() -> void:
	title = tr("PRICE_TITLE")
	# warning label autowrap 触发时会长出 2 行, +OK/Cancel chrome + 标题 ~80px,
	# 220 顶不住 → 内容被裁。提到 320 留出余量, ScrollContainer 再兜底超长内容。
	min_size = Vector2i(780, 480)
	dialog_hide_on_ok = false
	get_ok_button().text = tr("PRICE_CONFIRM")
	get_cancel_button().text = tr("ACTION_CANCEL")
	get_ok_button().pressed.connect(_on_confirm_pressed)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(750, 360)
	add_child(scroll)

	var root := VBoxContainer.new()
	root.add_theme_constant_override(&"separation", 8)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(root)

	_build_info(root)
	_build_form(root)
	_build_preview(root)

func refresh(model: Model) -> void:
	_model = model
	if _model == null:
		_warning_label.text = tr("PRICE_NO_MODEL")
		get_ok_button().disabled = true
		return
	var base: float = ResearchSystem.base_price_per_token(_model)
	var guidance: float = ResearchSystem.guidance_price_per_token(_model)
	var open_label: String = tr("PRICE_OPEN_SOURCE") if (_model.is_open_source
			or StringName(_model.provenance) == &"downloaded_os") else tr("PRICE_CLOSED_SOURCE")
	_title_label.text = tr("PRICE_TITLE_LABEL") % [
		String(_model.display_name), open_label,
		_format_per_m(float(_model.per_token_price))]
	_current_label.text = tr("PRICE_COST_GUIDE") % [
		_format_per_m(base), _format_per_m(guidance)]
	_price_spin.min_value = _PRICE_PER_M_MIN
	_price_spin.max_value = _PRICE_PER_M_MAX
	_price_spin.step = _PRICE_PER_M_STEP
	_price_spin.value = float(_model.per_token_price) * 1_000_000.0
	_refresh_preview()

func _build_info(root: VBoxContainer) -> void:
	_title_label = Label.new()
	_title_label.add_theme_color_override(&"font_color", UITheme.ACCENT_INFO)
	root.add_child(_title_label)
	_current_label = Label.new()
	root.add_child(_current_label)

func _build_form(root: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	var lbl := Label.new()
	lbl.text = tr("PRICE_NEW")
	lbl.custom_minimum_size = Vector2(80, 0)
	row.add_child(lbl)
	_price_spin = SpinBox.new()
	_price_spin.step = _PRICE_PER_M_STEP
	_price_spin.allow_greater = false
	_price_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_price_spin.value_changed.connect(func(_v): _refresh_preview())
	row.add_child(_price_spin)
	var unit := Label.new()
	unit.text = "$/M tok"
	row.add_child(unit)
	root.add_child(row)

func _build_preview(root: VBoxContainer) -> void:
	_preview_label = Label.new()
	_preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_preview_label)
	_warning_label = Label.new()
	_warning_label.add_theme_color_override(&"font_color", UITheme.ACCENT_DANGER)
	_warning_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_warning_label)

func _refresh_preview() -> void:
	if _model == null:
		return
	var new_per_token: float = _price_spin.value / 1_000_000.0
	var r: Dictionary = CommandBus.send(&"research.preview_growth_rate", {
		flops_per_token = float(_model.flops_per_token),
		active_param_ratio = float(_model.active_param_ratio),
		per_token_price = new_per_token,
		is_open_source = bool(_model.is_open_source)
				or StringName(_model.provenance) == &"downloaded_os",
	})
	if not r.get(&"ok", false):
		_preview_label.text = ""
		_warning_label.text = tr("PRICE_PREVIEW_FAILED") % String(r.get(&"error", &"unknown"))
		get_ok_button().disabled = true
		return
	get_ok_button().disabled = false
	var ratio: float = float(r.get(&"ratio_to_guidance", 0.0))
	var rate: float = float(r.get(&"rate", 0.0))
	# Three feedback zones — design §4.8 (ResearchSystem.weekly_growth_rate).
	var zone: String = ""
	if rate <= -0.999:
		zone = tr("PRICE_ZONE_ZERO")
		_warning_label.text = zone
	else:
		_warning_label.text = ""
		if ratio <= 0.6:
			zone = tr("PRICE_ZONE_BOOST")
		elif ratio <= 1.0:
			zone = tr("PRICE_ZONE_NEUTRAL")
		else:
			zone = tr("PRICE_ZONE_PENALTY")
	_preview_label.text = tr("PRICE_PREVIEW") % [
		ratio * 100.0, _format_growth(rate), zone]

func _format_growth(rate: float) -> String:
	if rate <= -0.999:
		return tr("PRICE_ZERO_SHORT")
	var pct: float = rate * 100.0
	if pct >= 0.0:
		return tr("PRICE_GROWTH_POS") % pct
	return tr("PRICE_GROWTH") % pct

func _format_per_m(per_token: float) -> String:
	var per_m: float = per_token * 1_000_000.0
	if per_m < 0.01:
		return "$%.4f/M tok" % per_m
	if per_m < 1.0:
		return "$%.2f/M tok" % per_m
	return "$%.2f/M tok" % per_m

func _on_confirm_pressed() -> void:
	if _model == null:
		return
	var new_per_token: float = _price_spin.value / 1_000_000.0
	var r: Dictionary = CommandBus.send(&"research.set_api_price", {
		model_id = _model.id,
		per_token_price = new_per_token,
	})
	if r.get(&"ok", false):
		var applied: float = float(r.get(&"applied_price", new_per_token))
		Log.info(&"ui", "price_edit_dialog_confirmed",
				{model_id = _model.id, price = applied})
		price_updated.emit(_model.id, applied)
		hide()
	else:
		_warning_label.text = tr("PRICE_FAILED") % String(r.get(&"error", &"unknown"))
