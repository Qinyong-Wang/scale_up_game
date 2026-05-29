extends GutTest

## EventBus — global notification hub. Past-tense signals only; emit and forget.
## Per design/事件总线信号表.md.
##
## 这些测试验证: (1) 所有信号存在; (2) 签名 (参数个数与名字) 与设计文档一致;
## (3) emit/connect 链路工作 (基础 sanity); (4) 命名风格契约 (过去时 + domain 前缀).

func before_each() -> void:
	GameState.reset()

# 期望的信号契约: name -> [(arg_name, type_hint_optional)]
# 与 design/事件总线信号表.md 的列保持一致.
const EXPECTED_SIGNALS: Dictionary = {
	# Lifecycle
	&"state_reset": [],
	&"save_loaded": [],
	# i18n
	&"locale_changed": [&"locale"],
	# Turn
	&"phase_started": [&"phase", &"turn"],
	&"turn_resolved": [&"turn"],
	# Economy
	&"resources_changed": [&"delta", &"reason"],
	&"cash_changed": [&"delta", &"reason"],
	&"debt_changed": [&"delta", &"reason"],
	&"equity_changed": [&"dilution"],
	&"loan_taken": [&"loan_id"],
	&"loan_repaid": [&"loan_id", &"fully"],
	&"funding_completed": [&"amount", &"dilution", &"valuation"],
	&"ledger_rolled": [&"turn", &"snapshot"],
	&"bankruptcy_warning": [&"reason", &"streak", &"threshold"],
	&"bankruptcy_triggered": [&"reason"],
	# Hiring
	&"lead_hired": [&"lead_id"],
	&"lead_fired": [&"lead_id"],
	&"lead_locked": [&"lead_id", &"task_id"],
	&"lead_released": [&"lead_id"],
	&"lead_assigned": [&"lead_id", &"product_id"],
	&"lead_unassigned": [&"lead_id"],
	&"staff_changed": [&"role", &"new_count"],
	&"lead_pool_refreshed": [&"pool"],
	&"player_scientist_created": [&"lead_id"],
	# Infra
	&"datacenter_added": [&"dc_id"],
	&"datacenter_removed": [&"dc_id"],
	&"datacenter_status_changed": [&"dc_id", &"old_status", &"new_status"],
	&"model_deployed": [&"dc_id", &"model_id"],
	&"open_source_model_deployed": [&"dc_id", &"release_id"],
	&"model_undeployed": [&"dc_id", &"model_id"],
	&"construction_progress": [&"construction_id", &"remaining", &"total"],
	&"construction_completed": [&"construction_id", &"dc_id"],
	&"gpus_bought": [&"dc_id", &"gpu_id", &"count", &"total_cost"],
	&"gpus_sold": [&"dc_id", &"count", &"refund"],
	&"dc_compute_recomputed": [&"dc_id", &"train_tflops", &"inference_tflops", &"serving_tokens_per_sec"],
	# Dataset
	&"dataset_added": [&"dataset_id", &"source"],
	&"dataset_removed": [&"dataset_id"],
	&"dataset_locked": [&"dataset_id", &"task_id"],
	&"dataset_released": [&"dataset_id"],
	&"dataset_market_updated": [&"kind"],
	# Research
	&"model_added": [&"model_id", &"provenance"],
	&"model_updated": [&"model_id", &"capability_delta"],
	&"model_evaluated": [&"model_id", &"capability"],
	&"model_published": [&"model_id", &"is_open_source"],
	&"model_unpublished": [&"model_id"],
	&"model_deleted": [&"model_id"],
	&"model_price_changed": [&"model_id", &"new_price"],
	# Tech tree
	&"tech_research_started": [&"tree", &"node_id", &"task_id"],
	&"tech_unlocked": [&"tree", &"node_id"],
	&"tech_research_cancelled": [&"tree", &"node_id"],
	# Tasks
	&"task_started": [&"id", &"subtype"],
	&"task_progress": [&"id", &"elapsed", &"total"],
	&"task_completed": [&"id", &"subtype", &"payload"],
	&"task_cancelled": [&"id", &"refund"],
	&"task_resources_locked": [&"id", &"locked"],
	&"task_resources_released": [&"id", &"released"],
	&"task_delayed": [&"id", &"new_total"],
	# Market (v7 PR-F: fame_changed deleted; v8 PR-H: npc_distilled deleted,
	# replaced with npc_released for timeline-driven NPCs).
	&"leaderboard_resolved": [&"turn"],
	&"player_rank_changed": [&"board", &"old_rank", &"new_rank"],
	&"npc_released": [&"npc_id", &"release_id", &"release_turn"],
	# User
	&"users_resolved": [&"turn", &"paid_users_delta"],
	&"token_demand_changed": [&"model_id", &"new_value"],
	&"paid_users_changed": [&"delta", &"new_total"],
	# Product
	&"product_created": [&"product_id"],
	&"product_updated": [&"product_id", &"changed_fields"],
	&"product_deleted": [&"product_id"],
	&"subscribers_changed": [&"product_id", &"delta", &"new_total"],
	&"quality_recomputed": [&"product_id", &"new_quality"],
	# Monetization
	&"revenue_resolved": [&"turn", &"breakdown"],
	# Marketing
	&"campaign_started": [&"campaign_id"],
	&"campaign_terminated": [&"campaign_id", &"reason"],
	&"campaign_progress": [&"campaign_id", &"remaining", &"total"],
	# Events
	&"event_pushed": [&"event_id", &"category", &"title"],
	&"event_resolved": [&"event_id", &"option_id", &"applied_effects"],
	# Charity
	&"charity_completed": [&"cause_id", &"amount", &"cumulative"],
	# Office / Collection
	&"collectible_bought": [&"collectible_id", &"price"],
	&"collectible_sold": [&"collectible_id", &"proceeds"],
	&"trophy_awarded": [&"trophy_id"],
	# Universe simulation
	&"simulation_stage_completed": [&"stage_id", &"stages_done"],
	&"universe_answer_revealed": [],
}

