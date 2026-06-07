extends Node

## TaskSystem v1 — owns active_tasks. Per design/任务系统设计.md.
##
## Implements all five subtypes (pretrain / posttrain / evaluate /
## data_collection / tech_research). Resource locking + rollback on lock
## failure; weekly_cost charged on upkeep; completion fan-out via CommandBus.
##
## Per design §1: pretrain / posttrain / evaluate templates have base_cost = 0
## (resource lock IS the cost). Only data_collection / tech_research can carry
## a positive base_cost.
##
## Per design §6.4: completion payloads NEVER carry capability data — capability
## is computed by the evaluate task only (see _compute_capability_measured).

const TEMPLATES: Dictionary = {
	# Unified pretrain template — player picks arch + size in PretrainDialog,
	# template carries only the duration_func + error rate. Per
	# design/任务系统设计.md §5.1.1 (revised) and 平衡参数.md §TaskSystem.
	&"pretrain_model": "res://resources/data/tasks/pretrain/pretrain_model.tres",
	# Legacy fixed-size pretrain templates — kept for backward compatibility
	# with existing tests and saves; PretrainDialog no longer surfaces them.
	&"train_sparrow_s": "res://resources/data/tasks/pretrain/sparrow_s.tres",
	&"train_otter_m": "res://resources/data/tasks/pretrain/otter_m.tres",
	&"train_orca_l": "res://resources/data/tasks/pretrain/orca_l.tres",
	&"train_elephant_mm": "res://resources/data/tasks/pretrain/elephant_mm.tres",
	&"posttrain_general": "res://resources/data/tasks/posttrain/general.tres",
	# v2 unified posttrain template (PosttrainDialog uses this).
	&"posttrain_model": "res://resources/data/tasks/posttrain/posttrain_model.tres",
	&"evaluate_general": "res://resources/data/tasks/evaluate/default.tres",
	&"data_collection_default": "res://resources/data/tasks/data_collection/default.tres",
	# v2.1: dynamic-cost data_collection used by DatasetCollectionDialog. base_cost
	# / weekly_cost / duration computed from kind+size in start payload via
	# _data_collection_pricing. See design/数据集系统设计.md §5.1ter.
	&"data_collection_dynamic": "res://resources/data/tasks/data_collection/dynamic.tres",
	&"tech_research_default": "res://resources/data/tasks/tech_research/default.tres",
	# Charity donation (design/慈善系统设计.md §5). Dynamic base_cost (= donation
	# amount) + dynamic duration (= tier weeks), both from the start payload.
	# No resource locks; CharitySystem launches it via charity.start_donation.
	&"charity_project": "res://resources/data/tasks/charity/charity_project.tres",
	# Universe-simulation capstone stage (慈善三期). Reuses charity_law (payload
	# amount + weeks). Per design/宇宙模拟工程设计.md §5.
	&"simulation_stage": "res://resources/data/tasks/simulation/simulation_stage.tres",
}

const REFUND_COEF: float = 0.5

# Scaling-law constants. Per 平衡参数.md §TaskSystem and 任务系统设计.md §6.6.1:
# Chinchilla compute = 6 × params × tokens (FLOPs). The duration divisor uses
# canonical `dc.train_tflops` plus model/lead/staff multipliers.
const SCALING_LAW_FLOPS_C: float = 6.0
const SCALING_LAW_QUALITY_FLOOR: float = 0.05

# Posttrain / evaluate constants. Per 平衡参数.md §TaskSystem.
# POSTTRAIN_RATIO (legacy posttrain_law ratio) 已废弃 (v2 posttrain_fixed_tier 替代).
const EVAL_BASE_WEEKS: int = 1
## 2026-05: 0.15 → 0.03. ML 工程师对预训练吞吐的边际加成调弱 —— 现实里训练
## 速度主要受 GPU 算力上限约束, 工程师只做效率优化, 不该让"多招人"成为压缩
## 工期的主力杠杆 (10 人原本 +52% 太离谱, 现约 +10%)。
const STAFF_MARGINAL: float = 0.03
# v12 (2026-05): posttrain 时长在档位基础周数上再加 floor(Σtoken / 此值) 周。
# 每 1B 后训练 token 多占 1 周集群; 正常 SFT 单跑 (≤0.5B) +0。Per 任务系统设计.md §6.2.
const POSTTRAIN_TOKENS_PER_WEEK_B: float = 1.0

# Chinchilla data_efficiency constants. Per 任务系统设计.md §6.7.1.
const CHINCHILLA_OPTIMAL_RATIO: float = 20.0      # tokens per param
const CHINCHILLA_UNDERTRAIN_EXP: float = 0.28     # loss exponent β (paper)
const CHINCHILLA_OVERTRAIN_SLOPE: float = 0.05    # log10 slope above optimal
const CHINCHILLA_EFFICIENCY_CAP: float = 1.10     # hard ceiling on the multiplier

# v9 (2026-05) Pretrain 数据配比公式. Per 平衡参数.md §DatasetSystem 公式 +
# 任务系统设计.md §6.7. 替代 v8 的 source min 乘子 + count-based tag ratio.
# - data_quality_factor = clamp(DATA_QUALITY_FACTOR_FLOOR + weighted_q,
#                               DATA_QUALITY_FACTOR_FLOOR, DATA_QUALITY_FACTOR_CAP)
#   where weighted_q = Σ(d.size × d.quality) / Σ(d.size).
# - tag_ratio = log(1 + TAG_RATIO_LOG_K × share) / log(1 + TAG_RATIO_LOG_K)
#   where share = Σ(d.size × d.quality | d has tag) / Σ(d.size × d.quality).
# - data_breadth_factor = DATA_BREADTH_MIN_FACTOR..1.0 based on broad general
#   knowledge share. Prevents pure code/reasoning data from replacing the
#   language/world-knowledge substrate of real pre-training mixes.
const TAG_RATIO_LOG_K: float = 20.0
const DATA_QUALITY_FACTOR_FLOOR: float = 0.5
const DATA_QUALITY_FACTOR_CAP: float = 1.5
const DATA_BREADTH_TARGET_SHARE: float = 0.45
const DATA_BREADTH_MIN_FACTOR: float = 0.65
const GENERAL_DATA_TAGS: Array[StringName] = [
	&"web", &"books", &"encyclopedia", &"edu", &"news", &"arxiv",
	&"multilingual", &"textbook", &"chat",
]
const BUSINESS_ANALYSIS_TAG: StringName = &"business_analysis"
const BUSINESS_ANALYSIS_CODE_MIN_FACTOR: float = 0.96
const BUSINESS_ANALYSIS_REASONING_MIN_FACTOR: float = 0.97
const BUSINESS_ANALYSIS_AGENT_MIN_FACTOR: float = 0.95

# Per-arch capability coefficient (multiplicative on raw evaluate score).
# Authoritative: 平衡参数.md §evaluate产出 (`arch_capability_coef`).
const ARCH_CAPABILITY_COEF: Dictionary = {
	&"ant_v1": 1.00,
	&"ant_v2": 1.05,
	&"bee_v1": 1.05,
	&"octopus_v1": 1.10,
	&"octopus_v2": 1.15,
	&"spider_v1": 1.05,
}

const OWNED_SLICES: Array[StringName] = [&"active_tasks"]

var _next_task_seq: int = 1

func _ready() -> void:
	CommandBus.register(&"task.start", _on_start)
	CommandBus.register(&"task.cancel", _on_cancel)
	CommandBus.register(&"task.preview", _on_preview)
	EventBus.phase_started.connect(_on_phase)
	EventBus.save_loaded.connect(_on_save_loaded)

# ---- start --------------------------------------------------------------

func _on_start(p: Dictionary) -> Dictionary:
	var template: TaskTemplate = _load_template(p.get(&"template_id", &""))
	if template == null:
		return {ok = false, error = &"unknown_template"}

	# Input-schema validation (cheap, before any locks).
	var verr: StringName = _validate(template, p)
	if verr != &"":
		return {ok = false, error = verr}

	var locked := {leads = [], staff = [], dc = &"", datasets = []}
	# Lock leads.
	for lead_id in (p.get(&"lead_ids", []) as Array):
		var r: Dictionary = CommandBus.send(&"hiring.lock_lead", {
			lead_id = lead_id, task_id = _peek_next_task_id(),
		})
		if not r.ok:
			_rollback(locked)
			return {ok = false, error = (&"lead_busy" if r.error == &"already_locked" or r.error == &"already_assigned" else r.error)}
		locked.leads.append(lead_id)
	# Lock staff. data_collection scales data_eng with size (2..8) and is
	# authoritative — lock the computed requirement, not whatever the caller sent.
	var staff: Dictionary = p.get(&"staff", {})
	if template.subtype == &"data_collection":
		staff = _required_staff(template, p)
	for role in staff.keys():
		var count: int = int(staff[role])
		var r: Dictionary = CommandBus.send(&"hiring.lock_staff", {
			role = role, count = count, holder_id = _peek_next_task_id(),
		})
		if not r.ok:
			_rollback(locked)
			return {ok = false, error = &"missing_staff"}
		locked.staff.append({role = role, count = count})
	# Lock datacenter.
	var dc_id: StringName = p.get(&"datacenter_id", &"")
	if dc_id != &"":
		var r: Dictionary = CommandBus.send(&"infra.assign_to_task", {
			dc_id = dc_id, task_id = _peek_next_task_id(),
		})
		if not r.ok:
			_rollback(locked)
			var dc_reason: StringName = r.get(&"error", &"unknown")
			Log.warn(&"tasks", "task_start_datacenter_unavailable",
				{dc_id = dc_id, reason = dc_reason})
			return {ok = false, error = &"datacenter_unavailable", reason = dc_reason}
		locked.dc = dc_id
	# Lock datasets.
	for ds_id in (p.get(&"dataset_ids", []) as Array):
		var r: Dictionary = CommandBus.send(&"dataset.lock", {
			dataset_id = ds_id, task_id = _peek_next_task_id(),
		})
		if not r.ok:
			_rollback(locked)
			return r
		locked.datasets.append(ds_id)

	# Charge base_cost (only data_collection / some tech_research are > 0;
	# pretrain/posttrain/evaluate are always 0). On failure we roll back.
	# v2.1: data_collection_law templates compute base_cost dynamically from
	# kind + target_size in payload (see _resolve_base_cost).
	var resolved_base_cost: int = _resolve_base_cost(template, p)
	if resolved_base_cost > 0:
		# Charity donations carry their own ledger reason so the financial report
		# lists them as charity (not generic task_start). Both reasons are
		# tax-deductible (neither is in EconomySystem.NON_TAXABLE_REASONS).
		# Per design/慈善系统设计.md §5.
		var start_reason: StringName = &"task_start"
		if template.subtype == &"charity":
			start_reason = &"charity_donation"
		elif template.subtype == &"simulation":
			start_reason = &"simulation_funding"
		var sr: Dictionary = CommandBus.send(&"economy.spend", {
			cost = {&"cash": resolved_base_cost},
			reason = start_reason,
		})
		if not sr.ok:
			_rollback(locked)
			return {ok = false, error = sr.get(&"error", &"insufficient_cash")}

	# Instantiate.
	var inst := TaskInstance.new()
	inst.id = _consume_next_task_id()
	inst.template_id = template.id
	inst.subtype = template.subtype
	inst.started_at_turn = GameState.turn
	inst.total_weeks = _resolve_duration(template, p)
	inst.elapsed_weeks = 0
	var typed_leads: Array[StringName] = []
	for l in locked.leads:
		typed_leads.append(StringName(l))
	inst.locked_lead_ids = typed_leads
	inst.locked_staff = staff.duplicate()
	inst.locked_datacenter_id = StringName(locked.dc)
	var typed_ds: Array[StringName] = []
	for d in locked.datasets:
		typed_ds.append(StringName(d))
	inst.locked_dataset_ids = typed_ds
	inst.base_model_id = StringName(p.get(&"base_model_id", &""))
	inst.completion_command = _resolve_completion_command(template.subtype)
	inst.completion_payload = _resolve_completion_payload(template, p, inst)
	# v2.1: stash dynamic costs so upkeep / cancel-refund don't have to re-derive
	# from completion_payload (which has String keys after save/load).
	inst.base_cost_override = resolved_base_cost
	inst.weekly_cost_override = _resolve_weekly_cost(template, p)

	GameState.active_tasks.append(inst)
	Log.info(&"tasks", "task started", {id = inst.id, subtype = inst.subtype, total = inst.total_weeks})
	EventBus.task_started.emit(inst.id, inst.subtype)
	EventBus.task_resources_locked.emit(inst.id, {
		leads = locked.leads, staff = locked.staff,
		datacenter_id = locked.dc, datasets = locked.datasets,
	})
	return {
		ok = true,
		task_id = inst.id,
		total_weeks = inst.total_weeks,
		total_cost = resolved_base_cost,
	}

