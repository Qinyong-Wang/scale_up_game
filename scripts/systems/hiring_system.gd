extends Node

## HiringSystem v1 — owns leads / lead_pool / staff_pool / staff_busy.
## Per design/招聘系统设计.md.
##
## Two-layer talent: named `Lead` (tri-state mutex idle/locked/assigned) +
## aggregate `staff_pool` (with parallel `staff_busy` for current locks).
## Weekly upkeep pays salaries; action phase refreshes the candidate pool.


const OWNED_SLICES: Array[StringName] = [
	&"leads", &"lead_pool", &"staff_pool", &"staff_busy",
]

## Per design/招聘系统设计.md §1.1 (also 公共枚举表 §2):
## 6 specialties, two of them (ml_research_lead / eval_lead) added to
## carve up the previously-overloaded chief_scientist role.
const SPECIALTIES: Array[StringName] = [
	&"chief_scientist",
	&"ml_research_lead",
	&"eval_lead",
	&"chief_engineer",
	&"data_scientist",
	&"marketing_lead",
]

## Paths to the data tables. Per design/招聘系统设计.md §7 + 平衡参数.md
## §HiringSystem the numeric source-of-truth is the .tres files; the
## dict/int fields below are runtime caches assembled at _ready.
const LEAD_LEVEL_PATHS: Dictionary = {
	&"S": "res://resources/data/hiring/lead_levels/s.tres",
	&"A": "res://resources/data/hiring/lead_levels/a.tres",
	&"B": "res://resources/data/hiring/lead_levels/b.tres",
	&"C": "res://resources/data/hiring/lead_levels/c.tres",
}
const STAFF_ROLE_PATHS: Dictionary = {
	&"ml_eng": "res://resources/data/hiring/staff_salaries/ml_eng.tres",
	&"infra_eng": "res://resources/data/hiring/staff_salaries/infra_eng.tres",
	&"data_eng": "res://resources/data/hiring/staff_salaries/data_eng.tres",
	&"marketing": "res://resources/data/hiring/staff_salaries/marketing.tres",
	&"ops": "res://resources/data/hiring/staff_salaries/ops.tres",
}
const LEAD_BONUS_PATHS: Dictionary = {
	&"chief_scientist": "res://resources/data/hiring/lead_bonus/chief_scientist.tres",
	&"ml_research_lead": "res://resources/data/hiring/lead_bonus/ml_research_lead.tres",
	&"eval_lead": "res://resources/data/hiring/lead_bonus/eval_lead.tres",
	&"chief_engineer": "res://resources/data/hiring/lead_bonus/chief_engineer.tres",
	&"data_scientist": "res://resources/data/hiring/lead_bonus/data_scientist.tres",
	&"marketing_lead": "res://resources/data/hiring/lead_bonus/marketing_lead.tres",
}
const POOL_CONFIG_PATH: String = "res://resources/data/hiring/pool_config.tres"

## Runtime caches populated from .tres in _load_tables() (called from
## _ready and lazily from any reader if the autoload hasn't run yet).
## Shape: { specialty: { bonus_key: coef_float } }.
##   *_speed keys are consumed by lead_speedup_for() (multiplicative speedup).
##   *_add keys are flat additive bonuses applied by their owning system.
##   evaluate_score_bonus / product_throughput / data_quality_add /
##   campaign_efficiency are used by Task / Product / Marketing systems and
##   are not part of lead_speedup_for()'s mapping.
var LEAD_BONUS_TABLE: Dictionary = {}
var SALARY_PER_ROLE: Dictionary = {}
var LEAD_POOL_BASE_SIZE: int = 0
var _lead_level_specs: Dictionary = {}   # &"S" -> LeadLevelSpec
var _pool_config: LeadPoolConfig = null

