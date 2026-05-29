class_name LeadPoolConfig
extends Resource

## Candidate pool tuning. Stored at resources/data/hiring/pool_config.tres.
## Per design/招聘系统设计.md §6 + design/平衡参数.md §HiringSystem.
##
## v7 PR-F (2026-05): cash-based brackets (replaces v6 fame_brackets).
## cash_brackets is an Array of Dictionaries:
##   { cash_min: int, weights: { &"S": p, &"A": p, &"B": p, &"C": p } }
##
## Brackets are scanned in descending cash_min order; the first one whose
## cash_min <= GameState.cash wins. The last entry (typically cash_min = 0)
## is the early-game / negative-cash default bracket.

@export var pool_size: int = 6
@export var cash_brackets: Array = []
