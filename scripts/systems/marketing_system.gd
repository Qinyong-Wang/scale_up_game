extends Node

## MarketingSystem v7 PR-F3 (2026-05) — owns campaigns. Per
## design/营销系统设计.md.
##
## start_campaign / terminate_campaign; upkeep phase drains weekly_budget
## per active campaign, decrements remaining_weeks, ends naturally at 0.
## Campaigns lock onto a single Product via target_product_id; UserSystem's
## _marketing_attract matches by product.id, so re-binding the product to a
## different model keeps the subscribers pool intact.
##
## Orphan handling: in upkeep, before charging, scan campaigns and terminate
## any whose target product is gone (deleted). 当周不扣预算, 避免「花钱打空气」。


const OWNED_SLICES: Array[StringName] = [&"campaigns"]

# Table-driven, see design/营销系统设计.md §6. Authoritative source:
# resources/data/marketing/tuning.tres; assembled by _load_tables() at
# _ready into these vars (UPPERCASE for callsite stability).
const TUNING_PATH: String = "res://resources/data/marketing/tuning.tres"
# 营销活动占用的员工角色 (硬性要求 + 锁定, design/营销系统设计.md §4)。
const MARKETING_STAFF_ROLE: StringName = &"marketing"
var MAX_CONCURRENT_CAMPAIGNS: int = 5
# 员工需求随周预算缩放: clamp(min + floor(budget / budget_per_extra_staff), min, max)。
var MIN_STAFF_PER_CAMPAIGN: int = 2
var MAX_STAFF_PER_CAMPAIGN: int = 8
var BUDGET_PER_EXTRA_STAFF: int = 100000

var _next_campaign_seq: int = 1

func _ready() -> void:
	_load_tables()
	CommandBus.register(&"marketing.start_campaign", _on_start_campaign)
	CommandBus.register(&"marketing.terminate_campaign", _on_terminate_campaign)
	EventBus.phase_started.connect(_on_phase)
	EventBus.save_loaded.connect(_on_save_loaded)

func _gen_campaign_id() -> StringName:
	var id := StringName("campaign_%04d" % _next_campaign_seq)
	_next_campaign_seq += 1
	return id

## _next_campaign_seq 是会话计数器, 不入存档。读档后恢复它 + 修旧档已有的重复
## campaign ID, 否则读档后新建的营销活动会和档里的撞 ID。
## 详见 design/数据集系统设计.md §3 同类病。
func _on_save_loaded() -> void:
	_next_campaign_seq = maxi(_next_campaign_seq,
			GameState.max_seq_for_prefix([GameState.campaigns], "campaign_") + 1)
	for ch in GameState.dedup_ids([GameState.campaigns], _gen_campaign_id):
		Log.warn(&"marketing", "save_loaded_duplicate_campaign_id_repaired",
				{old_id = ch.old_id, new_id = ch.new_id})

func _load_tables() -> void:
	var t := load(TUNING_PATH)
	if t is MarketingTuning:
		MAX_CONCURRENT_CAMPAIGNS = int(t.max_concurrent_campaigns)
		MIN_STAFF_PER_CAMPAIGN = int(t.min_staff_per_campaign)
		MAX_STAFF_PER_CAMPAIGN = int(t.max_staff_per_campaign)
		BUDGET_PER_EXTRA_STAFF = int(t.budget_per_extra_staff)
	else:
		Log.warn(&"marketing", "tuning_missing", {path = TUNING_PATH})

## 营销活动所需营销员工数, 随周预算缩放, clamp 到 [min, max]。
## 公开给 NewCampaignDialog 复用 (展示需求 + 校验)。
func required_staff_for_budget(weekly_budget: int) -> int:
	var step: int = maxi(1, BUDGET_PER_EXTRA_STAFF)
	var extra: int = int(maxi(0, weekly_budget) / float(step))
	return clampi(MIN_STAFF_PER_CAMPAIGN + extra,
			MIN_STAFF_PER_CAMPAIGN, MAX_STAFF_PER_CAMPAIGN)

