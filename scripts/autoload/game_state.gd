extends Node

## Persistent, globally readable game state. Passive container — owners
## (one system per top-level slice, see design/系统耦合矩阵.md §1) are the
## only writers. UI and other systems read directly.
##
## v1 expansion: every system listed in design/玩法设计.md §0 has its slice
## here. Resources (cash/paid_users/token_demand) are scalar/dict;
## assets are arrays of Resource subclasses. Owner system noted on each
## block. v7 PR-F (2026-05): `fame` field deleted along with the
## fame-driven mechanics (UserSystem demand, EconomySystem valuation,
## HiringSystem brackets, InfraSystem unlock, EventSystem triggers).

const SAVE_VERSION: int = 1
# Per 平衡参数.md §GameState + 经济系统设计.md §7: STARTING_CASH is the
# authoritative `starting_cash` field of resources/data/economy/tuning.tres.
# Loaded into these vars at reset() (and at first instantiation as a
# fallback). 1M ¥ baseline matches solo-desk → pod early-game sizing.
const _ECONOMY_TUNING_PATH: String = "res://resources/data/economy/tuning.tres"
var STARTING_CASH: int = 1_000_000
var STARTING_MONEY: int = 1_000_000  # legacy alias (economy_system tests)

# Per design/游戏基础架构设计.md §3.4.1: turn=0 anchors to the day the
# Transformer paper was published on arXiv (Vaswani et al., "Attention Is All
# You Need"). All hardware GPU launches and NPC competitor progression are
# pinned against this calendar.
const GAME_START_DATE: String = "2017-06-12"
const SECONDS_PER_DAY: int = 86_400
const DAYS_PER_TURN: int = 7

# Owner: TurnManager
var turn: int = 0

# 新手引导触发标志 — 会话态, 不入存档 (同 _next_*_seq 计数器, 见 §读档 ID 一致性)。
# StartScreen 确认新游戏时置 true; main._ready() 读后无条件清零并据此决定是否弹
# TutorialDialog。读档 / 继续游戏不置, 故只在真正的新游戏弹。见 教程与帮助系统设计.md §1。
var pending_intro: bool = false

# Founder profile — written once at new-game start (StartScreen / NewGameDialog),
# never mutated by any system. Per design/出身系统设计.md §3.
# founder_origin is &"" for legacy saves and the default (menu-skipped) new
# game; FounderSystem then yields a fully neutral spec.
var player_name: String = ""
var company_name: String = ""
var founder_origin: StringName = &""
# company_logo: UITheme.LOGO_MARKS 里的标志 id; &"" = 默认抽象「A」标记 (旧档 / 菜单跳过).
# founder_avatar: 创始人头像 key (avatar-NN); &"" = 走 lead.id 哈希肖像池. 见 §3.
var company_logo: StringName = &""
var founder_avatar: StringName = &""

# Owner: EconomySystem (resources dict kept for legacy `cost: {money: ...}` shape)
var cash: int = STARTING_CASH
var debt: int = 0
var equity: Dictionary = {founder = 1.0, investors = 0.0}
var loans: Array = []
var bankruptcy_streak: int = 0
var resources: Dictionary = {}  # legacy bucket for v0 spend payloads
# Derived weekly snapshots used by bankruptcy/credit/loan formulas. Recomputed
# at upkeep by EconomySystem from recent revenue & spend; readers may treat as
# read-only. weekly_burn_rate = rolling avg over burn_window_weeks;
# quarterly_revenue = rolling sum over revenue_window_weeks (~12 weeks).
var weekly_burn_rate: int = 0
var quarterly_revenue: int = 0
# 税务亏损结转池 (design/经济系统设计.md §4.9): 经营性净利润为负的周累加进来,
# 盈利周先抵减应税利润再计税。写存档。
var tax_loss_carryforward: int = 0
# EconomySystem records which funding rounds were already accepted so the same
# round can't fire twice. Player-initiated 8-round sequential
# (pre_seed→seed→a-f), see design/经济系统设计.md §4.6.
var funding_rounds_accepted: Dictionary = {}
# Weekly financial ledger (current week, in-progress) + rolling history snapshot.
# Per design/经济系统设计.md §4.8.
#   weekly_ledger  : {income: {category → amt}, expense: {category → amt},
#                     gross_in, gross_out}
#   ledger_history : Array of {turn, income, expense, gross_in, gross_out,
#                              ending_cash}, newest first, capped at 12 weeks.
var weekly_ledger: Dictionary = {income = {}, expense = {}, gross_in = 0, gross_out = 0}
var ledger_history: Array = []

