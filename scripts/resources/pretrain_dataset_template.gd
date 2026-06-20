class_name PretrainDatasetTemplate
extends Resource

## Static template for a pretraining dataset.
## Stored as .tres under resources/data/datasets/pretrain/{open_source,purchased}/.
## Per design/数据集系统设计.md §2 (v2).

@export var id: StringName
@export var display_name: String = ""
@export var source: StringName  # &"open_source" / &"purchased"
## v7 PR-G: 单模态; text/image/audio/video. 默认 text 与旧 .tres 兼容.
## 旧 code modality 视为 text; 代码专精用 coverage_tags = [&"code"].
@export var modality: StringName = &"text"
@export var size: float = 0.0   # B tokens
@export var quality: float = 0.0
@export var coverage_tags: Array[StringName] = []
@export var price: int = 0  # zero for open_source
@export var released_at_week: int = 0  # turn 0 = 2017-06-12, 见平衡参数 §时间锚点