## task subtype -> bonus key in LEAD_BONUS_TABLE that grants a multiplicative
## speedup. Subtypes not in this map (or whose lookup misses) yield 1.0.
const _TASK_SUBTYPE_TO_SPEED_KEY: Dictionary = {
	&"pretrain": &"pretrain_speed",
	&"posttrain": &"posttrain_speed",
	&"evaluate": &"evaluate_speed",
	&"data_collection": &"data_collection_speed",
	&"tech_research": &"research_speed",
}

## Lead pool refreshes every 4 weeks. Per design/招聘系统设计.md §4.1.
## Offset gate `(turn - 1) % N == 0` so the very first action phase (turn=1)
## seeds the pool — players get candidates from week 1 instead of waiting.
const LEAD_POOL_REFRESH_INTERVAL_WEEKS: int = 4

var _next_lead_seq: int = 1

## 取名规则: **名跟随肖像**。lead 的头像是多元肖像池, 名字按头像的族裔/性别走对应
## 名库 (中文 / 英文 / 西语 / …), 否则白人的脸配 "王美丽" → 出戏。见 design/招聘系统设计.md §1.3。
## 肖像族裔/性别表权威源在 IconRegistry; 名库在 PersonName。与 GameState.rng() 一起用,
## 同 seed 下名字稳定 (肖像索引是纯哈希, 取名只多 2 次 rng 抽取) → 测试可重现。
func _gen_name_for_id(id: StringName) -> String:
	var demo: Dictionary = IconRegistry.lead_demographics(id)
	var region: StringName = demo.get(&"region", &"east_asian")
	var gender: StringName = demo.get(&"gender", &"female")
	return PersonName.generate(region, gender, GameState.rng())

func _ready() -> void:
	_load_tables()
	CommandBus.register(&"hiring.hire_lead", _on_hire_lead)
	CommandBus.register(&"hiring.fire_lead", _on_fire_lead)
	CommandBus.register(&"hiring.adjust_staff", _on_adjust_staff)
	CommandBus.register(&"hiring.lock_lead", _on_lock_lead)
	CommandBus.register(&"hiring.release_lead", _on_release_lead)
	CommandBus.register(&"hiring.assign_lead", _on_assign_lead)
	CommandBus.register(&"hiring.unassign_lead", _on_unassign_lead)
	CommandBus.register(&"hiring.lock_staff", _on_lock_staff)
	CommandBus.register(&"hiring.release_staff", _on_release_staff)
	CommandBus.register(&"hiring.create_player_scientist", _on_create_player_scientist)
	EventBus.phase_started.connect(_on_phase)
	EventBus.save_loaded.connect(_on_save_loaded)

# ---- hire / fire --------------------------------------------------------

func _on_hire_lead(p: Dictionary) -> Dictionary:
	var pool_id: StringName = p.get(&"pool_lead_id", &"")
	var lead: Lead = _find_in_pool(pool_id)
	if lead == null:
		return {ok = false, error = &"unknown_pool_lead"}
	GameState.lead_pool.erase(lead)
	GameState.leads.append(lead)
	CommandBus.send(&"economy.spend", {
		cost = {&"cash": lead.signing_fee},
		reason = &"hire_lead",
	})
	Log.info(&"hiring", "lead_hired", {lead_id = lead.id, fee = lead.signing_fee})
	EventBus.lead_hired.emit(lead.id)
	return {ok = true, lead_id = lead.id}

func _on_fire_lead(p: Dictionary) -> Dictionary:
	var lead_id: StringName = p.get(&"lead_id", &"")
	var lead := find_lead(lead_id)
	if lead == null:
		return {ok = false, error = &"unknown_lead"}
	if lead.is_player_scientist:
		# Founder-as-scientist is unfireable. Per design/招聘系统设计.md §2 约定.
		return {ok = false, error = &"player_scientist_unfireable"}
	if not lead.is_idle():
		return {ok = false, error = &"lead_busy"}
	GameState.leads.erase(lead)
	Log.info(&"hiring", "lead_fired", {lead_id = lead_id})
	EventBus.lead_fired.emit(lead_id)
	return {ok = true}

# ---- player scientist ---------------------------------------------------

