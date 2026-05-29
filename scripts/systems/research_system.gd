extends Node

## ResearchSystem v2 — owns models with the 4-state lifecycle.
## Per design/研究系统设计.md.
##
## Lifecycle: pretrain → posttrain (optional, can repeat) → evaluate → publish.
##
##   pretrained ─posttrain─► posttrained ─evaluate─► evaluated ─publish─► published
##                                                          ▲                │
##                                                          │ unpublish      │
##                                                          └────────────────┘
##
## TaskSystem fans out completion events into:
##   research.add_model         (pretrain)  → status = pretrained
##   research.posttrain_apply   (posttrain) → status = posttrained, capability_stale = true
##   research.evaluate_apply    (evaluate)  → status = evaluated, capability revealed
##
## Player can also research.download_open_source to skip training and land
## directly at status = evaluated, provenance = downloaded_os. Deploying a
## public OS release uses research.ensure_open_source_release_published, which
## materializes/reuses that Model and publishes it through the same lifecycle.
##
## API pricing (v6 PR-E + v7 PR-F, 2026-05): the legacy hard ceiling has been
## removed. Players may set any non-negative per_token_price; the market
## reacts via the auto-created api Product's `subscribers` pool, evolved
## weekly in UserSystem based on the price's ratio to a guidance price
## (5× base for OS, 100× base for closed). Base is ¥/token serving cost on
## last-year's-newest GPU. See 研究系统设计.md §4.4 + 用户系统设计.md §5 +
## 平衡参数.md §ResearchSystem.


const OWNED_SLICES: Array[StringName] = [&"models"]

# v6 PR-E pricing constants (per 平衡参数.md §ResearchSystem).
const TURNS_PER_YEAR: int = 52
const OS_GUIDANCE_MULT: float = 5.0       # OS guidance price = 5 × base
const CLOSED_GUIDANCE_MULT: float = 100.0  # closed guidance price = 100 × base
# 2026-05: 算 cost 时 MoE active_param_ratio clamp 到 ≥ 0.125 (8×). 现实
# MoE serving 因路由 / KV / batch 浪费, 实际成本下降远不到论文宣称的 1/20+;
# 不 cap 的话 super_sparse 让 base 塌一个数量级, API 永远白菜价. 仅作用于
# base_price 计算; 训练 FLOPs / serving capacity 仍用原始 active_param_ratio.
const MOE_COST_SPARSITY_FLOOR: float = 0.125
const _SECONDS_PER_WEEK: float = 604_800.0
const _GRID_PER_CARD_FALLBACK: float = 280.0  # ¥/card/week if grid.tres missing

# 2026-05: CapEx 摊销周期 (固定 3 年 = 156 周). baseline weekly_cost 由
# (maint + power) 扩展为 (maint + power + purchase_price / GPU_AMORTIZATION_WEEKS),
# 让指导价反映 GPU 摊销 + 运维的真实云价口径。见 design/研究系统设计.md §4.4。
const GPU_AMORTIZATION_WEEKS: float = 156.0

var _next_model_seq: int = 1

# Yearly-cached baseline: ¥ per TFLOP·second on the best inference GPU released
# in the past year. Recomputed lazily when GameState.turn crosses a year line.
var _baseline_cache: Dictionary = {year = -1, value = 0.0}

func _ready() -> void:
	CommandBus.register(&"research.add_model", _on_add_model)
	CommandBus.register(&"research.posttrain_apply", _on_posttrain_apply)
	CommandBus.register(&"research.evaluate_apply", _on_evaluate_apply)
	CommandBus.register(&"research.download_open_source", _on_download_open_source)
	CommandBus.register(&"research.ensure_open_source_release_published", _on_ensure_open_source_release_published)
	CommandBus.register(&"research.publish_model", _on_publish_model)
	CommandBus.register(&"research.unpublish_model", _on_unpublish_model)
	CommandBus.register(&"research.set_api_price", _on_set_api_price)
	CommandBus.register(&"research.set_open_source", _on_set_open_source)
	CommandBus.register(&"research.delete_model", _on_delete_model)
	CommandBus.register(&"research.rename_model", _on_rename_model)
	# v6 PR-E pricing helpers (UI / tests preview base / guidance / growth rate).
	CommandBus.register(&"research.get_base_price", _on_get_base_price)
	CommandBus.register(&"research.get_guidance_price", _on_get_guidance_price)
	CommandBus.register(&"research.get_weekly_growth_rate", _on_get_weekly_growth_rate)
	# v8 PR-I: stateless pricing previews fed by flops_per_token (PretrainDialog
	# + PriceEditDialog don't have a Model yet). See design §4.8.
	CommandBus.register(&"research.preview_pricing", _on_preview_pricing)
	CommandBus.register(&"research.preview_growth_rate", _on_preview_growth_rate)
	EventBus.save_loaded.connect(_on_save_loaded)

# ---- add (TaskSystem private) -------------------------------------------

