extends Node

## TechTreeSystem v2 — owns unlocks / researching_nodes.
## Per design/科技树系统设计.md.
##
## Six trees (arch / attention / loss / engineering / application / context). Player calls
## `tech.start_research` which forwards to `task.start`; on completion the task
## fan-out calls back `tech.unlock_node`.
##
## Migration: old tree ids `inference` and `agent` are still accepted (call
## sites that haven't been updated yet); they are normalized to the new ids
## via `TREE_ID_ALIAS` before any read or write.


const OWNED_SLICES: Array[StringName] = [&"unlocks", &"researching_nodes"]

# Old tree id -> new tree id. Any incoming `tree` argument is normalized
# through this map so legacy callers (and old saves) keep working during the
# transition.
const TREE_ID_ALIAS: Dictionary = {
	&"inference": &"engineering",
	&"agent": &"application",
}

# Static node registry. Path-by-id; keep in sync with resources/data/tech/.
# Canonical animal-codename ids per 公共枚举表.md §7 / §13 + 平衡参数.md §TechTree.
const NODES: Dictionary = {
	# arch tree
	&"ant_v1": "res://resources/data/tech/arch/ant_v1.tres",
	&"ant_v2": "res://resources/data/tech/arch/ant_v2.tres",
	&"bee_v1": "res://resources/data/tech/arch/bee_v1.tres",
	&"octopus_v1": "res://resources/data/tech/arch/octopus_v1.tres",
	&"octopus_v2": "res://resources/data/tech/arch/octopus_v2.tres",
	&"spider_v1": "res://resources/data/tech/arch/spider_v1.tres",
	# (removed) falcon_loss — 错归 arch 树的过时 loss 节点, 已由 loss 子树
	# (ce_baseline / zloss / mtp) 替代; 旧存档读到它时 _load_node → null,
	# 各 accessor 优雅回退 (unknown_arch → coef 1.0)。
	# v5 (PR-C) sparse MoE family extensions
	&"octopus_sparse": "res://resources/data/tech/arch/octopus_sparse.tres",
	&"octopus_super_sparse": "res://resources/data/tech/arch/octopus_super_sparse.tres",
	# v7 PR-G: arch 陷阱节点 (capability_cap > 0) + multimodal method 子链 + 未来节点
	&"bert_encoder": "res://resources/data/tech/arch/bert_encoder.tres",
	&"t5_enc_dec": "res://resources/data/tech/arch/t5_enc_dec.tres",
	# v10/v11: encoder trap lineage — BERT can scale for a while, but
	# capability_cap keeps it below uncapped dense / MoE routes.
	&"roberta_encoder": "res://resources/data/tech/arch/roberta_encoder.tres",
	&"electra_encoder": "res://resources/data/tech/arch/electra_encoder.tres",
	&"deberta_encoder": "res://resources/data/tech/arch/deberta_encoder.tres",
	&"bert_scale_encoder": "res://resources/data/tech/arch/bert_scale_encoder.tres",
	&"bert_giant_encoder": "res://resources/data/tech/arch/bert_giant_encoder.tres",
	&"ul2_enc_dec": "res://resources/data/tech/arch/ul2_enc_dec.tres",
	&"cross_train": "res://resources/data/tech/arch/cross_train.tres",
	&"dit_v1": "res://resources/data/tech/arch/dit_v1.tres",
	&"pixel_ar": "res://resources/data/tech/arch/pixel_ar.tres",
	&"native_multimodal": "res://resources/data/tech/arch/native_multimodal.tres",
	&"world_model_v1": "res://resources/data/tech/arch/world_model_v1.tres",
	&"embodied_v1": "res://resources/data/tech/arch/embodied_v1.tres",
	# attention tree (v5, PR-C)
	&"mha_baseline": "res://resources/data/tech/attention/mha_baseline.tres",
	&"gqa": "res://resources/data/tech/attention/gqa.tres",
	&"mqa": "res://resources/data/tech/attention/mqa.tres",
	&"mla": "res://resources/data/tech/attention/mla.tres",
	&"hybrid_attention": "res://resources/data/tech/attention/hybrid_attention.tres",
	# v7 PR-G future
	&"infinite_attn": "res://resources/data/tech/attention/infinite_attn.tres",
	# loss tree (v5, PR-C)
	&"ce_baseline": "res://resources/data/tech/loss/ce_baseline.tres",
	&"zloss": "res://resources/data/tech/loss/zloss.tres",
	&"mtp": "res://resources/data/tech/loss/mtp.tres",
	# v7 PR-G reasoning RL chain
	&"dpo": "res://resources/data/tech/loss/dpo.tres",
	&"rlvr": "res://resources/data/tech/loss/rlvr.tres",
	&"o1_rl": "res://resources/data/tech/loss/o1_rl.tres",
	# engineering tree
	&"owl_cache": "res://resources/data/tech/engineering/owl_cache.tres",
	&"swarm_batch": "res://resources/data/tech/engineering/swarm_batch.tres",
	&"cheetah_decoding": "res://resources/data/tech/engineering/cheetah_decoding.tres",
	&"squirrel_int8": "res://resources/data/tech/engineering/squirrel_int8.tres",
	&"squirrel_int4": "res://resources/data/tech/engineering/squirrel_int4.tres",
	&"otter_paged_attn": "res://resources/data/tech/engineering/otter_paged_attn.tres",
	# v4 (PR-B): FP8 / FP4 quantization for fictionalized accelerator eras.
	# These are flops_per_token_reduction-bearing nodes.
	&"firefly_fp8": "res://resources/data/tech/engineering/firefly_fp8.tres",
	&"glowworm_fp4": "res://resources/data/tech/engineering/glowworm_fp4.tres",
	# v7 PR-G future
	&"bit2_quant": "res://resources/data/tech/engineering/bit2_quant.tres",
	&"analog_compute": "res://resources/data/tech/engineering/analog_compute.tres",
	# application tree
	&"tool_use": "res://resources/data/tech/application/tool_use.tres",
	&"fox_code_specialist": "res://resources/data/tech/application/fox_code_specialist.tres",
	# v7 PR-G context tree (new)
	&"ctx_4k": "res://resources/data/tech/context/ctx_4k.tres",
	&"ctx_32k": "res://resources/data/tech/context/ctx_32k.tres",
	&"ctx_200k": "res://resources/data/tech/context/ctx_200k.tres",
	&"ctx_1m": "res://resources/data/tech/context/ctx_1m.tres",
	&"ctx_10m": "res://resources/data/tech/context/ctx_10m.tres",
}

