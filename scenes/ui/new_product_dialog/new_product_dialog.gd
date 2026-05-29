extends ConfirmationDialog

## NewProductDialog — 精细化产品创建 / 编辑.
## Per design/产品系统设计.md §5.2 (create) + §0bis (api 类型分支).
##
## 两种 mode:
##   - "create": 完整表单, type 可选; OK → product.create.
##   - "edit":  type 固定, 锁掉; 其他字段可改; OK → product.update.
##
## type 下拉里把当前不满足阈值 / 应用节点的类型置灰并显示原因.
## bound_model 下拉根据选中的 type 过滤; api 仅显示无 api 产品的 model.
## api 类型: 隐藏 lead/staff/价格行 (api 没这些).

signal product_created(product_id: StringName)
signal product_edited(product_id: StringName)

const SECONDS_PER_MONTH: int = 2_592_000

# 哪些 type 在 UI 里列出 + 渲染顺序.
const TYPE_ORDER: Array[StringName] = [
	&"chatbot", &"agent", &"multimodal_assistant", &"coding_agent", &"api",
]

# Locked reason codes → 人类可读. 与 ProductSystem 错误码对齐.
const LOCK_REASONS: Dictionary = {
	&"application_node_locked": "PRODUCT_LOCK_APP_NODE",
	&"no_matching_model": "PRODUCT_LOCK_NO_MODEL",
	&"no_uncovered_model": "PRODUCT_LOCK_NO_UNCOVERED",
}

var _mode: StringName = &"create"
var _edit_product_id: StringName = &""

var _type_dropdown: OptionButton
var _model_dropdown: OptionButton
var _lead_dropdown: OptionButton
var _ml_eng_spinbox: SpinBox
var _price_spinbox: SpinBox
var _name_edit: LineEdit
var _auto_track_check: CheckBox

var _lead_row: Control
var _staff_row: Control
var _price_row: Control
var _auto_track_row: Control

var _preview_label: Label
var _warning_label: Label

func _ready() -> void:
	title = tr("PRODUCT_DLG_TITLE")
	min_size = Vector2i(840, 660)
	max_size = Vector2i(1140, 680)
	dialog_hide_on_ok = false
	get_ok_button().text = tr("PRODUCT_PUBLISH")
	get_cancel_button().text = tr("ACTION_CANCEL")
	get_ok_button().pressed.connect(_on_confirm_pressed)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(800, 540)
	add_child(scroll)

	var root := VBoxContainer.new()
	root.add_theme_constant_override(&"separation", 10)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(root)

	_build_form(root)
	root.add_child(HSeparator.new())
	_build_preview(root)

	Log.info(&"ui", "NewProductDialog ready")

# ---- public ----------------------------------------------------------------

## 用作 create 入口. 弹之前 refresh 一次.
func setup_create() -> void:
	_mode = &"create"
	_edit_product_id = &""
	title = tr("PRODUCT_DLG_TITLE")
	get_ok_button().text = tr("PRODUCT_PUBLISH")
	_type_dropdown.disabled = false
	refresh()

## 用作 edit 入口. 调用前: product 必须存在.
func setup_edit(product_id: StringName) -> void:
	_mode = &"edit"
	_edit_product_id = product_id
	title = tr("PRODUCT_EDIT_TITLE")
	get_ok_button().text = tr("SAVE_BTN")
	# type 不可改 (改 type = 改产品本质, 走"删→重建"流程).
	_type_dropdown.disabled = true
	refresh()
	_load_product_into_form()

func refresh() -> void:
	_populate_type_dropdown()
	_on_type_changed()  # 触发 model dropdown 重填
	_populate_lead_dropdown()
	_refresh_preview()

# ---- form ------------------------------------------------------------------

