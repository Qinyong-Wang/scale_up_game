extends Node

## EventSystem v1 — owns pending_events / event_history / event_cooldowns.
## Per design/事件系统设计.md.
##
## action phase: try to draw an event if no pending. choose_option dispatches
## EventEffects through CommandBus. flavor cards may be dismissed without a
## choice. Event templates discovered via the EVENTS table.
##
## v9 (2026-05): funding rounds removed from EventSystem. Funding is now
## player-initiated 8-round sequential (pre_seed→seed→a-f); see
## design/经济系统设计.md §4.6.


const OWNED_SLICES: Array[StringName] = [
	&"pending_events", &"event_history", &"event_cooldowns",
	&"event_trigger_counts", &"last_routine_turn",
]

const _EVENT_DIR: String = "res://resources/data/events/"

const EVENTS: Dictionary = {
	&"debug_add_starter": "res://resources/data/events/debug_add_starter.tres",
	# debug/测试夹具: 接替已删除的 funding_offer (天使投资人主动联系) 在测试里
	# "turn=1 空状态唯一可抽中卡"的角色。category=debug + weight=0 → 不进实战
	# 随机池, 玩家看不到; 测试需要时临时把 weight 调大再触发, 见 event_system_test。
	&"debug_test_offer": _EVENT_DIR + "debug_test_offer.tres",
	# 事件库 §1.6 时间锚点·技术范式卡 (v3): weight=0 不进随机池, 由
	# _maybe_trigger_paradigm_events() 在 min_turn 确定性 push.
	&"paradigm_rlhf": "res://resources/data/events/paradigm_rlhf.tres",
	&"paradigm_moe": "res://resources/data/events/paradigm_moe.tres",
	&"paradigm_long_ctx": "res://resources/data/events/paradigm_long_ctx.tres",
	&"paradigm_reasoning_rl": "res://resources/data/events/paradigm_reasoning_rl.tres",
	# v12 (2026-05): 历史档案 flavor 卡。weight=0 不进随机池, 由
	# _maybe_trigger_historical_event() 按固定顺序触发。
	&"history_attention_turning_point": _EVENT_DIR + "history_attention_turning_point.tres",
	&"history_encoder_pretraining": _EVENT_DIR + "history_encoder_pretraining.tres",
	&"history_large_decoder_wave": _EVENT_DIR + "history_large_decoder_wave.tres",
	&"history_synthetic_text_alarm": _EVENT_DIR + "history_synthetic_text_alarm.tres",
	&"history_scaling_laws": _EVENT_DIR + "history_scaling_laws.tres",
	&"history_sparse_expert_routing": _EVENT_DIR + "history_sparse_expert_routing.tres",
	&"history_foundation_model_frame": _EVENT_DIR + "history_foundation_model_frame.tres",
	&"history_diffusion_image_wave": _EVENT_DIR + "history_diffusion_image_wave.tres",
	&"history_instruction_chat_wave": _EVENT_DIR + "history_instruction_chat_wave.tres",
	&"history_open_weight_wave": _EVENT_DIR + "history_open_weight_wave.tres",
	&"history_multimodal_tool_wave": _EVENT_DIR + "history_multimodal_tool_wave.tres",
	&"history_long_context_race": _EVENT_DIR + "history_long_context_race.tres",
	&"history_verifiable_reasoning_wave": _EVENT_DIR + "history_verifiable_reasoning_wave.tres",
	# v10/v16: routine events (now forced every 12 weeks; see §4.5).
	&"routine_office_pet": _EVENT_DIR + "routine_office_pet.tres",
	&"routine_coffee_machine": _EVENT_DIR + "routine_coffee_machine.tres",
	&"routine_team_building": _EVENT_DIR + "routine_team_building.tres",
	&"routine_media_interview": _EVENT_DIR + "routine_media_interview.tres",
	&"routine_intern_demo": _EVENT_DIR + "routine_intern_demo.tres",
	&"routine_open_source_pr": _EVENT_DIR + "routine_open_source_pr.tres",
	&"routine_lawsuit_spam": _EVENT_DIR + "routine_lawsuit_spam.tres",
	&"routine_domain_renewal": _EVENT_DIR + "routine_domain_renewal.tres",
	&"routine_receipt_pile": _EVENT_DIR + "routine_receipt_pile.tres",
	&"routine_password_rotation": _EVENT_DIR + "routine_password_rotation.tres",
	&"routine_chair_squeak": _EVENT_DIR + "routine_chair_squeak.tres",
	&"routine_perf_review": _EVENT_DIR + "routine_perf_review.tres",
	&"routine_office_move": _EVENT_DIR + "routine_office_move.tres",
	# v10: opportunity 机会卡.
	&"big_client_hotpot": _EVENT_DIR + "big_client_hotpot.tres",
	&"viral_meme": _EVENT_DIR + "viral_meme.tres",
	&"star_researcher": _EVENT_DIR + "star_researcher.tres",
	&"gov_grant": _EVENT_DIR + "gov_grant.tres",
	&"conference_keynote": _EVENT_DIR + "conference_keynote.tres",
	&"acquihire_small": _EVENT_DIR + "acquihire_small.tres",
	# v10: crisis 危机卡.
	&"dc_meltdown": _EVENT_DIR + "dc_meltdown.tres",
	&"data_audit": _EVENT_DIR + "data_audit.tres",
	&"model_hallucination": _EVENT_DIR + "model_hallucination.tres",
	&"lead_poached": _EVENT_DIR + "lead_poached.tres",
	&"gpu_shortage": _EVENT_DIR + "gpu_shortage.tres",
	&"power_outage": _EVENT_DIR + "power_outage.tres",
	# v10: conditional 条件卡 (含 flavor).
	&"rank_one_party": _EVENT_DIR + "rank_one_party.tres",
	&"acquihire_offer": _EVENT_DIR + "acquihire_offer.tres",
	&"first_revenue": _EVENT_DIR + "first_revenue.tres",
	&"bubble_warning": _EVENT_DIR + "bubble_warning.tres",
	&"agi_rumor": _EVENT_DIR + "agi_rumor.tres",
	# v11: drama 真两难卡 (AI 历史争议 + 硅谷梗, 多数 max_triggers=1).
	# 见 design/事件库.md §1bis。2026-05 删除 moat_memo_leak / weights_leak /
	# deepseek_moment 三张"开源/降价"主题卡 (玩家不直接操盘定价/开源, 决策落点空)。
	&"board_coup": _EVENT_DIR + "board_coup.tres",
	&"pause_letter": _EVENT_DIR + "pause_letter.tres",
	&"data_lawsuit": _EVENT_DIR + "data_lawsuit.tres",
	&"sentient_engineer": _EVENT_DIR + "sentient_engineer.tres",
	&"celebrity_voice": _EVENT_DIR + "celebrity_voice.tres",
	&"doomer_vs_acc": _EVENT_DIR + "doomer_vs_acc.tres",
	&"three_commas_investor": _EVENT_DIR + "three_commas_investor.tres",
	&"middle_out": _EVENT_DIR + "middle_out.tres",
	&"not_hotdog": _EVENT_DIR + "not_hotdog.tres",
	&"hooli_keynote": _EVENT_DIR + "hooli_keynote.tres",
	&"platform_pivot": _EVENT_DIR + "platform_pivot.tres",
	&"rogue_agent": _EVENT_DIR + "rogue_agent.tres",
	&"benchmark_gaming": _EVENT_DIR + "benchmark_gaming.tres",
	&"hardware_box_pivot": _EVENT_DIR + "hardware_box_pivot.tres",
	&"exclusive_megadeal": _EVENT_DIR + "exclusive_megadeal.tres",
	&"rebrand_consultant": _EVENT_DIR + "rebrand_consultant.tres",
	&"fake_users": _EVENT_DIR + "fake_users.tres",
	# v11: 非技术向纯喜剧 (只玩钱和团队, 不碰订阅/技术).
	&"ai_orders_beef": _EVENT_DIR + "ai_orders_beef.tres",
	&"doomsday_bunker": _EVENT_DIR + "doomsday_bunker.tres",
	# v17: AI 行业黑色幽默一次性卡.
	&"support_bot_refund_policy": _EVENT_DIR + "support_bot_refund_policy.tres",
	&"forum_wisdom_summary": _EVENT_DIR + "forum_wisdom_summary.tres",
	&"fictional_case_law": _EVENT_DIR + "fictional_case_law.tres",
	&"history_image_overfit": _EVENT_DIR + "history_image_overfit.tres",
	&"support_bot_self_roast": _EVENT_DIR + "support_bot_self_roast.tres",
	&"compliance_bot_illegal_advice": _EVENT_DIR + "compliance_bot_illegal_advice.tres",
	# v11: 灰暗 / 伦理向 (利润 vs 良心的两难).
	&"labeling_sweatshop": _EVENT_DIR + "labeling_sweatshop.tres",
	&"surveillance_contract": _EVENT_DIR + "surveillance_contract.tres",
	&"companion_tragedy": _EVENT_DIR + "companion_tragedy.tres",
	&"crunch_culture": _EVENT_DIR + "crunch_culture.tres",
}

