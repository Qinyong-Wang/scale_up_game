extends PanelContainer

## StatChip — 顶栏指标块。
##
## 布局:
##   label xs
##   value base/md + delta xs
##
## 两种视觉变体 (见 design/UI视觉系统设计.md §5):
##   - 默认: Google Cloud Console 式紧凑卡 — 固定最小宽度、白底、细描边 (营收 tab 复用)。
##   - flat (set_flat(true)): 去描边/底色, value 提到 FS_MD, 不裁字 size-to-content;
##     顶栏靠块间竖线分隔成「仪表簇」, flat 块只负责自身的 label/value。

var _label_node: Label
var _value_node: Label
var _delta_node: Label
## flat 变体开关。顶栏 chip 走 flat (仪表簇), 默认 (营收 tab) 保持描边卡。
var _flat := false

func _ready() -> void:
	size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override(&"separation", 0)
	add_child(root)

	_label_node = Label.new()
	_label_node.add_theme_font_size_override(&"font_size", UITheme.FS_XS)
	_label_node.add_theme_color_override(&"font_color", UITheme.TEXT_SECONDARY)
	_label_node.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label_node.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_label_node.clip_text = true
	root.add_child(_label_node)

	var value_row := HBoxContainer.new()
	value_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_row.add_theme_constant_override(&"separation", UITheme.S_1)
	root.add_child(value_row)

	_value_node = Label.new()
	_value_node.add_theme_font_override(&"font", UITheme.get_ui_font_bold())
	_value_node.add_theme_color_override(&"font_color", UITheme.TEXT_PRIMARY)
	_value_node.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value_row.add_child(_value_node)

	_delta_node = Label.new()
	_delta_node.add_theme_font_size_override(&"font_size", UITheme.FS_XS)
	_delta_node.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_delta_node.visible = false
	value_row.add_child(_delta_node)

	_apply_variant()

## 切到 flat 仪表簇变体 (顶栏用)。可在 add_child (即 _ready) 前后调用:
## 前调只置位, _ready 末尾的 _apply_variant 应用; 后调即时重排。
func set_flat(v: bool) -> void:
	if _flat == v and _value_node != null:
		return
	_flat = v
	if _value_node != null:
		_apply_variant()

## 按 _flat 套用最小尺寸 / panel stylebox / value 字号与裁字策略。
func _apply_variant() -> void:
	if _flat:
		# size-to-content: 不强制最小宽 (大额数值撑开而非省略号), 高度交给内容 + 顶栏居中。
		custom_minimum_size = Vector2(custom_minimum_size.x, 0.0)
	else:
		custom_minimum_size = Vector2(maxf(custom_minimum_size.x, 104.0), 36.0)
	add_theme_stylebox_override(&"panel", _make_panel_style())
	if _value_node == null:
		return
	_value_node.add_theme_font_size_override(&"font_size",
		UITheme.FS_MD if _flat else UITheme.FS_BASE)
	if _flat:
		# size-to-content: value 与 label 都不裁字, 否则 clip_text=true 会把该块的
		# 最小宽压成 0, chip 只按更短的一边收宽, 把更长的 label/value 截掉
		# (曾把 "已发布"→"已发"、"付费用户" label 整条吞掉)。
		_value_node.clip_text = false
		_value_node.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
		_value_node.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		if _label_node != null:
			_label_node.clip_text = false
			_label_node.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	else:
		_value_node.clip_text = true
		_value_node.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_value_node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if _label_node != null:
			_label_node.clip_text = true
			_label_node.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	# 文字颜色随明暗上下文: flat = 顶栏深色玻璃 → on-dark 浅色; 默认卡 → 工作区深灰。
	if _label_node != null:
		_label_node.add_theme_color_override(&"font_color",
			UITheme.TEXT_ON_DARK_SECONDARY if _flat else UITheme.TEXT_SECONDARY)
	# set_flat 可能在 set_data 之后调用 (运行时切变体): 已有文案就重算 value 颜色。
	if _value_node.text != "":
		_value_node.add_theme_color_override(&"font_color",
			_infer_value_color(_label_node.text if _label_node != null else "", _value_node.text))