# ---- preview / cancel ---------------------------------------------------

func _on_preview(p: Dictionary) -> Dictionary:
	# Idempotent: only loads the template + computes duration. No charges,
	# no resource locks, no active_task creation. PretrainDialog calls this
	# on every input change to refresh its preview row.
	# Per design/任务系统设计.md §5.1.1.
	var template: TaskTemplate = _load_template(p.get(&"template_id", &""))
	if template == null:
		return {ok = false, error = &"unknown_template"}
	# Reflect payload overrides in preview output so PretrainDialog shows the
	# real numbers as the player adjusts inputs.
	var preview_size: float = float(p.get(&"size_params", 0.0))
	if preview_size <= 0.0:
		preview_size = template.output_size_params
	var preview_name: String = String(p.get(&"display_name", ""))
	if preview_name == "":
		preview_name = template.display_name
	# Predicted capability: only meaningful for pretrain. Per design §5.1.1,
	# evaluate-time math but with posttrain_count=0 + eval_lead=null.
	var predicted_capability: Dictionary = {}
	var preview_fpt: float = 0.0
	if template.subtype == &"pretrain":
		predicted_capability = _preview_capability_for_pretrain(template, p, preview_size)
		# Per design/研究系统设计.md §4.8: PretrainDialog needs flops_per_token
		# so it can feed `research.preview_pricing` and show 推理成本/指导价
		# as the player adjusts arch/size/attention/MoE. Formula must match
		# the completion path (see task_system.gd:837).
		var preview_arch: StringName = _template_arch(template, p)
		var preview_active_ratio: float = _active_param_ratio(preview_arch)
		var preview_attn: StringName = StringName(p.get(&"attention_id", &"mha_baseline"))
		var preview_attn_inf: float = _attention_inference_coef(preview_attn)
		if preview_attn_inf <= 0.0:
			preview_attn_inf = 1.0
		preview_fpt = Model.infer_flops_per_token(preview_size, preview_active_ratio) / preview_attn_inf
	# v7 PR-G: respect payload-provided input_modalities for preview echo.
	var preview_in_mods: Array = p.get(&"input_modalities", [])
	if preview_in_mods.is_empty():
		preview_in_mods = template.output_input_modalities.duplicate()
	return {
		ok = true,
		total_weeks = _resolve_duration(template, p),
		total_cost = _resolve_base_cost(template, p),
		weekly_cost = _resolve_weekly_cost(template, p),
		modifier_breakdown = _modifier_breakdown(template, p),
		predicted_capability = predicted_capability,
		flops_per_token = preview_fpt,
		size_params = preview_size,
		arch = _template_arch(template, p),
		input_modalities = preview_in_mods,
		output_modalities = template.output_output_modalities.duplicate(),
		display_name = preview_name,
		subtype = template.subtype,
	}

# Build a stub Model from the pretrain payload and run it through the real
# evaluate formula. Keeps prediction and post-evaluate math in lockstep — any
# tweak to _compute_capability_measured is automatically reflected here.
func _preview_capability_for_pretrain(template: TaskTemplate,
		p: Dictionary, size_m: float) -> Dictionary:
	if size_m <= 0.0:
		return {general = 0.0, code = 0.0, reasoning = 0.0, multimodal = 0.0, agent = 0.0}
	var stub_class := preload("res://scripts/resources/model.gd")
	var stub = stub_class.new()
	stub.id = &"__preview__"
	stub.arch = _template_arch(template, p)
	stub.size_params = size_m
	var typed_ds: Array[StringName] = []
	for d in (p.get(&"dataset_ids", []) as Array):
		typed_ds.append(StringName(d))
	stub.dataset_ids = typed_ds
	# v7 PR-G: PretrainDialog can pass input_modalities to override template default.
	var stub_in_mods: Array = p.get(&"input_modalities", [])
	var stub_in_typed: Array[StringName] = []
	for im in stub_in_mods:
		stub_in_typed.append(StringName(im))
	if stub_in_typed.is_empty():
		stub_in_typed = template.output_input_modalities.duplicate()
	stub.input_modalities = stub_in_typed
	stub.output_modalities = template.output_output_modalities.duplicate()
	# v7 PR-G: forward D-axis (context_length_tokens) + E-axis (multimodal_method)
	# from preview payload so PretrainDialog's predicted_capability already
	# reflects context agent_bonus + multimodal_method coef.
	stub.context_length_tokens = int(p.get(&"context_length_tokens", 4096))
	stub.multimodal_method = StringName(p.get(&"multimodal_method", &"none"))
	stub.posttrain_count = 0
	# 让预览的 predicted_capability 已反映科学家训练加分 (与完成时烘焙的一致)。
	stub.pretrain_score_mult = _resolve_lead_score_mult(
			p.get(&"lead_ids", []), &"pretrain_score_bonus")
	return _compute_capability_measured(stub, null)

func _on_cancel(p: Dictionary) -> Dictionary:
	var task_id: StringName = p.get(&"task_id", &"")
	var inst: TaskInstance = _find(task_id)
	if inst == null:
		return {ok = false, error = &"unknown_task"}
	_release_locks(inst)
	var template: TaskTemplate = _load_template(inst.template_id)
	var refund: int = 0
	if template != null and inst.total_weeks > 0:
		# v2.1: prefer per-instance base_cost_override (set for dynamic-cost
		# templates like data_collection_law). 0 means "use template default".
		var base_for_refund: int = (inst.base_cost_override
				if inst.base_cost_override > 0
				else int(template.base_cost))
		refund = int(round(float(base_for_refund)
			* (1.0 - float(inst.elapsed_weeks) / float(inst.total_weeks))
			* REFUND_COEF))
	if refund > 0:
		CommandBus.send(&"economy.award", {amount = refund, reason = &"task_cancel_refund"})
	GameState.active_tasks.erase(inst)
	EventBus.task_cancelled.emit(inst.id, refund)
	EventBus.task_resources_released.emit(inst.id, {})
	return {ok = true, refund = refund}

# ---- phase hooks --------------------------------------------------------

func _on_phase(phase: StringName, _turn: int) -> void:
	match phase:
		&"upkeep":
			_charge_weekly()
		&"action":
			_advance_progress()

func _charge_weekly() -> void:
	for inst in GameState.active_tasks:
		var template: TaskTemplate = _load_template(inst.template_id)
		if template == null:
			continue
		# v2.1: weekly_cost_override (set at start for dynamic-cost templates)
		# wins over the template's static weekly_cost. 0 = no override.
		var weekly: int = (inst.weekly_cost_override
			if inst.weekly_cost_override > 0
			else int(template.weekly_cost))
		if weekly > 0:
			CommandBus.send(&"economy.spend", {
				cost = {&"cash": weekly},
				reason = &"task_weekly",
			})

func _advance_progress() -> void:
	for inst in GameState.active_tasks.duplicate():
		var template: TaskTemplate = _load_template(inst.template_id)
		if template != null and template.error_rate_per_week > 0.0:
			if GameState.rng().randf() < template.error_rate_per_week:
				inst.total_weeks += 1
				EventBus.task_delayed.emit(inst.id, inst.total_weeks)
				Log.info(&"tasks", "task delayed", {
					id = inst.id, new_total = inst.total_weeks,
				})
		inst.elapsed_weeks += 1
		EventBus.task_progress.emit(inst.id, inst.elapsed_weeks, inst.total_weeks)
		if inst.elapsed_weeks >= inst.total_weeks:
			_complete(inst)

# ---- completion ---------------------------------------------------------

func _complete(inst: TaskInstance) -> void:
	GameState.active_tasks.erase(inst)
	# For evaluate tasks we recompute capability_measured at completion time so
	# the formula sees the current dataset / posttrain / lead state, not the
	# state at task.start. Done BEFORE releasing locks so eval_lead is still
	# locked-in (purely informational here; the formula doesn't read lock).
	if inst.subtype == &"evaluate":
		inst.completion_payload = _resolve_evaluate_payload_late(inst)
	_release_locks(inst)
	if inst.completion_command != &"":
		var r: Dictionary = CommandBus.send(inst.completion_command, inst.completion_payload)
		if not r.ok:
			Log.error(&"tasks", "completion command failed", {
				id = inst.id, command = inst.completion_command, error = r.get(&"error", &"")
			})
	Log.info(&"tasks", "task completed", {id = inst.id, subtype = inst.subtype})
	EventBus.task_completed.emit(inst.id, inst.subtype, inst.completion_payload)

# ---- input validation ---------------------------------------------------

