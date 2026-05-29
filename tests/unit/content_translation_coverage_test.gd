extends GutTest

## content 翻译覆盖率守护。对应 design/国际化设计.md §2bis + §7。
##
## 扫 resources/data 下所有 .tres 的含中文 (CJK) 双引号串 (= 源串当 key),
## 断言每条都在产物 content.en.translation 里有非空 en。新增 .tres 内容串却忘了
## 翻译 (或忘跑 tools/extract_content_strings.py + build_translations.gd) 会在此失败,
## 列出未翻清单 — 防止游戏内容悄悄漏翻。
##
## 抽取逻辑与 tools/extract_content_strings.py 对齐 (含 CJK 的双引号字面量)。

const DATA_DIR := "res://resources/data"
const CONTENT_EN := "res://resources/i18n/content.en.translation"

func test_every_tres_cjk_string_has_en_translation() -> void:
	var keys := _collect_tres_cjk_strings(DATA_DIR)
	assert_gt(keys.size(), 0, "应当从 .tres 扫到内容串")

	assert_true(ResourceLoader.exists(CONTENT_EN),
		"content.en.translation 必须存在 (跑 tools/build_translations.gd)")
	var t: Translation = load(CONTENT_EN)
	assert_true(t is Translation, "content.en 必须是 Translation 资源")

	var missing: Array = []
	for k in keys:
		var en := String(t.get_message(StringName(k)))
		if en.strip_edges().is_empty():
			missing.append(k)
	assert_eq(missing.size(), 0,
		"%d 条 .tres 内容串在 content.csv 无 en — 跑 extract_content_strings.py 后补译。示例: %s"
			% [missing.size(), str(missing.slice(0, 5))])

# ─── helpers (镜像 extract_content_strings.py) ───────────────────

func _collect_tres_cjk_strings(root: String) -> Array:
	var str_re := RegEx.new()
	str_re.compile("\"((?:[^\"\\\\]|\\\\.)*)\"")
	var cjk_re := RegEx.new()
	cjk_re.compile("[\\x{4e00}-\\x{9fff}]")
	var seen: Dictionary = {}
	_walk(root, str_re, cjk_re, seen)
	return seen.keys()

func _walk(dir_path: String, str_re: RegEx, cjk_re: RegEx, seen: Dictionary) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		var full := dir_path.path_join(name)
		if d.current_is_dir():
			_walk(full, str_re, cjk_re, seen)
		elif name.ends_with(".tres"):
			_scan_file(full, str_re, cjk_re, seen)
		name = d.get_next()
	d.list_dir_end()

func _scan_file(path: String, str_re: RegEx, cjk_re: RegEx, seen: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	while not f.eof_reached():
		var line := f.get_line()
		for m in str_re.search_all(line):
			var s := m.get_string(1)
			if cjk_re.search(s) != null:
				seen[s] = true
	f.close()
