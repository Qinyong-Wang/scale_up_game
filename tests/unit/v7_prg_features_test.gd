extends GutTest

## v7 PR-G feature regression tests:
##   1. Dataset.modality default text + from_dict legacy compat
##   2. Arch capability_cap clamps `base` for trap nodes (BERT/T5)
##   3. Context tree agent_bonus is additive on agent axis (gated by agent-size)
##   4. Multimodal method coef multiplies multimodal axis
##   5. PretrainDialog dataset modality validation rejects mismatched datasets
##   6. tech.get_context_tiers + tech.list_multimodal_methods round-trips


func before_each() -> void:
	GameState.reset()

# ---- 1. Dataset.modality ----

func test_dataset_default_modality_is_text() -> void:
	var ds := Dataset.new()
	assert_eq(ds.modality, &"text", "fresh Dataset defaults to text modality")

func test_dataset_from_dict_legacy_save_defaults_to_text() -> void:
	# Pre-G saves don't carry the modality field.
	var legacy := {
		"id": "legacy_ds",
		"kind": "pretrain",
		"source": "open_source",
		"size": 100.0,
		"quality": 0.9,
	}
	var ds := Dataset.from_dict(legacy)
	assert_eq(ds.modality, &"text", "legacy save → text modality")

func test_dataset_to_from_dict_roundtrip_preserves_modality() -> void:
	var ds := Dataset.new()
	ds.id = &"image_ds"
	ds.kind = &"pretrain"
	ds.source = &"collected"
	ds.modality = &"image"
	var d := ds.to_dict()
	var restored := Dataset.from_dict(d)
	assert_eq(restored.modality, &"image")

# ---- 2. Arch capability_cap (BERT / T5 traps) ----

func test_bert_encoder_caps_base() -> void:
	# A 100B BERT model would get base=clamp(20+12*log10(1000),10,95)=56;
	# capability_cap=30 must clamp base to 30 before other multipliers.
	_make_pretrain_dataset(&"d_big", 1.0, 2000.0)  # Chinchilla-optimal-ish
	var m := _make_model(&"bert_encoder", 100_000.0, [&"d_big"])
	var got: float = TaskSystem._compute_capability_measured(m, null).get(&"general", 0.0)
	# v9 (2026-05): quality=1.0 → data_quality_factor cap 1.5; data_eff ≈ 1.0;
	# arch_coef 1.0 for cap node. raw ≤ 30 × 1.5 ≈ 45. Still well below 56
	# (un-capped) which would scale to ~84 under v9. So < 50 confirms the cap.
	assert_true(got < 50.0, "BERT capped at ~30 (×1.5 factor → ~45); got %s" % got)

func test_decoder_uncapped_scales_normally() -> void:
	# Same size with ant_v2 should NOT be capped.
	_make_pretrain_dataset(&"d_big", 1.0, 2000.0)
	var m := _make_model(&"ant_v2", 100_000.0, [&"d_big"])
	var got: float = TaskSystem._compute_capability_measured(m, null).get(&"general", 0.0)
	assert_true(got > 40.0, "ant_v2 100B should score > 40; got %s" % got)

func test_t5_enc_dec_cap_45() -> void:
	_make_pretrain_dataset(&"d_big", 1.0, 2000.0)
	var m := _make_model(&"t5_enc_dec", 100_000.0, [&"d_big"])
	var got: float = TaskSystem._compute_capability_measured(m, null).get(&"general", 0.0)
	# v9 (2026-05): cap 45 × 1.5 factor ≈ 67.5. Un-capped would be ~84. Margin
	# is tight but distinguishable.
	assert_true(got < 75.0, "T5 capped at ~45 (×1.5 factor → ~67.5); got %s" % got)

# ---- 2bis. Encoder trap lineage (v10/v11): finite-scale BERT, t5→ul2 ----

func test_encoder_trap_chain_caps_registered() -> void:
	# Each successor raises the cap one notch; BERT can scale for a while but
	# still tops out below uncapped dense / MoE routes.
	var expected := {
		&"roberta_encoder": 38.0,
		&"electra_encoder": 45.0,
		&"deberta_encoder": 52.0,
		&"bert_scale_encoder": 60.0,
		&"bert_giant_encoder": 64.0,
		&"ul2_enc_dec": 58.0,
	}
	for arch_id in expected:
		var coefs: Dictionary = CommandBus.send(&"tech.get_arch_coefs", {arch_id = arch_id})
		assert_true(coefs.get(&"ok", false), "%s arch coefs load" % arch_id)
		assert_eq(coefs.get(&"capability_cap", 0.0), expected[arch_id],
				"%s capability_cap registered" % arch_id)