func _on_add_model(p: Dictionary) -> Dictionary:
	# Player-driven flow (PretrainDialog) supplies `display_name`. Per design
	# 研究系统设计.md §6.1 + 任务系统设计.md §5.1.1, that string is the model id
	# verbatim. Legacy callers (auto-play, tests) omit it — we fall back to an
	# auto-generated codename. TaskSystem only forwards display_name when the
	# original task.start payload explicitly supplied one.
	var raw_name: String = String(p.get(&"display_name", "")).strip_edges()
	var m := Model.new()
	if raw_name != "":
		if not _is_valid_model_name(raw_name):
			return {ok = false, error = &"invalid_model_name"}
		var sn := StringName(raw_name)
		if find_model(sn) != null:
			return {ok = false, error = &"duplicate_model_name"}
		# Bug 6: 同时检测与 NPC 已发布模型 display_name 的冲突, 避免排行榜里
		# "Wolf-3 (玩家)" 与 NPC "Wolf-3" 并列的混淆。
		if _name_collides_with_npc(raw_name):
			return {ok = false, error = &"duplicate_model_name"}
		m.id = sn
		m.display_name = raw_name
	else:
		m.id = _gen_id()
		m.display_name = String(m.id)
	m.arch = p.get(&"arch", &"")
	# §6.1: a freshly pretrained model has ZERO capability — evaluate is what
	# materialises the real numbers. We deliberately discard whatever
	# `capability` the caller (TaskSystem pretrain payload) supplied so the
	# only path that writes capability is `research.evaluate_apply`.
	m.capability = {
		&"general": 0.0,
		&"code": 0.0,
		&"reasoning": 0.0,
		&"multimodal": 0.0,
		&"agent": 0.0,
	}
	m.capability_revealed = false
	m.capability_stale = false
	var ds: Array = p.get(&"dataset_ids", [])
	var typed_ds: Array[StringName] = []
	for d in ds:
		typed_ds.append(StringName(d))
	m.dataset_ids = typed_ds
	m.size_params = float(p.get(&"size_params", 0.0))
	# v4 (PR-B): MoE archs declare active_param_ratio; flops_per_token must use
	# active params (not total). Dense archs default to 1.0.
	m.active_param_ratio = Model.active_param_ratio_for(m.arch)
	# v5 (PR-C): A/B/C/D axes. Pretrain payload carries attention_id, loss_id,
	# context_length_tokens (PretrainDialog 4 dropdowns). Default baselines for
	# legacy callers.
	m.attention_id = StringName(p.get(&"attention_id", &"mha_baseline"))
	m.loss_id = StringName(p.get(&"loss_id", &"ce_baseline"))
	m.context_length_tokens = int(p.get(&"context_length_tokens", 4096))
	# v7 PR-G: E-axis multimodal method. Default `none` for single-modality models
	# (input_modalities == [text]); PretrainDialog sets to cross_train when image/
	# audio modalities are added. Frozen at pretrain.
	m.multimodal_method = StringName(p.get(&"multimodal_method", &"none"))
	# 科学家预训练加分倍率 (TaskSystem 在完成时按锁定 lead 烘焙)。默认 1.0 = 无加成。
	# Per 任务系统设计.md §6.7。
	m.pretrain_score_mult = float(p.get(&"pretrain_score_mult", 1.0))
	# Bake attention.inference_coef into flops_per_token. If the caller already
	# pre-divided in the payload (TaskSystem completion path), normalize_flops_per_token
	# will pick up the explicit value; otherwise compute from active params and
	# divide by attention.inference_coef.
	var raw_fpt: float = float(p.get(&"flops_per_token", 0.0))
	if raw_fpt <= 0.0:
		var attn_inf: float = _attention_inference_coef(m.attention_id)
		raw_fpt = Model.infer_flops_per_token(m.size_params, m.active_param_ratio) / attn_inf
	m.flops_per_token = Model.normalize_flops_per_token(
			raw_fpt, m.size_params, m.active_param_ratio)
	m.input_modalities = _to_sn_array(p.get(&"input_modalities", [&"text"]))
	m.output_modalities = _to_sn_array(p.get(&"output_modalities", [&"text"]))
	m.trained_at_turn = GameState.turn
	m.status = &"pretrained"
	m.provenance = &"trained"
	GameState.models.append(m)
	Log.info(&"research", "model added", {id = m.id, arch = m.arch, size = m.size_params})
	EventBus.model_added.emit(m.id, m.provenance)
	return {ok = true, model_id = m.id}

# v5 (PR-C): query the attention subtree for the inference_coef of a node.
# Defaults to 1.0 for baseline / unknown so callers don't have to special-case.
## 取后训练 payload lead_ids 的首个 lead (供算后训练科学家加分倍率)。空 → null。
func _resolve_lead(lead_ids):
	if typeof(lead_ids) != TYPE_ARRAY or (lead_ids as Array).is_empty():
		return null
	return HiringSystem.find_lead(StringName(lead_ids[0]))

func _attention_inference_coef(attention_id: StringName) -> float:
	if attention_id == &"" or attention_id == &"mha_baseline":
		return 1.0
	var r: Dictionary = CommandBus.send(&"tech.get_attention_coefs", {attention_id = attention_id})
	if r.get(&"ok", false):
		return float(r.get(&"inference_coef", 1.0))
	return 1.0

func _to_sn_array(arr) -> Array[StringName]:
	var out: Array[StringName] = []
	for v in arr:
		out.append(StringName(v))
	return out

# ---- posttrain (v2) -----------------------------------------------------

## v2: §6.2. For each posttrain dataset, apply target_capability += target_gain
## and (1 - quality) × K to every other axis as forget. Capability is
## materialised here directly (no longer requires re-evaluate to surface).
## Falls back to v1 behavior (just stamp + stale) when no valid posttrain
## datasets are found (legacy callers / dataset_id-only payloads where the
## referenced ds is missing).
##
## 平衡参数: POSTTRAIN_GAIN_K = 8.0, POSTTRAIN_FORGET_K = 8.0,
## POSTTRAIN_CEILING_MULT = 1.4, POSTTRAIN_SATURATION_SCALE = 35.0 (v12 防刷分).
const POSTTRAIN_GAIN_K: float = 8.0
const POSTTRAIN_FORGET_K: float = 8.0
const POSTTRAIN_CEILING_MULT: float = 1.4
const POSTTRAIN_SATURATION_SCALE: float = 35.0
const CAPABILITY_AXES: Array[StringName] = [
	&"general", &"code", &"reasoning", &"multimodal", &"agent",
]

