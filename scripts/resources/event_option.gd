class_name EventOption
extends Resource

## A choice the player can make on an event card. Each option has a list
## of EventEffects applied in order on selection.
## Per design/事件系统设计.md §1.

@export var id: StringName
@export var label: String = ""
@export var effects: Array[Resource] = []  # Array[EventEffect] (typed at use)
