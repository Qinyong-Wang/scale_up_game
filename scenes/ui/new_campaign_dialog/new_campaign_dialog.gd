extends ConfirmationDialog

## NewCampaignDialog — start a marketing campaign.
## Per design/营销系统设计.md §4.
##
## 流程:
##   1. 营销 tab 顶部 "+ 新建活动" 按钮 → popup_centered.
##   2. 玩家填名称 / 周预算 / 周数 / 目标产品 / lead.
##   3. 任意字段变化 → _refresh_preview() 重算总投入 + CAC + 每周拉新预估.
##   4. "启动活动" → CommandBus.send(&"marketing.start_campaign", payload).
##
## 不持有任何系统状态; refresh() 每次从 GameState 重读 product + lead 列表.
## v7 PR-F3 (2026-05): type checkbox 删, 改成产品下拉; campaign 锁单个 product。

signal campaign_started_via_dialog(result: Dictionary)

const _API_TYPE: StringName = &"api"

# Form widgets
var _name_input: LineEdit
var _budget_spin: SpinBox
var _weeks_spin: SpinBox
var _product_dropdown: OptionButton
var _lead_dropdown: OptionButton
var _staff_label: Label

# Preview widgets
var _total_label: Label
var _cac_label: Label
var _attract_label: Label
var _api_demand_label: Label
var _warning_label: Label

func _ready() -> void:
	title = tr("CAMPAIGN_TITLE")
	min_size = Vector2i(780, 660)
	max_size = Vector2i(960, 680)
	dialog_hide_on_ok = false
	get_ok_button().text = tr("CAMPAIGN_START")
	get_cancel_button().text = tr("ACTION_CANCEL")
	get_ok_button().pressed.connect(_on_start_pressed)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(740, 540)
	add_child(scroll)

	var root := VBoxContainer.new()
	root.add_theme_constant_override(&"separation", 8)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(root)

	_build_form(root)
	root.add_child(HSeparator.new())
	_build_preview(root)

	Log.info(&"ui", "NewCampaignDialog ready")

# ---- public --------------------------------------------------------------

func refresh() -> void:
	_populate_product_dropdown()
	_populate_lead_dropdown()
	_refresh_preview()

# ---- form construction ---------------------------------------------------

func _build_form(root: VBoxContainer) -> void:
	_name_input = LineEdit.new()
	_name_input.placeholder_text = tr("CAMPAIGN_NAME_PLACEHOLDER")
	_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_input.text_changed.connect(func(_t): _refresh_preview())
	root.add_child(_label_row(tr("FIELD_NAME"), _name_input))

	_budget_spin = SpinBox.new()
	_budget_spin.min_value = 100
	_budget_spin.max_value = 20_000_000
	_budget_spin.step = 100
	_budget_spin.value = 5_000
	_budget_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# 8 位数 (20,000,000) 需要更宽的输入框, 否则数字被 spinner 箭头挡住。
	_budget_spin.custom_minimum_size = Vector2(180, 0)
	_budget_spin.value_changed.connect(func(_v): _refresh_preview())
	var budget_row := HBoxContainer.new()
	budget_row.add_theme_constant_override(&"separation", 6)
	# budget_row 包了 spin + "/周" label; 它本身也要 EXPAND_FILL 才能在 _label_row
	# 里撑开 (其他字段直接把控件交给 _label_row, 自带 EXPAND_FILL — 这行漏了导致
	# 输入框缩到最小宽被挡住)。
	budget_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	budget_row.add_child(_budget_spin)
	var per_week_l := Label.new()
	per_week_l.text = tr("CAMPAIGN_PER_WEEK")
	per_week_l.custom_minimum_size = Vector2(48, 0)
	budget_row.add_child(per_week_l)
	root.add_child(_label_row(tr("FIELD_WEEKLY_BUDGET"), budget_row))

	_weeks_spin = SpinBox.new()
	_weeks_spin.min_value = 1
	_weeks_spin.max_value = 52
	_weeks_spin.step = 1
	_weeks_spin.value = 13
	_weeks_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_weeks_spin.value_changed.connect(func(_v): _refresh_preview())
	root.add_child(_label_row(tr("FIELD_WEEKS"), _weeks_spin))

	# v7 PR-F3: 单选下拉, 锁 1 个具体产品。
	_product_dropdown = OptionButton.new()
	_product_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_product_dropdown.item_selected.connect(func(_i): _refresh_preview())
	root.add_child(_label_row(tr("CAMPAIGN_TARGET_PRODUCT"), _product_dropdown))

	_lead_dropdown = OptionButton.new()
	_lead_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lead_dropdown.item_selected.connect(func(_i): _refresh_preview())
	root.add_child(_label_row("Lead", _lead_dropdown))

	# v8: 营销活动硬性占用营销员工 (见 design/营销系统设计.md §4)。展示需求 + 空闲数。
	_staff_label = Label.new()
	_staff_label.add_theme_color_override(&"font_color", UITheme.TEXT_SECONDARY)
	root.add_child(_staff_label)

