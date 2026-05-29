extends GutTest

## TaskSystem v0 — task.start, monthly progress on phase_started(action),
## fan-out to research.add_model on completion. v0 covers only `pretrain`.

const TEMPLATE_SPARROW_S := &"train_sparrow_s"

func before_each() -> void:
	GameState.reset()

func _start_pretrain() -> Dictionary:
	return CommandBus.send(&"task.start", {template_id = TEMPLATE_SPARROW_S})

# ---- start ---------------------------------------------------------------

func test_start_unknown_template_returns_error() -> void:
	var r: Dictionary = CommandBus.send(&"task.start", {template_id = &"no_such_template"})
	assert_false(r.ok)
	assert_eq(r.error, &"unknown_template")

func test_start_creates_active_task_with_template_metadata() -> void:
	var r: Dictionary = _start_pretrain()
	assert_true(r.ok)
	assert_eq(GameState.active_tasks.size(), 1)
	var inst: TaskInstance = GameState.active_tasks[0]
	assert_eq(inst.template_id, TEMPLATE_SPARROW_S)
	assert_eq(inst.subtype, &"pretrain")
	assert_eq(inst.elapsed_weeks, 0)
	assert_eq(inst.total_weeks, 3)  # gpt_small.tres base_duration

func test_start_charges_base_cost_via_economy() -> void:
	# Per 平衡参数.md §TaskSystem and 任务系统设计.md §1: pretrain templates
	# carry base_cost = 0 — the lock on dataset / dc / lead IS the cost.
	# So `cash` should be unchanged when starting a pretrain task.
	var before: int = GameState.resources[&"money"]
	var r: Dictionary = _start_pretrain()
	assert_true(r.ok)
	assert_eq(GameState.resources[&"money"], before, "pretrain base_cost must be 0")

func test_start_emits_task_started() -> void:
	watch_signals(EventBus)
	var r: Dictionary = _start_pretrain()
	assert_signal_emitted(EventBus, "task_started")
	var params: Array = get_signal_parameters(EventBus, "task_started")
	assert_eq(params[0], r.task_id)
	assert_eq(params[1], &"pretrain")

func test_start_returns_total_months_and_total_cost() -> void:
	# total_cost == template.base_cost (= 0 for pretrain templates).
	var r: Dictionary = _start_pretrain()
	assert_eq(r.total_weeks, 3)
	assert_eq(r.total_cost, 0)

# ---- progress ------------------------------------------------------------

func test_action_phase_advances_elapsed_and_emits_progress() -> void:
	var r: Dictionary = _start_pretrain()
	watch_signals(EventBus)
	EventBus.phase_started.emit(&"action", 1)
	var inst: TaskInstance = GameState.active_tasks[0]
	assert_eq(inst.elapsed_weeks, 1)
	assert_signal_emitted(EventBus, "task_progress")
	var params: Array = get_signal_parameters(EventBus, "task_progress")
	assert_eq(params[0], r.task_id)
	assert_eq(params[1], 1)
	assert_eq(params[2], 3)

func test_other_phases_do_not_advance() -> void:
	_start_pretrain()
	EventBus.phase_started.emit(&"upkeep", 1)
	EventBus.phase_started.emit(&"resolve", 1)
	var inst: TaskInstance = GameState.active_tasks[0]
	assert_eq(inst.elapsed_weeks, 0)

# ---- completion ----------------------------------------------------------

func test_task_completes_after_total_months_action_phases() -> void:
	_start_pretrain()
	for i in range(3):
		EventBus.phase_started.emit(&"action", i + 1)
	assert_eq(GameState.active_tasks.size(), 0)
	assert_eq(GameState.models.size(), 1)

func test_completed_pretrain_produces_model_with_template_metadata() -> void:
	# Per design §6.4: pretrain payload no longer carries `capability` —
	# capability is computed by the evaluate task. The model still gets its
	# arch / size / modalities from the template at pretrain time.
	_start_pretrain()
	for i in range(3):
		EventBus.phase_started.emit(&"action", i + 1)
	var m = GameState.models[0]
	# sparrow_s outputs ant_v1 (per 公共枚举表.md §7 / 平衡参数.md §TaskSystem).
	assert_eq(m.arch, &"ant_v1")
	assert_almost_eq(float(m.size_params), 100.0, 0.001)
	# capability dict starts empty (or all-zero) until evaluate runs.
	# We assert no axis was populated by the pretrain fan-out.
	assert_eq(int(m.capability.get(&"general", 0)), 0,
			"pretrain must not preset capability — that's evaluate's job (§6.4)")

func test_task_completed_signal_fires_on_completion() -> void:
	var r: Dictionary = _start_pretrain()
	watch_signals(EventBus)
	for i in range(3):
		EventBus.phase_started.emit(&"action", i + 1)
	assert_signal_emitted(EventBus, "task_completed")
	var params: Array = get_signal_parameters(EventBus, "task_completed")
	assert_eq(params[0], r.task_id)
	assert_eq(params[1], &"pretrain")