# Routine event cadence in weeks. v16: 8 → 12 to fix over-frequent mature games.
const ROUTINE_INTERVAL: int = 12
const GLOBAL_MAX_TRIGGERS_PER_CARD: int = 3

# Paradigm cards trigger deterministically by turn threshold (NPC配置.md §1.4).
# Iteration order is preserved — earliest min_turn first.
const PARADIGM_EVENTS: Array[StringName] = [
	&"paradigm_rlhf",
	&"paradigm_moe",
	&"paradigm_long_ctx",
	&"paradigm_reasoning_rl",
]

const HISTORICAL_EVENTS: Array[StringName] = [
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

## v10 (2026-05): 0.35 → 0.10. v11: 0.10 → 0.07. v16: 0.07 → 0.03,
## With routine cadence 8→12 and max_triggers caps, mature games return to roughly
## one event every 6-8 weeks. See design/事件系统设计.md §4.1.
const EVENT_TRIGGER_PROB_PER_WEEK: float = 0.03
const HISTORY_LIMIT: int = 50

var _next_event_seq: int = 1

func _ready() -> void:
	CommandBus.register(&"event.choose_option", _on_choose_option)
	CommandBus.register(&"event.trigger_card", _on_trigger_card)
	CommandBus.register(&"event.dismiss_flavor", _on_dismiss_flavor)
	EventBus.phase_started.connect(_on_phase)
	EventBus.save_loaded.connect(_on_save_loaded)

# ---- commands -----------------------------------------------------------

func _on_choose_option(p: Dictionary) -> Dictionary:
	var event_id: StringName = p.get(&"event_id", &"")
	var inst := _find_pending(event_id)
	if inst == null:
		return {ok = false, error = &"unknown_event"}
	if inst.resolved_at_turn > 0:
		return {ok = false, error = &"already_resolved"}
	var card := _load_card(inst.template_id)
	var option_id: StringName = p.get(&"option_id", &"")
	var opt = _find_option(card, option_id)
	if opt == null:
		return {ok = false, error = &"unknown_option"}

	var applied: Array = []
	for effect in opt.effects:
		var r: Dictionary = _apply_effect(effect, inst)
		applied.append({kind = effect.kind, ok = r.get(&"ok", false), error = r.get(&"error", &"")})

	inst.chosen_option_id = option_id
	inst.resolved_at_turn = GameState.turn
	GameState.pending_events.erase(inst)
	GameState.event_history.append(inst)
	while GameState.event_history.size() > HISTORY_LIMIT:
		GameState.event_history.pop_front()
	EventBus.event_resolved.emit(inst.id, option_id, applied)
	return {ok = true, applied_effects = applied}

func _on_trigger_card(p: Dictionary) -> Dictionary:
	var template_id: StringName = p.get(&"template_id", &"")
	var card := _load_card(template_id)
	if card == null:
		return {ok = false, error = &"unknown_template"}
	if _triggers_exhausted(card):
		return {ok = false, error = &"event_trigger_exhausted"}
	var inst := _trigger(card)
	return {ok = true, event_id = inst.id}

func _on_dismiss_flavor(p: Dictionary) -> Dictionary:
	var event_id: StringName = p.get(&"event_id", &"")
	var inst := _find_pending(event_id)
	if inst == null:
		return {ok = false, error = &"unknown_event"}
	var card := _load_card(inst.template_id)
	if card == null:
		Log.warn(&"event", "missing_template_dismissed",
				{event_id = inst.id, template_id = inst.template_id})
		inst.resolved_at_turn = GameState.turn
		inst.chosen_option_id = &"missing_template"
		GameState.pending_events.erase(inst)
		GameState.event_history.append(inst)
		EventBus.event_resolved.emit(inst.id, &"missing_template", [])
		return {ok = true, applied_effects = []}
	if card.category != &"flavor":
		return {ok = false, error = &"not_flavor"}
	var applied: Array = []
	for effect in card.passive_effects:
		var r: Dictionary = _apply_effect(effect, inst)
		applied.append({kind = effect.kind, ok = r.get(&"ok", false), error = r.get(&"error", &"")})
	inst.resolved_at_turn = GameState.turn
	GameState.pending_events.erase(inst)
	GameState.event_history.append(inst)
	EventBus.event_resolved.emit(inst.id, &"dismissed", applied)
	return {ok = true, applied_effects = applied}

# ---- phase --------------------------------------------------------------

func _on_phase(phase: StringName, _turn: int) -> void:
	if phase != &"action":
		return
	# 时间锚点 paradigm 事件先于随机抽卡 (NPC配置.md §1.4): weight=0 不进随机池,
	# 由本函数按 min_turn 阈值确定性 push, 一次性 (cooldown=9999).
	_maybe_trigger_paradigm_events()
	if GameState.pending_events.size() > 0:
		return
	# v12: 历史档案卡是无选择 flavor, 但按固定历史顺序确定性出现, 不进随机池。
	_maybe_trigger_historical_event()
	if GameState.pending_events.size() > 0:
		return
	# v10/v11: routine 常规事件每 ROUTINE_INTERVAL 周强制弹一张, 优先于随机抽卡 (§4.5).
	_maybe_trigger_routine_event()
	if GameState.pending_events.size() > 0:
		return
	if GameState.rng().randf() > EVENT_TRIGGER_PROB_PER_WEEK:
		return
	var candidates: Array = []
	for tmpl_id in EVENTS.keys():
		# Paradigm cards are out of the random pool; deterministic trigger via
		# _maybe_trigger_paradigm_events() above (事件库 §1.6).
		if String(tmpl_id).begins_with("paradigm_"):
			continue
		# 历史档案也由固定时间线触发, 不进随机池。
		if String(tmpl_id).begins_with("history_"):
			continue
		var card := _load_card(tmpl_id)
		if card == null: continue
		# routine 卡只通过 _maybe_trigger_routine_event() 触发, 不进随机池.
		if card.category == &"routine": continue
		if not _conditions_met(card): continue
		if int(GameState.event_cooldowns.get(card.id, 0)) > GameState.turn: continue
		if _triggers_exhausted(card): continue  # v11: max_triggers 限次
		if int(card.weight) <= 0: continue  # weight=0 cards stay out of the pool
		candidates.append(card)
	if candidates.is_empty(): return
	var card: EventCard = _weighted_pick(candidates)
	_trigger(card)

# v10 §4.5: routine 常规事件每 ROUTINE_INTERVAL 周强制弹一张。用
# last_routine_turn 计时, 对忙碌队列造成的延迟也稳健。routine 池保证非空
# (至少 2 张只 gate min_turn>=4)。
func _maybe_trigger_routine_event() -> void:
	if GameState.pending_events.size() > 0:
		return
	if GameState.turn - GameState.last_routine_turn < ROUTINE_INTERVAL:
		return
	var candidates: Array = []
	for tmpl_id in EVENTS.keys():
		var cand := _load_card(tmpl_id)
		if cand == null: continue
		if cand.category != &"routine": continue
		if not _conditions_met(cand): continue
		if int(GameState.event_cooldowns.get(cand.id, 0)) > GameState.turn: continue
		if _triggers_exhausted(cand): continue  # v11: max_triggers 限次
		if int(cand.weight) <= 0: continue
		candidates.append(cand)
	if candidates.is_empty():
		return  # 本周没合格 routine, 下周再试
	var card: EventCard = _weighted_pick(candidates)
	_trigger(card)
	GameState.last_routine_turn = GameState.turn

# 事件库 §1.6 / NPC配置 §1.4: deterministic time-anchor trigger for paradigm_*
# cards. At most one paradigm event pushed per action phase; min_turn gates and
# the huge cooldown stamped at trigger time prevents re-triggers.
func _maybe_trigger_paradigm_events() -> void:
	if GameState.pending_events.size() > 0:
		return
	for tmpl_id in PARADIGM_EVENTS:
		if int(GameState.event_cooldowns.get(tmpl_id, 0)) > GameState.turn:
			continue
		var card := _load_card(tmpl_id)
		if card == null: continue
		if GameState.turn < int(card.min_turn): continue
		if _triggers_exhausted(card): continue  # v11: max_triggers 限次
		_trigger(card)
		return  # one per action phase, in min_turn order

func _maybe_trigger_historical_event() -> void:
	if GameState.pending_events.size() > 0:
		return
	for tmpl_id in HISTORICAL_EVENTS:
		if int(GameState.event_cooldowns.get(tmpl_id, 0)) > GameState.turn:
			continue
		var card := _load_card(tmpl_id)
		if card == null: continue
		if GameState.turn < int(card.min_turn): continue
		if not _conditions_met(card): continue
		if _triggers_exhausted(card): continue
		_trigger(card)
		return

# ---- helpers ------------------------------------------------------------

func _gen_event_id() -> StringName:
	var id := StringName("event_%04d" % _next_event_seq)
	_next_event_seq += 1
	return id

## _next_event_seq 是会话计数器, 不入存档。读档后恢复它 + 修旧档已有的重复
## event ID, 否则读档后新触发的事件会和档里的 pending / history 撞 ID。
## 详见 design/数据集系统设计.md §3 同类病。
func _on_save_loaded() -> void:
	_next_event_seq = maxi(_next_event_seq, GameState.max_seq_for_prefix(
			[GameState.pending_events, GameState.event_history], "event_") + 1)
	for ch in GameState.dedup_ids(
			[GameState.pending_events, GameState.event_history], _gen_event_id):
		Log.warn(&"event", "save_loaded_duplicate_event_id_repaired",
				{old_id = ch.old_id, new_id = ch.new_id})

func _trigger(card: EventCard) -> EventInstance:
	var inst := EventInstance.new()
	inst.id = _gen_event_id()
	inst.template_id = card.id
	inst.triggered_at_turn = GameState.turn
	GameState.pending_events.append(inst)
	GameState.event_cooldowns[card.id] = GameState.turn + _cooldown_turns(card)
	# v11 §4.7: 累计触发次数, 配合 max_triggers 实现限次。
	GameState.event_trigger_counts[card.id] = int(
			GameState.event_trigger_counts.get(card.id, 0)) + 1
	Log.info(&"event", "pushed", {id = inst.id, card = card.id, category = card.category})
	EventBus.event_pushed.emit(inst.id, card.category, card.title)
	return inst

## EventCard.cooldown_months is authored in design months; turns are weeks.
func _cooldown_turns(card: EventCard) -> int:
	return maxi(0, int(card.cooldown_months)) * TurnManager.WEEKS_PER_MONTH

## v17 §4.7: 所有卡都有 3 次硬上限; max_triggers>0 可设更严格单卡上限。
func _triggers_exhausted(card: EventCard) -> bool:
	return int(GameState.event_trigger_counts.get(card.id, 0)) >= _effective_max_triggers(card)

func _effective_max_triggers(card: EventCard) -> int:
	var maxt: int = int(card.max_triggers) if "max_triggers" in card else 0
	if maxt <= 0:
		return GLOBAL_MAX_TRIGGERS_PER_CARD
	return mini(maxt, GLOBAL_MAX_TRIGGERS_PER_CARD)

func _conditions_met(card: EventCard) -> bool:
	if GameState.turn < card.min_turn: return false
	if GameState.cash < card.requires_cash_min: return false
	# v7 PR-F: revenue + rank gates replace the legacy fame gate.
	if "requires_revenue_min" in card and int(card.requires_revenue_min) > 0:
		if GameState.quarterly_revenue < int(card.requires_revenue_min):
			return false
	if "requires_rank_max" in card and int(card.requires_rank_max) > 0:
		if not _player_in_top_n(&"total", int(card.requires_rank_max)):
			return false
	for tag in card.requires_unlocks:
		var parts: PackedStringArray = String(tag).split(":")
		if parts.size() != 2: continue
		var tree: StringName = StringName(parts[0])
		var node: StringName = StringName(parts[1])
		if not bool(GameState.unlocks.get(tree, {}).get(node, false)):
			return false
	# v10: 7 个状态门禁 (§4.3). 每张卡都至少满足一个条件, 贴合当前局势。
	if "requires_datacenter" in card and card.requires_datacenter:
		if GameState.datacenters.is_empty(): return false
	if "requires_product" in card and card.requires_product:
		if GameState.products.is_empty(): return false
	if "requires_published_model" in card and card.requires_published_model:
		if not _has_published_model(): return false
	if "requires_lead_min" in card and _non_founder_lead_count() < int(card.requires_lead_min):
		return false
	if "requires_staff_min" in card and _total_staff() < int(card.requires_staff_min):
		return false
	if "requires_dataset_min" in card and GameState.datasets.size() < int(card.requires_dataset_min):
		return false
	if "requires_paid_users_min" in card and GameState.paid_users < int(card.requires_paid_users_min):
		return false
	return true

func _has_published_model() -> bool:
	for m in GameState.models:
		if m.status == &"published":
			return true
	return false

## 数非 founder lead。创始人本身计入 GameState.leads (is_player_scientist=true),
## 但"挖人"/"星级研究员加盟"这类卡的叙事只对真招进来的 lead 成立, 单人时
## 期不应触发。见 design/事件系统设计.md §1 / §4.3。
func _non_founder_lead_count() -> int:
	var n: int = 0
	for l in GameState.leads:
		if not l.is_player_scientist:
			n += 1
	return n

func _total_staff() -> int:
	var n: int = 0
	for role in GameState.staff_pool.keys():
		n += int(GameState.staff_pool[role])
	return n

func _player_in_top_n(board_id: StringName, n: int) -> bool:
	var board: Array = GameState.leaderboard.get(board_id, [])
	for entry in board:
		if entry.entity_type == &"player_model" and entry.rank <= n:
			return true
	return false

func _weighted_pick(cards: Array) -> EventCard:
	var total: int = 0
	for c in cards:
		total += c.weight
	var roll: int = GameState.rng().randi_range(0, maxi(0, total - 1))
	var acc: int = 0
	for c in cards:
		acc += c.weight
		if roll < acc:
			return c
	return cards[-1]

func _find_pending(event_id: StringName) -> EventInstance:
	for inst in GameState.pending_events:
		if inst.id == event_id:
			return inst
	return null

func _find_option(card: EventCard, option_id: StringName):
	for opt in card.options:
		if opt.id == option_id:
			return opt
	return null

func _load_card(template_id: StringName) -> EventCard:
	var path: String = EVENTS.get(template_id, "")
	if path == "":
		return null
	var res := load(path)
	if res is EventCard:
		return res
	return null

func _apply_effect(effect, inst: EventInstance) -> Dictionary:
	# Start from the .tres effect.params, then layer per-instance dispatched
	# params on top so per-offer roll-time values (legacy hook — kept for
	# generality even though funding rounds no longer use it).
	var params: Dictionary = (effect.params if effect.params != null else {}).duplicate()
	if not inst.dispatched_params.is_empty():
		for k in inst.dispatched_params.keys():
			params[k] = inst.dispatched_params[k]
	var reason: StringName = StringName("event:" + String(inst.id))
	match effect.kind:
		&"economy_spend":
			var cost_payload: Dictionary = (params[&"cost"] if params.has(&"cost")
					else {&"cash": _resolve_money_amount(params)})
			return CommandBus.send(&"economy.spend", {
				cost = cost_payload,
				reason = reason,
			})
		&"economy_award":
			return CommandBus.send(&"economy.award", {
				amount = _resolve_money_amount(params), reason = reason,
			})
		&"fame_add":
			# v7 PR-F (2026-05): fame field retired. Legacy `fame_add` effects
			# in .tres are accepted but no longer apply any mechanical change.
			Log.warn(&"event", "fame_add_deprecated", {reason = reason})
			return {ok = true, deprecated = true}
		&"npc_perturb", &"npc_capability_jump":
			# v8 PR-H (2026-05): NPC is now timeline-driven; both deprecated.
			Log.warn(&"event", "npc_capability_effect_deprecated",
					{kind = String(effect.kind), reason = reason})
			return {ok = true, deprecated = true}
		&"tech_grant":
			return CommandBus.send(&"tech.unlock_node", {
				tree = params.get(&"tree", &""),
				node_id = params.get(&"node_id", &""),
			})
		&"dc_terminate":
			var dc_id: StringName = params.get(&"dc_id", &"")
			if dc_id == &"":
				dc_id = _random_dc_id()
			return CommandBus.send(&"infra.terminate_dc", {
				dc_id = dc_id,
			})
		&"model_buff":
			return CommandBus.send(&"research.evaluate_apply", {
				model_id = params.get(&"model_id", &""),
				capability_measured = params.get(
						&"capability_measured", params.get(&"capability_delta", {})),
			})
		&"flag_set":
			# Punt: no generic GameState flag bucket yet (autoload locked this
			# turn). Log and treat as ok so designers can wire flags into cards
			# once a flags slice is added. See 事件系统设计.md §6.3.
			Log.warn(&"event", "flag_set_unsupported",
					{flag = params.get(&"flag_name", &""), value = params.get(&"value", null)})
			return {ok = true}
		&"dataset_delete":
			var ds_id: StringName = params.get(&"dataset_id", &"")
			if ds_id == &"":
				ds_id = _random_dataset_id()
			return CommandBus.send(&"dataset.delete", {
				dataset_id = ds_id,
			})
		&"product_boost_subscribers":
			var pid: StringName = params.get(&"product_id", &"")
			if pid == &"":
				pid = _largest_product_id()
			return CommandBus.send(&"product.update_subscribers", {
				product_id = pid,
				delta = _resolve_subscriber_delta(params),
			})
		&"debug_starter_kit":
			return _apply_debug_starter_kit(inst)
		_:
			return {ok = false, error = &"unknown_kind"}

# ---- v10 比例化数值 / 随机目标 (事件系统设计.md §4.2.1) ------------------

## 解析 economy_spend / economy_award 的金额: 支持 pct (现金比例) + floor/cap
## 兜底, 兼容旧的 amount / cost:{cash} 绝对值写法。
func _resolve_money_amount(params: Dictionary) -> int:
	if params.has(&"pct"):
		var base: int = maxi(0, GameState.cash)
		var amt: int = int(round(absf(float(params[&"pct"])) * float(base)))
		if params.has(&"floor"):
			amt = maxi(amt, int(params[&"floor"]))
		if params.has(&"cap"):
			amt = mini(amt, int(params[&"cap"]))
		return amt
	if params.has(&"cost") and params[&"cost"] is Dictionary:
		return int(params[&"cost"].get(&"cash", 0))
	return int(params.get(&"amount", 0))

## 解析 product_boost_subscribers 的 delta: 支持 pct (总订阅数比例) + floor
## (最小绝对量级) + cap (|delta| 上限), 兼容旧的 delta 绝对值写法。
## 后期 5B+ 总订阅时, viral_meme 22% 会算成 +1.1B 用户; cap 保证单张卡
## 的 |delta| 不超过事件叙事可信度 (见 设计.md §4.2.1)。
func _resolve_subscriber_delta(params: Dictionary) -> int:
	if params.has(&"pct"):
		var total: int = 0
		for prod in GameState.products:
			total += int(prod.subscribers)
		var pct: float = float(params[&"pct"])
		var delta: int = int(round(pct * float(total)))
		var mag: int = absi(delta)
		var floor_mag: int = int(params.get(&"floor", 0))
		if floor_mag > 0:
			mag = maxi(mag, floor_mag)
		if params.has(&"cap"):
			mag = mini(mag, int(params[&"cap"]))
		return mag if pct >= 0.0 else -mag
	return int(params.get(&"delta", 0))

func _largest_product_id() -> StringName:
	var best: StringName = &""
	var best_subs: int = -1
	for prod in GameState.products:
		if int(prod.subscribers) > best_subs:
			best_subs = int(prod.subscribers)
			best = prod.id
	return best

func _random_dataset_id() -> StringName:
	if GameState.datasets.is_empty():
		return &""
	var idx: int = GameState.rng().randi_range(0, GameState.datasets.size() - 1)
	return GameState.datasets[idx].id

func _random_dc_id() -> StringName:
	if GameState.datacenters.is_empty():
		return &""
	var idx: int = GameState.rng().randi_range(0, GameState.datacenters.size() - 1)
	return GameState.datacenters[idx].id

# ---- UI 后果预览 (事件弹窗在选项上显示玩家"会得到什么") -------------------

## 把一个 EventOption 的所有 effect 翻成一句玩家能看懂的后果描述。比例化数值
## 按**当前** GameState 即时估算 (= 玩家此刻选择会落地的实际值)。无 effect 的
## 选项返回 "无直接影响"。供 UI 在选项按钮上拼到 label 后面。
## 选项后果预览 (UI 文案, 走 strings.csv 的 EVENT_CONSEQ_* key, 见 国际化设计.md §6bis)。
func describe_option_consequence(opt) -> String:
	if opt == null or opt.effects == null or opt.effects.is_empty():
		return tr("EVENT_CONSEQ_NONE")
	return _describe_effects_consequence(opt.effects, tr("EVENT_CONSEQ_NONE"))

func describe_effects_consequence(effects: Array) -> String:
	return _describe_effects_consequence(effects, "")

func _describe_effects_consequence(effects: Array, empty_text: String) -> String:
	if effects == null or effects.is_empty():
		return empty_text
	var parts: PackedStringArray = PackedStringArray()
	for effect in effects:
		var s: String = _describe_effect(effect)
		if s != "":
			parts.append(s)
	if parts.is_empty():
		return empty_text
	return ", ".join(parts)

func _describe_effect(effect) -> String:
	if effect == null:
		return ""
	var params: Dictionary = (effect.params if effect.params != null else {})
	match effect.kind:
		&"economy_spend":
			return tr("EVENT_CONSEQ_SPEND") % _fmt_grouped(_resolve_money_amount(params))
		&"economy_award":
			return tr("EVENT_CONSEQ_AWARD") % _fmt_grouped(_resolve_money_amount(params))
		&"product_boost_subscribers":
			var d: int = _resolve_subscriber_delta(params)
			if d >= 0:
				return tr("EVENT_CONSEQ_SUBS_UP") % _fmt_grouped(d)
			return tr("EVENT_CONSEQ_SUBS_DOWN") % _fmt_grouped(-d)
		&"dc_terminate":
			return tr("EVENT_CONSEQ_DC_TERMINATE")
		&"dataset_delete":
			return tr("EVENT_CONSEQ_DATASET_DELETE")
		&"tech_grant":
			return tr("EVENT_CONSEQ_TECH_GRANT")
		&"model_buff":
			return tr("EVENT_CONSEQ_MODEL_BUFF")
		_:
			return ""  # fame_add 等已废弃 effect 不展示

## 千分位分组, e.g. 1234567 → "1,234,567"。
func _fmt_grouped(n: int) -> String:
	var s: String = str(absi(n))
	var out: String = ""
	var c: int = 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return out

# ---- debug effects ------------------------------------------------------

## debug_starter_kit: award $3M, inject 2 leads per specialty (B level),
## create a fully-built 72-GPU rack DC, acquire all 2017 open-source datasets.
## Triggered only via event.trigger_card with template_id=&"debug_add_starter".
func _apply_debug_starter_kit(inst: EventInstance) -> Dictionary:
	var reason: StringName = StringName("event:" + String(inst.id))

	# 1. $3M cash
	CommandBus.send(&"economy.award", {amount = 3_000_000, reason = reason})
	Log.info(&"event", "debug_starter_kit_cash", {amount = 3_000_000})

	# 2. Two leads of each specialty at B level (ability 60, salary ¥700/week)
	var _seq: int = 0
	for specialty: StringName in HiringSystem.SPECIALTIES:
		for _i in range(2):
			_seq += 1
			var l := Lead.new()
			l.id = StringName("debug_lead_%04d" % _seq)
			l.display_name = "Debug %s #%d" % [String(specialty), _i + 1]
			l.specialty = specialty
			l.level = &"B"
			l.ability = 60.0
			l.signing_fee = 0
			l.weekly_salary = 700
			GameState.leads.append(l)
			EventBus.lead_hired.emit(l.id)
	Log.info(&"event", "debug_starter_kit_leads", {count = _seq})

	# 3. Instant 72-card self-built datacenter (facility_rack + cypress_t0, grid power).
	# cypress_t0 is the 2017 game-start GPU; cypress_t1 only
	# unlocks at turn=152 (2020-05) and would be timeline-inconsistent here.
	var dc_result := CommandBus.send(&"infra.debug_instant_owned_dc", {
		facility_spec_id = &"facility_rack",
		gpu_id = &"cypress_t0",
	})
	if not dc_result.get(&"ok", false):
		Log.warn(&"event", "debug_starter_kit_dc_failed", {error = dc_result.get(&"error", "")})

	# 4. All 2017 open-source datasets (released_at_week = 0). Per v2 timeline
	# the starter_* fake-ids were removed in favor of real-world 2017-era ones.
	var datasets_2017: Array[StringName] = [
		&"bookcorpus_v1", &"wiki_dump_2017", &"commoncrawl_raw_2017",
		&"chat_logs_v1", &"imdb_reviews_v1", &"math_reasoning_set_v1",
		&"image_corpus_v1", &"web_corpus_v1",
	]
	var acquired: int = 0
	for ds_id in datasets_2017:
		var r := CommandBus.send(&"dataset.acquire_open", {template_id = ds_id})
		if r.get(&"ok", false):
			acquired += 1
		elif r.get(&"error", &"") != &"already_owned":
			Log.warn(&"event", "debug_starter_kit_dataset_failed",
				{id = ds_id, error = r.get(&"error", "")})
	Log.info(&"event", "debug_starter_kit_datasets", {acquired = acquired})

	return {ok = true}