## Adds a "founder-as-scientist" Lead to GameState.leads (skipping the pool
## and hire flow). One per save. No signing fee, no salary, no equity grant
## (founder already owns the equity). Per design/招聘系统设计.md §2.
##
## 2026-05 rev: specialty input is **ignored** (kept on signature for
## back-compat). The founder is a universal lead — specialty is fixed to
## &"founder" so that every legacy `lead.specialty == &"X"` bonus read
## naturally fails (returns no bonus), while `lead_matches_specialty` /
## the validation helpers special-case `is_player_scientist` to pass any gate.
func _on_create_player_scientist(p: Dictionary) -> Dictionary:
	var specialty_in: StringName = p.get(&"specialty", &"")
	if specialty_in != &"" and specialty_in != &"founder" and not SPECIALTIES.has(specialty_in):
		return {ok = false, error = &"unknown_specialty"}
	for l in GameState.leads:
		if l.is_player_scientist:
			return {ok = false, error = &"already_created"}
	var ability: float = float(p.get(&"ability", 0.0))
	ability = clamp(ability, 0.0, 100.0)
	var display_name: String = String(p.get(&"display_name", "")).strip_edges()
	if display_name == "":
		display_name = "创始人"
	var lead := Lead.new()
	lead.id = &"player_self"
	lead.display_name = display_name
	lead.specialty = &"founder"
	lead.level = &"founder"
	lead.ability = ability
	lead.signing_fee = 0
	lead.weekly_salary = 0
	lead.is_player_scientist = true
	# 创始人头像: 显式 avatar_id 参数优先, 否则取新游戏选的 GameState.founder_avatar。
	# 见 design/出身系统设计.md §3。
	var avatar_in: StringName = p.get(&"avatar_id", &"")
	lead.avatar_id = avatar_in if avatar_in != &"" else GameState.founder_avatar
	GameState.leads.append(lead)
	Log.info(&"hiring", "player_scientist_created",
			{lead_id = lead.id, ability = ability, avatar = lead.avatar_id})
	EventBus.player_scientist_created.emit(lead.id)
	return {ok = true, lead_id = lead.id}

# ---- staff --------------------------------------------------------------

func _on_adjust_staff(p: Dictionary) -> Dictionary:
	var role: StringName = p.get(&"role", &"")
	var delta: int = int(p.get(&"delta", 0))
	if not GameState.staff_pool.has(role):
		return {ok = false, error = &"unknown_role"}
	var current: int = int(GameState.staff_pool[role])
	var new_count: int = current + delta
	if new_count < 0:
		return {ok = false, error = &"would_go_negative"}
	if delta < 0 and new_count < int(GameState.staff_busy.get(role, 0)):
		return {ok = false, error = &"would_fire_busy"}
	GameState.staff_pool[role] = new_count
	if delta > 0:
		# Charge first week's salary up-front (1 turn = 1 week).
		var salary: int = delta * int(SALARY_PER_ROLE.get(role, 0))
		CommandBus.send(&"economy.spend", {
			cost = {&"cash": salary},
			reason = &"hire_staff",
		})
	Log.info(&"hiring", "staff_changed", {role = role, new_count = new_count})
	EventBus.staff_changed.emit(role, new_count)
	return {ok = true, new_count = new_count}

# ---- lead lock / release (TaskSystem) -----------------------------------

func _on_lock_lead(p: Dictionary) -> Dictionary:
	var lead_id: StringName = p.get(&"lead_id", &"")
	var task_id: StringName = p.get(&"task_id", &"")
	var lead := find_lead(lead_id)
	if lead == null:
		return {ok = false, error = &"unknown_lead"}
	if lead.locked_by_task_id != &"":
		return {ok = false, error = &"already_locked"}
	if lead.assigned_to_product_id != &"":
		return {ok = false, error = &"already_assigned"}
	lead.locked_by_task_id = task_id
	EventBus.lead_locked.emit(lead_id, task_id)
	return {ok = true}

