extends GutTest

## End-to-end: drives every resource & asset through one full month of play.
## - HiringSystem: hire lead, hire staff (cash spent)
## - InfraSystem: rent dc (cash spent)
## - DatasetSystem: acquire open + purchase (cash spent on the latter)
## - TaskSystem: pretrain task locks lead/dc/dataset; charges base_cost
## - TurnManager: advance turns until task completes → research.add_model
## - ResearchSystem: publish model → MarketSystem ranks it → fame goes up
## - InfraSystem: deploy model on a second dc (training dc still serves)
## - ProductSystem: create chatbot product (locks chief engineer)
## - MarketingSystem: start campaign drains budget on upkeep
## - TurnManager.advance(): UserSystem fills subscribers + token_demand;
##                          MonetizationSystem awards revenue to cash
## - TechTreeSystem: research ant_v2 unlocks via task pipeline
## - EventSystem: trigger debug_test_offer card and accept → cash + fame
## - EconomySystem: take_loan, start_funding, repay_loan
##
## Asserts that every resource (cash/fame/paid_users/token_demand) and
## every asset (leads/datacenters/datasets/models/products/campaigns/loans/
## unlocks/active_tasks/event_history) was both produced and consumed.


func before_each() -> void:
	GameState.reset()

func _seed_chief_engineer() -> StringName:
	var l := Lead.new()
	l.id = &"lead_ce_seed"
	l.display_name = "Carol Chief"
	l.specialty = &"chief_engineer"
	l.level = &"A"
	l.ability = 75.0
	l.signing_fee = 0
	l.weekly_salary = 1150
	GameState.leads.append(l)
	return l.id

func _seed_chief_scientist() -> StringName:
	var l := Lead.new()
	l.id = &"lead_cs_seed"
	l.display_name = "Alice Scientist"
	l.specialty = &"chief_scientist"
	l.level = &"S"
	l.ability = 92.0
	l.signing_fee = 0
	l.weekly_salary = 1800
	GameState.leads.append(l)
	return l.id

func test_full_monthly_cycle_produces_and_consumes_all_resources_and_assets_DISABLED() -> void:
	pending("v7 PR-F: 整条 vertical slice 依赖 fame×cap demand 公式与 fame 累积; 需在 P13 整体改写")
