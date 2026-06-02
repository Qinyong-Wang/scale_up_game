extends GutTest

## End-to-end: a player calls `task.start` for a pretrain template, advances
## turns via TurnManager.advance(), and at the end has +1 model in their
## library and -base_cost cash. This exercises the real signal chain
## (TurnManager → phase_started → TaskSystem → research.add_model).

const TEMPLATE_SPARROW_S := &"train_sparrow_s"

func before_each() -> void:
	GameState.reset()

func test_full_pretrain_lifecycle_yields_one_model() -> void:
	var initial_money: int = GameState.resources[&"money"]

	# 1. Player starts a pretrain task. Per design §1, pretrain templates
	#    have base_cost = 0 — the resource lock IS the cost. So cash is unchanged.
	var r: Dictionary = CommandBus.send(&"task.start", {template_id = TEMPLATE_SPARROW_S})
	assert_true(r.ok, "task.start should succeed")
	assert_eq(GameState.active_tasks.size(), 1)
	assert_eq(GameState.models.size(), 0, "no model yet — training in progress")
	assert_eq(GameState.resources[&"money"], initial_money,
			"pretrain base_cost is 0, cash unchanged")

	# 2. Advance turns equal to the template's total_weeks. After the last
	#    action phase the task should complete and produce a Model.
	for _i in range(r.total_weeks):
		TurnManager.advance()

	# 3. State assertions.
	assert_eq(GameState.active_tasks.size(), 0, "task should be cleaned up")
	assert_eq(GameState.models.size(), 1, "one model produced")
	var m = GameState.models[0]
	# sparrow_s outputs ant_v1 per 公共枚举表.md §7 / 平衡参数.md §TaskSystem.
	assert_eq(m.arch, &"ant_v1")
	# Per design §6.4: capability stays unset after pretrain — evaluate sets it.
	assert_eq(int(m.capability.get(&"general", 0)), 0,
			"capability must not be preset by pretrain")
	assert_eq(m.status, &"pretrained", "freshly trained model is pretrained until evaluate/publish")

func test_progress_signals_arrive_each_action_phase() -> void:
	var progress_log: Array = []
	EventBus.task_progress.connect(func(id: StringName, elapsed: int, total: int) -> void:
		progress_log.append({id = id, elapsed = elapsed, total = total}))

	var r: Dictionary = CommandBus.send(&"task.start", {template_id = TEMPLATE_SPARROW_S})
	for _i in range(r.total_weeks):
		TurnManager.advance()

	assert_eq(progress_log.size(), r.total_weeks)
	for i in range(progress_log.size()):
		assert_eq(progress_log[i].elapsed, i + 1)
		assert_eq(progress_log[i].total, r.total_weeks)

func test_two_pretrains_in_sequence_yield_two_models() -> void:
	# Run one pretrain to completion, then start another.
	var r1: Dictionary = CommandBus.send(&"task.start", {template_id = TEMPLATE_SPARROW_S})
	for _i in range(r1.total_weeks):
		TurnManager.advance()
	assert_eq(GameState.models.size(), 1)

	var r2: Dictionary = CommandBus.send(&"task.start", {template_id = TEMPLATE_SPARROW_S})
	for _i in range(r2.total_weeks):
		TurnManager.advance()
	assert_eq(GameState.models.size(), 2)
	assert_ne(GameState.models[0].id, GameState.models[1].id, "model ids should differ")
