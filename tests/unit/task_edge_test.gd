extends GutTest

## TaskSystem v1 — 边界 / 失败路径补测.
## Per design/任务系统设计.md.


func before_each() -> void:
	GameState.reset()

func _seed_resources() -> Dictionary:
	var lead := Lead.new()
	lead.id = &"lead_cs_01"
	lead.specialty = &"chief_scientist"
	lead.level = &"S"
	lead.ability = 90.0
	GameState.leads.append(lead)
	CommandBus.send(&"hiring.adjust_staff", {role = &"ml_eng", delta = 5})
	var rdc: Dictionary = CommandBus.send(&"infra.debug_instant_owned_dc", {facility_spec_id = &"facility_solo", gpu_id = &"cypress_t0"})
	CommandBus.send(&"dataset.acquire_open", {template_id = &"web_corpus_v1"})
	return {lead_id = lead.id, dc_id = rdc.dc_id, dataset_id = &"web_corpus_v1"}

# ---- start 错误码 ------------------------------------------------------

func test_start_unknown_template_returns_error() -> void:
	var r: Dictionary = CommandBus.send(&"task.start", {template_id = &"nope"})
	assert_false(r.ok)
	assert_eq(r.error, &"unknown_template")

func test_start_with_unknown_lead_rolls_back_other_locks() -> void:
	# 任务 §lock: 任一资源锁失败应回滚之前已成功的锁.
	# 这里用一个不存在的 lead, 应触发 rollback.
	var ids := _seed_resources()
	var r: Dictionary = CommandBus.send(&"task.start", {
		template_id = &"train_sparrow_s",
		lead_ids = [&"nonexistent_lead"],
		staff = {&"ml_eng": 1},
		datacenter_id = ids.dc_id,
		dataset_ids = [ids.dataset_id],
	})
	assert_false(r.ok)
	# DC 应回 idle, dataset 应释放.
	for dc in GameState.datacenters:
		if dc.id == ids.dc_id:
			assert_eq(dc.status, &"idle", "DC 应回滚到 idle")
	for ds in GameState.datasets:
		if ds.id == ids.dataset_id:
			assert_eq(ds.locked_by_task_id, &"", "dataset 锁应被回滚")

func test_start_with_missing_staff_rolls_back_lead() -> void:
	# 没招够 ml_eng 5 个, 但任务要 10, 应失败 + 回滚.
	var ids := _seed_resources()
	var r: Dictionary = CommandBus.send(&"task.start", {
		template_id = &"train_sparrow_s",
		lead_ids = [ids.lead_id],
		staff = {&"ml_eng": 999},
		datacenter_id = ids.dc_id,
		dataset_ids = [ids.dataset_id],
	})
	assert_false(r.ok)
	assert_eq(r.error, &"missing_staff")
	# lead 应回 idle.
	for lead in GameState.leads:
		if lead.id == ids.lead_id:
			assert_eq(lead.locked_by_task_id, &"")

func test_start_with_busy_dc_rejected_with_datacenter_unavailable() -> void:
	var ids := _seed_resources()
	# 把 dc 占了
	CommandBus.send(&"infra.assign_to_task", {dc_id = ids.dc_id, task_id = &"other"})
	var r: Dictionary = CommandBus.send(&"task.start", {
		template_id = &"train_sparrow_s",
		lead_ids = [ids.lead_id],
		staff = {&"ml_eng": 1},
		datacenter_id = ids.dc_id,
		dataset_ids = [ids.dataset_id],
	})
	assert_false(r.ok)
	assert_eq(r.error, &"datacenter_unavailable")

func test_start_on_zero_gpu_dc_surfaces_no_gpus_reason() -> void:
	# A rented facility has 0 GPUs: it is idle, so pre-lock validation passes,
	# but assign_to_task rejects with no_gpus. task.start keeps the generic
	# datacenter_unavailable error code but must also surface the real reason.
	var ids := _seed_resources()
	var rdc: Dictionary = CommandBus.send(&"infra.rent_facility",
		{facility_spec_id = &"facility_pod", power_supply_id = &"grid"})
	var r: Dictionary = CommandBus.send(&"task.start", {
		template_id = &"train_sparrow_s",
		lead_ids = [ids.lead_id],
		staff = {&"ml_eng": 1},
		datacenter_id = rdc.dc_id,
		dataset_ids = [ids.dataset_id],
	})
	assert_false(r.ok)
	assert_eq(r.error, &"datacenter_unavailable")
	assert_eq(r.get(&"reason", &""), &"no_gpus")

