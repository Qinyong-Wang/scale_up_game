extends GutTest

## Resource 序列化往返测试. 所有进存档的 Resource 类型 (model / lead /
## datacenter / dataset / product / campaign / loan / npc_company /
## leaderboard_entry / event_instance / task_instance / datacenter_construction)
## 必须满足: instance.to_dict() | T.from_dict(d) 是无损往返.
##
## 钉住该契约可以保护 Save/Load (见 design/游戏基础架构设计.md §6 持久化),
## 因为 GameState.to_dict / from_dict 完全依赖每个资源的对称序列化.


# ---- Model -------------------------------------------------------------

func test_model_to_dict_contains_all_exported_fields() -> void:
	# 设计 design/研究系统设计.md §1: model 持有 capability / size_params / arch
	# 等多维度. 序列化必须完整, 否则 Save 会丢字段.
	var m := Model.new()
	m.id = &"sparrow_v0"
	m.display_name = "Sparrow v0"
	m.arch = &"ant_v1"
	m.capability = {&"general": 80.0, &"code": 40.0}
	m.size_params = 13_000.0
	m.flops_per_token = 26_000_000_000.0
	m.input_modalities = [&"text", &"image"]
	m.output_modalities = [&"text"]
	m.trained_at_turn = 12
	m.dataset_ids = [&"web_corpus", &"books"]
	m.status = &"published"
	m.source_release_id = &"release_wolf_3"
	m.is_open_source = false
	m.per_token_price = 0.002
	m.unpublished_at_turn = -1
	var d: Dictionary = m.to_dict()
	for k in [&"id", &"display_name", &"arch", &"capability", &"size_params",
			&"flops_per_token", &"input_modalities", &"output_modalities",
			&"trained_at_turn", &"dataset_ids", &"status", &"source_release_id", &"is_open_source",
			&"per_token_price", &"unpublished_at_turn"]:
		assert_true(d.has(k), "Model.to_dict 缺字段 %s" % k)

func test_model_roundtrip_preserves_all_fields() -> void:
	var src := Model.new()
	src.id = &"m_abc"
	src.display_name = "ABC"
	src.arch = &"ant_v1"
	src.capability = {&"general": 75.5, &"code": 22.0}
	src.size_params = 7000.0
	src.flops_per_token = 14e9
	src.input_modalities = [&"text", &"image"]
	src.output_modalities = [&"text"]
	src.trained_at_turn = 5
	src.dataset_ids = [&"d1", &"d2"]
	src.status = &"published"
	src.source_release_id = &"release_wolf_3"
	src.is_open_source = true
	src.per_token_price = 0.0
	src.unpublished_at_turn = 8
	var dst: Model = Model.from_dict(src.to_dict())
	assert_eq(dst.id, src.id)
	assert_eq(dst.display_name, src.display_name)
	assert_eq(dst.arch, src.arch)
	assert_eq(dst.capability, src.capability)
	assert_eq(dst.size_params, src.size_params)
	assert_eq(dst.flops_per_token, src.flops_per_token)
	assert_eq(dst.input_modalities, src.input_modalities)
	assert_eq(dst.output_modalities, src.output_modalities)
	assert_eq(dst.trained_at_turn, src.trained_at_turn)
	assert_eq(dst.dataset_ids, src.dataset_ids)
	assert_eq(dst.status, src.status)
	assert_eq(dst.source_release_id, src.source_release_id)
	assert_eq(dst.is_open_source, src.is_open_source)
	assert_eq(dst.per_token_price, src.per_token_price)
	assert_eq(dst.unpublished_at_turn, src.unpublished_at_turn)

func test_model_from_dict_defaults_when_keys_missing() -> void:
	# 旧存档可能没有新字段; 不应炸, 用默认值填.
	var dst: Model = Model.from_dict({})
	assert_eq(dst.id, &"")
	assert_eq(dst.status, &"pretrained")
	assert_eq(dst.provenance, &"trained")
	assert_eq(dst.source_release_id, &"")
	assert_eq(dst.per_token_price, 0.0)
	assert_eq(dst.unpublished_at_turn, -1)
	assert_false(dst.is_open_source)
	assert_false(dst.capability_revealed)
	assert_false(dst.capability_stale)
	# v7 PR-F: demand_multiplier field deleted from Model resource.

