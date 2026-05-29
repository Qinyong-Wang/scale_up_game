extends GutTest

## 科学家"训练加分"真正接入模型能力分 (问题5)。
## Per design/任务系统设计.md §6.7 + 研究系统设计.md §4.2 + 招聘系统设计.md §5.1。
##
## - 预训练: chief_scientist.pretrain_score_bonus → model.pretrain_score_mult → evaluate raw。
## - 后训练: ml_research_lead.posttrain_score_bonus → 放大目标轴增益。
## 两者都只对真正 lead 生效, player_scientist (万能 lead) 视为无加成。

func before_each() -> void:
	GameState.reset()

# ---- _resolve_lead_score_mult (通用解析器) ------------------------------

func test_resolve_lead_score_mult_chief_scientist() -> void:
	var l := Lead.new()
	l.id = &"cs_s"
	l.specialty = &"chief_scientist"
	l.ability = 92.0
	GameState.leads.append(l)
	var mult: float = TaskSystem._resolve_lead_score_mult([l.id], &"pretrain_score_bonus")
	# chief_scientist.pretrain_score_bonus = 0.06; 1 + 0.92×0.06 = 1.0552。
	assert_almost_eq(mult, 1.0 + 0.92 * 0.06, 0.001,
			"S 级首席科学家应给出 pretrain 分数倍率")

func test_resolve_lead_score_mult_no_lead_is_neutral() -> void:
	assert_eq(TaskSystem._resolve_lead_score_mult([], &"pretrain_score_bonus"), 1.0)

func test_resolve_lead_score_mult_player_scientist_is_neutral() -> void:
	var l := Lead.new()
	l.id = &"founder"
	l.specialty = &"chief_scientist"
	l.ability = 99.0
	l.is_player_scientist = true
	GameState.leads.append(l)
	assert_eq(TaskSystem._resolve_lead_score_mult([l.id], &"pretrain_score_bonus"), 1.0,
			"万能 lead (创始人) 不提供分数加成")

# ---- pretrain_score_mult 进 evaluate 能力分 -----------------------------

func _make_model(score_mult: float) -> Model:
	# 需要一份预训练数据集, 否则 Chinchilla data_efficiency=0 → 能力分恒 0。
	# 16B ≈ 800M 的 Chinchilla 最优 (20 tokens/param), data_efficiency ≈ 1.0。
	var ds := Dataset.new()
	ds.id = StringName("ds_sm_%d" % int(round(score_mult * 1000.0)))
	ds.kind = &"pretrain"
	ds.source = &"collected"
	ds.size = 16.0
	ds.quality = 0.7
	GameState.datasets.append(ds)
	var m := Model.new()
	m.id = StringName("m_score_%d" % int(round(score_mult * 1000.0)))
	m.arch = &"ant_v1"
	m.size_params = 800.0
	m.pretrain_score_mult = score_mult
	m.dataset_ids = [ds.id] as Array[StringName]
	m.input_modalities = [&"text"] as Array[StringName]
	return m

func test_pretrain_score_mult_scales_capability() -> void:
	var base_model := _make_model(1.0)
	var boosted := _make_model(1.10)
	var v_base: float = TaskSystem._compute_capability_measured(base_model, null).get(&"general", 0.0)
	var v_boost: float = TaskSystem._compute_capability_measured(boosted, null).get(&"general", 0.0)
	assert_gt(v_boost, v_base, "pretrain_score_mult>1 必须抬高能力分 (不再是死数据)")
	assert_almost_eq(v_boost, v_base * 1.10, 0.01,
			"能力分应正好按 pretrain_score_mult 放大")

func test_default_score_mult_is_neutral() -> void:
	# 默认 1.0 → 与无加成同分 (回归: 不破坏既有 / 旧档模型)。
	var m := _make_model(1.0)
	var v: float = TaskSystem._compute_capability_measured(m, null).get(&"general", 0.0)
	assert_gt(v, 0.0)

# ---- 预览 + modifier_breakdown 端到端 -----------------------------------

func _seed_dc() -> StringName:
	var dc := Datacenter.new()
	dc.id = &"dc_score_test"
	dc.facility_spec_id = &"facility_solo"
	dc.ownership = &"owned"
	dc.train_tflops = 50_000.0
	dc.cluster_efficiency = 1.0
	dc.gpu_count = 1
	dc.status = &"idle"
	GameState.datacenters.append(dc)
	return dc.id