func _on_release_lead(p: Dictionary) -> Dictionary:
	var lead_id: StringName = p.get(&"lead_id", &"")
	var task_id: StringName = p.get(&"task_id", &"")
	var lead := find_lead(lead_id)
	if lead == null:
		return {ok = false, error = &"unknown_lead"}
	if lead.locked_by_task_id != task_id:
		return {ok = false, error = &"not_locked_by_this_task"}
	lead.locked_by_task_id = &""
	EventBus.lead_released.emit(lead_id)
	return {ok = true}

# ---- lead assign / unassign (ProductSystem) -----------------------------

func _on_assign_lead(p: Dictionary) -> Dictionary:
	var lead_id: StringName = p.get(&"lead_id", &"")
	var product_id: StringName = p.get(&"product_id", &"")
	var lead := find_lead(lead_id)
	if lead == null:
		return {ok = false, error = &"unknown_lead"}
	if lead.locked_by_task_id != &"":
		return {ok = false, error = &"already_locked"}
	if lead.assigned_to_product_id != &"":
		return {ok = false, error = &"already_assigned"}
	lead.assigned_to_product_id = product_id
	EventBus.lead_assigned.emit(lead_id, product_id)
	return {ok = true}

func _on_unassign_lead(p: Dictionary) -> Dictionary:
	var lead_id: StringName = p.get(&"lead_id", &"")
	var lead := find_lead(lead_id)
	if lead == null:
		return {ok = false, error = &"unknown_lead"}
	if lead.assigned_to_product_id == &"":
		return {ok = false, error = &"not_assigned"}
	lead.assigned_to_product_id = &""
	EventBus.lead_unassigned.emit(lead_id)
	return {ok = true}

# ---- staff lock / release -----------------------------------------------

func _on_lock_staff(p: Dictionary) -> Dictionary:
	var role: StringName = p.get(&"role", &"")
	var count: int = int(p.get(&"count", 0))
	if not GameState.staff_pool.has(role):
		return {ok = false, error = &"unknown_role"}
	var idle: int = int(GameState.staff_pool[role]) - int(GameState.staff_busy.get(role, 0))
	if count > idle:
		return {ok = false, error = &"insufficient_idle"}
	GameState.staff_busy[role] = int(GameState.staff_busy.get(role, 0)) + count
	return {ok = true}

func _on_release_staff(p: Dictionary) -> Dictionary:
	var role: StringName = p.get(&"role", &"")
	var count: int = int(p.get(&"count", 0))
	if not GameState.staff_busy.has(role):
		return {ok = false, error = &"unknown_role"}
	var current: int = int(GameState.staff_busy[role])
	if count > current:
		return {ok = false, error = &"over_release"}
	GameState.staff_busy[role] = current - count
	return {ok = true}

# ---- phase hooks --------------------------------------------------------

func _on_phase(phase: StringName, turn: int) -> void:
	match phase:
		&"upkeep":
			_pay_salaries()
		&"action":
			# 老存档 / 老会话里 display_name 形如 "Lead 0001" 的 lead 重命名成真名 (按肖像族裔/性别)。
			# 幂等且 O(N): 推回合时跑一次, 旧 lead 在 1 周内拿到名字, 不需要 save+load。
			_migrate_legacy_lead_names()
			# Refresh every 4 weeks, with offset so
			# turn=1 (the very first action phase) seeds the pool.
			if turn >= 1 and (turn - 1) % LEAD_POOL_REFRESH_INTERVAL_WEEKS == 0:
				_refresh_lead_pool()

func _pay_salaries() -> void:
	var total: int = 0
	for lead in GameState.leads:
		total += int(lead.weekly_salary)
	for role in GameState.staff_pool.keys():
		total += int(GameState.staff_pool[role]) * int(SALARY_PER_ROLE.get(role, 0))
	if total > 0:
		CommandBus.send(&"economy.spend", {
			cost = {&"cash": total},
			reason = &"salaries",
		})