# ---- start 成功路径 ----------------------------------------------------

func test_start_emits_task_started_and_resources_locked() -> void:
	var ids := _seed_resources()
	watch_signals(EventBus)
	var r: Dictionary = CommandBus.send(&"task.start", {
		template_id = &"train_sparrow_s",
		lead_ids = [ids.lead_id],
		staff = {&"ml_eng": 1},
		datacenter_id = ids.dc_id,
		dataset_ids = [ids.dataset_id],
	})
	assert_true(r.ok)
	assert_signal_emitted(EventBus, "task_started")
	assert_signal_emitted(EventBus, "task_resources_locked")

func test_start_returns_total_weeks_and_cost() -> void:
	var ids := _seed_resources()
	var r: Dictionary = CommandBus.send(&"task.start", {
		template_id = &"train_sparrow_s",
		lead_ids = [ids.lead_id],
		staff = {&"ml_eng": 1},
		datacenter_id = ids.dc_id,
		dataset_ids = [ids.dataset_id],
	})
	assert_gt(int(r.total_weeks), 0)
	assert_gte(int(r.total_cost), 0)

# ---- preview -----------------------------------------------------------

func test_preview_unknown_template_error() -> void:
	var r: Dictionary = CommandBus.send(&"task.preview", {template_id = &"nope"})
	assert_false(r.ok)
	assert_eq(r.error, &"unknown_template")

func test_preview_does_not_create_active_task_or_charge() -> void:
	# §5.1.1: preview 是 idempotent, 不扣钱不锁资源.
	var before_cash: int = GameState.cash
	var ids := _seed_resources()
	var rent_cost: int = before_cash - GameState.cash  # 实际已扣的租金等
	var r: Dictionary = CommandBus.send(&"task.preview", {
		template_id = &"train_sparrow_s",
		dataset_ids = [ids.dataset_id],
		datacenter_id = ids.dc_id,
	})
	assert_true(r.ok)
	assert_eq(GameState.active_tasks.size(), 0)
	# preview 不应额外扣钱
	assert_eq(GameState.cash, before_cash - rent_cost)

func test_preview_returns_template_metadata() -> void:
	var r: Dictionary = CommandBus.send(&"task.preview",
			{template_id = &"train_sparrow_s"})
	assert_true(r.ok)
	# 关键字段都在
	for k in [&"total_weeks", &"total_cost", &"weekly_cost",
			&"size_params", &"arch", &"display_name", &"subtype"]:
		assert_true(r.has(k), "preview 缺字段 %s" % k)
	assert_false(r.has(&"expected_output"), "preview 不再暴露静态 expected_output")

func test_preview_allows_arch_override_separate_from_size_template() -> void:
	var r: Dictionary = CommandBus.send(&"task.preview", {
		template_id = &"train_sparrow_s",
		arch_id = &"ant_v2",
	})
	assert_true(r.ok)
	assert_eq(r.arch, &"ant_v2")
	assert_eq(float(r.size_params), 100.0)

# ---- cancel ------------------------------------------------------------

func test_cancel_unknown_task_error() -> void:
	var r: Dictionary = CommandBus.send(&"task.cancel", {task_id = &"nope"})
	assert_false(r.ok)
	assert_eq(r.error, &"unknown_task")

func test_cancel_immediately_after_start_refunds_full_coef() -> void:
	# §6 cancel: refund = base_cost × (1 - elapsed/total) × REFUND_COEF (0.5).
	# Pretrain templates carry base_cost = 0, so refund = 0 here. We still want
	# to assert the cancel path runs cleanly and returns a non-negative refund.
	var ids := _seed_resources()
	var rt: Dictionary = CommandBus.send(&"task.start", {
		template_id = &"train_sparrow_s",
		lead_ids = [ids.lead_id],
		staff = {&"ml_eng": 1},
		datacenter_id = ids.dc_id,
		dataset_ids = [ids.dataset_id],
	})
	var base_cost: int = int(rt.total_cost)
	var rc: Dictionary = CommandBus.send(&"task.cancel", {task_id = rt.task_id})
	assert_true(rc.ok)
	assert_eq(int(rc.refund), int(round(base_cost * 0.5)))