func test_encoder_trap_capped_below_dense_at_scale() -> void:
	# At 1T params dense `base` ≈ 68; BERT-scale clamps to 64 and ul2 to 58.
	# Even with their slightly higher arch_coef they must score below uncapped
	# dense — the trap holds no matter how deep the player invests in the
	# encoder line.
	_make_pretrain_dataset(&"d_huge", 1.0, 20_000.0)
	var dense := _make_model(&"ant_v2", 1_000_000.0, [&"d_huge"])
	var dense_score: float = TaskSystem._compute_capability_measured(
			dense, null).get(&"general", 0.0)
	for arch_id in [&"deberta_encoder", &"bert_giant_encoder", &"ul2_enc_dec"]:
		var m := _make_model(arch_id, 1_000_000.0, [&"d_huge"])
		var got: float = TaskSystem._compute_capability_measured(
				m, null).get(&"general", 0.0)
		assert_true(got < dense_score,
				"%s capped below uncapped dense at 1T; %s vs %s" % [
						arch_id, got, dense_score])

func test_bert_scale_nodes_raise_score_above_base_bert() -> void:
	# The BERT line is a finite-scale trap, not a completely flat dead node:
	# later BERT-scale techs should outperform the initial bert_encoder cap.
	_make_pretrain_dataset(&"d_scale", 1.0, 20_000.0)
	var base := _make_model(&"bert_encoder", 1_000_000.0, [&"d_scale"])
	var scaled := _make_model(&"bert_giant_encoder", 1_000_000.0, [&"d_scale"])
	var base_score: float = TaskSystem._compute_capability_measured(
			base, null).get(&"general", 0.0)
	var scaled_score: float = TaskSystem._compute_capability_measured(
			scaled, null).get(&"general", 0.0)
	assert_true(scaled_score > base_score,
			"BERT scale nodes should raise score: %s vs %s" % [scaled_score, base_score])

# ---- 3. Context tree agent_bonus (additive on agent axis) ----

func test_ctx_4k_baseline_no_agent_bonus() -> void:
	# 100B dense model, agent-eligible, with code+agent tag dataset.
	# Should get baseline agent score with NO context bonus.
	var ds := _make_pretrain_dataset(&"d_agent", 1.0, 2000.0, [&"agent"])
	var m := _make_model(&"ant_v2", 100_000.0, [ds.id])
	m.context_length_tokens = 4096
	var agent_4k: float = TaskSystem._compute_capability_measured(m, null).get(&"agent", -1.0)
	assert_true(agent_4k > 0.0, "agent-gate passes for 100B with agent dataset")

func test_ctx_1m_adds_agent_bonus_when_unlocked() -> void:
	# Unlock ctx_32k / 200k / 1m, set model to 1M ctx → bonus = 2+5+10 = 17.
	_unlock(&"context", [&"ctx_32k", &"ctx_200k", &"ctx_1m"])
	var ds := _make_pretrain_dataset(&"d_agent", 1.0, 2000.0, [&"agent"])
	var m := _make_model(&"ant_v2", 100_000.0, [ds.id])
	m.context_length_tokens = 4096
	var agent_4k: float = TaskSystem._compute_capability_measured(m, null).get(&"agent", -1.0)
	m.context_length_tokens = 1_000_000
	var agent_1m: float = TaskSystem._compute_capability_measured(m, null).get(&"agent", -1.0)
	assert_almost_eq(agent_1m - agent_4k, 17.0, 0.5,
			"ctx_32k+200k+1m sum to +17 agent bonus")

func test_context_bonus_zero_when_gate_fails() -> void:
	# Tiny model can't pass agent gate. Even with ctx_1m unlocked + chosen,
	# agent score stays 0.
	_unlock(&"context", [&"ctx_32k", &"ctx_200k", &"ctx_1m"])
	var ds := _make_pretrain_dataset(&"d_agent", 1.0, 50.0, [&"agent"])
	var m := _make_model(&"ant_v1", 1000.0, [ds.id])  # 1B model fails agent gate
	m.context_length_tokens = 1_000_000
	var agent: float = TaskSystem._compute_capability_measured(m, null).get(&"agent", -1.0)
	assert_eq(agent, 0.0, "agent gate failure → no context bonus either")