# Owner: HiringSystem
var leads: Array = []
var lead_pool: Array = []
var staff_pool: Dictionary = {}
var staff_busy: Dictionary = {}

# Owner: InfraSystem
var datacenters: Array = []
var construction_queue: Array = []

# Owner: DatasetSystem
var datasets: Array = []

# Owner: ResearchSystem
var models: Array = []

# Owner: TaskSystem
var active_tasks: Array = []

# Owner: TechTreeSystem
var unlocks: Dictionary = {}
var researching_nodes: Dictionary = {}

# Owner: MarketSystem
# v7 PR-F (2026-05): `fame` field deleted. Demand is now rank-driven via
# MarketSystem.get_rank_for_model() reading the leaderboard directly.
var leaderboard: Dictionary = {}
var leaderboard_history: Array = []
var npc_companies: Array = []
# v8 PR-H (2026-05): distillation_timers slice deleted. NPCs are timeline-driven
# now (NpcCompany.model_releases); there is no per-board catch-up countdown.

# Owner: UserSystem (resource type — paid_users + per-model token_demand)
var paid_users: int = 0
var token_demand: Dictionary = {}
## §0bis split: 仅 api 部分的 demand, 给 MonetizationSystem 直接读. UI 显示总
## demand 仍用 `token_demand`.
var api_token_demand: Dictionary = {}
var last_user_resolved_turn: int = -1

# Owner: ProductSystem
var products: Array = []

# Owner: MonetizationSystem (snapshot, not an asset)
var last_revenue_breakdown: Dictionary = {}

# Owner: MarketingSystem
var campaigns: Array = []

# Owner: EventSystem
var pending_events: Array = []
var event_history: Array = []
var event_cooldowns: Dictionary = {}
# Per-card lifetime trigger counts. Pairs with EventCard.max_triggers to cap how
# many times a card may ever fire ("一辈子只来一次"); see 事件系统设计.md §4.7.
var event_trigger_counts: Dictionary = {}
# Turn the last routine event was pushed. Routine events fire every
# EventSystem.ROUTINE_INTERVAL weeks; see 事件系统设计.md §4.5.
var last_routine_turn: int = 0

# Owner: CharitySystem (per design/慈善系统设计.md §4). Cumulative *completed*
# donation per cause id → amount. Only credited when a charity task completes
# (in-progress donations live in active_tasks). Display / ledger only — no longer
# decides tier; that's charity_tier_done below.
var charity_donated: Dictionary = {}

# Owner: CharitySystem. Completed-tier *count* per cause id (0..N). The sole
# source of truth for the active tier / capped buff: current tier index =
# count - 1, next donatable tier = count (sequential one-shot ladder). +1 each
# time a charity task completes. Per design/慈善系统设计.md §3-4.
var charity_tier_done: Dictionary = {}

# Owner: CollectionSystem (per design/办公室与收藏系统设计.md §5).
# owned_collectibles: {collectible_id(StringName): bought_price(int)} — 持有的收藏品 + 买入价。
# trophies: 已获得奖杯 id (StringName) 列表; 本期(二期)恒空, 授予来源后续接。
var owned_collectibles: Dictionary = {}
var trophies: Array = []
# 拍卖行轮换 lineup (当前上架的收藏 id) + 上次刷新回合。Per 办公室与收藏系统设计.md §8.3。
var auction_lineup: Array = []
var auction_refreshed_turn: int = -1

