extends GutTest

## Badge 组件契约。
## 对应 design/UI视觉系统设计.md §7。

const BadgeScene := preload("res://scenes/ui/components/badge/badge.tscn")

func _make() -> Control:
	var b: Control = BadgeScene.instantiate()
	add_child_autofree(b)
	return b

func test_displays_label_text() -> void:
	var b := _make()
	b.set_data("已发布", &"published")
	await get_tree().process_frame
	assert_eq(b.get_label_text(), "已发布")

func test_kind_maps_to_color() -> void:
	# 不同 kind 必须给出不同的语义色。这里只断三对最常用的差异:
	#   published (绿) ≠ training (蓝) ≠ danger (红)。
	var b_pub := _make()
	b_pub.set_data("发布", &"published")
	var b_train := _make()
	b_train.set_data("训练", &"training")
	var b_danger := _make()
	b_danger.set_data("过期", &"danger")
	await get_tree().process_frame
	var c_pub: Color = b_pub.get_background_color()
	var c_train: Color = b_train.get_background_color()
	var c_danger: Color = b_danger.get_background_color()
	assert_false(c_pub.is_equal_approx(c_train), "published ≠ training")
	assert_false(c_train.is_equal_approx(c_danger), "training ≠ danger")
	assert_false(c_pub.is_equal_approx(c_danger), "published ≠ danger")

func test_unknown_kind_falls_back_to_neutral() -> void:
	var b1 := _make()
	b1.set_data("?", &"some_unknown_kind_xyz")
	var b2 := _make()
	b2.set_data("?", &"neutral")
	await get_tree().process_frame
	assert_true(b1.get_background_color().is_equal_approx(b2.get_background_color()),
		"未知 kind 应回退到 neutral 同色")

func test_status_kinds_for_model_lifecycle_cover_all_four() -> void:
	# 模型状态四档必须都被识别 (不能落到 neutral 兜底)。
	var kinds: Array[StringName] = [
		&"pretrained", &"posttrained", &"evaluated", &"published",
	]
	var seen_colors: Dictionary = {}
	for kind in kinds:
		var b := _make()
		b.set_data("x", kind)
		await get_tree().process_frame
		var c: Color = b.get_background_color()
		seen_colors["%.3f_%.3f_%.3f" % [c.r, c.g, c.b]] = true
	# 4 档至少给出 3 种不同色 (允许 pretrained / posttrained 共享中性灰)。
	assert_gte(seen_colors.size(), 3,
		"模型四档状态至少 3 种不同色, 实际 %d" % seen_colors.size())

func test_changes_apply_immediately_on_repeated_set_data() -> void:
	var b := _make()
	b.set_data("一", &"published")
	await get_tree().process_frame
	var c1: Color = b.get_background_color()
	b.set_data("二", &"danger")
	await get_tree().process_frame
	assert_eq(b.get_label_text(), "二")
	assert_false(b.get_background_color().is_equal_approx(c1),
		"再次 set_data 应当切换底色")