# ---- concurrency / id allocation ----------------------------------------

func test_concurrent_tasks_each_advance_on_action_phase() -> void:
	var r1: Dictionary = _start_pretrain()
	var r2: Dictionary = _start_pretrain()
	assert_ne(r1.task_id, r2.task_id)
	assert_eq(GameState.active_tasks.size(), 2)

	EventBus.phase_started.emit(&"action", 1)
	for inst in GameState.active_tasks:
		assert_eq(inst.elapsed_weeks, 1)

func test_concurrent_tasks_complete_independently_in_order() -> void:
	# Two tasks of equal duration started together must both complete on the
	# same final action phase, producing two models.
	_start_pretrain()
	_start_pretrain()
	for i in range(3):
		EventBus.phase_started.emit(&"action", i + 1)
	assert_eq(GameState.active_tasks.size(), 0)
	assert_eq(GameState.models.size(), 2)

func test_task_ids_are_unique_and_zero_padded() -> void:
	var r1: Dictionary = _start_pretrain()
	var r2: Dictionary = _start_pretrain()
	assert_ne(r1.task_id, r2.task_id)
	# Format contract: "task_NNNN". UI / save code may pattern-match on this.
	assert_true(String(r1.task_id).begins_with("task_"))
	assert_eq(String(r1.task_id).length(), 9)

# ---- payload isolation --------------------------------------------------

func test_completed_model_metadata_is_independent_from_template() -> void:
	# After completion, mutating GameState.models[0].input_modalities must
	# not bleed into the cached TaskTemplate (which is shared via load()).
	_start_pretrain()
	for i in range(3):
		EventBus.phase_started.emit(&"action", i + 1)
	var m = GameState.models[0]
	m.input_modalities.append(&"video")
	# Re-load the template — its modalities must be untouched.
	var template := load("res://resources/data/tasks/pretrain/sparrow_s.tres") as TaskTemplate
	assert_eq(template.output_input_modalities.size(), 1)
	assert_false(template.output_input_modalities.has(&"video"))

# ---- cost on failure ----------------------------------------------------

func test_unknown_template_does_not_charge_money() -> void:
	var before: int = GameState.resources[&"money"]
	var r: Dictionary = CommandBus.send(&"task.start", {template_id = &"no_such_template"})
	assert_false(r.ok)
	assert_eq(GameState.resources[&"money"], before, "no charge on unknown template")
	assert_eq(GameState.active_tasks.size(), 0)

# ---- task.preview (PretrainDialog 用) -----------------------------------
# Per design/任务系统设计.md §5.1.1: 对话框上每次玩家改选项, 都会调 task.preview
# 来刷新"时长 / 成本 / 月度成本 / 模型规格". preview 必须幂等:
# 不锁资源, 不扣费, 不创建 active_task.

func test_preview_unknown_template_returns_error() -> void:
	var r: Dictionary = CommandBus.send(&"task.preview", {template_id = &"no_such"})
	assert_false(r.ok)
	assert_eq(r.error, &"unknown_template")

func test_preview_does_not_charge_money() -> void:
	var before: int = GameState.cash
	var r: Dictionary = CommandBus.send(&"task.preview", {template_id = TEMPLATE_SPARROW_S})
	assert_true(r.ok)
	assert_eq(GameState.cash, before, "preview must not charge")

func test_preview_does_not_create_active_task() -> void:
	var r: Dictionary = CommandBus.send(&"task.preview", {template_id = TEMPLATE_SPARROW_S})
	assert_true(r.ok)
	assert_eq(GameState.active_tasks.size(), 0, "preview must not create task")

func test_preview_does_not_lock_dataset() -> void:
	# Acquire web_corpus_v1 via dataset.acquire_open, then preview gpt_medium
	# referencing that dataset. The dataset must remain unlocked.
	CommandBus.send(&"dataset.acquire_open", {template_id = &"web_corpus_v1"})
	var ds_id: StringName = GameState.datasets[0].id
	var r: Dictionary = CommandBus.send(&"task.preview", {
		template_id = &"train_otter_m",
		dataset_ids = [ds_id],
	})
	assert_true(r.ok)
	assert_eq(GameState.datasets[0].locked_by_task_id, &"",
		"preview must not lock dataset")

