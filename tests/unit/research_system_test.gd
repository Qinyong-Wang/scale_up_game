extends GutTest

## ResearchSystem v2 — `research.add_model` (TaskSystem completion hook).
## After the 4-state lifecycle refactor, freshly added models land at
## status = &"pretrained" with capability HIDDEN until evaluate runs.


func before_each() -> void:
	GameState.reset()

func test_add_model_appends_to_models_array() -> void:
	var r: Dictionary = CommandBus.send(&"research.add_model", {
		capability = {&"general": 60.0, &"code": 40.0},
		arch = &"ant_v1",
		dataset_ids = [&"web_corpus_v1"],
		display_name = "Sparrow-Small",
	})
	assert_true(r.ok)
	assert_eq(GameState.models.size(), 1)
	var m: Model = GameState.models[0]
	assert_eq(m.display_name, "Sparrow-Small")
	assert_eq(m.arch, &"ant_v1")
	# §6.1: pretrain does NOT set capability. Stays 0 until evaluate.
	assert_almost_eq(float(m.capability.get(&"general", 0.0)), 0.0, 0.001)
	assert_false(m.capability_revealed)

func test_add_model_returns_unique_model_id() -> void:
	var r1: Dictionary = CommandBus.send(&"research.add_model", {
		capability = {&"general": 50.0}, arch = &"ant_v1", dataset_ids = []})
	var r2: Dictionary = CommandBus.send(&"research.add_model", {
		capability = {&"general": 51.0}, arch = &"ant_v1", dataset_ids = []})
	assert_ne(r1.model_id, r2.model_id)
	assert_eq(GameState.models.size(), 2)

func test_add_model_emits_model_added_signal() -> void:
	watch_signals(EventBus)
	var r: Dictionary = CommandBus.send(&"research.add_model", {
		capability = {&"general": 50.0}, arch = &"ant_v1", dataset_ids = []})
	assert_signal_emitted(EventBus, "model_added")
	var params: Array = get_signal_parameters(EventBus, "model_added")
	assert_eq(params[0], r.model_id)
	assert_eq(StringName(params[1]), &"trained")

func test_added_model_records_trained_at_turn() -> void:
	GameState.turn = 17
	CommandBus.send(&"research.add_model", {
		capability = {&"general": 50.0}, arch = &"ant_v1", dataset_ids = []})
	var m: Model = GameState.models[0]
	assert_eq(m.trained_at_turn, 17)

func test_added_model_default_status_is_pretrained() -> void:
	# §1: 训完 model.status = &"pretrained", capability 隐藏直到 evaluate.
	CommandBus.send(&"research.add_model", {
		capability = {&"general": 50.0}, arch = &"ant_v1", dataset_ids = []})
	var m: Model = GameState.models[0]
	assert_eq(m.status, &"pretrained")
	assert_eq(m.provenance, &"trained")
	assert_false(m.capability_revealed)

func test_pretrain_does_not_copy_capability_from_payload() -> void:
	# §6.1: caller-supplied capability is discarded — the model lands at zero
	# capability and evaluate fills it.
	var caller_capability := {&"general": 50.0}
	CommandBus.send(&"research.add_model", {
		capability = caller_capability, arch = &"ant_v1", dataset_ids = []})
	var m: Model = GameState.models[0]
	assert_almost_eq(float(m.capability.get(&"general", 0.0)), 0.0, 0.001)

func test_dataset_ids_are_converted_to_string_names() -> void:
	# The payload may carry plain Strings (e.g. from .tres parsing); the
	# stored field is typed Array[StringName], so conversion is a contract.
	CommandBus.send(&"research.add_model", {
		capability = {&"general": 50.0},
		arch = &"ant_v1",
		dataset_ids = ["web_corpus_v1", "code_corpus_v1"]})
	var m: Model = GameState.models[0]
	assert_eq(m.dataset_ids.size(), 2)
	assert_eq(typeof(m.dataset_ids[0]), TYPE_STRING_NAME)
	assert_eq(m.dataset_ids[0], &"web_corpus_v1")

