extends GutTest

## EventSystem v1 — trigger, choose, dismiss, effect dispatch.
## Per design/事件系统设计.md.


func before_each() -> void:
	GameState.reset()
	GameState.pending_events.clear()
	GameState.event_history.clear()
	GameState.event_cooldowns.clear()

func after_each() -> void:
	# debug_test_offer 是 weight=0 的 debug 夹具 (不进实战随机池)。随机池相关测试
	# 会临时把它的 weight / max_triggers 调大成可抽中候选; 资源是进程级缓存, 这里
	# 兜底复位, 防止污染后续测试 (即便上面的测试中途断言失败也能恢复)。
	var card := EventSystem._load_card(&"debug_test_offer")
	if card != null:
		card.weight = 0
		card.max_triggers = 0

func _seed_player_subboard_rank(rank: int = 1) -> void:
	var entry := LeaderboardEntry.new()
	entry.entity_id = &"player_model_sub"
	entry.entity_type = &"player_model"
	entry.rank = rank
	entry.capability_score = 99.0
	GameState.leaderboard[&"sub_general"] = [entry]

func _seed_player_main_rank(rank: int = 1, board_id: StringName = &"closed_source") -> void:
	var entry := LeaderboardEntry.new()
	entry.entity_id = &"player_model_main"
	entry.entity_type = &"player_model"
	entry.rank = rank
	entry.capability_score = 99.0
	GameState.leaderboard[board_id] = [entry]

func _seed_evaluated_model() -> StringName:
	var r: Dictionary = CommandBus.send(&"research.add_model", {
		arch = &"ant_v1", dataset_ids = []})
	CommandBus.send(&"research.evaluate_apply", {
		model_id = r.model_id,
		capability_measured = {&"general": 80.0, &"code": 80.0, &"reasoning": 80.0},
	})
	return r.model_id

func _seed_published_product() -> void:
	var mid: StringName = _seed_evaluated_model()
	CommandBus.send(&"research.publish_model", {
		model_id = mid, is_open_source = false, per_token_price = 0.001})
	var lead := Lead.new()
	lead.id = &"lead_product"
	lead.specialty = &"chief_engineer"
	lead.level = &"A"
	lead.ability = 80.0
	GameState.leads.append(lead)
	var prod: Dictionary = CommandBus.send(&"product.create", {
		type = &"chatbot", lead_id = lead.id, bound_model_id = mid,
		subscription_price = 99, staff = {}})
	assert_true(prod.ok)

func _seed_product_stub(id: StringName = &"prod_stub") -> void:
	var prod := Product.new()
	prod.id = id
	prod.subscribers = 1000
	GameState.products.append(prod)

# ---- §2 命令: 错误码 ---------------------------------------------------

func test_choose_unknown_event_returns_error() -> void:
	# §2: 未知 event_id → unknown_event.
	var r: Dictionary = CommandBus.send(&"event.choose_option", {
		event_id = &"x", option_id = &"accept"})
	assert_false(r.ok)
	assert_eq(r.error, &"unknown_event")

func test_trigger_unknown_template_returns_error() -> void:
	var r: Dictionary = CommandBus.send(&"event.trigger_card", {template_id = &"foo"})
	assert_false(r.ok)
	assert_eq(r.error, &"unknown_template")

func test_dismiss_flavor_unknown_event_returns_error() -> void:
	var r: Dictionary = CommandBus.send(&"event.dismiss_flavor", {event_id = &"nope"})
	assert_false(r.ok)
	assert_eq(r.error, &"unknown_event")

func test_dismiss_flavor_on_non_flavor_returns_error() -> void:
	# §2: dismiss_flavor 仅可作用于 category == flavor.
	var r1: Dictionary = CommandBus.send(&"event.trigger_card", {template_id = &"debug_test_offer"})
	var r: Dictionary = CommandBus.send(&"event.dismiss_flavor", {event_id = r1.event_id})
	assert_false(r.ok)
	assert_eq(r.error, &"not_flavor")

func test_choose_unknown_option_returns_error() -> void:
	var r1: Dictionary = CommandBus.send(&"event.trigger_card", {template_id = &"debug_test_offer"})
	var r: Dictionary = CommandBus.send(&"event.choose_option", {
		event_id = r1.event_id, option_id = &"nope"})
	assert_false(r.ok)
	assert_eq(r.error, &"unknown_option")

# ---- §6 trigger / 队列 / 历史 -----------------------------------------

func test_trigger_pushes_event_into_pending() -> void:
	var r: Dictionary = CommandBus.send(&"event.trigger_card", {template_id = &"debug_test_offer"})
	assert_true(r.ok)
	assert_eq(GameState.pending_events.size(), 1)
	assert_eq(GameState.pending_events[0].id, r.event_id)
	assert_eq(GameState.pending_events[0].template_id, &"debug_test_offer")
	assert_eq(GameState.pending_events[0].triggered_at_turn, GameState.turn)
	assert_eq(GameState.pending_events[0].resolved_at_turn, -1)
	assert_eq(GameState.pending_events[0].chosen_option_id, &"")

func test_trigger_emits_event_pushed_signal() -> void:
	# §3: trigger → emit event_pushed(event_id, category, title).
	watch_signals(EventBus)
	var r: Dictionary = CommandBus.send(&"event.trigger_card", {template_id = &"debug_test_offer"})
	assert_signal_emitted(EventBus, "event_pushed")
	var p: Array = get_signal_parameters(EventBus, "event_pushed")
	assert_eq(p[0], r.event_id)
	assert_eq(p[1], &"debug")  # debug_test_offer 是 debug 夹具卡

func test_trigger_records_cooldown_for_template() -> void:
	# §4.1: cooldown_months 是设计层"月", 落地到 turn 时按周换算。
	GameState.turn = 5
	CommandBus.send(&"event.trigger_card", {template_id = &"debug_test_offer"})
	# debug_test_offer cooldown_months = 24 → 24 * 4 周。
	assert_eq(int(GameState.event_cooldowns[&"debug_test_offer"]),
			5 + 24 * TurnManager.WEEKS_PER_MONTH)

func test_choose_accept_applies_effects_and_records_history() -> void:
	# accept option awards 1_000_000 cash. v7 PR-F: the legacy +5 fame effect
	# is now a deprecated no-op (fame field deleted), so only cash moves.
	var before_cash: int = GameState.cash
	var r1: Dictionary = CommandBus.send(&"event.trigger_card", {template_id = &"debug_test_offer"})
	var r: Dictionary = CommandBus.send(&"event.choose_option", {
		event_id = r1.event_id, option_id = &"accept"})
	assert_true(r.ok)
	assert_eq(GameState.pending_events.size(), 0)
	assert_eq(GameState.event_history.size(), 1)
	assert_eq(GameState.cash, before_cash + 1_000_000)

func test_choose_refuse_applies_no_effects_but_resolves() -> void:
	# refuse option 没有任何 effect, 但仍然把 event 移到 history.
	var r1: Dictionary = CommandBus.send(&"event.trigger_card", {template_id = &"debug_test_offer"})
	var before_cash: int = GameState.cash
	var r: Dictionary = CommandBus.send(&"event.choose_option", {
		event_id = r1.event_id, option_id = &"refuse"})
	assert_true(r.ok)
	assert_eq(GameState.cash, before_cash)
	assert_eq(GameState.pending_events.size(), 0)
	assert_eq(GameState.event_history.size(), 1)
	assert_eq(GameState.event_history[0].chosen_option_id, &"refuse")

func test_choose_emits_event_resolved_with_applied_effects_array() -> void:
	# §3: event_resolved(event_id, option_id, applied_effects).
	var r1: Dictionary = CommandBus.send(&"event.trigger_card", {template_id = &"debug_test_offer"})
	watch_signals(EventBus)
	CommandBus.send(&"event.choose_option", {event_id = r1.event_id, option_id = &"accept"})
	assert_signal_emitted(EventBus, "event_resolved")
	var p: Array = get_signal_parameters(EventBus, "event_resolved")
	assert_eq(p[0], r1.event_id)
	assert_eq(p[1], &"accept")
	assert_eq((p[2] as Array).size(), 2, "accept 有 2 个 effect (award + fame)")

func test_model_buff_effect_applies_evaluate_capability_measured() -> void:
	# 事件系统设计 §6.3: model_buff dispatches research.evaluate_apply, because
	# posttrain_apply no longer accepts capability_delta.
	var add: Dictionary = CommandBus.send(&"research.add_model", {
		arch = &"ant_v1", dataset_ids = []})
	var mid: StringName = add.model_id
	CommandBus.send(&"research.evaluate_apply", {
		model_id = mid, capability_measured = {&"general": 30.0}})
	var effect := EventEffect.new()
	effect.kind = &"model_buff"
	effect.params = {
		model_id = mid,
		capability_measured = {&"general": 77.0, &"code": 12.0},
	}
	var inst := EventInstance.new()
	inst.id = &"event_test"
	var r: Dictionary = EventSystem._apply_effect(effect, inst)
	assert_true(r.ok)
	var m = ResearchSystem.find_model(mid)
	assert_eq(m.status, &"evaluated")
	assert_almost_eq(float(m.capability[&"general"]), 77.0, 0.001)
	assert_almost_eq(float(m.capability[&"code"]), 12.0, 0.001)

