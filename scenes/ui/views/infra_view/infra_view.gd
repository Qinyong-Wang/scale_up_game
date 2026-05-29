extends VBoxContainer

## InfraView — 基建 tab 试点视图 (§10 step 6 第二批扩展)。
##
## 布局:
##   SectionHeader  数据中心 (N)         [+ 新建数据中心...]
##   FilterBar      [全部 (N)][租用 (N)][自建 (N)]   (ownership 筛选, 无搜索框)
##   FilterBar      [全部 (N)][≤72 卡 (N)][≤8k 卡 (N)][>8k 卡 (N)]  (卡数量筛选)
##   FilterBar      [全部 (N)][空闲 (N)][训练中 (N)][推理中 (N)]    (运行状态筛选)
##   HFlowContainer of DC Cards (空 / 无匹配时显示提示)
##
## ownership / 卡数量 / 运行状态三条筛选条**取交集** (AND)。
##   SectionHeader  自建中 (仅有队列时显示)
##   VBox of construction rows
##
## 信号:
##   new_dc_pressed
##   dc_action(dc_id, action_id)   # deploy / terminate / undeploy

signal new_dc_pressed
signal dc_action(dc_id: StringName, action_id: StringName)

const SectionHeaderScene := preload("res://scenes/ui/components/section_header/section_header.tscn")
const FilterBarScene := preload("res://scenes/ui/components/filter_bar/filter_bar.tscn")
const CardScene := preload("res://scenes/ui/components/card/card.tscn")
const AvatarScene := preload("res://scenes/ui/components/avatar/avatar.tscn")
const BadgeScene := preload("res://scenes/ui/components/badge/badge.tscn")
const DcCard := preload("res://scenes/ui/views/infra_view/dc_card.gd")

# ownership 筛选 pills — 第一个 "全部" 互斥其余 (FilterBar 语义)。
# pill label 为 i18n key (const 不能调 tr); set_pills 前用 _localize_options() 翻。
const _OWNERSHIP_PILLS: Array = [
	{"id": &"all",    "label": "FILTER_ALL"},
	{"id": &"rented", "label": "INFRA_OWN_RENTED"},
	{"id": &"owned",  "label": "INFRA_OWN_OWNED"},
]

# 卡数量筛选 pills — 按已装 GPU 卡数分三档 (阈值见 _size_bucket_of)。
const _SIZE_PILLS: Array = [
	{"id": &"all",   "label": "FILTER_ALL"},
	{"id": &"small", "label": "INFRA_SIZE_SMALL"},
	{"id": &"mid",   "label": "INFRA_SIZE_MID"},
	{"id": &"large", "label": "INFRA_SIZE_LARGE"},
]

# 运行状态筛选 pills — 按 Datacenter.status 三态 (idle / training / serving)。
const _STATUS_PILLS: Array = [
	{"id": &"all",      "label": "FILTER_ALL"},
	{"id": &"idle",     "label": "INFRA_STATUS_IDLE"},
	{"id": &"training", "label": "INFRA_STATUS_TRAINING"},
	{"id": &"serving",  "label": "INFRA_STATUS_SERVING"},
]

## const pill 表里的 label 是 i18n key, 渲染前翻成当前 locale 文案。
func _localize_options(opts: Array) -> Array:
	var out: Array = []
	for o in opts:
		out.append({"id": o.id, "label": tr(String(o.label))})
	return out

var _section: Control                  # SectionHeader for 数据中心
var _filter_bar: Control                # FilterBar — ownership 筛选
var _size_filter_bar: Control           # FilterBar — 卡数量筛选
var _status_filter_bar: Control         # FilterBar — 运行状态筛选
var _dc_grid: HFlowContainer
var _empty_label: Label
# 自建队列 section + rows 按 refresh 状态动态进出树, 见 _refresh_construction()。
var _construction_section: Control
var _construction_rows: HFlowContainer