# Legacy arch id aliases — old saves (and any in-flight code that still passes
# `transformer_v*`) get normalized to the corresponding animal-codename id
# before any registry lookup. Keep small; the migration goal is to delete it
# once no caller produces these names.
const ARCH_ID_ALIAS: Dictionary = {
	&"transformer_v0": &"ant_v1",
	&"transformer_v1": &"ant_v1",
	&"transformer_v2": &"ant_v2",
}

func _ready() -> void:
	CommandBus.register(&"tech.start_research", _on_start_research)
	CommandBus.register(&"tech.unlock_node", _on_unlock_node)
	CommandBus.register(&"tech.is_unlocked", _on_is_unlocked)
	CommandBus.register(&"tech.list_available", _on_list_available)
	CommandBus.register(&"tech.get_arch_coefs", _on_get_arch_coefs)
	# v5 (PR-C): attention + loss subtrees feed PretrainDialog B / C axes.
	CommandBus.register(&"tech.get_attention_coefs", _on_get_attention_coefs)
	CommandBus.register(&"tech.get_loss_coefs", _on_get_loss_coefs)
	CommandBus.register(&"tech.get_engineering_coefs", _on_get_engineering_coefs)
	CommandBus.register(&"tech.get_application_unlocks", _on_get_application_unlocks)
	# v7 PR-G: context tree (D 轴解锁档位 + agent_bonus) + multimodal method 列表.
	CommandBus.register(&"tech.get_context_tiers", _on_get_context_tiers)
	CommandBus.register(&"tech.list_multimodal_methods", _on_list_multimodal_methods)
	EventBus.task_cancelled.connect(_on_task_cancelled)
	# v5 (PR-C): default-unlock the baseline nodes so any player can start a
	# pretrain even before they research anything. Safe to call repeatedly —
	# is_unlocked() is idempotent on the GameState.unlocks dict.
	_ensure_baseline_unlocks()

