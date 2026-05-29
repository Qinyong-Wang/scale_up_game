class_name Dataset
extends Resource

## Training data asset. Lives in DatasetSystem.datasets.
## Per design/数据集系统设计.md §1 (v2).

@export var id: StringName
@export var display_name: String = ""
@export var kind: StringName = &"pretrain"  # &"pretrain" / &"posttrain" (v2)
@export var source: StringName  # &"open_source" / &"purchased" / &"collected"
## v7 PR-G: 单模态; text/image/audio/video/code. 默认 text (旧存档兼容).
## pretrain 训练时校验 dataset.modality ∈ model.input_modalities ∪ {text}.
@export var modality: StringName = &"text"
@export var size: float = 0.0
@export var quality: float = 0.0
@export var coverage_tags: Array[StringName] = []
## Only meaningful when kind == &"posttrain". Empty string for pretrain.
@export var target_capability: StringName = &""
@export var locked_by_task_id: StringName = &""

## v9 (2026-05): deprecated; returns 1.0 unconditionally.
## Old v2 semantics (purchased ×1.05 / open_source ×0.9 / collected ×1.0) were
## removed when evaluate switched to token×quality weighted scoring. Kept for
## save-file compatibility and any legacy preview UI that still reads it.
## Per 数据集系统设计 §1 v9 + 平衡参数.md §DatasetSystem 公式.
func pretrain_quality_multiplier() -> float:
	return 1.0

func to_dict() -> Dictionary:
	var tags: Array = []
	for t in coverage_tags:
		tags.append(String(t))
	return {
		id = String(id),
		display_name = display_name,
		kind = String(kind),
		source = String(source),
		modality = String(modality),
		size = size,
		quality = quality,
		coverage_tags = tags,
		target_capability = String(target_capability),
		locked_by_task_id = String(locked_by_task_id),
	}

static func from_dict(d: Dictionary) -> Dataset:
	var ds := Dataset.new()
	ds.id = StringName(d.get("id", ""))
	ds.display_name = String(d.get("display_name", ""))
	# v2: legacy saves may not carry kind; default to pretrain.
	ds.kind = StringName(d.get("kind", "pretrain"))
	ds.source = StringName(d.get("source", ""))
	# v7 PR-G: legacy saves default to text modality.
	ds.modality = StringName(d.get("modality", "text"))
	ds.size = float(d.get("size", 0.0))
	ds.quality = float(d.get("quality", 0.0))
	var tags: Array[StringName] = []
	for t in d.get("coverage_tags", []):
		tags.append(StringName(t))
	ds.coverage_tags = tags
	ds.target_capability = StringName(d.get("target_capability", ""))
	ds.locked_by_task_id = StringName(d.get("locked_by_task_id", ""))
	return ds