func _on_posttrain_apply(p: Dictionary) -> Dictionary:
	var m := find_model(p.get(&"model_id", &""))
	if m == null:
		return {ok = false, error = &"unknown_model"}
	if m.status == &"published":
		return {ok = false, error = &"already_published"}

	# Accept either v2 dataset_ids[] or legacy dataset_id singleton.
	var dataset_ids: Array = p.get(&"dataset_ids", [])
	if dataset_ids.is_empty():
		var single_id: StringName = p.get(&"dataset_id", &"")
		if single_id != &"":
			dataset_ids = [single_id]

	# Append to model.dataset_ids for audit, dedup.
	for ds_id in dataset_ids:
		var ds_sn := StringName(ds_id)
		if ds_sn != &"" and not m.dataset_ids.has(ds_sn):
			m.dataset_ids.append(ds_sn)

	# Resolve dataset_ids → Dataset[], skip nulls. simulate_posttrain itself
	# does kind / target_capability filtering, but we still track whether any
	# valid posttrain dataset existed so the v1 stale-fallback path can fire
	# below for legacy callers (wrong-kind dataset, missing dataset).
	var resolved: Array = []
	var any_posttrain_applied: bool = false
	for ds_id in dataset_ids:
		var ds = DatasetSystem.find_dataset(StringName(ds_id))
		if ds == null:
			continue
		resolved.append(ds)
		if ds.kind == &"posttrain" and ds.target_capability != &"" \
				and CAPABILITY_AXES.has(ds.target_capability):
			any_posttrain_applied = true

	# Run the shared pure simulator. The dialog preview calls this same function
	# (with the same base_power) so its capability_delta_preview matches the apply
	# outcome exactly (see 研究系统设计.md §5.3 v2.1 preview-apply consistency clause).
	# base_power is captured BEFORE mutating m.capability, and excludes posttrain_delta
	# inside posttrain_base_power so the soft ceiling tracks pretrain investment only.
	var base_power: float = posttrain_base_power(m)
	# 后训练科学家加分: 由完成 payload 锁定的 lead 的 posttrain_score_bonus 抬高 ceiling。
	# 预览 (PosttrainDialog) 用同一倍率, 保证 preview == apply (§5.3 v2.1 契约)。
	var score_mult: float = HiringSystem.lead_score_mult(
			_resolve_lead(p.get(&"lead_ids", [])), &"posttrain_score_bonus")
	var sim: Dictionary = simulate_posttrain(m.capability, resolved, base_power, score_mult)
	m.capability = (sim.capability as Dictionary).duplicate()
	var delta: Dictionary = (sim.delta as Dictionary).duplicate()

	# Bug B fix (2026-05): accumulate clamp-aware delta into m.posttrain_delta
	# so research.evaluate_apply can layer it back on top of capability_measured.
	# Without this, a later evaluate would erase the axis-directional shift the
	# player saw in the posttrain dialog. Per 研究系统设计.md §6.2.
	for ax in CAPABILITY_AXES:
		m.posttrain_delta[ax] = float(m.posttrain_delta.get(ax, 0.0)) + float(delta[ax])

	if any_posttrain_applied:
		# v2: capability is now authoritative; no stale flag needed.
		m.capability_revealed = true
		m.capability_stale = false
	else:
		# Compat path: legacy callers / no valid posttrain dataset found. Keep
		# v1 stale semantics so the publish gate still forces a re-evaluate.
		if m.capability_revealed:
			m.capability_stale = true

	m.status = &"posttrained"
	m.posttrain_count += 1
	EventBus.model_updated.emit(m.id, delta)
	Log.info(&"research", "posttrain applied", {
		id = m.id, posttrain_count = m.posttrain_count, delta = delta,
		posttrain_delta_total = m.posttrain_delta,
		applied_v2 = any_posttrain_applied,
	})
	return {ok = true, capability_delta = delta}

## v12 (2026-05) pretrained "raw power" — the soft-ceiling basis for posttrain
## specialization. = max(size-scaling head, strongest *pretrained* axis):
##   - size head mirrors evaluate's `base = clamp(20 + 12·log10(size/100), 10, 95)`
##     so bigger models earn a higher posttrain ceiling.
##   - strongest pretrained axis subtracts m.posttrain_delta so repeated posttrain
##     runs can't ratchet the ceiling upward (the ceiling tracks pretrain
##     investment / realized pretrain quality, not posttrain gains themselves).
## apply 与 PosttrainDialog 预览共用此函数 (v2.1 preview-apply 一致性契约).
## Per 研究系统设计.md §4.2.
func posttrain_base_power(model) -> float:
	if model == null:
		return 0.0
	var size_m: float = maxf(float(model.size_params), 1.0)
	var size_head: float = clampf(
			20.0 + 12.0 * (log(size_m / 100.0) / log(10.0)), 10.0, 95.0)
	var pretrained_max: float = 0.0
	for ax in CAPABILITY_AXES:
		var cur: float = float(model.capability.get(ax, 0.0))
		var pt: float = float(model.posttrain_delta.get(ax, 0.0))
		pretrained_max = maxf(pretrained_max, cur - pt)
	return maxf(size_head, pretrained_max)

