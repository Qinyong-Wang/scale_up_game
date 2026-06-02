extends GutTest

## ModelCardView 单测 — §10 step 5 模型 tab 试点。
##
## View 是纯展示组件: 接 Array[Model] 进来, 按 filter / search / sort 排出可见
## 卡片, 点 action 按钮 emit (model_id, action_id), 点 "+ 训练新模型" emit
## new_model_pressed。不访问 GameState / EventBus / CommandBus。

const ModelViewScene := preload("res://scenes/ui/views/model_view/model_view.tscn")

func _make() -> Control:
	var v: Control = ModelViewScene.instantiate()
	add_child_autofree(v)
	return v

func _make_model(id: StringName, display_name: String, status: StringName, created: int = 1) -> Model:
	var m := Model.new()
	m.id = id
	m.display_name = display_name
	m.arch = &"ant_v2"
	m.size_params = 7000.0  # 7B
	m.flops_per_token = 7_000_000_000.0
	m.status = status
	m.provenance = &"trained"
	m.trained_at_turn = created
	m.capability_revealed = (status == &"evaluated" or status == &"published")
	if m.capability_revealed:
		m.capability = {
			&"general": 42.0,
			&"code": 38.0,
			&"reasoning": 35.0,
			&"multimodal": 20.0,
			&"agent": 15.0,
		}
	return m

func _seed_four_status() -> Array:
	return [
		_make_model(&"m_pre", "sparrow-pre", &"pretrained", 1),
		_make_model(&"m_post", "sparrow-post", &"posttrained", 2),
		_make_model(&"m_eval", "sparrow-eval", &"evaluated", 3),
		_make_model(&"m_pub", "sparrow-pub", &"published", 4),
	]

# ─── 基本渲染 ─────────────────────────────────────────────────

func test_empty_models_shows_empty_state() -> void:
	var v := _make()
	v.refresh([])
	await get_tree().process_frame
	assert_true(v.is_empty_state_visible())
	assert_eq(v.get_visible_card_count(), 0)

func test_refresh_with_models_creates_cards() -> void:
	var v := _make()
	v.refresh(_seed_four_status())
	await get_tree().process_frame
	assert_eq(v.get_visible_card_count(), 4)
	assert_false(v.is_empty_state_visible())

# ─── status 决定 action 按钮 ─────────────────────────────────

func test_pretrained_card_has_evaluate_action() -> void:
	var v := _make()
	v.refresh([_make_model(&"x", "sparrow", &"pretrained")])
	await get_tree().process_frame
	var actions: Array = v.get_card_action_ids_for_test(&"x")
	assert_true(actions.has(&"evaluate"),
		"pretrained 卡片应当含 evaluate action, 实际: %s" % str(actions))

func test_posttrained_card_has_evaluate_action() -> void:
	var v := _make()
	v.refresh([_make_model(&"x", "sparrow", &"posttrained")])
	await get_tree().process_frame
	assert_true(v.get_card_action_ids_for_test(&"x").has(&"evaluate"))

func test_evaluated_card_has_publish_actions() -> void:
	var v := _make()
	v.refresh([_make_model(&"x", "sparrow", &"evaluated")])
	await get_tree().process_frame
	var actions: Array = v.get_card_action_ids_for_test(&"x")
	assert_true(actions.has(&"publish_closed"))
	assert_true(actions.has(&"publish_open"))

func test_published_card_has_unpublish_and_price_actions() -> void:
	var v := _make()
	v.refresh([_make_model(&"x", "sparrow", &"published")])
	await get_tree().process_frame
	var actions: Array = v.get_card_action_ids_for_test(&"x")
	assert_true(actions.has(&"unpublish"))
	# v8 PR-I: 旧 price_up / price_down 两个按钮换成单个 price_edit 触发对话框。
	assert_true(actions.has(&"price_edit"))
	assert_false(actions.has(&"price_up"))
	assert_false(actions.has(&"price_down"))

func test_all_states_have_delete_action() -> void:
	var v := _make()
	v.refresh(_seed_four_status())
	await get_tree().process_frame
	for id in [&"m_pre", &"m_post", &"m_eval", &"m_pub"]:
		assert_true(v.get_card_action_ids_for_test(id).has(&"delete"),
			"%s 应当含 delete action" % id)

# ─── FilterBar 过滤 ─────────────────────────────────────────