func test_add_model_derives_flops_per_token_from_size_when_missing() -> void:
	# 研究系统设计 §6.1: flops_per_token is physical FLOPs/token and defaults
	# to 2 × params when the pretrain payload omits the field.
	CommandBus.send(&"research.add_model", {
		arch = &"ant_v1",
		size_params = 7000.0,
		dataset_ids = [],
		display_name = "M2",
	})
	var m: Model = GameState.models[0]
	assert_almost_eq(m.flops_per_token, 14_000_000_000.0, 1.0)

# v5 (PR-C): A/B/C/D 4-axis: add_model writes attention_id / loss_id /
# context_length_tokens onto the Model, and the new sparse-MoE archs map to
# the right active_param_ratio.

func test_add_model_writes_attention_loss_context_from_payload() -> void:
	CommandBus.send(&"research.add_model", {
		arch = &"ant_v1",
		size_params = 800.0,
		attention_id = &"gqa",
		loss_id = &"zloss",
		context_length_tokens = 200000,
		dataset_ids = [],
		display_name = "Test-Quad-Axis",
	})
	var m: Model = GameState.models[0]
	assert_eq(m.attention_id, &"gqa")
	assert_eq(m.loss_id, &"zloss")
	assert_eq(m.context_length_tokens, 200000)

func test_add_model_defaults_baselines_for_missing_quad_axis_fields() -> void:
	CommandBus.send(&"research.add_model", {
		arch = &"ant_v1",
		size_params = 800.0,
		dataset_ids = [],
		display_name = "Test-No-Quad-Axis",
	})
	var m: Model = GameState.models[0]
	assert_eq(m.attention_id, &"mha_baseline")
	assert_eq(m.loss_id, &"ce_baseline")
	assert_eq(m.context_length_tokens, 4096)

func test_add_model_with_gqa_divides_flops_per_token() -> void:
	# GQA inference_coef = 1.30 → flops_per_token = 2 × 800 × 1e6 / 1.30 ≈ 1.23e9
	CommandBus.send(&"research.add_model", {
		arch = &"ant_v1",
		size_params = 800.0,
		attention_id = &"gqa",
		dataset_ids = [],
		display_name = "GQA-FPT",
	})
	var m: Model = GameState.models[0]
	assert_almost_eq(m.flops_per_token, 2.0 * 800.0 * 1.0e6 / 1.30, 1.0)

func test_add_model_sparse_moe_active_param_ratio() -> void:
	# octopus_sparse → active_param_ratio = 0.05 (1/20)
	CommandBus.send(&"research.add_model", {
		arch = &"octopus_sparse",
		size_params = 8000.0,
		dataset_ids = [],
		display_name = "Sparse-MoE",
	})
	var m: Model = GameState.models[0]
	assert_almost_eq(m.active_param_ratio, 0.05, 0.001)
	# fpt: 2 × 8000 × 0.05 × 1e6 / 1.0 (mha baseline) = 8e8
	assert_almost_eq(m.flops_per_token, 8.0e8, 1.0)

func test_add_model_super_sparse_moe_active_param_ratio() -> void:
	CommandBus.send(&"research.add_model", {
		arch = &"octopus_super_sparse",
		size_params = 8000.0,
		dataset_ids = [],
		display_name = "Super-Sparse-MoE",
	})
	var m: Model = GameState.models[0]
	assert_almost_eq(m.active_param_ratio, 0.025, 0.001)
	# fpt: 2 × 8000 × 0.025 × 1e6 = 4e8
	assert_almost_eq(m.flops_per_token, 4.0e8, 1.0)

