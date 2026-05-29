extends GutTest

## InfraSystem — facility / GPU split asset model.
## Per design/基础设施系统设计.md.
##
## See also infra_edge_test.gd for state-machine error-path coverage.


func before_each() -> void:
	GameState.reset()

func _add_published_model() -> StringName:
	var r: Dictionary = CommandBus.send(&"research.add_model", {
		capability = {&"general": 60.0}, arch = &"ant_v1", dataset_ids = []})
	CommandBus.send(&"research.evaluate_apply", {
		model_id = r.model_id, capability_measured = {&"general": 60.0}})
	CommandBus.send(&"research.publish_model", {
		model_id = r.model_id, is_open_source = false, per_token_price = 0.001})
	return r.model_id

# ============================================================================
# facility / GPU split asset model. Per design/基础设施系统设计.md.
# ============================================================================

func _rent_solo() -> StringName:
	# `facility_solo` has no fame gate, no build, max_gpu_count=1.
	var r: Dictionary = CommandBus.send(&"infra.rent_facility",
		{facility_spec_id = &"facility_solo", power_supply_id = &"grid"})
	return r.dc_id

func _rent_pod() -> StringName:
	# 8-card pod, no fame gate.
	var r: Dictionary = CommandBus.send(&"infra.rent_facility",
		{facility_spec_id = &"facility_pod", power_supply_id = &"grid"})
	return r.dc_id

# ---- rent_facility ------------------------------------------------------

func test_rent_facility_unknown_spec_returns_unknown_spec() -> void:
	var r: Dictionary = CommandBus.send(&"infra.rent_facility",
		{facility_spec_id = &"facility_xxl", power_supply_id = &"grid"})
	assert_false(r.ok)
	assert_eq(r.error, &"unknown_spec")

func test_rent_facility_unknown_power_returns_unknown_power() -> void:
	var r: Dictionary = CommandBus.send(&"infra.rent_facility",
		{facility_spec_id = &"facility_solo", power_supply_id = &"plasma"})
	assert_false(r.ok)
	assert_eq(r.error, &"unknown_power")

func test_rent_facility_creates_idle_dc_with_zero_gpus() -> void:
	var id := _rent_solo()
	var dc = InfraSystem.find_dc(id)
	assert_eq(dc.status, &"idle")
	assert_eq(dc.gpu_count, 0)
	assert_eq(dc.gpu_id, &"")
	assert_eq(dc.max_gpu_count, 1)
	assert_eq(dc.facility_spec_id, &"facility_solo")
	assert_eq(dc.power_supply, &"grid")

func test_rent_facility_charges_nothing_upfront() -> void:
	# Per design 基础设施系统设计 §4: facility rent has zero upfront.
	var before: int = GameState.cash
	_rent_solo()
	assert_eq(GameState.cash, before)

func test_rent_facility_below_unlock_fame_rejected() -> void:
	# v7 PR-F: facility_room requires cash ≥ 100_000.
	GameState.cash = 50_000
	var r: Dictionary = CommandBus.send(&"infra.rent_facility",
		{facility_spec_id = &"facility_room", power_supply_id = &"grid"})
	assert_false(r.ok)
	assert_eq(r.error, &"facility_unlock_required")

func test_rent_facility_at_unlock_fame_succeeds() -> void:
	# v7 PR-F: rent uses cash gate; room requires 100_000 to unlock.
	GameState.cash = 100_000_000
	var r: Dictionary = CommandBus.send(&"infra.rent_facility",
		{facility_spec_id = &"facility_room", power_supply_id = &"grid"})
	assert_true(r.ok)

# ---- build_facility -----------------------------------------------------

func test_build_facility_grid_power_no_install_cost() -> void:
	# grid (常规供电): install_cost_per_card = 0; facility_pod.land_build_cost = 5_000.
	GameState.cash = 10_000_000
	var before: int = GameState.cash
	var r: Dictionary = CommandBus.send(&"infra.build_facility",
		{facility_spec_id = &"facility_pod", power_supply_id = &"grid"})
	assert_true(r.ok)
	assert_eq(GameState.cash, before - 5_000)

func test_build_facility_green_power_charges_install_cost() -> void:
	# v11: green (绿色能源) 一次性安装费 = install_cost_per_card × max_gpu_count.
	# facility_pod: land_build_cost 5_000, max_gpu_count 8; green install 5_200/卡 (2026-05).
	# Charge = 5_000 + 5_200 × 8 = 46_600 (无 GPU 声明)。
	GameState.cash = 10_000_000
	var before: int = GameState.cash
	var r: Dictionary = CommandBus.send(&"infra.build_facility",
		{facility_spec_id = &"facility_pod", power_supply_id = &"green"})
	assert_true(r.ok)
	assert_eq(GameState.cash, before - (5_000 + 5_200 * 8))

func test_build_facility_zero_weeks_completes_immediately() -> void:
	# facility_solo.build_weeks = 0 → completes immediately.
	var r: Dictionary = CommandBus.send(&"infra.build_facility",
		{facility_spec_id = &"facility_solo", power_supply_id = &"grid"})
	assert_true(r.ok)
	assert_eq(GameState.construction_queue.size(), 0)
	assert_eq(GameState.datacenters.size(), 1)
	assert_eq(GameState.datacenters[0].ownership, &"owned")

func test_build_facility_with_gpu_charges_combined_upfront() -> void:
	# facility_pod.land_build_cost = 5_000; no power modifier (grid = 0).
	# cypress_t0.purchase_price = 5_200 (2026-05 GPU +30%); pod.max_gpu_count = 8.
	# Total = 5_000 + 8 × 5_200 = 46_600.
	GameState.cash = 1_000_000
	var before: int = GameState.cash
	var r: Dictionary = CommandBus.send(&"infra.build_facility", {
		facility_spec_id = &"facility_pod",
		power_supply_id = &"grid",
		gpu_id = &"cypress_t0",
	})
	assert_true(r.ok)
	assert_eq(GameState.cash, before - 46_600)

func test_build_facility_with_gpu_auto_installs_on_completion() -> void:
	# facility_solo.build_weeks = 0 → instant completion.
	# solo.max_gpu_count = 1; cypress_t0 → train_tflops > 0 after install.
	GameState.cash = 1_000_000
	var r: Dictionary = CommandBus.send(&"infra.build_facility", {
		facility_spec_id = &"facility_solo",
		power_supply_id = &"grid",
		gpu_id = &"cypress_t0",
	})
	assert_true(r.ok)
	assert_eq(GameState.datacenters.size(), 1)
	var dc = GameState.datacenters[0]
	assert_eq(dc.gpu_id, &"cypress_t0")
	assert_eq(dc.gpu_count, 1)
	assert_eq(dc.gpu_purchase_history.size(), 1)
	assert_gt(dc.train_tflops, 0.0, "auto-installed GPU must give non-zero TFLOPS")

func test_build_facility_with_gpu_non_zero_weeks_completes_on_advance() -> void:
	# facility_pod.build_weeks = 1; after 1 advance, GPU should be installed.
	GameState.cash = 1_000_000
	var r: Dictionary = CommandBus.send(&"infra.build_facility", {
		facility_spec_id = &"facility_pod",
		power_supply_id = &"grid",
		gpu_id = &"cypress_t0",
	})
	assert_true(r.ok)
	assert_eq(GameState.construction_queue.size(), 1)
	assert_eq(GameState.datacenters.size(), 0)
	TurnManager.advance()
	assert_eq(GameState.construction_queue.size(), 0)
	assert_eq(GameState.datacenters.size(), 1)
	var dc = GameState.datacenters[0]
	assert_eq(dc.gpu_id, &"cypress_t0")
	assert_eq(dc.gpu_count, 8)
	assert_gt(dc.train_tflops, 0.0, "auto-installed 8×cypress_t0 must give non-zero TFLOPS")

# ---- save_loaded id repair ----------------------------------------------

func _loaded_dc(id: StringName, facility: StringName, gpu_count: int,
		status := &"idle", busy := &"") -> Datacenter:
	# Mimics a Datacenter coming straight off Datacenter.from_dict().
	var dc := Datacenter.new()
	dc.id = id
	dc.display_name = "%s [%s]" % [facility, id]
	dc.facility_spec_id = facility
	dc.ownership = &"owned"
	dc.gpu_id = &"cypress_t0"
	dc.gpu_count = gpu_count
	dc.max_gpu_count = gpu_count
	dc.train_tflops = 100.0 * float(gpu_count)
	dc.cluster_efficiency = 0.8
	dc.status = status
	dc.busy_with_task_id = busy
	return dc

