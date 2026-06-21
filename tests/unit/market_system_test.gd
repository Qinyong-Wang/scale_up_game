extends GutTest

## MarketSystem v8 PR-H (2026-05) — timeline-driven competitors.
## 8 boards (total + closed/open + 5 subs), 23 NPCs (5 main + 18 sub),
## NPC capability = latest NpcModelRelease.capability.
## Per design/竞争对手系统设计.md + design/NPC配置.md.

# Boards an NPC may explicitly join via board_membership (the `total` board
# is computed from main-board membership, not declared on NPCs directly).
const ALL_BOARDS: Array[StringName] = [
	&"closed_source", &"open_source",
	&"sub_general", &"sub_code", &"sub_reasoning", &"sub_multimodal", &"sub_agent",
]
const ALL_BOARDS_INCLUDING_TOTAL: Array[StringName] = [
	&"total",
	&"closed_source", &"open_source",
	&"sub_general", &"sub_code", &"sub_reasoning", &"sub_multimodal", &"sub_agent",
]
const NPC_TOTAL_CAP: float = 1100.0

func before_each() -> void:
	GameState.reset()

# ---- helpers -----------------------------------------------------------

func _add_published_model(open: bool = false, cap: Dictionary = {}) -> StringName:
	var caps: Dictionary = cap
	if caps.is_empty():
		caps = {&"general": 80.0, &"code": 50.0,
				&"reasoning": 0.0, &"multimodal": 0.0}
	var r: Dictionary = CommandBus.send(&"research.add_model", {
		capability = caps, arch = &"ant_v1", dataset_ids = []})
	CommandBus.send(&"research.evaluate_apply", {
		model_id = r.model_id, capability_measured = caps})
	CommandBus.send(&"research.publish_model", {
		model_id = r.model_id, is_open_source = open, per_token_price = 0.001})
	return r.model_id

func _add_dominant_player_model(open: bool = false) -> StringName:
	return _add_published_model(open, {
		&"general": 1000.0, &"code": 1000.0,
		&"reasoning": 1000.0, &"multimodal": 1000.0, &"agent": 1000.0,
	})

func _make_release(rid: StringName, label: String, turn: int, caps: Dictionary) -> NpcModelRelease:
	var r := NpcModelRelease.new()
	r.id = rid
	r.display_name = label
	r.release_turn = turn
	r.capability = caps
	r.release_kind = &"pretrain"
	return r

func _cap_total(caps: Dictionary) -> float:
	var total: float = 0.0
	for axis in NpcCompany.AXES:
		total += float(caps.get(String(axis), 0.0))
	return total

func _assert_source_board_contains_exact_npc_releases(board_id: StringName, expected: Dictionary) -> void:
	var actual := {}
	for entry in GameState.leaderboard[board_id]:
		if entry.entity_type == &"npc":
			actual[entry.entity_id] = entry.company_name
	assert_eq(actual.size(), expected.size(),
			"%s 应收录所有已首发的对应阵营 NPC release" % board_id)
	for release_id in expected.keys():
		assert_true(actual.has(release_id),
				"%s 缺少 %s (%s)" % [board_id, release_id, expected[release_id]])

func _expected_launched_npcs_by_source(open: bool) -> Dictionary:
	var expected := {}
	for npc in GameState.npc_companies:
		if npc.current_release_id == &"":
			continue
		if bool(npc.is_open_source) == open:
			expected[npc.current_release_id] = npc.display_name
	return expected

# ---- §2 commands -------------------------------------------------------

func test_preview_rank_unknown_model_returns_negative_one() -> void:
	var r: Dictionary = CommandBus.send(&"market.preview_rank", {model_id = &"nope"})
	assert_true(r.ok)
	assert_eq(int(r.predicted_rank), -1)
	assert_eq(StringName(r.board), &"")