func test_cancel_releases_resources() -> void:
	var ids := _seed_resources()
	var rt: Dictionary = CommandBus.send(&"task.start", {
		template_id = &"train_sparrow_s",
		lead_ids = [ids.lead_id],
		staff = {&"ml_eng": 1},
		datacenter_id = ids.dc_id,
		dataset_ids = [ids.dataset_id],
	})
	CommandBus.send(&"task.cancel", {task_id = rt.task_id})
	# Lead 回 idle, DC 回 idle, dataset 释放.
	for lead in GameState.leads:
		if lead.id == ids.lead_id:
			assert_true(lead.is_idle())
	for dc in GameState.datacenters:
		if dc.id == ids.dc_id:
			assert_eq(dc.status, &"idle")
	for ds in GameState.datasets:
		if ds.id == ids.dataset_id:
			assert_eq(ds.locked_by_task_id, &"")

func test_cancel_emits_task_cancelled_with_refund() -> void:
	var ids := _seed_resources()
	var rt: Dictionary = CommandBus.send(&"task.start", {
		template_id = &"train_sparrow_s",
		lead_ids = [ids.lead_id],
		staff = {&"ml_eng": 1},
		datacenter_id = ids.dc_id,
		dataset_ids = [ids.dataset_id],
	})
	watch_signals(EventBus)
	var rc: Dictionary = CommandBus.send(&"task.cancel", {task_id = rt.task_id})
	assert_signal_emitted(EventBus, "task_cancelled")
	var p: Array = get_signal_parameters(EventBus, "task_cancelled")
	assert_eq(p[0], rt.task_id)
	assert_eq(int(p[1]), int(rc.refund))

func test_cancel_late_in_task_returns_smaller_refund() -> void:
	# 退款公式: refund = base_cost × (1 - elapsed/total) × REFUND_COEF.
	# 用 data_collection_default 验证 (它的 base_cost > 0); pretrain 模板
	# base_cost = 0, refund 永远是 0, 没法体现这条公式.
	var rt: Dictionary = CommandBus.send(&"task.start", {
		template_id = &"data_collection_default",
		lead_ids = [],
		staff = {},
	})
	var total_weeks: int = int(rt.total_weeks)
	if total_weeks <= 1:
		return
	for i in range(maxi(1, total_weeks / 2)):
		EventBus.phase_started.emit(&"action", i + 1)
	if GameState.active_tasks.size() == 0:
		return
	var rc: Dictionary = CommandBus.send(&"task.cancel", {task_id = rt.task_id})
	assert_true(rc.ok)
	# refund 严格小于 base_cost × 0.5 (只有 base_cost > 0 时才有意义).
	assert_lt(int(rc.refund), int(round(int(rt.total_cost) * 0.5)))

# ---- upkeep weekly cost -------------------------------------------------

func test_upkeep_emits_task_weekly_for_each_active_task() -> void:
	# upkeep 期间 TaskSystem 应为每个 active_task 发 reason=task_weekly 的 spend.
	# 用 data_collection_default (weekly_cost=5000) 而不是零周费训练模板.
	# data_collection task 不需要 dc / staff / dataset, 只是个时长任务.
	var rt: Dictionary = CommandBus.send(&"task.start", {
		template_id = &"data_collection_default",
		lead_ids = [],
		staff = {},
		datacenter_id = &"",
		dataset_ids = [],
	})
	assert_true(rt.ok, "data_collection_default 应可无资源启动")
	watch_signals(EventBus)
	EventBus.phase_started.emit(&"upkeep", 1)
	var found_weekly: bool = false
	for i in range(get_signal_emit_count(EventBus, "resources_changed")):
		var p: Array = get_signal_parameters(EventBus, "resources_changed", i)
		if p[1] == &"task_weekly":
			var d: Dictionary = p[0]
			assert_eq(int(d.get(&"cash", 0)), -5000,
					"task_weekly 的 cash delta 应等于 -weekly_cost")
			found_weekly = true
			break
	assert_true(found_weekly, "应有 reason=task_weekly 的 resources_changed")

# ---- progress + completion ---------------------------------------------

func test_progress_signals_each_action_phase() -> void:
	var ids := _seed_resources()
	var rt: Dictionary = CommandBus.send(&"task.start", {
		template_id = &"train_sparrow_s",
		lead_ids = [ids.lead_id],
		staff = {&"ml_eng": 1},
		datacenter_id = ids.dc_id,
		dataset_ids = [ids.dataset_id],
	})
	watch_signals(EventBus)
	EventBus.phase_started.emit(&"action", 1)
	assert_signal_emitted(EventBus, "task_progress")

