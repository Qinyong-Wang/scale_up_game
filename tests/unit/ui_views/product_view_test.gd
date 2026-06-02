extends GutTest

## ProductView 单测 — §10 step 6 第三批 (产品)。

const ProductViewScene := preload("res://scenes/ui/views/product_view/product_view.tscn")

func _make() -> Control:
	var v: Control = ProductViewScene.instantiate()
	add_child_autofree(v)
	return v

func _product(id: StringName, display_name: String, type: StringName, subs: int = 100) -> Product:
	var p := Product.new()
	p.id = id
	p.display_name = display_name
	p.type = type
	p.bound_model_id = &"wolf_os"
	p.subscription_price = 49
	p.subscribers = subs
	p.quality = 0.7
	p.launched_at_turn = 1
	return p

func _default_data() -> Dictionary:
	return {
		"products": [],
		"has_published_model": false,
		"pool_rows": [],     # Array of {model_id, display_name, capacity, demand, sub_demand, api_demand, util_pct, warn}
	}

# ─── 创建入口 ────────────────────────────────────────────────

func test_create_button_renders_when_published_model_exists() -> void:
	var v := _make()
	var data := _default_data()
	data["has_published_model"] = true
	v.refresh(data)
	await get_tree().process_frame
	var btns: PackedStringArray = v.all_button_texts_for_test()
	var found := false
	for t in btns:
		if String(t).find("创建产品") != -1:
			found = true
	assert_true(found, "应当含 '+ 创建产品...' 按钮")

func test_create_button_is_shrink_not_full_width() -> void:
	# 创建产品按钮应收紧, 不占满整屏 (design §9)。
	var v := _make()
	var data := _default_data()
	data["has_published_model"] = true
	v.refresh(data)
	await get_tree().process_frame
	assert_eq(v._create_btn.size_flags_horizontal, Control.SIZE_SHRINK_BEGIN,
		"创建产品按钮不应 SIZE_FILL 铺满整屏")

func test_create_button_uses_prominent_cta_style() -> void:
	var v := _make()
	var data := _default_data()
	data["has_published_model"] = true
	v.refresh(data)
	await get_tree().process_frame
	assert_gte(int(v._create_btn.custom_minimum_size.y), 40,
		"创建产品按钮应使用更醒目的 create CTA 高度")
	var normal: StyleBox = v._create_btn.get_theme_stylebox(&"normal")
	assert_true(normal is StyleBoxFlat)
	if normal is StyleBoxFlat:
		assert_true((normal as StyleBoxFlat).bg_color.is_equal_approx(UITheme.ACCENT_INFO),
			"创建产品按钮应是炭黑实心主按钮")

func test_no_published_model_hint_replaces_button() -> void:
	var v := _make()
	v.refresh(_default_data())  # has_published_model = false
	await get_tree().process_frame
	var labels: PackedStringArray = v.all_label_texts_for_test()
	var found_hint := false
	for t in labels:
		if String(t).find("需要先发布至少一个模型") != -1:
			found_hint = true
	assert_true(found_hint, "无 published 模型时显示提示, 不显示创建按钮")

func test_create_button_emits_signal() -> void:
	var v := _make()
	var data := _default_data()
	data["has_published_model"] = true
	v.refresh(data)
	await get_tree().process_frame
	watch_signals(v)
	v.click_new_product_for_test()
	assert_signal_emitted(v, "new_product_pressed")

# ─── 算力池 section ──────────────────────────────────────────

func test_compute_pool_section_renders_when_rows_present() -> void:
	var v := _make()
	var data := _default_data()
	data["pool_rows"] = [{
		"model_id": &"wolf_os", "display_name": "Wolf",
		"capacity": 100_000, "demand": 50_000,
		"sub_demand": 30_000, "api_demand": 20_000,
		"util_pct": 50.0,
	}]
	v.refresh(data)
	await get_tree().process_frame
	var labels: PackedStringArray = v.all_label_texts_for_test()
	var has_section := false
	for t in labels:
		if String(t).find("算力池") != -1:
			has_section = true
	assert_true(has_section, "有 pool_rows 时显示 '算力池' section")

