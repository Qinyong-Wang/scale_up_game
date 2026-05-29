extends Control

## CapacityPie — 单个模型算力池的可视化饼图。
##
## 三档切片: 订阅占用 (绿) / API 占用 (蓝) / 空闲 (灰)。需求超过 capacity 时
## 整圈红边 + 切片按 ratio = capacity / total_demand 缩放, 把"算力已满"直接
## 投射在玩家视线里 (单靠 util_pct 数字玩家容易忽略)。
##
## 用法:
##   var pie := preload("res://scenes/ui/components/capacity_pie/capacity_pie.tscn").instantiate()
##   pie.set_data(capacity, sub_demand, api_demand)   # 单位 tokens/周
##
## capacity == 0 时画灰圆 (未部署), 不画切片。
##
## 见 design/营收系统设计.md §5.2bis.


@export var capacity: int = 0
@export var sub_demand: int = 0
@export var api_demand: int = 0

const _SIZE_DEFAULT: int = 56
const _SLICE_STEPS_PER_REV: int = 64   # 一整圈采样数, 越大越圆

func _ready() -> void:
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(_SIZE_DEFAULT, _SIZE_DEFAULT)

func set_data(p_capacity: int, p_sub_demand: int, p_api_demand: int) -> void:
	capacity = maxi(0, p_capacity)
	sub_demand = maxi(0, p_sub_demand)
	api_demand = maxi(0, p_api_demand)
	queue_redraw()

func _draw() -> void:
	var radius: float = minf(size.x, size.y) * 0.5 - 2.0
	if radius <= 0.0:
		return
	var center: Vector2 = size * 0.5

	if capacity <= 0:
		# 未部署 — 单灰圆 + 描边, 配合外层"未在 DC 部署"警告行做总解释。
		draw_circle(center, radius, UITheme.BG_ELEVATED)
		draw_arc(center, radius, 0.0, TAU, _SLICE_STEPS_PER_REV,
				UITheme.BORDER_SUBTLE, 1.5, true)
		return

	var total_demand: float = float(sub_demand + api_demand)
	var ratio: float = 1.0
	if total_demand > float(capacity) and total_demand > 0.0:
		ratio = float(capacity) / total_demand
	var served_sub: float = float(sub_demand) * ratio
	var served_api: float = float(api_demand) * ratio
	var idle: float = maxf(0.0, float(capacity) - served_sub - served_api)

	var unit: float = TAU / float(capacity)
	var start_angle: float = -PI * 0.5     # 12 点钟开始, 顺时针填
	if served_sub > 0.0:
		_draw_slice(center, radius, start_angle, served_sub * unit,
				UITheme.ACCENT_PRIMARY)
		start_angle += served_sub * unit
	if served_api > 0.0:
		_draw_slice(center, radius, start_angle, served_api * unit,
				UITheme.ACCENT_INFO)
		start_angle += served_api * unit
	if idle > 0.0:
		_draw_slice(center, radius, start_angle, idle * unit,
				UITheme.BG_ELEVATED)

	var saturated: bool = total_demand > float(capacity)
	var outline_color: Color = UITheme.ACCENT_DANGER if saturated else UITheme.BORDER_SUBTLE
	var outline_w: float = 2.0 if saturated else 1.0
	draw_arc(center, radius, 0.0, TAU, _SLICE_STEPS_PER_REV,
			outline_color, outline_w, true)

func _draw_slice(center: Vector2, radius: float, start: float, span: float,
		color: Color) -> void:
	if span <= 0.0:
		return
	var steps: int = maxi(2, int(ceil(span * float(_SLICE_STEPS_PER_REV) / TAU)))
	var pts := PackedVector2Array()
	pts.append(center)
	for i in range(steps + 1):
		var a: float = start + span * (float(i) / float(steps))
		pts.append(center + Vector2(cos(a), sin(a)) * radius)
	draw_polygon(pts, PackedColorArray([color]))

# ─── 测试 introspection ──────────────────────────────────────

## 返回 (served_sub, served_api, idle) 三档的实际像素切片角度 (弧度), 测试用。
func get_slice_angles_for_test() -> Dictionary:
	if capacity <= 0:
		return {sub = 0.0, api = 0.0, idle = 0.0, saturated = false}
	var total_demand: float = float(sub_demand + api_demand)
	var ratio: float = 1.0
	if total_demand > float(capacity) and total_demand > 0.0:
		ratio = float(capacity) / total_demand
	var unit: float = TAU / float(capacity)
	var sub_a: float = float(sub_demand) * ratio * unit
	var api_a: float = float(api_demand) * ratio * unit
	var idle_a: float = maxf(0.0, TAU - sub_a - api_a)
	return {
		sub = sub_a,
		api = api_a,
		idle = idle_a,
		saturated = total_demand > float(capacity),
	}
