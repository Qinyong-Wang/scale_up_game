extends ConfirmationDialog

## NewDatacenterDialog — 新建数据中心 (云租用 / 自建 + 满配 GPU).
## Per design/基础设施系统设计.md §1.4 / §5.2.
##
## 玩家只有两种模式: 云租用 (cloud) 与 自建 (owned)。原「立即租用」(rented)
## 因与云租用体验难分已下线 (见 design/基础设施系统设计.md §1.4)。
##
## 流程:
##   1. 选模式 (云租用 / 自建) + 规模档位 + 供电方式 + GPU 型号.
##   2. 预览一次性费用 (建设费 + 满配 GPU) + 周运营费.
##   3. 确认 → create_cloud_dc / build_facility.
##      自建模式只触发 build_facility; GPU 完工后自动满配.

signal datacenter_created(dc_id: StringName)


const POWER_ORDER: Array[StringName] = [&"grid", &"green"]

var _mode_build: CheckBox
var _mode_cloud: CheckBox
var _facility_dropdown: OptionButton
var _power_dropdown: OptionButton
var _gpu_dropdown: OptionButton
var _facility_row: Control
var _facility_preview: TextureRect          # 选中档位的建筑预览图 (自建模式可见)
var _facility_preview_row: Control
var _power_row: Control
var _cloud_count_spinbox: SpinBox
var _cloud_count_row: Control

var _upfront_label: Label
var _weekly_label: Label
var _warning_label: Label

func _ready() -> void:
	title = tr("DC_TITLE")
	min_size = Vector2i(840, 660)
	max_size = Vector2i(1140, 680)
	dialog_hide_on_ok = false
	get_ok_button().text = tr("DC_CONFIRM_CLOUD")
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

	# 云租用是默认模式 — 同步行可见性 (隐藏规模/供电, 显示 GPU 数量).
	_on_mode_changed()

	Log.info(&"ui", "NewDatacenterDialog ready")

# ---- public ----------------------------------------------------------------

## 弹出前调用以刷新下拉列表内容 (读当前 GameState).
func refresh() -> void:
	_populate_facility_dropdown()
	_populate_power_dropdown()
	_populate_gpu_dropdown()
	_refresh_preview()

# ---- form ------------------------------------------------------------------

func _build_form(root: VBoxContainer) -> void:
	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override(&"separation", 16)
	var mode_lbl := Label.new()
	mode_lbl.text = tr("DC_MODE")
	mode_lbl.custom_minimum_size = Vector2(70, 0)
	mode_row.add_child(mode_lbl)
	# 两种模式各加一句括号说明, 避免玩家分不清差别。
	var mode_group := ButtonGroup.new()
	_mode_cloud = CheckBox.new()
	_mode_cloud.text = tr("DC_MODE_CLOUD")
	_mode_cloud.button_group = mode_group
	_mode_cloud.button_pressed = true
	_mode_cloud.toggled.connect(func(_p): _on_mode_changed())
	mode_row.add_child(_mode_cloud)
	_mode_build = CheckBox.new()
	_mode_build.text = tr("DC_MODE_BUILD")
	_mode_build.button_group = mode_group
	_mode_build.toggled.connect(func(_p): _on_mode_changed())
	mode_row.add_child(_mode_build)
	root.add_child(mode_row)

	_facility_dropdown = OptionButton.new()
	_facility_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_facility_dropdown.item_selected.connect(func(_i): _refresh_preview())
	_facility_row = _label_row(tr("FIELD_SIZE"), _facility_dropdown)
	root.add_child(_facility_row)

	# 选中档位的建筑预览图; 空标签占位让图与上方下拉左对齐。
	_facility_preview = TextureRect.new()
	_facility_preview.custom_minimum_size = Vector2(96, 96)
	_facility_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_facility_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_facility_preview_row = _label_row("", _facility_preview)
	root.add_child(_facility_preview_row)

	_power_dropdown = OptionButton.new()
	_power_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_power_dropdown.item_selected.connect(func(_i): _refresh_preview())
	_power_row = _label_row(tr("DC_POWER"), _power_dropdown)
	root.add_child(_power_row)

	_gpu_dropdown = OptionButton.new()
	_gpu_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_gpu_dropdown.item_selected.connect(func(_i): _refresh_preview())
	root.add_child(_label_row(tr("DC_GPU_MODEL"), _gpu_dropdown))

	_cloud_count_spinbox = SpinBox.new()
	_cloud_count_spinbox.min_value = 1
	_cloud_count_spinbox.max_value = 3000
	_cloud_count_spinbox.value = 8
	_cloud_count_spinbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cloud_count_spinbox.value_changed.connect(func(_v): _refresh_preview())
	_cloud_count_row = _label_row(tr("DC_GPU_COUNT"), _cloud_count_spinbox)
	_cloud_count_row.visible = false
	root.add_child(_cloud_count_row)