func test_preview_rank_known_model_returns_rank_and_board() -> void:
	# publish 立即重排, preview_rank 应能查到. `total` 在 BOARD_IDS 首位.
	var mid: StringName = _add_published_model(false)
	var r: Dictionary = CommandBus.send(&"market.preview_rank", {model_id = mid})
	assert_true(r.ok)
	assert_gt(int(r.predicted_rank), 0)
	assert_true(StringName(r.board) in ALL_BOARDS_INCLUDING_TOTAL)

func test_get_rank_returns_zero_for_unpublished() -> void:
	var r: Dictionary = CommandBus.send(&"market.get_rank",
			{model_id = &"nope", board_id = &"total"})
	assert_true(r.ok)
	assert_eq(int(r.rank), 0)

func test_get_rank_unknown_board_returns_error() -> void:
	var r: Dictionary = CommandBus.send(&"market.get_rank",
			{model_id = &"x", board_id = &"unknown_board"})
	assert_false(r.ok)

# ---- v10: get_rank_vs_npcs (UserSystem product-growth ranking) ----------

func test_get_rank_vs_npcs_excludes_players_own_models() -> void:
	# Two player models (one stronger) + two NPC rivals. On the global `total`
	# board the weak player model is dragged down by the company's own stronger
	# model; the vs-NPC rank counts only the rivals.
	var weak: StringName = _add_published_model(false, {&"general": 80.0})
	var _strong: StringName = _add_published_model(false, {&"general": 95.0})
	for spec in [{id = &"npc_lo", g = 50.0}, {id = &"npc_hi", g = 90.0}]:
		var npc := NpcCompany.new()
		npc.id = spec.id
		npc.display_name = String(spec.id)
		npc.board_membership = [&"closed_source"]
		npc.model_releases = [_make_release(StringName("rel_%s" % String(spec.id)),
				String(spec.id), 0, {general = spec.g, code = 0.0,
				reasoning = 0.0, multimodal = 0.0, agent = 0.0})]
		GameState.npc_companies.append(npc)
	EventBus.phase_started.emit(&"action", GameState.turn)
	# Global total: strong95 > npc_hi90 > weak80 > npc_lo50 → weak is #3.
	assert_eq(MarketSystem.get_rank_for_model(weak, &"total"), 3,
			"global leaderboard ranks the company's own models against each other")
	# vs NPC: only npc_hi(90) beats weak(80) — the company's own strong model
	# and npc_lo are not counted → weak is #2.
	assert_eq(MarketSystem.get_rank_vs_npcs(weak, &"total"), 2,
			"vs-NPC rank ignores the player's own other published models")

func test_get_rank_vs_npcs_zero_when_not_on_board() -> void:
	assert_eq(MarketSystem.get_rank_vs_npcs(&"no_such_model", &"total"), 0)

func test_get_rank_vs_npcs_supports_hidden_downloaded_os_model() -> void:
	GameState.turn = 520
	EventBus.phase_started.emit(&"action", 520)
	var r: Dictionary = CommandBus.send(&"research.ensure_open_source_release_published",
			{release_id = &"release_wolf_5"})
	assert_true(r.ok)
	assert_gt(MarketSystem.get_rank_vs_npcs(r.model_id, &"total"), 0,
			"downloaded_os 隐藏于公开榜, 但产品增长仍要能拿到总榜相对 NPC 名次")
	assert_gt(MarketSystem.get_rank_vs_npcs(r.model_id, &"open_source"), 0,
			"downloaded_os 隐藏于公开榜, 但产品增长仍要能拿到开源榜相对 NPC 名次")

# ---- §1 default NPCs ---------------------------------------------------

func test_default_npcs_seeded_23() -> void:
	# §NPC配置 §1: 5 main + 18 sub-board specialists = 23.
	assert_eq(GameState.npc_companies.size(), 23)

func test_default_npcs_have_unique_ids() -> void:
	var ids := {}
	for npc in GameState.npc_companies:
		assert_false(ids.has(npc.id), "NPC id 不应重复: %s" % npc.id)
		ids[npc.id] = true