var _cards_by_id: Dictionary = {}
var _construction_cards_by_id: Dictionary = {}
var _construction_avatars_by_id: Dictionary = {}
var _construction_progress_by_id: Dictionary = {}
var _construction_fields_by_id: Dictionary = {}
var _icon_cache: Dictionary = {}        # icon_path -> Texture2D (避免每次 refresh 重 load)
var _datacenters: Array = []            # 当前 refresh 的全量 DC 列表 (未过滤)
var _filter_state: Dictionary = {}        # 上次 ownership FilterBar 状态
var _size_filter_state: Dictionary = {}   # 上次卡数量 FilterBar 状态
var _status_filter_state: Dictionary = {} # 上次运行状态 FilterBar 状态

func _exit_tree() -> void:
	# detached 节点 (queue 空时不挂在树里) 必须手动 free, 否则 orphan 泄漏。
	if _construction_section != null and _construction_section.get_parent() == null:
		_construction_section.queue_free()
	if _construction_rows != null and _construction_rows.get_parent() == null:
		_construction_rows.queue_free()

func _ready() -> void:
	add_theme_constant_override(&"separation", UITheme.S_4)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	_section = SectionHeaderScene.instantiate()
	add_child(_section)
	_section.set_data(tr("INFRA_SECTION"), -1, tr("INFRA_NEW_DC"), &"new_dc")
	_section.action_pressed.connect(_on_section_action)

	# ownership 筛选条 — 只用 pills, 不需要搜索 / 排序。
	_filter_bar = FilterBarScene.instantiate()
	add_child(_filter_bar)
	_filter_bar.set_pills(_localize_options(_OWNERSHIP_PILLS))
	_filter_bar.set_search_visible(false)
	_filter_bar.state_changed.connect(_on_filter_changed)
	_filter_state = _filter_bar.get_state()

	# 卡数量筛选条 — 同样只用 pills, 与 ownership 取交集。
	_size_filter_bar = FilterBarScene.instantiate()
	add_child(_size_filter_bar)
	_size_filter_bar.set_pills(_localize_options(_SIZE_PILLS))
	_size_filter_bar.set_search_visible(false)
	_size_filter_bar.state_changed.connect(_on_size_filter_changed)
	_size_filter_state = _size_filter_bar.get_state()

	# 运行状态筛选条 — 同样只用 pills, 与前两条取交集。
	_status_filter_bar = FilterBarScene.instantiate()
	add_child(_status_filter_bar)
	_status_filter_bar.set_pills(_localize_options(_STATUS_PILLS))
	_status_filter_bar.set_search_visible(false)
	_status_filter_bar.state_changed.connect(_on_status_filter_changed)
	_status_filter_state = _status_filter_bar.get_state()

	_dc_grid = HFlowContainer.new()
	_dc_grid.add_theme_constant_override(&"h_separation", UITheme.S_3)
	_dc_grid.add_theme_constant_override(&"v_separation", UITheme.S_3)
	add_child(_dc_grid)

	_empty_label = Label.new()
	_empty_label.text = tr("INFRA_EMPTY")
	_empty_label.add_theme_color_override(&"font_color", UITheme.TEXT_SECONDARY)
	_empty_label.visible = false
	add_child(_empty_label)

	# 自建队列 section + rows 暂不挂进树, refresh 时按 queue 实际状态进出。
	_construction_section = SectionHeaderScene.instantiate()
	_construction_section.set_data(tr("INFRA_BUILDING"),-1, "", &"")

	_construction_rows = HFlowContainer.new()
	_construction_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_construction_rows.add_theme_constant_override(&"h_separation", UITheme.S_3)
	_construction_rows.add_theme_constant_override(&"v_separation", UITheme.S_3)

