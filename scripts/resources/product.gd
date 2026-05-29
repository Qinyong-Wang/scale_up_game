class_name Product
extends Resource

## A consumer-facing product (chatbot / agent / ...). Lives in
## ProductSystem.products. Per design/产品系统设计.md §1.

@export var id: StringName
@export var display_name: String = ""
@export var type: StringName = &"chatbot"  # &"chatbot" / &"agent" / ...
@export var bound_model_id: StringName
## When true, the product re-binds to any newly published model (matching
## is_open_source) that satisfies the type's unlock_thresholds. See §2/§4.
@export var auto_track_latest: bool = true
## Whether the bound model is open-source. Used by auto-track to keep the
## product on a model of the same kind. Set on create from the bound model.
@export var is_open_source: bool = false
@export var subscription_price: int = 0
@export var lead_id: StringName = &""
@export var assigned_staff: Dictionary = {}
@export var subscribers: int = 0
@export var launched_at_turn: int = 0
@export var quality: float = 0.0

func to_dict() -> Dictionary:
	var staff: Dictionary = {}
	for k in assigned_staff.keys():
		staff[String(k)] = int(assigned_staff[k])
	return {
		id = String(id),
		display_name = display_name,
		type = String(type),
		bound_model_id = String(bound_model_id),
		auto_track_latest = auto_track_latest,
		is_open_source = is_open_source,
		subscription_price = subscription_price,
		lead_id = String(lead_id),
		assigned_staff = staff,
		subscribers = subscribers,
		launched_at_turn = launched_at_turn,
		quality = quality,
	}

static func from_dict(d: Dictionary) -> Product:
	var p := Product.new()
	p.id = StringName(d.get("id", ""))
	p.display_name = String(d.get("display_name", ""))
	p.type = StringName(d.get("type", "chatbot"))
	p.bound_model_id = StringName(d.get("bound_model_id", ""))
	p.auto_track_latest = bool(d.get("auto_track_latest", true))
	p.is_open_source = bool(d.get("is_open_source", false))
	p.subscription_price = int(d.get("subscription_price", 0))
	p.lead_id = StringName(d.get("lead_id", ""))
	var staff: Dictionary = {}
	for k in (d.get("assigned_staff", {}) as Dictionary).keys():
		staff[StringName(k)] = int(d.assigned_staff[k])
	p.assigned_staff = staff
	p.subscribers = int(d.get("subscribers", 0))
	p.launched_at_turn = int(d.get("launched_at_turn", 0))
	p.quality = float(d.get("quality", 0.0))
	return p
