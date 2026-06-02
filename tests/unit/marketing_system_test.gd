extends GutTest

## MarketingSystem — campaigns drain on upkeep, end naturally at 0, terminate
## if their target product disappears. Per design/营销系统设计.md.
## v7 PR-F3 (2026-05): campaign 锁 product (target_product_id 必填), 不再走
## target_product_types 的类型 fan-out。
## All values per-week (1 turn = 1 week).


func before_each() -> void:
	GameState.reset()
	# v8: campaigns hard-require + lock marketing staff. Seed a generous idle
	# pool so the existing start/cap tests can launch (cap test needs 5).
	GameState.staff_pool[&"marketing"] = 10

# ---- helpers -----------------------------------------------------------

func _make_product(id: StringName = &"p_chat", type: StringName = &"chatbot") -> Product:
	var p := Product.new()
	p.id = id
	p.type = type
	p.bound_model_id = &"m_test"
	p.subscription_price = 49
	p.subscribers = 0
	GameState.products.append(p)
	return p

func _start(target: StringName, extra: Dictionary = {}) -> Dictionary:
	var payload: Dictionary = {
		display_name = "Test",
		weekly_budget = 1000,
		total_weeks = 3,
		target_product_id = target,
	}
	for k in extra.keys():
		payload[k] = extra[k]
	return CommandBus.send(&"marketing.start_campaign", payload)

# Mirrors HiringSystem._pay_salaries: leads + staff_pool headcount × role salary.
# Upkeep charges this every week, so cash-delta tests must subtract it (the
# seeded marketing staff now incur salary).
func _weekly_salary() -> int:
	var total: int = 0
	for lead in GameState.leads:
		total += int(lead.weekly_salary)
	for role in GameState.staff_pool.keys():
		total += int(GameState.staff_pool[role]) * int(HiringSystem.SALARY_PER_ROLE.get(role, 0))
	return total

# ---- §2 start / terminate ----------------------------------------------

func test_start_campaign_without_target_product_returns_error() -> void:
	_make_product()
	var r: Dictionary = CommandBus.send(&"marketing.start_campaign", {
		display_name = "X", weekly_budget = 1000, total_weeks = 1})
	assert_false(r.ok)
	assert_eq(r.error, &"product_required")

func test_start_campaign_unknown_product_returns_error() -> void:
	_make_product(&"p1")
	var r: Dictionary = _start(&"p_nope")
	assert_false(r.ok)
	assert_eq(r.error, &"unknown_product")

func test_start_campaign_creates_active_campaign() -> void:
	var p := _make_product()
	var r: Dictionary = _start(p.id)
	assert_true(r.ok)
	assert_eq(GameState.campaigns.size(), 1)
	assert_eq(StringName(GameState.campaigns[0].target_product_id), p.id)

func test_terminate_unknown_returns_error() -> void:
	var r: Dictionary = CommandBus.send(&"marketing.terminate_campaign", {campaign_id = &"x"})
	assert_false(r.ok)
	assert_eq(r.error, &"unknown_campaign")

# ---- §5.1 upkeep --------------------------------------------------------

func test_upkeep_drains_weekly_budget() -> void:
	var p := _make_product()
	_start(p.id, {weekly_budget = 5000})
	var before: int = GameState.cash
	EventBus.phase_started.emit(&"upkeep", 1)
	assert_eq(GameState.cash, before - 5000 - _weekly_salary())

func test_campaign_finishes_after_total_weeks() -> void:
	var p := _make_product()
	_start(p.id, {total_weeks = 2})
	watch_signals(EventBus)
	EventBus.phase_started.emit(&"upkeep", 1)
	EventBus.phase_started.emit(&"upkeep", 2)
	assert_eq(GameState.campaigns.size(), 0)
	assert_signal_emitted(EventBus, "campaign_terminated")

# v7 PR-F3: 孤儿 campaign — target product 被删除时自动 terminate, 当周不扣预算。
func test_campaign_terminates_when_target_product_deleted() -> void:
	var p := _make_product(&"p_doomed")
	var r: Dictionary = _start(p.id)
	var cid: StringName = StringName(r.get(&"campaign_id", &""))
	# Delete the product (simulate player removing it).
	GameState.products.clear()
	watch_signals(EventBus)
	var before: int = GameState.cash
	EventBus.phase_started.emit(&"upkeep", 1)
	assert_eq(GameState.campaigns.size(), 0)
	assert_eq(GameState.cash, before - _weekly_salary(),
			"孤儿 campaign 当周不扣活动预算 (员工工资照付)")
	assert_signal_emitted_with_parameters(
			EventBus, "campaign_terminated",
			[cid, &"target_product_gone"])

