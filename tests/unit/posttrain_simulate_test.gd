extends GutTest

## ResearchSystem.simulate_posttrain — 纯函数版的 posttrain 结算, 同时给
## research.posttrain_apply 和 PosttrainDialog 预览共用, 保证 preview 与 apply
## 输出逐位一致.
##
## v12 (2026-05) 防刷分重写: 按 target_capability 聚合 (token 加权质量) → log 只对
## 聚合总量取一次 (杀拆碎); 目标轴朝软天花板 base_power×CEILING_MULT 饱和 (杀无限堆);
## 其余轴按 (1-q̄) forget 且 clamp ≥0.
##
## Per design/研究系统设计.md §4.2 (apply 公式) + §5.3 (预览契约 v2.1)
##     + 平衡参数.md §Posttrain 能力增减.


const AXES: Array[StringName] = [
	&"general", &"code", &"reasoning", &"multimodal", &"agent",
]
# 与 research_system.gd 同步; 测试里用来手算期望值.
const CEILING_MULT: float = 1.4
const SAT_SCALE: float = 35.0

func before_each() -> void:
	GameState.reset()

func _ds(id: StringName, axis: StringName, quality: float, size_b: float) -> Dataset:
	var ds := Dataset.new()
	ds.id = id
	ds.kind = &"posttrain"
	ds.source = &"purchased"
	ds.size = size_b
	ds.quality = quality
	ds.target_capability = axis
	return ds

func _initial(g: float = 0.0, c: float = 0.0, r: float = 0.0,
		m: float = 0.0, a: float = 0.0) -> Dictionary:
	return {
		&"general": g, &"code": c, &"reasoning": r,
		&"multimodal": m, &"agent": a,
	}

# 手算一份单轴聚合后目标轴的 realized 增益, 用于期望值核对.
func _expected_realized(base_power: float, c0: float, qbar: float, total_tokens_b: float) -> float:
	var ceiling: float = base_power * CEILING_MULT
	if ceiling <= c0:
		return 0.0
	var size_factor: float = log(1.0 + total_tokens_b * 1000.0) / log(2.0)
	var raw_gain: float = 8.0 * qbar * qbar * size_factor
	return (ceiling - c0) * (1.0 - exp(-raw_gain / SAT_SCALE))

# ---- API 契约 -----------------------------------------------------------

func test_simulate_returns_capability_and_delta_keys() -> void:
	var res: Dictionary = ResearchSystem.simulate_posttrain(_initial(), [], 100.0)
	assert_true(res.has(&"capability"))
	assert_true(res.has(&"delta"))
	for ax in AXES:
		assert_true((res.capability as Dictionary).has(ax),
				"capability should contain axis %s" % String(ax))
		assert_true((res.delta as Dictionary).has(ax),
				"delta should contain axis %s" % String(ax))

func test_empty_dataset_list_is_noop() -> void:
	var initial := _initial(50.0, 30.0, 30.0, 0.0, 0.0)
	var res: Dictionary = ResearchSystem.simulate_posttrain(initial, [], 100.0)
	for ax in AXES:
		assert_almost_eq(float((res.capability as Dictionary)[ax]),
				float(initial[ax]), 0.001)
		assert_almost_eq(float((res.delta as Dictionary)[ax]), 0.0, 0.001)

# ---- 防拆碎: 聚合不变性 (v12 核心) --------------------------------------

func test_fragmentation_is_neutralized() -> void:
	# 同样 1.0B token、同 quality, 拆成 1 份 vs 10 份必须给出完全相同的结果.
	# (旧版凹 log + 逐份相加会让 10 份收益远高于 1 份 → 这正是要堵的漏洞.)
	var one := [_ds(&"big", &"code", 0.80, 1.0)]
	var ten: Array = []
	for i in range(10):
		ten.append(_ds(StringName("small_%d" % i), &"code", 0.80, 0.1))
	var r_one: Dictionary = ResearchSystem.simulate_posttrain(_initial(), one, 100.0)
	var r_ten: Dictionary = ResearchSystem.simulate_posttrain(_initial(), ten, 100.0)
	assert_almost_eq(float((r_one.delta as Dictionary)[&"code"]),
			float((r_ten.delta as Dictionary)[&"code"]), 0.01,
			"拆成 10 份与 1 份聚合后 token/质量相同, code 增益必须一致")
	# 而且具体值 = 单轴聚合公式 (base_power=100, c0=0, q̄=0.8, T=1.0) ≈ 107.4.
	assert_almost_eq(float((r_one.delta as Dictionary)[&"code"]),
			_expected_realized(100.0, 0.0, 0.80, 1.0), 0.5)