func test_filter_published_shows_only_published() -> void:
	var v := _make()
	v.refresh(_seed_four_status())
	await get_tree().process_frame
	v.set_filter_pill_for_test(&"published")
	await get_tree().process_frame
	assert_eq(v.get_visible_card_count(), 1)
	assert_true(v.is_card_visible_for_test(&"m_pub"))

func test_filter_all_shows_everything() -> void:
	var v := _make()
	v.refresh(_seed_four_status())
	await get_tree().process_frame
	v.set_filter_pill_for_test(&"evaluated")
	await get_tree().process_frame
	v.set_filter_pill_for_test(&"all")
	await get_tree().process_frame
	assert_eq(v.get_visible_card_count(), 4)

# ─── 搜索 ────────────────────────────────────────────────────

func test_search_filters_by_codename_substring() -> void:
	var v := _make()
	v.refresh([
		_make_model(&"a", "sparrow-7B", &"pretrained"),
		_make_model(&"b", "orca-13B", &"pretrained"),
		_make_model(&"c", "sparrow-13B", &"pretrained"),
	])
	await get_tree().process_frame
	v.set_search_text_for_test("sparrow")
	await get_tree().process_frame
	assert_eq(v.get_visible_card_count(), 2)
	assert_true(v.is_card_visible_for_test(&"a"))
	assert_true(v.is_card_visible_for_test(&"c"))
	assert_false(v.is_card_visible_for_test(&"b"))

func test_search_is_case_insensitive() -> void:
	var v := _make()
	v.refresh([_make_model(&"a", "Sparrow-7B", &"pretrained")])
	await get_tree().process_frame
	v.set_search_text_for_test("spar")
	await get_tree().process_frame
	assert_eq(v.get_visible_card_count(), 1)

# ─── 信号 ────────────────────────────────────────────────────

func test_action_button_emits_model_action_with_ids() -> void:
	var v := _make()
	v.refresh([_make_model(&"sparrow_7b", "sparrow", &"pretrained")])
	await get_tree().process_frame
	watch_signals(v)
	v.click_card_action_for_test(&"sparrow_7b", &"evaluate")
	await get_tree().process_frame
	assert_signal_emitted_with_parameters(v, "model_action",
		[&"sparrow_7b", &"evaluate"])

func test_new_model_button_emits_signal() -> void:
	var v := _make()
	v.refresh([])
	await get_tree().process_frame
	watch_signals(v)
	v.click_new_model_for_test()
	await get_tree().process_frame
	assert_signal_emitted(v, "new_model_pressed")

# ─── 卡片字段 ────────────────────────────────────────────────

func test_pretrained_capability_shown_as_unknown() -> void:
	var v := _make()
	v.refresh([_make_model(&"x", "sparrow", &"pretrained")])
	await get_tree().process_frame
	var fields: Dictionary = v.get_card_fields_for_test(&"x")
	# capability 在未评估时显示 总 ?? + 五轴 ??
	var text: String = fields.get("能力", "")
	assert_true(text.begins_with("总 ??"),
		"未评估模型 capability 应以「总 ??」开头, 实际: %s" % text)
	for label in ["通 ??", "码 ??", "推 ??", "多 ??", "Agent ??"]:
		assert_true(text.find(label) != -1,
			"未评估 capability 应含 %s, 实际: %s" % [label, text])

func test_evaluated_capability_shows_numbers() -> void:
	var v := _make()
	v.refresh([_make_model(&"x", "sparrow", &"evaluated")])
	await get_tree().process_frame
	var fields: Dictionary = v.get_card_fields_for_test(&"x")
	# capability_revealed = true, 总分 + 五维数字。42+38+35+20+15 = 150。
	var text: String = fields.get("能力", "")
	assert_true(text.find("总 150") != -1,
		"evaluated capability 应含总分 150, 实际: %s" % text)
	assert_true(text.find("通 42") != -1,
		"应含 general=42, 实际: %s" % text)
	assert_true(text.find("Agent 15") != -1,
		"应含 agent=15, 实际: %s" % text)

# ─── 定价信息可见性 (v8 PR-I) ─────────────────────────────────
# 见 design/研究系统设计.md §4.8: 推理成本 / 指导价必须常显, published 额外
# 显示当前定价比 + 周需求增长率。