# Per design §6.1: cheap pre-lock validation. Returns &"" on success or an
# error code consumed by the caller.
func _validate(template: TaskTemplate, p: Dictionary) -> StringName:
	var schema: Dictionary = template.input_schema
	var lead_ids: Array = p.get(&"lead_ids", [])
	# Lead requirement.
	if bool(schema.get(&"needs_lead", false)) and lead_ids.is_empty():
		return &"missing_lead"
	# Specialty requirement. Per 招聘系统设计 §2 (2026-05): player_scientist 万能匹配.
	var needs_spec: StringName = schema.get(&"needs_lead_specialty", &"")
	if needs_spec != &"":
		if lead_ids.is_empty():
			return &"missing_lead"
		var first_lead = HiringSystem.find_lead(StringName(lead_ids[0]))
		if first_lead == null:
			return &"missing_lead"
		if not HiringSystem.lead_matches_specialty(first_lead, needs_spec):
			return &"lead_specialty_mismatch"
	# Staff requirement (v8). data_collection hard-requires data engineers scaling
	# with size (2..8); task_system locks the computed amount so the caller need
	# not pre-specify. Other templates' static needs_staff must be supplied in the
	# payload. Either way the pool must have enough idle.
	var needs_staff: Dictionary = _required_staff(template, p)
	var data_collection_staff: bool = template.subtype == &"data_collection"
	for role in needs_staff.keys():
		var need: int = int(needs_staff[role])
		var idle: int = int(GameState.staff_pool.get(role, 0)) \
				- int(GameState.staff_busy.get(role, 0))
		if idle < need:
			return &"missing_staff"
		if not data_collection_staff:
			var supplied: int = int((p.get(&"staff", {}) as Dictionary).get(role, 0))
			if supplied < need:
				return &"missing_staff"
	# Datacenter requirement.
	if bool(schema.get(&"needs_dc", false)):
		var dc_id: StringName = p.get(&"datacenter_id", &"")
		if dc_id == &"":
			return &"datacenter_unavailable"
		var dc = _find_dc(dc_id)
		if dc == null or dc.status != &"idle":
			return &"datacenter_unavailable"
	# Dataset requirement.
	if bool(schema.get(&"needs_dataset", false)):
		var dsids: Array = p.get(&"dataset_ids", [])
		if dsids.is_empty():
			return &"dataset_required"
		# v2: pretrain tasks only accept pretrain datasets; posttrain tasks only
		# accept posttrain datasets. Per 任务系统设计 §6.6.1 / §6.6.2 v2.
		var required_kind: StringName = &""
		match template.subtype:
			&"pretrain": required_kind = &"pretrain"
			&"posttrain": required_kind = &"posttrain"
		for ds_id in dsids:
			var ds = _find_dataset(StringName(ds_id))
			if ds == null:
				return &"dataset_required"
			if ds.locked_by_task_id != &"":
				return &"dataset_locked"
			if required_kind != &"" and ds.kind != required_kind:
				return &"dataset_kind_mismatch"
	# v7 PR-G: pretrain dataset.modality ⊂ model.input_modalities ∪ {text}.
	# Validated independently of `needs_dataset` since the pretrain template
	# doesn't set that flag but still receives dataset_ids from PretrainDialog.
	# text is always allowed (any model needs a text backbone).
	if template.subtype == &"pretrain":
		var pretrain_dsids: Array = p.get(&"dataset_ids", [])
		if not pretrain_dsids.is_empty():
			var allowed_modalities: Dictionary = {&"text": true}
			for m in p.get(&"input_modalities", []):
				allowed_modalities[StringName(m)] = true
			for ds_id in pretrain_dsids:
				var ds = _find_dataset(StringName(ds_id))
				if ds == null:
					continue
				var ds_mod: StringName = &"text"
				if "modality" in ds and StringName(ds.modality) != &"":
					ds_mod = StringName(ds.modality)
				if not allowed_modalities.has(ds_mod):
					return &"dataset_modality_mismatch"
	# Base model requirement (posttrain / evaluate).
	if bool(schema.get(&"needs_base_model", false)):
		var bm_id: StringName = p.get(&"base_model_id", &"")
		if bm_id == &"":
			return &"base_model_unevaluable"
		var bm = _find_model(bm_id)
		if bm == null:
			return &"base_model_unevaluable"
		# For posttrain: cannot run on already-published model.
		if template.subtype == &"posttrain" and String(bm.status) == "published":
			return &"base_model_already_published"
		# v2 posttrain: validate datacenter has enough GPUs for the size tier.
		# Legacy DCs (rent_dc / build_dc) carry gpu_count=0 with synthetic
		# train_tflops > 0 — those bypass the gpu floor since they don't model
		# real GPUs. Real DCs (rent_facility + buy_gpus) carry gpu_count > 0.
		if template.subtype == &"posttrain":
			var dc_id: StringName = p.get(&"datacenter_id", &"")
			if dc_id != &"":
				var dc = _find_dc(dc_id)
				if dc != null:
					var have_gpu: int = int(dc.gpu_count) if "gpu_count" in dc else 0
					if have_gpu > 0:
						var tier := _posttrain_tier_for(float(bm.size_params))
						if have_gpu < int(tier.min_gpu):
							return &"posttrain_datacenter_too_small"
	# Tech node requirement.
	if bool(schema.get(&"needs_target_node", false)):
		var node_id: StringName = p.get(&"target_node_id", &"")
		if node_id == &"":
			return &"prerequisite_unlock_missing"
		# Check via TechTreeSystem.NODES (tolerate either ResearchSystem agent
		# absent at boot — fall back to file lookup).
		if TechTreeSystem != null and TechTreeSystem.NODES.has(node_id):
			pass
		elif _load_tech_node(node_id) == null:
			return &"prerequisite_unlock_missing"
		# v6 (PR-D): tech_research enforces per-node min_researchers /
		# min_engineers / min_gpu_count. Read from the TechNode template and
		# compare against the payload staff dict + selected datacenter.
		# Per design/科技树系统设计.md §6.0 / §6.1.
		if template.subtype == &"tech_research":
			var node_v6: TechNode = _load_tech_node(node_id)
			if node_v6 != null:
				var staff_v6: Dictionary = p.get(&"staff", {})
				var ml_have: int = int(staff_v6.get(&"ml_eng", 0))
				if ml_have < node_v6.min_researchers:
					return &"tech_researchers_too_few"
				var infra_have: int = int(staff_v6.get(&"infra_eng", 0))
				if infra_have < node_v6.min_engineers:
					return &"tech_engineers_too_few"
				if node_v6.min_gpu_count > 0:
					var dc_v6_id: StringName = p.get(&"datacenter_id", &"")
					var dc_v6 = _find_dc(dc_v6_id)
					if dc_v6 != null:
						var have_gpu_v6: int = int(dc_v6.gpu_count) if "gpu_count" in dc_v6 else 0
						if have_gpu_v6 < node_v6.min_gpu_count:
							return &"tech_datacenter_too_small"
	# v2.1: data_collection_law posttrain runs require a target_capability so
	# the resulting Dataset can be applied via PosttrainDialog. Per
	# 数据集系统设计.md §5.1ter.
	if template.duration_func == &"data_collection_law":
		var dc_kind: StringName = StringName(p.get(&"kind", &"pretrain"))
		if dc_kind == &"posttrain":
			var tcap: StringName = StringName(p.get(&"target_capability", &""))
			if tcap == &"":
				return &"target_capability_required"
		var dc_size: float = float(p.get(&"target_size", 0.0))
		if dc_size <= 0.0:
			return &"target_size_required"
	return &""

# ---- duration / completion payload --------------------------------------

func _resolve_duration(template: TaskTemplate, p: Dictionary) -> int:
	match template.duration_func:
		&"fixed":
			return template.base_duration
		&"node_defined":
			# tech_research duration is the node's historical research_months
			# field, interpreted as weeks, divided by the lead's research_speed
			# bonus (chief_scientist provides 0.55).
			# Per design/招聘系统设计.md §1.1 (Research quadrant).
			var node_id: StringName = p.get(&"target_node_id", &"")
			var node: TechNode = _load_tech_node(node_id)
			var base: int = node.research_months if node != null else template.base_duration
			var speedup: float = _resolve_lead_speedup(p, &"tech_research")
			if speedup <= 0.0:
				speedup = 1.0
			return maxi(1, int(ceil(float(base) / speedup)))
		&"scaling_law":
			return _scaling_law(template, p)
		&"posttrain_law":
			# Legacy alias for v1 saves / tests. Use fixed tier going forward.
			return _posttrain_fixed_tier(template, p)
		&"posttrain_fixed_tier":
			return _posttrain_fixed_tier(template, p)
		&"evaluate_law":
			return _evaluate_law(template, p)
		&"data_collection_law":
			# v2.1: kind+size-based duration for self-collected datasets.
			# Per design/数据集系统设计.md §5.1ter.
			return int(_data_collection_pricing(p).duration)
		&"charity_law":
			# Charity donation duration = the tier's weeks, passed by
			# CharitySystem. Per design/慈善系统设计.md §5.
			return maxi(1, int(p.get(&"weeks", template.base_duration)))
		_:
			return template.base_duration

func _modifier_breakdown(template: TaskTemplate, p: Dictionary) -> Array:
	match template.duration_func:
		&"scaling_law":
			return _scaling_law_modifier_breakdown(template, p)
		&"posttrain_law":
			return _posttrain_modifier_breakdown(template, p)
		&"evaluate_law":
			return [_modifier_entry(&"lead_speedup", "TASK_MOD_LEAD_SPEEDUP",
					_resolve_lead_speedup(p, &"evaluate"))]
		_:
			return []

func _scaling_law_modifier_breakdown(template: TaskTemplate, p: Dictionary) -> Array:
	var out: Array = []
	var arch_id: StringName = _template_arch(template, p)
	# --- 模型性能分数影响因素 ---
	var avg_quality: float = _preview_dataset_quality(p.get(&"dataset_ids", []))
	if avg_quality > 0.0:
		out.append(_modifier_entry(&"dataset_quality", "TASK_MOD_DATASET_QUALITY", avg_quality, &"score"))
	var breadth_factor: float = _preview_data_breadth_factor(p.get(&"dataset_ids", []))
	if breadth_factor > 0.0:
		out.append(_modifier_entry(&"data_breadth", "TASK_MOD_DATA_BREADTH",
				breadth_factor, &"score"))
	out.append(_modifier_entry(&"arch_capability_coef", "TASK_MOD_ARCH_CAPABILITY",
			_arch_capability_coef(arch_id), &"score"))
	# 首席科学家的预训练加分 (pretrain_score_bonus): 烘焙进模型, evaluate 时乘进能力分。
	# 见 任务系统设计.md §6.7 + 招聘系统设计.md §5.1。
	out.append(_modifier_entry(&"lead_score_bonus", "TASK_MOD_LEAD_SCORE_BONUS",
			_resolve_lead_score_mult(p.get(&"lead_ids", []), &"pretrain_score_bonus"), &"score"))
	# --- 训练速度影响因素 ---
	var dc_eff: float = _preview_dc_cluster_efficiency(p.get(&"datacenter_id", &""))
	if dc_eff > 0.0:
		out.append(_modifier_entry(&"cluster_efficiency", "TASK_MOD_CLUSTER_EFFICIENCY", dc_eff, &"speed"))
	out.append(_modifier_entry(&"arch_train_coef", "TASK_MOD_ARCH_TRAIN",
			_arch_train_coef(arch_id), &"speed"))
	# v5 (PR-C): A/B/C/D axes breakdown so PretrainDialog can show the player
	# why a given attention / loss / context selection speeds up or slows down
	# the training. ctx_penalty is shown as 1/penalty (≤ 1.0) — UI treats it
	# the same as other speed multipliers (lower number → slower).
	var attention_id: StringName = StringName(p.get(&"attention_id", &"mha_baseline"))
	var loss_id: StringName = StringName(p.get(&"loss_id", &"ce_baseline"))
	var ctx_tokens: int = int(p.get(&"context_length_tokens", 4096))
	out.append(_modifier_entry(&"attention_train_coef", "TASK_MOD_ATTENTION_TRAIN",
			_attention_train_coef(attention_id), &"speed"))
	out.append(_modifier_entry(&"loss_train_coef", "TASK_MOD_LOSS_TRAIN",
			_loss_train_coef(loss_id), &"speed"))
	out.append(_modifier_entry(&"context_length_penalty", "TASK_MOD_CONTEXT_PENALTY",
			1.0 / _context_length_train_penalty(ctx_tokens), &"speed"))
	# v5 (PR-C): loss capability_coef boosts evaluate score; expose in the score
	# section so player understands C-axis trade-off.
	out.append(_modifier_entry(&"loss_capability_coef", "TASK_MOD_LOSS_CAPABILITY",
			_loss_capability_coef(loss_id), &"score"))
	out.append(_modifier_entry(&"lead_speedup", "TASK_MOD_LEAD_SPEEDUP",
			_resolve_lead_speedup(p, &"pretrain"), &"speed"))
	out.append(_modifier_entry(&"staff_speedup", "TASK_MOD_STAFF_SPEEDUP",
			_resolve_staff_multiplier(p), &"speed"))
	return out

