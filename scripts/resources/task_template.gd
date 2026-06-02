class_name TaskTemplate
extends Resource

## Static template that defines a class of long-running task. Stored as
## .tres under resources/data/tasks/<subtype>/. Per design/任务系统设计.md §1.
##
## Supported subtypes: pretrain / posttrain / evaluate / data_collection /
## tech_research / charity / simulation.
## Duration is computed by `duration_func`:
##   - &"fixed":        base_duration (turns)
##   - &"node_defined": TechNode.research_months (historical key; weeks)
##   - &"scaling_law":  6 × C × size_params × dataset_tokens /
##                      (dc.train_tflops × arch_train_coef × dataset_quality)

@export var id: StringName
@export var subtype: StringName                  # &"pretrain" | &"posttrain" | &"evaluate" | &"data_collection" | &"tech_research" | &"charity" | &"simulation"
@export var display_name: String = ""

# Costs (per-week — 1 turn = 1 week)
@export var base_cost: int = 0                   # one-shot, charged on start. Model lifecycle tasks (pretrain/posttrain/evaluate) MUST be 0 per design §1.
@export var weekly_cost: int = 0                 # per-turn upkeep

# Duration
@export var duration_func: StringName = &"fixed"
@export var base_duration: int = 1               # weeks; used by `duration_func == &"fixed"`

# Optional input validation hints. Per design §1 / §6.1.
# Recognized keys (all optional):
#   needs_lead: bool                       — first lead_id is required
#   needs_lead_specialty: StringName       — first lead must have this specialty
#   needs_dc: bool                         — datacenter_id required & idle
#   needs_dataset: bool                    — at least one dataset required
#   needs_base_model: bool                 — base_model_id required & in models
#   needs_target_node: bool                — target_node_id required & in NODES
@export var input_schema: Dictionary = {}

# Pretrain-specific output (used by completion fan-out → research.add_model)
@export var output_arch: StringName = &""
@export var output_size_params: float = 0.0           # in millions
@export var output_flops_per_token: float = 0.0
@export var output_input_modalities: Array[StringName] = [&"text"]
@export var output_output_modalities: Array[StringName] = [&"text"]

# Risk: probability per action phase that the task is delayed by 1 week.
# Used by all subtypes; 0 means deterministic.
@export var error_rate_per_week: float = 0.0