func _build_preview(root: VBoxContainer) -> void:
	var sec := Label.new()
	sec.text = tr("FIELD_PREVIEW")
	sec.add_theme_color_override(&"font_color", UITheme.ACCENT_INFO)
	root.add_child(sec)
	_total_label = Label.new()
	root.add_child(_total_label)
	_cac_label = Label.new()
	root.add_child(_cac_label)
	# 订阅产品: 显示「人/周」; api 产品: 显示「tokens/周」(只一行根据 type 切换)。
	_attract_label = Label.new()
	_attract_label.add_theme_color_override(&"font_color", UITheme.ACCENT_PRIMARY)
	root.add_child(_attract_label)
	_api_demand_label = Label.new()
	_api_demand_label.add_theme_color_override(&"font_color", UITheme.ACCENT_PRIMARY)
	root.add_child(_api_demand_label)
	_warning_label = Label.new()
	_warning_label.add_theme_color_override(&"font_color", UITheme.ACCENT_DANGER)
	_warning_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_warning_label)

func _label_row(label_text: String, control: Control) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 6)
	var l := Label.new()
	l.text = label_text
	l.custom_minimum_size = Vector2(80, 0)
	row.add_child(l)
	row.add_child(control)
	return row

# ---- populate widgets ----------------------------------------------------

## v7 PR-F3: dropdown 列出玩家所有产品。label 格式: "产品名 (type · bound_model)"。
func _populate_product_dropdown() -> void:
	_product_dropdown.clear()
	for prod in GameState.products:
		var label: String = _product_label(prod)
		var idx: int = _product_dropdown.item_count
		_product_dropdown.add_item(label)
		_product_dropdown.set_item_metadata(idx, prod.id)
	if _product_dropdown.item_count > 0:
		_product_dropdown.select(0)

func _product_label(prod) -> String:
	var name: String = String(prod.display_name) if "display_name" in prod \
			and not String(prod.display_name).is_empty() else String(prod.id)
	var ptype: String = "?"
	if "type" in prod:
		ptype = tr(ProductSystem.TYPE_LABEL_KEY.get(
				StringName(prod.type), String(prod.type)))
	var bound: String = String(prod.bound_model_id) if "bound_model_id" in prod \
			and prod.bound_model_id != &"" else tr("CAMPAIGN_UNBOUND")
	return "%s  (%s · %s)" % [name, ptype, bound]

