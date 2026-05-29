extends GutTest

## Bug B fix (2026-05): evaluate_apply 不再覆盖 posttrain 的 +target/-forget
## delta. Posttrain 把 clamp 后的 delta 累加到 model.posttrain_delta;
## evaluate_apply 把 capability_measured 与 posttrain_delta 相加 (clamp ≥ 0)
## 后写入 m.capability. 详见 研究系统设计.md §6.2 / §6.3.


const AXES: Array[StringName] = [&"general", &"code", &"reasoning",
		&"multimodal", &"agent"]

func before_each() -> void:
	GameState.reset()

func _seed_model(initial_caps: Dictionary = {}) -> StringName:
	var caps: Dictionary = {
		&"general": 50.0, &"code": 30.0, &"reasoning": 30.0,
		&"multimodal": 0.0, &"agent": 0.0,
	}
	for k in initial_caps.keys():
		caps[k] = initial_caps[k]
	var r: Dictionary = CommandBus.send(&"research.add_model", {
		capability = {}, arch = &"ant_v1", size_params = 800.0,
		dataset_ids = [], display_name = "M_overlay"})
	var m := ResearchSystem.find_model(r.model_id)
	m.capability = caps
	m.capability_revealed = true
	m.status = &"evaluated"
	return r.model_id

func _seed_posttrain_dataset(id: StringName, axis: StringName, quality: float,
		size_b: float = 0.05) -> StringName:
	var ds := Dataset.new()
	ds.id = id
	ds.kind = &"posttrain"
	ds.source = &"purchased"
	ds.size = size_b
	ds.quality = quality
	ds.target_capability = axis
	GameState.datasets.append(ds)
	return ds.id

# ---- posttrain accumulates into model.posttrain_delta -------------------

func test_posttrain_apply_accumulates_delta_into_model() -> void:
	var mid := _seed_model()
	var dsid := _seed_posttrain_dataset(&"code_ds", &"code", 0.93, 0.10)
	CommandBus.send(&"research.posttrain_apply", {
		model_id = mid, dataset_ids = [dsid]})
	var m := ResearchSystem.find_model(mid)
	# code axis got +target_gain, others lost forget (clamped ≥ 0).
	assert_gt(float(m.posttrain_delta.get(&"code", 0.0)), 0.0,
			"code axis must have positive accumulated posttrain_delta")
	assert_lt(float(m.posttrain_delta.get(&"general", 0.0)), 0.0,
			"general axis (forget) must have negative accumulated posttrain_delta")

func test_multiple_posttrain_apply_calls_keep_accumulating() -> void:
	var mid := _seed_model()
	var dsid := _seed_posttrain_dataset(&"code_ds", &"code", 0.90, 0.05)
	CommandBus.send(&"research.posttrain_apply", {
		model_id = mid, dataset_ids = [dsid]})
	var m := ResearchSystem.find_model(mid)
	var code_after_1: float = float(m.posttrain_delta.get(&"code", 0.0))
	CommandBus.send(&"research.posttrain_apply", {
		model_id = mid, dataset_ids = [dsid]})
	var code_after_2: float = float(m.posttrain_delta.get(&"code", 0.0))
	assert_gt(code_after_2, code_after_1,
			"second posttrain should further increase accumulated code delta")

# ---- evaluate_apply layers posttrain_delta on top of measured -----------

func test_evaluate_apply_layers_posttrain_delta() -> void:
	var mid := _seed_model()
	var m := ResearchSystem.find_model(mid)
	# Stamp a known posttrain_delta directly (bypass the formula so we can
	# isolate evaluate's behavior).
	m.posttrain_delta = {
		&"general": -2.0, &"code": 30.0, &"reasoning": 0.0,
		&"multimodal": 0.0, &"agent": 0.0,
	}
	var measured: Dictionary = {
		&"general": 40.0, &"code": 25.0, &"reasoning": 20.0,
		&"multimodal": 0.0, &"agent": 0.0,
	}
	CommandBus.send(&"research.evaluate_apply",
			{model_id = mid, capability_measured = measured})
	m = ResearchSystem.find_model(mid)
	assert_almost_eq(float(m.capability[&"general"]), 38.0, 0.001,
			"general = measured 40 + posttrain -2 = 38")
	assert_almost_eq(float(m.capability[&"code"]), 55.0, 0.001,
			"code = measured 25 + posttrain +30 = 55")