# Owner: SimulationSystem (per design/宇宙模拟工程设计.md §4). 已完成的宇宙模拟阶段数
# (0=未开始, 5=全部完成)。
var simulation_stages_done: int = 0

# Old-style bucket (legacy v0; some tests still expect employees as alias for leads).
var employees: Array = []

# RNG bookkeeping (saved with the rest of the state).
var rng_seed: int = 0
var rng_state: int = 0
var _rng: RandomNumberGenerator = null

const STAFF_ROLES: Array[StringName] = [&"ml_eng", &"infra_eng", &"data_eng", &"marketing", &"ops"]
const TECH_TREES: Array[StringName] = [&"arch", &"attention", &"loss", &"engineering", &"application", &"context"]

func _ready() -> void:
	reset()

func _refresh_starting_cash_from_tuning() -> void:
	# Pulled out so reset() can refresh on every game start (covers test-time
	# .tres edits and post-_init updates). Falls back to the var defaults if
	# the file is missing.
	if not ResourceLoader.exists(_ECONOMY_TUNING_PATH):
		return
	var t := load(_ECONOMY_TUNING_PATH)
	if t != null and "starting_cash" in t:
		STARTING_CASH = int(t.starting_cash)
		STARTING_MONEY = STARTING_CASH

func reset() -> void:
	_refresh_starting_cash_from_tuning()
	turn = 0

	player_name = ""
	company_name = ""
	founder_origin = &""
	company_logo = &""
	founder_avatar = &""

	cash = STARTING_CASH
	debt = 0
	equity = {founder = 1.0, investors = 0.0}
	loans = []
	bankruptcy_streak = 0
	resources = {&"money": STARTING_CASH}
	weekly_burn_rate = 0
	quarterly_revenue = 0
	tax_loss_carryforward = 0
	funding_rounds_accepted = {}
	weekly_ledger = {income = {}, expense = {}, gross_in = 0, gross_out = 0}
	ledger_history = []

	leads = []
	lead_pool = []
	staff_pool = {}
	staff_busy = {}
	for role in STAFF_ROLES:
		staff_pool[role] = 0
		staff_busy[role] = 0

	datacenters = []
	construction_queue = []

	datasets = []
	models = []
	active_tasks = []

	unlocks = {}
	for tree in TECH_TREES:
		unlocks[tree] = {}
	# ant_v1 is the always-on starting arch (per 公共枚举表.md §7 / 平衡参数.md §arch).
	# Animal-codename canonical id; legacy `transformer_v1` alias is still
	# accepted by tech_tree_system._on_get_arch_coefs for old saves.
	unlocks[&"arch"][&"ant_v1"] = true
	# v5 (PR-C): baseline nodes for the new B/C subtrees so PretrainDialog has
	# at least one option in each dropdown from turn 0.
	unlocks[&"attention"][&"mha_baseline"] = true
	unlocks[&"loss"][&"ce_baseline"] = true
	# v7 PR-G: context tree baseline (ctx_4k always unlocked).
	unlocks[&"context"][&"ctx_4k"] = true
	researching_nodes = {}

	# 8 boards per design/市场系统设计.md §1 (v7 PR-F): the unified `total` board
	# plus closed/open source totals + 5 sub-axes (general/code/reasoning/
	# multimodal/agent). `total` is the user-facing demand-driving board;
	# closed_source/open_source are kept for display only.
	leaderboard = {
		total = [],
		closed_source = [],
		open_source = [],
		sub_general = [],
		sub_code = [],
		sub_reasoning = [],
		sub_multimodal = [],
		sub_agent = [],
	}
	leaderboard_history = []
	npc_companies = []

	paid_users = 0
	token_demand = {}
	api_token_demand = {}
	last_user_resolved_turn = -1

	products = []
	last_revenue_breakdown = {}
	campaigns = []

	pending_events = []
	event_history = []
	event_cooldowns = {}
	event_trigger_counts = {}
	last_routine_turn = 0

	charity_donated = {}
	charity_tier_done = {}
	owned_collectibles = {}
	trophies = []
	auction_lineup = []
	auction_refreshed_turn = -1
	simulation_stages_done = 0

	employees = []

	rng_seed = 0
	rng_state = 0
	_rng = null
	EventBus.state_reset.emit()

