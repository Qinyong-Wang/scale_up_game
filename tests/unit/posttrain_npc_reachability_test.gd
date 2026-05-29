extends GutTest

## v12 防刷分后的「可达性」守护测试。
##
## 背景: posttrain 改成「按轴聚合 + 朝软天花板 base_power×1.4 饱和」后, 靠堆/拆
## 后训练数据集刷分的捷径没了。本测试回答: **合法玩家 (走真实 pretrain evaluate +
## 适度 posttrain) 还够得着顶级 NPC 吗?** NPC capability 是 build_npc_timelines.py
## 手写死的、锚现实进度的数组 (与玩家公式无关), 所以这里只验证玩家侧的可达上限。
##
## 参照 NPC (resources/data/npcs, 五轴之和 = 总榜评分 market_system._score_caps_for_board):
##   - sub_code 榜 AntCode-7 (turn 980): [152,200,165,130,140] 合计 787
##   - 主榜 Orca-8.5 (turn 635):        [185,178,210,172,168] 合计 913
##
## Per design/研究系统设计.md §4.2 + 平衡参数.md §Posttrain / §evaluate产出.


const AXES: Array[StringName] = [
	&"general", &"code", &"reasoning", &"multimodal", &"agent",
]

func before_each() -> void:
	GameState.reset()

func _make_pretrain_dataset(id: StringName, size_b: float, tags: Array,
		quality: float) -> Dataset:
	var ds := Dataset.new()
	ds.id = id
	ds.kind = &"pretrain"
	ds.source = &"collected"
	ds.size = size_b
	ds.quality = quality
	var typed: Array[StringName] = []
	for t in tags:
		typed.append(StringName(t))
	ds.coverage_tags = typed
	GameState.datasets.append(ds)
	return ds

func _make_model(id: StringName, size_m: float, dataset_ids: Array,
		modalities: Array, arch: StringName) -> Model:
	var m := Model.new()
	m.id = id
	m.arch = arch
	m.size_params = size_m
	var typed: Array[StringName] = []
	for d in dataset_ids:
		typed.append(StringName(d))
	m.dataset_ids = typed
	var typed_in: Array[StringName] = []
	for x in modalities:
		typed_in.append(StringName(x))
	m.input_modalities = typed_in
	m.status = &"pretrained"
	GameState.models.append(m)
	return m

func _make_posttrain_dataset(id: StringName, axis: StringName, quality: float,
		size_b: float) -> Dataset:
	var ds := Dataset.new()
	ds.id = id
	ds.kind = &"posttrain"
	ds.source = &"purchased"
	ds.size = size_b
	ds.quality = quality
	ds.target_capability = axis
	GameState.datasets.append(ds)
	return ds

func _axis_sum(caps: Dictionary) -> float:
	var s: float = 0.0
	for ax in AXES:
		s += float(caps.get(ax, 0.0))
	return s

# ---- 可达性: frontier 玩家 build 经 pretrain 就够得着顶级 NPC ----------------

func test_maxed_frontier_player_reaches_top_npc_via_pretrain() -> void:
	# 100T (1e8 M) octopus_v2, Chinchilla 最优 (2e6 B token) 满质量多标签数据 +
	# 图像模态 + tool_use 解锁。保守起见不叠 loss / lead 加成 (ce_baseline, lead=null)。
	GameState.unlocks[&"application"] = {&"tool_use": true}
	var ds := _make_pretrain_dataset(&"d_frontier", 2_000_000.0,
			[&"code", &"reasoning", &"agent", &"chat"], 1.0)
	var m := _make_model(&"m_frontier", 100_000_000.0, [ds.id],
			[&"text", &"image"], &"octopus_v2")
	var caps: Dictionary = TaskSystem._compute_capability_measured(m, null)
	var total: float = _axis_sum(caps)
	# 手算 raw = base95 × arch1.15 × data_q1.5 ≈ 164; agent 轴 ×1.5(tool_use);
	# 五轴合计 ≈ 901 → 已超过 sub_code 榜 AntCode-7 (787) 且逼近主榜 Orca-8.5 (913)。
	assert_gt(total, 787.0,
			"frontier 玩家 build 仅靠 pretrain 五轴之和应超过 AntCode-7 (787); 实测 %.0f" % total)
	# general 轴 (= raw) 应对得上顶级 NPC 的 general 量级 (AntCode-7 general 152)。
	assert_gt(float(caps[&"general"]), 150.0,
			"frontier general 轴应达 ~164 (≥ AntCode-7 的 152); 实测 %.1f" % float(caps[&"general"]))