## Per design/招聘系统设计.md §5.4: campaign 的 marketing_lead 是软要求 (提供
## conversion 加成)。下拉只列匹配 specialty 的 idle lead (含创始人, 创始人无加成),
## 保留"(无 Lead)"作为合法选项。
func _populate_lead_dropdown() -> void:
	_lead_dropdown.clear()
	_lead_dropdown.add_item(tr("CAMPAIGN_NO_LEAD"))
	_lead_dropdown.set_item_metadata(0, &"")
	for lead in GameState.leads:
		if not lead.is_idle():
			continue
		if not HiringSystem.lead_matches_specialty(lead, &"marketing_lead"):
			continue
		var suffix: String = tr("CAMPAIGN_FOUNDER_SUFFIX") if lead.is_player_scientist else ""
		var idx := _lead_dropdown.item_count
		# 下拉已按 specialty 过滤 (marketing_lead), 不再露出 raw 枚举。
		_lead_dropdown.add_item(tr("CAMPAIGN_LEAD_ITEM") % [
				NameRomanizer.localized(lead.display_name), String(lead.level),
				float(lead.ability), suffix])
		_lead_dropdown.set_item_metadata(idx, lead.id)
	_lead_dropdown.select(0)

# ---- payload + preview ---------------------------------------------------

func _selected_lead_id() -> StringName:
	var i := _lead_dropdown.selected
	if i <= 0:
		return &""
	return _lead_dropdown.get_item_metadata(i)

func _selected_target_product_id() -> StringName:
	if _product_dropdown.item_count <= 0:
		return &""
	var i := _product_dropdown.selected
	if i < 0:
		return &""
	return StringName(_product_dropdown.get_item_metadata(i))

func _selected_target_product():
	var pid := _selected_target_product_id()
	if pid == &"":
		return null
	for prod in GameState.products:
		if prod.id == pid:
			return prod
	return null

func _build_payload() -> Dictionary:
	var payload: Dictionary = {
		weekly_budget = int(_budget_spin.value),
		total_weeks = int(_weeks_spin.value),
		target_product_id = _selected_target_product_id(),
	}
	var disp: String = _name_input.text.strip_edges()
	if disp != "":
		payload[&"display_name"] = disp
	var lid := _selected_lead_id()
	if lid != &"":
		payload[&"lead_id"] = lid
	return payload

func _lead_multiplier(lead_id: StringName) -> float:
	if lead_id == &"":
		return 1.0
	var lead = HiringSystem.find_lead(lead_id)
	if lead == null or lead.specialty != &"marketing_lead":
		return 1.0
	var table: Dictionary = HiringSystem.LEAD_BONUS_TABLE.get(&"marketing_lead", {})
	var coef: float = float(table.get(&"campaign_efficiency", 0.0))
	return 1.0 + (float(lead.ability) / 100.0) * coef

