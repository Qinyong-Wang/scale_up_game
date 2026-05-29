extends Node

## SimulationSystem — owns the universe-simulation capstone ladder
## (simulation_stages_done). Per design/宇宙模拟工程设计.md.
##
## 5 stages unlock in order (weather → ocean → earth → solar_system → universe).
## Each stage runs as a `simulation` TaskSystem task (funding charged up front,
## tax-deductible; runs `weeks`; completion advances the ladder). Starting a
## stage requires the player to DONATE one self-owned, idle datacenter whose
## train_tflops ≥ min_train_tflops (the donated dc is permanently removed) + cash
## ≥ cost. Finishing the last stage reveals "42" and awards universe_answer.

const STAGE_PATHS: Dictionary = {
	&"weather":      "res://resources/data/simulation/weather.tres",
	&"ocean":        "res://resources/data/simulation/ocean.tres",
	&"earth":        "res://resources/data/simulation/earth.tres",
	&"solar_system": "res://resources/data/simulation/solar_system.tres",
	&"universe":     "res://resources/data/simulation/universe.tres",
}
const SIMULATION_TEMPLATE_ID: StringName = &"simulation_stage"
const UNIVERSE_TROPHY_ID: StringName = &"universe_answer"

var _stages: Array = []   # SimulationStageSpec, sorted by order

func _ready() -> void:
	_load_tables()
	CommandBus.register(&"simulation.start_stage", _on_start_stage)
	CommandBus.register(&"simulation.complete_stage", _on_complete_stage)

func _load_tables() -> void:
	_stages.clear()
	for id in STAGE_PATHS.keys():
		var spec := load(STAGE_PATHS[id])
		if spec is SimulationStageSpec:
			_stages.append(spec)
		else:
			Log.warn(&"simulation", "stage_spec_missing", {id = id})
	_stages.sort_custom(func(a, b): return int(a.order) < int(b.order))

# ---- introspection ------------------------------------------------------

func all_stages() -> Array:
	if _stages.is_empty():
		_load_tables()
	return _stages

func total_stages() -> int:
	return all_stages().size()

func stages_done() -> int:
	return int(GameState.simulation_stages_done)

## Index of the next stage that can be started (-1 when all done).
func next_stage_index() -> int:
	var done: int = stages_done()
	if done >= total_stages():
		return -1
	return done

func stage_at(index: int) -> SimulationStageSpec:
	var stages: Array = all_stages()
	if index < 0 or index >= stages.size():
		return null
	return stages[index]

func spec_for(stage_id: StringName) -> SimulationStageSpec:
	for s in all_stages():
		if s.id == stage_id:
			return s
	return null

## A simulation stage is currently computing.
func is_running() -> bool:
	for t in GameState.active_tasks:
		if t.subtype == &"simulation":
			return true
	return false

## A datacenter qualifies to be donated to `spec` when it is self-owned, idle,
## not rented out to the compute platform, and its real training compute clears
## the stage's FLOPs gate.
func dc_meets_gate(dc, spec: SimulationStageSpec) -> bool:
	if dc == null or spec == null:
		return false
	return (dc.ownership == &"owned"
			and dc.status == &"idle"
			and not bool(dc.rent_out_enabled)
			and float(dc.train_tflops) >= float(spec.min_train_tflops))

## All datacenters the player could donate to `spec` (self-owned, idle, not
## rented out, big enough). The donation dialog lists these; one is consumed on
## start.
func eligible_datacenters(spec: SimulationStageSpec) -> Array:
	var out: Array = []
	for dc in GameState.datacenters:
		if dc_meets_gate(dc, spec):
			out.append(dc)
	return out

func _find_dc(dc_id: StringName):
	for dc in GameState.datacenters:
		if dc.id == dc_id:
			return dc
	return null

func universe_revealed() -> bool:
	return stages_done() >= total_stages()

# ---- commands -----------------------------------------------------------

## simulation.start_stage {dc_id} — start the next stage by donating a datacenter.
## The chosen dc must be self-owned + idle + meet the stage's FLOPs gate; on
## success it is PERMANENTLY removed (no GPU resale refund) and `cost` is charged.
func _on_start_stage(p: Dictionary) -> Dictionary:
	var idx: int = next_stage_index()
	if idx < 0:
		return {ok = false, error = &"all_done"}
	if is_running():
		return {ok = false, error = &"already_running"}
	var spec := stage_at(idx)
	if spec == null:
		return {ok = false, error = &"all_done"}
	var dc_id: StringName = StringName(p.get(&"dc_id", p.get("dc_id", &"")))
	var dc = _find_dc(dc_id)
	if dc == null:
		return {ok = false, error = &"unknown_dc"}
	if dc.ownership != &"owned":
		return {ok = false, error = &"dc_not_owned"}
	if dc.status != &"idle":
		return {ok = false, error = &"dc_busy"}
	if bool(dc.rent_out_enabled):
		return {ok = false, error = &"dc_rented_out"}
	if float(dc.train_tflops) < float(spec.min_train_tflops):
		return {ok = false, error = &"compute_too_small"}
	if int(spec.cost) > GameState.cash:
		return {ok = false, error = &"insufficient_cash"}
	var r: Dictionary = CommandBus.send(&"task.start", {
		template_id = SIMULATION_TEMPLATE_ID,
		stage_id = spec.id,
		amount = int(spec.cost),
		weeks = maxi(1, int(spec.weeks)),
	})
	if not r.get(&"ok", false):
		return r
	# Consume the donated datacenter (permanent, no GPU resale refund). Idle-only,
	# so there is no serving/training to unwind. Done after task.start succeeds so
	# a failed start never silently eats the dc.
	GameState.datacenters.erase(dc)
	EventBus.datacenter_removed.emit(dc.id)
	Log.info(&"simulation", "datacenter donated", {
		stage = spec.id, dc_id = dc.id, train_tflops = dc.train_tflops,
	})
	Log.info(&"simulation", "stage started", {
		stage = spec.id, cost = spec.cost, weeks = spec.weeks,
		donated_dc_id = dc.id, task_id = r.get(&"task_id", &""),
	})
	return {ok = true, task_id = r.get(&"task_id", &""),
			stage_id = spec.id, cost = int(spec.cost), weeks = int(spec.weeks),
			donated_dc_id = dc.id}

## simulation.complete_stage {stage_id} — TaskSystem completion callback.
func _on_complete_stage(p: Dictionary) -> Dictionary:
	var stage_id: StringName = StringName(p.get(&"stage_id", p.get("stage_id", &"")))
	var spec := spec_for(stage_id)
	if spec == null:
		return {ok = false, error = &"unknown_stage"}
	GameState.simulation_stages_done = maxi(
			int(GameState.simulation_stages_done), int(spec.order) + 1)
	var done: int = stages_done()
	Log.info(&"simulation", "stage completed", {stage = stage_id, stages_done = done})
	EventBus.simulation_stage_completed.emit(stage_id, done)
	# Last stage (universe) → reveal 42 + award the trophy.
	if int(spec.order) == total_stages() - 1:
		CollectionSystem.award_trophy(UNIVERSE_TROPHY_ID)
		Log.info(&"simulation", "universe answer revealed", {answer = 42})
		EventBus.universe_answer_revealed.emit()
	return {ok = true, stages_done = done}
