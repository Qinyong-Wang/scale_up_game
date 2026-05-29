extends GutTest

## ResearchDialog headless interaction smoke. Per design/科技树系统设计.md §5.2 (v6 PR-D).
##
## Mirrors tests/integration/pretrain_dialog_test.gd: we don't simulate mouse
## clicks, but we drive the dialog's public methods (setup / refresh /
## _refresh_preview / _on_start_pressed), inspect its child controls, and
## verify the resulting GameState + signals.

const ResearchDialog := preload("res://scenes/ui/research_dialog/research_dialog.gd")

# Cheapest researchable node at boot. Same anchor as tech_tree_system_test.gd.
const NODE := &"gqa"
const TREE := &"attention"
const NODE_WEEKS := 24
const NODE_MIN_ML := 2
const NODE_MIN_INFRA := 1
const NODE_MIN_GPU := 8

var _dlg

func before_each() -> void:
	GameState.reset()
	GameState.cash = 10_000_000

func after_each() -> void:
	if _dlg != null:
		_dlg.queue_free()
		_dlg = null

# ---- helpers ------------------------------------------------------------

func _provision_pod_dc(min_gpu: int = NODE_MIN_GPU) -> StringName:
	# Rent an 8-card pod + buy enough GPUs so the dialog sees a valid DC.
	var r: Dictionary = CommandBus.send(&"infra.rent_facility",
			{facility_spec_id = &"facility_pod", power_supply_id = &"grid"})
	assert_true(r.ok, "rent_facility failed: %s" % str(r))
	CommandBus.send(&"infra.buy_gpus",
			{dc_id = r.dc_id, gpu_id = &"cypress_t0", count = min_gpu})
	return r.dc_id

func _provision_staff(ml: int = NODE_MIN_ML, infra: int = NODE_MIN_INFRA) -> void:
	CommandBus.send(&"hiring.adjust_staff", {role = &"ml_eng", delta = ml})
	CommandBus.send(&"hiring.adjust_staff", {role = &"infra_eng", delta = infra})

func _seed_chief_scientist(ability: float = 80.0) -> StringName:
	var l := Lead.new()
	l.id = &"lead_cs_dlg"
	l.display_name = "Alice"
	l.specialty = &"chief_scientist"
	l.level = &"A"
	l.ability = ability
	l.signing_fee = 0
	l.weekly_salary = 0
	GameState.leads.append(l)
	return l.id

func _make_dialog(tree: StringName = TREE, node_id: StringName = NODE):
	_dlg = ResearchDialog.new()
	_dlg.setup(tree, node_id)
	add_child_autofree(_dlg)
	return _dlg

# ---- instantiation -----------------------------------------------------

func test_dialog_instantiates_and_loads_node_template() -> void:
	var dlg = _make_dialog()
	assert_not_null(dlg._node, "node template should load for gqa")
	assert_eq(dlg._node.id, NODE)
	assert_eq(dlg._node.research_months, NODE_WEEKS)
	assert_eq(dlg._node.min_researchers, NODE_MIN_ML)
	assert_eq(dlg._node.min_engineers, NODE_MIN_INFRA)
	assert_eq(dlg._node.min_gpu_count, NODE_MIN_GPU)

func test_dialog_title_includes_node_display_name() -> void:
	var dlg = _make_dialog()
	assert_true(dlg.title.find("Grouped-Query") != -1,
			"title should include display_name (got: %s)" % dlg.title)

func test_dialog_content_is_in_scroll_container() -> void:
	# Same hygiene as PretrainDialog — long warnings / DC lists shouldn't push
	# the OK button off-screen in 1280x720.
	var dlg = _make_dialog()
	var found_scroll: ScrollContainer = null
	for c in dlg.get_children():
		if c is ScrollContainer:
			found_scroll = c
			break
	assert_not_null(found_scroll, "ResearchDialog 必须把内容包在 ScrollContainer 里")

# ---- form controls -----------------------------------------------------

func test_lead_dropdown_has_no_lead_option_when_empty() -> void:
	# No leads in GameState — dropdown should still have "(无 Lead, 无加速)" entry.
	var dlg = _make_dialog()
	assert_eq(dlg._lead_dropdown.item_count, 1)
	assert_true(dlg._lead_dropdown.get_item_text(0).find("无 Lead") != -1,
			"first dropdown entry must be the 'no-lead' option")

func test_lead_dropdown_defaults_to_chief_scientist() -> void:
	_seed_chief_scientist()
	var dlg = _make_dialog()
	# 2 items: "(无 Lead)" + Alice.
	assert_eq(dlg._lead_dropdown.item_count, 2)
	# Default selection should be the chief_scientist (index 1), not "(无 Lead)".
	assert_eq(dlg._lead_dropdown.selected, 1,
			"chief_scientist should be auto-selected")