func _refresh_preview() -> void:
	var budget: int = int(_budget_spin.value)
	var weeks: int = int(_weeks_spin.value)
	var total: int = budget * weeks
	_total_label.text = tr("CAMPAIGN_TOTAL") % [_money(total), weeks]

	var lead_mult: float = _lead_multiplier(_selected_lead_id())
	# 创始人出身加成 (网红 user_growth_multiplier): UserSystem 对本周正向用户净增
	# 整体 ×该系数, 营销拉新是其中一部分, 因此活动预期人数也应体现 (见 design/
	# 营销系统设计.md §4 + 出身系统设计.md §5)。
	var founder_mult: float = FounderSystem.user_growth_multiplier()
	var growth_mult: float = lead_mult * founder_mult
	var rate: float = UserSystem.MARKETING_CONVERSION_RATE
	var cac: float = 1.0 / max(rate * growth_mult, 1e-9)
	var cac_suffix: String = ""
	if lead_mult > 1.0:
		cac_suffix += " (lead ×%.2f)" % lead_mult
	if not is_equal_approx(founder_mult, 1.0):
		cac_suffix += " · " + (tr("CAMPAIGN_FOUNDER_GROWTH") % founder_mult)
	_cac_label.text = tr("CAMPAIGN_CAC") % [cac, cac_suffix]

	# 按目标产品类型切换显示。
	var per_week: float = float(budget) * rate * growth_mult
	var target = _selected_target_product()
	var is_api: bool = target != null and "type" in target and target.type == _API_TYPE
	if target == null:
		_attract_label.text = tr("CAMPAIGN_ATTRACT_NONE")
		_api_demand_label.visible = false
	elif is_api:
		_attract_label.text = tr("CAMPAIGN_ATTRACT_API") % [
				_money(int(round(per_week))), cac]
		var tokens: int = int(round(per_week * float(UserSystem.API_TOKENS_PER_SUB_PER_WEEK)))
		_api_demand_label.text = tr("CAMPAIGN_API_TOKENS") % _format_tokens(tokens)
		_api_demand_label.visible = true
	else:
		_attract_label.text = tr("CAMPAIGN_ATTRACT_SUB") % [
				_money(int(round(per_week)))]
		_api_demand_label.visible = false

	# v8: 营销员工硬性要求, 数量随周预算缩放 (2..8) — 展示需求/空闲, 不足则拦截。
	var need_staff: int = MarketingSystem.required_staff_for_budget(budget)
	var idle_staff: int = int(GameState.staff_pool.get(&"marketing", 0)) \
			- int(GameState.staff_busy.get(&"marketing", 0))
	_staff_label.text = tr("CAMPAIGN_STAFF_REQ") % [need_staff, idle_staff]

	# Validation gate.
	var problems: Array = []
	if budget <= 0:
		problems.append(tr("CAMPAIGN_ERR_BUDGET"))
	if weeks <= 0:
		problems.append(tr("CAMPAIGN_ERR_WEEKS"))
	if need_staff > 0 and idle_staff < need_staff:
		problems.append(tr("CAMPAIGN_ERR_STAFF") % [need_staff, idle_staff])
	if budget > 0 and GameState.cash < budget:
		problems.append(tr("CAMPAIGN_ERR_CASH") % [
				_money(budget), _money(GameState.cash)])
	if GameState.campaigns.size() >= MarketingSystem.MAX_CONCURRENT_CAMPAIGNS:
		problems.append(tr("CAMPAIGN_ERR_CAP") % [
				GameState.campaigns.size(),
				MarketingSystem.MAX_CONCURRENT_CAMPAIGNS])
	if target == null:
		problems.append(tr("CAMPAIGN_ERR_NO_PRODUCT"))
	if problems.is_empty():
		_warning_label.text = ""
		get_ok_button().disabled = false
	else:
		_warning_label.text = "⚠ " + " · ".join(problems)
		get_ok_button().disabled = true

# ---- start ---------------------------------------------------------------

func _on_start_pressed() -> void:
	var payload := _build_payload()
	var r: Dictionary = CommandBus.send(&"marketing.start_campaign", payload)
	if r.ok:
		Log.info(&"ui", "NewCampaignDialog started campaign", {
				campaign_id = r.get(&"campaign_id", &""),
				weekly_budget = payload.get(&"weekly_budget", 0),
				total_weeks = payload.get(&"total_weeks", 0)})
		campaign_started_via_dialog.emit(r)
		hide()
	else:
		var err: String = String(r.get(&"error", &"unknown"))
		Log.warn(&"ui", "NewCampaignDialog start failed", {error = err})
		_warning_label.text = tr("CAMPAIGN_START_FAILED") % err
		get_ok_button().disabled = true

# ---- formatting ---------------------------------------------------------

func _money(n) -> String:
	var v: int = int(n)
	var s: String = str(absi(v))
	var out: String = ""
	var i: int = s.length()
	while i > 3:
		out = "," + s.substr(i - 3, 3) + out
		i -= 3
	out = s.substr(0, i) + out
	return ("-" + out) if v < 0 else out

func _format_tokens(n: int) -> String:
	var v: int = abs(n)
	if v >= 1_000_000_000_000:
		return "%.2fT" % (float(n) / 1_000_000_000_000.0)
	if v >= 1_000_000_000:
		return "%.2fB" % (float(n) / 1_000_000_000.0)
	if v >= 1_000_000:
		return "%.2fM" % (float(n) / 1_000_000.0)
	if v >= 1_000:
		return "%.1fK" % (float(n) / 1_000.0)
	return str(n)