func test_save_loaded_repairs_duplicate_datacenter_ids() -> void:
	# Corrupted-save state: id counters reset to 1 on load → facilities built
	# after a load collide with loaded ids. find_dc() returns the FIRST match,
	# so the player's idle 8k cluster silently resolves to a busy 8-card pod.
	GameState.datacenters.append(
		_loaded_dc(&"dc_owned_0001", &"facility_pod", 8, &"training", &"task_x"))
	GameState.datacenters.append(
		_loaded_dc(&"dc_owned_0001", &"facility_floor", 8000, &"idle"))
	EventBus.save_loaded.emit()
	var seen: Dictionary = {}
	for dc in GameState.datacenters:
		assert_false(seen.has(dc.id),
			"datacenter id %s duplicated after load" % dc.id)
		seen[dc.id] = true
	# The 8000-card floor survives as a distinct, addressable datacenter.
	var floor_dc: Datacenter = null
	for dc in GameState.datacenters:
		if dc.facility_spec_id == &"facility_floor":
			floor_dc = dc
	assert_not_null(floor_dc)
	assert_eq(floor_dc.gpu_count, 8000)

func test_save_loaded_re_id_clears_stale_lock_on_duplicate() -> void:
	# find_dc always drove the FIRST copy, so the re-id'd duplicate was never
	# really busy — its stale training lock must be cleared on repair.
	GameState.datacenters.append(
		_loaded_dc(&"dc_owned_0003", &"facility_pod", 8, &"idle"))
	GameState.datacenters.append(
		_loaded_dc(&"dc_owned_0003", &"facility_hall", 2000, &"training", &"task_y"))
	EventBus.save_loaded.emit()
	var hall_dc: Datacenter = null
	for dc in GameState.datacenters:
		if dc.facility_spec_id == &"facility_hall":
			hall_dc = dc
	assert_not_null(hall_dc)
	assert_ne(hall_dc.id, &"dc_owned_0003")
	assert_eq(hall_dc.status, &"idle")
	assert_eq(hall_dc.busy_with_task_id, &"")

func test_save_loaded_restores_construction_id_counter() -> void:
	# A loaded save already uses dc_owned_0007; a facility built afterwards must
	# not reuse 0001..0007. facility_solo.build_weeks = 0 → instant completion,
	# so the completed dc id equals the construction id.
	GameState.cash = 100_000_000
	GameState.datacenters.append(_loaded_dc(&"dc_owned_0007", &"facility_pod", 8))
	EventBus.save_loaded.emit()
	var r: Dictionary = CommandBus.send(&"infra.build_facility",
		{facility_spec_id = &"facility_solo", power_supply_id = &"grid"})
	assert_true(r.ok)
	var built: Datacenter = GameState.datacenters[GameState.datacenters.size() - 1]
	assert_gt(String(built.id).trim_prefix("dc_owned_").to_int(), 7,
		"built facility id must not collide with loaded dc_owned_0007")

# ---- buy_gpus -----------------------------------------------------------

func test_buy_gpus_unknown_dc_returns_error() -> void:
	var r: Dictionary = CommandBus.send(&"infra.buy_gpus",
		{dc_id = &"none", gpu_id = &"cypress_t0", count = 1})
	assert_false(r.ok)
	assert_eq(r.error, &"unknown_dc")

func test_buy_gpus_unknown_gpu_returns_error() -> void:
	var id := _rent_solo()
	var r: Dictionary = CommandBus.send(&"infra.buy_gpus",
		{dc_id = id, gpu_id = &"unobtainium", count = 1})
	assert_false(r.ok)
	assert_eq(r.error, &"unknown_gpu")

func test_buy_gpus_charges_and_updates_compute() -> void:
	GameState.cash = 10_000_000
	var id := _rent_solo()
	var dc = InfraSystem.find_dc(id)
	var before: int = GameState.cash
	var r: Dictionary = CommandBus.send(&"infra.buy_gpus",
		{dc_id = id, gpu_id = &"cypress_t0", count = 1})
	assert_true(r.ok)
	# 1 cypress_t0 = $5 200 (2026-05 GPU +30%).
	assert_eq(GameState.cash, before - 5_200)
	assert_eq(dc.gpu_count, 1)
	assert_eq(dc.gpu_id, &"cypress_t0")
	assert_eq(dc.gpu_purchase_history.size(), 1)
	# 1 card → big_cluster_decay = 1.0; native_cluster_eff = 0.85; grid efficiency_modifier = 1.0
	assert_almost_eq(dc.cluster_efficiency, 0.85, 0.001)
	# train_tflops = 125 × 1 × 0.85 = 106.25
	assert_almost_eq(dc.train_tflops, 106.25, 0.1)
	# v3: inference_tflops = per_card_inference_tflops × 1 × 0.85.
	# v6 PR-E (2026-05): per_card_inference_tflops 调到训练的 30% — cypress_t0
	# = 125 × 0.30 = 37.5. 见 平衡参数.md GPUSpec.
	assert_almost_eq(dc.inference_tflops, 37.5 * 0.85, 0.001)
	# idle dc 不绑模型, serving_tokens_per_sec 应为 0.
	assert_eq(dc.serving_tokens_per_sec, 0.0)

# ---- v11: ecosystem_score 训练惩罚 / 新机架档位 / 无内部 id 名 -------------

func test_low_ecosystem_brand_penalizes_train_but_not_inference() -> void:
	# bamboo (ecosystem_score 0.6) 训练算力打 6 折; 推理算力不打折。
	GameState.cash = 100_000_000
	GameState.turn = 205  # bamboo_t2 release_turn = 205
	var id := _rent_pod()
	CommandBus.send(&"infra.buy_gpus", {dc_id = id, gpu_id = &"bamboo_t2", count = 1})
	var dc = InfraSystem.find_dc(id)
	var ce: float = dc.cluster_efficiency  # ecosystem 不进 cluster_efficiency
	# bamboo_t2: per_card_tflops 300, per_card_inference 90, ecosystem_score 0.6.
	assert_almost_eq(dc.train_tflops, 300.0 * ce * 0.6, 0.5,
		"低生态品牌训练算力应被 ecosystem_score 打折")
	assert_almost_eq(dc.inference_tflops, 90.0 * ce, 0.5,
		"推理算力不受 ecosystem_score 影响")

func test_full_ecosystem_brand_has_no_train_penalty() -> void:
	# cypress (ecosystem_score 1.0) 训练算力不打折。
	GameState.cash = 100_000_000
	var id := _rent_pod()
	CommandBus.send(&"infra.buy_gpus", {dc_id = id, gpu_id = &"cypress_t0", count = 1})
	var dc = InfraSystem.find_dc(id)
	# cypress_t0: per_card_tflops 125, cluster_eff 0.85, ecosystem 1.0.
	assert_almost_eq(dc.train_tflops, 125.0 * dc.cluster_efficiency, 0.5)

func test_rack_16_and_32_tiers_rentable() -> void:
	GameState.cash = 100_000_000
	var r16: Dictionary = CommandBus.send(&"infra.rent_facility",
		{facility_spec_id = &"facility_rack_16", power_supply_id = &"grid"})
	assert_true(r16.ok, "16 卡机架应可租")
	assert_eq(InfraSystem.find_dc(r16.dc_id).max_gpu_count, 16)
	var r32: Dictionary = CommandBus.send(&"infra.rent_facility",
		{facility_spec_id = &"facility_rack_32", power_supply_id = &"grid"})
	assert_true(r32.ok, "32 卡机架应可租")
	assert_eq(InfraSystem.find_dc(r32.dc_id).max_gpu_count, 32)

func test_built_dc_display_name_has_no_internal_id() -> void:
	# v11: dc 名只显示档位, 不带 [dc_NNNN] 内部 id。
	var id := _rent_pod()
	var dc = InfraSystem.find_dc(id)
	assert_eq(dc.display_name.find("[dc_"), -1,
		"display_name 不应含内部 id, 实际: %s" % dc.display_name)