func _ensure_baseline_unlocks() -> void:
	# These are the "0-cost / 0-month default" baselines for the B and C axes.
	# Without them, PretrainDialog's attention / loss dropdowns would be empty
	# at game start.
	var attn: Dictionary = GameState.unlocks.get(&"attention", {})
	attn[&"mha_baseline"] = true
	GameState.unlocks[&"attention"] = attn
	var loss_slice: Dictionary = GameState.unlocks.get(&"loss", {})
	loss_slice[&"ce_baseline"] = true
	GameState.unlocks[&"loss"] = loss_slice
	# v7 PR-G: context baseline (ctx_4k) — PretrainDialog D 轴必须始终至少有 4k 一档.
	var ctx_slice: Dictionary = GameState.unlocks.get(&"context", {})
	ctx_slice[&"ctx_4k"] = true
	GameState.unlocks[&"context"] = ctx_slice

# ---- commands -----------------------------------------------------------

func _on_start_research(p: Dictionary) -> Dictionary:
	var tree: StringName = _normalize_tree(p.get(&"tree", &""))
	var node_id: StringName = p.get(&"node_id", &"")
	var node: TechNode = _load_node(node_id)
	if node == null:
		return {ok = false, error = &"unknown_node"}
	# Node template's tree might still use an old id; normalize it too.
	var node_tree: StringName = _normalize_tree(node.tree)
	if node_tree != tree:
		return {ok = false, error = &"unknown_node"}
	if is_unlocked(tree, node_id):
		return {ok = false, error = &"already_unlocked"}
	if _is_researching(tree, node_id):
		return {ok = false, error = &"already_researching"}
	for pre in node.prerequisites:
		# Defensive: the prereq must exist in the registry and live in the same
		# tree (cross-tree prereqs are not allowed by design).
		var pre_node: TechNode = _load_node(pre)
		if pre_node != null and _normalize_tree(pre_node.tree) != tree:
			return {ok = false, error = &"prerequisites_missing"}
		if not is_unlocked(tree, pre):
			return {ok = false, error = &"prerequisites_missing"}
	# Forward to TaskSystem.
	# v6 (PR-D): pass datacenter_id so TaskSystem can lock the cluster for the
	# research duration + validate node.min_gpu_count.
	var r: Dictionary = CommandBus.send(&"task.start", {
		template_id = &"tech_research_default",
		lead_ids = p.get(&"lead_ids", []),
		staff = p.get(&"staff", {}),
		datacenter_id = p.get(&"datacenter_id", &""),
		target_node_id = node_id,
		target_tree = tree,
	})
	if not r.ok:
		return r
	GameState.researching_nodes[tree] = GameState.researching_nodes.get(tree, {})
	GameState.researching_nodes[tree][node_id] = r.task_id
	Log.info(&"tech", "research_started", {tree = tree, node = node_id, task_id = r.task_id})
	EventBus.tech_research_started.emit(tree, node_id, r.task_id)
	return {ok = true, task_id = r.task_id}

func _on_unlock_node(p: Dictionary) -> Dictionary:
	var tree: StringName = _normalize_tree(p.get(&"tree", &""))
	var node_id: StringName = p.get(&"node_id", &"")
	GameState.unlocks[tree] = GameState.unlocks.get(tree, {})
	GameState.unlocks[tree][node_id] = true
	if GameState.researching_nodes.has(tree):
		GameState.researching_nodes[tree].erase(node_id)
	Log.info(&"tech", "unlocked", {tree = tree, node = node_id})
	EventBus.tech_unlocked.emit(tree, node_id)
	return {ok = true}

func _on_is_unlocked(p: Dictionary) -> Dictionary:
	var tree: StringName = _normalize_tree(p.get(&"tree", &""))
	return {ok = true, unlocked = is_unlocked(tree, p.get(&"node_id", &""))}

func _on_list_available(p: Dictionary) -> Dictionary:
	var tree: StringName = _normalize_tree(p.get(&"tree", &""))
	if not GameState.TECH_TREES.has(tree):
		return {ok = false, error = &"unknown_tree"}
	var available: Array = []
	for node_id in NODES.keys():
		var node: TechNode = _load_node(node_id)
		if _normalize_tree(node.tree) != tree: continue
		if is_unlocked(tree, node_id): continue
		var ok_pre: bool = true
		for pre in node.prerequisites:
			if not is_unlocked(tree, pre):
				ok_pre = false
				break
		if ok_pre:
			available.append(node_id)
	return {ok = true, nodes = available}

