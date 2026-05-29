extends GutTest

## 慈善系统 — CharityCauseSpec / CharitySystem / GameState.charity_donated +
## task 驱动的捐助流程 + 三个系统钩子 (S 级权重 / 估值 / 营销转化率)。
## Per design/慈善系统设计.md.

func before_each() -> void:
	GameState.reset()

func after_each() -> void:
	GameState.reset()

# ---- spec + 访问器 (未捐助时全中性) ------------------------------------

func test_three_cause_specs_load() -> void:
	var ids: Array = []
	for s in CharitySystem.all_specs():
		ids.append(s.id)
	assert_eq(CharitySystem.all_specs().size(), 3)
	assert_true(ids.has(&"bio_science"))
	assert_true(ids.has(&"fundamental_compute"))
	assert_true(ids.has(&"social_welfare"))

func test_no_donation_is_fully_neutral() -> void:
	assert_eq(CharitySystem.s_tier_weight_bonus(), 0.0)
	assert_eq(CharitySystem.valuation_multiplier(), 1.0)
	assert_eq(CharitySystem.conversion_multiplier(), 1.0)

func test_unknown_cause_spec_is_null() -> void:
	assert_null(CharitySystem.spec_for(&"nonsense"))
	assert_eq(CharitySystem.current_tier_index(&"nonsense"), -1)
	assert_eq(CharitySystem.current_bonus(&"nonsense"), 0.0)

# ---- 取档逻辑 (按已完成档数, 顺序爬梯) ---------------------------------

func test_tier_lookup_by_tier_done() -> void:
	# bio_science 三档 bonus 0.02 / 0.05 / 0.08; 取档只看已完成档数 charity_tier_done。
	GameState.charity_tier_done[&"bio_science"] = 0
	assert_eq(CharitySystem.current_tier_index(&"bio_science"), -1)
	assert_eq(CharitySystem.current_bonus(&"bio_science"), 0.0)
	assert_eq(CharitySystem.next_tier_index(&"bio_science"), 0, "未完成任何档 → 下一可捐为第 0 档")
	GameState.charity_tier_done[&"bio_science"] = 1
	assert_eq(CharitySystem.current_tier_index(&"bio_science"), 0)
	assert_almost_eq(CharitySystem.current_bonus(&"bio_science"), 0.02, 0.0001)
	assert_eq(CharitySystem.next_tier_index(&"bio_science"), 1)
	GameState.charity_tier_done[&"bio_science"] = 2
	assert_eq(CharitySystem.current_tier_index(&"bio_science"), 1)
	assert_almost_eq(CharitySystem.current_bonus(&"bio_science"), 0.05, 0.0001)
	GameState.charity_tier_done[&"bio_science"] = 3
	assert_eq(CharitySystem.current_tier_index(&"bio_science"), 2, "三档全完成 → 封顶在最后一档")
	assert_almost_eq(CharitySystem.current_bonus(&"bio_science"), 0.08, 0.0001)
	assert_eq(CharitySystem.next_tier_index(&"bio_science"), -1, "全完成后无下一可捐档")

# ---- start_donation 校验 + 护栏 ----------------------------------------

func test_start_donation_rejects_unknown_cause() -> void:
	GameState.cash = 1_000_000_000
	var r: Dictionary = CommandBus.send(&"charity.start_donation",
			{cause_id = &"nonsense", tier_index = 0})
	assert_false(r.get(&"ok", false))
	assert_eq(r.get(&"error", &""), &"cause_unknown")

func test_start_donation_rejects_invalid_tier() -> void:
	GameState.cash = 1_000_000_000
	var r: Dictionary = CommandBus.send(&"charity.start_donation",
			{cause_id = &"bio_science", tier_index = 9})
	assert_false(r.get(&"ok", false))
	assert_eq(r.get(&"error", &""), &"tier_invalid")

func test_start_donation_blocks_donating_into_negative_cash() -> void:
	# 慈善是自愿支出, 不允许捐成负数 / 触发破产倒计时。
	GameState.cash = 5_000_000   # < 10M tier-0 amount
	var r: Dictionary = CommandBus.send(&"charity.start_donation",
			{cause_id = &"bio_science", tier_index = 0})
	assert_false(r.get(&"ok", false))
	assert_eq(r.get(&"error", &""), &"insufficient_cash")
	assert_eq(GameState.cash, 5_000_000, "拒绝后现金不变")
	assert_eq(GameState.active_tasks.size(), 0, "拒绝后不创建任务")

