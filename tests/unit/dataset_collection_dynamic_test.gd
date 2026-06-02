extends GutTest

## DatasetCollectionDialog backend (data_collection_dynamic template +
## data_collection_law) — verify pricing, validation, and completion payload.
## Per design/数据集系统设计.md §5.1ter.


var _ds_zero_id: StringName = &""

func before_each() -> void:
	GameState.reset()
	# Generous budget so cash check never fails the test path.
	GameState.cash = 10_000_000
	# Per design/招聘系统设计.md §5.4: data_collection_dynamic now requires a
	# data_scientist lead. Seed a zero-ability one so existing tests pass the
	# gate without altering quality math (data_quality_add × 0 = 0).
	_ds_zero_id = _seed_zero_data_scientist()
	# v8: data_collection now also hard-requires a data engineer (locked for the
	# task). Seed idle data_eng staff so the start path can lock them.
	GameState.staff_pool[&"data_eng"] = 2

func _seed_zero_data_scientist() -> StringName:
	var l := Lead.new()
	l.id = &"lead_ds_zero"
	l.specialty = &"data_scientist"
	l.level = &"C"
	l.ability = 0.0
	l.signing_fee = 0
	l.weekly_salary = 0
	GameState.leads.append(l)
	return l.id

# ---- preview / pricing (pretrain) ----------------------------------------

func test_preview_pretrain_50b_size_returns_expected_cost_and_duration() -> void:
	# Per design §5.1ter (2026-05-19 ×2 提速 + 20 周 cap):
	# base_cost = 5000 + size_B × 5000;
	# duration = min(20, max(2, ceil(size_B / 200))).
	var r: Dictionary = CommandBus.send(&"task.preview", {
		template_id = &"data_collection_dynamic",
		kind = &"pretrain",
		target_size = 50.0,
	})
	assert_true(r.ok)
	assert_eq(int(r.total_cost), 5000 + 50 * 5000,
			"pretrain 50B base_cost should match design formula")
	assert_eq(int(r.weekly_cost), 3000)
	assert_eq(int(r.total_weeks), 2,
			"pretrain 50B duration = max(2, ceil(50/200)) = max(2,1) = 2 weeks")

func test_preview_pretrain_min_duration_floor_is_two_weeks() -> void:
	var r: Dictionary = CommandBus.send(&"task.preview", {
		template_id = &"data_collection_dynamic",
		kind = &"pretrain",
		target_size = 1.0,
	})
	assert_true(r.ok)
	assert_eq(int(r.total_weeks), 2,
			"pretrain duration has 2-week floor even at size 1B")

func test_preview_pretrain_2000b_size_post_speedup() -> void:
	# 2026-05-19 ×2 提速: ceil(2000/200) = 10 周 (上一版 20 周, 现在的 cap 是 20)。
	var r: Dictionary = CommandBus.send(&"task.preview", {
		template_id = &"data_collection_dynamic",
		kind = &"pretrain",
		target_size = 2000.0,
	})
	assert_true(r.ok)
	assert_eq(int(r.total_cost), 5000 + 2000 * 5000,
			"pretrain 2000B base_cost = 5k + 2000 × 5k (cost 公式不变)")
	assert_eq(int(r.total_weeks), 10,
			"pretrain 2000B duration = ceil(2000/200) = 10 周 (×2 提速后)")

func test_preview_pretrain_100t_caps_at_20_weeks() -> void:
	# 上界拉到 100T (= 100000 B tokens) 后, duration 走到 20 周硬 cap, 不再爆炸。
	# 成本仍线性 (玩家肯砸钱就能短周期拿到大数据)。
	var r: Dictionary = CommandBus.send(&"task.preview", {
		template_id = &"data_collection_dynamic",
		kind = &"pretrain",
		target_size = 100000.0,
	})
	assert_true(r.ok, "preview 应支持 size = 100T (=100000B)")
	assert_eq(int(r.total_cost), 5000 + 100000 * 5000,
			"pretrain 100T base_cost = 5k + 100000 × 5k (cost 公式不变)")
	assert_eq(int(r.total_weeks), 20,
			"pretrain 100T duration cap = 20 周 (min(20, ceil(100000/200)))")