## Pure simulator shared by research.posttrain_apply (above) and PosttrainDialog
## preview. Per 研究系统设计 §4.2 (apply 公式) + §5.3 (v2.1 preview-apply
## consistency clause): apply 和预览必须用同一份公式 + 同一 base_power.
##
## v12 (2026-05) 防刷分重写, 两层:
##   1. 按 target_capability 聚合: 同轴数据集合并成 T=Σsize、q̄=Σ(q·size)/T, log 只
##      对聚合总量取一次 → 把一份拆成多小份与一整份完全等价 (杀拆碎漏洞)。
##   2. 目标轴朝软天花板 (base_power × CEILING_MULT) 指数饱和, 永不超过 ceiling 且
##      边际递减 → 堆再多数据也刷不到无穷 (杀无限堆漏洞)。
## forget = K_forget·max(0,1-q̄) 施加到其余轴, clamp ≥0; 轴组按固定轴序结算 (确定性)。
##
## Inputs:
##   initial_capability — Dictionary keyed by capability axis. Missing axes → 0.
##   datasets           — Array of Dataset resources. Wrong-kind / missing
##                        target_capability datasets are silently skipped.
##   base_power         — 软天花板基准, 由 posttrain_base_power(model) 得出。0 →
##                        ceiling 0 → 目标轴无增益 (防御: 调用方漏传时不刷分)。
##
## Returns: {capability: Dictionary, delta: Dictionary} — both keyed by axis.
##   capability = final state after aggregation + saturation, axes clamped ≥ 0.
##   delta      = realized (after - before) per axis (目标轴记实际 realized 而非
##                名义 raw_gain; forget 记 clamp 后真实差值)。
func simulate_posttrain(initial_capability: Dictionary, datasets: Array,
		base_power: float = 0.0, score_mult: float = 1.0) -> Dictionary:
	# score_mult (默认 1.0 = 无加成): 后训练科学家 (ml_research_lead) 的
	# posttrain_score_bonus 抬高软天花板 → 同样的数据能把目标轴推得更高 (仍受 ceiling
	# 限制, 不会无限堆)。Per 研究系统设计.md §4.2 + 招聘系统设计.md §5.1。
	var caps: Dictionary = {}
	var delta: Dictionary = {}
	for ax in CAPABILITY_AXES:
		caps[ax] = float(initial_capability.get(ax, 0.0))
		delta[ax] = 0.0
	# Step 1: aggregate per target axis (kills fragmentation — see header).
	var tokens: Dictionary = {}       # axis -> Σ size_b
	var q_weighted: Dictionary = {}   # axis -> Σ (quality × size_b)
	for ds in datasets:
		if ds == null or ds.kind != &"posttrain":
			continue
		var axis: StringName = ds.target_capability
		if axis == &"" or not CAPABILITY_AXES.has(axis):
			continue
		var q: float = clampf(float(ds.quality), 0.0, 1.0)
		var size_b: float = maxf(0.0, float(ds.size))
		tokens[axis] = float(tokens.get(axis, 0.0)) + size_b
		q_weighted[axis] = float(q_weighted.get(axis, 0.0)) + q * size_b
	# Step 2: per axis group, saturate target toward ceiling, forget the rest.
	# 科学家加分抬高 ceiling (score_mult≥1.0), 让强 lead 把目标轴推得更高。
	var ceiling: float = maxf(0.0, base_power) * POSTTRAIN_CEILING_MULT * maxf(1.0, score_mult)
	for axis in CAPABILITY_AXES:
		var total_tokens: float = float(tokens.get(axis, 0.0))
		if total_tokens <= 0.0:
			continue
		var qbar: float = clampf(float(q_weighted[axis]) / total_tokens, 0.0, 1.0)
		# log2(1 + T × 1000): a 0.05B (50M token) aggregate gets log2(51) ≈ 5.67.
		var size_factor: float = log(1.0 + total_tokens * 1000.0) / log(2.0)
		var raw_gain: float = POSTTRAIN_GAIN_K * qbar * qbar * size_factor
		var forget: float = POSTTRAIN_FORGET_K * maxf(0.0, 1.0 - qbar)
		# Target axis: exponential approach to ceiling (never exceeds it).
		var c0: float = float(caps[axis])
		var realized: float = 0.0
		if ceiling > c0:
			realized = (ceiling - c0) * (1.0 - exp(-raw_gain / POSTTRAIN_SATURATION_SCALE))
		caps[axis] = c0 + realized
		delta[axis] = float(delta[axis]) + realized
		# Other axes: forgetting, clamped to ≥ 0.
		for other in CAPABILITY_AXES:
			if other == axis:
				continue
			var before: float = float(caps[other])
			var after: float = maxf(0.0, before - forget)
			caps[other] = after
			delta[other] = float(delta[other]) + (after - before)
	return {capability = caps, delta = delta}

# ---- evaluate -----------------------------------------------------------

## §6.3: evaluate writes the authoritative capability over the (previously
## hidden / stale) values. Sets revealed=true and clears stale flag.
func _on_evaluate_apply(p: Dictionary) -> Dictionary:
	var m := find_model(p.get(&"model_id", &""))
	if m == null:
		return {ok = false, error = &"unknown_model"}
	if m.status == &"published":
		return {ok = false, error = &"already_published"}
	var measured: Dictionary = p.get(&"capability_measured", {})
	# Bug B fix (2026-05): layer m.posttrain_delta on top of measured so the
	# axis-directional shifts from posttrain survive re-evaluation. clamp ≥ 0
	# per 研究系统设计.md §6.3.
	var caps: Dictionary = {}
	for ax in CAPABILITY_AXES:
		var base_val: float = float(measured.get(ax, 0.0))
		var pt_val: float = float(m.posttrain_delta.get(ax, 0.0))
		caps[ax] = maxf(0.0, base_val + pt_val)
	m.capability = caps
	m.capability_revealed = true
	m.capability_stale = false
	m.status = &"evaluated"
	Log.info(&"research", "model evaluated", {
		id = m.id, capability = m.capability,
		measured_before_overlay = measured,
		posttrain_delta = m.posttrain_delta,
	})
	EventBus.model_evaluated.emit(m.id, m.capability)
	# Also fire model_updated so legacy subscribers (ProductSystem quality
	# recompute, UI list refreshers) pick up the new capability without having
	# to subscribe to the new signal.
	EventBus.model_updated.emit(m.id, {})
	return {ok = true}

