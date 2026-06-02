extends Node

## MarketSystem v8 PR-H (2026-05) — timeline-driven competitors.
## Owns leaderboard (8 boards: total / closed_source / open_source / 5 subs),
## leaderboard_history, npc_companies. NPC capability comes from the latest
## NpcModelRelease whose release_turn <= GameState.turn. Per
## design/竞争对手系统设计.md + design/NPC配置.md.
##
## Weekly action phase:
##   _advance_npc_releases()           # flip current_release_id; emit npc_released
##   _resolve_leaderboard()            # rebuild all 8 boards; emit player_rank_changed
##   _push_history()
##
## v8 PR-H delta vs v7:
##   - Removed step jump (step_size / step_period / growth_curve / perturbation
##     / next_step_turn) — NPC capability is a snapshot of latest release.
##   - Removed distillation timers and `npc_distilled` signal.
##   - Removed `market.perturb_npc` and `market.boost_npc` commands.
##   - Added `npc_released` signal.
##   - LeaderboardEntry now carries `company_name` (model — company UI).

const NpcCompanyT := preload("res://scripts/resources/npc_company.gd")
const NpcModelReleaseT := preload("res://scripts/resources/npc_model_release.gd")
const LeaderboardEntryT := preload("res://scripts/resources/leaderboard_entry.gd")
const MarketTuningT := preload("res://scripts/resources/market_tuning.gd")

const OWNED_SLICES: Array[StringName] = [
	&"leaderboard", &"leaderboard_history", &"npc_companies",
]

const TUNING_PATH: String = "res://resources/data/market/tuning.tres"
var HISTORY_LIMIT: int = 36

const BOARD_IDS: Array[StringName] = [
	&"total",
	&"closed_source", &"open_source",
	&"sub_general", &"sub_code", &"sub_reasoning", &"sub_multimodal", &"sub_agent",
]

const SUB_BOARD_AXIS: Dictionary = {
	&"sub_general": &"general",
	&"sub_code": &"code",
	&"sub_reasoning": &"reasoning",
	&"sub_multimodal": &"multimodal",
	&"sub_agent": &"agent",
}

const SUB_BOARD_FOR_PRODUCT_TYPE: Dictionary = {
	&"chatbot": &"sub_general",
	&"agent": &"sub_agent",
	&"multimodal_assistant": &"sub_multimodal",
	&"coding_agent": &"sub_code",
	&"api": &"sub_general",
}

const NPC_TRES_DIR: String = "res://resources/data/npcs/"
const NPC_TRES_PATHS: Dictionary = {
	&"npc_ant_quickcode": "res://resources/data/npcs/npc_ant_quickcode.tres",
	&"npc_ant_swarm": "res://resources/data/npcs/npc_ant_swarm.tres",
	&"npc_bamboo_compiler": "res://resources/data/npcs/npc_bamboo_compiler.tres",
	&"npc_beaver_network": "res://resources/data/npcs/npc_beaver_network.tres",
	&"npc_bee_logic": "res://resources/data/npcs/npc_bee_logic.tres",
	&"npc_crow_labs": "res://resources/data/npcs/npc_crow_labs.tres",
	&"npc_dolphin_vision": "res://resources/data/npcs/npc_dolphin_vision.tres",
	&"npc_falcon_inc": "res://resources/data/npcs/npc_falcon_inc.tres",
	&"npc_finch_open": "res://resources/data/npcs/npc_finch_open.tres",
	&"npc_hare_express": "res://resources/data/npcs/npc_hare_express.tres",
	&"npc_heron_vision": "res://resources/data/npcs/npc_heron_vision.tres",
	&"npc_lynx_devnet": "res://resources/data/npcs/npc_lynx_devnet.tres",
	&"npc_octopus_think": "res://resources/data/npcs/npc_octopus_think.tres",
	&"npc_orca_lab": "res://resources/data/npcs/npc_orca_lab.tres",
	&"npc_otter_tools": "res://resources/data/npcs/npc_otter_tools.tres",
	&"npc_owl_open": "res://resources/data/npcs/npc_owl_open.tres",
	&"npc_raccoon_ops": "res://resources/data/npcs/npc_raccoon_ops.tres",
	&"npc_raven_ai": "res://resources/data/npcs/npc_raven_ai.tres",
	&"npc_sparrow_chat": "res://resources/data/npcs/npc_sparrow_chat.tres",
	&"npc_termite_devkit": "res://resources/data/npcs/npc_termite_devkit.tres",
	&"npc_tiger_studio": "res://resources/data/npcs/npc_tiger_studio.tres",
	&"npc_whale_audio": "res://resources/data/npcs/npc_whale_audio.tres",
	&"npc_wolf_research": "res://resources/data/npcs/npc_wolf_research.tres",
}