func test_model_from_dict_legacy_internal_status_maps_to_pretrained() -> void:
	# Backward compat: 旧 2-state 存档用的 &"internal" 应被解释成 &"pretrained".
	var dst: Model = Model.from_dict({"status": "internal"})
	assert_eq(dst.status, &"pretrained")

func test_model_from_dict_repairs_missing_flops_per_token_from_size() -> void:
	# 旧自定义 pretrain 存档会有 size_params 但 flops_per_token=0; load 时
	# 必须迁移, 否则部署容量会按 max(fpt, 1) 变成离谱 tok/s.
	var dst: Model = Model.from_dict({
		"id": "M2",
		"display_name": "M2",
		"size_params": 7000.0,
		"flops_per_token": 0.0,
	})
	assert_almost_eq(dst.flops_per_token, 14_000_000_000.0, 1.0)

func test_model_from_dict_repairs_legacy_short_flops_per_token_from_size() -> void:
	# 早期开源/固定模板把 7B 写成 14000 这类 MFLOPs 缩写; 存档读取时
	# 统一回真实 FLOPs/token.
	var dst: Model = Model.from_dict({
		"id": "wolf",
		"size_params": 7000.0,
		"flops_per_token": 14000.0,
	})
	assert_almost_eq(dst.flops_per_token, 14_000_000_000.0, 1.0)

func test_model_string_name_arrays_return_typed() -> void:
	# input_modalities 在 from_dict 后必须是 Array[StringName] (类型化数组).
	var src := Model.new()
	src.input_modalities = [&"text"]
	var dst: Model = Model.from_dict(src.to_dict())
	# 把 text 加进 typed array 不应抛 (如果不是 typed 也能加进, 这里改用 typeof 钉)
	assert_eq(typeof(dst.input_modalities), TYPE_ARRAY)
	assert_eq(dst.input_modalities[0], StringName("text"))

# ---- Lead --------------------------------------------------------------

func test_lead_roundtrip_preserves_all_fields() -> void:
	var src := Lead.new()
	src.id = &"lead_01"
	src.display_name = "Alice"
	src.specialty = &"chief_scientist"
	src.level = &"S"
	src.ability = 92.5
	src.signing_fee = 200_000
	src.weekly_salary = 50_000
	src.locked_by_task_id = &"task_5"
	src.assigned_to_product_id = &""
	src.avatar_id = &"avatar-04"
	var dst: Lead = Lead.from_dict(src.to_dict())
	assert_eq(dst.id, src.id)
	assert_eq(dst.display_name, src.display_name)
	assert_eq(dst.specialty, src.specialty)
	assert_eq(dst.level, src.level)
	assert_eq(dst.ability, src.ability)
	assert_eq(dst.signing_fee, src.signing_fee)
	assert_eq(dst.weekly_salary, src.weekly_salary)
	assert_eq(dst.locked_by_task_id, src.locked_by_task_id)
	assert_eq(dst.assigned_to_product_id, src.assigned_to_product_id)
	assert_eq(dst.avatar_id, src.avatar_id)

func test_lead_avatar_id_defaults_empty_for_legacy_save() -> void:
	# 旧档 Lead 无 avatar_id → 回退空 (走按 id 哈希的肖像池)。
	var src := Lead.new()
	src.id = &"lead_legacy"
	var d: Dictionary = src.to_dict()
	d.erase("avatar_id")
	assert_eq(Lead.from_dict(d).avatar_id, &"")

func test_lead_is_idle_after_roundtrip_preserves_lock_state() -> void:
	# §招聘 §1 三态互斥: locked_by_task_id 非空时 is_idle() 必须 false.
	var src := Lead.new()
	src.id = &"l1"
	src.specialty = &"chief_engineer"
	src.level = &"A"
	src.locked_by_task_id = &"t1"
	var dst: Lead = Lead.from_dict(src.to_dict())
	assert_false(dst.is_idle())

	src.locked_by_task_id = &""
	src.assigned_to_product_id = &"p1"
	dst = Lead.from_dict(src.to_dict())
	assert_false(dst.is_idle())

	src.assigned_to_product_id = &""
	dst = Lead.from_dict(src.to_dict())
	assert_true(dst.is_idle())

# ---- Datacenter --------------------------------------------------------

