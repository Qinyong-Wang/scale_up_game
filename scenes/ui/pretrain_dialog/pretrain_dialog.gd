extends ConfirmationDialog

## PretrainDialog — 启动预训练对话框. Per design/任务系统设计.md §5.1.1.
##
## 流程:
##   1. 主 HUD 在「模型」标签里点「训练新模型...」 → 创建本对话框 → popup_centered.
##   2. 玩家输入名字 + 架构 + 大小 + DC + 数据集 + Lead + ML eng → 任意变化触发 task.preview.
##   3. 点「启动训练」→ 校验通过则 CommandBus.send(&"task.start", ...), 失败把错误码贴到警告区.
##
## 模板固定为 &"pretrain_model" (统一 pretrain task), 大小/架构/名字由 UI 拼装入 payload.
## 不持有任何系统状态, 每次 refresh() 都从 GameState 重新读切片.

signal task_started_via_dialog(result: Dictionary)


const TEMPLATE_ID := &"pretrain_model"

# Form widgets
var _name_input: LineEdit
var _arch_dropdown: OptionButton                # A-axis (family / arch tree)
var _attention_dropdown: OptionButton           # v5 (PR-C): B-axis
var _loss_dropdown: OptionButton                # v5 (PR-C): C-axis
var _context_dropdown: OptionButton             # v5 (PR-C): D-axis
var _multimodal_method_dropdown: OptionButton   # v7 (PR-G): E-axis
var _modality_checks: Dictionary = {}           # v7 (PR-G): {StringName: CheckBox} for input_modalities
var _size_spin: SpinBox
var _size_unit_dropdown: OptionButton  # 0 = M (×1), 1 = B (×1000)
var _dc_dropdown: OptionButton
var _dataset_box: VBoxContainer
var _dataset_checkboxes: Array = []  # [{box: CheckBox, id: StringName}]
var _lead_dropdown: OptionButton
var _ml_eng_spin: SpinBox
var _ml_eng_hint: Label

# v7 (PR-G) input modality choices for the multimodal training UI. `text` is
# always selected and disabled; image/audio/video are optional checkboxes.
const _MODALITY_OPTIONS: Array = [&"text", &"image", &"audio", &"video"]

# 能力轴 → i18n key (与 dataset_collection / posttrain 对齐, const 不能调 tr; 取用处 tr)。
const _CAP_AXIS_LABELS: Dictionary = {
	&"general": "CAP_GENERAL", &"code": "CAP_CODE", &"reasoning": "CAP_REASONING",
	&"multimodal": "CAP_MULTIMODAL", &"agent": "CAP_AGENT",
}
# 数据集来源 → i18n key (与 dataset_view 对齐)。
const _DS_SOURCE_LABELS: Dictionary = {
	&"open_source": "DATASET_SRC_OPEN", &"purchased": "DATASET_SRC_PURCHASED",
	&"collected": "DATASET_SRC_COLLECTED",
}

# v7 (PR-G) — E-axis multimodal method options. Each label maps to a method id
# the player can pick when the model has non-text input modalities.
# 值为 i18n key (const 不能调 tr); 取用处 tr()。
const _MULTIMODAL_METHOD_LABELS: Dictionary = {
	&"none": "PRETRAIN_MM_NONE",
	&"cross_train": "PRETRAIN_MM_CROSS",
	&"pixel_ar": "PRETRAIN_MM_PIXEL",
	&"diffusion_ar": "PRETRAIN_MM_DIFFUSION",
	&"native_ar": "PRETRAIN_MM_NATIVE",
}

# Preview widgets
var _spec_label: Label
var _duration_label: Label
var _cost_label: Label
var _pricing_label: Label  # v8 PR-I — 推理成本 / 指导价 (开源 / 闭源)
var _speed_section_label: Label
var _speed_modifier_label: Label
var _speed_total_label: Label
var _score_section_label: Label
var _score_modifier_label: Label
var _score_total_label: Label
var _capability_section_label: Label
var _capability_label: Label
var _warning_label: Label

func _ready() -> void:
	title = tr("PRETRAIN_TITLE")
	# 两栏布局 (表单 | 预览)。由 main 用 popup_centered_ratio(0.82) 撑到视口
	# ~82%, 不再被旧的 720×640 框死; min_size 仅作窄窗兜底。
	# See design/任务系统设计.md §5.1.1.
	min_size = Vector2i(1240, 680)
	dialog_hide_on_ok = false
	get_ok_button().text = tr("PRETRAIN_START")
	get_cancel_button().text = tr("ACTION_CANCEL")
	UITheme.apply_button_variant(get_ok_button(), &"create")
	UITheme.apply_button_variant(get_cancel_button(), &"secondary")
	get_ok_button().pressed.connect(_on_start_pressed)

	# 左右两栏: 左 = 表单, 右 = 实时预览。各自独立 ScrollContainer, 内容超高
	# 时各自滚动, 不会把 OK/Cancel 顶出可视区。两栏并排充分利用宽屏空间,
	# 玩家配参数时能同时看到预览, 不必上下滚动。
	var outer := HBoxContainer.new()
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_theme_constant_override(&"separation", 12)
	add_child(outer)

	var form_panel := _make_main_panel(Vector2(690, 540), 1.15)
	outer.add_child(form_panel)
	var form_panel_root := _make_panel_root(form_panel)
	_add_panel_title(form_panel_root, tr("PRETRAIN_CONFIG"))

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	form_panel_root.add_child(scroll)

	var root := VBoxContainer.new()
	root.add_theme_constant_override(&"separation", UITheme.S_3)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(root)
	_build_form_rows(root)

	outer.add_child(VSeparator.new())

	# 预览块放进独立 ScrollContainer, 内容超出时预览自身可滚。
	var preview_panel := _make_main_panel(Vector2(560, 540), 0.85)
	outer.add_child(preview_panel)
	var preview_panel_root := _make_panel_root(preview_panel)
	_add_panel_title(preview_panel_root, tr("PRETRAIN_PREVIEW"))

	var preview_scroll := ScrollContainer.new()
	preview_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	preview_panel_root.add_child(preview_scroll)
	var preview_box := VBoxContainer.new()
	preview_box.add_theme_constant_override(&"separation", UITheme.S_3)
	preview_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_scroll.add_child(preview_box)
	_build_preview_block(preview_box)

	Log.info(&"ui", "PretrainDialog ready")