func _refresh_lead_pool() -> void:
	GameState.lead_pool.clear()
	for i in range(LEAD_POOL_BASE_SIZE):
		# v7 PR-F: fame field deleted; pass 0 to satisfy the legacy 2nd arg.
		var level: StringName = _draw_level(GameState.cash, 0.0)
		var specialty: StringName = SPECIALTIES[GameState.rng().randi_range(0, SPECIALTIES.size() - 1)]
		GameState.lead_pool.append(_gen_lead(level, specialty))
	EventBus.lead_pool_refreshed.emit(GameState.lead_pool.duplicate())

# ---- helpers ------------------------------------------------------------

func find_lead(lead_id: StringName) -> Lead:
	for l in GameState.leads:
		if l.id == lead_id:
			return l
	return null

func _find_in_pool(pool_id: StringName) -> Lead:
	for l in GameState.lead_pool:
		if l.id == pool_id:
			return l
	return null

## v7 PR-F (2026-05): cash drives S/A/B/C draw probability (fame deleted).
## Brackets are scanned in descending cash_min order; the first whose
## cash_min ≤ GameState.cash wins. Below the lowest bracket, the last
## entry (typically a C-heavy distribution) applies.
func _draw_level(cash: int, _legacy_fame: float = 0.0) -> StringName:
	if _pool_config == null:
		_load_tables()
	var roll: float = GameState.rng().randf()
	var cash_brackets: Array = _sorted_cash_brackets()
	if cash_brackets.is_empty():
		return &"C"
	for b in cash_brackets:
		if cash >= int(b.get("cash_min", 0)):
			return _pick_level(_origin_adjusted_weights(b.get("weights", {})), roll)
	# Cash below every bracket → use the lowest one.
	return _pick_level(_origin_adjusted_weights(
			cash_brackets[cash_brackets.size() - 1].get("weights", {})), roll)

## Applies the founder origin's + charity's additive S-tier bonus to a cash
## bracket's level weights, then renormalizes the four levels to sum 1.0. Per
## design/出身系统设计.md §4.1 / §5 + 慈善系统设计.md §6 (生物科学基金). Returns
## the weights untouched when the combined bonus is 0 (no origin/charity) so
## behaviour is bit-for-bit unchanged.
func _origin_adjusted_weights(weights: Dictionary) -> Dictionary:
	var bonus: float = FounderSystem.s_tier_weight_bonus() + CharitySystem.s_tier_weight_bonus()
	if is_zero_approx(bonus):
		return weights
	var w: Dictionary = weights.duplicate()
	w[&"S"] = maxf(0.0, float(w.get(&"S", 0.0)) + bonus)
	var total: float = 0.0
	for k in [&"S", &"A", &"B", &"C"]:
		total += float(w.get(k, 0.0))
	if total > 0.0:
		for k in [&"S", &"A", &"B", &"C"]:
			w[k] = float(w.get(k, 0.0)) / total
	return w

# Back-compat shim for callers (tests) that hard-coded the old fame path.
func _draw_level_by_fame(_fame: float) -> StringName:
	return _draw_level(GameState.cash)

func _sorted_cash_brackets() -> Array:
	var raw: Array = []
	if _pool_config != null and "cash_brackets" in _pool_config:
		raw = (_pool_config.cash_brackets as Array).duplicate()
	raw.sort_custom(func(a, b): return int(a.get("cash_min", 0)) > int(b.get("cash_min", 0)))
	return raw

func _pick_level(weights: Dictionary, roll: float) -> StringName:
	var order: Array[StringName] = [&"S", &"A", &"B", &"C"]
	var cum: float = 0.0
	for lvl in order:
		cum += float(weights.get(lvl, 0.0))
		if roll < cum:
			return lvl
	return &"C"

