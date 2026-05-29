class_name TechNode
extends Resource

## Static template for one node in a tech tree.
## Stored as .tres under resources/data/tech/<tree>/.
## Per design/科技树系统设计.md §1.

@export var id: StringName
@export var tree: StringName  # &"arch" / &"attention" / &"loss" / &"engineering" / &"application" / &"context"
@export var display_name: String = ""
@export var description: String = ""
@export var prerequisites: Array[StringName] = []
@export var research_cost: int = 0  # v6: 保留为 0; 历史字段, 算力开销由锁 dc 承担
@export var research_months: int = 1  # 历史字段名, 实际单位是周. v6 范围 [24, 48] (baseline 节点 = 0).
@export var effects: Dictionary = {}
@export var effects_summary: String = ""

# v6 (PR-D): 研究该节点所需的最少资源. ResearchDialog 让玩家在此基础上选择 ≥ min 的具体数值.
# 见 design/科技树系统设计.md §6.0 节点权威表.
@export var min_researchers: int = 0   # ml_eng 最低数 (典型 2..5)
@export var min_engineers: int = 0     # infra_eng 最低数 (典型 1..10)
@export var min_gpu_count: int = 0     # datacenter GPU 数 (典型 8/32/64/128/256/500)

# v7 PR-G: arch 树专用; > 0 时把 evaluate `base` 钳到该上限. 用于 BERT / encoder-decoder
# 等不可 scale 的陷阱架构, 模拟现实里 LLM 范式取代 encoder/encoder-decoder 的过程.
# 见 design/科技树系统设计.md §1 + 任务系统设计 §6.7.
@export var capability_cap: float = 0.0
