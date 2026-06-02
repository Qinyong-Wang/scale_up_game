extends GutTest

## Save/load — JSON snapshot round-trip + version/corruption gating.
## Per design/游戏基础架构设计.md §6.

const TEST_SLOT := &"unit_test_save"

func before_each() -> void:
	Save.save_dir = "user://test_saves"
	GameState.reset()
	Save.delete_slot(TEST_SLOT)

func after_each() -> void:
	Save.delete_slot(TEST_SLOT)
	Save.save_dir = Save.DEFAULT_SAVE_DIR

func _seed_some_state() -> Dictionary:
	# Drive a small slice end-to-end so every slice has data.
	var lead := Lead.new()
	lead.id = &"lead_seed"; lead.specialty = &"chief_scientist"; lead.level = &"S"
	lead.ability = 90.0; lead.signing_fee = 0
	GameState.leads.append(lead)
	CommandBus.send(&"hiring.adjust_staff", {role = &"ml_eng", delta = 3})
	var rdc: Dictionary = CommandBus.send(&"infra.debug_instant_owned_dc", {facility_spec_id = &"facility_solo", gpu_id = &"cypress_t0"})
	CommandBus.send(&"dataset.acquire_open", {template_id = &"web_corpus_v1"})
	var rt: Dictionary = CommandBus.send(&"task.start", {
		template_id = &"train_sparrow_s", lead_ids = [lead.id],
		staff = {&"ml_eng": 2}, datacenter_id = rdc.dc_id,
		dataset_ids = [&"web_corpus_v1"],
	})
	for i in range(int(rt.total_weeks)):
		EventBus.phase_started.emit(&"action", i + 1)
	# At this point: 1 model, 1 lead idle, 1 dataset, 1 dc idle.
	# v7 PR-F: fame field deleted; nothing to seed there.
	GameState.paid_users = 42
	GameState.unlocks[&"engineering"][&"owl_cache"] = true
	return {
		dc_id = rdc.dc_id,
		model_id = GameState.models[0].id,
		lead_id = lead.id,
	}

# ---- write / read round-trip --------------------------------------------

func test_write_creates_file_and_returns_path() -> void:
	var r: Dictionary = Save.write(TEST_SLOT)
	assert_true(r.ok)
	assert_true(FileAccess.file_exists(r.path))

func test_round_trip_restores_resources() -> void:
	_seed_some_state()
	var snap_cash: int = GameState.cash
	var snap_users: int = GameState.paid_users
	var snap_models: int = GameState.models.size()
	Save.write(TEST_SLOT)

	# Mutate then load → state should be restored.
	GameState.cash = -999
	GameState.paid_users = 0
	GameState.models.clear()
	var r: Dictionary = Save.read(TEST_SLOT)
	assert_true(r.ok)
	assert_eq(GameState.cash, snap_cash)
	assert_eq(GameState.paid_users, snap_users)
	assert_eq(GameState.models.size(), snap_models)

func test_round_trip_restores_assets_with_typed_subclasses() -> void:
	var ids := _seed_some_state()
	Save.write(TEST_SLOT)
	GameState.reset()
	Save.read(TEST_SLOT)
	# Models are restored as Model instances.
	var m = GameState.models[0]
	assert_eq(m.id, ids.model_id)
	assert_eq(m.get_script(), preload("res://scripts/resources/model.gd"))
	# Datacenters are restored as Datacenter instances.
	var dc = GameState.datacenters[0]
	assert_eq(dc.id, ids.dc_id)
	assert_eq(dc.get_script(), preload("res://scripts/resources/datacenter.gd"))
	# Lead.
	var l = GameState.leads[0]
	assert_eq(l.id, ids.lead_id)
	assert_eq(l.specialty, &"chief_scientist")

func test_round_trip_restores_api_token_demand() -> void:
	# UserSystem 写, MonetizationSystem 读. 不进存档会让读档后第一周的收入算错。
	GameState.api_token_demand = {&"m_a": 12345, &"m_b": 678}
	Save.write(TEST_SLOT)
	GameState.api_token_demand = {}
	Save.read(TEST_SLOT)
	assert_eq(int(GameState.api_token_demand.get(&"m_a", 0)), 12345)
	assert_eq(int(GameState.api_token_demand.get(&"m_b", 0)), 678)

func test_round_trip_restores_unlocks_with_string_name_keys() -> void:
	_seed_some_state()
	Save.write(TEST_SLOT)
	GameState.reset()
	Save.read(TEST_SLOT)
	# Both pre-seeded ant_v1 and the test-set owl_cache should survive.
	assert_true(bool(GameState.unlocks.get(&"arch", {}).get(&"ant_v1", false)))
	assert_true(bool(GameState.unlocks.get(&"engineering", {}).get(&"owl_cache", false)))

