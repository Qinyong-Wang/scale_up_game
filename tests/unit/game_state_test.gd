extends GutTest

## Tests for GameState — the passive data container shared across systems.
## Per design/游戏基础架构设计.md §2 (state slices) + §6 (持久化).


func before_each() -> void:
	GameState.reset()

# ---- 日期锚点 (游戏基础架构 §3.4.1) ----------------------------------

func test_game_start_date_is_transformer_paper_day() -> void:
	# Per design/游戏基础架构设计.md §3.4.1: turn=0 锚定到 2017-06-12.
	assert_eq(GameState.GAME_START_DATE, "2017-06-12")

func test_turn_to_date_at_zero_returns_anchor() -> void:
	assert_eq(GameState.turn_to_date(0), "2017-06-12")

func test_turn_to_date_advances_seven_days_per_turn() -> void:
	assert_eq(GameState.turn_to_date(1), "2017-06-19")
	assert_eq(GameState.turn_to_date(52), "2018-06-11")  # 52 周后

func test_turn_to_date_handles_year_boundaries() -> void:
	# 152 weeks from 2017-06-12 = 2020-05-11 (NVIDIA A100 era)
	assert_eq(GameState.turn_to_date(152), "2020-05-11")
	# 353 weeks = 2024-03-18 (NVIDIA B200 announce)
	assert_eq(GameState.turn_to_date(353), "2024-03-18")

func test_date_to_turn_inverts_turn_to_date() -> void:
	assert_eq(GameState.date_to_turn("2017-06-12"), 0)
	assert_eq(GameState.date_to_turn("2017-06-19"), 1)
	assert_eq(GameState.date_to_turn("2024-03-18"), 353)

func test_current_date_tracks_game_state_turn() -> void:
	GameState.turn = 0
	assert_eq(GameState.current_date(), "2017-06-12")
	GameState.turn = 100
	assert_eq(GameState.current_date(), GameState.turn_to_date(100))

# ---- 默认值与切片所有权 ------------------------------------------------

func test_reset_initializes_to_design_defaults() -> void:
	assert_eq(GameState.turn, 0)
	assert_eq(GameState.cash, GameState.STARTING_CASH)
	assert_eq(GameState.resources.get(&"money", 0), GameState.STARTING_MONEY)
	assert_eq(GameState.employees, [])
	assert_eq(GameState.datacenters, [])
	assert_eq(GameState.construction_queue, [])
	assert_eq(GameState.models, [])
	assert_eq(GameState.active_tasks, [])
	# v7 (PR-G): TECH_TREES grew from 5 to 6 with the context subtree.
	# Baseline unlocks: arch:ant_v1 / attention:mha_baseline / loss:ce_baseline /
	# context:ctx_4k.
	assert_eq(GameState.unlocks.size(), 6)
	assert_true(bool(GameState.unlocks.get(&"arch", {}).get(&"ant_v1", false)))
	assert_true(bool(GameState.unlocks.get(&"attention", {}).get(&"mha_baseline", false)))
	assert_true(bool(GameState.unlocks.get(&"loss", {}).get(&"ce_baseline", false)))
	assert_true(bool(GameState.unlocks.get(&"context", {}).get(&"ctx_4k", false)))

func test_reset_seeds_economy_with_starting_cash() -> void:
	# 经济 §1: starting_cash 由 GameState.STARTING_CASH 决定 (USD seed-tier).
	assert_eq(GameState.cash, GameState.STARTING_CASH)
	assert_eq(GameState.resources[&"money"], GameState.STARTING_CASH)

func test_reset_initializes_equity_to_full_founder_share() -> void:
	# 经济 §1: 起手 founder=1.0, investors=0.0; 融资稀释才动.
	assert_eq(GameState.equity[&"founder"], 1.0)
	assert_eq(GameState.equity[&"investors"], 0.0)

func test_reset_initializes_zero_debt_zero_loans() -> void:
	assert_eq(GameState.debt, 0)
	assert_eq(GameState.loans, [])
	assert_eq(GameState.bankruptcy_streak, 0)