func test_datacenter_roundtrip_preserves_state_machine_and_links() -> void:
	# §基础设施 §1: status ∈ {idle, training, serving}; 链接 deployed_model_id /
	# busy_with_task_id.
	var src := Datacenter.new()
	src.id = &"dc_0001"
	src.display_name = "Solo DC [dc_0001]"
	src.facility_spec_id = &"facility_solo"
	src.ownership = &"rented"
	src.train_tflops = 50_000.0
	src.inference_tflops = 30_000.0
	src.facility_weekly_cost = 500
	src.status = &"serving"
	src.deployed_model_id = &"m1"
	src.busy_with_task_id = &""
	var dst: Datacenter = Datacenter.from_dict(src.to_dict())
	assert_eq(dst.id, src.id)
	assert_eq(dst.facility_spec_id, src.facility_spec_id)
	assert_eq(dst.ownership, src.ownership)
	assert_eq(dst.train_tflops, src.train_tflops)
	assert_eq(dst.inference_tflops, src.inference_tflops)
	assert_eq(dst.facility_weekly_cost, src.facility_weekly_cost)
	assert_eq(dst.status, src.status)
	assert_eq(dst.deployed_model_id, src.deployed_model_id)
	assert_eq(dst.busy_with_task_id, src.busy_with_task_id)

func test_datacenter_default_status_is_idle() -> void:
	var dst: Datacenter = Datacenter.from_dict({})
	assert_eq(dst.status, &"idle")
	assert_eq(dst.ownership, &"rented")

func test_datacenter_construction_roundtrip() -> void:
	var src := DatacenterConstruction.new()
	src.id = &"dc_owned_0001"
	src.facility_spec_id = &"facility_room"
	src.weeks_remaining = 5
	src.total_weeks = 16
	var dst: DatacenterConstruction = DatacenterConstruction.from_dict(src.to_dict())
	assert_eq(dst.id, src.id)
	assert_eq(dst.facility_spec_id, src.facility_spec_id)
	assert_eq(dst.weeks_remaining, src.weeks_remaining)
	assert_eq(dst.total_weeks, src.total_weeks)

# ---- Dataset -----------------------------------------------------------

func test_dataset_roundtrip_preserves_all_fields() -> void:
	# §数据集 §1: 三渠道 source ∈ {open_source, purchased, collected};
	# coverage_tags 是 Array[StringName].
	var src := Dataset.new()
	src.id = &"ds_web"
	src.display_name = "Web Corpus"
	src.source = &"open_source"
	src.size = 4.5
	src.quality = 75.0
	src.coverage_tags = [&"web", &"english", &"chinese"]
	src.locked_by_task_id = &"task_7"
	var dst: Dataset = Dataset.from_dict(src.to_dict())
	assert_eq(dst.id, src.id)
	assert_eq(dst.source, src.source)
	assert_eq(dst.size, src.size)
	assert_eq(dst.quality, src.quality)
	assert_eq(dst.coverage_tags, src.coverage_tags)
	assert_eq(dst.locked_by_task_id, src.locked_by_task_id)

func test_dataset_empty_tags_array_survives() -> void:
	var src := Dataset.new()
	src.id = &"d1"
	src.source = &"purchased"
	src.coverage_tags = []
	var dst: Dataset = Dataset.from_dict(src.to_dict())
	assert_eq(dst.coverage_tags.size(), 0)
	assert_eq(typeof(dst.coverage_tags), TYPE_ARRAY)

# ---- Product -----------------------------------------------------------

func test_product_roundtrip_preserves_all_fields_and_assigned_staff() -> void:
	# §产品 §1: assigned_staff 是 {role: int} 字典, 必须保留 role 的 StringName 含义.
	var src := Product.new()
	src.id = &"prod_chat"
	src.display_name = "ChatBot Pro"
	src.type = &"chatbot"
	src.bound_model_id = &"m1"
	src.subscription_price = 99
	src.lead_id = &"lead_ce_01"
	src.assigned_staff = {&"ml_eng": 2, &"ops": 1}
	src.subscribers = 1234
	src.launched_at_turn = 4
	src.quality = 0.78
	var dst: Product = Product.from_dict(src.to_dict())
	assert_eq(dst.id, src.id)
	assert_eq(dst.type, src.type)
	assert_eq(dst.bound_model_id, src.bound_model_id)
	assert_eq(dst.subscription_price, src.subscription_price)
	assert_eq(dst.lead_id, src.lead_id)
	assert_eq(dst.assigned_staff, src.assigned_staff)
	assert_eq(dst.subscribers, src.subscribers)
	assert_eq(dst.launched_at_turn, src.launched_at_turn)
	assert_eq(dst.quality, src.quality)

