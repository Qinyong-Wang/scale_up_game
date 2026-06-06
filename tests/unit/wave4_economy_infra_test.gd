extends GutTest

## Tests for the Wave 4 alignment changes.
## - STARTING_CASH = 80_000 per 经济系统 v2 tuning.tres (was 1_000_000 pre-v9).
## - repay_loan / charge_loans emit cash_changed + debt_changed.
## - accept_funding_round honors `recheck_conditions` flag.
## - InfraSystem rent/build returns `facility_unlock_required`.
## - InfraSystem buy_gpus rejects pre-release-turn purchases (`gpu_not_released`).
## - InfraSystem buy_gpus allowed during dc.status != idle.
## - InfraSystem assign_to_task rejects 0-card dcs (`no_gpus`).


func before_each() -> void:
	GameState.reset()

# ---- STARTING_CASH ------------------------------------------------------

func test_starting_cash_is_one_million_per_design() -> void:
	# 经济系统 v2 (2026-05): tuning.tres starting_cash = 80_000.
	assert_eq(GameState.STARTING_CASH, 80_000)
	assert_eq(GameState.cash, 80_000)

# ---- repay_loan / charge_loans signal completeness ----------------------

func test_repay_loan_emits_cash_and_debt_changed() -> void:
	# 经济系统设计 §3 contract: any cash-affecting event fires cash_changed
	# AND any debt-affecting event fires debt_changed. Both must fire on repay.
	GameState.cash = 1_000_000
	var lr: Dictionary = CommandBus.send(&"economy.take_loan",
			{amount = 100_000, term_weeks = 12})
	assert_true(lr.ok)
	watch_signals(EventBus)
	CommandBus.send(&"economy.repay_loan", {loan_id = lr.loan_id, amount = 50_000})
	assert_signal_emitted(EventBus, "cash_changed")
	assert_signal_emitted(EventBus, "debt_changed")
	assert_signal_emitted(EventBus, "resources_changed")

func test_charge_loans_emits_debt_changed_for_principal_paydown() -> void:
	GameState.cash = 1_000_000
	var lr: Dictionary = CommandBus.send(&"economy.take_loan",
			{amount = 120_000, term_weeks = 12})
	watch_signals(EventBus)
	# Run upkeep — _charge_loans should fire.
	EventBus.phase_started.emit(&"upkeep", 1)
	# At least one debt_changed should fire (for the 10k principal paydown).
	assert_signal_emitted(EventBus, "debt_changed")

# ---- start_funding_round (玩家自发, v9 替代 accept_funding_round) ---------

func test_start_funding_round_seed_blocks_when_conditions_unmet() -> void:
	# 没 evaluated 模型, seed 应被 conditions_not_met 拦下.
	# (v9.1: 不再需要先接 pre_seed)
	var r: Dictionary = CommandBus.send(&"economy.start_funding_round", {round = &"seed"})
	assert_false(r.ok)
	assert_eq(r.error, &"conditions_not_met")

func test_start_funding_round_seed_passes_when_conditions_met() -> void:
	CommandBus.send(&"research.add_model",
			{capability = {}, arch = &"ant_v1", dataset_ids = []})
	var mid: StringName = GameState.models[0].id
	CommandBus.send(&"research.evaluate_apply",
			{model_id = mid, capability_measured = {&"general": 50.0}})
	var r: Dictionary = CommandBus.send(&"economy.start_funding_round", {round = &"seed"})
	assert_true(r.ok, "seed accept should succeed: %s" % r)

func test_start_funding_round_pre_seed_no_conditions() -> void:
	# pre_seed 是开局可接的, 无前置条件.
	var r: Dictionary = CommandBus.send(&"economy.start_funding_round",
			{round = &"pre_seed"})
	assert_true(r.ok)

# ---- bankruptcy_warning carries reason and fires for cash_too_deep ------

func test_bankruptcy_warning_reason_for_cash_negative() -> void:
	GameState.cash = -1
	watch_signals(EventBus)
	EventBus.phase_started.emit(&"resolve", 1)
	var p: Array = get_signal_parameters(EventBus, "bankruptcy_warning")
	assert_eq(StringName(p[0]), &"cash_negative")

# ---- InfraSystem error codes --------------------------------------------

func test_rent_facility_returns_facility_unlock_required_when_cash_below_gate() -> void:
	# v7 PR-F: facility gate is now cash, not fame. Error code stays
	# facility_unlock_required for UI/back-compat.
	GameState.cash = 100_000
	var r: Dictionary = CommandBus.send(&"infra.rent_facility",
			{facility_spec_id = &"facility_hall", power_supply_id = &"grid"})
	assert_false(r.ok)
	assert_eq(r.error, &"facility_unlock_required")

func test_build_facility_returns_facility_unlock_required_when_cash_below_gate() -> void:
	# v7 PR-F: gate is now cash, not fame. Force low cash below
	# facility_hall.unlock_cash_required to retain the original test intent.
	GameState.cash = 100_000
	var r: Dictionary = CommandBus.send(&"infra.build_facility",
			{facility_spec_id = &"facility_hall", power_supply_id = &"grid"})
	assert_false(r.ok)
	assert_eq(r.error, &"facility_unlock_required")

func test_buy_gpus_rejects_unreleased_gpu() -> void:
	# cypress_t1 has release_turn=152; can't buy at turn 0.
	GameState.cash = 100_000_000
	var rdc: Dictionary = CommandBus.send(&"infra.rent_facility",
			{facility_spec_id = &"facility_pod", power_supply_id = &"grid"})
	var r: Dictionary = CommandBus.send(&"infra.buy_gpus",
			{dc_id = rdc.dc_id, gpu_id = &"cypress_t1", count = 1})
	assert_false(r.ok)
	assert_eq(r.error, &"gpu_not_released")

func test_buy_gpus_succeeds_when_dc_is_serving() -> void:
	# Elastic capacity affordance: adding cards mid-serve must work.
	GameState.cash = 100_000_000
	var rdc: Dictionary = CommandBus.send(&"infra.rent_facility",
			{facility_spec_id = &"facility_pod", power_supply_id = &"grid"})
	CommandBus.send(&"infra.buy_gpus",
			{dc_id = rdc.dc_id, gpu_id = &"cypress_t0", count = 1})
	# Plant a published model, deploy → status becomes serving.
	var rm: Dictionary = CommandBus.send(&"research.add_model",
			{capability = {}, arch = &"ant_v1", dataset_ids = []})
	CommandBus.send(&"research.evaluate_apply",
			{model_id = rm.model_id, capability_measured = {&"general": 50.0}})
	CommandBus.send(&"research.publish_model",
			{model_id = rm.model_id, is_open_source = false, per_token_price = 0.001})
	CommandBus.send(&"infra.deploy_model",
			{dc_id = rdc.dc_id, model_id = rm.model_id})
	# Now buy more cards — must succeed despite serving status.
	var r: Dictionary = CommandBus.send(&"infra.buy_gpus",
			{dc_id = rdc.dc_id, gpu_id = &"cypress_t0", count = 1})
	assert_true(r.ok, "buy_gpus during serving must succeed")

func test_assign_to_task_rejects_zero_card_dc() -> void:
	GameState.cash = 100_000_000
	var rdc: Dictionary = CommandBus.send(&"infra.rent_facility",
			{facility_spec_id = &"facility_pod", power_supply_id = &"grid"})
	# No GPUs bought.
	var r: Dictionary = CommandBus.send(&"infra.assign_to_task",
			{dc_id = rdc.dc_id, task_id = &"t1"})
	assert_false(r.ok)
	assert_eq(r.error, &"no_gpus")
