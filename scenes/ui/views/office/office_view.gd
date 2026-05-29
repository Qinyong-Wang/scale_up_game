extends Control

## OfficeView — 「办公室」第一人称房间场景。Per design/办公室与收藏系统设计.md §8.1。
##
## 第一人称坐在办公桌前: 近处桌面 + 电脑显示器 (点屏幕 → computer_pressed → 收藏柜
## dialog), 近处桌上散放**奖章** (form=medal), 远处茶几上散放**奖杯** (form=trophy),
## 终局后显示器下方摆出**终极答案盒** (form=answer_box)。
## 点奖章/奖杯/答案盒 → honor_pressed(id) → main 弹荣誉信息 dialog (名+描述+flavor)。
##
## 美术: room-bg 是第一人称房间场景图 (办公桌+电脑+茶几烤进画面), 按**等比 FIT** 居中
## 铺进 stage rect (整图必全显, 留极薄的中性 letterbox, 不裁不变形) — 这样奖章/奖杯的
## 归一化锚点能精确落到桌面/茶几上 (COVER 会裁掉图边、锚点会飘)。荣誉物是透明精灵
## (office_texture("medal-<id>" / "trophy-<id>" / "answer_box-<id>"))。
## 缺图回退程序化占位 / 图标字形。
##
## 视图不读 GameState; main.gd refresh({trophies}) 传全部 TrophySpec (带 earned + form)。
##
## 信号: computer_pressed() / honor_pressed(trophy_id)

signal computer_pressed
signal honor_pressed(trophy_id: StringName)

const _MIN_HEIGHT: int = 560
const _TROPHY_GLYPH_CP: int = 0xea65  # Material Icons emoji_events (回退字形)

# 归一化锚点 (相对 room-bg 整图, FIT 后映射到 stage rect)。按真图布局微调。
const _ROOM_ASPECT := 1280.0 / 731.0  # room-bg 出图宽高比 (无图时回退用)
# Computer hotspot / visible screen: hotspot is slightly larger for easier clicks;
# screen rect only draws the lightweight dashboard glow.
const _COMPUTER_HOTSPOT := Rect2(0.386, 0.395, 0.248, 0.295)
const _COMPUTER_SCREEN := Rect2(0.402, 0.412, 0.216, 0.245)
# 近处桌面散放奖章的落点 (锚 = 物体底部中心), 落在键盘两侧的空桌面 (image y~0.86)。
const _DESK_ANCHORS: Array[Vector2] = [
	Vector2(0.34, 0.88), Vector2(0.66, 0.88), Vector2(0.27, 0.92),
	Vector2(0.73, 0.92), Vector2(0.50, 0.94),
]
# 远处茶几 (左侧低矮长凳, image x0.06-0.30, 台面 y~0.75) 散放奖杯的落点。
const _TABLE_ANCHORS: Array[Vector2] = [
	Vector2(0.105, 0.748), Vector2(0.175, 0.755), Vector2(0.245, 0.747),
]
const _ANSWER_BOX_ANCHORS: Array[Vector2] = [
	Vector2(0.50, 0.865),
]

# letterbox 底色 (中性浅灰, 贴近房间墙色)。程序化占位配色 (仅缺 room-bg 时可见)。
const _LETTERBOX := Color("#eef1f3")
const _STAGE_KEYLINE := Color("#202124", 0.10)
const _STAGE_HIGHLIGHT := Color("#ffffff", 0.22)
const _WALL := Color("#e8eaed")
const _FLOOR := Color("#bdc1c6")
const _MONITOR := Color("#202124")
const _SCREEN := Color("#1e8e3e")
const _SCREEN_DARK := Color("#0f1c22")
const _SCREEN_GRID := Color("#c4eef7", 0.16)
const _SCREEN_LINE := Color("#7fd6e8", 0.72)
const _SCREEN_FILL := Color("#6bc4d6", 0.28)
const _SCREEN_HOVER := Color("#d8fbff", 0.38)
const _SCREEN_AFFORDANCE := Color("#d8fbff", 0.42)
const _ATMOSPHERE := Color("#081018")
const _HONOR_SHADOW := Color("#101820", 0.22)
const _ANSWER_BOX_BG := Color("#2f3437")
const _ANSWER_BOX_LID := Color("#4b5256")
const _ANSWER_BOX_TEXT := Color("#f8fafd")