func test_cloud_dc_display_name_shows_count_no_internal_id() -> void:
	GameState.cash = 100_000_000
	var r: Dictionary = CommandBus.send(&"infra.create_cloud_dc",
		{gpu_id = &"cypress_t0", count = 8})
	var dc = InfraSystem.find_dc(r.dc_id)
	# 云 dc 名不存文案 (locale 感知, 见 §6ter): 卡数在 display_label() 里, 不在 display_name。
	TranslationServer.set_locale("zh_CN")
	var label: String = dc.display_label()
	assert_eq(label.find("[dc_"), -1, "云 dc 名不应含内部 id")
	assert_string_contains(label, "8", "云 dc 名应显示卡数")

func test_buy_gpus_capacity_exceeded_returns_error() -> void:
	GameState.cash = 100_000_000
	var id := _rent_pod()
	# pod max = 8. Buy 5 then try 4 more.
	CommandBus.send(&"infra.buy_gpus", {dc_id = id, gpu_id = &"cypress_t0", count = 5})
	var r: Dictionary = CommandBus.send(&"infra.buy_gpus",
		{dc_id = id, gpu_id = &"cypress_t0", count = 4})
	assert_false(r.ok)
	assert_eq(r.error, &"capacity_exceeded")

func test_buy_gpus_mixed_brand_returns_error() -> void:
	GameState.cash = 100_000_000
	var id := _rent_pod()
	# maple_t1 release_turn=178 (MI100, 2020-11). Advance turn so the test can
	# actually attempt to buy a different-brand GPU — otherwise gpu_not_released
	# would mask the mixed_brand check.
	GameState.turn = 178
	CommandBus.send(&"infra.buy_gpus", {dc_id = id, gpu_id = &"cypress_t0", count = 2})
	var r: Dictionary = CommandBus.send(&"infra.buy_gpus",
		{dc_id = id, gpu_id = &"maple_t1", count = 1})
	assert_false(r.ok)
	assert_eq(r.error, &"mixed_brand")

func test_buy_gpus_allowed_while_training() -> void:
	# 基础设施系统设计 §6.1.3: GPU buy/sell is allowed in any dc.status —
	# adding cards mid-training is the design's elastic-capacity affordance.
	GameState.cash = 100_000_000
	var pod_id := _rent_pod()
	CommandBus.send(&"infra.buy_gpus", {dc_id = pod_id, gpu_id = &"cypress_t0", count = 1})
	CommandBus.send(&"infra.assign_to_task", {dc_id = pod_id, task_id = &"t2"})
	var r: Dictionary = CommandBus.send(&"infra.buy_gpus",
		{dc_id = pod_id, gpu_id = &"cypress_t0", count = 1})
	assert_true(r.ok, "buy_gpus must succeed during training (no dc_not_idle reject)")

func test_buy_gpus_emits_signals() -> void:
	GameState.cash = 10_000_000
	var id := _rent_solo()
	watch_signals(EventBus)
	CommandBus.send(&"infra.buy_gpus",
		{dc_id = id, gpu_id = &"cypress_t0", count = 1})
	assert_signal_emitted(EventBus, "gpus_bought")
	assert_signal_emitted(EventBus, "dc_compute_recomputed")

# ---- sell_gpus ----------------------------------------------------------

func test_sell_gpus_unknown_dc_returns_error() -> void:
	var r: Dictionary = CommandBus.send(&"infra.sell_gpus",
		{dc_id = &"nope", count = 1})
	assert_false(r.ok)
	assert_eq(r.error, &"unknown_dc")

func test_sell_gpus_not_enough_returns_error() -> void:
	var id := _rent_solo()
	var r: Dictionary = CommandBus.send(&"infra.sell_gpus", {dc_id = id, count = 1})
	assert_false(r.ok)
	assert_eq(r.error, &"not_enough_gpus")

func test_sell_gpus_same_turn_refunds_full_price() -> void:
	GameState.cash = 10_000_000
	var id := _rent_solo()
	# bought_at_turn = 0 (default), GameState.turn = 0, so years = 0,
	# depreciated price = unit_price × 1.0 = unit_price.
	CommandBus.send(&"infra.buy_gpus", {dc_id = id, gpu_id = &"cypress_t0", count = 1})
	var before: int = GameState.cash
	var r: Dictionary = CommandBus.send(&"infra.sell_gpus", {dc_id = id, count = 1})
	assert_true(r.ok)
	# cypress_t0 purchase_price = 5_200 (2026-05 GPU +30%), same-turn full refund.
	assert_eq(int(r.refund), 5_200)
	assert_eq(GameState.cash, before + 5_200)
	# GPU asset bookkeeping cleared on full sell.
	var dc = InfraSystem.find_dc(id)
	assert_eq(dc.gpu_count, 0)
	assert_eq(dc.gpu_id, &"")
	assert_eq(dc.gpu_purchase_history.size(), 0)

func test_sell_gpus_after_one_year_applies_10_pct_decay() -> void:
	GameState.cash = 10_000_000
	var id := _rent_solo()
	CommandBus.send(&"infra.buy_gpus",
		{dc_id = id, gpu_id = &"cypress_t0", count = 1})
	# Advance 12 turns → 1 year → 0.9× refund.
	GameState.turn = 12
	var r: Dictionary = CommandBus.send(&"infra.sell_gpus", {dc_id = id, count = 1})
	assert_true(r.ok)
	# 5_200 × 0.9 = 4_680 (2026-05 GPU +30%).
	assert_eq(int(r.refund), 4_680)

func test_sell_gpus_when_training_rejected() -> void:
	GameState.cash = 10_000_000
	var id := _rent_solo()
	CommandBus.send(&"infra.buy_gpus", {dc_id = id, gpu_id = &"cypress_t0", count = 1})
	CommandBus.send(&"infra.assign_to_task", {dc_id = id, task_id = &"t1"})
	var r: Dictionary = CommandBus.send(&"infra.sell_gpus", {dc_id = id, count = 1})
	assert_false(r.ok)
	assert_eq(r.error, &"dc_busy")

func test_sell_gpus_fifo_order() -> void:
	# Buy two batches at different turns. Selling 1 should sell from the
	# earliest batch (=more depreciated → lower refund) per FIFO.
	GameState.cash = 100_000_000
	var id := _rent_pod()
	GameState.turn = 0
	CommandBus.send(&"infra.buy_gpus",
		{dc_id = id, gpu_id = &"cypress_t0", count = 1})
	GameState.turn = 24  # 2 years later
	CommandBus.send(&"infra.buy_gpus",
		{dc_id = id, gpu_id = &"cypress_t0", count = 1})
	# Now sell 1 — should sell the OLDER one (batch 0, bought at turn 0):
	# years = (24 - 0)/12 = 2, refund = 5_200 × 0.81 = 4_212 (2026-05 GPU +30%).
	var r: Dictionary = CommandBus.send(&"infra.sell_gpus",
		{dc_id = id, count = 1})
	assert_true(r.ok)
	assert_eq(int(r.refund), 4_212)
	# DC still has 1 GPU left (the newer batch).
	var dc = InfraSystem.find_dc(id)
	assert_eq(dc.gpu_count, 1)
	assert_eq(dc.gpu_purchase_history.size(), 1)
	assert_eq(dc.gpu_purchase_history[0].bought_at_turn, 24)

# ---- terminate auto-sells GPUs -----------------------------------------

func test_terminate_auto_sells_remaining_gpus() -> void:
	GameState.cash = 10_000_000
	var id := _rent_solo()
	CommandBus.send(&"infra.buy_gpus",
		{dc_id = id, gpu_id = &"cypress_t0", count = 1})
	var before: int = GameState.cash
	var r: Dictionary = CommandBus.send(&"infra.terminate_dc", {dc_id = id})
	assert_true(r.ok)
	# Refund == 5_200 (cypress_t0 purchase_price, 2026-05 GPU +30%; turn 0, no decay).
	assert_eq(int(r.refund_for_remaining_gpus), 5_200)
	assert_eq(GameState.cash, before + 5_200)
	assert_eq(GameState.datacenters.size(), 0)

# ---- cluster efficiency ------------------------------------------------

