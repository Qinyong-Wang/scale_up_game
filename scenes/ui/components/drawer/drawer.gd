extends PanelContainer

## Drawer — 右抽屉。
##
## 布局:
##   ┌─ PanelContainer (DRAWER_W, BG_SURFACE) ────────────┐
##   │ Header [title]                          [✕ close]  │
##   │ ─────────────────────────────────────────────────── │
##   │ ScrollContainer (content 节点由调用方塞入)          │
##   │ ─────────────────────────────────────────────────── │
##   │ Footer [secondary]                  [primary]       │
##   └────────────────────────────────────────────────────┘
##
## API: open(data) 显示并配置, close() 隐藏。
## data dict:
##   title: String                                              (必填)
##   content: Control                                           (必填, 内容节点)
##   primary:   {"label": String, "action_id": StringName}     (可选)
##   secondary: {"label": String, "action_id": StringName}     (可选)
##
## 旧 content 在 open() 时 queue_free, 不留泄漏。

signal closed
signal primary_pressed(action_id: StringName)
signal secondary_pressed(action_id: StringName)

const IconButtonScene := preload("res://scenes/ui/components/icon_button/icon_button.gd")
const IconButtonTscn := preload("res://scenes/ui/components/icon_button/icon_button.tscn")

var _title_label: Label
var _close_btn: Control            # IconButton instance
var _scroll: ScrollContainer
var _content_holder: VBoxContainer
var _primary_btn: Button
var _secondary_btn: Button
var _footer_row: HBoxContainer

var _primary_id: StringName = &""
var _secondary_id: StringName = &""
var _current_content: Control = null

func _ready() -> void:
	custom_minimum_size = Vector2(UITheme.DRAWER_W, 0)
	visible = false

	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.add_theme_constant_override(&"separation", UITheme.S_2)
	add_child(v)

	# ─── Header ────────────────────────────────────────────
	var header := HBoxContainer.new()
	header.add_theme_constant_override(&"separation", UITheme.S_3)
	v.add_child(header)

	_title_label = Label.new()
	_title_label.add_theme_font_size_override(&"font_size", UITheme.FS_LG)
	_title_label.add_theme_color_override(&"font_color", UITheme.TEXT_PRIMARY)
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title_label)

	_close_btn = IconButtonTscn.instantiate()
	header.add_child(_close_btn)
	# IconButton._ready 在加到 tree 后触发, 此时 set_data 是安全的。
	_close_btn.set_data("✕", "", &"close", &"ghost")
	_close_btn.pressed_with_id.connect(_on_close_pressed)

	v.add_child(HSeparator.new())

	# ─── Content (Scroll) ─────────────────────────────────
	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_scroll)

	_content_holder = VBoxContainer.new()
	_content_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_content_holder)

	v.add_child(HSeparator.new())

	# ─── Footer ────────────────────────────────────────────
	_footer_row = HBoxContainer.new()
	_footer_row.add_theme_constant_override(&"separation", UITheme.S_2)
	v.add_child(_footer_row)

	_secondary_btn = Button.new()
	_secondary_btn.visible = false
	UITheme.apply_button_variant(_secondary_btn, &"secondary")
	_secondary_btn.pressed.connect(_on_secondary_pressed)
	_footer_row.add_child(_secondary_btn)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_footer_row.add_child(spacer)

	_primary_btn = Button.new()
	_primary_btn.visible = false
	UITheme.apply_button_variant(_primary_btn, &"primary")
	_primary_btn.pressed.connect(_on_primary_pressed)
	_footer_row.add_child(_primary_btn)

func open(data: Dictionary) -> void:
	_title_label.text = String(data.get("title", ""))

	# 旧 content 清理 (调用方丢进来的 Control 抽屉负责释放)。
	if _current_content != null and is_instance_valid(_current_content):
		_current_content.queue_free()
	_current_content = data.get("content", null)
	if _current_content != null:
		_content_holder.add_child(_current_content)

	# Primary
	if data.has("primary"):
		var p: Dictionary = data["primary"]
		_primary_btn.text = String(p.get("label", ""))
		_primary_id = StringName(p.get("action_id", &""))
		_primary_btn.visible = not _primary_btn.text.is_empty()
	else:
		_primary_btn.text = ""
		_primary_id = &""
		_primary_btn.visible = false

	# Secondary
	if data.has("secondary"):
		var s: Dictionary = data["secondary"]
		_secondary_btn.text = String(s.get("label", ""))
		_secondary_id = StringName(s.get("action_id", &""))
		_secondary_btn.visible = not _secondary_btn.text.is_empty()
	else:
		_secondary_btn.text = ""
		_secondary_id = &""
		_secondary_btn.visible = false

	visible = true

func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()

func _on_close_pressed(_id: StringName) -> void:
	close()

func _on_primary_pressed() -> void:
	primary_pressed.emit(_primary_id)

func _on_secondary_pressed() -> void:
	secondary_pressed.emit(_secondary_id)

# ─── 测试 introspection ──────────────────────────────────────

func get_title_text() -> String:
	return _title_label.text if _title_label != null else ""

func is_primary_visible() -> bool:
	return _primary_btn != null and _primary_btn.visible

func is_secondary_visible() -> bool:
	return _secondary_btn != null and _secondary_btn.visible

func click_close_for_test() -> void:
	close()

func click_primary_for_test() -> void:
	if _primary_btn != null and _primary_btn.visible:
		_primary_btn.pressed.emit()

func click_secondary_for_test() -> void:
	if _secondary_btn != null and _secondary_btn.visible:
		_secondary_btn.pressed.emit()