func test_start_donation_charges_up_front_but_does_not_credit_yet() -> void:
	GameState.cash = 1_000_000_000
	var r: Dictionary = CommandBus.send(&"charity.start_donation",
			{cause_id = &"bio_science", tier_index = 0})
	assert_true(r.get(&"ok", false))
	assert_eq(GameState.cash, 1_000_000_000 - 10_000_000, "启动当周一次性扣捐助额")
	assert_eq(GameState.active_tasks.size(), 1, "起了一个慈善任务")
	assert_eq(GameState.active_tasks[0].subtype, &"charity")
	# 进行中: 尚未推进档数 / 计入累计, 加成未生效。
	assert_eq(CharitySystem.tier_done(&"bio_science"), 0, "进行中不推进档数")
	assert_eq(CharitySystem.donated_for(&"bio_science"), 0)
	assert_eq(CharitySystem.s_tier_weight_bonus(), 0.0, "任务进行中加成不生效")

# ---- 顺序爬梯 + 每档一次 + 互斥 ----------------------------------------

func test_start_donation_must_follow_tier_order() -> void:
	# 未完成第 0 档 → 不能越级捐第 1 档。
	GameState.cash = 2_000_000_000
	var r: Dictionary = CommandBus.send(&"charity.start_donation",
			{cause_id = &"bio_science", tier_index = 1})
	assert_false(r.get(&"ok", false))
	assert_eq(r.get(&"error", &""), &"tier_out_of_order")
	assert_eq(GameState.active_tasks.size(), 0, "越级被拒, 不创建任务")
	# 捐第 0 档则可以。
	var r0: Dictionary = CommandBus.send(&"charity.start_donation",
			{cause_id = &"bio_science", tier_index = 0})
	assert_true(r0.get(&"ok", false))

func test_start_donation_rejects_already_completed_tier() -> void:
	# 第 0 档已完成 → 不能重捐第 0 档 (只能往上捐第 1 档)。
	GameState.cash = 2_000_000_000
	GameState.charity_tier_done[&"bio_science"] = 1
	var r: Dictionary = CommandBus.send(&"charity.start_donation",
			{cause_id = &"bio_science", tier_index = 0})
	assert_false(r.get(&"ok", false))
	assert_eq(r.get(&"error", &""), &"tier_out_of_order")

func test_start_donation_rejects_while_same_cause_running() -> void:
	# 同一方向一次只能进行一档捐助。
	GameState.cash = 2_000_000_000
	CommandBus.send(&"charity.start_donation", {cause_id = &"bio_science", tier_index = 0})
	var r: Dictionary = CommandBus.send(&"charity.start_donation",
			{cause_id = &"bio_science", tier_index = 0})
	assert_false(r.get(&"ok", false))
	assert_eq(r.get(&"error", &""), &"already_running")

func test_start_donation_rejects_when_all_tiers_done() -> void:
	GameState.cash = 2_000_000_000
	GameState.charity_tier_done[&"bio_science"] = 3
	var r: Dictionary = CommandBus.send(&"charity.start_donation",
			{cause_id = &"bio_science", tier_index = 2})
	assert_false(r.get(&"ok", false))
	assert_eq(r.get(&"error", &""), &"all_tiers_done")

# ---- 完成回调 charity.credit -------------------------------------------

func test_credit_advances_tier_and_emits_signal() -> void:
	watch_signals(EventBus)
	var r: Dictionary = CommandBus.send(&"charity.credit",
			{cause_id = &"bio_science", amount = 10_000_000})
	assert_true(r.get(&"ok", false))
	assert_eq(CharitySystem.tier_done(&"bio_science"), 1, "完成一档 → 档数 +1")
	assert_eq(CharitySystem.donated_for(&"bio_science"), 10_000_000)
	assert_signal_emitted(EventBus, "charity_completed")
	# 再完成一档: 档数 +1, 累计额累加, 当前档跳到第 1 档。
	CommandBus.send(&"charity.credit", {cause_id = &"bio_science", amount = 100_000_000})
	assert_eq(CharitySystem.tier_done(&"bio_science"), 2)
	assert_eq(CharitySystem.donated_for(&"bio_science"), 110_000_000)
	assert_eq(CharitySystem.current_tier_index(&"bio_science"), 1)

func test_credit_rejects_invalid_payload() -> void:
	var r: Dictionary = CommandBus.send(&"charity.credit",
			{cause_id = &"", amount = 0})
	assert_false(r.get(&"ok", false))

func test_reaching_global_tier_awards_charity_global_trophy() -> void:
	# 顺序爬完三档 (全球级顶档) → 点亮「全球慈善家」奖杯。
	CommandBus.send(&"charity.credit", {cause_id = &"bio_science", amount = 10_000_000})
	assert_false(CollectionSystem.is_trophy_earned(&"charity_global"), "完成一档不授奖")
	CommandBus.send(&"charity.credit", {cause_id = &"bio_science", amount = 100_000_000})
	CommandBus.send(&"charity.credit", {cause_id = &"bio_science", amount = 1_000_000_000})
	assert_eq(CharitySystem.current_tier_index(&"bio_science"), 2, "达到全球级顶档")
	assert_true(CollectionSystem.is_trophy_earned(&"charity_global"))

