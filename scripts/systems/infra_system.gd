extends Node

## InfraSystem v2 — facility + GPU split asset model.
## Per design/基础设施系统设计.md.
##
## Two independent assets:
##   1. Facility (机房) = building, sets max_gpu_count + land cost + power.
##   2. GPU = depreciating asset, bought/sold separately, single brand per dc.
##
## Commands:
##   - infra.rent_facility / infra.build_facility
##   - infra.terminate_dc (auto-sells remaining GPUs first)
##   - infra.buy_gpus / infra.sell_gpus (new)
##   - infra.deploy_model / infra.undeploy_model
##   - infra.deploy_open_source_model
##   - infra.preview_deploy_capacity (v3, UI 部署对话框用; 不改 dc 状态, 返回预计 t/s)
##   - infra.assign_to_task / infra.release_from_task (unchanged)
##
## v3 (2026-05): inference_tflops + serving_tokens_per_sec.
##   - per GPU: per_card_inference_tflops (TFLOPs, batched/KV-cache 折损后的等效推理算力).
##   - per dc: inference_tflops = per_card_inference_tflops × gpu_count × cluster_efficiency.
##   - on deploy_model / deploy_open_source_model: serving_tokens_per_sec
##     = inference_tflops × 1e12 / max(target.flops_per_token, 1).
##   - MonetizationSystem 直接读 dc.serving_tokens_per_sec, 不再做 BASELINE 缩放.
##

const OWNED_SLICES: Array[StringName] = [&"datacenters", &"construction_queue"]

# Facility tier table (19 tiers per design; solo 1 → planet 100M).
const FACILITY_SPECS: Dictionary = {
	&"facility_solo": "res://resources/data/infra/facilities/facility_solo.tres",
	&"facility_pod": "res://resources/data/infra/facilities/facility_pod.tres",
	&"facility_rack_16": "res://resources/data/infra/facilities/facility_rack_16.tres",
	&"facility_rack_32": "res://resources/data/infra/facilities/facility_rack_32.tres",
	&"facility_rack": "res://resources/data/infra/facilities/facility_rack.tres",
	&"facility_room": "res://resources/data/infra/facilities/facility_room.tres",
	&"facility_hall": "res://resources/data/infra/facilities/facility_hall.tres",
	&"facility_floor": "res://resources/data/infra/facilities/facility_floor.tres",
	&"facility_building_s": "res://resources/data/infra/facilities/facility_building_s.tres",
	&"facility_building_m": "res://resources/data/infra/facilities/facility_building_m.tres",
	&"facility_building_l": "res://resources/data/infra/facilities/facility_building_l.tres",
	&"facility_campus_s": "res://resources/data/infra/facilities/facility_campus_s.tres",
	&"facility_campus_m": "res://resources/data/infra/facilities/facility_campus_m.tres",
	&"facility_campus_l": "res://resources/data/infra/facilities/facility_campus_l.tres",
	&"facility_metropolis": "res://resources/data/infra/facilities/facility_metropolis.tres",
	&"facility_space_s": "res://resources/data/infra/facilities/facility_space_s.tres",
	&"facility_space_m": "res://resources/data/infra/facilities/facility_space_m.tres",
	&"facility_space_l": "res://resources/data/infra/facilities/facility_space_l.tres",
	&"facility_planet": "res://resources/data/infra/facilities/facility_planet.tres",
}

const GPU_SPECS: Dictionary = {
	&"cypress_t0": "res://resources/data/infra/gpus/cypress_t0.tres",
	&"cypress_t1": "res://resources/data/infra/gpus/cypress_t1.tres",
	&"cypress_t2": "res://resources/data/infra/gpus/cypress_t2.tres",
	&"cypress_t3": "res://resources/data/infra/gpus/cypress_t3.tres",
	&"maple_t1": "res://resources/data/infra/gpus/maple_t1.tres",
	&"maple_t2": "res://resources/data/infra/gpus/maple_t2.tres",
	&"maple_t3": "res://resources/data/infra/gpus/maple_t3.tres",
	&"bamboo_t1": "res://resources/data/infra/gpus/bamboo_t1.tres",
	&"bamboo_t2": "res://resources/data/infra/gpus/bamboo_t2.tres",
	&"bamboo_t3": "res://resources/data/infra/gpus/bamboo_t3.tres",
	&"bamboo_t4": "res://resources/data/infra/gpus/bamboo_t4.tres",
}

# v11: two options only — grid (常规供电) / green (绿色能源).
const POWER_SPECS: Dictionary = {
	&"grid": "res://resources/data/infra/power/grid.tres",
	&"green": "res://resources/data/infra/power/green.tres",
}

# v11: legacy saves may carry the old 5-power ids — remap on load.
# coal → grid (conventional); solar/wind/nuclear → green.
const _LEGACY_POWER_MIGRATION: Dictionary = {
	&"coal": &"grid",
	&"solar": &"green",
	&"wind": &"green",
	&"nuclear": &"green",
}

# 2026-05: 长上下文 serving 吞吐惩罚 (除数). 长上下文因 KV cache 显存带宽瓶颈急剧掉
# 吞吐 — 部署模型 context_length_tokens 越大, serving t/s 越低. 档值与
# design/平衡参数.md + context 子树 .tres 的 `serving_penalty` 一致; 这里硬编码兜底
# (与 TaskSystem._CONTEXT_LENGTH_PENALTY 同模式), .tres 缺失 / 测试时也能算。
const _CONTEXT_SERVING_PENALTY: Dictionary = {
	4096:     1.0,
	32768:    1.5,
	200000:   3.0,
	1000000:  6.0,
	10000000: 12.0,
}

var _next_dc_seq: int = 1
var _next_construction_seq: int = 1

func _ready() -> void:
	# v2 commands
	CommandBus.register(&"infra.rent_facility", _on_rent_facility)
	CommandBus.register(&"infra.build_facility", _on_build_facility)
	CommandBus.register(&"infra.create_cloud_dc", _on_create_cloud_dc)
	CommandBus.register(&"infra.buy_gpus", _on_buy_gpus)
	CommandBus.register(&"infra.sell_gpus", _on_sell_gpus)
	CommandBus.register(&"infra.terminate_dc", _on_terminate_dc)
	CommandBus.register(&"infra.deploy_model", _on_deploy_model)
	CommandBus.register(&"infra.deploy_open_source_model", _on_deploy_open_source_model)
	CommandBus.register(&"infra.undeploy_model", _on_undeploy_model)
	CommandBus.register(&"infra.set_dc_rent_out", _on_set_dc_rent_out)
	CommandBus.register(&"infra.preview_deploy_capacity", _on_preview_deploy_capacity)
	CommandBus.register(&"infra.assign_to_task", _on_assign_to_task)
	CommandBus.register(&"infra.release_from_task", _on_release_from_task)
	CommandBus.register(&"infra.debug_instant_owned_dc", _on_debug_instant_owned_dc)
	EventBus.phase_started.connect(_on_phase)
	EventBus.save_loaded.connect(_on_save_loaded)
	# v4 (PR-B): tech_unlocked on the engineering tree must immediately
	# recompute every serving dc's t/s so the UI + MonetizationSystem see the
	# new multipliers (FP8 / int8 / KV cache / paged attn / ...).
	EventBus.tech_unlocked.connect(_on_tech_unlocked)

