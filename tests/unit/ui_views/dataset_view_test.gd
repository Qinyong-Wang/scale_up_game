extends GutTest

## DatasetView 单测 — §10 step 6 (数据 tab)。

const DatasetViewScene := preload("res://scenes/ui/views/dataset_view/dataset_view.tscn")

func _make() -> Control:
	var v: Control = DatasetViewScene.instantiate()
	add_child_autofree(v)
	return v

# View 字段访问支持 dict 的 .key 访问; 测试用 dict mock 而非 resource。
func _tmpl(id: StringName, display_name: String, source: StringName, kind: StringName = &"pretrain", price: int = 0, size: float = 1.0, tags: Array = []) -> Dictionary:
	return {
		"id": id, "display_name": display_name, "source": source, "kind": kind,
		"price": price, "size": size, "quality": 0.0,
		"coverage_tags": tags,
	}

func _ds(id: StringName, display_name: String, source: StringName, kind: StringName = &"pretrain", size: float = 1.0, tags: Array = []) -> Dictionary:
	return {
		"id": id, "display_name": display_name, "source": source, "kind": kind,
		"size": size, "quality": 0.7, "locked_by_task_id": &"",
		"coverage_tags": tags,
	}

func _default_data() -> Dictionary:
	return {
		"active_kind": &"pretrain",
		"market_templates": [],
		"owned_datasets": [],
	}

func test_kind_selector_buttons_render() -> void:
	var v := _make()
	v.refresh(_default_data())
	await get_tree().process_frame
	var btns: PackedStringArray = v.all_button_texts_for_test()
	var has_pre := false
	var has_post := false
	for t in btns:
		if String(t).find("预训练") != -1: has_pre = true
		if String(t).find("后训练") != -1: has_post = true
	assert_true(has_pre and has_post)

func test_collect_button_is_shrink_not_full_width() -> void:
	# 自采按钮应收紧, 不占满整屏 (design §9)。
	var v := _make()
	await get_tree().process_frame
	assert_eq(v._collect_btn.size_flags_horizontal, Control.SIZE_SHRINK_BEGIN,
		"自采数据按钮不应 SIZE_FILL 铺满整屏")

func test_collect_button_uses_prominent_cta_style() -> void:
	var v := _make()
	await get_tree().process_frame
	assert_gte(int(v._collect_btn.custom_minimum_size.y), 40,
		"开始采集按钮应使用更醒目的 create CTA 高度")
	var normal: StyleBox = v._collect_btn.get_theme_stylebox(&"normal")
	assert_true(normal is StyleBoxFlat)
	if normal is StyleBoxFlat:
		assert_true((normal as StyleBoxFlat).bg_color.is_equal_approx(UITheme.ACCENT_INFO),
			"开始采集按钮应是炭黑实心主按钮")

func test_kind_switch_emits_signal() -> void:
	var v := _make()
	v.refresh(_default_data())
	await get_tree().process_frame
	watch_signals(v)
	v.click_kind_for_test(&"posttrain")
	assert_signal_emitted_with_parameters(v, "kind_switched", [&"posttrain"])

func test_market_open_source_template_has_acquire_action() -> void:
	var v := _make()
	var data := _default_data()
	data["market_templates"] = [_tmpl(&"ds_open", "Image Corpus v1", &"open_source")]
	v.refresh(data)
	await get_tree().process_frame
	var btns: PackedStringArray = v.all_button_texts_for_test()
	var found := false
	for t in btns:
		if String(t) == "获取":
			found = true
	assert_true(found, "open_source 模板应当显示短 '获取' 按钮, 避免长名称挤坏卡片")

func test_market_purchased_template_has_buy_action() -> void:
	var v := _make()
	var data := _default_data()
	data["market_templates"] = [_tmpl(&"ds_paid", "Math Reasoning Set v1", &"purchased", &"pretrain", 100_000)]
	v.refresh(data)
	await get_tree().process_frame
	var btns: PackedStringArray = v.all_button_texts_for_test()
	var found := false
	for t in btns:
		if String(t).find("购买") != -1 and String(t).find("Math Reasoning Set v1") == -1:
			found = true
	assert_true(found, "purchased 模板应当显示短 '购买' 按钮, 避免长名称挤坏卡片")

