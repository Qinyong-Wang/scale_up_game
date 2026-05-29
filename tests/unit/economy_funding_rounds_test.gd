extends GutTest

## EconomySystem — 8 轮融资 (pre_seed→seed→a→b→c→d→e→f), 可跳轮.
## Per design/经济系统设计.md §4.6.
##
## 玩家自发: economy.start_funding_round + economy.preview_funding_rounds.
## v9.1: 删除顺序锁, 只要 conditions 满足即可接该轮 (允许跳过前置轮).
## EventSystem 不再推融资 offer; funding_round_*.tres 事件 + funding_round_accept
## effect kind 已删除。

const ROUND_ORDER: Array[StringName] = [
	&"pre_seed", &"seed", &"a", &"b", &"c", &"d", &"e", &"f",
]

func before_each() -> void:
	GameState.reset()
	GameState.rng_seed = 42
	GameState._rng = null

# ---- preview --------------------------------------------------------------

func test_preview_returns_eight_rounds_in_order() -> void:
	var r: Dictionary = CommandBus.send(&"economy.preview_funding_rounds", {})
	assert_true(r.ok)
	var rounds: Array = r.rounds
	assert_eq(rounds.size(), 8, "expected 8 funding rounds")
	for i in range(ROUND_ORDER.size()):
		assert_eq(StringName(rounds[i].round), ROUND_ORDER[i],
				"round at index %d should be %s, got %s" % [
					i, ROUND_ORDER[i], rounds[i].round])

func test_preview_includes_amount_dilution_envelopes_and_display_name() -> void:
	var r: Dictionary = CommandBus.send(&"economy.preview_funding_rounds", {})
	var first: Dictionary = r.rounds[0]
	assert_gt(int(first.amount_min), 0)
	assert_gt(int(first.amount_max), int(first.amount_min))
	assert_gt(float(first.dilution_min), 0.0)
	assert_gt(float(first.dilution_max), float(first.dilution_min))
	assert_true(first.has(&"display_name"))
	assert_true(first.has(&"unlock_summary"))

func test_preview_initial_state_only_pre_seed_available() -> void:
	# Brand-new company: pre_seed is the only round with no preconditions.
	# v9.1: 其余轮 status=locked 表示 conditions 未满足 (不再因 order 锁定).
	var r: Dictionary = CommandBus.send(&"economy.preview_funding_rounds", {})
	assert_eq(StringName(r.rounds[0].status), &"available", "pre_seed must be available at game start")
	for i in range(1, ROUND_ORDER.size()):
		assert_eq(StringName(r.rounds[i].status), &"locked",
				"%s should be locked initially (conditions unmet), got %s" % [
					ROUND_ORDER[i], r.rounds[i].status])

func test_preview_after_pre_seed_accept_marks_pre_seed_accepted() -> void:
	var r1: Dictionary = CommandBus.send(&"economy.start_funding_round",
			{round = &"pre_seed"})
	assert_true(r1.ok, "pre_seed accept should succeed: %s" % r1)
	var pv: Dictionary = CommandBus.send(&"economy.preview_funding_rounds", {})
	assert_eq(StringName(pv.rounds[0].status), &"accepted",
			"pre_seed should now be accepted")
	# seed needs an evaluated model so it is still locked-by-conditions.
	assert_eq(StringName(pv.rounds[1].status), &"locked",
			"seed still requires evaluated model")

# ---- 可跳轮 (v9.1): 不再有顺序锁 -------------------------------------------

func test_skip_pre_seed_directly_to_seed_when_conditions_met() -> void:
	# 直接接 seed (跳过 pre_seed) — 只要 conditions 满足即可.
	_seed_evaluated_model()
	var r: Dictionary = CommandBus.send(&"economy.start_funding_round",
			{round = &"seed"})
	assert_true(r.ok, "seed should accept directly when conditions met: %s" % r)
	# pre_seed 未接受, 但 seed 已接受.
	assert_false(bool(GameState.funding_rounds_accepted.get(&"pre_seed", false)))
	assert_true(bool(GameState.funding_rounds_accepted.get(&"seed", false)))

func test_seed_without_pre_seed_blocked_by_conditions_only() -> void:
	# 没 pre_seed 也没 evaluated 模型 → 走 conditions_not_met, 不是 round_locked.
	var r: Dictionary = CommandBus.send(&"economy.start_funding_round",
			{round = &"seed"})
	assert_false(r.ok)
	assert_eq(r.error, &"conditions_not_met",
			"v9.1: skip rejection should be conditions_not_met, got %s" % r.error)

func test_skip_to_a_round_blocked_by_conditions_only() -> void:
	# A 轮需要 sub-board top3 + published + product, 开局都没有 → conditions_not_met.
	var r: Dictionary = CommandBus.send(&"economy.start_funding_round", {round = &"a"})
	assert_false(r.ok)
	assert_eq(r.error, &"conditions_not_met")

