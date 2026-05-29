extends Node

## Fan-in command dispatch. Callers know only the command StringName,
## not which system processes it. A single handler per command (re-register
## allowed only via the explicit `replace` flag — used by tests).
##
## Contract: handler(payload: Dictionary) -> Dictionary, with at least `ok: bool`.
## Failure path adds `error: StringName`.

var _handlers: Dictionary = {}

func register(cmd: StringName, handler: Callable, replace: bool = false) -> void:
	if not replace and _handlers.has(cmd):
		Log.error(&"system", "duplicate command handler", {cmd = cmd})
		return
	_handlers[cmd] = handler

func send(cmd: StringName, payload: Dictionary = {}) -> Dictionary:
	var h: Variant = _handlers.get(cmd)
	if h == null:
		Log.warn(&"bus", "no handler for command", {cmd = cmd})
		return {ok = false, error = &"unknown_command"}
	return (h as Callable).call(payload)
