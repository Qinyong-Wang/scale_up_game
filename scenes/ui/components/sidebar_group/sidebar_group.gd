extends VBoxContainer

## SidebarGroup — 侧栏分组容器。
##
## 顶部 header (group 标题 + 折叠箭头), 下方装一组 SidebarItem。
## 点击 header 切换折叠态; 折叠时子项全部隐藏。

signal collapsed_changed(collapsed: bool)

const _ARROW_EXPANDED := "▾"
const _ARROW_COLLAPSED := "▸"

var _header_button: Button
var _header_arrow: Label
var _header_title: Label
var _items_container: VBoxContainer
var _collapsed: bool = false
# _ready 前调 set_title / add_item 时, 把参数 / 节点存这里。
var _pending_title: String = ""
var _pending_items: Array = []

func _ready() -> void:
	add_theme_constant_override(&"separation", 2)

	_header_button = Button.new()
	_header_button.focus_mode = Control.FOCUS_NONE
	_header_button.flat = true
	_header_button.pressed.connect(_on_header_pressed)
	add_child(_header_button)

	var header_row := HBoxContainer.new()
	header_row.set_anchors_preset(Control.PRESET_FULL_RECT)
	header_row.add_theme_constant_override(&"separation", UITheme.S_2)
	header_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_header_button.add_child(header_row)

	_header_arrow = Label.new()
	_header_arrow.text = _ARROW_EXPANDED
	_header_arrow.add_theme_font_size_override(&"font_size", UITheme.FS_SM)
	_header_arrow.add_theme_color_override(&"font_color", UITheme.TEXT_SECONDARY)
	_header_arrow.custom_minimum_size = Vector2(12, 0)
	header_row.add_child(_header_arrow)

	_header_title = Label.new()
	_header_title.add_theme_font_size_override(&"font_size", UITheme.FS_XS)
	_header_title.add_theme_color_override(&"font_color", UITheme.TEXT_SECONDARY)
	header_row.add_child(_header_title)

	_items_container = VBoxContainer.new()
	_items_container.add_theme_constant_override(&"separation", 2)
	add_child(_items_container)

	if _pending_title != "":
		_header_title.text = _pending_title
		_pending_title = ""
	for it in _pending_items:
		_items_container.add_child(it)
	_pending_items = []

func set_title(title: String) -> void:
	if _header_title == null:
		_pending_title = title.to_upper()
		return
	_header_title.text = title.to_upper()

## 把 SidebarItem 加进 group; 集中通过这个 API 而不是 add_child(), 这样 group
## 才能控制每个 item 的可见性。
##
## 若在 _ready 之前调用 (例如调用方 build sub-tree 然后才挂进 root), 节点存到
## pending 列表里, _ready 时一次性 add 进 _items_container。
func add_item(item: Control) -> void:
	if _items_container == null:
		_pending_items.append(item)
		return
	_items_container.add_child(item)

func set_collapsed(collapsed: bool) -> void:
	if _collapsed == collapsed:
		return
	_collapsed = collapsed
	_header_arrow.text = _ARROW_COLLAPSED if collapsed else _ARROW_EXPANDED
	if _items_container != null:
		_items_container.visible = not collapsed
	collapsed_changed.emit(collapsed)

func is_collapsed() -> bool:
	return _collapsed

func _on_header_pressed() -> void:
	set_collapsed(not _collapsed)

# ─── 测试 introspection ──────────────────────────────────────

func get_title_text() -> String:
	# header 把标题改成大写显示, 但测试关心的是原值; 我们存 upper 后的版本
	# 也无所谓 — 直接返回当前显示文本。调用方传入啥, 测试断啥。
	return _header_title.text if _header_title != null else ""

func click_header_for_test() -> void:
	if _header_button != null:
		_header_button.pressed.emit()