func test_posttrain_still_adds_specialization_on_frontier_model() -> void:
	# 饱和不等于没用: 在强基座上 posttrain 仍能把弱轴显著抬高 (天花板 = base_power×1.4
	# 很高), 只是不再能无限堆。
	GameState.unlocks[&"application"] = {&"tool_use": true}
	var ds := _make_pretrain_dataset(&"d_fr2", 2_000_000.0,
			[&"code", &"reasoning", &"agent", &"chat"], 1.0)
	var m := _make_model(&"m_fr2", 100_000_000.0, [ds.id],
			[&"text", &"image"], &"octopus_v2")
	var caps: Dictionary = TaskSystem._compute_capability_measured(m, null)
	m.capability = caps.duplicate()
	m.capability_revealed = true
	var bp: float = ResearchSystem.posttrain_base_power(m)
	# base_power = 最强轴 (agent ≈ 246) → ceiling ≈ 344, multimodal (~164) 有大缺口。
	var mm_before: float = float(caps[&"multimodal"])
	var sft := _make_posttrain_dataset(&"d_mm_spec", &"multimodal", 0.92, 0.5)
	var sim: Dictionary = ResearchSystem.simulate_posttrain(caps, [sft], bp)
	var mm_gain: float = float((sim.delta as Dictionary)[&"multimodal"])
	assert_gt(mm_gain, 20.0,
			"强基座上一次高质 posttrain 应给目标轴明显增益 (>20); 实测 +%.1f" % mm_gain)
	# 但绝不超过软天花板。
	assert_lt(float((sim.capability as Dictionary)[&"multimodal"]), bp * 1.4 + 0.001,
			"目标轴不得超过软天花板 base_power×1.4")
	gut.p("frontier multimodal: %.1f → %.1f (ceiling %.1f)" % [
			mm_before, float((sim.capability as Dictionary)[&"multimodal"]), bp * 1.4])

# ---- 反面: 小模型不能再靠 posttrain 堆到 frontier (这是有意的削弱) ------------

func test_small_model_cannot_posttrain_stack_to_frontier() -> void:
	# 1B (1000 M) 模型 base_power≈size头 32 → 每轴天花板 ≈45。即便喂海量满质量 SFT,
	# 单轴也封顶在 ~45, 五轴合计远够不到 turn-matched NPC (如 AntCode-3 turn440 合计 ~286)。
	# 这正是 v12 想要的: 不能用玩具模型 SFT 出 SOTA。
	var bp: float = ResearchSystem.posttrain_base_power(
			_make_model(&"m_tiny", 1000.0, [], [&"text"], &"ant_v1"))
	# 给每一轴都喂一份巨量高质 posttrain 数据。
	var datasets: Array = []
	for ax in AXES:
		datasets.append(_make_posttrain_dataset(
				StringName("d_%s" % String(ax)), ax, 0.95, 50.0))
	var initial: Dictionary = {}
	for ax in AXES:
		initial[ax] = 0.0
	var sim: Dictionary = ResearchSystem.simulate_posttrain(initial, datasets, bp)
	var total: float = _axis_sum(sim.capability)
	# 每轴 ≤ ceiling≈45, 但 forget 会互相砍, 总和只会更低。给个宽松上限断言.
	for ax in AXES:
		assert_lt(float((sim.capability as Dictionary)[ax]), bp * 1.4 + 0.001,
				"小模型 %s 轴 posttrain 仍受 ~45 天花板限制" % String(ax))
	assert_lt(total, 286.0,
			"1B 模型纯堆 posttrain 五轴之和够不到 turn-matched NPC (~286); 实测 %.0f" % total)