# v7 PR-F3: 旧存档若没有 target_product_id, 启动时被 UserSystem / MarketingSystem
# 当孤儿对待 (无法找到匹配 product)。本测试覆盖 from_dict 路径不会崩。
func test_legacy_campaign_without_product_id_is_orphan() -> void:
	# 模拟旧存档: 直接装一个没 target_product_id 的 Campaign 到 state.
	var c := Campaign.new()
	c.id = &"legacy_c"
	c.display_name = "Old"
	c.weekly_budget = 1_000
	c.total_weeks = 3
	c.remaining_weeks = 3
	c.target_product_id = &""  # legacy
	c.target_product_types = [&"chatbot"] as Array[StringName]
	GameState.campaigns.append(c)
	# upkeep 扫到它发现没 target_product_id 应当 terminate。
	watch_signals(EventBus)
	EventBus.phase_started.emit(&"upkeep", 1)
	assert_eq(GameState.campaigns.size(), 0)
	assert_signal_emitted(EventBus, "campaign_terminated")

# ---- concurrent campaigns ---------------------------------------------

func test_two_concurrent_campaigns_both_drain_separately() -> void:
	var pa := _make_product(&"p_a", &"chatbot")
	var pb := _make_product(&"p_b", &"agent")
	_start(pa.id, {weekly_budget = 3000, total_weeks = 4})
	_start(pb.id, {weekly_budget = 7000, total_weeks = 4})
	var before: int = GameState.cash
	EventBus.phase_started.emit(&"upkeep", 1)
	assert_eq(GameState.cash, before - 10000 - _weekly_salary())

func test_two_concurrent_campaigns_finish_independently() -> void:
	var p := _make_product()
	_start(p.id, {display_name = "Short", total_weeks = 1})
	_start(p.id, {display_name = "Long", total_weeks = 3})
	EventBus.phase_started.emit(&"upkeep", 1)
	assert_eq(GameState.campaigns.size(), 1)
	assert_eq(GameState.campaigns[0].display_name, "Long")

# ---- design §2: campaign cap (5 concurrent) ----------------------

func test_start_campaign_at_cap_returns_error() -> void:
	var p := _make_product()
	for i in range(5):
		var r: Dictionary = _start(p.id, {display_name = "C%d" % i})
		assert_true(r.ok)
	assert_eq(GameState.campaigns.size(), 5)
	var blocked: Dictionary = _start(p.id, {display_name = "C6"})
	assert_false(blocked.ok)
	assert_eq(blocked.error, &"too_many_campaigns")

func test_terminating_under_cap_frees_slot() -> void:
	var p := _make_product()
	var ids: Array = []
	for i in range(5):
		var r: Dictionary = _start(p.id, {display_name = "C%d" % i})
		ids.append(r.campaign_id)
	CommandBus.send(&"marketing.terminate_campaign", {campaign_id = ids[0]})
	var ok: Dictionary = _start(p.id, {display_name = "C-new"})
	assert_true(ok.ok)

# ---- v8: staff requirement + lock --------------------------------------

func _make_marketing_lead(id: StringName = &"mkt_lead") -> Lead:
	var l := Lead.new()
	l.id = id
	l.specialty = &"marketing_lead"
	l.level = &"B"
	l.ability = 60.0
	GameState.leads.append(l)
	return l

func test_start_campaign_requires_marketing_staff() -> void:
	GameState.staff_pool[&"marketing"] = 0
	var p := _make_product()
	var r: Dictionary = _start(p.id)
	assert_false(r.ok)
	assert_eq(r.error, &"insufficient_staff")

func test_start_campaign_locks_and_releases_marketing_staff() -> void:
	# Min 2 staff per campaign. Seed exactly 2 → one small campaign uses them all.
	GameState.staff_pool[&"marketing"] = 2
	var p := _make_product()
	var r: Dictionary = _start(p.id)  # budget 1000 → required = min = 2
	assert_true(r.ok)
	assert_eq(int(GameState.staff_busy.get(&"marketing", 0)), 2,
			"small campaign should lock the minimum 2 marketing staff")
	# No idle marketing staff left → a second campaign is blocked.
	var blocked: Dictionary = _start(p.id)
	assert_false(blocked.ok)
	assert_eq(blocked.error, &"insufficient_staff")
	# Terminating frees the staff.
	CommandBus.send(&"marketing.terminate_campaign", {campaign_id = r.campaign_id})
	assert_eq(int(GameState.staff_busy.get(&"marketing", 0)), 0,
			"terminate should release the locked marketing staff")