func test_choose_marks_resolved_at_turn_and_chosen_option() -> void:
	GameState.turn = 9
	var r1: Dictionary = CommandBus.send(&"event.trigger_card", {template_id = &"debug_test_offer"})
	CommandBus.send(&"event.choose_option", {event_id = r1.event_id, option_id = &"accept"})
	var hist: EventInstance = GameState.event_history[0]
	assert_eq(hist.resolved_at_turn, 9)
	assert_eq(hist.chosen_option_id, &"accept")

# ---- 历史上限 ------------------------------------------------------------

func test_event_history_capped_at_history_limit() -> void:
	# §6: while history.size() > HISTORY_LIMIT (50): pop_front.
	# 用直接构造 EventInstance 把 history 撑满, 再触发一次, 应只剩 50.
	for i in range(55):
		var inst := EventInstance.new()
		inst.id = StringName("evt_%d" % i)
		inst.template_id = &"debug_test_offer"
		inst.resolved_at_turn = 0
		GameState.event_history.append(inst)
	# 当前 55 条, 触发一次正常事件 → resolve → history 变 56 然后 pop 到 50.
	# 但实际实现用 while history.size() > HISTORY_LIMIT 是在 resolve 时执行,
	# 所以我们手动调一次 resolve 路径:
	var r1: Dictionary = CommandBus.send(&"event.trigger_card", {template_id = &"debug_test_offer"})
	CommandBus.send(&"event.choose_option", {event_id = r1.event_id, option_id = &"refuse"})
	assert_eq(GameState.event_history.size(), 50)

# ---- §6 phase action: 概率抽取 ----------------------------------------

func test_phase_action_does_not_draw_when_pending_exists() -> void:
	# §6: if pending_events.size() > 0: return.
	# 先放一个 pending event, 跑 phase, pending 数量不应 +1.
	CommandBus.send(&"event.trigger_card", {template_id = &"debug_test_offer"})
	var before_count: int = GameState.pending_events.size()
	# 多跑几次 phase, 概率 1.0 也不会再加.
	for i in range(10):
		EventBus.phase_started.emit(&"action", i + 1)
	assert_eq(GameState.pending_events.size(), before_count)

func test_phase_action_respects_cooldown() -> void:
	# §6: cooldown 在 turn N 之前不再抽到该卡.
	# trigger debug_test_offer 一次, cooldown=24; 之后在 cooldown 窗口内多次跑
	# action 相位, debug_test_offer 都不应被再次抽到 (v10: 其它卡可能被抽中, 这里
	# 只钉住 debug_test_offer 被 cooldown 屏蔽这一点).
	# 必须持有 card 的强引用: Godot 资源缓存只在有外部引用时保活, 否则下次 load()
	# 重新解析回 weight=0, mutation 丢失。debug_test_offer 默认 weight=0, 调大成候选。
	var card := EventSystem._load_card(&"debug_test_offer")
	card.weight = 10
	CommandBus.send(&"event.trigger_card", {template_id = &"debug_test_offer"})
	GameState.pending_events.clear()  # 模拟玩家处理完, 但 cooldowns 仍在
	# v10: 把 routine 计时推到很远, 排除 routine 强制弹出的干扰.
	GameState.last_routine_turn = 1000
	# cooldown 指向 turn (trigger_turn + 24). 在 cooldown 窗口内不应抽到.
	var redrawn: int = 0
	for i in range(20):
		GameState.turn = i + 1
		GameState.pending_events.clear()  # 每周清空, 只观察单周抽卡结果
		EventBus.phase_started.emit(&"action", GameState.turn)
		for inst in GameState.pending_events:
			if inst.template_id == &"debug_test_offer":
				redrawn += 1
	assert_eq(redrawn, 0, "cooldown 窗口内 debug_test_offer 不应被再次抽到")

func test_phase_action_does_not_draw_below_min_turn() -> void:
	# debug_test_offer min_turn = 1. 在 turn=0 时不应抽到.
	var card := EventSystem._load_card(&"debug_test_offer")  # 持引用保活 mutation
	card.weight = 10  # 否则 weight=0 永不进池, 测试空转
	GameState.turn = 0
	# 强行把 RNG seed 设到 known 状态以让 randf() 命中 (≤0.35), 但 min_turn 屏蔽.
	GameState.rng_seed = 0
	GameState._rng = null
	for i in range(10):
		EventBus.phase_started.emit(&"action", 0)
	# turn=0 时 < min_turn (1), 应没有 debug_test_offer 被抽中.
	assert_eq(GameState.pending_events.size(), 0)

# ---- §6.3 effect dispatch ----------------------------------------------

func test_award_and_fame_effects_dispatched_through_command_bus() -> void:
	# §6.3: 选择 accept option 时的 economy_award effect 走 CommandBus.
	# v7 PR-F: fame_add effect 改为 deprecated no-op (fame 字段已删), 不再
# v7 PR-F deleted: 	# 触发 market.add_fame 或 fame_changed 信号.
	watch_signals(EventBus)
	var r1: Dictionary = CommandBus.send(&"event.trigger_card", {template_id = &"debug_test_offer"})
	CommandBus.send(&"event.choose_option", {event_id = r1.event_id, option_id = &"accept"})
	var has_event_award: bool = false
	for i in range(get_signal_emit_count(EventBus, "resources_changed")):
		var p: Array = get_signal_parameters(EventBus, "resources_changed", i)
		if String(p[1]).begins_with("event:"):
			has_event_award = true; break
	assert_true(has_event_award, "economy_award effect 应通过 economy.spend/award 走 bus")

func test_choose_when_already_resolved_returns_already_resolved() -> void:
	# §2: 二次选 option 应返回 already_resolved. 但当前实现会先 erase, 所以必须
	# 直接构造已 resolved 的 inst 加回 pending 模拟竞态.
	var inst := EventInstance.new()
	inst.id = &"_evt_locked"
	inst.template_id = &"debug_test_offer"
	inst.resolved_at_turn = 5
	GameState.pending_events.append(inst)
	var r: Dictionary = CommandBus.send(&"event.choose_option", {
		event_id = inst.id, option_id = &"accept"})
	assert_false(r.ok)
	assert_eq(r.error, &"already_resolved")

# ---- §6 weighted_pick / 多卡牌 -----------------------------------------

func test_weighted_pick_on_single_card_returns_that_card() -> void:
	# 单卡候选时 _weighted_pick 必返回该卡 (直接单测函数, 不依赖 0.07 概率抽取的
	# 随机循环, 也不依赖 debug 夹具进实战池)。
	var card := EventSystem._load_card(&"debug_test_offer")
	assert_eq(EventSystem._weighted_pick([card]), card,
			"候选只有一张卡时 _weighted_pick 必返回它")

# ---- §6 conditions: requires_fame / requires_cash ----------------------

func test_default_debug_test_offer_is_triggerable_at_zero_fame_and_zero_cash() -> void:
	# debug_test_offer 无 cash/fame 门禁 (requires_cash_min 默认负无穷), 故即使
	# cash=0 也满足触发条件。直接断言 _conditions_met, 不走 0.07 概率随机循环。
	var card := EventSystem._load_card(&"debug_test_offer")
	GameState.cash = 0
	GameState.turn = 1
	assert_true(EventSystem._conditions_met(card),
			"cash=0 时无门禁卡应满足触发条件")

# ---- §6.5 融资轮 (v9 已迁移)
# 融资改为玩家自发的 8 轮顺序 (pre_seed→seed→a-f), 见
# tests/unit/economy_funding_rounds_test.gd. EventSystem 不再推融资 offer。

# ---- §6.3 effect dispatch: dataset_delete & product_boost_subscribers ---

func test_dataset_delete_effect_dispatches_dataset_delete_command() -> void:
	# 注入一个 dataset, 通过 event 选项 dataset_delete effect 删掉它.
	var ds := Dataset.new()
	ds.id = &"ds_test_2"
	ds.display_name = "Test Dataset"
	ds.source = &"open_source"
	ds.size = 10.0
	ds.quality = 0.5
	GameState.datasets.append(ds)
	# Inject an effect into debug_test_offer card's accept option (non-destructive
	# for test scope: we restore after).
	var card := load("res://resources/data/events/debug_test_offer.tres") as EventCard
	var eff := EventEffect.new()
	eff.kind = &"dataset_delete"
	eff.params = {&"dataset_id": &"ds_test_2"}
	for opt in card.options:
		if opt.id == &"accept":
			opt.effects.append(eff)
	var r1: Dictionary = CommandBus.send(&"event.trigger_card",
			{template_id = &"debug_test_offer"})
	CommandBus.send(&"event.choose_option",
			{event_id = r1.event_id, option_id = &"accept"})
	var still_there: bool = false
	for d in GameState.datasets:
		if d.id == &"ds_test_2":
			still_there = true
	assert_false(still_there, "dataset_delete effect should have removed ds_test_2")
	# Restore card.
	for opt in card.options:
		if opt.id == &"accept":
			opt.effects.erase(eff)