func refresh(data: Dictionary) -> void:
	var dcs: Array = data.get("datacenters", [])
	var facility_labels: Dictionary = data.get("facility_labels", {})
	# facility_icons: {facility_spec_id: icon_path}; 调用方 (main.gd) 提供路径,
	# view 自己 load 贴图 (缺图 → null → Avatar 回退 seed/glyph)。
	var facility_icons: Dictionary = data.get("facility_icons", {})
	# facility_train_bonuses: {facility_spec_id: float}; 太空档训练加速, 显示在卡片字段。
	var facility_train_bonuses: Dictionary = data.get("facility_train_bonuses", {})
	var gpu_labels: Dictionary = data.get("gpu_labels", {})
	var power_labels: Dictionary = data.get("power_labels", {})
	var serving_target_labels: Dictionary = data.get("serving_target_labels", {})
	var dc_rental_net: Dictionary = data.get("dc_rental_net", {})
	var queue: Array = data.get("construction_queue", [])

	# DC 卡片墙。
	_clear_children(_dc_grid)
	_cards_by_id.clear()
	_datacenters = dcs
	for dc in dcs:
		var card: Control = CardScene.instantiate()
		_dc_grid.add_child(card)
		# facility_labels / facility_icons 用 String 键 (云租用 DC 的 facility_spec_id
		# 是空 StringName, Dictionary 对 &"" 的 get 恒失败 → 取不到云图标; String("") 正常)。
		var fid: String = String(dc.facility_spec_id)
		DcCard.populate(card, dc,
			String(facility_labels.get(fid, fid)),
			String(gpu_labels.get(dc.gpu_id, String(dc.gpu_id))) if String(dc.gpu_id) != "" else tr("INFRA_NO_GPU"),
			String(power_labels.get(dc.power_supply, String(dc.power_supply))),
			String(serving_target_labels.get(dc.id, "")),
			_load_facility_icon(String(facility_icons.get(fid, ""))),
			float(facility_train_bonuses.get(fid, 0.0)),
			int(dc_rental_net.get(dc.id, 0)))
		card.action_pressed.connect(_on_card_action.bind(StringName(dc.id)))
		_cards_by_id[StringName(dc.id)] = card

	_section.set_data(tr("INFRA_SECTION"), dcs.size(), tr("INFRA_NEW_DC"), &"new_dc")

	# ownership 筛选: 刷新 pill 计数 + 按当前选中态显隐卡片。
	_update_pill_counts()
	_apply_filter()

	# 自建队列 — visible toggle 不够 (老测试 _collect_text 不过滤 visible),
	# 真正把 section 与 rows 摘出树。
	_clear_children(_construction_rows)
	_construction_cards_by_id.clear()
	_construction_avatars_by_id.clear()
	_construction_progress_by_id.clear()
	_construction_fields_by_id.clear()
	var section_in_tree: bool = _construction_section.get_parent() != null
	var rows_in_tree: bool = _construction_rows.get_parent() != null
	if queue.is_empty():
		if section_in_tree:
			remove_child(_construction_section)
		if rows_in_tree:
			remove_child(_construction_rows)
	else:
		if not section_in_tree:
			add_child(_construction_section)
		if not rows_in_tree:
			add_child(_construction_rows)
		# 重新把 section 标题刷一遍, 别保留过时 visible=false 的 dead state。
		_construction_section.set_data(tr("INFRA_BUILDING"),queue.size(), "", &"")
		for c in queue:
			var card := _make_construction_card(c)
			_construction_rows.add_child(card)

# ─── 自建队列卡片 ────────────────────────────────────────────

