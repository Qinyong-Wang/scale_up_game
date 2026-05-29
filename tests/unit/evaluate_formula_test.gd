extends GutTest

## Authoritative tests for the evaluate-task capability formula (v9, 2026-05).
## Per 任务系统设计.md §6.7 + 平衡参数.md §DatasetSystem 公式 + §evaluate产出.
##
## Formula:
##   base = clamp(20 + 12 × log10(size_M / 100), 10, 95)
##   weighted_q          = Σ(d.size × d.quality) / Σ(d.size)            over pretrain
##   data_quality_factor = clamp(0.5 + weighted_q, 0.5, 1.5)
##   data_breadth_factor = 0.65..1.0 from general-knowledge token×quality share
##   raw  = base × ARCH_CAPABILITY_COEF[arch] × loss_capability_coef
##              × data_quality_factor × data_breadth_factor
##              × data_efficiency × lead_eval_acc
##   per-axis ratio: log(1 + 20 × share) / log(21), share = token×quality share
##
## Convention used here: most baseline tests use `quality = 0.5` so
## `data_quality_factor = 1.0`, isolating the base/arch/eff/lead axes.


func before_each() -> void:
	GameState.reset()

func _make_dataset(id: StringName, quality: float,
		tags: Array = [], size_b: float = 100.0) -> Dataset:
	var ds := Dataset.new()
	ds.id = id
	ds.kind = &"pretrain"
	# v9: source no longer affects formulas; use `collected` for clarity.
	ds.source = &"collected"
	ds.size = size_b
	ds.quality = quality
	var typed: Array[StringName] = []
	for t in tags:
		typed.append(StringName(t))
	ds.coverage_tags = typed
	GameState.datasets.append(ds)
	return ds

# Optimal Chinchilla token count for a given model size_params (M).
# data_efficiency == 1.0 at this token count, isolating other multipliers.
func _optimal_tokens_b(size_params_m: float) -> float:
	return 0.02 * size_params_m

func _make_model(arch: StringName, size_m: float,
		dataset_ids: Array = [], modalities: Array = [&"text"]) -> Model:
	var m := Model.new()
	m.id = &"m_eval"
	m.arch = arch
	m.size_params = size_m
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

# v9 tag_ratio helper: log(1 + 20×share) / log(21).
func _expected_ratio(share: float) -> float:
	return log(1.0 + 20.0 * share) / log(21.0)

func _expected_breadth_factor(general_share: float) -> float:
	return 0.65 + (1.0 - 0.65) * minf(maxf(general_share, 0.0) / 0.45, 1.0)

# ---- size_to_cap_curve --------------------------------------------------

func test_base_curve_at_anchor_points() -> void:
	# Use quality=0.5 → data_quality_factor = 0.5 + 0.5 = 1.0 (neutral).
	# 100M → 20.00; 800M → 30.83; 8B → 42.84; 80B → 54.84.
	var pairs: Array = [
		[100.0, 20.0],
		[800.0, 30.83],
		[8_000.0, 42.84],
		[80_000.0, 54.84],
	]
	for p in pairs:
		GameState.reset()
		var size_m: float = float(p[0])
		var ds := _make_dataset(&"d_opt", 0.5, [], _optimal_tokens_b(size_m))
		var m := _make_model(&"ant_v1", size_m, [ds.id])
		var got: float = TaskSystem._compute_capability_measured(m, null).get(&"general", -1.0)
		assert_almost_eq(got, float(p[1]), 0.5,
				"size %s → base %s" % [p[0], p[1]])

func test_base_curve_clamps_low_high() -> void:
	GameState.reset()
	var ds_tiny := _make_dataset(&"d_tiny", 0.5, [], _optimal_tokens_b(1.0))
	var m_tiny := _make_model(&"ant_v1", 1.0, [ds_tiny.id])
	assert_almost_eq(
		float(TaskSystem._compute_capability_measured(m_tiny, null).get(&"general", -1.0)),
		10.0, 0.5)
	GameState.reset()
	var ds_huge := _make_dataset(&"d_huge", 0.5, [], _optimal_tokens_b(1e12))
	var m_huge := _make_model(&"ant_v1", 1e12, [ds_huge.id])
	assert_almost_eq(
		float(TaskSystem._compute_capability_measured(m_huge, null).get(&"general", -1.0)),
		95.0, 0.5)

# ---- arch_capability_coef -----------------------------------------------