# ---- v10 §4.5 routine 常规事件 -----------------------------------------

func test_routine_event_fires_after_interval() -> void:
	# §4.5: turn - last_routine_turn >= ROUTINE_INTERVAL (12) → 强制弹一张 routine.
	GameState.turn = 12
	GameState.last_routine_turn = 0
	EventSystem._maybe_trigger_routine_event()
	assert_eq(GameState.pending_events.size(), 1, "满 12 周应强制弹一张 routine")
	var inst: EventInstance = GameState.pending_events[0]
	var card := EventSystem._load_card(inst.template_id)
	assert_eq(card.category, &"routine", "弹出的应是 routine 类")

func test_routine_event_stamps_last_routine_turn() -> void:
	GameState.turn = 12
	GameState.last_routine_turn = 0
	EventSystem._maybe_trigger_routine_event()
	assert_eq(GameState.last_routine_turn, 12, "触发后 last_routine_turn 记到当前 turn")

func test_routine_event_does_not_fire_before_interval() -> void:
	# turn - last_routine_turn < ROUTINE_INTERVAL → 不弹.
	GameState.turn = 3
	GameState.last_routine_turn = 0
	EventSystem._maybe_trigger_routine_event()
	assert_eq(GameState.pending_events.size(), 0, "未满 routine 间隔不应弹 routine")

func test_routine_pool_never_empty_at_interval() -> void:
	# §4.5: 低门槛 routine 池永不空, 在最早可触发的 turn (= ROUTINE_INTERVAL) 必有候选。
	GameState.turn = EventSystem.ROUTINE_INTERVAL
	GameState.last_routine_turn = 0
	EventSystem._maybe_trigger_routine_event()
	assert_eq(GameState.pending_events.size(), 1,
			"turn=ROUTINE_INTERVAL 时 routine 池必有候选")

func test_low_gate_routine_pool_has_recurring_variety() -> void:
	# v16: 无产品/无员工局不能只剩 routine_lawsuit_spam 一张反复刷屏。
	# v17: 至少 5 张 routine 只 gate min_turn 且走默认 3 次硬上限, 让长期停滞局也有分布。
	var low_gate_default_cap: Array = []
	for tid in EventSystem.EVENTS.keys():
		var card := EventSystem._load_card(tid)
		if card == null or card.category != &"routine":
			continue
		if card.requires_datacenter:
			continue
		if card.requires_product:
			continue
		if card.requires_published_model:
			continue
		if int(card.requires_cash_min) != -2147483648:
			continue
		if int(card.requires_revenue_min) != 0:
			continue
		if int(card.requires_rank_max) != 0:
			continue
		if int(card.requires_lead_min) != 0:
			continue
		if int(card.requires_staff_min) != 0:
			continue
		if int(card.requires_dataset_min) != 0:
			continue
		if int(card.requires_paid_users_min) != 0:
			continue
		if card.requires_unlocks.size() > 0:
			continue
		if int(card.max_triggers) != 0:
			continue
		if int(card.weight) <= 0:
			continue
		low_gate_default_cap.append(card.id)
	assert_true(low_gate_default_cap.size() >= 5,
			"低门槛默认 3 次硬上限 routine 至少 5 张, 实际 %d: %s"
			% [low_gate_default_cap.size(), str(low_gate_default_cap)])

# ---- v10 §2 回合推进门禁 ------------------------------------------------

func test_can_advance_false_while_event_pending() -> void:
	CommandBus.send(&"event.trigger_card", {template_id = &"debug_test_offer"})
	assert_false(TurnManager.can_advance(), "有 pending 事件时不允许推进回合")

func test_can_advance_true_when_no_pending() -> void:
	assert_true(TurnManager.can_advance(), "无 pending 事件时可以推进回合")
	CommandBus.send(&"event.trigger_card", {template_id = &"debug_test_offer"})
	CommandBus.send(&"event.choose_option", {
		event_id = GameState.pending_events[0].id, option_id = &"refuse"})
	assert_true(TurnManager.can_advance(), "处理完事件后恢复可推进")

# ---- v10 §4.3 前置条件 --------------------------------------------------

func test_requires_datacenter_card_blocked_without_dc() -> void:
	var card := load("res://resources/data/events/dc_meltdown.tres") as EventCard
	assert_true(card.requires_datacenter, "dc_meltdown 应 gate requires_datacenter")
	GameState.datacenters.clear()
	assert_false(EventSystem._conditions_met(card), "无数据中心时该卡不进候选池")

func _seed_founder_lead() -> void:
	# 模拟新游戏入场后的 GameState.leads: 只有 founder.
	var f := Lead.new()
	f.id = &"player_self"
	f.display_name = "Founder"
	f.specialty = &"founder"
	f.level = &"founder"
	f.ability = 50.0
	f.is_player_scientist = true
	GameState.leads.append(f)

func _seed_real_lead(id: StringName = &"lead_real") -> void:
	var l := Lead.new()
	l.id = id
	l.display_name = "Real Lead"
	l.specialty = &"ml_researcher"
	l.level = &"B"
	l.ability = 60.0
	GameState.leads.append(l)

func test_requires_lead_min_excludes_founder() -> void:
	# 单人时期 GameState.leads 里只有创始人 → lead_poached("挖你最依赖的那位 lead")
	# 不应触发, 否则文案荒诞。requires_lead_min 只数非 founder lead。
	GameState.turn = 10
	GameState.leads.clear()
	_seed_product_stub()
	_seed_founder_lead()
	var card := load("res://resources/data/events/lead_poached.tres") as EventCard
	assert_false(EventSystem._conditions_met(card),
			"只有 founder 时 lead_poached 不应满足条件")
	_seed_real_lead()
	assert_true(EventSystem._conditions_met(card),
			"招到一个非 founder lead 后 lead_poached 才进候选池")

func test_routine_coffee_machine_requires_staff() -> void:
	# 单人时期 staff_pool 全为 0 → "工程师们眼神涣散"叙事不符, 不应弹。
	GameState.turn = 10
	GameState.staff_pool.clear()
	GameState.leads.clear()
	_seed_founder_lead()
	var card := load("res://resources/data/events/routine_coffee_machine.tres") as EventCard
	assert_false(EventSystem._conditions_met(card),
			"无员工时 routine_coffee_machine 不应触发")
	GameState.staff_pool[&"ml_eng"] = 1
	assert_true(EventSystem._conditions_met(card),
			"有 1 个员工后 routine_coffee_machine 可触发")

func test_routine_all_hands_requires_staff() -> void:
	# 一个人开"全员大会"叙事荒诞。
	GameState.turn = 10
	GameState.staff_pool.clear()
	GameState.leads.clear()
	_seed_founder_lead()
	var card := load("res://resources/data/events/routine_all_hands.tres") as EventCard
	assert_false(EventSystem._conditions_met(card),
			"无员工时 routine_all_hands 不应触发")
	GameState.staff_pool[&"ml_eng"] = 1
	assert_true(EventSystem._conditions_met(card),
			"有 1 个员工后 routine_all_hands 可触发")

func test_routine_office_move_requires_staff() -> void:
	# 单人创始人时期"工位挤到叠罗汉 / 搬大办公室"叙事不符, 不应弹。
	# 见 design/事件系统设计.md §4.5: 多人意象 routine 卡须 gate requires_staff_min。
	GameState.turn = 30
	GameState.staff_pool.clear()
	GameState.leads.clear()
	_seed_founder_lead()
	var card := load("res://resources/data/events/routine_office_move.tres") as EventCard
	assert_false(EventSystem._conditions_met(card),
			"无员工时 routine_office_move 不应触发")
	GameState.staff_pool[&"ml_eng"] = 1
	assert_true(EventSystem._conditions_met(card),
			"有 1 个员工后 routine_office_move 可触发")

func test_dark_ethics_cards_surface_more_readily() -> void:
	# 用户反馈: 血奴/血汗类事件落在庞大随机池里几乎抽不到。2026-05 放宽门槛 +
	# 提高权重 (仍保留一局 1 次): crunch_culture min_turn 24→12 / staff 2→1 /
	# weight 8→24; labeling_sweatshop min_turn 30→16 / weight 8→24。
	var crunch := EventSystem._load_card(&"crunch_culture")
	assert_eq(int(crunch.min_turn), 12)
	assert_eq(int(crunch.requires_staff_min), 1)
	assert_eq(int(crunch.weight), 24, "crunch 权重应提到 24, 在随机池里更容易被抽中")
	assert_eq(int(crunch.max_triggers), 1, "仍保留一局只来一次")
	var sweat := EventSystem._load_card(&"labeling_sweatshop")
	assert_eq(int(sweat.min_turn), 16)
	assert_eq(int(sweat.weight), 24)
	assert_eq(int(sweat.max_triggers), 1)
	# 旧门槛 (turn>=24 + 2 名员工) 收紧后单人/双人早期几乎遇不到; 放宽后
	# turn>=12 且 1 名员工即进候选。
	GameState.turn = 12
	GameState.staff_pool.clear()
	GameState.staff_pool[&"ml_eng"] = 1
	_seed_product_stub()
	assert_true(EventSystem._conditions_met(crunch),
			"turn>=12 且有 1 名员工时 crunch_culture 应进候选")