func _make_construction_card(c: Dictionary) -> Control:
	var cid: StringName = StringName(_dict_get_any(c, ["id", &"id"], &""))
	var id_text: String = String(cid)
	var facility_label: String = String(_dict_get_any(c, ["facility_label", &"facility_label"], id_text))
	var icon_path: String = String(_dict_get_any(c, ["facility_icon", &"facility_icon", "icon_path", &"icon_path"], ""))
	var weeks_remaining: int = _queue_weeks_remaining(c)
	var total_weeks: int = _queue_total_weeks(c)
	var percent: int = _construction_progress_percent(weeks_remaining, total_weeks)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(UITheme.CARD_MIN_W, 0)
	card.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	card.add_theme_stylebox_override(&"panel", _construction_card_style())
	_construction_cards_by_id[cid] = card

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override(&"separation", UITheme.S_2)
	card.add_child(outer)

	var accent := ColorRect.new()
	accent.custom_minimum_size = Vector2(0, 4)
	accent.color = UITheme.ACCENT_INFO
	accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(accent)

	var header := HBoxContainer.new()
	header.add_theme_constant_override(&"separation", UITheme.S_2)
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_child(header)

	var avatar: Control = AvatarScene.instantiate()
	avatar.custom_minimum_size = Vector2(64, 64)
	avatar.set_data(_load_facility_icon(icon_path), "", cid, &"datacenter")
	header.add_child(avatar)
	_construction_avatars_by_id[cid] = avatar

	var title_col := VBoxContainer.new()
	title_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_col.add_theme_constant_override(&"separation", 0)
	header.add_child(title_col)

	var title := Label.new()
	title.text = facility_label
	title.add_theme_font_override(&"font", UITheme.get_ui_font_bold())
	title.add_theme_font_size_override(&"font_size", UITheme.FS_MD)
	title.add_theme_color_override(&"font_color", UITheme.TEXT_PRIMARY)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.max_lines_visible = 2
	title_col.add_child(title)

	var subtitle := Label.new()
	subtitle.text = id_text
	subtitle.add_theme_font_size_override(&"font_size", UITheme.FS_SM)
	subtitle.add_theme_color_override(&"font_color", UITheme.TEXT_SECONDARY)
	title_col.add_child(subtitle)

	var badge: Control = BadgeScene.instantiate()
	badge.set_data(tr("INFRA_BUILDING"), &"training")
	badge.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	header.add_child(badge)

	var fields: Dictionary = {}
	var fields_panel := PanelContainer.new()
	fields_panel.add_theme_stylebox_override(&"panel", _construction_fields_style())
	fields_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_child(fields_panel)

	var fields_box := VBoxContainer.new()
	fields_box.add_theme_constant_override(&"separation", UITheme.S_1)
	fields_panel.add_child(fields_box)

	var power_label: String = String(_dict_get_any(c, ["power_label", &"power_label"], ""))
	if not power_label.is_empty():
		_add_construction_field(fields_box, fields, tr("DC_POWER"), power_label)
	var gpu_label: String = String(_dict_get_any(c, ["gpu_label", &"gpu_label"], ""))
	if not gpu_label.is_empty():
		_add_construction_field(fields_box, fields, tr("INFRA_BUILD_GPU"), gpu_label)
	_add_construction_field(fields_box, fields, tr("INFRA_BUILD_DURATION"),
		tr("INFRA_BUILD_DURATION_VALUE") % [weeks_remaining, total_weeks])
	_construction_fields_by_id[cid] = fields

	var progress_row := HBoxContainer.new()
	progress_row.add_theme_constant_override(&"separation", UITheme.S_2)
	progress_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_child(progress_row)

	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = 100
	bar.value = percent
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 10)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_theme_stylebox_override(&"background", _progress_background_style())
	bar.add_theme_stylebox_override(&"fill", _progress_fill_style())
	progress_row.add_child(bar)
	_construction_progress_by_id[cid] = bar

	var pct := Label.new()
	pct.text = "%d%%" % percent
	pct.add_theme_font_override(&"font", UITheme.get_ui_font_bold())
	pct.add_theme_font_size_override(&"font_size", UITheme.FS_SM)
	pct.add_theme_color_override(&"font_color", UITheme.TEXT_SECONDARY)
	progress_row.add_child(pct)
	return card

func _add_construction_field(parent: VBoxContainer, fields: Dictionary,
		label_text: String, value_text: String) -> void:
	fields[label_text] = value_text
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", UITheme.S_2)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lab := Label.new()
	lab.text = label_text
	lab.custom_minimum_size = Vector2(72, 0)
	lab.add_theme_font_size_override(&"font_size", UITheme.FS_SM)
	lab.add_theme_color_override(&"font_color", UITheme.TEXT_SECONDARY)
	row.add_child(lab)
	var val := Label.new()
	val.text = value_text
	val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	val.add_theme_font_override(&"font", UITheme.get_ui_font_bold())
	val.add_theme_font_size_override(&"font_size", UITheme.FS_SM)
	val.add_theme_color_override(&"font_color", UITheme.TEXT_PRIMARY)
	val.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(val)
	parent.add_child(row)

