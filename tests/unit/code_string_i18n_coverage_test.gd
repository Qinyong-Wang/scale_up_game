extends GutTest

## 代码里写死的中文 UI 串守护。对应 design/国际化设计.md §6ter。
##
## content_translation_coverage_test 只扫 .tres; 代码 (scripts/ + scenes/) 里写死的
## 人面中文串 (账本分类 / 任务修正项 / DC 名 / 出身名 ...) 没有任何守护 —— 正是事件后果
## 预览、账本分类、DC 名当初漏翻的盲区。本测试扫所有 .gd 的中文字符串字面量, 断言每条
## 要么可翻译 (= strings.csv 的 zh 列 / content.csv 的 key), 要么在 allowlist (设计上
## 故意不翻)。新写死一句中文 UI 文案却忘了走 tr/key 时, 这里会失败并列出清单。

const SCAN_DIRS := ["res://scripts", "res://scenes"]
const STRINGS_CSV := "res://resources/i18n/strings.csv"
const CONTENT_CSV := "res://resources/i18n/content.csv"

# 整文件跳过: 中文数据池 (运行时由 NameRomanizer 转拼音, 非 UI 文案, 见 §12)。
const SKIP_FILES := {
	"name_romanizer.gd": true,
	"person_name.gd": true,
}

# 故意不翻的写死中文 (设计有据, 见 国际化设计.md §故意不翻):
const ALLOWLIST := {
	"创始人": true,                # 默认开局名 (种子数据)
	"中文": true,                  # 语言按钮本族文字
	# 截图夹具 (仅 AGI_SHOT_* / AGI_OPEN_DRAWER 下构造, 不进实战 UI)
	"微型星球算力中心": true,
	"Cedar 接口": true, "Cedar 聊天助手": true,
	"Maple 接口": true, "Maple 编程助手": true,
}

var _str_re: RegEx
var _cjk_re: RegEx

func before_all() -> void:
	_str_re = RegEx.new()
	_str_re.compile("\"((?:[^\"\\\\]|\\\\.)*)\"")
	_cjk_re = RegEx.new()
	_cjk_re.compile("[\\x{4e00}-\\x{9fff}]")

func test_no_untranslatable_hardcoded_cjk_in_code() -> void:
	var translatable := _load_translatable()
	assert_gt(translatable.size(), 0, "应能从 CSV 读出可翻译串")
	var offenders: Array = []
	for d in SCAN_DIRS:
		_scan(d, translatable, offenders)
	assert_eq(offenders.size(), 0,
		"%d 条代码里写死的中文 UI 串未翻译 (改成 strings.csv 语义 key、或确属故意不翻则加 allowlist):\n%s"
			% [offenders.size(), "\n".join(PackedStringArray(offenders))])

# ─── 可翻译串集合 (strings.csv zh 列 + content.csv key) ───────────────

func _load_translatable() -> Dictionary:
	var out: Dictionary = {}
	for row in _read_csv(CONTENT_CSV):       # content.csv: key 列即中文源串
		if row.size() >= 1 and _cjk_re.search(row[0]) != null:
			out[row[0]] = true
	for row in _read_csv(STRINGS_CSV):       # strings.csv: zh 列 (index 1)
		if row.size() >= 2 and _cjk_re.search(row[1]) != null:
			out[row[1]] = true
	return out

func _read_csv(path: String) -> Array:
	var rows: Array = []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return rows
	while not f.eof_reached():
		rows.append(f.get_csv_line())  # Godot 原生 CSV 解析 (处理引号/逗号转义)
	f.close()
	return rows

# ─── 扫描 .gd ─────────────────────────────────────────────────────

func _scan(dir_path: String, translatable: Dictionary, offenders: Array) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		var full := dir_path.path_join(name)
		if d.current_is_dir():
			_scan(full, translatable, offenders)
		elif name.ends_with(".gd") and not SKIP_FILES.has(name):
			_scan_file(full, translatable, offenders)
		name = d.get_next()
	d.list_dir_end()

func _scan_file(path: String, translatable: Dictionary, offenders: Array) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var lineno := 0
	while not f.eof_reached():
		var line := f.get_line()
		lineno += 1
		var code := _strip_comment(line)
		# 开发者向 / 非 UI 行: 日志、调试打印、隐藏 tab 节点名 (索引用)、
		# _sanitize_tech_text 的英文→中文替换表 (locale 守护过, 属内容层)。
		if code.find("Log.") != -1 or code.find("print(") != -1:
			continue
		if code.find("_make_tab(") != -1 or code.find("\"tab\":") != -1:
			continue
		if code.find("out = out.replace(") != -1:
			continue
		for m in _str_re.search_all(code):
			var lit := m.get_string(1)
			if _cjk_re.search(lit) == null:
				continue
			if translatable.has(lit) or ALLOWLIST.has(lit):
				continue
			offenders.append("%s:%d  \"%s\"" % [path, lineno, lit])
	f.close()

## 截掉行内注释 (字符串外的第一个 #), 保留代码部分。逐字符跟踪是否在双引号串内,
## 处理 \" 转义, 避免把字符串里的 # 当成注释。
func _strip_comment(line: String) -> String:
	var in_str := false
	var i := 0
	while i < line.length():
		var c := line[i]
		if c == "\\" and in_str:
			i += 2
			continue
		if c == "\"":
			in_str = not in_str
		elif c == "#" and not in_str:
			return line.substr(0, i)
		i += 1
	return line
