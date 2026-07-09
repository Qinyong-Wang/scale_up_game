extends GutHookScript

const RICH_TEXT_FONT_SLOTS: Array[StringName] = [
	&"font",
	&"normal_font",
	&"bold_font",
	&"italics_font",
	&"bold_italics_font",
]


func run() -> void:
	# 把测试基线 locale 钉到 zh_CN。游戏首次启动默认 en (国际化设计 §11.3),
	# 但大量既有测试仍断言中文 UI 文案; headless 默认又是 en_US, 不钉住会
	# 产生顺序相关误失败。需要切语言的测试自己 set/restore locale。
	TranslationServer.set_locale("zh_CN")
	UITheme.install()
	var regular := UITheme.get_ui_font()
	var bold := UITheme.get_ui_font_bold()
	if regular == null:
		return
	_apply_to_tree(Engine.get_main_loop().root, regular, bold)


func _apply_to_tree(root: Node, regular: Font, bold: Font) -> void:
	if root == null or regular == null:
		return

	var resolved_bold := bold if bold != null else regular
	if root is RichTextLabel:
		_apply_to_rich_text_label(root as RichTextLabel, regular, resolved_bold)
	elif root is TextEdit:
		(root as TextEdit).add_theme_font_override(&"font", regular)
	elif root is Label:
		(root as Label).add_theme_font_override(&"font", regular)
	elif root is Button:
		(root as Button).add_theme_font_override(&"font", regular)

	for child in root.get_children():
		if child is Node:
			_apply_to_tree(child as Node, regular, resolved_bold)


func _apply_to_rich_text_label(label: RichTextLabel, regular: Font, bold: Font) -> void:
	for slot in RICH_TEXT_FONT_SLOTS:
		var font := bold if String(slot).find("bold") != -1 else regular
		label.add_theme_font_override(slot, font)