func _label_row(label_text: String, control: Control) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 6)
	var l := Label.new()
	l.text = label_text
	l.custom_minimum_size = Vector2(70, 0)
	row.add_child(l)
	row.add_child(control)
	return row

func _build_preview(root: VBoxContainer) -> void:
	_upfront_label = Label.new()
	_upfront_label.add_theme_color_override(&"font_color", UITheme.ACCENT_INFO)
	_upfront_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_upfront_label)

	_weekly_label = Label.new()
	_weekly_label.add_theme_color_override(&"font_color", UITheme.ACCENT_INFO)
	_weekly_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_weekly_label)

	_warning_label = Label.new()
	_warning_label.add_theme_color_override(&"font_color", UITheme.ACCENT_DANGER)
	_warning_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_warning_label)

# ---- populate --------------------------------------------------------------

func _populate_facility_dropdown() -> void:
	_facility_dropdown.clear()
	for spec_id in _facility_ids_by_tier():
		var spec: FacilitySpec = _load_facility_spec(spec_id)
		if spec == null:
			continue
		var locked: bool = GameState.cash < spec.unlock_cash_required
		var lbl: String = tr("DC_FACILITY_ITEM") % [tr(spec.display_name), spec.max_gpu_count]
		if locked:
			lbl += tr("DC_FACILITY_UNLOCK") % _money(spec.unlock_cash_required)
		_facility_dropdown.add_item(lbl)
		_facility_dropdown.set_item_metadata(_facility_dropdown.item_count - 1, spec_id)
		if locked:
			_facility_dropdown.set_item_disabled(_facility_dropdown.item_count - 1, true)
	if _facility_dropdown.item_count > 0:
		_facility_dropdown.select(0)

func _populate_power_dropdown() -> void:
	_power_dropdown.clear()
	for power_id in POWER_ORDER:
		var spec: PowerSupplySpec = _load_power_spec(power_id)
		if spec == null:
			continue
		var lbl: String = tr("DC_POWER_ITEM") % [
			tr(spec.display_name), _money(spec.weekly_cost_per_card)]
		# 绿色能源额外标出一次性安装 + 储能费 (按卡计)。
		if spec.install_cost_per_card > 0:
			lbl += tr("DC_POWER_INSTALL") % _money(spec.install_cost_per_card)
		_power_dropdown.add_item(lbl)
		_power_dropdown.set_item_metadata(_power_dropdown.item_count - 1, power_id)
		var ptex: Texture2D = IconRegistry.get_icon(&"power", power_id)
		if ptex != null:
			_power_dropdown.set_item_icon(_power_dropdown.item_count - 1, ptex)
	if _power_dropdown.item_count > 0:
		_power_dropdown.select(0)

