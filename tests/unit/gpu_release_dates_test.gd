extends GutTest

## Verifies each GPU .tres has a release_turn that correctly maps to a calendar
## date via GameState.turn_to_date(), anchored to 2017-06-12 (Transformer paper).
## Per design/游戏基础架构设计.md §3.4.1 + design/平衡参数.md GPUSpec table v4.
##
## v4 (PR-A, 2026-05): release_turn is anchored to the canonical GPU
## launch timeline described in design/平衡参数.md.


const GPU_PATHS := [
	"res://resources/data/infra/gpus/cypress_t0.tres",
	"res://resources/data/infra/gpus/cypress_t1.tres",
	"res://resources/data/infra/gpus/cypress_t2.tres",
	"res://resources/data/infra/gpus/cypress_t3.tres",
	"res://resources/data/infra/gpus/maple_t1.tres",
	"res://resources/data/infra/gpus/maple_t2.tres",
	"res://resources/data/infra/gpus/maple_t3.tres",
	"res://resources/data/infra/gpus/bamboo_t1.tres",
	"res://resources/data/infra/gpus/bamboo_t2.tres",
	"res://resources/data/infra/gpus/bamboo_t3.tres",
	"res://resources/data/infra/gpus/bamboo_t4.tres",
]

# Canonical anchor turns from 平衡参数.md v4 GPUSpec table.
const EXPECTED_RELEASE_TURNS: Dictionary = {
	&"cypress_t0": 0,    # 2017-06
	&"cypress_t1": 152,  # 2020-05
	&"cypress_t2": 249,  # 2022-03
	&"cypress_t3": 353,  # 2024-03
	&"maple_t1":   178,  # 2020-11
	&"maple_t2":   230,  # 2021-11
	&"maple_t3":   339,  # 2023-12
	&"bamboo_t1":   99,  # 2019-05
	&"bamboo_t2":  205,  # 2021-05
	&"bamboo_t3":  339,  # 2023-12
	&"bamboo_t4":  391,  # 2024-12
}

func test_every_gpu_release_turn_resolves_to_a_calendar_date() -> void:
	# Each GPU's release_turn must be ≥ 0 and round-trip through turn_to_date /
	# date_to_turn cleanly. This guards against accidental negative or NaN
	# release_turn values that would make GPUs un-unlockable.
	for path in GPU_PATHS:
		assert_true(FileAccess.file_exists(path), "missing tres: %s" % path)
		var spec = load(path)
		assert_true(spec is GPUSpec, "%s did not load as GPUSpec" % path)
		assert_true(spec.release_turn >= 0,
			"%s release_turn %d must be ≥ 0" % [path, spec.release_turn])
		var date := GameState.turn_to_date(spec.release_turn)
		# Date must parse back to the same turn (sanity).
		assert_eq(GameState.date_to_turn(date), spec.release_turn,
			"%s: turn %d → %s → did not round-trip" % [path, spec.release_turn, date])

func test_starting_era_gpus_unlock_at_or_near_2017_06_12() -> void:
	# Per design/平衡参数.md: at game start (turn=0 = 2017-06-12) the player
	# must have at least one GPU buyable so the game can actually begin.
	# In v4 that GPU is cypress_t0.
	var any_at_start := false
	for path in GPU_PATHS:
		var spec = load(path)
		if spec.release_turn == 0:
			any_at_start = true
			assert_eq(GameState.turn_to_date(0), "2017-06-12",
				"%s claims release_turn=0 but turn_to_date(0) is wrong" % path)
	assert_true(any_at_start,
		"at least one GPU must have release_turn=0 (available at game start)")

func test_release_turns_match_real_world_anchors_v4() -> void:
	# PR-A v4: each GPU's release_turn must match the canonical
	# launch anchor in 平衡参数.md. Catches drift if a .tres is edited without
	# updating the design doc (or vice versa).
	for path in GPU_PATHS:
		var spec = load(path)
		var expected: int = int(EXPECTED_RELEASE_TURNS.get(spec.id, -1))
		assert_ne(expected, -1,
			"%s: id %s missing from EXPECTED_RELEASE_TURNS (sync the table)" %
				[path, str(spec.id)])
		assert_eq(spec.release_turn, expected,
			"%s: release_turn=%d but design anchor is %d" %
				[path, spec.release_turn, expected])

func test_cypress_t0_is_the_unique_game_start_starter() -> void:
	# In v4 cypress_t0 is the only cypress at turn 0; cypress_t1 moves to turn
	# 152 so the early game has time pressure to upgrade.
	var t0 = load("res://resources/data/infra/gpus/cypress_t0.tres")
	var t1 = load("res://resources/data/infra/gpus/cypress_t1.tres")
	assert_eq(t0.release_turn, 0)
	assert_gt(t1.release_turn, 0, "cypress_t1 must no longer be a turn-0 starter")

func test_generation_gap_is_about_two_years_for_cypress() -> void:
	# GPU cadence: every ~100 weeks (≈2 years) a new generation.
	# Game's design intent (平衡参数.md) is to mirror this so the player
	# experiences a real "hardware refresh cycle".
	var t0 = load("res://resources/data/infra/gpus/cypress_t0.tres").release_turn
	var t1 = load("res://resources/data/infra/gpus/cypress_t1.tres").release_turn
	var t2 = load("res://resources/data/infra/gpus/cypress_t2.tres").release_turn
	var t3 = load("res://resources/data/infra/gpus/cypress_t3.tres").release_turn
	# t0 → t1 = 152 weeks (≈2.9 yr)
	# t1 → t2 = 97 weeks (≈1.87 yr)
	# t2 → t3 = 104 weeks (≈2.00 yr)
	assert_almost_eq(float(t1 - t0), 152.0, 1.0)
	assert_almost_eq(float(t2 - t1), 97.0, 1.0)
	assert_almost_eq(float(t3 - t2), 104.0, 1.0)
