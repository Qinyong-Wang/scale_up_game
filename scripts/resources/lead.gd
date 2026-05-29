class_name Lead
extends Resource

## A named human resource. Lives in HiringSystem (leads/lead_pool).
## Three-state mutex: idle / locked_by_task_id / assigned_to_product_id.
## Per design/招聘系统设计.md §1.

@export var id: StringName
@export var display_name: String = ""
@export var specialty: StringName  # one of HiringSystem.SPECIALTIES (6 total): &"chief_scientist" / &"ml_research_lead" / &"eval_lead" / &"chief_engineer" / &"data_scientist" / &"marketing_lead"
@export var level: StringName  # &"S" / &"A" / &"B" / &"C" / &"founder" (player-scientist)
@export var ability: float = 0.0
@export var signing_fee: int = 0
@export var weekly_salary: int = 0
## True iff this Lead represents the founder/player. Player-scientists are
## free (no salary, no fee), cannot be fired, and there can only be one per
## save. Per design/招聘系统设计.md §1 / §2.
@export var is_player_scientist: bool = false
@export var locked_by_task_id: StringName = &""
@export var assigned_to_product_id: StringName = &""
## Explicit avatar key (新游戏给「玩家自己」选的创始人头像, `avatar-NN`).
## 空 → 走 IconRegistry 按 lead.id 哈希分配的多元肖像池. 见 design/出身系统设计.md §3.
@export var avatar_id: StringName = &""

func is_idle() -> bool:
	return locked_by_task_id == &"" and assigned_to_product_id == &""

func to_dict() -> Dictionary:
	return {
		id = String(id),
		display_name = display_name,
		specialty = String(specialty),
		level = String(level),
		ability = ability,
		signing_fee = signing_fee,
		weekly_salary = weekly_salary,
		is_player_scientist = is_player_scientist,
		locked_by_task_id = String(locked_by_task_id),
		assigned_to_product_id = String(assigned_to_product_id),
		avatar_id = String(avatar_id),
	}

static func from_dict(d: Dictionary) -> Lead:
	var l := Lead.new()
	l.id = StringName(d.get("id", ""))
	l.display_name = String(d.get("display_name", ""))
	l.specialty = StringName(d.get("specialty", ""))
	l.level = StringName(d.get("level", ""))
	l.ability = float(d.get("ability", 0.0))
	l.signing_fee = int(d.get("signing_fee", 0))
	# Accept legacy `monthly_salary` from older saves; new field is weekly_salary.
	l.weekly_salary = int(d.get("weekly_salary", d.get("monthly_salary", 0)))
	l.is_player_scientist = bool(d.get("is_player_scientist", false))
	l.locked_by_task_id = StringName(d.get("locked_by_task_id", ""))
	l.assigned_to_product_id = StringName(d.get("assigned_to_product_id", ""))
	l.avatar_id = StringName(d.get("avatar_id", ""))
	return l
