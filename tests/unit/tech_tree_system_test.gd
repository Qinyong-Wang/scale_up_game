extends GutTest

## TechTreeSystem v6 (PR-D) — historical timeline + ResearchDialog scaffolding.
## start_research forwards to TaskSystem; unlock_node is the TaskSystem
## completion fan-out. Per design/科技树系统设计.md §0 / §6.0.
##
## v6 changes covered:
## - All nodes now declare min_researchers / min_engineers / min_gpu_count.
## - tech_research_default template requires needs_dc; start_research must
##   provide ml_eng + infra_eng staff + datacenter_id.
## - Linear prerequisite chains (gqa is the simplest reachable node at boot).

# Cheapest researchable node at game start (attention tree baseline → gqa).
# Used for "happy path" coverage to keep tests cheap.
const NODE := &"gqa"
const TREE := &"attention"
const NODE_WEEKS := 24             # research_months on resources/data/tech/attention/gqa.tres
const NODE_MIN_ML := 2
const NODE_MIN_INFRA := 1
const NODE_MIN_GPU := 8

func before_each() -> void:
	GameState.reset()

# ---- helpers ------------------------------------------------------------

# Build the minimal kit needed to start research on NODE (gqa): a pod-sized DC
# with ≥ NODE_MIN_GPU cards + enough idle staff. Returns the dc_id.
func _setup_research_resources(min_ml: int = NODE_MIN_ML,
		min_infra: int = NODE_MIN_INFRA, min_gpu: int = NODE_MIN_GPU) -> StringName:
	GameState.cash = 10_000_000
	# Pod (8-card max) is enough for the small nodes; bigger nodes need racks /
	# rooms but those aren't covered by these unit tests.
	var rr: Dictionary = CommandBus.send(&"infra.rent_facility",
			{facility_spec_id = &"facility_pod", power_supply_id = &"grid"})
	assert_true(rr.ok, "rent_facility failed: %s" % str(rr))
	var dc_id: StringName = rr.dc_id
	CommandBus.send(&"infra.buy_gpus",
			{dc_id = dc_id, gpu_id = &"cypress_t0", count = min_gpu})
	CommandBus.send(&"hiring.adjust_staff", {role = &"ml_eng", delta = min_ml})
	CommandBus.send(&"hiring.adjust_staff", {role = &"infra_eng", delta = min_infra})
	return dc_id

func _ok_payload(dc_id: StringName,
		ml: int = NODE_MIN_ML, infra: int = NODE_MIN_INFRA,
		node: StringName = NODE, tree: StringName = TREE) -> Dictionary:
	return {
		tree = tree, node_id = node,
		lead_ids = [],
		staff = {ml_eng = ml, infra_eng = infra},
		datacenter_id = dc_id,
	}

# ---- start_research errors (cheap negative tests, no DC needed) --------

func test_start_research_unknown_node_returns_error() -> void:
	var r: Dictionary = CommandBus.send(&"tech.start_research", {
		tree = &"arch", node_id = &"nope"})
	assert_false(r.ok)
	assert_eq(r.error, &"unknown_node")

func test_start_research_already_unlocked_returns_error() -> void:
	GameState.unlocks[&"attention"][&"gqa"] = true
	var r: Dictionary = CommandBus.send(&"tech.start_research", {
		tree = &"attention", node_id = &"gqa"})
	assert_false(r.ok)
	assert_eq(r.error, &"already_unlocked")

func test_start_research_prerequisites_missing_returns_error() -> void:
	# Remove the seeded mha_baseline to break the prerequisite chain.
	GameState.unlocks[&"attention"].erase(&"mha_baseline")
	var r: Dictionary = CommandBus.send(&"tech.start_research", {
		tree = &"attention", node_id = &"gqa"})
	assert_false(r.ok)
	assert_eq(r.error, &"prerequisites_missing")

# ---- v6: resource-gating errors ----------------------------------------

func test_start_research_rejects_missing_datacenter() -> void:
	# No DC provided → schema needs_dc fails first.
	var r: Dictionary = CommandBus.send(&"tech.start_research", {
		tree = TREE, node_id = NODE,
		lead_ids = [], staff = {ml_eng = NODE_MIN_ML, infra_eng = NODE_MIN_INFRA},
	})
	assert_false(r.ok)
	assert_eq(r.error, &"datacenter_unavailable")