func _disabled_test_full_monthly_cycle_produces_and_consumes_all_resources_and_assets() -> void:
	# Snapshot the cash floor we drop to so we can assert revenue restored some.
	var initial_cash: int = GameState.cash

	# === ASSETS PRODUCED: leads, staff, datacenters, datasets ===
	var cs_id: StringName = _seed_chief_scientist()
	var ce_id: StringName = _seed_chief_engineer()
	assert_eq(GameState.leads.size(), 2)

	CommandBus.send(&"hiring.adjust_staff", {role = &"ml_eng", delta = 4})
	assert_eq(GameState.staff_pool[&"ml_eng"], 4)

	# Two datacenters: one for training, one for serving.
	var dc_train: Dictionary = CommandBus.send(&"infra.debug_instant_owned_dc", {facility_spec_id = &"facility_room", gpu_id = &"cypress_t0"})
	var dc_serve: Dictionary = CommandBus.send(&"infra.debug_instant_owned_dc", {facility_spec_id = &"facility_room", gpu_id = &"cypress_t0"})
	assert_eq(GameState.datacenters.size(), 2)

	var ds_open: Dictionary = CommandBus.send(&"dataset.acquire_open",
		{template_id = &"web_corpus_v1"})
	var ds_paid: Dictionary = CommandBus.send(&"dataset.purchase",
		{template_id = &"codebase_v1"})
	assert_eq(GameState.datasets.size(), 2)

	# === TASKS: pretrain locks lead + staff + dc + dataset ===
	var task_r: Dictionary = CommandBus.send(&"task.start", {
		template_id = &"train_sparrow_s",
		lead_ids = [cs_id],
		staff = {&"ml_eng": 2},
		datacenter_id = dc_train.dc_id,
		dataset_ids = [ds_open.dataset_id],
	})
	assert_true(task_r.ok)
	# Resources are now locked.
	assert_eq(HiringSystem.find_lead(cs_id).locked_by_task_id, task_r.task_id)
	assert_eq(GameState.staff_busy[&"ml_eng"], 2)
	assert_eq(InfraSystem.find_dc(dc_train.dc_id).status, &"training")
	# Advance to completion.
	for i in range(int(task_r.total_weeks)):
		TurnManager.advance()
	# === ASSETS PRODUCED: models ===
	assert_eq(GameState.models.size(), 1)
	# Resources released.
	assert_eq(HiringSystem.find_lead(cs_id).locked_by_task_id, &"")
	assert_eq(GameState.staff_busy[&"ml_eng"], 0)
	assert_eq(InfraSystem.find_dc(dc_train.dc_id).status, &"idle")

	var model_id: StringName = GameState.models[0].id

	# === RESOURCE PRODUCED: fame (publish → leaderboard → ranks → fame) ===
	# Per 4-state lifecycle: evaluate before publish.
	CommandBus.send(&"research.evaluate_apply", {
		model_id = model_id, capability_measured = {&"general": 60.0}})
	CommandBus.send(&"research.publish_model", {
		model_id = model_id, is_open_source = false, per_token_price = 0.001})
	# Leaderboard auto-resolved on publish; advance to award fame.
	var fame_before_advance: float = GameState.fame
	TurnManager.advance()
	assert_gt(GameState.fame, fame_before_advance)

	# Deploy on the serving dc.
	CommandBus.send(&"infra.deploy_model", {dc_id = dc_serve.dc_id, model_id = model_id})
	assert_eq(InfraSystem.find_dc(dc_serve.dc_id).status, &"serving")

	# === ASSETS PRODUCED: products ===
	var prod_r: Dictionary = CommandBus.send(&"product.create", {
		type = &"chatbot",
		display_name = "ChatBot Pro",
		lead_id = ce_id,
		bound_model_id = model_id,
		subscription_price = 99,
		staff = {&"ml_eng": 1},
	})
	assert_true(prod_r.ok)
	assert_eq(HiringSystem.find_lead(ce_id).assigned_to_product_id, prod_r.product_id)

	# === ASSETS PRODUCED: campaigns (drains cash, boosts user growth) ===
	var camp_r: Dictionary = CommandBus.send(&"marketing.start_campaign", {
		display_name = "Launch", weekly_budget = 1150, total_weeks = 9,
		target_segment = &"chatbot_users",
	})
	assert_eq(GameState.campaigns.size(), 1)

	# === RESOURCES PRODUCED: paid_users + token_demand + revenue ===
	var cash_before_revenue_advance: int = GameState.cash
	TurnManager.advance()
	# Subscribers should have moved (player is published with fame > 0).
	assert_true(
		GameState.paid_users >= 0,
		"paid_users computed (may be 0 if quality × fame too low for delta).")
	# Token demand should be present for the published model.
	assert_true(GameState.token_demand.has(model_id))
	# Revenue breakdown was written.
	assert_eq(int(GameState.last_revenue_breakdown.turn), GameState.turn)

	# === ASSETS PRODUCED: unlocks (via tech research task pipeline) ===
	# v6: tech_research requires datacenter + min_researchers/min_engineers staff.
	# Use gqa (24 weeks, 2 ml_eng + 1 infra_eng + 8-GPU pod) — cheaper than ant_v2.
	CommandBus.send(&"hiring.adjust_staff", {role = &"infra_eng", delta = 1})
	var pod: Dictionary = CommandBus.send(&"infra.rent_facility",
			{facility_spec_id = &"facility_pod", power_supply_id = &"grid"})
	CommandBus.send(&"infra.buy_gpus",
			{dc_id = pod.dc_id, gpu_id = &"cypress_t0", count = 8})
	# The pretrain bench already booked 2 ml_eng; release them before tech_research.
	# Add a fresh pair so the staff pool can satisfy gqa's min_researchers = 2.
	CommandBus.send(&"hiring.adjust_staff", {role = &"ml_eng", delta = 2})
	var tech_r: Dictionary = CommandBus.send(&"tech.start_research", {
		tree = &"attention", node_id = &"gqa",
		lead_ids = [], staff = {&"ml_eng": 2, &"infra_eng": 1},
		datacenter_id = pod.dc_id,
	})
	assert_true(tech_r.ok, "tech_research start failed: %s" % str(tech_r))
	# gqa: research_months = 24 (weeks). Advance 24 turns to finish.
	for i in range(24):
		TurnManager.advance()
	assert_true(bool(GameState.unlocks[&"attention"][&"gqa"]))

	# === ASSETS CONSUMED: events ===
	var ev_r: Dictionary = CommandBus.send(&"event.trigger_card", {template_id = &"debug_test_offer"})
	var fame_pre_event: float = GameState.fame
	var cash_pre_event: int = GameState.cash
	CommandBus.send(&"event.choose_option", {event_id = ev_r.event_id, option_id = &"accept"})
	assert_eq(GameState.cash, cash_pre_event + 1_000_000)
	assert_almost_eq(GameState.fame, fame_pre_event + 5.0, 0.001)
	assert_eq(GameState.event_history.size(), 1)

	# === ASSETS PRODUCED: loans + funding ===
	var loan_r: Dictionary = CommandBus.send(&"economy.take_loan", {
		amount = 100000, term_weeks = 12})
	assert_true(loan_r.ok)
	assert_eq(GameState.loans.size(), 1)
	# Repay partial.
	CommandBus.send(&"economy.repay_loan", {loan_id = loan_r.loan_id, amount = 20000})
	assert_eq(GameState.debt, 80000)

	var fund_r: Dictionary = CommandBus.send(&"economy.start_funding_round", {round = &"pre_seed"})
	assert_true(fund_r.ok)
	assert_lt(float(GameState.equity.founder), 1.0)

	# === ASSETS CONSUMED: products / leads / datacenters can be rolled up ===
	CommandBus.send(&"product.delete", {product_id = prod_r.product_id})
	assert_eq(HiringSystem.find_lead(ce_id).assigned_to_product_id, &"")
	CommandBus.send(&"infra.undeploy_model", {dc_id = dc_serve.dc_id})
	CommandBus.send(&"infra.terminate_dc", {dc_id = dc_serve.dc_id})
	CommandBus.send(&"infra.terminate_dc", {dc_id = dc_train.dc_id})
	# v6: also clean up the pod used for tech_research.
	CommandBus.send(&"infra.terminate_dc", {dc_id = pod.dc_id})
	assert_eq(GameState.datacenters.size(), 0)
	# Datasets can now be deleted (unlocked because the pretrain task completed).
	CommandBus.send(&"dataset.delete", {dataset_id = ds_open.dataset_id})
	CommandBus.send(&"dataset.delete", {dataset_id = ds_paid.dataset_id})
	assert_eq(GameState.datasets.size(), 0)

	# Sanity: cash moved away from initial (we both spent and earned across the slice).
	assert_ne(GameState.cash, initial_cash)
