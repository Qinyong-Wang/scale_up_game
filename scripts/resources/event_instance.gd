class_name EventInstance
extends Resource

## A triggered event awaiting / having received a player choice.
## Lives in EventSystem.pending_events / event_history.
## Per design/事件系统设计.md §1.

@export var id: StringName
@export var template_id: StringName
@export var triggered_at_turn: int = 0
@export var resolved_at_turn: int = -1
@export var chosen_option_id: StringName = &""
# Per-instance dispatch params merged into every chosen option's effect.params
# at choose-time. Used by funding rounds (and any future card whose offer
# carries roll-time concrete values) to ensure what's promised on the card is
# exactly what's applied on accept. Storing on the instance survives the
# Godot sub-resource caching quirk where mutating effect.params on a cached
# .tres doesn't persist across `load()` calls.
@export var dispatched_params: Dictionary = {}

func to_dict() -> Dictionary:
	return {
		id = String(id),
		template_id = String(template_id),
		triggered_at_turn = triggered_at_turn,
		resolved_at_turn = resolved_at_turn,
		chosen_option_id = String(chosen_option_id),
		dispatched_params = dispatched_params.duplicate(),
	}

static func from_dict(d: Dictionary) -> EventInstance:
	var e := EventInstance.new()
	e.id = StringName(d.get("id", ""))
	e.template_id = StringName(d.get("template_id", ""))
	e.triggered_at_turn = int(d.get("triggered_at_turn", 0))
	e.resolved_at_turn = int(d.get("resolved_at_turn", -1))
	e.chosen_option_id = StringName(d.get("chosen_option_id", ""))
	var dp = d.get("dispatched_params", {})
	if dp is Dictionary:
		e.dispatched_params = dp.duplicate()
	return e