func test_start_research_rejects_too_few_researchers() -> void:
	var dc_id := _setup_research_resources()
	var payload := _ok_payload(dc_id, NODE_MIN_ML - 1, NODE_MIN_INFRA)
	var r: Dictionary = CommandBus.send(&"tech.start_research", payload)
	assert_false(r.ok)
	assert_eq(r.error, &"tech_researchers_too_few")

func test_start_research_rejects_too_few_engineers() -> void:
	var dc_id := _setup_research_resources()
	var payload := _ok_payload(dc_id, NODE_MIN_ML, 0)
	var r: Dictionary = CommandBus.send(&"tech.start_research", payload)
	assert_false(r.ok)
	assert_eq(r.error, &"tech_engineers_too_few")

func test_start_research_rejects_small_datacenter() -> void:
	# octopus_sparse requires 256 GPUs, an 8-card pod must be rejected.
	# First unlock the prerequisite chain so prereq check passes.
	for nid in [&"ant_v2", &"bee_v1", &"octopus_v1", &"octopus_v2"]:
		GameState.unlocks[&"arch"][nid] = true
	var dc_id := _setup_research_resources(5, 8, 8)  # only 8 GPUs in pod
	var payload := _ok_payload(dc_id, 5, 8, &"octopus_sparse", &"arch")
	var r: Dictionary = CommandBus.send(&"tech.start_research", payload)
	assert_false(r.ok)
	assert_eq(r.error, &"tech_datacenter_too_small")

# ---- v6: success path --------------------------------------------------

func test_start_research_locks_datacenter() -> void:
	var dc_id := _setup_research_resources()
	var r: Dictionary = CommandBus.send(&"tech.start_research", _ok_payload(dc_id))
	assert_true(r.ok)
	var dc = InfraSystem.find_dc(dc_id)
	# Research locks the dc just like pretrain (status moves out of idle).
	assert_ne(dc.status, &"idle", "DC must not be idle while research is active")

func test_start_research_records_in_researching_nodes() -> void:
	var dc_id := _setup_research_resources()
	var r: Dictionary = CommandBus.send(&"tech.start_research", _ok_payload(dc_id))
	assert_true(r.ok)
	assert_eq(GameState.researching_nodes.get(TREE, {}).get(NODE), r.task_id)

func test_start_research_does_not_charge_node_research_cost() -> void:
	# §6 v6: research_cost is 0 on all nodes; only resource locks "pay".
	var dc_id := _setup_research_resources()
	var before_cash: int = GameState.cash
	var r: Dictionary = CommandBus.send(&"tech.start_research", _ok_payload(dc_id))
	assert_true(r.ok)
	assert_eq(GameState.cash, before_cash)

func test_start_research_already_researching_returns_error() -> void:
	var dc_id := _setup_research_resources()
	CommandBus.send(&"tech.start_research", _ok_payload(dc_id))
	# Second attempt on same node — even with fresh resources it should reject.
	var r: Dictionary = CommandBus.send(&"tech.start_research", _ok_payload(dc_id))
	assert_false(r.ok)
	assert_eq(r.error, &"already_researching")

# ---- task pipeline integration -----------------------------------------

func test_research_completes_via_task_pipeline() -> void:
	var dc_id := _setup_research_resources()
	var r: Dictionary = CommandBus.send(&"tech.start_research", _ok_payload(dc_id))
	assert_true(r.ok, "start_research failed: %s" % str(r))
	# gqa: research_months = 24 (weeks). With no lead, no speedup.
	for i in range(NODE_WEEKS):
		EventBus.phase_started.emit(&"action", i + 1)
	assert_true(bool(GameState.unlocks[TREE][NODE]),
			"node %s should be unlocked after %d weeks" % [NODE, NODE_WEEKS])
	assert_false(GameState.researching_nodes.get(TREE, {}).has(NODE))
	# DC must be released back to idle.
	var dc = InfraSystem.find_dc(dc_id)
	assert_eq(dc.status, &"idle")