# ---- rent / build (v2) --------------------------------------------------

func _on_rent_facility(p: Dictionary) -> Dictionary:
	var spec: FacilitySpec = _load_facility_spec(p.get(&"facility_spec_id", &""))
	if spec == null:
		return {ok = false, error = &"unknown_spec"}
	var power_id: StringName = p.get(&"power_supply_id", &"grid")
	var pwr: PowerSupplySpec = _load_power_spec(power_id)
	if pwr == null:
		return {ok = false, error = &"unknown_power"}
	if GameState.cash < spec.unlock_cash_required:
		return {ok = false, error = &"facility_unlock_required"}
	var dc := _make_dc(spec, pwr, &"rented")
	GameState.datacenters.append(dc)
	# Per design 基础设施系统设计 §4: facility rent has ZERO upfront —
	# the first weekly charge lands at the next upkeep phase, not now.
	Log.info(&"infra", "facility_rented",
		{dc_id = dc.id, spec = spec.id, power = power_id})
	EventBus.datacenter_added.emit(dc.id)
	EventBus.dc_compute_recomputed.emit(dc.id, dc.train_tflops, dc.inference_tflops, dc.serving_tokens_per_sec)
	return {ok = true, dc_id = dc.id}

func _on_build_facility(p: Dictionary) -> Dictionary:
	var spec: FacilitySpec = _load_facility_spec(p.get(&"facility_spec_id", &""))
	if spec == null:
		return {ok = false, error = &"unknown_spec"}
	var power_id: StringName = p.get(&"power_supply_id", &"grid")
	var pwr: PowerSupplySpec = _load_power_spec(power_id)
	if pwr == null:
		return {ok = false, error = &"unknown_power"}
	if GameState.cash < spec.unlock_cash_required:
		return {ok = false, error = &"facility_unlock_required"}
	# Optional gpu_id: if provided, GPU cost is charged now and auto-installed on completion.
	var gpu_id: StringName = p.get(&"gpu_id", &"")
	var gpu: GPUSpec = _load_gpu_spec(gpu_id) if gpu_id != &"" else null
	var c := DatacenterConstruction.new()
	c.id = StringName("dc_owned_%04d" % _next_construction_seq)
	_next_construction_seq += 1
	c.facility_spec_id = spec.id
	c.power_supply = power_id
	c.weeks_remaining = spec.build_weeks
	c.total_weeks = spec.build_weeks
	c.gpu_id = gpu_id
	GameState.construction_queue.append(c)
	var build_cost: int = int(spec.land_build_cost * (1.0 + pwr.build_cost_modifier))
	var gpu_total: int = 0
	if gpu != null:
		gpu_total = spec.max_gpu_count * gpu.purchase_price
	# v11: 绿色能源一次性安装 + 储能费, 按机房满配卡数计价 (grid 为 0)。
	var power_install: int = pwr.install_cost_per_card * spec.max_gpu_count
	CommandBus.send(&"economy.spend", {
		cost = {&"cash": build_cost + gpu_total + power_install},
		reason = &"facility_build",
	})
	Log.info(&"infra", "facility_build_started",
		{construction_id = c.id, spec = spec.id, power = power_id,
		build_cost = build_cost, gpu_id = gpu_id, gpu_total = gpu_total,
		power_install = power_install})
	# Edge case: build_weeks == 0 → instant completion (e.g. solo desktop).
	if c.weeks_remaining <= 0:
		_complete_construction(c)
	return {ok = true, construction_id = c.id}

func _on_debug_instant_owned_dc(p: Dictionary) -> Dictionary:
	# Debug-only: create a fully-built owned DC instantly, no cost, no build queue.
	var facility_id: StringName = p.get(&"facility_spec_id", &"facility_rack")
	var gpu_id: StringName = p.get(&"gpu_id", &"cypress_t0")
	var fac_spec: FacilitySpec = _load_facility_spec(facility_id)
	if fac_spec == null:
		return {ok = false, error = &"unknown_spec"}
	var pwr: PowerSupplySpec = _load_power_spec(&"grid")
	var dc: Datacenter = _make_dc(fac_spec, pwr, &"owned")
	var gpu: GPUSpec = _load_gpu_spec(gpu_id)
	if gpu != null and fac_spec.max_gpu_count > 0:
		dc.gpu_id = gpu_id
		dc.gpu_count = fac_spec.max_gpu_count
		var batch := GPUBatch.new()
		batch.count = fac_spec.max_gpu_count
		batch.unit_price = gpu.purchase_price
		batch.bought_at_turn = GameState.turn
		dc.gpu_purchase_history.append(batch)
		_recompute_compute(dc)
	GameState.datacenters.append(dc)
	Log.info(&"infra", "debug_instant_dc_created",
		{dc_id = dc.id, spec = facility_id, gpu = gpu_id, gpu_count = dc.gpu_count})
	EventBus.datacenter_added.emit(dc.id)
	EventBus.dc_compute_recomputed.emit(dc.id, dc.train_tflops, dc.inference_tflops, dc.serving_tokens_per_sec)
	return {ok = true, dc_id = dc.id}

func _on_create_cloud_dc(p: Dictionary) -> Dictionary:
	var gpu_id: StringName = p.get(&"gpu_id", &"")
	var gpu: GPUSpec = _load_gpu_spec(gpu_id)
	if gpu == null:
		return {ok = false, error = &"unknown_gpu"}
	if gpu.release_turn > GameState.turn:
		return {ok = false, error = &"gpu_not_released"}
	var count: int = int(p.get(&"count", 0))
	if count <= 0:
		return {ok = false, error = &"invalid_count"}
	var dc := Datacenter.new()
	dc.id = StringName("dc_%04d" % _next_dc_seq)
	_next_dc_seq += 1
	# 云租 DC 名不存文案 (会被 locale 烤死): 留空, 由 Datacenter.display_label() 按
	# ownership=cloud + max_gpu_count 实时拼 INFRA_CLOUD_DC (见 国际化设计.md §6ter)。
	dc.display_name = ""
	dc.facility_spec_id = &""
	dc.ownership = &"cloud"
	dc.power_supply = &""
	dc.max_gpu_count = count
	dc.gpu_id = gpu_id
	dc.gpu_count = count
	dc.gpu_purchase_history = []
	dc.train_tflops = 0.0
	dc.inference_tflops = 0.0
	dc.serving_tokens_per_sec = 0.0
	dc.cluster_efficiency = 0.0
	dc.facility_weekly_cost = 0
	dc.status = &"idle"
	_recompute_compute(dc)
	GameState.datacenters.append(dc)
	Log.info(&"infra", "cloud_dc_created",
		{dc_id = dc.id, gpu_id = gpu_id, count = count,
		weekly_cost = gpu.rent_weekly_cost * count})
	EventBus.datacenter_added.emit(dc.id)
	EventBus.dc_compute_recomputed.emit(dc.id, dc.train_tflops, dc.inference_tflops, dc.serving_tokens_per_sec)
	return {ok = true, dc_id = dc.id}

# ---- buy / sell GPUs ----------------------------------------------------