func test_rogue_agent_requires_coding_agent_unlock() -> void:
	# 还没研究出 Coding Agent (application:fox_code_specialist) 时,
	# "编程助手 agent 半夜自己开上万块 GPU" 叙事不成立, 不应弹。
	GameState.turn = 40
	GameState.unlocks.clear()
	GameState.datacenters.clear()
	GameState.datacenters.append(Datacenter.new())  # rogue_agent 还 gate requires_datacenter
	_seed_product_stub()
	var card := load("res://resources/data/events/rogue_agent.tres") as EventCard
	assert_false(EventSystem._conditions_met(card),
			"未解锁 Coding Agent 时 rogue_agent 不应触发")
	GameState.unlocks[&"application"] = {&"fox_code_specialist": true}
	assert_true(EventSystem._conditions_met(card),
			"解锁 Coding Agent 后 rogue_agent 可触发")

func test_event_trigger_prob_per_week_is_low() -> void:
	# §4.1 频率取舍 (v16): 成熟局审计约每 4.7 周一张, 随机概率降到 0.03。
	assert_eq(EventSystem.EVENT_TRIGGER_PROB_PER_WEEK, 0.03,
			"v16: 随机抽取概率应固定为 0.03")

func test_requires_dataset_min_card_blocked_without_dataset() -> void:
	var card := load("res://resources/data/events/data_audit.tres") as EventCard
	GameState.turn = 10
	GameState.datasets.clear()
	assert_false(EventSystem._conditions_met(card), "无数据集时 data_audit 不触发")
	var ds := Dataset.new()
	ds.id = &"ds_cond_test"
	GameState.datasets.append(ds)
	assert_true(EventSystem._conditions_met(card), "有数据集后 data_audit 可触发")

func test_subscriber_effect_cards_require_product_gate() -> void:
	# product_boost_subscribers 不带 product_id 时会挑最大订阅产品。无产品时没有目标,
	# 所以这类卡必须先 gate requires_product, 否则预览有变化但结算会失败。
	var missing: Array = []
	for tid in EventSystem.EVENTS.keys():
		var card := EventSystem._load_card(tid)
		if card == null:
			continue
		var has_subscriber_effect: bool = false
		for opt in card.options:
			for eff in opt.effects:
				if eff.kind == &"product_boost_subscribers":
					has_subscriber_effect = true
		if "passive_effects" in card:
			for eff in card.passive_effects:
				if eff.kind == &"product_boost_subscribers":
					has_subscriber_effect = true
		if has_subscriber_effect and not card.requires_product:
			missing.append(String(card.id))
	assert_eq(missing, [],
			"含订阅变化 effect 的事件必须 requires_product=true: %s" % str(missing))

func test_flavor_cards_have_no_hidden_options() -> void:
	# flavor UI 只显示"知道了"并走 dismiss_flavor, 不会展示/结算 options。
	# 因此 flavor 卡不能再藏旧 option 或废弃 npc_* effect。
	var offenders: Array = []
	for tid in EventSystem.EVENTS.keys():
		var card := EventSystem._load_card(tid)
		if card != null and card.category == &"flavor" and card.options.size() > 0:
			offenders.append(String(card.id))
	assert_eq(offenders, [], "flavor 卡不应有隐藏 options: %s" % str(offenders))

# ---- v10 §4.2.1 比例化数值 ---------------------------------------------

func test_proportional_economy_spend_uses_pct_of_cash() -> void:
	GameState.cash = 1_000_000
	var eff := EventEffect.new()
	eff.kind = &"economy_spend"
	eff.params = {&"pct": 0.05, &"floor": 1000, &"cap": 100000}
	var inst := EventInstance.new()
	inst.id = &"e_spend"
	var r: Dictionary = EventSystem._apply_effect(eff, inst)
	assert_true(r.ok)
	assert_eq(GameState.cash, 1_000_000 - 50_000, "spend 5% of 1M = 50k")

func test_proportional_economy_spend_respects_floor() -> void:
	GameState.cash = 1000  # 5% = 50, floor 提到 1000
	var eff := EventEffect.new()
	eff.kind = &"economy_spend"
	eff.params = {&"pct": 0.05, &"floor": 1000, &"cap": 100000}
	var inst := EventInstance.new()
	inst.id = &"e_spend_floor"
	EventSystem._apply_effect(eff, inst)
	assert_eq(GameState.cash, 1000 - 1000, "现金太少时 floor 兜底, 花 1000")

func test_proportional_economy_award_uses_pct_of_cash() -> void:
	GameState.cash = 1_000_000
	var eff := EventEffect.new()
	eff.kind = &"economy_award"
	eff.params = {&"pct": 0.1, &"floor": 5000}
	var inst := EventInstance.new()
	inst.id = &"e_award"
	EventSystem._apply_effect(eff, inst)
	assert_eq(GameState.cash, 1_000_000 + 100_000, "award 10% of 1M = 100k")

## High-cash regression: at $100B 现金, 4 张曾经无 cap 的卡 (gov_grant /
## big_client_hotpot / routine_intern_demo / routine_open_source_pr) 会算出
## 数十亿美金的"政府补助 / 实习生 demo 奖金", 极其离谱。这里固定每张卡 cap
## 的预期上限, 防止后续编辑 .tres 时无意删掉 cap 后被忽略。
func test_high_cash_economy_award_caps_are_enforced() -> void:
	GameState.cash = 100_000_000_000  # $100B
	# 表: tres 路径 → 期望 cap (上限金额)
	var cases: Array = [
		{path = "res://resources/data/events/gov_grant.tres",
				option = &"apply", expected_cap = 20_000_000},
		{path = "res://resources/data/events/big_client_hotpot.tres",
				option = &"sign", expected_cap = 100_000_000},
		{path = "res://resources/data/events/routine_intern_demo.tres",
				option = &"adopt", expected_cap = 150_000},
		{path = "res://resources/data/events/routine_open_source_pr.tres",
				option = &"merge", expected_cap = 300_000},
	]
	for c in cases:
		var card = load(c.path)
		assert_not_null(card, "%s 应可加载" % c.path)
		var opt = null
		for o in card.options:
			if o.id == c.option:
				opt = o
				break
		assert_not_null(opt, "%s 应有 option %s" % [c.path, c.option])
		# 找该 option 里 economy_award/spend 的金额, 不应超过 expected_cap.
		for eff in opt.effects:
			if eff.kind == &"economy_award" or eff.kind == &"economy_spend":
				var amount: int = EventSystem._resolve_money_amount(eff.params)
				assert_eq(amount, c.expected_cap,
						"%s/%s 在 $100B 现金下应被 cap 到 $%d" % [c.path, c.option, c.expected_cap])

## subscribers 池上限和现金一样: 后期 chatbot 单产品 2B, 总订阅可到 5B,
## 一张 22% pct 的 viral_meme 会 +1.1B 用户 — 远超叙事可信度。resolver
## 必须支持 `cap` (|delta| 上限), 这里固定关键卡的 cap。
func test_high_subs_total_caps_are_enforced() -> void:
	var prod := Product.new()
	prod.id = &"prod_huge"
	prod.subscribers = 5_000_000_000  # 5B 总订阅
	GameState.products.append(prod)
	# 表: tres 路径 → option → 期望 cap (|delta| 上限)
	var cases: Array = [
		{path = "res://resources/data/events/viral_meme.tres",
				option = &"ride", expected_cap = 200_000_000},
		{path = "res://resources/data/events/rank_one_party.tres",
				option = &"party", expected_cap = 200_000_000},
		{path = "res://resources/data/events/big_client_hotpot.tres",
				option = &"sign", expected_cap = 100_000_000},
		{path = "res://resources/data/events/conference_keynote.tres",
				option = &"speak", expected_cap = 100_000_000},
		{path = "res://resources/data/events/routine_media_interview.tres",
				option = &"accept", expected_cap = 10_000_000},
		{path = "res://resources/data/events/model_hallucination.tres",
				option = &"deny", expected_cap = 200_000_000},  # 负向 cap
	]
	for c in cases:
		var card = load(c.path)
		assert_not_null(card, "%s 应可加载" % c.path)
		var opt = null
		for o in card.options:
			if o.id == c.option:
				opt = o
				break
		assert_not_null(opt, "%s 应有 option %s" % [c.path, c.option])
		for eff in opt.effects:
			if eff.kind == &"product_boost_subscribers":
				var d: int = EventSystem._resolve_subscriber_delta(eff.params)
				assert_eq(absi(d), c.expected_cap,
						"%s/%s 在 5B 总订阅下 |delta| 应被 cap 到 %d" % [c.path, c.option, c.expected_cap])