func test_token_weighted_quality_drags_qbar_down() -> void:
	# 一小份高质 (q0.9,0.1B) + 一大份低质 (q0.3,0.9B) → q̄ = 0.36, 不是 0.6 算术平均.
	# 掺低质大份既塌 gain 又重 forget. 用 general 有余量看 forget.
	var a := _ds(&"hi", &"code", 0.90, 0.1)
	var b := _ds(&"lo", &"code", 0.30, 0.9)
	var res: Dictionary = ResearchSystem.simulate_posttrain(
			_initial(100.0, 0.0, 0.0, 0.0, 0.0), [a, b], 100.0)
	# q̄ = (0.9*0.1 + 0.3*0.9)/1.0 = 0.36; realized 远低于纯高质.
	var qbar := (0.9 * 0.1 + 0.3 * 0.9) / 1.0
	assert_almost_eq(float((res.delta as Dictionary)[&"code"]),
			_expected_realized(100.0, 0.0, qbar, 1.0), 0.5)
	# forget = 8 * (1 - 0.36) = 5.12, general 100 → 94.88.
	assert_almost_eq(float((res.delta as Dictionary)[&"general"]), -5.12, 0.05)

# ---- 防无限堆: 软天花板 + 饱和 (v12 核心) -------------------------------

func test_target_axis_never_exceeds_ceiling() -> void:
	# 一份巨量高质数据 (q0.95, 50B) 也不能把轴顶过 base_power×1.4 = 140.
	var ds := _ds(&"huge", &"code", 0.95, 50.0)
	var res: Dictionary = ResearchSystem.simulate_posttrain(_initial(), [ds], 100.0)
	var code: float = float((res.capability as Dictionary)[&"code"])
	assert_lt(code, 140.0001, "code 不得超过软天花板 140")
	assert_gt(code, 130.0, "巨量高质数据应逼近(但不超过)天花板")

func test_stacking_more_tokens_has_diminishing_returns() -> void:
	# 同 quality, token 量 ×10, 增益远小于 ×10 (饱和), 应 < ×2.
	var small := [_ds(&"s", &"code", 0.80, 0.1)]
	var big := [_ds(&"b", &"code", 0.80, 1.0)]
	var d_small: float = float(
			(ResearchSystem.simulate_posttrain(_initial(), small, 100.0).delta as Dictionary)[&"code"])
	var d_big: float = float(
			(ResearchSystem.simulate_posttrain(_initial(), big, 100.0).delta as Dictionary)[&"code"])
	assert_gt(d_big, d_small, "更多 token 仍应更多增益")
	assert_lt(d_big, d_small * 2.0,
			"10× token 增益必须远小于 10×(明显边际递减), 实测应 < 2×")

func test_ceiling_scales_with_base_power() -> void:
	# 弱基座 (base_power=30) 天花板 42, 强基座 (base_power=120) 天花板 168.
	# 同一份数据, 强基座能专精得更高.
	var ds := _ds(&"d", &"code", 0.90, 0.2)
	var weak: float = float(
			(ResearchSystem.simulate_posttrain(_initial(), [ds], 30.0).capability as Dictionary)[&"code"])
	var strong: float = float(
			(ResearchSystem.simulate_posttrain(_initial(), [ds], 120.0).capability as Dictionary)[&"code"])
	assert_lt(weak, 42.0001, "弱基座 code 不得超 30×1.4=42")
	assert_gt(strong, weak, "强基座天花板更高, 同数据应专精得更高")

func test_zero_base_power_yields_no_gain() -> void:
	# base_power=0 → ceiling 0 → 目标轴拿不到增益 (防御: 调用方没给 base_power 时不刷分).
	var ds := _ds(&"d", &"code", 0.90, 0.2)
	var res: Dictionary = ResearchSystem.simulate_posttrain(_initial(), [ds], 0.0)
	assert_almost_eq(float((res.delta as Dictionary)[&"code"]), 0.0, 0.001)