func _on_buy_gpus(p: Dictionary) -> Dictionary:
	var dc := find_dc(p.get(&"dc_id", &""))
	if dc == null:
		return {ok = false, error = &"unknown_dc"}
	if dc.ownership == &"cloud":
		return {ok = false, error = &"cloud_dc_no_purchase"}
	# 基础设施系统设计 §6.1.3: GPU buy/sell is allowed in any dc.status
	# (training / serving included). Adding cards mid-run is the design's
	# explicit "elastic capacity" affordance.
	var gpu_id: StringName = p.get(&"gpu_id", &"")
	var gpu: GPUSpec = _load_gpu_spec(gpu_id)
	if gpu == null:
		return {ok = false, error = &"unknown_gpu"}
	# 平衡参数 §GPUSpec: GPUs cannot be purchased before their release_turn.
	if gpu.release_turn > GameState.turn:
		return {ok = false, error = &"gpu_not_released"}
	var count: int = int(p.get(&"count", 0))
	if count <= 0:
		return {ok = false, error = &"invalid_count"}
	if dc.gpu_id != &"" and dc.gpu_id != gpu_id:
		return {ok = false, error = &"mixed_brand"}
	if dc.gpu_count + count > dc.max_gpu_count:
		return {ok = false, error = &"capacity_exceeded"}
	var total_cost: int = count * gpu.purchase_price
	var r: Dictionary = CommandBus.send(&"economy.spend", {
		cost = {&"cash": total_cost},
		reason = &"gpu_purchase",
	})
	if not r.get("ok", false):
		return r
	if dc.gpu_id == &"":
		dc.gpu_id = gpu_id
	dc.gpu_count += count
	var batch := GPUBatch.new()
	batch.count = count
	batch.unit_price = gpu.purchase_price
	batch.bought_at_turn = GameState.turn
	dc.gpu_purchase_history.append(batch)
	_recompute_compute(dc)
	Log.info(&"infra", "gpus_bought",
		{dc_id = dc.id, gpu_id = gpu_id, count = count, total_cost = total_cost})
	EventBus.gpus_bought.emit(dc.id, gpu_id, count, total_cost)
	EventBus.dc_compute_recomputed.emit(dc.id, dc.train_tflops, dc.inference_tflops, dc.serving_tokens_per_sec)
	return {ok = true, total_cost = total_cost}

func _on_sell_gpus(p: Dictionary) -> Dictionary:
	var dc := find_dc(p.get(&"dc_id", &""))
	if dc == null:
		return {ok = false, error = &"unknown_dc"}
	if dc.ownership == &"cloud":
		return {ok = false, error = &"cloud_dc_no_sale"}
	if dc.status != &"idle":
		return {ok = false, error = &"dc_busy"}
	var count: int = int(p.get(&"count", 0))
	if count <= 0:
		return {ok = false, error = &"invalid_count"}
	if dc.gpu_count < count:
		return {ok = false, error = &"not_enough_gpus"}
	var refund: int = _sell_gpus_internal(dc, count)
	_recompute_compute(dc)
	if refund > 0:
		CommandBus.send(&"economy.award", {
			amount = refund, reason = &"gpu_resale",
		})
	Log.info(&"infra", "gpus_sold",
		{dc_id = dc.id, count = count, refund = refund})
	EventBus.gpus_sold.emit(dc.id, count, refund)
	EventBus.dc_compute_recomputed.emit(dc.id, dc.train_tflops, dc.inference_tflops, dc.serving_tokens_per_sec)
	return {ok = true, refund = refund}

# Internal: do the FIFO depreciation walk, mutate dc state, return refund.
# Caller is responsible for awarding cash + emitting signals.
func _sell_gpus_internal(dc: Datacenter, count: int) -> int:
	var refund: int = 0
	var remaining: int = count
	while remaining > 0 and dc.gpu_purchase_history.size() > 0:
		var batch: GPUBatch = dc.gpu_purchase_history[0]
		var take: int = min(remaining, batch.count)
		var years: float = float(GameState.turn - batch.bought_at_turn) / 12.0
		if years < 0.0:
			years = 0.0
		var depreciated: float = float(batch.unit_price) * pow(0.9, years)
		refund += int(round(float(take) * depreciated))
		batch.count -= take
		remaining -= take
		if batch.count <= 0:
			dc.gpu_purchase_history.pop_front()
	dc.gpu_count -= count
	if dc.gpu_count <= 0:
		dc.gpu_count = 0
		dc.gpu_id = &""
		dc.gpu_purchase_history.clear()
	return refund

# ---- terminate ----------------------------------------------------------

func _on_terminate_dc(p: Dictionary) -> Dictionary:
	var dc := find_dc(p.get(&"dc_id", &""))
	if dc == null:
		return {ok = false, error = &"unknown_dc"}
	if dc.status != &"idle":
		return {ok = false, error = &"dc_busy"}
	if dc.ownership == &"cloud":
		GameState.datacenters.erase(dc)
		Log.info(&"infra", "cloud_dc_terminated", {dc_id = dc.id})
		EventBus.datacenter_removed.emit(dc.id)
		return {ok = true, refund_for_remaining_gpus = 0}
	var refund: int = 0
	if dc.gpu_count > 0:
		var n := dc.gpu_count
		refund = _sell_gpus_internal(dc, n)
		if refund > 0:
			CommandBus.send(&"economy.award", {
				amount = refund, reason = &"gpu_resale_on_terminate",
			})
		EventBus.gpus_sold.emit(dc.id, n, refund)
	GameState.datacenters.erase(dc)
	Log.info(&"infra", "dc_terminated",
		{dc_id = dc.id, refund_for_remaining_gpus = refund})
	EventBus.datacenter_removed.emit(dc.id)
	return {ok = true, refund_for_remaining_gpus = refund}

# ---- deploy / undeploy --------------------------------------------------

func _on_deploy_model(p: Dictionary) -> Dictionary:
	var dc := find_dc(p.get(&"dc_id", &""))
	if dc == null:
		return {ok = false, error = &"unknown_dc"}
	if dc.status != &"idle":
		return {ok = false, error = &"dc_not_idle"}
	var model_id: StringName = p.get(&"model_id", &"")
	var model = _find_model(model_id)
	if model == null:
		return {ok = false, error = &"unknown_model"}
	if model.status != &"published":
		return {ok = false, error = &"model_not_published"}
	if dc.gpu_count <= 0:
		return {ok = false, error = &"no_gpus"}
	dc.status = &"serving"
	dc.serving_target_kind = &"owned_model"
	dc.serving_target_id = model_id
	dc.deployed_model_id = model_id
	# v4 (PR-B): single source of truth for serving t/s. _refresh_serving_capacity
	# applies engineering multipliers (throughput_multiplier + flops_per_token_reduction)
	# uniformly with the buy/sell/tech_unlocked paths.
	_normalized_model_fpt(model)   # side-effect: legacy fpt migration
	_refresh_serving_capacity(dc)
	Log.info(&"infra", "model_deployed",
		{dc_id = dc.id, model_id = model_id, target_kind = dc.serving_target_kind,
		serving_tokens_per_sec = dc.serving_tokens_per_sec})
	EventBus.datacenter_status_changed.emit(dc.id, &"idle", &"serving")
	EventBus.model_deployed.emit(dc.id, model_id)
	EventBus.dc_compute_recomputed.emit(dc.id, dc.train_tflops, dc.inference_tflops, dc.serving_tokens_per_sec)
	return {ok = true, tokens_per_sec = dc.serving_tokens_per_sec}