func _posttrain_modifier_breakdown(template: TaskTemplate, p: Dictionary) -> Array:
	return [
		_modifier_entry(&"arch_train_coef", "TASK_MOD_ARCH_TRAIN",
				_arch_train_coef(_template_arch(template, p)), &"speed"),
		_modifier_entry(&"lead_speedup", "TASK_MOD_LEAD_SPEEDUP",
				_resolve_lead_speedup(p, &"posttrain"), &"speed"),
		_modifier_entry(&"staff_speedup", "TASK_MOD_STAFF_SPEEDUP",
				_resolve_staff_multiplier(p), &"speed"),
	]

# category: &"speed" = affects training duration; &"score" = affects capability score.
func _modifier_entry(id: StringName, label: String, value: float, category: StringName = &"speed") -> Dictionary:
	return {
		id = id,
		label = label,
		value = value,
		kind = _modifier_kind(value),
		category = category,
	}

func _modifier_kind(value: float) -> StringName:
	if value > 1.0001:
		return &"buff"
	if value < 0.9999:
		return &"debuff"
	return &"neutral"

## v9 (2026-05): preview helper for evaluate-time data_quality_factor. Returns
## the *factor* (clamped 0.5..1.5) so PretrainDialog modifier breakdown can
## display "数据质量" in the same units as the evaluate公式.
## Posttrain datasets ignored. Returns 0.0 when no pretrain datasets — caller
## treats that as "neutral, skip showing this modifier".
## Per 任务系统设计 §6.7 + 平衡参数.md §DatasetSystem 公式.
func _preview_dataset_quality(dataset_ids: Array) -> float:
	var wq: float = _weighted_pretrain_quality(dataset_ids)
	if wq < 0.0:
		return 0.0
	return clampf(DATA_QUALITY_FACTOR_FLOOR + wq, DATA_QUALITY_FACTOR_FLOOR, DATA_QUALITY_FACTOR_CAP)

func _preview_data_breadth_factor(dataset_ids: Array) -> float:
	if _pretrain_token_weight(dataset_ids) <= 0.0:
		return 0.0
	return _data_breadth_factor(dataset_ids)

func _preview_dc_cluster_efficiency(dc_id: StringName) -> float:
	if dc_id == &"":
		return 0.0
	var dc = _find_dc(dc_id)
	if dc == null:
		return 0.0
	return dc.cluster_efficiency if dc.cluster_efficiency > 0.0 else 1.0

func _arch_train_coef(arch_id: StringName) -> float:
	var coefs: Dictionary = CommandBus.send(&"tech.get_arch_coefs", {arch_id = arch_id})
	if coefs.ok:
		return float(coefs.train_coef)
	return 1.0

func _template_arch(template: TaskTemplate, p: Dictionary) -> StringName:
	var arch: StringName = StringName(p.get(&"arch_id", template.output_arch))
	if arch == &"":
		# Unified pretrain_model template carries no default arch; fall back
		# to ant_v1 so downstream consumers always see a valid id.
		arch = &"ant_v1"
	return arch

# Pretrain duration. Per 任务系统设计.md §6.6.1 + 平衡参数.md §TaskSystem.
# Compute units stay abstract (size_params in M × dataset_tokens in B), but
# the scaling constant matches the Chinchilla 6× rule. The datacenter's
# cluster_efficiency (big_cluster_decay per 平衡参数 §大集群衰减 + chief_engineer
# cluster_eff_add per 招聘 §1.1) is ALREADY baked into dc.train_tflops
# (基础设施系统设计 §4.1), so the divisor uses train_tflops directly and must
# NOT re-apply cluster_efficiency — doing so squared the big_cluster_decay.
func _scaling_law(template: TaskTemplate, p: Dictionary) -> int:
	# Payload override: PretrainDialog passes player-input size_params (in M).
	# Falls back to template.output_size_params for legacy fixed-size templates.
	var size_params: float = float(p.get(&"size_params", template.output_size_params))
	if size_params <= 0.0:
		size_params = template.output_size_params
	if size_params <= 0.0:
		return maxi(1, template.base_duration)

	# v9 (2026-05): _scaling_law no longer applies a data-quality multiplier.
	# Training duration depends only on Σ tokens × the usual compute/architecture
	# factors. Quality affects evaluate score, not training time (per
	# 数据集系统设计 §1 + 任务系统设计 §6.6.1 v9).
	var dataset_tokens: float = 0.0
	var any_pretrain: bool = false
	for ds_id in (p.get(&"dataset_ids", []) as Array):
		var ds = _find_dataset(ds_id)
		if ds == null:
			continue
		if ds.kind != &"pretrain":
			continue
		dataset_tokens += ds.size
		any_pretrain = true
	if dataset_tokens <= 0.0 or not any_pretrain:
		return maxi(1, template.base_duration)

	# Datacenter side. dc.train_tflops already includes cluster_efficiency
	# (基础设施系统设计 §4.1), so we read it directly — no second multiply.
	var dc_train_tflops: float = 50_000.0
	var dc_id: StringName = p.get(&"datacenter_id", &"")
	if dc_id != &"":
		var dc = _find_dc(dc_id)
		if dc != null and dc.train_tflops > 0.0:
			dc_train_tflops = dc.train_tflops

	var arch_id: StringName = _template_arch(template, p)
	var arch_coef: float = _arch_train_coef(arch_id)
	# v4 (PR-B): MoE training only updates active params per token. The Chinchilla
	# rule `compute = 6 × N × D` becomes `6 × (N × active_ratio) × D`. The data
	# side (Chinchilla optimal tokens) still uses TOTAL params — MoE is data-hungry
	# by design (see 平衡参数.md "模型架构激活参数比例").
	var active_ratio: float = _active_param_ratio(arch_id)

	# v5 (PR-C): A/B/C/D 4-axis multipliers. All default to 1.0 baselines so
	# pre-PR-C callers (no attention_id / loss_id / context_length_tokens in
	# payload) keep getting the same duration as before.
	var attention_id: StringName = StringName(p.get(&"attention_id", &"mha_baseline"))
	var loss_id: StringName = StringName(p.get(&"loss_id", &"ce_baseline"))
	var ctx_tokens: int = int(p.get(&"context_length_tokens", 4096))
	# v7 PR-G: E-axis multimodal_method imposes an extra train_penalty.
	var mm_method: StringName = StringName(p.get(&"multimodal_method", &"none"))
	var attention_train_coef: float = _attention_train_coef(attention_id)
	var loss_train_coef: float = _loss_train_coef(loss_id)
	var ctx_penalty: float = _context_length_train_penalty(ctx_tokens)
	var mm_penalty: float = _multimodal_method_train_penalty(mm_method)

	# Lead + staff multipliers (design §6.6.4). Lead by first lead_id (subtype
	# bonus key looked up via HiringSystem). Staff by ml_eng count.
	var lead_speedup: float = _resolve_lead_speedup(p, &"pretrain")
	var staff_mult: float = _resolve_staff_multiplier(p)

	var compute: float = SCALING_LAW_FLOPS_C * size_params * active_ratio * dataset_tokens * ctx_penalty * mm_penalty
	var divisor: float = dc_train_tflops * arch_coef \
			* attention_train_coef * loss_train_coef \
			* lead_speedup * staff_mult
	if divisor <= 0.0:
		return maxi(1, template.base_duration)
	return maxi(1, int(ceil(compute / divisor)))

# Posttrain duration tier table. Per 任务系统设计.md §6.6.2 (v2) + 平衡参数.md
# `POSTTRAIN_TIER_TABLE`. Tier is selected by base_model.size_params (M params).
# `min_gpu_count` is a validation threshold, not a throughput input; lead/staff
# do NOT affect duration in v2.
const POSTTRAIN_TIERS: Array = [
	{cap_m = 10_000.0,    min_gpu = 8,    weeks = 1, id = &"posttrain_tier_s"},
	{cap_m = 100_000.0,   min_gpu = 72,   weeks = 2, id = &"posttrain_tier_m"},
	{cap_m = 500_000.0,   min_gpu = 500,  weeks = 4, id = &"posttrain_tier_l"},
	{cap_m = INF,         min_gpu = 1000, weeks = 8, id = &"posttrain_tier_xl"},
]

func _posttrain_tier_for(size_params_m: float) -> Dictionary:
	for tier in POSTTRAIN_TIERS:
		if size_params_m <= tier.cap_m:
			return tier
	return POSTTRAIN_TIERS[-1]

# Posttrain duration v2. Per 任务系统设计.md §6.6.2: fixed by model.size_params.
# Lead/staff/arch do not affect duration. Falls back to template.base_duration
# only when base_model is missing (defensive — start should have rejected this).
func _posttrain_fixed_tier(template: TaskTemplate, p: Dictionary) -> int:
	var base_id: StringName = p.get(&"base_model_id", &"")
	var base = _find_model(base_id)
	var tier_weeks: int
	if base == null or float(base.size_params) <= 0.0:
		tier_weeks = maxi(1, template.base_duration)
	else:
		tier_weeks = int(_posttrain_tier_for(float(base.size_params)).weeks)
	# v12: token-volume surcharge — bulk-stacking posttrain data costs real cluster
	# time. +1 week per POSTTRAIN_TOKENS_PER_WEEK_B (B tokens). Normal SFT adds 0.
	# Per 任务系统设计.md §6.2 + 研究系统设计.md §4.2 (聚合+饱和 后, 数据量改吃时间).
	var extra: int = int(floor(_posttrain_total_tokens(p) / POSTTRAIN_TOKENS_PER_WEEK_B))
	return tier_weeks + extra

# v12: total posttrain-dataset tokens (B) locked for this task. Used by the
# token-volume duration surcharge above.
func _posttrain_total_tokens(p: Dictionary) -> float:
	var total: float = 0.0
	for ds_id in p.get(&"dataset_ids", []):
		var ds = DatasetSystem.find_dataset(StringName(ds_id))
		if ds != null and ds.kind == &"posttrain":
			total += maxf(0.0, float(ds.size))
	return total

# Evaluate duration. Per design §6.6.3: EVAL_BASE_WEEKS scaled by lead bonus.
func _evaluate_law(_template: TaskTemplate, p: Dictionary) -> int:
	var lead_speedup: float = _resolve_lead_speedup(p, &"evaluate")
	if lead_speedup <= 0.0:
		lead_speedup = 1.0
	return maxi(1, int(ceil(float(EVAL_BASE_WEEKS) / lead_speedup)))