# Cached previous-rank per board so we can emit player_rank_changed on change.
var _prev_player_rank: Dictionary = {}  # board_id → int

func _ready() -> void:
	_load_tables()
	CommandBus.register(&"market.preview_rank", _on_preview_rank)
	CommandBus.register(&"market.get_rank", _on_get_rank)
	EventBus.phase_started.connect(_on_phase)
	EventBus.model_published.connect(func(_id, _open): _resolve_leaderboard())
	EventBus.model_unpublished.connect(func(_id): _resolve_leaderboard())
	EventBus.state_reset.connect(_on_state_reset)
	EventBus.save_loaded.connect(_on_save_loaded)
	_on_state_reset()

func _on_state_reset() -> void:
	_rebuild_current_leaderboard(true)

func _on_save_loaded() -> void:
	_rebuild_current_leaderboard(true)

func _rebuild_current_leaderboard(silent: bool = false) -> void:
	_install_default_npcs()
	_init_leaderboard_keys()
	_prev_player_rank.clear()
	# Sync current_release_id with the current turn (silent — don't replay the
	# entire timeline as fresh news on reset / save-load).
	_advance_npc_releases(silent)
	# Immediately resolve so leaderboards reflect NPC state without waiting for
	# the first action phase (tests assert against GameState.leaderboard right
	# after reset; pre-v8 NPC capability was set in install_default and boards
	# stayed empty until action). UserSystem doesn't rebuild here so this is
	# safe to call early.
	_resolve_leaderboard()

func _init_leaderboard_keys() -> void:
	var lb: Dictionary = GameState.leaderboard
	for board_id in BOARD_IDS:
		if not lb.has(board_id):
			lb[board_id] = []
	GameState.leaderboard = lb

# ---- commands -----------------------------------------------------------

func _on_preview_rank(p: Dictionary) -> Dictionary:
	var model_id: StringName = p.get(&"model_id", &"")
	for board_name in BOARD_IDS:
		var board: Array = GameState.leaderboard.get(board_name, [])
		for entry in board:
			if entry.entity_id == model_id:
				return {ok = true, predicted_rank = entry.rank, board = board_name}
	return {ok = true, predicted_rank = -1, board = &""}

## v7 PR-F: query the player model's 1-based rank on a specific board.
## Returns 0 when the model is not on the board (UserSystem treats 0 like #4+).
func _on_get_rank(p: Dictionary) -> Dictionary:
	var model_id: StringName = p.get(&"model_id", &"")
	var board_id: StringName = p.get(&"board_id", &"")
	if not GameState.leaderboard.has(board_id):
		return {ok = false, error = &"unknown_board"}
	var board: Array = GameState.leaderboard.get(board_id, [])
	for entry in board:
		if entry.entity_type == &"player_model" and entry.entity_id == model_id:
			return {ok = true, rank = entry.rank}
	return {ok = true, rank = 0}

