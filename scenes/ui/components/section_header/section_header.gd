extends HBoxContainer

## SectionHeader — 主区每个 section 的标题条。
##
## 布局: [title FS_LG] [count FS_SM secondary] ──── [action_button]
##
## 直接继承 HBoxContainer 让最小尺寸从子节点冒泡, 否则在父 Container 里会被
## 压扁导致内容看不到。

signal action_pressed(action_id: StringName)

var _title_node: Label
var _count_node: Label
var _action_button: Button
var _action_id: StringName = &""

# 在 _ready 跑之前调 set_data 时, 把参数存起来等 _ready 后再 apply。
var _pending_data: Array = []   # [title, count, action_text, action_id] 或空

func _ready() -> void:
	add_theme_constant_override(&"separation", UITheme.S_3)
	custom_minimum_size.y = max(custom_minimum_size.y, 32)

	_title_node = Label.new()
	_title_node.add_theme_font_override(&"font", UITheme.get_ui_font_bold())
	_title_node.add_theme_font_size_override(&"font_size", UITheme.FS_LG)
	_title_node.add_theme_color_override(&"font_color", UITheme.TEXT_PRIMARY)
	_title_node.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_title_node)

	_count_node = Label.new()
	_count_node.add_theme_font_size_override(&"font_size", UITheme.FS_SM)
	_count_node.add_theme_color_override(&"font_color", UITheme.TEXT_SECONDARY)
	_count_node.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_count_node.visible = false
	add_child(_count_node)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(spacer)

	_action_button = Button.new()
	_action_button.visible = false
	UITheme.apply_button_variant(_action_button, &"create")
	_action_button.pressed.connect(_on_action_pressed)
	add_child(_action_button)

	if not _pending_data.is_empty():
		var d := _pending_data
		_pending_data = []
		set_data(d[0], d[1], d[2], d[3])

func set_data(title: String, count: int, action_text: String, action_id: StringName) -> void:
	# 在 _ready 跑之前调用时 (例如 instantiate 后立即 set_data 但还没 add_child),
	# 内部节点是 null。先把参数记下来, _ready 时补 apply。
	if _title_node == null:
		_pending_data = [title, count, action_text, action_id]
		return
	_title_node.text = title
	if count >= 0:
		_count_node.text = str(count)
		_count_node.visible = true
	else:
		_count_node.text = ""
		_count_node.visible = false
	_action_id = action_id
	if action_text.is_empty():
		_action_button.visible = false
		_action_button.text = ""
	else:
		_action_button.visible = true
		_action_button.text = action_text

func _on_action_pressed() -> void:
	if not is_inside_tree():
		return
	call_deferred(&"_emit_action_pressed_deferred")

func _emit_action_pressed_deferred() -> void:
	if not is_inside_tree():
		return
	action_pressed.emit(_action_id)

# ─── 测试 introspection ──────────────────────────────────────

func get_title_text() -> String:
	return _title_node.text if _title_node != null else ""

func get_count_text() -> String:
	return _count_node.text if _count_node != null else ""

func is_count_visible() -> bool:
	return _count_node != null and _count_node.visible

func is_action_visible() -> bool:
	return _action_button != null and _action_button.visible

func click_action_for_test() -> void:
	if _action_button != null and _action_button.visible:
		_action_button.pressed.emit()