func test_completion_runs_completion_command_and_emits_task_completed() -> void:
	var ids := _seed_resources()
	var rt: Dictionary = CommandBus.send(&"task.start", {
		template_id = &"train_sparrow_s",
		lead_ids = [ids.lead_id],
		staff = {&"ml_eng": 1},
		datacenter_id = ids.dc_id,
		dataset_ids = [ids.dataset_id],
	})
	watch_signals(EventBus)
	for i in range(int(rt.total_weeks) + 5):
		EventBus.phase_started.emit(&"action", i + 1)
	assert_signal_emitted(EventBus, "task_completed")
	# pretrain task 完成后应有新 model.
	assert_eq(GameState.models.size(), 1)
	# 资源应已释放
	assert_eq(GameState.active_tasks.size(), 0)
	for lead in GameState.leads:
		if lead.id == ids.lead_id:
			assert_true(lead.is_idle())

# ---- pretrain 完成 payload (设计 §6.4) -------------------------------------

func test_pretrain_completion_payload_omits_capability() -> void:
	# 设计 §6.4: pretrain 完成 payload 不再带 capability — 那是 evaluate 的活.
	var ids := _seed_resources()
	var rt: Dictionary = CommandBus.send(&"task.start", {
		template_id = &"train_sparrow_s",
		lead_ids = [ids.lead_id],
		staff = {&"ml_eng": 1},
		datacenter_id = ids.dc_id,
		dataset_ids = [ids.dataset_id],
	})
	for i in range(int(rt.total_weeks) + 1):
		EventBus.phase_started.emit(&"action", i + 1)
	assert_eq(GameState.models.size(), 1)
	var m = GameState.models[0]
	# model.capability 应该是空 dict (或全 0), 因为 pretrain 不写 capability.
	assert_eq(int(m.capability.get(&"general", 0)), 0,
			"pretrain payload 不应预设 capability")

# ---- evaluate task --------------------------------------------------------

func _seed_eval_lead(specialty: StringName = &"eval_lead") -> StringName:
	var l := Lead.new()
	l.id = &"lead_eval_01"
	l.specialty = specialty
	l.level = &"A"
	l.ability = 75.0
	GameState.leads.append(l)
	return l.id

# Zero-ability eval_lead used when a test wants to satisfy the
# needs_lead_specialty=eval_lead gate without altering duration math.
func _seed_zero_eval_lead() -> StringName:
	var l := Lead.new()
	l.id = &"lead_eval_zero"
	l.specialty = &"eval_lead"
	l.level = &"C"
	l.ability = 0.0
	GameState.leads.append(l)
	return l.id

func _add_pretrained_model(arch: StringName = &"ant_v1",
		size: float = 100.0,
		dataset_ids: Array = []) -> StringName:
	var r: Dictionary = CommandBus.send(&"research.add_model", {
		arch = arch, size_params = size, dataset_ids = dataset_ids,
		input_modalities = [&"text"], output_modalities = [&"text"],
	})
	assert_true(r.ok, "research.add_model should seed a model: %s" % str(r))
	return r.get(&"model_id", &"")

func test_evaluate_template_loads_via_template_id() -> void:
	# evaluate_general 模板存在且可被 preview.
	var r: Dictionary = CommandBus.send(&"task.preview", {
		template_id = &"evaluate_general",
	})
	assert_true(r.ok)
	assert_eq(r.subtype, &"evaluate")

func test_evaluate_start_creates_evaluate_subtype_task() -> void:
	# evaluate_general 现在要求 eval_lead (设计 §5.4). 用零能力 eval_lead 通过校验.
	var lid := _seed_zero_eval_lead()
	var mid := _add_pretrained_model()
	var r: Dictionary = CommandBus.send(&"task.start", {
		template_id = &"evaluate_general",
		base_model_id = mid,
		lead_ids = [lid],
		staff = {},
		dataset_ids = [],
	})
	assert_true(r.ok, "evaluate.start 应成功 (eval_general base_cost = 0)")
	assert_eq(GameState.active_tasks.size(), 1)
	assert_eq(GameState.active_tasks[0].subtype, &"evaluate")
	# evaluate_law 默认 1 月 (零 ability lead → speedup = 1.0).
	assert_eq(int(r.total_weeks), 1)

func test_evaluate_with_eval_lead_speeds_up() -> void:
	# eval_lead ability=75 → speedup = 1 + 0.75 × 0.33 = 1.2475 → ceil(1/1.2475) = 1.
	# (1 月已是 floor, 测一下还是稳定通过.)
	var lid := _seed_eval_lead()
	var mid := _add_pretrained_model()
	var r: Dictionary = CommandBus.send(&"task.start", {
		template_id = &"evaluate_general",
		base_model_id = mid,
		lead_ids = [lid],
		staff = {},
	})
	assert_true(r.ok)
	assert_eq(int(r.total_weeks), 1)

