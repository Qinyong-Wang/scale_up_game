extends GutTest

## D-6: LoanDialog 与 FundingDialog 的金额 SpinBox 自身不支持千分位, 难以阅读 7
## 位以上数字。两个对话框各加一个 echo Label 实时显示 "= $X,XXX,XXX"。
## 这里只验证 echo 文本同步 SpinBox 值; 不校验完整对话框流程 (那是 economy 端测试)。

const LoanDialog := preload("res://scenes/ui/loan_dialog/loan_dialog.gd")
const FundingDialog := preload("res://scenes/ui/funding_dialog/funding_dialog.gd")

var _dlg

func before_each() -> void:
	GameState.reset()

func after_each() -> void:
	if _dlg != null:
		_dlg.queue_free()
		_dlg = null

func test_loan_dialog_echoes_amount_with_thousand_separators() -> void:
	_dlg = LoanDialog.new()
	add_child_autofree(_dlg)
	# 不必 popup; 直接打 _refresh_preview 触发 echo 更新.
	_dlg._amount_spin.max_value = 10_000_000
	_dlg._amount_spin.value = 2_660_000
	_dlg._refresh_preview()
	assert_eq(_dlg._amount_echo.text, "= $2,660,000",
			"echo label 应实时反映金额, 实际: %s" % _dlg._amount_echo.text)

func test_loan_dialog_echo_updates_when_value_changes() -> void:
	_dlg = LoanDialog.new()
	add_child_autofree(_dlg)
	# step=10000 限制了取值; 选两个对齐 step 的金额验证 echo 跟随。
	_dlg._amount_spin.max_value = 10_000_000
	_dlg._amount_spin.value = 500_000
	_dlg._refresh_preview()
	assert_eq(_dlg._amount_echo.text, "= $500,000")
	_dlg._amount_spin.value = 1_230_000
	_dlg._refresh_preview()
	assert_eq(_dlg._amount_echo.text, "= $1,230,000")

func test_loan_dialog_offers_three_year_term() -> void:
	_dlg = LoanDialog.new()
	add_child_autofree(_dlg)
	assert_true(LoanDialog.TERMS.has(156), "贷款弹窗必须提供 3 年期 (156 周) 选项")
	assert_eq(LoanDialog.TERMS.max(), 156, "贷款弹窗最长选项应为 3 年期")

func test_funding_dialog_echoes_amount_with_thousand_separators() -> void:
	_dlg = FundingDialog.new()
	add_child_autofree(_dlg)
	# 取真实存在的轮号 pre_seed (amount_min=500k, amount_max=2M).
	_dlg.open_for_round(&"pre_seed")
	_dlg.hide()  # 测试不需要真正弹出.
	_dlg._amount_spin.value = 1_300_000
	_dlg._refresh_preview()
	assert_eq(_dlg._amount_echo.text, "= $1,300,000",
			"echo label 应实时反映金额, 实际: %s" % _dlg._amount_echo.text)