func _resolve_lead_speedup(p: Dictionary, subtype: StringName) -> float:
	var lead_ids: Array = p.get(&"lead_ids", [])
	if lead_ids.is_empty():
		return 1.0
	var lead = HiringSystem.find_lead(StringName(lead_ids[0]))
	if lead == null:
		return 1.0
	return HiringSystem.lead_speedup_for(lead, subtype)

## 解析 lead 的"分数加成"倍率 (区别于 *_speedup 的时长倍率)。读 LEAD_BONUS_TABLE 的
## `*_score_bonus` 系数, 按 ability 线性缩放: mult = 1 + (ability/100) × coef。
## player_scientist (万能 lead) coef 恒 0 → 退化为 1.0 (无加成)。无 lead / 缺该 key
## 同样返回 1.0。Per 招聘系统设计.md §5.1 + 任务系统设计.md §6.7。
func _resolve_lead_score_mult(lead_ids: Array, bonus_key: StringName) -> float:
	if lead_ids.is_empty():
		return 1.0
	var lead = HiringSystem.find_lead(StringName(lead_ids[0]))
	return HiringSystem.lead_score_mult(lead, bonus_key)

func _resolve_staff_multiplier(p: Dictionary) -> float:
	var staff: Dictionary = p.get(&"staff", {})
	var ml_eng: int = int(staff.get(&"ml_eng", 0))
	if ml_eng <= 0:
		return 1.0
	return 1.0 + STAFF_MARGINAL * (log(1.0 + float(ml_eng)) / log(2.0))

func _resolve_completion_command(subtype: StringName) -> StringName:
	match subtype:
		&"pretrain": return &"research.add_model"
		&"posttrain": return &"research.posttrain_apply"
		&"evaluate": return &"research.evaluate_apply"
		&"data_collection": return &"dataset.add"
		&"tech_research": return &"tech.unlock_node"
		&"charity": return &"charity.credit"
		&"simulation": return &"simulation.complete_stage"
		_: return &""

func _resolve_completion_payload(template: TaskTemplate, p: Dictionary, inst: TaskInstance) -> Dictionary:
	match template.subtype:
		&"pretrain":
			# Per design §6.4: NEVER include capability — capability is
			# computed by evaluate. Send only physical metadata.
			# Player-driven fields (display_name, size_params) come from the
			# PretrainDialog payload; fall back to template defaults so legacy
			# fixed-size templates (sparrow_s / otter_m / ...) still work.
			# We forward display_name ONLY when the caller explicitly supplied
			# one, so ResearchSystem can distinguish "player named it" (use as
			# id) from "template default" (auto-gen codename id).
			var psize: float = float(p.get(&"size_params", 0.0))
			if psize <= 0.0:
				psize = template.output_size_params
			var pretrain_arch: StringName = _template_arch(template, p)
			# v4 (PR-B): MoE archs reduce flops_per_token via active_param_ratio.
			# research.add_model will re-derive this from arch, but pre-fill so
			# the completion payload is self-consistent.
			var active_ratio: float = _active_param_ratio(pretrain_arch)
			# v5 (PR-C): A/B/C/D axes. Forward the 3 non-A fields (attention/
			# loss/context) into the completion payload; ResearchSystem.add_model
			# will write them onto the Model + bake attention.inference_coef into
			# flops_per_token.
			var attention_id: StringName = StringName(p.get(&"attention_id", &"mha_baseline"))
			var loss_id: StringName = StringName(p.get(&"loss_id", &"ce_baseline"))
			var ctx_tokens: int = int(p.get(&"context_length_tokens", 4096))
			# v7 PR-G: multimodal_method (E-axis). Default `none` for single-modality;
			# PretrainDialog enables it only when input_modalities has non-text.
			var mm_method: StringName = StringName(p.get(&"multimodal_method", &"none"))
			var attn_inf_coef: float = _attention_inference_coef(attention_id)
			# v7 PR-G: PretrainDialog can override modalities (the pretrain_model
			# template defaults to [text] but multimodal training extends with
			# image / audio / video). Fall back to template defaults when payload
			# omits them.
			var in_mods_payload: Array = p.get(&"input_modalities", [])
			var typed_in_mods: Array[StringName] = []
			for im in in_mods_payload:
				typed_in_mods.append(StringName(im))
			if typed_in_mods.is_empty():
				typed_in_mods = template.output_input_modalities.duplicate()
			# Output modalities mirror input for now (no separate UI yet).
			var typed_out_mods: Array[StringName] = template.output_output_modalities.duplicate()
			var payload := {
				arch = pretrain_arch,
				attention_id = attention_id,
				loss_id = loss_id,
				context_length_tokens = ctx_tokens,
				multimodal_method = mm_method,
				dataset_ids = inst.locked_dataset_ids.duplicate(),
				size_params = psize,
				# fpt baseline (active × 2 × N × 1e6); ResearchSystem will divide
				# by attention.inference_coef again. We send the pre-divided value
				# so legacy add_model paths (no attention_id) get the same number.
				flops_per_token = Model.infer_flops_per_token(psize, active_ratio) / attn_inf_coef,
				input_modalities = typed_in_mods,
				output_modalities = typed_out_mods,
				# 科学家预训练加分: 完成时按锁定的 lead 烘焙成倍率写到 model 上,
				# evaluate 计算能力分时整体放大。Per 任务系统设计.md §6.7。
				pretrain_score_mult = _resolve_lead_score_mult(
						inst.locked_lead_ids, &"pretrain_score_bonus"),
			}
			var pname: String = String(p.get(&"display_name", "")).strip_edges()
			if pname != "":
				payload[&"display_name"] = pname
			return payload
		&"posttrain":
			# v2: pass full dataset list + dc + leads so ResearchSystem can apply
			# the per-dataset capability deltas (target axis +X, others -Y).
			# Per 任务系统设计 §6.4 (v2) + 研究系统 §6.2 (v2).
			# Keep legacy `dataset_id` as the first id for backward compat with
			# v1 callers / saves that read that field.
			var ds_id: StringName = &""
			if inst.locked_dataset_ids.size() > 0:
				ds_id = inst.locked_dataset_ids[0]
			return {
				model_id = p.get(&"base_model_id", &""),
				dataset_id = ds_id,
				dataset_ids = inst.locked_dataset_ids.duplicate(),
				datacenter_id = inst.locked_datacenter_id,
				lead_ids = inst.locked_lead_ids.duplicate(),
			}
		&"evaluate":
			# Capability is computed at completion time, not here, because
			# posttrain_count / dataset.quality / arch_bonus may have shifted
			# between start and completion. We stash inputs and run the
			# formula in _complete via _resolve_evaluate_payload_late().
			return {
				model_id = p.get(&"base_model_id", &""),
				capability_measured = {},  # filled in at completion
			}
		&"data_collection":
			# v9 (2026-05): kind-aware completion payload for DatasetCollectionDialog.
			# Per 数据集系统设计.md §5 + 任务系统设计.md §6.7 v9.
			# - kind=pretrain: default single-tag [web]; player can opt into
			#   specialty tags via `target_tags` in payload (dialog supports
			#   1-2 multi-select). Base quality 0.55 (uncurated web).
			# - kind=posttrain: [target_capability, instruction]; base 0.65.
			# Pre-v9 callers fed a 5-tag "balanced" default which combined with the
			# old count-based tag_ratio formula made self-collected pretrain trivially
			# max all axes. v9 公式 (token×quality 加权) + 单 tag 默认共同矫正这点。
			var dc_kind: StringName = StringName(p.get(&"kind", &"pretrain"))
			var default_q: float = 0.65 if dc_kind == &"posttrain" else 0.55
			var base_quality: float = float(p.get(&"target_quality", default_q))
			var option_quality_bonus: float = _data_collection_option_quality_bonus(dc_kind, p)
			var quality_final: float = _data_collection_quality(
					base_quality, p.get(&"lead_ids", []), option_quality_bonus)
			if option_quality_bonus > 0.0:
				Log.info(&"tasks", "data_collection_employee_work_monitoring", {
					bonus = option_quality_bonus,
					quality = quality_final,
					kind = dc_kind,
				})
			var tags: Array
			if p.has(&"target_tags"):
				tags = p.get(&"target_tags", [])
			elif dc_kind == &"posttrain":
				var tcap: StringName = StringName(p.get(&"target_capability", &""))
				tags = [tcap, &"instruction"]
			else:
				tags = [&"web"]
			var dc_payload: Dictionary = {
				kind = dc_kind,
				size = float(p.get(&"target_size", 5.0)),
				quality = quality_final,
				coverage_tags = tags,
				source = &"collected",
				# v7 PR-G: pass through chosen modality; defaults to text for
				# legacy callers / pre-G save fixtures.
				modality = StringName(p.get(&"modality", &"text")),
			}
			if dc_kind == &"posttrain":
				dc_payload[&"target_capability"] = StringName(p.get(&"target_capability", &""))
			var dc_name: String = String(p.get(&"display_name", "")).strip_edges()
			if dc_name != "":
				dc_payload[&"display_name"] = dc_name
			return dc_payload
		&"tech_research":
			return {
				tree = p.get(&"target_tree", &""),
				node_id = p.get(&"target_node_id", &""),
			}
		&"charity":
			# Credited to the cause on completion → activates the capped buff.
			# Per design/慈善系统设计.md §5.
			return {
				cause_id = StringName(p.get(&"cause_id", &"")),
				amount = int(p.get(&"amount", 0)),
			}
		&"simulation":
			# Advances the universe-simulation ladder on completion.
			# Per design/宇宙模拟工程设计.md §5.
			return {
				stage_id = StringName(p.get(&"stage_id", &"")),
			}
		_:
			return {}