func _on_deploy_open_source_model(p: Dictionary) -> Dictionary:
	var dc := find_dc(p.get(&"dc_id", &""))
	if dc == null:
		return {ok = false, error = &"unknown_dc"}
	if dc.status != &"idle":
		return {ok = false, error = &"dc_not_idle"}
	if dc.gpu_count <= 0:
		return {ok = false, error = &"no_gpus"}
	# Public OS deploys are materialized as player-owned published Models so
	# pricing, API products, capacity and revenue all share the normal path.
	var release_id: StringName = p.get(&"release_id", &"")
	var materialized: Dictionary = CommandBus.send(&"research.ensure_open_source_release_published", {
		release_id = release_id,
	})
	if not materialized.get(&"ok", false):
		return {ok = false, error = StringName(materialized.get(&"error", &"unknown_release"))}
	var model_id: StringName = StringName(materialized.get(&"model_id", &""))
	var model = _find_model(model_id)
	if model == null:
		return {ok = false, error = &"unknown_model"}
	if model.status != &"published":
		return {ok = false, error = &"model_not_published"}
	dc.status = &"serving"
	dc.serving_target_kind = &"owned_model"
	dc.serving_target_id = model_id
	dc.deployed_model_id = model_id
	_normalized_model_fpt(model)
	_refresh_serving_capacity(dc)
	Log.info(&"infra", "open_source_model_deployed",
		{dc_id = dc.id, release_id = release_id, model_id = model_id,
		serving_tokens_per_sec = dc.serving_tokens_per_sec})
	EventBus.datacenter_status_changed.emit(dc.id, &"idle", &"serving")
	EventBus.model_deployed.emit(dc.id, model_id)
	EventBus.open_source_model_deployed.emit(dc.id, release_id)
	EventBus.dc_compute_recomputed.emit(dc.id, dc.train_tflops, dc.inference_tflops, dc.serving_tokens_per_sec)
	return {ok = true, tokens_per_sec = dc.serving_tokens_per_sec, model_id = model_id}

func _on_undeploy_model(p: Dictionary) -> Dictionary:
	var dc := find_dc(p.get(&"dc_id", &""))
	if dc == null:
		return {ok = false, error = &"unknown_dc"}
	if dc.status != &"serving":
		return {ok = false, error = &"not_serving"}
	var prev: StringName = dc.deployed_model_id
	if prev == &"":
		prev = dc.serving_target_id
	dc.status = &"idle"
	dc.serving_target_kind = &""
	dc.serving_target_id = &""
	dc.deployed_model_id = &""
	dc.serving_tokens_per_sec = 0.0   # v3: clear cached capacity
	Log.info(&"infra", "model_undeployed", {dc_id = dc.id, target_id = prev})
	EventBus.datacenter_status_changed.emit(dc.id, &"serving", &"idle")
	EventBus.model_undeployed.emit(dc.id, prev)
	EventBus.dc_compute_recomputed.emit(dc.id, dc.train_tflops, dc.inference_tflops, dc.serving_tokens_per_sec)
	return {ok = true}

# ---- preview deploy capacity (v3, UI 部署对话框用) ----------------------

func _on_preview_deploy_capacity(p: Dictionary) -> Dictionary:
	# §6.4bis: pure read — does not change dc state. Allowed in any dc status
	# (idle/serving/training) so the UI can answer "what t/s would I get if I
	# switched to this model" while the dc is still serving the previous one.
	var dc := find_dc(p.get(&"dc_id", &""))
	if dc == null:
		return {ok = false, error = &"unknown_dc"}
	var model_id: StringName = p.get(&"model_id", &"")
	var release_id: StringName = p.get(&"release_id", &"")
	if model_id == &"" and release_id == &"":
		return {ok = false, error = &"missing_target"}
	var fpt: float = 0.0
	var kind: StringName = &""
	var target_id: StringName = &""
	if model_id != &"":
		var model = _find_model(model_id)
		if model == null:
			return {ok = false, error = &"unknown_model"}
		if model.status != &"published":
			return {ok = false, error = &"model_not_published"}
		fpt = _normalized_model_fpt(model)
		kind = &"owned_model"
		target_id = model_id
	else:
		# v9 PR-I: OS preview also走 OS NPC release.
		var resolve: Dictionary = _resolve_os_release(release_id)
		if not resolve.get(&"ok", false):
			return {ok = false, error = StringName(resolve.get(&"error", &"unknown_release"))}
		fpt = _release_flops_per_token(resolve.release)
		kind = &"open_source_model"
		target_id = release_id
	# v4 (PR-B): preview must mirror the same engineering-multiplier path as
	# the actual deploy, otherwise the UI would show optimistic/pessimistic
	# numbers vs. what the player gets after pressing Deploy.
	var eng_mults: Dictionary = _engineering_serving_mults()
	var effective_inf: float = float(dc.inference_tflops) * eng_mults.throughput_multiplier
	var effective_fpt: float = fpt * eng_mults.flops_per_token_reduction
	var tps: float = effective_inf * 1.0e12 / effective_fpt
	return {
		ok = true,
		tokens_per_sec = tps,
		inference_tflops = float(dc.inference_tflops),
		flops_per_token = fpt,
		target_kind = kind,
		target_id = target_id,
	}

# ---- task lock / release ------------------------------------------------

func _on_assign_to_task(p: Dictionary) -> Dictionary:
	var dc := find_dc(p.get(&"dc_id", &""))
	if dc == null:
		return {ok = false, error = &"unknown_dc"}
	if dc.status != &"idle":
		return {ok = false, error = &"dc_not_idle"}
	# Zero-card dcs cannot accept training tasks (they would never make progress).
	if dc.gpu_count <= 0:
		return {ok = false, error = &"no_gpus"}
	dc.status = &"training"
	dc.busy_with_task_id = p.get(&"task_id", &"")
	EventBus.datacenter_status_changed.emit(dc.id, &"idle", &"training")
	return {ok = true}

func _on_release_from_task(p: Dictionary) -> Dictionary:
	var dc := find_dc(p.get(&"dc_id", &""))
	if dc == null:
		return {ok = false, error = &"unknown_dc"}
	var task_id: StringName = p.get(&"task_id", &"")
	if dc.busy_with_task_id != task_id:
		return {ok = false, error = &"not_locked_by_this_task"}
	dc.status = &"idle"
	dc.busy_with_task_id = &""
	EventBus.datacenter_status_changed.emit(dc.id, &"training", &"idle")
	return {ok = true}

# ---- phase hooks --------------------------------------------------------

func _on_phase(phase: StringName, _turn: int) -> void:
	match phase:
		&"upkeep":
			_charge_weekly_costs()
			_settle_idle_rentals()
		&"action":
			_advance_construction()