func test_pool_header_red_when_capacity_zero() -> void:
	# 老集成测试要求: capacity=0 时 header label 红色 (容量 0 t/s)。
	var v := _make()
	var data := _default_data()
	data["pool_rows"] = [{
		"model_id": &"wolf_os", "display_name": "Wolf",
		"capacity": 0, "demand": 5_000,
		"sub_demand": 5_000, "api_demand": 0,
		"util_pct": 0.0,
	}]
	v.refresh(data)
	await get_tree().process_frame
	var lbl: Label = v.find_pool_header_for_test(&"wolf_os")
	assert_not_null(lbl, "应找到 wolf_os 的 pool header label")
	if lbl != null:
		var c: Color = lbl.get_theme_color(&"font_color")
		assert_gt(c.r, 0.9, "capacity=0 header 应红色 (got %s)" % str(c))
		assert_lt(c.g, 0.7, "capacity=0 header 应红色")

func test_pool_header_yellow_when_util_above_80() -> void:
	var v := _make()
	var data := _default_data()
	data["pool_rows"] = [{
		"model_id": &"wolf_os", "display_name": "Wolf",
		"capacity": 100_000, "demand": 85_000,
		"sub_demand": 50_000, "api_demand": 35_000,
		"util_pct": 85.0,
	}]
	v.refresh(data)
	await get_tree().process_frame
	var lbl: Label = v.find_pool_header_for_test(&"wolf_os")
	assert_not_null(lbl)
	if lbl != null:
		var c: Color = lbl.get_theme_color(&"font_color")
		# 黄色: r 高 + g 较高 + b 低。
		assert_gt(c.r, 0.9)
		assert_gt(c.g, 0.7)
		assert_lt(c.b, 0.6)

func test_pool_header_uses_compact_tps_labels() -> void:
	# capacity/demand 是 tokens/周 (1 turn = 1 week), 显示前除 SECONDS_PER_WEEK 转
	# t/s。1.39B tok/周 ≈ 2.3k t/s; 5.14B tok/周 ≈ 8.5k t/s — 与营收 tab 同源,
	# 不再把 tok/周 错当 t/s 显示成 1.39B/5.14B t/s。
	var v := _make()
	var data := _default_data()
	data["pool_rows"] = [{
		"model_id": &"wolf_os", "display_name": "Wolf",
		"capacity": 1_391_040_000, "demand": 5_140_800_000,
		"sub_demand": 5_140_800_000, "api_demand": 0,
		"util_pct": 372.0,
	}]
	v.refresh(data)
	await get_tree().process_frame
	var labels: PackedStringArray = v.all_label_texts_for_test()
	var joined := "\n".join(labels)
	assert_true(joined.find("2.3k t/s") != -1, "容量应显示为 t/s 量级, 实际: %s" % joined)
	assert_true(joined.find("8.5k t/s") != -1, "需求应显示为 t/s 量级, 实际: %s" % joined)
	assert_false(joined.find("B t/s") != -1,
			"不应出现 'B t/s' 这种数量级错误 (那是把 tok/周当 t/s)")
	assert_false(joined.find("1391040000") != -1, "不应显示十位以上裸整数")
	assert_false(joined.find("5140800000") != -1, "不应显示十位以上裸整数")

func test_pool_header_uses_chinese_occupancy_label_and_caps_extreme_util() -> void:
	var v := _make()
	var data := _default_data()
	data["pool_rows"] = [{
		"model_id": &"wolf_os", "display_name": "Wolf",
		"capacity": 1_000, "demand": 25_000,
		"sub_demand": 25_000, "api_demand": 0,
		"util_pct": 2500.0,
	}]
	v.refresh(data)
	await get_tree().process_frame
	var lbl: Label = v.find_pool_header_for_test(&"wolf_os")
	assert_not_null(lbl)
	if lbl == null:
		return
	assert_ne(lbl.text.find("占用"), -1)
	assert_eq(lbl.text.find("util"), -1, "玩家界面不显示 raw util")
	assert_ne(lbl.text.find(">999%"), -1, "极端超载用上限文案, 避免 62346% 这种视觉噪音")
	assert_eq(lbl.text.find("2500%"), -1)

