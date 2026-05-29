extends GutTest

## Posttrain v2 — per-dataset target +X / others -Y capability delta,
## fixed-tier duration table, dataset kind / dc gpu validation.
## Per design/研究系统设计.md §6.2 (v2) + 任务系统设计.md §6.6.2 (v2)
##     + 平衡参数.md Posttrain 能力增减系数.


func before_each() -> void:
	GameState.reset()

func _seed_model(size_params_m: float = 800.0,
		initial_caps: Dictionary = {}) -> StringName:
	var caps: Dictionary = {
		&"general": 50.0, &"code": 30.0, &"reasoning": 30.0,
		&"multimodal": 0.0, &"agent": 0.0,
	}
	for k in initial_caps.keys():
		caps[k] = initial_caps[k]
	var r: Dictionary = CommandBus.send(&"research.add_model", {
		capability = {}, arch = &"ant_v1",
		size_params = size_params_m,
		dataset_ids = [], display_name = "M_pt"})
	var m := ResearchSystem.find_model(r.model_id)
	m.capability = caps
	m.capability_revealed = true  # pretend it was evaluated for the test
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

# ---- core formula --------------------------------------------------------

func test_high_quality_posttrain_adds_to_target_axis() -> void:
	var mid := _seed_model()
	var dsid := _seed_posttrain_dataset(&"code_ds_premium", &"code", 0.93, 0.10)
	var code_before: float = float(GameState.models[0].capability[&"code"])
	var r: Dictionary = CommandBus.send(&"research.posttrain_apply", {
		model_id = mid, dataset_ids = [dsid],
	})
	assert_true(r.ok)
	var code_after: float = float(GameState.models[0].capability[&"code"])
	# v12: base_power=max(size头30.84, general50)=50 → ceiling 70. code 从 30 起,
	# raw_gain=8*0.8649*log2(101)≈46.07; realized=(70-30)*(1-exp(-46.07/35))≈29.3.
	assert_almost_eq(code_after - code_before, 29.3, 2.0,
			"premium posttrain 把目标轴朝天花板 70 饱和, 从 30 起约 +29")

func test_posttrain_forgets_other_axes_evenly() -> void:
	var mid := _seed_model(800.0, {&"general": 50.0, &"reasoning": 30.0})
	var dsid := _seed_posttrain_dataset(&"code_only", &"code", 0.85, 0.05)
	# forget = K_f × (1 - q) = 8 × 0.15 = 1.20.
	var general_before: float = float(GameState.models[0].capability[&"general"])
	var reasoning_before: float = float(GameState.models[0].capability[&"reasoning"])
	CommandBus.send(&"research.posttrain_apply", {
		model_id = mid, dataset_ids = [dsid],
	})
	var general_after: float = float(GameState.models[0].capability[&"general"])
	var reasoning_after: float = float(GameState.models[0].capability[&"reasoning"])
	assert_almost_eq(general_before - general_after, 1.20, 0.1)
	assert_almost_eq(reasoning_before - reasoning_after, 1.20, 0.1)

func test_low_quality_posttrain_net_negative_total() -> void:
	# q=0.30, size=0.02B → gain ≈ 8 × 0.09 × log2(21) ≈ 3.16.
	# forget = 8 × 0.70 = 5.60.
	# Initial caps below: g=50, c=50, r=50, m=0, a=0.
	# Only general + reasoning have headroom to lose 5.60 each (multimodal/agent
	# at 0 stay clamped at 0 — design 研究系统设计.md §6.2 + §5.3 v2.1 clamp rule).
	# v12: code 从 50 起朝天花板 70 饱和, raw_gain≈3.16 → realized≈1.7 (gap 仅 20).
	# forget=5.60 砍 general+reasoning 各 5.60. Net ≈ +1.7 - 5.6 - 5.6 ≈ -9.5.
	# Test only asserts total_after < total_before, which still holds.
	var mid := _seed_model(800.0, {
		&"general": 50.0, &"code": 50.0, &"reasoning": 50.0,
		&"multimodal": 0.0, &"agent": 0.0,
	})
	var dsid := _seed_posttrain_dataset(&"bad_data", &"code", 0.30, 0.02)
	var total_before: float = 0.0
	for ax in [&"general", &"code", &"reasoning", &"multimodal", &"agent"]:
		total_before += float(GameState.models[0].capability[ax])
	CommandBus.send(&"research.posttrain_apply", {
		model_id = mid, dataset_ids = [dsid],
	})
	var total_after: float = 0.0
	for ax in [&"general", &"code", &"reasoning", &"multimodal", &"agent"]:
		total_after += float(GameState.models[0].capability[ax])
	assert_lt(total_after, total_before,
			"low-quality posttrain should make net total decrease")

