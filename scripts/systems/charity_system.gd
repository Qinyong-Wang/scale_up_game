extends Node

## CharitySystem — owns the charity_donated slice. Per design/慈善系统设计.md.
##
## Loads the CharityCauseSpec .tres files at _ready and exposes the current
## buff per effect_kind (mirror of FounderSystem). HiringSystem / EconomySystem
## / UserSystem call the accessors below at runtime; with no completed donation
## they return fully neutral values so the pre-charity game is unchanged.
##
## Donating is task-driven (design §5): `charity.start_donation` launches a
## `charity` TaskSystem task (which charges the donation up front + makes it
## tax-deductible that week); the buff does NOT apply until the task completes,
## at which point TaskSystem fans out to `charity.credit` here, crediting the
## amount and activating the (capped) tier bonus.

const CAUSE_PATHS: Dictionary = {
	&"bio_science":         "res://resources/data/charity/causes/bio_science.tres",
	&"fundamental_compute": "res://resources/data/charity/causes/fundamental_compute.tres",
	&"social_welfare":      "res://resources/data/charity/causes/social_welfare.tres",
}

## Display order used by the charity tab.
const CAUSE_ORDER: Array[StringName] = [
	&"bio_science", &"fundamental_compute", &"social_welfare",
]

## TaskSystem template that backs every charity donation.
const CHARITY_TEMPLATE_ID: StringName = &"charity_project"

## 完成第 i 档(0-based)→ 点亮第 i 枚慈善奖章 (办公室桌上, form=medal)。三档=铜/银/金,
## 顶档金牌即「全球慈善家」。与 causes 的 tier_amounts (3 档) 平行。Per 办公室与收藏系统设计.md §4。
const TIER_MEDALS: Array[StringName] = [
	&"charity_bronze", &"charity_silver", &"charity_global",
]

var _specs: Dictionary = {}   # id -> CharityCauseSpec

func _ready() -> void:
	_load_tables()
	CommandBus.register(&"charity.start_donation", _on_start_donation)
	CommandBus.register(&"charity.credit", _on_credit)

func _load_tables() -> void:
	_specs.clear()
	for id in CAUSE_PATHS.keys():
		var spec := load(CAUSE_PATHS[id])
		if spec is CharityCauseSpec:
			_specs[id] = spec
		else:
			Log.warn(&"charity", "cause_spec_missing", {id = id})

# ---- introspection ------------------------------------------------------

## All loaded cause specs in display order (skips any that failed to load).
func all_specs() -> Array:
	if _specs.is_empty():
		_load_tables()
	var out: Array = []
	for id in CAUSE_ORDER:
		if _specs.has(id):
			out.append(_specs[id])
	return out

func spec_for(cause_id: StringName) -> CharityCauseSpec:
	if _specs.is_empty():
		_load_tables()
	if _specs.has(cause_id):
		return _specs[cause_id]
	return null

## Completed cumulative donation for a cause (in-progress tasks not counted).
## Display / ledger only — the active tier is driven by tier_done().
func donated_for(cause_id: StringName) -> int:
	return int(GameState.charity_donated.get(cause_id, 0))

## Number of completed donation tiers for a cause (0..N). Sequential one-shot
## ladder: each tier is donated exactly once, in order. Source of truth for the
## active tier / buff.
func tier_done(cause_id: StringName) -> int:
	return int(GameState.charity_tier_done.get(cause_id, 0))

## Highest *completed* tier index (-1 when none completed). For UI + bonus lookup.
func current_tier_index(cause_id: StringName) -> int:
	var spec := spec_for(cause_id)
	if spec == null:
		return -1
	return mini(tier_done(cause_id), spec.tier_amounts.size()) - 1

## Index of the next donatable tier (= completed count), or -1 when all tiers
## are done / the cause is unknown.
func next_tier_index(cause_id: StringName) -> int:
	var spec := spec_for(cause_id)
	if spec == null:
		return -1
	var nxt: int = tier_done(cause_id)
	return nxt if nxt < spec.tier_amounts.size() else -1

## True when a charity task for this cause is currently in progress (one tier at
## a time per cause). Reads active_tasks (subtype=charity, payload cause_id).
func is_donating(cause_id: StringName) -> bool:
	for t in GameState.active_tasks:
		if t.subtype != &"charity":
			continue
		var pc: Dictionary = t.completion_payload
		var pc_cause: StringName = StringName(pc.get(&"cause_id", pc.get("cause_id", &"")))
		if pc_cause == cause_id:
			return true
	return false

## Active bonus magnitude for a cause (semantics per spec.effect_kind). 0.0 when
## no tier reached.
func current_bonus(cause_id: StringName) -> float:
	var spec := spec_for(cause_id)
	if spec == null:
		return 0.0
	var idx: int = current_tier_index(cause_id)
	if idx < 0 or idx >= spec.tier_bonuses.size():
		return 0.0
	return float(spec.tier_bonuses[idx])

