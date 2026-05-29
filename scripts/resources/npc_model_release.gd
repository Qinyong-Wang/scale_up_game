class_name NpcModelRelease
extends Resource

## One product release on an NPC's product timeline.
## Lives as a sub-resource inside resources/data/npcs/<id>.tres → NpcCompany.model_releases.
## Per design/竞争对手系统设计.md §1 + design/NPC配置.md §3.

const AXES: Array[StringName] = [&"general", &"code", &"reasoning", &"multimodal", &"agent"]

@export var id: StringName
@export var display_name: String = ""
@export var release_turn: int = 0

# 5-axis capability at release time. Drives leaderboard ranking via NpcCompany.model_capability
# (= latest release.capability, computed every action phase by MarketSystem).
@export var capability: Dictionary = {
	general = 0.0,
	code = 0.0,
	reasoning = 0.0,
	multimodal = 0.0,
	agent = 0.0,
}

# Narrative tag only; not consumed by leaderboard scoring.
@export var release_kind: StringName = &"pretrain"

# Training context — visible to the player in the competitor detail view.
# For non-pretrain release_kind these may be 0 / "" (the release is "based on" a prior pretrain).
@export var cluster_gpu_id: StringName = &""
@export var cluster_gpu_count: int = 0
@export var training_weeks: int = 0
@export var params_b: float = 0.0          # billions; e.g. 1500.0 == 1.5T
@export var active_params_b: float = 0.0   # MoE active; dense == params_b
@export var dataset_tokens_b: float = 0.0  # billions
@export var arch_codename: StringName = &""

# ---- serialization -----------------------------------------------------

func to_dict() -> Dictionary:
	return {
		id = String(id),
		display_name = display_name,
		release_turn = release_turn,
		capability = _axis_dict_copy(capability),
		release_kind = String(release_kind),
		cluster_gpu_id = String(cluster_gpu_id),
		cluster_gpu_count = cluster_gpu_count,
		training_weeks = training_weeks,
		params_b = params_b,
		active_params_b = active_params_b,
		dataset_tokens_b = dataset_tokens_b,
		arch_codename = String(arch_codename),
	}

static func from_dict(d: Dictionary) -> NpcModelRelease:
	var r := NpcModelRelease.new()
	r.id = StringName(d.get("id", ""))
	r.display_name = String(d.get("display_name", ""))
	r.release_turn = int(d.get("release_turn", 0))
	r.capability = _coerce_axis_dict(d.get("capability", 0.0))
	r.release_kind = StringName(d.get("release_kind", "pretrain"))
	r.cluster_gpu_id = StringName(d.get("cluster_gpu_id", ""))
	r.cluster_gpu_count = int(d.get("cluster_gpu_count", 0))
	r.training_weeks = int(d.get("training_weeks", 0))
	r.params_b = float(d.get("params_b", 0.0))
	r.active_params_b = float(d.get("active_params_b", 0.0))
	r.dataset_tokens_b = float(d.get("dataset_tokens_b", 0.0))
	r.arch_codename = StringName(d.get("arch_codename", ""))
	return r

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
