class_name LeadLevelSpec
extends Resource

## Static template for a lead level (S/A/B/C).
## Stored under resources/data/hiring/lead_levels/*.tres.
## Per design/招聘系统设计.md §7 + design/平衡参数.md §HiringSystem.
## HiringSystem reads these at _ready and uses them in _gen_lead and the
## fame-bracket draw.

@export var id: StringName             # &"S" / &"A" / &"B" / &"C"
@export var ability: float = 0.0
@export var signing_fee: int = 0
@export var weekly_salary: int = 0      # ¥/week (1 turn = 1 week)