# ---- 契约: 所有信号必须存在 -------------------------------------------

func test_all_documented_signals_exist() -> void:
	# 设计文档列出的每个信号都必须在 EventBus 上声明.
	for sig_name in EXPECTED_SIGNALS.keys():
		assert_true(EventBus.has_signal(sig_name),
				"EventBus 缺少信号 %s (设计文档已登记)" % sig_name)

func test_signal_arg_counts_match_design_doc() -> void:
	var by_name: Dictionary = {}
	for s in EventBus.get_signal_list():
		by_name[StringName(s.name)] = s
	for sig_name in EXPECTED_SIGNALS.keys():
		var expected_args: Array = EXPECTED_SIGNALS[sig_name]
		if not by_name.has(sig_name):
			fail_test("缺少信号 %s" % sig_name)
			continue
		var actual_args: Array = by_name[sig_name].args
		assert_eq(actual_args.size(), expected_args.size(),
				"信号 %s 参数个数: 期望 %d, 实际 %d" %
				[sig_name, expected_args.size(), actual_args.size()])

func test_signal_arg_names_match_design_doc() -> void:
	# 不仅个数, 名字也要对 — UI / 订阅方按名读字段.
	var by_name: Dictionary = {}
	for s in EventBus.get_signal_list():
		by_name[StringName(s.name)] = s
	for sig_name in EXPECTED_SIGNALS.keys():
		var expected_args: Array = EXPECTED_SIGNALS[sig_name]
		if not by_name.has(sig_name) or by_name[sig_name].args.size() != expected_args.size():
			continue  # 由前两个测试报错
		var actual_args: Array = by_name[sig_name].args
		for i in range(expected_args.size()):
			var actual_name: String = String(actual_args[i].name)
			var expected_name: String = String(expected_args[i])
			assert_eq(actual_name, expected_name,
					"信号 %s 第 %d 参数名不一致: 期望 %s, 实际 %s" %
					[sig_name, i, expected_name, actual_name])

