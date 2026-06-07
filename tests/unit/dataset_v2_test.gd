extends GutTest

## DatasetSystem v2 — kind split + time-gated release + pretrain quality min.
## Per design/数据集系统设计.md §1 / §6 + 平衡参数.md Pretrain 乘子表。


func before_each() -> void:
	GameState.reset()

# ---- kind field ---------------------------------------------------------

func test_acquired_pretrain_template_has_kind_pretrain() -> void:
	var r: Dictionary = CommandBus.send(&"dataset.acquire_open",
			{template_id = &"bookcorpus_v1"})
	assert_true(r.ok, "bookcorpus_v1 should be a turn-0 pretrain open template")
	var ds := DatasetSystem.find_dataset(&"bookcorpus_v1")
	assert_not_null(ds)
	assert_eq(ds.kind, &"pretrain")

func test_acquired_posttrain_template_has_kind_posttrain_and_target() -> void:
	# agent_traces_v1 is a 2023 H1 posttrain template (turn 312). Bump turn
	# to a date past its release before purchasing.
	GameState.turn = 400
	var r: Dictionary = CommandBus.send(&"dataset.purchase",
			{template_id = &"agent_traces_v1"})
	assert_true(r.ok)
	var ds := DatasetSystem.find_dataset(&"agent_traces_v1")
	assert_not_null(ds)
	assert_eq(ds.kind, &"posttrain")
	assert_eq(ds.target_capability, &"agent")

# ---- pretrain_quality_multiplier (v9: deprecated, always 1.0) -----------

func test_pretrain_multiplier_always_returns_one_in_v9() -> void:
	# v9 (2026-05): source field no longer drives a global score multiplier.
	# The function is kept for API compatibility with old save fixtures and
	# returns 1.0 across all sources. The real per-dataset effect now flows
	# through ds.quality + ds.size in TaskSystem._compute_capability_measured.
	for src in [&"open_source", &"purchased", &"collected"]:
		var ds := Dataset.new()
		ds.kind = &"pretrain"
		ds.source = src
		assert_almost_eq(ds.pretrain_quality_multiplier(), 1.0, 0.001,
				"v9: pretrain_quality_multiplier deprecated, must return 1.0 for source %s" % src)

func test_posttrain_dataset_multiplier_is_neutral() -> void:
	var ds := Dataset.new()
	ds.kind = &"posttrain"
	ds.source = &"open_source"
	assert_almost_eq(ds.pretrain_quality_multiplier(), 1.0, 0.001)

# ---- time-gated release (released_at_week) ------------------------------

func test_acquire_open_future_template_returns_not_released_yet() -> void:
	# alpaca_52k_v1 has released_at_week=286. At turn 0 it should be hidden.
	GameState.turn = 0
	var r: Dictionary = CommandBus.send(&"dataset.acquire_open",
			{template_id = &"alpaca_52k_v1"})
	assert_false(r.ok)
	assert_eq(r.error, &"not_released_yet")

func test_acquire_open_after_release_succeeds() -> void:
	GameState.turn = 300  # past alpaca's 286
	var r: Dictionary = CommandBus.send(&"dataset.acquire_open",
			{template_id = &"alpaca_52k_v1"})
	assert_true(r.ok, "alpaca_52k_v1 should be available at turn 300")

func test_purchase_future_template_returns_not_released_yet() -> void:
	# code_review_pairs_v1 released_at_week=312
	GameState.turn = 100
	var r: Dictionary = CommandBus.send(&"dataset.purchase",
			{template_id = &"code_review_pairs_v1"})
	assert_false(r.ok)
	assert_eq(r.error, &"not_released_yet")

# ---- list_market filtering ----------------------------------------------

func test_list_market_filters_by_kind() -> void:
	GameState.turn = 500  # past everything
	var r: Dictionary = CommandBus.send(&"dataset.list_market", {kind = &"posttrain"})
	assert_true(r.ok)
	for item in (r.items as Array):
		assert_eq(StringName(item.kind), &"posttrain")

func test_list_market_filters_by_source() -> void:
	GameState.turn = 500
	var r: Dictionary = CommandBus.send(&"dataset.list_market", {source = &"purchased"})
	assert_true(r.ok)
	for item in (r.items as Array):
		assert_eq(StringName(item.source), &"purchased")

func test_list_market_hides_future_templates() -> void:
	GameState.turn = 0
	var r: Dictionary = CommandBus.send(&"dataset.list_market", {})
	for item in (r.items as Array):
		assert_lte(int(item.released_at_week), 0,
			"list_market must not surface templates with future release week")

