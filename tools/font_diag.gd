extends SceneTree

## One-shot font diagnostic. Run with:
##   godot --headless --path . -s tools/font_diag.gd
## Loads the configured UI font, checks for specific CJK characters,
## and prints results so we can verify glyph coverage without rendering.

func _init() -> void:
	var path := "res://assets/fonts/cjk.ttf"
	print("=== font diag ===")
	print("path: ", path)
	var res: Resource = load(path)
	print("type: ", res.get_class() if res else "<null>")
	if res == null:
		print("FAIL: load returned null")
		quit(1)
		return

	var font: Font = res
	print("font_name: ", font.get_font_name())
	print("face_count: ", font.get_face_count() if font.has_method("get_face_count") else "n/a")

	var samples := {
		"A (0x0041)": 0x0041,
		"arrow right (0x2192)": 0x2192,
		"warning sign (0x26a0)": 0x26a0,
		"check mark (0x2713)": 0x2713,
		"ellipsis (0x2026)": 0x2026,
		"em dash (0x2014)": 0x2014,
		"middle dot (0x00b7)": 0x00b7,
		"greater equal (0x2265)": 0x2265,
		"multiplication sign (0x00d7)": 0x00d7,
		"sigma (0x03a3)": 0x03a3,
		"almost equal (0x2248)": 0x2248,
		"游 (0x6e38)": 0x6e38,
		"戏 (0x620f)": 0x620f,
		"模 (0x6a21)": 0x6a21,
		"型 (0x578b)": 0x578b,
		"训 (0x8bad)": 0x8bad,
		"练 (0x7ec3)": 0x7ec3,
		"回 (0x56de)": 0x56de,
		"合 (0x5408)": 0x5408,
		"现 (0x73b0)": 0x73b0,
		"金 (0x91d1)": 0x91d1,
	}
	print("--- glyph coverage ---")
	for label in samples:
		var cp: int = samples[label]
		var has := font.has_char(cp)
		print("%s : %s" % [label, "YES" if has else "NO"])

	# Sanity: project setting vs actual font being looked up
	var proj_default: Variant = ProjectSettings.get_setting("gui/theme/default_font")
	print("project default_font setting: ", proj_default)
	print("ThemeDB.set_project_theme: ",
			ClassDB.class_has_method(&"ThemeDB", &"set_project_theme"))
	print("ThemeDB object get_default_theme: ", ThemeDB.has_method(&"get_default_theme"))
	var default_theme: Theme = ThemeDB.get_default_theme()
	print("ThemeDB default theme: ", default_theme.get_class() if default_theme else "<null>")
	if default_theme:
		default_theme.default_font = font
		default_theme.set_font(&"font", &"Label", font)

	# Check if the loaded font is the same as the project default
	if proj_default is Font:
		print("default_font.get_font_name(): ", proj_default.get_font_name())

	var label := Label.new()
	var label_font: Font = label.get_theme_font(&"font")
	print("--- fresh Label theme font ---")
	print("type: ", label_font.get_class() if label_font else "<null>")
	print("font_name: ", label_font.get_font_name() if label_font else "<null>")
	if label_font:
		for label_text in samples:
			var cp2: int = samples[label_text]
			var has2 := label_font.has_char(cp2)
			print("Label %s : %s" % [label_text, "YES" if has2 else "NO"])
	label.free()

	print("=== done ===")
	quit(0)