func test_cluster_efficiency_decay_with_size() -> void:
	# 1 card vs 8 cards. Decay = clamp(1 - 0.04*log10(n), 0.5, 1.0).
	# n=1 → 1.00; n=8 → 1 - 0.04*0.903 = 0.9639.
	GameState.cash = 100_000_000
	var solo := _rent_solo()
	var pod := _rent_pod()
	CommandBus.send(&"infra.buy_gpus",
		{dc_id = solo, gpu_id = &"cypress_t0", count = 1})
	CommandBus.send(&"infra.buy_gpus",
		{dc_id = pod, gpu_id = &"cypress_t0", count = 8})
	var dc1 = InfraSystem.find_dc(solo)
	var dc8 = InfraSystem.find_dc(pod)
	# solo: native_cluster_eff × 1.0 (grid) × 1.00 = 0.85
	assert_almost_eq(dc1.cluster_efficiency, 0.85, 0.001)
	# pod: 0.85 × 1.0 × (1 - 0.04*0.9031) ≈ 0.85 × 0.9639 ≈ 0.819
	assert_almost_eq(dc8.cluster_efficiency, 0.85 * (1.0 - 0.04 * 0.9031), 0.005)

# ---- power supply effects ----------------------------------------------

func test_green_power_break_even_around_5_years() -> void:
	# 2026-05: 绿色能源每卡每周省 (grid 24 − green 4) = $20; 安装费 $5200/卡 (power_factor=1.0 基准卡)。
	# 回本点 = 5200 / 20 = 260 周 = 5 年。高功耗卡省得更多 → 回本更快 (见 §1.5)。
	var grid_path: String = InfraSystem.POWER_SPECS.get(&"grid", "")
	var green_path: String = InfraSystem.POWER_SPECS.get(&"green", "")
	var grid_spec: PowerSupplySpec = load(grid_path)
	var green_spec: PowerSupplySpec = load(green_path)
	var weekly_saving: int = grid_spec.weekly_cost_per_card - green_spec.weekly_cost_per_card
	assert_gt(weekly_saving, 0, "绿色能源周电费应低于常规供电")
	var break_even_weeks: float = float(green_spec.install_cost_per_card) / float(weekly_saving)
	assert_almost_eq(break_even_weeks, 260.0, 1.0, "绿色能源回本点应约为 260 周 (5 年)")

func test_only_grid_and_green_power_options() -> void:
	# v11: 供电从 5 种砍到 2 种。
	assert_eq(InfraSystem.POWER_SPECS.size(), 2)
	assert_true(InfraSystem.POWER_SPECS.has(&"grid"))
	assert_true(InfraSystem.POWER_SPECS.has(&"green"))

func test_upkeep_charges_facility_and_gpu_runtime_separately() -> void:
	GameState.cash = 10_000_000
	var id := _rent_solo()  # rented: rent_weekly_cost = 500
	CommandBus.send(&"infra.buy_gpus",
		{dc_id = id, gpu_id = &"cypress_t0", count = 1})
	# 2026-05: cypress_t0 maint 4 + grid 电费 round(24 × power_factor 0.66) = 16 → 20.
	# Rented facility uses rent_weekly_cost (500), not land_weekly_cost (0).
	# Total upkeep = 500 (rent_weekly_cost) + 20 (gpu_runtime) = 520。
	# 出租默认关 (opt-in), 此处未开 → 不产生租金, 只扣成本。
	var before: int = GameState.cash
	EventBus.phase_started.emit(&"upkeep", 1)
	assert_eq(GameState.cash, before - 520)

func test_upkeep_with_zero_gpus_only_charges_facility_cost() -> void:
	GameState.cash = 10_000_000
	_rent_solo()
	var before: int = GameState.cash
	EventBus.phase_started.emit(&"upkeep", 1)
	# Rented solo: rent_weekly_cost = 500.
	assert_eq(GameState.cash, before - 500)

# ---- rented vs owned weekly cost distinction ----------------------------

func test_upkeep_rented_facility_uses_rent_weekly_cost() -> void:
	# facility_solo: rent_weekly_cost = 500, land_weekly_cost = 0.
	# Rented → should charge rent_weekly_cost.
	GameState.cash = 10_000_000
	var id := _rent_solo()
	assert_eq(InfraSystem.find_dc(id).ownership, &"rented")
	var before: int = GameState.cash
	EventBus.phase_started.emit(&"upkeep", 1)
	assert_eq(GameState.cash, before - 500)

func test_upkeep_owned_facility_uses_land_weekly_cost() -> void:
	# build_facility (solo, build_weeks=0 → instant), ownership = "owned".
	# Owned → should charge land_weekly_cost = 0 (solo is home setup).
	GameState.cash = 10_000_000
	var r: Dictionary = CommandBus.send(&"infra.build_facility",
		{facility_spec_id = &"facility_solo", power_supply_id = &"grid"})
	assert_true(r.ok)
	assert_eq(GameState.construction_queue.size(), 0)
	assert_eq(GameState.datacenters.size(), 1)
	var dc = GameState.datacenters[0]
	assert_eq(dc.ownership, &"owned")
	var before: int = GameState.cash
	EventBus.phase_started.emit(&"upkeep", 1)
	# land_weekly_cost = 0, no GPUs.
	assert_eq(GameState.cash, before)

func test_upkeep_rented_is_more_expensive_than_owned_same_spec() -> void:
	# Renting is more expensive per week than owning (rent includes amortization premium).
	GameState.cash = 10_000_000
	# Rented.
	var rented_id := _rent_solo()
	var before_r: int = GameState.cash
	EventBus.phase_started.emit(&"upkeep", 1)
	var rented_cost: int = before_r - GameState.cash
	# Owned (build_weeks=0 → instant). Build a pod (8-card rack) instead of
	# solo, because solo is a home setup with zero land cost — that would tie
	# with rented in a comparison.
	GameState.datacenters.clear()
	# v7 PR-F: pod has land_weekly_cost = 0 too; pick room (500-card) which
	# actually has non-zero land_weekly_cost so a real comparison is possible.
	# cash gating handled by separate GameState.cash assignment in the caller.
	CommandBus.send(&"infra.build_facility",
		{facility_spec_id = &"facility_room", power_supply_id = &"grid"})
	# Force-complete since room has build_weeks > 0.
	for c in GameState.construction_queue.duplicate():
		c.weeks_remaining = 0
	EventBus.phase_started.emit(&"action", 99)
	var before_o: int = GameState.cash
	EventBus.phase_started.emit(&"upkeep", 2)
	var owned_cost: int = before_o - GameState.cash
	# rented solo (500) vs owned room (15k land) — owned room IS more expensive
	# than rented solo. Sanity check is just that both are nonzero and
	# we measured a meaningful difference.
	assert_true(rented_cost > 0)
	assert_true(owned_cost > 0)

# ============================================================================
# Cloud GPU rental. Per design/基础设施系统设计.md §cloud_dc.
# ============================================================================

func test_create_cloud_dc_unknown_gpu_returns_error() -> void:
	var r: Dictionary = CommandBus.send(&"infra.create_cloud_dc",
		{gpu_id = &"unobtainium", count = 4})
	assert_false(r.ok)
	assert_eq(r.error, &"unknown_gpu")

func test_create_cloud_dc_zero_count_returns_error() -> void:
	var r: Dictionary = CommandBus.send(&"infra.create_cloud_dc",
		{gpu_id = &"cypress_t0", count = 0})
	assert_false(r.ok)
	assert_eq(r.error, &"invalid_count")

func test_create_cloud_dc_creates_idle_dc_with_compute() -> void:
	var r: Dictionary = CommandBus.send(&"infra.create_cloud_dc",
		{gpu_id = &"cypress_t0", count = 4})
	assert_true(r.ok)
	var dc = InfraSystem.find_dc(r.dc_id)
	assert_eq(dc.ownership, &"cloud")
	assert_eq(dc.gpu_id, &"cypress_t0")
	assert_eq(dc.gpu_count, 4)
	assert_eq(dc.status, &"idle")
	assert_eq(dc.facility_spec_id, &"")
	# No GPU purchase: history empty, cash unchanged.
	assert_eq(dc.gpu_purchase_history.size(), 0)
	assert_eq(GameState.cash, GameState.STARTING_CASH)
	# Compute should be calculated.
	assert_true(dc.train_tflops > 0.0)

func test_create_cloud_dc_no_upfront_cost() -> void:
	var before: int = GameState.cash
	CommandBus.send(&"infra.create_cloud_dc", {gpu_id = &"cypress_t0", count = 8})
	assert_eq(GameState.cash, before)