func test_preview_returns_template_metadata_for_dialog() -> void:
	# The PretrainDialog displays size, arch, modalities — preview must
	# surface these without the UI having to load .tres directly.
	var r: Dictionary = CommandBus.send(&"task.preview", {template_id = TEMPLATE_SPARROW_S})
	assert_true(r.ok)
	assert_eq(int(r.total_weeks), 3)
	assert_eq(int(r.total_cost), 0, "pretrain templates carry base_cost = 0")
	assert_eq(int(r.monthly_cost), 0)
	assert_almost_eq(float(r.size_params), 100.0, 0.001)
	assert_eq(r.arch, &"ant_v1")
	assert_eq(String(r.display_name), "Train Sparrow-S")
	assert_false(r.has(&"expected_output"),
			"capability is computed by evaluate, not preview metadata")
	assert_eq((r.input_modalities as Array).size(), 1)
	assert_eq((r.output_modalities as Array).size(), 1)

func test_preview_returns_monthly_cost_for_scaling_template() -> void:
	# All pretrain templates carry weekly_cost = 0 per design §1 (cost = locks).
	# Preview must still return the field so the dialog can render the row.
	var r: Dictionary = CommandBus.send(&"task.preview", {template_id = &"train_otter_m"})
	assert_true(r.ok)
	assert_eq(int(r.monthly_cost), 0)

func test_preview_returns_flops_per_token_for_pretrain() -> void:
	# Per design/研究系统设计.md §4.8 + design/任务系统设计.md §4.1: preview
	# must surface flops_per_token so PretrainDialog can show 推理成本/指导价.
	# Formula matches the completion path: infer_flops_per_token(size, active_ratio)
	# / attention_inference_coef. sparrow_s (ant_v1 dense, 100M, mha_baseline) →
	# 2 * 100 * 1.0 * 1e6 / 1.0 = 2e8.
	var r: Dictionary = CommandBus.send(&"task.preview", {template_id = TEMPLATE_SPARROW_S})
	assert_true(r.ok)
	assert_true(r.has(&"flops_per_token"), "preview must return flops_per_token")
	assert_almost_eq(float(r.flops_per_token), 2.0e8, 1.0)

func test_preview_flops_per_token_folds_in_moe_active_ratio() -> void:
	# orca_l uses octopus_v1 (MoE active_ratio = 0.25) at 8000M params.
	# Dense formula would give 2 * 8000 * 1 * 1e6 = 1.6e10; MoE folds in
	# active_ratio to give 2 * 8000 * 0.25 * 1e6 = 4e9.
	var r: Dictionary = CommandBus.send(&"task.preview", {template_id = &"train_orca_l"})
	assert_true(r.ok)
	assert_almost_eq(float(r.flops_per_token), 4.0e9, 1.0)

func test_preview_flops_per_token_divides_by_attention_inference_coef() -> void:
	# When the player picks an attention with inference_coef > 1 (e.g. mqa/gqa
	# reduces KV-cache cost) the per-token compute drops. Use a payload-driven
	# preview to force attention_id, since the legacy fixture templates always
	# default to mha_baseline. With size 100M / arch ant_v1 / mqa, fpt should
	# equal sparrow's fpt / mqa.inference_coef.
	var baseline: Dictionary = CommandBus.send(&"task.preview", {
		template_id = TEMPLATE_SPARROW_S,
		size_params = 100.0,
		arch_id = &"ant_v1",
		attention_id = &"mha_baseline",
	})
	var mqa: Dictionary = CommandBus.send(&"task.preview", {
		template_id = TEMPLATE_SPARROW_S,
		size_params = 100.0,
		arch_id = &"ant_v1",
		attention_id = &"mqa",
	})
	assert_true(baseline.ok and mqa.ok)
	assert_gt(float(baseline.flops_per_token), float(mqa.flops_per_token),
			"mqa (inference_coef > 1) must reduce flops_per_token")

func test_preview_flops_per_token_zero_for_non_pretrain() -> void:
	# Non-pretrain templates (posttrain / evaluate / data_collection / tech)
	# don't have a flops_per_token concept — preview should return 0.
	var r: Dictionary = CommandBus.send(&"task.preview", {template_id = &"posttrain_general"})
	assert_true(r.ok)
	assert_almost_eq(float(r.flops_per_token), 0.0, 0.001)

func test_preview_total_months_matches_start_for_same_inputs() -> void:
	# When given the same inputs, preview and start must agree on duration.
	# This is the contract the dialog relies on for trustworthy estimates.
	CommandBus.send(&"dataset.acquire_open", {template_id = &"web_corpus_v1"})
	var ds_id: StringName = GameState.datasets[0].id
	var rdc: Dictionary = CommandBus.send(&"infra.debug_instant_owned_dc", {facility_spec_id = &"facility_solo", gpu_id = &"cypress_t0"})
	var inputs := {
		template_id = &"train_otter_m",
		datacenter_id = rdc.dc_id,
		dataset_ids = [ds_id],
	}
	var preview: Dictionary = CommandBus.send(&"task.preview", inputs)
	var started: Dictionary = CommandBus.send(&"task.start", inputs)
	assert_true(preview.ok)
	assert_true(started.ok)
	assert_eq(int(preview.total_weeks), int(started.total_weeks))
