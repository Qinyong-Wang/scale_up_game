extends GutTest

## EconomySystem v0 — only `economy.spend` / `economy.award`.
## Per design/经济系统设计.md §2: spend never fails (cash may go negative);
## the bankruptcy gate handles persistent negativity (deferred to v1).

func before_each() -> void:
	GameState.reset()

func test_spend_decrements_money_and_returns_ok() -> void:
	var before: int = GameState.resources[&"money"]
	var r: Dictionary = CommandBus.send(&"economy.spend",
		{cost = {&"money": 500}, reason = &"test"})
	assert_true(r.ok)
	assert_eq(GameState.resources[&"money"], before - 500)

func test_spend_allows_negative_balance() -> void:
	GameState.cash = 100
	GameState.resources[&"money"] = 100
	var r: Dictionary = CommandBus.send(&"economy.spend",
		{cost = {&"money": 500}, reason = &"test"})
	assert_true(r.ok)
	assert_eq(GameState.resources[&"money"], -400)
	assert_eq(GameState.cash, -400)

func test_award_increments_money() -> void:
	var before: int = GameState.resources[&"money"]
	var r: Dictionary = CommandBus.send(&"economy.award",
		{amount = 250, reason = &"test"})
	assert_true(r.ok)
	assert_eq(GameState.resources[&"money"], before + 250)

func test_spend_emits_resources_changed_with_negative_delta() -> void:
	watch_signals(EventBus)
	CommandBus.send(&"economy.spend", {cost = {&"money": 500}, reason = &"task_start"})
	assert_signal_emitted(EventBus, "resources_changed")
	var params: Array = get_signal_parameters(EventBus, "resources_changed")
	# params[0] is the args of the latest emit
	var delta: Dictionary = params[0]
	var reason: StringName = params[1]
	assert_eq(delta[&"money"], -500)
	assert_eq(reason, &"task_start")

func test_award_emits_resources_changed_with_positive_delta() -> void:
	watch_signals(EventBus)
	CommandBus.send(&"economy.award", {amount = 250, reason = &"refund"})
	var params: Array = get_signal_parameters(EventBus, "resources_changed")
	var delta: Dictionary = params[0]
	assert_eq(delta[&"money"], 250)
	assert_eq(params[1], &"refund")

func test_spend_with_multiple_resource_keys_decrements_each() -> void:
	GameState.cash = 1000
	GameState.resources[&"money"] = 1000
	GameState.resources[&"compute"] = 50
	var r: Dictionary = CommandBus.send(&"economy.spend",
		{cost = {&"money": 200, &"compute": 10}, reason = &"task_start"})
	assert_true(r.ok)
	assert_eq(GameState.resources[&"money"], 800)
	assert_eq(GameState.resources[&"compute"], 40)

func test_spend_emits_delta_for_every_key_in_cost() -> void:
	GameState.resources[&"compute"] = 50
	watch_signals(EventBus)
	CommandBus.send(&"economy.spend",
		{cost = {&"money": 200, &"compute": 10}, reason = &"task_start"})
	var params: Array = get_signal_parameters(EventBus, "resources_changed")
	var delta: Dictionary = params[0]
	assert_eq(delta[&"money"], -200)
	assert_eq(delta[&"compute"], -10)

func test_spend_creates_unknown_resource_key_with_negative_balance() -> void:
	# A key that wasn't seeded by reset() defaults to 0 before the subtraction.
	# This is a v0 quirk worth pinning so we notice if the policy changes.
	assert_false(GameState.resources.has(&"datasets"))
	CommandBus.send(&"economy.spend",
		{cost = {&"datasets": 5}, reason = &"test"})
	assert_eq(GameState.resources[&"datasets"], -5)

func test_sequential_spends_accumulate() -> void:
	var before: int = GameState.resources[&"money"]
	CommandBus.send(&"economy.spend", {cost = {&"money": 100}, reason = &"a"})
	CommandBus.send(&"economy.spend", {cost = {&"money": 250}, reason = &"b"})
	CommandBus.send(&"economy.spend", {cost = {&"money": 50}, reason = &"c"})
	assert_eq(GameState.resources[&"money"], before - 400)

func test_spend_with_empty_cost_emits_empty_delta_and_keeps_balance() -> void:
	var before: int = GameState.resources[&"money"]
	watch_signals(EventBus)
	var r: Dictionary = CommandBus.send(&"economy.spend", {cost = {}, reason = &"noop"})
	assert_true(r.ok)
	assert_eq(GameState.resources[&"money"], before)
	var params: Array = get_signal_parameters(EventBus, "resources_changed")
	assert_eq((params[0] as Dictionary).size(), 0)

func test_award_zero_amount_is_a_noop_on_balance() -> void:
	var before: int = GameState.resources[&"money"]
	CommandBus.send(&"economy.award", {amount = 0, reason = &"test"})
	assert_eq(GameState.resources[&"money"], before)