func test_state_reset_reinstalls_default_npcs() -> void:
	GameState.npc_companies.clear()
	GameState.reset()
	assert_eq(GameState.npc_companies.size(), 23)

func test_default_npcs_include_at_least_10_open_source_competitors() -> void:
	var open_count: int = 0
	for npc in GameState.npc_companies:
		if bool(npc.is_open_source):
			open_count += 1
	assert_gte(open_count, 10)

func test_new_open_source_competitors_are_seeded() -> void:
	var expected := {
		&"npc_lynx_devnet": &"sub_code",
		&"npc_heron_vision": &"sub_multimodal",
		&"npc_otter_tools": &"sub_agent",
	}
	var found := {}
	for npc in GameState.npc_companies:
		if expected.has(npc.id):
			assert_true(bool(npc.is_open_source), "%s 应为开源 NPC" % npc.id)
			assert_true(expected[npc.id] in npc.board_membership,
					"%s 应进入 %s 榜" % [npc.id, expected[npc.id]])
			found[npc.id] = true
	for npc_id in expected.keys():
		assert_true(found.has(npc_id), "默认 NPC 应包含 %s" % npc_id)

func test_npc_paths_table_matches_disk() -> void:
	# Exported PCK builds cannot reliably enumerate res:// directories. NPC
	# timeline loading must use an explicit path table, otherwise builds fall
	# back to seed-only competitors and the leaderboard stops evolving.
	var on_disk: Array = _collect_npc_tres_paths()
	var listed: Array = MarketSystem.NPC_TRES_PATHS.values()
	on_disk.sort()
	listed.sort()
	for path in on_disk:
		assert_true(listed.has(path),
				"NPC on disk not listed in MarketSystem table: %s" % path)
	for path in listed:
		assert_true(on_disk.has(path),
				"NPC listed in MarketSystem table but missing on disk: %s" % path)

func test_every_listed_npc_path_loads_as_company() -> void:
	for npc_id in MarketSystem.NPC_TRES_PATHS:
		var res := load(MarketSystem.NPC_TRES_PATHS[npc_id])
		assert_true(res is NpcCompany,
				"NPC_TRES_PATHS[%s] must load as NpcCompany" % npc_id)
		assert_eq(StringName(res.id), npc_id,
				"NPC id field must match table key for %s" % npc_id)

func _collect_npc_tres_paths() -> Array:
	var out: Array = []
	var dir := DirAccess.open(MarketSystem.NPC_TRES_DIR)
	assert_not_null(dir, "NPC root must exist in editor")
	if dir == null:
		return out
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".tres"):
			out.append(MarketSystem.NPC_TRES_DIR + fname)
		fname = dir.get_next()
	dir.list_dir_end()
	return out

func test_npc_capability_is_5d_dict() -> void:
	var npc: NpcCompany = GameState.npc_companies[0]
	assert_true(npc.model_capability is Dictionary)
	for axis in NpcCompany.AXES:
		assert_true(npc.model_capability.has(String(axis)),
				"NPC 应有 axis %s" % axis)

func test_npc_release_totals_are_capped_to_player_reachable_band() -> void:
	var max_total: float = 0.0
	var max_label: String = ""
	for npc in GameState.npc_companies:
		for release in npc.model_releases:
			var total: float = _cap_total(release.capability)
			if total > max_total:
				max_total = total
				max_label = "%s / %s" % [String(npc.id), String(release.id)]
			assert_lte(total, NPC_TOTAL_CAP + 0.001,
					"NPC release 总分不得超过 %.0f: %s %.1f" %
					[NPC_TOTAL_CAP, String(release.id), total])
	assert_gt(max_total, 1000.0,
			"测试前提: 后期 NPC 仍应接近 1000-1100 竞争带; max %s %.1f" %
			[max_label, max_total])

