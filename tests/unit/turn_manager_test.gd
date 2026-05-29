extends GutTest

## Tests for TurnManager — drives upkeep/action/resolve phases per design 3.4.

func before_each() -> void:
	GameState.reset()

func test_advance_increments_turn() -> void:
	var before := GameState.turn
	TurnManager.advance()
	assert_eq(GameState.turn, before + 1)

func test_turn_unit_is_week() -> void:
	assert_eq(TurnManager.TURN_UNIT, &"week")
	assert_eq(TurnManager.WEEKS_PER_MONTH, 4)
	# Per design/游戏基础架构设计.md §3.4.1, label shows both turn count and
	# the real-world calendar date anchored to GAME_START_DATE.
	assert_eq(TurnManager.turn_label(3), "第 3 周 · 2017-07-03")
	assert_eq(TurnManager.duration_label(5), "5 周")

func test_advance_emits_phases_in_order() -> void:
	var seen: Array = []
	EventBus.phase_started.connect(func(phase: StringName, _t: int) -> void:
		seen.append(phase))
	TurnManager.advance()
	assert_eq(seen, [&"upkeep", &"action", &"resolve"])

func test_advance_emits_turn_resolved_after_phases() -> void:
	var order: Array = []
	EventBus.phase_started.connect(func(phase: StringName, _t: int) -> void:
		order.append([&"phase", phase]))
	EventBus.turn_resolved.connect(func(t: int) -> void:
		order.append([&"resolved", t]))
	TurnManager.advance()
	assert_eq(order[-1][0], &"resolved")
	assert_eq(order[-1][1], GameState.turn)

func test_is_advancing_true_until_turn_resolved() -> void:
	var phase_flags: Array = []
	var resolved_flags: Array = []
	EventBus.phase_started.connect(func(_phase: StringName, _t: int) -> void:
		phase_flags.append(TurnManager.is_advancing()))
	EventBus.turn_resolved.connect(func(_t: int) -> void:
		resolved_flags.append(TurnManager.is_advancing()))
	TurnManager.advance()
	assert_eq(phase_flags, [true, true, true])
	assert_eq(resolved_flags, [true],
			"turn_resolved 期间仍应允许 HUD 识别推进中并做批处理收尾")
	assert_false(TurnManager.is_advancing(), "advance() 返回后推进标记必须复位")

func test_phase_signal_carries_current_turn() -> void:
	var seen_turns: Array = []
	EventBus.phase_started.connect(func(_phase: StringName, t: int) -> void:
		seen_turns.append(t))
	TurnManager.advance()
	for t in seen_turns:
		assert_eq(t, GameState.turn)

func test_multiple_advances_increment_turn_each_time() -> void:
	TurnManager.advance()
	TurnManager.advance()
	TurnManager.advance()
	assert_eq(GameState.turn, 3)

func test_each_advance_emits_full_phase_sequence() -> void:
	var seen: Array = []
	EventBus.phase_started.connect(func(phase: StringName, _t: int) -> void:
		seen.append(phase))
	TurnManager.advance()
	TurnManager.advance()
	# Two advances must yield two complete phase sequences back-to-back.
	assert_eq(seen, [&"upkeep", &"action", &"resolve", &"upkeep", &"action", &"resolve"])

func test_turn_resolved_payload_matches_turn_after_advance() -> void:
	var resolved_turns: Array = []
	EventBus.turn_resolved.connect(func(t: int) -> void: resolved_turns.append(t))
	TurnManager.advance()
	TurnManager.advance()
	assert_eq(resolved_turns, [1, 2])
