extends SceneTree

## One-shot tool. Run with:
##   godot --headless --path . -s tools/build_theme.gd
##
## 生成 res://resources/ui/theme.tres, 把 design/UI视觉系统设计.md §2 的视觉
## token 装成 Godot Theme 资源。生成结果通过 ResourceSaver 序列化, 浮点值与
## 运行时 Color("#hex") 字节一致, 测试可以用严格 == 断言。
##
## 不在运行时调用; UITheme.install() 在启动时 load() 这份 .tres 后 merge 进
## ThemeDB.default_theme。

const UITheme_ := preload("res://scripts/autoload/ui_theme.gd")

const OUT_PATH := "res://resources/ui/theme.tres"

func _init() -> void:
	# 直接读 UITheme 脚本里的常量, 保持单一事实源。
	var theme := Theme.new()

	# ─── PanelContainer / Panel: 白色卡片面 ─────────────────
	var card_sb := _make_card_stylebox()
	theme.set_stylebox(&"panel", &"PanelContainer", card_sb)
	theme.set_stylebox(&"panel", &"Panel", card_sb.duplicate())

	# ─── Label ───────────────────────────────────────────────
	theme.set_color(&"font_color", &"Label", UITheme_.TEXT_PRIMARY)
	theme.set_color(&"font_outline_color", &"Label", UITheme_.BG_BASE)
	theme.set_constant(&"outline_size", &"Label", 0)

	# ─── Button ──────────────────────────────────────────────
	# 浅色下 pressed/focus 用 BG_ELEVATED 跟 BG_SURFACE 太接近, 按一下看不出反馈;
	# 这里用 BG_SURFACE.lerp(ACCENT_INFO, ...) 混出"刚按过"的灰黑调, pressed 再用
	# 1px top/bottom content nudge 做下压感, focus 也走填充态避免白底上按钮被剥成光板。
	var pressed_bg: Color = UITheme_.BG_SURFACE.lerp(UITheme_.ACCENT_INFO, 0.16)
	var focus_bg:   Color = UITheme_.BG_SURFACE.lerp(UITheme_.ACCENT_INFO, 0.05)
	theme.set_stylebox(&"normal",   &"Button", _btn_box(UITheme_.BG_SURFACE,  UITheme_.BORDER_SUBTLE))
	theme.set_stylebox(&"hover",    &"Button", _btn_box(UITheme_.BG_ELEVATED, UITheme_.BORDER_STRONG))
	theme.set_stylebox(&"pressed",  &"Button", _btn_box(pressed_bg,           UITheme_.ACCENT_INFO, true))
	theme.set_stylebox(&"disabled", &"Button", _btn_box(UITheme_.BG_SURFACE,  UITheme_.BORDER_SUBTLE))
	theme.set_stylebox(&"focus",    &"Button", _focus_box_filled(focus_bg, UITheme_.ACCENT_INFO))
	theme.set_color(&"font_color",          &"Button", UITheme_.TEXT_PRIMARY)
	theme.set_color(&"font_hover_color",    &"Button", UITheme_.TEXT_PRIMARY)
	theme.set_color(&"font_hover_pressed_color", &"Button", UITheme_.TEXT_PRIMARY)
	theme.set_color(&"font_pressed_color",  &"Button", UITheme_.ACCENT_INFO)
	theme.set_color(&"font_focus_color",    &"Button", UITheme_.TEXT_PRIMARY)
	theme.set_color(&"font_disabled_color", &"Button", UITheme_.TEXT_DISABLED)

	# ─── LineEdit / TextEdit: 输入框 ─────────────────────────
	var input_normal := _input_box(UITheme_.BG_ELEVATED, UITheme_.BORDER_SUBTLE)
	var input_focus  := _input_box(UITheme_.BG_ELEVATED, UITheme_.ACCENT_INFO)
	theme.set_stylebox(&"normal", &"LineEdit", input_normal)
	theme.set_stylebox(&"focus",  &"LineEdit", input_focus)
	theme.set_color(&"font_color",             &"LineEdit", UITheme_.TEXT_PRIMARY)
	theme.set_color(&"font_placeholder_color", &"LineEdit", UITheme_.TEXT_SECONDARY)
	theme.set_color(&"caret_color",            &"LineEdit", UITheme_.ACCENT_INFO)
	theme.set_color(&"selection_color",        &"LineEdit", UITheme_.ACCENT_INFO)
	theme.set_stylebox(&"normal", &"TextEdit", input_normal.duplicate())
	theme.set_stylebox(&"focus",  &"TextEdit", input_focus.duplicate())
	theme.set_color(&"font_color", &"TextEdit", UITheme_.TEXT_PRIMARY)

	# ─── ProgressBar ─────────────────────────────────────────
	theme.set_stylebox(&"background", &"ProgressBar", _bar_bg())
	theme.set_stylebox(&"fill",       &"ProgressBar", _bar_fill())

	# ─── TabContainer / ScrollContainer: 透明 panel ──────────
	# Godot 默认 TabContainer / ScrollContainer 的 panel stylebox 是深灰, 在
	# 浅色主题下会穿透父 PanelContainer 的 BG_BASE。这里改成与 BG_BASE 同色
	# 的填充, 让主区背景从父面板平滑延伸进来。
	theme.set_stylebox(&"panel", &"TabContainer",    _flat(UITheme_.BG_BASE))
	theme.set_stylebox(&"panel", &"ScrollContainer", _flat(UITheme_.BG_BASE))

	# ─── HSeparator / VSeparator: 浅色下用 BORDER_SUBTLE 实线 ─
	theme.set_stylebox(&"separator", &"HSeparator", _separator_line(UITheme_.BORDER_SUBTLE))
	theme.set_stylebox(&"separator", &"VSeparator", _separator_line(UITheme_.BORDER_SUBTLE))

	# ─── Window / AcceptDialog / ConfirmationDialog ────────
	# Godot 默认 Window panel 是深灰, 在浅色主题下整个 modal 会"穿底"。给 Window
	# (以及它的子类 AcceptDialog / ConfirmationDialog / FileDialog) 一份浅色面板,
	# 同时把标题字色锚到 TEXT_PRIMARY, modal 整体就跟主区一致了。
	var window_panel := _window_panel()
	var window_border := _window_embedded_border()
	var close_icon := _make_close_icon()
	for window_type in [&"Window", &"AcceptDialog", &"ConfirmationDialog", &"FileDialog", &"PopupPanel"]:
		theme.set_stylebox(&"panel", window_type, window_panel.duplicate())
		theme.set_stylebox(&"embedded_border", window_type, window_border.duplicate())
		theme.set_stylebox(&"embedded_unfocused_border", window_type, window_border.duplicate())
		theme.set_color(&"title_color", window_type, UITheme_.TEXT_PRIMARY)
		# Godot 默认 title 字号偏小, CJK 字体在小号下 anti-alias 偏灰; 升到 FS_MD 确保
		# 标题在浅色面板上清晰。
		theme.set_constant(&"title_height", window_type, UITheme_.BUTTON_H)
		theme.set_font_size(&"title_font_size", window_type, UITheme_.FS_MD)
		# 关闭键 icon 默认是白 X (深色主题), 浅色下不可见。用程序生成的深色 X 覆盖。
		theme.set_icon(&"close", window_type, close_icon)
		theme.set_icon(&"close_pressed", window_type, close_icon)

	# ─── CheckBox / CheckButton: 字色锚定 + 浅色安全图标 ─────
	var checkbox_checked := _make_checkbox_icon(true, false)
	var checkbox_unchecked := _make_checkbox_icon(false, false)
	var checkbox_checked_disabled := _make_checkbox_icon(true, true)
	var checkbox_unchecked_disabled := _make_checkbox_icon(false, true)
	var switch_checked := _make_switch_icon(true, false)
	var switch_unchecked := _make_switch_icon(false, false)
	var switch_checked_disabled := _make_switch_icon(true, true)
	var switch_unchecked_disabled := _make_switch_icon(false, true)
	for cb_type in [&"CheckBox", &"CheckButton"]:
		theme.set_color(&"font_color",         cb_type, UITheme_.TEXT_PRIMARY)
		theme.set_color(&"font_hover_color",   cb_type, UITheme_.TEXT_PRIMARY)
		theme.set_color(&"font_hover_pressed_color", cb_type, UITheme_.TEXT_PRIMARY)
		theme.set_color(&"font_pressed_color", cb_type, UITheme_.ACCENT_INFO)
		theme.set_color(&"font_disabled_color", cb_type, UITheme_.TEXT_DISABLED)
		theme.set_color(&"font_focus_color",   cb_type, UITheme_.TEXT_PRIMARY)
	theme.set_icon(&"checked", &"CheckBox", checkbox_checked)
	theme.set_icon(&"unchecked", &"CheckBox", checkbox_unchecked)
	theme.set_icon(&"checked_disabled", &"CheckBox", checkbox_checked_disabled)
	theme.set_icon(&"unchecked_disabled", &"CheckBox", checkbox_unchecked_disabled)
	theme.set_icon(&"checked", &"CheckButton", switch_checked)
	theme.set_icon(&"unchecked", &"CheckButton", switch_unchecked)
	theme.set_icon(&"checked_disabled", &"CheckButton", switch_checked_disabled)
	theme.set_icon(&"unchecked_disabled", &"CheckButton", switch_unchecked_disabled)
	theme.set_icon(&"checked_mirrored", &"CheckButton", switch_checked)
	theme.set_icon(&"unchecked_mirrored", &"CheckButton", switch_unchecked)
	theme.set_icon(&"checked_disabled_mirrored", &"CheckButton", switch_checked_disabled)
	theme.set_icon(&"unchecked_disabled_mirrored", &"CheckButton", switch_unchecked_disabled)

	# ─── OptionButton / MenuButton: 复用 Button 状态箱 + 字色 ─
	for ob_type in [&"OptionButton", &"MenuButton"]:
		theme.set_stylebox(&"normal",   ob_type, _btn_box(UITheme_.BG_SURFACE,  UITheme_.BORDER_SUBTLE))
		theme.set_stylebox(&"hover",    ob_type, _btn_box(UITheme_.BG_ELEVATED, UITheme_.BORDER_STRONG))
		theme.set_stylebox(&"pressed",  ob_type, _btn_box(pressed_bg,           UITheme_.ACCENT_INFO, true))
		theme.set_stylebox(&"disabled", ob_type, _btn_box(UITheme_.BG_SURFACE,  UITheme_.BORDER_SUBTLE))
		theme.set_stylebox(&"focus",    ob_type, _focus_box_filled(focus_bg, UITheme_.ACCENT_INFO))
		theme.set_color(&"font_color",         ob_type, UITheme_.TEXT_PRIMARY)
		theme.set_color(&"font_hover_color",   ob_type, UITheme_.TEXT_PRIMARY)
		theme.set_color(&"font_hover_pressed_color", ob_type, UITheme_.TEXT_PRIMARY)
		theme.set_color(&"font_pressed_color", ob_type, UITheme_.ACCENT_INFO)
		theme.set_color(&"font_focus_color",   ob_type, UITheme_.TEXT_PRIMARY)
		theme.set_color(&"font_disabled_color", ob_type, UITheme_.TEXT_DISABLED)
		# item icon 素材是 128px 方图, 不约束会把收起的下拉按钮撑高; 压到 ~20px 行高。
		theme.set_constant(&"icon_max_width", ob_type, UITheme_.S_5)

	# ─── PopupMenu (OptionButton 弹出列表) ─────────────────
	theme.set_stylebox(&"panel",     &"PopupMenu", _window_panel())
	theme.set_stylebox(&"hover",     &"PopupMenu", _flat(UITheme_.ACCENT_INFO_SUBTLE))
	theme.set_stylebox(&"selected",  &"PopupMenu", _flat(UITheme_.ACCENT_INFO_SUBTLE))
	theme.set_color(&"font_color",            &"PopupMenu", UITheme_.TEXT_PRIMARY)
	theme.set_color(&"font_hover_color",      &"PopupMenu", UITheme_.TEXT_PRIMARY)
	theme.set_color(&"font_selected_color",   &"PopupMenu", UITheme_.TEXT_PRIMARY)
	theme.set_color(&"font_selected_hover_color", &"PopupMenu", UITheme_.TEXT_PRIMARY)
	theme.set_color(&"font_disabled_color",   &"PopupMenu", UITheme_.TEXT_DISABLED)
	theme.set_color(&"font_separator_color",  &"PopupMenu", UITheme_.TEXT_SECONDARY)
	theme.set_color(&"font_accelerator_color", &"PopupMenu", UITheme_.TEXT_SECONDARY)
	# 下拉项里的 128px 素材同样要压, 否则每项被图标撑成上百像素高。
	theme.set_constant(&"icon_max_width", &"PopupMenu", UITheme_.S_5)

	# ─── 序列化 ──────────────────────────────────────────────
	var dir := OUT_PATH.get_base_dir()
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir)):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var err := ResourceSaver.save(theme, OUT_PATH)
	if err != OK:
		push_error("ResourceSaver.save failed: %d" % err)
		quit(1)
		return
	print("theme.tres written to ", OUT_PATH)
	quit(0)