func test_default_npcs_cover_every_sub_board() -> void:
	var coverage := {}
	for board in ALL_BOARDS:
		coverage[board] = 0
	for npc in GameState.npc_companies:
		for b in npc.board_membership:
			coverage[b] = int(coverage.get(b, 0)) + 1
	for board in ALL_BOARDS:
		assert_gt(int(coverage[board]), 0, "board %s 应至少有 1 家 NPC" % board)

# ---- §5.1 timeline advance ---------------------------------------------

func test_npc_release_capability_lifts_to_current_release() -> void:
	# NPC has a timeline; current_release.capability is mirrored to model_capability.
	var npc: NpcCompany = NpcCompany.new()
	npc.id = &"npc_test_timeline"
	npc.display_name = "TimelineTest"
	npc.board_membership = [&"closed_source"]
	var r1 := _make_release(&"rel_t_1", "T-1", 0,
			{general = 5.0, code = 1.0, reasoning = 1.0, multimodal = 0.0, agent = 0.0})
	var r2 := _make_release(&"rel_t_2", "T-2", 10,
			{general = 50.0, code = 20.0, reasoning = 30.0, multimodal = 0.0, agent = 0.0})
	npc.model_releases = [r1, r2]
	GameState.npc_companies.append(npc)
	# At turn 0 only r1 is eligible.
	EventBus.phase_started.emit(&"action", 0)
	assert_eq(npc.current_release_id, &"rel_t_1")
	assert_almost_eq(float(npc.model_capability["general"]), 5.0, 0.001)
	# Advance to turn 10; r2 should now be current.
	GameState.turn = 10
	EventBus.phase_started.emit(&"action", 10)
	assert_eq(npc.current_release_id, &"rel_t_2")
	assert_almost_eq(float(npc.model_capability["general"]), 50.0, 0.001)

func test_npc_without_eligible_release_is_pre_launch() -> void:
	# Pre-launch (no release.release_turn <= current turn) → NPC absent from boards.
	var npc: NpcCompany = NpcCompany.new()
	npc.id = &"npc_late"
	npc.display_name = "Late"
	npc.board_membership = [&"closed_source"]
	npc.model_releases = [_make_release(&"rel_l_1", "L-1", 100,
			{general = 80.0, code = 0.0, reasoning = 0.0, multimodal = 0.0, agent = 0.0})]
	GameState.npc_companies.append(npc)
	GameState.turn = 5
	EventBus.phase_started.emit(&"action", 5)
	assert_eq(npc.current_release_id, &"")
	for entry in GameState.leaderboard[&"closed_source"]:
		assert_ne(entry.entity_id, &"rel_l_1",
				"pre-launch NPC 不应在排行榜上")

func test_npc_release_capability_holds_between_releases() -> void:
	# No step-jump drift: between r1 and r2, capability stays flat at r1's value.
	var npc: NpcCompany = NpcCompany.new()
	npc.id = &"npc_flat"
	npc.display_name = "Flat"
	npc.board_membership = [&"closed_source"]
	npc.model_releases = [
		_make_release(&"rel_f_1", "F-1", 0,
				{general = 10.0, code = 5.0, reasoning = 5.0, multimodal = 0.0, agent = 0.0}),
		_make_release(&"rel_f_2", "F-2", 50,
				{general = 80.0, code = 60.0, reasoning = 60.0, multimodal = 0.0, agent = 0.0}),
	]
	GameState.npc_companies.append(npc)
	for t in range(1, 50):
		GameState.turn = t
		EventBus.phase_started.emit(&"action", t)
	# Still on r1.
	assert_eq(npc.current_release_id, &"rel_f_1")
	assert_almost_eq(float(npc.model_capability["general"]), 10.0, 0.001)