func test_round_trip_restores_active_task_and_locks() -> void:
	# Start a long task and save mid-flight. v2 changed the data factor to
	# source-based min (0.9 for open) rather than the old quality average, so
	# we use train_otter_m (800M model) to keep duration > 1 turn even with a
	# lead in the seat.
	var lead := Lead.new()
	lead.id = &"lead_long"; lead.specialty = &"chief_scientist"; lead.level = &"S"
	lead.ability = 92.0
	GameState.leads.append(lead)
	CommandBus.send(&"hiring.adjust_staff", {role = &"ml_eng", delta = 2})
	var rdc: Dictionary = CommandBus.send(&"infra.debug_instant_owned_dc", {facility_spec_id = &"facility_solo", gpu_id = &"cypress_t0"})
	CommandBus.send(&"dataset.acquire_open", {template_id = &"web_corpus_v1"})
	var r: Dictionary = CommandBus.send(&"task.start", {
		template_id = &"train_otter_m", lead_ids = [lead.id],
		staff = {&"ml_eng": 1}, datacenter_id = rdc.dc_id,
		dataset_ids = [&"web_corpus_v1"],
	})
	assert_true(r.ok)
	assert_gt(int(r.total_weeks), 1,
			"task must take >1 turn so we can save mid-flight")
	# Advance one month, then save.
	EventBus.phase_started.emit(&"action", 1)
	Save.write(TEST_SLOT)
	GameState.reset()
	Save.read(TEST_SLOT)
	assert_eq(GameState.active_tasks.size(), 1)
	var t = GameState.active_tasks[0]
	assert_eq(t.id, r.task_id)
	assert_eq(t.elapsed_weeks, 1)
	assert_eq(t.locked_datacenter_id, rdc.dc_id)
	assert_true(t.locked_lead_ids.has(lead.id))

func test_round_trip_restores_construction_queue() -> void:
	GameState.cash = 10_000_000
	var r: Dictionary = CommandBus.send(&"infra.build_facility", {
		facility_spec_id = &"facility_pod",
		power_supply_id = &"grid",
		gpu_id = &"cypress_t0",
	})
	assert_true(r.ok)
	assert_eq(GameState.construction_queue.size(), 1)
	var construction_id: StringName = GameState.construction_queue[0].id
	Save.write(TEST_SLOT)

	GameState.reset()
	Save.read(TEST_SLOT)

	assert_eq(GameState.construction_queue.size(), 1)
	var c = GameState.construction_queue[0]
	assert_eq(c.get_script(), preload("res://scripts/resources/datacenter_construction.gd"))
	assert_eq(c.id, construction_id)
	assert_eq(c.facility_spec_id, &"facility_pod")
	assert_eq(c.power_supply, &"grid")
	assert_eq(c.gpu_id, &"cypress_t0")
	assert_eq(c.weeks_remaining, 1)
	assert_eq(c.total_weeks, 1)

func test_read_missing_slot_returns_not_found() -> void:
	var r: Dictionary = Save.read(&"definitely_does_not_exist")
	assert_false(r.ok)
	assert_eq(r.error, &"not_found")

func test_read_corrupted_file_returns_corrupted() -> void:
	Save._ensure_dir()
	var path: String = "%s/%s.json" % [Save.save_dir, String(TEST_SLOT)]
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("{not valid json")
	f.close()
	var r: Dictionary = Save.read(TEST_SLOT)
	assert_false(r.ok)
	assert_eq(r.error, &"corrupted")

func test_read_wrong_version_rejected() -> void:
	Save._ensure_dir()
	var path: String = "%s/%s.json" % [Save.save_dir, String(TEST_SLOT)]
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({version = 9999, state = {}}))
	f.close()
	var r: Dictionary = Save.read(TEST_SLOT)
	assert_false(r.ok)
	assert_eq(r.error, &"incompatible_version")

func test_save_loaded_signal_emitted_on_read() -> void:
	Save.write(TEST_SLOT)
	watch_signals(EventBus)
	Save.read(TEST_SLOT)
	assert_signal_emitted(EventBus, "save_loaded")

func test_list_slots_includes_written_slot() -> void:
	Save.write(TEST_SLOT)
	var slots: Array = Save.list_slots()
	assert_true(slots.has(TEST_SLOT))

func test_rng_state_survives_save_load() -> void:
	# Advance the stream by N draws, save, and capture what the next draw
	# would have been. After reset+load, the next draw must match.
	GameState.rng_seed = 12345
	GameState._rng = null
	for i in range(5):
		GameState.rng().randi()
	Save.write(TEST_SLOT)
	var expected_next: int = GameState.rng().randi()

	GameState.reset()
	Save.read(TEST_SLOT)
	assert_eq(GameState.rng().randi(), expected_next)