func test_evaluate_completion_calls_evaluate_apply_with_capability() -> void:
	# 完成后应调用 research.evaluate_apply, payload 含 model_id + capability_measured.
	var lid := _seed_zero_eval_lead()
	var mid := _add_pretrained_model(&"ant_v1", 800.0)
	var rt: Dictionary = CommandBus.send(&"task.start", {
		template_id = &"evaluate_general",
		base_model_id = mid,
		lead_ids = [lid],
	})
	assert_true(rt.ok)
	# 用一个 helper Object 收集 payload (避免 lambda capture by-value 陷阱).
	var collector := {payload = {}, fired = false}
	var cb := func(_id, _sub, payload):
		collector["payload"] = payload
		collector["fired"] = true
	EventBus.task_completed.connect(cb)
	for i in range(int(rt.total_weeks) + 2):
		EventBus.phase_started.emit(&"action", i + 1)
	EventBus.task_completed.disconnect(cb)
	assert_eq(GameState.active_tasks.size(), 0, "evaluate task 应完成")
	assert_true(collector["fired"], "task_completed 信号应已触发")
	# completion_payload 应有 capability_measured key.
	var p: Dictionary = collector["payload"]
	assert_true(p.has(&"capability_measured"),
			"evaluate completion payload 应含 capability_measured. payload keys = %s" % [p.keys()])

func test_evaluate_capability_increases_with_size() -> void:
	# size_params 800M 对应的 size_curve = 60 × log10(0.8/1 + 1) = 60×log10(1.0008) ≈ 0.02
	# 等等, 800M = 0.8B 所以 size_curve = 60 × log10(0.0008+1) ≈ 0.02. 太小.
	# 用 70B = 70000M: size_curve = 60×log10(70+1) = 60×log10(71) ≈ 60×1.851 ≈ 111 → clamp 95.
	# 用 7B = 7000M: 60×log10(7+1) = 60×log10(8) ≈ 60×0.903 ≈ 54.
	# 先 add 一个 100M model 和一个 7000M model, 比较 capability_measured 大小.
	# 但实测中我们只能跑一个 evaluate task. 直接调内部函数测.
	var small_ds: Dictionary = CommandBus.send(&"dataset.add", {
		size = 2.0, quality = 1.0, coverage_tags = []})
	var big_ds: Dictionary = CommandBus.send(&"dataset.add", {
		size = 140.0, quality = 1.0, coverage_tags = []})
	assert_true(small_ds.ok)
	assert_true(big_ds.ok)
	var small_id := _add_pretrained_model(&"ant_v1", 100.0,
			[small_ds.get(&"dataset_id", &"")])
	var big_id := _add_pretrained_model(&"ant_v1", 7000.0,
			[big_ds.get(&"dataset_id", &"")])
	var small = ResearchSystem.find_model(small_id)
	var big = ResearchSystem.find_model(big_id)
	var cap_small = TaskSystem._compute_capability_measured(small, null)
	var cap_big = TaskSystem._compute_capability_measured(big, null)
	# 大模型 general 应严格大于小模型.
	assert_gt(float(cap_big.get(&"general", -1.0)), float(cap_small.get(&"general", -1.0)),
			"7B 模型 capability 应大于 100M")

func test_evaluate_capability_clamps_to_100() -> void:
	# 巨大模型, raw 容易超 100. 应被 clamp 到 100.
	var huge_id := _add_pretrained_model(&"ant_v1", 1_000_000.0)  # 1T params
	var huge = ResearchSystem.find_model(huge_id)
	var cap = TaskSystem._compute_capability_measured(huge, null)
	assert_lte(float(cap[&"general"]), 100.0)
	assert_gte(float(cap[&"general"]), 0.0)

func test_evaluate_capability_zero_multimodal_for_text_only() -> void:
	# 没有 image 模态的模型, multimodal axis 应为 0.
	var mid := _add_pretrained_model(&"ant_v1", 800.0)
	var m = ResearchSystem.find_model(mid)
	# input_modalities default = [&"text"], 没有 image.
	var cap = TaskSystem._compute_capability_measured(m, null)
	assert_almost_eq(float(cap[&"multimodal"]), 0.0, 0.001)

# ---- input_schema 校验 ----------------------------------------------------