# ---- evaluate capability formula ---------------------------------------
# Per 任务系统设计.md §6.7 + 平衡参数.md §evaluate产出.
#
#   base = clamp(20 + 12 × log10(size_params_M / 100), 10, 95)
#   axis = base × arch_capability_coef × data_quality_avg
#               × posttrain_lift × lead_eval_acc
#               × DATASET_TAG_RATIOS[axis]
#
# `arch_capability_coef` is a per-arch table (ARCH_CAPABILITY_COEF), with a
# fallback to TechNode.effects.capability_coef when set, else 1.0.
# `posttrain_lift = 1 + 0.10 × posttrain_count(model)`.
# `lead_eval_acc` reads ml_research_lead.evaluate_score_bonus (from
# HiringSystem.LEAD_BONUS_TABLE) — NOT eval_lead.evaluate_speed (which is a
# duration multiplier consumed by _evaluate_law).
func _compute_capability_measured(model, eval_lead) -> Dictionary:
	if model == null:
		return {}
	var size_m: float = maxf(float(model.size_params), 1.0)
	var base: float = clampf(20.0 + 12.0 * (log(size_m / 100.0) / log(10.0)), 10.0, 95.0)
	# v7 PR-G: arch.capability_cap (trap nodes like BERT/T5) clamps `base` to a
	# hard ceiling — the model can still gain from arch_coef / data_q / etc. but
	# the size-scaling head is bounded. cap=0 means no clamp.
	var arch_cap: float = _arch_capability_cap(model.arch)
	if arch_cap > 0.0:
		base = minf(base, arch_cap)
	var arch_coef: float = _arch_capability_coef(model.arch)
	# v9: data_quality_factor = clamp(0.5 + token×quality avg, 0.5, 1.5). No more
	# source min; source field is audit-only. Per 平衡参数.md §DatasetSystem 公式.
	var weighted_q: float = _weighted_pretrain_quality(model.dataset_ids)
	if weighted_q < 0.0:
		weighted_q = 0.5  # safety floor for legacy callers w/o pretrain datasets
	var data_q: float = clampf(
			DATA_QUALITY_FACTOR_FLOOR + weighted_q,
			DATA_QUALITY_FACTOR_FLOOR, DATA_QUALITY_FACTOR_CAP)
	var data_breadth: float = _data_breadth_factor(model.dataset_ids)
	var data_efficiency: float = _chinchilla_data_efficiency(size_m, model.dataset_ids)
	# Bug B fix (2026-05): posttrain_lift removed from the evaluate formula.
	# Posttrain's effect on capability now flows through model.posttrain_delta
	# (accumulated at posttrain_apply, layered onto capability_measured by
	# research.evaluate_apply). See 研究系统设计.md §6.3 / 任务系统设计.md §6.7.
	var lead_eval_acc: float = _resolve_eval_score_bonus(eval_lead)
	# v5 (PR-C): loss C-axis node scales the overall capability score. Surfaced
	# to the player in task.preview modifier_breakdown as "Loss 能力系数".
	# ce_baseline → 1.0 (neutral). Per 任务系统设计.md §6.7.
	var loss_coef: float = _loss_capability_coef(
			StringName(model.loss_id) if "loss_id" in model else &"ce_baseline")
	var has_image: bool = (model.input_modalities as Array).has(&"image")
	# 预训练科学家加分: 在预训练完成时按 lead ability×pretrain_score_bonus 烘焙到
	# model.pretrain_score_mult (默认 1.0), evaluate 时整体放大能力分。Per §6.7。
	var pretrain_score_mult: float = float(model.pretrain_score_mult) \
			if "pretrain_score_mult" in model else 1.0
	var raw: float = base * arch_coef * loss_coef * data_q * data_breadth \
			* data_efficiency * lead_eval_acc * pretrain_score_mult
	# DATASET_TAG_RATIOS per design §evaluate产出. Per 任务系统设计.md §6.7 and
	# 平衡参数.md §evaluate产出: 100 = SOTA baseline only — there is NO upper
	# cap, scores are free to grow past 100 in late game.
	var general_ratio: float = 1.0
	var code_ratio: float = _dataset_tag_ratio(model.dataset_ids, &"code")
	var reasoning_ratio: float = _dataset_tag_ratio(model.dataset_ids, &"reasoning",
			[&"chat", &"reasoning"])
	var business_share: float = _dataset_weighted_tag_share(model.dataset_ids,
			[BUSINESS_ANALYSIS_TAG])
	var business_code_factor: float = _business_analysis_axis_factor(
			business_share, BUSINESS_ANALYSIS_CODE_MIN_FACTOR)
	var business_reasoning_factor: float = _business_analysis_axis_factor(
			business_share, BUSINESS_ANALYSIS_REASONING_MIN_FACTOR)
	var business_agent_factor: float = _business_analysis_axis_factor(
			business_share, BUSINESS_ANALYSIS_AGENT_MIN_FACTOR)
	if business_share > 0.0:
		Log.debug(&"task", "business_analysis_axis_penalty", {
			model_id = model.id,
			share = business_share,
			code_factor = business_code_factor,
			reasoning_factor = business_reasoning_factor,
			agent_factor = business_agent_factor,
		})
	# v7 PR-G: multimodal axis gets a method-specific bonus from PretrainDialog
	# E-axis. cross_train = 1.0 (baseline); diffusion_ar / pixel_ar / native_ar
	# scale up. `none` (single-modality model) → no multi axis regardless.
	var mm_method_coef: float = _multimodal_method_capability_coef(
			StringName(model.multimodal_method) if "multimodal_method" in model else &"none")
	var multimodal_ratio: float = (1.0 * mm_method_coef) if has_image else 0.0
	# Agent axis is gated by hard size thresholds (§6.7.2). Below either
	# threshold we zero it out before computing the ratio so the player sees
	# a sharp cliff, not a vanishingly small number.
	# v7 PR-G: context tree adds an *additive* agent_bonus on top of raw × ratio
	# (only when gate passes). Encourages "big model + 1M ctx" to get an agent step.
	var agent_score: float = 0.0
	if _passes_agent_size_gate(size_m, model.arch):
		var agent_ratio: float = _dataset_tag_ratio(model.dataset_ids, &"agent")
		agent_ratio *= _tool_use_tech_bonus()
		var ctx_bonus: float = _context_agent_bonus(
				int(model.context_length_tokens) if "context_length_tokens" in model else 4096)
		agent_score = (maxf(0.0, raw * agent_ratio) + ctx_bonus) * business_agent_factor
	return {
		general = maxf(0.0, raw * general_ratio),
		code = maxf(0.0, raw * code_ratio * business_code_factor),
		reasoning = maxf(0.0, raw * reasoning_ratio * business_reasoning_factor),
		multimodal = maxf(0.0, raw * multimodal_ratio),
		agent = agent_score,
	}

# v7 PR-G: capability_cap on arch tree nodes. 0 = no cap (default for sane
# decoder-only archs). The encoder trap lineage bounds the `base` term: BERT can
# scale for a while (30→64 cap), but size never fully rescues the route — see
# 科技树系统设计.md §6.
func _arch_capability_cap(arch_id: StringName) -> float:
	var coefs: Dictionary = CommandBus.send(&"tech.get_arch_coefs", {arch_id = arch_id})
	if coefs.get(&"ok", false):
		return float(coefs.get(&"capability_cap", 0.0))
	return 0.0

# v7 PR-G: PretrainDialog E-axis multimodal method → multimodal-axis capability
# coef. Authoritative source for the table is 平衡参数.md §Multimodal method.
const MULTIMODAL_METHOD_CAPABILITY_COEF: Dictionary = {
	&"none": 1.0,
	&"cross_train": 1.0,
	&"pixel_ar": 1.15,
	&"diffusion_ar": 1.20,
	&"native_ar": 1.30,
}
func _multimodal_method_capability_coef(method: StringName) -> float:
	if MULTIMODAL_METHOD_CAPABILITY_COEF.has(method):
		return float(MULTIMODAL_METHOD_CAPABILITY_COEF[method])
	return 1.0

const MULTIMODAL_METHOD_TRAIN_PENALTY: Dictionary = {
	&"none": 1.0,
	&"cross_train": 1.0,
	&"pixel_ar": 1.10,
	&"diffusion_ar": 1.15,
	&"native_ar": 1.30,
}
func _multimodal_method_train_penalty(method: StringName) -> float:
	if MULTIMODAL_METHOD_TRAIN_PENALTY.has(method):
		return float(MULTIMODAL_METHOD_TRAIN_PENALTY[method])
	return 1.0

# v7 PR-G: context tree agent_bonus is *additive* on agent axis. Sums
# `effects.agent_bonus` over all unlocked context nodes whose `max_tokens`
# the model's context_length_tokens covers (i.e. tier ≤ chosen tokens).
# In practice ctx_4k contributes 0; ctx_32k +2 / ctx_200k +5 / ctx_1m +10 /
# ctx_10m +20. Sums (not max) so the bonus reads as cumulative tier rewards.
func _context_agent_bonus(model_ctx_tokens: int) -> float:
	var r: Dictionary = CommandBus.send(&"tech.get_context_tiers", {})
	if not r.get(&"ok", false):
		return 0.0
	var bonus: float = 0.0
	for tier in r.get(&"tiers", []):
		if int(tier.get(&"max_tokens", 0)) <= model_ctx_tokens:
			bonus += float(tier.get(&"agent_bonus", 0.0))
	return bonus

# §6.7 / 平衡参数.md: tool_use application-tech node, when unlocked, multiplies
# the agent capability ratio by AGENT_TOOL_USE_BONUS. Application tech now only
# keeps nodes with direct consumers, so no product-quality-only effect leaks here.
const AGENT_TOOL_USE_BONUS: float = 1.5
func _tool_use_tech_bonus() -> float:
	var unlocks: Dictionary = GameState.unlocks.get(&"application", {})
	if bool(unlocks.get(&"tool_use", false)):
		return AGENT_TOOL_USE_BONUS
	return 1.0

# §6.7.2 / 平衡参数.md: agent capability needs both enough world knowledge
# (total params ≥ 70B) and enough per-token active compute (≥ 27B). Below
# either threshold agent = 0 regardless of data / arch / posttrain.
const AGENT_MIN_ACTIVE_B: float = 27.0       # B parameters
const AGENT_MIN_TOTAL_B: float = 70.0        # B parameters
# v4 (PR-B): single source of truth is Model.ACTIVE_PARAM_RATIO_BY_ARCH.
# _active_param_ratio() below proxies through it so TaskSystem + Model +
# ResearchSystem can never drift apart.

func _active_param_ratio(arch_id: StringName) -> float:
	return Model.active_param_ratio_for(arch_id)

# v5 (PR-C): attention / loss / context_length helpers used by _scaling_law +
# the pretrain completion payload. All return 1.0 baselines for unknown ids so
# missing TechTree registrations degrade gracefully (callers that don't pass
# these fields keep the pre-PR-C behavior).

func _attention_train_coef(attention_id: StringName) -> float:
	if attention_id == &"" or attention_id == &"mha_baseline":
		return 1.0
	var r: Dictionary = CommandBus.send(&"tech.get_attention_coefs", {attention_id = attention_id})
	if r.get(&"ok", false):
		return float(r.get(&"train_coef", 1.0))
	return 1.0

func _attention_inference_coef(attention_id: StringName) -> float:
	# Used by ResearchSystem.add_model to bake inference_coef into model.flops_per_token.
	# Returns 1.0 (no fpt reduction) for baseline / unknown.
	if attention_id == &"" or attention_id == &"mha_baseline":
		return 1.0
	var r: Dictionary = CommandBus.send(&"tech.get_attention_coefs", {attention_id = attention_id})
	if r.get(&"ok", false):
		return float(r.get(&"inference_coef", 1.0))
	return 1.0

func _loss_train_coef(loss_id: StringName) -> float:
	if loss_id == &"" or loss_id == &"ce_baseline":
		return 1.0
	var r: Dictionary = CommandBus.send(&"tech.get_loss_coefs", {loss_id = loss_id})
	if r.get(&"ok", false):
		return float(r.get(&"train_coef", 1.0))
	return 1.0

func _loss_capability_coef(loss_id: StringName) -> float:
	# Used by evaluate (capability_measured) — loss tech node may scale the
	# overall capability score.
	if loss_id == &"" or loss_id == &"ce_baseline":
		return 1.0
	var r: Dictionary = CommandBus.send(&"tech.get_loss_coefs", {loss_id = loss_id})
	if r.get(&"ok", false):
		return float(r.get(&"capability_coef", 1.0))
	return 1.0

# Per 平衡参数.md §context_length: tokens → train-duration penalty multiplier.
# v7 PR-G: added 10M tier matching ctx_10m context tree node.
const _CONTEXT_LENGTH_PENALTY: Dictionary = {
	4096:     1.00,
	32768:    1.10,
	200000:   1.30,
	1000000:  1.60,
	10000000: 2.20,
}

