extends AcceptDialog

## HonorDialog — 点击办公室房间里的奖章/奖杯弹出的荣誉信息框。Per design/办公室与收藏系统设计.md §8.1。
##
## 显示荣誉名 (标题) + 可选答案主视觉 + 描述 + flavor 叙事文案。
## dialog 不读 GameState; main.gd refresh({name, description, flavor, answer?}) 接已翻译字符串。

# 内容窄、行数少 → 紧凑框, 高度交给内容自适应 (min y=0), 宽度固定让文案换行可读。
const _CONTENT_W := 420
const _ANSWER_FONT_SIZE := 96

var _answer: Label
var _desc: Label
var _flavor: Label

func _ready() -> void:
	min_size = Vector2i(_CONTENT_W + 48, 0)
	get_ok_button().text = tr("ACTION_CLOSE")

	var root := VBoxContainer.new()
	root.add_theme_constant_override(&"separation", UITheme.S_3)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(root)

	_answer = Label.new()
	_answer.visible = false
	_answer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_answer.add_theme_font_override(&"font", UITheme.get_ui_font_bold())
	_answer.add_theme_font_size_override(&"font_size", _ANSWER_FONT_SIZE)
	_answer.add_theme_color_override(&"font_color", UITheme.ACCENT_INFO)
	_answer.custom_minimum_size = Vector2(_CONTENT_W, 118)
	_answer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(_answer)

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
	_answer.text = String(data.get("answer", ""))
	_answer.visible = not _answer.text.is_empty()
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

func get_answer_text_for_test() -> String:
	return _answer.text

func is_answer_visible_for_test() -> bool:
	return _answer.visible

func get_answer_alignment_for_test() -> HorizontalAlignment:
	return _answer.horizontal_alignment

func get_answer_font_size_for_test() -> int:
	return _answer.get_theme_font_size(&"font_size")