func test_below_global_tier_does_not_award_trophy() -> void:
	CommandBus.send(&"charity.credit", {cause_id = &"bio_science", amount = 10_000_000})
	assert_false(CollectionSystem.is_trophy_earned(&"charity_global"))

func test_each_tier_awards_its_medal() -> void:
	# 每完成一档点亮对应慈善奖章: 铜(首档)/银(二档)/金(顶档=全球慈善家)。
	CommandBus.send(&"charity.credit", {cause_id = &"bio_science", amount = 10_000_000})
	assert_true(CollectionSystem.is_trophy_earned(&"charity_bronze"), "完成首档 → 铜牌")
	assert_false(CollectionSystem.is_trophy_earned(&"charity_silver"))
	CommandBus.send(&"charity.credit", {cause_id = &"bio_science", amount = 100_000_000})
	assert_true(CollectionSystem.is_trophy_earned(&"charity_silver"), "完成二档 → 银牌")
	assert_false(CollectionSystem.is_trophy_earned(&"charity_global"))
	CommandBus.send(&"charity.credit", {cause_id = &"bio_science", amount = 1_000_000_000})
	assert_true(CollectionSystem.is_trophy_earned(&"charity_global"), "完成顶档 → 金牌")

# ---- 端到端: 捐助任务跑满 → 加成生效 -----------------------------------

func _drive_tasks_to_completion(max_iters: int = 80) -> void:
	# 直接推进 TaskSystem 的 action 相位 (charity_project error_rate=0, 确定性)。
	var i: int = 0
	while not GameState.active_tasks.is_empty() and i < max_iters:
		TaskSystem._on_phase(&"action", GameState.turn)
		i += 1

func test_donation_buff_activates_only_after_task_completes() -> void:
	watch_signals(EventBus)
	GameState.cash = 1_000_000_000
	var r: Dictionary = CommandBus.send(&"charity.start_donation",
			{cause_id = &"bio_science", tier_index = 0})
	assert_true(r.get(&"ok", false))
	assert_eq(CharitySystem.s_tier_weight_bonus(), 0.0, "进行中不生效")
	_drive_tasks_to_completion()
	assert_eq(GameState.active_tasks.size(), 0, "任务应已完成移除")
	assert_eq(CharitySystem.tier_done(&"bio_science"), 1, "完成一档")
	assert_eq(CharitySystem.donated_for(&"bio_science"), 10_000_000)
	assert_almost_eq(CharitySystem.s_tier_weight_bonus(), 0.02, 0.0001, "完成后加成生效")
	assert_signal_emitted(EventBus, "charity_completed")

func test_full_ladder_each_tier_runs_once_in_order() -> void:
	# 顺序爬三档, 每档跑满一次; 最终封顶 + 无法再启动。
	GameState.cash = 2_000_000_000
	for tier in range(3):
		var r: Dictionary = CommandBus.send(&"charity.start_donation",
				{cause_id = &"bio_science", tier_index = tier})
		assert_true(r.get(&"ok", false), "第 %d 档应可启动" % tier)
		# 进行中重复点同一档被拒。
		var dup: Dictionary = CommandBus.send(&"charity.start_donation",
				{cause_id = &"bio_science", tier_index = tier})
		assert_eq(dup.get(&"error", &""), &"already_running")
		_drive_tasks_to_completion()
		assert_eq(CharitySystem.tier_done(&"bio_science"), tier + 1)
	assert_almost_eq(CharitySystem.s_tier_weight_bonus(), 0.08, 0.0001, "三档完成封顶")
	# 全完成后无法再捐。
	var done: Dictionary = CommandBus.send(&"charity.start_donation",
			{cause_id = &"bio_science", tier_index = 2})
	assert_eq(done.get(&"error", &""), &"all_tiers_done")

# ---- 抵税: charity_donation 必须是可抵扣支出 ----------------------------

func test_charity_donation_reason_is_tax_deductible() -> void:
	# 全额可抵 (design §5): charity_donation 不得进不可抵名单。
	assert_false(EconomySystem.NON_TAXABLE_REASONS.has(&"charity_donation"),
			"慈善捐助必须可抵税, 不能划进 NON_TAXABLE_REASONS")