func _context_length_train_penalty(tokens: int) -> float:
	if _CONTEXT_LENGTH_PENALTY.has(tokens):
		return float(_CONTEXT_LENGTH_PENALTY[tokens])
	# v7 PR-G: also accept any value the context tree exposes — useful if a future
	# tier gets added in .tres without updating this fallback table. We just look
	# up the tier whose max_tokens matches.
	var r: Dictionary = CommandBus.send(&"tech.get_context_tiers", {})
	if r.get(&"ok", false):
		for tier in r.get(&"tiers", []):
			if int(tier.get(&"max_tokens", 0)) == tokens:
				return float(tier.get(&"train_penalty", 1.0))
	return 1.0

func _passes_agent_size_gate(size_params_m: float, arch_id: StringName) -> bool:
	var total_b: float = size_params_m / 1000.0
	var active_b: float = total_b * _active_param_ratio(arch_id)
	return active_b >= AGENT_MIN_ACTIVE_B and total_b >= AGENT_MIN_TOTAL_B

func _arch_capability_coef(arch_id: StringName) -> float:
	# Prefer the authoritative table (平衡参数.md §evaluate产出).
	if ARCH_CAPABILITY_COEF.has(arch_id):
		return float(ARCH_CAPABILITY_COEF[arch_id])
	# Tech-tree arch node may carry a `capability_coef` effect; unknown ids
	# (e.g. removed legacy nodes in old saves) return ok=false → coef stays 1.0.
	var coefs: Dictionary = CommandBus.send(&"tech.get_arch_coefs", {arch_id = arch_id})
	if coefs.ok and coefs.has(&"capability_coef"):
		return float(coefs[&"capability_coef"])
	return 1.0

# `evaluate_score_bonus` is on `ml_research_lead`, not on `eval_lead`. Per
# 招聘系统设计 §1.1 + 平衡参数.md §LEAD_BONUS_TABLE: a lead with
# specialty=ml_research_lead contributes `1 + (ability/100) × 0.10`. Other
# specialties (eval_lead provides evaluate_speed for *duration*, not score)
# contribute 1.0 here.
func _resolve_eval_score_bonus(lead) -> float:
	if lead == null or lead.specialty != &"ml_research_lead":
		return 1.0
	var bonus_table: Dictionary = HiringSystem.LEAD_BONUS_TABLE.get(&"ml_research_lead", {})
	var coef: float = float(bonus_table.get(&"evaluate_score_bonus", 0.0))
	if coef <= 0.0:
		return 1.0
	return 1.0 + (float(lead.ability) / 100.0) * coef

## Chinchilla scaling-law data efficiency. Per design 任务系统设计.md §6.7.1.
##
## Returns a multiplier in [0, CHINCHILLA_EFFICIENCY_CAP]:
##   ratio = Σ dataset.size / (CHINCHILLA_OPTIMAL_RATIO × size_params / 1000)
##   - undertrain (ratio ≤ 1):  ratio ^ CHINCHILLA_UNDERTRAIN_EXP   (paper β ≈ 0.28)
##   - overtrain  (ratio > 1):  1 + CHINCHILLA_OVERTRAIN_SLOPE × log10(ratio)
##
## The conversion factor 1/1000 comes from size_params being in M and dataset
## sizes in B tokens — `20 tokens/param × 1e6 / 1e9 = 0.02` B tokens per M param.
func _chinchilla_data_efficiency(size_params_m: float, dataset_ids: Array) -> float:
	if size_params_m <= 0.0:
		return 0.0
	var actual_tokens_b: float = 0.0
	for did in dataset_ids:
		var ds = _find_dataset(StringName(did))
		if ds != null:
			actual_tokens_b += float(ds.size)
	if actual_tokens_b <= 0.0:
		return 0.0
	var optimal_tokens_b: float = (CHINCHILLA_OPTIMAL_RATIO * size_params_m) / 1000.0
	var ratio: float = actual_tokens_b / optimal_tokens_b
	var eff: float
	if ratio <= 1.0:
		eff = pow(ratio, CHINCHILLA_UNDERTRAIN_EXP)
	else:
		eff = 1.0 + CHINCHILLA_OVERTRAIN_SLOPE * (log(ratio) / log(10.0))
	return clampf(eff, 0.0, CHINCHILLA_EFFICIENCY_CAP)

## v9 (2026-05): token-weighted average of pretrain dataset `quality` field.
## Returns a value in [0, 1] when at least one pretrain dataset is found, or
## `-1.0` when none are present. Posttrain datasets are ignored.
##
## Replaces v2 `_avg_dataset_quality` which returned the source-min multiplier
## (purchased ×1.05 / open ×0.9 / collected ×1.0) and bypassed `ds.quality`
## entirely. Per 平衡参数.md §DatasetSystem 公式 + 任务系统设计.md §6.7.
func _weighted_pretrain_quality(dataset_ids: Array) -> float:
	var total_size: float = 0.0
	var weighted: float = 0.0
	for did in dataset_ids:
		var ds = _find_dataset(StringName(did))
		if ds == null:
			continue
		if ds.kind != &"pretrain":
			continue
		var size: float = maxf(0.0, float(ds.size))
		if size <= 0.0:
			continue
		var q: float = clampf(float(ds.quality), 0.0, 1.0)
		total_size += size
		weighted += size * q
	if total_size <= 0.0:
		return -1.0
	return weighted / total_size

func _pretrain_token_weight(dataset_ids: Array) -> float:
	var total_weight: float = 0.0
	for did in dataset_ids:
		var ds = _find_dataset(StringName(did))
		if ds == null:
			continue
		if ds.kind != &"pretrain":
			continue
		var size: float = maxf(0.0, float(ds.size))
		if size <= 0.0:
			continue
		var q: float = clampf(float(ds.quality), 0.0, 1.0)
		total_weight += size * q
	return total_weight

## v10 (2026-05): broad general/world-knowledge coverage factor.
## Pure specialty pretrain (code/reasoning/agent only) keeps its tag ratio but
## loses raw score because it lacks the broad language and factual substrate of
## real frontier pre-training mixes. Empty coverage_tags count as broad for
## legacy fixtures/saves whose pretrain data predates explicit tag coverage.
func _data_breadth_factor(dataset_ids: Array) -> float:
	if _pretrain_token_weight(dataset_ids) <= 0.0:
		return 1.0
	var share: float = _dataset_weighted_tag_share(dataset_ids, GENERAL_DATA_TAGS, true)
	var normalized: float = clampf(share / DATA_BREADTH_TARGET_SHARE, 0.0, 1.0)
	return DATA_BREADTH_MIN_FACTOR + (1.0 - DATA_BREADTH_MIN_FACTOR) * normalized

# Project staffing for self-collected datasets (v8, 2026-05): every collection
# locks data engineers, scaling with dataset size, clamped to [2, 8]. Mirrors
# marketing's 2..8 rule. "更缓" curve — typical small datasets stay at 2; only
# huge corpora hit 8. Kind-specific because pretrain crawls span 1..100000 B
# tokens while posttrain annotates 0.01..0.5 B. See design/数据集系统设计.md §5.
const _PROJECT_STAFF_MIN: int = 2
const _PROJECT_STAFF_MAX: int = 8
const _DATA_STAFF_BTOKENS_PER_EXTRA_PRETRAIN: float = 4000.0   # +1 工程师 / 4000B (≈8 人需 24T)
const _DATA_STAFF_BTOKENS_PER_EXTRA_POSTTRAIN: float = 0.08    # +1 工程师 / 0.08B (满 8 人近 0.5B 上限)

## data_eng 需求数 (随 kind + size 缩放, clamp [2,8])。公开给对话框复用。
func data_collection_staff_count(kind: StringName, size_b: float) -> int:
	var per: float = _DATA_STAFF_BTOKENS_PER_EXTRA_PRETRAIN if kind == &"pretrain" \
			else _DATA_STAFF_BTOKENS_PER_EXTRA_POSTTRAIN
	var extra: int = int(floor(maxf(0.0, size_b) / maxf(0.0001, per)))
	return clampi(_PROJECT_STAFF_MIN + extra, _PROJECT_STAFF_MIN, _PROJECT_STAFF_MAX)

# Required staff dict {role: count} for a task. Only templates that DECLARE
# `needs_staff` in their input_schema require staff (so the legacy
# data_collection_default fixture — no declaration — still starts resource-free).
# Self-collect (data_collection w/ a declaration) scales data_eng with dataset
# size (2..8) and task_system is authoritative (it locks this amount; the caller
# need not pre-specify). Other templates use the static schema count.
func _required_staff(template: TaskTemplate, p: Dictionary) -> Dictionary:
	var schema_staff: Dictionary = template.input_schema.get(&"needs_staff", {})
	if schema_staff.is_empty():
		return {}
	if template.subtype == &"data_collection":
		var kind: StringName = StringName(p.get(&"kind", &"pretrain"))
		var size_b: float = float(p.get(&"target_size", 0.0))
		return {&"data_eng": data_collection_staff_count(kind, size_b)}
	return schema_staff

# data_scientist lead bonus to posttrain data quality (0 if no lead or the
# first lead isn't a data_scientist).
func _data_collection_lead_bonus(lead_ids: Array) -> float:
	if lead_ids.is_empty():
		return 0.0
	var lead = HiringSystem.find_lead(StringName(lead_ids[0]))
	if lead == null or lead.specialty != &"data_scientist":
		return 0.0
	var table: Dictionary = HiringSystem.LEAD_BONUS_TABLE.get(&"data_scientist", {})
	var coef: float = float(table.get(&"data_quality_add", 0.0))
	return (float(lead.ability) / 100.0) * coef

# Produced dataset quality (clamped to [0,1]); pricing uses the UNCLAMPED labor
# quality and intentionally excludes posttrain-only internal-signal bonuses.
func _data_collection_quality(target_quality: float, lead_ids: Array,
		option_bonus: float = 0.0) -> float:
	return clampf(target_quality + _data_collection_lead_bonus(lead_ids)
			+ option_bonus, 0.0, 1.0)

func _data_collection_option_quality_bonus(kind: StringName, p: Dictionary) -> float:
	if kind != &"posttrain":
		return 0.0
	if not bool(p.get(&"monitor_employee_work_data", false)):
		return 0.0
	return POSTTRAIN_EMPLOYEE_WORK_DATA_QUALITY_ADD

# v2.1: dynamic pricing/duration for self-collected datasets. Per
# design/数据集系统设计.md §5.1ter. kind ∈ {pretrain, posttrain}; size in B tokens.
# Pretrain is unlabeled (cheap, scales mildly with size); posttrain is labeled
# (expensive per token, smaller sizes are typical).
## 2026-05-19: 采集再提速 ×2 + 单任务硬上限 20 周。pretrain 100T 等超大数据
## 不再要 1000 周, 走到上限就 cap 在 20 周 — 后期玩家肯花钱就能短周期拿到大数据。
const _DATA_COLLECTION_MAX_WEEKS: int = 20
const POSTTRAIN_EMPLOYEE_WORK_DATA_QUALITY_ADD: float = 0.03