func _seed_lead(id: StringName, specialty: StringName, ability: float = 70.0) -> void:
	var l := Lead.new()
	l.id = id
	l.display_name = String(id)
	l.specialty = specialty
	l.level = &"B"
	l.ability = ability
	l.signing_fee = 0
	l.weekly_salary = 0
	GameState.leads.append(l)

func test_lead_dropdown_excludes_non_research_specialties() -> void:
	# 研究对话框只该列出能加速 tech_research 的方向 (当前仅 chief_scientist 带
	# research_speed); 工程 / 评估 / 数据 / 营销方向的 lead 不该出现。
	_seed_lead(&"l_eng", &"chief_engineer")
	_seed_lead(&"l_eval", &"eval_lead")
	_seed_lead(&"l_data", &"data_scientist")
	_seed_lead(&"l_mkt", &"marketing_lead")
	var dlg = _make_dialog()
	# 仅 "(无 Lead)" 一项 — 四个非研究方向 lead 全被过滤。
	assert_eq(dlg._lead_dropdown.item_count, 1,
			"非研究方向的 lead 不应出现在研究对话框")

func test_lead_dropdown_excludes_ml_research_lead() -> void:
	# ml_research_lead 加成集中在 posttrain / evaluate, 不带 research_speed,
	# 对 tech_research 无加速 — 故同样被研究对话框过滤掉。
	_seed_lead(&"l_mlr", &"ml_research_lead")
	var dlg = _make_dialog()
	assert_eq(dlg._lead_dropdown.item_count, 1,
			"ml_research_lead 不带 research_speed 加成, 不该列出")

func test_lead_dropdown_shows_only_research_leads_when_mixed() -> void:
	_seed_chief_scientist()
	_seed_lead(&"l_eng", &"chief_engineer")
	_seed_lead(&"l_mlr", &"ml_research_lead")
	var dlg = _make_dialog()
	# "(无 Lead)" + chief_scientist = 2; chief_engineer / ml_research_lead 均被过滤。
	assert_eq(dlg._lead_dropdown.item_count, 2,
			"混合方向时只列出 chief_scientist")

func test_staff_spinboxes_use_min_from_node() -> void:
	_provision_staff(5, 3)  # surplus
	var dlg = _make_dialog()
	assert_eq(int(dlg._ml_eng_spin.min_value), NODE_MIN_ML)
	assert_eq(int(dlg._infra_eng_spin.min_value), NODE_MIN_INFRA)
	# Default value should equal the min.
	assert_eq(int(dlg._ml_eng_spin.value), NODE_MIN_ML)
	assert_eq(int(dlg._infra_eng_spin.value), NODE_MIN_INFRA)

func test_staff_spinbox_max_reflects_available_pool() -> void:
	_provision_staff(5, 3)
	var dlg = _make_dialog()
	# ml_eng pool=5, busy=0 → max=5
	assert_eq(int(dlg._ml_eng_spin.max_value), 5)
	assert_eq(int(dlg._infra_eng_spin.max_value), 3)
	# Hint label should mention "可用 5".
	assert_true(dlg._ml_eng_hint.text.find("5") != -1)
	assert_true(dlg._infra_eng_hint.text.find("3") != -1)

func test_dc_dropdown_filters_undersized_clusters() -> void:
	# Provide one 8-card pod (OK for gqa) + one zero-GPU pod (rejected because
	# 0 < 8).
	_provision_pod_dc()
	CommandBus.send(&"infra.rent_facility",
			{facility_spec_id = &"facility_pod", power_supply_id = &"grid"})
	var dlg = _make_dialog()
	# placeholder + 1 valid DC = 2 items total.
	assert_eq(dlg._dc_dropdown.item_count, 2,
			"only the 8-card pod should appear; the 0-card pod should be hidden")

func test_dc_dropdown_excludes_busy_clusters() -> void:
	# A pod that's been assigned to a fake task must not appear (status != idle).
	var pod_id := _provision_pod_dc()
	CommandBus.send(&"infra.assign_to_task", {dc_id = pod_id, task_id = &"dummy_task"})
	var dlg = _make_dialog()
	assert_eq(dlg._dc_dropdown.item_count, 1,
			"busy DC must be filtered out (only '(无可用数据中心)' placeholder remains)")

# ---- validation / warning area -----------------------------------------

func test_start_button_disabled_when_no_dc_available() -> void:
	_provision_staff()  # has staff but no DC
	var dlg = _make_dialog()
	dlg._refresh_preview()
	assert_true(dlg.get_ok_button().disabled,
			"start should be disabled when no DC selected")
	assert_true(dlg._warning_label.text.find("数据中心") != -1
			or dlg._warning_label.text.find("8 卡") != -1,
			"warning should mention DC requirement (got: %s)" % dlg._warning_label.text)