func test_arch_coef_uses_authoritative_table() -> void:
	var ds := _make_dataset(&"d_q1", 0.5, [], _optimal_tokens_b(800.0))
	var m1 := _make_model(&"ant_v1", 800.0, [ds.id])
	var v1: float = TaskSystem._compute_capability_measured(m1, null).get(&"general", 0.0)
	_clear_models()
	var m2 := _make_model(&"ant_v2", 800.0, [ds.id])
	var v2: float = TaskSystem._compute_capability_measured(m2, null).get(&"general", 0.0)
	assert_almost_eq(v2, v1 * 1.05, 0.1)

func test_arch_coef_octopus_v2_strongest() -> void:
	var ds := _make_dataset(&"d_q1", 0.5, [], _optimal_tokens_b(800.0))
	_make_model(&"octopus_v2", 800.0, [ds.id])
	var v: float = TaskSystem._compute_capability_measured(GameState.models[0], null).get(&"general", 0.0)
	assert_almost_eq(v, 30.83 * 1.15, 0.5)

# ---- posttrain_count no longer affects evaluate raw score (Bug B fix) ----

func test_posttrain_count_does_not_lift_evaluate_score() -> void:
	var ds := _make_dataset(&"d_q1", 0.5, [], _optimal_tokens_b(800.0))
	var m := _make_model(&"ant_v1", 800.0, [ds.id])
	var base: float = TaskSystem._compute_capability_measured(m, null).get(&"general", 0.0)
	m.posttrain_count = 1
	var v1: float = TaskSystem._compute_capability_measured(m, null).get(&"general", 0.0)
	m.posttrain_count = 5
	var v5: float = TaskSystem._compute_capability_measured(m, null).get(&"general", 0.0)
	assert_almost_eq(v1, base, 0.001)
	assert_almost_eq(v5, base, 0.001)

# ---- lead_eval_acc reads ml_research_lead, not eval_lead ----------------

func test_eval_lead_specialty_does_not_lift_score() -> void:
	var ds := _make_dataset(&"d_q1", 0.5, [], _optimal_tokens_b(800.0))
	var m := _make_model(&"ant_v1", 800.0, [ds.id])
	var without: float = TaskSystem._compute_capability_measured(m, null).get(&"general", 0.0)
	var lead := Lead.new()
	lead.id = &"l_eval"
	lead.specialty = &"eval_lead"
	lead.ability = 90.0
	GameState.leads.append(lead)
	var withlead: float = TaskSystem._compute_capability_measured(m, lead).get(&"general", 0.0)
	assert_almost_eq(withlead, without, 0.001)

func test_ml_research_lead_lifts_evaluate_score() -> void:
	var ds := _make_dataset(&"d_q1", 0.5, [], _optimal_tokens_b(800.0))
	var m := _make_model(&"ant_v1", 800.0, [ds.id])
	var without: float = TaskSystem._compute_capability_measured(m, null).get(&"general", 0.0)
	var lead := Lead.new()
	lead.id = &"l_mlr"
	lead.specialty = &"ml_research_lead"
	lead.ability = 80.0
	GameState.leads.append(lead)
	var withlead: float = TaskSystem._compute_capability_measured(m, lead).get(&"general", 0.0)
	assert_almost_eq(withlead / without, 1.088, 0.01)

# ---- loss C-axis capability_coef multiplies evaluate raw ----------------

func test_loss_capability_coef_lifts_evaluate_score() -> void:
	# ce_baseline (default) → coef 1.0; mtp → coef 1.08. The C-axis loss node
	# must scale the evaluate raw score, not just appear in modifier_breakdown.
	var ds := _make_dataset(&"d_q1", 0.5, [], _optimal_tokens_b(800.0))
	var m_base := _make_model(&"ant_v1", 800.0, [ds.id])
	var base: float = TaskSystem._compute_capability_measured(m_base, null).get(&"general", 0.0)
	_clear_models()
	var m_mtp := _make_model(&"ant_v1", 800.0, [ds.id])
	m_mtp.loss_id = &"mtp"
	var lifted: float = TaskSystem._compute_capability_measured(m_mtp, null).get(&"general", 0.0)
	assert_almost_eq(lifted / base, 1.08, 0.01,
			"mtp loss (capability_coef 1.08) must scale evaluate raw")

func test_ce_baseline_loss_is_neutral() -> void:
	var ds := _make_dataset(&"d_q1", 0.5, [], _optimal_tokens_b(800.0))
	var m := _make_model(&"ant_v1", 800.0, [ds.id])
	# default loss_id is ce_baseline → coef 1.0, raw == un-lossed baseline.
	var got: float = TaskSystem._compute_capability_measured(m, null).get(&"general", 0.0)
	assert_almost_eq(got, 30.83, 0.5, "ce_baseline loss leaves raw unchanged")

