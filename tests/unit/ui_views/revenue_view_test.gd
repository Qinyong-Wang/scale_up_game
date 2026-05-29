extends GutTest

## RevenueView 单测 — 营收 tab 视图 (营收系统设计 §6bis)。
## 纯展示视图, 数据由 refresh(data) 喂入。验证: KPI chip / 来源占比条 /
## 可折叠分组 (展开收起 + 跨 refresh 记忆) / 产品行 / 算力需求默认收起 /
## 未结算空态。locale 钉 zh_CN, 避免顺序相关 flaky (见 i18n-tests-pin-zh-locale)。

const RevenueViewScene := preload("res://scenes/ui/views/revenue_view/revenue_view.tscn")

var _saved_locale: String = ""

func before_each() -> void:
	_saved_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("zh_CN")

func after_each() -> void:
	TranslationServer.set_locale(_saved_locale)

func _make() -> Control:
	var v: Control = RevenueViewScene.instantiate()
	add_child_autofree(v)
	return v

# api_total 800k / sub_total 400k / grand 1.2M。两个模型:
#   cedar 640k (api 520k + sub 120k) → 53%
#   maple 560k (api 280k + sub 280k) → 47%
func _settled_data() -> Dictionary:
	return {
		"settled": true,
		"turn": 7,
		"api_total": 800_000,
		"sub_total": 400_000,
		"grand_total": 1_200_000,
		"api_demand_lost": 0,
		"groups": [
			{
				"model_id": &"cedar", "display_name": "Cedar-7B",
				"total": 640_000, "api": 520_000, "sub": 120_000,
				"products": [
					{"name": "Cedar API", "kind": &"api", "amount": 520_000},
					{"name": "Cedar Chat", "kind": &"sub", "amount": 120_000},
				],
			},
			{
				"model_id": &"maple", "display_name": "Maple-3B",
				"total": 560_000, "api": 280_000, "sub": 280_000,
				"products": [
					{"name": "Maple API", "kind": &"api", "amount": 280_000},
					{"name": "Maple Chat", "kind": &"sub", "amount": 280_000},
				],
			},
		],
		"demand_rows": [
			{"display_name": "Cedar-7B", "total": 50_000, "sub": 30_000, "api": 20_000},
		],
	}

# ─── 未结算空态 ──────────────────────────────────────────────

func test_not_settled_shows_hint_and_no_groups() -> void:
	var v := _make()
	v.refresh({"settled": false})
	await get_tree().process_frame
	assert_false(v.is_settled_for_test(), "settled=false 应进入空态")
	assert_eq(v.group_ids_for_test().size(), 0, "空态不渲染分组")
	var labels: PackedStringArray = v.all_label_texts_for_test()
	var found := false
	for t in labels:
		if String(t).find("尚未结算") != -1:
			found = true
	assert_true(found, "未结算应显示 '(尚未结算)' 提示, 实际: %s" % str(labels))

# ─── KPI chip ────────────────────────────────────────────────

func test_three_chips_show_total_api_sub() -> void:
	var v := _make()
	v.refresh(_settled_data())
	await get_tree().process_frame
	# 紧凑金额: 1.2M / 800k / 400k。
	assert_string_contains(v.get_chip_value_for_test(0), "1.2M")
	assert_string_contains(v.get_chip_value_for_test(1), "800k")
	assert_string_contains(v.get_chip_value_for_test(2), "400k")

func test_billions_use_B_suffix_not_G() -> void:
	# 钱的十亿量级用 B (不是 token 量纲的 G)。
	var v := _make()
	var data := _settled_data()
	data["api_total"] = 4_200_000_000
	data["sub_total"] = 1_000_000_000
	data["grand_total"] = 5_200_000_000
	v.refresh(data)
	await get_tree().process_frame
	assert_string_contains(v.get_chip_value_for_test(0), "5.2B")
	assert_string_contains(v.get_chip_value_for_test(1), "4.2B")
	for i in range(3):
		assert_eq(v.get_chip_value_for_test(i).find("G"), -1,
			"钱不该出现 G 后缀 (chip %d: %s)" % [i, v.get_chip_value_for_test(i)])

# ─── 来源占比条 ──────────────────────────────────────────────