func _build_form(root: VBoxContainer) -> void:
	_type_dropdown = OptionButton.new()
	_type_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_type_dropdown.item_selected.connect(func(_i): _on_type_changed())
	root.add_child(_label_row(tr("FIELD_TYPE"), _type_dropdown))

	_model_dropdown = OptionButton.new()
	_model_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_model_dropdown.item_selected.connect(func(_i): _refresh_preview())
	root.add_child(_label_row(tr("PRODUCT_BIND_MODEL"), _model_dropdown))

	_name_edit = LineEdit.new()
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.placeholder_text = tr("PRODUCT_NAME_PLACEHOLDER")
	root.add_child(_label_row(tr("PRODUCT_NAME"), _name_edit))

	_lead_dropdown = OptionButton.new()
	_lead_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lead_dropdown.item_selected.connect(func(_i): _refresh_preview())
	_lead_row = _label_row("Lead", _lead_dropdown)
	root.add_child(_lead_row)

	_ml_eng_spinbox = SpinBox.new()
	_ml_eng_spinbox.min_value = 0
	_ml_eng_spinbox.max_value = 20
	_ml_eng_spinbox.value = 0
	_ml_eng_spinbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ml_eng_spinbox.value_changed.connect(func(_v): _refresh_preview())
	_staff_row = _label_row(tr("PRODUCT_ML_ENG"), _ml_eng_spinbox)
	_ml_eng_spinbox.tooltip_text = tr("PRODUCT_ML_TOOLTIP")
	root.add_child(_staff_row)

	_price_spinbox = SpinBox.new()
	_price_spinbox.min_value = 0
	_price_spinbox.max_value = 10000
	# D-12: 默认值在 _on_type_changed 里按所选类型读 spec.subscription_price_guidance,
	# 避免老硬编码 99 把玩家钉死在惩罚区。这里只给个初始占位。
	_price_spinbox.value = 0
	_price_spinbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_price_spinbox.value_changed.connect(func(_v): _refresh_preview())
	_price_row = _label_row(tr("PRODUCT_SUB_PRICE"), _price_spinbox)
	root.add_child(_price_row)

	_auto_track_check = CheckBox.new()
	_auto_track_check.text = tr("PRODUCT_AUTO_TRACK")
	_auto_track_check.tooltip_text = tr("PRODUCT_AUTO_TOOLTIP")
	_auto_track_check.button_pressed = true
	_auto_track_row = _label_row("", _auto_track_check)
	root.add_child(_auto_track_row)

func _label_row(label_text: String, control: Control) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 6)
	var l := Label.new()
	l.text = label_text
	l.custom_minimum_size = Vector2(90, 0)
	row.add_child(l)
	row.add_child(control)
	return row

func _build_preview(root: VBoxContainer) -> void:
	_preview_label = Label.new()
	_preview_label.add_theme_color_override(&"font_color", UITheme.ACCENT_INFO)
	_preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_preview_label)

	_warning_label = Label.new()
	_warning_label.add_theme_color_override(&"font_color", UITheme.ACCENT_DANGER)
	_warning_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_warning_label)

# ---- populate --------------------------------------------------------------

func _populate_type_dropdown() -> void:
	_type_dropdown.clear()
	for type_id in TYPE_ORDER:
		var spec: ProductTypeSpec = ProductSystem.get_type_spec(type_id)
		if spec == null:
			continue
		var locked_reason: StringName = _lock_reason_for_type(type_id, spec)
		var label_text: String = tr(ProductSystem.TYPE_LABEL_KEY.get(
				type_id, String(spec.display_name)))
		if locked_reason != &"":
			label_text += "  " + tr(String(LOCK_REASONS.get(locked_reason, "PRODUCT_LOCKED_SHORT")))
			# D-11: 解锁所需阈值 + 玩家当前对应能力的最高值, 直接告诉玩家差多少。
			label_text += " · " + _threshold_vs_player_summary(spec)
		_type_dropdown.add_item(label_text)
		var idx: int = _type_dropdown.item_count - 1
		_type_dropdown.set_item_metadata(idx, type_id)
		if locked_reason != &"":
			_type_dropdown.set_item_disabled(idx, true)
	# 默认选第一个未锁的; 都锁了就选 0.
	for i in range(_type_dropdown.item_count):
		if not _type_dropdown.is_item_disabled(i):
			_type_dropdown.select(i)
			return
	if _type_dropdown.item_count > 0:
		_type_dropdown.select(0)