func _on_save_loaded() -> void:
	# _next_dc_seq / _next_construction_seq are session-only counters — they are
	# NOT in OWNED_SLICES, so a fresh load resurrects them at 1. Restore them
	# past the highest id already in use, then repair any duplicate ids a buggy
	# pre-fix save may already contain. Order matters: restore first so the
	# repair mints fresh ids that don't collide again.
	_restore_id_counters()
	_repair_datacenter_ids()
	_migrate_legacy_power()
	for dc in GameState.datacenters:
		# v9 PR-I + 2026-05 bugfix: legacy saves may store either a deleted OS
		# template id or a release id directly on the DC. Valid releases migrate
		# into owned published Models so ProductSystem can expose and price their API.
		if dc.status == &"serving" and dc.serving_target_kind == &"open_source_model":
			var release_id: StringName = dc.serving_target_id
			var materialized: Dictionary = CommandBus.send(&"research.ensure_open_source_release_published", {
				release_id = release_id,
			})
			if materialized.get(&"ok", false):
				var model_id: StringName = StringName(materialized.get(&"model_id", &""))
				Log.info(&"infra", "save_loaded_materialized_os_serving",
					{dc_id = dc.id, release_id = release_id, model_id = model_id})
				dc.serving_target_kind = &"owned_model"
				dc.serving_target_id = model_id
				dc.deployed_model_id = model_id
			else:
				Log.info(&"infra", "save_loaded_drop_legacy_os_serving",
					{dc_id = dc.id, legacy_target_id = release_id,
					error = materialized.get(&"error", &"unknown_release")})
				dc.status = &"idle"
				dc.serving_target_kind = &""
				dc.serving_target_id = &""
				dc.deployed_model_id = &""
				dc.serving_tokens_per_sec = 0.0
		# Full recompute (not just serving capacity): derived compute fields
		# (train_tflops / inference_tflops / cluster_efficiency / facility_weekly_cost)
		# are pure functions of the dc's stored config, so recomputing on load
		# self-heals them against current specs/formulas. In particular this applies
		# the space-tier train_speed_bonus (2026-05) to space DCs already in old saves,
		# not only ones bought/sold after load. _recompute_compute calls
		# _refresh_serving_capacity internally.
		_recompute_compute(dc)
		EventBus.dc_compute_recomputed.emit(
				dc.id, dc.train_tflops, dc.inference_tflops, dc.serving_tokens_per_sec)

## Restore the id sequence counters from whatever ids the loaded save already
## uses, so facilities created after the load never collide with loaded ones.
## `dc_NNNN` ids draw from _next_dc_seq; `dc_owned_NNNN` from _next_construction_seq.
## v11: power supply was cut from 5 options to 2 (grid / green). Remap any
## legacy id on loaded datacenters + construction queue so cost / efficiency
## lookups don't silently fall through to "free electricity" (null spec).
func _migrate_legacy_power() -> void:
	for dc in GameState.datacenters:
		if _LEGACY_POWER_MIGRATION.has(dc.power_supply):
			var mapped: StringName = _LEGACY_POWER_MIGRATION[dc.power_supply]
			Log.info(&"infra", "save_loaded_migrate_power",
				{dc_id = dc.id, old = dc.power_supply, new = mapped})
			dc.power_supply = mapped
	for c in GameState.construction_queue:
		if _LEGACY_POWER_MIGRATION.has(c.power_supply):
			c.power_supply = _LEGACY_POWER_MIGRATION[c.power_supply]

func _restore_id_counters() -> void:
	var max_dc: int = 0
	var max_owned: int = 0
	var all_ids: Array[StringName] = []
	for dc in GameState.datacenters:
		all_ids.append(dc.id)
	for c in GameState.construction_queue:
		all_ids.append(c.id)
	for raw in all_ids:
		var s: String = String(raw)
		if s.begins_with("dc_owned_"):
			max_owned = maxi(max_owned, s.trim_prefix("dc_owned_").to_int())
		elif s.begins_with("dc_"):
			max_dc = maxi(max_dc, s.trim_prefix("dc_").to_int())
	_next_dc_seq = max_dc + 1
	_next_construction_seq = max_owned + 1

## Repair a save that already contains duplicate datacenter ids (the symptom of
## the pre-fix counter-reset bug). find_dc() returns the FIRST match, so a
## collided id silently resolves to the wrong physical dc — the player selects
## an idle 8k cluster but the engine drives a busy 8-card pod. We keep the id on
## the first occurrence (every task lock already resolved to it) and re-id the
## rest with fresh unique ids.
func _repair_datacenter_ids() -> void:
	var seen: Dictionary = {}
	for dc in GameState.datacenters:
		if not seen.has(dc.id):
			seen[dc.id] = true
			continue
		var old_id: StringName = dc.id
		var new_id: StringName
		if String(old_id).begins_with("dc_owned_"):
			new_id = StringName("dc_owned_%04d" % _next_construction_seq)
			_next_construction_seq += 1
		else:
			new_id = StringName("dc_%04d" % _next_dc_seq)
			_next_dc_seq += 1
		dc.display_name = dc.display_name.replace(String(old_id), String(new_id))
		dc.id = new_id
		seen[new_id] = true
		# find_dc() always resolved this id to the FIRST dc, so any task that
		# "owns" this duplicate was really driving the other one. Drop the stale
		# lock so the re-id'd dc is a clean, usable idle asset.
		if dc.busy_with_task_id != &"":
			dc.busy_with_task_id = &""
			if dc.status == &"training":
				dc.status = &"idle"
		Log.warn(&"infra", "save_loaded_duplicate_dc_id_repaired",
			{old_id = old_id, new_id = new_id})

## v4 (PR-B): engineering-tree unlock → recompute every serving dc so the new
## throughput_multiplier / flops_per_token_reduction multipliers are visible
## immediately on dc cards and in MonetizationSystem's API capacity pool.
## arch / application unlocks don't change serving t/s and are ignored.
func _on_tech_unlocked(tree: StringName, _node_id: StringName) -> void:
	if tree != &"engineering":
		return
	for dc in GameState.datacenters:
		if dc.status != &"serving":
			continue
		_refresh_serving_capacity(dc)
		EventBus.dc_compute_recomputed.emit(
				dc.id, dc.train_tflops, dc.inference_tflops, dc.serving_tokens_per_sec)

# === Idle GPU rental (出租到算力平台, 2026-05; design §4.4) ===
const RENT_OUT_FRACTION: float = 0.5    # rent-out price = 50% of (halved) cloud rent
const PLATFORM_FEE_RATE: float = 0.22   # third-party platform management fee

## Weekly electricity per card for a (gpu, power) combo, scaled by the GPU's
## power_factor. Centralized so upkeep charge, cached facility_weekly_cost, and
## ResearchSystem's pricing baseline all agree. Returns a float; cash callers
## round per-card. See design/基础设施系统设计.md §4.2.
func electricity_per_card(gpu, pwr) -> float:
	if gpu == null or pwr == null:
		return 0.0
	var pf: float = float(gpu.power_factor) if "power_factor" in gpu else 1.0
	return float(pwr.weekly_cost_per_card) * pf