## Returns the multiplicative time-saving speedup a `lead` provides on a task
## of subtype `task_subtype` (see _TASK_SUBTYPE_TO_SPEED_KEY).
##   speedup = 1.0 + (lead.ability / 100.0) * coef
## If the lead's specialty lacks a matching `*_speed` bonus, returns 1.0.
## Returns 1.0 for null lead or unknown subtype. Callers treat this as a
## divisor on remaining-work weeks (higher = faster). Per design/平衡参数.md
## §HiringSystem and 任务系统设计 §6.6.4.
##
## Per 招聘系统设计 §2 (2026-05 rev): player_scientist 是"万能 lead", 任意 specialty
## 校验都通行但**不提供任何 bonus**, 所以这里强制返回 1.0。
func lead_speedup_for(lead, task_subtype: StringName) -> float:
	if lead == null:
		return 1.0
	if lead.is_player_scientist:
		return 1.0
	var speed_key = _TASK_SUBTYPE_TO_SPEED_KEY.get(task_subtype, null)
	if speed_key == null:
		return 1.0
	var bonuses = LEAD_BONUS_TABLE.get(lead.specialty, null)
	if bonuses == null:
		return 1.0
	if not bonuses.has(speed_key):
		return 1.0
	var coef: float = float(bonuses[speed_key])
	var ability: float = float(lead.ability)
	return 1.0 + (ability / 100.0) * coef

## Specialty 匹配统一入口: lead 是 player_scientist (万能) 或 specialty 严格相等 → true.
## Per 招聘系统设计 §2 / §5.4 (2026-05 rev).
func lead_matches_specialty(lead, needs: StringName) -> bool:
	if lead == null:
		return false
	if lead.is_player_scientist:
		return true
	return lead.specialty == needs

## 读 LEAD_BONUS_TABLE 的一个 bonus 系数 (含 ability scaling). 对 player_scientist 总是
## 返回 0, 让调用方"取 bonus, 把它加到结果上"的写法对玩家直接退化为无加成。
## 例: monetization_system / infra_system / user_system / task_system 都用这个。
func lead_bonus_coef(lead, key: StringName) -> float:
	if lead == null or lead.is_player_scientist:
		return 0.0
	var bonuses = LEAD_BONUS_TABLE.get(lead.specialty, null)
	if bonuses == null:
		return 0.0
	return float(bonuses.get(key, 0.0))

## 把一个 `*_score_bonus` 系数算成分数倍率 `1 + ability/100 × coef` (区别于
## lead_speedup_for 的时长倍率)。null / player_scientist / 缺该 key → 1.0 (无加成)。
## 供 TaskSystem (pretrain) / ResearchSystem (posttrain) / PosttrainDialog 共用,
## 保证预览与结算一致。Per 招聘系统设计.md §5.1 + 平衡参数.md §LEAD_BONUS。
func lead_score_mult(lead, bonus_key: StringName) -> float:
	var coef: float = lead_bonus_coef(lead, bonus_key)
	if coef <= 0.0:
		return 1.0
	return 1.0 + (float(lead.ability) / 100.0) * coef

func _gen_lead_id() -> StringName:
	var id := StringName("lead_%04d" % _next_lead_seq)
	_next_lead_seq += 1
	return id

## _next_lead_seq 是会话计数器, 不入存档。读档后恢复它跳过档内已用编号, 再修
## 旧档已有的重复 lead ID — 否则读档后新雇的 lead 会和档里的撞 ID, find 取首个
## → 锁定 / 派单解析到错的人。详见 design/数据集系统设计.md §3 同类病。
func _on_save_loaded() -> void:
	_next_lead_seq = maxi(_next_lead_seq, GameState.max_seq_for_prefix(
			[GameState.leads, GameState.lead_pool], "lead_") + 1)
	for ch in GameState.dedup_ids([GameState.leads, GameState.lead_pool], _gen_lead_id):
		# 被重发 ID 的副本是 find 取不到的影子, 其上的锁是死锁, 清掉。
		ch.obj.locked_by_task_id = &""
		ch.obj.assigned_to_product_id = &""
		Log.warn(&"hiring", "save_loaded_duplicate_lead_id_repaired",
				{old_id = ch.old_id, new_id = ch.new_id})
	_migrate_legacy_lead_names()