## Convenience read for non-CommandBus callers (HiringSystem / UserSystem
## hot path). Matches `market.get_rank` contract — 0 means "not on the board".
func get_rank_for_model(model_id: StringName, board_id: StringName) -> int:
	var board: Array = GameState.leaderboard.get(board_id, [])
	for entry in board:
		if entry.entity_type == &"player_model" and entry.entity_id == model_id:
			return int(entry.rank)
	return 0

## v10: rank a player model among COMPETITOR (NPC) entries only — the player's
## own other published models are NOT counted. UserSystem uses this for product
## user-growth so a company never competes with itself: keeping a stronger
## (but costlier-to-serve) model in R&D must not push down the cheaper model
## the product actually serves. The public leaderboard (get_rank_for_model)
## still ranks everyone. Returns 0 when the model is not on the board.
func get_rank_vs_npcs(model_id: StringName, board_id: StringName) -> int:
	var board: Array = GameState.leaderboard.get(board_id, [])
	var my_score: float = -1.0
	for entry in board:
		if entry.entity_type == &"player_model" and entry.entity_id == model_id:
			my_score = float(entry.capability_score)
			break
	if my_score < 0.0:
		var m = _find_model(model_id)
		if m == null or m.status != &"published":
			return 0
		if not _model_eligible_for_board(m, board_id):
			return 0
		my_score = _score_caps_for_board(m.capability, board_id)
	var rank: int = 1
	for entry in board:
		if entry.entity_type == &"npc" and float(entry.capability_score) > my_score:
			rank += 1
	return rank

## v9 PR-I: reverse-lookup a release across all NPCs. Used by
## ResearchSystem.download_open_source + InfraSystem.deploy_open_source_model.
## Returns {ok = true, npc, release} on match, {ok = false} otherwise.
func find_release(release_id: StringName) -> Dictionary:
	if release_id == &"":
		return {ok = false}
	for npc in GameState.npc_companies:
		if npc == null:
			continue
		for release in npc.model_releases:
			if release != null and release.id == release_id:
				return {ok = true, npc = npc, release = release}
	return {ok = false}

## v9 PR-I: enumerate every release that the player can download / serve right now.
## Filter: npc.is_open_source && release.release_kind == &"pretrain" && release.release_turn <= turn.
## Returns an Array of {npc_id, npc_display_name, release}, ascending by release_turn.
func list_downloadable_releases(turn: int) -> Array:
	var out: Array = []
	for npc in GameState.npc_companies:
		if npc == null or not bool(npc.is_open_source):
			continue
		for release in npc.model_releases:
			if release == null:
				continue
			if release.release_kind != &"pretrain":
				continue
			if int(release.release_turn) > turn:
				continue
			out.append({
				npc_id = npc.id,
				npc_display_name = npc.display_name,
				npc = npc,
				release = release,
			})
	out.sort_custom(func(a, b): return int(a.release.release_turn) < int(b.release.release_turn))
	return out

# ---- phase --------------------------------------------------------------

func _on_phase(phase: StringName, _turn: int) -> void:
	if phase != &"action":
		return
	_advance_npc_releases()
	_resolve_leaderboard()
	_push_history()

# ---- §5.1 NPC release timeline advance --------------------------------

## Flip each NPC's current_release_id to the latest release with
## release_turn <= GameState.turn. Emit npc_released on transitions (skipped
## when `silent` is true — used by state_reset / save-load so we don't
## replay an entire pre-loaded timeline as fresh news).
func _advance_npc_releases(silent: bool = false) -> void:
	for npc in GameState.npc_companies:
		var r: NpcModelReleaseT = npc.latest_release_at(GameState.turn)
		if r == null:
			# Pre-launch: empty current_release, zero capability.
			if npc.current_release_id != &"":
				npc.current_release_id = &""
				_zero_capability(npc)
			continue
		if npc.current_release_id != r.id:
			npc.current_release_id = r.id
			npc.model_capability = NpcCompanyT._coerce_axis_dict(r.capability)
			if not silent:
				Log.info(&"market", "npc_release", {
					npc = npc.id, release = r.id, turn = GameState.turn,
					kind = r.release_kind})
				EventBus.npc_released.emit(npc.id, r.id, r.release_turn)

