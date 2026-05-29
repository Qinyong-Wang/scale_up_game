extends GutTest

## Tests for the agent capability axis + tool_use tech bonus + score cap removal.
## Per design/任务系统设计.md §6.7 + 平衡参数.md §evaluate产出 (revised).


func before_each() -> void:
	GameState.reset()

func _make_dataset(id: StringName, size_b: float, tags: Array, quality: float = 0.5) -> Dataset:
	var ds := Dataset.new()
	ds.id = id
	ds.kind = &"pretrain"
	# v9 (2026-05): quality=0.5 yields data_quality_factor = clamp(0.5+0.5)=1.0,
	# isolating the agent axis from data_quality_factor. (source field is no
	# longer in the formula in v9.)
	ds.source = &"collected"
	ds.size = size_b
	ds.quality = quality
	var typed: Array[StringName] = []
	for t in tags:
		typed.append(StringName(t))
	ds.coverage_tags = typed
	GameState.datasets.append(ds)
	return ds

func _make_model(size_m: float, dataset_ids: Array,
		modalities: Array = [&"text"], arch: StringName = &"ant_v1") -> Model:
	var m := Model.new()
	m.id = &"m_agent"
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

# ---- 5-axis presence ----------------------------------------------------

func test_capability_dict_has_agent_axis() -> void:
	var ds := _make_dataset(&"d_any", 16.0, [&"chat"])
	var m := _make_model(800.0, [ds.id])
	var caps: Dictionary = TaskSystem._compute_capability_measured(m, null)
	for axis in [&"general", &"code", &"reasoning", &"multimodal", &"agent"]:
		assert_true(caps.has(axis), "capability dict missing axis %s" % String(axis))

func test_npc_company_axes_constant_includes_agent() -> void:
	# AXES is the single source of truth iterated by market_system; new
	# capability dimensions must be added here too.
	assert_true((NpcCompany.AXES as Array).has(&"agent"))

# ---- agent dataset tag --------------------------------------------------

func test_agent_axis_zero_when_no_agent_dataset() -> void:
	# Model with only non-agent data should have agent score = 0.
	var ds := _make_dataset(&"d_web", 16.0, [&"web"])
	var m := _make_model(800.0, [ds.id])
	var caps: Dictionary = TaskSystem._compute_capability_measured(m, null)
	assert_eq(float(caps.get(&"agent", -1.0)), 0.0)

func test_agent_axis_scales_with_agent_tag_ratio() -> void:
	# v9 (2026-05): tag_ratio = log(1+20×share)/log(21). 50% share → ≈ 0.787.
	# 2 datasets same size+quality, 1 tagged agent → token-weighted share=0.5.
	# Model size 70B dense to clear the §6.7.2 size gate.
	# optimal tokens = 0.02 × 70,000 = 1400 B → split 700 each.
	var ds1 := _make_dataset(&"d_agent", 700.0, [&"agent"])
	var ds2 := _make_dataset(&"d_chat", 700.0, [&"chat"])
	var m := _make_model(70_000.0, [ds1.id, ds2.id])
	var caps: Dictionary = TaskSystem._compute_capability_measured(m, null)
	var general: float = float(caps.get(&"general", 0.0))
	var agent: float = float(caps.get(&"agent", 0.0))
	var expected_ratio: float = log(1.0 + 20.0 * 0.5) / log(21.0)  # ≈ 0.787
	assert_almost_eq(agent, general * expected_ratio, 0.5,
		"v9 agent axis should scale by log-curve agent-tag ratio (got general=%.2f agent=%.2f)" % [general, agent])

# ---- tool_use tech bonus -----------------------------------------------

func test_tool_use_tech_unlocked_multiplies_agent_by_1_5() -> void:
	# Use 70B dense to clear the §6.7.2 size gate.
	var ds := _make_dataset(&"d_agent_only", 1400.0, [&"agent"])
	var m := _make_model(70_000.0, [ds.id])
	var without: float = float(TaskSystem._compute_capability_measured(m, null).get(&"agent", 0.0))
	# Unlock tool_use, recompute.
	GameState.unlocks[&"application"] = GameState.unlocks.get(&"application", {})
	GameState.unlocks[&"application"][&"tool_use"] = true
	var with_unlock: float = float(TaskSystem._compute_capability_measured(m, null).get(&"agent", 0.0))
	assert_almost_eq(with_unlock / without, 1.5, 0.01,
		"tool_use unlock should bump agent axis by ×1.5 (without=%.2f with=%.2f)" % [without, with_unlock])

func test_tool_use_only_affects_agent_axis() -> void:
	# Other axes (general / code / reasoning / multimodal) must NOT change when
	# tool_use unlocks. Use 70B dense to clear the §6.7.2 size gate.
	var ds := _make_dataset(&"d_mix", 1400.0, [&"agent", &"code", &"chat"])
	var m := _make_model(70_000.0, [ds.id])
	var before: Dictionary = TaskSystem._compute_capability_measured(m, null)
	GameState.unlocks[&"application"] = GameState.unlocks.get(&"application", {})
	GameState.unlocks[&"application"][&"tool_use"] = true
	var after: Dictionary = TaskSystem._compute_capability_measured(m, null)
	for axis in [&"general", &"code", &"reasoning", &"multimodal"]:
		assert_almost_eq(float(after[axis]), float(before[axis]), 0.001,
			"tool_use should not change axis %s" % String(axis))
	assert_gt(float(after[&"agent"]), float(before[&"agent"]),
		"tool_use should raise agent axis")

