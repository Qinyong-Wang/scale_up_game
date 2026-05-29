extends PanelContainer

## Badge — 状态徽章。
##
## 继承 PanelContainer 让最小尺寸从子 Label 冒泡; 否则在父 HBox 里被压扁
## 不显示文字。
##
## 用在卡片 header 右侧、表格行、tooltip 等地方显示模型状态 / 任务状态 /
## 数据中心容量等小标签。颜色由 kind 决定, 文案由调用方传入 (国际化设计.md §6)。

# kind → (bg color, fg color) 映射, 全部引用 UITheme 单一事实源。
# pretrained / posttrained 都用中性色 (尚未评估, 无价值表达);
# evaluated / published 用主色 (有价值);
# training 用 info 色 (进行中);
# warning / danger 走警示色。
var _KIND_BG: Dictionary = {}
var _KIND_FG: Dictionary = {}

func _init_kind_tables() -> void:
	if not _KIND_BG.is_empty():
		return
	# posttrained 用比 pretrained 略亮一档的中性色 (在 BG_ELEVATED 和
	# BORDER_STRONG 之间插一档), 这是当前唯一不在 UITheme 调色板里的颜色;
	# 后续若需要加进 token 表再回头收。
	var posttrained_color := Color(0.282, 0.318, 0.357, 1.0)
	_KIND_BG = {
		&"neutral":     UITheme.BG_ELEVATED,
		&"pretrained":  UITheme.BG_ELEVATED,
		&"posttrained": posttrained_color,
		&"evaluated":   UITheme.ACCENT_INFO,
		&"published":   UITheme.ACCENT_PRIMARY,
		&"training":    UITheme.ACCENT_INFO,
		&"idle":        UITheme.BG_ELEVATED,
		&"warning":     UITheme.ACCENT_WARNING,
		&"danger":      UITheme.ACCENT_DANGER,
		&"info":        UITheme.ACCENT_INFO,
	}
	_KIND_FG = {
		&"neutral":     UITheme.TEXT_PRIMARY,
		&"pretrained":  UITheme.TEXT_PRIMARY,
		&"posttrained": UITheme.TEXT_PRIMARY,
		&"idle":        UITheme.TEXT_PRIMARY,
	}

var _bg: StyleBoxFlat
var _label: Label
var _kind: StringName = &"neutral"

func _ready() -> void:
	_init_kind_tables()
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	size_flags_vertical = Control.SIZE_SHRINK_CENTER

	_bg = StyleBoxFlat.new()
	_bg.corner_radius_top_left = UITheme.R_SM
	_bg.corner_radius_top_right = UITheme.R_SM
	_bg.corner_radius_bottom_left = UITheme.R_SM
	_bg.corner_radius_bottom_right = UITheme.R_SM
	_bg.content_margin_left = UITheme.S_2
	_bg.content_margin_right = UITheme.S_2
	_bg.content_margin_top = 2
	_bg.content_margin_bottom = 2
	add_theme_stylebox_override(&"panel", _bg)

	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override(&"font_size", UITheme.FS_XS)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)

	_apply_kind(_kind)

func set_data(label_text: String, kind: StringName) -> void:
	_kind = kind
	if _label != null:
		_label.text = label_text
	_apply_kind(kind)

func _apply_kind(kind: StringName) -> void:
	if _bg == null:
		return
	var bg: Color = _KIND_BG.get(kind, _KIND_BG[&"neutral"])
	var fg: Color = _KIND_FG.get(kind, Color.WHITE)
	_bg.bg_color = bg
	if _label != null:
		_label.add_theme_color_override(&"font_color", fg)

# ─── 测试 introspection ──────────────────────────────────────

func get_label_text() -> String:
	return _label.text if _label != null else ""

func get_background_color() -> Color:
	return _bg.bg_color if _bg != null else Color.MAGENTA