# Posttrain self-collect labor cost curve (2026-05 rev). Posttrain data cost is
# driven by annotation labor, not token volume — higher quality means pricier
# labelers (crowd → domain → senior expert → PhD). `rate` is $/example; examples
# ≈ size_B × 1e6 (1000 tokens/example).
#
# Priced on EFFECTIVE quality (player-selected target tier + data_scientist lead
# bonus) so a stronger lead → higher-quality data → higher price (closes the
# "cheap tier + strong lead buys PhD data at $1/example" exploit). The rate is a
# CONTINUOUS piecewise curve through these anchors, NOT discrete buckets: a
# higher selected tier — or a stronger lead — always costs strictly more, never
# saturating into a flat top bucket. (The old discrete table priced 资深专家 /
# PhD identically once any lead pushed effective quality past 0.90, so picking
# the expert tier didn't get more expensive.) Anchors keep the legacy per-tier
# rates at the bare tier qualities (no lead). See design/数据集系统设计.md §5.
const _POSTTRAIN_RATE_ANCHORS: Array = [
	[0.65, 1.0],    # T1 众包 crowd
	[0.80, 10.0],   # T2 领域标注员 domain
	[0.85, 50.0],   # mid anchor — keeps purchased-set premium in the 2–4× band
	[0.90, 60.0],   # T3 资深专家 senior expert
	[0.95, 800.0],  # T4 PhD
]
# Above the top anchor (only reachable via lead bonus): gentle exponential so a
# PhD-tier selection + strong lead keeps rising monotonically, never saturates.
const _POSTTRAIN_RATE_TAIL_K: float = 6.0
const _POSTTRAIN_RATE_MAX: float = 5000.0

func _posttrain_labor_rate(effective_quality: float) -> float:
	var a: Array = _POSTTRAIN_RATE_ANCHORS
	var q: float = effective_quality
	if q <= float(a[0][0]):
		return float(a[0][1])
	var top: int = a.size() - 1
	var top_q: float = float(a[top][0])
	if q >= top_q:
		return minf(float(a[top][1]) * exp(_POSTTRAIN_RATE_TAIL_K * (q - top_q)),
				_POSTTRAIN_RATE_MAX)
	for i in range(top):
		var q1: float = float(a[i + 1][0])
		if q <= q1:
			var q0: float = float(a[i][0])
			var r0: float = float(a[i][1])
			var r1: float = float(a[i + 1][1])
			return r0 + (q - q0) / (q1 - q0) * (r1 - r0)
	return float(a[top][1])

func _data_collection_pricing(p: Dictionary) -> Dictionary:
	var kind: StringName = StringName(p.get(&"kind", &"pretrain"))
	var size_b: float = maxf(0.0, float(p.get(&"target_size", 0.0)))
	if kind == &"posttrain":
		# Effective quality = chosen target + lead bonus, so price tracks what you
		# get. UNCLAMPED (no 1.0 ceiling) so the rate curve keeps rising for a
		# PhD-tier pick + strong lead instead of saturating; the produced dataset
		# quality is still clamped in _data_collection_quality. Internal employee
		# work monitoring is not annotation labor, so it does not affect this rate.
		var target_q: float = float(p.get(&"target_quality", 0.65))
		var eff_q: float = target_q + _data_collection_lead_bonus(p.get(&"lead_ids", []))
		var rate: float = _posttrain_labor_rate(eff_q)
		return {
			base_cost = 30_000 + int(round(size_b * 1_000_000.0 * float(rate))),
			weekly_cost = 8_000,
			duration = mini(_DATA_COLLECTION_MAX_WEEKS,
					maxi(3, int(ceil(size_b * 0.6)))),
		}
	return {
		base_cost = 5_000 + int(round(size_b * 5_000.0)),
		weekly_cost = 3_000,
		duration = mini(_DATA_COLLECTION_MAX_WEEKS,
				maxi(2, int(ceil(size_b / 200.0)))),
	}

# Returns the effective base_cost charged at task.start. Templates with a
# `data_collection_law` duration_func compute it from kind+size in payload;
# all other templates fall through to the static template.base_cost.
func _resolve_base_cost(template: TaskTemplate, p: Dictionary) -> int:
	if template.duration_func == &"data_collection_law":
		return int(_data_collection_pricing(p).base_cost)
	if template.duration_func == &"charity_law":
		# Charity donation amount is the up-front (tax-deductible) cost.
		return maxi(0, int(p.get(&"amount", 0)))
	return int(template.base_cost)

# Mirrors _resolve_base_cost for the per-week upkeep cost.
func _resolve_weekly_cost(template: TaskTemplate, p: Dictionary) -> int:
	if template.duration_func == &"data_collection_law":
		return int(_data_collection_pricing(p).weekly_cost)
	return int(template.weekly_cost)

## v9 (2026-05): token×quality weighted share, then log-dampened to a ratio.
## Replaces v8 `count(datasets_with_tag) / count(all)` which (a) didn't reflect
## token volume so a tiny specialty set "claimed" half a ratio, and (b) was
## diluted by mixing in extra unrelated datasets.
##
## share = Σ(d.size × d.quality | d has tag in {tag} ∪ any_of) / Σ(d.size × d.quality)
## ratio = log(1 + TAG_RATIO_LOG_K × share) / log(1 + TAG_RATIO_LOG_K)
##
## K=20 gives: 5% share → 0.23 ratio, 20% → 0.53, 50% → 0.79, 100% → 1.0.
##
## Posttrain datasets are excluded (only pretrain coverage_tags drive evaluate).
## Per 平衡参数.md §DatasetSystem 公式 + 任务系统设计.md §6.7.
func _dataset_tag_ratio(dataset_ids: Array, tag: StringName,
		any_of: Array = []) -> float:
	var needles: Array[StringName] = [tag]
	for needle in any_of:
		var typed := StringName(needle)
		if not needles.has(typed):
			needles.append(typed)
	var share: float = _dataset_weighted_tag_share(dataset_ids, needles)
	return log(1.0 + TAG_RATIO_LOG_K * share) / log(1.0 + TAG_RATIO_LOG_K)

func _dataset_weighted_tag_share(dataset_ids: Array, tags: Array,
		count_untagged_as_hit: bool = false) -> float:
	if dataset_ids.is_empty():
		return 0.0
	var total_weight: float = 0.0
	var hit_weight: float = 0.0
	for did in dataset_ids:
		var ds = _find_dataset(StringName(did))
		if ds == null:
			continue
		if ds.kind != &"pretrain":
			continue
		var size: float = maxf(0.0, float(ds.size))
		if size <= 0.0:
			continue
		var q: float = clampf(float(ds.quality), 0.0, 1.0)
		var w: float = size * q
		total_weight += w
		var ds_tags: Array = ds.coverage_tags as Array
		var hit: bool = false
		if count_untagged_as_hit and ds_tags.is_empty():
			hit = true
		else:
			for needle in tags:
				if ds_tags.has(StringName(needle)):
					hit = true
					break
		if hit:
			hit_weight += w
	if total_weight <= 0.0:
		return 0.0
	return hit_weight / total_weight

func _business_analysis_axis_factor(share: float, min_factor: float) -> float:
	var s: float = clampf(share, 0.0, 1.0)
	return 1.0 - s * (1.0 - min_factor)

# ---- locks --------------------------------------------------------------

func _release_locks(inst: TaskInstance) -> void:
	for lead_id in inst.locked_lead_ids:
		CommandBus.send(&"hiring.release_lead", {lead_id = lead_id, task_id = inst.id})
	for role in inst.locked_staff.keys():
		CommandBus.send(&"hiring.release_staff", {
			role = role, count = int(inst.locked_staff[role]), holder_id = inst.id,
		})
	if inst.locked_datacenter_id != &"":
		CommandBus.send(&"infra.release_from_task", {
			dc_id = inst.locked_datacenter_id, task_id = inst.id,
		})
	for ds_id in inst.locked_dataset_ids:
		CommandBus.send(&"dataset.release", {dataset_id = ds_id, task_id = inst.id})

func _rollback(locked: Dictionary) -> void:
	for ds_id in (locked.datasets as Array):
		CommandBus.send(&"dataset.release", {dataset_id = ds_id, task_id = _peek_next_task_id()})
	if String(locked.dc) != "":
		CommandBus.send(&"infra.release_from_task", {dc_id = locked.dc, task_id = _peek_next_task_id()})
	for entry in (locked.staff as Array):
		CommandBus.send(&"hiring.release_staff", {
			role = entry.role, count = entry.count, holder_id = _peek_next_task_id(),
		})
	for lead_id in (locked.leads as Array):
		CommandBus.send(&"hiring.release_lead", {lead_id = lead_id, task_id = _peek_next_task_id()})

# ---- helpers ------------------------------------------------------------

func _find(task_id: StringName) -> TaskInstance:
	for t in GameState.active_tasks:
		if t.id == task_id:
			return t
	return null

func _load_template(template_id: StringName) -> TaskTemplate:
	var path: String = TEMPLATES.get(template_id, "")
	if path == "":
		return null
	var res := load(path)
	if res is TaskTemplate:
		return res
	return null

func _load_tech_node(node_id: StringName) -> TechNode:
	# Delegate to TechTreeSystem's single source of truth (its NODES registry).
	# v6 (PR-D) reads min_researchers / min_engineers / min_gpu_count from the
	# template during _validate. TechTreeSystem is registered as autoload before
	# TaskSystem in project.godot, so this call is safe at any point after _ready.
	if node_id == &"":
		return null
	return TechTreeSystem.get_node_template(node_id)

func _peek_next_task_id() -> StringName:
	return StringName("task_%04d" % _next_task_seq)

func _consume_next_task_id() -> StringName:
	var id := _peek_next_task_id()
	_next_task_seq += 1
	return id

## _next_task_seq 是会话计数器, 不入存档。读档后恢复它跳过档内已用编号, 否则
## 新任务会和档里的 active_tasks 撞 task ID。
## 这里只 restore 不 dedup: task 是主动 locker, 去重要跨系统重打 dataset / dc /
## lead 的锁标签, 风险高; 且 task 是短期对象 (几周内完成消失), restore 已杜绝
## 新碰撞。被动型对象 (lead / model / product ...) 才在各自系统里做 dedup。
func _on_save_loaded() -> void:
	_next_task_seq = maxi(_next_task_seq,
			GameState.max_seq_for_prefix([GameState.active_tasks], "task_") + 1)

func _find_dataset(ds_id: StringName):
	for ds in GameState.datasets:
		if ds.id == ds_id:
			return ds
	return null

func _find_dc(dc_id: StringName):
	for dc in GameState.datacenters:
		if dc.id == dc_id:
			return dc
	return null

func _find_model(model_id: StringName):
	for m in GameState.models:
		if m.id == model_id:
			return m
	return null

# Override of _complete for evaluate so capability is computed at completion
# time using current model / lead state (not at start time).
func _resolve_evaluate_payload_late(inst: TaskInstance) -> Dictionary:
	var model = _find_model(StringName(inst.completion_payload.get(&"model_id", &"")))
	if model == null:
		return inst.completion_payload
	# Find an eval_lead from locked leads (if any matched).
	var eval_lead = null
	for lid in inst.locked_lead_ids:
		var l = HiringSystem.find_lead(lid)
		if l != null and l.specialty == &"eval_lead":
			eval_lead = l
			break
	var capability = _compute_capability_measured(model, eval_lead)
	var p := inst.completion_payload.duplicate()
	p[&"capability_measured"] = capability
	return p