func test_default_display_name_falls_back_to_model_id() -> void:
	# When the caller omits display_name, the system uses the generated id —
	# guarantees UI never has to deal with an empty string.
	var r: Dictionary = CommandBus.send(&"research.add_model", {
		capability = {&"general": 50.0}, arch = &"ant_v1", dataset_ids = []})
	var m: Model = GameState.models[0]
	assert_eq(m.display_name, String(r.model_id))

func test_model_id_is_stringname_typed() -> void:
	var r: Dictionary = CommandBus.send(&"research.add_model", {
		capability = {&"general": 50.0}, arch = &"ant_v1", dataset_ids = []})
	assert_eq(typeof(r.model_id), TYPE_STRING_NAME)

# ---- Bug 6: 玩家模型命名应避免与 NPC 已发布模型同名 ---------------------

func _seed_npc_release(model_label: String, release_turn: int = 0) -> void:
	const ReleaseT := preload("res://scripts/resources/npc_model_release.gd")
	var rel := ReleaseT.new()
	rel.id = StringName("rel_" + model_label)
	rel.display_name = model_label
	rel.release_turn = release_turn
	var company := NpcCompany.new()
	company.id = StringName("npc_" + model_label)
	company.display_name = "Test NPC " + model_label
	var typed: Array[ReleaseT] = [rel]
	company.model_releases = typed
	GameState.npc_companies.append(company)

func test_add_model_rejects_name_already_used_by_released_npc_model() -> void:
	GameState.turn = 100
	_seed_npc_release("Wolf-3", 50)
	# 100 > 50 → released.   # released 50 turns ago.
	var r: Dictionary = CommandBus.send(&"research.add_model", {
		capability = {&"general": 50.0}, arch = &"ant_v1", dataset_ids = [],
		display_name = "Wolf-3",
	})
	assert_false(r.ok, "玩家不能与 NPC 已 released 模型同名")
	assert_eq(StringName(r.get(&"error", &"")), &"duplicate_model_name")

func test_add_model_allows_name_used_only_by_future_npc_release() -> void:
	# 未来 release 还没揭示给玩家, 名字应当可用 (避免提前剧透时间线)。
	GameState.turn = 10
	_seed_npc_release("FutureFox", 50)
	var r: Dictionary = CommandBus.send(&"research.add_model", {
		capability = {&"general": 50.0}, arch = &"ant_v1", dataset_ids = [],
		display_name = "FutureFox",
	})
	assert_true(r.ok, "未来发布的 NPC 名不应阻止玩家当前使用")

func test_add_model_npc_name_collision_is_case_insensitive() -> void:
	GameState.turn = 10
	_seed_npc_release("Sparrow-Large", 0)
	var r: Dictionary = CommandBus.send(&"research.add_model", {
		capability = {&"general": 50.0}, arch = &"ant_v1", dataset_ids = [],
		display_name = "sparrow-large",
	})
	assert_false(r.ok)
	assert_eq(StringName(r.get(&"error", &"")), &"duplicate_model_name")

# ---- save_loaded: model ID 计数器恢复 + 重复修复 (读档撞 ID 防御) -------

func _seed_model(id: StringName) -> Model:
	var m := Model.new()
	m.id = id
	return m

func test_save_loaded_restores_model_id_counter() -> void:
	GameState.models.append(_seed_model(&"model_0009"))
	EventBus.save_loaded.emit()
	var new_id := ResearchSystem._gen_id()
	assert_gt(String(new_id).trim_prefix("model_").to_int(), 9,
			"读档后新发的 model ID 不能复用 ≤0009 (实际 %s)" % new_id)

func test_save_loaded_repairs_duplicate_model_ids() -> void:
	GameState.models.append(_seed_model(&"model_0001"))
	GameState.models.append(_seed_model(&"model_0001"))
	EventBus.save_loaded.emit()
	var seen := {}
	for m in GameState.models:
		assert_false(seen.has(m.id), "model id %s 读档后仍重复" % m.id)
		seen[m.id] = true