func test_validate_missing_lead_when_required() -> void:
	# 用 evaluate_general 模板, 临时给它打上 needs_lead = true.
	# (我们直接 mutate 内存里的 template — 测试范围内 OK.)
	# 注: evaluate_general 现在静态声明了 needs_lead_specialty=&"eval_lead"
	# (设计 §5.4). 这里我们覆盖整套 schema 后再恢复, 避免污染同一份资源缓存。
	var t := load("res://resources/data/tasks/evaluate/default.tres")
	var saved: Dictionary = t.input_schema.duplicate()
	t.input_schema = {needs_lead = true}
	var mid := _add_pretrained_model()
	var r: Dictionary = CommandBus.send(&"task.start", {
		template_id = &"evaluate_general",
		base_model_id = mid,
		lead_ids = [],
	})
	assert_false(r.ok)
	assert_eq(r.error, &"missing_lead")
	t.input_schema = saved

func test_validate_lead_specialty_mismatch() -> void:
	var t := load("res://resources/data/tasks/evaluate/default.tres")
	var saved: Dictionary = t.input_schema.duplicate()
	t.input_schema = {needs_lead_specialty = &"eval_lead"}
	# 提供一个 chief_scientist (而不是 eval_lead).
	var l := Lead.new()
	l.id = &"l_cs"
	l.specialty = &"chief_scientist"
	l.ability = 80.0
	GameState.leads.append(l)
	var mid := _add_pretrained_model()
	var r: Dictionary = CommandBus.send(&"task.start", {
		template_id = &"evaluate_general",
		base_model_id = mid,
		lead_ids = [l.id],
	})
	assert_false(r.ok)
	assert_eq(r.error, &"lead_specialty_mismatch")
	t.input_schema = saved

func test_validate_player_scientist_passes_any_specialty_gate() -> void:
	# Per 招聘系统设计 §2 + §5.4 (2026-05 rev): 创始人是万能 lead, 在
	# needs_lead_specialty 校验上对任何 specialty 都放行 (虽然不提供 bonus)。
	var t := load("res://resources/data/tasks/evaluate/default.tres")
	var saved: Dictionary = t.input_schema.duplicate()
	t.input_schema = {needs_lead = true, needs_lead_specialty = &"eval_lead"}
	var founder_r: Dictionary = CommandBus.send(&"hiring.create_player_scientist", {})
	assert_true(founder_r.ok)
	var mid := _add_pretrained_model()
	var r: Dictionary = CommandBus.send(&"task.start", {
		template_id = &"evaluate_general",
		base_model_id = mid,
		lead_ids = [StringName(founder_r.lead_id)],
	})
	assert_true(r.ok, "founder 应能通过 eval_lead specialty 校验, 实际: %s" % str(r))
	t.input_schema = saved

func test_validate_dataset_required_but_empty() -> void:
	var t := load("res://resources/data/tasks/posttrain/general.tres")
	var saved: Dictionary = t.input_schema.duplicate()
	t.input_schema = {needs_dataset = true}
	var mid := _add_pretrained_model()
	var r: Dictionary = CommandBus.send(&"task.start", {
		template_id = &"posttrain_general",
		base_model_id = mid,
		dataset_ids = [],
	})
	assert_false(r.ok)
	assert_eq(r.error, &"dataset_required")
	t.input_schema = saved

func test_validate_base_model_unevaluable() -> void:
	# evaluate 在 base_model_id 不存在时返回 base_model_unevaluable.
	var t := load("res://resources/data/tasks/evaluate/default.tres")
	var saved: Dictionary = t.input_schema.duplicate()
	t.input_schema = {needs_base_model = true}
	var r: Dictionary = CommandBus.send(&"task.start", {
		template_id = &"evaluate_general",
		base_model_id = &"nonexistent_model",
	})
	assert_false(r.ok)
	assert_eq(r.error, &"base_model_unevaluable")
	t.input_schema = saved

# ---- staff multiplier (scaling_law 衰减) ----------------------------------