# ---- public ----------------------------------------------------------------

## Re-read slices and repopulate every dropdown / checkbox / preview. Call this
## just before popup_centered() — the dialog never auto-syncs with GameState.
func refresh() -> void:
	_populate_arch_dropdown()
	# v5 (PR-C): B/C/D axes.
	_populate_attention_dropdown()
	_populate_loss_dropdown()
	_populate_context_dropdown()
	# v7 (PR-G): modality checks + E-axis multimodal_method.
	_populate_modality_checks()
	_populate_multimodal_method_dropdown()
	_populate_dc_dropdown()
	_populate_dataset_checkboxes()
	_populate_lead_dropdown()
	_populate_ml_eng_spin()
	_refresh_preview()

# ---- form rows -------------------------------------------------------------

func _build_form_rows(root: VBoxContainer) -> void:
	# Name — same string is used as both display_name and model.id.
	_name_input = LineEdit.new()
	_name_input.placeholder_text = "MyOwl-1"
	_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_input.text_changed.connect(func(_t): _refresh_preview())
	root.add_child(_label_row(tr("PRETRAIN_NAME"), _name_input))

	# A-axis: architecture family (dense / MoE / sparse MoE)
	_arch_dropdown = OptionButton.new()
	_arch_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_arch_dropdown.item_selected.connect(func(_i): _refresh_preview())
	root.add_child(_label_row(tr("PRETRAIN_AXIS_ARCH"), _arch_dropdown))

	# v5 (PR-C) B-axis: attention mechanism (MHA / GQA / MQA / MLA / Hybrid)
	_attention_dropdown = OptionButton.new()
	_attention_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_attention_dropdown.item_selected.connect(func(_i): _refresh_preview())
	root.add_child(_label_row(tr("PRETRAIN_AXIS_ATTENTION"), _attention_dropdown))

	# v5 (PR-C) C-axis: loss function (CE / Z-loss / MTP)
	_loss_dropdown = OptionButton.new()
	_loss_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_loss_dropdown.item_selected.connect(func(_i): _refresh_preview())
	root.add_child(_label_row("Loss (C)", _loss_dropdown))

	# v5 (PR-C) D-axis: context length. v7 (PR-G) — gated by context subtree:
	# only unlocked ctx_* tiers appear here.
	_context_dropdown = OptionButton.new()
	_context_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_context_dropdown.item_selected.connect(func(_i): _refresh_preview())
	root.add_child(_label_row(tr("PRETRAIN_AXIS_CONTEXT"), _context_dropdown))

	# v7 (PR-G) — modality multi-select: text always on; image/audio/video optional.
	var mod_row := HBoxContainer.new()
	mod_row.add_theme_constant_override(&"separation", 6)
	var mod_label := Label.new()
	mod_label.text = tr("PRETRAIN_INPUT_MODALITY")
	mod_label.custom_minimum_size = Vector2(80, 0)
	mod_row.add_child(mod_label)
	for m in _MODALITY_OPTIONS:
		var cb := CheckBox.new()
		cb.text = String(m)
		if m == &"text":
			cb.button_pressed = true
			cb.disabled = true
		cb.toggled.connect(func(_p):
			_populate_multimodal_method_dropdown()
			_refresh_preview())
		mod_row.add_child(cb)
		_modality_checks[m] = cb
	root.add_child(mod_row)

	# v7 (PR-G) E-axis: multimodal training method. Disabled when only text is
	# selected (single-modality has no method to choose).
	_multimodal_method_dropdown = OptionButton.new()
	_multimodal_method_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_multimodal_method_dropdown.item_selected.connect(func(_i): _refresh_preview())
	root.add_child(_label_row(tr("PRETRAIN_AXIS_MM"), _multimodal_method_dropdown))

	# Size: 单一 SpinBox (D-2). 单位固定 B (billion params), 允许 0.1 小数;
	# 0.1B = 100M。把旧的"数字 + M/B 单位下拉"两控件合并成一个, 避免玩家
	# 把 100B 误输成 100M (差 1000×)。后缀 "B" 提示单位。
	var size_row := HBoxContainer.new()
	size_row.add_theme_constant_override(&"separation", 6)
	var size_label := Label.new()
	size_label.text = tr("PRETRAIN_SIZE")
	size_label.custom_minimum_size = Vector2(80, 0)
	size_row.add_child(size_label)
	_size_spin = SpinBox.new()
	_size_spin.min_value = 0.1     # 100M params 下限 (步进对齐, 允许整 B 值)
	_size_spin.max_value = 100_000.0  # 100T 上限 (B 单位, 100_000B = 100T)
	_size_spin.step = 0.1
	_size_spin.value = 1.0         # 默认 1B
	_size_spin.suffix = "B"        # Godot 4: 自动加单位后缀
	_size_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_size_spin.value_changed.connect(func(_v): _refresh_preview())
	size_row.add_child(_size_spin)
	root.add_child(size_row)

	# D-2 兼容: 老 _size_unit_dropdown 仍然存在 (隐藏, 不入 UI 主树), 单测
	# 可通过 .select(0/1) 模拟旧的 M/B 两档行为, _build_payload 会读它的
	# metadata。生产路径玩家看不到此控件, 永远走 B 单位。
	_size_unit_dropdown = OptionButton.new()
	_size_unit_dropdown.add_item("M")
	_size_unit_dropdown.set_item_metadata(0, 1.0)
	_size_unit_dropdown.add_item("B")
	_size_unit_dropdown.set_item_metadata(1, 1000.0)
	_size_unit_dropdown.select(1)    # 默认 B, 与 _size_spin.suffix 一致.
	_size_unit_dropdown.visible = false
	root.add_child(_size_unit_dropdown)

	# Datacenter
	_dc_dropdown = OptionButton.new()
	_dc_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dc_dropdown.item_selected.connect(func(_i): _refresh_preview())
	root.add_child(_label_row(tr("FIELD_DATACENTER"), _dc_dropdown))

	# Datasets — built dynamically in _populate_dataset_checkboxes().
	var ds_label := Label.new()
	ds_label.text = tr("FIELD_DATASET")
	root.add_child(ds_label)
	_dataset_box = VBoxContainer.new()
	_dataset_box.add_theme_constant_override(&"separation", 2)
	root.add_child(_dataset_box)

	# Lead
	_lead_dropdown = OptionButton.new()
	_lead_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lead_dropdown.item_selected.connect(func(_i): _refresh_preview())
	root.add_child(_label_row("Lead", _lead_dropdown))

	# ML eng
	var ml_row := HBoxContainer.new()
	ml_row.add_theme_constant_override(&"separation", 6)
	var ml_label := Label.new()
	ml_label.text = tr("STAFF_ROLE_ML_ENG")
	ml_label.custom_minimum_size = Vector2(80, 0)
	ml_row.add_child(ml_label)
	_ml_eng_spin = SpinBox.new()
	_ml_eng_spin.min_value = 0
	_ml_eng_spin.max_value = 0
	_ml_eng_spin.step = 1
	_ml_eng_spin.value_changed.connect(func(_v): _refresh_preview())
	ml_row.add_child(_ml_eng_spin)
	_ml_eng_hint = Label.new()
	_ml_eng_hint.add_theme_color_override(&"font_color", UITheme.TEXT_SECONDARY)
	ml_row.add_child(_ml_eng_hint)
	root.add_child(ml_row)