# ---- v9 tag_ratio: token×quality weighted share + log dampening ---------

func test_code_axis_uses_log_curve_at_50_percent_share() -> void:
	# Two datasets same size and quality, one tagged code → share=0.5.
	# ratio = log(11)/log(21) ≈ 0.787.
	var half: float = _optimal_tokens_b(800.0) / 2.0
	var ds1 := _make_dataset(&"d_a", 0.5, [&"code"], half)
	var ds2 := _make_dataset(&"d_b", 0.5, [], half)
	var m := _make_model(&"ant_v1", 800.0, [ds1.id, ds2.id])
	var caps: Dictionary = TaskSystem._compute_capability_measured(m, null)
	# raw = 30.83 × 1.0 (factor) × 1.0 (ant_v1) × 1.0 (eff) × 1.0 (lead) = 30.83.
	assert_almost_eq(float(caps.get(&"general", 0.0)), 30.83, 0.5)
	assert_almost_eq(float(caps.get(&"code", 0.0)), 30.83 * _expected_ratio(0.5), 0.5,
			"v9: 50%% token share → log ratio ≈ 0.787 of raw, not 0.5")

func test_reasoning_axis_uses_chat_or_reasoning_tag() -> void:
	var third: float = _optimal_tokens_b(800.0) / 3.0
	var ds1 := _make_dataset(&"d_a", 0.5, [&"chat"], third)
	var ds2 := _make_dataset(&"d_b", 0.5, [&"reasoning"], third)
	var ds3 := _make_dataset(&"d_c", 0.5, [], third)
	var m := _make_model(&"ant_v1", 800.0, [ds1.id, ds2.id, ds3.id])
	var reasoning_score: float = TaskSystem._compute_capability_measured(m, null).get(&"reasoning", 0.0)
	# share = 2/3 ≈ 0.667. ratio = log(14.33)/log(21) ≈ 0.875.
	assert_almost_eq(reasoning_score, 30.83 * _expected_ratio(2.0 / 3.0), 0.5)

func test_multimodal_axis_zero_without_image_modality() -> void:
	var ds := _make_dataset(&"d_q1", 0.5, [], _optimal_tokens_b(800.0))
	var m := _make_model(&"ant_v1", 800.0, [ds.id], [&"text"])
	var multimodal_score: float = TaskSystem._compute_capability_measured(m, null).get(&"multimodal", -1.0)
	assert_eq(multimodal_score, 0.0)

func test_multimodal_axis_nonzero_with_image_input() -> void:
	var ds := _make_dataset(&"d_q1", 0.5, [], _optimal_tokens_b(800.0))
	var m := _make_model(&"ant_v1", 800.0, [ds.id], [&"text", &"image"])
	var multimodal_score: float = TaskSystem._compute_capability_measured(m, null).get(&"multimodal", -1.0)
	assert_gt(multimodal_score, 0.0)

# ---- v9 NEW: token weighting + quality weighting in tag_ratio -----------

func test_tag_ratio_is_token_weighted_not_count_weighted() -> void:
	# 1B math-reasoning + 15B web (web has no code/reasoning tag).
	# share(reasoning) = (1×0.5)/((1+15)×0.5) = 1/16 = 0.0625.
	# ratio ≈ log(1 + 1.25)/log(21) = log(2.25)/log(21) ≈ 0.266.
	# Old v8 formula was hit/total = 1/2 = 0.5 → tiny set falsely "half-covered".
	var opt: float = _optimal_tokens_b(800.0)
	# Scale to optimal: 1 + 15 = 16; use opt/16 per "unit".
	_make_dataset(&"ds_math", 0.5, [&"reasoning"], opt / 16.0)
	_make_dataset(&"ds_web", 0.5, [&"web"], opt * 15.0 / 16.0)
	var m := _make_model(&"ant_v1", 800.0, [&"ds_math", &"ds_web"])
	var caps: Dictionary = TaskSystem._compute_capability_measured(m, null)
	var raw: float = float(caps.get(&"general", 0.0))
	var reasoning: float = float(caps.get(&"reasoning", 0.0))
	# Expected share ≈ 1/16 = 0.0625, ratio ≈ 0.266.
	assert_almost_eq(reasoning / raw, _expected_ratio(1.0 / 16.0), 0.05,
			"v9: tag_ratio must reflect token weight, not dataset count")

