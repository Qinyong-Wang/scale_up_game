extends GutTest

## 收藏系统 — CollectibleSpec / TrophySpec / CollectionSystem + 增值曲线(2070
## 封顶) + 拍卖买入 / 收藏柜卖出(抽成) + 税务表外 + 存档。
## Per design/办公室与收藏系统设计.md。

func before_each() -> void:
	GameState.reset()

func after_each() -> void:
	GameState.reset()

func _set_year(year: int) -> void:
	GameState.turn = GameState.date_to_turn("%d-06-12" % year)

# ---- specs 加载 ---------------------------------------------------------

func test_collectible_specs_load() -> void:
	assert_gt(CollectionSystem.all_specs().size(), 70, "内容填充后应有数十件收藏")
	assert_not_null(CollectionSystem.spec_for(&"starry_vortex"))
	assert_null(CollectionSystem.spec_for(&"nonsense"))

func test_each_category_has_15_to_25_items() -> void:
	var counts: Dictionary = {}
	for spec in CollectionSystem.all_specs():
		counts[spec.category] = int(counts.get(spec.category, 0)) + 1
	assert_eq(counts.size(), 5, "应有 5 个类别")
	for cat in counts.keys():
		var n: int = int(counts[cat])
		assert_true(n >= 15 and n <= 25, "类别 %s 应有 15-25 件, 实际 %d" % [cat, n])

func test_trophy_specs_load() -> void:
	# 5 个荣誉: 慈善铜/银/金 (奖章) + 登顶总榜 (奖杯) + 宇宙「42」(答案盒)。
	assert_eq(CollectionSystem.all_trophy_specs().size(), 5)

func test_universe_answer_uses_answer_box_form() -> void:
	var found: TrophySpec = null
	for t in CollectionSystem.all_trophy_specs():
		if t.id == &"universe_answer":
			found = t
			break
	assert_not_null(found)
	assert_eq(found.form, &"answer_box", "终局 42 应在办公室显示为可打开的答案盒")

# ---- 增值曲线 + 2070 封顶 ----------------------------------------------

func test_price_at_debut_year() -> void:
	_set_year(2017)
	assert_eq(CollectionSystem.current_price(&"first_ai_card"), 5000)

func test_price_interpolates_between_keyframes() -> void:
	# first_ai_card 文物级曲线 2035:50M → 2055:2B, 2040 (1/4 处) 应约 537.5M。
	_set_year(2040)
	assert_almost_eq(CollectionSystem.current_price(&"first_ai_card"), 537_500_000, 1_000_000)

func test_relic_gpu_caps_above_1b() -> void:
	# 第一块训练 GPU 是文物级, 2070 封顶价应 ≥ 1B (用户要求)。
	_set_year(2070)
	assert_eq(CollectionSystem.current_price(&"first_ai_card"), 8_000_000_000)
	assert_gt(CollectionSystem.current_price(&"first_ai_card"), 1_000_000_000)

func test_price_flat_after_2070() -> void:
	_set_year(2095)
	assert_eq(CollectionSystem.current_price(&"first_ai_card"), 8_000_000_000, "2070 之后封顶不再涨")

# ---- 买入 ---------------------------------------------------------------

func test_buy_succeeds_and_records_owned() -> void:
	_set_year(2017)
	GameState.cash = 10_000_000
	watch_signals(EventBus)
	var r: Dictionary = CommandBus.send(&"collection.buy", {collectible_id = &"genesis_coin_7"})
	assert_true(r.get(&"ok", false))
	assert_eq(GameState.cash, 10_000_000 - 1000, "扣当前市价")
	assert_true(CollectionSystem.is_owned(&"genesis_coin_7"))
	assert_eq(CollectionSystem.bought_price(&"genesis_coin_7"), 1000)
	assert_signal_emitted(EventBus, "collectible_bought")

func test_buy_rejects_unknown() -> void:
	GameState.cash = 10_000_000
	var r: Dictionary = CommandBus.send(&"collection.buy", {collectible_id = &"nope"})
	assert_eq(r.get(&"error", &""), &"unknown_collectible")

