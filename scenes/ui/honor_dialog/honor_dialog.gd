extends AcceptDialog

## HonorDialog — 点击办公室房间里的奖章/奖杯弹出的荣誉信息框。Per design/办公室与收藏系统设计.md §8.1。
##
## 显示荣誉名 (标题) + 描述 + flavor 叙事文案。dialog 不读 GameState;
## main.gd refresh({name, description, flavor}) 接已翻译字符串。

# 内容窄、行数少 → 紧凑框, 高度交给内容自适应 (min y=0), 宽度固定让文案换行可读。
const _CONTENT_W := 360

var _desc: Label
var _flavor: Label

func _ready() -> void:
	min_size = Vector2i(_CONTENT_W + 48, 0)
	get_ok_button().text = tr("ACTION_CLOSE")

	var root := VBoxContainer.new()
	root.add_theme_constant_override(&"separation", UITheme.S_3)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(root)

	_desc = Label.new()
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.custom_minimum_size = Vector2(_CONTENT_W, 0)
	_desc.add_theme_font_size_override(&"font_size", UITheme.FS_MD)
	_desc.add_theme_color_override(&"font_color", UITheme.TEXT_PRIMARY)
	root.add_child(_desc)

	_flavor = Label.new()
	_flavor.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_flavor.custom_minimum_size = Vector2(_CONTENT_W, 0)
	_flavor.add_theme_color_override(&"font_color", UITheme.TEXT_SECONDARY)
	root.add_child(_flavor)

func refresh(data: Dictionary) -> void:
	title = String(data.get("name", ""))
	_desc.text = String(data.get("description", ""))
	_flavor.text = String(data.get("flavor", ""))
	_flavor.visible = not _flavor.text.is_empty()

# ─── 测试 introspection ──────────────────────────────────────

func get_title_for_test() -> String:
	return title

func get_description_text_for_test() -> String:
	return _desc.text

func get_flavor_text_for_test() -> String:
	return _flavor.text
