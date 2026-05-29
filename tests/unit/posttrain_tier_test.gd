extends GutTest

## Posttrain duration tier table — fixed weeks by model size, fixed min GPU.
## Per design/任务系统设计.md §6.6.2 (v2) + 平衡参数.md POSTTRAIN_TIER_TABLE.


var _ml_zero_id: StringName = &""

func before_each() -> void:
	GameState.reset()
	# Per design/招聘系统设计.md §5.4: posttrain_model requires ml_research_lead.
	# Seed a zero-ability one so duration math is unaffected.
	_ml_zero_id = _seed_zero_ml_research_lead()

func _seed_zero_ml_research_lead() -> StringName:
	var l := Lead.new()
	l.id = &"lead_ml_zero"
	l.specialty = &"ml_research_lead"
	l.level = &"C"
	l.ability = 0.0
	l.signing_fee = 0
	l.weekly_salary = 0
	GameState.leads.append(l)
	return l.id

func _pretrained_model(size_params_m: float, mid: StringName = &"m_pt") -> StringName:
	var r: Dictionary = CommandBus.send(&"research.add_model", {
		capability = {}, arch = &"ant_v1",
		size_params = size_params_m,
		dataset_ids = [], display_name = String(mid)})
	return r.model_id

func _add_posttrain_ds(id: StringName, size_b: float = 0.05) -> StringName:
	var ds := Dataset.new()
	ds.id = id
	ds.kind = &"posttrain"
	ds.source = &"open_source"
	ds.size = size_b
	ds.quality = 0.75
	ds.target_capability = &"general"
	GameState.datasets.append(ds)
	return id

# ---- duration by tier ---------------------------------------------------

func test_tier_s_1_week_for_small_model() -> void:
	# ≤ 10B (10_000 M) → 1 week.
	var mid := _pretrained_model(1000.0)
	var dsid := _add_posttrain_ds(&"ds_s")
	var rdc: Dictionary = CommandBus.send(&"infra.debug_instant_owned_dc", {facility_spec_id = &"facility_rack", gpu_id = &"cypress_t0"})
	var r: Dictionary = CommandBus.send(&"task.start", {
		template_id = &"posttrain_model",
		base_model_id = mid,
		datacenter_id = rdc.dc_id,
		dataset_ids = [dsid],
		lead_ids = [_ml_zero_id],
	})
	assert_true(r.ok, "start should succeed: " + str(r.get(&"error", &"")))
	assert_eq(int(r.total_weeks), 1)

func test_tier_m_2_weeks_for_50b_model() -> void:
	# Between 10B and 100B → 2 weeks.
	var mid := _pretrained_model(50_000.0)
	var dsid := _add_posttrain_ds(&"ds_m")
	var rdc: Dictionary = CommandBus.send(&"infra.debug_instant_owned_dc", {facility_spec_id = &"facility_rack", gpu_id = &"cypress_t0"})
	var r: Dictionary = CommandBus.send(&"task.start", {
		template_id = &"posttrain_model",
		base_model_id = mid,
		datacenter_id = rdc.dc_id,
		dataset_ids = [dsid],
		lead_ids = [_ml_zero_id],
	})
	assert_true(r.ok, str(r))
	assert_eq(int(r.total_weeks), 2)

func test_tier_l_4_weeks_for_300b_model() -> void:
	# Between 100B and 500B → 4 weeks.
	# Even without a real 500-gpu DC, the duration computation doesn't care
	# about gpu_count (only validation does). We bypass validation here by
	# using a template with no needs_dc enforcement OR by ensuring a big DC.
	var mid := _pretrained_model(300_000.0)
	var dsid := _add_posttrain_ds(&"ds_l")
	# posttrain_general has empty input_schema → no dc validation.
	var rdc: Dictionary = CommandBus.send(&"infra.debug_instant_owned_dc", {facility_spec_id = &"facility_rack", gpu_id = &"cypress_t0"})
	var r: Dictionary = CommandBus.send(&"task.start", {
		template_id = &"posttrain_general",
		base_model_id = mid,
		datacenter_id = rdc.dc_id,
		dataset_ids = [dsid],
	})
	assert_true(r.ok)
	assert_eq(int(r.total_weeks), 4)