func _zero_capability(npc) -> void:
	for axis in NpcCompanyT.AXES:
		npc.model_capability[String(axis)] = 0.0

# ---- §5.1 / §5.2 Leaderboard rebuild -----------------------------------

func _resolve_leaderboard() -> void:
	for board_id in BOARD_IDS:
		var entries: Array = []
		# Player models.
		for m in GameState.models:
			if m.status != &"published":
				continue
			if _model_hidden_from_public_leaderboard(m):
				continue
			if not _model_eligible_for_board(m, board_id):
				continue
			entries.append(_entry_from_model(m, board_id))
		# NPCs (must have a current_release to enter).
		for npc in GameState.npc_companies:
			if npc.current_release_id == &"":
				continue
			var eligible: bool
			if board_id == &"total":
				eligible = _npc_eligible_for_total(npc)
			elif board_id == &"closed_source":
				eligible = not npc.is_open_source
			elif board_id == &"open_source":
				eligible = npc.is_open_source
			else:
				eligible = (board_id in npc.board_membership)
			if not eligible:
				continue
			entries.append(_entry_from_npc(npc, board_id))
		entries.sort_custom(func(a, b): return a.capability_score > b.capability_score)
		_assign_ranks(entries)
		GameState.leaderboard[board_id] = entries
		_check_player_rank_changed(board_id, entries)
	EventBus.leaderboard_resolved.emit(GameState.turn)

func _model_eligible_for_board(m, board_id: StringName) -> bool:
	match board_id:
		&"closed_source":
			return not m.is_open_source
		&"open_source":
			return m.is_open_source
		&"total":
			return true
		_:
			return true  # sub_* takes open + closed

func _model_hidden_from_public_leaderboard(m) -> bool:
	return m.provenance == &"downloaded_os" and m.source_release_id != &""

func _npc_eligible_for_total(npc) -> bool:
	return (&"closed_source" in npc.board_membership) or (&"open_source" in npc.board_membership)

func _entry_from_model(m, board_id: StringName) -> LeaderboardEntryT:
	var entry := LeaderboardEntryT.new()
	entry.entity_id = m.id
	entry.entity_type = &"player_model"
	entry.display_name = m.display_name
	entry.company_name = ""  # v8 PR-H: player has no company name shown
	entry.capability_score = _score_caps_for_board(m.capability, board_id)
	return entry

func _entry_from_npc(npc, board_id: StringName) -> LeaderboardEntryT:
	var entry := LeaderboardEntryT.new()
	var release: NpcModelReleaseT = _find_release(npc, npc.current_release_id)
	entry.entity_type = &"npc"
	if release != null:
		entry.entity_id = release.id
		entry.display_name = release.display_name
		entry.capability_score = _score_caps_for_board(release.capability, board_id)
	else:
		# Defensive fallback — shouldn't happen because eligibility filter
		# already requires current_release_id != "".
		entry.entity_id = npc.id
		entry.display_name = npc.display_name
		entry.capability_score = _score_caps_for_board(npc.model_capability, board_id)
	entry.company_name = npc.display_name
	return entry

func _score_caps_for_board(caps: Dictionary, board_id: StringName) -> float:
	if SUB_BOARD_AXIS.has(board_id):
		var axis := String(SUB_BOARD_AXIS[board_id])
		return float(caps.get(axis, 0.0))
	# total / closed_source / open_source: sum of all 5 axes.
	var s: float = 0.0
	for axis in NpcCompanyT.AXES:
		s += float(caps.get(String(axis), 0.0))
	return s