## 把旧档 / 旧会话里 display_name 形如 "Lead 0001" 或 "" 的 lead 重命名成真名 (按肖像族裔/性别)。
## founder (is_player_scientist) / debug_* 名字保留 — 玩家定的名字 / debug 标识。
## 幂等: 已是真名的 lead 不会被换 (生成名永不形如 "Lead <数字>")。
func _migrate_legacy_lead_names() -> void:
	var renamed_count: int = 0
	for arr in [GameState.leads, GameState.lead_pool]:
		for l in arr:
			if l == null:
				continue
			if l.is_player_scientist:
				continue
			if not _is_legacy_lead_name(String(l.display_name)):
				continue
			var old_name: String = String(l.display_name)
			l.display_name = _gen_name_for_id(l.id)
			renamed_count += 1
			Log.info(&"hiring", "legacy_lead_name_migrated",
					{lead_id = l.id, old = old_name, new = l.display_name})
	if renamed_count > 0:
		Log.info(&"hiring", "legacy_lead_name_migration_done", {count = renamed_count})

## 旧 display_name 形态: 空串 / "Lead 0001" 这种 "Lead <数字>"。debug starter kit
## 生成的 "Debug <specialty> #N" 不算 legacy, 保留以便 debug 识别。
static func _is_legacy_lead_name(lead_name: String) -> bool:
	if lead_name.is_empty():
		return true
	if not lead_name.begins_with("Lead "):
		return false
	var tail := lead_name.substr(5).strip_edges()
	if tail.is_empty():
		return false
	for ch in tail:
		if ch < "0" or ch > "9":
			return false
	return true

## Builds a Lead with stats from resources/data/hiring/lead_levels/<level>.tres.
## Falls back to the C-tier spec if the level is unknown.
func _gen_lead(level: StringName, specialty: StringName) -> Lead:
	if _lead_level_specs.is_empty():
		_load_tables()
	var lead := Lead.new()
	lead.id = _gen_lead_id()
	lead.display_name = _gen_name_for_id(lead.id)
	lead.specialty = specialty
	lead.level = level
	var spec: LeadLevelSpec = _lead_level_specs.get(level, _lead_level_specs.get(&"C"))
	if spec != null:
		lead.ability = spec.ability
		lead.signing_fee = spec.signing_fee
		lead.weekly_salary = spec.weekly_salary
	return lead

# ---- table loading ------------------------------------------------------

func _load_tables() -> void:
	_lead_level_specs.clear()
	for level in LEAD_LEVEL_PATHS.keys():
		var spec := load(LEAD_LEVEL_PATHS[level])
		if spec is LeadLevelSpec:
			_lead_level_specs[level] = spec
		else:
			Log.warn(&"hiring", "lead_level_spec_missing", {level = level})

	SALARY_PER_ROLE.clear()
	for role in STAFF_ROLE_PATHS.keys():
		var spec := load(STAFF_ROLE_PATHS[role])
		if spec is StaffRoleSpec:
			SALARY_PER_ROLE[role] = int(spec.weekly_salary)
		else:
			Log.warn(&"hiring", "staff_role_spec_missing", {role = role})

	LEAD_BONUS_TABLE.clear()
	for sp in LEAD_BONUS_PATHS.keys():
		var spec := load(LEAD_BONUS_PATHS[sp])
		if spec is LeadBonusSpec:
			LEAD_BONUS_TABLE[sp] = spec.bonuses.duplicate()
		else:
			Log.warn(&"hiring", "lead_bonus_spec_missing", {specialty = sp})

	var cfg := load(POOL_CONFIG_PATH)
	if cfg is LeadPoolConfig:
		_pool_config = cfg
		LEAD_POOL_BASE_SIZE = cfg.pool_size
	else:
		Log.warn(&"hiring", "pool_config_missing", {path = POOL_CONFIG_PATH})
