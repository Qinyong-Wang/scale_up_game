extends GutTest

## DatasetSystem v1 — three sources, lock/release, dedup.
## Per design/数据集系统设计.md.

func before_each() -> void:
	GameState.reset()

# ---- acquire_open --------------------------------------------------------

func test_acquire_open_unknown_template_returns_error() -> void:
	var r: Dictionary = CommandBus.send(&"dataset.acquire_open", {template_id = &"nope"})
	assert_false(r.ok)
	assert_eq(r.error, &"unknown_template")

func test_acquire_open_purchased_template_returns_error() -> void:
	# codebase_v1 is `purchased`; trying to acquire it as open must fail.
	var r: Dictionary = CommandBus.send(&"dataset.acquire_open", {template_id = &"codebase_v1"})
	assert_false(r.ok)
	assert_eq(r.error, &"unknown_template")

func test_acquire_open_appends_dataset_and_emits_signal() -> void:
	watch_signals(EventBus)
	var r: Dictionary = CommandBus.send(&"dataset.acquire_open", {template_id = &"web_corpus_v1"})
	assert_true(r.ok)
	assert_eq(GameState.datasets.size(), 1)
	assert_eq(GameState.datasets[0].source, &"open_source")
	assert_signal_emitted(EventBus, "dataset_added")

func test_acquire_open_already_owned_returns_error() -> void:
	CommandBus.send(&"dataset.acquire_open", {template_id = &"web_corpus_v1"})
	var r: Dictionary = CommandBus.send(&"dataset.acquire_open", {template_id = &"web_corpus_v1"})
	assert_false(r.ok)
	assert_eq(r.error, &"already_owned")

# ---- purchase -----------------------------------------------------------

func test_purchase_open_template_returns_error() -> void:
	var r: Dictionary = CommandBus.send(&"dataset.purchase", {template_id = &"web_corpus_v1"})
	assert_false(r.ok)
	assert_eq(r.error, &"unknown_template")

func test_purchase_charges_price() -> void:
	var before: int = GameState.cash
	var r: Dictionary = CommandBus.send(&"dataset.purchase", {template_id = &"codebase_v1"})
	assert_true(r.ok)
	assert_eq(GameState.cash, before - 80000)

func test_purchase_already_owned_returns_error() -> void:
	CommandBus.send(&"dataset.purchase", {template_id = &"codebase_v1"})
	var r: Dictionary = CommandBus.send(&"dataset.purchase", {template_id = &"codebase_v1"})
	assert_false(r.ok)
	assert_eq(r.error, &"already_owned")

# ---- add ----------------------------------------------------------------

func test_add_appends_collected_dataset() -> void:
	var r: Dictionary = CommandBus.send(&"dataset.add", {
		size = 5.0, quality = 0.6, coverage_tags = ["chat"], source = &"collected"})
	assert_true(r.ok)
	assert_eq(GameState.datasets.size(), 1)
	assert_eq(GameState.datasets[0].source, &"collected")

# ---- delete -------------------------------------------------------------

func test_delete_unknown_returns_error() -> void:
	var r: Dictionary = CommandBus.send(&"dataset.delete", {dataset_id = &"x"})
	assert_false(r.ok)
	assert_eq(r.error, &"unknown_dataset")

func test_delete_locked_returns_error() -> void:
	var r1: Dictionary = CommandBus.send(&"dataset.acquire_open", {template_id = &"web_corpus_v1"})
	CommandBus.send(&"dataset.lock", {dataset_id = r1.dataset_id, task_id = &"t"})
	var r: Dictionary = CommandBus.send(&"dataset.delete", {dataset_id = r1.dataset_id})
	assert_false(r.ok)
	assert_eq(r.error, &"locked")

func test_delete_idle_succeeds() -> void:
	var r1: Dictionary = CommandBus.send(&"dataset.acquire_open", {template_id = &"web_corpus_v1"})
	var r: Dictionary = CommandBus.send(&"dataset.delete", {dataset_id = r1.dataset_id})
	assert_true(r.ok)
	assert_eq(GameState.datasets.size(), 0)

# ---- lock / release -----------------------------------------------------

func test_lock_unknown_returns_error() -> void:
	var r: Dictionary = CommandBus.send(&"dataset.lock", {dataset_id = &"x", task_id = &"t"})
	assert_false(r.ok)
	assert_eq(r.error, &"unknown_dataset")