func _find_release(npc, release_id: StringName) -> NpcModelReleaseT:
	if release_id == &"":
		return null
	for r in npc.model_releases:
		if r != null and r.id == release_id:
			return r
	return null

func _assign_ranks(entries: Array) -> void:
	for i in range(entries.size()):
		entries[i].rank = i + 1

func _check_player_rank_changed(board_id: StringName, entries: Array) -> void:
	var new_rank: int = -1
	for entry in entries:
		if entry.entity_type == &"player_model":
			if new_rank < 0 or entry.rank < new_rank:
				new_rank = entry.rank
	var old_rank: int = int(_prev_player_rank.get(board_id, -1))
	if old_rank != new_rank:
		EventBus.player_rank_changed.emit(board_id, old_rank, new_rank)
		_prev_player_rank[board_id] = new_rank
	# 总榜登顶 → 点亮「登顶总榜」奖杯 (办公室荣誉桌)。Per 办公室与收藏系统设计.md §4。
	if board_id == &"total" and new_rank == 1:
		CollectionSystem.award_trophy(&"leaderboard_first")

# ---- §4 history --------------------------------------------------------

func _push_history() -> void:
	var snap: Dictionary = {turn = GameState.turn}
	for board_id in BOARD_IDS:
		snap[board_id] = (GameState.leaderboard.get(board_id, []) as Array).duplicate()
	GameState.leaderboard_history.append(snap)
	while GameState.leaderboard_history.size() > HISTORY_LIMIT:
		GameState.leaderboard_history.pop_front()

# ---- helpers ------------------------------------------------------------

func _find_npc(npc_id):
	var sn: StringName = StringName(npc_id)
	for npc in GameState.npc_companies:
		if npc.id == sn:
			return npc
	return null

func _find_model(model_id: StringName):
	for m in GameState.models:
		if m.id == model_id:
			return m
	return null

# ---- NPC roster install -------------------------------------------------

func _install_default_npcs() -> void:
	GameState.npc_companies.clear()
	var loaded: Array = _load_npc_tres_paths()
	if loaded.is_empty():
		loaded = _build_default_roster()
	for npc in loaded:
		# Defensive: ensure releases are sorted ascending by release_turn so
		# latest_release_at() works in a single pass.
		var releases: Array = npc.model_releases
		releases.sort_custom(func(a, b): return a.release_turn < b.release_turn)
		# Reassign through a typed array to keep the export type happy.
		var typed: Array[NpcModelReleaseT] = []
		for r in releases:
			typed.append(r)
		npc.model_releases = typed
		GameState.npc_companies.append(npc)

func _load_npc_tres_paths() -> Array:
	var out: Array = []
	for npc_id in NPC_TRES_PATHS.keys():
		var path: String = String(NPC_TRES_PATHS[npc_id])
		var res = load(path)
		if res is NpcCompanyT:
			if res.id != npc_id:
				Log.warn(&"market", "npc_id_mismatch", {
					expected = npc_id, actual = res.id, path = path,
				})
			out.append(res.duplicate(true))
		else:
			Log.warn(&"market", "npc_spec_missing", {
				id = npc_id, path = path,
			})
	return out

# Hardcoded fallback roster for test fixtures / fresh checkouts. Each entry is
# a minimal timeline (single seed release at turn 0) so the NPC actually joins
# the leaderboard. The .tres files in resources/data/npcs/ override these with
# full historical timelines. v8 PR-H — 23 NPCs (5 main + 18 sub).
func _build_default_roster() -> Array:
	var out: Array = []
	for cfg in _DEFAULT_ROSTER:
		var n := NpcCompanyT.new()
		n.id = cfg.id
		n.display_name = cfg.display_name
		n.is_open_source = cfg.is_open_source
		# board_membership is typed Array[StringName]; promote from the
		# untyped literal in _DEFAULT_ROSTER.
		var boards: Array[StringName] = []
		for b in cfg.boards:
			boards.append(StringName(b))
		n.board_membership = boards
		var rel := NpcModelReleaseT.new()
		rel.id = StringName("release_" + String(cfg.id) + "_seed")
		rel.display_name = cfg.seed_display_name
		rel.release_turn = int(cfg.seed_turn)
		rel.capability = _axis_dict(cfg.seed_cap)
		rel.release_kind = &"pretrain"
		var releases: Array[NpcModelReleaseT] = [rel]
		n.model_releases = releases
		out.append(n)
	return out