func _populate_gpu_dropdown() -> void:
	# 重填会清空选择, 先记住当前 GPU 以便填完恢复 (模式切换时复用)。
	var prev: StringName = _selected_gpu_id()
	_gpu_dropdown.clear()
	var is_cloud: bool = _mode_cloud != null and _mode_cloud.button_pressed
	for gpu_id in _released_gpu_ids():
		var gpu: GPUSpec = _load_gpu_spec(gpu_id)
		if gpu == null:
			continue
		# 价格随模式切换: 云租用看单卡周租价, 自建看单卡买断价 —
		# 否则玩家在云租用模式下看到买断价会误判成本。
		var price_part: String
		if is_cloud:
			price_part = tr("DC_GPU_RENT") % _money(gpu.rent_weekly_cost)
		else:
			price_part = tr("DC_GPU_BUY") % _money(gpu.purchase_price)
		# v3: 显示训练 + 推理算力 (单卡, batched 推理 + KV cache 折损后);
		# 实际 t/s 容量在基础设施 tab 选模型部署时按模型大小现算 (preview_deploy_capacity).
		# 单位走 UITheme.format_compute, 大卡自动升档到 PFLOPs。
		var lbl: String = tr("DC_GPU_ITEM") % [
			tr(gpu.display_name), price_part,
			UITheme.format_compute(gpu.per_card_tflops),
			UITheme.format_compute(gpu.per_card_inference_tflops)]
		# 生态训练惩罚 < 1 的品牌 (maple / bamboo) 标出, 避免玩家只看纸面算力。
		if gpu.ecosystem_score < 1.0:
			lbl += tr("DC_GPU_ECO") % gpu.ecosystem_score
		_gpu_dropdown.add_item(lbl)
		_gpu_dropdown.set_item_metadata(_gpu_dropdown.item_count - 1, gpu_id)
		var gtex: Texture2D = IconRegistry.gpu_icon(gpu_id)   # 按植物族取图
		if gtex != null:
			_gpu_dropdown.set_item_icon(_gpu_dropdown.item_count - 1, gtex)
	_select_gpu_or_first(prev)

func _selected_gpu_id() -> StringName:
	if _gpu_dropdown == null or _gpu_dropdown.selected < 0:
		return &""
	return StringName(_gpu_dropdown.get_item_metadata(_gpu_dropdown.selected))

func _select_gpu_or_first(gpu_id: StringName) -> void:
	if _gpu_dropdown.item_count == 0:
		return
	for i in _gpu_dropdown.item_count:
		if StringName(_gpu_dropdown.get_item_metadata(i)) == gpu_id:
			_gpu_dropdown.select(i)
			return
	_gpu_dropdown.select(0)

# ---- preview ---------------------------------------------------------------

func _on_mode_changed() -> void:
	var is_cloud: bool = _mode_cloud != null and _mode_cloud.button_pressed
	if is_cloud:
		get_ok_button().text = tr("DC_CONFIRM_CLOUD")
	else:
		get_ok_button().text = tr("DC_CONFIRM_BUILD")
	if _facility_row != null:
		_facility_row.visible = not is_cloud
	if _facility_preview_row != null:
		_facility_preview_row.visible = not is_cloud
	if _power_row != null:
		_power_row.visible = not is_cloud
	if _cloud_count_row != null:
		_cloud_count_row.visible = is_cloud
	# GPU 下拉里的价格随模式变 (周租价 / 买断价), 重填一次。
	if _gpu_dropdown != null and _gpu_dropdown.item_count > 0:
		_populate_gpu_dropdown()
	_refresh_preview()