# ---- 4. Multimodal method capability coef ----

func test_multimodal_method_native_strongest() -> void:
	var ds := _make_pretrain_dataset(&"d_mm", 1.0, 2000.0)
	var m := _make_model(&"ant_v2", 8000.0, [ds.id], [&"text", &"image"])
	m.multimodal_method = &"cross_train"
	var v_cross: float = TaskSystem._compute_capability_measured(m, null).get(&"multimodal", 0.0)
	m.multimodal_method = &"native_ar"
	var v_native: float = TaskSystem._compute_capability_measured(m, null).get(&"multimodal", 0.0)
	# native_ar = 1.30 / cross_train = 1.00.
	assert_almost_eq(v_native / max(v_cross, 0.0001), 1.30, 0.05)

func test_multimodal_method_none_for_single_modality() -> void:
	# Single-modality (text-only) model has multimodal=0 regardless of method.
	var ds := _make_pretrain_dataset(&"d_text", 1.0, 2000.0)
	var m := _make_model(&"ant_v2", 8000.0, [ds.id], [&"text"])
	m.multimodal_method = &"diffusion_ar"
	var v: float = TaskSystem._compute_capability_measured(m, null).get(&"multimodal", -1.0)
	assert_eq(v, 0.0, "text-only model has multimodal=0")

# ---- 5. PretrainDialog dataset modality validation ----

func test_pretrain_rejects_image_dataset_for_text_only_model() -> void:
	# Set up: a text-only model trying to use an image dataset → fail.
	# Stand up a chief_scientist lead so the lead/specialty gate doesn't
	# short-circuit before our modality check.
	_make_chief_scientist_lead(&"l_cs")
	var image_ds := _make_pretrain_dataset(&"d_img", 0.9, 50.0)
	image_ds.modality = &"image"
	var template := load("res://resources/data/tasks/pretrain/pretrain_model.tres")
	var payload := {
		template_id = &"pretrain_model",
		lead_ids = [&"l_cs"],
		size_params = 1000.0,
		arch_id = &"ant_v1",
		attention_id = &"mha_baseline",
		loss_id = &"ce_baseline",
		context_length_tokens = 4096,
		multimodal_method = &"none",
		input_modalities = [&"text"],
		dataset_ids = [&"d_img"],
	}
	var err: StringName = TaskSystem._validate(template, payload)
	assert_eq(err, &"dataset_modality_mismatch")

func test_pretrain_accepts_text_dataset_for_text_only_model() -> void:
	_make_chief_scientist_lead(&"l_cs")
	_make_pretrain_dataset(&"d_text", 0.9, 50.0)
	var template := load("res://resources/data/tasks/pretrain/pretrain_model.tres")
	var payload := {
		template_id = &"pretrain_model",
		lead_ids = [&"l_cs"],
		size_params = 1000.0,
		arch_id = &"ant_v1",
		input_modalities = [&"text"],
		dataset_ids = [&"d_text"],
	}
	var err: StringName = TaskSystem._validate(template, payload)
	assert_ne(err, &"dataset_modality_mismatch")

func test_pretrain_treats_code_dataset_modality_as_text() -> void:
	_make_chief_scientist_lead(&"l_cs")
	var code_ds := _make_pretrain_dataset(&"d_code", 0.9, 50.0, [&"code"])
	code_ds.modality = &"code"
	var template := load("res://resources/data/tasks/pretrain/pretrain_model.tres")
	var payload := {
		template_id = &"pretrain_model",
		lead_ids = [&"l_cs"],
		size_params = 1000.0,
		arch_id = &"ant_v1",
		input_modalities = [&"text"],
		dataset_ids = [&"d_code"],
	}
	var err: StringName = TaskSystem._validate(template, payload)
	assert_ne(err, &"dataset_modality_mismatch",
			"code data is a text subset; code specialization lives in coverage_tags")