func _on_get_arch_coefs(p: Dictionary) -> Dictionary:
	var arch_id: StringName = _normalize_arch(p.get(&"arch_id", &""))
	var node: TechNode = _load_node(arch_id)
	if node == null or _normalize_tree(node.tree) != &"arch":
		return {ok = false, error = &"unknown_arch"}
	# v7 PR-G: expose capability_cap so callers (TaskSystem evaluate, PretrainDialog
	# preview) can clamp `base` for trap nodes (BERT/T5).
	return {
		ok = true,
		train_coef = float(node.effects.get(&"train_coef", 1.0)),
		inference_coef = float(node.effects.get(&"inference_coef", 1.0)),
		capability_coef = float(node.effects.get(&"capability_coef", 1.0)),
		capability_cap = float(node.capability_cap) if "capability_cap" in node else 0.0,
	}

# v5 (PR-C): Attention subtree coefs (PretrainDialog B-axis).
# Returns 1.0 baselines when attention_id is empty (caller didn't specify) so
# old call sites that only know arch_id keep working transparently.
func _on_get_attention_coefs(p: Dictionary) -> Dictionary:
	var attention_id: StringName = StringName(p.get(&"attention_id", &"mha_baseline"))
	if attention_id == &"":
		attention_id = &"mha_baseline"
	var node: TechNode = _load_node(attention_id)
	if node == null or _normalize_tree(node.tree) != &"attention":
		return {ok = false, error = &"unknown_attention"}
	return {
		ok = true,
		train_coef = float(node.effects.get(&"train_coef", 1.0)),
		inference_coef = float(node.effects.get(&"inference_coef", 1.0)),
	}

# v5 (PR-C): Loss subtree coefs (PretrainDialog C-axis).
func _on_get_loss_coefs(p: Dictionary) -> Dictionary:
	var loss_id: StringName = StringName(p.get(&"loss_id", &"ce_baseline"))
	if loss_id == &"":
		loss_id = &"ce_baseline"
	var node: TechNode = _load_node(loss_id)
	if node == null or _normalize_tree(node.tree) != &"loss":
		return {ok = false, error = &"unknown_loss"}
	return {
		ok = true,
		train_coef = float(node.effects.get(&"train_coef", 1.0)),
		capability_coef = float(node.effects.get(&"capability_coef", 1.0)),
	}

func _on_get_engineering_coefs(p: Dictionary) -> Dictionary:
	# Aggregate engineering-tree node effects. Caller may pass an explicit
	# `node_ids` list; otherwise we use everything currently unlocked in the
	# engineering tree.
	var node_ids: Array = p.get(&"node_ids", [])
	if node_ids.is_empty():
		var unlocked: Dictionary = GameState.unlocks.get(&"engineering", {})
		# Defensive: also pick up legacy `inference` slice if it exists in old saves.
		var legacy: Dictionary = GameState.unlocks.get(&"inference", {})
		for nid in unlocked.keys():
			if bool(unlocked[nid]):
				node_ids.append(nid)
		for nid in legacy.keys():
			if bool(legacy[nid]) and not node_ids.has(nid):
				node_ids.append(nid)
	var throughput: float = 1.0
	# v4 (PR-B): flops_per_token_reduction replaces quality_penalty. ≤ 1, multiplicative.
	# Aggregating unlocked FP8/INT8/INT4/FP4 nodes lets infra apply the reduction
	# directly when computing dc.serving_tokens_per_sec.
	var fpt_reduction: float = 1.0
	for nid in node_ids:
		var node: TechNode = _load_node(nid)
		if node == null or _normalize_tree(node.tree) != &"engineering":
			continue
		throughput *= float(node.effects.get(&"throughput_multiplier", 1.0))
		fpt_reduction *= float(node.effects.get(&"flops_per_token_reduction", 1.0))
	return {
		ok = true,
		throughput_multiplier = throughput,
		flops_per_token_reduction = fpt_reduction,
	}