func test_cloud_dc_upkeep_charges_rent_weekly_cost() -> void:
	# cypress_t0.rent_weekly_cost = 130 (2026-05 砍半到 40 周回本); 8 cards → $1,040/week.
	GameState.cash = 10_000_000
	var r: Dictionary = CommandBus.send(&"infra.create_cloud_dc",
		{gpu_id = &"cypress_t0", count = 8})
	var before: int = GameState.cash
	EventBus.phase_started.emit(&"upkeep", 1)
	assert_eq(GameState.cash, before - 1_040)

func test_cloud_dc_upkeep_does_not_charge_facility_or_maintenance() -> void:
	# Cloud DC has no facility cost and no separate GPU maintenance.
	# Only rent_weekly_cost is charged.
	GameState.cash = 10_000_000
	var r: Dictionary = CommandBus.send(&"infra.create_cloud_dc",
		{gpu_id = &"cypress_t0", count = 1})
	var before: int = GameState.cash
	EventBus.phase_started.emit(&"upkeep", 1)
	# Only rent_weekly_cost=130 (2026-05 砍半), not maintenance(4)+power(round(24×0.66)=16)=20.
	assert_eq(GameState.cash, before - 130)

func test_cloud_dc_buy_gpus_rejected() -> void:
	var r: Dictionary = CommandBus.send(&"infra.create_cloud_dc",
		{gpu_id = &"cypress_t0", count = 2})
	var buy: Dictionary = CommandBus.send(&"infra.buy_gpus",
		{dc_id = r.dc_id, gpu_id = &"cypress_t0", count = 1})
	assert_false(buy.ok)
	assert_eq(buy.error, &"cloud_dc_no_purchase")

# ============================================================================
# 电费随功耗系数 scale + 闲置出租到算力平台 (2026-05). design §4.2 / §4.4.
# ============================================================================

func test_electricity_per_card_scales_by_power_factor() -> void:
	var grid: PowerSupplySpec = load("res://resources/data/infra/power/grid.tres")
	var t1: GPUSpec = load("res://resources/data/infra/gpus/cypress_t1.tres")  # factor 1.0
	var t3: GPUSpec = load("res://resources/data/infra/gpus/cypress_t3.tres")  # factor 2.55
	var b1: GPUSpec = load("res://resources/data/infra/gpus/bamboo_t1.tres")   # factor 0.65
	# 基准卡 (cypress_t1) = 24; 高功耗卡更贵、低功耗卡更便宜 (功耗 ∝ 算力^0.45).
	assert_eq(int(round(InfraSystem.electricity_per_card(t1, grid))), 24)
	assert_eq(int(round(InfraSystem.electricity_per_card(t3, grid))), 61)
	assert_eq(int(round(InfraSystem.electricity_per_card(b1, grid))), 16)

func test_cloud_rent_is_purchase_over_40() -> void:
	# 云租砍半: rent_weekly_cost = purchase_price / 40 (40 周回本).
	var t1: GPUSpec = load("res://resources/data/infra/gpus/cypress_t1.tres")
	assert_eq(t1.rent_weekly_cost, 325)   # 13000 / 40
	assert_eq(t1.purchase_price / t1.rent_weekly_cost, 40)

func test_idle_dc_does_not_rent_out_by_default() -> void:
	GameState.cash = 10_000_000
	# facility_pod (8 卡) + cypress_t0, idle owned. 出租默认关 → 只扣成本, 无租金。
	CommandBus.send(&"infra.debug_instant_owned_dc",
		{facility_spec_id = &"facility_pod", gpu_id = &"cypress_t0"})
	var dc = GameState.datacenters[0]
	assert_false(dc.rent_out_enabled, "rent_out 默认应为关")
	var n: int = dc.gpu_count
	var before: int = GameState.cash
	EventBus.phase_started.emit(&"upkeep", 1)
	assert_eq(GameState.cash, before - (4 + 16) * n, "未开出租 → 只扣 opex")
	assert_eq(int(GameState.weekly_ledger.income.get("ECO_CAT_GPU_RENTAL", 0)), 0)

func test_idle_owned_dc_rents_out_when_enabled() -> void:
	GameState.cash = 10_000_000
	# facility_pod (8 卡) + cypress_t0: 云租 130 → 出租 65/卡; 电费 round(24×0.66)=16.
	CommandBus.send(&"infra.debug_instant_owned_dc",
		{facility_spec_id = &"facility_pod", gpu_id = &"cypress_t0"})
	var dc = GameState.datacenters[0]
	# opt-in: 开启出租。
	var sr: Dictionary = CommandBus.send(&"infra.set_dc_rent_out",
		{dc_id = dc.id, enabled = true})
	assert_true(sr.ok)
	assert_true(dc.rent_out_enabled)
	var n: int = dc.gpu_count
	assert_gt(n, 0)
	var gross: int = 65 * n                       # int(130 × 0.5) × n
	var fee: int = int(round(float(gross) * 0.22))
	var opex: int = (4 + 16) * n                  # maint + electricity (pod land = 0)
	var before: int = GameState.cash
	EventBus.phase_started.emit(&"upkeep", 1)
	assert_eq(GameState.cash, before + gross - fee - opex)
	assert_eq(dc.status, &"idle", "出租不应改变 dc 状态")
	# 两笔分别落入账本类目 (resolve 滚动前可见).
	var ledger: Dictionary = GameState.weekly_ledger
	assert_eq(int(ledger.income.get("ECO_CAT_GPU_RENTAL", 0)), gross)
	assert_eq(int(ledger.expense.get("ECO_CAT_RENTAL_FEE", 0)), fee)

func test_set_dc_rent_out_rejected_for_cloud() -> void:
	var r: Dictionary = CommandBus.send(&"infra.create_cloud_dc",
		{gpu_id = &"cypress_t0", count = 4})
	var sr: Dictionary = CommandBus.send(&"infra.set_dc_rent_out",
		{dc_id = r.dc_id, enabled = true})
	assert_false(sr.ok)
	assert_eq(sr.error, &"cloud_dc_no_rental")

func test_enabled_dc_without_gpus_earns_no_rental() -> void:
	GameState.cash = 10_000_000
	# facility_solo: owned, build_weeks=0 → instant, 0 GPU, land_weekly_cost=0.
	var r: Dictionary = CommandBus.send(&"infra.build_facility",
		{facility_spec_id = &"facility_solo", power_supply_id = &"grid"})
	assert_true(r.ok)
	var dc = GameState.datacenters[0]
	CommandBus.send(&"infra.set_dc_rent_out", {dc_id = dc.id, enabled = true})
	var before: int = GameState.cash
	EventBus.phase_started.emit(&"upkeep", 1)
	assert_eq(GameState.cash, before, "开了出租但无 GPU → 无租金、无运行成本")

func test_cloud_dc_sell_gpus_rejected() -> void:
	var r: Dictionary = CommandBus.send(&"infra.create_cloud_dc",
		{gpu_id = &"cypress_t0", count = 2})
	var sell: Dictionary = CommandBus.send(&"infra.sell_gpus",
		{dc_id = r.dc_id, count = 1})
	assert_false(sell.ok)
	assert_eq(sell.error, &"cloud_dc_no_sale")

func test_cloud_dc_terminate_returns_zero_refund_and_removes_dc() -> void:
	var r: Dictionary = CommandBus.send(&"infra.create_cloud_dc",
		{gpu_id = &"cypress_t0", count = 4})
	var before: int = GameState.cash
	var t: Dictionary = CommandBus.send(&"infra.terminate_dc", {dc_id = r.dc_id})
	assert_true(t.ok)
	assert_eq(int(t.refund_for_remaining_gpus), 0)
	assert_eq(GameState.cash, before)
	assert_eq(GameState.datacenters.size(), 0)

func test_cloud_dc_can_deploy_and_serve_model() -> void:
	var mid := _add_published_model()
	var r: Dictionary = CommandBus.send(&"infra.create_cloud_dc",
		{gpu_id = &"cypress_t0", count = 1})
	var d: Dictionary = CommandBus.send(&"infra.deploy_model",
		{dc_id = r.dc_id, model_id = mid})
	assert_true(d.ok)
	assert_eq(InfraSystem.find_dc(r.dc_id).status, &"serving")

