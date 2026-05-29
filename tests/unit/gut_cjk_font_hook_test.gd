extends GutTest

const HOOK_PATH := "res://tests/support/gut_cjk_font_hook.gd"
const CONFIG_PATH := "res://.gutconfig.json"
const RICH_TEXT_FONT_SLOTS: Array[StringName] = [
	&"font",
	&"normal_font",
	&"bold_font",
	&"italics_font",
	&"bold_italics_font",
]


func test_gut_config_registers_cjk_font_hook() -> void:
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	assert_not_null(file, ".gutconfig.json 必须可读")
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	assert_true(parsed is Dictionary, ".gutconfig.json 必须是 JSON object")
	if not (parsed is Dictionary):
		return
	assert_eq(parsed.get("pre_run_script", ""), HOOK_PATH,
		"GUT 必须在测试前安装 CJK 输出字体 hook")


func test_hook_replaces_gut_rich_text_fonts_with_ui_fonts() -> void:
	assert_true(ResourceLoader.exists(HOOK_PATH),
		"GUT CJK 字体 hook 必须存在: %s" % HOOK_PATH)
	if not ResourceLoader.exists(HOOK_PATH):
		return
	var hook: GutHookScript = load(HOOK_PATH).new()
	var root := Node.new()
	var output := RichTextLabel.new()
	root.add_child(output)

	var plugin_font: Font = load("res://addons/gut/fonts/CourierPrime-Regular.ttf")
	for slot in RICH_TEXT_FONT_SLOTS:
		output.add_theme_font_override(slot, plugin_font)

	hook._apply_to_tree(root, UITheme.get_ui_font(), UITheme.get_ui_font_bold())

	var regular := UITheme.get_ui_font()
	var bold := UITheme.get_ui_font_bold()
	for slot in RICH_TEXT_FONT_SLOTS:
		var expected := bold if String(slot).find("bold") != -1 else regular
		assert_eq(output.get_theme_font(slot).get_font_name(), expected.get_font_name(),
			"%s 应被替换成 UITheme 字体" % String(slot))

	root.free()


func test_hook_replaces_gut_text_edit_font_with_ui_font() -> void:
	assert_true(ResourceLoader.exists(HOOK_PATH),
		"GUT CJK 字体 hook 必须存在: %s" % HOOK_PATH)
	if not ResourceLoader.exists(HOOK_PATH):
		return
	var hook: GutHookScript = load(HOOK_PATH).new()
	var root := Node.new()
	var output := TextEdit.new()
	root.add_child(output)

	var plugin_font: Font = load("res://addons/gut/fonts/CourierPrime-Regular.ttf")
	output.add_theme_font_override(&"font", plugin_font)

	hook._apply_to_tree(root, UITheme.get_ui_font(), UITheme.get_ui_font_bold())

	var regular := UITheme.get_ui_font()
	assert_eq(output.get_theme_font(&"font").get_font_name(), regular.get_font_name(),
		"GUT editor OutputText 使用 TextEdit, 也必须替换为 UITheme 字体")

	root.free()