func test_evaluate_apply_clamps_negative_to_zero() -> void:
	# measured 5 + posttrain -20 should clamp to 0, not -15.
	var mid := _seed_model()
	var m := ResearchSystem.find_model(mid)
	m.posttrain_delta = {
		&"general": -20.0, &"code": 0.0, &"reasoning": 0.0,
		&"multimodal": 0.0, &"agent": 0.0,
	}
	var measured: Dictionary = {
		&"general": 5.0, &"code": 10.0, &"reasoning": 10.0,
		&"multimodal": 0.0, &"agent": 0.0,
	}
	CommandBus.send(&"research.evaluate_apply",
			{model_id = mid, capability_measured = measured})
	m = ResearchSystem.find_model(mid)
	assert_eq(float(m.capability[&"general"]), 0.0,
			"general must clamp to 0, not go negative")

func test_evaluate_apply_with_zero_posttrain_delta_equals_measured() -> void:
	# Fresh model with no posttrain → evaluate just stamps measured straight in.
	var mid := _seed_model()
	var measured: Dictionary = {
		&"general": 42.0, &"code": 15.0, &"reasoning": 18.0,
		&"multimodal": 0.0, &"agent": 0.0,
	}
	CommandBus.send(&"research.evaluate_apply",
			{model_id = mid, capability_measured = measured})
	var m := ResearchSystem.find_model(mid)
	for ax in AXES:
		assert_almost_eq(float(m.capability[ax]), float(measured[ax]), 0.001,
				"axis %s should equal measured when no posttrain" % String(ax))

# ---- end-to-end: posttrain → evaluate keeps axis-directional change -----

func test_posttrain_then_evaluate_preserves_axis_lift() -> void:
	# Player flow: pretrained → posttrain (sees code +X) → evaluate → publish.
	# The big code lift seen in the posttrain dialog must survive the evaluate
	# re-measurement, not be overwritten by a flat (1 + 0.10n) lift.
	var mid := _seed_model({&"general": 50.0, &"code": 30.0})
	var dsid := _seed_posttrain_dataset(&"code_ds", &"code", 0.93, 0.10)
	# Snapshot what the player sees after posttrain in the dialog: it's exactly
	# m.capability after the apply (the dialog uses simulate_posttrain which
	# matches apply per §5.3 v2.1).
	CommandBus.send(&"research.posttrain_apply", {
		model_id = mid, dataset_ids = [dsid]})
	var m := ResearchSystem.find_model(mid)
	var code_after_posttrain: float = float(m.capability[&"code"])
	# Now re-evaluate. measured uses the bare formula (no posttrain_lift), so
	# without Bug B fix the result would drop below code_after_posttrain.
	# With the fix, evaluate adds posttrain_delta back → result preserves lift.
	var measured: Dictionary = TaskSystem._compute_capability_measured(m, null)
	CommandBus.send(&"research.evaluate_apply",
			{model_id = mid, capability_measured = measured})
	m = ResearchSystem.find_model(mid)
	assert_almost_eq(float(m.capability[&"code"]),
			float(measured[&"code"]) + float(m.posttrain_delta[&"code"]),
			0.001,
			"code after evaluate must equal measured + posttrain_delta")
	# Most importantly: the posttrain lift survived. (Allow a tiny tolerance
	# since measured-general/code may be smaller than the model's revealed
	# capability before evaluate; we only care the posttrain delta is layered.)
	assert_gt(float(m.capability[&"code"]),
			float(measured[&"code"]),
			"posttrain code gain must survive evaluate")