func _refresh_preview() -> void:
	# 建筑预览图只取决于选中档位, 放最前面 — 不受下面 GPU/模式早退影响。
	if _facility_preview != null:
		var fspec: FacilitySpec = _selected_facility_spec()
		_facility_preview.texture = fspec.load_icon() if fspec != null else null

	var gpu: GPUSpec = _selected_gpu_spec()
	var is_cloud: bool = _mode_cloud != null and _mode_cloud.button_pressed

	if gpu == null:
		_upfront_label.text = tr("DC_SELECT_GPU")
		_weekly_label.text = ""
		_warning_label.text = ""
		get_ok_button().disabled = true
		return

	if is_cloud:
		var count: int = int(_cloud_count_spinbox.value)
		var weekly_total: int = gpu.rent_weekly_cost * count
		_upfront_label.text = tr("DC_UPFRONT_NONE")
		_weekly_label.text = tr("DC_WEEKLY_CLOUD") % [
			_money(gpu.rent_weekly_cost), count, _money(weekly_total)]
		_warning_label.text = ""
		get_ok_button().disabled = false
		return

	var spec: FacilitySpec = _selected_facility_spec()
	var pwr: PowerSupplySpec = _selected_power_spec()

	if spec == null or pwr == null:
		_upfront_label.text = tr("DC_SELECT_ALL")
		_weekly_label.text = ""
		_warning_label.text = ""
		get_ok_button().disabled = true
		return

	# Non-cloud mode is always self-build (owned).
	var gpu_total: int = spec.max_gpu_count * gpu.purchase_price
	var facility_upfront: int = int(spec.land_build_cost * (1.0 + pwr.build_cost_modifier))
	# v11: 绿色能源一次性安装 + 储能费, 按机房满配卡数计。
	var power_install: int = pwr.install_cost_per_card * spec.max_gpu_count
	var total_upfront: int = facility_upfront + gpu_total + power_install
	var upfront_text: String = tr("DC_UPFRONT_BUILD") % [
		_money(facility_upfront), spec.max_gpu_count, _money(gpu_total)]
	if power_install > 0:
		upfront_text += tr("DC_UPFRONT_GREEN") % _money(power_install)
	upfront_text += tr("DC_UPFRONT_DONE") % [_money(total_upfront), spec.build_weeks]
	_upfront_label.text = upfront_text

	var per_card_weekly: int = gpu.maintenance_per_week + pwr.weekly_cost_per_card
	# Self-built (owned) facilities pay land_weekly_cost.
	var fac_weekly: int = spec.land_weekly_cost
	var weekly_total_op: int = fac_weekly + per_card_weekly * spec.max_gpu_count
	_weekly_label.text = tr("DC_WEEKLY_BUILD") % [
		_money(fac_weekly), _money(gpu.maintenance_per_week),
		_money(pwr.weekly_cost_per_card), spec.max_gpu_count, _money(weekly_total_op)]

	var warnings: Array = []
	if GameState.cash < spec.unlock_cash_required:
		warnings.append(tr("DC_WARN_THRESHOLD") % [
			_money(spec.unlock_cash_required), _money(GameState.cash)])
	# Self-build charges facility build + GPU + 绿色能源安装 upfront.
	if total_upfront > GameState.cash:
		warnings.append(tr("DC_WARN_CASH") % [_money(total_upfront), _money(GameState.cash)])

	if warnings.is_empty():
		_warning_label.text = ""
		get_ok_button().disabled = false
	else:
		_warning_label.text = tr("WARN_PREFIX") + " · ".join(warnings)
		get_ok_button().disabled = true

# ---- confirm ---------------------------------------------------------------

func _on_confirm_pressed() -> void:
	var gpu: GPUSpec = _selected_gpu_spec()
	if gpu == null:
		return
	var is_cloud: bool = _mode_cloud.button_pressed
	if is_cloud:
		_confirm_cloud(gpu)
		return
	var spec: FacilitySpec = _selected_facility_spec()
	var pwr: PowerSupplySpec = _selected_power_spec()
	if spec == null or pwr == null:
		return
	_confirm_build(spec, pwr, gpu)

func _confirm_build(spec: FacilitySpec, pwr: PowerSupplySpec, gpu: GPUSpec) -> void:
	var r: Dictionary = CommandBus.send(&"infra.build_facility", {
		facility_spec_id = spec.id, power_supply_id = pwr.id, gpu_id = gpu.id})
	if not r.ok:
		_warning_label.text = tr("DC_BUILD_FAILED") % String(r.get(&"error", &"unknown"))
		Log.warn(&"ui", "NewDatacenterDialog build_facility failed", {error = r.get(&"error")})
		return

	Log.info(&"ui", "NewDatacenterDialog build started",
		{construction_id = r.get(&"construction_id"), gpu_id = gpu.id, count = spec.max_gpu_count})
	datacenter_created.emit(StringName(r.get(&"construction_id", &"")))
	hide()