func test_reset_initializes_all_three_tech_trees() -> void:
	# 科技树 §1: 三棵 DAG (arch / engineering / application), reset 后必有这三个 key.
	for tree in [&"arch", &"engineering", &"application"]:
		assert_true(GameState.unlocks.has(tree),
				"unlocks 缺少 tree %s" % tree)

func test_reset_initializes_all_staff_role_buckets() -> void:
	# 招聘 §1: 5 个 staff role 必须在 staff_pool / staff_busy 中各有 0 计数.
	for role in [&"ml_eng", &"infra_eng", &"data_eng", &"marketing", &"ops"]:
		assert_eq(int(GameState.staff_pool.get(role, -1)), 0,
				"staff_pool 缺 role %s" % role)
		assert_eq(int(GameState.staff_busy.get(role, -1)), 0,
				"staff_busy 缺 role %s" % role)

func test_reset_initializes_leaderboard_two_boards() -> void:
	# 市场 §1: leaderboard 维护 open_source / closed_source 两个榜.
	assert_true(GameState.leaderboard.has(&"open_source"))
	assert_true(GameState.leaderboard.has(&"closed_source"))

func test_reset_initializes_user_state_to_zero() -> void:
	# 用户 §1: paid_users 起手 0, token_demand 空, last_user_resolved_turn = -1.
	assert_eq(GameState.paid_users, 0)
	assert_eq(GameState.token_demand, {})
	assert_eq(GameState.last_user_resolved_turn, -1)

func test_reset_initializes_event_buckets_empty() -> void:
	# 事件 §1: 三个事件相关结构都应空.
	assert_eq(GameState.pending_events, [])
	assert_eq(GameState.event_history, [])
	assert_eq(GameState.event_cooldowns, {})

# ---- pending_intro (新手引导, 会话态不入存档) -------------------------

func test_pending_intro_defaults_false() -> void:
	# 教程与帮助 §1: 默认不弹引导; 只有起始页新游戏会置 true。
	assert_false(GameState.pending_intro, "pending_intro 默认 false")

func test_pending_intro_not_persisted_in_to_dict() -> void:
	# 会话态标志 (同 _next_*_seq 计数器), 不进存档快照。
	GameState.pending_intro = true
	assert_false(GameState.to_dict().has("pending_intro"),
			"pending_intro 不应出现在存档快照里")

# ---- 信号 / 事件 -------------------------------------------------------

func test_reset_emits_state_reset_signal() -> void:
	watch_signals(EventBus)
	GameState.reset()
	assert_signal_emitted(EventBus, "state_reset")

func test_reset_clears_mutated_state_back_to_defaults() -> void:
	# 把每个 owned slice 都改一下, 确认 reset() 清干净.
	GameState.turn = 42
	GameState.resources[&"money"] = 0
	GameState.resources[&"compute"] = 99
	GameState.employees.append("alice")
	GameState.datacenters.append("dc1")
	GameState.construction_queue.append("build1")
	GameState.models.append("m1")
	GameState.active_tasks.append("t1")
	GameState.unlocks[&"tier1"] = true
	GameState.reset()
	assert_eq(GameState.turn, 0)
	assert_eq(GameState.cash, GameState.STARTING_CASH)
	assert_eq(GameState.resources[&"money"], GameState.STARTING_MONEY)
	assert_false(GameState.resources.has(&"compute"))
	assert_eq(GameState.employees, [])
	assert_eq(GameState.datacenters, [])
	assert_eq(GameState.construction_queue, [])
	assert_eq(GameState.models, [])
	assert_eq(GameState.active_tasks, [])
	assert_true(bool(GameState.unlocks.get(&"arch", {}).get(&"ant_v1", false)))