func _queue_weeks_remaining(c: Dictionary) -> int:
	return int(_dict_get_any(c, ["weeks_remaining", &"weeks_remaining", "months_remaining", &"months_remaining"], 0))

func _queue_total_weeks(c: Dictionary) -> int:
	return int(_dict_get_any(c, ["total_weeks", &"total_weeks", "total_months", &"total_months"], 0))

func _construction_progress_percent(weeks_remaining: int, total_weeks: int) -> int:
	if total_weeks <= 0:
		return 0
	var done: int = clampi(total_weeks - weeks_remaining, 0, total_weeks)
	return int(round(float(done) * 100.0 / float(total_weeks)))

func _dict_get_any(d: Dictionary, keys: Array, default_value):
	for k in keys:
		if d.has(k):
			return d[k]
	return default_value

func _construction_card_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = UITheme.BG_SURFACE
	sb.border_color = UITheme.BORDER_SUBTLE
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(UITheme.R_MD)
	sb.content_margin_left = UITheme.S_3
	sb.content_margin_right = UITheme.S_3
	sb.content_margin_top = UITheme.S_2
	sb.content_margin_bottom = UITheme.S_3
	return sb

func _construction_fields_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = UITheme.BG_BASE
	sb.border_color = Color(0, 0, 0, 0)
	sb.set_border_width_all(0)
	sb.set_corner_radius_all(UITheme.R_SM)
	sb.content_margin_left = UITheme.S_2
	sb.content_margin_right = UITheme.S_2
	sb.content_margin_top = UITheme.S_2
	sb.content_margin_bottom = UITheme.S_2
	return sb

func _progress_background_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = UITheme.BG_ELEVATED
	sb.border_color = UITheme.BORDER_SUBTLE
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(UITheme.R_SM)
	return sb

func _progress_fill_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = UITheme.ACCENT_INFO
	sb.border_color = UITheme.ACCENT_INFO
	sb.set_border_width_all(0)
	sb.set_corner_radius_all(UITheme.R_SM)
	return sb

# ─── ownership 筛选 ──────────────────────────────────────────

# DC 的 ownership 归一化为 &"owned" / &"rented" (其余值按 rented 处理)。
func _ownership_of(dc) -> StringName:
	return &"owned" if StringName(dc.ownership) == &"owned" else &"rented"

# DC 按已装 GPU 卡数归一化为 small (≤72) / mid (≤8000) / large (>8000)。
# 阈值对齐 facility 档位: ≤72 = solo/pod/rack, ≤8k = room/hall/floor, >8k = building+。
func _size_bucket_of(dc) -> StringName:
	var n: int = int(dc.gpu_count)
	if n <= 72:
		return &"small"
	if n <= 8000:
		return &"mid"
	return &"large"

# DC 运行状态归一化为 idle / training / serving (未知值按 idle 处理)。
func _status_of(dc) -> StringName:
	var s := StringName(dc.status)
	if s == &"training" or s == &"serving":
		return s
	return &"idle"

func _update_pill_counts() -> void:
	if _filter_bar != null:
		var rented := 0
		var owned := 0
		for dc in _datacenters:
			if _ownership_of(dc) == &"owned":
				owned += 1
			else:
				rented += 1
		_filter_bar.update_pill_counts({
			&"all": _datacenters.size(),
			&"rented": rented,
			&"owned": owned,
		})
	if _size_filter_bar != null:
		var small := 0
		var mid := 0
		var large := 0
		for dc in _datacenters:
			match _size_bucket_of(dc):
				&"small": small += 1
				&"mid":   mid += 1
				&"large": large += 1
		_size_filter_bar.update_pill_counts({
			&"all": _datacenters.size(),
			&"small": small,
			&"mid": mid,
			&"large": large,
		})
	if _status_filter_bar != null:
		var idle := 0
		var training := 0
		var serving := 0
		for dc in _datacenters:
			match _status_of(dc):
				&"training": training += 1
				&"serving":  serving += 1
				_:           idle += 1
		_status_filter_bar.update_pill_counts({
			&"all": _datacenters.size(),
			&"idle": idle,
			&"training": training,
			&"serving": serving,
		})

