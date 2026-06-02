extends GutTest

## CollectiblesDialog 测试: 收藏柜卡渲染 / 空状态 / 卖出信号。
## dialog 不读 GameState; refresh({cabinet}) 接 dict。Per design/办公室与收藏系统设计.md §8.2。

const CollectiblesDialog := preload("res://scenes/ui/collectibles_dialog/collectibles_dialog.gd")

var _dlg

func before_each() -> void:
	GameState.reset()
	_dlg = CollectiblesDialog.new()
	add_child_autofree(_dlg)

func _owned(id: String, bought: int, price: int) -> Dictionary:
	return {id = StringName(id), display_name = "藏品", description = "描述",
			category = &"painting", bought_price = bought, current_price = price}

func _data(cabinet: Array, fee: float = 0.15) -> Dictionary:
	return {cabinet = cabinet, sell_fee = fee}

func test_cabinet_count() -> void:
	_dlg.refresh(_data([_owned("p1", 100, 200)]))
	assert_eq(_dlg.get_cabinet_card_count_for_test(), 1)

func test_empty_cabinet() -> void:
	_dlg.refresh(_data([]))
	assert_eq(_dlg.get_cabinet_card_count_for_test(), 0)

func test_click_sell_emits_signal() -> void:
	_dlg.refresh(_data([_owned("p1", 100, 200)]))
	watch_signals(_dlg)
	_dlg.click_sell_for_test(&"p1")
	await get_tree().process_frame
	assert_signal_emitted_with_parameters(_dlg, "sell_pressed", [&"p1"])

# 价格 / 盈亏一律用 $ (顶栏现金一致), 不用人民币 ¥。见设计 §8。
func test_prices_use_dollar_not_rmb() -> void:
	_dlg.refresh(_data([_owned("p1", 1000000, 2500000)]))  # 盈利 → 正盈亏
	var card: Control = _dlg._cards[&"p1"]
	for idx in 3:  # 买入价 / 当前市价 / 浮动盈亏
		var v: String = String(card.get_field_row_for_test(idx).get("value", ""))
		assert_eq(v.find("¥"), -1, "字段 %d 不应含人民币符号 ¥: %s" % [idx, v])
		assert_true(v.find("$") != -1, "字段 %d 应含 $: %s" % [idx, v])

# 藏品卡头像走逐件收藏图标 (art 就位后)。见设计 §8。
func test_card_uses_collectible_icon() -> void:
	_dlg.refresh(_data([_owned("genesis_coin_7", 1000, 5000)]))
	var card: Control = _dlg._cards[&"genesis_coin_7"]
	assert_true(card.is_avatar_texture_visible_for_test(),
		"配了逐件图标时藏品卡头像应走贴图层")

# 卖出抽成必须在 UI 体现: 抽成字段 (比例 + 扣额) + 卖出按钮显示到手回款。见设计 §8.2。
func test_sell_fee_field_shown() -> void:
	_dlg.refresh(_data([_owned("p1", 1000000, 2000000)], 0.15))  # 市价 2M, 抽成 15% → 扣 300k
	var card: Control = _dlg._cards[&"p1"]
	var found := false
	for i in card.get_field_count():
		var v: String = String(card.get_field_row_for_test(i).get("value", ""))
		if v.find("15%") != -1 and v.find("-$300,000") != -1:
			found = true
	assert_true(found, "应有抽成字段显示比例 15% 与扣额 -$300,000")

func test_sell_button_shows_net_proceeds() -> void:
	_dlg.refresh(_data([_owned("p1", 1000000, 2000000)], 0.15))  # 到手 = round(2M*0.85) = 1.7M
	var card: Control = _dlg._cards[&"p1"]
	var btn: Button = card._action_buttons[&"sell"]
	assert_true(btn.text.find("1,700,000") != -1, "卖出按钮应显示到手回款 1,700,000: %s" % btn.text)
	assert_eq(btn.text.find("¥"), -1, "按钮不应含人民币符号 ¥")

func test_no_sell_fee_field_when_fee_zero() -> void:
	_dlg.refresh(_data([_owned("p1", 1000000, 2000000)], 0.0))
	var card: Control = _dlg._cards[&"p1"]
	# fee=0 → 不显示抽成字段 (买入价 / 当前市价 / 浮动盈亏 共 3 个)
	assert_eq(card.get_field_count(), 3, "抽成为 0 时不显示抽成字段")