func test_market_templates_render_as_cards() -> void:
	var v := _make()
	var data := _default_data()
	data["market_templates"] = [
		_tmpl(&"ds_open", "Image Corpus v1", &"open_source"),
		_tmpl(&"ds_paid", "Math Reasoning Set v1", &"purchased", &"pretrain", 100_000),
	]
	v.refresh(data)
	await get_tree().process_frame
	assert_true(v.has_method("get_market_card_count_for_test"),
		"DatasetView 应暴露市场卡片计数, 表明市场已从长列表迁到 Card/HFlow")
	if not v.has_method("get_market_card_count_for_test"):
		return
	assert_eq(v.get_market_card_count_for_test(), 2)

func test_market_card_keeps_action_with_template_fields() -> void:
	var v := _make()
	var data := _default_data()
	data["market_templates"] = [_tmpl(&"ds_open", "Image Corpus v1", &"open_source", &"pretrain", 0, 50.0)]
	v.refresh(data)
	await get_tree().process_frame
	assert_true(v.has_method("get_market_card_actions_for_test"))
	assert_true(v.has_method("get_market_card_fields_for_test"))
	if not v.has_method("get_market_card_actions_for_test") \
			or not v.has_method("get_market_card_fields_for_test"):
		return
	var actions: Array = v.get_market_card_actions_for_test(&"ds_open")
	var fields: Dictionary = v.get_market_card_fields_for_test(&"ds_open")
	assert_true(actions.has(&"acquire"), "获取动作应在同一张数据集卡片 footer 内")
	assert_eq(fields.get("规模", ""), "50.000B tokens")
	assert_eq(fields.get("来源", ""), "开源")

func test_acquire_click_emits_signal() -> void:
	var v := _make()
	var data := _default_data()
	data["market_templates"] = [_tmpl(&"ds_x", "X", &"open_source")]
	v.refresh(data)
	await get_tree().process_frame
	watch_signals(v)
	v.click_template_action_for_test(&"ds_x", &"acquire")
	await get_tree().process_frame
	assert_signal_emitted_with_parameters(v, "template_action", [&"ds_x", &"acquire"])

func test_collect_button_renders() -> void:
	# 老集成测试 test_dataset_tab_has_collection_launcher 要求 "采集" 按钮。
	var v := _make()
	v.refresh(_default_data())
	await get_tree().process_frame
	var btns: PackedStringArray = v.all_button_texts_for_test()
	var found := false
	for t in btns:
		if String(t).find("采集") != -1:
			found = true
	assert_true(found, "应有 '开始采集...' 按钮")

func test_collect_emits_signal() -> void:
	var v := _make()
	v.refresh(_default_data())
	await get_tree().process_frame
	watch_signals(v)
	v.click_collect_for_test()
	assert_signal_emitted(v, "collect_pressed")

func test_owned_dataset_renders_with_delete_when_unlocked() -> void:
	var v := _make()
	var data := _default_data()
	data["owned_datasets"] = [_ds(&"mine", "My Set", &"open_source")]
	v.refresh(data)
	await get_tree().process_frame
	var btns: PackedStringArray = v.all_button_texts_for_test()
	var has_delete := false
	for t in btns:
		if String(t).find("删除") != -1:
			has_delete = true
	assert_true(has_delete)

func test_owned_dataset_renders_as_card_with_delete_action() -> void:
	var v := _make()
	var data := _default_data()
	data["owned_datasets"] = [_ds(&"mine", "My Set", &"open_source")]
	v.refresh(data)
	await get_tree().process_frame
	assert_true(v.has_method("get_owned_card_count_for_test"))
	assert_true(v.has_method("get_owned_card_actions_for_test"))
	if not v.has_method("get_owned_card_count_for_test") \
			or not v.has_method("get_owned_card_actions_for_test"):
		return
	assert_eq(v.get_owned_card_count_for_test(), 1)
	assert_true(v.get_owned_card_actions_for_test(&"mine").has(&"delete"),
		"删除动作应在同一张我的数据集卡片 footer 内")

