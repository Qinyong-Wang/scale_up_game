extends GutTest

## CharityView 视图测试 — 仿 marketing_view_test 模式。
## 视图自身不读 GameState; 通过 refresh(data) 接 dict。
## Per design/慈善系统设计.md §8。

const CharityViewScene := preload("res://scenes/ui/views/charity/charity_view.tscn")

var _view: Control

func before_each() -> void:
	GameState.reset()
	_view = CharityViewScene.instantiate()
	add_child_autofree(_view)

func _cause(cause_id: String, effect: String, tier_idx: int, donated: int,
		in_progress: Array = [], donating: bool = false) -> Dictionary:
	# 顺序爬梯: 已完成档数 = tier_idx + 1 (current_tier_index = tier_done - 1)。
	return {
		id = StringName(cause_id),
		display_name = "测试方向",
		description = "测试描述",
		effect_kind = StringName(effect),
		current_tier_index = tier_idx,
		current_bonus = (0.02 if tier_idx == 0 else 0.0),
		donated = donated,
		tier_done = tier_idx + 1,
		donating = donating,
		tier_amounts = [10_000_000, 100_000_000, 1_000_000_000],
		tier_labels = ["区域级捐助", "国家级捐助", "全球级捐助"],
		tier_bonuses = [0.02, 0.05, 0.08],
		in_progress = in_progress,
	}

func _data(causes: Array, cash: int = 2_000_000_000) -> Dictionary:
	return {cash = cash, causes = causes}

# ---- 空状态 -----------------------------------------------------------

func test_empty_state_renders_no_card() -> void:
	_view.refresh(_data([]))
	assert_eq(_view.get_card_count_for_test(), 0)

func test_three_causes_render_three_cards() -> void:
	_view.refresh(_data([
		_cause("bio_science", "s_tier_weight", -1, 0),
		_cause("fundamental_compute", "valuation_mult", -1, 0),
		_cause("social_welfare", "conversion_mult", -1, 0),
	]))
	assert_eq(_view.get_card_count_for_test(), 3)

# ---- 捐助按钮 + 可负担性 -----------------------------------------------

func test_tier_buttons_present() -> void:
	_view.refresh(_data([_cause("bio_science", "s_tier_weight", -1, 0)]))
	var card: Control = _view.get_card_for_test(&"bio_science")
	assert_not_null(card)
	# 三档 → 三个捐助按钮。
	assert_eq(card.get_action_count(), 3)

func test_click_donate_emits_signal_with_cause_and_tier() -> void:
	# 第 0 档已完成 (tier_idx=0 → tier_done=1) → 下一可捐为第 1 档, 点它。
	_view.refresh(_data([_cause("bio_science", "s_tier_weight", 0, 10_000_000)]))
	watch_signals(_view)
	_view.click_donate_for_test(&"bio_science", 1)
	await get_tree().process_frame
	assert_signal_emitted_with_parameters(_view, "donate_pressed",
			[&"bio_science", 1])

func test_only_next_tier_enabled_others_disabled() -> void:
	# 顺序爬梯: 第 0 档已完成 → donate_0 禁用 (已完成), donate_1 可点 (下一档),
	# donate_2 禁用 (未解锁)。现金充足。
	_view.refresh(_data([_cause("bio_science", "s_tier_weight", 0, 10_000_000)]))
	var card: Control = _view.get_card_for_test(&"bio_science")
	assert_true(card._action_buttons[&"donate_0"].disabled, "已完成档应禁用")
	assert_false(card._action_buttons[&"donate_1"].disabled, "下一可捐档应可点")
	assert_true(card._action_buttons[&"donate_2"].disabled, "未解锁的更高档应禁用")

func test_unaffordable_next_tier_button_disabled() -> void:
	# 下一可捐为第 0 档 (10M), 但现金只有 5M → 禁用。
	_view.refresh(_data([_cause("bio_science", "s_tier_weight", -1, 0)], 5_000_000))
	var card: Control = _view.get_card_for_test(&"bio_science")
	assert_true(card._action_buttons[&"donate_0"].disabled, "买不起下一档应禁用")

func test_in_progress_disables_next_tier_button() -> void:
	# 该方向已有进行中的捐助任务 → 下一档按钮禁用 (一次只捐一档)。
	_view.refresh(_data([_cause("bio_science", "s_tier_weight", -1, 0,
			[{amount = 10_000_000, remaining = 3, total = 4}], true)]))
	var card: Control = _view.get_card_for_test(&"bio_science")
	assert_true(card._action_buttons[&"donate_0"].disabled, "进行中时下一档应禁用")

# ---- 状态徽章 / 加成显示 -----------------------------------------------

func test_status_badge_shows_tier_when_donated() -> void:
	_view.refresh(_data([_cause("bio_science", "s_tier_weight", 0, 10_000_000)]))
	var card: Control = _view.get_card_for_test(&"bio_science")
	assert_eq(card.get_status_label_text(), tr("区域级捐助"))

func test_in_progress_shown_as_field() -> void:
	_view.refresh(_data([_cause("bio_science", "s_tier_weight", -1, 0,
			[{amount = 10_000_000, remaining = 3, total = 4}])]))
	var card: Control = _view.get_card_for_test(&"bio_science")
	# 至少有「进行中」这条字段 (有 in_progress 时多一条)。
	assert_gt(card.get_field_count(), 3)

# ---- 宇宙模拟工程段 ----------------------------------------------------

func _sim_stage(id: String, status: String, can_start: bool = false) -> Dictionary:
	return {id = StringName(id), display_name = "阶段", description = "描述",
			order = 0, cost = 1_000_000_000, weeks = 8, min_tflops = 2.0e7,
			status = status, can_start = can_start, gate_reason = "", remaining_weeks = 0}

func _sim(stages: Array, stages_done: int, revealed: bool) -> Dictionary:
	return {stages_done = stages_done, total = stages.size(),
			revealed = revealed, stages = stages}

func test_sim_stages_render() -> void:
	var sim: Dictionary = _sim([
		_sim_stage("weather", "done"),
		_sim_stage("ocean", "available", true),
		_sim_stage("earth", "locked"),
	], 1, false)
	_view.refresh({cash = 0, causes = [], simulation = sim})
	assert_eq(_view.get_sim_card_count_for_test(), 3)
	assert_false(_view.is_answer_revealed_for_test())

func test_sim_available_start_emits_signal() -> void:
	var sim: Dictionary = _sim([_sim_stage("weather", "available", true)], 0, false)
	_view.refresh({cash = 0, causes = [], simulation = sim})
	watch_signals(_view)
	_view.click_sim_start_for_test(&"weather")
	await get_tree().process_frame
	assert_signal_emitted(_view, "sim_start_pressed")

func test_sim_answer_revealed_when_all_done() -> void:
	var sim: Dictionary = _sim([_sim_stage("universe", "done")], 5, true)
	_view.refresh({cash = 0, causes = [], simulation = sim})
	assert_true(_view.is_answer_revealed_for_test(), "全部完成应揭晓终极答案")