func test_donation_lands_in_weekly_ledger_expense() -> void:
	# 慈善单列为「慈善捐助」类目 (design §5), 不混进 task_start / 其他。
	GameState.cash = 1_000_000_000
	CommandBus.send(&"charity.start_donation",
			{cause_id = &"bio_science", tier_index = 0})
	var expense: Dictionary = GameState.weekly_ledger.get(&"expense", {})
	assert_true(expense.has("ECO_CAT_CHARITY"), "捐助应单列记入当周账本 expense")
	assert_eq(int(expense.get("ECO_CAT_CHARITY", 0)), 10_000_000)

# ---- GameState 序列化 --------------------------------------------------

func test_charity_state_round_trips_through_dict() -> void:
	GameState.charity_donated[&"social_welfare"] = 110_000_000
	GameState.charity_tier_done[&"social_welfare"] = 2
	GameState.charity_donated[&"bio_science"] = 10_000_000
	GameState.charity_tier_done[&"bio_science"] = 1
	var d: Dictionary = GameState.to_dict()
	GameState.reset()
	assert_eq(CharitySystem.tier_done(&"social_welfare"), 0, "reset 清空")
	GameState.from_dict(d)
	assert_eq(CharitySystem.donated_for(&"social_welfare"), 110_000_000)
	assert_eq(CharitySystem.tier_done(&"social_welfare"), 2)
	assert_eq(CharitySystem.current_tier_index(&"social_welfare"), 1)
	assert_eq(CharitySystem.tier_done(&"bio_science"), 1)

func test_legacy_save_without_charity_key_defaults_empty() -> void:
	GameState.from_dict({turn = 3})
	assert_eq(CharitySystem.donated_for(&"bio_science"), 0)
	assert_eq(CharitySystem.tier_done(&"bio_science"), 0)
	assert_eq(CharitySystem.s_tier_weight_bonus(), 0.0)

# ---- 经济钩子: 估值乘子 ------------------------------------------------

func test_fundamental_compute_lifts_valuation() -> void:
	GameState.cash = 1_000_000_000
	var base_v: int = EconomySystem._compute_valuation()
	# 直接 credit (不走 task) 以隔离现金支出对估值的影响。
	CommandBus.send(&"charity.credit",
			{cause_id = &"fundamental_compute", amount = 10_000_000})
	assert_almost_eq(CharitySystem.valuation_multiplier(), 1.01, 0.0001)
	var new_v: int = EconomySystem._compute_valuation()
	assert_eq(new_v, int(round(float(base_v) * 1.01)), "估值应乘 +1% 封顶系数")

# ---- 用户钩子: 营销转化率 ----------------------------------------------

func _run_growth(credit_social_welfare: bool) -> int:
	GameState.reset()
	if credit_social_welfare:
		CommandBus.send(&"charity.credit",
				{cause_id = &"social_welfare", amount = 10_000_000})
	var m := Model.new()
	m.id = &"m1"
	m.arch = &"ant_v1"
	m.status = &"published"
	GameState.models.append(m)
	var prod := Product.new()
	prod.id = &"p1"
	prod.type = &"chatbot"
	prod.bound_model_id = &"m1"
	prod.subscribers = 0
	GameState.products.append(prod)
	var c := Campaign.new()
	c.id = &"c1"
	c.target_product_id = &"p1"
	c.weekly_budget = 100_000
	c.remaining_weeks = 4
	c.total_weeks = 4
	GameState.campaigns.append(c)
	CommandBus.send(&"user.recompute_now", {})
	return prod.subscribers

func test_social_welfare_lifts_marketing_conversion() -> void:
	var base: int = _run_growth(false)
	var boosted: int = _run_growth(true)
	assert_gt(base, 0, "营销预算应带来基础拉新")
	assert_gt(boosted, base, "失业援助捐助应抬高营销转化")

# ---- 招聘钩子: S 级权重 ------------------------------------------------

func _count_s_draws(draws: int, cash: int) -> int:
	GameState.rng_seed = 12345
	GameState.rng_state = 0
	GameState._rng = null
	var n: int = 0
	for i in range(draws):
		if HiringSystem._draw_level(cash) == &"S":
			n += 1
	return n

func test_bio_science_lifts_s_tier_draw_rate() -> void:
	# 低现金段基础 S 权重为 0 → 未捐助永远抽不到 S; 捐生物科学后能抽到。
	var base_s: int = _count_s_draws(200, 80_000)
	CommandBus.send(&"charity.credit",
			{cause_id = &"bio_science", amount = 10_000_000})
	var donated_s: int = _count_s_draws(200, 80_000)
	assert_eq(base_s, 0, "未捐助在低现金段不应抽到 S")
	assert_gt(donated_s, 0, "捐生物科学基金后应能在低现金段抽到 S")
