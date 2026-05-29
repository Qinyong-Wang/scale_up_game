extends GutTest

## Tests that the live signal/command surface matches the design tables.
## Catches drift between code and design when adding/removing new entries.
## Per 设计/事件总线信号表.md + 设计/命令总线表.md.

func before_each() -> void:
	GameState.reset()

# ---- model_added carries provenance per 公共枚举表 §6bis -----------------

func test_model_added_emits_provenance_for_trained() -> void:
	watch_signals(EventBus)
	var r: Dictionary = CommandBus.send(&"research.add_model", {
		capability = {}, arch = &"ant_v1", dataset_ids = []})
	assert_signal_emitted(EventBus, "model_added")
	var p: Array = get_signal_parameters(EventBus, "model_added")
	assert_eq(p.size(), 2, "model_added must carry (model_id, provenance)")
	assert_eq(StringName(p[1]), &"trained",
			"player-pretrained model has provenance = trained")

func test_model_added_emits_provenance_for_downloaded_os() -> void:
	# v9 PR-I: OS models come from OS NPC pretrain releases (Wolf-3 @ turn 330).
	GameState.turn = 335
	watch_signals(EventBus)
	var r: Dictionary = CommandBus.send(&"research.download_open_source",
			{release_id = &"release_wolf_3"})
	assert_true(r.ok, "download release_wolf_3: %s" % str(r.get(&"error", &"")))
	var p: Array = get_signal_parameters(EventBus, "model_added")
	assert_eq(StringName(p[1]), &"downloaded_os",
			"OS-downloaded model has provenance = downloaded_os")

# ---- bankruptcy_warning carries reason per 经济系统设计.md §6.2 ----------

func test_bankruptcy_warning_carries_reason_cash_negative() -> void:
	GameState.cash = -1
	watch_signals(EventBus)
	EventBus.phase_started.emit(&"resolve", 1)
	var p: Array = get_signal_parameters(EventBus, "bankruptcy_warning")
	assert_eq(p.size(), 3, "bankruptcy_warning must carry (reason, streak, threshold)")
	assert_eq(StringName(p[0]), &"cash_negative")

func test_bankruptcy_warning_fires_for_cash_too_deep_before_trigger() -> void:
	# 经济系统设计 §6.2: cash 跌破 depth 阈值前先发 warning, 再发 trigger.
	GameState.cash = -10_000_000  # 远低于 -1M floor
	watch_signals(EventBus)
	EventBus.phase_started.emit(&"resolve", 1)
	# Both warning and triggered should fire in this order.
	var warned: bool = false
	for i in range(get_signal_emit_count(EventBus, "bankruptcy_warning")):
		var p: Array = get_signal_parameters(EventBus, "bankruptcy_warning", i)
		if StringName(p[0]) == &"cash_too_deep":
			warned = true
			break
	assert_true(warned, "cash_too_deep warning must fire before trigger")
	assert_signal_emitted(EventBus, "bankruptcy_triggered")

# ---- research.set_api_price returns applied_price -----------------------

func test_set_api_price_returns_applied_price_unmodified() -> void:
	# v6 PR-E (2026-05): no hard cap. applied_price = max(0, requested).
	var r: Dictionary = CommandBus.send(&"research.add_model", {
		capability = {}, arch = &"ant_v1", dataset_ids = []})
	var mid: StringName = r.model_id
	CommandBus.send(&"research.set_open_source",
			{model_id = mid, is_open_source = true})
	var ap: Dictionary = CommandBus.send(&"research.set_api_price",
			{model_id = mid, per_token_price = 1.0})
	assert_true(ap.ok)
	assert_true(ap.has("applied_price"),
			"set_api_price must return applied_price (命令总线表 §ResearchSystem)")
	assert_almost_eq(float(ap.applied_price), 1.0, 0.0001)

func test_set_api_price_negative_floored_to_zero() -> void:
	var r: Dictionary = CommandBus.send(&"research.add_model", {
		capability = {}, arch = &"ant_v1", dataset_ids = []})
	var ap: Dictionary = CommandBus.send(&"research.set_api_price",
			{model_id = r.model_id, per_token_price = -5.0})
	assert_true(ap.ok)
	assert_almost_eq(float(ap.applied_price), 0.0, 0.0001)

# ---- v6 PR-E pricing commands are registered ---------------------------

func test_get_base_price_registered() -> void:
	var rm: Dictionary = CommandBus.send(&"research.add_model", {
		capability = {}, arch = &"ant_v1", size_params = 7000.0,
		flops_per_token = 1.4e10, dataset_ids = []})
	var r: Dictionary = CommandBus.send(&"research.get_base_price", {model_id = rm.model_id})
	assert_true(r.ok, "research.get_base_price must be registered")
	assert_gt(float(r.price), 0.0)

func test_get_guidance_price_registered() -> void:
	var rm: Dictionary = CommandBus.send(&"research.add_model", {
		capability = {}, arch = &"ant_v1", size_params = 7000.0,
		flops_per_token = 1.4e10, dataset_ids = []})
	var r: Dictionary = CommandBus.send(&"research.get_guidance_price", {model_id = rm.model_id})
	assert_true(r.ok)
	assert_gt(float(r.price), 0.0)

func test_get_weekly_growth_rate_registered() -> void:
	var rm: Dictionary = CommandBus.send(&"research.add_model", {
		capability = {}, arch = &"ant_v1", size_params = 7000.0,
		flops_per_token = 1.4e10, dataset_ids = []})
	var r: Dictionary = CommandBus.send(&"research.get_weekly_growth_rate",
			{model_id = rm.model_id})
	assert_true(r.ok)
	# Default per_token_price = 0 < 0.6 × guidance → growth rate = +0.02 (v11 ×0.5).
	assert_almost_eq(float(r.rate), 0.02, 0.0001)

# ---- evidence-based posttrain count -------------------------------------

func test_posttrain_apply_increments_model_posttrain_count() -> void:
	# Real persistent counter (Wave 2): each posttrain_apply bumps by 1.
	var r: Dictionary = CommandBus.send(&"research.add_model", {
		capability = {}, arch = &"ant_v1", dataset_ids = []})
	var mid: StringName = r.model_id
	# Need a dataset for posttrain payload — borrow web_corpus_v1.
	CommandBus.send(&"dataset.acquire_open", {template_id = &"web_corpus_v1"})
	CommandBus.send(&"research.posttrain_apply",
			{model_id = mid, dataset_id = &"web_corpus_v1"})
	CommandBus.send(&"research.posttrain_apply",
			{model_id = mid, dataset_id = &"web_corpus_v1"})
	var m = ResearchSystem.find_model(mid)
	assert_eq(m.posttrain_count, 2)