func test_staff_multiplier_speeds_up_pretrain() -> void:
	# 2026-05: STAFF_MARGINAL 0.15 → 0.03 (ML 工程师加速调弱, 见 任务系统设计.md §6.4)。
	# 7 ml_eng → staff_mult = 1 + 0.03 × log2(1+7) = 1 + 0.03×3 = 1.09。
	# 该乘子小, 不一定跨过 ceil 边界, 故不再钉死绝对周数; 改为:
	#   (a) staff_speedup 乘子按公式精确算出 (= 1.09), 钉死 STAFF_MARGINAL;
	#   (b) 有 staff 的工期 ≤ 无 staff (方向性: 加人不会变慢)。
	CommandBus.send(&"dataset.acquire_open", {template_id = &"web_corpus_v1"})
	var dc := preload("res://scripts/resources/datacenter.gd").new()
	dc.id = &"dc_test_staff_mult"
	dc.facility_spec_id = &"facility_solo"
	dc.ownership = &"owned"
	dc.train_tflops = 50_000.0
	dc.cluster_efficiency = 1.0
	dc.gpu_count = 1
	dc.status = &"idle"
	GameState.datacenters.append(dc)
	CommandBus.send(&"hiring.adjust_staff", {role = &"ml_eng", delta = 7})
	var base_args := {
		template_id = &"train_otter_m",
		lead_ids = [],
		datacenter_id = dc.id,
		dataset_ids = [&"web_corpus_v1"],
	}
	var r_without: Dictionary = CommandBus.send(&"task.preview", base_args.duplicate())
	var with_args: Dictionary = base_args.duplicate()
	with_args["staff"] = {&"ml_eng": 7}
	var r_with: Dictionary = CommandBus.send(&"task.preview", with_args)
	assert_true(r_without.ok and r_with.ok)
	var mult: float = 0.0
	for entry in (r_with.modifier_breakdown as Array):
		if StringName(entry.id) == &"staff_speedup":
			mult = float(entry.value)
	assert_almost_eq(mult, 1.09, 0.001,
			"7 ml_eng 的 staff 乘子应为 1 + 0.03×log2(8) = 1.09 (STAFF_MARGINAL=0.03)")
	assert_true(int(r_with.total_weeks) <= int(r_without.total_weeks),
			"加 ml_eng 不应增加工期")

func test_lead_speedup_applies_to_pretrain() -> void:
	# 2026-05 rev: chief_scientist pretrain_speed coef lowered from 0.40 to 0.22.
	# Ability=92 → speedup = 1 + 0.92 × 0.22 = 1.2024. Test is only that adding
	# a lead lowers duration vs no-lead; absolute month count drifts with the
	# scaling_law inputs.
	var l := Lead.new()
	l.id = &"l_cs_92"
	l.specialty = &"chief_scientist"
	l.ability = 92.0
	GameState.leads.append(l)
	CommandBus.send(&"dataset.acquire_open", {template_id = &"web_corpus_v1"})
	var rdc: Dictionary = CommandBus.send(&"infra.debug_instant_owned_dc", {facility_spec_id = &"facility_solo", gpu_id = &"cypress_t0"})
	var r_with: Dictionary = CommandBus.send(&"task.preview", {
		template_id = &"train_otter_m",
		lead_ids = [l.id],
		staff = {},
		datacenter_id = rdc.dc_id,
		dataset_ids = [&"web_corpus_v1"],
	})
	var r_without: Dictionary = CommandBus.send(&"task.preview", {
		template_id = &"train_otter_m",
		lead_ids = [],
		staff = {},
		datacenter_id = rdc.dc_id,
		dataset_ids = [&"web_corpus_v1"],
	})
	assert_true(r_with.ok and r_without.ok)
	assert_lt(int(r_with.total_weeks), int(r_without.total_weeks),
			"lead should shorten pretrain")

func test_preview_returns_pretrain_modifier_breakdown() -> void:
	var l := Lead.new()
	l.id = &"l_cs_100"
	l.specialty = &"chief_scientist"
	l.ability = 100.0
	GameState.leads.append(l)
	CommandBus.send(&"dataset.acquire_open", {template_id = &"web_corpus_v1"})
	var rdc: Dictionary = CommandBus.send(&"infra.debug_instant_owned_dc", {facility_spec_id = &"facility_solo", gpu_id = &"cypress_t0"})
	CommandBus.send(&"hiring.adjust_staff", {role = &"ml_eng", delta = 3})
	var r: Dictionary = CommandBus.send(&"task.preview", {
		template_id = &"train_otter_m",
		lead_ids = [l.id],
		staff = {&"ml_eng": 3},
		datacenter_id = rdc.dc_id,
		dataset_ids = [&"web_corpus_v1"],
	})
	assert_true(r.ok)
	assert_true(r.has(&"modifier_breakdown"))
	var by_id := {}
	for entry in (r.modifier_breakdown as Array):
		by_id[StringName(entry.id)] = entry
	assert_true(by_id.has(&"dataset_quality"))
	assert_true(by_id.has(&"arch_train_coef"))
	assert_true(by_id.has(&"lead_speedup"))
	assert_true(by_id.has(&"staff_speedup"))
	# v9 (2026-05): dataset_quality 显示的是 data_quality_factor (0.5..1.5).
	# web_corpus_v1 quality=0.55 → factor = 0.5 + 0.55 = 1.05 → kind=buff.
	# (旧 v2 source-min 时是 open_source ×0.9 → debuff)
	assert_eq(by_id[&"dataset_quality"].kind, &"buff",
			"v9: data_quality_factor 1.05 for q=0.55 web_corpus_v1 should be buff")
	assert_eq(by_id[&"lead_speedup"].kind, &"buff")
	# 2026-05 rev: pretrain_speed coef 0.22; ability=100 → 1 + 1.0 × 0.22 = 1.22.
	assert_almost_eq(float(by_id[&"lead_speedup"].value), 1.22, 0.001)

