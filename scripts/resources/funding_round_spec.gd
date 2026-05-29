class_name FundingRoundSpec
extends Resource

## Per-round funding template. Stored under
## resources/data/economy/funding_rounds/<round>.tres
## (pre_seed/seed/a/b/c/d/e/f — 8 rounds, sequential lock).
## Per design/经济系统设计.md §4.6 + §5.
##
## Assembled at EconomySystem._ready into FUNDING_ROUND_TABLE = {
##   id: { amin: int, amax: int, dmin: float, dmax: float,
##         display_name: String, unlock_summary: String }
## }.

@export var id: StringName                  # &"pre_seed" / &"seed" / &"a"..&"f"
@export var amount_min: int = 0
@export var amount_max: int = 0
@export var dilution_min: float = 0.0
@export var dilution_max: float = 0.0
## UI label shown on the round card (e.g. "种子轮"). Chinese display name.
@export var display_name: String = ""
## Human-readable unlock condition shown on locked round cards.
## (Actual condition check stays in code — design §4.6.)
@export var unlock_summary: String = ""