func test_preview_pretrain_duration_cap_kicks_in_at_4000b() -> void:
	# 4000B → ceil(4000/200) = 20 → 刚刚不触发 cap (取等)。
	# 4001B → 21 → 被 cap 砍到 20。检查 cap 边界。
	var r4000: Dictionary = CommandBus.send(&"task.preview", {
		template_id = &"data_collection_dynamic",
		kind = &"pretrain", target_size = 4000.0,
	})
	var r5000: Dictionary = CommandBus.send(&"task.preview", {
		template_id = &"data_collection_dynamic",
		kind = &"pretrain", target_size = 5000.0,
	})
	assert_eq(int(r4000.total_weeks), 20, "4000B 正好 20 周")
	assert_eq(int(r5000.total_weeks), 20, "5000B 也是 20 周 (cap 卡住)")

# ---- preview / pricing (posttrain) ---------------------------------------

func test_preview_posttrain_05b_size_returns_expected_cost_and_duration() -> void:
	# Per design §5.1ter (2026-05-19 ×2 提速 + 20 周 cap):
	# base_cost = 30000 + size_B × 1_000_000;
	# duration = min(20, max(3, ceil(size_B × 0.6))).
	var r: Dictionary = CommandBus.send(&"task.preview", {
		template_id = &"data_collection_dynamic",
		kind = &"posttrain",
		target_size = 0.05,
		target_capability = &"code",
	})
	assert_true(r.ok)
	assert_eq(int(r.total_cost), 30_000 + int(round(0.05 * 1_000_000.0)))
	assert_eq(int(r.weekly_cost), 8000)
	assert_eq(int(r.total_weeks), 3,
			"posttrain duration floor 3 weeks; 0.05 × 0.6 = 0.03 → ceil → 1 → max(3,1)=3")

func test_preview_posttrain_05b_duration_scales() -> void:
	var r: Dictionary = CommandBus.send(&"task.preview", {
		template_id = &"data_collection_dynamic",
		kind = &"posttrain",
		target_size = 0.5,
		target_capability = &"reasoning",
	})
	assert_true(r.ok)
	# 0.5 × 0.6 = 0.3 → ceil → 1; max(3, 1) = 3 (×2 提速后仍受 3 周 floor 保护)。
	assert_eq(int(r.total_weeks), 3)

# ---- posttrain self-collect labor cost curve (2026-05 rev) ----------------
# Per design/数据集系统设计.md §5: posttrain cost scales with EFFECTIVE quality
# (target_quality + data_scientist lead bonus), not token volume alone. The rate
# is a CONTINUOUS piecewise curve (not discrete buckets) through anchors
# $/example: 0.65→1, 0.80→10, 0.85→50, 0.90→60, 0.95→800 (gentle exp tail above).
# examples ≈ size_B × 1e6; base_cost = 30_000 + size_B × 1e6 × rate. A higher
# selected tier — or a stronger lead — always costs strictly more (no saturation).

func _posttrain_cost(size_b: float, target_q: float, lead_ids: Array) -> int:
	var r: Dictionary = CommandBus.send(&"task.preview", {
		template_id = &"data_collection_dynamic",
		kind = &"posttrain",
		target_size = size_b,
		target_capability = &"code",
		target_quality = target_q,
		lead_ids = lead_ids,
	})
	assert_true(r.ok, "preview ok: %s" % str(r))
	return int(r.total_cost)

func _expected(size_b: float, rate: float) -> int:
	return 30_000 + int(round(size_b * 1_000_000.0 * rate))

func test_posttrain_tier_t1_default_quality_matches_legacy_formula() -> void:
	# target 0.65 → T1 rate $1 → 30k + size×1e6×1 (== legacy 30k + size×1M).
	assert_eq(_posttrain_cost(0.05, 0.65, []), _expected(0.05, 1.0),
			"T1 (q≤0.65) keeps legacy 30k + size_B × 1M")