func test_task_cancel_clears_researching_nodes() -> void:
	var dc_id := _setup_research_resources()
	var r: Dictionary = CommandBus.send(&"tech.start_research", _ok_payload(dc_id))
	CommandBus.send(&"task.cancel", {task_id = r.task_id})
	assert_false(GameState.researching_nodes.get(TREE, {}).has(NODE))

# ---- unlock + read commands --------------------------------------------

func test_unlock_node_marks_unlocked_and_emits() -> void:
	watch_signals(EventBus)
	CommandBus.send(&"tech.unlock_node", {tree = &"engineering", node_id = &"owl_cache"})
	assert_true(bool(GameState.unlocks[&"engineering"][&"owl_cache"]))
	assert_signal_emitted(EventBus, "tech_unlocked")

func test_is_unlocked_returns_truth() -> void:
	var r: Dictionary = CommandBus.send(&"tech.is_unlocked", {
		tree = &"arch", node_id = &"ant_v1"})
	assert_true(r.ok)
	assert_true(r.unlocked)

func test_get_arch_coefs_default_for_v1() -> void:
	var r: Dictionary = CommandBus.send(&"tech.get_arch_coefs", {arch_id = &"ant_v1"})
	assert_true(r.ok)
	assert_eq(r.train_coef, 1.0)

func test_get_arch_coefs_unknown_returns_error() -> void:
	var r: Dictionary = CommandBus.send(&"tech.get_arch_coefs", {arch_id = &"nope"})
	assert_false(r.ok)
	assert_eq(r.error, &"unknown_arch")

func test_list_available_unknown_tree_returns_error() -> void:
	var r: Dictionary = CommandBus.send(&"tech.list_available", {tree = &"foo"})
	assert_false(r.ok)
	assert_eq(r.error, &"unknown_tree")

func test_list_available_excludes_already_unlocked() -> void:
	var r: Dictionary = CommandBus.send(&"tech.list_available", {tree = &"arch"})
	assert_true(r.ok)
	assert_does_not_have(r.nodes, &"ant_v1")

# ---- alias acceptance --------------------------------------------------

func test_alias_inference_routes_to_engineering() -> void:
	CommandBus.send(&"tech.unlock_node", {tree = &"inference", node_id = &"owl_cache"})
	assert_true(bool(GameState.unlocks[&"engineering"][&"owl_cache"]))
	var r: Dictionary = CommandBus.send(&"tech.is_unlocked", {
		tree = &"inference", node_id = &"owl_cache"})
	assert_true(r.unlocked)

func test_alias_agent_routes_to_application() -> void:
	CommandBus.send(&"tech.unlock_node", {tree = &"agent", node_id = &"tool_use"})
	assert_true(bool(GameState.unlocks[&"application"][&"tool_use"]))
	var r: Dictionary = CommandBus.send(&"tech.is_unlocked", {
		tree = &"agent", node_id = &"tool_use"})
	assert_true(r.unlocked)

# ---- registry coverage --------------------------------------------------

func test_all_three_trees_populated() -> void:
	for tree in GameState.TECH_TREES:
		var r: Dictionary = CommandBus.send(&"tech.list_available", {tree = tree})
		assert_true(r.ok, "tree %s should be a known tree" % [tree])
		assert_gt(r.nodes.size(), 0, "tree %s should have at least one available node" % [tree])

# ---- effects_summary ---------------------------------------------------

func test_effects_summary_populated_on_arch_node() -> void:
	var node: TechNode = preload("res://resources/data/tech/arch/ant_v2.tres")
	assert_ne(node.effects_summary, "")

func test_effects_summary_populated_on_engineering_node() -> void:
	var node: TechNode = preload("res://resources/data/tech/engineering/owl_cache.tres")
	assert_ne(node.effects_summary, "")

func test_effects_summary_populated_on_application_node() -> void:
	var node: TechNode = preload("res://resources/data/tech/application/tool_use.tres")
	assert_ne(node.effects_summary, "")

# ---- v6: TechNode field assertions -------------------------------------