## v9 PR-I: find_release reverse-lookup used by ResearchSystem / InfraSystem.
func test_find_release_known_id_returns_npc_and_release() -> void:
	var r: Dictionary = MarketSystem.find_release(&"release_wolf_1")
	assert_true(r.get(&"ok", false), "wolf_1 should be findable: %s" % str(r))
	assert_eq(StringName(r.npc.id), &"npc_wolf_research")
	assert_eq(StringName(r.release.id), &"release_wolf_1")
	assert_eq(StringName(r.release.release_kind), &"pretrain")

func test_find_release_unknown_id_returns_not_ok() -> void:
	var r: Dictionary = MarketSystem.find_release(&"definitely_not_here")
	assert_false(r.get(&"ok", false))

func test_list_downloadable_releases_empty_at_turn_zero() -> void:
	var lst: Array = MarketSystem.list_downloadable_releases(0)
	assert_eq(lst.size(), 0, "no OS pretrain releases by turn 0")

func test_list_downloadable_releases_includes_wolf_1_after_release() -> void:
	# Wolf-1 lands at turn 215; list at turn 220 should include it.
	var lst: Array = MarketSystem.list_downloadable_releases(220)
	var ids: Array[StringName] = []
	for entry in lst:
		ids.append(StringName(entry.release.id))
	assert_true(ids.has(&"release_wolf_1"),
			"release_wolf_1 should be downloadable by turn 220; got %s" % str(ids))

func test_list_downloadable_releases_includes_added_open_source_npcs() -> void:
	var lst: Array = MarketSystem.list_downloadable_releases(520)
	var ids: Array[StringName] = []
	for entry in lst:
		ids.append(StringName(entry.release.id))
	for release_id in [&"release_lynx_1", &"release_heron_1", &"release_otter_1"]:
		assert_true(ids.has(release_id),
				"%s should be downloadable by turn 520; got %s" % [release_id, str(ids)])

func test_list_downloadable_releases_excludes_closed_source() -> void:
	# At turn 500 OrcaLab has released Orca-4 etc. (closed), should not appear.
	var lst: Array = MarketSystem.list_downloadable_releases(500)
	for entry in lst:
		assert_true(bool(entry.npc.is_open_source),
				"list_downloadable_releases must only return OS NPC releases; got %s from %s"
				% [String(entry.release.id), String(entry.npc.id)])

func test_list_downloadable_releases_excludes_non_pretrain() -> void:
	var lst: Array = MarketSystem.list_downloadable_releases(500)
	for entry in lst:
		assert_eq(StringName(entry.release.release_kind), &"pretrain",
				"only pretrain releases are downloadable; got %s (kind=%s)"
				% [String(entry.release.id), String(entry.release.release_kind)])

func test_npc_released_signal_fires_on_transition() -> void:
	watch_signals(EventBus)
	var npc: NpcCompany = NpcCompany.new()
	npc.id = &"npc_sig"
	npc.display_name = "Sig"
	npc.board_membership = [&"closed_source"]
	npc.model_releases = [
		_make_release(&"rel_s_1", "S-1", 0,
				{general = 5.0, code = 0.0, reasoning = 0.0, multimodal = 0.0, agent = 0.0}),
		_make_release(&"rel_s_2", "S-2", 7,
				{general = 50.0, code = 0.0, reasoning = 0.0, multimodal = 0.0, agent = 0.0}),
	]
	GameState.npc_companies.append(npc)
	GameState.turn = 7
	EventBus.phase_started.emit(&"action", 7)
	assert_signal_emitted(EventBus, "npc_released")

# ---- §5.1 / §5.2 leaderboard rebuild -----------------------------------

func test_eight_boards_initialized() -> void:
	for board in ALL_BOARDS_INCLUDING_TOTAL:
		assert_true(GameState.leaderboard.has(board),
				"leaderboard 缺 %s" % board)
		assert_true(GameState.leaderboard[board] is Array)