# ---- download open-source ----------------------------------------------

## v9 PR-I: instantiate a Model from an OS NPC's pretrain release. The release
## carries arch / params / cluster lore; flops_per_token is derived via the
## same formula as player-trained models. Per design/研究系统设计.md §4.5 +
## NPC配置.md §2.6.
func _on_download_open_source(p: Dictionary) -> Dictionary:
	var release_id: StringName = p.get(&"release_id", &"")
	var resolved: Dictionary = _resolve_open_source_release(release_id)
	if not resolved.get(&"ok", false):
		return {ok = false, error = StringName(resolved.get(&"error", &"unknown_release"))}
	var npc = resolved.npc
	var release = resolved.release
	var m := _make_downloaded_model_from_release(release_id, release)
	_append_downloaded_model(m, release_id, npc.id)
	return {ok = true, model_id = m.id}

func _on_ensure_open_source_release_published(p: Dictionary) -> Dictionary:
	var release_id: StringName = p.get(&"release_id", &"")
	var resolved: Dictionary = _resolve_open_source_release(release_id)
	if not resolved.get(&"ok", false):
		return {ok = false, error = StringName(resolved.get(&"error", &"unknown_release"))}
	var npc = resolved.npc
	var release = resolved.release
	var created: bool = false
	var published: bool = false
	var m := _find_downloaded_model_for_release(release_id, release)
	if m == null:
		m = _make_downloaded_model_from_release(release_id, release)
		_append_downloaded_model(m, release_id, npc.id)
		created = true
	if m.status != &"published":
		if m.status != &"evaluated":
			return {ok = false, error = &"not_evaluated"}
		var requested: float = float(m.per_token_price)
		if p.has(&"per_token_price"):
			requested = float(p[&"per_token_price"])
		elif p.has("per_token_price"):
			requested = float(p["per_token_price"])
		elif requested <= 0.0:
			requested = guidance_price_per_token(m)
		var pub: Dictionary = _on_publish_model({
			model_id = m.id,
			is_open_source = true,
			per_token_price = requested,
		})
		if not pub.get(&"ok", false):
			return pub
		published = true
	else:
		if not m.is_open_source:
			m.is_open_source = true
		# Re-emit the lifecycle signal so old saves with a published downloaded_os
		# model but no API product self-heal through ProductSystem's idempotent path.
		EventBus.model_published.emit(m.id, m.is_open_source)
	Log.info(&"research", "open_source_release_ensured", {
		release_id = release_id,
		model_id = m.id,
		created = created,
		published = published,
		price = m.per_token_price,
	})
	return {
		ok = true,
		model_id = m.id,
		created = created,
		published = published,
		applied_price = m.per_token_price,
	}

func _resolve_open_source_release(release_id: StringName) -> Dictionary:
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

func _make_downloaded_model_from_release(release_id: StringName, release) -> Model:
	var size_m: float = float(release.params_b) * 1000.0
	var active_ratio: float = 1.0
	if float(release.params_b) > 0.0:
		active_ratio = float(release.active_params_b) / float(release.params_b)

	var m := Model.new()
	m.id = _gen_id()
	m.display_name = release.display_name
	m.arch = release.arch_codename
	m.size_params = size_m
	m.active_param_ratio = active_ratio
	m.flops_per_token = Model.infer_flops_per_token(size_m, active_ratio)
	# OS NPC releases don't yet declare attention/loss/context axes; default to
	# baselines (same as legacy save load path). Future: extend NpcModelRelease.
	m.attention_id = &"mha_baseline"
	m.loss_id = &"ce_baseline"
	m.context_length_tokens = 4096
	m.input_modalities = [&"text"]
	m.output_modalities = [&"text"]
	m.capability = release.capability.duplicate()
	m.capability_revealed = true
	m.capability_stale = false
	m.dataset_ids = []
	m.trained_at_turn = GameState.turn
	m.status = &"evaluated"
	m.provenance = &"downloaded_os"
	m.source_release_id = release_id
	return m

func _append_downloaded_model(m: Model, release_id: StringName, npc_id: StringName) -> void:
	GameState.models.append(m)
	Log.info(&"research", "model downloaded", {
		id = m.id, release_id = release_id, npc_id = npc_id})
	EventBus.model_added.emit(m.id, m.provenance)
	EventBus.model_evaluated.emit(m.id, m.capability)
	EventBus.model_updated.emit(m.id, {})

func _find_downloaded_model_for_release(release_id: StringName, release) -> Model:
	for m in GameState.models:
		if m.provenance == &"downloaded_os" and m.source_release_id == release_id:
			return m
	for m in GameState.models:
		if m.provenance != &"downloaded_os":
			continue
		if m.source_release_id != &"":
			continue
		if String(m.display_name) != String(release.display_name):
			continue
		m.source_release_id = release_id
		Log.info(&"research", "legacy_downloaded_model_release_linked", {
			model_id = m.id, release_id = release_id})
		return m
	return null

# ---- publish / unpublish ------------------------------------------------