func test_all_non_baseline_nodes_have_weeks_in_24_48_range() -> void:
	# baseline nodes (ant_v1 / mha_baseline / ce_baseline) keep weeks = 0; every
	# other registered node must sit in the v6 historical band.
	# v7 PR-G: ctx_4k is the context-tree baseline (always unlocked, 0 weeks).
	const BASELINES: Array[StringName] = [&"ant_v1", &"mha_baseline", &"ce_baseline", &"ctx_4k"]
	for nid in TechTreeSystem.NODES.keys():
		var node: TechNode = TechTreeSystem.get_node_template(nid)
		assert_not_null(node, "node %s failed to load" % [nid])
		if BASELINES.has(nid):
			assert_eq(node.research_months, 0, "%s should remain a 0-week baseline" % [nid])
			continue
		assert_between(node.research_months, 24, 48,
				"%s research_months=%d should be in [24,48]" % [nid, node.research_months])

func test_all_non_baseline_nodes_declare_resource_minima() -> void:
	# v7 PR-G: ctx_4k is the context-tree baseline (always unlocked, 0 weeks).
	const BASELINES: Array[StringName] = [&"ant_v1", &"mha_baseline", &"ce_baseline", &"ctx_4k"]
	for nid in TechTreeSystem.NODES.keys():
		if BASELINES.has(nid): continue
		var node: TechNode = TechTreeSystem.get_node_template(nid)
		assert_between(node.min_researchers, 1, 5, "%s min_researchers" % [nid])
		assert_between(node.min_engineers, 1, 10, "%s min_engineers" % [nid])
		assert_between(node.min_gpu_count, 8, 500, "%s min_gpu_count" % [nid])

# ---- get_engineering_coefs --------------------------------------------

func test_get_engineering_coefs_default_no_unlocks() -> void:
	var r: Dictionary = CommandBus.send(&"tech.get_engineering_coefs", {})
	assert_true(r.ok)
	assert_eq(r.throughput_multiplier, 1.0)
	assert_false(r.has(&"train_efficiency"), "train_efficiency was removed because no training formula consumes it")
	assert_eq(r.flops_per_token_reduction, 1.0)

func test_get_engineering_coefs_aggregates_unlocked() -> void:
	CommandBus.send(&"tech.unlock_node", {tree = &"engineering", node_id = &"owl_cache"})
	CommandBus.send(&"tech.unlock_node", {tree = &"engineering", node_id = &"swarm_batch"})
	var r: Dictionary = CommandBus.send(&"tech.get_engineering_coefs", {})
	assert_true(r.ok)
	assert_almost_eq(float(r.throughput_multiplier), 1.3 * 1.5, 0.001)

func test_get_engineering_coefs_flops_per_token_reduction_from_quant() -> void:
	CommandBus.send(&"tech.unlock_node", {tree = &"engineering", node_id = &"squirrel_int8"})
	var r: Dictionary = CommandBus.send(&"tech.get_engineering_coefs", {})
	assert_almost_eq(float(r.flops_per_token_reduction), 0.6, 0.001)
	assert_almost_eq(float(r.throughput_multiplier), 1.0, 0.001)

func test_get_engineering_coefs_fpt_reduction_accumulates_multiplicatively() -> void:
	CommandBus.send(&"tech.unlock_node", {tree = &"engineering", node_id = &"owl_cache"})
	CommandBus.send(&"tech.unlock_node", {tree = &"engineering", node_id = &"firefly_fp8"})
	CommandBus.send(&"tech.unlock_node", {tree = &"engineering", node_id = &"squirrel_int8"})
	var r: Dictionary = CommandBus.send(&"tech.get_engineering_coefs", {})
	assert_almost_eq(float(r.flops_per_token_reduction), 0.5 * 0.6, 0.001)

func test_get_engineering_coefs_explicit_node_ids() -> void:
	var r: Dictionary = CommandBus.send(&"tech.get_engineering_coefs", {
		node_ids = [&"owl_cache"]})
	assert_almost_eq(float(r.throughput_multiplier), 1.3, 0.001)

# ---- get_application_unlocks ------------------------------------------