func test_reset_clears_all_collections_after_mutation() -> void:
	# 钉每一个 owned slice (Array / Dictionary) 在 reset 后回归.
	GameState.leads.append(Lead.new())
	GameState.lead_pool.append(Lead.new())
	GameState.staff_pool[&"ml_eng"] = 17
	GameState.staff_busy[&"ml_eng"] = 17
	GameState.datacenters.append("dc")
	GameState.construction_queue.append("c")
	GameState.datasets.append("d")
	GameState.products.append("p")
	GameState.campaigns.append("c1")
	GameState.npc_companies.append("npc")
	GameState.pending_events.append("evt")
	GameState.event_history.append("evt2")
	GameState.event_cooldowns[&"funding"] = 3
	GameState.paid_users = 5000
	GameState.token_demand[&"m1"] = 12345
	GameState.last_user_resolved_turn = 5
	GameState.last_revenue_breakdown = {turn = 5, api_total = 100}

	GameState.reset()

	assert_eq(GameState.leads, [])
	assert_eq(GameState.lead_pool, [])
	assert_eq(int(GameState.staff_pool[&"ml_eng"]), 0)
	assert_eq(int(GameState.staff_busy[&"ml_eng"]), 0)
	assert_eq(GameState.datacenters, [])
	assert_eq(GameState.construction_queue, [])
	assert_eq(GameState.datasets, [])
	assert_eq(GameState.products, [])
	assert_eq(GameState.campaigns, [])
	assert_eq(GameState.pending_events, [])
	assert_eq(GameState.event_history, [])
	assert_eq(GameState.event_cooldowns, {})
	# v7 PR-F: fame field deleted; nothing to reset.
	assert_eq(GameState.paid_users, 0)
	assert_eq(GameState.token_demand, {})
	assert_eq(GameState.last_user_resolved_turn, -1)
	assert_eq(GameState.last_revenue_breakdown, {})
	# Note: npc_companies 由 MarketSystem 在 state_reset 后重新装填,
	# 不一定为空 (这是预期, 见 design/市场系统设计.md §1).

func test_resources_owned_by_economy_via_dictionary() -> void:
	assert_true(GameState.resources is Dictionary)
	assert_true(GameState.resources.has(&"money"))

# ---- RNG --------------------------------------------------------------

func test_rng_returns_deterministic_sequence_for_same_seed() -> void:
	GameState.rng_seed = 12345
	GameState._rng = null
	var a1 := GameState.rng().randi()
	var a2 := GameState.rng().randi()
	GameState.reset()
	GameState.rng_seed = 12345
	var b1 := GameState.rng().randi()
	var b2 := GameState.rng().randi()
	assert_eq(a1, b1)
	assert_eq(a2, b2)

func test_rng_caches_instance_across_calls() -> void:
	var first := GameState.rng()
	var second := GameState.rng()
	assert_same(first, second)

func test_rng_state_advances_between_calls() -> void:
	GameState.rng_seed = 7
	GameState._rng = null
	GameState.rng().randi()
	var s1: int = GameState.rng_state
	GameState.rng().randi()
	var s2: int = GameState.rng_state
	assert_ne(s1, s2, "rng_state 应在每次 randi() 后推进")

func test_reset_drops_cached_rng_instance() -> void:
	# reset() 必须把 _rng 置 null, 否则后续 rng_seed 修改不会生效.
	GameState.rng_seed = 1
	GameState._rng = null
	var first := GameState.rng()
	assert_not_null(first)
	GameState.reset()
	assert_null(GameState._rng, "reset 后 _rng 应被清空")

# ---- to_dict / from_dict 切片往返 -------------------------------------

func test_to_dict_includes_every_owned_slice_key() -> void:
	# 钉 to_dict 的输出键; 漏掉哪个就丢档.
	var d: Dictionary = GameState.to_dict()
	for k in [
		"turn", "cash", "debt", "equity", "loans", "bankruptcy_streak", "resources",
		"leads", "lead_pool", "staff_pool", "staff_busy",
		"datacenters", "construction_queue",
		"datasets", "models", "active_tasks",
		"unlocks", "researching_nodes",
		"leaderboard", "leaderboard_history", "npc_companies",
		"paid_users", "token_demand", "last_user_resolved_turn",
		"products", "last_revenue_breakdown", "campaigns",
		"pending_events", "event_history", "event_cooldowns",
		"rng_seed", "rng_state",
	]:
		assert_true(d.has(k), "to_dict 缺 key %s" % k)