func test_source_bar_splits_api_and_sub_by_grand_total() -> void:
	var v := _make()
	v.refresh(_settled_data())
	await get_tree().process_frame
	var bar: Control = v.get_source_bar_for_test()
	assert_not_null(bar, "应有来源占比条")
	var fr: Array = bar.get_fill_fractions_for_test()
	assert_eq(fr.size(), 2, "来源条两段: API + 订阅")
	assert_almost_eq(float(fr[0]), 800_000.0 / 1_200_000.0, 0.001)
	assert_almost_eq(float(fr[1]), 400_000.0 / 1_200_000.0, 0.001)

func test_source_value_label_shows_rounded_percentages() -> void:
	var v := _make()
	v.refresh(_settled_data())
	await get_tree().process_frame
	var txt: String = v.get_source_value_text_for_test()
	assert_string_contains(txt, "67")   # 800/1200 = 66.7% → 67
	assert_string_contains(txt, "33")   # 400/1200 = 33.3% → 33

# ─── 分组 ────────────────────────────────────────────────────

func test_groups_render_in_given_order() -> void:
	var v := _make()
	v.refresh(_settled_data())
	await get_tree().process_frame
	var ids: Array = v.group_ids_for_test()
	assert_eq(ids, [&"cedar", &"maple"])

func test_group_header_shows_model_name_amount_and_share_pct() -> void:
	var v := _make()
	v.refresh(_settled_data())
	await get_tree().process_frame
	assert_string_contains(v.get_group_amount_text_for_test(&"cedar"), "640k")
	assert_string_contains(v.get_group_pct_text_for_test(&"cedar"), "53")   # 640/1200
	var labels: PackedStringArray = v.all_label_texts_for_test()
	var has_name := false
	for t in labels:
		if String(t).find("Cedar-7B") != -1:
			has_name = true
	assert_true(has_name, "分组头应显示模型 display_name")

func test_group_bar_uses_grand_total_denominator_with_api_sub_split() -> void:
	var v := _make()
	v.refresh(_settled_data())
	await get_tree().process_frame
	var bar: Control = v.find_group_bar_for_test(&"cedar")
	assert_not_null(bar)
	var fr: Array = bar.get_fill_fractions_for_test()
	# 两段 (api 520k + sub 120k), 分母 grand 1.2M → 0.433 + 0.10。
	assert_eq(fr.size(), 2)
	assert_almost_eq(float(fr[0]), 520_000.0 / 1_200_000.0, 0.001)
	assert_almost_eq(float(fr[1]), 120_000.0 / 1_200_000.0, 0.001)

func test_groups_default_expanded_and_show_product_rows() -> void:
	var v := _make()
	v.refresh(_settled_data())
	await get_tree().process_frame
	assert_true(v.is_group_expanded_for_test(&"cedar"), "模型分组默认展开")
	assert_string_contains(v.get_group_caret_for_test(&"cedar"), "▼")
	var labels: PackedStringArray = v.all_label_texts_for_test()
	var has_product := false
	for t in labels:
		if String(t).find("Cedar API") != -1:
			has_product = true
	assert_true(has_product, "展开时应显示产品行 display_name")

func test_toggle_group_collapses_body() -> void:
	var v := _make()
	v.refresh(_settled_data())
	await get_tree().process_frame
	v.toggle_group_for_test(&"cedar")
	await get_tree().process_frame
	assert_false(v.is_group_expanded_for_test(&"cedar"), "点击后应收起")
	assert_string_contains(v.get_group_caret_for_test(&"cedar"), "▶")

func test_collapse_state_persists_across_refresh() -> void:
	var v := _make()
	v.refresh(_settled_data())
	await get_tree().process_frame
	v.toggle_group_for_test(&"cedar")
	await get_tree().process_frame
	# 模拟回合推进重渲: 同样的数据再 refresh 一次, 展开态不应丢失。
	v.refresh(_settled_data())
	await get_tree().process_frame
	assert_false(v.is_group_expanded_for_test(&"cedar"),
		"refresh 之间应记忆折叠态")

# ─── 算力需求 section ────────────────────────────────────────

func test_demand_section_collapsed_by_default() -> void:
	var v := _make()
	v.refresh(_settled_data())
	await get_tree().process_frame
	assert_false(v.is_demand_expanded_for_test(), "算力需求 section 默认收起")

func test_toggle_demand_expands_section() -> void:
	var v := _make()
	v.refresh(_settled_data())
	await get_tree().process_frame
	v.toggle_demand_for_test()
	await get_tree().process_frame
	assert_true(v.is_demand_expanded_for_test())