func test_owned_dataset_filters_by_active_kind() -> void:
	var v := _make()
	var data := _default_data()
	data["active_kind"] = &"posttrain"
	data["owned_datasets"] = [
		_ds(&"mine_pre", "P", &"open_source", &"pretrain"),
		_ds(&"mine_post", "Q", &"open_source", &"posttrain"),
	]
	v.refresh(data)
	await get_tree().process_frame
	var labels: PackedStringArray = v.all_label_texts_for_test()
	var has_q := false
	var has_p := false
	for t in labels:
		if String(t).find("Q") != -1: has_q = true
		if String(t).find("P") != -1: has_p = true
	assert_true(has_q, "active_kind=posttrain 时应显示 Q (posttrain)")
	assert_false(has_p, "active_kind=posttrain 时不应显示 pretrain 的 P")

# ─── 来源 / 规模筛选 ──────────────────────────────────────────

func test_source_filter_hides_nonmatching_market_cards() -> void:
	var v := _make()
	var data := _default_data()
	data["market_templates"] = [
		_tmpl(&"ds_open", "Open Set", &"open_source"),
		_tmpl(&"ds_paid", "Paid Set", &"purchased", &"pretrain", 100_000),
	]
	v.refresh(data)
	await get_tree().process_frame
	assert_eq(v.get_visible_market_count_for_test(), 2, "默认 (全部) 两张卡都可见")
	v.click_source_filter_for_test(&"open_source")
	assert_eq(v.get_visible_market_count_for_test(), 1, "只筛开源后只剩 1 张")

func test_size_filter_buckets_market_by_b_tokens() -> void:
	var v := _make()
	var data := _default_data()
	data["market_templates"] = [
		_tmpl(&"small_ds", "Small", &"open_source", &"pretrain", 0, 5.0),
		_tmpl(&"mid_ds", "Mid", &"open_source", &"pretrain", 0, 200.0),
		_tmpl(&"large_ds", "Large", &"open_source", &"pretrain", 0, 5000.0),
	]
	v.refresh(data)
	await get_tree().process_frame
	v.click_size_filter_for_test(&"small")
	assert_eq(v.get_visible_market_count_for_test(), 1, "≤10B 只剩 Small")
	v.click_size_filter_for_test(&"small")  # 再点一次取消 → 回到全部
	assert_eq(v.get_visible_market_count_for_test(), 3)
	v.click_size_filter_for_test(&"large")
	assert_eq(v.get_visible_market_count_for_test(), 1, ">1000B 只剩 Large")

func test_source_and_size_filters_intersect() -> void:
	var v := _make()
	var data := _default_data()
	data["market_templates"] = [
		_tmpl(&"a", "A", &"open_source", &"pretrain", 0, 5.0),
		_tmpl(&"b", "B", &"open_source", &"pretrain", 0, 5000.0),
		_tmpl(&"c", "C", &"purchased", &"pretrain", 100, 5.0),
	]
	v.refresh(data)
	await get_tree().process_frame
	v.click_source_filter_for_test(&"open_source")
	v.click_size_filter_for_test(&"small")
	assert_eq(v.get_visible_market_count_for_test(), 1,
		"仅 A 同时满足 开源 且 ≤10B")

## coverage_tags 在 .tres 上明确写了 (例: `[code, languages]`), 但卡片只显示
## 来源/模态/规模, 玩家看不到这些标签 → 不知道一个数据集到底覆盖哪些方向。
## 市场模板 + 我的数据集两边都要补「标签」字段。
func test_market_card_shows_coverage_tags() -> void:
	var v := _make()
	var data := _default_data()
	data["market_templates"] = [_tmpl(&"ds_code", "Code Set", &"open_source",
			&"pretrain", 0, 50.0, [&"code", &"languages"])]
	v.refresh(data)
	await get_tree().process_frame
	var fields: Dictionary = v.get_market_card_fields_for_test(&"ds_code")
	var tags_val: String = String(fields.get("标签", ""))
	assert_string_contains(tags_val, "代码", "市场卡片应显示 coverage_tags 中的 'code' 中文标签")
	assert_string_contains(tags_val, "语言", "市场卡片应显示 coverage_tags 中的 'languages' 中文标签")
	assert_eq(tags_val.find("languages"), -1, "玩家界面不应显示内部 tag id")

