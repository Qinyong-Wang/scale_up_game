extends GutTest

## v9 (2026-05): Pretrain quality is now token×quality weighted, not source-min.
## Per design/数据集系统设计.md §1 + 任务系统设计.md §6.7 + 平衡参数.md §DatasetSystem 公式.
##
## - _scaling_law no longer uses any "data quality" factor: training time only
##   depends on Σ tokens (and the usual A/B/C/D + lead/staff/dc multipliers).
## - _compute_capability_measured's `data_quality_factor` = clamp(0.5 + Σ(size×q)/Σ(size), 0.5, 1.5).
## - source ∈ {open_source, purchased, collected} no longer affects evaluate
##   or duration; it's audit metadata only.


func before_each() -> void:
	GameState.reset()

var _dc_seq: int = 0

func _synthetic_dc(train_tflops: float = 50_000.0) -> StringName:
	_dc_seq += 1
	var dc := Datacenter.new()
	dc.id = StringName("dc_test_pqf_%d" % _dc_seq)
	dc.facility_spec_id = &"facility_solo"
	dc.ownership = &"owned"
	dc.train_tflops = train_tflops
	dc.cluster_efficiency = 1.0
	dc.gpu_count = 1
	dc.status = &"idle"
	GameState.datacenters.append(dc)
	return dc.id

func _add_dataset(id: StringName, source: StringName, size_b: float = 100.0,
		quality: float = 0.5) -> StringName:
	var ds := Dataset.new()
	ds.id = id
	ds.kind = &"pretrain"
	ds.source = source
	ds.size = size_b
	ds.quality = quality
	GameState.datasets.append(ds)
	return ds.id

# ---- _scaling_law no longer reads quality / source (v9) -----------------

func test_scaling_law_duration_is_source_invariant() -> void:
	# v9: open / purchased / collected with same tokens → same weeks.
	# otter_m (800M), ant_v2 (train_coef 1.2), dc 50k tflops eff=1.0.
	# compute = 6 × 800 × 100 = 480_000; divisor = 50000 × 1.0 × 1.2 = 60_000.
	# weeks = ceil(480000 / 60000) = 8.
	var dc_id := _synthetic_dc()
	for src in [&"open_source", &"purchased", &"collected"]:
		GameState.datasets.clear()
		_add_dataset(StringName("ds_%s" % src), src, 100.0, 0.5)
		var r: Dictionary = CommandBus.send(&"task.start", {
			template_id = &"train_otter_m",
			lead_ids = [], staff = {},
			datacenter_id = dc_id,
			dataset_ids = [StringName("ds_%s" % src)],
		})
		assert_true(r.ok, "start failed for source %s: %s" % [src, r])
		assert_eq(int(r.total_weeks), 8,
				"v9: duration must be source-invariant; got %d for source=%s"
						% [int(r.total_weeks), src])
		CommandBus.send(&"task.cancel", {task_id = r.task_id})

func test_scaling_law_duration_is_quality_invariant() -> void:
	# v9: quality 0.3 / 0.7 / 0.95 with same tokens → same weeks.
	var dc_id := _synthetic_dc()
	for q in [0.3, 0.7, 0.95]:
		GameState.datasets.clear()
		_add_dataset(&"ds_q", &"collected", 100.0, q)
		var r: Dictionary = CommandBus.send(&"task.start", {
			template_id = &"train_otter_m",
			lead_ids = [], staff = {},
			datacenter_id = dc_id,
			dataset_ids = [&"ds_q"],
		})
		assert_true(r.ok)
		assert_eq(int(r.total_weeks), 8,
				"v9: duration must be quality-invariant; got %d for q=%s"
						% [int(r.total_weeks), q])
		CommandBus.send(&"task.cancel", {task_id = r.task_id})

# ---- _compute_capability_measured data_quality_factor (v9) --------------

func _make_eval_model(dataset_ids: Array) -> Model:
	var m := Model.new()
	m.id = &"m_eval"
	m.arch = &"ant_v1"
	m.size_params = 800.0
	var typed: Array[StringName] = []
	for d in dataset_ids:
		typed.append(StringName(d))
	m.dataset_ids = typed
	m.input_modalities = [&"text"] as Array[StringName]
	GameState.models.append(m)
	return m

func _optimal_tokens(size_m: float) -> float:
	return 0.02 * size_m