func test_boards_populated_after_resolve() -> void:
	# v8 PR-H: NPC release timelines start as early as turn 70 (OrcaLab) but
	# some sub-board specialists don't launch until turn 200+ (Sparrow Chat
	# at 230) or 380+ (agent specialists). Advance to turn 500 so every
	# board has at least one launched NPC.
	GameState.turn = 500
	EventBus.phase_started.emit(&"action", 500)
	for board in ALL_BOARDS_INCLUDING_TOTAL:
		var entries: Array = GameState.leaderboard[board]
		assert_gt(entries.size(), 0, "board %s 不应为空" % board)

func test_source_display_boards_include_all_launched_npcs_by_source() -> void:
	# Source boards are ecosystem display boards. They should follow
	# npc.is_open_source, while total-board eligibility remains controlled by
	# board_membership source tags.
	GameState.turn = 520
	EventBus.phase_started.emit(&"action", 520)
	var expected_open := _expected_launched_npcs_by_source(true)
	var expected_closed := _expected_launched_npcs_by_source(false)
	assert_gt(expected_open.size(), 1, "测试前提: turn 520 应有多家开源 NPC 已首发")
	assert_gt(expected_closed.size(), 4, "测试前提: turn 520 应有多家闭源 NPC 已首发")
	_assert_source_board_contains_exact_npc_releases(&"open_source", expected_open)
	_assert_source_board_contains_exact_npc_releases(&"closed_source", expected_closed)

func test_save_loaded_reinstalls_npc_roster_and_rebuilds_source_boards() -> void:
	# Regression for legacy saves like "ttt": saved leaderboard snapshots used
	# the old source-board filter, and saved npc_companies could be missing NPCs
	# added later. save_loaded must rebuild from resources at the saved turn.
	GameState.turn = 520
	GameState.npc_companies = []
	GameState.leaderboard[&"open_source"] = []
	var stale := LeaderboardEntry.new()
	stale.entity_id = &"release_wolf_5"
	stale.entity_type = &"npc"
	stale.display_name = "Wolf-5"
	stale.company_name = "Wolf Research"
	stale.capability_score = 466.0
	stale.rank = 1
	GameState.leaderboard[&"open_source"] = [stale]
	EventBus.save_loaded.emit()
	assert_eq(GameState.npc_companies.size(), 23,
			"读档后 NPC roster 应以 resources/data/npcs/*.tres 为权威")
	assert_true(MarketSystem.find_release(&"release_lynx_1").ok,
			"读档后应补回旧档缺失的新增开源 NPC release")
	var expected_open := _expected_launched_npcs_by_source(true)
	assert_gte(expected_open.size(), 10, "turn 520 应已有 10 家开源 NPC 首发")
	_assert_source_board_contains_exact_npc_releases(&"open_source", expected_open)

func test_downloaded_os_model_does_not_duplicate_source_release_on_public_boards() -> void:
	GameState.turn = 520
	EventBus.phase_started.emit(&"action", 520)
	var r: Dictionary = CommandBus.send(&"research.ensure_open_source_release_published",
			{release_id = &"release_wolf_5"})
	assert_true(r.ok)
	var wolf_rows: int = 0
	var npc_seen: bool = false
	var player_seen: bool = false
	for entry in GameState.leaderboard[&"open_source"]:
		if String(entry.display_name) != "Wolf-5":
			continue
		wolf_rows += 1
		if entry.entity_type == &"npc" and entry.entity_id == &"release_wolf_5":
			npc_seen = true
		if entry.entity_type == &"player_model" and entry.entity_id == r.model_id:
			player_seen = true
	assert_eq(wolf_rows, 1, "公开开源榜上 Wolf-5 只能显示来源 NPC release 一条")
	assert_true(npc_seen, "来源 NPC release 仍应显示")
	assert_false(player_seen, "downloaded_os 运营副本不应作为玩家模型重复显示")
	assert_eq(MarketSystem.get_rank_for_model(r.model_id, &"open_source"), 0,
			"公开榜查询不把 downloaded_os 当玩家原创上榜模型")