func test_lock_already_locked_returns_error() -> void:
	var r1: Dictionary = CommandBus.send(&"dataset.acquire_open", {template_id = &"web_corpus_v1"})
	CommandBus.send(&"dataset.lock", {dataset_id = r1.dataset_id, task_id = &"t"})
	var r: Dictionary = CommandBus.send(&"dataset.lock", {dataset_id = r1.dataset_id, task_id = &"t2"})
	assert_false(r.ok)
	assert_eq(r.error, &"already_locked")

func test_release_wrong_task_returns_error() -> void:
	var r1: Dictionary = CommandBus.send(&"dataset.acquire_open", {template_id = &"web_corpus_v1"})
	CommandBus.send(&"dataset.lock", {dataset_id = r1.dataset_id, task_id = &"t1"})
	var r: Dictionary = CommandBus.send(&"dataset.release", {dataset_id = r1.dataset_id, task_id = &"t2"})
	assert_false(r.ok)
	assert_eq(r.error, &"not_locked_by_this_task")

# ---- template directory scan -------------------------------------------
# Per design §6.1: templates live under resources/data/datasets/*.tres and
# DatasetSystem must lazy-scan that directory so adding a .tres requires no
# code change.

func test_at_least_four_distinct_templates_loadable() -> void:
	# Acquire/purchase the four core templates we ship and assert each lands
	# as a distinct dataset with the expected `source` and `id`.
	var open_a: Dictionary = CommandBus.send(&"dataset.acquire_open", {template_id = &"web_corpus_v1"})
	var open_b: Dictionary = CommandBus.send(&"dataset.acquire_open", {template_id = &"math_reasoning_set_v1"})
	var open_c: Dictionary = CommandBus.send(&"dataset.acquire_open", {template_id = &"image_corpus_v1"})
	var pur_a: Dictionary = CommandBus.send(&"dataset.purchase", {template_id = &"polyglot_code_v1"})
	assert_true(open_a.ok, "web_corpus_v1 open template should be loadable")
	assert_true(open_b.ok, "math_reasoning_set_v1 open template should be loadable")
	assert_true(open_c.ok, "image_corpus_v1 open template should be loadable")
	assert_true(pur_a.ok, "polyglot_code_v1 purchased template should be loadable")
	assert_eq(GameState.datasets.size(), 4)
	var ids: Array = []
	for ds in GameState.datasets:
		ids.append(ds.id)
	assert_true(ids.has(&"web_corpus_v1"))
	assert_true(ids.has(&"math_reasoning_set_v1"))
	assert_true(ids.has(&"image_corpus_v1"))
	assert_true(ids.has(&"polyglot_code_v1"))

func test_coverage_tags_retrievable_from_loaded_templates() -> void:
	# math_reasoning_set_v1 must carry [reasoning, math]
	CommandBus.send(&"dataset.acquire_open", {template_id = &"math_reasoning_set_v1"})
	var ds := DatasetSystem.find_dataset(&"math_reasoning_set_v1")
	assert_not_null(ds)
	assert_true(ds.coverage_tags.has(&"reasoning"))
	assert_true(ds.coverage_tags.has(&"math"))

func test_coverage_tags_for_image_corpus() -> void:
	CommandBus.send(&"dataset.acquire_open", {template_id = &"image_corpus_v1"})
	var ds := DatasetSystem.find_dataset(&"image_corpus_v1")
	assert_not_null(ds)
	assert_true(ds.coverage_tags.has(&"multimodal"))
	assert_true(ds.coverage_tags.has(&"image"))

func test_coverage_tags_for_polyglot_code() -> void:
	CommandBus.send(&"dataset.purchase", {template_id = &"polyglot_code_v1"})
	var ds := DatasetSystem.find_dataset(&"polyglot_code_v1")
	assert_not_null(ds)
	assert_true(ds.coverage_tags.has(&"code"))
	assert_true(ds.coverage_tags.has(&"languages"))

func test_science_reasoning_template_is_purchasable_with_correct_tags() -> void:
	var before: int = GameState.cash
	var r: Dictionary = CommandBus.send(&"dataset.purchase", {template_id = &"science_reasoning_v1"})
	assert_true(r.ok)
	assert_eq(GameState.cash, before - 150000)
	var ds := DatasetSystem.find_dataset(&"science_reasoning_v1")
	assert_not_null(ds)
	assert_true(ds.coverage_tags.has(&"reasoning"))
	assert_true(ds.coverage_tags.has(&"science"))