# ─── 产品卡片 ────────────────────────────────────────────────

func test_subscription_product_renders_with_quality_and_subscribers() -> void:
	var v := _make()
	var data := _default_data()
	data["products"] = [_product(&"p1", "MyChat", &"chatbot", 200)]
	v.refresh(data)
	await get_tree().process_frame
	var fields: Dictionary = v.get_card_fields_for_test(&"p1")
	# 至少含订阅数 / 质量 / 绑定模型字段。
	var has_subs := false
	for v_str in fields.values():
		if String(v_str).find("200") != -1:
			has_subs = true
	assert_true(has_subs, "subscription 卡片应当显示订阅数, 实际字段: %s" % str(fields))

func test_product_card_uses_bound_model_display_label() -> void:
	var v := _make()
	var data := _default_data()
	data["products"] = [_product(&"p1", "MyChat", &"chatbot", 200)]
	data["model_labels"] = {&"wolf_os": "Wolf Prime"}
	v.refresh(data)
	await get_tree().process_frame
	var subtitle: String = v.get_card_subtitle_for_test(&"p1")
	assert_ne(subtitle.find("Wolf Prime"), -1)
	assert_eq(subtitle.find("wolf_os"), -1, "产品卡片不应显示绑定模型内部 id")

func test_product_card_uses_compact_tps_fields() -> void:
	# ProductCard 也走每周 token → t/s. 5.1408B tok/周 ≈ 8.5k t/s。
	var v := _make()
	var data := _default_data()
	data["products"] = [
		_product(&"p_sub", "OpenChat Pro", &"chatbot", 439),
		_product(&"p_api", "API endpoint", &"api"),
	]
	data["api_demand_per_product"] = {&"p_api": 5_140_800_000}
	data["sub_tps_per_product"] = {&"p_sub": 5_140_800_000}
	v.refresh(data)
	await get_tree().process_frame
	var sub_fields: Dictionary = v.get_card_fields_for_test(&"p_sub")
	var api_fields: Dictionary = v.get_card_fields_for_test(&"p_api")
	assert_eq(sub_fields.get("t/s 占用", ""), "8.5k t/s")
	assert_eq(api_fields.get("需求", ""), "8.5k t/s")
	assert_false(str(sub_fields).find("5,140,800,000") != -1,
		"订阅产品卡片不应显示十位以上裸整数")
	assert_false(str(api_fields).find("5,140,800,000") != -1,
		"API 产品卡片不应显示十位以上裸整数")
	assert_false(str(sub_fields).find("B t/s") != -1,
		"订阅卡片不应出现 'B t/s' (单位错位)")
	assert_false(str(api_fields).find("B t/s") != -1,
		"API 卡片不应出现 'B t/s' (单位错位)")

func test_pool_and_product_card_render_same_weekly_demand_tps() -> void:
	# 横向一致性: 同一份 weekly demand 进入 pool row 和 ProductCard 时, 两处 t/s
	# 文案必须一致; 防止某个局部 helper 又退回按月秒数折算。
	var v := _make()
	var data := _default_data()
	data["products"] = [_product(&"p_sub", "OpenChat Pro", &"chatbot", 439)]
	data["pool_rows"] = [{
		"model_id": &"wolf_os", "display_name": "Wolf",
		"capacity": 10_000_000_000, "demand": 5_140_800_000,
		"sub_demand": 5_140_800_000, "api_demand": 0,
		"util_pct": 51.4,
	}]
	data["sub_tps_per_product"] = {&"p_sub": 5_140_800_000}
	v.refresh(data)
	await get_tree().process_frame
	var pool_header: Label = v.find_pool_header_for_test(&"wolf_os")
	assert_not_null(pool_header)
	if pool_header != null:
		assert_ne(pool_header.text.find("8.5k t/s"), -1,
			"算力池需求应按周量折算, 实际: %s" % pool_header.text)
	var fields: Dictionary = v.get_card_fields_for_test(&"p_sub")
	assert_eq(fields.get("t/s 占用", ""), "8.5k t/s",
			"产品卡片应与算力池需求使用同一周量 t/s 口径")

