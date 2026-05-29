extends Node

## Save/load autoload. Per design/游戏基础架构设计.md §6.
##
## Saves are JSON snapshots of GameState.to_dict() under user://saves/<slot>.json.
## Version mismatch / corrupted file are surfaced as errors rather than silently
## migrated. Tests should override `save_dir` to user://test_saves to keep
## production saves clean.

const DEFAULT_SAVE_DIR := "user://saves"
const AUTOSAVE_SLOT := &"autosave"

var save_dir: String = DEFAULT_SAVE_DIR

func write(slot: StringName) -> Dictionary:
	_ensure_dir()
	var data := {
		version = GameState.SAVE_VERSION,
		saved_at = Time.get_datetime_string_from_system(),
		turn = GameState.turn,
		state = GameState.to_dict(),
	}
	var path: String = "%s/%s.json" % [save_dir, String(slot)]
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		Log.error(&"save", "write_failed", {path = path, err = FileAccess.get_open_error()})
		return {ok = false, error = &"write_failed"}
	f.store_string(JSON.stringify(data))
	f.close()
	Log.info(&"save", "wrote", {slot = slot, turn = GameState.turn})
	return {ok = true, path = path}

func read(slot: StringName) -> Dictionary:
	var path: String = "%s/%s.json" % [save_dir, String(slot)]
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {ok = false, error = &"not_found"}
	var raw: String = f.get_as_text()
	f.close()
	var json := JSON.new()
	var parse_err: int = json.parse(raw)
	if parse_err != OK:
		Log.warn(&"save", "corrupted", {
			path = path,
			line = json.get_error_line(),
			message = json.get_error_message(),
		})
		return {ok = false, error = &"corrupted"}
	var parsed: Variant = json.data
	if typeof(parsed) != TYPE_DICTIONARY:
		Log.warn(&"save", "corrupted", {path = path})
		return {ok = false, error = &"corrupted"}
	var data: Dictionary = parsed
	if int(data.get("version", -1)) != GameState.SAVE_VERSION:
		return {
			ok = false, error = &"incompatible_version",
			file_version = data.get("version", -1),
			save_version = GameState.SAVE_VERSION,
		}
	if not (data.get("state") is Dictionary):
		return {ok = false, error = &"corrupted"}
	GameState.reset()
	GameState.from_dict(data.state)
	EventBus.save_loaded.emit()
	Log.info(&"save", "loaded", {slot = slot, turn = GameState.turn})
	return {ok = true, turn = GameState.turn}

func list_slots() -> Array:
	_ensure_dir()
	var dir: DirAccess = DirAccess.open(save_dir)
	if dir == null:
		return []
	var slots: Array = []
	for f in dir.get_files():
		if f.ends_with(".json"):
			slots.append(StringName(f.replace(".json", "")))
	return slots

func delete_slot(slot: StringName) -> bool:
	var path: String = "%s/%s.json" % [save_dir, String(slot)]
	if not FileAccess.file_exists(path):
		return false
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK

func _ensure_dir() -> void:
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(save_dir)):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(save_dir))
