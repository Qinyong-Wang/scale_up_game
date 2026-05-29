class_name TrophySpec
extends Resource

## One trophy displayed on the office honor desk. Stored at
## resources/data/trophies/<id>.tres, loaded by CollectionSystem.
## Per design/办公室与收藏系统设计.md §4.
##
## Phase 2 builds the display framework only: the desk shows every TrophySpec,
## highlighting earned ones (GameState.trophies) and greying out the rest with
## unlock_hint. Award sources (charity tier / leaderboard #1 / universe "42")
## are wired later.

@export var id: StringName
@export var display_name: String = ""
@export var description: String = ""
## Shown while not yet earned — how to obtain it.
@export var unlock_hint: String = ""
## Physical form in the office room: &"trophy" sits on the far coffee table,
## &"medal" lies on the near desk, and &"answer_box" is the final 42 box.
## Per design/办公室与收藏系统设计.md §4/§8.1.
@export var form: StringName = &"trophy"
## Extra narrative blurb shown in the honor info dialog (after name + description),
## i18n via content.csv (Chinese source string as key).
@export var flavor: String = ""
