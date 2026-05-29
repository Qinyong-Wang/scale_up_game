extends Control

## Avatar — 卡片左上角的头像 / 缩略图。
##
## 真实立绘到位前的占位实现:
##   - 有 texture → 直接贴图。
##   - 无 texture → 按 seed_id 哈希到 HSL 配色, 上面叠首 1-2 字或 glyph。
##
## 不调 tr() — 文案由调用方传入, 已 i18n 化 (国际化设计.md §6)。
## 不持有业务系统引用 (UI视觉系统设计.md §7)。

const _GLYPHS := {
	&"model": "◉",
	&"datacenter": "▣",
	&"lead": "●",
	&"dataset": "▸",
}

# Default 48x48, 调用方可通过 custom_minimum_size / size_flags 覆盖。
const _DEFAULT_SIDE := 48

var _texture: Texture2D
var _fallback_text: String = ""
var _seed_id: StringName = &""
var _kind: StringName = &""

var _bg_panel: ColorRect
var _label: Label
var _texture_rect: TextureRect

func _ready() -> void:
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(_DEFAULT_SIDE, _DEFAULT_SIDE)

	_bg_panel = ColorRect.new()
	_bg_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg_panel.color = UITheme.BG_ELEVATED
	_bg_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg_panel)

	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_color_override(&"font_color", Color.WHITE)
	# 回退 glyph/首字母字号随头像尺寸缩放 — 否则大头像 (160px) 里小字会很别扭。
	_label.add_theme_font_size_override(&"font_size", _glyph_font_size())
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)

	_texture_rect = TextureRect.new()
	_texture_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_texture_rect.visible = false
	add_child(_texture_rect)

	_refresh()

## p_texture: null → 走 seed/text 回退; 非 null → 贴图。
## p_fallback_text: 显示文字源, 空字符串触发 glyph 回退。
## p_seed_id: 颜色随机种子, 同 id 永远同色; 空 id 用中性兜底。
## p_kind: 类型, 用于 fallback_text 空时挑 glyph。
func set_data(p_texture: Texture2D, p_fallback_text: String, p_seed_id: StringName, p_kind: StringName) -> void:
	_texture = p_texture
	_fallback_text = p_fallback_text
	_seed_id = p_seed_id
	_kind = p_kind
	if is_inside_tree():
		_refresh()

func _refresh() -> void:
	if _texture != null:
		_texture_rect.texture = _texture
		_texture_rect.visible = true
		_bg_panel.visible = false
		_label.visible = false
		return
	_texture_rect.visible = false
	_bg_panel.visible = true
	_bg_panel.color = _seed_color(_seed_id)
	_label.visible = true
	_label.text = _display_text(_fallback_text, _kind)

# glyph/首字母字号 ≈ 边长 0.42, 钳在 [FS_MD, 72]; 默认 48px → ~20, 大头像 160px → ~67。
func _glyph_font_size() -> int:
	var side: float = minf(custom_minimum_size.x, custom_minimum_size.y)
	if side <= 0.0:
		side = float(_DEFAULT_SIDE)
	return int(clampf(side * 0.42, float(UITheme.FS_MD), 72.0))

func _seed_color(seed_key: StringName) -> Color:
	if String(seed_key).is_empty():
		return UITheme.BG_ELEVATED
	var h := _stable_hash(String(seed_key))
	var hue := float(h % 360) / 360.0
	return Color.from_hsv(hue, 0.55, 0.55)

# FNV-1a 32-bit — 比 djb2 雪崩更好, 单字符输入也能均匀分布到 360 个色相桶。
func _stable_hash(s: String) -> int:
	var h: int = 2166136261
	for c in s.to_utf8_buffer():
		h = (h ^ c) & 0xFFFFFFFF
		h = (h * 16777619) & 0xFFFFFFFF
	return h

func _display_text(text: String, kind: StringName) -> String:
	if text.is_empty():
		if _GLYPHS.has(kind):
			return _GLYPHS[kind]
		return "?"
	var first := text.substr(0, 1)
	if _is_cjk(first):
		return first
	return text.substr(0, 2).to_upper()

func _is_cjk(s: String) -> bool:
	if s.is_empty():
		return false
	var cp := s.unicode_at(0)
	if cp >= 0x4E00 and cp <= 0x9FFF: return true   # CJK Unified
	if cp >= 0x3400 and cp <= 0x4DBF: return true   # Extension A
	if cp >= 0xF900 and cp <= 0xFAFF: return true   # Compatibility
	if cp >= 0x3040 and cp <= 0x309F: return true   # Hiragana
	if cp >= 0x30A0 and cp <= 0x30FF: return true   # Katakana
	return false

# ─── 测试 introspection ──────────────────────────────────────

func get_displayed_color() -> Color:
	return _bg_panel.color if _bg_panel != null else Color.MAGENTA

func get_displayed_text() -> String:
	return _label.text if _label != null else ""

func is_texture_layer_visible() -> bool:
	return _texture_rect != null and _texture_rect.visible

func is_fallback_layer_visible() -> bool:
	if _bg_panel == null or _label == null:
		return false
	return _bg_panel.visible and _label.visible