func test_owned_card_shows_coverage_tags() -> void:
	var v := _make()
	var data := _default_data()
	data["owned_datasets"] = [_ds(&"mine_tagged", "Mine", &"open_source",
			&"pretrain", 5.0, [&"web", &"books"])]
	v.refresh(data)
	await get_tree().process_frame
	var fields: Dictionary = _owned_fields(v, &"mine_tagged")
	var tags_val: String = String(fields.get("标签", ""))
	assert_string_contains(tags_val, "网页", "我的数据集卡片应显示 coverage_tags 中的 'web' 中文标签")
	assert_string_contains(tags_val, "书籍", "我的数据集卡片应显示 coverage_tags 中的 'books' 中文标签")
	assert_eq(tags_val.find("books"), -1, "玩家界面不应显示内部 tag id")

func test_dataset_cards_hide_business_analysis_tag() -> void:
	var v := _make()
	var data := _default_data()
	data["market_templates"] = [_tmpl(&"ds_business", "Business Set", &"purchased",
			&"pretrain", 100, 5.0, [&"news", &"business_analysis"])]
	data["owned_datasets"] = [_ds(&"mine_business", "Mine", &"purchased",
			&"pretrain", 5.0, [&"web", &"business_analysis"])]
	v.refresh(data)
	await get_tree().process_frame
	var market_fields: Dictionary = v.get_market_card_fields_for_test(&"ds_business")
	var market_tags: String = String(market_fields.get("标签", ""))
	assert_string_contains(market_tags, "新闻", "普通可见 tag 仍应显示")
	assert_eq(market_tags.find("business"), -1, "隐藏标签不应在市场卡片显示")
	assert_eq(market_tags.find("商业"), -1, "隐藏标签不应在市场卡片显示")
	var owned_fields: Dictionary = _owned_fields(v, &"mine_business")
	var owned_tags: String = String(owned_fields.get("标签", ""))
	assert_string_contains(owned_tags, "网页", "普通可见 tag 仍应显示")
	assert_eq(owned_tags.find("business"), -1, "隐藏标签不应在我的数据集卡片显示")
	assert_eq(owned_tags.find("商业"), -1, "隐藏标签不应在我的数据集卡片显示")

func test_dataset_cards_hide_internal_source_enums() -> void:
	var v := _make()
	var data := _default_data()
	data["market_templates"] = [
		_tmpl(&"ds_open", "Open Set", &"open_source", &"pretrain", 0, 5.0, [&"web"]),
		_tmpl(&"ds_paid", "Paid Set", &"purchased", &"pretrain", 100, 5.0, [&"books"]),
	]
	data["owned_datasets"] = [_ds(&"mine", "Mine", &"collected", &"pretrain", 5.0, [&"code"])]
	v.refresh(data)
	await get_tree().process_frame
	var labels := "\n".join(v.all_label_texts_for_test())
	assert_eq(labels.find("open_source"), -1)
	assert_eq(labels.find("purchased"), -1)
	assert_eq(labels.find("collected"), -1)
	assert_ne(labels.find("开源"), -1)
	assert_ne(labels.find("商业"), -1)
	assert_ne(labels.find("自采"), -1)

## Returns owned-card fields by walking via the _card_fields private path.
## Mirrors get_market_card_fields_for_test but for owned grid (no public
## helper exists yet).
func _owned_fields(v: Control, did: StringName) -> Dictionary:
	if not v.has_method("get_owned_card_fields_for_test"):
		return {}
	return v.get_owned_card_fields_for_test(did)

func test_filter_applies_to_owned_grid() -> void:
	var v := _make()
	var data := _default_data()
	data["owned_datasets"] = [
		_ds(&"o1", "Mine Open", &"open_source", &"pretrain", 5.0),
		_ds(&"o2", "Mine Collected", &"collected", &"pretrain", 5.0),
	]
	v.refresh(data)
	await get_tree().process_frame
	assert_eq(v.get_visible_owned_count_for_test(), 2)
	v.click_source_filter_for_test(&"collected")
	assert_eq(v.get_visible_owned_count_for_test(), 1, "只筛自采后只剩 1 张")