# ---- score cap removal --------------------------------------------------

func test_capability_score_can_exceed_100_with_huge_model() -> void:
	# Bug B fix (2026-05): posttrain_lift mul removed; frontier scores are now
	# driven by size × arch × data alone (posttrain delta is layered on by
	# evaluate_apply via m.posttrain_delta, not via the eval formula).
	# 1e8 M = 1 T params, octopus_v2 arch, Chinchilla-optimal data → base clamps
	# to 95, arch ×1.15, data_eff ≈ 1.0 → raw ≈ 109.
	var ds2 := _make_dataset(&"d_huge2", 2_000_000.0,
			[&"chat", &"reasoning", &"code", &"agent"], 1.0)
	var m2 := _make_model(100_000_000.0, [ds2.id],
			[&"text", &"image"], &"octopus_v2")
	var caps2: Dictionary = TaskSystem._compute_capability_measured(m2, null)
	assert_gt(float(caps2.get(&"general", 0.0)), 100.0,
		"frontier-tier model should exceed 100; got %.1f" % float(caps2.get(&"general", 0.0)))

func test_npc_release_capability_is_uncapped() -> void:
	# v8 PR-H: NPC capability comes from latest NpcModelRelease, with no upper
	# clamp. Set up a release whose capability sits above 100 to prove the
	# leaderboard pipeline accepts uncapped values.
	var npc: NpcCompany = NpcCompany.new()
	npc.id = &"npc_uncap_test"
	npc.display_name = "UncapTest"
	npc.board_membership = [&"closed_source"]
	var rel := NpcModelRelease.new()
	rel.id = &"release_uncap_test_1"
	rel.display_name = "Uncap-1"
	rel.release_turn = 0
	rel.capability = {general = 130.0, code = 60.0, reasoning = 60.0,
			multimodal = 60.0, agent = 60.0}
	rel.release_kind = &"pretrain"
	npc.model_releases = [rel]
	GameState.npc_companies.append(npc)
	EventBus.phase_started.emit(&"action", GameState.turn)
	assert_almost_eq(float(npc.model_capability.get(&"general", 0.0)), 130.0, 0.001,
			"NPC capability should mirror release.capability without any clamp")

# ---- hard gates: active params ≥ 27B AND total params ≥ 70B ------------
# Per 任务系统设计.md §6.7.2.

func _agent_for(size_m: float, arch: StringName,
		extra_tags: Array = []) -> float:
	GameState.reset()
	# Provide Chinchilla-optimal data + the agent tag so the only thing being
	# tested is the size gate, not data efficiency / agent ratio.
	var tags: Array = [&"agent"]
	for t in extra_tags:
		tags.append(t)
	var ds := _make_dataset(&"d_for_gate", 0.02 * size_m, tags, 1.0)
	var m := _make_model(size_m, [ds.id], [&"text"], arch)
	return float(TaskSystem._compute_capability_measured(m, null).get(&"agent", -1.0))

func test_dense_model_under_70b_total_has_zero_agent() -> void:
	# 50 B params, dense ant_v1, agent dataset → still 0 because total < 70B.
	var got: float = _agent_for(50_000.0, &"ant_v1")
	assert_eq(got, 0.0, "dense 50B should fail the total≥70B gate")

func test_dense_model_at_or_above_70b_total_has_positive_agent() -> void:
	# 70 B dense passes both gates (active = total = 70 ≥ 27 ≥ 70 ✓).
	var got: float = _agent_for(70_000.0, &"ant_v1")
	assert_gt(got, 0.0, "dense 70B should clear both gates")

func test_dense_26b_fails_both_gates_just_in_case() -> void:
	# Even though total<70 already trips the gate, also exercises the active
	# threshold for a dense model.
	assert_eq(_agent_for(26_000.0, &"ant_v1"), 0.0)

func test_moe_octopus_v2_with_high_total_but_low_active_has_zero_agent() -> void:
	# octopus_v2: active_ratio 0.125. 200 B total → 25 B active < 27 → gate trips.
	var got: float = _agent_for(200_000.0, &"octopus_v2")
	assert_eq(got, 0.0,
		"octopus_v2 200B (active 25B) should fail active≥27B gate; got %.2f" % got)

func test_moe_octopus_v2_large_enough_to_pass_active_gate() -> void:
	# 800 B total × 0.125 = 100 B active ≥ 27 ✓, total 800 ≥ 70 ✓.
	var got: float = _agent_for(800_000.0, &"octopus_v2")
	assert_gt(got, 0.0,
		"octopus_v2 800B (active 100B) should clear both gates; got %.2f" % got)

func test_moe_octopus_v1_at_minimum_passing_size() -> void:
	# octopus_v1 ratio 0.25. 108 B total → 27 B active = threshold; total > 70 ✓.
	var got: float = _agent_for(108_000.0, &"octopus_v1")
	assert_gt(got, 0.0,
		"octopus_v1 108B (active 27B) should clear active gate")

# ---- leaderboard sub_agent ----------------------------------------------

func test_leaderboard_default_has_sub_agent() -> void:
	GameState.reset()
	assert_true(GameState.leaderboard.has(&"sub_agent"),
		"sub_agent board should be initialised in GameState.leaderboard")
