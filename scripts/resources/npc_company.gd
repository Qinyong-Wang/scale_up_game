class_name NpcCompany
extends Resource

## A simulated competitor. Lives in MarketSystem.npc_companies.
## Per design/竞争对手系统设计.md §1 + design/NPC配置.md.
##
## v8 PR-H (2026-05) — timeline-driven. Each NPC carries a pre-authored
## `model_releases` array; MarketSystem flips `current_release_id` each week
## to the latest release with `release_turn <= GameState.turn`. `model_capability`
## becomes a derived cache (= current_release.capability). The pre-v8 step-jump
## fields (growth_curve / step_size / step_period_* / next_step_turn / perturbation)
## are removed. Old saves without `model_releases` still load (capability stays
## flat at whatever the dict said).

# Preload alias (suffix T to avoid shadowing the class_name; the gdscript
# hygiene test forbids same-name preload constants). Using a preload const
# for the typed array element is required: at parse-time the global class
# symbol isn't yet available inside resource scripts referenced by autoloads.
const NpcModelReleaseT := preload("res://scripts/resources/npc_model_release.gd")

const AXES: Array[StringName] = [&"general", &"code", &"reasoning", &"multimodal", &"agent"]

@export var id: StringName
@export var display_name: String = ""

@export var is_open_source: bool = false

# Which boards this NPC appears on — subset of:
#   closed_source / open_source / sub_general / sub_code / sub_reasoning / sub_multimodal / sub_agent.
# The `total` board is computed from main-board membership; not declared here.
@export var board_membership: Array[StringName] = []

# Full product timeline, sorted ascending by release_turn. Authored in .tres
# as inline sub-resources.
@export var model_releases: Array[NpcModelReleaseT] = []

# ---- runtime-derived ----------------------------------------------------
# Persisted via to_dict / from_dict so save→load preserves the visible state.
@export var current_release_id: StringName = &""

# Cache mirroring current_release.capability for fast reads. Other systems
# may read this directly; MarketSystem owns updates.
@export var model_capability: Dictionary = {
	general = 0.0,
	code = 0.0,
	reasoning = 0.0,
	multimodal = 0.0,
	agent = 0.0,
}

# ---- helpers ------------------------------------------------------------

## Latest release whose release_turn <= turn, or null if none yet (NPC hasn't
## "launched" their first product). model_releases is expected sorted ascending.
func latest_release_at(turn: int) -> NpcModelReleaseT:
	var best: NpcModelReleaseT = null
	for r in model_releases:
		if r == null:
			continue
		if r.release_turn <= turn:
			best = r
		else:
			break
	return best

# ---- save / load --------------------------------------------------------

func to_dict() -> Dictionary:
	var releases: Array = []
	for r in model_releases:
		if r != null:
			releases.append(r.to_dict())
	return {
		id = String(id),
		display_name = display_name,
		is_open_source = is_open_source,
		board_membership = _sn_array_to_strings(board_membership),
		model_releases = releases,
		current_release_id = String(current_release_id),
		model_capability = _axis_dict_copy(model_capability),
	}

static func from_dict(d: Dictionary) -> NpcCompany:
	var n := NpcCompany.new()
	n.id = StringName(d.get("id", ""))
	n.display_name = String(d.get("display_name", ""))
	n.is_open_source = bool(d.get("is_open_source", false))
	n.board_membership = _strings_to_sn_array(d.get("board_membership", []))
	var releases_in = d.get("model_releases", [])
	var arr: Array[NpcModelReleaseT] = []
	if releases_in is Array:
		for entry in releases_in:
			if entry is Dictionary:
				arr.append(NpcModelReleaseT.from_dict(entry))
	n.model_releases = arr
	n.current_release_id = StringName(d.get("current_release_id", ""))
	n.model_capability = _coerce_axis_dict(d.get("model_capability", 0.0))
	return n

static func _coerce_axis_dict(v) -> Dictionary:
	var out: Dictionary = {general = 0.0, code = 0.0, reasoning = 0.0, multimodal = 0.0, agent = 0.0}
	if v is Dictionary:
		for k in v.keys():
			out[String(k)] = float(v[k])
	elif v is float or v is int:
		var f: float = float(v)
		for axis in AXES:
			out[String(axis)] = f
	return out

static func _axis_dict_copy(d: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k in d.keys():
		out[String(k)] = float(d[k])
	for axis in AXES:
		if not out.has(String(axis)):
			out[String(axis)] = 0.0
	return out

static func _sn_array_to_strings(arr) -> Array:
	var out: Array = []
	for v in arr:
		out.append(String(v))
	return out

static func _strings_to_sn_array(arr) -> Array[StringName]:
	var out: Array[StringName] = []
	if arr is Array:
		for v in arr:
			out.append(StringName(v))
	return out