func test_no_project_signal_missing_from_contract_table() -> void:
	# EventBus 是信号声明表: 新增信号必须同步本测试与 design/事件总线信号表.md。
	var script_signals: Array = EventBus.get_script().get_script_signal_list()
	for s in script_signals:
		assert_true(EXPECTED_SIGNALS.has(StringName(s.name)),
				"EventBus 信号 %s 已声明但未进契约表" % String(s.name))

# ---- 命名风格契约 ------------------------------------------------------

func test_signal_names_use_past_tense_or_state_change_form() -> void:
	# §约定: <domain>_<past_tense_verb>. 至少应用 _ 分段, 不应是命令式.
	# 只校验本项目自己声明的信号 (即 EXPECTED_SIGNALS), 跳过 Node 内置信号 (ready / renamed 等).
	var current_form_blacklist: Array[String] = [
		"add_", "remove_", "create_", "delete_", "start_", "stop_",
		"resolve_", "send_", "emit_", "register_",
	]
	for sig_name in EXPECTED_SIGNALS.keys():
		var name: String = String(sig_name)
		if name in ["state_reset", "save_loaded"]:
			continue
		assert_true(name.find("_") != -1, "信号名 %s 应有 domain_ 前缀" % name)
		for prefix in current_form_blacklist:
			assert_false(name.begins_with(prefix),
					"信号 %s 使用现在时前缀 %s, 应改过去时" % [name, prefix])

# ---- emit / connect 基础链路 ------------------------------------------

func test_state_reset_emits_with_no_args() -> void:
	watch_signals(EventBus)
	GameState.reset()
	assert_signal_emitted(EventBus, "state_reset")

func test_phase_started_relays_phase_and_turn() -> void:
	watch_signals(EventBus)
	EventBus.phase_started.emit(&"action", 7)
	var p: Array = get_signal_parameters(EventBus, "phase_started")
	assert_eq(p[0], &"action")
	assert_eq(p[1], 7)

func test_turn_resolved_passes_turn_int() -> void:
	watch_signals(EventBus)
	EventBus.turn_resolved.emit(12)
	var p: Array = get_signal_parameters(EventBus, "turn_resolved")
	assert_eq(p[0], 12)

func test_resources_changed_dictionary_payload_preserved() -> void:
	watch_signals(EventBus)
	EventBus.resources_changed.emit({&"money": -100, &"compute": 5}, &"test")
	var p: Array = get_signal_parameters(EventBus, "resources_changed")
	var delta: Dictionary = p[0]
	assert_eq(delta[&"money"], -100)
	assert_eq(delta[&"compute"], 5)
	assert_eq(p[1], &"test")

func test_subscribers_can_attach_and_receive() -> void:
	# Sanity: 不通过中间 system, 直接 connect 一个 lambda 收信号.
	var received: Array = []
	var cb := func(turn: int): received.append(turn)
	EventBus.turn_resolved.connect(cb)
	EventBus.turn_resolved.emit(99)
	EventBus.turn_resolved.disconnect(cb)
	assert_eq(received, [99])

func test_disconnect_stops_delivery() -> void:
	var received: Array = []
	var cb := func(turn: int): received.append(turn)
	EventBus.turn_resolved.connect(cb)
	EventBus.turn_resolved.disconnect(cb)
	EventBus.turn_resolved.emit(99)
	assert_eq(received, [])

func test_users_resolved_chains_into_revenue_resolved() -> void:
	# 关键信号链 §156: users_resolved → MonetizationSystem 订阅 → revenue_resolved.
	watch_signals(EventBus)
	EventBus.users_resolved.emit(1, 0)
	assert_signal_emitted(EventBus, "revenue_resolved",
			"users_resolved → revenue_resolved 链应自动触发")

func test_state_reset_signal_arity_zero() -> void:
	# Lifecycle 中只有 state_reset / save_loaded 是 0 参; 这个测试钉住.
	var by_name: Dictionary = {}
	for s in EventBus.get_signal_list():
		by_name[s.name] = s
	for name in ["state_reset", "save_loaded"]:
		assert_true(by_name.has(name), "缺少 lifecycle 信号 %s" % name)
		assert_eq((by_name[name].args as Array).size(), 0,
				"%s 应为 0 参数信号" % name)