func test_closed_source_model_does_not_appear_on_open_board() -> void:
	var mid: StringName = _add_published_model(false)
	for entry in GameState.leaderboard[&"open_source"]:
		assert_ne(entry.entity_type, &"player_model",
				"闭源模型不应上开源总榜")
	assert_eq(MarketSystem.get_rank_for_model(mid, &"open_source"), 0,
			"闭源模型在开源榜 rank 应为 0")

func test_open_source_model_does_not_appear_on_closed_board() -> void:
	var mid: StringName = _add_published_model(true)
	for entry in GameState.leaderboard[&"closed_source"]:
		assert_ne(entry.entity_type, &"player_model",
				"开源模型不应上闭源总榜")
	assert_eq(MarketSystem.get_rank_for_model(mid, &"closed_source"), 0,
			"开源模型在闭源榜 rank 应为 0")

func test_published_model_appears_on_total_board() -> void:
	# v7 PR-F: total board includes all published player models regardless
	# of open/closed source.
	var mid_c: StringName = _add_published_model(false)
	var mid_o: StringName = _add_published_model(true)
	var ids := {}
	for entry in GameState.leaderboard[&"total"]:
		if entry.entity_type == &"player_model":
			ids[entry.entity_id] = true
	assert_true(ids.has(mid_c), "total 应含闭源玩家模型")
	assert_true(ids.has(mid_o), "total 应含开源玩家模型")

func test_published_model_appears_on_all_sub_boards_regardless_of_source() -> void:
	var mid: StringName = _add_published_model(true)
	for sub in [&"sub_general", &"sub_code", &"sub_reasoning",
			&"sub_multimodal", &"sub_agent"]:
		var found: bool = false
		for entry in GameState.leaderboard[sub]:
			if entry.entity_id == mid:
				found = true; break
		assert_true(found, "model 应出现在 %s 上" % sub)

func test_unpublished_model_not_in_any_board() -> void:
	var mid: StringName = _add_published_model(false)
	CommandBus.send(&"research.unpublish_model", {model_id = mid})
	for board in ALL_BOARDS_INCLUDING_TOTAL:
		for entry in GameState.leaderboard[board]:
			assert_ne(entry.entity_id, mid)
		assert_eq(MarketSystem.get_rank_for_model(mid, board), 0,
				"unpublished model 在 %s rank 应为 0" % board)

func test_action_emits_leaderboard_resolved() -> void:
	watch_signals(EventBus)
	EventBus.phase_started.emit(&"action", 7)
	assert_signal_emitted(EventBus, "leaderboard_resolved")
	var p: Array = get_signal_parameters(EventBus, "leaderboard_resolved")
	assert_eq(p[0], GameState.turn)

func test_ranks_are_descending_in_capability() -> void:
	_add_published_model(false)
	for board in ALL_BOARDS_INCLUDING_TOTAL:
		var prev_score: float = INF
		var entries: Array = GameState.leaderboard[board]
		for entry in entries:
			assert_lte(entry.capability_score, prev_score)
			prev_score = entry.capability_score
		for i in range(entries.size()):
			assert_eq(entries[i].rank, i + 1)

func test_total_board_score_is_sum_of_axes() -> void:
	_add_published_model(false, {&"general": 10.0, &"code": 20.0,
			&"reasoning": 30.0, &"multimodal": 40.0, &"agent": 50.0})
	for entry in GameState.leaderboard[&"closed_source"]:
		if entry.entity_type == &"player_model":
			assert_almost_eq(entry.capability_score, 150.0, 0.001)
			return
	fail_test("closed_source 上没找到玩家 entry")