func test_get_application_unlocks_empty_by_default() -> void:
	var r: Dictionary = CommandBus.send(&"tech.get_application_unlocks", {})
	assert_true(r.ok)
	assert_eq(r.nodes.size(), 0)

func test_get_application_unlocks_returns_unlocked_ids() -> void:
	CommandBus.send(&"tech.unlock_node", {tree = &"application", node_id = &"tool_use"})
	CommandBus.send(&"tech.unlock_node", {tree = &"application", node_id = &"fox_code_specialist"})
	var r: Dictionary = CommandBus.send(&"tech.get_application_unlocks", {})
	assert_true(r.ok)
	assert_has(r.nodes, &"tool_use")
	assert_has(r.nodes, &"fox_code_specialist")

func test_get_application_unlocks_picks_up_legacy_agent_slice() -> void:
	GameState.unlocks[&"agent"] = {&"tool_use": true}
	var r: Dictionary = CommandBus.send(&"tech.get_application_unlocks", {})
	assert_has(r.nodes, &"tool_use")

# ---- defensive: cross-tree prereq rejection ---------------------------

func test_cross_tree_prereq_is_rejected() -> void:
	# spider_v1 lives in arch tree; asking for it under engineering must reject.
	var r: Dictionary = CommandBus.send(&"tech.start_research", {
		tree = &"engineering", node_id = &"spider_v1"})
	assert_false(r.ok)
	assert_eq(r.error, &"unknown_node")

# ---- falcon_loss 移除 + 旧存档兼容 ------------------------------------

func test_falcon_loss_removed_from_registry() -> void:
	# 过时的 loss 节点 (错归 arch 树, capability_coef 永不生效) 已移除。
	assert_false(TechTreeSystem.NODES.has(&"falcon_loss"),
		"falcon_loss 应已从科技树注册表移除")

func test_research_removed_node_rejected() -> void:
	var r: Dictionary = CommandBus.send(&"tech.start_research", {
		tree = &"arch", node_id = &"falcon_loss"})
	assert_false(r.ok)
	assert_eq(r.error, &"unknown_node")

func test_removed_arch_id_resolves_gracefully_for_old_saves() -> void:
	# 旧存档里 arch_id=falcon_loss 的模型不能让 get_arch_coefs 崩 — 优雅失败,
	# caller (task_system._arch_capability_coef) 回退到 coef 1.0。
	var r: Dictionary = CommandBus.send(&"tech.get_arch_coefs", {arch_id = &"falcon_loss"})
	assert_false(r.ok)
	assert_eq(r.get(&"error", &""), &"unknown_arch")

func test_dead_unconsumed_nodes_removed_from_registry() -> void:
	for nid in [
		&"crab_decoder", &"whale_audio",
		&"crow_rag", &"raccoon_planning", &"elephant_memory",
		&"spider_long_ctx", &"dolphin_image_gen",
		&"world_simulation", &"embodied_agent",
		&"ant_tensor_para", &"ant_pipeline_para", &"firefly_mixed_prec",
	]:
		assert_false(TechTreeSystem.NODES.has(nid), "%s should not be registered" % nid)

func test_registered_nodes_only_use_consumed_effect_keys() -> void:
	var allowed := {
		&"arch": {
			&"train_coef": true,
			&"inference_coef": true,
			&"capability_coef": true,
			&"multimodal_method_unlock": true,
		},
		&"attention": {&"train_coef": true, &"inference_coef": true},
		&"loss": {&"train_coef": true, &"capability_coef": true},
		&"engineering": {
			&"throughput_multiplier": true,
			&"flops_per_token_reduction": true,
		},
		&"application": {},
		&"context": {
			&"max_tokens": true,
			&"train_penalty": true,
			&"agent_bonus": true,
			&"serving_penalty": true,
		},
	}
	for nid in TechTreeSystem.NODES.keys():
		var node: TechNode = TechTreeSystem.get_node_template(nid)
		assert_not_null(node, "node %s failed to load" % nid)
		var tree_allowed: Dictionary = allowed.get(node.tree, {})
		for key in node.effects.keys():
			var skey := StringName(key)
			assert_true(tree_allowed.has(skey),
					"%s declares unconsumed effect key %s" % [nid, skey])