func test_api_product_shows_api_badge_or_label() -> void:
	# 老集成测试要求 "[API]" 字符串出现。
	var v := _make()
	var data := _default_data()
	data["products"] = [_product(&"p_api", "API endpoint", &"api")]
	v.refresh(data)
	await get_tree().process_frame
	var labels: PackedStringArray = v.all_label_texts_for_test()
	var found := false
	for t in labels:
		if String(t).find("[API]") != -1:
			found = true
	assert_true(found, "api 产品应当显示 [API] 标签, 实际 labels: %s" % str(labels))

func test_subscription_card_has_edit_and_delete_actions() -> void:
	var v := _make()
	var data := _default_data()
	data["products"] = [_product(&"p1", "MyChat", &"chatbot")]
	v.refresh(data)
	await get_tree().process_frame
	var actions: Array = v.get_card_actions_for_test(&"p1")
	assert_true(actions.has(&"edit"))
	assert_true(actions.has(&"delete"))

func test_api_card_has_edit_and_delete_actions() -> void:
	var v := _make()
	var data := _default_data()
	data["products"] = [_product(&"p_api", "API", &"api")]
	v.refresh(data)
	await get_tree().process_frame
	var actions: Array = v.get_card_actions_for_test(&"p_api")
	assert_true(actions.has(&"edit"))
	assert_true(actions.has(&"delete"))

func test_api_card_shows_guidance_and_base_cost_when_provided() -> void:
	# Per design/产品系统设计.md ProductCard 显示契约: API 卡片需要除现有的
	# 单价 / 需求 / 上周营收外, 再显示 推理成本 + 指导价。
	var v := _make()
	var data := _default_data()
	data["products"] = [_product(&"p_api", "API endpoint", &"api")]
	data["api_pricing_per_product"] = {
		&"p_api": {
			&"base_price": 1.0e-8,        # $1e-8/tok = $0.01/M tok
			&"guidance_price": 4.0e-7,    # $4e-7/tok = $0.40/M tok (closed=40×)
		}
	}
	v.refresh(data)
	await get_tree().process_frame
	var fields: Dictionary = v.get_card_fields_for_test(&"p_api")
	assert_true(fields.has("推理成本"),
			"API 卡片应显示推理成本, 实际字段: %s" % str(fields.keys()))
	assert_true(fields.has("指导价"),
			"API 卡片应显示指导价, 实际字段: %s" % str(fields.keys()))

func test_subscription_card_shows_reference_price_when_provided() -> void:
	# 订阅产品 ProductCard 多一个「参考订阅价」字段 (= ProductTypeSpec.subscription_price_guidance).
	var v := _make()
	var data := _default_data()
	data["products"] = [_product(&"p_sub", "MyChat Pro", &"chatbot")]
	data["sub_guidance_per_product"] = {&"p_sub": 49}
	v.refresh(data)
	await get_tree().process_frame
	var fields: Dictionary = v.get_card_fields_for_test(&"p_sub")
	assert_true(fields.has("参考订阅价"),
			"订阅卡片应显示参考订阅价, 实际字段: %s" % str(fields.keys()))
	assert_true((fields["参考订阅价"] as String).find("49") != -1)

func test_card_action_emits_product_action_signal() -> void:
	var v := _make()
	var data := _default_data()
	data["products"] = [_product(&"p1", "MyChat", &"chatbot")]
	v.refresh(data)
	await get_tree().process_frame
	watch_signals(v)
	v.click_card_action_for_test(&"p1", &"delete")
	await get_tree().process_frame
	assert_signal_emitted_with_parameters(v, "product_action", [&"p1", &"delete"])

func test_empty_products_shows_hint() -> void:
	var v := _make()
	v.refresh(_default_data())
	await get_tree().process_frame
	var labels: PackedStringArray = v.all_label_texts_for_test()
	# "已上线产品" section + "(无)" hint。
	var has_section := false
	for t in labels:
		if String(t).find("已上线产品") != -1:
			has_section = true
	assert_true(has_section)