func _apply_filter() -> void:
	var own_sel: Array = _filter_state.get("selected_pills", [&"all"])
	var own_unrestricted: bool = own_sel.has(&"all")
	var size_sel: Array = _size_filter_state.get("selected_pills", [&"all"])
	var size_unrestricted: bool = size_sel.has(&"all")
	var status_sel: Array = _status_filter_state.get("selected_pills", [&"all"])
	var status_unrestricted: bool = status_sel.has(&"all")
	var visible_count := 0
	for dc in _datacenters:
		var card: Control = _cards_by_id.get(StringName(dc.id), null)
		if card == null:
			continue
		# ownership ∩ 卡数量 ∩ 运行状态, 三条筛选条取交集。
		var own_ok: bool = own_unrestricted or own_sel.has(_ownership_of(dc))
		var size_ok: bool = size_unrestricted or size_sel.has(_size_bucket_of(dc))
		var status_ok: bool = status_unrestricted or status_sel.has(_status_of(dc))
		var vis: bool = own_ok and size_ok and status_ok
		card.visible = vis
		if vis:
			visible_count += 1
	# 空提示: 完全没 DC → 建议新建; 有 DC 但被筛掉 → 提示放宽筛选。
	if _datacenters.is_empty():
		_empty_label.text = tr("INFRA_EMPTY")
		_empty_label.visible = true
	elif visible_count == 0:
		_empty_label.text = tr("INFRA_EMPTY_FILTERED")
		_empty_label.visible = true
	else:
		_empty_label.visible = false

# ─── 信号 ────────────────────────────────────────────────────

func _on_section_action(_id: StringName) -> void:
	new_dc_pressed.emit()

func _on_filter_changed(state: Dictionary) -> void:
	_filter_state = state
	_apply_filter()

func _on_size_filter_changed(state: Dictionary) -> void:
	_size_filter_state = state
	_apply_filter()

func _on_status_filter_changed(state: Dictionary) -> void:
	_status_filter_state = state
	_apply_filter()

func _on_card_action(action_id: StringName, dc_id: StringName) -> void:
	dc_action.emit(dc_id, action_id)

# ─── helpers ─────────────────────────────────────────────────