# 返回类型当前是否被锁; 锁则给个 reason code, 否则 &"".
func _lock_reason_for_type(type_id: StringName, spec: ProductTypeSpec) -> StringName:
	# 应用节点 (tool_use 等) 未解.
	if spec.application_node_required != &"":
		var u: Dictionary = CommandBus.send(&"tech.is_unlocked", {
			tree = &"application", node_id = spec.application_node_required})
		if not bool(u.get(&"unlocked", false)):
			return &"application_node_locked"
	# api 类型: 至少要有一个还没开 api 的 published 模型.
	if type_id == &"api":
		for m in GameState.models:
			if m.status != &"published":
				continue
			var has_api: bool = false
			for prod in GameState.products:
				if prod.type == &"api" and prod.bound_model_id == m.id:
					has_api = true
					break
			if not has_api:
				return &""
		return &"no_uncovered_model"
	# 其他: 至少要有一个 published 模型满足所有 unlock_thresholds.
	for m in GameState.models:
		if m.status != &"published":
			continue
		if _model_meets_spec(m, spec):
			return &""
	return &"no_matching_model"

func _model_meets_spec(m, spec: ProductTypeSpec) -> bool:
	for axis in spec.unlock_thresholds.keys():
		if float(m.capability.get(axis, 0.0)) < float(spec.unlock_thresholds[axis]):
			return false
	return true

func _thresholds_summary(spec: ProductTypeSpec) -> String:
	var parts: Array = []
	for axis in spec.unlock_thresholds.keys():
		parts.append("%s≥%.0f" % [String(axis), float(spec.unlock_thresholds[axis])])
	if spec.application_node_required != &"":
		parts.append(String(spec.application_node_required))
	return ",".join(parts) if not parts.is_empty() else tr("VALUE_NONE")

# D-11: 对每个阈值轴, 显示 "axis≥需求 (当前 X)" — X 取所有 published 模型该
# 轴能力的最高值; 没 published 模型时 X = 0。让玩家瞬间看到差多少。
func _threshold_vs_player_summary(spec: ProductTypeSpec) -> String:
	var parts: Array = []
	for axis in spec.unlock_thresholds.keys():
		var need: float = float(spec.unlock_thresholds[axis])
		var best: float = 0.0
		for m in GameState.models:
			if m.status != &"published":
				continue
			best = maxf(best, float(m.capability.get(axis, 0.0)))
		parts.append(tr("PRODUCT_THRESH") % [String(axis), need, best])
	if spec.application_node_required != &"":
		parts.append(tr("PRODUCT_NEED_RESEARCH") % String(spec.application_node_required))
	return ", ".join(parts) if not parts.is_empty() else tr("VALUE_NONE")

func _populate_model_dropdown() -> void:
	_model_dropdown.clear()
	var type_id: StringName = _selected_type_id()
	var spec: ProductTypeSpec = ProductSystem.get_type_spec(type_id) if type_id != &"" else null
	if spec == null:
		return
	for m in GameState.models:
		if m.status != &"published":
			continue
		if type_id == &"api":
			# api 跳过 capability 阈值, 但筛掉已有 api 产品的 model.
			var has_api: bool = false
			for prod in GameState.products:
				if prod.type == &"api" and prod.bound_model_id == m.id:
					has_api = true
					break
			# 编辑模式下当前 product 的 bound_model 例外: 保留它.
			var cur: Product = _editing_product()
			if has_api and (cur == null or cur.bound_model_id != m.id):
				continue
		else:
			if not _model_meets_spec(m, spec):
				continue
		var cap_summary: String = _cap_summary(m)
		var lbl: String = "%s · %s" % [
			m.display_name if m.display_name != "" else String(m.id), cap_summary]
		_model_dropdown.add_item(lbl)
		_model_dropdown.set_item_metadata(_model_dropdown.item_count - 1, m.id)
	if _model_dropdown.item_count > 0:
		_model_dropdown.select(0)

