class_name CharityCauseSpec
extends Resource

## One charity "cause" (公益方向) the player can donate to. Stored at
## resources/data/charity/causes/<id>.tres, loaded by CharitySystem.
## Per design/慈善系统设计.md §3.
##
## Each cause drives exactly one direct buff (effect_kind) and is laddered:
## donating launches a `charity` task; on completion the donated amount is
## credited to the cause's cumulative total, and the active bonus is the
## highest tier whose threshold the cumulative has reached (capped at the top
## tier). Donating is a money sink; the buff is small and capped on purpose.

@export var id: StringName
@export var display_name: String = ""
## One-line description shown on the charity card.
@export var description: String = ""

## Which direct buff this cause drives:
##   &"s_tier_weight"  — additive bonus to the S-tier hiring draw weight.
##   &"valuation_mult" — valuation multiplier is (1.0 + bonus).
##   &"conversion_mult"— marketing conversion multiplier is (1.0 + bonus).
@export var effect_kind: StringName = &""

## Ascending cumulative-donation thresholds (one per tier). Reaching
## tier_amounts[i] (cumulative, completed) activates tier_bonuses[i].
@export var tier_amounts: Array[int] = []
## Weeks the charity task runs for a donation at each tier (bigger = longer).
@export var tier_weeks: Array[int] = []
## Bonus magnitude per tier (semantics depend on effect_kind). The last entry
## is the cap. Neutral (no tier reached) is 0.0 for every effect_kind.
@export var tier_bonuses: Array[float] = []
## Per-tier display label (e.g. 区域级 / 国家级 / 全球级). UI / i18n only.
@export var tier_labels: Array[String] = []
