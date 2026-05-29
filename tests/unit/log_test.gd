extends GutTest

## Tests for the Log autoload — minimal level + category filter, captured sink for assertions.

func before_each() -> void:
	Log.captured.clear()
	Log.enabled = true
	Log.min_level = Log.Level.TRACE
	Log.category_filter.clear()

func test_records_messages_into_captured_sink() -> void:
	Log.info(&"test", "hello", {n = 1})
	assert_eq(Log.captured.size(), 1)
	var rec: Dictionary = Log.captured[0]
	assert_eq(rec.level, Log.Level.INFO)
	assert_eq(rec.category, &"test")
	assert_eq(rec.message, "hello")
	assert_eq(rec.data.n, 1)

func test_min_level_drops_lower_records() -> void:
	Log.min_level = Log.Level.WARN
	Log.debug(&"test", "should drop")
	Log.warn(&"test", "should keep")
	assert_eq(Log.captured.size(), 1)
	assert_eq(Log.captured[0].level, Log.Level.WARN)

func test_category_blacklist_filters() -> void:
	Log.category_filter[&"noisy"] = false
	Log.info(&"noisy", "drop me")
	Log.info(&"quiet", "keep me")
	assert_eq(Log.captured.size(), 1)
	assert_eq(Log.captured[0].category, &"quiet")

func test_disabled_log_records_nothing() -> void:
	Log.enabled = false
	Log.error(&"test", "blackout")
	assert_eq(Log.captured.size(), 0)

func test_all_five_levels_routed() -> void:
	Log.trace(&"test", "t")
	Log.debug(&"test", "d")
	Log.info(&"test", "i")
	Log.warn(&"test", "w")
	Log.error(&"test", "e")
	assert_eq(Log.captured.size(), 5)
	assert_eq(Log.captured[0].level, Log.Level.TRACE)
	assert_eq(Log.captured[4].level, Log.Level.ERROR)

func test_silent_level_drops_every_record() -> void:
	# SILENT is the kill switch — even ERROR must be filtered.
	Log.min_level = Log.Level.SILENT
	Log.error(&"test", "should drop")
	Log.warn(&"test", "should drop")
	assert_eq(Log.captured.size(), 0)

func test_category_default_is_allow() -> void:
	# Categories absent from the filter dictionary must default to allowed
	# (the filter is a blacklist, not a whitelist).
	Log.category_filter[&"blocked"] = false
	Log.info(&"never_seen_before", "ok")
	assert_eq(Log.captured.size(), 1)
	assert_eq(Log.captured[0].category, &"never_seen_before")

func test_explicit_true_in_category_filter_keeps_record() -> void:
	Log.category_filter[&"keep"] = true
	Log.info(&"keep", "ok")
	assert_eq(Log.captured.size(), 1)

func test_record_data_is_null_when_omitted() -> void:
	Log.info(&"test", "no payload")
	assert_eq(Log.captured.size(), 1)
	assert_null(Log.captured[0].data)

func test_records_preserve_insertion_order() -> void:
	Log.info(&"test", "first")
	Log.info(&"test", "second")
	Log.info(&"test", "third")
	assert_eq(Log.captured[0].message, "first")
	assert_eq(Log.captured[1].message, "second")
	assert_eq(Log.captured[2].message, "third")