func _confirm_cloud(gpu: GPUSpec) -> void:
	var count: int = int(_cloud_count_spinbox.value)
	var r: Dictionary = CommandBus.send(&"infra.create_cloud_dc", {
		gpu_id = gpu.id, count = count})
	if not r.ok:
		_warning_label.text = tr("DC_CLOUD_FAILED") % String(r.get(&"error", &"unknown"))
		Log.warn(&"ui", "NewDatacenterDialog create_cloud_dc failed",
			{error = r.get(&"error")})
		return
	Log.info(&"ui", "NewDatacenterDialog cloud_dc created",
		{dc_id = r.dc_id, gpu_id = gpu.id, count = count})
	datacenter_created.emit(StringName(r.dc_id))
	hide()

# ---- helpers ---------------------------------------------------------------

func _selected_facility_spec() -> FacilitySpec:
	if _facility_dropdown.selected < 0:
		return null
	var spec_id: StringName = _facility_dropdown.get_item_metadata(_facility_dropdown.selected)
	return _load_facility_spec(spec_id)

func _selected_power_spec() -> PowerSupplySpec:
	if _power_dropdown.selected < 0:
		return null
	var power_id: StringName = _power_dropdown.get_item_metadata(_power_dropdown.selected)
	return _load_power_spec(power_id)

func _selected_gpu_spec() -> GPUSpec:
	if _gpu_dropdown.selected < 0:
		return null
	var gpu_id: StringName = _gpu_dropdown.get_item_metadata(_gpu_dropdown.selected)
	return _load_gpu_spec(gpu_id)

func _facility_ids_by_tier() -> Array:
	var ids: Array = []
	for id in InfraSystem.FACILITY_SPECS.keys():
		ids.append(StringName(id))
	ids.sort_custom(func(a, b):
		var sa: FacilitySpec = _load_facility_spec(a)
		var sb: FacilitySpec = _load_facility_spec(b)
		var ta: int = sa.tier_index if sa != null else 999
		var tb: int = sb.tier_index if sb != null else 999
		return ta < tb)
	return ids

func _released_gpu_ids() -> Array:
	var ids: Array = []
	for id in InfraSystem.GPU_SPECS.keys():
		var gpu: GPUSpec = _load_gpu_spec(StringName(id))
		if gpu != null and gpu.release_turn <= GameState.turn:
			ids.append(StringName(id))
	ids.sort_custom(func(a, b):
		var ga: GPUSpec = _load_gpu_spec(a)
		var gb: GPUSpec = _load_gpu_spec(b)
		var ra: int = ga.release_turn if ga != null else 99999
		var rb: int = gb.release_turn if gb != null else 99999
		if ra == rb:
			return String(a) < String(b)
		return ra < rb)
	return ids

func _load_facility_spec(spec_id: StringName) -> FacilitySpec:
	var path: String = InfraSystem.FACILITY_SPECS.get(spec_id, "")
	if path == "":
		return null
	var res := load(path)
	if res is FacilitySpec:
		return res
	return null

func _load_gpu_spec(gpu_id: StringName) -> GPUSpec:
	var path: String = InfraSystem.GPU_SPECS.get(gpu_id, "")
	if path == "":
		return null
	var res := load(path)
	if res is GPUSpec:
		return res
	return null

func _load_power_spec(power_id: StringName) -> PowerSupplySpec:
	var path: String = InfraSystem.POWER_SPECS.get(power_id, "")
	if path == "":
		return null
	var res := load(path)
	if res is PowerSupplySpec:
		return res
	return null

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