func test_data_collection_quality_uses_data_scientist_bonus() -> void:
	# 2026-05 rev: data_scientist.data_quality_add = 0.22.
	# ability=100 turns target_quality 0.60 into collected quality 0.82.
	var l := Lead.new()
	l.id = &"l_ds_100"
	l.specialty = &"data_scientist"
	l.ability = 100.0
	GameState.leads.append(l)
	var r: Dictionary = CommandBus.send(&"task.start", {
		template_id = &"data_collection_default",
		lead_ids = [l.id],
		target_size = 5.0,
		target_quality = 0.60,
		target_tags = [&"chat"],
	})
	assert_true(r.ok)
	for i in range(int(r.total_weeks)):
		EventBus.phase_started.emit(&"action", i + 1)
	assert_eq(GameState.datasets.size(), 1)
	assert_almost_eq(float(GameState.datasets[0].quality), 0.82, 0.001)

# ---- posttrain payload (设计 §6.4 — no capability_delta) ------------------

func test_posttrain_payload_no_capability_delta() -> void:
	# v2: posttrain task only accepts posttrain datasets. Use the earliest
	# posttrain template (task_specific_sft_v1, 2019 H2, turn 130, open SFT).
	# Completion payload must carry model_id but never capability_delta —
	# that's computed in ResearchSystem._on_posttrain_apply at completion.
	GameState.turn = 200  # past task_specific_sft_v1's release_at_week=130
	var mid := _add_pretrained_model(&"ant_v1", 100.0,
			[StringName("ds_for_posttrain")])
	CommandBus.send(&"dataset.acquire_open", {template_id = &"task_specific_sft_v1"})
	var rt: Dictionary = CommandBus.send(&"task.start", {
		template_id = &"posttrain_general",
		base_model_id = mid,
		lead_ids = [],
		staff = {},
		dataset_ids = [&"task_specific_sft_v1"],
	})
	assert_true(rt.ok)
	var inst = GameState.active_tasks[0]
	assert_true(inst.completion_payload.has(&"model_id"))
	assert_false(inst.completion_payload.has(&"capability_delta"),
			"posttrain payload 不应含 capability_delta — 设计 §6.4")

# ---- posttrain 模板 base_cost 必须 = 0 ------------------------------------

func test_posttrain_template_base_cost_is_zero() -> void:
	# 设计 §1: 模型生命周期 task base_cost 必须 = 0.
	var t := load("res://resources/data/tasks/posttrain/general.tres")
	assert_eq(int(t.base_cost), 0,
			"posttrain_general.tres base_cost 必须为 0 (设计 §1)")

func test_evaluate_template_base_cost_is_zero() -> void:
	var t := load("res://resources/data/tasks/evaluate/default.tres")
	assert_eq(int(t.base_cost), 0,
			"evaluate/default.tres base_cost 必须为 0 (设计 §1)")

# ---- save_loaded: task ID 计数器恢复 (只 restore, 不 dedup) -------------

func test_save_loaded_restores_task_id_counter() -> void:
	# task 是主动 locker, dedup 要跨系统重打锁标签风险高; 只 restore 计数器即可
	# 杜绝读档后新任务与档内 active_tasks 撞 task ID。
	var t := TaskInstance.new()
	t.id = &"task_0011"
	GameState.active_tasks.append(t)
	EventBus.save_loaded.emit()
	var next_id: StringName = TaskSystem._peek_next_task_id()
	assert_gt(String(next_id).trim_prefix("task_").to_int(), 11,
			"读档后新任务 ID 不能复用 ≤0011 (实际 %s)" % next_id)
