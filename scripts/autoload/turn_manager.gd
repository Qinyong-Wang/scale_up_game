extends Node

## Drives the weekly turn cycle. Per design/游戏基础架构设计.md §3.4:
## advance() bumps `turn`, emits phase_started for upkeep/action/resolve in
## order, then emits turn_resolved. TurnManager itself never calls system
## methods directly — systems do their work in response to phase signals.
##
## After turn_resolved, an autosave is written to the &"autosave" slot
## (skipped during test runs to keep tests hermetic).

const PHASES: Array[StringName] = [&"upkeep", &"action", &"resolve"]
const TURN_UNIT: StringName = &"week"
const WEEKS_PER_MONTH: int = 4

var autosave_enabled: bool = true
var _is_advancing: bool = false

func _ready() -> void:
	for arg in OS.get_cmdline_args():
		if arg.begins_with("-gtest") or arg == "--test" or arg.find("gut_cmdln.gd") != -1:
			autosave_enabled = false
			break

## Whether the player may advance to the next week. False while events are
## pending — they must be resolved first. Per 事件系统设计.md §2 (回合推进门禁).
## advance() itself stays pure (no guard); the gate is enforced at the UI layer.
func can_advance() -> bool:
	return GameState.pending_events.is_empty()

func is_advancing() -> bool:
	return _is_advancing

func advance() -> void:
	GameState.turn += 1
	_is_advancing = true
	Log.info(&"turn", "advance", {turn = GameState.turn})
	for phase in PHASES:
		EventBus.phase_started.emit(phase, GameState.turn)
	EventBus.turn_resolved.emit(GameState.turn)
	_is_advancing = false
	if autosave_enabled:
		Save.write(Save.AUTOSAVE_SLOT)

func turn_label(turn: int = -1) -> String:
	var t: int = GameState.turn if turn < 0 else turn
	return tr("TURN_LABEL") % [t, GameState.turn_to_date(t)]

func duration_label(turns: int) -> String:
	return tr("COUNT_WEEKS") % int(turns)