func test_sub_board_score_is_single_axis() -> void:
	var mid: StringName = _add_published_model(false, {
			&"general": 10.0, &"code": 999.0,
			&"reasoning": 30.0, &"multimodal": 40.0, &"agent": 50.0})
	for entry in GameState.leaderboard[&"sub_code"]:
		if entry.entity_id == mid:
			assert_almost_eq(entry.capability_score, 999.0, 0.001)
			return
	fail_test("sub_code 上没找到玩家 entry")

# ---- §5.2 LeaderboardEntry display -------------------------------------

func test_player_entry_has_empty_company_name() -> void:
	_add_published_model(false, {&"general": 100.0, &"code": 0.0,
			&"reasoning": 0.0, &"multimodal": 0.0, &"agent": 0.0})
	for entry in GameState.leaderboard[&"total"]:
		if entry.entity_type == &"player_model":
			assert_eq(entry.company_name, "", "玩家 entry company_name 应为空")
			return
	fail_test("找不到玩家 entry")

func test_npc_entry_has_company_name_and_release_model_name() -> void:
	# NPC entry: display_name = release.display_name; company_name = npc.display_name.
	# v8 PR-H: NPC timelines start at turn 70+; advance so the total board has NPCs.
	GameState.turn = 500
	EventBus.phase_started.emit(&"action", 500)
	for entry in GameState.leaderboard[&"total"]:
		if entry.entity_type == &"npc":
			assert_ne(entry.company_name, "", "NPC entry company_name 应非空")
			assert_ne(entry.display_name, entry.company_name,
					"NPC entry 模型名 与 公司名 应不同 (前者是 release name)")
			return
	fail_test("找不到 NPC entry")

# ---- §3 player_rank_changed --------------------------------------------

func test_player_rank_changed_emits_when_rank_changes() -> void:
	watch_signals(EventBus)
	_add_dominant_player_model(false)
	assert_signal_emitted(EventBus, "player_rank_changed")

# ---- §6.6 immediate resolve --------------------------------------------

func test_publish_triggers_immediate_resolve_leaderboard() -> void:
	var mid: StringName = _add_published_model(false)
	var found: bool = false
	for entry in GameState.leaderboard[&"closed_source"]:
		if entry.entity_id == mid:
			found = true; break
	assert_true(found)

# ---- §4 history --------------------------------------------------------

func test_history_grows_each_action_phase() -> void:
	for i in range(5):
		EventBus.phase_started.emit(&"action", i + 1)
	assert_eq(GameState.leaderboard_history.size(), 5)

func test_history_capped_at_history_limit() -> void:
	for i in range(40):
		EventBus.phase_started.emit(&"action", i + 1)
	assert_eq(GameState.leaderboard_history.size(), 36)

# ---- v3 initial calibration -------------------------------------------

func test_initial_capability_seed_calibrated_to_2017_sota() -> void:
	# NPC seeds (turn 0) anchor to 2017 SOTA → all axes ≤ 5.
	for npc in GameState.npc_companies:
		for axis in NpcCompany.AXES:
			var v: float = float(npc.model_capability.get(String(axis), 0.0))
			assert_lte(v, 5.0,
					"%s.%s 初始 %.1f 超过 2017 SOTA 倒推上限 5" % [npc.id, axis, v])
			assert_gte(v, 0.0,
					"%s.%s 初始 %.1f 不能为负" % [npc.id, axis, v])

func test_top_npc_orca_lab_general_leads_closed_main_board() -> void:
	# OrcaLab seeds general = 4, highest among closed-source main board NPCs.
	var orca: NpcCompany = null
	for npc in GameState.npc_companies:
		if npc.id == &"npc_orca_lab": orca = npc; break
	assert_not_null(orca, "默认 NPC 应包含 npc_orca_lab")
	for npc in GameState.npc_companies:
		if npc.id == &"npc_orca_lab": continue
		if not (&"closed_source" in npc.board_membership): continue
		assert_gte(float(orca.model_capability["general"]),
				float(npc.model_capability["general"]),
				"OrcaLab seed 应 ≥ %s 的 general" % npc.id)
