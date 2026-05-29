extends Node

## FounderSystem — read-only registry of founder "origin" specs.
## Per design/出身系统设计.md §4-5.
##
## Loads the FounderOriginSpec .tres files at _ready and exposes the current
## origin's multipliers, keyed off GameState.founder_origin. HiringSystem /
## EconomySystem / UserSystem call the accessors below at runtime; an unknown
## or empty origin yields a fully neutral spec so legacy saves and default
## new games behave exactly like the pre-origin game.

const ORIGIN_PATHS: Dictionary = {
	&"scientist":    "res://resources/data/founders/scientist.tres",
	&"entrepreneur": "res://resources/data/founders/entrepreneur.tres",
	&"influencer":   "res://resources/data/founders/influencer.tres",
}

## Display order used by NewGameDialog.
const ORIGIN_ORDER: Array[StringName] = [&"scientist", &"entrepreneur", &"influencer"]

var _specs: Dictionary = {}            # id -> FounderOriginSpec
var _neutral: FounderOriginSpec = null

func _ready() -> void:
	_load_tables()

func _load_tables() -> void:
	_specs.clear()
	for id in ORIGIN_PATHS.keys():
		var spec := load(ORIGIN_PATHS[id])
		if spec is FounderOriginSpec:
			_specs[id] = spec
		else:
			Log.warn(&"founder", "origin_spec_missing", {id = id})
	_neutral = FounderOriginSpec.new()
	_neutral.id = &""
	# strings.csv 语义 key (显示处 tr, 见 国际化设计.md §6ter); 代码定义的名进不了 content.csv。
	_neutral.display_name = "FOUNDER_NEUTRAL"

# ---- introspection ------------------------------------------------------

## All loaded origin specs in display order (skips any that failed to load).
func all_specs() -> Array:
	if _specs.is_empty():
		_load_tables()
	var out: Array = []
	for id in ORIGIN_ORDER:
		if _specs.has(id):
			out.append(_specs[id])
	return out

## Spec for the current GameState.founder_origin; neutral spec when the
## origin is empty / unknown (legacy save or default new game).
func current_spec() -> FounderOriginSpec:
	return spec_for(GameState.founder_origin)

func spec_for(origin: StringName) -> FounderOriginSpec:
	if _specs.is_empty():
		_load_tables()
	if _specs.has(origin):
		return _specs[origin]
	return _neutral

# ---- accessors used by the game systems ---------------------------------

func s_tier_weight_bonus() -> float:
	return current_spec().s_tier_weight_bonus

func funding_multiplier() -> float:
	return current_spec().funding_multiplier

func user_growth_multiplier() -> float:
	return current_spec().user_growth_multiplier

func seed_round_unlocked() -> bool:
	return current_spec().seed_round_unlocked
