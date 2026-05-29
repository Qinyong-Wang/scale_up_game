extends GutTest

## SimulationDonationDialog 测试 — 捐建数据中心对话框: 列出满足门槛的自有空闲未出租 DC
## 供单选, 确认 → 发 confirmed_dc(dc_id)。无可捐 DC 时禁用确认。
## Per design/宇宙模拟工程设计.md §8。

const DialogScript := preload("res://scenes/ui/simulation_donation_dialog/simulation_donation_dialog.gd")

var _dlg

func before_each() -> void:
	GameState.reset()
	_dlg = DialogScript.new()
	add_child_autofree(_dlg)

func _stage() -> Dictionary:
	return {display_name = "宇宙模拟", min_train_tflops = 1.5e11,
			cost = 1_000_000_000_000, weeks = 52}

func _dc(dc_id: String, tflops: float, gpu_count: int = 1000) -> Dictionary:
	return {id = StringName(dc_id), display_name = "数据中心 " + dc_id,
			gpu_count = gpu_count, train_tflops = tflops, gpu_id = &"cypress_t3"}

# ---- 列表 + 空状态 ------------------------------------------------------

func test_lists_eligible_dcs() -> void:
	_dlg.open_for_stage(_stage(), [_dc("a", 2.0e11), _dc("b", 1.8e11)])
	assert_eq(_dlg.get_dc_option_count_for_test(), 2)
	assert_false(_dlg.is_confirm_disabled_for_test(), "有可捐 DC → 确认可点")

func test_empty_disables_confirm() -> void:
	_dlg.open_for_stage(_stage(), [])
	assert_eq(_dlg.get_dc_option_count_for_test(), 0)
	assert_true(_dlg.is_confirm_disabled_for_test(), "无可捐 DC → 确认禁用")

# ---- 选择 + 确认 --------------------------------------------------------

func test_default_selects_first_and_confirm_emits_it() -> void:
	_dlg.open_for_stage(_stage(), [_dc("a", 2.0e11), _dc("b", 1.8e11)])
	watch_signals(_dlg)
	_dlg.click_confirm_for_test()
	assert_signal_emitted_with_parameters(_dlg, "confirmed_dc", [&"a"])

func test_select_then_confirm_emits_chosen_dc() -> void:
	_dlg.open_for_stage(_stage(), [_dc("a", 2.0e11), _dc("b", 1.8e11)])
	watch_signals(_dlg)
	_dlg.select_dc_for_test(&"b")
	_dlg.click_confirm_for_test()
	assert_signal_emitted_with_parameters(_dlg, "confirmed_dc", [&"b"])

func test_reopen_repopulates_list() -> void:
	_dlg.open_for_stage(_stage(), [_dc("a", 2.0e11)])
	assert_eq(_dlg.get_dc_option_count_for_test(), 1)
	_dlg.open_for_stage(_stage(), [_dc("a", 2.0e11), _dc("b", 1.8e11), _dc("c", 1.6e11)])
	assert_eq(_dlg.get_dc_option_count_for_test(), 3, "重开应重建列表, 不残留旧项")