func test_posttrain_tier_t2_professional() -> void:
	assert_eq(_posttrain_cost(0.05, 0.80, []), _expected(0.05, 10.0),
			"T2 (0.65<q≤0.80) = 30k + size_B × 10M")

func test_posttrain_tier_t3_expert() -> void:
	assert_eq(_posttrain_cost(0.05, 0.90, []), _expected(0.05, 60.0),
			"T3 (0.80<q≤0.90) = 30k + size_B × 60M")

func test_posttrain_tier_t4_phd_is_very_expensive() -> void:
	# 0.03B PhD ≈ 24,030,000 (30k + 0.03×1e6×800).
	assert_eq(_posttrain_cost(0.03, 0.95, []), _expected(0.03, 800.0),
			"T4 (q>0.90) = 30k + size_B × 800M; 0.03B ≈ 24M")

func test_posttrain_cost_is_continuous_above_t1() -> void:
	# Continuous curve (not discrete buckets): q just above the T1 anchor costs
	# strictly more than T1 but strictly less than the T2 anchor.
	var t1: int = _posttrain_cost(0.05, 0.65, [])
	var t2: int = _posttrain_cost(0.05, 0.80, [])
	var just_above: int = _posttrain_cost(0.05, 0.66, [])
	assert_gt(just_above, t1, "q=0.66 should cost strictly more than T1 (0.65)")
	assert_lt(just_above, t2, "q=0.66 should cost strictly less than T2 (0.80)")

func test_posttrain_strictly_increases_with_selected_tier_same_lead() -> void:
	# The fix for "selecting the expert tier didn't get more expensive": with the
	# SAME lead, a higher selected quality tier always costs strictly more.
	# 1) zero-ability lead (bonus 0 → effective == selected target).
	var z := [_ds_zero_id]
	var t1: int = _posttrain_cost(0.05, 0.65, z)
	var t2: int = _posttrain_cost(0.05, 0.80, z)
	var t3: int = _posttrain_cost(0.05, 0.90, z)
	var t4: int = _posttrain_cost(0.05, 0.95, z)
	assert_gt(t2, t1, "T2 domain > T1 crowd")
	assert_gt(t3, t2, "T3 senior expert > T2 domain")
	assert_gt(t4, t3, "T4 PhD > T3 senior expert")
	# 2) strong lead — the original bug: bonus pushed every tier into the top
	# bucket so T2/T3/T4 priced identically. They must still differ now.
	var sl := Lead.new()
	sl.id = &"l_ds_strong2"
	sl.specialty = &"data_scientist"
	sl.ability = 100.0
	GameState.leads.append(sl)
	var s2: int = _posttrain_cost(0.05, 0.80, [sl.id])
	var s3: int = _posttrain_cost(0.05, 0.90, [sl.id])
	var s4: int = _posttrain_cost(0.05, 0.95, [sl.id])
	assert_gt(s3, s2, "strong lead: T3 still > T2 (no saturation)")
	assert_gt(s4, s3, "strong lead: T4 still > T3 (no saturation)")

func test_posttrain_uses_effective_quality_not_selected() -> void:
	# Exploit guard kept: T1 selection (target 0.65) + strong data_scientist lead
	# (+0.22 → effective 0.87) is charged near the senior-expert rate, not crowd
	# rate. Otherwise a cheap tier + lead bonus buys high-quality data at $1/ex.
	var l := Lead.new()
	l.id = &"l_ds_strong"
	l.specialty = &"data_scientist"
	l.ability = 100.0
	GameState.leads.append(l)
	var bare: int = _posttrain_cost(0.05, 0.65, [])
	var with_lead: int = _posttrain_cost(0.05, 0.65, [l.id])
	assert_gt(with_lead, bare,
			"effective pricing: bare T1 target + strong lead (eff 0.87) costs more than bare T1")
	assert_gt(with_lead, _expected(0.05, 40.0),
			"eff 0.87 should be charged near the senior-expert rate, not crowd rate")

