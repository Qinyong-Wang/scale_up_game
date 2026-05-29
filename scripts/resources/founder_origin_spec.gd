class_name FounderOriginSpec
extends Resource

## One founder "origin" (出身) the player picks when starting a new game.
## Stored at resources/data/founders/<id>.tres, loaded by FounderSystem.
## Per design/出身系统设计.md §4.
##
## Every field's default is the neutral value ("no effect"), so a missing
## origin (legacy save / default new game) behaves like a plain founder.

@export var id: StringName
@export var display_name: String = ""
## One-line persona shown in NewGameDialog.
@export var description: String = ""
## 优势文案 — short upside summary for the UI.
@export var perk_summary: String = ""
## 劣势文案 — short downside summary for the UI.
@export var drawback_summary: String = ""

## HiringSystem: additive bonus to the S-tier draw weight (before renormalize).
## Additive (not multiplicative) because early-game cash brackets have a 0
## base S weight, where a multiplier would do nothing.
@export var s_tier_weight_bonus: float = 0.0

## EconomySystem: multiplier on valuation and on the rolled funding amount.
@export var funding_multiplier: float = 1.0

## UserSystem: multiplier applied to positive weekly subscriber growth only.
@export var user_growth_multiplier: float = 1.0

## EconomySystem: when true, the seed funding round is unlocked from turn 0.
@export var seed_round_unlocked: bool = false
