extends GutTest

const SOURCE_ROOTS: Array[String] = [
	"res://scripts",
	"res://scenes",
	"res://tests",
]
const RUNTIME_UI_FILES: Array[String] = [
	"res://scenes/main/main.gd",
	"res://scenes/ui/new_datacenter_dialog/new_datacenter_dialog.gd",
]
const KNOWN_INTEGER_DIVISION_SNIPPETS: Dictionary = {
	"res://scenes/ui/views/model_view/model_card.gd": [
		"tokens / 1000000",
		"tokens / 1000",
	],
	"res://scripts/autoload/game_state.gd": [
		"(unix - anchor_unix) / SECONDS_PER_DAY",
	],
}
const KNOWN_UNUSED_PARAMETER_SNIPPETS: Dictionary = {
	"res://scenes/ui/views/event_view/event_view.gd": [
		"event_id: StringName, category: StringName",
	],
	"res://scenes/ui/views/model_view/model_card.gd": [
		"static func _actions(m, status: StringName)",
	],
}

func test_preload_constants_do_not_shadow_global_classes() -> void:
	var global_names: Array[String] = _global_class_names()
	var offenders: Array[String] = []
	for path in _gd_files(SOURCE_ROOTS):
		var text: String = FileAccess.get_file_as_string(path)
		for global_name in global_names:
			var needle: String = "const %s := preload(" % global_name
			if text.contains(needle):
				offenders.append("%s uses `%s`" % [path, needle])
	assert_eq(offenders, [], "用 class_name 注册的资源脚本不要再声明同名 preload 常量。")

func test_custom_signals_use_typed_emit() -> void:
	var offenders: Array[String] = []
	for path in _gd_files(["res://scripts", "res://scenes"]):
		var text: String = FileAccess.get_file_as_string(path)
		for signal_id in _declared_signal_names(text):
			if text.contains("emit_signal(\"%s\"" % signal_id):
				offenders.append("%s emits `%s` through string emit_signal" % [path, signal_id])
	assert_eq(offenders, [], "自定义信号用 signal_name.emit(...) 发射, 避免 UNUSED_SIGNAL 误报。")

func test_node_scripts_do_not_use_name_parameter() -> void:
	var pattern := RegEx.new()
	assert_eq(pattern.compile("func\\s+[^\\(]+\\([^\\)]*\\bname\\s*:"), OK)
	var offenders: Array[String] = []
	for path in _gd_files(SOURCE_ROOTS):
		var text: String = FileAccess.get_file_as_string(path)
		for hit in pattern.search_all(text):
			offenders.append("%s: `%s`" % [path, hit.get_string()])
	assert_eq(offenders, [], "`name` 会遮蔽 Node.name; UI / system / test helper 参数改用 display_name。")

func test_retired_fame_runtime_hooks_are_not_reintroduced() -> void:
	var offenders: Array[String] = []
	for path in RUNTIME_UI_FILES:
		var text: String = FileAccess.get_file_as_string(path)
		for needle in ["EventBus.fame_changed", "GameState.fame", "unlock_fame_required"]:
			if text.contains(needle):
				offenders.append("%s still references `%s`" % [path, needle])
	assert_eq(offenders, [], "v7 PR-F 已删除 fame 字段和信号, HUD / 基建弹窗不能再读旧接口。")

func test_known_integer_divisions_are_explicit() -> void:
	var offenders: Array[String] = []
	for path in KNOWN_INTEGER_DIVISION_SNIPPETS:
		var text: String = FileAccess.get_file_as_string(path)
		for snippet in KNOWN_INTEGER_DIVISION_SNIPPETS[path]:
			if text.contains(String(snippet)):
				offenders.append("%s still has `%s`" % [path, snippet])
	assert_eq(offenders, [], "整数除法必须显式转 float, 或用 floori/roundi 标明取整。")

func test_known_unused_parameters_are_prefixed() -> void:
	var offenders: Array[String] = []
	for path in KNOWN_UNUSED_PARAMETER_SNIPPETS:
		var text: String = FileAccess.get_file_as_string(path)
		for snippet in KNOWN_UNUSED_PARAMETER_SNIPPETS[path]:
			if text.contains(String(snippet)):
				offenders.append("%s still has `%s`" % [path, snippet])
	assert_eq(offenders, [], "未使用参数加 `_` 前缀, 避免 UNUSED_PARAMETER warning。")

