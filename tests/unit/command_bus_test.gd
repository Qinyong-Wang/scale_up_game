extends GutTest

## Tests for the CommandBus autoload — fan-in command dispatch with single-handler-per-cmd contract.
##
## Note: we DO NOT clear `_handlers` between tests. Autoloads register handlers in `_ready()`,
## which runs once per process; clearing would permanently break other systems' registrations
## for the rest of the run. Each test uses a unique command name and `replace = true`
## to keep test-local registrations idempotent.

func test_register_and_send_returns_handler_result() -> void:
	CommandBus.register(&"test.echo", func(p: Dictionary) -> Dictionary:
		return {ok = true, payload = p}, true)
	var r: Dictionary = CommandBus.send(&"test.echo", {a = 1})
	assert_true(r.ok)
	assert_eq(r.payload.a, 1)

func test_send_unknown_command_returns_error() -> void:
	var r: Dictionary = CommandBus.send(&"nonexistent.cmd", {})
	assert_false(r.ok)
	assert_eq(r.error, &"unknown_command")

func test_register_twice_replaces_handler_when_replace_true() -> void:
	CommandBus.register(&"test.replace", func(_p): return {ok = true, v = 1}, true)
	CommandBus.register(&"test.replace", func(_p): return {ok = true, v = 2}, true)
	var r: Dictionary = CommandBus.send(&"test.replace", {})
	assert_eq(r.v, 2)

func test_send_with_default_payload() -> void:
	CommandBus.register(&"test.noarg", func(p: Dictionary) -> Dictionary:
		return {ok = true, size = p.size()}, true)
	var r: Dictionary = CommandBus.send(&"test.noarg")
	assert_true(r.ok)
	assert_eq(r.size, 0)

func test_register_without_replace_keeps_original_handler() -> void:
	# Without replace=true the second registration must be ignored, so the
	# handler from the FIRST register call still wins. This guards against
	# accidental fan-in collisions (two systems claiming the same command).
	CommandBus.register(&"test.no_replace", func(_p): return {ok = true, v = &"first"}, true)
	CommandBus.register(&"test.no_replace", func(_p): return {ok = true, v = &"second"})
	var r: Dictionary = CommandBus.send(&"test.no_replace", {})
	assert_eq(r.v, &"first")

func test_handler_failure_result_passes_through_verbatim() -> void:
	# The bus must not rewrite a handler's failure response — callers rely on
	# the `error` field being whatever the handler set (e.g. economy.spend
	# returning &"insufficient_funds" once that path lands).
	CommandBus.register(&"test.failure",
		func(_p): return {ok = false, error = &"custom_reason", detail = 42}, true)
	var r: Dictionary = CommandBus.send(&"test.failure", {})
	assert_false(r.ok)
	assert_eq(r.error, &"custom_reason")
	assert_eq(r.detail, 42)

func test_distinct_string_names_do_not_collide() -> void:
	CommandBus.register(&"test.alpha", func(_p): return {ok = true, who = &"alpha"}, true)
	CommandBus.register(&"test.beta", func(_p): return {ok = true, who = &"beta"}, true)
	assert_eq(CommandBus.send(&"test.alpha", {}).who, &"alpha")
	assert_eq(CommandBus.send(&"test.beta", {}).who, &"beta")