# ---- commercial set price vs self-collect equivalent (balance guard) ------
# Buying a posttrain set should be a convenience premium (~2–4×) over
# self-collecting the same size & quality — not wildly more (which makes the
# purchase pointless) nor less. Guards against size/price drift. Per design §6.
const _PURCHASED_TEMPLATES := [
	"res://resources/data/datasets/posttrain/purchased/reasoning_chains_v1.tres",
	"res://resources/data/datasets/posttrain/purchased/code_review_pairs_v1.tres",
	"res://resources/data/datasets/posttrain/purchased/agent_traces_v1.tres",
]

func test_commercial_set_price_is_sane_premium_over_self_collect() -> void:
	for path in _PURCHASED_TEMPLATES:
		var tmpl = load(path)
		var r: Dictionary = CommandBus.send(&"task.preview", {
			template_id = &"data_collection_dynamic", kind = &"posttrain",
			target_size = float(tmpl.size), target_quality = float(tmpl.quality),
			target_capability = tmpl.target_capability,
		})
		assert_true(r.ok, "preview ok for %s" % tmpl.id)
		var self_cost: float = float(int(r.total_cost) + int(r.weekly_cost) * int(r.total_weeks))
		var ratio: float = float(tmpl.price) / maxf(self_cost, 1.0)
		assert_between(ratio, 2.0, 4.0,
				"%s buy/self ratio = %.1fx (want 2–4x convenience premium)" % [String(tmpl.id), ratio])

# ---- start: validation ---------------------------------------------------

func test_start_posttrain_without_target_capability_errors() -> void:
	var r: Dictionary = CommandBus.send(&"task.start", {
		template_id = &"data_collection_dynamic",
		kind = &"posttrain",
		target_size = 0.05,
		# no target_capability!
		lead_ids = [_ds_zero_id], staff = {&"data_eng": 1},
	})
	assert_false(r.ok)
	assert_eq(r.error, &"target_capability_required")

func test_start_zero_size_errors() -> void:
	var r: Dictionary = CommandBus.send(&"task.start", {
		template_id = &"data_collection_dynamic",
		kind = &"pretrain",
		target_size = 0.0,
		lead_ids = [_ds_zero_id], staff = {&"data_eng": 1},
	})
	assert_false(r.ok)
	assert_eq(r.error, &"target_size_required")

func test_start_without_data_eng_staff_errors() -> void:
	# v8: data_collection hard-requires data engineers (min 2); none idle → block.
	GameState.staff_pool[&"data_eng"] = 0
	var r: Dictionary = CommandBus.send(&"task.start", {
		template_id = &"data_collection_dynamic",
		kind = &"pretrain",
		target_size = 10.0,
		lead_ids = [_ds_zero_id], staff = {},
	})
	assert_false(r.ok)
	assert_eq(r.error, &"missing_staff")

func test_data_collection_staff_count_scales_with_size() -> void:
	# Min 2, scales with dataset size, capped at 8. task_system is authoritative.
	assert_eq(TaskSystem.data_collection_staff_count(&"pretrain", 10.0), 2, "small pretrain → 2")
	assert_eq(TaskSystem.data_collection_staff_count(&"pretrain", 4_000.0), 3, "4000B pretrain → 3")
	assert_eq(TaskSystem.data_collection_staff_count(&"pretrain", 1_000_000.0), 8, "huge corpus clamps 8")
	assert_eq(TaskSystem.data_collection_staff_count(&"posttrain", 0.05), 2, "small posttrain → 2")
	assert_eq(TaskSystem.data_collection_staff_count(&"posttrain", 0.48), 8, "near-max posttrain → 8")

func test_start_locks_and_releases_scaled_data_eng() -> void:
	# Small project locks the floor of 2; cancelling releases them.
	GameState.cash = 1_000_000
	GameState.staff_pool[&"data_eng"] = 2
	var r: Dictionary = CommandBus.send(&"task.start", {
		template_id = &"data_collection_dynamic",
		kind = &"pretrain",
		target_size = 10.0,
		lead_ids = [_ds_zero_id], staff = {},
	})
	assert_true(r.ok, "start: %s" % str(r))
	assert_eq(int(GameState.staff_busy.get(&"data_eng", 0)), 2,
			"small collection should lock the minimum 2 data_eng")
	CommandBus.send(&"task.cancel", {task_id = r.task_id})
	assert_eq(int(GameState.staff_busy.get(&"data_eng", 0)), 0,
			"cancel should release the locked data_eng")