## §6.4: publish requires status==evaluated AND capability fresh. Pricing floors
## at 0 and then UserSystem applies demand elasticity through the api product.
## Open/closed source choice is permanent — see set_open_source error path below.
func _on_publish_model(p: Dictionary) -> Dictionary:
	var m := find_model(p.get(&"model_id", &""))
	if m == null:
		return {ok = false, error = &"unknown_model"}
	if m.status == &"published":
		return {ok = false, error = &"already_published"}
	if m.status != &"evaluated":
		return {ok = false, error = &"not_evaluated"}
	if m.capability_stale:
		return {ok = false, error = &"capability_stale"}
	# Bug fix 2026-05: posttrain 任务进行中不能发布。否则 posttrain 完成时
	# _on_posttrain_apply 会因 already_published 拒绝, 玩家几周算力白花。
	# 见 design/研究系统设计.md §4.4。
	for t in GameState.active_tasks:
		if t.subtype == &"posttrain" and t.base_model_id == m.id:
			return {ok = false, error = &"posttrain_in_progress"}
	m.status = &"published"
	m.is_open_source = bool(p.get(&"is_open_source", false))
	var requested: float = float(p.get(&"per_token_price", 0.0))
	# v7 PR-F (2026-05): no hard clamp — only floor to 0. Market elasticity
	# is applied to the auto-created api Product's `subscribers` pool by
	# UserSystem (see 用户系统设计.md §5).
	m.per_token_price = maxf(0.0, requested)
	Log.info(&"research", "model_published", {
		model_id = m.id, open_source = m.is_open_source, price = m.per_token_price})
	EventBus.model_published.emit(m.id, m.is_open_source)
	return {ok = true, applied_price = m.per_token_price}

func _on_unpublish_model(p: Dictionary) -> Dictionary:
	var m := find_model(p.get(&"model_id", &""))
	if m == null:
		return {ok = false, error = &"unknown_model"}
	if m.status != &"published":
		return {ok = false, error = &"not_published"}
	if _has_product_binding(m.id):
		return {ok = false, error = &"in_use_by_product"}
	# Auto-undeploy from any datacenters serving this model.
	for dc in GameState.datacenters:
		if dc.deployed_model_id == m.id:
			CommandBus.send(&"infra.undeploy_model", {dc_id = dc.id})
	# Capability stays revealed; we just drop back to evaluated so the player
	# can re-publish (after re-pricing) without a new evaluate task.
	m.status = &"evaluated"
	m.unpublished_at_turn = GameState.turn
	EventBus.model_unpublished.emit(m.id)
	return {ok = true}

# ---- pricing ------------------------------------------------------------

## v7 PR-F (2026-05): no hard ceiling, only floor to 0. Market elasticity
## lives on the api Product.subscribers pool in UserSystem — see
## 研究系统设计.md §4.4 + 用户系统设计.md §5.
func _on_set_api_price(p: Dictionary) -> Dictionary:
	var m := find_model(p.get(&"model_id", &""))
	if m == null:
		return {ok = false, error = &"unknown_model"}
	var requested: float = float(p.get(&"per_token_price", 0.0))
	m.per_token_price = maxf(0.0, requested)
	EventBus.model_price_changed.emit(m.id, m.per_token_price)
	return {ok = true, applied_price = m.per_token_price}

## set_open_source is a pre-publish toggle for the open/closed flag. Once
## published, the choice is permanent (see §1).
func _on_set_open_source(p: Dictionary) -> Dictionary:
	var m := find_model(p.get(&"model_id", &""))
	if m == null:
		return {ok = false, error = &"unknown_model"}
	if m.status == &"published":
		return {ok = false, error = &"already_published"}
	m.is_open_source = bool(p.get(&"is_open_source", false))
	return {ok = true}

# ---- v6 PR-E pricing commands -------------------------------------------

func _on_get_base_price(p: Dictionary) -> Dictionary:
	var m := find_model(p.get(&"model_id", &""))
	if m == null:
		return {ok = false, error = &"unknown_model"}
	return {ok = true, price = base_price_per_token(m)}

func _on_get_guidance_price(p: Dictionary) -> Dictionary:
	var m := find_model(p.get(&"model_id", &""))
	if m == null:
		return {ok = false, error = &"unknown_model"}
	return {ok = true, price = guidance_price_per_token(m)}

func _on_get_weekly_growth_rate(p: Dictionary) -> Dictionary:
	var m := find_model(p.get(&"model_id", &""))
	if m == null:
		return {ok = false, error = &"unknown_model"}
	var guidance: float = guidance_price_per_token(m)
	var ratio: float = 0.0 if guidance <= 0.0 else m.per_token_price / guidance
	return {ok = true, rate = weekly_growth_rate(m), ratio_to_guidance = ratio}

# v8 PR-I — stateless pricing previews. Used by PretrainDialog (no Model yet)
# and PriceEditDialog (player typing a candidate price). Same formulas as
# §4.4 but parameterised by flops_per_token instead of a Model. See
# design/研究系统设计.md §4.8.
func _on_preview_pricing(p: Dictionary) -> Dictionary:
	var fpt: float = float(p.get(&"flops_per_token", 0.0))
	if fpt <= 0.0:
		return {ok = false, error = &"invalid_flops"}
	# 2026-05: 可选 active_param_ratio 让 PretrainDialog 把 arch 信息带进来,
	# 触发 MoE cost-sparsity 8× cap. 默认 1.0 不动 fpt.
	var active: float = float(p.get(&"active_param_ratio", 1.0))
	var base: float = _base_price_from_flops(fpt, active)
	return {
		ok = true,
		base_price = base,
		guidance_open = base * OS_GUIDANCE_MULT,
		guidance_closed = base * CLOSED_GUIDANCE_MULT,
	}

func _on_preview_growth_rate(p: Dictionary) -> Dictionary:
	var fpt: float = float(p.get(&"flops_per_token", 0.0))
	if fpt <= 0.0:
		return {ok = false, error = &"invalid_flops"}
	var price: float = max(0.0, float(p.get(&"per_token_price", 0.0)))
	var is_open: bool = bool(p.get(&"is_open_source", false))
	var active: float = float(p.get(&"active_param_ratio", 1.0))
	var base: float = _base_price_from_flops(fpt, active)
	var mult: float = OS_GUIDANCE_MULT if is_open else CLOSED_GUIDANCE_MULT
	var guidance: float = base * mult
	var ratio: float = 0.0 if guidance <= 0.0 else price / guidance
	return {
		ok = true,
		rate = _weekly_growth_rate_from_ratio(ratio, guidance),
		ratio_to_guidance = ratio,
	}