func test_turn0_open_datasets_cover_2017_baseline() -> void:
	# v2: starter_* fake-ids were removed. Real 2017 templates available at
	# turn 0 are bookcorpus / wiki / commoncrawl / imdb / news_archive_2017q2.
	# This test asserts the cold-start coverage stays usable.
	var ids: Array[StringName] = [
		&"bookcorpus_v1",
		&"wiki_dump_2017",
		&"imdb_reviews_v1",
	]
	for template_id in ids:
		var r: Dictionary = CommandBus.send(&"dataset.acquire_open", {template_id = template_id})
		assert_true(r.ok, "%s should be a turn-0 open template" % template_id)
		var ds := DatasetSystem.find_dataset(template_id)
		assert_not_null(ds)
		assert_eq(ds.source, &"open_source")
		assert_eq(ds.kind, &"pretrain")
	assert_true(DatasetSystem.find_dataset(&"bookcorpus_v1").coverage_tags.has(&"books"))
	assert_true(DatasetSystem.find_dataset(&"wiki_dump_2017").coverage_tags.has(&"encyclopedia"))

# Build (exported PCK) can't enumerate res:// via DirAccess, so the template
# tables in DatasetSystem are hardcoded. These two tests catch the regression
# where a new .tres lands on disk but is forgotten in PRETRAIN_PATHS /
# POSTTRAIN_PATHS — which in the build silently disappears from the market.
func test_pretrain_paths_table_matches_disk() -> void:
	_assert_paths_table_matches_disk(
			"res://resources/data/datasets/pretrain",
			DatasetSystem.PRETRAIN_PATHS, "pretrain")

func test_posttrain_paths_table_matches_disk() -> void:
	_assert_paths_table_matches_disk(
			"res://resources/data/datasets/posttrain",
			DatasetSystem.POSTTRAIN_PATHS, "posttrain")

func test_every_listed_template_path_loads_as_template_resource() -> void:
	for tid in DatasetSystem.PRETRAIN_PATHS:
		var res := load(DatasetSystem.PRETRAIN_PATHS[tid])
		assert_true(res is PretrainDatasetTemplate,
				"PRETRAIN_PATHS[%s] must load as PretrainDatasetTemplate" % tid)
		assert_eq(StringName(res.id), tid,
				"template id field must match table key for %s" % tid)
	for tid in DatasetSystem.POSTTRAIN_PATHS:
		var res := load(DatasetSystem.POSTTRAIN_PATHS[tid])
		assert_true(res is PosttrainDatasetTemplate,
				"POSTTRAIN_PATHS[%s] must load as PosttrainDatasetTemplate" % tid)
		assert_eq(StringName(res.id), tid,
				"template id field must match table key for %s" % tid)

func _assert_paths_table_matches_disk(
		root: String, table: Dictionary, kind_label: String) -> void:
	var on_disk: Array = _collect_tres_paths(root)
	var listed: Array = table.values()
	on_disk.sort()
	listed.sort()
	for path in on_disk:
		assert_true(listed.has(path),
				"%s template on disk not listed in DatasetSystem table: %s" % [kind_label, path])
	for path in listed:
		assert_true(on_disk.has(path),
				"%s template listed in table but missing on disk: %s" % [kind_label, path])

func _collect_tres_paths(root: String) -> Array:
	var out: Array = []
	var dir := DirAccess.open(root)
	assert_not_null(dir, "dataset root must exist in editor: %s" % root)
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if dir.current_is_dir() and not entry.begins_with("."):
			var sub := DirAccess.open("%s/%s" % [root, entry])
			if sub != null:
				sub.list_dir_begin()
				var fname: String = sub.get_next()
				while fname != "":
					if not sub.current_is_dir() and fname.ends_with(".tres"):
						out.append("%s/%s/%s" % [root, entry, fname])
					fname = sub.get_next()
				sub.list_dir_end()
		entry = dir.get_next()
	dir.list_dir_end()
	return out

func test_locked_dataset_cannot_be_deleted_explicit() -> void:
	# Re-asserts the locked-delete contract directly against the new templates,
	# guarding against any regression in the dir-scan refactor.
	var r1: Dictionary = CommandBus.send(&"dataset.acquire_open", {template_id = &"math_reasoning_set_v1"})
	assert_true(r1.ok)
	CommandBus.send(&"dataset.lock", {dataset_id = r1.dataset_id, task_id = &"trainer"})
	var r_del: Dictionary = CommandBus.send(&"dataset.delete", {dataset_id = r1.dataset_id})
	assert_false(r_del.ok)
	assert_eq(r_del.error, &"locked")
	# After release, delete succeeds.
	CommandBus.send(&"dataset.release", {dataset_id = r1.dataset_id, task_id = &"trainer"})
	var r_del2: Dictionary = CommandBus.send(&"dataset.delete", {dataset_id = r1.dataset_id})
	assert_true(r_del2.ok)
	assert_eq(GameState.datasets.size(), 0)