var _computer_btn: Button
var _honor_buttons: Dictionary = {}   # id -> Control (测试 introspection)
var _desk_ids: Array[StringName] = []  # form=medal, 摆桌面
var _table_ids: Array[StringName] = [] # form=trophy, 摆茶几
var _answer_box_ids: Array[StringName] = [] # form=answer_box, 终局密封盒
var _earned: Array = []                # earned honor dicts (id/display_name/form)
var _computer_hovered: bool = false

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(0, _MIN_HEIGHT)
	clip_contents = true

	_computer_btn = Button.new()
	_computer_btn.flat = true
	_computer_btn.focus_mode = Control.FOCUS_NONE
	_computer_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_computer_btn.tooltip_text = tr("OFFICE_COMPUTER_TOOLTIP")
	var empty := StyleBoxEmpty.new()
	for state in [&"normal", &"hover", &"pressed", &"disabled", &"focus"]:
		_computer_btn.add_theme_stylebox_override(state, empty)
	_computer_btn.mouse_entered.connect(func(): _set_computer_hovered(true))
	_computer_btn.mouse_exited.connect(func(): _set_computer_hovered(false))
	_computer_btn.pressed.connect(_on_computer_pressed)
	add_child(_computer_btn)

	resized.connect(_layout)
	_layout()
	# ScrollContainer 不拉伸子节点 → 房间会缩在顶部留白。延迟找到祖先 ScrollContainer,
	# 把自身最小高同步成其视口高 → 房间铺满 tab (FIT 居中, 余下为 letterbox 中性色)。
	call_deferred("_sync_fill_height")

var _scroll: ScrollContainer

func _sync_fill_height() -> void:
	var p: Node = get_parent()
	while p != null and not (p is ScrollContainer):
		p = p.get_parent()
	if p is ScrollContainer:
		_scroll = p as ScrollContainer
		if not _scroll.resized.is_connected(_on_scroll_resized):
			_scroll.resized.connect(_on_scroll_resized)
		_on_scroll_resized()

func _on_scroll_resized() -> void:
	if _scroll != null:
		custom_minimum_size.y = maxf(float(_MIN_HEIGHT), _scroll.size.y)

func refresh(data: Dictionary) -> void:
	_earned.clear()
	for t in data.get("trophies", []):
		if bool(t.get("earned", false)):
			_earned.append(t)
	_rebuild_honors()
	_layout()
	queue_redraw()

func _on_computer_pressed() -> void:
	Log.info(&"ui", "office_computer_pressed", {})
	computer_pressed.emit()

func _set_computer_hovered(value: bool) -> void:
	if _computer_hovered == value:
		return
	_computer_hovered = value
	queue_redraw()

# ---- 奖章 / 奖杯精灵 -----------------------------------------------------

func _rebuild_honors() -> void:
	for c in _honor_buttons.values():
		c.queue_free()
	_honor_buttons.clear()
	_desk_ids.clear()
	_table_ids.clear()
	_answer_box_ids.clear()
	for t in _earned:
		var tid: StringName = StringName(t.get("id", &""))
		if String(tid).is_empty():
			continue
		var form: StringName = StringName(t.get("form", &"trophy"))
		var btn := _make_honor_button(tid, form, tr(String(t.get("display_name", String(tid)))))
		add_child(btn)
		_honor_buttons[tid] = btn
		if form == &"medal":
			_desk_ids.append(tid)
		elif form == &"answer_box":
			_answer_box_ids.append(tid)
		else:
			_table_ids.append(tid)

func _make_honor_button(tid: StringName, form: StringName, name_str: String) -> Control:
	var tex: Texture2D = IconRegistry.office_texture(StringName(String(form) + "-" + String(tid)))
	if tex != null:
		var tb := TextureButton.new()
		tb.texture_normal = tex
		tb.ignore_texture_size = true
		tb.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		tb.tooltip_text = name_str
		tb.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		tb.pressed.connect(func(): _on_honor_pressed(tid))
		return tb
	if form == &"answer_box":
		return _make_answer_box_button(tid, name_str)
	# 回退: 图标字形按钮 (金橙)。
	var btn := Button.new()
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.tooltip_text = name_str
	var icon_font: Font = UITheme.get_icon_font()
	if icon_font != null:
		btn.add_theme_font_override(&"font", icon_font)
	btn.add_theme_color_override(&"font_color", UITheme.ACCENT_WARNING)
	btn.text = String.chr(_TROPHY_GLYPH_CP)
	btn.pressed.connect(func(): _on_honor_pressed(tid))
	return btn