func _on_start_campaign(p: Dictionary) -> Dictionary:
	if GameState.campaigns.size() >= MAX_CONCURRENT_CAMPAIGNS:
		Log.warn(&"marketing", "too_many_campaigns", {
			active = GameState.campaigns.size(), cap = MAX_CONCURRENT_CAMPAIGNS,
		})
		return {ok = false, error = &"too_many_campaigns"}

	var lead_id: StringName = p.get(&"lead_id", &"")
	if lead_id != &"":
		var lead = HiringSystem.find_lead(lead_id)
		if lead == null:
			return {ok = false, error = &"unknown_lead"}
		if not HiringSystem.lead_matches_specialty(lead, &"marketing_lead"):
			return {ok = false, error = &"lead_specialty_mismatch"}
		# v8: 一个 marketing_lead 同一时刻只能带一个项目 — 必须 idle。
		if not lead.is_idle():
			return {ok = false, error = &"lead_busy"}

	# v7 PR-F3: target_product_id 必填 + 必须指向现存产品。
	var target_product_id: StringName = StringName(p.get(&"target_product_id", &""))
	if target_product_id == &"":
		return {ok = false, error = &"product_required"}
	if not _product_exists(target_product_id):
		return {ok = false, error = &"unknown_product"}

	# v8: 硬性要求营销员工, 数量随周预算缩放 (2..8)。启动前确认有足够空闲营销员工。
	var weekly_budget: int = int(p.get(&"weekly_budget", p.get(&"monthly_budget", 0)))
	var need_staff: int = required_staff_for_budget(weekly_budget)
	if need_staff > 0 and _idle_staff(MARKETING_STAFF_ROLE) < need_staff:
		Log.warn(&"marketing", "insufficient_staff", {
			role = MARKETING_STAFF_ROLE, need = need_staff,
			idle = _idle_staff(MARKETING_STAFF_ROLE),
		})
		return {ok = false, error = &"insufficient_staff"}

	var c := Campaign.new()
	c.id = _gen_campaign_id()
	c.display_name = p.get(&"display_name", "Campaign %s" % c.id)
	c.weekly_budget = weekly_budget
	c.total_weeks = int(p.get(&"total_weeks", p.get(&"total_months", 1)))
	c.remaining_weeks = c.total_weeks
	c.target_product_id = target_product_id
	c.lead_id = lead_id
	c.started_at_turn = GameState.turn

	# Lock lead (so it can't run a second campaign / a training task) then staff.
	# On any failure, roll back whatever we already locked and bail.
	if lead_id != &"":
		var lr: Dictionary = CommandBus.send(&"hiring.lock_lead", {
			lead_id = lead_id, task_id = c.id,
		})
		if not lr.ok:
			return {ok = false, error = &"lead_busy"}
	if need_staff > 0:
		var sr: Dictionary = CommandBus.send(&"hiring.lock_staff", {
			role = MARKETING_STAFF_ROLE, count = need_staff, holder_id = c.id,
		})
		if not sr.ok:
			if lead_id != &"":
				CommandBus.send(&"hiring.release_lead", {lead_id = lead_id, task_id = c.id})
			return {ok = false, error = &"insufficient_staff"}
		c.locked_staff = {MARKETING_STAFF_ROLE: need_staff}

	GameState.campaigns.append(c)
	Log.info(&"marketing", "campaign_started", {
		id = c.id, target_product_id = target_product_id,
		lead_id = lead_id, staff = c.locked_staff,
	})
	EventBus.campaign_started.emit(c.id)
	return {ok = true, campaign_id = c.id}

func _on_terminate_campaign(p: Dictionary) -> Dictionary:
	var c := _find(p.get(&"campaign_id", &""))
	if c == null:
		return {ok = false, error = &"unknown_campaign"}
	_release_campaign_resources(c)
	GameState.campaigns.erase(c)
	EventBus.campaign_terminated.emit(c.id, &"player_terminated")
	return {ok = true}

## 释放活动占用的 lead + 营销员工 (终止 / 自然结束 / 孤儿 都走这里)。幂等:
## 释放后清空登记, 重复调用不会二次释放。
func _release_campaign_resources(c: Campaign) -> void:
	if c.lead_id != &"":
		CommandBus.send(&"hiring.release_lead", {lead_id = c.lead_id, task_id = c.id})
	for role in c.locked_staff.keys():
		var count: int = int(c.locked_staff[role])
		if count > 0:
			CommandBus.send(&"hiring.release_staff", {role = role, count = count})
	c.locked_staff = {}

func _idle_staff(role: StringName) -> int:
	return int(GameState.staff_pool.get(role, 0)) - int(GameState.staff_busy.get(role, 0))

func _on_phase(phase: StringName, _turn: int) -> void:
	if phase != &"upkeep":
		return
	for c in GameState.campaigns.duplicate():
		# v7 PR-F3: orphan check — 没 target_product_id 或 product 不在了
		# → terminate 不扣预算。
		var target: StringName = c.target_product_id if "target_product_id" in c else &""
		if target == &"" or not _product_exists(target):
			Log.info(&"marketing", "campaign_orphan_terminate", {
				id = c.id, target_product_id = target,
			})
			_release_campaign_resources(c)
			GameState.campaigns.erase(c)
			EventBus.campaign_terminated.emit(c.id, &"target_product_gone")
			continue
		CommandBus.send(&"economy.spend", {
			cost = {&"cash": c.weekly_budget},
			reason = StringName("campaign:" + String(c.id)),
		})
		c.remaining_weeks -= 1
		EventBus.campaign_progress.emit(c.id, c.remaining_weeks, c.total_weeks)
		if c.remaining_weeks <= 0:
			_release_campaign_resources(c)
			GameState.campaigns.erase(c)
			EventBus.campaign_terminated.emit(c.id, &"finished_naturally")

func _find(id: StringName) -> Campaign:
	for c in GameState.campaigns:
		if c.id == id:
			return c
	return null

func _product_exists(product_id: StringName) -> bool:
	for p in GameState.products:
		if p.id == product_id:
			return true
	return false