## Gross weekly rental for one idle card of `gpu` on the compute platform,
## before the platform management fee. = rent_weekly_cost × RENT_OUT_FRACTION.
func rental_gross_per_card(gpu) -> int:
	if gpu == null:
		return 0
	return int(float(gpu.rent_weekly_cost) * RENT_OUT_FRACTION)

## Net weekly rental (gross − platform fee) for `dc` if settled now, or 0 when it
## isn't an idle owned dc with GPUs. UI display helper; mirrors _settle_idle_rentals
## so cards and actual settlement agree.
func dc_rental_net_weekly(dc) -> int:
	if dc == null or not dc.rent_out_enabled or dc.status != &"idle" \
			or dc.ownership == &"cloud" or dc.gpu_count <= 0:
		return 0
	var gpu: GPUSpec = _load_gpu_spec(dc.gpu_id) if dc.gpu_id != &"" else null
	if gpu == null:
		return 0
	var gross: int = rental_gross_per_card(gpu) * dc.gpu_count
	return gross - int(round(float(gross) * PLATFORM_FEE_RATE))

## Player opt-in toggle: enable/disable renting this dc's idle GPUs to the compute
## platform. Flag persists on the dc; rental only fires while idle (see
## _settle_idle_rentals). Cloud dc can't rent (cards aren't owned).
func _on_set_dc_rent_out(p: Dictionary) -> Dictionary:
	var dc_id: StringName = p.get(&"dc_id", &"")
	var dc: Datacenter = find_dc(dc_id)
	if dc == null:
		return {ok = false, error = &"unknown_dc"}
	if dc.ownership == &"cloud":
		return {ok = false, error = &"cloud_dc_no_rental"}
	dc.rent_out_enabled = bool(p.get(&"enabled", true))
	Log.info(&"infra", "dc_rent_out_set", {dc_id = dc_id, enabled = dc.rent_out_enabled})
	return {ok = true}

## Passive weekly income: idle, non-cloud dc with installed GPUs rents its cards
## to a third-party compute platform. Booked as two ledger lines — gross rental
## income (taxable) + platform management fee (deductible). Fires in upkeep right
## after _charge_weekly_costs so both land before resolve-phase taxation.
func _settle_idle_rentals() -> void:
	var gross_total: int = 0
	for dc in GameState.datacenters:
		# Opt-in (rent_out_enabled): only idle dc whose GPUs you own (owned +
		# rented building) sublet their cards; cloud cards aren't yours.
		if not dc.rent_out_enabled or dc.status != &"idle" \
				or dc.ownership == &"cloud" or dc.gpu_count <= 0:
			continue
		var gpu: GPUSpec = _load_gpu_spec(dc.gpu_id) if dc.gpu_id != &"" else null
		if gpu == null:
			continue
		gross_total += rental_gross_per_card(gpu) * dc.gpu_count
	if gross_total <= 0:
		return
	var fee: int = int(round(float(gross_total) * PLATFORM_FEE_RATE))
	CommandBus.send(&"economy.award", {amount = gross_total, reason = &"gpu_rental_income"})
	if fee > 0:
		CommandBus.send(&"economy.spend",
				{cost = {&"cash": fee}, reason = &"gpu_rental_platform_fee"})
	Log.debug(&"infra", "idle_rentals_settled",
			{gross = gross_total, fee = fee, net = gross_total - fee})

func _charge_weekly_costs() -> void:
	# Per design §6.2 (and 平衡参数.md): upkeep fires every turn = every week,
	# so the field values stored on FacilitySpec / GPUSpec / PowerSupplySpec
	# are per-week amounts.
	# Two split buckets:
	#   facility_total = rent_weekly_cost (rented) or land_weekly_cost (owned)
	#   gpu_runtime_total = (maintenance + electricity) × gpu_count summed
	# Legacy DCs (no facility_spec_id in FACILITY_SPECS) fall back to the old
	# single facility_weekly_cost lump.
	var facility_total: int = 0
	var gpu_runtime_total: int = 0
	var cloud_gpu_total: int = 0
	for dc in GameState.datacenters:
		if dc.ownership == &"cloud":
			var cgpu: GPUSpec = _load_gpu_spec(dc.gpu_id) if dc.gpu_id != &"" else null
			if cgpu != null and dc.gpu_count > 0:
				cloud_gpu_total += cgpu.rent_weekly_cost * dc.gpu_count
			continue
		var fac: FacilitySpec = _load_facility_spec(dc.facility_spec_id)
		if fac != null:
			# Rented facilities pay rent_weekly_cost (includes landlord amortization);
			# owned facilities pay land_weekly_cost only.
			if dc.ownership == &"rented":
				facility_total += fac.rent_weekly_cost
			else:
				facility_total += fac.land_weekly_cost
			var pwr: PowerSupplySpec = _load_power_spec(dc.power_supply)
			var gpu: GPUSpec = _load_gpu_spec(dc.gpu_id) if dc.gpu_id != &"" else null
			if gpu != null and dc.gpu_count > 0:
				# Electricity scales by GPU power_factor (基础设施系统设计.md §4.2).
				var per_card: int = gpu.maintenance_per_week \
						+ int(round(electricity_per_card(gpu, pwr)))
				gpu_runtime_total += per_card * dc.gpu_count
			# v7 PR-F: PowerSupplySpec.fame_modifier path deleted with the fame field.
		else:
			# Legacy spec — use cached lump cost.
			facility_total += int(dc.facility_weekly_cost)
	if facility_total > 0:
		CommandBus.send(&"economy.spend", {
			cost = {&"cash": facility_total},
			reason = &"facility_costs",
		})
	if gpu_runtime_total > 0:
		CommandBus.send(&"economy.spend", {
			cost = {&"cash": gpu_runtime_total},
			reason = &"gpu_runtime_costs",
		})
	if cloud_gpu_total > 0:
		CommandBus.send(&"economy.spend", {
			cost = {&"cash": cloud_gpu_total},
			reason = &"cloud_gpu_costs",
		})
	# v7 PR-F: market.add_fame weekly image-modifier path deleted with fame field.

func _advance_construction() -> void:
	for c in GameState.construction_queue.duplicate():
		c.weeks_remaining -= 1
		EventBus.construction_progress.emit(c.id, c.weeks_remaining, c.total_weeks)
		if c.weeks_remaining <= 0:
			_complete_construction(c)

func _complete_construction(c) -> void:
	var fac_spec: FacilitySpec = _load_facility_spec(c.facility_spec_id)
	if fac_spec == null:
		Log.warn(&"infra", "construction_unknown_spec", {spec = c.facility_spec_id})
		GameState.construction_queue.erase(c)
		return
	var pwr: PowerSupplySpec = _load_power_spec(c.power_supply)
	var dc: Datacenter = _make_dc(fac_spec, pwr, &"owned")
	dc.id = c.id
	GameState.datacenters.append(dc)
	GameState.construction_queue.erase(c)
	# Auto-install pre-paid GPUs (gpu_id stored at build time, cost already charged).
	if c.gpu_id != &"":
		var gpu: GPUSpec = _load_gpu_spec(c.gpu_id)
		if gpu != null and dc.max_gpu_count > 0:
			dc.gpu_id = c.gpu_id
			dc.gpu_count = dc.max_gpu_count
			var batch := GPUBatch.new()
			batch.count = dc.max_gpu_count
			batch.unit_price = gpu.purchase_price
			batch.bought_at_turn = GameState.turn
			dc.gpu_purchase_history.append(batch)
			_recompute_compute(dc)
			Log.info(&"infra", "construction_gpu_auto_installed",
				{dc_id = dc.id, gpu_id = c.gpu_id, count = dc.max_gpu_count})
		else:
			Log.warn(&"infra", "construction_gpu_auto_install_failed",
				{dc_id = dc.id, gpu_id = c.gpu_id})
	EventBus.construction_completed.emit(c.id, dc.id)
	EventBus.datacenter_added.emit(dc.id)
	EventBus.dc_compute_recomputed.emit(dc.id, dc.train_tflops, dc.inference_tflops, dc.serving_tokens_per_sec)

