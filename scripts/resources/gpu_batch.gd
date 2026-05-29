class_name GPUBatch
extends Resource

## A single GPU purchase batch held inside Datacenter.gpu_purchase_history.
## Used for FIFO depreciation when selling GPUs back.
## Per design/基础设施系统设计.md §1 + §6.1.2.

@export var gpu_id: StringName = &""    # Which GPU model this batch holds
@export var count: int = 0
@export var unit_price: int = 0
@export var bought_at_turn: int = 0

# Legacy alias for bought_at_turn (some callers write `purchase_turn`).
var purchase_turn: int:
	get: return bought_at_turn
	set(v): bought_at_turn = v

func to_dict() -> Dictionary:
	return {
		gpu_id = String(gpu_id),
		count = count,
		unit_price = unit_price,
		bought_at_turn = bought_at_turn,
	}

static func from_dict(d: Dictionary):
	var b := GPUBatch.new()
	b.gpu_id = StringName(d.get("gpu_id", ""))
	b.count = int(d.get("count", 0))
	b.unit_price = int(d.get("unit_price", 0))
	b.bought_at_turn = int(d.get("bought_at_turn", d.get("purchase_turn", 0)))
	return b