# 化名规范 (CLAUDE.md): 真实品牌 (GPT/Llama/Claude/Gemini/NVIDIA/AMD/...) 不出现
# 在 UI 代码 / .tres 的玩家可见字段中。仅 design/ 与代码注释里的 "≈ X" 对照允许。
# 本测试扫 scenes/ui/ 下所有 .gd 文件的字符串字面量, 防 Bug 3 (MyGPT-1) 回归 +
# 后续新 UI 也不漏。
const FORBIDDEN_BRAND_TOKENS: Array[String] = [
	"GPT", "Llama", "LLaMA", "Gemini", "OpenAI", "ChatGPT", "Anthropic",
	"NVIDIA", "Nvidia", "AMD", "Mistral", "DeepSeek",
]
# 已知的"≈ X" 对照注释 — 这些是设计文档式注释, 不暴露给玩家。
const BRAND_COMMENT_WHITELIST: Dictionary = {
	"res://scenes/ui/price_edit_dialog/price_edit_dialog.gd": [
		"GPT/Claude 定价单位",
	],
}

func test_ui_dialogs_do_not_leak_real_brand_names() -> void:
	var offenders: Array[String] = []
	for path in _gd_files(["res://scenes/ui"]):
		var text: String = FileAccess.get_file_as_string(path)
		var whitelist: Array = BRAND_COMMENT_WHITELIST.get(path, []) as Array
		for line in text.split("\n"):
			var stripped := String(line).strip_edges()
			if stripped.is_empty() or stripped.begins_with("#"):
				continue
			var quoted := _strip_inline_comment(stripped)
			for brand in FORBIDDEN_BRAND_TOKENS:
				if not quoted.contains(brand):
					continue
				var whitelisted: bool = false
				for w in whitelist:
					if stripped.contains(String(w)):
						whitelisted = true
						break
				if whitelisted:
					continue
				offenders.append("%s: 含品牌 `%s` → `%s`" % [path, brand, stripped])
	assert_eq(offenders, [],
			"UI .gd 文件不得包含真实品牌名 (玩家可见字段 / placeholder / 按钮文案);" \
			+ " 例外仅限注释 + BRAND_COMMENT_WHITELIST。CLAUDE.md §化名规范。")

# 去掉行尾 `# ...` 注释段, 仅保留代码 + 字符串字面量, 避免误判 ≈X 对照说明。
func _strip_inline_comment(line: String) -> String:
	# 简化扫描: 找第一个 `#`, 如果它前面的字符串里"#" 数量为偶数 (在引号外),
	# 把后面截掉。对 placeholder_text = "MyGPT-1" 这种简单单引号情况已足够;
	# 复杂多引号 / triple-quote 不做精确处理 (我们关心的 UI .gd 文件都是简单的)。
	var in_str: bool = false
	var str_char: String = ""
	for i in range(line.length()):
		var c: String = line[i]
		if in_str:
			if c == str_char:
				in_str = false
		else:
			if c == "\"" or c == "'":
				in_str = true
				str_char = c
			elif c == "#":
				return line.substr(0, i)
	return line

func _global_class_names() -> Array[String]:
	var names: Array[String] = []
	for path in _gd_files(["res://scripts/resources"]):
		var text: String = FileAccess.get_file_as_string(path)
		for line in text.split("\n"):
			var stripped: String = String(line).strip_edges()
			if stripped.begins_with("class_name "):
				var parts := stripped.split(" ", false)
				if parts.size() >= 2:
					names.append(String(parts[1]))
	return names

func _declared_signal_names(text: String) -> Array[String]:
	var names: Array[String] = []
	for line in text.split("\n"):
		var stripped: String = String(line).strip_edges()
		if not stripped.begins_with("signal "):
			continue
		var decl: String = stripped.trim_prefix("signal ").strip_edges()
		var paren_index: int = decl.find("(")
		names.append(decl.substr(0, paren_index) if paren_index >= 0 else decl)
	return names

func _gd_files(roots: Array) -> Array[String]:
	var out: Array[String] = []
	for root in roots:
		_collect_gd_files(String(root), out)
	out.sort()
	return out

func _collect_gd_files(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	assert_not_null(dir, "目录应存在: %s" % dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = dir.get_next()
			continue
		var full_path := dir_path.path_join(entry)
		if dir.current_is_dir():
			_collect_gd_files(full_path, out)
		elif entry.ends_with(".gd"):
			out.append(full_path)
		entry = dir.get_next()
	dir.list_dir_end()