func test_multi_dataset_aggregates_not_stacks() -> void:
	# v12 防拆碎: 两份 0.05B code 聚合成 0.10B 单轴组, 结果必须等于「一份 0.10B」,
	# 而不是旧版的「两份各自结算再线性相加」(那会给约 2× 收益, 是被堵的漏洞).
	var mid_split := _seed_model()
	var a := _seed_posttrain_dataset(&"code_a", &"code", 0.85, 0.05)
	var b := _seed_posttrain_dataset(&"code_b", &"code", 0.85, 0.05)
	var split_before: float = float(GameState.models[0].capability[&"code"])
	CommandBus.send(&"research.posttrain_apply", {
		model_id = mid_split, dataset_ids = [a, b],
	})
	var split_delta: float = float(GameState.models[0].capability[&"code"]) - split_before

	GameState.reset()
	var mid_one := _seed_model()
	var c := _seed_posttrain_dataset(&"code_one", &"code", 0.85, 0.10)
	var one_before: float = float(GameState.models[0].capability[&"code"])
	CommandBus.send(&"research.posttrain_apply", {
		model_id = mid_one, dataset_ids = [c],
	})
	var one_delta: float = float(GameState.models[0].capability[&"code"]) - one_before

	assert_almost_eq(split_delta, one_delta, 0.5,
			"两份 0.05B 必须 == 一份 0.10B (聚合, 不再线性堆叠)")

func test_multi_dataset_different_axes() -> void:
	var mid := _seed_model()
	var a := _seed_posttrain_dataset(&"code_a", &"code", 0.85, 0.05)
	var b := _seed_posttrain_dataset(&"reasoning_a", &"reasoning", 0.85, 0.05)
	var code_before: float = float(GameState.models[0].capability[&"code"])
	var reasoning_before: float = float(GameState.models[0].capability[&"reasoning"])
	CommandBus.send(&"research.posttrain_apply", {
		model_id = mid, dataset_ids = [a, b],
	})
	# v12: 各轴从自己的数据集朝天花板 70 饱和 (从 30 起 ~+24), 再被另一轴组的
	# forget 砍 ~-1.2. 两轴净增均明显为正 (约 +23).
	var code_delta: float = float(GameState.models[0].capability[&"code"]) - code_before
	var reasoning_delta: float = float(GameState.models[0].capability[&"reasoning"]) - reasoning_before
	assert_gt(code_delta, 15.0, "code axis should net-gain when own dataset present")
	assert_gt(reasoning_delta, 15.0, "reasoning axis should net-gain when own dataset present")

# ---- side effects --------------------------------------------------------

func test_posttrain_marks_capability_revealed_not_stale() -> void:
	# v2: capability is authoritative after posttrain; no re-evaluate needed.
	var mid := _seed_model()
	var dsid := _seed_posttrain_dataset(&"any_ds", &"general", 0.85, 0.05)
	CommandBus.send(&"research.posttrain_apply", {
		model_id = mid, dataset_ids = [dsid],
	})
	var m := ResearchSystem.find_model(mid)
	assert_true(m.capability_revealed)
	assert_false(m.capability_stale,
			"v2 posttrain should not stale capability")

func test_posttrain_increments_posttrain_count() -> void:
	var mid := _seed_model()
	var dsid := _seed_posttrain_dataset(&"d_count", &"general", 0.80, 0.05)
	CommandBus.send(&"research.posttrain_apply", {
		model_id = mid, dataset_ids = [dsid]})
	CommandBus.send(&"research.posttrain_apply", {
		model_id = mid, dataset_ids = [dsid]})
	# Note: same dataset_id added once to model.dataset_ids (dedup), but count++.
	var m := ResearchSystem.find_model(mid)
	assert_eq(m.posttrain_count, 2)

func test_posttrain_returns_capability_delta_payload() -> void:
	var mid := _seed_model()
	var dsid := _seed_posttrain_dataset(&"d_ret", &"code", 0.85, 0.05)
	var r: Dictionary = CommandBus.send(&"research.posttrain_apply", {
		model_id = mid, dataset_ids = [dsid]})
	assert_true(r.has(&"capability_delta"))
	var delta: Dictionary = r.capability_delta
	assert_gt(float(delta[&"code"]), 0.0)
	assert_lt(float(delta[&"general"]), 0.0)

func test_posttrain_legacy_singleton_dataset_id_still_works() -> void:
	# Backward compat: callers (legacy tests, saves) may send `dataset_id` not
	# `dataset_ids`. The system should accept it as a single-element list.
	var mid := _seed_model()
	var dsid := _seed_posttrain_dataset(&"legacy_ds", &"code", 0.85, 0.05)
	var r: Dictionary = CommandBus.send(&"research.posttrain_apply", {
		model_id = mid, dataset_id = dsid})
	assert_true(r.ok)
	assert_true(r.has(&"capability_delta"))

func test_posttrain_with_pretrain_dataset_falls_back_to_v1_stale() -> void:
	# Compat path: ResearchSystem treats wrong-kind dataset as if no v2 data
	# was applied — just stamps stale + count++, doesn't mutate capability.
	var mid := _seed_model(800.0, {&"code": 100.0})
	var ds := Dataset.new()
	ds.id = &"wrong_kind"
	ds.kind = &"pretrain"   # Not posttrain!
	ds.source = &"open_source"
	GameState.datasets.append(ds)
	CommandBus.send(&"research.posttrain_apply", {
		model_id = mid, dataset_id = &"wrong_kind"})
	var m := ResearchSystem.find_model(mid)
	assert_almost_eq(float(m.capability[&"code"]), 100.0, 0.001,
			"wrong-kind dataset should not mutate capability")
	assert_true(m.capability_stale, "wrong-kind should set stale (v1 fallback)")