func test_list_market_hides_already_owned() -> void:
	CommandBus.send(&"dataset.acquire_open", {template_id = &"bookcorpus_v1"})
	var r: Dictionary = CommandBus.send(&"dataset.list_market", {})
	for item in (r.items as Array):
		assert_ne(StringName(item.id), &"bookcorpus_v1",
			"owned templates should not appear in market list")

func test_news_archive_carries_hidden_business_analysis_tag() -> void:
	# The tag is hidden in UI, but the template must carry it so evaluate can
	# apply the small code/reasoning/agent black-humor penalty.
	GameState.turn = 0
	var r: Dictionary = CommandBus.send(&"dataset.list_market", {kind = &"pretrain"})
	assert_true(r.ok)
	var found: bool = false
	for item in (r.items as Array):
		if StringName(item.id) != &"news_archive_2017q2":
			continue
		found = true
		assert_true((item.coverage_tags as Array).has("business_analysis"),
				"news archive should carry hidden business_analysis tag")
	assert_true(found, "news_archive_2017q2 should be available at turn 0")

# ---- dataset_market_updated signal at half-year boundary ----------------

func test_market_updated_signal_fires_at_half_year() -> void:
	watch_signals(EventBus)
	GameState.turn = 26  # half-year boundary
	EventBus.phase_started.emit(&"action", 26)
	assert_signal_emitted(EventBus, "dataset_market_updated")

func test_market_updated_signal_does_not_fire_mid_period() -> void:
	watch_signals(EventBus)
	GameState.turn = 13  # mid-period, not a boundary
	EventBus.phase_started.emit(&"action", 13)
	assert_signal_not_emitted(EventBus, "dataset_market_updated")

# ---- to_dict / from_dict roundtrip preserves new fields -----------------

func test_dataset_roundtrip_preserves_kind_and_target_capability() -> void:
	var src := Dataset.new()
	src.id = &"ds_round"
	src.kind = &"posttrain"
	src.source = &"purchased"
	src.size = 0.05
	src.quality = 0.85
	src.target_capability = &"code"
	var dst: Dataset = Dataset.from_dict(src.to_dict())
	assert_eq(dst.kind, &"posttrain")
	assert_eq(dst.target_capability, &"code")

# ---- save_loaded: ds_collected ID 计数器恢复 + 重复修复 ------------------

func _collected(id: StringName, locked_by: StringName = &"") -> Dataset:
	var ds := Dataset.new()
	ds.id = id
	ds.kind = &"pretrain"
	ds.source = &"collected"
	ds.size = 1.0
	ds.locked_by_task_id = locked_by
	return ds

func test_save_loaded_restores_collected_id_counter() -> void:
	# 读档后 _next_dataset_seq 必须跳到档内现存 ds_collected_NNNN 最大编号之后,
	# 否则新采集的数据集会和读档进来的撞 ID (already_locked 的根因)。
	GameState.datasets.append(_collected(&"ds_collected_0005"))
	EventBus.save_loaded.emit()
	var r: Dictionary = CommandBus.send(&"dataset.add",
			{kind = &"pretrain", source = &"collected", size = 1.0})
	assert_true(r.ok)
	var new_seq: int = String(r.dataset_id).trim_prefix("ds_collected_").to_int()
	assert_gt(new_seq, 5,
			"读档后采集的数据集 ID 不能复用 ≤0005 (实际 %s)" % r.dataset_id)

func test_save_loaded_repairs_duplicate_dataset_ids() -> void:
	# 旧 buggy 存档可能已含两个同 ID 的 ds_collected — find_dataset 只返回第一个,
	# 训练时 dataset.lock 解析错副本 → already_locked。读档后必须去重。
	GameState.datasets.append(_collected(&"ds_collected_0001", &"task_a"))
	GameState.datasets.append(_collected(&"ds_collected_0001"))
	EventBus.save_loaded.emit()
	var seen: Dictionary = {}
	for ds in GameState.datasets:
		assert_false(seen.has(ds.id), "dataset id %s 读档后仍重复" % ds.id)
		seen[ds.id] = true

func test_save_loaded_re_id_clears_stale_lock_on_duplicate_dataset() -> void:
	# find_dataset 总驱动首个副本; 被重发 ID 的副本上的残留锁是死锁, 要清掉,
	# 否则它读档后变成一个永远 already_locked 的不可用数据集。
	var a := _collected(&"ds_collected_0002")
	var b := _collected(&"ds_collected_0002", &"stale_task")
	GameState.datasets.append(a)
	GameState.datasets.append(b)
	EventBus.save_loaded.emit()
	assert_eq(a.id, &"ds_collected_0002", "首个副本保留原 ID")
	assert_ne(b.id, &"ds_collected_0002", "第二个副本必须重发 ID")
	assert_eq(b.locked_by_task_id, &"", "重发 ID 的副本残留锁必须清掉")
