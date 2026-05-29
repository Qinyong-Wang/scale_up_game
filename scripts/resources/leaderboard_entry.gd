class_name LeaderboardEntry
extends Resource

## One row of a leaderboard. Lives in GameState.leaderboard[<board_id>].
## Per design/竞争对手系统设计.md §1.
##
## v8 PR-H (2026-05): `company_name` added. NPC entries render as
## `{display_name} — {company_name}` (model — company); player entries leave
## company_name empty so UI shows just the model name.

@export var entity_id: StringName
@export var entity_type: StringName  # &"player_model" / &"npc"
@export var display_name: String = ""
@export var company_name: String = ""
@export var capability_score: float = 0.0
@export var rank: int = 0

func to_dict() -> Dictionary:
	return {
		entity_id = String(entity_id),
		entity_type = String(entity_type),
		display_name = display_name,
		company_name = company_name,
		capability_score = capability_score,
		rank = rank,
	}

static func from_dict(d: Dictionary) -> LeaderboardEntry:
	var e := LeaderboardEntry.new()
	e.entity_id = StringName(d.get("entity_id", ""))
	e.entity_type = StringName(d.get("entity_type", ""))
	e.display_name = String(d.get("display_name", ""))
	e.company_name = String(d.get("company_name", ""))
	e.capability_score = float(d.get("capability_score", 0.0))
	e.rank = int(d.get("rank", 0))
	return e
