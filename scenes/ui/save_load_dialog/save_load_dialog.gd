extends AcceptDialog

## SaveLoadDialog — 简易存档/读档对话框. Per design/游戏基础架构设计.md §6.3.1.
##
## 顶栏「💾」按钮打开此对话框, 玩家可:
##   - 输入 slot 名 → 「保存」 (空名 fallback 到 manual_<turn>);
##   - 在已有 slot 行点「读取」 / 「覆盖」 / 「删除」;
##   - autosave slot 始终排在最前, 灰底, 不允许手动删除。
##
## 不做版本迁移 — 失败 (`not_found` / `corrupted` / `incompatible_version`) 直接
## 在对话框内红字显示, 不关闭。

const ROW_META_DELETE_BTN := "delete_btn"

var _content_scroll: ScrollContainer
var _create_section: PanelContainer
var _slots_section: PanelContainer
var _status_panel: PanelContainer
var _create_title_label: Label
var _slots_title_label: Label
var _slot_list: VBoxContainer
var _empty_state: PanelContainer
var _new_slot_input: LineEdit
var _status_label: Label
var _save_btn: Button

func _ready() -> void:
	title = tr("SAVE_TITLE")
	min_size = Vector2i(900, 660)
	dialog_hide_on_ok = true
	get_ok_button().text = tr("ACTION_CLOSE")

	var root := VBoxContainer.new()
	root.add_theme_constant_override(&"separation", UITheme.S_3)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(root)

	_content_scroll = ScrollContainer.new()
	_content_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content_scroll.custom_minimum_size = Vector2(840, 500)
	_content_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(_content_scroll)

	var content_margin := MarginContainer.new()
	content_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_margin.add_theme_constant_override(&"margin_left", UITheme.S_1)
	content_margin.add_theme_constant_override(&"margin_right", UITheme.S_1)
	content_margin.add_theme_constant_override(&"margin_top", UITheme.S_1)
	content_margin.add_theme_constant_override(&"margin_bottom", UITheme.S_1)
	_content_scroll.add_child(content_margin)

	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override(&"separation", UITheme.S_3)
	content_margin.add_child(content)

	var create := _make_section("SAVE_SECTION_CREATE", &"save")
	_create_section = create.panel
	_create_title_label = create.title
	var create_body: VBoxContainer = create.body
	content.add_child(_create_section)

	# ---- 顶部: 新建存档区 ------------------------------------------------
	var new_row := HBoxContainer.new()
	new_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	new_row.add_theme_constant_override(&"separation", UITheme.S_3)
	var lbl := Label.new()
	lbl.text = tr("SAVE_NEW")
	lbl.custom_minimum_size.x = 96
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override(&"font_size", UITheme.FS_SM)
	lbl.add_theme_color_override(&"font_color", UITheme.TEXT_SECONDARY)
	new_row.add_child(lbl)
	_new_slot_input = LineEdit.new()
	_new_slot_input.placeholder_text = tr("SAVE_SLOT_PLACEHOLDER")
	_new_slot_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_new_slot_input.max_length = 24
	new_row.add_child(_new_slot_input)
	_save_btn = Button.new()
	_save_btn.text = tr("SAVE_BTN")
	_save_btn.pressed.connect(_on_save_pressed)
	UITheme.apply_button_variant(_save_btn, &"create")
	new_row.add_child(_save_btn)
	create_body.add_child(new_row)

	# ---- 中部: slot 列表 -------------------------------------------------
	var slots := _make_section("SAVE_SECTION_SLOTS", &"slots")
	_slots_section = slots.panel
	_slots_title_label = slots.title
	var slots_body: VBoxContainer = slots.body
	content.add_child(_slots_section)

	_empty_state = _make_empty_state()
	slots_body.add_child(_empty_state)

	_slot_list = VBoxContainer.new()
	_slot_list.add_theme_constant_override(&"separation", UITheme.S_2)
	_slot_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slots_body.add_child(_slot_list)

	# ---- 底部: status -----------------------------------------------------
	_status_panel = PanelContainer.new()
	_status_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_panel.visible = false
	_status_panel.add_theme_stylebox_override(&"panel", _status_stylebox())
	root.add_child(_status_panel)
	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_font_size_override(&"font_size", UITheme.FS_SM)
	_status_label.add_theme_color_override(&"font_color", UITheme.TEXT_SECONDARY)
	_status_panel.add_child(_status_label)

