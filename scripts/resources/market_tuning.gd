class_name MarketTuning
extends Resource

## MarketSystem tunable knobs. Stored at resources/data/market/tuning.tres.
## Per design/竞争对手系统设计.md §6 + design/平衡参数.md §MarketSystem.
## v7 PR-F (2026-05): fame_* knobs deleted along with the fame field.
## v8 PR-H (2026-05): npc_perturb_decay / distillation_* deleted —
## NPC is now timeline-driven, no perturbation or distillation catch-up.

@export var history_limit: int = 36