func test_product_assigned_staff_keys_become_string_name_after_roundtrip() -> void:
	# to_dict 用 String 键, from_dict 转回 StringName.
	var src := Product.new()
	src.id = &"p1"
	src.assigned_staff = {&"ml_eng": 3}
	var d: Dictionary = src.to_dict()
	# JSON 中是 String 键
	assert_true(d.assigned_staff.has("ml_eng"))
	var dst: Product = Product.from_dict(d)
	# 还原成 StringName 键
	assert_true(dst.assigned_staff.has(&"ml_eng"))
	assert_eq(int(dst.assigned_staff[&"ml_eng"]), 3)

func test_product_default_type_chatbot() -> void:
	var dst: Product = Product.from_dict({})
	assert_eq(dst.type, &"chatbot")

# ---- Campaign ----------------------------------------------------------

func test_campaign_roundtrip_preserves_all_fields() -> void:
	# §营销 §1: 持续 N 周, 周度扣预算.
	var src := Campaign.new()
	src.id = &"camp_q1"
	src.display_name = "Q1 push"
	src.weekly_budget = 50_000
	src.remaining_weeks = 2
	src.total_weeks = 3
	src.target_segment = &"chatbot_users"
	src.lead_id = &"lead_marketing_01"
	src.fake_score_level = &"high"
	src.started_at_turn = 4
	var dst: Campaign = Campaign.from_dict(src.to_dict())
	assert_eq(dst.id, src.id)
	assert_eq(dst.weekly_budget, src.weekly_budget)
	assert_eq(dst.remaining_weeks, src.remaining_weeks)
	assert_eq(dst.total_weeks, src.total_weeks)
	assert_eq(dst.target_segment, src.target_segment)
	assert_eq(dst.lead_id, src.lead_id)
	assert_eq(dst.fake_score_level, src.fake_score_level)
	assert_eq(dst.started_at_turn, src.started_at_turn)

func test_campaign_default_target_segment_is_all() -> void:
	var dst: Campaign = Campaign.from_dict({})
	assert_eq(dst.target_segment, &"all")

func test_campaign_default_fake_score_level_is_none() -> void:
	var dst: Campaign = Campaign.from_dict({})
	assert_eq(dst.fake_score_level, &"none")

# ---- Loan --------------------------------------------------------------

func test_loan_roundtrip_preserves_all_fields() -> void:
	# §经济 §1: principal_initial / principal_remaining / interest / weeks.
	var src := Loan.new()
	src.id = &"loan_01"
	src.principal_initial = 500_000
	src.principal_remaining = 350_000
	src.weekly_interest_rate = 0.015
	src.weeks_remaining = 18
	src.taken_at_turn = 6
	var dst: Loan = Loan.from_dict(src.to_dict())
	assert_eq(dst.id, src.id)
	assert_eq(dst.principal_initial, src.principal_initial)
	assert_eq(dst.principal_remaining, src.principal_remaining)
	assert_eq(dst.weekly_interest_rate, src.weekly_interest_rate)
	assert_eq(dst.weeks_remaining, src.weeks_remaining)
	assert_eq(dst.taken_at_turn, src.taken_at_turn)

# ---- NpcCompany --------------------------------------------------------