func _label_row(label_text: String, control: Control) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", UITheme.S_2)
	var l := Label.new()
	l.text = label_text
	l.custom_minimum_size = Vector2(104, 0)
	l.add_theme_color_override(&"font_color", UITheme.TEXT_SECONDARY)
	row.add_child(l)
	row.add_child(control)
	return row

func _make_main_panel(minimum: Vector2, stretch_ratio: float) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = stretch_ratio
	panel.custom_minimum_size = minimum
	panel.add_theme_stylebox_override(&"panel",
			_make_panel_style(UITheme.BG_SURFACE, UITheme.R_LG, UITheme.S_4))
	return panel

func _make_panel_root(panel: PanelContainer) -> VBoxContainer:
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override(&"separation", UITheme.S_3)
	panel.add_child(root)
	return root

func _add_panel_title(root: VBoxContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override(&"font", UITheme.get_ui_font_bold())
	label.add_theme_font_size_override(&"font_size", UITheme.FS_MD)
	label.add_theme_color_override(&"font_color", UITheme.TEXT_PRIMARY)
	root.add_child(label)

func _add_subpanel(root: VBoxContainer) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override(&"panel",
			_make_panel_style(UITheme.BG_BASE, UITheme.R_MD, UITheme.S_3))
	root.add_child(panel)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override(&"separation", UITheme.S_1)
	panel.add_child(box)
	return box

func _make_panel_style(bg: Color, radius: int, padding: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = UITheme.BORDER_SUBTLE
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = padding
	sb.content_margin_right = padding
	sb.content_margin_top = padding
	sb.content_margin_bottom = padding
	return sb

func _build_preview_block(root: VBoxContainer) -> void:
	var summary_box := _add_subpanel(root)
	_spec_label = Label.new()
	_duration_label = Label.new()
	_cost_label = Label.new()
	# v8 PR-I — 在 spec/duration/cost 三行下加一行 推理成本 + 指导价 (开源/闭源)。
	# 玩家调 arch/attention/MoE active_ratio 时这条会实时随 flops_per_token 变。
	_pricing_label = Label.new()
	_pricing_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for l in [_spec_label, _duration_label, _cost_label, _pricing_label]:
		l.add_theme_color_override(&"font_color", UITheme.ACCENT_INFO)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		summary_box.add_child(l)

	var speed_box := _add_subpanel(root)
	_speed_section_label = Label.new()
	_speed_section_label.text = tr("PRETRAIN_SPEED_SECTION")
	_speed_section_label.add_theme_color_override(&"font_color", UITheme.ACCENT_INFO)
	_speed_section_label.add_theme_font_override(&"font", UITheme.get_ui_font_bold())
	speed_box.add_child(_speed_section_label)
	_speed_modifier_label = Label.new()
	_speed_modifier_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_speed_modifier_label.add_theme_color_override(&"font_color", UITheme.ACCENT_WARNING)
	speed_box.add_child(_speed_modifier_label)
	_speed_total_label = Label.new()
	_speed_total_label.add_theme_color_override(&"font_color", UITheme.ACCENT_PRIMARY)
	speed_box.add_child(_speed_total_label)

	var score_box := _add_subpanel(root)
	_score_section_label = Label.new()
	_score_section_label.text = tr("PRETRAIN_SCORE_SECTION")
	_score_section_label.add_theme_color_override(&"font_color", UITheme.ACCENT_INFO)
	_score_section_label.add_theme_font_override(&"font", UITheme.get_ui_font_bold())
	score_box.add_child(_score_section_label)
	_score_modifier_label = Label.new()
	_score_modifier_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_score_modifier_label.add_theme_color_override(&"font_color", UITheme.ACCENT_WARNING)
	score_box.add_child(_score_modifier_label)
	_score_total_label = Label.new()
	_score_total_label.add_theme_color_override(&"font_color", UITheme.ACCENT_PRIMARY)
	score_box.add_child(_score_total_label)

	# Predicted capability block (4 axes). Per design 任务系统设计.md §5.1.1.
	var capability_box := _add_subpanel(root)
	_capability_section_label = Label.new()
	_capability_section_label.text = tr("PRETRAIN_CAP_SECTION")
	_capability_section_label.add_theme_color_override(&"font_color", UITheme.ACCENT_INFO)
	_capability_section_label.add_theme_font_override(&"font", UITheme.get_ui_font_bold())
	capability_box.add_child(_capability_section_label)
	_capability_label = Label.new()
	_capability_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_capability_label.add_theme_color_override(&"font_color", UITheme.ACCENT_PRIMARY)
	capability_box.add_child(_capability_label)

	var warning_box := _add_subpanel(root)
	_warning_label = Label.new()
	_warning_label.add_theme_color_override(&"font_color", UITheme.ACCENT_DANGER)
	_warning_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warning_box.add_child(_warning_label)

# ---- populate --------------------------------------------------------------

func _populate_arch_dropdown() -> void:
	_arch_dropdown.clear()
	var arch_ids: Array = []
	var unlocked: Dictionary = GameState.unlocks.get(&"arch", {})
	for arch_id in unlocked.keys():
		if bool(unlocked[arch_id]):
			arch_ids.append(StringName(arch_id))
	if arch_ids.is_empty():
		arch_ids.append(&"ant_v1")
	arch_ids.sort_custom(func(a, b): return String(a) < String(b))
	for arch_id in arch_ids:
		_arch_dropdown.add_item(_arch_label(arch_id))
		_arch_dropdown.set_item_metadata(_arch_dropdown.item_count - 1, arch_id)
	_arch_dropdown.disabled = arch_ids.is_empty()
	if _arch_dropdown.item_count > 0:
		_arch_dropdown.select(0)

# v5 (PR-C): B-axis populate. mha_baseline always present as the default unlock.
func _populate_attention_dropdown() -> void:
	_attention_dropdown.clear()
	var ids: Array = _unlocked_node_ids(&"attention", &"mha_baseline")
	for nid in ids:
		_attention_dropdown.add_item(_subtree_label(nid))
		_attention_dropdown.set_item_metadata(_attention_dropdown.item_count - 1, nid)
	if _attention_dropdown.item_count > 0:
		_attention_dropdown.select(0)

# v5 (PR-C): C-axis populate.
func _populate_loss_dropdown() -> void:
	_loss_dropdown.clear()
	var ids: Array = _unlocked_node_ids(&"loss", &"ce_baseline")
	for nid in ids:
		_loss_dropdown.add_item(_subtree_label(nid))
		_loss_dropdown.set_item_metadata(_loss_dropdown.item_count - 1, nid)
	if _loss_dropdown.item_count > 0:
		_loss_dropdown.select(0)

# v7 (PR-G): D-axis populate now reads `tech.get_context_tiers`. Only unlocked
# context-tree nodes appear; ctx_4k baseline is always present.
func _populate_context_dropdown() -> void:
	_context_dropdown.clear()
	var r: Dictionary = CommandBus.send(&"tech.get_context_tiers", {})
	var tiers: Array = r.get(&"tiers", []) if r.get(&"ok", false) else []
	if tiers.is_empty():
		_context_dropdown.add_item("4k")
		_context_dropdown.set_item_metadata(0, 4096)
		_context_dropdown.select(0)
		return
	for tier in tiers:
		var tokens: int = int(tier.get(&"max_tokens", 4096))
		var label: String = _format_context_label(tokens)
		var bonus: float = float(tier.get(&"agent_bonus", 0.0))
		var penalty: float = float(tier.get(&"train_penalty", 1.0))
		if bonus > 0.0:
			label += tr("PRETRAIN_AGENT_BONUS") % [bonus, penalty]
		_context_dropdown.add_item(label)
		_context_dropdown.set_item_metadata(_context_dropdown.item_count - 1, tokens)
	_context_dropdown.select(0)

func _format_context_label(tokens: int) -> String:
	if tokens >= 1000000:
		return "%dM" % (tokens / 1000000)
	if tokens >= 1000:
		return "%dk" % (tokens / 1000)
	return str(tokens)

# v7 (PR-G): modality multi-select doesn't auto-populate; text is always on,
# others stay as the player left them. Called on refresh() to reset state when
# the dialog is reopened.
func _populate_modality_checks() -> void:
	for m in _MODALITY_OPTIONS:
		var cb: CheckBox = _modality_checks.get(m, null)
		if cb == null:
			continue
		if m == &"text":
			cb.button_pressed = true
		else:
			cb.button_pressed = false

# v7 (PR-G): E-axis populate. When only `text` is selected the dropdown is
# disabled and the implicit method is `none`. Otherwise the dropdown lists
# `cross_train` (always available) plus any unlocked multimodal_method (from
# arch.dit_v1 / pixel_ar / native_multimodal nodes).
func _populate_multimodal_method_dropdown() -> void:
	if _multimodal_method_dropdown == null:
		return
	_multimodal_method_dropdown.clear()
	var non_text_selected: bool = false
	for m in _MODALITY_OPTIONS:
		if m == &"text":
			continue
		var cb: CheckBox = _modality_checks.get(m, null)
		if cb != null and cb.button_pressed:
			non_text_selected = true
			break
	if not non_text_selected:
		_multimodal_method_dropdown.add_item(tr(_MULTIMODAL_METHOD_LABELS[&"none"]))
		_multimodal_method_dropdown.set_item_metadata(0, &"none")
		_multimodal_method_dropdown.select(0)
		_multimodal_method_dropdown.disabled = true
		return
	_multimodal_method_dropdown.disabled = false
	var r: Dictionary = CommandBus.send(&"tech.list_multimodal_methods", {})
	var methods: Array = r.get(&"methods", []) if r.get(&"ok", false) else [&"cross_train"]
	for method in methods:
		var sn := StringName(method)
		var lbl: String = tr(_MULTIMODAL_METHOD_LABELS.get(sn, String(sn)))
		_multimodal_method_dropdown.add_item(lbl)
		_multimodal_method_dropdown.set_item_metadata(_multimodal_method_dropdown.item_count - 1, sn)
	_multimodal_method_dropdown.select(0)

# Collect unlocked node ids in a subtree, ordered with the baseline first then
# alphabetical. Falls back to [baseline_id] if the tree slice is empty (defensive
# for tests that wipe GameState.unlocks).
func _unlocked_node_ids(tree: StringName, baseline_id: StringName) -> Array:
	var slice: Dictionary = GameState.unlocks.get(tree, {})
	var ids: Array = []
	for nid in slice.keys():
		if bool(slice[nid]):
			ids.append(StringName(nid))
	if ids.is_empty():
		ids.append(baseline_id)
	ids.sort_custom(func(a, b):
		# Pin the baseline to the top so the default option is always at index 0.
		if a == baseline_id: return true
		if b == baseline_id: return false
		return String(a) < String(b))
	return ids

# Same shape as _arch_label but reused for attention / loss nodes.
func _subtree_label(node_id: StringName) -> String:
	var node := _load_arch_node(node_id)
	if node == null:
		return String(node_id)
	var summary: String = tr(String(node.effects_summary))
	if summary == "":
		return "%s [%s]" % [tr(node.display_name), String(node_id)]
	return "%s [%s · %s]" % [tr(node.display_name), String(node_id), summary]

func _populate_dc_dropdown() -> void:
	_dc_dropdown.clear()
	_dc_dropdown.add_item(tr("MSG_NONE"))
	_dc_dropdown.set_item_metadata(0, &"")
	for dc in GameState.datacenters:
		if dc.status == &"idle":
			var tflop_str: String = tr("PRETRAIN_NO_GPU") if dc.train_tflops <= 0.0 else UITheme.format_compute(dc.train_tflops)
			var own_label: String = tr("DC_OWNERSHIP_" + String(dc.ownership).to_upper())
			var lbl: String = "%s [%s · %s]" % [dc.display_label(), own_label, tflop_str]
			# 太空数据中心: 选项后缀标明训练加速 (已含在上面的 train_tflops / 预计时长里)。
			var bonus: float = InfraSystem.facility_train_bonus(dc.facility_spec_id)
			if bonus > 0.0:
				lbl += " " + (tr("PRETRAIN_DC_SPACE_BONUS") % int(round(bonus * 100.0)))
			_dc_dropdown.add_item(lbl)
			_dc_dropdown.set_item_metadata(_dc_dropdown.item_count - 1, dc.id)
	if _dc_dropdown.item_count > 1:
		_dc_dropdown.select(1)
	else:
		_dc_dropdown.select(0)

func _populate_dataset_checkboxes() -> void:
	for c in _dataset_box.get_children():
		c.queue_free()
	_dataset_checkboxes.clear()
	# D-3: 按 source 分组 (open_source / purchased / collected), 每组一个小标题,
	# 与数据集 tab 的市场列表风格对齐。数据集多时不再是一长串无序列表。
	var by_source: Dictionary = {}
	for ds in GameState.datasets:
		if ds.locked_by_task_id != &"":
			continue
		if ds.kind != &"pretrain":
			continue
		var src: StringName = ds.source
		if not by_source.has(src):
			by_source[src] = []
		by_source[src].append(ds)
	if by_source.is_empty():
		var hint := Label.new()
		hint.text = tr("PRETRAIN_NO_DATASET")
		hint.add_theme_color_override(&"font_color", UITheme.TEXT_SECONDARY)
		_dataset_box.add_child(hint)
		return
	# 固定 3 组顺序: open_source → purchased → collected。
	const _SOURCE_ORDER: Array[StringName] = [&"open_source", &"purchased", &"collected"]
	# 值为 i18n key (const 不能调 tr); 取用处 tr()。
	const _SOURCE_TITLE: Dictionary = {
		&"open_source": "PRETRAIN_SRC_OPEN",
		&"purchased": "PRETRAIN_SRC_PURCHASED",
		&"collected": "DATASET_SRC_COLLECTED",
	}
	for src in _SOURCE_ORDER:
		if not by_source.has(src):
			continue
		var list: Array = by_source[src]
		if list.is_empty():
			continue
		var src_title := Label.new()
		src_title.text = tr(String(_SOURCE_TITLE.get(src, String(src))))
		src_title.add_theme_color_override(&"font_color", UITheme.TEXT_SECONDARY)
		_dataset_box.add_child(src_title)
		for ds in list:
			_dataset_box.add_child(_build_dataset_checkbox(ds))

# D-3: 单条 Dataset → CheckBox; 抽出来给 _populate_dataset_checkboxes 用。
func _build_dataset_checkbox(ds) -> CheckBox:
	var box := CheckBox.new()
	# v9 (2026-05): pretrain math now reads ds.quality + ds.size; source is
	# audit-only. 在分组标题下不再重复 source, 字段更紧凑。
	var q_pct: int = int(round(float(ds.quality) * 100.0))
	var tag_str: String = ""
	if ds.coverage_tags.size() > 0:
		var parts: Array = []
		for t in ds.coverage_tags:
			parts.append(String(t))
		tag_str = " · " + ", ".join(parts)
	box.text = "  %s [q=%d%%%s]  %.0fB tokens" % [
		ds.display_name, q_pct, tag_str, ds.size]
	box.tooltip_text = tr("PRETRAIN_DS_TOOLTIP") % [
		tr(_DS_SOURCE_LABELS.get(ds.source, String(ds.source))), ds.quality, tag_str]
	box.toggled.connect(func(_p): _refresh_preview())
	_dataset_checkboxes.append({box = box, id = ds.id})
	return box

## Per design/招聘系统设计.md §5.4: pretrain 强制 chief_scientist。下拉只列匹配
## specialty 的 idle lead (含创始人 — is_player_scientist 万能 lead), 默认选中
## 第一位真正的 chief_scientist; 没有时退到创始人; 都没有时禁用 OK 并给提示。
func _populate_lead_dropdown() -> void:
	_lead_dropdown.clear()
	var first_match_index: int = -1
	var founder_index: int = -1
	for l in GameState.leads:
		if not l.is_idle():
			continue
		if not HiringSystem.lead_matches_specialty(l, &"chief_scientist"):
			continue
		var suffix: String = tr("CAMPAIGN_FOUNDER_SUFFIX") if l.is_player_scientist else ""
		# 下拉已按 specialty 过滤 (此处 chief_scientist), specialty 本身冗余 — 只露出
		# 友好等级 "S 级" 和能力数值, 不再打印 chief_scientist / S 这种 raw 枚举。
		_lead_dropdown.add_item(tr("CAMPAIGN_LEAD_ITEM") % [
			l.display_name, String(l.level), l.ability, suffix])
		_lead_dropdown.set_item_metadata(_lead_dropdown.item_count - 1, l.id)
		if l.is_player_scientist:
			if founder_index < 0:
				founder_index = _lead_dropdown.item_count - 1
		else:
			if first_match_index < 0:
				first_match_index = _lead_dropdown.item_count - 1
	if _lead_dropdown.item_count == 0:
		_lead_dropdown.add_item(tr("PRETRAIN_NO_CS"))
		_lead_dropdown.set_item_metadata(0, &"")
		_lead_dropdown.select(0)
	else:
		_lead_dropdown.select(first_match_index if first_match_index >= 0 else founder_index)

func _populate_ml_eng_spin() -> void:
	var pool: int = int(GameState.staff_pool.get(&"ml_eng", 0))
	var busy: int = int(GameState.staff_busy.get(&"ml_eng", 0))
	var avail: int = max(0, pool - busy)
	_ml_eng_spin.max_value = avail
	if _ml_eng_spin.value > avail:
		_ml_eng_spin.value = avail
	_ml_eng_hint.text = tr("PRETRAIN_AVAIL") % avail

# ---- preview ---------------------------------------------------------------

func _refresh_preview() -> void:
	var payload := _build_payload()
	var r: Dictionary = CommandBus.send(&"task.preview", payload)
	if not r.ok:
		_spec_label.text = tr("PRETRAIN_TEMPLATE_MISSING") % String(payload.get(&"template_id", &""))
		_duration_label.text = ""
		_cost_label.text = ""
		_pricing_label.text = ""
		_speed_modifier_label.text = ""
		_speed_total_label.text = ""
		_score_modifier_label.text = ""
		_score_total_label.text = ""
		_capability_label.text = ""
		_warning_label.text = tr("PRETRAIN_PREVIEW_FAILED") % String(r.get(&"error", &"unknown"))
		get_ok_button().disabled = true
		return
	var modalities: String = "%s → %s" % [
		_join_modalities(r.input_modalities), _join_modalities(r.output_modalities)]
	var name_for_preview: String = String(payload.get(&"display_name", "")).strip_edges()
	if name_for_preview == "":
		name_for_preview = tr("PRETRAIN_UNNAMED")
	_spec_label.text = tr("PRETRAIN_SPEC") % [
		name_for_preview, _format_size(float(r.size_params)), String(r.arch), modalities]
	_duration_label.text = tr("PRETRAIN_DURATION") % int(r.total_weeks)
	var weekly: int = int(r.weekly_cost)
	if weekly > 0:
		_cost_label.text = tr("PRETRAIN_COST_RECUR") % [
			_money(int(r.total_cost)), _money(weekly)]
	else:
		_cost_label.text = tr("PRETRAIN_COST") % _money(int(r.total_cost))
	_update_pricing_preview(float(r.get(&"flops_per_token", 0.0)))
	_update_modifier_sections(r.get(&"modifier_breakdown", []))
	_update_predicted_capability(r.get(&"predicted_capability", {}))

	var problems := _validate(payload, r)
	if problems.is_empty():
		_warning_label.text = ""
		get_ok_button().disabled = false
	else:
		_warning_label.text = tr("WARN_PREFIX") + " · ".join(problems)
		get_ok_button().disabled = true

func _validate(payload: Dictionary, preview: Dictionary) -> Array:
	var problems: Array = []
	# Name validation.
	var raw_name: String = String(payload.get(&"display_name", "")).strip_edges()
	if raw_name == "":
		problems.append(tr("PRETRAIN_ERR_NAME"))
	elif not _is_valid_name(raw_name):
		problems.append(tr("PRETRAIN_ERR_NAME_INVALID"))
	elif _name_already_used(raw_name):
		problems.append(tr("PRETRAIN_ERR_NAME_TAKEN") % raw_name)

	# Size validation.
	var size_m: float = float(payload.get(&"size_params", 0.0))
	if size_m <= 0.0:
		problems.append(tr("PRETRAIN_ERR_SIZE"))

	# scaling_law inputs (DC + dataset). Only the unified pretrain_model template
	# is used here, so we don't bother probing the duration_func — always check.
	if String(payload.get(&"datacenter_id", &"")) == "":
		problems.append(tr("PRETRAIN_ERR_DC"))
	else:
		var sel_dc_id := StringName(payload.get(&"datacenter_id", &""))
		for chk_dc in GameState.datacenters:
			if chk_dc.id == sel_dc_id and chk_dc.train_tflops <= 0.0:
				problems.append(tr("PRETRAIN_ERR_NO_COMPUTE"))
				break
	if (payload.get(&"dataset_ids", []) as Array).is_empty():
		problems.append(tr("PRETRAIN_ERR_DATASET"))

	# Per design/招聘系统设计.md §5.4: pretrain 强制 chief_scientist.
	if (payload.get(&"lead_ids", []) as Array).is_empty():
		problems.append(tr("PRETRAIN_ERR_CS"))

	# Cash check.
	if int(preview.total_cost) > GameState.cash:
		problems.append(tr("DC_WARN_CASH") % [
			_money(int(preview.total_cost)), _money(GameState.cash)])
	return problems

const _MAX_NAME_LEN: int = 40
func _is_valid_name(candidate_name: String) -> bool:
	if candidate_name.is_empty() or candidate_name.length() > _MAX_NAME_LEN:
		return false
	for c in candidate_name:
		var ok := false
		if c.is_valid_int(): ok = true
		elif c == "-" or c == "_" or c == "." or c == " ": ok = true
		elif c.to_lower() != c.to_upper(): ok = true
		elif c.unicode_at(0) >= 0x4E00 and c.unicode_at(0) <= 0x9FFF: ok = true
		if not ok:
			return false
	return true

func _name_already_used(candidate_name: String) -> bool:
	var sn := StringName(candidate_name)
	for m in GameState.models:
		if m.id == sn:
			return true
	for inst in GameState.active_tasks:
		if inst.subtype != &"pretrain":
			continue
		var planned: String = String(inst.completion_payload.get(&"display_name", ""))
		if planned.strip_edges() == candidate_name:
			return true
	return false

# ---- start -----------------------------------------------------------------

func _on_start_pressed() -> void:
	var payload := _build_payload()
	var r: Dictionary = CommandBus.send(&"task.start", payload)
	if r.ok:
		Log.info(&"ui", "PretrainDialog launched task", {task_id = r.get(&"task_id", &"")})
		task_started_via_dialog.emit(r)
		hide()
	else:
		var err: String = String(r.get(&"error", &"unknown"))
		Log.warn(&"ui", "PretrainDialog start failed", {error = err})
		_warning_label.text = tr("PRETRAIN_START_FAILED") % err
		get_ok_button().disabled = true

func _build_payload() -> Dictionary:
	var arch_id: StringName = &""
	if _arch_dropdown != null and _arch_dropdown.selected >= 0:
		arch_id = _arch_dropdown.get_item_metadata(_arch_dropdown.selected)

	# v5 (PR-C): B/C/D axes.
	var attention_id: StringName = &"mha_baseline"
	if _attention_dropdown != null and _attention_dropdown.selected >= 0:
		attention_id = _attention_dropdown.get_item_metadata(_attention_dropdown.selected)
	var loss_id: StringName = &"ce_baseline"
	if _loss_dropdown != null and _loss_dropdown.selected >= 0:
		loss_id = _loss_dropdown.get_item_metadata(_loss_dropdown.selected)
	var context_tokens: int = 4096
	if _context_dropdown != null and _context_dropdown.selected >= 0:
		context_tokens = int(_context_dropdown.get_item_metadata(_context_dropdown.selected))

	# v7 (PR-G): input_modalities multi-check + E-axis multimodal_method.
	var input_modalities: Array = []
	for m in _MODALITY_OPTIONS:
		var cb: CheckBox = _modality_checks.get(m, null)
		if cb != null and cb.button_pressed:
			input_modalities.append(StringName(m))
	if input_modalities.is_empty():
		input_modalities.append(&"text")
	var multimodal_method: StringName = &"none"
	if _multimodal_method_dropdown != null and _multimodal_method_dropdown.selected >= 0 \
			and not _multimodal_method_dropdown.disabled:
		multimodal_method = StringName(_multimodal_method_dropdown.get_item_metadata(
				_multimodal_method_dropdown.selected))

	# D-2: 大小用单一 SpinBox (单位 B), 默认 ×1000 转 M。隐藏的兼容下拉允许
	# 测试切回 M 单位 (×1)。生产路径下拉永远在 B (index 1)。
	var size_unit_mult: float = 1000.0
	if _size_unit_dropdown != null and _size_unit_dropdown.selected >= 0:
		size_unit_mult = float(_size_unit_dropdown.get_item_metadata(_size_unit_dropdown.selected))
	var size_params_m: float = 0.0
	if _size_spin != null:
		size_params_m = float(_size_spin.value) * size_unit_mult

	var dc_id: StringName = &""
	if _dc_dropdown != null and _dc_dropdown.selected >= 0:
		dc_id = _dc_dropdown.get_item_metadata(_dc_dropdown.selected)

	var dataset_ids: Array = []
	for entry in _dataset_checkboxes:
		if entry.box.button_pressed:
			dataset_ids.append(entry.id)

	var lead_ids: Array = []
	if _lead_dropdown != null and _lead_dropdown.selected >= 0:
		var lid = _lead_dropdown.get_item_metadata(_lead_dropdown.selected)
		if lid != null and lid != &"":
			lead_ids.append(lid)

	var staff: Dictionary = {}
	if _ml_eng_spin != null and int(_ml_eng_spin.value) > 0:
		staff[&"ml_eng"] = int(_ml_eng_spin.value)

	var display_name: String = ""
	if _name_input != null:
		display_name = _name_input.text.strip_edges()

	var payload: Dictionary = {
		template_id = TEMPLATE_ID,
		size_params = size_params_m,
		# v5 (PR-C): always forward B/C/D so the backend can apply the multipliers
		# (defaults are baseline 1.0 so nothing changes when the player keeps the
		# defaults).
		attention_id = attention_id,
		loss_id = loss_id,
		context_length_tokens = context_tokens,
		# v7 (PR-G): E-axis multimodal_method + input_modalities override (task
		# template defaults [text] only — PretrainDialog can extend with image /
		# audio / video).
		multimodal_method = multimodal_method,
		input_modalities = input_modalities,
	}
	if display_name != "":
		payload[&"display_name"] = display_name
	if arch_id != &"":
		payload[&"arch_id"] = arch_id
	if dc_id != &"":
		payload[&"datacenter_id"] = dc_id
	if not dataset_ids.is_empty():
		payload[&"dataset_ids"] = dataset_ids
	if not lead_ids.is_empty():
		payload[&"lead_ids"] = lead_ids
	if not staff.is_empty():
		payload[&"staff"] = staff
	return payload

# ---- formatting helpers ----------------------------------------------------

func _join_modalities(arr: Array) -> String:
	var parts: Array = []
	for v in arr:
		parts.append(String(v))
	return "+".join(parts) if not parts.is_empty() else "?"

func _format_size(size_m: float) -> String:
	if size_m >= 1000.0:
		return "%.1fB params" % (size_m / 1000.0)
	return "%dM params" % int(size_m)

# v8 PR-I — 把 task.preview 的 flops_per_token 喂给 research.preview_pricing,
# 让玩家在调架构 / 大小 / attention / MoE / context 时实时看到推理成本 + 指导价
# (开源 / 闭源两档)。详见 design/研究系统设计.md §4.8.
func _update_pricing_preview(fpt: float) -> void:
	if fpt <= 0.0:
		_pricing_label.text = ""
		return
	# 2026-05: 带上 active_param_ratio 触发 MoE 8× cost cap (super_sparse 等
	# 高稀疏 arch 在算 base price 时按 active=0.125 算).
	var arch_id: StringName = &""
	if _arch_dropdown and _arch_dropdown.selected >= 0:
		arch_id = StringName(_arch_dropdown.get_item_metadata(_arch_dropdown.selected))
	var active_ratio: float = Model.active_param_ratio_for(arch_id)
	var r: Dictionary = CommandBus.send(&"research.preview_pricing",
			{flops_per_token = fpt, active_param_ratio = active_ratio})
	if not r.get(&"ok", false):
		_pricing_label.text = ""
		return
	var base: float = float(r.base_price)
	var g_open: float = float(r.guidance_open)
	var g_closed: float = float(r.guidance_closed)
	_pricing_label.text = tr("PRETRAIN_PRICING") % [
		_format_per_m(base), _format_per_m(g_open), _format_per_m(g_closed)]

func _format_per_m(per_token: float) -> String:
	var per_m: float = per_token * 1_000_000.0
	if per_m < 0.01:
		return "$%.4f/M" % per_m
	if per_m < 1.0:
		return "$%.2f/M" % per_m
	return "$%.2f/M" % per_m

func _update_modifier_sections(entries: Array) -> void:
	var speed_entries: Array = []
	var score_entries: Array = []
	for e in entries:
		var cat: StringName = e.get(&"category", &"speed")
		if cat == &"score":
			score_entries.append(e)
		else:
			speed_entries.append(e)

	_speed_modifier_label.text = _format_modifier_lines(speed_entries)
	_speed_total_label.text = _format_total_line(speed_entries, tr("PRETRAIN_SPEED_TOTAL"))

	_score_modifier_label.text = _format_modifier_lines(score_entries)
	_score_total_label.text = _format_total_line(score_entries, tr("PRETRAIN_SCORE_TOTAL"))

func _format_modifier_lines(entries: Array) -> String:
	if entries.is_empty():
		return tr("PRETRAIN_NO_MOD")
	var lines: Array = []
	for e in entries:
		var kind: StringName = e.get(&"kind", &"neutral")
		var prefix := "  = "
		if kind == &"buff":
			prefix = "  + "
		elif kind == &"debuff":
			prefix = "  - "
		# label 是 TASK_MOD_* 语义 key (task_system 产出), 显示时 tr 成当前语言。
		lines.append("%s%s  ×%.2f" % [
			prefix,
			tr(String(e.get(&"label", e.get(&"id", &"?")))),
			float(e.get(&"value", 1.0)),
		])
	return "\n".join(lines)

func _update_predicted_capability(caps: Dictionary) -> void:
	if caps.is_empty():
		_capability_label.text = tr("PRETRAIN_NO_EST")
		return
	# 5 capability axes; scores have no upper cap (100 = SOTA baseline).
	var lines: Array = []
	for axis in [&"general", &"code", &"reasoning", &"multimodal", &"agent"]:
		var v: float = float(caps.get(axis, 0.0))
		lines.append("  %-10s  %6.1f" % [tr(_CAP_AXIS_LABELS[axis]), v])
	_capability_label.text = "\n".join(lines)

func _format_total_line(entries: Array, label: String) -> String:
	var total: float = 1.0
	for e in entries:
		total *= float(e.get(&"value", 1.0))
	var pct: float = (total - 1.0) * 100.0
	var sign_str := "+" if pct >= 0.0 else ""
	return "  %s: ×%.2f  (%s%.1f%%)" % [label, total, sign_str, pct]

func _arch_label(arch_id: StringName) -> String:
	var node := _load_arch_node(arch_id)
	if node == null:
		return String(arch_id)
	var summary: String = tr(node.effects_summary)
	if summary == "":
		return "%s [%s]" % [tr(node.display_name), String(arch_id)]
	return "%s [%s · %s]" % [tr(node.display_name), String(arch_id), summary]

func _load_arch_node(arch_id: StringName) -> TechNode:
	var path: String = "res://resources/data/tech/arch/%s.tres" % String(arch_id)
	if not FileAccess.file_exists(path):
		return null
	var res := load(path)
	if res is TechNode:
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
