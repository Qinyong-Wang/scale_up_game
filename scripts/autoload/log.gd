extends Node

## Minimal logger per design/开发调试设计.md. v0 covers:
##   - 5 levels (TRACE..ERROR) + SILENT
##   - per-category filter (default-on)
##   - captured sink (always on) so tests can assert on log records
##   - console sink (on in editor builds, off when running with --test)
##
## Deferred: caller-frame extraction via get_stack(), file/overlay sinks,
## BusInspector signal mirroring, F2/F3/F4 hotkeys.

enum Level { TRACE, DEBUG, INFO, WARN, ERROR, SILENT }

var enabled: bool = true
var min_level: int = Level.DEBUG
var category_filter: Dictionary = {}
var captured: Array = []
var console_enabled: bool = true

func _ready() -> void:
	# Silence stdout during automated test runs to keep output clean.
	for arg in OS.get_cmdline_args():
		if arg.begins_with("-gtest") or arg == "--test" or arg.find("gut_cmdln.gd") != -1:
			console_enabled = false
			min_level = Level.WARN
			break

func trace(category: StringName, message: String, data: Variant = null) -> void:
	_record(Level.TRACE, category, message, data)

func debug(category: StringName, message: String, data: Variant = null) -> void:
	_record(Level.DEBUG, category, message, data)

func info(category: StringName, message: String, data: Variant = null) -> void:
	_record(Level.INFO, category, message, data)

func warn(category: StringName, message: String, data: Variant = null) -> void:
	_record(Level.WARN, category, message, data)

func error(category: StringName, message: String, data: Variant = null) -> void:
	_record(Level.ERROR, category, message, data)

func _record(level: int, category: StringName, message: String, data: Variant) -> void:
	if not enabled:
		return
	if level < min_level:
		return
	if category_filter.get(category, true) == false:
		return
	var record := {
		level = level,
		category = category,
		message = message,
		data = data,
		time_msec = Time.get_ticks_msec(),
	}
	captured.append(record)
	if console_enabled:
		print(_format(record))

const _LEVEL_NAMES: Array[String] = ["TRACE", "DEBUG", "INFO ", "WARN ", "ERROR"]

func _format(record: Dictionary) -> String:
	var lvl := _LEVEL_NAMES[record.level]
	var cat: String = String(record.category).rpad(8)
	var line: String = "[%s] [%s] %s" % [lvl, cat, record.message]
	if record.data != null:
		line += " " + JSON.stringify(record.data)
	return line