func _base_price_from_flops(fpt: float, active_ratio: float = 1.0) -> float:
	# Mirror base_price_per_token's MoE 8× cap so the stateless preview matches
	# the Model-bound path (PretrainDialog → preview_pricing). See §4.4.
	var eff_fpt: float = fpt
	if active_ratio > 0.0 and active_ratio < MOE_COST_SPARSITY_FLOOR:
		eff_fpt = fpt * MOE_COST_SPARSITY_FLOOR / active_ratio
	return _yearly_baseline_dollar_per_tflop_second() * eff_fpt / 1.0e12

func _weekly_growth_rate_from_ratio(r: float, guidance: float) -> float:
	if guidance <= 0.0:
		return 0.0
	if r <= 0.6:
		return 0.02
	if r <= 1.0:
		return 0.05 - 0.05 * r
	if r < 2.5:
		return -0.10 * (r - 1.0)
	return -1.0

# ---- delete / rename ----------------------------------------------------

func _on_delete_model(p: Dictionary) -> Dictionary:
	var m := find_model(p.get(&"model_id", &""))
	if m == null:
		return {ok = false, error = &"unknown_model"}
	if _is_serving_anywhere(m.id) or _has_product_binding(m.id):
		return {ok = false, error = &"in_use"}
	if m.status == &"published":
		return {ok = false, error = &"already_published"}
	GameState.models.erase(m)
	EventBus.model_deleted.emit(m.id)
	return {ok = true}

func _on_rename_model(p: Dictionary) -> Dictionary:
	var m := find_model(p.get(&"model_id", &""))
	if m == null:
		return {ok = false, error = &"unknown_model"}
	m.display_name = p.get(&"display_name", m.display_name)
	EventBus.model_updated.emit(m.id, {})
	return {ok = true}

# ---- helpers ------------------------------------------------------------

func find_model(model_id: StringName) -> Model:
	for m in GameState.models:
		if m.id == model_id:
			return m
	return null

func capability_total(m: Model) -> float:
	var s: float = 0.0
	for v in m.capability.values():
		s += float(v)
	return s

func _has_product_binding(model_id: StringName) -> bool:
	# §0bis: type=api 的产品**不算**绑定 — unpublish 时它由 ProductSystem
	# 静默清理, 不应阻挡 unpublish. 只看订阅类型产品.
	for prod in GameState.products:
		if prod.bound_model_id != model_id:
			continue
		if "type" in prod and prod.type == &"api":
			continue
		return true
	return false

func _is_serving_anywhere(model_id: StringName) -> bool:
	for dc in GameState.datacenters:
		if dc.deployed_model_id == model_id:
			return true
	return false

func _gen_id() -> StringName:
	var seq := _next_model_seq
	_next_model_seq += 1
	return StringName("model_%04d" % seq)

## _next_model_seq 是会话计数器, 不入存档。读档后恢复它 + 修旧档已有的重复
## model ID, 否则读档后新训练的模型会和档里的撞 ID (find_model 取首个 → 部署 /
## 评估 / 榜单解析到错的模型)。详见 design/数据集系统设计.md §3 同类病。
func _on_save_loaded() -> void:
	_next_model_seq = maxi(_next_model_seq,
			GameState.max_seq_for_prefix([GameState.models], "model_") + 1)
	for ch in GameState.dedup_ids([GameState.models], _gen_id):
		Log.warn(&"research", "save_loaded_duplicate_model_id_repaired",
				{old_id = ch.old_id, new_id = ch.new_id})

## Bug 6: 玩家命名查重要扫 NPC 已 released 的模型名 (turn ≤ GameState.turn)。
## 还没释出的未来 release 不算 — 避免提前剧透时间线。比较走 lower-case 字符串,
## "Wolf-3" 与 "wolf-3" 视为同名。
func _name_collides_with_npc(candidate_name: String) -> bool:
	var needle: String = candidate_name.to_lower()
	for npc in GameState.npc_companies:
		var releases: Array = npc.model_releases if "model_releases" in npc else []
		for r in releases:
			if int(r.release_turn) > GameState.turn:
				continue
			if String(r.display_name).strip_edges().to_lower() == needle:
				return true
	return false

# Validation for player-supplied model names. Per 任务系统设计.md §5.1.1:
# trimmed length 1..40, only Chinese / English letters / digits / dash /
# underscore / dot / space. No leading/trailing whitespace (we strip_edges
# before calling). Other punctuation is rejected so the id is safe to use
# in StringName, .tres filenames, and UI labels.
const _MAX_MODEL_NAME_LEN: int = 40
func _is_valid_model_name(candidate_name: String) -> bool:
	if candidate_name.is_empty() or candidate_name.length() > _MAX_MODEL_NAME_LEN:
		return false
	for c in candidate_name:
		var ok: bool = false
		if c.is_valid_int(): ok = true
		elif c == "-" or c == "_" or c == "." or c == " ": ok = true
		elif c.to_lower() != c.to_upper(): ok = true  # any cased letter (incl. CJK)
		elif c.unicode_at(0) >= 0x4E00 and c.unicode_at(0) <= 0x9FFF: ok = true
		if not ok:
			return false
	return true

# ---- v6 PR-E pricing helpers --------------------------------------------