func test_start_large_collection_needs_more_data_eng() -> void:
	# A 4000B pretrain needs 3 engineers — only 2 idle → blocked; 3 idle → ok.
	GameState.cash = 100_000_000
	GameState.staff_pool[&"data_eng"] = 2
	var blocked: Dictionary = CommandBus.send(&"task.start", {
		template_id = &"data_collection_dynamic",
		kind = &"pretrain", target_size = 4_000.0,
		lead_ids = [_ds_zero_id], staff = {},
	})
	assert_false(blocked.ok)
	assert_eq(blocked.error, &"missing_staff")
	GameState.staff_pool[&"data_eng"] = 3
	var ok: Dictionary = CommandBus.send(&"task.start", {
		template_id = &"data_collection_dynamic",
		kind = &"pretrain", target_size = 4_000.0,
		lead_ids = [_ds_zero_id], staff = {},
	})
	assert_true(ok.ok, "3 idle data_eng should satisfy a 4000B collection")
	assert_eq(int(GameState.staff_busy.get(&"data_eng", 0)), 3)

# ---- start: charges base_cost dynamically + completes correctly ---------

func test_start_pretrain_charges_dynamic_base_cost() -> void:
	GameState.cash = 1_000_000
	var before: int = GameState.cash
	var r: Dictionary = CommandBus.send(&"task.start", {
		template_id = &"data_collection_dynamic",
		kind = &"pretrain",
		target_size = 20.0,
		lead_ids = [_ds_zero_id], staff = {&"data_eng": 1},
	})
	assert_true(r.ok, "pretrain start: %s" % str(r))
	# Per design: 5000 + 20*5000 = 105_000.
	assert_eq(GameState.cash, before - 105_000,
			"start should charge 5k + size_B × 5k")

func test_complete_pretrain_default_single_web_tag() -> void:
	# v9 (2026-05): self-collected pretrain no longer auto-applies a 5-tag
	# full-coverage set. When the dialog payload omits target_tags, default to
	# [web] only — player must explicitly opt into specialty tags. Per
	# design/数据集系统设计.md §5 + 任务系统设计.md §6.7.
	GameState.cash = 1_000_000
	var r: Dictionary = CommandBus.send(&"task.start", {
		template_id = &"data_collection_dynamic",
		kind = &"pretrain",
		target_size = 10.0,
		lead_ids = [_ds_zero_id], staff = {&"data_eng": 1},
	})
	assert_true(r.ok)
	for i in range(int(r.total_weeks)):
		EventBus.phase_started.emit(&"action", i + 1)
	assert_eq(GameState.datasets.size(), 1)
	var ds = GameState.datasets[0]
	assert_eq(ds.kind, &"pretrain")
	assert_eq(ds.source, &"collected")
	assert_almost_eq(float(ds.size), 10.0, 0.001)
	assert_almost_eq(float(ds.quality), 0.55, 0.001,
			"pretrain default quality is 0.55 (no lead bonus)")
	# v9: default single tag [web]; no code/reasoning/books/general auto-coverage.
	assert_eq(ds.coverage_tags.size(), 1,
			"v9: default pretrain coverage_tags should be single-tag [web]")
	assert_eq(StringName(ds.coverage_tags[0]), &"web")