func _make_answer_box_button(tid: StringName, name_str: String) -> Button:
	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.tooltip_text = name_str
	btn.text = "?"
	btn.add_theme_font_size_override(&"font_size", UITheme.FS_LG)
	btn.add_theme_color_override(&"font_color", _ANSWER_BOX_TEXT)
	btn.add_theme_color_override(&"font_hover_color", _ANSWER_BOX_TEXT)
	btn.add_theme_color_override(&"font_pressed_color", _ANSWER_BOX_TEXT)
	btn.add_theme_stylebox_override(&"normal", _answer_box_style(_ANSWER_BOX_BG, _ANSWER_BOX_LID, 2))
	btn.add_theme_stylebox_override(&"hover",
			_answer_box_style(_ANSWER_BOX_BG.lightened(0.10), UITheme.ACCENT_WARNING, 2))
	btn.add_theme_stylebox_override(&"pressed",
			_answer_box_style(_ANSWER_BOX_BG.darkened(0.08), UITheme.ACCENT_WARNING, 2))
	btn.pressed.connect(func(): _on_honor_pressed(tid))
	return btn

func _answer_box_style(bg: Color, border: Color, border_w: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.border_width_left = border_w
	sb.border_width_top = border_w
	sb.border_width_right = border_w
	sb.border_width_bottom = border_w
	sb.corner_radius_top_left = UITheme.R_SM
	sb.corner_radius_top_right = UITheme.R_SM
	sb.corner_radius_bottom_left = UITheme.R_SM
	sb.corner_radius_bottom_right = UITheme.R_SM
	sb.content_margin_left = 0
	sb.content_margin_right = 0
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	return sb

func _on_honor_pressed(tid: StringName) -> void:
	Log.info(&"ui", "office_honor_pressed", {id = tid})
	honor_pressed.emit(tid)

# ---- Layout (FIT transform maps normalized anchors) ---------------------

# 等比 FIT 居中: 整图必全显, 不裁不变形, 余下为 letterbox。
func _stage_rect() -> Rect2:
	var ar := _ROOM_ASPECT
	var bg: Texture2D = IconRegistry.office_texture(&"room-bg")
	if bg != null and bg.get_width() > 0 and bg.get_height() > 0:
		ar = float(bg.get_width()) / float(bg.get_height())
	var sw: float = size.x
	var sh: float = size.x / ar
	if sh > size.y:
		sh = size.y
		sw = size.y * ar
	return Rect2((size - Vector2(sw, sh)) * 0.5, Vector2(sw, sh))

func _stage_to_rect(normalized_rect: Rect2) -> Rect2:
	var sr := _stage_rect()
	return Rect2(sr.position + normalized_rect.position * sr.size, normalized_rect.size * sr.size)

func _layout() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var sr := _stage_rect()
	# Computer hotspot.
	var computer_rect := _stage_to_rect(_COMPUTER_HOTSPOT)
	_computer_btn.position = computer_rect.position
	_computer_btn.size = computer_rect.size
	# 奖章 (桌面平放, 小, 随手一摆带点斜) / 奖杯 (茶几立放, 略大, 端正)。锚点 = 底部中心。
	_place_honors(_desk_ids, _DESK_ANCHORS, sr, sr.size.y * 0.075, true)
	_place_honors(_table_ids, _TABLE_ANCHORS, sr, sr.size.y * 0.095, false)
	_place_honors(_answer_box_ids, _ANSWER_BOX_ANCHORS, sr, sr.size.y * 0.105, false)
	queue_redraw()

func _place_honors(ids: Array[StringName], anchors: Array[Vector2], cr: Rect2, side: float,
		tilt: bool) -> void:
	for i in ids.size():
		var btn: Control = _honor_buttons.get(ids[i], null)
		if btn == null:
			continue
		var a: Vector2 = anchors[i % anchors.size()]
		# 同一锚点重复用时, 沿 x 轻微错开避免完全重叠。
		var jitter: float = float(i / anchors.size()) * side * 0.7
		var center_bottom: Vector2 = cr.position + (a + Vector2(jitter / maxf(cr.size.x, 1.0), 0.0)) * cr.size
		btn.size = Vector2(side, side)
		btn.position = center_bottom - Vector2(side * 0.5, side)
		# 「零散随意」: 桌上奖章按 id 稳定地各斜一点 (绕自身中心), 茶几奖杯端正立着。
		btn.pivot_offset = btn.size * 0.5
		btn.rotation = deg_to_rad(float(int(String(ids[i]).hash()) % 17 - 8)) if tilt else 0.0

# ---- Drawing (room-bg FIT, procedural fallback) -------------------------

func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var sr := _stage_rect()
	# letterbox 底 (整面铺中性色, room-bg FIT 居中盖在中央)。
	draw_rect(Rect2(Vector2.ZERO, size), _LETTERBOX)
	var bg: Texture2D = IconRegistry.office_texture(&"room-bg")
	if bg != null:
		draw_texture_rect(bg, sr, false)
	else:
		# Fallback without room art: wall + floor + central monitor.
		var floor_y: float = sr.position.y + sr.size.y * 0.62
		draw_rect(Rect2(sr.position.x, sr.position.y, sr.size.x, sr.size.y * 0.62), _WALL)
		draw_rect(Rect2(sr.position.x, floor_y, sr.size.x, sr.size.y * 0.38), _FLOOR)
		var m := Rect2(_computer_btn.position, _computer_btn.size)
		draw_rect(m, _MONITOR)
		draw_rect(m.grow(-6.0), _SCREEN)
	_draw_stage_keyline(sr)
	_draw_honor_shadows()
	_draw_monitor_dashboard()
	_draw_atmosphere()

func _draw_stage_keyline(sr: Rect2) -> void:
	draw_rect(sr, _STAGE_HIGHLIGHT, false, 1.0)
	draw_rect(sr.grow(-1.0), _STAGE_KEYLINE, false, 1.0)

func _draw_monitor_dashboard() -> void:
	var screen := _stage_to_rect(_COMPUTER_SCREEN)
	if screen.size.x <= 0.0 or screen.size.y <= 0.0:
		return
	var glow_alpha := 0.16 if _computer_hovered else 0.07
	draw_rect(screen.grow(screen.size.y * 0.08), Color(_SCREEN_AFFORDANCE, glow_alpha))
	if _computer_hovered:
		draw_rect(screen.grow(screen.size.y * 0.10), Color(_SCREEN_HOVER, 0.10))
	draw_rect(screen, Color(_SCREEN_DARK, 0.78))
	var inset := screen.grow(-screen.size.y * 0.08)
	if inset.size.x <= 0.0 or inset.size.y <= 0.0:
		return
	for i in range(1, 4):
		var y := inset.position.y + inset.size.y * float(i) / 4.0
		draw_line(Vector2(inset.position.x, y), Vector2(inset.end.x, y), _SCREEN_GRID, 1.0)
	for i in range(1, 4):
		var x := inset.position.x + inset.size.x * float(i) / 4.0
		draw_line(Vector2(x, inset.position.y), Vector2(x, inset.end.y), _SCREEN_GRID, 1.0)
	var bars := [0.34, 0.58, 0.46]
	var bar_w := inset.size.x * 0.10
	for i in bars.size():
		var h := inset.size.y * float(bars[i])
		var x := inset.position.x + inset.size.x * (0.12 + float(i) * 0.14)
		var y := inset.end.y - h
		draw_rect(Rect2(Vector2(x, y), Vector2(bar_w, h)), Color(_SCREEN_FILL, 0.55))
	var top_y := inset.position.y + inset.size.y * 0.12
	for i in range(3):
		var dot_x := inset.position.x + inset.size.x * (0.08 + float(i) * 0.05)
		draw_circle(Vector2(dot_x, top_y), maxf(2.0, inset.size.y * 0.014), Color(_SCREEN_LINE, 0.50))
	var points := PackedVector2Array()
	var wave_values: Array[float] = [0.70, 0.54, 0.58, 0.40, 0.34, 0.24]
	for i in range(6):
		var t := float(i) / 5.0
		var x := inset.position.x + inset.size.x * (0.50 + t * 0.42)
		var wave: float = wave_values[i]
		var y: float = inset.position.y + inset.size.y * wave
		points.append(Vector2(x, y))
	draw_polyline(points, _SCREEN_LINE, 2.0, true)
	var border_color := _SCREEN_HOVER if _computer_hovered else Color(_SCREEN_LINE, 0.42)
	draw_rect(screen, border_color, false, 2.0)
	_draw_screen_corner_brackets(screen, _SCREEN_AFFORDANCE if _computer_hovered else Color(_SCREEN_AFFORDANCE, 0.46))

func _draw_screen_corner_brackets(rect: Rect2, color: Color) -> void:
	var len := minf(rect.size.x, rect.size.y) * 0.12
	var w := 2.0
	var p := rect.position
	var e := rect.end
	draw_line(p, p + Vector2(len, 0.0), color, w, true)
	draw_line(p, p + Vector2(0.0, len), color, w, true)
	draw_line(Vector2(e.x, p.y), Vector2(e.x - len, p.y), color, w, true)
	draw_line(Vector2(e.x, p.y), Vector2(e.x, p.y + len), color, w, true)
	draw_line(Vector2(p.x, e.y), Vector2(p.x + len, e.y), color, w, true)
	draw_line(Vector2(p.x, e.y), Vector2(p.x, e.y - len), color, w, true)
	draw_line(e, e - Vector2(len, 0.0), color, w, true)
	draw_line(e, e - Vector2(0.0, len), color, w, true)

func _draw_honor_shadows() -> void:
	for c in _honor_buttons.values():
		var btn := c as Control
		if btn == null or not btn.visible:
			continue
		var center := btn.position + Vector2(btn.size.x * 0.5, btn.size.y * 0.90)
		_draw_ellipse(center, btn.size.x * 0.42, maxf(3.0, btn.size.y * 0.09), _HONOR_SHADOW)

func _draw_ellipse(center: Vector2, radius_x: float, radius_y: float, color: Color) -> void:
	var points := PackedVector2Array()
	for i in range(24):
		var a := TAU * float(i) / 24.0
		points.append(center + Vector2(cos(a) * radius_x, sin(a) * radius_y))
	draw_colored_polygon(points, color)

func _draw_atmosphere() -> void:
	var steps := 18
	for i in range(steps):
		var t := float(i + 1) / float(steps)
		var alpha := 0.018 * t
		var y := size.y * (0.64 + 0.36 * float(i) / float(steps))
		var h := size.y * 0.36 / float(steps) + 1.0
		draw_rect(Rect2(0.0, y, size.x, h), Color(_ATMOSPHERE, alpha))
	for i in range(12):
		var t := float(i + 1) / 12.0
		var w := size.x * 0.16 * (1.0 - float(i) / 12.0)
		var alpha := 0.010 * t
		draw_rect(Rect2(0.0, 0.0, w, size.y), Color(_ATMOSPHERE, alpha))
		draw_rect(Rect2(size.x - w, 0.0, w, size.y), Color(_ATMOSPHERE, alpha))

# ─── 测试 introspection ──────────────────────────────────────

func get_desk_medal_count_for_test() -> int:
	return _desk_ids.size()

func get_table_trophy_count_for_test() -> int:
	return _table_ids.size()

func get_answer_box_count_for_test() -> int:
	return _answer_box_ids.size()

func get_honor_count_for_test() -> int:
	return _honor_buttons.size()

func get_computer_hotspot_rect_for_test() -> Rect2:
	return _stage_to_rect(_COMPUTER_HOTSPOT)

func get_computer_screen_rect_for_test() -> Rect2:
	return _stage_to_rect(_COMPUTER_SCREEN)

func get_stage_rect_for_test() -> Rect2:
	return _stage_rect()

func get_honor_size_for_test(tid: StringName) -> Vector2:
	var b: Control = _honor_buttons.get(tid, null)
	return b.size if b != null else Vector2.ZERO

func get_honor_bottom_anchor_normalized_for_test(tid: StringName) -> Vector2:
	var b: Control = _honor_buttons.get(tid, null)
	if b == null:
		return Vector2.ZERO
	var sr := _stage_rect()
	var bottom_center := b.position + Vector2(b.size.x * 0.5, b.size.y)
	return (bottom_center - sr.position) / sr.size

func is_computer_hovered_for_test() -> bool:
	return _computer_hovered

func set_computer_hover_for_test(value: bool) -> void:
	_set_computer_hovered(value)

func click_computer_for_test() -> void:
	_computer_btn.pressed.emit()

func click_honor_for_test(tid: StringName) -> void:
	var b: Control = _honor_buttons.get(tid, null)
	if b != null:
		b.pressed.emit()