## Lint: 凡是写了 `pct` 的 product_boost_subscribers 必须同时写 `cap`,
## 否则后期 5B+ 总订阅时单张卡能加 / 减数亿用户。
func test_all_proportional_subscriber_effects_have_cap() -> void:
	var dir := DirAccess.open("res://resources/data/events/")
	assert_not_null(dir, "events 目录应可打开")
	dir.list_dir_begin()
	var missing: Array = []
	var fname: String = dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".tres"):
			var card = load("res://resources/data/events/" + fname)
			if card != null and card.options != null:
				for opt in card.options:
					for eff in opt.effects:
						if eff.kind == &"product_boost_subscribers" \
								and eff.params.has(&"pct") and not eff.params.has(&"cap"):
							missing.append("%s/%s" % [fname, opt.id])
			if card != null and "passive_effects" in card:
				for eff in card.passive_effects:
					if eff.kind == &"product_boost_subscribers" \
							and eff.params.has(&"pct") and not eff.params.has(&"cap"):
						missing.append("%s/passive" % fname)
		fname = dir.get_next()
	assert_eq(missing, [], "所有 pct 化的订阅 effect 必须有 cap, 缺失: %s" % str(missing))

## Lint: 凡是写了 `pct` 的 economy_spend/economy_award 必须同时写 `cap`,
## 否则高现金期会算出几十亿美元的金额, 完全脱离事件叙事 (见 §4.2.1)。
func test_all_proportional_economy_effects_have_cap() -> void:
	var dir := DirAccess.open("res://resources/data/events/")
	assert_not_null(dir, "events 目录应可打开")
	dir.list_dir_begin()
	var missing: Array = []
	var fname: String = dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".tres"):
			var card = load("res://resources/data/events/" + fname)
			if card != null and card.options != null:
				for opt in card.options:
					for eff in opt.effects:
						if (eff.kind == &"economy_spend" or eff.kind == &"economy_award") \
								and eff.params.has(&"pct") and not eff.params.has(&"cap"):
							missing.append("%s/%s/%s" % [fname, opt.id, eff.kind])
			if card != null and "passive_effects" in card:
				for eff in card.passive_effects:
					if (eff.kind == &"economy_spend" or eff.kind == &"economy_award") \
							and eff.params.has(&"pct") and not eff.params.has(&"cap"):
						missing.append("%s/passive/%s" % [fname, eff.kind])
		fname = dir.get_next()
	assert_eq(missing, [], "所有 pct 化的经济 effect 必须有 cap, 缺失: %s" % str(missing))

func test_proportional_subscriber_boost_uses_pct_of_total() -> void:
	var prod := Product.new()
	prod.id = &"prod_prop"
	prod.subscribers = 1000
	GameState.products.append(prod)
	var eff := EventEffect.new()
	eff.kind = &"product_boost_subscribers"
	eff.params = {&"pct": 0.2, &"floor": 10}
	var inst := EventInstance.new()
	inst.id = &"e_subs"
	EventSystem._apply_effect(eff, inst)
	assert_eq(prod.subscribers, 1200, "boost 20% of 1000 总订阅 = +200")

func test_proportional_subscriber_boost_negative_pct() -> void:
	var prod := Product.new()
	prod.id = &"prod_neg"
	prod.subscribers = 1000
	GameState.products.append(prod)
	var eff := EventEffect.new()
	eff.kind = &"product_boost_subscribers"
	eff.params = {&"pct": -0.1, &"floor": 10}
	var inst := EventInstance.new()
	inst.id = &"e_subs_neg"
	EventSystem._apply_effect(eff, inst)
	assert_eq(prod.subscribers, 900, "负 pct 应扣订阅: -10% of 1000 = -100")

# ---- v10 选项后果预览 (UI 在按钮上显示玩家会得到什么) -------------------

func _opt_of(template_id: StringName, option_id: StringName):
	var card := EventSystem._load_card(template_id)
	for o in card.options:
		if o.id == option_id:
			return o
	return null

func test_savings_or_honesty_options_do_not_award_cash() -> void:
	# "把钱省下来"、"拒绝刷榜保持诚实"、"占领道德高地"不代表有外部现金流入, 不应用
	# economy_award 凭空发钱。需要机械影响时用订阅/风险/未来系统表达。
	var cases := {
		&"rebrand_consultant": &"keep_identity",
		&"benchmark_gaming": &"stay_honest",
		&"pause_letter": &"sign",
	}
	var offenders: Array = []
	for cid in cases:
		var opt = _opt_of(cid, cases[cid])
		assert_not_null(opt, "%s 应有选项 %s" % [cid, cases[cid]])
		if opt == null:
			continue
		for eff in opt.effects:
			if eff.kind == &"economy_award":
				offenders.append("%s/%s" % [cid, cases[cid]])
	assert_eq(offenders, [],
			"省钱/诚实选项不应使用 economy_award: %s" % str(offenders))

func test_describe_consequence_proportional_spend_shows_amount() -> void:
	# routine_coffee_machine / buy_fancy: spend pct 0.6% of cash.
	GameState.cash = 1_000_000
	var s: String = EventSystem.describe_option_consequence(
			_opt_of(&"routine_coffee_machine", &"buy_fancy"))
	assert_string_contains(s, "支出")
	assert_string_contains(s, "6,000", "1M 的 0.6% = $6,000")

func test_describe_consequence_empty_effects_says_no_effect() -> void:
	var s: String = EventSystem.describe_option_consequence(
			_opt_of(&"routine_coffee_machine", &"instant"))
	assert_eq(s, "无直接影响", "无 effect 的选项应显式说明无影响")

func test_describe_consequence_absolute_award_shows_grouped_amount() -> void:
	# debug_test_offer / accept: economy_award amount=1_000_000 (旧绝对值写法).
	var s: String = EventSystem.describe_option_consequence(
			_opt_of(&"debug_test_offer", &"accept"))
	assert_string_contains(s, "获得")
	assert_string_contains(s, "1,000,000")

func test_describe_consequence_subscriber_boost_shows_sign() -> void:
	# model_hallucination / deny: product_boost pct -12%.
	var prod := Product.new()
	prod.id = &"prod_desc"
	prod.subscribers = 1000
	GameState.products.append(prod)
	var s: String = EventSystem.describe_option_consequence(
			_opt_of(&"model_hallucination", &"deny"))
	assert_string_contains(s, "订阅", "应描述订阅变化")
	assert_string_contains(s, "-", "负向 effect 应带减号")

func test_describe_consequence_localizes_to_en() -> void:
	# 后果预览是 UI 层文案 (strings.csv 的 EVENT_CONSEQ_*), 切 en 必须翻成英文,
	# 否则事件选项按钮在英文界面下半句仍是中文 (见 §6bis)。
	GameState.cash = 1_000_000
	TranslationServer.set_locale("en")
	var spend: String = EventSystem.describe_option_consequence(
			_opt_of(&"routine_coffee_machine", &"buy_fancy"))
	var none: String = EventSystem.describe_option_consequence(
			_opt_of(&"routine_coffee_machine", &"instant"))
	TranslationServer.set_locale("zh_CN")  # 恢复基线, 防泄漏到后续测试
	assert_eq(none.find("无直接影响"), -1, "en 下 '无直接影响' 应被翻译")
	assert_eq(spend.find("支出"), -1, "en 下 '支出' 应被翻译")
	assert_string_contains(spend, "6,000", "金额插值仍应保留")

func test_destructive_consequence_previews_explain_asset_loss() -> void:
	# v14 文案审计: 破坏性 effect 要把永久性和副作用讲清楚, 避免玩家以为
	# 只是临时停机 / 系统因为没钱自动卖资产。
	var dc_text: String = EventSystem.describe_option_consequence(
			_opt_of(&"dc_meltdown", &"ignore"))
	assert_string_contains(dc_text, "数据中心")
	assert_string_contains(dc_text, "GPU")
	assert_string_contains(dc_text, "出售")

	var dataset_text: String = EventSystem.describe_option_consequence(
			_opt_of(&"data_audit", &"comply"))
	assert_string_contains(dataset_text, "永久")
	assert_string_contains(dataset_text, "数据集")

func test_event_copy_does_not_promise_unimplemented_hiring_changes() -> void:
	# 这些事件只落现金 / 订阅 effect, 没有真正修改 lead/staff 资产; 文案不能
	# 写成"研究员加入 / 团队入伙 / lead 离开"。
	var cases: Dictionary = {
		&"star_researcher": ["加入", "挖来"],
		&"acquihire_small": ["整个团队加入", "人才入伙"],
		&"lead_poached": ["放他走"],
	}
	for cid in cases:
		var card := EventSystem._load_card(cid)
		assert_not_null(card, "%s.tres 应可加载" % cid)
		var text: String = String(card.body)
		for opt in card.options:
			text += " " + String(opt.label)
		for banned in cases[cid]:
			assert_eq(text.find(String(banned)), -1,
					"%s 文案暗示未实现的资产变化: %s" % [cid, banned])