func test_tag_ratio_is_quality_weighted() -> void:
	# Same SIZE but different quality. 8B q=0.2 code + 8B q=1.0 non-code.
	# share(code) = (8×0.2) / (8×0.2 + 8×1.0) = 1.6 / 9.6 = 0.1667.
	# ratio ≈ log(1+3.33)/log(21) = log(4.33)/log(21) ≈ 0.482.
	# If quality were ignored: share would be 0.5 → ratio ≈ 0.787.
	var half: float = _optimal_tokens_b(800.0) / 2.0
	_make_dataset(&"ds_code_lo", 0.2, [&"code"], half)
	_make_dataset(&"ds_web_hi", 1.0, [&"web"], half)
	var m := _make_model(&"ant_v1", 800.0, [&"ds_code_lo", &"ds_web_hi"])
	var caps: Dictionary = TaskSystem._compute_capability_measured(m, null)
	var raw: float = float(caps.get(&"general", 0.0))
	var code: float = float(caps.get(&"code", 0.0))
	var got_ratio: float = code / raw
	assert_almost_eq(got_ratio, _expected_ratio(1.6 / 9.6), 0.05,
			"v9: low-quality code can't claim full share against high-quality web")

func test_pure_code_pretrain_gets_breadth_penalty() -> void:
	# Pure specialty data still gives code ratio=1, but raw is penalized because
	# it lacks the broad world/language substrate seen in real pre-training mixes.
	var ds := _make_dataset(&"d_code_only", 0.5, [&"code"], _optimal_tokens_b(800.0))
	var m := _make_model(&"ant_v1", 800.0, [ds.id])
	var caps: Dictionary = TaskSystem._compute_capability_measured(m, null)
	var expected_raw: float = 30.83 * _expected_breadth_factor(0.0)
	assert_almost_eq(float(caps.get(&"general", 0.0)), expected_raw, 0.5,
			"v10: pure code pretrain should carry the minimum breadth factor")
	assert_almost_eq(float(caps.get(&"code", 0.0)), expected_raw, 0.5,
			"v10: code ratio remains 1.0 when all weighted tokens are code")

func test_breadth_penalty_is_neutral_at_realistic_general_share() -> void:
	# 45% broad knowledge + 55% code reaches the target breadth share, so raw is
	# neutral while the code axis still uses the log-ratio curve for 55% share.
	var opt: float = _optimal_tokens_b(800.0)
	_make_dataset(&"ds_web", 0.5, [&"web"], opt * 0.45)
	_make_dataset(&"ds_code", 0.5, [&"code"], opt * 0.55)
	var m := _make_model(&"ant_v1", 800.0, [&"ds_web", &"ds_code"])
	var caps: Dictionary = TaskSystem._compute_capability_measured(m, null)
	var general: float = float(caps.get(&"general", 0.0))
	assert_almost_eq(general, 30.83, 0.5,
			"v10: breadth factor should be neutral once general share reaches 45%%")
	assert_almost_eq(float(caps.get(&"code", 0.0)),
			general * _expected_ratio(0.55), 0.5,
			"v10: code axis should still follow token×quality tag share")

func test_full_share_yields_ratio_one() -> void:
	# Single dataset tagged code → 100% share → ratio = 1.0.
	var ds := _make_dataset(&"d_code", 0.5, [&"code"], _optimal_tokens_b(800.0))
	var m := _make_model(&"ant_v1", 800.0, [ds.id])
	var caps: Dictionary = TaskSystem._compute_capability_measured(m, null)
	var raw: float = float(caps.get(&"general", 0.0))
	var code: float = float(caps.get(&"code", 0.0))
	assert_almost_eq(code / raw, 1.0, 0.01,
			"v9: 100%% share → ratio = 1.0")

func test_zero_share_yields_ratio_zero() -> void:
	# Single dataset tagged only web → 0% code share → ratio = 0.
	var ds := _make_dataset(&"d_web", 0.5, [&"web"], _optimal_tokens_b(800.0))
	var m := _make_model(&"ant_v1", 800.0, [ds.id])
	var caps: Dictionary = TaskSystem._compute_capability_measured(m, null)
	var code: float = float(caps.get(&"code", 0.0))
	assert_almost_eq(code, 0.0, 0.001)

# ---- 数值常量 SCALING_LAW_FLOPS_C ----------------------------------------

func test_scaling_law_constant_is_six_per_design() -> void:
	assert_eq(TaskSystem.SCALING_LAW_FLOPS_C, 6.0)

func test_tag_ratio_log_k_is_twenty() -> void:
	# Regression guard: tuning constant lives at module scope for tests.
	assert_eq(TaskSystem.TAG_RATIO_LOG_K, 20.0)

# ---- helpers ------------------------------------------------------------

func _clear_models() -> void:
	GameState.models.clear()