func test_tier_xl_8_weeks_for_huge_model() -> void:
	# > 500B → 8 weeks.
	var mid := _pretrained_model(800_000.0)
	var dsid := _add_posttrain_ds(&"ds_xl")
	var rdc: Dictionary = CommandBus.send(&"infra.debug_instant_owned_dc", {facility_spec_id = &"facility_rack", gpu_id = &"cypress_t0"})
	var r: Dictionary = CommandBus.send(&"task.start", {
		template_id = &"posttrain_general",
		base_model_id = mid,
		datacenter_id = rdc.dc_id,
		dataset_ids = [dsid],
	})
	assert_true(r.ok)
	assert_eq(int(r.total_weeks), 8)

# ---- v12 token 量附加周 --------------------------------------------------

func test_normal_size_dataset_adds_no_extra_weeks() -> void:
	# 正常 SFT 单跑 (0.05B) → floor(0.05/1.0)=0 附加周, tier-S 仍 1 周.
	var mid := _pretrained_model(1000.0)
	var dsid := _add_posttrain_ds(&"ds_small", 0.05)
	var rdc: Dictionary = CommandBus.send(&"infra.debug_instant_owned_dc", {facility_spec_id = &"facility_rack", gpu_id = &"cypress_t0"})
	var r: Dictionary = CommandBus.send(&"task.start", {
		template_id = &"posttrain_model",
		base_model_id = mid,
		datacenter_id = rdc.dc_id,
		dataset_ids = [dsid],
		lead_ids = [_ml_zero_id],
	})
	assert_true(r.ok, str(r))
	assert_eq(int(r.total_weeks), 1)

func test_bulk_tokens_add_extra_weeks() -> void:
	# tier-S 模型 (1 周基础) + 2.5B 后训练数据 → +floor(2.5/1.0)=2 周 → 共 3 周.
	var mid := _pretrained_model(1000.0)
	var dsid := _add_posttrain_ds(&"ds_bulk", 2.5)
	var rdc: Dictionary = CommandBus.send(&"infra.debug_instant_owned_dc", {facility_spec_id = &"facility_rack", gpu_id = &"cypress_t0"})
	var r: Dictionary = CommandBus.send(&"task.start", {
		template_id = &"posttrain_model",
		base_model_id = mid,
		datacenter_id = rdc.dc_id,
		dataset_ids = [dsid],
		lead_ids = [_ml_zero_id],
	})
	assert_true(r.ok, str(r))
	assert_eq(int(r.total_weeks), 3,
			"2.5B 后训练数据应在 tier-S 1 周基础上 +2 周")

func test_token_surcharge_sums_across_datasets() -> void:
	# 多份合计 token 决定附加周: 0.7B + 0.7B = 1.4B → +floor(1.4)=1 周 → 共 2 周.
	var mid := _pretrained_model(1000.0)
	var a := _add_posttrain_ds(&"ds_a", 0.7)
	var b := _add_posttrain_ds(&"ds_b", 0.7)
	var rdc: Dictionary = CommandBus.send(&"infra.debug_instant_owned_dc", {facility_spec_id = &"facility_rack", gpu_id = &"cypress_t0"})
	var r: Dictionary = CommandBus.send(&"task.start", {
		template_id = &"posttrain_model",
		base_model_id = mid,
		datacenter_id = rdc.dc_id,
		dataset_ids = [a, b],
		lead_ids = [_ml_zero_id],
	})
	assert_true(r.ok, str(r))
	assert_eq(int(r.total_weeks), 2,
			"合计 1.4B 后训练数据应 +1 周")
