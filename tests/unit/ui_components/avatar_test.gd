extends GutTest

## Avatar 组件契约。
## 对应 design/UI视觉系统设计.md §7 + 国际化设计.md §6 (Avatar 不调 tr())。
##
## 行为:
##   - 有 texture 时贴图覆盖回退层。
##   - 无 texture 时按 seed_id 哈希到 HSL 配色 + 文字 / glyph 显示。
##   - 同一 seed_id 永远是同一颜色 (deterministic), 不同 seed_id 大概率不同色。
##   - fallback_text 为空时按 kind 取 glyph (◉ model / ▣ datacenter / ● lead / ▸ dataset)。
##   - 中文 fallback_text 取首 1 字; 西文取首 2 字大写。

const AvatarScene := preload("res://scenes/ui/components/avatar/avatar.tscn")

func _make() -> Control:
	var a: Control = AvatarScene.instantiate()
	add_child_autofree(a)
	return a

# ─── 实例化与默认尺寸 ─────────────────────────────────────────

func test_instantiates_with_default_min_size() -> void:
	var a := _make()
	await get_tree().process_frame
	assert_eq(a.custom_minimum_size, Vector2(48, 48))

# ─── 文字回退 ─────────────────────────────────────────────────

func test_chinese_fallback_uses_first_one_char() -> void:
	var a := _make()
	a.set_data(null, "梧桐机房", &"dc_wutong_1", &"datacenter")
	await get_tree().process_frame
	assert_eq(a.get_displayed_text(), "梧")

func test_latin_fallback_uses_first_two_chars_upper() -> void:
	var a := _make()
	a.set_data(null, "alice wang", &"lead_alice", &"lead")
	await get_tree().process_frame
	assert_eq(a.get_displayed_text(), "AL")

func test_empty_text_falls_back_to_kind_glyph() -> void:
	var a := _make()
	a.set_data(null, "", &"m1", &"model")
	await get_tree().process_frame
	assert_eq(a.get_displayed_text(), "◉")

func test_empty_text_unknown_kind_falls_back_to_question() -> void:
	var a := _make()
	a.set_data(null, "", &"x", &"unknown_kind_xxx")
	await get_tree().process_frame
	assert_eq(a.get_displayed_text(), "?")

func test_glyphs_for_each_known_kind() -> void:
	var cases := {
		&"model": "◉",
		&"datacenter": "▣",
		&"lead": "●",
		&"dataset": "▸",
	}
	for kind in cases:
		var a := _make()
		a.set_data(null, "", &"seed", kind)
		await get_tree().process_frame
		assert_eq(a.get_displayed_text(), cases[kind], "glyph for kind %s" % kind)

# ─── 颜色 deterministic ──────────────────────────────────────

func test_same_seed_id_yields_same_color() -> void:
	var a1 := _make()
	a1.set_data(null, "x", &"seed_alpha", &"lead")
	await get_tree().process_frame
	var c1: Color = a1.get_displayed_color()
	var a2 := _make()
	a2.set_data(null, "x", &"seed_alpha", &"lead")
	await get_tree().process_frame
	var c2: Color = a2.get_displayed_color()
	assert_true(c1.is_equal_approx(c2),
		"同 seed_id 必须同色, 实际 %s vs %s" % [c1, c2])

func test_different_seed_ids_yield_different_colors_in_most_cases() -> void:
	# 哈希分布性质 — 给 8 个不同 id, 至少出现 4 种不同色。
	var ids: Array[StringName] = [
		&"a", &"b", &"c", &"d", &"e", &"f", &"g", &"h",
	]
	var colors_seen: Dictionary = {}
	for id in ids:
		var a := _make()
		a.set_data(null, "x", id, &"lead")
		await get_tree().process_frame
		var c: Color = a.get_displayed_color()
		# 量化到 0.01 精度去重, 避免浮点抖动误判。
		var key := "%.2f_%.2f_%.2f" % [c.h, c.s, c.v]
		colors_seen[key] = true
	assert_gte(colors_seen.size(), 4,
		"8 个不同 id 至少应当产出 4 种不同色, 实际 %d" % colors_seen.size())

func test_empty_seed_id_uses_neutral_fallback_color() -> void:
	var a := _make()
	a.set_data(null, "x", &"", &"lead")
	await get_tree().process_frame
	# 空 seed 用 UITheme.BG_ELEVATED 作中性兜底, 别撞具体玩家的颜色。
	assert_true(a.get_displayed_color().is_equal_approx(UITheme.BG_ELEVATED),
		"空 seed 应当用 BG_ELEVATED, 实际 %s" % a.get_displayed_color())

# ─── texture vs 回退 切换 ────────────────────────────────────

func test_texture_when_provided_hides_fallback() -> void:
	var a := _make()
	var tex := PlaceholderTexture2D.new()
	a.set_data(tex, "x", &"seed", &"lead")
	await get_tree().process_frame
	assert_true(a.is_texture_layer_visible())
	assert_false(a.is_fallback_layer_visible())

func test_clearing_texture_restores_fallback() -> void:
	var a := _make()
	var tex := PlaceholderTexture2D.new()
	a.set_data(tex, "x", &"seed", &"lead")
	await get_tree().process_frame
	a.set_data(null, "x", &"seed", &"lead")
	await get_tree().process_frame
	assert_false(a.is_texture_layer_visible())
	assert_true(a.is_fallback_layer_visible())