static func _axis_dict(values: Array) -> Dictionary:
	return {
		general = float(values[0]),
		code = float(values[1]),
		reasoning = float(values[2]),
		multimodal = float(values[3]),
		agent = float(values[4]) if values.size() >= 5 else 0.0,
	}

# v8 PR-H seed roster — 23 NPCs (5 main + 18 sub-board specialists). Each
# has a single tiny release at turn 0 so leaderboards are non-empty in tests.
# Real per-NPC timelines live in resources/data/npcs/*.tres.
const _DEFAULT_ROSTER: Array = [
	# Main board (5): 4 closed + 1 open frontier lab.
	{id = &"npc_orca_lab", display_name = "OrcaLab", is_open_source = false,
		seed_display_name = "Orca-seed", seed_turn = 0, seed_cap = [4, 1, 2, 0, 0],
		boards = [&"closed_source", &"sub_general", &"sub_reasoning", &"sub_agent"]},
	{id = &"npc_raven_ai", display_name = "RavenAI", is_open_source = false,
		seed_display_name = "Raven-seed", seed_turn = 0, seed_cap = [3, 1, 2, 0, 0],
		boards = [&"closed_source", &"sub_reasoning"]},
	{id = &"npc_tiger_studio", display_name = "Tiger Studio", is_open_source = false,
		seed_display_name = "Tiger-seed", seed_turn = 0, seed_cap = [2, 1, 1, 1, 0],
		boards = [&"closed_source", &"sub_multimodal"]},
	{id = &"npc_falcon_inc", display_name = "Falcon Inc", is_open_source = false,
		seed_display_name = "Falcon-seed", seed_turn = 0, seed_cap = [2, 2, 1, 0, 0],
		boards = [&"closed_source", &"sub_code", &"sub_agent"]},
	{id = &"npc_wolf_research", display_name = "Wolf Research", is_open_source = true,
		seed_display_name = "Wolf-seed", seed_turn = 0, seed_cap = [3, 1, 1, 0, 0],
		boards = [&"open_source", &"sub_general"]},

	# sub_general (3)
	{id = &"npc_sparrow_chat", display_name = "Sparrow Chat", is_open_source = false,
		seed_display_name = "Sparrow-seed", seed_turn = 0, seed_cap = [3, 1, 1, 0, 0],
		boards = [&"sub_general"]},
	{id = &"npc_hare_express", display_name = "Hare Express", is_open_source = false,
		seed_display_name = "Hare-seed", seed_turn = 0, seed_cap = [2, 1, 1, 0, 0],
		boards = [&"sub_general"]},
	{id = &"npc_finch_open", display_name = "Finch Open", is_open_source = true,
		seed_display_name = "Finch-seed", seed_turn = 0, seed_cap = [2, 1, 1, 0, 0],
		boards = [&"sub_general"]},

	# sub_code (4)
	{id = &"npc_ant_quickcode", display_name = "Ant QuickCode", is_open_source = true,
		seed_display_name = "AntCode-seed", seed_turn = 0, seed_cap = [1, 2, 1, 0, 0],
		boards = [&"sub_code"]},
	{id = &"npc_lynx_devnet", display_name = "Lynx Devnet", is_open_source = true,
		seed_display_name = "Lynx-seed", seed_turn = 0, seed_cap = [1, 2, 1, 0, 0],
		boards = [&"sub_code"]},
	{id = &"npc_termite_devkit", display_name = "Termite Devkit", is_open_source = false,
		seed_display_name = "Termite-seed", seed_turn = 0, seed_cap = [1, 2, 1, 0, 0],
		boards = [&"sub_code"]},
	{id = &"npc_bamboo_compiler", display_name = "Bamboo Compiler", is_open_source = false,
		seed_display_name = "Bamboo-seed", seed_turn = 0, seed_cap = [1, 2, 2, 0, 0],
		boards = [&"sub_code"]},

	# sub_reasoning (3)
	{id = &"npc_bee_logic", display_name = "Bee Logic", is_open_source = true,
		seed_display_name = "Bee-seed", seed_turn = 0, seed_cap = [1, 1, 2, 0, 0],
		boards = [&"sub_reasoning"]},
	{id = &"npc_octopus_think", display_name = "Octopus Think", is_open_source = false,
		seed_display_name = "Octopus-seed", seed_turn = 0, seed_cap = [1, 1, 2, 0, 0],
		boards = [&"sub_reasoning"]},
	{id = &"npc_owl_open", display_name = "Owl Open", is_open_source = true,
		seed_display_name = "Owl-seed", seed_turn = 0, seed_cap = [2, 1, 2, 0, 0],
		boards = [&"sub_reasoning"]},

	# sub_multimodal (4)
	{id = &"npc_dolphin_vision", display_name = "Dolphin Vision", is_open_source = false,
		seed_display_name = "Dolphin-seed", seed_turn = 0, seed_cap = [1, 0, 1, 2, 0],
		boards = [&"sub_multimodal"]},
	{id = &"npc_whale_audio", display_name = "Whale Audio", is_open_source = false,
		seed_display_name = "Whale-seed", seed_turn = 0, seed_cap = [1, 0, 1, 2, 0],
		boards = [&"sub_multimodal"]},
	{id = &"npc_beaver_network", display_name = "Beaver Network", is_open_source = true,
		seed_display_name = "Beaver-seed", seed_turn = 0, seed_cap = [2, 1, 1, 1, 0],
		boards = [&"sub_multimodal"]},
	{id = &"npc_heron_vision", display_name = "Heron Vision", is_open_source = true,
		seed_display_name = "Heron-seed", seed_turn = 0, seed_cap = [1, 1, 1, 2, 0],
		boards = [&"sub_multimodal"]},

	# sub_agent (4) — real-world agent specialists launch later, but we seed at
	# turn 0 so the board is non-empty in tests; .tres timelines push real first
	# launches to turn 395+ (post paradigm_reasoning_rl).
	{id = &"npc_raccoon_ops", display_name = "Raccoon Ops", is_open_source = false,
		seed_display_name = "Raccoon-seed", seed_turn = 0, seed_cap = [1, 1, 1, 0, 1],
		boards = [&"sub_agent"]},
	{id = &"npc_ant_swarm", display_name = "Ant Swarm", is_open_source = false,
		seed_display_name = "Swarm-seed", seed_turn = 0, seed_cap = [1, 1, 1, 0, 1],
		boards = [&"sub_agent"]},
	{id = &"npc_crow_labs", display_name = "Crow Labs", is_open_source = true,
		seed_display_name = "Crow-seed", seed_turn = 0, seed_cap = [1, 1, 1, 0, 1],
		boards = [&"sub_agent"]},
	{id = &"npc_otter_tools", display_name = "Otter Tools", is_open_source = true,
		seed_display_name = "Otter-seed", seed_turn = 0, seed_cap = [1, 1, 1, 0, 1],
		boards = [&"sub_agent"]},
]

# ---- table loading ------------------------------------------------------

func _load_tables() -> void:
	var t := load(TUNING_PATH)
	if t is MarketTuningT:
		HISTORY_LIMIT = int(t.history_limit)
	else:
		Log.warn(&"market", "tuning_missing", {path = TUNING_PATH})