func test_start_button_enabled_when_all_resources_provided() -> void:
	_provision_staff()
	_provision_pod_dc()
	var dlg = _make_dialog()
	dlg._refresh_preview()
	assert_false(dlg.get_ok_button().disabled,
			"start should be enabled with min staff + valid DC (warning was: %s)" \
			% dlg._warning_label.text)
	assert_eq(dlg._warning_label.text, "")

func test_start_button_disables_when_staff_dropped_below_min() -> void:
	_provision_staff()
	_provision_pod_dc()
	var dlg = _make_dialog()
	# Force the spinbox below min (bypass SpinBox.min_value clamp by setting
	# value directly through the dialog's payload — simulate UI tampering).
	dlg._ml_eng_spin.min_value = 0  # relax clamp for the test
	dlg._ml_eng_spin.value = 0
	dlg._refresh_preview()
	assert_true(dlg.get_ok_button().disabled,
			"setting ml_eng below min should disable start")
	assert_true(dlg._warning_label.text.find("研究员") != -1,
			"warning should call out researcher shortage")

# ---- preview duration --------------------------------------------------

func test_preview_shows_base_weeks_without_lead() -> void:
	_provision_staff()
	_provision_pod_dc()
	var dlg = _make_dialog()
	# Default lead selection is "(无 Lead)" when no chief_scientist exists.
	dlg._refresh_preview()
	assert_true(dlg._duration_label.text.find("%d 周" % NODE_WEEKS) != -1,
			"duration label should show base weeks when no lead (got: %s)" \
			% dlg._duration_label.text)

func test_preview_shrinks_weeks_when_chief_scientist_selected() -> void:
	# chief_scientist S, ability=100 → research_speed = 0.55 → 1.55× speedup.
	# 24 / 1.55 = 15.48 → ceil = 16 weeks.
	_seed_chief_scientist(100.0)
	_provision_staff()
	_provision_pod_dc()
	var dlg = _make_dialog()
	dlg._refresh_preview()
	# Two assertions: weeks decreased, and the suffix labels the speedup.
	assert_true(dlg._duration_label.text.find("16 周") != -1
			or dlg._duration_label.text.find("15 周") != -1,
			"lead speedup should shrink weeks (got: %s)" % dlg._duration_label.text)
	assert_true(dlg._duration_label.text.find("Lead") != -1,
			"label should mention Lead multiplier")

# ---- start path --------------------------------------------------------

func test_on_start_pressed_dispatches_tech_start_research() -> void:
	_provision_staff()
	var dc_id := _provision_pod_dc()
	var dlg = _make_dialog()
	dlg._refresh_preview()
	watch_signals(dlg)
	dlg._on_start_pressed()
	assert_signal_emitted(dlg, "task_started_via_dialog")
	# A tech_research task should be alive in active_tasks.
	assert_eq(GameState.active_tasks.size(), 1)
	assert_eq(GameState.active_tasks[0].subtype, &"tech_research")
	assert_eq(GameState.active_tasks[0].locked_datacenter_id, dc_id)
	# researching_nodes records the (tree, node) pair.
	assert_true(GameState.researching_nodes.get(TREE, {}).has(NODE))

func test_on_start_pressed_writes_warning_on_failure() -> void:
	# No DC + no staff → tech.start_research will reject with a missing-resource
	# error code. Dialog should surface it in the warning label without
	# crashing.
	var dlg = _make_dialog()
	# Bypass the local disable so we can verify the failure path through the
	# CommandBus instead of just the pre-check.
	dlg.get_ok_button().disabled = false
	dlg._on_start_pressed()
	assert_true(dlg._warning_label.text.find("启动失败") != -1
			or dlg._warning_label.text.find("datacenter") != -1
			or dlg._warning_label.text.find("数据中心") != -1,
			"warning label should explain why start failed (got: %s)" \
			% dlg._warning_label.text)
	assert_eq(GameState.active_tasks.size(), 0)

# ---- end-to-end via the dialog -----------------------------------------

func test_research_completes_when_driven_via_dialog() -> void:
	_provision_staff()
	_provision_pod_dc()
	var dlg = _make_dialog()
	dlg._refresh_preview()
	dlg._on_start_pressed()
	# Advance gqa's 24 weeks; the task should unlock & release.
	for _i in range(NODE_WEEKS):
		TurnManager.advance()
	assert_true(bool(GameState.unlocks[TREE][NODE]),
			"%s should be unlocked after %d weeks" % [NODE, NODE_WEEKS])
	assert_false(GameState.researching_nodes.get(TREE, {}).has(NODE))