# ---- accessors used by the game systems (mirror FounderSystem) ----------

func _bonus_by_effect(effect_kind: StringName) -> float:
	var total: float = 0.0
	for id in CAUSE_ORDER:
		var spec := spec_for(id)
		if spec != null and spec.effect_kind == effect_kind:
			total += current_bonus(id)
	return total

## HiringSystem: additive S-tier draw-weight bonus (stacks with founder origin).
func s_tier_weight_bonus() -> float:
	return _bonus_by_effect(&"s_tier_weight")

## EconomySystem: multiplier on valuation (1.0 = neutral).
func valuation_multiplier() -> float:
	return 1.0 + _bonus_by_effect(&"valuation_mult")

## UserSystem: multiplier on marketing conversion / attraction (1.0 = neutral).
func conversion_multiplier() -> float:
	return 1.0 + _bonus_by_effect(&"conversion_mult")

# ---- commands -----------------------------------------------------------

## charity.start_donation {cause_id, tier_index} — launch a charity task that
## charges the tier's donation up front and credits the cause on completion.
## Per design/慈善系统设计.md §5. Guards against donating into negative cash
## here (economy.spend itself allows negative balances, so the floor must be
## enforced before task.start).
func _on_start_donation(p: Dictionary) -> Dictionary:
	var cause_id: StringName = StringName(p.get(&"cause_id", &""))
	var spec := spec_for(cause_id)
	if spec == null:
		return {ok = false, error = &"cause_unknown"}
	var tier_index: int = int(p.get(&"tier_index", -1))
	if tier_index < 0 or tier_index >= spec.tier_amounts.size():
		return {ok = false, error = &"tier_invalid"}
	# Sequential one-shot ladder (design §5): must donate the next tier in order;
	# already-completed or higher tiers are locked, and one donation per cause at
	# a time.
	var nxt: int = next_tier_index(cause_id)
	if nxt < 0:
		return {ok = false, error = &"all_tiers_done"}
	if tier_index != nxt:
		return {ok = false, error = &"tier_out_of_order"}
	if is_donating(cause_id):
		return {ok = false, error = &"already_running"}
	var amount: int = int(spec.tier_amounts[tier_index])
	if amount > GameState.cash:
		return {ok = false, error = &"insufficient_cash"}
	var weeks: int = 1
	if tier_index < spec.tier_weeks.size():
		weeks = maxi(1, int(spec.tier_weeks[tier_index]))
	var r: Dictionary = CommandBus.send(&"task.start", {
		template_id = CHARITY_TEMPLATE_ID,
		cause_id = cause_id,
		amount = amount,
		weeks = weeks,
	})
	if not r.get(&"ok", false):
		return r
	Log.info(&"charity", "donation started", {
		cause = cause_id, tier = tier_index, amount = amount, weeks = weeks,
		task_id = r.get(&"task_id", &""),
	})
	return {ok = true, task_id = r.get(&"task_id", &""), amount = amount, weeks = weeks}

## charity.credit {cause_id, amount} — TaskSystem completion callback. Credits
## the donation to the cause's cumulative total; the buff activates here.
func _on_credit(p: Dictionary) -> Dictionary:
	# Payload keys may come back as String after a save/load mid-task.
	var cause_id: StringName = StringName(p.get(&"cause_id", p.get("cause_id", &"")))
	var amount: int = int(p.get(&"amount", p.get("amount", 0)))
	if cause_id == &"" or amount <= 0:
		return {ok = false, error = &"invalid_payload"}
	var cumulative: int = int(GameState.charity_donated.get(cause_id, 0)) + amount
	GameState.charity_donated[cause_id] = cumulative
	# Sequential ladder: each completed task advances exactly one tier.
	var done: int = int(GameState.charity_tier_done.get(cause_id, 0)) + 1
	GameState.charity_tier_done[cause_id] = done
	Log.info(&"charity", "donation credited", {
		cause = cause_id, amount = amount, cumulative = cumulative, tier_done = done,
	})
	EventBus.charity_completed.emit(cause_id, amount, cumulative)
	# 每完成一档 → 点亮该档对应的慈善奖章 (铜/银/金, 摆办公室桌上)。顶档金牌=「全球慈善家」。
	# 授予幂等: 首次完成某档(任一方向)即点亮, 之后再在别的方向完成同档不重复。Per §4。
	var completed_tier: int = done - 1  # 刚完成那一档的 0-based 序号
	if completed_tier >= 0 and completed_tier < TIER_MEDALS.size():
		CollectionSystem.award_trophy(TIER_MEDALS[completed_tier])
	return {ok = true, cumulative = cumulative, tier_done = done}
