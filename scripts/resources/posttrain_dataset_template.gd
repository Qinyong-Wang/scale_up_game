class_name PosttrainDatasetTemplate
extends Resource

## Static template for a post-training (SFT / RLHF / preference) dataset.
## Stored as .tres under resources/data/datasets/posttrain/{open_source,purchased}/.
## Per design/数据集系统设计.md §2 (v2).
##
## Unlike pretrain datasets, posttrain datasets carry a `target_capability` axis
## which determines which capability dimension is boosted on apply
## (see 研究系统设计 §6.2 v2 + 平衡参数 Posttrain 能力增减系数).

@export var id: StringName
@export var display_name: String = ""
@export var source: StringName  # &"open_source" / &"purchased"
## v7 PR-G: 单模态; 默认 text. posttrain 数据集通常都是 text 指令, 但为保持
## 数据资产模型一致性也声明 modality. code 不作为独立模态。
@export var modality: StringName = &"text"
@export var size: float = 0.0   # B tokens (典型 0.01 ~ 0.5)
@export var quality: float = 0.0
## Required for posttrain. Must be one of:
## &"general" / &"code" / &"reasoning" / &"multimodal" / &"agent"
@export var target_capability: StringName = &"general"
@export var coverage_tags: Array[StringName] = []
@export var price: int = 0
@export var released_at_week: int = 0