func _make_section(title_key: String, icon_kind: StringName) -> Dictionary:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override(&"panel", _section_stylebox())

	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override(&"separation", UITheme.S_3)
	panel.add_child(box)

	var header := HBoxContainer.new()
	header.add_theme_constant_override(&"separation", UITheme.S_2)
	box.add_child(header)

	var icon := _SectionIcon.new()
	icon.kind = icon_kind
	icon.custom_minimum_size = Vector2(28, 28)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(icon)

	var title := Label.new()
	title.text = tr(title_key)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_override(&"font", UITheme.get_ui_font_bold())
	title.add_theme_font_size_override(&"font_size", UITheme.FS_MD)
	title.add_theme_color_override(&"font_color", UITheme.TEXT_PRIMARY)
	header.add_child(title)

	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override(&"separation", UITheme.S_2)
	box.add_child(body)
	return {panel = panel, title = title, body = body}

func _make_empty_state() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override(&"panel",
		_box(UITheme.BG_BASE, UITheme.BORDER_SUBTLE, UITheme.R_MD, UITheme.S_4))

	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override(&"separation", UITheme.S_1)
	panel.add_child(col)

	var title := Label.new()
	title.text = tr("SAVE_EMPTY_TITLE")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override(&"font", UITheme.get_ui_font_bold())
	title.add_theme_font_size_override(&"font_size", UITheme.FS_MD)
	title.add_theme_color_override(&"font_color", UITheme.TEXT_PRIMARY)
	col.add_child(title)

	var hint := Label.new()
	hint.text = tr("SAVE_EMPTY_HINT")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override(&"font_size", UITheme.FS_SM)
	hint.add_theme_color_override(&"font_color", UITheme.TEXT_SECONDARY)
	col.add_child(hint)
	return panel

func _section_stylebox() -> StyleBoxFlat:
	return _box(UITheme.BG_SURFACE, UITheme.BORDER_SUBTLE, UITheme.R_MD, UITheme.S_4)

func _status_stylebox() -> StyleBoxFlat:
	return _box(UITheme.BG_BASE, UITheme.BORDER_SUBTLE, UITheme.R_SM, UITheme.S_2)

