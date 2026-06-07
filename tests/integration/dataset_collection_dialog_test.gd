extends GutTest

## DatasetCollectionDialog smoke + quality-tier behavior. Per
## design/数据集系统设计.md §5 (posttrain 自采人力分档).
## Headless: we don't click; we drive widgets + _build_payload directly.
## Mirrors new_campaign_dialog_test pattern.

const DatasetCollectionDialog := preload("res://scenes/ui/dataset_collection_dialog/dataset_collection_dialog.gd")

var _dlg

func before_each() -> void:
	GameState.reset()
	# Dialog's lead dropdown filters for data_scientist; seed one so refresh()
	# exercises the populated path.
	var l := Lead.new()
	l.id = &"l_ds"
	l.specialty = &"data_scientist"
	l.level = &"C"
	l.ability = 0.0
	GameState.leads.append(l)

func after_each() -> void:
	if _dlg != null:
		_dlg.queue_free()
		_dlg = null

func _make_dialog(kind: StringName):
	_dlg = DatasetCollectionDialog.new()
	add_child_autofree(_dlg)
	_dlg.set_initial_kind(kind)
	_dlg.refresh()
	return _dlg

# ---- instantiation -------------------------------------------------------

func test_dialog_instantiates_and_refresh_does_not_crash() -> void:
	var dlg = _make_dialog(&"posttrain")
	assert_not_null(dlg._quality_tier_dropdown, "quality tier dropdown built")
	assert_eq(dlg._quality_tier_dropdown.item_count, 4, "4 labor-grade tiers")
	assert_not_null(dlg._employee_monitor_checkbox, "employee monitoring checkbox built")

# ---- tier row visibility (assert the row container, not the dropdown) -----

func test_quality_tier_row_visible_for_posttrain() -> void:
	var dlg = _make_dialog(&"posttrain")
	assert_true(dlg._quality_tier_row.visible,
			"quality tier row shows in posttrain mode")

func test_quality_tier_row_hidden_for_pretrain() -> void:
	var dlg = _make_dialog(&"pretrain")
	assert_false(dlg._quality_tier_row.visible,
			"quality tier row hidden in pretrain mode")

func test_employee_monitoring_row_visible_for_posttrain() -> void:
	var dlg = _make_dialog(&"posttrain")
	assert_true(dlg._employee_monitor_row.visible,
			"employee monitoring option shows in posttrain mode")
	assert_eq(dlg._employee_monitor_checkbox.text, "监控员工日常工作数据")

func test_employee_monitoring_row_hidden_for_pretrain() -> void:
	var dlg = _make_dialog(&"pretrain")
	assert_false(dlg._employee_monitor_row.visible,
			"employee monitoring option hidden in pretrain mode")

# ---- tier selection → target_quality in payload --------------------------

func test_each_tier_maps_to_expected_target_quality() -> void:
	var dlg = _make_dialog(&"posttrain")
	var expected := [0.65, 0.80, 0.90, 0.95]
	for idx in range(4):
		dlg._quality_tier_dropdown.select(idx)
		var payload: Dictionary = dlg._build_payload()
		assert_true(payload.has(&"target_quality"),
				"posttrain payload carries target_quality")
		assert_almost_eq(float(payload[&"target_quality"]), expected[idx], 0.001,
				"tier %d → target_quality %.2f" % [idx, expected[idx]])

func test_default_tier_is_t1_basic() -> void:
	var dlg = _make_dialog(&"posttrain")
	var payload: Dictionary = dlg._build_payload()
	assert_almost_eq(float(payload[&"target_quality"]), 0.65, 0.001,
			"default selection is T1 (q0.65), preserving legacy cheap default")

func test_employee_monitoring_maps_to_posttrain_payload() -> void:
	var dlg = _make_dialog(&"posttrain")
	var default_payload: Dictionary = dlg._build_payload()
	assert_false(bool(default_payload.get(&"monitor_employee_work_data", false)),
			"employee monitoring is opt-in")
	dlg._employee_monitor_checkbox.button_pressed = true
	var payload: Dictionary = dlg._build_payload()
	assert_true(bool(payload.get(&"monitor_employee_work_data", false)),
			"posttrain payload carries employee monitoring choice")

func test_pretrain_payload_has_no_target_quality() -> void:
	var dlg = _make_dialog(&"pretrain")
	var payload: Dictionary = dlg._build_payload()
	assert_false(payload.has(&"target_quality"),
			"pretrain (web scrape) has no labor-grade tier / target_quality")
	assert_false(payload.has(&"monitor_employee_work_data"),
			"pretrain payload does not carry posttrain-only employee monitoring")