func _cap_summary(m) -> String:
	var parts: Array = []
	for axis in [&"general", &"code", &"reasoning", &"multimodal", &"agent"]:
		var v: float = float(m.capability.get(axis, 0.0))
		if v >= 1.0:
			parts.append("%s %.0f" % [tr("CAP_" + String(axis).to_upper()), v])
	return ",".join(parts) if not parts.is_empty() else tr("VALUE_UNEVALUATED")

## Per 招聘系统设计 §5.4: product 强制 chief_engineer (ProductSystem 自校).
## 下拉只列匹配 specialty 的 idle (或当前已绑定) lead, 含创始人。Lead 仍是可选 — 第 0 项是 "(无)"。
func _populate_lead_dropdown() -> void:
	_lead_dropdown.clear()
	_lead_dropdown.add_item(tr("MSG_NONE"))
	_lead_dropdown.set_item_metadata(0, &"")
	for l in GameState.leads:
		if not HiringSystem.lead_matches_specialty(l, &"chief_engineer"):
			continue
		# 在编辑模式下, 把当前已绑定的 lead 允许选 (即使 assigned_to_product_id 非空).
		var cur := _editing_product()
		var is_current_lead: bool = (cur != null and cur.lead_id == l.id)
		if l.assigned_to_product_id != &"" and not is_current_lead:
			continue
		var suffix: String = tr("CAMPAIGN_FOUNDER_SUFFIX") if l.is_player_scientist else ""
		var lbl: String = tr("PRODUCT_LEAD_ITEM") % [NameRomanizer.localized(l.display_name), String(l.level), l.ability, suffix]
		_lead_dropdown.add_item(lbl)
		_lead_dropdown.set_item_metadata(_lead_dropdown.item_count - 1, l.id)
	_lead_dropdown.select(0)

# ---- mode-driven visibility ------------------------------------------------

func _on_type_changed() -> void:
	var type_id: StringName = _selected_type_id()
	# api: 隐藏 lead/staff/price/auto_track 行. lead 仍可选 (给 throughput bonus).
	var is_api: bool = type_id == &"api"
	_staff_row.visible = not is_api
	_price_row.visible = not is_api
	_auto_track_row.visible = not is_api
	# D-12: create 模式下, 切类型时把订阅价默认到 spec.subscription_price_guidance,
	# 避免玩家点 "新建产品" 拿到 $99 而落在惩罚区。edit 模式不动 (已被 setup_edit 填回)。
	if _mode == &"create" and not is_api:
		var spec: ProductTypeSpec = ProductSystem.get_type_spec(type_id) if type_id != &"" else null
		if spec != null and int(spec.subscription_price_guidance) > 0:
			_price_spinbox.value = float(spec.subscription_price_guidance)
	# api 也支持 lead, 所以 _lead_row 仍可见.
	_populate_model_dropdown()
	_refresh_preview()

# ---- preview ---------------------------------------------------------------

