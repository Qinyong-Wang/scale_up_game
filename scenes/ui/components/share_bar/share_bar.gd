extends Control

## ShareBar — 营收页横向占比条 (营收系统设计 §6ter)。
##
## 用法:
##   var bar := preload("res://scenes/ui/components/share_bar/share_bar.tscn").instantiate()
##   add_child(bar)
##   bar.set_segments([{value = 520_000.0, color = UITheme.ACCENT_INFO},
##                     {value = 120_000.0, color = UITheme.ACCENT_PRIMARY}], 1_200_000.0)
##
## 在浅灰 track (BG_ELEVATED) 上从左到右按 value/total 铺彩色段 (方角, 8px 高)。
## total <= 段和时回退到段和当分母 (条不会铺超过 100%); 空数据只画 track。
## 纯展示, 无信号 — 比例数字由调用方算好喂进来。


const _HEIGHT: float = 8.0
const _MIN_WIDTH: float = 80.0

var _segments: Array = []   # [{value: float, color: Color}, ...]
var _total: float = 0.0

func _ready() -> void:
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(_MIN_WIDTH, _HEIGHT)
	else:
		custom_minimum_size.y = maxf(custom_minimum_size.y, _HEIGHT)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_segments(segments: Array, total: float) -> void:
	_segments = segments
	var sum: float = 0.0
	for s in segments:
		sum += maxf(0.0, float(s.get("value", 0.0)))
	# 分母至少是段和, 防止 total 给小了导致条溢出 100%。
	_total = maxf(total, sum)
	queue_redraw()

func _draw() -> void:
	var bar_h: float = _HEIGHT
	var y: float = (size.y - bar_h) * 0.5
	var w: float = size.x
	if w <= 0.0:
		return
	# track
	draw_rect(Rect2(0.0, y, w, bar_h), UITheme.BG_ELEVATED)
	if _total <= 0.0:
		return
	var x: float = 0.0
	for s in _segments:
		var v: float = maxf(0.0, float(s.get("value", 0.0)))
		if v <= 0.0:
			continue
		var seg_w: float = w * (v / _total)
		var col: Color = s.get("color", UITheme.ACCENT_PRIMARY)
		draw_rect(Rect2(x, y, seg_w, bar_h), col)
		x += seg_w

# ─── 测试 introspection ──────────────────────────────────────

## 每段相对分母的填充比例 (= value/total), 负值钳 0; 不依赖渲染。
func get_fill_fractions_for_test() -> Array:
	var out: Array = []
	for s in _segments:
		if _total <= 0.0:
			out.append(0.0)
		else:
			out.append(maxf(0.0, float(s.get("value", 0.0))) / _total)
	return out

func get_total_for_test() -> float:
	return _total