# ---- forget clamp-to-zero (保留: forget 公式未变) -----------------------

func test_forget_clamps_to_zero_on_zero_axis() -> void:
	# 五轴全 0 的模型 + 一份 code 数据: code 拿饱和增益, 其余四轴 clamp 在 0, delta 0.
	var ds := _ds(&"code_ds", &"code", 0.85, 0.05)
	var res: Dictionary = ResearchSystem.simulate_posttrain(_initial(), [ds], 100.0)
	assert_almost_eq(float((res.delta as Dictionary)[&"code"]),
			_expected_realized(100.0, 0.0, 0.85, 0.05), 0.5)
	for ax in [&"general", &"reasoning", &"multimodal", &"agent"]:
		assert_almost_eq(float((res.capability as Dictionary)[ax]), 0.0, 0.001,
				"axis %s should stay clamped at 0" % String(ax))
		assert_almost_eq(float((res.delta as Dictionary)[ax]), 0.0, 0.001,
				"delta on already-zero axis %s should be 0 (clamped)" % String(ax))

func test_forget_clamps_partially_when_axis_below_forget() -> void:
	# multimodal=0.5, forget=8*(1-0.85)=1.2 → after = max(0, 0.5-1.2)=0, delta=-0.5.
	var ds := _ds(&"code_q85", &"code", 0.85, 0.05)
	var initial := _initial(50.0, 30.0, 30.0, 0.5, 0.0)
	var res: Dictionary = ResearchSystem.simulate_posttrain(initial, [ds], 100.0)
	assert_almost_eq(float((res.capability as Dictionary)[&"multimodal"]), 0.0, 0.001)
	assert_almost_eq(float((res.delta as Dictionary)[&"multimodal"]), -0.5, 0.001,
			"multimodal delta should be -0.5 (clamp truncates) not -1.2")
	assert_almost_eq(float((res.delta as Dictionary)[&"agent"]), 0.0, 0.001)

func test_two_same_axis_datasets_forget_once_aggregated() -> void:
	# 两份都打 code (聚合成一个轴组) → forget 只施加一次, 不是两次.
	# multimodal=2.0, q̄=0.70 → forget=8*0.3=2.4: 2.0 → max(0,2.0-2.4)=0, delta=-2.0.
	var a := _ds(&"code_a", &"code", 0.70, 0.05)
	var b := _ds(&"code_b", &"code", 0.70, 0.05)
	var initial := _initial(0.0, 0.0, 0.0, 2.0, 0.0)
	var res: Dictionary = ResearchSystem.simulate_posttrain(initial, [a, b], 100.0)
	assert_almost_eq(float((res.delta as Dictionary)[&"multimodal"]), -2.0, 0.001,
			"聚合后 forget 只施加一次, multimodal 只被吃掉原本的 2.0")
	assert_almost_eq(float((res.capability as Dictionary)[&"multimodal"]), 0.0, 0.001)

func test_forget_linear_in_quality() -> void:
	# forget = 8 × (1 - q̄). q̄=0.6 → 3.2. 用满头部轴看 forget (general 有余量).
	var ds := _ds(&"low_q", &"code", 0.60, 0.05)
	var initial := _initial(100.0, 100.0, 100.0, 100.0, 100.0)
	var res: Dictionary = ResearchSystem.simulate_posttrain(initial, [ds], 100.0)
	assert_almost_eq(float((res.delta as Dictionary)[&"general"]), -3.2, 0.05)

# ---- preview vs apply 等价 (v2.1 硬性 guard) ----------------------------