func test_v10_cards_registered_in_events_table() -> void:
	# 代表性事件都应在 EVENTS 表注册且 .tres 可加载.
	for tid in [&"routine_all_hands", &"big_client_hotpot", &"dc_meltdown",
			&"rank_one_party", &"first_revenue", &"agi_rumor"]:
		assert_true(EventSystem.EVENTS.has(tid), "EVENTS 应注册 %s" % tid)
		var card := EventSystem._load_card(tid)
		assert_not_null(card, "%s.tres 应可加载" % tid)

func test_all_event_resource_files_are_registered() -> void:
	# 事件目录里不能有"脚本重生成出来但系统不认识"的孤儿 .tres。
	var dir := DirAccess.open("res://resources/data/events/")
	assert_not_null(dir, "events 目录应可打开")
	dir.list_dir_begin()
	var missing: Array = []
	var fname: String = dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".tres"):
			var path := "res://resources/data/events/" + fname
			var card := load(path) as EventCard
			assert_not_null(card, "%s 应可加载为 EventCard" % fname)
			if card != null and not EventSystem.EVENTS.has(card.id):
				missing.append("%s:%s" % [fname, card.id])
		fname = dir.get_next()
	assert_eq(missing, [], "所有事件 .tres 都必须在 EventSystem.EVENTS 注册: %s" % str(missing))

func test_product_boost_subscribers_effect_dispatches_update_subscribers() -> void:
	# 直接验下游命令 OK + 通过 effect kind 走 dispatch 表.
	var prod := Product.new()
	prod.id = &"prod_test_1"
	prod.subscribers = 100
	GameState.products.append(prod)
	var card := load("res://resources/data/events/debug_test_offer.tres") as EventCard
	var eff := EventEffect.new()
	eff.kind = &"product_boost_subscribers"
	eff.params = {&"product_id": &"prod_test_1", &"delta": 250}
	for opt in card.options:
		if opt.id == &"accept":
			opt.effects.append(eff)
	var r1: Dictionary = CommandBus.send(&"event.trigger_card",
			{template_id = &"debug_test_offer"})
	CommandBus.send(&"event.choose_option",
			{event_id = r1.event_id, option_id = &"accept"})
	assert_eq(prod.subscribers, 350, "product_boost_subscribers should add delta")
	for opt in card.options:
		if opt.id == &"accept":
			opt.effects.erase(eff)

# ---- v3 §1.6 时间锚点·技术范式事件 ----------------------------------------

func test_paradigm_rlhf_card_loads_and_has_min_turn_282() -> void:
	# 事件库 §1.6.1: paradigm_rlhf 应在 EVENTS 注册, min_turn=282 (2022-11-30).
	var path: String = "res://resources/data/events/paradigm_rlhf.tres"
	var card := load(path) as EventCard
	assert_not_null(card, "paradigm_rlhf.tres 必须存在")
	assert_eq(int(card.min_turn), 282, "paradigm_rlhf min_turn 应是 282")
	assert_eq(int(card.weight), 0, "paradigm_rlhf weight 应为 0 (不进随机池)")
	assert_eq(int(card.cooldown_months), 9999, "paradigm_rlhf cooldown 应是 9999 (一次性)")

func test_paradigm_moe_card_loads_and_has_min_turn_297() -> void:
	var card := load("res://resources/data/events/paradigm_moe.tres") as EventCard
	assert_not_null(card)
	assert_eq(int(card.min_turn), 297)
	assert_eq(int(card.weight), 0)

func test_paradigm_card_registered_in_events_table() -> void:
	# EventSystem.EVENTS 字典必须包含 paradigm_*.
	var has_rlhf: bool = EventSystem.EVENTS.has(&"paradigm_rlhf")
	var has_moe: bool = EventSystem.EVENTS.has(&"paradigm_moe")
	assert_true(has_rlhf, "EVENTS 应注册 paradigm_rlhf")
	assert_true(has_moe, "EVENTS 应注册 paradigm_moe")

func test_npc_capability_jump_effect_is_deprecated_no_op() -> void:
	# v8 PR-H (2026-05): NPC is timeline-driven; npc_capability_jump effect kind
	# is deprecated and no-ops. paradigm_* 卡现在是无 options 的 flavor; 这里直接
	# 调 dispatch 表验证旧 effect 兼容路径不会改 NPC capability。
	var orca = null
	for npc in GameState.npc_companies:
		if npc.id == &"npc_orca_lab": orca = npc; break
	var before: float = float(orca.model_capability["general"])
	var eff := EventEffect.new()
	eff.kind = &"npc_capability_jump"
	eff.params = {
		&"npc_ids": [&"npc_orca_lab"],
		&"delta": {&"general": 99.0},
	}
	var inst := EventInstance.new()
	inst.id = &"event_deprecated_npc_jump"
	var r: Dictionary = EventSystem._apply_effect(eff, inst)
	assert_true(r.ok)
	assert_almost_eq(float(orca.model_capability["general"]), before, 0.001,
			"v8 PR-H: paradigm effect 不再改 NPC capability")

func test_paradigm_rlhf_triggers_automatically_at_turn_282() -> void:
	# §1.6: paradigm 事件 weight=0 不进随机池, 但应在 min_turn 自动确定性触发.
	# 推进游戏到 turn=282, 应 pending paradigm_rlhf.
	GameState.turn = 282
	# 模拟 action 阶段调度.
	EventBus.phase_started.emit(&"action", 282)
	# 检查 pending events 里有 paradigm_rlhf.
	var found: bool = false
	for inst in GameState.pending_events:
		if inst.template_id == &"paradigm_rlhf":
			found = true; break
	assert_true(found,
			"paradigm_rlhf 在 turn=282 时应自动 trigger (确定性, 非随机)")

func test_flag_set_effect_returns_ok_punt() -> void:
	# flag_set 当前是 punt: 不写实际 flag, 只 log + return ok=true.
	var card := load("res://resources/data/events/debug_test_offer.tres") as EventCard
	var eff := EventEffect.new()
	eff.kind = &"flag_set"
	eff.params = {&"flag_name": &"some_flag", &"value": true}
	for opt in card.options:
		if opt.id == &"accept":
			opt.effects.append(eff)
	var r1: Dictionary = CommandBus.send(&"event.trigger_card",
			{template_id = &"debug_test_offer"})
	var r: Dictionary = CommandBus.send(&"event.choose_option",
			{event_id = r1.event_id, option_id = &"accept"})
	assert_true(r.ok)
	# Find the flag_set entry in applied_effects; its ok flag should be true.
	var found: bool = false
	for entry in r.applied_effects:
		if entry.kind == &"flag_set":
			found = true
			assert_true(entry.ok, "flag_set punt returns ok=true")
	assert_true(found, "applied_effects should contain flag_set entry")
	for opt in card.options:
		if opt.id == &"accept":
			opt.effects.erase(eff)

# ---- save_loaded: event ID 计数器恢复 + 重复修复 (读档撞 ID 防御) -------

func _seed_event(id: StringName) -> EventInstance:
	var e := EventInstance.new()
	e.id = id
	return e

func test_save_loaded_restores_event_id_counter() -> void:
	GameState.event_history.append(_seed_event(&"event_0012"))
	EventBus.save_loaded.emit()
	var new_id := EventSystem._gen_event_id()
	assert_gt(String(new_id).trim_prefix("event_").to_int(), 12,
			"读档后新发的 event ID 不能复用 ≤0012 (实际 %s)" % new_id)

func test_save_loaded_repairs_duplicate_event_ids() -> void:
	GameState.pending_events.append(_seed_event(&"event_0001"))
	GameState.event_history.append(_seed_event(&"event_0001"))
	EventBus.save_loaded.emit()
	var seen := {}
	for e in (GameState.pending_events + GameState.event_history):
		assert_false(seen.has(e.id), "event id %s 读档后仍重复" % e.id)
		seen[e.id] = true

# ========================================================================
# v11 §4.1 降频 / §4.7 max_triggers / drama 真两难卡
# ========================================================================

## v11 新增的 drama 真两难卡 id
## (AI 历史争议 6 + 硅谷梗 11 + 非技术向喜剧 2 + 灰暗伦理向 4)。
## 2026-05 删除原 AI 历史争议线里的 moat_memo_leak / weights_leak / deepseek_moment
## (开源/降价主题卡, 玩家不直接操盘定价/开源), 9→6。
const _V11_DRAMA_CARDS: Array[StringName] = [
	# AI 历史争议 (6)
	&"board_coup", &"pause_letter", &"data_lawsuit",
	&"sentient_engineer", &"celebrity_voice",
	&"doomer_vs_acc",
	# 硅谷梗 (11)
	&"three_commas_investor", &"middle_out", &"not_hotdog", &"hooli_keynote",
	&"platform_pivot", &"rogue_agent", &"benchmark_gaming", &"hardware_box_pivot",
	&"exclusive_megadeal", &"rebrand_consultant", &"fake_users",
	# 非技术向纯喜剧 (2)
	&"ai_orders_beef", &"doomsday_bunker",
	# 灰暗 / 伦理向 (4)
	&"labeling_sweatshop", &"surveillance_contract", &"companion_tragedy",
	&"crunch_culture",
]