func _refresh_preview() -> void:
	var type_id: StringName = _selected_type_id()
	if type_id == &"":
		_preview_label.text = tr("PRODUCT_SELECT_TYPE")
		_warning_label.text = ""
		get_ok_button().disabled = true
		return
	var spec: ProductTypeSpec = ProductSystem.get_type_spec(type_id)
	var model_id: StringName = _selected_model_id()
	if model_id == &"":
		_preview_label.text = tr("PRODUCT_NO_MODEL") % _thresholds_summary(spec)
		_warning_label.text = ""
		get_ok_button().disabled = true
		return
	var m = _find_model(model_id)
	if m == null:
		_preview_label.text = tr("PRODUCT_MODEL_MISSING")
		get_ok_button().disabled = true
		return
	var preview_lines: Array = []
	if type_id == &"api":
		preview_lines.append(tr("PRODUCT_TYPE_API"))
		# v7 PR-F: 估算 demand 基于该 model 的总榜 rank, 不再读 fame.
		var rank: int = MarketSystem.get_rank_for_model(m.id, &"total")
		var rank_label: String = "#%d" % rank if rank > 0 else tr("PRODUCT_UNRANKED")
		preview_lines.append(tr("PRODUCT_DEMAND_API") % rank_label)
	else:
		var per_user_month: int = int(spec.tokens_per_user_per_month) if spec != null else 0
		preview_lines.append(tr("PRODUCT_TYPE_SUB") % [
			tr(spec.display_name), _format_tps(per_user_month)])
		var price: int = int(_price_spinbox.value)
		preview_lines.append(tr("PRODUCT_REVENUE_EST") % [
			0, price, _money(0)])
		var ml: int = int(_ml_eng_spinbox.value)
		# Quality 公式简化估算: model_factor × (1 + ml × 0.05) × (lead bonus if any).
		var cap_sum: float = 0.0
		for v in m.capability.values():
			cap_sum += float(v)
		var q: float = clampf(cap_sum / 100.0 * (1.0 + 0.05 * ml), 0.0, 1.5)
		preview_lines.append(tr("PRODUCT_QUALITY_EST") % [
			q, cap_sum, ml])
	_preview_label.text = "\n".join(preview_lines)
	_warning_label.text = ""
	get_ok_button().disabled = false

# ---- confirm ---------------------------------------------------------------

func _on_confirm_pressed() -> void:
	if _mode == &"edit":
		_confirm_edit()
	else:
		_confirm_create()

func _confirm_create() -> void:
	var type_id: StringName = _selected_type_id()
	var model_id: StringName = _selected_model_id()
	if type_id == &"" or model_id == &"":
		return
	var payload: Dictionary = {
		type = type_id,
		bound_model_id = model_id,
	}
	var name_str: String = _name_edit.text.strip_edges()
	if name_str != "":
		payload[&"display_name"] = name_str
	if type_id != &"api":
		payload[&"subscription_price"] = int(_price_spinbox.value)
		payload[&"auto_track_latest"] = _auto_track_check.button_pressed
		var ml: int = int(_ml_eng_spinbox.value)
		if ml > 0:
			payload[&"staff"] = {&"ml_eng": ml}
	var lead_id: StringName = _selected_lead_id()
	if lead_id != &"":
		payload[&"lead_id"] = lead_id
	var r: Dictionary = CommandBus.send(&"product.create", payload)
	if not r.ok:
		_warning_label.text = tr("PRODUCT_CREATE_FAILED") % String(r.get(&"error", &"unknown"))
		Log.warn(&"ui", "NewProductDialog create failed", {error = r.get(&"error")})
		return
	product_created.emit(r.product_id)
	hide()

