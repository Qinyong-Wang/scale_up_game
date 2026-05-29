class_name EventEffect
extends Resource

## One outcome of an EventOption. Dispatched via CommandBus from EventSystem.
## Per design/事件系统设计.md §1, §6.3.

@export var kind: StringName
@export var params: Dictionary = {}