func _make_panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	if _flat:
		# 仪表簇: 透明无边框, 只留左右内边距给块间竖线呼吸。
		sb.bg_color = Color(0, 0, 0, 0)
		sb.set_border_width_all(0)
		sb.content_margin_left = UITheme.S_2
		sb.content_margin_right = UITheme.S_2
		sb.content_margin_top = 0
		sb.content_margin_bottom = 0
		return sb
	sb.bg_color = UITheme.BG_SURFACE
	sb.border_color = UITheme.BORDER_SUBTLE
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.corner_radius_top_left = UITheme.R_SM
	sb.corner_radius_top_right = UITheme.R_SM
	sb.corner_radius_bottom_right = UITheme.R_SM
	sb.corner_radius_bottom_left = UITheme.R_SM
	sb.content_margin_left = UITheme.S_2
	sb.content_margin_right = UITheme.S_2
	sb.content_margin_top = UITheme.S_1
	sb.content_margin_bottom = UITheme.S_1
	return sb

func set_data(label_text: String, value_text: String, delta: float, delta_text: String) -> void:
	if _label_node != null:
		_label_node.text = label_text
	if _value_node != null:
		_value_node.text = value_text
		_value_node.add_theme_color_override(&"font_color",
			_infer_value_color(label_text, value_text))
	if _delta_node == null:
		return
	if is_nan(delta):
		_delta_node.visible = false
		_delta_node.text = ""
		return
	_delta_node.visible = true
	_delta_node.text = delta_text
	var color: Color
	if delta > 0.0:
		color = UITheme.ACCENT_PRIMARY_ON_DARK if _flat else UITheme.ACCENT_PRIMARY
	elif delta < 0.0:
		color = UITheme.ACCENT_DANGER_ON_DARK if _flat else UITheme.ACCENT_DANGER
	else:
		color = UITheme.TEXT_ON_DARK_SECONDARY if _flat else UITheme.TEXT_SECONDARY
	_delta_node.add_theme_color_override(&"font_color", color)

# label_text 是已翻译文案 (main.gd 传 tr("TOPBAR_CASH") 等), 故按 key 的 tr 值比对,
# 中英文都成立 — 不再写死中文。
func _infer_value_color(label_text: String, value_text: String) -> Color:
	# flat = 顶栏深色玻璃 → on-dark 档 (浅色); 默认卡 → 工作区深色档。
	var danger: Color = UITheme.ACCENT_DANGER_ON_DARK if _flat else UITheme.ACCENT_DANGER
	var primary: Color = UITheme.ACCENT_PRIMARY_ON_DARK if _flat else UITheme.ACCENT_PRIMARY
	var neutral: Color = UITheme.TEXT_ON_DARK_SECONDARY if _flat else UITheme.TEXT_SECONDARY
	var default_c: Color = UITheme.TEXT_ON_DARK if _flat else UITheme.TEXT_PRIMARY
	if label_text == tr("TOPBAR_CASH") and value_text.find("$-") != -1:
		return danger
	if label_text == tr("TOPBAR_NET_CASHFLOW"):
		if value_text.begins_with("+"):
			return primary
		if value_text.begins_with("-"):
			return danger
		return neutral
	return default_c

# ─── 测试 introspection ──────────────────────────────────────

## 给老代码与测试的兼容口子: 直接拿到内部 value Label, 可以读 .text 或临时
## 越过 set_data 直接改文字。但**优先用 set_data**, 这个 getter 只是过渡。
func get_value_label() -> Label:
	return _value_node

func get_label_text() -> String:
	return _label_node.text if _label_node != null else ""

func get_value_text() -> String:
	return _value_node.text if _value_node != null else ""

func get_delta_text() -> String:
	return _delta_node.text if _delta_node != null else ""

func is_delta_visible() -> bool:
	return _delta_node != null and _delta_node.visible

func get_delta_color() -> Color:
	if _delta_node == null:
		return Color.MAGENTA
	return _delta_node.get_theme_color(&"font_color")