# ---- date helpers (game world timeline anchored to GAME_START_DATE) -----

## Returns the calendar date corresponding to a given turn number, formatted
## as "YYYY-MM-DD". Per design/游戏基础架构设计.md §3.4.1.
func turn_to_date(t: int) -> String:
	var anchor_unix: int = Time.get_unix_time_from_datetime_string(GAME_START_DATE)
	var unix: int = anchor_unix + t * DAYS_PER_TURN * SECONDS_PER_DAY
	return Time.get_date_string_from_unix_time(unix)

## Inverse of turn_to_date: returns the turn number for a given calendar date.
## Truncates to whole turns (i.e. returns the turn whose week contains `date`).
func date_to_turn(date: String) -> int:
	var anchor_unix: int = Time.get_unix_time_from_datetime_string(GAME_START_DATE)
	var unix: int = Time.get_unix_time_from_datetime_string(date)
	var days: float = float(unix - anchor_unix) / float(SECONDS_PER_DAY)
	return floori(days / float(DAYS_PER_TURN))

## Convenience: current in-game date based on GameState.turn.
func current_date() -> String:
	return turn_to_date(turn)

func rng() -> RandomNumberGenerator:
	if _rng == null:
		_rng = RandomNumberGenerator.new()
		_rng.seed = rng_seed
		_rng.state = rng_state
	rng_state = _rng.state
	return _rng

# ---- save / load --------------------------------------------------------


func to_dict() -> Dictionary:
	# Sync rng_state before snapshotting so load resumes the same stream.
	if _rng != null:
		rng_state = _rng.state
	return {
		turn = turn,
		player_name = player_name,
		company_name = company_name,
		founder_origin = String(founder_origin),
		company_logo = String(company_logo),
		founder_avatar = String(founder_avatar),
		cash = cash,
		debt = debt,
		equity = {founder = float(equity.get(&"founder", 1.0)),
				  investors = float(equity.get(&"investors", 0.0))},
		loans = _arr_to_dicts(loans),
		bankruptcy_streak = bankruptcy_streak,
		resources = _dict_with_sn_keys_to_strings(resources),
		weekly_burn_rate = weekly_burn_rate,
		quarterly_revenue = quarterly_revenue,
		tax_loss_carryforward = tax_loss_carryforward,
		funding_rounds_accepted = _dict_with_sn_keys_to_strings(funding_rounds_accepted),
		weekly_ledger = weekly_ledger.duplicate(true),
		ledger_history = ledger_history.duplicate(true),

		leads = _arr_to_dicts(leads),
		lead_pool = _arr_to_dicts(lead_pool),
		staff_pool = _dict_with_sn_keys_to_strings(staff_pool),
		staff_busy = _dict_with_sn_keys_to_strings(staff_busy),

		datacenters = _arr_to_dicts(datacenters),
		construction_queue = _arr_to_dicts(construction_queue),

		datasets = _arr_to_dicts(datasets),
		models = _arr_to_dicts(models),
		active_tasks = _arr_to_dicts(active_tasks),

		unlocks = _nested_sn_dict_to_strings(unlocks),
		researching_nodes = _nested_sn_dict_to_strings(researching_nodes),

		leaderboard = _leaderboard_to_dict(leaderboard),
		leaderboard_history = _history_to_dicts(leaderboard_history),
		npc_companies = _arr_to_dicts(npc_companies),

		paid_users = paid_users,
		token_demand = _dict_with_sn_keys_to_strings(token_demand),
		api_token_demand = _dict_with_sn_keys_to_strings(api_token_demand),
		last_user_resolved_turn = last_user_resolved_turn,

		products = _arr_to_dicts(products),
		last_revenue_breakdown = _breakdown_to_dict(last_revenue_breakdown),
		campaigns = _arr_to_dicts(campaigns),

		pending_events = _arr_to_dicts(pending_events),
		event_history = _arr_to_dicts(event_history),
		event_cooldowns = _dict_with_sn_keys_to_strings(event_cooldowns),
		event_trigger_counts = _dict_with_sn_keys_to_strings(event_trigger_counts),
		last_routine_turn = last_routine_turn,

		charity_donated = _dict_with_sn_keys_to_strings(charity_donated),
		charity_tier_done = _dict_with_sn_keys_to_strings(charity_tier_done),
		owned_collectibles = _dict_with_sn_keys_to_strings(owned_collectibles),
		trophies = _sn_arr_to_strings(trophies),
		auction_lineup = _sn_arr_to_strings(auction_lineup),
		auction_refreshed_turn = auction_refreshed_turn,
		simulation_stages_done = simulation_stages_done,

		rng_seed = rng_seed,
		rng_state = rng_state,
	}

