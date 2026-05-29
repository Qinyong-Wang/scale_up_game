class_name LeadBonusSpec
extends Resource

## Per-specialty bonus row. Stored under resources/data/hiring/lead_bonus/*.tres.
## Per design/招聘系统设计.md §1.1 + §7 + design/平衡参数.md §LEAD_BONUS_TABLE.
## Assembled at HiringSystem._ready into LEAD_BONUS_TABLE = { specialty: bonuses }.
##
## bonuses is a Dictionary of { bonus_key: coef_float }:
##   *_speed     -> multiplicative speedup consumed by lead_speedup_for()
##   *_add       -> additive flat bonus (applied by the owning system)
##   *_bonus     -> semantic flat bonus on score / throughput / quality

@export var specialty: StringName       # &"chief_scientist" / &"ml_research_lead" / ... (6 total)
@export var bonuses: Dictionary = {}