func _clear_children(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()

# 路径空 / 资源不存在 → null (Avatar 走 seed/glyph 回退)。结果缓存避免重复 load。
# TODO(图片素材生成流程.md §9): 与 FacilitySpec.load_icon / 其它 view 统一成 helper。
func _load_facility_icon(icon_path: String) -> Texture2D:
	if icon_path.is_empty():
		return null
	if _icon_cache.has(icon_path):
		return _icon_cache[icon_path]
	var tex: Texture2D = null
	if ResourceLoader.exists(icon_path):
		tex = load(icon_path) as Texture2D
	_icon_cache[icon_path] = tex
	return tex

# ─── 测试 introspection ──────────────────────────────────────

func get_card_count() -> int:
	return _cards_by_id.size()

func get_construction_card_count_for_test() -> int:
	return _construction_cards_by_id.size()

func is_construction_avatar_texture_visible_for_test(construction_id: StringName) -> bool:
	var a: Control = _construction_avatars_by_id.get(construction_id, null)
	return a != null and a.has_method(&"is_texture_layer_visible") and a.is_texture_layer_visible()

func get_construction_progress_value_for_test(construction_id: StringName) -> int:
	var b: ProgressBar = _construction_progress_by_id.get(construction_id, null)
	return int(round(b.value)) if b != null else -1

func get_construction_fields_for_test(construction_id: StringName) -> Dictionary:
	return _construction_fields_by_id.get(construction_id, {})

func get_visible_card_count() -> int:
	var n := 0
	for c in _cards_by_id.values():
		if c != null and c.visible:
			n += 1
	return n

func is_card_visible_for_test(dc_id: StringName) -> bool:
	var c: Control = _cards_by_id.get(dc_id, null)
	return c != null and c.visible

# 卡片头像是否走了贴图 (而非 seed/glyph 回退) — 验证建筑图标接入。
func is_card_avatar_texture_visible_for_test(dc_id: StringName) -> bool:
	var c: Control = _cards_by_id.get(dc_id, null)
	return c != null and c.has_method(&"is_avatar_texture_visible_for_test") \
		and c.is_avatar_texture_visible_for_test()

func get_filter_pill_count() -> int:
	return _filter_bar.get_pill_count() if _filter_bar != null else 0

func get_filter_pill_text_for_test(pill_id: StringName) -> String:
	if _filter_bar != null and _filter_bar.has_method(&"get_pill_text_for_test"):
		return _filter_bar.get_pill_text_for_test(pill_id)
	return ""

func click_filter_pill_for_test(pill_id: StringName) -> void:
	if _filter_bar != null:
		_filter_bar.click_pill_for_test(pill_id)

func get_size_filter_pill_count() -> int:
	return _size_filter_bar.get_pill_count() if _size_filter_bar != null else 0

func get_size_filter_pill_text_for_test(pill_id: StringName) -> String:
	if _size_filter_bar != null and _size_filter_bar.has_method(&"get_pill_text_for_test"):
		return _size_filter_bar.get_pill_text_for_test(pill_id)
	return ""

func click_size_filter_pill_for_test(pill_id: StringName) -> void:
	if _size_filter_bar != null:
		_size_filter_bar.click_pill_for_test(pill_id)

func get_status_filter_pill_count() -> int:
	return _status_filter_bar.get_pill_count() if _status_filter_bar != null else 0

func get_status_filter_pill_text_for_test(pill_id: StringName) -> String:
	if _status_filter_bar != null and _status_filter_bar.has_method(&"get_pill_text_for_test"):
		return _status_filter_bar.get_pill_text_for_test(pill_id)
	return ""

func click_status_filter_pill_for_test(pill_id: StringName) -> void:
	if _status_filter_bar != null:
		_status_filter_bar.click_pill_for_test(pill_id)

func get_card_actions_for_test(dc_id: StringName) -> Array:
	var c: Control = _cards_by_id.get(dc_id, null)
	if c == null:
		return []
	var btns: Dictionary = c.get(&"_action_buttons")
	return btns.keys() if btns != null else []

func get_card_fields_for_test(dc_id: StringName) -> Dictionary:
	var c: Control = _cards_by_id.get(dc_id, null)
	if c == null:
		return {}
	var fields: Dictionary = {}
	var count: int = c.get_field_count()
	for i in range(count):
		var row: Dictionary = c.get_field_row_for_test(i)
		if row.has("label"):
			fields[row.label] = row.value
	return fields

func click_card_action_for_test(dc_id: StringName, action_id: StringName) -> void:
	var c: Control = _cards_by_id.get(dc_id, null)
	if c != null and c.has_method(&"click_action_for_test"):
		c.click_action_for_test(action_id)

func click_new_dc_for_test() -> void:
	if _section != null and _section.has_method(&"click_action_for_test"):
		_section.click_action_for_test()

func all_button_texts_for_test() -> PackedStringArray:
	var out := PackedStringArray()
	_collect_text(self, true, out)
	return out

func all_label_texts_for_test() -> PackedStringArray:
	var out := PackedStringArray()
	_collect_text(self, false, out)
	return out

func _collect_text(node: Node, want_button: bool, out: PackedStringArray) -> void:
	for child in node.get_children():
		if want_button and child is Button:
			out.append((child as Button).text)
		elif (not want_button) and child is Label:
			out.append((child as Label).text)
		_collect_text(child, want_button, out)