func _seed_pretrain_ds() -> StringName:
	var ds := Dataset.new()
	ds.id = &"ds_score_test"
	ds.kind = &"pretrain"
	ds.source = &"collected"
	ds.size = 16.0
	ds.quality = 0.7
	GameState.datasets.append(ds)
	return ds.id

func test_preview_reflects_lead_score_bonus_and_shows_modifier() -> void:
	var dc_id := _seed_dc()
	var ds_id := _seed_pretrain_ds()
	var lead := Lead.new()
	lead.id = &"cs_preview"
	lead.specialty = &"chief_scientist"
	lead.ability = 92.0
	GameState.leads.append(lead)

	var base_payload := {
		template_id = &"train_otter_m",
		datacenter_id = dc_id,
		dataset_ids = [ds_id],
		lead_ids = [],
		staff = {},
	}
	var with_lead := base_payload.duplicate()
	with_lead.lead_ids = [lead.id]

	var r0: Dictionary = CommandBus.send(&"task.preview", base_payload)
	var r1: Dictionary = CommandBus.send(&"task.preview", with_lead)
	assert_true(r0.ok and r1.ok, "preview 应成功: %s / %s" % [r0, r1])

	var g0: float = float((r0.predicted_capability as Dictionary).get(&"general", 0.0))
	var g1: float = float((r1.predicted_capability as Dictionary).get(&"general", 0.0))
	assert_gt(g1, g0, "带 S 级科学家的预估能力分应高于无 lead")

	# modifier_breakdown 必须含 score 类的 lead_score_bonus 项, 值 > 1。
	var found := false
	for e in (r1.modifier_breakdown as Array):
		if StringName(e.get(&"id", &"")) == &"lead_score_bonus":
			found = true
			assert_eq(StringName(e.get(&"category", &"speed")), &"score",
					"科学家训练加分应归入 score 区")
			assert_gt(float(e.get(&"value", 1.0)), 1.0,
					"带 S 级科学家时加分倍率应 > 1")
	assert_true(found, "pretrain modifier_breakdown 应含 lead_score_bonus 项")

# ---- 后训练科学家加分 (ml_research_lead.posttrain_score_bonus) -----------

func test_lead_score_mult_ml_research_lead_posttrain() -> void:
	var l := Lead.new()
	l.id = &"mrl_s"
	l.specialty = &"ml_research_lead"
	l.ability = 92.0
	# ml_research_lead.posttrain_score_bonus = 0.06; 1 + 0.92×0.06 = 1.0552。
	assert_almost_eq(HiringSystem.lead_score_mult(l, &"posttrain_score_bonus"),
			1.0 + 0.92 * 0.06, 0.001)

func test_lead_score_mult_null_is_neutral() -> void:
	assert_eq(HiringSystem.lead_score_mult(null, &"posttrain_score_bonus"), 1.0)

func _ds_posttrain(axis: StringName, quality: float, size_b: float) -> Dataset:
	var ds := Dataset.new()
	ds.id = StringName("ds_pt_%s" % String(axis))
	ds.kind = &"posttrain"
	ds.source = &"purchased"
	ds.size = size_b
	ds.quality = quality
	ds.target_capability = axis
	return ds

func _initial_caps() -> Dictionary:
	return {&"general": 0.0, &"code": 0.0, &"reasoning": 0.0,
			&"multimodal": 0.0, &"agent": 0.0}

func test_posttrain_score_mult_raises_target_axis_gain() -> void:
	var ds := _ds_posttrain(&"code", 0.8, 5.0)
	var base_power: float = 50.0
	var plain: Dictionary = ResearchSystem.simulate_posttrain(
			_initial_caps(), [ds], base_power, 1.0)
	var boosted: Dictionary = ResearchSystem.simulate_posttrain(
			_initial_caps(), [ds], base_power, 1.06)
	assert_gt(float(boosted.delta.code), float(plain.delta.code),
			"后训练科学家加分应放大目标轴增益 (抬高 ceiling)")

func test_posttrain_default_score_mult_matches_explicit_one() -> void:
	# 回归: 省略 score_mult 必须与显式 1.0 逐位一致 (不破坏既有预览/结算)。
	var ds := _ds_posttrain(&"reasoning", 0.7, 4.0)
	var a: Dictionary = ResearchSystem.simulate_posttrain(_initial_caps(), [ds], 40.0)
	var b: Dictionary = ResearchSystem.simulate_posttrain(_initial_caps(), [ds], 40.0, 1.0)
	assert_almost_eq(float(a.delta.reasoning), float(b.delta.reasoning), 0.0001,
			"默认 score_mult 必须等价于 1.0")
