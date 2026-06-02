extends GutTest

## End-to-end coverage of the in-game timeline.
##
## Per design/游戏基础架构设计.md §3.4.1: turn=0 is anchored to 2017-06-12
## (Transformer paper publication). This file verifies that the anchor +
## date helpers integrate correctly with TurnManager phases, save/load,
## the main HUD, and InfraSystem GPU release gating — i.e. all the seams
## where the timeline interacts with other systems.

const Main := preload("res://scenes/main/main.gd")

func before_each() -> void:
	GameState.reset()

# ---- TurnManager ↔ GameState date sync ------------------------------------

func test_advancing_turns_progresses_in_game_date_by_seven_days() -> void:
	assert_eq(GameState.current_date(), "2017-06-12",
		"fresh game must anchor to Transformer paper day")
	TurnManager.advance()
	assert_eq(GameState.current_date(), "2017-06-19")
	TurnManager.advance()
	assert_eq(GameState.current_date(), "2017-06-26")

func test_one_year_of_turns_equals_52_weeks() -> void:
	# 52 turns × 7 days = 364 days → one day shy of 2018-06-12.
	for _i in range(52):
		TurnManager.advance()
	assert_eq(GameState.turn, 52)
	assert_eq(GameState.current_date(), "2018-06-11")

func test_phase_signal_turn_resolves_to_same_date_as_game_state() -> void:
	# When phase_started fires, the turn payload must equal GameState.turn at
	# that moment, and turn_to_date(payload) must equal current_date(). This
	# guards against any system computing dates off a stale signal payload.
	var observed: Array = []
	EventBus.phase_started.connect(func(_phase: StringName, t: int) -> void:
		observed.append({
			turn = t,
			payload_date = GameState.turn_to_date(t),
			live_date = GameState.current_date(),
		}))
	TurnManager.advance()
	TurnManager.advance()
	assert_eq(observed.size(), 6, "two advances → 3 phases × 2 = 6 signals")
	for entry in observed:
		assert_eq(entry.payload_date, entry.live_date,
			"turn %d: payload date %s ≠ current date %s"
				% [entry.turn, entry.payload_date, entry.live_date])

# ---- Save / load preserves the timeline ----------------------------------

func test_save_then_load_preserves_in_game_date() -> void:
	# Advance to a known date in 2020 (152 weeks), save,
	# reset, restore — date should be exactly the same.
	for _i in range(152):
		TurnManager.advance()
	var date_before := GameState.current_date()
	assert_eq(date_before, "2020-05-11")
	var snapshot := GameState.to_dict()
	GameState.reset()
	assert_eq(GameState.current_date(), "2017-06-12",
		"reset should drop us back to the anchor")
	GameState.from_dict(snapshot)
	assert_eq(GameState.current_date(), date_before,
		"loaded state must restore the same in-game date")
	assert_eq(GameState.turn, 152)

# ---- HUD renders the in-game date -----------------------------------------

func test_main_hud_top_bar_displays_current_date() -> void:
	var hud = Main.new()
	add_child_autofree(hud)
	await get_tree().process_frame
	# After two advances the HUD should reflect 2017-06-26.
	TurnManager.advance()
	TurnManager.advance()
	hud._refresh()
	var label_text: String = hud._turn_label.text
	assert_true(label_text.find(GameState.current_date()) != -1,
		"HUD turn label %s must contain current date %s"
			% [label_text, GameState.current_date()])
	assert_true(label_text.find("第 2 周") != -1,
		"HUD turn label %s must show week count" % label_text)

# ---- GPU release gating walks with the timeline ---------------------------

func _rent_solo_facility() -> StringName:
	# facility_solo has max_gpu_count=1 — enough to test buy gating.
	var r: Dictionary = CommandBus.send(&"infra.rent_facility",
		{facility_spec_id = &"facility_solo", power_supply_id = &"grid"})
	return r.dc_id

func test_gpu_with_future_release_turn_is_unbuyable_at_game_start() -> void:
	# cypress_t1 has release_turn=152. At turn 0 (2017-06-12)
	# it must be rejected by infra.buy_gpus.
	var dc_id := _rent_solo_facility()
	var buy_early: Dictionary = CommandBus.send(&"infra.buy_gpus", {
		dc_id = dc_id, gpu_id = &"cypress_t1", count = 1})
	assert_false(buy_early.ok, "cypress_t1 should be release-gated at turn 0")
	assert_eq(StringName(buy_early.error), &"gpu_not_released")

func test_gpu_becomes_buyable_after_advancing_to_its_release_turn() -> void:
	# Pre-fund so a successful buy can spend; the rent itself only spends a
		# small first-week land cost.
	GameState.cash = 10_000_000
	var dc_id := _rent_solo_facility()
	# Jump to bamboo_t1.release_turn (=99). Iterating 99 turns
	# via TurnManager.advance() would multiply the test runtime; the assertion
	# is purely about the release_turn gate, so a direct set is fine.
	GameState.turn = 99
	assert_eq(GameState.current_date(), GameState.turn_to_date(99))
	var buy_late: Dictionary = CommandBus.send(&"infra.buy_gpus", {
		dc_id = dc_id, gpu_id = &"bamboo_t1", count = 1})
	assert_true(buy_late.ok,
		"bamboo_t1 should be buyable at its release_turn (got %s)" % str(buy_late))

func test_starter_gpu_buyable_on_the_anchor_date() -> void:
	# cypress_t0 has release_turn=0 → buyable on 2017-06-12 (game start).
	GameState.cash = 10_000_000
	assert_eq(GameState.current_date(), "2017-06-12")
	var dc_id := _rent_solo_facility()
	var buy: Dictionary = CommandBus.send(&"infra.buy_gpus", {
		dc_id = dc_id, gpu_id = &"cypress_t0", count = 1})
	assert_true(buy.ok, "cypress_t0 should be buyable at game start (got %s)" % str(buy))

# ---- Historical education events -----------------------------------------

func test_history_archive_event_arrives_without_choice_or_direct_effect() -> void:
	GameState.cash = 1_000_000
	TurnManager.advance()
	assert_eq(GameState.pending_events.size(), 1,
			"turn=1 action phase should push the first post-2017 history archive event")
	var inst: EventInstance = GameState.pending_events[0]
	assert_eq(inst.template_id, &"history_attention_turning_point")
	var card := EventSystem._load_card(inst.template_id)
	assert_eq(card.category, &"flavor")
	assert_eq(card.options.size(), 0, "history archive events should not ask the player to choose")
	assert_false(TurnManager.can_advance(), "pending flavor event still gates turn advance")
	var r: Dictionary = CommandBus.send(&"event.dismiss_flavor", {event_id = inst.id})
	assert_true(r.ok)
	assert_eq(GameState.cash, 1_000_000, "history archive dismiss should not pay or charge money")
	assert_true(TurnManager.can_advance())