func test_buy_rejects_already_owned() -> void:
	_set_year(2017)
	GameState.cash = 10_000_000
	CommandBus.send(&"collection.buy", {collectible_id = &"genesis_coin_7"})
	var r: Dictionary = CommandBus.send(&"collection.buy", {collectible_id = &"genesis_coin_7"})
	assert_eq(r.get(&"error", &""), &"already_owned")

func test_buy_blocks_into_negative_cash() -> void:
	_set_year(2017)
	GameState.cash = 500   # < 1000 genesis price
	var r: Dictionary = CommandBus.send(&"collection.buy", {collectible_id = &"genesis_coin_7"})
	assert_eq(r.get(&"error", &""), &"insufficient_cash")
	assert_eq(GameState.cash, 500, "拒绝后现金不变")
	assert_false(CollectionSystem.is_owned(&"genesis_coin_7"))

# ---- 卖出(抽成) -------------------------------------------------------

func test_sell_returns_proceeds_minus_fee() -> void:
	_set_year(2017)
	GameState.cash = 10_000_000
	CommandBus.send(&"collection.buy", {collectible_id = &"genesis_coin_7"})  # price 1000
	var cash_after_buy: int = GameState.cash
	watch_signals(EventBus)
	var r: Dictionary = CommandBus.send(&"collection.sell", {collectible_id = &"genesis_coin_7"})
	assert_true(r.get(&"ok", false))
	var expected: int = int(round(1000.0 * (1.0 - CollectionSystem.SELL_FEE)))  # 850
	assert_eq(int(r.proceeds), expected)
	assert_eq(GameState.cash, cash_after_buy + expected)
	assert_false(CollectionSystem.is_owned(&"genesis_coin_7"))
	assert_signal_emitted(EventBus, "collectible_sold")

func test_sell_rejects_not_owned() -> void:
	var r: Dictionary = CommandBus.send(&"collection.sell", {collectible_id = &"genesis_coin_7"})
	assert_eq(r.get(&"error", &""), &"not_owned")

func test_buy_low_sell_high_profits() -> void:
	# 2017 买创世币(1000), 推到 2035(3,000,000)卖, 扣 15% 抽成仍大赚。
	_set_year(2017)
	GameState.cash = 10_000_000
	CommandBus.send(&"collection.buy", {collectible_id = &"genesis_coin_7"})
	_set_year(2035)
	var r: Dictionary = CommandBus.send(&"collection.sell", {collectible_id = &"genesis_coin_7"})
	assert_eq(int(r.proceeds), int(round(3_000_000.0 * 0.85)))

# ---- 税务: 收藏品买卖是表外资产 ----------------------------------------

func test_collectible_reasons_are_non_taxable() -> void:
	assert_true(EconomySystem.NON_TAXABLE_REASONS.has(&"collectible_purchase"),
			"买入是资产负债表科目, 不应抵税")
	assert_true(EconomySystem.NON_TAXABLE_REASONS.has(&"collectible_sale"),
			"卖出回款不应计入应税收入")

# ---- 奖杯展示框架 -------------------------------------------------------

func test_trophies_unearned_by_default() -> void:
	for t in CollectionSystem.all_trophy_specs():
		assert_false(CollectionSystem.is_trophy_earned(t.id), "本期默认未获得")

func test_trophy_earned_reflects_gamestate() -> void:
	GameState.trophies.append(&"charity_global")
	assert_true(CollectionSystem.is_trophy_earned(&"charity_global"))
	assert_false(CollectionSystem.is_trophy_earned(&"leaderboard_first"))

func test_award_trophy_idempotent_and_emits() -> void:
	watch_signals(EventBus)
	assert_true(CollectionSystem.award_trophy(&"leaderboard_first"), "首次授予返回 true")
	assert_true(CollectionSystem.is_trophy_earned(&"leaderboard_first"))
	assert_signal_emitted(EventBus, "trophy_awarded")
	assert_false(CollectionSystem.award_trophy(&"leaderboard_first"), "重复授予返回 false")

func test_award_unknown_trophy_ignored() -> void:
	assert_false(CollectionSystem.award_trophy(&"nope"))
	assert_eq(GameState.trophies.size(), 0)