# ─── 工厂函数 ──────────────────────────────────────────────

func _make_card_stylebox() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = UITheme_.BG_SURFACE
	sb.border_color = UITheme_.BORDER_SUBTLE
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.corner_radius_top_left = UITheme_.R_MD
	sb.corner_radius_top_right = UITheme_.R_MD
	sb.corner_radius_bottom_left = UITheme_.R_MD
	sb.corner_radius_bottom_right = UITheme_.R_MD
	sb.content_margin_left = UITheme_.S_4
	sb.content_margin_top = UITheme_.S_3
	sb.content_margin_right = UITheme_.S_4
	sb.content_margin_bottom = UITheme_.S_3
	return sb

func _btn_box(bg: Color, border: Color, pressed_nudge: bool = false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.corner_radius_top_left = UITheme_.R_SM
	sb.corner_radius_top_right = UITheme_.R_SM
	sb.corner_radius_bottom_left = UITheme_.R_SM
	sb.corner_radius_bottom_right = UITheme_.R_SM
	sb.content_margin_left = UITheme_.S_3
	sb.content_margin_top = UITheme_.S_2 + 1 if pressed_nudge else UITheme_.S_2
	sb.content_margin_right = UITheme_.S_3
	sb.content_margin_bottom = UITheme_.S_2 - 1 if pressed_nudge else UITheme_.S_2
	return sb

func _focus_box(border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_color = border
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.corner_radius_top_left = UITheme_.R_SM
	sb.corner_radius_top_right = UITheme_.R_SM
	sb.corner_radius_bottom_left = UITheme_.R_SM
	sb.corner_radius_bottom_right = UITheme_.R_SM
	return sb

func _focus_box_filled(bg: Color, border: Color) -> StyleBoxFlat:
	# focus 走 filled 版本: 给 bg 一点淡蓝, 这样焦点态既能从 normal 区分, 也能让按钮
	# 在 BG_SURFACE 父面板上仍可见 (透明 focus 在白底上会把按钮"剥成"光板)。
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.corner_radius_top_left = UITheme_.R_SM
	sb.corner_radius_top_right = UITheme_.R_SM
	sb.corner_radius_bottom_left = UITheme_.R_SM
	sb.corner_radius_bottom_right = UITheme_.R_SM
	sb.content_margin_left = UITheme_.S_3
	sb.content_margin_top = UITheme_.S_2
	sb.content_margin_right = UITheme_.S_3
	sb.content_margin_bottom = UITheme_.S_2
	return sb

func _input_box(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.corner_radius_top_left = UITheme_.R_SM
	sb.corner_radius_top_right = UITheme_.R_SM
	sb.corner_radius_bottom_left = UITheme_.R_SM
	sb.corner_radius_bottom_right = UITheme_.R_SM
	sb.content_margin_left = UITheme_.S_3
	sb.content_margin_top = UITheme_.S_2
	sb.content_margin_right = UITheme_.S_3
	sb.content_margin_bottom = UITheme_.S_2
	return sb

func _bar_bg() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = UITheme_.BG_ELEVATED
	sb.corner_radius_top_left = UITheme_.R_SM
	sb.corner_radius_top_right = UITheme_.R_SM
	sb.corner_radius_bottom_left = UITheme_.R_SM
	sb.corner_radius_bottom_right = UITheme_.R_SM
	return sb

func _bar_fill() -> StyleBoxFlat:
	# GCP 控制台风格: 进度条填充用 Google 蓝 (与"训练中"状态色一致)。
	var sb := StyleBoxFlat.new()
	sb.bg_color = UITheme_.ACCENT_INFO
	sb.corner_radius_top_left = UITheme_.R_SM
	sb.corner_radius_top_right = UITheme_.R_SM
	sb.corner_radius_bottom_left = UITheme_.R_SM
	sb.corner_radius_bottom_right = UITheme_.R_SM
	return sb

func _flat(bg: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	return sb

func _separator_line(c: Color) -> StyleBoxLine:
	var sb := StyleBoxLine.new()
	sb.color = c
	sb.thickness = 1
	return sb

func _make_close_icon() -> ImageTexture:
	# 程序绘制 16×16 深色 X (TEXT_SECONDARY), 给 Window 当 close icon. 默认 Godot
	# 图标是白 X, 在浅色 panel 上看不见。
	var s := 16
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c: Color = UITheme_.TEXT_SECONDARY
	# 两条对角线, 各画 2px 粗 (主 + 偏移), 留 3px 边距让 X 在中间。
	var pad := 3
	for i in range(pad, s - pad):
		var j := s - 1 - i
		img.set_pixel(i, i, c)
		img.set_pixel(i, j, c)
		if i + 1 < s - pad:
			img.set_pixel(i + 1, i, c)
			img.set_pixel(i + 1, j, c)
	return ImageTexture.create_from_image(img)

func _make_checkbox_icon(checked: bool, disabled: bool) -> ImageTexture:
	var s := 18
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var bg := UITheme_.ACCENT_INFO if checked else UITheme_.BG_SURFACE
	var border := UITheme_.ACCENT_INFO if checked else UITheme_.BORDER_STRONG
	var mark := UITheme_.BG_SURFACE
	if disabled:
		bg = UITheme_.BORDER_SUBTLE if checked else UITheme_.BG_SURFACE
		border = UITheme_.BORDER_SUBTLE
		mark = UITheme_.TEXT_DISABLED
	var rect := Rect2i(1, 1, 16, 16)
	_stroke_round_rect(img, rect, 4, border, bg, 2)
	if checked:
		_draw_line(img, Vector2i(5, 9), Vector2i(8, 12), mark, 2)
		_draw_line(img, Vector2i(8, 12), Vector2i(13, 6), mark, 2)
	return ImageTexture.create_from_image(img)

func _make_switch_icon(checked: bool, disabled: bool) -> ImageTexture:
	var w := 42
	var h := 24
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var track := UITheme_.ACCENT_INFO if checked else UITheme_.BG_SURFACE
	var border := UITheme_.ACCENT_INFO if checked else UITheme_.BORDER_STRONG
	var knob := UITheme_.BG_SURFACE if checked else UITheme_.TEXT_SECONDARY
	if disabled:
		track = UITheme_.BORDER_SUBTLE if checked else UITheme_.BG_SURFACE
		border = UITheme_.BORDER_SUBTLE
		knob = UITheme_.TEXT_DISABLED
	_stroke_round_rect(img, Rect2i(1, 3, 40, 18), 9, border, track, 2)
	var cx := 30 if checked else 12
	_fill_circle(img, Vector2i(cx, 12), 7, knob)
	return ImageTexture.create_from_image(img)

func _stroke_round_rect(
		img: Image,
		rect: Rect2i,
		radius: int,
		border: Color,
		fill: Color,
		width: int
	) -> void:
	_fill_round_rect(img, rect, radius, border)
	var inset := Vector2i(width, width)
	var inner := Rect2i(rect.position + inset, rect.size - inset * 2)
	_fill_round_rect(img, inner, max(0, radius - width), fill)

func _fill_round_rect(img: Image, rect: Rect2i, radius: int, color: Color) -> void:
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			if _point_in_round_rect(Vector2i(x, y), rect, radius):
				_set_pixel_safe(img, x, y, color)

func _point_in_round_rect(p: Vector2i, rect: Rect2i, radius: int) -> bool:
	var left := rect.position.x
	var top := rect.position.y
	var right := rect.position.x + rect.size.x - 1
	var bottom := rect.position.y + rect.size.y - 1
	if p.x < left or p.x > right or p.y < top or p.y > bottom:
		return false
	var cx: int = clampi(p.x, left + radius, right - radius)
	var cy: int = clampi(p.y, top + radius, bottom - radius)
	var dx := p.x - cx
	var dy := p.y - cy
	return dx * dx + dy * dy <= radius * radius

func _fill_circle(img: Image, center: Vector2i, radius: int, color: Color) -> void:
	for y in range(center.y - radius, center.y + radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			var dx := x - center.x
			var dy := y - center.y
			if dx * dx + dy * dy <= radius * radius:
				_set_pixel_safe(img, x, y, color)

func _draw_line(img: Image, a: Vector2i, b: Vector2i, color: Color, thickness: int) -> void:
	var dx := b.x - a.x
	var dy := b.y - a.y
	var steps: int = maxi(abs(dx), abs(dy))
	if steps <= 0:
		_set_pixel_safe(img, a.x, a.y, color)
		return
	var half := int(floor(float(thickness) / 2.0))
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var x := int(round(lerpf(float(a.x), float(b.x), t)))
		var y := int(round(lerpf(float(a.y), float(b.y), t)))
		for oy in range(-half, half + 1):
			for ox in range(-half, half + 1):
				_set_pixel_safe(img, x + ox, y + oy, color)

func _set_pixel_safe(img: Image, x: int, y: int, color: Color) -> void:
	if x >= 0 and x < img.get_width() and y >= 0 and y < img.get_height():
		img.set_pixel(x, y, color)

func _window_panel() -> StyleBoxFlat:
	# Window / Dialog / PopupMenu 通用面板: 纯白底 + 1px 边 + R_LG 圆角 + 内边距。
	var sb := StyleBoxFlat.new()
	sb.bg_color = UITheme_.BG_SURFACE
	sb.border_color = UITheme_.BORDER_SUBTLE
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.corner_radius_top_left = UITheme_.R_LG
	sb.corner_radius_top_right = UITheme_.R_LG
	sb.corner_radius_bottom_left = UITheme_.R_LG
	sb.corner_radius_bottom_right = UITheme_.R_LG
	sb.content_margin_left = UITheme_.S_4
	sb.content_margin_top = UITheme_.S_4
	sb.content_margin_right = UITheme_.S_4
	sb.content_margin_bottom = UITheme_.S_4
	return sb

func _window_embedded_border() -> StyleBoxFlat:
	# Embedded Window 的边框同时承载标题栏背景。顶部 margin 留出 title_height
	# + breathing room, 否则浅色 Dialog 的标题区域会透出背后的主界面。
	var sb := _window_panel()
	sb.content_margin_top = UITheme_.S_10
	# Godot 4.3: 嵌入窗口的 embedded_border 只画在「内容矩形」里, 标题栏在其上方且
	# 默认无填充 → 浅色主题下标题区透出背后主界面 (看起来"header 透明")。用
	# expand_margin_top 把白色填充向上延伸盖住整条标题栏 (title_height=BUTTON_H)。
	sb.expand_margin_top = float(UITheme_.S_10)
	return sb