const _V17_BLACK_HUMOR_CARDS: Array[StringName] = [
	&"support_bot_refund_policy",
	&"forum_wisdom_summary",
	&"fictional_case_law",
	&"history_image_overfit",
	&"support_bot_self_roast",
	&"compliance_bot_illegal_advice",
]

## drama 卡两难选项只允许用这些**已实现**的 effect kind (真生效)。
const _IMPLEMENTED_EFFECT_KINDS: Array[StringName] = [
	&"economy_spend", &"economy_award", &"product_boost_subscribers",
	&"dc_terminate", &"dataset_delete",
]

func test_routine_interval_is_12() -> void:
	# v16 §4.5: routine 强制间隔 8 → 12 周, 修复成熟局事件过密。
	assert_eq(EventSystem.ROUTINE_INTERVAL, 12, "v16: routine 强制间隔应为 12 周")

func test_event_card_has_max_triggers_field() -> void:
	# v11 §4.7: EventCard 新增 max_triggers; drama 卡设为 1 (一辈子只来一次)。
	var card := load("res://resources/data/events/board_coup.tres") as EventCard
	assert_not_null(card, "board_coup.tres 应存在")
	assert_eq(int(card.max_triggers), 1, "board_coup 应是一次性事件 max_triggers=1")

func test_global_event_trigger_cap_is_three() -> void:
	# v17: 即使卡片 max_triggers=0, 单卡最多也只能触发三次。
	assert_eq(EventSystem.GLOBAL_MAX_TRIGGERS_PER_CARD, 3,
			"单个事件全局硬上限应固定为 3 次")

func test_routine_chore_cards_have_trigger_caps() -> void:
	# 用户反馈: 养猫 / 咖啡机坏 出现 1-2 次就够, 实习生 demo 一次就够 —
	# 否则后期反复刷屏出戏。pet/coffee max_triggers=2, intern=1。
	# 2026-05: 搬办公室也限次 —— 公司一局里搬 1-2 次合理, 反复刷"换大办公室"出戏。
	var cases := {
		&"routine_office_pet": 2,
		&"routine_coffee_machine": 2,
		&"routine_intern_demo": 1,
		&"routine_office_move": 2,
	}
	for cid in cases:
		var card := EventSystem._load_card(cid)
		assert_not_null(card, "%s.tres 应可加载" % cid)
		assert_eq(int(card.max_triggers), int(cases[cid]),
				"%s 应限触发 %d 次" % [cid, cases[cid]])

func test_asset_loss_crisis_has_first_year_protection_and_cap() -> void:
	# v15: 随机关停数据中心是永久资产损失, 不应在开局十几周就弹。
	# 首年保护 = 52 周; 一局最多触发 2 次。
	var card := EventSystem._load_card(&"dc_meltdown")
	assert_not_null(card, "dc_meltdown.tres 应可加载")
	assert_eq(int(card.min_turn), 52, "dc_meltdown 应首年保护, 第 52 周后才进池")
	assert_eq(int(card.max_triggers), 2, "dc_meltdown 一局最多触发 2 次")

func test_open_source_pr_routine_has_trigger_cap() -> void:
	# v15: 神秘 PR 是轻量 routine, 出现两次就够。
	var card := EventSystem._load_card(&"routine_open_source_pr")
	assert_not_null(card, "routine_open_source_pr.tres 应可加载")
	assert_eq(int(card.max_triggers), 2, "routine_open_source_pr 一局最多触发 2 次")

func test_routine_chore_caps_stay_small_late_game() -> void:
	# 后期现金可达数十亿, 琐事 cap 不应再算出 100w 量级 (喝奶茶 100w 出戏)。
	var caps := {
		&"routine_all_hands": 100_000,   # 喝奶茶
		&"routine_office_pet": 60_000,   # 养猫
		&"routine_coffee_machine": 100_000,  # 咖啡机
		&"routine_lawsuit_spam": 150_000,  # 无厘头律师函"小钱私了"
	}
	for cid in caps:
		var card := EventSystem._load_card(cid)
		assert_not_null(card)
		for opt in card.options:
			for eff in opt.effects:
				if eff.params.has(&"cap") or eff.params.has("cap"):
					var cap_v: int = int(eff.params.get(&"cap", eff.params.get("cap", 0)))
					assert_true(cap_v <= int(caps[cid]),
							"%s 的 cap 应 ≤ %d (后期不出戏), 实际 %d" % [cid, caps[cid], cap_v])

func test_event_trigger_counts_in_owned_slices() -> void:
	# v11: event_trigger_counts 必须入存档 (owner=EventSystem)。
	assert_true(EventSystem.OWNED_SLICES.has(&"event_trigger_counts"),
			"event_trigger_counts 应在 EventSystem.OWNED_SLICES")

func test_trigger_increments_trigger_count() -> void:
	# v11 §4.7: _trigger 每推一张卡就把 event_trigger_counts[id] += 1。
	assert_eq(int(GameState.event_trigger_counts.get(&"debug_test_offer", 0)), 0)
	CommandBus.send(&"event.trigger_card", {template_id = &"debug_test_offer"})
	assert_eq(int(GameState.event_trigger_counts.get(&"debug_test_offer", 0)), 1,
			"trigger 一次后该卡计数应为 1")
	CommandBus.send(&"event.trigger_card", {template_id = &"debug_test_offer"})
	assert_eq(int(GameState.event_trigger_counts.get(&"debug_test_offer", 0)), 2)

func test_triggers_exhausted_blocks_card_at_limit() -> void:
	var card := load("res://resources/data/events/board_coup.tres") as EventCard
	assert_false(EventSystem._triggers_exhausted(card), "未触发时不应耗尽")
	GameState.event_trigger_counts[card.id] = 1
	assert_true(EventSystem._triggers_exhausted(card), "达到 max_triggers(=1) 后应耗尽")

func test_default_max_triggers_uses_global_hard_cap() -> void:
	# v17: max_triggers=0 表示走系统默认硬上限 3, 不再是真正无限。
	var card := load("res://resources/data/events/debug_test_offer.tres") as EventCard
	GameState.event_trigger_counts[card.id] = 2
	assert_false(EventSystem._triggers_exhausted(card),
			"默认硬上限下, 第 3 次触发前不应耗尽")
	GameState.event_trigger_counts[card.id] = 3
	assert_true(EventSystem._triggers_exhausted(card),
			"max_triggers=0 的卡达到全局 3 次硬上限后应耗尽")

func test_authored_max_triggers_cannot_exceed_global_hard_cap() -> void:
	# 单卡显式写大于 3 也不能绕过系统硬上限。
	var card := EventSystem._load_card(&"debug_test_offer")
	var saved_max: int = int(card.max_triggers)
	card.max_triggers = 10
	GameState.event_trigger_counts[card.id] = 3
	assert_true(EventSystem._triggers_exhausted(card),
			"显式 max_triggers>3 也应被全局硬上限压到 3")
	card.max_triggers = saved_max

func test_trigger_card_respects_global_hard_cap() -> void:
	var card := EventSystem._load_card(&"debug_test_offer")
	GameState.event_trigger_counts[card.id] = EventSystem.GLOBAL_MAX_TRIGGERS_PER_CARD
	var r: Dictionary = CommandBus.send(&"event.trigger_card",
			{template_id = &"debug_test_offer"})
	assert_false(r.ok)
	assert_eq(r.error, &"event_trigger_exhausted")
	assert_eq(GameState.pending_events.size(), 0,
			"强制触发命令也不能绕过单卡 3 次硬上限")

func test_exhausted_card_excluded_from_random_pool() -> void:
	# debug_test_offer 在空状态/turn=1 时是随机池唯一候选。临时给它 max_triggers=1,
	# 触发一次耗尽后, 之后多次 action 相位都不应再抽到它 (验证 max_triggers 真生效)。
	GameState.turn = 1
	GameState.last_routine_turn = 100000  # 关掉 routine 强制弹出干扰
	var card := load("res://resources/data/events/debug_test_offer.tres") as EventCard
	var saved_max: int = card.max_triggers
	card.max_triggers = 1
	card.weight = 10  # 默认 weight=0 不进池; 调大成候选才能验证"耗尽后被排除"非空转
	CommandBus.send(&"event.trigger_card", {template_id = &"debug_test_offer"})  # count→1
	GameState.pending_events.clear()
	GameState.event_cooldowns.clear()  # 排除 cooldown, 只验 max_triggers
	GameState.rng_seed = 7
	GameState._rng = null
	var drawn: int = 0
	for i in range(60):
		GameState.pending_events.clear()
		EventBus.phase_started.emit(&"action", 1)
		for inst in GameState.pending_events:
			if inst.template_id == &"debug_test_offer":
				drawn += 1
	card.max_triggers = saved_max  # restore cached resource before asserting
	assert_eq(drawn, 0, "max_triggers 耗尽后该卡不应再被随机池抽到")