# v7 PR-G: Context tree (D 轴) — returns unlocked context tiers sorted by max_tokens.
# Always includes baseline ctx_4k. Used by PretrainDialog D-axis dropdown +
# task_system._compute_capability_measured agent_bonus aggregation.
func _on_get_context_tiers(_p: Dictionary) -> Dictionary:
	var tiers: Array = []
	var unlocked: Dictionary = GameState.unlocks.get(&"context", {})
	# Ensure baseline appears even if save predates context tree (defensive).
	if not unlocked.has(&"ctx_4k"):
		unlocked = unlocked.duplicate()
		unlocked[&"ctx_4k"] = true
	for nid in unlocked.keys():
		if not bool(unlocked[nid]):
			continue
		var node: TechNode = _load_node(nid)
		if node == null or _normalize_tree(node.tree) != &"context":
			continue
		tiers.append({
			node_id = nid,
			max_tokens = int(node.effects.get(&"max_tokens", 4096)),
			train_penalty = float(node.effects.get(&"train_penalty", 1.0)),
			agent_bonus = float(node.effects.get(&"agent_bonus", 0.0)),
			serving_penalty = float(node.effects.get(&"serving_penalty", 1.0)),
		})
	tiers.sort_custom(func(a, b): return a.max_tokens < b.max_tokens)
	return {ok = true, tiers = tiers}

# v7 PR-G: Multimodal method list (PretrainDialog E 轴) — `cross_train` 始终在内
# (即使 arch.cross_train 未解锁也允许 baseline cross_train, 因为单模态文本模型也用 default).
# 解锁 arch.dit_v1 / pixel_ar / native_multimodal 后追加 diffusion_ar / pixel_ar / native_ar.
func _on_list_multimodal_methods(_p: Dictionary) -> Dictionary:
	var methods: Array[StringName] = [&"cross_train"]
	var arch_unlocked: Dictionary = GameState.unlocks.get(&"arch", {})
	for nid in arch_unlocked.keys():
		if not bool(arch_unlocked[nid]):
			continue
		var node: TechNode = _load_node(nid)
		if node == null:
			continue
		var m: StringName = StringName(node.effects.get(&"multimodal_method_unlock", &""))
		if m != &"" and not methods.has(m):
			methods.append(m)
	return {ok = true, methods = methods}

func _on_get_application_unlocks(_p: Dictionary) -> Dictionary:
	# Return the list of unlocked application-tree node ids, plus any legacy
	# `agent` slice in case a save predates the rename.
	var out: Array[StringName] = []
	var slice: Dictionary = GameState.unlocks.get(&"application", {})
	for nid in slice.keys():
		if bool(slice[nid]):
			out.append(StringName(nid))
	var legacy: Dictionary = GameState.unlocks.get(&"agent", {})
	for nid in legacy.keys():
		if bool(legacy[nid]) and not out.has(StringName(nid)):
			out.append(StringName(nid))
	return {ok = true, nodes = out}

# ---- helpers ------------------------------------------------------------

func is_unlocked(tree: StringName, node_id: StringName) -> bool:
	var t: StringName = _normalize_tree(tree)
	return bool(GameState.unlocks.get(t, {}).get(node_id, false))

func get_node_template(node_id: StringName) -> TechNode:
	return _load_node(node_id)

# All node ids belonging to `tree`, in registry order. UI (tech_view 树状布局)
# uses this to enumerate the full tree, not just the available frontier.
func nodes_in_tree(tree: StringName) -> Array:
	var t: StringName = _normalize_tree(tree)
	var out: Array = []
	for nid in NODES.keys():
		var node: TechNode = _load_node(nid)
		if node != null and _normalize_tree(node.tree) == t:
			out.append(nid)
	return out

func _is_researching(tree: StringName, node_id: StringName) -> bool:
	var t: StringName = _normalize_tree(tree)
	return GameState.researching_nodes.get(t, {}).has(node_id)

func _load_node(node_id: StringName) -> TechNode:
	var path: String = NODES.get(node_id, "")
	if path == "":
		return null
	var res := load(path)
	if res is TechNode:
		return res
	return null

func _normalize_tree(tree: StringName) -> StringName:
	if TREE_ID_ALIAS.has(tree):
		return TREE_ID_ALIAS[tree]
	return tree

# Normalize legacy `transformer_v*` arch ids to their animal-codename
# equivalents (per 公共枚举表.md §7 — animals are canonical, transformers are
# transition aliases for old saves only).
func _normalize_arch(arch_id: StringName) -> StringName:
	if ARCH_ID_ALIAS.has(arch_id):
		return ARCH_ID_ALIAS[arch_id]
	return arch_id

func _on_task_cancelled(task_id: StringName, _refund: int) -> void:
	for tree in GameState.researching_nodes.keys():
		var nodes: Dictionary = GameState.researching_nodes[tree]
		for node_id in nodes.keys():
			if nodes[node_id] == task_id:
				nodes.erase(node_id)
				EventBus.tech_research_cancelled.emit(tree, node_id)
