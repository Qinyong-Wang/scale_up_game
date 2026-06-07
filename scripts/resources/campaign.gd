class_name Campaign
extends Resource

## A marketing campaign drains cash each turn (1 turn = 1 week) and boosts
## one specific product's subscribers.
## Per design/营销系统设计.md §1.
##
## Targeting model (v7 PR-F3, 2026-05):
##   target_product_id: StringName — campaign 锁的具体 Product.id。
##     UserSystem._marketing_attract 按 product.id 匹配。
##     换模型 = 改 product.bound_model_id (campaign 不动); subscribers 池随
##     product 走。target product 被删 → MarketingSystem upkeep 扫到自动终止。
##
## Legacy fields (saved games before v7 PR-F3):
##   target_product_types: Array[StringName] — 旧的 type fan-out 字段, 保留
##     仅供 from_dict 读到时映射; 新代码不再读。
##   target_segment: StringName — 更老的字段, from_dict 通过 segment 映射
##     到 types (兼容路径)。
##   fame_boost: bool — v7 PR-F 删, 静默忽略。

@export var id: StringName
@export var display_name: String = ""
@export var weekly_budget: int = 0
@export var remaining_weeks: int = 0
@export var total_weeks: int = 0
# v7 PR-F3: 主要匹配字段。
@export var target_product_id: StringName = &""
@export var lead_id: StringName = &""
# Performance-score claim honesty. See design/营销系统设计.md §5.2.
@export var fake_score_level: StringName = &"none"
@export var started_at_turn: int = 0
# v8 (2026-05): 活动占用的资源 — marketing 员工数 (role → count)。开活动时
# hiring.lock_staff, 结束 (终止 / 自然结束 / 孤儿) 时按这里登记的数量释放。
# 见 design/营销系统设计.md §4。lead_id 同样在活动期间被 hiring 锁定。
@export var locked_staff: Dictionary = {}

# Legacy fields — kept for backwards-compat with older saves. New code reads
# target_product_id only; arrays / segment exist purely to roundtrip old saves.
@export var target_product_types: Array[StringName] = []
@export var target_segment: StringName = &"all"

func to_dict() -> Dictionary:
	return {
		id = String(id),
		display_name = display_name,
		weekly_budget = weekly_budget,
		remaining_weeks = remaining_weeks,
		total_weeks = total_weeks,
		target_product_id = String(target_product_id),
		# Legacy fields preserved for old-save round-trip.
		target_product_types = _sn_array_to_strings(target_product_types),
		lead_id = String(lead_id),
		fake_score_level = String(fake_score_level),
		target_segment = String(target_segment),
		started_at_turn = started_at_turn,
		locked_staff = _staff_to_strings(locked_staff),
	}

static func from_dict(d: Dictionary) -> Campaign:
	var c := Campaign.new()
	c.id = StringName(d.get("id", ""))
	c.display_name = String(d.get("display_name", ""))
	# Accept legacy monthly_* keys; value semantics are now per-week.
	c.weekly_budget = int(d.get("weekly_budget", d.get("monthly_budget", 0)))
	c.remaining_weeks = int(d.get("remaining_weeks", d.get("remaining_months", 0)))
	c.total_weeks = int(d.get("total_weeks", d.get("total_months", 0)))
	c.started_at_turn = int(d.get("started_at_turn", 0))
	c.lead_id = StringName(d.get("lead_id", ""))
	c.fake_score_level = normalize_fake_score_level(d.get("fake_score_level", "none"))
	# Old saves (pre-v8) have no locked_staff; leave empty so release is a no-op.
	var ls: Dictionary = d.get("locked_staff", {})
	var typed_ls: Dictionary = {}
	for k in ls.keys():
		typed_ls[StringName(k)] = int(ls[k])
	c.locked_staff = typed_ls
	# v7 PR-F3 主字段; 旧存档没有就留空 (运行时会被孤儿处理终止)。
	c.target_product_id = StringName(d.get("target_product_id", ""))
	# 旧字段保留, 仅用于序列化往返。
	if d.has("target_product_types"):
		var raw: Array = d.get("target_product_types", [])
		var typed: Array[StringName] = []
		for v in raw:
			typed.append(StringName(v))
		c.target_product_types = typed
		c.target_segment = StringName(d.get("target_segment", "all"))
	else:
		var seg := StringName(d.get("target_segment", "all"))
		c.target_segment = seg
		c.target_product_types = _legacy_segment_to_types(seg)
	return c

# ---- helpers ------------------------------------------------------------

static func _legacy_segment_to_types(segment: StringName) -> Array[StringName]:
	# Per design 营销系统设计.md §1 legacy mapping (v7 PR-F: fame_boost gone).
	match segment:
		&"chatbot_users":
			return [&"chatbot"] as Array[StringName]
		&"agent_users":
			return [&"agent", &"coding_agent"] as Array[StringName]
		_:
			# &"all" and &"open_source_devs" both map to "no target type filter".
			return [] as Array[StringName]

static func fake_score_levels() -> Array[StringName]:
	return [&"none", &"low", &"medium", &"high"] as Array[StringName]

static func is_valid_fake_score_level(value) -> bool:
	return fake_score_levels().has(StringName(value))

static func normalize_fake_score_level(value) -> StringName:
	var level := StringName(value)
	if is_valid_fake_score_level(level):
		return level
	return &"none"

static func _sn_array_to_strings(arr: Array[StringName]) -> Array:
	var out: Array = []
	for sn in arr:
		out.append(String(sn))
	return out

static func _staff_to_strings(d: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k in d.keys():
		out[String(k)] = int(d[k])
	return out
