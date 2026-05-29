class_name PowerSupplySpec
extends Resource

## Static template for a power supply option. Stored under
## resources/data/infra/power/*.tres.
## Per design/基础设施系统设计.md §1 + design/平衡参数.md PowerSupplySpec table.
##
## weekly_cost_per_card is per-week (1 turn = 1 week).
##
## v11 (2026-05): two options only — `grid` (常规供电) and `green` (绿色能源).
## green's weekly electricity is much cheaper, paid for by a one-shot
## `install_cost_per_card` (build + storage). The numbers are tuned so a
## fully-loaded datacenter breaks even at ~5 years (260 weeks) of operation.

@export var id: StringName
@export var display_name: String = ""
@export var weekly_cost_per_card: int = 0        # ¥/card/week electricity
@export var install_cost_per_card: int = 0       # ¥/card one-shot install + storage
                                                 # (charged upfront at build, sized to
                                                 # facility.max_gpu_count)
@export var build_cost_modifier: float = 0.0     # extra % on land_build_cost
@export var efficiency_modifier: float = 1.0    # multiplied into cluster_efficiency
@export var carbon_kg_per_card_week: float = 0.0
# v7 PR-F (2026-05): `fame_modifier` deleted with the fame field.