func from_dict(d: Dictionary) -> void:
	turn = int(d.get("turn", 0))
	player_name = String(d.get("player_name", ""))
	company_name = String(d.get("company_name", ""))
	founder_origin = StringName(d.get("founder_origin", ""))
	company_logo = StringName(d.get("company_logo", ""))
	founder_avatar = StringName(d.get("founder_avatar", ""))

	cash = int(d.get("cash", STARTING_CASH))
	debt = int(d.get("debt", 0))
	var eq: Dictionary = d.get("equity", {})
	equity = {
		founder = float(eq.get("founder", 1.0)),
		investors = float(eq.get("investors", 0.0)),
	}
	loans = _dicts_to_arr(d.get("loans", []), Loan)
	bankruptcy_streak = int(d.get("bankruptcy_streak", 0))
	resources = _strings_to_sn_keys(d.get("resources", {&"money": cash}))
	# Accept legacy "monthly_burn_rate" / "annual_revenue" keys from older saves.
	weekly_burn_rate = int(d.get("weekly_burn_rate", d.get("monthly_burn_rate", 0)))
	quarterly_revenue = int(d.get("quarterly_revenue", d.get("annual_revenue", 0)))
	tax_loss_carryforward = int(d.get("tax_loss_carryforward", 0))
	funding_rounds_accepted = _strings_to_sn_keys(d.get("funding_rounds_accepted", {}))
	weekly_ledger = d.get("weekly_ledger",
			{income = {}, expense = {}, gross_in = 0, gross_out = 0}).duplicate(true)
	ledger_history = (d.get("ledger_history", []) as Array).duplicate(true)

	leads = _dicts_to_arr(d.get("leads", []), Lead)
	lead_pool = _dicts_to_arr(d.get("lead_pool", []), Lead)
	staff_pool = _strings_to_sn_keys(d.get("staff_pool", {}))
	staff_busy = _strings_to_sn_keys(d.get("staff_busy", {}))
	for role in STAFF_ROLES:
		if not staff_pool.has(role): staff_pool[role] = 0
		if not staff_busy.has(role): staff_busy[role] = 0

	datacenters = _dicts_to_arr(d.get("datacenters", []), Datacenter)
	construction_queue = _dicts_to_arr(d.get("construction_queue", []), DatacenterConstruction)

	datasets = _dicts_to_arr(d.get("datasets", []), Dataset)
	models = _dicts_to_arr(d.get("models", []), Model)
	active_tasks = _dicts_to_arr(d.get("active_tasks", []), TaskInstance)

	unlocks = _strings_to_nested_sn(d.get("unlocks", {}))
	for tree in TECH_TREES:
		if not unlocks.has(tree):
			unlocks[tree] = {}
	researching_nodes = _strings_to_nested_sn(d.get("researching_nodes", {}))

	# v7 PR-F: fame field deleted; legacy saves' "fame" key is silently ignored.
	leaderboard = _leaderboard_from_dict(d.get("leaderboard", {}))
	leaderboard_history = _history_from_dicts(d.get("leaderboard_history", []))
	npc_companies = _dicts_to_arr(d.get("npc_companies", []), NpcCompany)
	# v8 PR-H: distillation_timers removed from save schema; old saves silently drop it.

	paid_users = int(d.get("paid_users", 0))
	token_demand = _strings_to_sn_keys(d.get("token_demand", {}))
	api_token_demand = _strings_to_sn_keys(d.get("api_token_demand", {}))
	last_user_resolved_turn = int(d.get("last_user_resolved_turn", -1))

	products = _dicts_to_arr(d.get("products", []), Product)
	last_revenue_breakdown = _breakdown_from_dict(d.get("last_revenue_breakdown", {}))
	campaigns = _dicts_to_arr(d.get("campaigns", []), Campaign)

	pending_events = _dicts_to_arr(d.get("pending_events", []), EventInstance)
	event_history = _dicts_to_arr(d.get("event_history", []), EventInstance)
	event_cooldowns = _strings_to_sn_keys(d.get("event_cooldowns", {}))
	event_trigger_counts = _strings_to_sn_keys(d.get("event_trigger_counts", {}))
	last_routine_turn = int(d.get("last_routine_turn", 0))

	charity_donated = _strings_to_sn_keys(d.get("charity_donated", {}))
	charity_tier_done = _strings_to_sn_keys(d.get("charity_tier_done", {}))
	owned_collectibles = _strings_to_sn_keys(d.get("owned_collectibles", {}))
	trophies = _strings_to_sn_arr(d.get("trophies", []))
	auction_lineup = _strings_to_sn_arr(d.get("auction_lineup", []))
	auction_refreshed_turn = int(d.get("auction_refreshed_turn", -1))
	simulation_stages_done = int(d.get("simulation_stages_done", 0))

	rng_seed = int(d.get("rng_seed", 0))
	rng_state = int(d.get("rng_state", 0))
	_rng = null  # next rng() call will rebuild from seed/state

