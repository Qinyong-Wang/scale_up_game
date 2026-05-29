class_name DatacenterConstruction
extends Resource

## In-progress build of a datacenter / facility. Lives in
## InfraSystem.construction_queue.
## Per design/基础设施系统设计.md §1.
##
## v2 schema: facility_spec_id + power_supply (separate GPU buy step). The old
## `spec_id` field is preserved as a getter/setter that aliases
## facility_spec_id so old save files & tests keep working.
## See also scripts/resources/facility_construction.gd for the renamed class.
##
## All week counters are per-week (1 turn = 1 week).

@export var id: StringName
@export var facility_spec_id: StringName
@export var power_supply: StringName = &"grid"
@export var weeks_remaining: int = 0
@export var total_weeks: int = 0
# Optional GPU to auto-install when construction completes. Empty for legacy
# `infra.build_dc` path; set by `infra.build_facility` when caller bundles a
# GPU purchase with the build. Mirrors FacilityConstruction.gpu_id.
@export var gpu_id: StringName = &""

# Legacy alias (old export field name `spec_id`).
var spec_id: StringName:
	get: return facility_spec_id
	set(v): facility_spec_id = v

# Legacy aliases so existing callers/saves using `months_remaining` /
# `total_months` keep working. Values are interpreted as turns = weeks.
var months_remaining: int:
	get: return weeks_remaining
	set(v): weeks_remaining = v

var total_months: int:
	get: return total_weeks
	set(v): total_weeks = v

func to_dict() -> Dictionary:
	return {
		id = String(id),
		facility_spec_id = String(facility_spec_id),
		power_supply = String(power_supply),
		weeks_remaining = weeks_remaining,
		total_weeks = total_weeks,
		gpu_id = String(gpu_id),
	}

static func from_dict(d: Dictionary) -> DatacenterConstruction:
	var c := DatacenterConstruction.new()
	c.id = StringName(d.get("id", ""))
	var fid: String = String(d.get("facility_spec_id", d.get("spec_id", "")))
	c.facility_spec_id = StringName(fid)
	c.power_supply = StringName(d.get("power_supply", "grid"))
	c.weeks_remaining = int(d.get("weeks_remaining", d.get("months_remaining", 0)))
	c.total_weeks = int(d.get("total_weeks", d.get("total_months", 0)))
	c.gpu_id = StringName(d.get("gpu_id", ""))
	return c