# ---- helpers ------------------------------------------------------------

func find_dc(dc_id: StringName) -> Datacenter:
	for dc in GameState.datacenters:
		if dc.id == dc_id:
			return dc
	return null

func _make_dc(spec: FacilitySpec, pwr: PowerSupplySpec, ownership: StringName) -> Datacenter:
	var dc := Datacenter.new()
	dc.id = StringName("dc_%04d" % _next_dc_seq)
	_next_dc_seq += 1
	# Player-facing name is just the facility tier (e.g. "16 卡机架"); the
	# internal id is kept off the UI — the player only cares about card count.
	dc.display_name = spec.display_name
	dc.facility_spec_id = spec.id
	dc.ownership = ownership
	dc.power_supply = pwr.id if pwr != null else &"grid"
	dc.max_gpu_count = spec.max_gpu_count
	dc.gpu_id = &""
	dc.gpu_count = 0
	dc.gpu_purchase_history = []
	dc.train_tflops = 0.0
	dc.inference_tflops = 0.0
	dc.serving_tokens_per_sec = 0.0
	dc.cluster_efficiency = 0.0
	# Cache correct weekly facility cost based on ownership.
	dc.facility_weekly_cost = spec.rent_weekly_cost if ownership == &"rented" else spec.land_weekly_cost
	dc.status = &"idle"
	return dc

func _recompute_compute(dc: Datacenter) -> void:
	var gpu: GPUSpec = _load_gpu_spec(dc.gpu_id) if dc.gpu_id != &"" else null
	var pwr: PowerSupplySpec = _load_power_spec(dc.power_supply)
	var fac: FacilitySpec = _load_facility_spec(dc.facility_spec_id)
	# Per 招聘系统设计 §1.1 + 平衡参数 §LEAD_BONUS_TABLE: a chief_engineer
	# assigned to a dc adds `cluster_eff_add` (default 0.05 × ability/100)
	# on top of the gpu/power/decay baseline.
	var ce_bonus: float = _chief_engineer_cluster_bonus_for_dc(dc.id)
	if gpu == null or dc.gpu_count <= 0:
		dc.train_tflops = 0.0
		dc.inference_tflops = 0.0
		dc.cluster_efficiency = 0.0
	else:
		var big_cluster_decay: float = clampf(
			1.0 - 0.04 * log(max(dc.gpu_count, 1)) / log(10.0), 0.5, 1.0)
		var pwr_eff: float = pwr.efficiency_modifier if pwr != null else 1.0
		dc.cluster_efficiency = gpu.native_cluster_eff * pwr_eff * big_cluster_decay + ce_bonus
		# gpu.ecosystem_score is the training-throughput multiplier (software /
		# framework maturity). It penalizes TRAINING only — inference_tflops is
		# left unscaled, so a low-ecosystem brand (bamboo) is cheap iron that
		# still serves at full speed but trains slowly. cypress 1.0 / maple 0.8 /
		# bamboo 0.6. See design/基础设施系统设计.md §1.5.
		dc.train_tflops = (gpu.per_card_tflops * float(dc.gpu_count)
				* dc.cluster_efficiency * gpu.ecosystem_score)
		# 太空数据中心训练加速 (2026-05): 真空辐射散热 → 无热降频, 训练吞吐 +10~20%.
		# 只加训练 (train_tflops), 不加推理. bonus 来自 FacilitySpec.train_speed_bonus
		# (地面档 0; space_s/m/l +10/15/20%, planet +20%). 见 §1.5 / §4.1.
		if fac != null and fac.train_speed_bonus > 0.0:
			dc.train_tflops *= (1.0 + fac.train_speed_bonus)
		dc.inference_tflops = gpu.per_card_inference_tflops * float(dc.gpu_count) * dc.cluster_efficiency
	# v3 §6.1.1: serving_tokens_per_sec follows inference_tflops when GPU
	# count changes; save_loaded also reuses this path to repair cached legacy
	# capacities.
	_refresh_serving_capacity(dc)
	# Cache weekly cost too (UI display convenience). Must match what
	# _apply_facility_costs() actually deducts at upkeep:
	#   cloud  → gpu.rent_weekly_cost × count (no facility / power / maint)
	#   rented → fac.rent_weekly_cost + (maint + power) × count
	#   owned  → fac.land_weekly_cost + (maint + power) × count
	if dc.ownership == &"cloud":
		dc.facility_weekly_cost = (gpu.rent_weekly_cost * dc.gpu_count) if gpu != null else 0
	else:
		var land: int = 0
		if fac != null:
			land = fac.rent_weekly_cost if dc.ownership == &"rented" else fac.land_weekly_cost
		var per_card: int = 0
		if gpu != null:
			per_card += gpu.maintenance_per_week + int(round(electricity_per_card(gpu, pwr)))
		dc.facility_weekly_cost = land + per_card * dc.gpu_count

## Sum of `cluster_eff_add` contributions from chief_engineer leads currently
## assigned to this dc. ability scales the bonus linearly per 招聘系统 §1.1.
##
## Lookup is by lead.assigned_to_dc_id, which any future "assign engineer to
## dc" UI should populate. For now this is computed defensively (returns 0.0
## when the field is absent, so legacy code paths see no behavior change).
func _chief_engineer_cluster_bonus_for_dc(dc_id: StringName) -> float:
	var bonus_table: Dictionary = HiringSystem.LEAD_BONUS_TABLE.get(&"chief_engineer", {})
	var coef: float = float(bonus_table.get(&"cluster_eff_add", 0.0))
	if coef <= 0.0:
		return 0.0
	var total: float = 0.0
	for lead in GameState.leads:
		if lead.specialty != &"chief_engineer":
			continue
		var assigned_dc = ""
		if "assigned_to_dc_id" in lead:
			assigned_dc = String(lead.assigned_to_dc_id)
		if assigned_dc != String(dc_id):
			continue
		total += coef * (float(lead.ability) / 100.0)
	return total

## v3 §6.1.1: shared helper used by `_recompute_compute` (during buy/sell while
## serving) and the deploy paths. Looks up flops_per_token for the dc's current
## serving target. Returns 0 when no target / unknown id.
## v9 PR-I: open_source_model id is now an OS NPC release_id; resolve via MarketSystem.
func _flops_per_token_for(kind: StringName, id: StringName) -> float:
	if id == &"":
		return 0.0
	if kind == &"owned_model":
		var m = _find_model(id)
		if m == null:
			return 0.0
		return _normalized_model_fpt(m)
	if kind == &"open_source_model":
		var found: Dictionary = MarketSystem.find_release(id)
		if not found.get(&"ok", false):
			return 0.0
		return _release_flops_per_token(found.release)
	return 0.0