func test_campaign_staff_scales_with_budget() -> void:
	# 2 at min budget, more as budget grows, capped at 8. Per design §4.
	assert_eq(MarketingSystem.required_staff_for_budget(1_000), 2, "tiny budget → floor 2")
	assert_eq(MarketingSystem.required_staff_for_budget(100_000), 3, "¥100k/wk → 3")
	assert_eq(MarketingSystem.required_staff_for_budget(300_000), 5, "¥300k/wk → 5")
	assert_eq(MarketingSystem.required_staff_for_budget(600_000), 8, "¥600k/wk → 8 (cap)")
	assert_eq(MarketingSystem.required_staff_for_budget(50_000_000), 8, "huge budget clamps at 8")
	# A big-budget campaign actually locks the scaled count.
	GameState.staff_pool[&"marketing"] = 8
	var p := _make_product()
	var r: Dictionary = _start(p.id, {weekly_budget = 600_000})
	assert_true(r.ok)
	assert_eq(int(GameState.staff_busy.get(&"marketing", 0)), 8,
			"¥600k/wk campaign should lock 8 marketing staff")

func test_marketing_lead_locked_to_one_campaign() -> void:
	var lead := _make_marketing_lead()
	var p := _make_product()
	var r: Dictionary = _start(p.id, {lead_id = lead.id})
	assert_true(r.ok)
	assert_false(lead.is_idle(), "lead should be locked while running a campaign")
	# Same lead can't run a second campaign.
	var blocked: Dictionary = _start(p.id, {lead_id = lead.id})
	assert_false(blocked.ok)
	assert_eq(blocked.error, &"lead_busy")
	# Terminating the first campaign frees the lead.
	CommandBus.send(&"marketing.terminate_campaign", {campaign_id = r.campaign_id})
	assert_true(lead.is_idle(), "lead should be idle again after campaign ends")

func test_campaign_natural_end_releases_lead_and_staff() -> void:
	GameState.staff_pool[&"marketing"] = 2
	var lead := _make_marketing_lead()
	var p := _make_product()
	var r: Dictionary = _start(p.id, {lead_id = lead.id, total_weeks = 1})
	assert_true(r.ok)
	EventBus.phase_started.emit(&"upkeep", 1)  # runs to 0 → finished naturally
	assert_eq(GameState.campaigns.size(), 0)
	assert_true(lead.is_idle(), "natural end should free the lead")
	assert_eq(int(GameState.staff_busy.get(&"marketing", 0)), 0,
			"natural end should free the marketing staff")

# ---- save_loaded: campaign ID 计数器恢复 + 重复修复 (读档撞 ID 防御) ----

func _seed_campaign(id: StringName) -> Campaign:
	var c := Campaign.new()
	c.id = id
	return c

func test_save_loaded_restores_campaign_id_counter() -> void:
	GameState.campaigns.append(_seed_campaign(&"campaign_0004"))
	EventBus.save_loaded.emit()
	var new_id := MarketingSystem._gen_campaign_id()
	assert_gt(String(new_id).trim_prefix("campaign_").to_int(), 4,
			"读档后新发的 campaign ID 不能复用 ≤0004 (实际 %s)" % new_id)

func test_save_loaded_repairs_duplicate_campaign_ids() -> void:
	GameState.campaigns.append(_seed_campaign(&"campaign_0001"))
	GameState.campaigns.append(_seed_campaign(&"campaign_0001"))
	EventBus.save_loaded.emit()
	var seen := {}
	for c in GameState.campaigns:
		assert_false(seen.has(c.id), "campaign id %s 读档后仍重复" % c.id)
		seen[c.id] = true

func test_save_loaded_retags_marketing_lead_lock_when_campaign_id_repaired() -> void:
	var first := _seed_campaign(&"campaign_0001")
	GameState.campaigns.append(first)
	var lead := _make_marketing_lead(&"lead_mkt_dup")
	lead.locked_by_task_id = &"campaign_0001"
	var duplicate := _seed_campaign(&"campaign_0001")
	duplicate.lead_id = lead.id
	GameState.campaigns.append(duplicate)

	EventBus.save_loaded.emit()

	assert_ne(duplicate.id, &"campaign_0001",
			"duplicate campaign should receive a fresh ID on load")
	assert_eq(lead.locked_by_task_id, duplicate.id,
			"lead lock holder should follow the repaired campaign ID")
	var r: Dictionary = CommandBus.send(&"marketing.terminate_campaign", {
			campaign_id = duplicate.id,
	})
	assert_true(r.ok)
	assert_true(lead.is_idle(),
			"terminating a repaired campaign should release its marketing lead")