func test_back_fill_pre_seed_after_seed_accepted() -> void:
	# 跳轮接了 seed 之后, 仍可回头接 pre_seed (它没有 conditions, 永远 available).
	_seed_evaluated_model()
	CommandBus.send(&"economy.start_funding_round", {round = &"seed"})
	var r: Dictionary = CommandBus.send(&"economy.start_funding_round",
			{round = &"pre_seed"})
	assert_true(r.ok, "pre_seed remains accept-able after skipping: %s" % r)

func test_unknown_round_returns_unknown_round() -> void:
	var r: Dictionary = CommandBus.send(&"economy.start_funding_round",
			{round = &"super_secret_round"})
	assert_false(r.ok)
	assert_eq(r.error, &"unknown_round")

func test_already_accepted_returns_already_accepted() -> void:
	CommandBus.send(&"economy.start_funding_round", {round = &"pre_seed"})
	var r: Dictionary = CommandBus.send(&"economy.start_funding_round",
			{round = &"pre_seed"})
	assert_false(r.ok)
	assert_eq(r.error, &"already_accepted")

# ---- conditions gate ------------------------------------------------------

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

func test_seed_conditions_require_evaluated_model() -> void:
	# 没 evaluated 模型 → seed conditions fail. (v9.1: 不再需要先接 pre_seed.)
	var r: Dictionary = CommandBus.send(&"economy.start_funding_round", {round = &"seed"})
	assert_false(r.ok)
	assert_eq(r.error, &"conditions_not_met")

func test_seed_succeeds_when_evaluated_model_present() -> void:
	_seed_evaluated_model()
	var r: Dictionary = CommandBus.send(&"economy.start_funding_round", {round = &"seed"})
	assert_true(r.ok, "seed should succeed once evaluated model exists: %s" % r)

func test_preview_status_available_when_conditions_met() -> void:
	# evaluated 模型 → seed available, 即使 pre_seed 未接.
	_seed_evaluated_model()
	var pv: Dictionary = CommandBus.send(&"economy.preview_funding_rounds", {})
	assert_eq(StringName(pv.rounds[0].status), &"available", "pre_seed always available")
	assert_eq(StringName(pv.rounds[1].status), &"available", "seed should be available")
	# a requires rank + published + product.
	assert_eq(StringName(pv.rounds[2].status), &"locked")

# ---- amount & dilution stay in spec envelope ------------------------------

func test_pre_seed_amount_within_spec_envelope() -> void:
	var r: Dictionary = CommandBus.send(&"economy.start_funding_round", {round = &"pre_seed"})
	assert_true(r.ok)
	var spec: Dictionary = EconomySystem.FUNDING_ROUND_TABLE[&"pre_seed"]
	assert_true(int(r.amount) >= int(spec.amin) and int(r.amount) <= int(spec.amax),
			"amount %d not in [%d, %d]" % [int(r.amount), int(spec.amin), int(spec.amax)])
	assert_true(float(r.dilution) >= float(spec.dmin)
				and float(r.dilution) <= float(spec.dmax),
			"dilution %.4f not in [%.4f, %.4f]" % [
				float(r.dilution), float(spec.dmin), float(spec.dmax)])

func test_explicit_amount_clamped_to_envelope() -> void:
	# Test/CLI path can pass explicit amount/dilution; economy clamps to spec.
	var r: Dictionary = CommandBus.send(&"economy.start_funding_round", {
		round = &"pre_seed",
		amount = 999_999_999,    # way above pre_seed max
		dilution = 0.99,
	})
	assert_true(r.ok)
	var spec: Dictionary = EconomySystem.FUNDING_ROUND_TABLE[&"pre_seed"]
	assert_true(int(r.amount) <= int(spec.amax))
	assert_true(float(r.dilution) <= float(spec.dmax))

# ---- founder stake floor --------------------------------------------------

func test_founder_below_50_rejects_accept() -> void:
	# Pre-set founder to a value where the round dilution would drop them below 50%.
	# pre_seed dilution_max = 0.09 → 0.54 × (1 - 0.09) = 0.4914 ≤ 0.5 → reject.
	GameState.equity.founder = 0.54
	GameState.equity.investors = 0.46
	var r: Dictionary = CommandBus.send(&"economy.start_funding_round", {
		round = &"pre_seed",
		dilution = 0.09,
	})
	assert_false(r.ok)
	assert_eq(r.error, &"founder_stake_below_50")
	# Must not mark as accepted on reject.
	assert_false(bool(GameState.funding_rounds_accepted.get(&"pre_seed", false)))

# ---- emits the proper signals ---------------------------------------------

func test_accept_emits_funding_completed_equity_changed_cash_changed() -> void:
	watch_signals(EventBus)
	var r: Dictionary = CommandBus.send(&"economy.start_funding_round", {round = &"pre_seed"})
	assert_true(r.ok)
	assert_signal_emitted(EventBus, "funding_completed")
	assert_signal_emitted(EventBus, "equity_changed")
	assert_signal_emitted(EventBus, "cash_changed")