func _box(bg: Color, border: Color, radius: int, margin: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = margin
	sb.content_margin_right = margin
	sb.content_margin_top = margin
	sb.content_margin_bottom = margin
	return sb

# ---- public -------------------------------------------------------------

## 重建 slot 行. 在打开 / save / load / delete 后调用。
func refresh() -> void:
	if _slot_list == null:
		return
	# remove + queue_free 保证下面 add_child 看到的是干净列表;
	# queue_free 单用是 deferred 的, 同一帧内 _slot_list.get_child_count() 还包含旧行。
	for c in _slot_list.get_children():
		_slot_list.remove_child(c)
		c.queue_free()
	var slots: Array = Save.list_slots()
	# autosave 排首位, 其余按字典序。
	slots.sort_custom(func(a, b):
		if a == Save.AUTOSAVE_SLOT: return true
		if b == Save.AUTOSAVE_SLOT: return false
		return String(a) < String(b))
	if _empty_state != null:
		_empty_state.visible = slots.is_empty()
	if _slot_list != null:
		_slot_list.visible = not slots.is_empty()
	for slot in slots:
		_slot_list.add_child(_make_slot_row(slot))

func open() -> void:
	refresh()
	_set_status("")
	popup_centered()

func _set_status(text: String, is_error: bool = false) -> void:
	if _status_label == null:
		return
	_status_label.text = text
	_status_label.add_theme_color_override(&"font_color",
		UITheme.ACCENT_DANGER if is_error else UITheme.TEXT_SECONDARY)
	if _status_panel != null:
		_status_panel.visible = not text.is_empty()

# ---- save / load / delete handlers --------------------------------------

func _on_save_pressed() -> void:
	var raw: String = _new_slot_input.text
	var clean: String = _sanitize_slot_name(raw)
	if clean.is_empty():
		clean = "manual_%d" % GameState.turn
	_save_slot(clean)
	_new_slot_input.text = ""

func _save_slot(slot: String) -> void:
	if slot.is_empty():
		slot = "manual_%d" % GameState.turn
	var r: Dictionary = Save.write(StringName(slot))
	if r.get(&"ok", false):
		_set_status(tr("SAVE_OK") % [slot, GameState.turn])
	else:
		_set_status(tr("SAVE_FAILED") % String(r.get(&"error", &"unknown")), true)
	refresh()

func _load_slot(slot: StringName) -> void:
	var r: Dictionary = Save.read(slot)
	if r.get(&"ok", false):
		_set_status(tr("SAVE_LOADED") % [String(slot), int(r.get(&"turn", 0))])
	else:
		var err: String = String(r.get(&"error", &"unknown"))
		_set_status(tr("MENU_LOAD_FAILED") % err, true)

func _delete_slot(slot: StringName) -> void:
	if slot == Save.AUTOSAVE_SLOT:
		_set_status(tr("SAVE_NO_DEL_AUTO"), true)
		return
	if Save.delete_slot(slot):
		_set_status(tr("SAVE_DELETED") % String(slot))
	else:
		_set_status(tr("SAVE_DEL_FAILED") % String(slot), true)
	refresh()

# ---- row construction ---------------------------------------------------

func _make_slot_row(slot: StringName) -> Control:
	var panel := PanelContainer.new()
	# autosave 行用 BG_BASE 灰底, 其余 slot 用 BG_SURFACE 纯白; 便于一眼区分。
	var bg := UITheme.BG_BASE if slot == Save.AUTOSAVE_SLOT else UITheme.BG_SURFACE
	panel.add_theme_stylebox_override(&"panel",
		_box(bg, UITheme.BORDER_SUBTLE, UITheme.R_MD, UITheme.S_3))

	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override(&"separation", UITheme.S_3)
	panel.add_child(row)

	var icon := _SlotIcon.new()
	icon.is_auto = slot == Save.AUTOSAVE_SLOT
	icon.custom_minimum_size = Vector2(40, 40)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)

	var info_col := VBoxContainer.new()
	info_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_col.add_theme_constant_override(&"separation", 2)
	row.add_child(info_col)

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override(&"separation", 8)
	info_col.add_child(title_row)
	var name_lbl := Label.new()
	name_lbl.text = String(slot)
	name_lbl.add_theme_font_override(&"font", UITheme.get_ui_font_bold())
	name_lbl.add_theme_font_size_override(&"font_size", UITheme.FS_MD)
	name_lbl.add_theme_color_override(&"font_color", UITheme.TEXT_PRIMARY)
	title_row.add_child(name_lbl)
	if slot == Save.AUTOSAVE_SLOT:
		var tag := _make_pill_label()
		tag.text = tr("SAVE_AUTO_TAG")
		title_row.add_child(tag)

	var meta := _read_slot_meta(slot)
	var meta_lbl := Label.new()
	meta_lbl.text = tr("SAVE_META") % [int(meta.get("turn", 0)), String(meta.get("saved_at", "-"))]
	meta_lbl.add_theme_font_size_override(&"font_size", UITheme.FS_SM)
	meta_lbl.add_theme_color_override(&"font_color", UITheme.TEXT_SECONDARY)
	info_col.add_child(meta_lbl)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override(&"separation", UITheme.S_2)
	row.add_child(actions)

	var load_btn := Button.new()
	load_btn.text = tr("SAVE_LOAD_BTN")
	load_btn.pressed.connect(func(): _load_slot(slot))
	UITheme.apply_button_variant(load_btn, &"primary")
	actions.add_child(load_btn)

	var overwrite_btn := Button.new()
	overwrite_btn.text = tr("SAVE_OVERWRITE")
	overwrite_btn.pressed.connect(func(): _save_slot(String(slot)))
	UITheme.apply_button_variant(overwrite_btn, &"toolbar")
	actions.add_child(overwrite_btn)

	if slot != Save.AUTOSAVE_SLOT:
		var del_btn := Button.new()
		del_btn.text = tr("ACTION_DELETE")
		del_btn.pressed.connect(func(): _delete_slot(slot))
		UITheme.apply_button_variant(del_btn, &"danger")
		actions.add_child(del_btn)
		panel.set_meta(ROW_META_DELETE_BTN, true)
	panel.set_meta("slot_id", String(slot))
	return panel

func _make_pill_label() -> Label:
	var tag := Label.new()
	tag.add_theme_font_size_override(&"font_size", UITheme.FS_XS)
	tag.add_theme_color_override(&"font_color", UITheme.TEXT_PRIMARY)
	tag.add_theme_stylebox_override(&"normal",
		_box(UITheme.ACCENT_INFO_SUBTLE, UITheme.BORDER_SUBTLE, UITheme.R_SM, UITheme.S_1))
	return tag