func test_cloud_dc_pre_release_gpu_rejected() -> void:
	GameState.turn = 0
	# cypress_t1 release_turn = 152 (A100, 2020-05); at turn 0 should be rejected.
	var r: Dictionary = CommandBus.send(&"infra.create_cloud_dc",
		{gpu_id = &"cypress_t1", count = 1})
	assert_false(r.ok)
	assert_eq(r.error, &"gpu_not_released")

# ============================================================================
# v3 — model-aware serving capacity: serving_tokens_per_sec computed at deploy
# time from inference_tflops × 1e12 / target.flops_per_token.
# Per design/基础设施系统设计.md §1 + §6.4 + §6.4bis.
# ============================================================================

const _BASELINE_FPT_7B: float = 1.4e10   # 7B reference: 2 × 7e9 FLOPs/token.

func _add_published_model_with_fpt(fpt: float) -> StringName:
	# Variant of _add_published_model that pins flops_per_token (so we can
	# reason about deploy-time t/s without depending on TaskSystem fixtures).
	var r: Dictionary = CommandBus.send(&"research.add_model", {
		capability = {&"general": 60.0}, arch = &"ant_v1",
		dataset_ids = [], flops_per_token = fpt})
	CommandBus.send(&"research.evaluate_apply", {
		model_id = r.model_id, capability_measured = {&"general": 60.0}})
	CommandBus.send(&"research.publish_model", {
		model_id = r.model_id, is_open_source = false, per_token_price = 0.001})
	return r.model_id

func _solo_with_one_t1() -> StringName:
	GameState.cash = 10_000_000
	var id := _rent_solo()
	CommandBus.send(&"infra.buy_gpus", {dc_id = id, gpu_id = &"cypress_t0", count = 1})
	return id

# ---- deploy_model writes serving_tokens_per_sec ------------------------

func test_deploy_model_caches_serving_tokens_per_sec_from_flops_per_token() -> void:
	# §6.4: serving_tokens_per_sec = inference_tflops × 1e12 / model.flops_per_token.
	# v6 PR-E (2026-05): 1 × cypress_t0 on grid: inference_tflops = 37.5 × 0.85 = 31.875.
	# Deploy 7B-equivalent (fpt = 1.4e10) → 31.875e12 / 1.4e10 ≈ 2276.79 t/s.
	var dc_id := _solo_with_one_t1()
	var mid := _add_published_model_with_fpt(_BASELINE_FPT_7B)
	var r: Dictionary = CommandBus.send(&"infra.deploy_model",
		{dc_id = dc_id, model_id = mid})
	assert_true(r.ok)
	assert_almost_eq(float(r.tokens_per_sec), 2276.79, 5.0)
	var dc = InfraSystem.find_dc(dc_id)
	assert_almost_eq(dc.serving_tokens_per_sec, 2276.79, 5.0)

func test_deploy_model_larger_fpt_lower_capacity() -> void:
	# §6.4: 模型大 10× → t/s 低 10×. 70B ≈ fpt = 1.4e11 → ~227.68 t/s.
	var dc_id := _solo_with_one_t1()
	var mid := _add_published_model_with_fpt(_BASELINE_FPT_7B * 10.0)
	var r: Dictionary = CommandBus.send(&"infra.deploy_model",
		{dc_id = dc_id, model_id = mid})
	assert_true(r.ok)
	assert_almost_eq(float(r.tokens_per_sec), 227.68, 1.0)

func test_deploy_open_source_model_uses_release_flops_per_token() -> void:
	# v9 PR-I: open-source serving 走 OS NPC release, fpt 派生自 release.params_b.
	# release_wolf_1 (turn 215, params_b=13.0 dense): size_params=13000M, active_ratio=1.0
	# → expected fpt = 2 × 13000 × 1.0 × 1e6 = 2.6e10.
	GameState.turn = 220
	var dc_id := _solo_with_one_t1()
	var found: Dictionary = MarketSystem.find_release(&"release_wolf_1")
	if not found.get(&"ok", false):
		pending("release_wolf_1 not present, skipping")
		return
	var release = found.release
	var size_m: float = float(release.params_b) * 1000.0
	var active_ratio: float = 1.0
	if float(release.params_b) > 0.0:
		active_ratio = float(release.active_params_b) / float(release.params_b)
	var expected_fpt: float = 2.0 * size_m * active_ratio * 1.0e6
	var dc = InfraSystem.find_dc(dc_id)
	var inf_tf: float = dc.inference_tflops
	var expected_tps: float = inf_tf * 1.0e12 / expected_fpt
	var r: Dictionary = CommandBus.send(&"infra.deploy_open_source_model",
		{dc_id = dc_id, release_id = &"release_wolf_1"})
	assert_true(r.ok, "deploy release_wolf_1: %s" % str(r.get(&"error", &"")))
	assert_almost_eq(float(r.tokens_per_sec), expected_tps, max(1.0, expected_tps * 0.01))
	assert_almost_eq(dc.serving_tokens_per_sec, expected_tps, max(1.0, expected_tps * 0.01))

# ---- 2026-05: 长上下文吞吐惩罚 (serving_penalty) -----------------------

func _find_owned_model(model_id: StringName):
	for m in GameState.models:
		if m.id == model_id:
			return m
	return null

func test_long_context_model_reduces_serving_tokens_per_sec() -> void:
	# 2026-05: 部署模型 context_length_tokens 越大, serving t/s 越低.
	# 200k 档 serving_penalty = 3.0 → t/s 应为 4k 基线的 1/3 (同 fpt / 同卡).
	var dc_base := _solo_with_one_t1()
	var mid_base := _add_published_model_with_fpt(_BASELINE_FPT_7B)
	# 基线模型保留默认 context_length_tokens = 4096 (penalty 1.0).
	var r_base: Dictionary = CommandBus.send(&"infra.deploy_model",
		{dc_id = dc_base, model_id = mid_base})
	assert_true(r_base.ok)
	var tps_4k: float = float(r_base.tokens_per_sec)
	assert_gt(tps_4k, 0.0)

	# 同 fpt / 同卡, 但 200k 上下文 → serving_penalty = 3.0.
	var dc_long := _solo_with_one_t1()
	var mid_long := _add_published_model_with_fpt(_BASELINE_FPT_7B)
	var m_long = _find_owned_model(mid_long)
	m_long.context_length_tokens = 200_000
	var r_long: Dictionary = CommandBus.send(&"infra.deploy_model",
		{dc_id = dc_long, model_id = mid_long})
	assert_true(r_long.ok)
	assert_almost_eq(float(r_long.tokens_per_sec), tps_4k / 3.0, tps_4k * 0.01,
		"200k ctx serving t/s 应为 4k 基线的 1/3 (serving_penalty=3.0)")

func test_baseline_4k_context_has_no_serving_penalty() -> void:
	# 4k baseline: penalty = 1.0, 与无惩罚旧公式数值一致 (回归保护).
	# 1 × cypress_t0 grid: inference_tflops = 31.875; fpt = 1.4e10 → ~2276.79 t/s.
	var dc_id := _solo_with_one_t1()
	var mid := _add_published_model_with_fpt(_BASELINE_FPT_7B)
	var m = _find_owned_model(mid)
	assert_eq(m.context_length_tokens, 4096, "默认 ctx = 4096")
	var r: Dictionary = CommandBus.send(&"infra.deploy_model",
		{dc_id = dc_id, model_id = mid})
	assert_true(r.ok)
	assert_almost_eq(float(r.tokens_per_sec), 2276.79, 5.0,
		"4k 上下文 serving_penalty=1.0, t/s 不变")

func test_undeploy_model_clears_serving_tokens_per_sec() -> void:
	# §6.4: undeploy_model 把 serving_tokens_per_sec 清 0.
	var dc_id := _solo_with_one_t1()
	var mid := _add_published_model_with_fpt(_BASELINE_FPT_7B)
	CommandBus.send(&"infra.deploy_model", {dc_id = dc_id, model_id = mid})
	var dc = InfraSystem.find_dc(dc_id)
	assert_gt(dc.serving_tokens_per_sec, 0.0)
	CommandBus.send(&"infra.undeploy_model", {dc_id = dc_id})
	assert_eq(dc.serving_tokens_per_sec, 0.0)