## ¥/token base serving cost for a model. Computed from the yearly baseline
## (¥ per TFLOP·second on last-year's-newest GPU) and the model's
## flops_per_token, which already folds in MoE active_param_ratio and
## attention.inference_coef. Engineering tree's flops_per_token_reduction is
## NOT applied here — it lives in InfraSystem.serving_tokens_per_sec.
##
## 2026-05: MoE cost-sparsity 8× cap. active_param_ratio < 0.125 时把 fpt
## 抬到 active=0.125 等效 (现实 super_sparse serving 实际成本下降远不到
## 1/40, 不 cap 玩家 API 永远白菜价). 仅 base_price 这条路径用 cap, 训练
## 与 serving capacity 仍读原始 m.flops_per_token.
func base_price_per_token(m: Model) -> float:
	var dollar_per_tflop_second: float = _yearly_baseline_dollar_per_tflop_second()
	var fpt: float = float(m.flops_per_token)
	if fpt <= 0.0:
		return 0.0
	var active: float = float(m.active_param_ratio)
	if active > 0.0 and active < MOE_COST_SPARSITY_FLOOR:
		fpt = fpt * MOE_COST_SPARSITY_FLOOR / active
	return dollar_per_tflop_second * fpt / 1.0e12

## ¥/token guidance price = 5 × base (OS) or 100 × base (closed). Players who
## charge at or below this don't lose demand multiplier; above it the
## multiplier decays weekly per weekly_growth_rate. downloaded_os models
## follow the OS branch even when is_open_source = false.
func guidance_price_per_token(m: Model) -> float:
	var base: float = base_price_per_token(m)
	var mult: float = CLOSED_GUIDANCE_MULT
	if m.is_open_source or m.provenance == &"downloaded_os":
		mult = OS_GUIDANCE_MULT
	return base * mult

## Weekly growth rate of the demand multiplier for a model at its current
## per_token_price. ∈ [-1.0, +0.02]. Special value -1.0 signals the "cliff":
## demand is zero this week but the multiplier itself is NOT mutated, so a
## price drop next week restores demand from where it was.
##   r ≤ 0.6:   +2%
##   r ≤ 1.0:   +2% → 0   (linear, 0.05 - 0.05 r)
##   r <  2.5:   0 → -15% (linear, -0.10 × (r - 1.0))  (v11 ×0.5)
##   r ≥ 2.5:   cliff (-1.0)
func weekly_growth_rate(m: Model) -> float:
	var guidance: float = guidance_price_per_token(m)
	if guidance <= 0.0:
		return 0.0
	return _weekly_growth_rate_from_ratio(m.per_token_price / guidance, guidance)

## ¥ / (TFLOP × second), the yearly-snapshot serving cost reference. Cached
## per game-year (52 turns); when the cache miss fires we re-scan GPU_SPECS
## for the "best inference TFLOPs" card released within the past year. If no
## GPU was released in the past year (early game), fall back to the best card
## released by year_start.
func _yearly_baseline_dollar_per_tflop_second() -> float:
	var year: int = GameState.turn / TURNS_PER_YEAR
	if int(_baseline_cache.get(&"year", -1)) == year:
		return float(_baseline_cache.get(&"value", 0.0))
	var year_start: int = year * TURNS_PER_YEAR
	var window_lo: int = year_start - TURNS_PER_YEAR
	var best = null
	for gpu_id in InfraSystem.GPU_SPECS.keys():
		var path: String = InfraSystem.GPU_SPECS.get(gpu_id, "")
		if path == "":
			continue
		var g = load(path)
		if g == null or not ("per_card_inference_tflops" in g):
			continue
		var rt: int = int(g.release_turn)
		# Past-year window: [year_start - 52, year_start)
		if rt < window_lo or rt >= year_start:
			continue
		if best == null or float(g.per_card_inference_tflops) > float(best.per_card_inference_tflops):
			best = g
	if best == null:
		# Fallback: best GPU released anytime up to year_start (handles year 0
		# when nothing was released in [-52, 0)).
		for gpu_id in InfraSystem.GPU_SPECS.keys():
			var path2: String = InfraSystem.GPU_SPECS.get(gpu_id, "")
			if path2 == "":
				continue
			var g2 = load(path2)
			if g2 == null or not ("per_card_inference_tflops" in g2):
				continue
			if int(g2.release_turn) > year_start:
				continue
			if best == null or float(g2.per_card_inference_tflops) > float(best.per_card_inference_tflops):
				best = g2
	if best == null:
		_baseline_cache = {year = year, value = 0.0}
		return 0.0
	var grid_per_card: float = _GRID_PER_CARD_FALLBACK
	var grid_path: String = InfraSystem.POWER_SPECS.get(&"grid", "")
	if grid_path != "":
		var grid = load(grid_path)
		if grid != null and "weekly_cost_per_card" in grid:
			grid_per_card = float(grid.weekly_cost_per_card)
	# 2026-05: electricity scales by the baseline GPU's power_factor (§4.2) so the
	# serving-cost basis matches what upkeep actually charges on that GPU.
	grid_per_card *= float(best.power_factor) if "power_factor" in best else 1.0
	# 2026-05: weekly_cost 包含 CapEx 摊销 (购卡价 / 156 周). 纯 OpEx 让指导
	# 价比真实云价低 ~6×, MoE 稀疏后期 API 必触 2.5× cliff. 见 §4.4。
	var capex_per_week: float = 0.0
	if "purchase_price" in best:
		capex_per_week = float(best.purchase_price) / GPU_AMORTIZATION_WEEKS
	var weekly_cost: float = float(best.maintenance_per_week) + grid_per_card + capex_per_week
	var denom: float = float(best.per_card_inference_tflops) * _SECONDS_PER_WEEK * float(best.native_cluster_eff)
	var value: float = 0.0
	if denom > 0.0:
		value = weekly_cost / denom
	_baseline_cache = {year = year, value = value}
	return value