# ---- save/load helpers --------------------------------------------------

func _arr_to_dicts(arr: Array) -> Array:
	var out: Array = []
	for r in arr:
		out.append(r.to_dict())
	return out

func _dicts_to_arr(arr, klass) -> Array:
	var out: Array = []
	for d in arr:
		out.append(klass.from_dict(d))
	return out

# ---- 读档 ID 一致性 helper ----------------------------------------------
# 各系统的 _next_*_seq 自增 ID 计数器是会话变量, 不入存档。读档后用下面两个
# helper 恢复计数器 + 修旧档已有的重复 ID, 防止新建对象与档内对象撞 ID。
# (撞 ID → find_* 取首个匹配 → 锁/派单解析到错的对象, 见 759612f / 数据集系统设计 §3。)

## 扫描多个对象数组, 返回带某前缀的 ID 中最大的数字后缀 (无匹配返回 0)。
func max_seq_for_prefix(arrays: Array, prefix: String) -> int:
	var m: int = 0
	for arr in arrays:
		for o in arr:
			var s: String = String(o.id)
			if s.begins_with(prefix):
				m = maxi(m, s.trim_prefix(prefix).to_int())
	return m

## 给多个数组里 ID 重复的对象 (第 2 个及之后出现的) 重新发 ID。`gen` 是无参
## Callable, 每调一次产出一个全新唯一 ID。返回 [{obj, old_id, new_id}], 让调用
## 方做后续清锁 / re-tag。须在计数器已 restore 之后调, 保证 gen 产出不再撞。
func dedup_ids(arrays: Array, gen: Callable) -> Array:
	var seen: Dictionary = {}
	var changes: Array = []
	for arr in arrays:
		for o in arr:
			if not seen.has(o.id):
				seen[o.id] = true
				continue
			var old_id = o.id
			var new_id = gen.call()
			o.id = new_id
			seen[new_id] = true
			changes.append({obj = o, old_id = old_id, new_id = new_id})
	return changes