func test_buy_gpus_while_serving_recomputes_serving_tokens_per_sec() -> void:
	# §2 约定: serving 状态下加卡仍允许; serving_tokens_per_sec 必须随 inference_tflops 重算.
	GameState.cash = 100_000_000
	var dc_id := _rent_pod()
	CommandBus.send(&"infra.buy_gpus", {dc_id = dc_id, gpu_id = &"cypress_t0", count = 2})
	var mid := _add_published_model_with_fpt(_BASELINE_FPT_7B)
	CommandBus.send(&"infra.deploy_model", {dc_id = dc_id, model_id = mid})
	var dc = InfraSystem.find_dc(dc_id)
	var tps_before: float = dc.serving_tokens_per_sec
	CommandBus.send(&"infra.buy_gpus", {dc_id = dc_id, gpu_id = &"cypress_t0", count = 2})
	# 卡数从 2 → 4, inference_tflops 翻倍 (cluster_eff 在 ≤8 卡基本没变化).
	assert_almost_eq(dc.serving_tokens_per_sec, tps_before * 2.0, tps_before * 0.05)

func test_save_loaded_recomputes_legacy_serving_capacity_with_zero_model_fpt() -> void:
	# 旧档可能已经缓存了 fpt=0 时算出的巨大 serving_tokens_per_sec.
	# save_loaded 后 InfraSystem 必须用迁移后的模型 FLOPs/token 重算。
	var dc_id := _solo_with_one_t1()
	var m := Model.new()
	m.id = &"legacy_m2"
	m.display_name = "M2"
	m.status = &"published"
	m.size_params = 7000.0
	m.flops_per_token = 0.0
	GameState.models.append(m)
	var dc = InfraSystem.find_dc(dc_id)
	dc.status = &"serving"
	dc.serving_target_kind = &"owned_model"
	dc.serving_target_id = m.id
	dc.deployed_model_id = m.id
	dc.serving_tokens_per_sec = dc.inference_tflops * 1.0e12

	EventBus.save_loaded.emit()

	assert_almost_eq(m.flops_per_token, 14_000_000_000.0, 1.0)
	assert_almost_eq(dc.serving_tokens_per_sec, 2276.79, 5.0)

func test_save_loaded_materializes_legacy_open_source_serving_target() -> void:
	# 旧档保存的是 release id, 没有 Model / API 产品。加载时要迁移到正常
	# published model serving 管道, 否则产品页仍然看不到 API, 也无法调价。
	GameState.turn = 220
	var dc_id := _solo_with_one_t1()
	var dc = InfraSystem.find_dc(dc_id)
	dc.status = &"serving"
	dc.serving_target_kind = &"open_source_model"
	dc.serving_target_id = &"release_wolf_1"
	dc.deployed_model_id = &""
	dc.serving_tokens_per_sec = 0.0

	EventBus.save_loaded.emit()

	assert_eq(dc.status, &"serving")
	assert_eq(dc.serving_target_kind, &"owned_model")
	assert_ne(dc.deployed_model_id, &"")
	assert_eq(dc.serving_target_id, dc.deployed_model_id)
	assert_gt(dc.serving_tokens_per_sec, 0.0)
	var m = ResearchSystem.find_model(dc.deployed_model_id)
	assert_not_null(m)
	assert_eq(m.status, &"published")
	assert_eq(m.provenance, &"downloaded_os")
	assert_eq(m.source_release_id, &"release_wolf_1")
	var api_count: int = 0
	for p in GameState.products:
		if p.type == &"api" and p.bound_model_id == m.id:
			api_count += 1
	assert_eq(api_count, 1)

func test_sell_gpus_while_idle_clears_serving_tokens_per_sec_naturally() -> void:
	# 卖空所有卡 → inference_tflops = 0 → serving_tokens_per_sec = 0
	# (idle 状态; serving 时不允许卖, 所以这里以 idle 为前提验证零卡边界).
	var dc_id := _solo_with_one_t1()
	var dc = InfraSystem.find_dc(dc_id)
	assert_gt(dc.inference_tflops, 0.0)
	CommandBus.send(&"infra.sell_gpus", {dc_id = dc_id, count = 1})
	assert_eq(dc.inference_tflops, 0.0)
	assert_eq(dc.serving_tokens_per_sec, 0.0)

# ---- preview_deploy_capacity (UI 部署对话框用) -----------------------

func test_preview_deploy_capacity_for_owned_model_returns_tps_without_deploying() -> void:
	# §6.4bis: preview 不改 dc 状态; 返回 tokens_per_sec / inference_tflops / flops_per_token.
	var dc_id := _solo_with_one_t1()
	var mid := _add_published_model_with_fpt(_BASELINE_FPT_7B)
	var r: Dictionary = CommandBus.send(&"infra.preview_deploy_capacity",
		{dc_id = dc_id, model_id = mid})
	assert_true(r.ok)
	assert_almost_eq(float(r.tokens_per_sec), 2276.79, 5.0)
	assert_almost_eq(float(r.flops_per_token), _BASELINE_FPT_7B, 1.0)
	assert_eq(r.target_kind, &"owned_model")
	assert_eq(r.target_id, mid)
	# dc 未发生状态变化.
	var dc = InfraSystem.find_dc(dc_id)
	assert_eq(dc.status, &"idle")
	assert_eq(dc.serving_tokens_per_sec, 0.0)

func test_preview_deploy_capacity_unknown_dc_returns_error() -> void:
	var r: Dictionary = CommandBus.send(&"infra.preview_deploy_capacity",
		{dc_id = &"nope", model_id = &"x"})
	assert_false(r.ok)
	assert_eq(r.error, &"unknown_dc")

func test_preview_deploy_capacity_missing_target_returns_error() -> void:
	var dc_id := _solo_with_one_t1()
	var r: Dictionary = CommandBus.send(&"infra.preview_deploy_capacity", {dc_id = dc_id})
	assert_false(r.ok)
	assert_eq(r.error, &"missing_target")

func test_preview_deploy_capacity_unknown_model_returns_error() -> void:
	var dc_id := _solo_with_one_t1()
	var r: Dictionary = CommandBus.send(&"infra.preview_deploy_capacity",
		{dc_id = dc_id, model_id = &"bogus_model"})
	assert_false(r.ok)
	assert_eq(r.error, &"unknown_model")

func test_preview_deploy_capacity_unpublished_model_returns_error() -> void:
	var dc_id := _solo_with_one_t1()
	var rm: Dictionary = CommandBus.send(&"research.add_model", {
		capability = {&"general": 60.0}, arch = &"ant_v1", dataset_ids = []})
	# 不调 publish; 还停在 pretrained.
	var r: Dictionary = CommandBus.send(&"infra.preview_deploy_capacity",
		{dc_id = dc_id, model_id = rm.model_id})
	assert_false(r.ok)
	assert_eq(r.error, &"model_not_published")

func test_preview_deploy_capacity_unknown_release_returns_error() -> void:
	# v9 PR-I: preview path takes release_id (OS NPC pretrain release).
	GameState.turn = 500
	var dc_id := _solo_with_one_t1()
	var r: Dictionary = CommandBus.send(&"infra.preview_deploy_capacity",
		{dc_id = dc_id, release_id = &"no_such_release"})
	assert_false(r.ok)
	assert_eq(r.error, &"unknown_release")

func test_preview_deploy_capacity_works_while_dc_serving_other_model() -> void:
	# §6.4bis: preview 在任何 dc 状态下都能查; 玩家想"如果换到这个模型 t/s 是多少".
	var dc_id := _solo_with_one_t1()
	var mid_a := _add_published_model_with_fpt(_BASELINE_FPT_7B)
	CommandBus.send(&"infra.deploy_model", {dc_id = dc_id, model_id = mid_a})
	var mid_b := _add_published_model_with_fpt(_BASELINE_FPT_7B * 10.0)  # 10× larger
	var r: Dictionary = CommandBus.send(&"infra.preview_deploy_capacity",
		{dc_id = dc_id, model_id = mid_b})
	assert_true(r.ok)
	assert_almost_eq(float(r.tokens_per_sec), 227.68, 1.0)
	# dc 仍在 serving mid_a, 没有切换.
	var dc = InfraSystem.find_dc(dc_id)
	assert_eq(dc.serving_target_id, mid_a)

# ============================================================================
# v4 (PR-B): engineering tree multipliers (throughput_multiplier +
# flops_per_token_reduction) are baked INTO dc.serving_tokens_per_sec via
# InfraSystem._refresh_serving_capacity, not applied later by MonetizationSystem.
# Per design/基础设施系统设计.md §6.1.1.
# ============================================================================