func _confirm_edit() -> void:
	var p = _editing_product()
	if p == null:
		_warning_label.text = tr("PRODUCT_GONE")
		return
	var fields: Dictionary = {}
	var new_name: String = _name_edit.text.strip_edges()
	if new_name != "" and new_name != p.display_name:
		fields[&"display_name"] = new_name
	var new_model: StringName = _selected_model_id()
	if new_model != &"" and new_model != p.bound_model_id:
		fields[&"bound_model_id"] = new_model
	if p.type != &"api":
		var new_price: int = int(_price_spinbox.value)
		if new_price != p.subscription_price:
			fields[&"price"] = new_price
		var new_auto: bool = _auto_track_check.button_pressed
		if new_auto != p.auto_track_latest:
			fields[&"auto_track_latest"] = new_auto
		var ml: int = int(_ml_eng_spinbox.value)
		var old_ml: int = int(p.assigned_staff.get(&"ml_eng", 0))
		if ml != old_ml:
			var new_staff: Dictionary = {}
			if ml > 0:
				new_staff[&"ml_eng"] = ml
			fields[&"staff"] = new_staff
	# Lead: 走单独的 unassign/assign 命令对, 因为 product.update 没暴露 lead 字段.
	var target_lead: StringName = _selected_lead_id()
	if target_lead != p.lead_id:
		if p.lead_id != &"":
			var ur: Dictionary = CommandBus.send(&"hiring.unassign_lead", {lead_id = p.lead_id})
			if not ur.ok:
				_warning_label.text = tr("PRODUCT_UNBIND_FAILED") % String(ur.get(&"error", &""))
				return
			p.lead_id = &""
		if target_lead != &"":
			var ar: Dictionary = CommandBus.send(&"hiring.assign_lead", {
				lead_id = target_lead, product_id = p.id})
			if not ar.ok:
				_warning_label.text = tr("PRODUCT_BIND_FAILED") % String(ar.get(&"error", &""))
				return
			p.lead_id = target_lead
		# product_updated 信号让 UI 刷新.
		EventBus.product_updated.emit(p.id, [&"lead_id"])
	if not fields.is_empty():
		var r: Dictionary = CommandBus.send(&"product.update", {
			product_id = _edit_product_id, fields = fields})
		if not r.ok:
			_warning_label.text = tr("PRODUCT_UPDATE_FAILED") % String(r.get(&"error", &"unknown"))
			Log.warn(&"ui", "NewProductDialog edit failed", {error = r.get(&"error")})
			return
	product_edited.emit(_edit_product_id)
	hide()

# ---- load existing product into form ---------------------------------------

func _load_product_into_form() -> void:
	var p = _editing_product()
	if p == null:
		return
	# 选中 type.
	for i in range(_type_dropdown.item_count):
		if _type_dropdown.get_item_metadata(i) == p.type:
			_type_dropdown.select(i)
			break
	_on_type_changed()  # 刷新 model dropdown 等
	_name_edit.text = p.display_name
	# 选中当前 model (即使它已经"被绑死").
	for i in range(_model_dropdown.item_count):
		if _model_dropdown.get_item_metadata(i) == p.bound_model_id:
			_model_dropdown.select(i)
			break
	# Lead.
	for i in range(_lead_dropdown.item_count):
		if _lead_dropdown.get_item_metadata(i) == p.lead_id:
			_lead_dropdown.select(i)
			break
	# Staff / price.
	if p.type != &"api":
		_ml_eng_spinbox.value = int(p.assigned_staff.get(&"ml_eng", 0))
		_price_spinbox.value = int(p.subscription_price)
		_auto_track_check.button_pressed = bool(p.auto_track_latest)
	_refresh_preview()

# ---- helpers ---------------------------------------------------------------

func _selected_type_id() -> StringName:
	if _type_dropdown.selected < 0:
		return &""
	return _type_dropdown.get_item_metadata(_type_dropdown.selected)

func _selected_model_id() -> StringName:
	if _model_dropdown.selected < 0:
		return &""
	return _model_dropdown.get_item_metadata(_model_dropdown.selected)

func _selected_lead_id() -> StringName:
	if _lead_dropdown.selected < 0:
		return &""
	return _lead_dropdown.get_item_metadata(_lead_dropdown.selected)

func _editing_product() -> Product:
	if _mode != &"edit" or _edit_product_id == &"":
		return null
	return ProductSystem.find_product(_edit_product_id)

func _find_model(model_id: StringName) -> Model:
	for m in GameState.models:
		if m.id == model_id:
			return m
	return null

func _format_tps(tokens_per_month: int) -> String:
	# 走 UITheme 统一格式化, 自动升档 k → M → G (与营收 / 顶栏一致)。
	return UITheme.format_tps(float(tokens_per_month) / float(SECONDS_PER_MONTH))

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