func _dict_with_sn_keys_to_strings(d: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k in d.keys():
		var v = d[k]
		if v is StringName:
			v = String(v)
		out[String(k)] = v
	return out

func _strings_to_sn_keys(d) -> Dictionary:
	var out: Dictionary = {}
	if d is Dictionary:
		for k in d.keys():
			out[StringName(k)] = d[k]
	return out

func _sn_arr_to_strings(arr: Array) -> Array:
	var out: Array = []
	for v in arr:
		out.append(String(v))
	return out

func _strings_to_sn_arr(arr) -> Array:
	var out: Array = []
	if arr is Array:
		for v in arr:
			out.append(StringName(v))
	return out

func _nested_sn_dict_to_strings(d: Dictionary) -> Dictionary:
	# Two-level dicts like unlocks[tree][node_id] = bool/value.
	var out: Dictionary = {}
	for k in d.keys():
		var inner = d[k]
		if inner is Dictionary:
			out[String(k)] = _dict_with_sn_keys_to_strings(inner)
		else:
			out[String(k)] = inner
	return out

func _strings_to_nested_sn(d) -> Dictionary:
	var out: Dictionary = {}
	if d is Dictionary:
		for k in d.keys():
			var inner = d[k]
			if inner is Dictionary:
				out[StringName(k)] = _strings_to_sn_keys(inner)
			else:
				out[StringName(k)] = inner
	return out

const _LEADERBOARD_KEYS: Array = [
	"total",                          # v7 PR-F: unified user-facing board
	"closed_source", "open_source",
	"sub_general", "sub_code", "sub_reasoning", "sub_multimodal", "sub_agent",
]

func _leaderboard_to_dict(lb: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k in _LEADERBOARD_KEYS:
		out[k] = _arr_to_dicts(lb.get(StringName(k), []))
	return out

func _leaderboard_from_dict(d) -> Dictionary:
	var out: Dictionary = {}
	for k in _LEADERBOARD_KEYS:
		var arr = []
		if d is Dictionary:
			arr = d.get(k, [])
		out[StringName(k)] = _dicts_to_arr(arr, LeaderboardEntry)
	return out

func _history_to_dicts(history: Array) -> Array:
	# v7 PR-F: fame field removed from history snapshots.
	var out: Array = []
	for snap in history:
		var s: Dictionary = {
			turn = int(snap.get("turn", 0)),
		}
		for k in _LEADERBOARD_KEYS:
			s[k] = _arr_to_dicts(snap.get(StringName(k), []))
		out.append(s)
	return out

func _history_from_dicts(arr) -> Array:
	var out: Array = []
	if arr is Array:
		for d in arr:
			var s: Dictionary = {
				turn = int(d.get("turn", 0)),
			}
			for k in _LEADERBOARD_KEYS:
				s[StringName(k)] = _dicts_to_arr(d.get(k, []), LeaderboardEntry)
			out.append(s)
	return out

func _breakdown_to_dict(b: Dictionary) -> Dictionary:
	if b.is_empty():
		return {}
	return {
		turn = int(b.get(&"turn", -1)),
		api_total = int(b.get(&"api_total", 0)),
		api_per_model = _dict_with_sn_keys_to_strings(b.get(&"api_per_model", {})),
		api_per_product = _dict_with_sn_keys_to_strings(b.get(&"api_per_product", {})),
		subscription_total = int(b.get(&"subscription_total", 0)),
		subscription_per_product = _dict_with_sn_keys_to_strings(b.get(&"subscription_per_product", {})),
		api_demand_lost = int(b.get(&"api_demand_lost", 0)),
	}

func _breakdown_from_dict(d) -> Dictionary:
	if not (d is Dictionary) or d.is_empty():
		return {}
	return {
		turn = int(d.get("turn", -1)),
		api_total = int(d.get("api_total", 0)),
		api_per_model = _strings_to_sn_keys(d.get("api_per_model", {})),
		api_per_product = _strings_to_sn_keys(d.get("api_per_product", {})),
		subscription_total = int(d.get("subscription_total", 0)),
		subscription_per_product = _strings_to_sn_keys(d.get("subscription_per_product", {})),
		api_demand_lost = int(d.get("api_demand_lost", 0)),
	}
