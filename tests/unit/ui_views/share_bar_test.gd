extends GutTest

## ShareBar 单测 — 营收页占比条组件 (营收系统设计 §6ter)。
## 只测数据/比例语义 (get_fill_fractions_for_test), 不依赖实际渲染。

const ShareBarScene := preload("res://scenes/ui/components/share_bar/share_bar.tscn")
const ACCENT := Color("#1e8e3e")

func _make() -> Control:
	var b: Control = ShareBarScene.instantiate()
	add_child_autofree(b)
	return b

func test_single_segment_fraction_is_value_over_total() -> void:
	var b := _make()
	b.set_segments([{value = 500.0, color = ACCENT}], 1000.0)
	var fr: Array = b.get_fill_fractions_for_test()
	assert_eq(fr.size(), 1)
	assert_almost_eq(float(fr[0]), 0.5, 0.001)

func test_stacked_segments_use_shared_total() -> void:
	var b := _make()
	b.set_segments([
		{value = 300.0, color = ACCENT},
		{value = 200.0, color = ACCENT},
	], 1000.0)
	var fr: Array = b.get_fill_fractions_for_test()
	assert_eq(fr.size(), 2)
	assert_almost_eq(float(fr[0]), 0.3, 0.001)
	assert_almost_eq(float(fr[1]), 0.2, 0.001)

func test_total_below_segment_sum_falls_back_to_sum() -> void:
	# 防溢出: 给的 total 小于段和时, 用段和当分母 (条不会铺超过 100%)。
	var b := _make()
	b.set_segments([
		{value = 600.0, color = ACCENT},
		{value = 600.0, color = ACCENT},
	], 1000.0)
	assert_almost_eq(b.get_total_for_test(), 1200.0, 0.001)
	var fr: Array = b.get_fill_fractions_for_test()
	assert_almost_eq(float(fr[0]), 0.5, 0.001)
	assert_almost_eq(float(fr[1]), 0.5, 0.001)

func test_empty_segments_yield_zero_total() -> void:
	var b := _make()
	b.set_segments([], 0.0)
	assert_eq(b.get_total_for_test(), 0.0)
	assert_eq(b.get_fill_fractions_for_test().size(), 0)

func test_negative_value_clamped_to_zero() -> void:
	var b := _make()
	b.set_segments([{value = -50.0, color = ACCENT}], 100.0)
	var fr: Array = b.get_fill_fractions_for_test()
	assert_eq(fr.size(), 1)
	assert_almost_eq(float(fr[0]), 0.0, 0.001)