func test_simulate_matches_research_posttrain_apply() -> void:
	# 同 initial + 同数据集 + 同 base_power, simulate 与 apply 必须逐位一致.
	var ds_code := _ds(&"code_apply", &"code", 0.85, 0.05)
	var ds_reason := _ds(&"reason_apply", &"reasoning", 0.75, 0.04)
	GameState.datasets.append(ds_code)
	GameState.datasets.append(ds_reason)

	var initial := _initial(50.0, 30.0, 30.0, 0.0, 0.0)
	var r: Dictionary = CommandBus.send(&"research.add_model", {
		capability = {}, arch = &"ant_v1",
		size_params = 800.0,
		dataset_ids = [], display_name = "M_match"})
	var m = ResearchSystem.find_model(r.model_id)
	m.capability = initial.duplicate()
	m.capability_revealed = true
	m.status = &"evaluated"
	# 取 apply 前的 base_power, 与 apply 内部 posttrain_base_power(m) 一致.
	var base_power: float = ResearchSystem.posttrain_base_power(m)

	var apply_r: Dictionary = CommandBus.send(&"research.posttrain_apply", {
		model_id = r.model_id, dataset_ids = [ds_code.id, ds_reason.id],
	})
	var apply_caps: Dictionary = m.capability.duplicate()
	var apply_delta: Dictionary = apply_r.capability_delta

	var sim: Dictionary = ResearchSystem.simulate_posttrain(initial,
			[ds_code, ds_reason], base_power)
	var sim_caps: Dictionary = sim.capability
	var sim_delta: Dictionary = sim.delta

	for ax in AXES:
		assert_almost_eq(float(sim_caps[ax]), float(apply_caps[ax]), 0.001,
				"simulate.capability[%s] must equal apply outcome" % String(ax))
		assert_almost_eq(float(sim_delta[ax]), float(apply_delta[ax]), 0.001,
				"simulate.delta[%s] must equal apply outcome" % String(ax))

# ---- bad dataset filtering ----------------------------------------------

func test_skips_wrong_kind_dataset() -> void:
	var bad := _ds(&"bad", &"code", 0.85, 0.05)
	bad.kind = &"pretrain"
	var initial := _initial(50.0, 30.0, 30.0, 0.0, 0.0)
	var res: Dictionary = ResearchSystem.simulate_posttrain(initial, [bad], 100.0)
	for ax in AXES:
		assert_almost_eq(float((res.capability as Dictionary)[ax]),
				float(initial[ax]), 0.001,
				"wrong-kind dataset should be skipped, axis %s unchanged" % String(ax))
		assert_almost_eq(float((res.delta as Dictionary)[ax]), 0.0, 0.001)

func test_skips_dataset_with_empty_target_capability() -> void:
	var bad := _ds(&"no_target", &"", 0.85, 0.05)
	bad.target_capability = &""
	var initial := _initial(50.0, 30.0, 30.0, 0.0, 0.0)
	var res: Dictionary = ResearchSystem.simulate_posttrain(initial, [bad], 100.0)
	for ax in AXES:
		assert_almost_eq(float((res.delta as Dictionary)[ax]), 0.0, 0.001)

# ---- posttrain_base_power 助手 ------------------------------------------

func test_base_power_uses_size_head_when_unevaluated() -> void:
	# 未评估模型 (capability 全 0) → base_power = size 头 clamp(20+12*log10(size/100),10,95).
	var r: Dictionary = CommandBus.send(&"research.add_model", {
		capability = {}, arch = &"ant_v1", size_params = 800.0,
		dataset_ids = [], display_name = "M_size"})
	var m = ResearchSystem.find_model(r.model_id)
	# 800M: 20 + 12*log10(8) = 20 + 12*0.9031 ≈ 30.84.
	assert_almost_eq(ResearchSystem.posttrain_base_power(m), 30.84, 0.2)

func test_base_power_excludes_posttrain_delta_to_prevent_ratchet() -> void:
	# pretrained general=50, 已有 posttrain_delta code=+40 → pretrained 最强轴仍是 50,
	# base_power 不被 posttrain 自身贡献抬高 (防 ratchet).
	var r: Dictionary = CommandBus.send(&"research.add_model", {
		capability = {}, arch = &"ant_v1", size_params = 800.0,
		dataset_ids = [], display_name = "M_ratchet"})
	var m = ResearchSystem.find_model(r.model_id)
	m.capability = {&"general": 50.0, &"code": 70.0, &"reasoning": 0.0,
			&"multimodal": 0.0, &"agent": 0.0}
	m.posttrain_delta = {&"general": 0.0, &"code": 40.0, &"reasoning": 0.0,
			&"multimodal": 0.0, &"agent": 0.0}
	# pretrained: general 50, code 70-40=30 → max 50 (> size 头 30.84).
	assert_almost_eq(ResearchSystem.posttrain_base_power(m), 50.0, 0.2)