func test_evaluate_data_quality_factor_token_weighted() -> void:
	# Two pretrain datasets at Chinchilla optimal: 8B quality=0.3 + 8B quality=0.9.
	# weighted_q = (8×0.3 + 8×0.9) / 16 = 0.6. factor = 0.5 + 0.6 = 1.1.
	var opt: float = _optimal_tokens(800.0)
	_add_dataset(&"ds_lo", &"open_source", opt / 2.0, 0.3)
	_add_dataset(&"ds_hi", &"purchased", opt / 2.0, 0.9)
	var m := _make_eval_model([&"ds_lo", &"ds_hi"])
	var general: float = TaskSystem._compute_capability_measured(m, null).get(&"general", 0.0)
	# base(800M) ≈ 30.83, ant_v1 ×1.0, data_efficiency ≈ 1.0, lead = 1.0.
	# expected = 30.83 × 1.1 ≈ 33.91.
	assert_almost_eq(general, 30.83 * 1.1, 0.5,
			"v9: data_quality_factor must be token-weighted average of size×quality")

func test_evaluate_data_quality_factor_biased_by_size() -> void:
	# 15B quality=0.3 + 1B quality=0.95 → weighted_q ≈ (15×0.3 + 1×0.95)/16 ≈ 0.341.
	# 1B high-quality cannot save 15B low-quality. factor ≈ 0.841.
	var opt: float = _optimal_tokens(800.0)
	# Scale up sizes proportionally to keep ≈ optimal tokens.
	_add_dataset(&"ds_bulk", &"open_source", opt * 15.0 / 16.0, 0.3)
	_add_dataset(&"ds_gem", &"purchased", opt * 1.0 / 16.0, 0.95)
	var m := _make_eval_model([&"ds_bulk", &"ds_gem"])
	var general: float = TaskSystem._compute_capability_measured(m, null).get(&"general", 0.0)
	# weighted_q = 0.3 × 15/16 + 0.95 × 1/16 = 0.281 + 0.059 = 0.340625.
	# factor = 0.5 + 0.341 = 0.841. base 30.83 × 0.841 ≈ 25.93.
	assert_almost_eq(general, 30.83 * 0.841, 0.5,
			"v9: bulk low-quality token weight should dominate over tiny high-quality set")

func test_evaluate_data_quality_factor_clamped_to_cap() -> void:
	# Pure quality=1.0 → factor 1.5 (cap).
	var opt: float = _optimal_tokens(800.0)
	_add_dataset(&"ds_godly", &"collected", opt, 1.0)
	var m := _make_eval_model([&"ds_godly"])
	var general: float = TaskSystem._compute_capability_measured(m, null).get(&"general", 0.0)
	assert_almost_eq(general, 30.83 * 1.5, 0.5,
			"v9: data_quality_factor caps at 1.5 even with quality=1.0")

func test_evaluate_data_quality_factor_clamped_to_floor() -> void:
	# Pure quality=0.0 → factor max(0.5, 0.5) = 0.5.
	var opt: float = _optimal_tokens(800.0)
	_add_dataset(&"ds_trash", &"open_source", opt, 0.0)
	var m := _make_eval_model([&"ds_trash"])
	var general: float = TaskSystem._compute_capability_measured(m, null).get(&"general", 0.0)
	assert_almost_eq(general, 30.83 * 0.5, 0.5,
			"v9: data_quality_factor floors at 0.5 even with quality=0.0")

func test_evaluate_source_field_does_not_affect_score_in_v9() -> void:
	# Same size + quality, different source → identical evaluate score.
	# (regression guard against re-introducing source-min behavior)
	var opt: float = _optimal_tokens(800.0)
	_add_dataset(&"ds_open", &"open_source", opt, 0.7)
	var m1 := _make_eval_model([&"ds_open"])
	var v_open: float = TaskSystem._compute_capability_measured(m1, null).get(&"general", 0.0)
	GameState.models.clear()
	GameState.datasets.clear()
	_add_dataset(&"ds_buy", &"purchased", opt, 0.7)
	var m2 := _make_eval_model([&"ds_buy"])
	var v_buy: float = TaskSystem._compute_capability_measured(m2, null).get(&"general", 0.0)
	assert_almost_eq(v_buy, v_open, 0.001,
			"v9: source field must not affect evaluate score")