func test_npc_company_roundtrip_preserves_all_fields() -> void:
	# §竞争对手 §1 v8: NPC = identity + board_membership + model_releases timeline.
	var src := NpcCompany.new()
	src.id = &"acme"
	src.display_name = "ACME AI"
	src.is_open_source = true
	src.board_membership = [&"closed_source", &"sub_code"]
	var r := NpcModelRelease.new()
	r.id = &"release_acme_1"
	r.display_name = "ACME-1"
	r.release_turn = 100
	r.capability = {general = 40.0, code = 60.0, reasoning = 30.0,
			multimodal = 0.0, agent = 0.0}
	r.release_kind = &"pretrain"
	r.cluster_gpu_id = &"cypress_t1"
	r.cluster_gpu_count = 2000
	r.training_weeks = 22
	r.params_b = 70.0
	r.active_params_b = 70.0
	r.dataset_tokens_b = 800.0
	r.arch_codename = &"ant_v2"
	src.model_releases = [r]
	src.current_release_id = &"release_acme_1"
	src.model_capability = {general = 40.0, code = 60.0, reasoning = 30.0,
			multimodal = 0.0, agent = 0.0}
	var dst: NpcCompany = NpcCompany.from_dict(src.to_dict())
	assert_eq(dst.id, src.id)
	assert_eq(dst.display_name, src.display_name)
	assert_eq(dst.is_open_source, src.is_open_source)
	assert_eq(dst.board_membership.size(), 2)
	assert_true(&"closed_source" in dst.board_membership)
	assert_true(&"sub_code" in dst.board_membership)
	assert_eq(dst.model_releases.size(), 1)
	assert_eq(dst.model_releases[0].id, &"release_acme_1")
	assert_eq(dst.model_releases[0].release_turn, 100)
	assert_almost_eq(float(dst.model_releases[0].capability["code"]), 60.0, 0.001)
	assert_eq(dst.current_release_id, &"release_acme_1")
	assert_almost_eq(float(dst.model_capability["general"]), 40.0, 0.001)

func test_npc_from_dict_accepts_scalar_capability_cache() -> void:
	# 向前兼容: 老存档 model_capability 是单 float 时, 应自动 broadcast 到 5 axes.
	var dst: NpcCompany = NpcCompany.from_dict({
		"id": "legacy", "model_capability": 60.0,
	})
	for axis in NpcCompany.AXES:
		assert_almost_eq(float(dst.model_capability[String(axis)]), 60.0, 0.001)

func test_npc_model_release_roundtrip() -> void:
	# §1 v8: NpcModelRelease 携带集群 / 训练 / 架构信息, 也参与 to/from dict.
	var src := NpcModelRelease.new()
	src.id = &"release_orca_4"
	src.display_name = "Orca-4"
	src.release_turn = 300
	src.capability = {general = 78.0, code = 65.0, reasoning = 70.0,
			multimodal = 30.0, agent = 15.0}
	src.release_kind = &"pretrain"
	src.cluster_gpu_id = &"cypress_t2"
	src.cluster_gpu_count = 16000
	src.training_weeks = 25
	src.params_b = 1500.0
	src.active_params_b = 220.0
	src.dataset_tokens_b = 13000.0
	src.arch_codename = &"octopus_v2"
	var dst: NpcModelRelease = NpcModelRelease.from_dict(src.to_dict())
	assert_eq(dst.id, &"release_orca_4")
	assert_eq(dst.display_name, "Orca-4")
	assert_eq(dst.release_turn, 300)
	assert_almost_eq(float(dst.capability["reasoning"]), 70.0, 0.001)
	assert_eq(dst.cluster_gpu_id, &"cypress_t2")
	assert_eq(dst.cluster_gpu_count, 16000)
	assert_eq(dst.training_weeks, 25)
	assert_almost_eq(float(dst.params_b), 1500.0, 0.001)
	assert_almost_eq(float(dst.active_params_b), 220.0, 0.001)
	assert_almost_eq(float(dst.dataset_tokens_b), 13000.0, 0.001)
	assert_eq(dst.arch_codename, &"octopus_v2")
	assert_eq(dst.release_kind, &"pretrain")

# ---- LeaderboardEntry --------------------------------------------------

func test_leaderboard_entry_roundtrip() -> void:
	# §竞争对手 §1 v8: entity_type ∈ {player_model, npc}; company_name 仅 NPC 填.
	var src := LeaderboardEntry.new()
	src.entity_id = &"m1"
	src.entity_type = &"player_model"
	src.display_name = "Sparrow-Player"
	src.company_name = ""
	src.capability_score = 88.4
	src.rank = 2
	var dst: LeaderboardEntry = LeaderboardEntry.from_dict(src.to_dict())
	assert_eq(dst.entity_id, src.entity_id)
	assert_eq(dst.entity_type, src.entity_type)
	assert_eq(dst.display_name, src.display_name)
	assert_eq(dst.company_name, "")
	assert_eq(dst.capability_score, src.capability_score)
	assert_eq(dst.rank, src.rank)