## v4 (PR-B): engineering-tree multipliers are now applied here so dc.serving_tokens_per_sec
## reflects unlocked KV-cache / quantization / FP8 / FP4 effects directly. MonetizationSystem
## reads this value verbatim and no longer multiplies again.
##   serving_t/s = (inference_tflops × throughput_multiplier × 1e12)
##                 / (model.flops_per_token × flops_per_token_reduction)
func _refresh_serving_capacity(dc: Datacenter) -> void:
	if dc.status == &"serving" and dc.serving_target_id != &"":
		var fpt: float = _flops_per_token_for(dc.serving_target_kind, dc.serving_target_id)
		if fpt > 0.0:
			var eng_mults: Dictionary = _engineering_serving_mults()
			var effective_inf: float = float(dc.inference_tflops) * eng_mults.throughput_multiplier
			# 2026-05: 长上下文吞吐惩罚 — 部署模型 ctx 越长, 等效 fpt 越高 → serving t/s 越低.
			var ctx_penalty: float = _context_serving_penalty_for(
					dc.serving_target_kind, dc.serving_target_id)
			var effective_fpt: float = fpt * eng_mults.flops_per_token_reduction * ctx_penalty
			if effective_fpt > 0.0:
				dc.serving_tokens_per_sec = effective_inf * 1.0e12 / effective_fpt
				return
	dc.serving_tokens_per_sec = 0.0

## 2026-05: 部署模型的长上下文吞吐惩罚 (除数). owned 模型按 `context_length_tokens`
## 查表; OS / NPC release 无 ctx 字段, 视作 1.0 (无惩罚).
func _context_serving_penalty_for(kind: StringName, id: StringName) -> float:
	if kind != &"owned_model" or id == &"":
		return 1.0
	var m = _find_model(id)
	if m == null or not ("context_length_tokens" in m):
		return 1.0
	return _context_serving_penalty(int(m.context_length_tokens))

func _context_serving_penalty(tokens: int) -> float:
	if _CONTEXT_SERVING_PENALTY.has(tokens):
		return float(_CONTEXT_SERVING_PENALTY[tokens])
	# 兜底: ctx 子树新增档位但硬编码表未同步时, 查 tech.get_context_tiers 的 serving_penalty.
	var r: Dictionary = CommandBus.send(&"tech.get_context_tiers", {})
	if r.get(&"ok", false):
		for tier in r.get(&"tiers", []):
			if int(tier.get(&"max_tokens", 0)) == tokens:
				return float(tier.get(&"serving_penalty", 1.0))
	return 1.0

## Aggregate the engineering-tree multipliers that affect serving t/s.
## Returns a dict with two fields, defaulted to 1.0 if TechTreeSystem hasn't
## registered (e.g. during early autoload boot or some unit-test harnesses).
func _engineering_serving_mults() -> Dictionary:
	var r: Dictionary = CommandBus.send(&"tech.get_engineering_coefs", {})
	if not r.get(&"ok", false):
		return {throughput_multiplier = 1.0, flops_per_token_reduction = 1.0}
	return {
		throughput_multiplier = float(r.get(&"throughput_multiplier", 1.0)),
		flops_per_token_reduction = float(r.get(&"flops_per_token_reduction", 1.0)),
	}

func _normalized_model_fpt(model) -> float:
	# v4 (PR-B): MoE models declare active_param_ratio; flops_per_token must
	# be 2 × size × active_ratio. Falls back to 1.0 for dense models and legacy
	# saves where the field was not yet present.
	var active_ratio: float = 1.0
	if "active_param_ratio" in model and float(model.active_param_ratio) > 0.0:
		active_ratio = float(model.active_param_ratio)
	var fpt: float = Model.normalize_flops_per_token(
			float(model.flops_per_token), float(model.size_params), active_ratio)
	if fpt > 0.0 and fpt != float(model.flops_per_token):
		model.flops_per_token = fpt
	return maxf(fpt, 1.0)

## v9 PR-I: derive flops_per_token for an NPC release using the same formula
## as player-trained models (2 × size × active_ratio × 1e6). Active ratio comes
## from release.active_params_b / release.params_b (dense → 1.0).
func _release_flops_per_token(release) -> float:
	if release == null:
		return 1.0
	var params_b: float = float(release.params_b)
	if params_b <= 0.0:
		return 1.0
	var active_b: float = float(release.active_params_b)
	var active_ratio: float = 1.0 if active_b <= 0.0 else (active_b / params_b)
	var size_m: float = params_b * 1000.0
	return maxf(Model.infer_flops_per_token(size_m, active_ratio), 1.0)

## v9 PR-I: shared validation chain for OS NPC release lookup. Returns:
##   {ok = true, npc, release}   on success
##   {ok = false, error = ...}   with one of:
##     &"unknown_release" / &"not_open_source" / &"not_pretrain" / &"not_released_yet"
func _resolve_os_release(release_id: StringName) -> Dictionary:
	var found: Dictionary = MarketSystem.find_release(release_id)
	if not found.get(&"ok", false):
		return {ok = false, error = &"unknown_release"}
	var npc = found.npc
	var release = found.release
	if not bool(npc.is_open_source):
		return {ok = false, error = &"not_open_source"}
	if release.release_kind != &"pretrain":
		return {ok = false, error = &"not_pretrain"}
	if int(release.release_turn) > GameState.turn:
		return {ok = false, error = &"not_released_yet"}
	return {ok = true, npc = npc, release = release}

func _load_facility_spec(spec_id: StringName) -> FacilitySpec:
	var path: String = FACILITY_SPECS.get(spec_id, "")
	if path == "":
		return null
	var res := load(path)
	if res is FacilitySpec:
		return res
	return null

## 太空数据中心训练加速: 该机房档位的训练算力乘子加成 (0.0 = 无)。已烘焙进
## dc.train_tflops; UI (infra 卡片 / 预训练 DC 下拉) 用此值单独显示「太空 +N%」。
## 空 id (云租用 DC) / 未知档位 → 0.0。见 design/基础设施系统设计.md §4.1。
func facility_train_bonus(spec_id: StringName) -> float:
	if spec_id == &"":
		return 0.0
	var spec: FacilitySpec = _load_facility_spec(spec_id)
	return spec.train_speed_bonus if spec != null else 0.0

func _load_gpu_spec(gpu_id: StringName) -> GPUSpec:
	if gpu_id == &"":
		return null
	var path: String = GPU_SPECS.get(gpu_id, "")
	if path == "":
		return null
	var res := load(path)
	if res is GPUSpec:
		return res
	return null

func _load_power_spec(pwr_id: StringName) -> PowerSupplySpec:
	if pwr_id == &"":
		return null
	var path: String = POWER_SPECS.get(pwr_id, "")
	if path == "":
		return null
	var res := load(path)
	if res is PowerSupplySpec:
		return res
	return null

func _find_model(model_id: StringName):
	for m in GameState.models:
		if m.id == model_id:
			return m
	return null
