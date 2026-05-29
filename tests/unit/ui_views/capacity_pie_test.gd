extends GutTest

## CapacityPie — 算力池饼图三档切片 + 饱和红边。
## 见 design/营收系统设计.md §5.2bis。


const PieScene := preload("res://scenes/ui/components/capacity_pie/capacity_pie.tscn")

func _make(cap: int, sub_d: int, api_d: int) -> Control:
	var pie: Control = PieScene.instantiate()
	add_child_autofree(pie)
	pie.set_data(cap, sub_d, api_d)
	return pie

func test_no_capacity_yields_zero_slices() -> void:
	var pie := _make(0, 100, 100)
	var a: Dictionary = pie.get_slice_angles_for_test()
	assert_eq(a.sub, 0.0)
	assert_eq(a.api, 0.0)
	assert_eq(a.idle, 0.0)
	assert_false(a.saturated, "capacity=0 不算饱和, 算未部署")

func test_half_subscription_quarter_api_idles_rest() -> void:
	# capacity=1000, sub=500, api=250 → sub 1/2 圈, api 1/4 圈, idle 1/4 圈.
	var pie := _make(1000, 500, 250)
	var a: Dictionary = pie.get_slice_angles_for_test()
	assert_almost_eq(float(a.sub), TAU * 0.5, 0.001)
	assert_almost_eq(float(a.api), TAU * 0.25, 0.001)
	assert_almost_eq(float(a.idle), TAU * 0.25, 0.001)
	assert_false(a.saturated)

func test_saturation_scales_slices_to_full_circle() -> void:
	# capacity=1000, demand=3000 (sub=2000 + api=1000) → ratio=1/3.
	# sub 切片 = (2000/3) / 1000 圈 = 2/3 圈; api = (1000/3)/1000 = 1/3 圈; idle = 0.
	var pie := _make(1000, 2000, 1000)
	var a: Dictionary = pie.get_slice_angles_for_test()
	assert_almost_eq(float(a.sub), TAU * 2.0 / 3.0, 0.001)
	assert_almost_eq(float(a.api), TAU * 1.0 / 3.0, 0.001)
	assert_almost_eq(float(a.idle), 0.0, 0.001)
	assert_true(a.saturated, "demand > capacity 应标记 saturated")

func test_exactly_full_is_not_saturated() -> void:
	# total_demand == capacity 不算 saturated, 红边只有真超量时才亮。
	var pie := _make(1000, 600, 400)
	var a: Dictionary = pie.get_slice_angles_for_test()
	assert_almost_eq(float(a.sub), TAU * 0.6, 0.001)
	assert_almost_eq(float(a.api), TAU * 0.4, 0.001)
	assert_almost_eq(float(a.idle), 0.0, 0.001)
	assert_false(a.saturated)

func test_pure_subscription_no_api() -> void:
	var pie := _make(1000, 700, 0)
	var a: Dictionary = pie.get_slice_angles_for_test()
	assert_almost_eq(float(a.sub), TAU * 0.7, 0.001)
	assert_almost_eq(float(a.api), 0.0, 0.001)
	assert_almost_eq(float(a.idle), TAU * 0.3, 0.001)

func test_pure_api_no_subscription() -> void:
	var pie := _make(1000, 0, 800)
	var a: Dictionary = pie.get_slice_angles_for_test()
	assert_almost_eq(float(a.sub), 0.0, 0.001)
	assert_almost_eq(float(a.api), TAU * 0.8, 0.001)
	assert_almost_eq(float(a.idle), TAU * 0.2, 0.001)
