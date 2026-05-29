class_name TaskInstance
extends Resource

## Runtime task instance. Lives in GameState.active_tasks; only TaskSystem
## writes. Holds a reference to its TaskTemplate by id (not by Resource ref)
## so saves don't pull the template into the snapshot.
## Per design/任务系统设计.md §1.

@export var id: StringName
@export var template_id: StringName
@export var subtype: StringName
@export var started_at_turn: int = 0
# Time fields are per-week (1 turn = 1 week). Per design/任务系统设计.md §1.
@export var total_weeks: int = 1
@export var elapsed_weeks: int = 0

# Resource locks
@export var locked_lead_ids: Array[StringName] = []
@export var locked_staff: Dictionary = {}
@export var locked_datacenter_id: StringName = &""
@export var locked_dataset_ids: Array[StringName] = []

# Used by posttrain / evaluate. Per design §1.
@export var base_model_id: StringName = &""

# Completion fan-out
@export var completion_command: StringName = &""
@export var completion_payload: Dictionary = {}

# Per-instance overrides for cost fields. 0 = use template default. Set by
# TaskSystem when the template's cost is dynamic (e.g. data_collection_law's
# kind/size-based pricing). Per design/数据集系统设计.md §5.1ter (v2.1).
@export var base_cost_override: int = 0
@export var weekly_cost_override: int = 0

func to_dict() -> Dictionary:
	var leads_arr: Array = []
	for l in locked_lead_ids:
		leads_arr.append(String(l))
	var ds_arr: Array = []
	for d in locked_dataset_ids:
		ds_arr.append(String(d))
	var staff: Dictionary = {}
	for k in locked_staff.keys():
		staff[String(k)] = int(locked_staff[k])
	return {
		id = String(id),
		template_id = String(template_id),
		subtype = String(subtype),
		started_at_turn = started_at_turn,
		total_weeks = total_weeks,
		elapsed_weeks = elapsed_weeks,
		locked_lead_ids = leads_arr,
		locked_staff = staff,
		locked_datacenter_id = String(locked_datacenter_id),
		locked_dataset_ids = ds_arr,
		base_model_id = String(base_model_id),
		completion_command = String(completion_command),
		completion_payload = _payload_to_dict(completion_payload),
		base_cost_override = base_cost_override,
		weekly_cost_override = weekly_cost_override,
	}

static func from_dict(d: Dictionary) -> TaskInstance:
	var inst := TaskInstance.new()
	inst.id = StringName(d.get("id", ""))
	inst.template_id = StringName(d.get("template_id", ""))
	inst.subtype = StringName(d.get("subtype", ""))
	inst.started_at_turn = int(d.get("started_at_turn", 0))
	# Accept legacy total_months / elapsed_months / monthly_cost_override from old saves.
	inst.total_weeks = int(d.get("total_weeks", d.get("total_months", 1)))
	inst.elapsed_weeks = int(d.get("elapsed_weeks", d.get("elapsed_months", 0)))
	var leads_arr: Array[StringName] = []
	for l in d.get("locked_lead_ids", []):
		leads_arr.append(StringName(l))
	inst.locked_lead_ids = leads_arr
	var staff: Dictionary = {}
	for k in (d.get("locked_staff", {}) as Dictionary).keys():
		staff[StringName(k)] = int(d.locked_staff[k])
	inst.locked_staff = staff
	inst.locked_datacenter_id = StringName(d.get("locked_datacenter_id", ""))
	var ds_arr: Array[StringName] = []
	for x in d.get("locked_dataset_ids", []):
		ds_arr.append(StringName(x))
	inst.locked_dataset_ids = ds_arr
	inst.base_model_id = StringName(d.get("base_model_id", ""))
	inst.completion_command = StringName(d.get("completion_command", ""))
	inst.completion_payload = _payload_from_dict(d.get("completion_payload", {}))
	inst.base_cost_override = int(d.get("base_cost_override", 0))
	inst.weekly_cost_override = int(d.get("weekly_cost_override",
			d.get("monthly_cost_override", 0)))
	return inst

# Completion payload may contain mixed types (Dictionary, Array,
# StringName-keyed sub-dicts). For JSON we stringify keys and StringName
# values; on load we don't re-typify (safe because consumers re-type at use).
static func _payload_to_dict(p: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k in p.keys():
		out[String(k)] = _payload_value(p[k])
	return out

static func _payload_value(v):
	if v is StringName:
		return String(v)
	if v is Array:
		var arr: Array = []
		for x in v:
			arr.append(_payload_value(x))
		return arr
	if v is Dictionary:
		var d: Dictionary = {}
		for k in v.keys():
			d[String(k)] = _payload_value(v[k])
		return d
	return v

static func _payload_from_dict(p: Dictionary) -> Dictionary:
	# We keep keys as plain strings; consumers cast via StringName(...) when
	# they read fields, which is already the convention in TaskSystem.
	return p.duplicate(true)