func test_leaderboard_entry_npc_carries_company_name() -> void:
	var src := LeaderboardEntry.new()
	src.entity_id = &"release_orca_5"
	src.entity_type = &"npc"
	src.display_name = "Orca-5"
	src.company_name = "OrcaLab"
	src.capability_score = 540.0
	src.rank = 1
	var dst: LeaderboardEntry = LeaderboardEntry.from_dict(src.to_dict())
	assert_eq(dst.company_name, "OrcaLab")
	assert_eq(dst.display_name, "Orca-5")

# ---- EventInstance -----------------------------------------------------

func test_event_instance_pending_roundtrip() -> void:
	# §事件 §1: pending = chosen_option_id 为空; resolved = 非空 + resolved_at_turn ≥ 0.
	var src := EventInstance.new()
	src.id = &"evt_5"
	src.template_id = &"debug_test_offer"
	src.triggered_at_turn = 7
	src.resolved_at_turn = -1
	src.chosen_option_id = &""
	var dst: EventInstance = EventInstance.from_dict(src.to_dict())
	assert_eq(dst.id, src.id)
	assert_eq(dst.template_id, src.template_id)
	assert_eq(dst.triggered_at_turn, src.triggered_at_turn)
	assert_eq(dst.resolved_at_turn, -1)
	assert_eq(dst.chosen_option_id, &"")

func test_event_instance_resolved_roundtrip() -> void:
	var src := EventInstance.new()
	src.id = &"evt_5"
	src.template_id = &"debug_test_offer"
	src.triggered_at_turn = 7
	src.resolved_at_turn = 7
	src.chosen_option_id = &"accept"
	var dst: EventInstance = EventInstance.from_dict(src.to_dict())
	assert_eq(dst.resolved_at_turn, 7)
	assert_eq(dst.chosen_option_id, &"accept")

# ---- TaskInstance ------------------------------------------------------

func test_task_instance_simple_roundtrip() -> void:
	# §任务 §1: 通用四子类型, 持有 locks + completion_command/payload.
	var src := TaskInstance.new()
	src.id = &"task_10"
	src.template_id = &"pretrain"
	src.subtype = &"pretrain"
	src.started_at_turn = 3
	src.total_weeks = 4
	src.elapsed_weeks = 1
	src.locked_lead_ids = [&"lead_cs"]
	src.locked_staff = {&"ml_eng": 4}
	src.locked_datacenter_id = &"dc_0001"
	src.locked_dataset_ids = [&"web", &"books"]
	src.completion_command = &"research.add_model"
	src.completion_payload = {
		&"capability": {&"general": 50.0},
		&"arch": &"ant_v1",
		&"dataset_ids": [&"web", &"books"],
	}
	var dst: TaskInstance = TaskInstance.from_dict(src.to_dict())
	assert_eq(dst.id, src.id)
	assert_eq(dst.template_id, src.template_id)
	assert_eq(dst.subtype, src.subtype)
	assert_eq(dst.started_at_turn, src.started_at_turn)
	assert_eq(dst.total_weeks, src.total_weeks)
	assert_eq(dst.elapsed_weeks, src.elapsed_weeks)
	assert_eq(dst.locked_lead_ids, src.locked_lead_ids)
	assert_eq(dst.locked_staff[&"ml_eng"], src.locked_staff[&"ml_eng"])
	assert_eq(dst.locked_datacenter_id, src.locked_datacenter_id)
	assert_eq(dst.locked_dataset_ids, src.locked_dataset_ids)
	assert_eq(dst.completion_command, src.completion_command)

func test_task_instance_completion_payload_string_keys_after_roundtrip() -> void:
	# completion_payload 在 to_dict 时所有 key/StringName 值都被字符串化;
	# from_dict 不再回 typify (TaskSystem 消费时统一 cast).
	var src := TaskInstance.new()
	src.completion_command = &"research.add_model"
	src.completion_payload = {
		&"arch": &"ant_v1",
		&"capability": {&"general": 50.0},
	}
	var d: Dictionary = src.to_dict()
	var p: Dictionary = d.completion_payload
	assert_true(p.has("arch"), "key 应字符串化")
	assert_eq(p["arch"], "ant_v1", "StringName 值应字符串化")
	assert_true((p["capability"] as Dictionary).has("general"))

func test_task_instance_default_total_weeks_is_one() -> void:
	# default_value 在 from_dict 缺键时应给出, 防止 0 周任务无限循环.
	var dst: TaskInstance = TaskInstance.from_dict({})
	assert_eq(dst.total_weeks, 1)
	assert_eq(dst.elapsed_weeks, 0)