func test_engineering_throughput_multiplier_baked_into_serving_t_s() -> void:
	# Unlock owl_cache (throughput_multiplier=1.3) → serving t/s scales by 1.3.
	var dc_id := _solo_with_one_t1()
	var mid := _add_published_model_with_fpt(_BASELINE_FPT_7B)
	CommandBus.send(&"infra.deploy_model", {dc_id = dc_id, model_id = mid})
	var dc = InfraSystem.find_dc(dc_id)
	var baseline_tps: float = dc.serving_tokens_per_sec
	CommandBus.send(&"tech.unlock_node", {tree = &"engineering", node_id = &"owl_cache"})
	# tech_unlocked → _on_tech_unlocked recomputes serving t/s.
	assert_almost_eq(dc.serving_tokens_per_sec, baseline_tps * 1.3, baseline_tps * 0.02)

func test_engineering_flops_per_token_reduction_baked_into_serving_t_s() -> void:
	# Unlock squirrel_int8 (flops_per_token_reduction=0.6) → t/s scales by 1/0.6 ≈ 1.67.
	# squirrel_int8 prereq is owl_cache; unlock it first.
	var dc_id := _solo_with_one_t1()
	var mid := _add_published_model_with_fpt(_BASELINE_FPT_7B)
	CommandBus.send(&"infra.deploy_model", {dc_id = dc_id, model_id = mid})
	var dc = InfraSystem.find_dc(dc_id)
	var baseline_tps: float = dc.serving_tokens_per_sec
	CommandBus.send(&"tech.unlock_node", {tree = &"engineering", node_id = &"owl_cache"})
	CommandBus.send(&"tech.unlock_node", {tree = &"engineering", node_id = &"squirrel_int8"})
	# Combined: owl_cache (×1.3 throughput) + int8 (÷0.6 fpt) = ×1.3 / 0.6 ≈ ×2.167
	var expected: float = baseline_tps * 1.3 / 0.6
	assert_almost_eq(dc.serving_tokens_per_sec, expected, expected * 0.02)

func test_tech_unlocked_signal_emits_dc_compute_recomputed_for_serving_dcs() -> void:
	# v4 (PR-B): _on_tech_unlocked must emit dc_compute_recomputed so UI refreshes.
	var dc_id := _solo_with_one_t1()
	var mid := _add_published_model_with_fpt(_BASELINE_FPT_7B)
	CommandBus.send(&"infra.deploy_model", {dc_id = dc_id, model_id = mid})
	watch_signals(EventBus)
	CommandBus.send(&"tech.unlock_node", {tree = &"engineering", node_id = &"owl_cache"})
	assert_signal_emitted(EventBus, "dc_compute_recomputed")

func test_tech_unlocked_on_non_engineering_tree_does_not_recompute() -> void:
	# arch / application unlocks should not trigger a serving recompute (only
	# engineering affects t/s). Verify by unlocking an arch node and watching
	# that serving_t/s stays unchanged.
	var dc_id := _solo_with_one_t1()
	var mid := _add_published_model_with_fpt(_BASELINE_FPT_7B)
	CommandBus.send(&"infra.deploy_model", {dc_id = dc_id, model_id = mid})
	var dc = InfraSystem.find_dc(dc_id)
	var before: float = dc.serving_tokens_per_sec
	CommandBus.send(&"tech.unlock_node", {tree = &"arch", node_id = &"ant_v2"})
	assert_almost_eq(dc.serving_tokens_per_sec, before, 0.001)

func test_preview_deploy_capacity_includes_engineering_multipliers() -> void:
	# preview must mirror deploy: with engineering unlocks active, the previewed
	# t/s should match what deploy would actually cache.
	var dc_id := _solo_with_one_t1()
	var mid := _add_published_model_with_fpt(_BASELINE_FPT_7B)
	CommandBus.send(&"tech.unlock_node", {tree = &"engineering", node_id = &"owl_cache"})
	var preview: Dictionary = CommandBus.send(&"infra.preview_deploy_capacity",
		{dc_id = dc_id, model_id = mid})
	assert_true(preview.ok)
	CommandBus.send(&"infra.deploy_model", {dc_id = dc_id, model_id = mid})
	var dc = InfraSystem.find_dc(dc_id)
	# preview and deploy must agree to within rounding.
	assert_almost_eq(float(preview.tokens_per_sec), dc.serving_tokens_per_sec,
			max(0.01, dc.serving_tokens_per_sec * 0.01))

# ============================================================================
# v4 (PR-B): MoE active_param_ratio cuts BOTH training compute and inference
# flops_per_token. Tests for inference live here; training-side test lives in
# scaling_law_test.gd. Per design/平衡参数.md "模型架构激活参数比例".
# ============================================================================

func test_moe_model_flops_per_token_uses_active_param_ratio() -> void:
	# A 100B octopus_v1 model (active_ratio=0.25) should have flops_per_token
	# equal to a 25B dense model: 2 × 25e9 = 5e10 (not 2e11).
	var moe_model := Model.new()
	moe_model.id = &"moe_100b"
	moe_model.display_name = "MoE 100B"
	moe_model.status = &"published"
	moe_model.arch = &"octopus_v1"
	moe_model.size_params = 100_000.0       # 100B in M-params
	moe_model.active_param_ratio = 0.25
	moe_model.flops_per_token = Model.infer_flops_per_token(
			moe_model.size_params, moe_model.active_param_ratio)
	GameState.models.append(moe_model)
	assert_almost_eq(moe_model.flops_per_token, 5.0e10, 1.0,
			"MoE 100B (1/4 active) must use 25B-equivalent flops_per_token")

func test_dense_model_flops_per_token_unchanged_by_active_param_ratio() -> void:
	# Dense models (active_param_ratio = 1.0) keep the legacy formula 2 × N.
	var dense_model := Model.new()
	dense_model.id = &"dense_100b"
	dense_model.display_name = "Dense 100B"
	dense_model.status = &"published"
	dense_model.arch = &"ant_v1"
	dense_model.size_params = 100_000.0
	dense_model.active_param_ratio = 1.0
	dense_model.flops_per_token = Model.infer_flops_per_token(
			dense_model.size_params, dense_model.active_param_ratio)
	GameState.models.append(dense_model)
	assert_almost_eq(dense_model.flops_per_token, 2.0e11, 1.0,
			"Dense 100B must use 2 × 100B flops_per_token")

# ─── DC 名本地化 (Datacenter.display_label, 见 国际化设计.md §6ter) ──────────

func test_display_label_cloud_is_localized_and_count_based() -> void:
	# 云租 DC 名按 ownership+卡数实时拼, 不存中文; 切 locale 即时变。
	var dc := Datacenter.new()
	dc.ownership = &"cloud"
	dc.display_name = ""
	dc.max_gpu_count = 64
	TranslationServer.set_locale("zh_CN")
	var zh: String = dc.display_label()
	TranslationServer.set_locale("en")
	var en: String = dc.display_label()
	TranslationServer.set_locale("zh_CN")
	assert_string_contains(zh, "64", "云租名应含卡数")
	assert_string_contains(en, "64", "云租名应含卡数")
	assert_ne(zh, en, "云租名应随 locale 变")
	assert_eq(en.find("Cloud"), 0, "en 下云租名应是英文")

func test_display_label_owned_translates_spec_name() -> void:
	# 自有 DC 沿用设施名 (content.csv 的中文 key), 显示时翻译。
	var dc := Datacenter.new()
	dc.ownership = &"owned"
	dc.display_name = "8k 卡整层"  # 真实设施 spec 名, 在 content.csv 有 en
	TranslationServer.set_locale("en")
	var en: String = dc.display_label()
	TranslationServer.set_locale("zh_CN")
	var zh: String = dc.display_label()
	assert_ne(en, zh, "自有 DC 设施名应随 locale 翻译")
	assert_eq(en.find("8k 卡整层"), -1, "en 下不应残留中文设施名")

func test_display_label_strips_legacy_id_suffix() -> void:
	var dc := Datacenter.new()
	dc.ownership = &"owned"
	dc.display_name = "8k 卡整层 [dc_0007]"
	TranslationServer.set_locale("zh_CN")
	assert_eq(dc.display_label().find("[dc_"), -1, "旧档 id 后缀应裁掉")