func test_complete_pretrain_player_chosen_tags_passthrough() -> void:
	# v9: when the dialog passes target_tags (player specialty choice), they
	# must flow through to the new Dataset verbatim.
	GameState.cash = 1_000_000
	var r: Dictionary = CommandBus.send(&"task.start", {
		template_id = &"data_collection_dynamic",
		kind = &"pretrain",
		target_size = 10.0,
		target_tags = [&"code", &"reasoning"],
		lead_ids = [_ds_zero_id], staff = {&"data_eng": 1},
	})
	assert_true(r.ok)
	for i in range(int(r.total_weeks)):
		EventBus.phase_started.emit(&"action", i + 1)
	assert_eq(GameState.datasets.size(), 1)
	var ds = GameState.datasets[0]
	var tag_set: Dictionary = {}
	for t in ds.coverage_tags:
		tag_set[StringName(t)] = true
	assert_true(tag_set.has(&"code"))
	assert_true(tag_set.has(&"reasoning"))
	assert_false(tag_set.has(&"web"),
			"v9: when target_tags supplied, default web should NOT be appended")

func test_complete_posttrain_produces_dataset_with_target_capability() -> void:
	GameState.cash = 5_000_000
	var r: Dictionary = CommandBus.send(&"task.start", {
		template_id = &"data_collection_dynamic",
		kind = &"posttrain",
		target_size = 0.05,
		target_capability = &"code",
		lead_ids = [_ds_zero_id], staff = {&"data_eng": 1},
	})
	assert_true(r.ok)
	for i in range(int(r.total_weeks)):
		EventBus.phase_started.emit(&"action", i + 1)
	assert_eq(GameState.datasets.size(), 1)
	var ds = GameState.datasets[0]
	assert_eq(ds.kind, &"posttrain")
	assert_eq(ds.source, &"collected")
	assert_eq(ds.target_capability, &"code")
	assert_almost_eq(float(ds.quality), 0.65, 0.001,
			"posttrain default quality 0.65 (no lead bonus)")
	# Tags per design: [target_capability, instruction].
	var tag_set: Dictionary = {}
	for t in ds.coverage_tags:
		tag_set[StringName(t)] = true
	assert_true(tag_set.has(&"code"))
	assert_true(tag_set.has(&"instruction"))

# ---- weekly cost uses override (not template default 0) -------------------

func test_weekly_cost_uses_dynamic_override_during_upkeep() -> void:
	GameState.cash = 1_000_000
	var rt: Dictionary = CommandBus.send(&"task.start", {
		template_id = &"data_collection_dynamic",
		kind = &"posttrain",
		target_size = 0.05,
		target_capability = &"general",
		lead_ids = [_ds_zero_id], staff = {&"data_eng": 1},
	})
	assert_true(rt.ok)
	watch_signals(EventBus)
	EventBus.phase_started.emit(&"upkeep", 1)
	var found_weekly: bool = false
	for i in range(get_signal_emit_count(EventBus, "resources_changed")):
		var p: Array = get_signal_parameters(EventBus, "resources_changed", i)
		if p[1] == &"task_weekly":
			var d: Dictionary = p[0]
			# Posttrain weekly = 8000 per design §5.1ter.
			assert_eq(int(d.get(&"cash", 0)), -8000,
					"posttrain weekly should be 8000 (override, not template's 0)")
			found_weekly = true
			break
	assert_true(found_weekly, "task_weekly must fire with override amount")

# ---- lead bonus still applies --------------------------------------------

func test_data_scientist_lead_bonus_added_to_kind_default_quality() -> void:
	# 2026-05 rev: data_scientist.data_quality_add = 0.22.
	# Pretrain base 0.55 + 0.22 (ability=100) → 0.77.
	var l := Lead.new()
	l.id = &"l_ds_100"
	l.specialty = &"data_scientist"
	l.ability = 100.0
	GameState.leads.append(l)
	GameState.cash = 1_000_000
	var r: Dictionary = CommandBus.send(&"task.start", {
		template_id = &"data_collection_dynamic",
		kind = &"pretrain",
		target_size = 5.0,
		lead_ids = [l.id], staff = {&"data_eng": 1},
	})
	assert_true(r.ok)
	for i in range(int(r.total_weeks)):
		EventBus.phase_started.emit(&"action", i + 1)
	assert_eq(GameState.datasets.size(), 1)
	assert_almost_eq(float(GameState.datasets[0].quality), 0.77, 0.001,
			"pretrain base 0.55 + data_scientist 0.22 → 0.77")