func test_task_instance_locked_arrays_are_typed() -> void:
	var src := TaskInstance.new()
	src.id = &"t1"
	src.locked_lead_ids = [&"l1", &"l2"]
	src.locked_dataset_ids = [&"d1"]
	var dst: TaskInstance = TaskInstance.from_dict(src.to_dict())
	# 类型化数组在 from_dict 中重建 (Array[StringName])
	assert_eq(typeof(dst.locked_lead_ids), TYPE_ARRAY)
	assert_eq(dst.locked_lead_ids[0], StringName("l1"))
	assert_eq(dst.locked_dataset_ids[0], StringName("d1"))

# ---- 跨类型: GameState 完整往返 ------------------------------------------

func test_gamestate_roundtrip_with_one_of_every_resource() -> void:
	# 把每种 Resource 各放一份到 GameState, 走 to_dict/from_dict, 验证回来仍是
	# 同样的对象 (按 id / 关键字段比对). 保护 Save/Load 端到端.
	GameState.reset()

	var lead := Lead.new()
	lead.id = &"lead_01"; lead.specialty = &"chief_scientist"; lead.level = &"S"
	GameState.leads.append(lead)

	var dc := Datacenter.new()
	dc.id = &"dc_01"; dc.facility_spec_id = &"facility_solo"; dc.status = &"idle"
	GameState.datacenters.append(dc)

	var ds := Dataset.new()
	ds.id = &"d1"; ds.source = &"open_source"
	GameState.datasets.append(ds)

	var m := Model.new()
	m.id = &"m1"; m.arch = &"ant_v1"; m.status = &"published"
	GameState.models.append(m)

	var prod := Product.new()
	prod.id = &"p1"; prod.type = &"chatbot"; prod.subscription_price = 99
	GameState.products.append(prod)

	var camp := Campaign.new()
	camp.id = &"c1"; camp.weekly_budget = 1000; camp.total_weeks = 3; camp.remaining_weeks = 3
	GameState.campaigns.append(camp)

	var loan := Loan.new()
	loan.id = &"loan1"; loan.principal_initial = 100_000; loan.principal_remaining = 100_000
	GameState.loans.append(loan)

	# MarketSystem 已在 reset() 时往 npc_companies 注入 4 家默认 NPC, 这里
	# 清空再加自己一家, 才能保证 from_dict 结果首位是 acme.
	GameState.npc_companies.clear()
	var npc := NpcCompany.new()
	npc.id = &"acme"
	GameState.npc_companies.append(npc)

	var lb := LeaderboardEntry.new()
	lb.entity_id = &"m1"; lb.entity_type = &"player_model"; lb.rank = 1
	GameState.leaderboard[&"closed_source"] = [lb]

	var evt := EventInstance.new()
	evt.id = &"e1"; evt.template_id = &"debug_test_offer"
	GameState.pending_events.append(evt)

	var ti := TaskInstance.new()
	ti.id = &"t1"; ti.subtype = &"pretrain"; ti.total_weeks = 2
	GameState.active_tasks.append(ti)

	var c := DatacenterConstruction.new()
	c.id = &"dc_owned_01"; c.facility_spec_id = &"facility_room"; c.total_weeks = 16
	GameState.construction_queue.append(c)

	var snapshot: Dictionary = GameState.to_dict()
	GameState.reset()
	GameState.from_dict(snapshot)

	assert_eq(GameState.leads.size(), 1)
	assert_eq(GameState.leads[0].id, &"lead_01")
	assert_eq(GameState.datacenters[0].id, &"dc_01")
	assert_eq(GameState.datasets[0].id, &"d1")
	assert_eq(GameState.models[0].id, &"m1")
	assert_eq(GameState.products[0].id, &"p1")
	assert_eq(GameState.campaigns[0].id, &"c1")
	assert_eq(GameState.loans[0].id, &"loan1")
	assert_eq(GameState.npc_companies[0].id, &"acme")
	assert_eq(GameState.leaderboard[&"closed_source"][0].entity_id, &"m1")
	assert_eq(GameState.pending_events[0].id, &"e1")
	assert_eq(GameState.active_tasks[0].id, &"t1")
	assert_eq(GameState.construction_queue[0].id, &"dc_owned_01")
