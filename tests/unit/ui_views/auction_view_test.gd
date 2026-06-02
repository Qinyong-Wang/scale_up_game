extends GutTest

## AuctionView 视图测试 (拍卖行目录)。视图自身不读 GameState; refresh(data) 接 dict。
## Per design/办公室与收藏系统设计.md §8。

const AuctionViewScene := preload("res://scenes/ui/views/auction/auction_view.tscn")

var _view: Control

func before_each() -> void:
	GameState.reset()
	_view = AuctionViewScene.instantiate()
	add_child_autofree(_view)

func _lot(id: String, price: int, affordable: bool) -> Dictionary:
	return {id = StringName(id), display_name = "拍品", description = "描述",
			category = &"crypto", price = price, affordable = affordable}

func _data(auction: Array) -> Dictionary:
	return {cash = 1_000_000_000, auction = auction}

func test_lots_render() -> void:
	_view.refresh(_data([_lot("c1", 1000, true), _lot("c2", 2000, true)]))
	assert_eq(_view.get_card_count_for_test(), 2)

func test_empty_auction() -> void:
	_view.refresh(_data([]))
	assert_eq(_view.get_card_count_for_test(), 0)

func test_click_buy_emits_signal() -> void:
	_view.refresh(_data([_lot("c1", 1000, true)]))
	watch_signals(_view)
	_view.click_buy_for_test(&"c1")
	await get_tree().process_frame
	assert_signal_emitted_with_parameters(_view, "buy_pressed", [&"c1"])

func test_unaffordable_lot_buy_disabled() -> void:
	_view.refresh(_data([_lot("c1", 1000, false)]))
	var card: Control = _view.get_card_for_test(&"c1")
	assert_not_null(card)
	assert_true(card._action_buttons[&"buy"].disabled, "买不起应禁用买入按钮")

# 定价用全局货币符号 $ (顶栏现金一致), 不用人民币 ¥。见设计 §8。
func test_price_uses_dollar_not_rmb() -> void:
	_view.refresh(_data([_lot("c1", 1234567, true)]))
	var card: Control = _view.get_card_for_test(&"c1")
	assert_not_null(card)
	var row: Dictionary = card.get_field_row_for_test(0)
	assert_true(String(row.get("value", "")).begins_with("$"), "市价应以 $ 开头: %s" % row)
	assert_eq(String(row.get("value", "")).find("¥"), -1, "市价不应含人民币符号 ¥")

# 卡片头像走逐件收藏图标 (art 就位后)。用真实收藏 id。见设计 §8。
func test_card_uses_collectible_icon() -> void:
	_view.refresh(_data([_lot("genesis_coin_7", 5000, true)]))
	var card: Control = _view.get_card_for_test(&"genesis_coin_7")
	assert_not_null(card)
	assert_true(card.is_avatar_texture_visible_for_test(),
		"配了逐件图标时卡片头像应走贴图层")
