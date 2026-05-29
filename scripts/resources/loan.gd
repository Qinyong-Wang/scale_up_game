class_name Loan
extends Resource

## A loan contract held in EconomySystem.loans.
## Per design/经济系统设计.md §1. All time fields are in weeks
## (1 turn = 1 week per TurnManager.TURN_UNIT).

@export var id: StringName
@export var principal_initial: int = 0
@export var principal_remaining: int = 0
@export var weekly_interest_rate: float = 0.0
@export var weeks_remaining: int = 0
@export var taken_at_turn: int = 0

func to_dict() -> Dictionary:
	return {
		id = String(id),
		principal_initial = principal_initial,
		principal_remaining = principal_remaining,
		weekly_interest_rate = weekly_interest_rate,
		weeks_remaining = weeks_remaining,
		taken_at_turn = taken_at_turn,
	}

static func from_dict(d: Dictionary) -> Loan:
	var l := Loan.new()
	l.id = StringName(d.get("id", ""))
	l.principal_initial = int(d.get("principal_initial", 0))
	l.principal_remaining = int(d.get("principal_remaining", 0))
	l.weekly_interest_rate = float(d.get("weekly_interest_rate", d.get("monthly_interest_rate", 0.0)))
	l.weeks_remaining = int(d.get("weeks_remaining", d.get("months_remaining", 0)))
	l.taken_at_turn = int(d.get("taken_at_turn", 0))
	return l