func test_pretrain_accepts_image_dataset_when_model_has_image_modality() -> void:
	_make_chief_scientist_lead(&"l_cs")
	var image_ds := _make_pretrain_dataset(&"d_img", 0.9, 50.0)
	image_ds.modality = &"image"
	var template := load("res://resources/data/tasks/pretrain/pretrain_model.tres")
	var payload := {
		template_id = &"pretrain_model",
		lead_ids = [&"l_cs"],
		size_params = 1000.0,
		arch_id = &"ant_v1",
		input_modalities = [&"text", &"image"],
		dataset_ids = [&"d_img"],
	}
	var err: StringName = TaskSystem._validate(template, payload)
	assert_ne(err, &"dataset_modality_mismatch")

# ---- 6. Tech tree command round-trips ----

func test_get_context_tiers_baseline_only() -> void:
	# Fresh GameState should expose at minimum the ctx_4k baseline.
	var r: Dictionary = CommandBus.send(&"tech.get_context_tiers", {})
	assert_true(r.get(&"ok", false), "command returns ok")
	var tiers: Array = r.get(&"tiers", [])
	assert_true(tiers.size() >= 1, "at least ctx_4k baseline")
	assert_eq(tiers[0].max_tokens, 4096)
	assert_eq(tiers[0].agent_bonus, 0.0)

func test_get_context_tiers_after_unlock_sorts_ascending() -> void:
	_unlock(&"context", [&"ctx_200k", &"ctx_32k", &"ctx_1m"])
	var r: Dictionary = CommandBus.send(&"tech.get_context_tiers", {})
	var tiers: Array = r.get(&"tiers", [])
	# 4k + 32k + 200k + 1m = 4 tiers, sorted ascending.
	assert_eq(tiers.size(), 4)
	assert_eq(int(tiers[0].max_tokens), 4096)
	assert_eq(int(tiers[1].max_tokens), 32768)
	assert_eq(int(tiers[2].max_tokens), 200000)
	assert_eq(int(tiers[3].max_tokens), 1000000)

func test_list_multimodal_methods_baseline_only_cross_train() -> void:
	var r: Dictionary = CommandBus.send(&"tech.list_multimodal_methods", {})
	var methods: Array = r.get(&"methods", [])
	assert_true(methods.has(&"cross_train"), "cross_train baseline always available")
	assert_false(methods.has(&"diffusion_ar"), "diffusion_ar locked until dit_v1")

func test_list_multimodal_methods_after_dit_unlock() -> void:
	_unlock(&"arch", [&"dit_v1"])
	var r: Dictionary = CommandBus.send(&"tech.list_multimodal_methods", {})
	var methods: Array = r.get(&"methods", [])
	assert_true(methods.has(&"diffusion_ar"), "diffusion_ar unlocked via dit_v1")

# ---- helpers ----

func _make_pretrain_dataset(id: StringName, quality: float, size_b: float,
		tags: Array = []) -> Dataset:
	var ds := Dataset.new()
	ds.id = id
	ds.kind = &"pretrain"
	ds.source = &"collected"
	ds.modality = &"text"
	ds.size = size_b
	ds.quality = quality
	var typed: Array[StringName] = []
	for t in tags:
		typed.append(StringName(t))
	ds.coverage_tags = typed
	GameState.datasets.append(ds)
	return ds

func _make_model(arch: StringName, size_m: float,
		dataset_ids: Array = [], modalities: Array = [&"text"]) -> Model:
	var m := Model.new()
	m.id = &"m_test"
	m.arch = arch
	m.size_params = size_m
	m.active_param_ratio = Model.active_param_ratio_for(arch)
	var typed_ds: Array[StringName] = []
	for d in dataset_ids:
		typed_ds.append(StringName(d))
	m.dataset_ids = typed_ds
	var typed_in: Array[StringName] = []
	for x in modalities:
		typed_in.append(StringName(x))
	m.input_modalities = typed_in
	m.status = &"pretrained"
	GameState.models.append(m)
	return m

func _make_chief_scientist_lead(id: StringName) -> Lead:
	var l := Lead.new()
	l.id = id
	l.specialty = &"chief_scientist"
	l.ability = 70.0
	l.level = &"B"
	GameState.leads.append(l)
	return l

func _unlock(tree: StringName, node_ids: Array) -> void:
	if not GameState.unlocks.has(tree):
		GameState.unlocks[tree] = {}
	for nid in node_ids:
		GameState.unlocks[tree][StringName(nid)] = true