func _read_slot_meta(slot: StringName) -> Dictionary:
	# 轻量 peek: 解析 JSON header, 失败回 {} 不抛错。
	var path: String = "%s/%s.json" % [Save.save_dir, String(slot)]
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var raw: String = f.get_as_text()
	f.close()
	var json := JSON.new()
	if json.parse(raw) != OK:
		return {turn = 0, saved_at = tr("SAVE_CORRUPT")}
	var parsed = json.data
	if not (parsed is Dictionary):
		return {turn = 0, saved_at = tr("SAVE_CORRUPT")}
	return {
		turn = int(parsed.get("turn", 0)),
		saved_at = String(parsed.get("saved_at", "-")),
	}

# ---- helpers used by tests ---------------------------------------------

func _row_count() -> int:
	if _slot_list == null:
		return 0
	return _slot_list.get_child_count()

func _slot_has_delete_button(slot: StringName) -> bool:
	for child in _slot_list.get_children():
		if String(child.get_meta("slot_id", "")) == String(slot):
			return bool(child.get_meta(ROW_META_DELETE_BTN, false))
	return false

func _slot_has_action_button(slot: StringName, text: String) -> bool:
	for child in _slot_list.get_children():
		if String(child.get_meta("slot_id", "")) != String(slot):
			continue
		return _node_has_button_text(child, text)
	return false

func _node_has_button_text(node: Node, text: String) -> bool:
	if node is Button and (node as Button).text == text:
		return true
	for child in node.get_children():
		if _node_has_button_text(child, text):
			return true
	return false

func _sanitize_slot_name(raw: String) -> String:
	# 只留 a-z 0-9 _ -. 截到 24 字符. 空字符串由调用方 fallback。
	var lower: String = raw.strip_edges().to_lower()
	var out := ""
	for i in range(lower.length()):
		var c: String = lower[i]
		var b: int = c.unicode_at(0)
		var is_alpha: bool = b >= 0x61 and b <= 0x7a   # a-z
		var is_digit: bool = b >= 0x30 and b <= 0x39   # 0-9
		var is_dash: bool = c == "_" or c == "-"
		if is_alpha or is_digit or is_dash:
			out += c
		if out.length() >= 24:
			break
	return out

class _SectionIcon extends Control:
	var kind: StringName = &"save"

	func _ready() -> void:
		resized.connect(queue_redraw)

	func _draw() -> void:
		var bg := StyleBoxFlat.new()
		bg.bg_color = UITheme.ACCENT_INFO_SUBTLE
		bg.border_color = UITheme.BORDER_SUBTLE
		bg.set_border_width_all(1)
		bg.set_corner_radius_all(UITheme.R_SM)
		draw_style_box(bg, Rect2(Vector2.ZERO, size))
		var col := Color(UITheme.TEXT_PRIMARY, 0.72)
		var pad := 7.0
		if kind == &"slots":
			for i in range(3):
				var y := pad + float(i) * 6.0
				draw_rect(Rect2(pad, y, size.x - pad * 2.0, 3.0), col)
			return
		var body := Rect2(pad, pad, size.x - pad * 2.0, size.y - pad * 2.0)
		draw_rect(body, Color(UITheme.TEXT_PRIMARY, 0.10))
		draw_line(Vector2(body.position.x + 4, body.position.y + 4),
			Vector2(body.end.x - 4, body.position.y + 4), col, 2.0)
		draw_rect(Rect2(body.position.x + 5, body.end.y - 7, body.size.x - 10, 4), col)

class _SlotIcon extends Control:
	var is_auto: bool = false

	func _ready() -> void:
		resized.connect(queue_redraw)

	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, size)
		var bg := UITheme.ACCENT_INFO_SUBTLE if is_auto else UITheme.BG_BASE
		var sb := StyleBoxFlat.new()
		sb.bg_color = bg
		sb.border_color = UITheme.BORDER_SUBTLE
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(UITheme.R_MD)
		draw_style_box(sb, rect)
		var col := Color(UITheme.TEXT_PRIMARY, 0.68)
		var pad := 10.0
		var disk := Rect2(pad, pad, size.x - pad * 2.0, size.y - pad * 2.0)
		draw_rect(disk, Color(UITheme.TEXT_PRIMARY, 0.10))
		draw_line(Vector2(disk.position.x + 4, disk.position.y + 5),
			Vector2(disk.end.x - 4, disk.position.y + 5), col, 2.0)
		draw_rect(Rect2(disk.position.x + 5, disk.end.y - 8, disk.size.x - 10, 4), col)