# ---- 存档 ---------------------------------------------------------------

func test_owned_and_trophies_round_trip() -> void:
	_set_year(2017)
	GameState.cash = 10_000_000
	CommandBus.send(&"collection.buy", {collectible_id = &"genesis_coin_7"})
	GameState.trophies.append(&"leaderboard_first")
	var d: Dictionary = GameState.to_dict()
	GameState.reset()
	assert_false(CollectionSystem.is_owned(&"genesis_coin_7"))
	GameState.from_dict(d)
	assert_true(CollectionSystem.is_owned(&"genesis_coin_7"))
	assert_eq(CollectionSystem.bought_price(&"genesis_coin_7"), 1000)
	assert_true(CollectionSystem.is_trophy_earned(&"leaderboard_first"))

func test_legacy_save_without_keys_defaults_empty() -> void:
	GameState.from_dict({turn = 3})
	assert_eq(GameState.owned_collectibles.size(), 0)
	assert_eq(GameState.trophies.size(), 0)

# ---- 拍卖行轮换 lineup: 数量不多不少 + 多样性 + 稀有度 ------------------

func _rng(s: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r

func test_lineup_size_is_slots_when_inventory_large() -> void:
	# 库存充足 (78 件) 时 lineup 正好 SLOTS 个, 不多不少。
	var lineup: Array = CollectionSystem.roll_auction_lineup(CollectionSystem.all_specs(), _rng(1))
	assert_eq(lineup.size(), CollectionSystem.AUCTION_SLOTS)

func test_lineup_capped_to_available_when_few() -> void:
	# 库存少于 SLOTS 时显示剩余全部 (晚期收得差不多了)。
	var few: Array = CollectionSystem.all_specs().slice(0, 3)
	var lineup: Array = CollectionSystem.roll_auction_lineup(few, _rng(1))
	assert_eq(lineup.size(), 3)

func test_lineup_no_duplicates() -> void:
	var lineup: Array = CollectionSystem.roll_auction_lineup(CollectionSystem.all_specs(), _rng(3))
	var seen: Dictionary = {}
	for id in lineup:
		assert_false(seen.has(id), "lineup 不应重复")
		seen[id] = true

func test_lineup_spans_all_categories() -> void:
	# 多样性: 5 类齐全 + SLOTS≥5 → lineup 必覆盖全部 5 类。
	for seed_v in [7, 13, 42, 99, 256]:
		var lineup: Array = CollectionSystem.roll_auction_lineup(CollectionSystem.all_specs(), _rng(seed_v))
		var cats: Dictionary = {}
		for id in lineup:
			cats[CollectionSystem.spec_for(id).category] = true
		assert_eq(cats.size(), 5, "seed %d: lineup 应覆盖全部 5 类" % seed_v)

func test_rare_relic_appears_less_than_common() -> void:
	# 稀有度=出现概率: 多次 roll 中文物级 (低权重) 明显比便宜款 (高权重) 少出现。
	var specs: Array = CollectionSystem.all_specs()
	var rng := _rng(99)
	var relic: int = 0
	var common: int = 0
	for i in range(300):
		var lineup: Array = CollectionSystem.roll_auction_lineup(specs, rng)
		if lineup.has(&"first_ai_card"):
			relic += 1
		if lineup.has(&"retired_mining_card"):
			common += 1
	assert_lt(relic, common, "文物级应明显比便宜款少 (relic=%d common=%d)" % [relic, common])

func test_auction_lineup_persists_through_save() -> void:
	# available_lots() 懒刷新会写 GameState.auction_lineup; 应随存档往返。
	GameState.cash = 100_000_000_000
	var lots: Array = CollectionSystem.available_lots()
	assert_gt(lots.size(), 0)
	var before: Array = GameState.auction_lineup.duplicate()
	assert_gt(before.size(), 0, "懒刷新应填充 lineup")
	var d: Dictionary = GameState.to_dict()
	GameState.reset()
	GameState.from_dict(d)
	assert_eq(GameState.auction_lineup, before)