func test_v11_drama_cards_registered_and_loadable() -> void:
	for tid in _V11_DRAMA_CARDS:
		assert_true(EventSystem.EVENTS.has(tid), "EVENTS 应注册 drama 卡 %s" % tid)
		var card := EventSystem._load_card(tid)
		assert_not_null(card, "%s.tres 应可加载" % tid)

func test_v11_drama_cards_both_options_have_real_effects() -> void:
	# 真两难: drama 卡每个选项都必须挂 ≥1 个 effect (不再有"一支为空")。
	for tid in _V11_DRAMA_CARDS:
		var card := EventSystem._load_card(tid)
		assert_not_null(card, "%s 应可加载" % tid)
		assert_gt(card.options.size(), 1, "%s 应有 ≥2 个选项" % tid)
		for opt in card.options:
			assert_gt(opt.effects.size(), 0,
					"drama 卡 %s 的选项 %s 必须有真生效 effect (真两难)" % [tid, opt.id])

func test_v11_drama_effects_use_implemented_kinds_only() -> void:
	# 真生效: drama 卡只允许用已实现的 effect kind, 禁用废弃 no-op 的
	# fame_add / npc_* 与尚未落地的 flag_set。
	for tid in _V11_DRAMA_CARDS:
		var card := EventSystem._load_card(tid)
		assert_not_null(card)
		for opt in card.options:
			for eff in opt.effects:
				assert_true(_IMPLEMENTED_EFFECT_KINDS.has(eff.kind),
						"%s/%s 用了未实现/废弃的 effect kind: %s" % [tid, opt.id, eff.kind])

func test_v11_drama_cards_have_max_triggers() -> void:
	# drama 卡都应限次 (max_triggers > 0), 不无限重复。
	for tid in _V11_DRAMA_CARDS:
		var card := EventSystem._load_card(tid)
		assert_not_null(card)
		assert_gt(int(card.max_triggers), 0,
				"drama 卡 %s 应设 max_triggers>0 (不无限重复)" % tid)

func test_ai_orders_beef_is_one_time_routine_candidate() -> void:
	# 用户反馈随机池里很难看到这个梗; v17 改为 routine 候选, 但仍一局只来一次。
	var card := EventSystem._load_card(&"ai_orders_beef")
	assert_not_null(card, "ai_orders_beef 应在 EVENTS 注册")
	assert_eq(card.category, &"routine", "AI 擅自采购牛肉应作为公司日常事故进入 routine 池")
	assert_eq(int(card.max_triggers), 1, "AI 订牛肉梗一局只出现一次")
	assert_eq(int(card.requires_staff_min), 1, "至少有员工后才触发 AI 助理采购事故")

func test_v17_black_humor_cards_registered_once_only() -> void:
	for tid in _V17_BLACK_HUMOR_CARDS:
		assert_true(EventSystem.EVENTS.has(tid), "EVENTS 应注册黑色幽默卡 %s" % tid)
		var card := EventSystem._load_card(tid)
		assert_not_null(card, "%s.tres 应可加载" % tid)
		assert_eq(int(card.max_triggers), 1, "%s 应是一局只出现一次" % tid)

func test_v17_black_humor_cards_have_real_two_way_effects() -> void:
	for tid in _V17_BLACK_HUMOR_CARDS:
		var card := EventSystem._load_card(tid)
		assert_not_null(card, "%s 应可加载" % tid)
		assert_eq(card.requires_product, true,
				"%s 都围绕已上线产品/助手事故, 应 gate requires_product" % tid)
		assert_gt(card.options.size(), 1, "%s 应有两个选择" % tid)
		for opt in card.options:
			assert_gt(opt.effects.size(), 0,
					"黑色幽默卡 %s 的选项 %s 必须有真生效 effect" % [tid, opt.id])
			for eff in opt.effects:
				assert_true(_IMPLEMENTED_EFFECT_KINDS.has(eff.kind),
						"%s/%s 用了未实现/废弃的 effect kind: %s" % [tid, opt.id, eff.kind])

func test_retrofit_old_cards_now_have_dual_real_branches() -> void:
	# v11: 给 3 张老 opportunity 卡补齐"空选项", 变成双支真两难。
	var cases := {
		&"big_client_hotpot": &"refuse",
		&"viral_meme": &"lowkey",
		&"star_researcher": &"pass",
	}
	for cid in cases:
		var opt = _opt_of(cid, cases[cid])
		assert_not_null(opt, "%s 应有选项 %s" % [cid, cases[cid]])
		assert_gt(opt.effects.size(), 0,
				"%s/%s 现在应有真 effect (不再是空选项)" % [cid, cases[cid]])

# ========================================================================
# v12 历史档案 flavor 卡: 无选择 + 无直接影响 + 固定顺序触发
# ========================================================================

const _V12_HISTORY_CARDS: Array[StringName] = [
	&"history_attention_turning_point",
	&"history_encoder_pretraining",
	&"history_large_decoder_wave",
	&"history_synthetic_text_alarm",
	&"history_scaling_laws",
	&"history_sparse_expert_routing",
	&"history_foundation_model_frame",
	&"history_diffusion_image_wave",
	&"history_instruction_chat_wave",
	&"history_open_weight_wave",
	&"history_multimodal_tool_wave",
	&"history_long_context_race",
	&"history_verifiable_reasoning_wave",
]

func test_event_card_has_passive_effects_field() -> void:
	var card := EventCard.new()
	assert_eq(card.passive_effects.size(), 0,
			"v12: EventCard 应提供 passive_effects 给无选择 flavor 卡")

func test_v12_history_cards_registered_and_loadable() -> void:
	for tid in _V12_HISTORY_CARDS:
		assert_true(EventSystem.EVENTS.has(tid), "EVENTS 应注册历史档案卡 %s" % tid)
		var card := EventSystem._load_card(tid)
		assert_not_null(card, "%s.tres 应可加载" % tid)

func test_v12_history_cards_are_flavor_no_choice_with_passive_effects() -> void:
	var prev_turn: int = -1
	for tid in _V12_HISTORY_CARDS:
		var card := EventSystem._load_card(tid)
		assert_not_null(card)
		assert_eq(card.category, &"flavor", "%s 应是 flavor 无选择事件" % tid)
		assert_eq(int(card.weight), 0, "%s 不进随机池" % tid)
		assert_eq(int(card.cooldown_months), 9999, "%s 应一次性 cooldown" % tid)
		assert_eq(int(card.max_triggers), 1, "%s 应 max_triggers=1" % tid)
		assert_eq(card.options.size(), 0, "%s 不应有玩家选项" % tid)
		assert_eq(card.passive_effects.size(), 0,
				"%s 是教育新闻, 不应有读新闻发钱/扣钱这类直接影响" % tid)
		assert_gt(int(card.min_turn), prev_turn, "历史档案 min_turn 应按顺序递增")
		prev_turn = int(card.min_turn)

func test_history_events_constant_matches_card_order() -> void:
	assert_eq(EventSystem.HISTORICAL_EVENTS.size(), _V12_HISTORY_CARDS.size())
	for i in range(_V12_HISTORY_CARDS.size()):
		assert_eq(EventSystem.HISTORICAL_EVENTS[i], _V12_HISTORY_CARDS[i],
				"HISTORICAL_EVENTS 应按历史顺序登记")

func test_history_event_triggers_deterministically_at_min_turn() -> void:
	GameState.turn = 1
	GameState.last_routine_turn = 100000
	EventBus.phase_started.emit(&"action", GameState.turn)
	assert_eq(GameState.pending_events.size(), 1)
	assert_eq(GameState.pending_events[0].template_id, &"history_attention_turning_point",
			"turn=1 应先推 2017 注意力范式历史档案卡")

func test_exhausted_history_event_advances_to_next_card() -> void:
	GameState.turn = 70
	GameState.last_routine_turn = 100000
	GameState.event_trigger_counts[&"history_attention_turning_point"] = 1
	EventBus.phase_started.emit(&"action", GameState.turn)
	assert_eq(GameState.pending_events.size(), 1)
	assert_eq(GameState.pending_events[0].template_id, &"history_encoder_pretraining",
			"第一张耗尽后应按顺序推下一张已到 min_turn 的历史档案")

func test_dismiss_history_flavor_has_no_direct_effects() -> void:
	GameState.cash = 1_000_000
	var r1: Dictionary = CommandBus.send(&"event.trigger_card",
			{template_id = &"history_attention_turning_point"})
	assert_true(r1.ok)
	var r: Dictionary = CommandBus.send(&"event.dismiss_flavor", {event_id = r1.event_id})
	assert_true(r.ok)
	assert_eq(GameState.cash, 1_000_000,
			"历史档案是新闻/教育内容, dismiss 不应改变现金")
	assert_eq((r.applied_effects as Array).size(), 0)

func test_describe_effects_consequence_empty_for_no_passive_effects() -> void:
	var s: String = EventSystem.describe_effects_consequence([])
	assert_eq(s, "", "无 passive effects 时 flavor dismiss 按钮不应拼后果预览")