func test_to_dict_uses_string_keys_for_unlocks() -> void:
	# §6.5 持久化: JSON-friendly 时所有 StringName 键转成 String.
	GameState.unlocks[&"engineering"][&"owl_cache"] = true
	var d: Dictionary = GameState.to_dict()
	assert_true((d.unlocks as Dictionary).has("engineering"))
	assert_true((d.unlocks["engineering"] as Dictionary).has("owl_cache"))

func test_from_dict_restores_string_name_keys_in_unlocks() -> void:
	var snap: Dictionary = GameState.to_dict()
	(snap.unlocks as Dictionary)["engineering"] = {"owl_cache": true}
	GameState.from_dict(snap)
	# 再次访问要用 StringName 键.
	assert_true(bool(GameState.unlocks.get(&"engineering", {}).get(&"owl_cache", false)))

func test_economy_slice_roundtrips_through_save_dict() -> void:
	GameState.cash = -42_000
	GameState.debt = 200_000
	GameState.equity = {founder = 0.6, investors = 0.4}
	GameState.bankruptcy_streak = 2
	var loan := Loan.new()
	loan.id = &"loan_xyz"; loan.principal_initial = 50_000; loan.principal_remaining = 30_000
	loan.weekly_interest_rate = 0.02; loan.weeks_remaining = 6
	GameState.loans.append(loan)
	var snap: Dictionary = GameState.to_dict()
	GameState.reset()
	GameState.from_dict(snap)
	assert_eq(GameState.cash, -42_000)
	assert_eq(GameState.debt, 200_000)
	assert_eq(GameState.equity[&"founder"], 0.6)
	assert_eq(GameState.equity[&"investors"], 0.4)
	assert_eq(GameState.bankruptcy_streak, 2)
	assert_eq(GameState.loans.size(), 1)
	assert_eq(GameState.loans[0].id, &"loan_xyz")
	assert_eq(GameState.loans[0].principal_remaining, 30_000)

func test_token_demand_roundtrips_with_string_name_keys() -> void:
	GameState.token_demand[&"m_alpha"] = 12345
	GameState.token_demand[&"m_beta"] = 67890
	var snap: Dictionary = GameState.to_dict()
	GameState.reset()
	GameState.from_dict(snap)
	assert_eq(int(GameState.token_demand[&"m_alpha"]), 12345)
	assert_eq(int(GameState.token_demand[&"m_beta"]), 67890)

func test_event_cooldowns_roundtrip() -> void:
	GameState.event_cooldowns[&"debug_test_offer"] = 3
	GameState.event_cooldowns[&"data_breach"] = 6
	var snap: Dictionary = GameState.to_dict()
	GameState.reset()
	GameState.from_dict(snap)
	assert_eq(int(GameState.event_cooldowns[&"debug_test_offer"]), 3)
	assert_eq(int(GameState.event_cooldowns[&"data_breach"]), 6)

func test_researching_nodes_roundtrip_with_nested_string_name_keys() -> void:
	# tech_tree §7: researching_nodes[tree][node_id] = task_id (StringName 嵌套).
	GameState.researching_nodes[&"engineering"] = {&"owl_cache": &"task_99"}
	var snap: Dictionary = GameState.to_dict()
	GameState.reset()
	GameState.from_dict(snap)
	assert_true(GameState.researching_nodes.has(&"engineering"))
	assert_eq(StringName(GameState.researching_nodes[&"engineering"][&"owl_cache"]), &"task_99")

func test_last_revenue_breakdown_roundtrip() -> void:
	GameState.last_revenue_breakdown = {
		&"turn": 5,
		&"api_total": 1234,
		&"api_per_model": {&"m1": 1234},
		&"subscription_total": 5678,
		&"subscription_per_product": {&"p1": 5678},
		&"api_demand_lost": 100,
	}
	var snap: Dictionary = GameState.to_dict()
	GameState.reset()
	GameState.from_dict(snap)
	var br: Dictionary = GameState.last_revenue_breakdown
	assert_eq(int(br[&"turn"]), 5)
	assert_eq(int(br[&"api_total"]), 1234)
	assert_eq(int(br[&"api_per_model"][&"m1"]), 1234)
	assert_eq(int(br[&"subscription_total"]), 5678)
	assert_eq(int(br[&"api_demand_lost"]), 100)