func test_pretrained_card_shows_inference_cost_and_guidance() -> void:
	# 评估前的模型也需要显示推理成本和指导价 (评估前还没决定开/闭源, 因此
	# 指导价显示「开源 / 闭源」两档让玩家提前预估发布定价空间)。
	GameState.reset()
	GameState.turn = 0
	var v := _make()
	v.refresh([_make_model(&"x", "sparrow", &"pretrained")])
	await get_tree().process_frame
	var fields: Dictionary = v.get_card_fields_for_test(&"x")
	assert_true(fields.has("推理成本"),
			"pretrained 卡片必须显示推理成本, 实际字段: %s" % str(fields.keys()))
	assert_true(fields.has("指导价"),
			"pretrained 卡片必须显示指导价, 实际字段: %s" % str(fields.keys()))
	# 推理成本是 $X/M tok 格式。
	assert_true((fields["推理成本"] as String).find("/M") != -1,
			"推理成本应为 $X/M 格式, 实际: %s" % fields["推理成本"])

func test_evaluated_card_shows_both_open_and_closed_guidance() -> void:
	# 评估后未发布的模型仍不知最终开/闭源 — 指导价显示两档。
	GameState.reset()
	GameState.turn = 0
	var v := _make()
	v.refresh([_make_model(&"x", "sparrow", &"evaluated")])
	await get_tree().process_frame
	var fields: Dictionary = v.get_card_fields_for_test(&"x")
	var guidance: String = fields.get("指导价", "")
	assert_true(guidance.find("开源") != -1 and guidance.find("闭源") != -1,
			"evaluated 卡片指导价应同时含开源与闭源档, 实际: %s" % guidance)

func test_published_card_shows_single_guidance_matching_open_source_flag() -> void:
	# Published 后开/闭源已锁定, 指导价只显示对应那档, 不再列两档。
	GameState.reset()
	GameState.turn = 0
	var m: Model = _make_model(&"x", "sparrow", &"published")
	m.is_open_source = false
	m.per_token_price = 0.000002
	var v := _make()
	v.refresh([m])
	await get_tree().process_frame
	var fields: Dictionary = v.get_card_fields_for_test(&"x")
	var guidance: String = fields.get("指导价", "")
	# 闭源指导价 = 40×base; 开源指导价 = 2×base; 闭源数值显著大于开源。published
	# 闭源模型不应在指导价字段同时列出开源档。
	assert_false(guidance.find("开源") != -1 and guidance.find("闭源") != -1,
			"published 卡片指导价应只显示一档, 实际: %s" % guidance)

func test_published_card_shows_ratio_and_growth_rate() -> void:
	# Published 模型额外字段: 定价比 (price / guidance) + 周需求增长率。
	GameState.reset()
	GameState.turn = 0
	var m: Model = _make_model(&"x", "sparrow", &"published")
	m.is_open_source = false
	# Pick a price near guidance so ratio shows clearly. Closed guidance = 40×base.
	# Use ResearchSystem-computed base to land exactly at ratio=1.0.
	m.per_token_price = ResearchSystem.guidance_price_per_token(m)
	var v := _make()
	v.refresh([m])
	await get_tree().process_frame
	var fields: Dictionary = v.get_card_fields_for_test(&"x")
	assert_true(fields.has("定价比"),
			"published 卡片应显示定价比, 实际字段: %s" % str(fields.keys()))
	assert_true(fields.has("周需求增长"),
			"published 卡片应显示周需求增长, 实际字段: %s" % str(fields.keys()))
	# At ratio = 1.0 the growth rate is exactly 0 — UI should render "0%" or
	# similar; we just check it doesn't show the 需求归零 warning.
	assert_eq((fields["周需求增长"] as String).find("需求归零"), -1,
			"ratio=1 时不应触发需求归零警告, 实际: %s" % fields["周需求增长"])

func test_published_card_marks_demand_zero_when_growth_rate_minus_one() -> void:
	GameState.reset()
	GameState.turn = 0
	var m: Model = _make_model(&"x", "sparrow", &"published")
	m.is_open_source = false
	# 3× guidance → ratio = 3.0 → 需求归零 (-1.0).
	m.per_token_price = ResearchSystem.guidance_price_per_token(m) * 3.0
	var v := _make()
	v.refresh([m])
	await get_tree().process_frame
	var fields: Dictionary = v.get_card_fields_for_test(&"x")
	var text: String = String(fields.get("周需求增长", ""))
	assert_true(text.find("需求归零") != -1,
			"价格过高应显示「需求归零」警告, 实际: %s" % text)
	assert_eq(text.find("cliff"), -1, "玩家可见文案不应泄露 'cliff' 内部术语")
