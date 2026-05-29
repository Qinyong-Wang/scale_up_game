extends SceneTree

## One-shot tool. Run with:
##   godot --headless --path . -s tools/build_translations.gd
##
## 把 resources/i18n/strings.csv 读出来, 按列名为每个 locale 生成一份
## Translation 资源 (res://resources/i18n/strings.<locale>.translation)。
##
## 为什么不用 Godot 编辑器的 csv_translation import 流程:
##   - 测试在 headless 跑, 我们要 .translation 文件提交进库即用,
##     不依赖编辑器 import 阶段产物。
##   - 让 i18n 与 ui_theme 的 build_theme.gd 套路一致, 全靠 tool 脚本
##     从源文件生成产物, 可重现。
##
## CSV 规范 (design/国际化设计.md §3):
##   - 第一行表头, 第一列必须叫 keys, 其余列名 = locale (zh / en / ...)
##   - 空 value 视为未翻译, 不写进 Translation, 让 tr() 走 fallback。
##   - 标准 CSV 转义 (引号包含逗号 / 双引号转义)。

const CSV_PATH := "res://resources/i18n/strings.csv"
# 游戏内容文案 (源中文串当 key, 列 keys,en; 见 国际化设计.md §2bis)。可选。
const CONTENT_CSV_PATH := "res://resources/i18n/content.csv"

# CSV column header -> Godot locale code.
const LOCALE_MAP := {
	"zh": "zh_CN",
	"en": "en",
}

func _init() -> void:
	# strings.csv 必需; content.csv 可选 (阶段 3 才有)。各自产出
	# <basename>.<locale>.translation。
	if not _build_csv(CSV_PATH, "strings"):
		quit(1)
		return
	if FileAccess.file_exists(CONTENT_CSV_PATH):
		if not _build_csv(CONTENT_CSV_PATH, "content"):
			quit(1)
			return
	quit(0)

## 读一个 CSV → 每个 locale 列生成一份 res://resources/i18n/<basename>.<locale>.translation。
## 返回 false = 出错 (调用方 quit(1))。
func _build_csv(csv_path: String, out_basename: String) -> bool:
	if not FileAccess.file_exists(csv_path):
		push_error(csv_path + " not found")
		return false
	var rows := _read_csv(csv_path)
	if rows.is_empty():
		push_error(csv_path + " is empty")
		return false
	var header: PackedStringArray = rows[0]
	if header.size() < 2 or header[0] != "keys":
		push_error("%s 第一列必须是 keys, 实际表头: %s" % [csv_path, str(header)])
		return false

	# 第 i 列对应一个 locale; 收集 column → translation.
	var translations: Dictionary = {}
	for col in range(1, header.size()):
		var col_name: String = header[col]
		var locale: String = LOCALE_MAP.get(col_name, col_name)
		var t := Translation.new()
		t.locale = locale
		translations[col] = t
		print(out_basename, ": locale ", col_name, " -> ", locale)

	# 数据行: 把每个 cell 加入对应 locale 的 Translation。
	for r in range(1, rows.size()):
		var row: PackedStringArray = rows[r]
		if row.is_empty() or row[0].strip_edges().is_empty():
			continue
		# CSV 里写字面 \n 代表换行 (多行文案约定, 见 国际化设计 §3)。key 与 value 同样转,
		# 这样 content 源串里的 \n 与 runtime 加载 .tres 后的真换行一致。
		var key: String = row[0].replace("\\n", "\n")
		for col in translations.keys():
			if col >= row.size():
				continue
			var val: String = row[col]
			if val.is_empty():
				continue  # 空 = 未翻译, 走 fallback
			val = val.replace("\\n", "\n")
			var t: Translation = translations[col]
			t.add_message(key, val)

	# 序列化。
	for col in translations.keys():
		var t: Translation = translations[col]
		var locale: String = t.locale
		var out_path := "res://resources/i18n/%s.%s.translation" % [out_basename, _locale_to_filename(locale)]
		var err := ResourceSaver.save(t, out_path)
		if err != OK:
			push_error("ResourceSaver.save failed for %s: %d" % [out_path, err])
			return false
		print("wrote ", out_path, " (", t.get_message_count(), " messages)")
	return true

func _locale_to_filename(locale: String) -> String:
	# zh_CN -> zh; en -> en. 与 LOCALE_MAP 反向, 文件名保持短码方便人眼识别。
	for col_name in LOCALE_MAP.keys():
		if LOCALE_MAP[col_name] == locale:
			return col_name
	return locale

## 极简 CSV parser, 支持双引号引用与转义 ("")。
func _read_csv(path: String) -> Array:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return []
	var text := f.get_as_text()
	f.close()
	var rows: Array = []
	var row: PackedStringArray = PackedStringArray()
	var cell := ""
	var in_quotes := false
	var i := 0
	var n := text.length()
	while i < n:
		var ch := text[i]
		if in_quotes:
			if ch == "\"":
				if i + 1 < n and text[i + 1] == "\"":
					cell += "\""
					i += 2
					continue
				in_quotes = false
				i += 1
				continue
			cell += ch
			i += 1
			continue
		# 非引号态
		if ch == "\"":
			in_quotes = true
			i += 1
			continue
		if ch == ",":
			row.append(cell)
			cell = ""
			i += 1
			continue
		if ch == "\n":
			row.append(cell)
			rows.append(row)
			row = PackedStringArray()
			cell = ""
			i += 1
			continue
		if ch == "\r":
			i += 1
			continue
		cell += ch
		i += 1
	# 文件末尾如果没换行, flush 最后一行。
	if cell.length() > 0 or row.size() > 0:
		row.append(cell)
		rows.append(row)
	return rows