func test_last_revenue_breakdown_empty_dict_roundtrips_as_empty() -> void:
	# §营收 §1 注释: breakdown 是 snapshot, 月度覆盖; 起手为空.
	var snap: Dictionary = GameState.to_dict()
	GameState.reset()
	GameState.from_dict(snap)
	assert_true((GameState.last_revenue_breakdown as Dictionary).is_empty())

func test_staff_pool_roundtrip_preserves_role_keys() -> void:
	GameState.staff_pool[&"ml_eng"] = 5
	GameState.staff_pool[&"data_eng"] = 2
	GameState.staff_busy[&"ml_eng"] = 3
	var snap: Dictionary = GameState.to_dict()
	GameState.reset()
	GameState.from_dict(snap)
	assert_eq(int(GameState.staff_pool[&"ml_eng"]), 5)
	assert_eq(int(GameState.staff_pool[&"data_eng"]), 2)
	assert_eq(int(GameState.staff_busy[&"ml_eng"]), 3)

func test_from_dict_with_missing_unlocks_seeds_three_trees() -> void:
	# 旧档可能没有某棵树的键; from_dict 应保证三棵树键都在.
	var snap: Dictionary = GameState.to_dict()
	(snap.unlocks as Dictionary).erase("application")
	GameState.from_dict(snap)
	assert_true(GameState.unlocks.has(&"application"))

func test_from_dict_with_missing_staff_roles_fills_zero() -> void:
	# 同样保证 5 个 staff_role 都存在 (新增 role 时旧档不炸).
	var snap: Dictionary = GameState.to_dict()
	(snap.staff_pool as Dictionary).erase("ops")
	GameState.from_dict(snap)
	assert_true(GameState.staff_pool.has(&"ops"))
	assert_eq(int(GameState.staff_pool[&"ops"]), 0)

func test_save_version_constant_is_positive_integer() -> void:
	# §6.6: SAVE_VERSION 不能是 0/负数, 否则 incompatible_version 检测失效.
	assert_gt(GameState.SAVE_VERSION, 0)

func test_to_dict_syncs_rng_state_before_snapshot() -> void:
	# 文档要求: to_dict 先把 _rng.state 同步回 rng_state, 否则 read 后会
	# 重放被吃掉的随机数. 钉这个不变量.
	GameState.rng_seed = 99
	GameState._rng = null
	GameState.rng().randi()
	GameState.rng().randi()
	var live_state: int = GameState._rng.state
	var d: Dictionary = GameState.to_dict()
	assert_eq(int(d.rng_state), live_state)

# ---- 公司标志 / 创始人头像 (出身系统设计 §3) -----------------------------

func test_reset_clears_company_logo_and_founder_avatar() -> void:
	GameState.company_logo = &"gem_violet"
	GameState.founder_avatar = &"avatar-03"
	GameState.reset()
	assert_eq(GameState.company_logo, &"")
	assert_eq(GameState.founder_avatar, &"")

func test_company_logo_and_founder_avatar_roundtrip() -> void:
	GameState.company_logo = &"node_teal"
	GameState.founder_avatar = &"avatar-05"
	var snap: Dictionary = GameState.to_dict()
	GameState.reset()
	GameState.from_dict(snap)
	assert_eq(GameState.company_logo, &"node_teal")
	assert_eq(GameState.founder_avatar, &"avatar-05")

func test_legacy_save_without_logo_avatar_defaults_empty() -> void:
	# 旧档没有这俩 key → 回退空 (默认 A 标记 / 哈希肖像), 不破坏兼容。
	var snap: Dictionary = GameState.to_dict()
	snap.erase("company_logo")
	snap.erase("founder_avatar")
	GameState.from_dict(snap)
	assert_eq(GameState.company_logo, &"")
	assert_eq(GameState.founder_avatar, &"")
