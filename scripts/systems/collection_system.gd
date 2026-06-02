extends Node

## CollectionSystem — owns owned_collectibles + trophies slices. Per
## design/办公室与收藏系统设计.md.
##
## Loads CollectibleSpec + TrophySpec .tres at _ready. Collectible market price
## tracks the in-game calendar via piecewise-linear interpolation over the
## spec's (curve_years, curve_prices), capped at the last (2070) keyframe.
##
## Auction (collection.buy) and cabinet sale (collection.sell) are instant
## commands. Collectibles are a balance-sheet asset class: both buy and sell are
## tax-neutral (their economy reasons are in NON_TAXABLE_REASONS), so the sink is
## the tied-up cash + the SELL_FEE skim, not a tax write-off.

# 收藏品 .tres 由 tools/build_collectibles.py 生成 (每类 15-25 件), 数量多。
# 发布包里 res:// 目录枚举不可靠, 且导出资源可能显示为 .tres.remap, 所以这里
# 用显式路径表作为加载权威来源 (同 DatasetSystem 的导出兼容范式)。
const COLLECTIBLE_DIR: String = "res://resources/data/collectibles/"
const COLLECTIBLE_PATHS: Dictionary = {
	&"abstract_red_field": "res://resources/data/collectibles/abstract_red_field.tres",
	&"analog_compute_die": "res://resources/data/collectibles/analog_compute_die.tres",
	&"banned_first_print": "res://resources/data/collectibles/banned_first_print.tres",
	&"beta_resource_card": "res://resources/data/collectibles/beta_resource_card.tres",
	&"blue_period_boy": "res://resources/data/collectibles/blue_period_boy.tres",
	&"cluster_node_zero": "res://resources/data/collectibles/cluster_node_zero.tres",
	&"coachbuilt_one_off": "res://resources/data/collectibles/coachbuilt_one_off.tres",
	&"cold_titanium_plate": "res://resources/data/collectibles/cold_titanium_plate.tres",
	&"crystal_phoenix": "res://resources/data/collectibles/crystal_phoenix.tres",
	&"cubist_figure": "res://resources/data/collectibles/cubist_figure.tres",
	&"cypherpunk_mail": "res://resources/data/collectibles/cypherpunk_mail.tres",
	&"dao_constitution_nft": "res://resources/data/collectibles/dao_constitution_nft.tres",
	&"dark_market_ghost": "res://resources/data/collectibles/dark_market_ghost.tres",
	&"data_center_busbar": "res://resources/data/collectibles/data_center_busbar.tres",
	&"defi_genesis_lp": "res://resources/data/collectibles/defi_genesis_lp.tres",
	&"dripping_chaos": "res://resources/data/collectibles/dripping_chaos.tres",
	&"echo_scream": "res://resources/data/collectibles/echo_scream.tres",
	&"edge_chip_first": "res://resources/data/collectibles/edge_chip_first.tres",
	&"electric_record_car": "res://resources/data/collectibles/electric_record_car.tres",
	&"error_inverted_holo": "res://resources/data/collectibles/error_inverted_holo.tres",
	&"first_ai_card": "res://resources/data/collectibles/first_ai_card.tres",
	&"first_smart_contract": "res://resources/data/collectibles/first_smart_contract.tres",
	&"first_tensor_board": "res://resources/data/collectibles/first_tensor_board.tres",
	&"flame_beast_card": "res://resources/data/collectibles/flame_beast_card.tres",
	&"fork_war_snapshot": "res://resources/data/collectibles/fork_war_snapshot.tres",
	&"founder_hyper_one": "res://resources/data/collectibles/founder_hyper_one.tres",
	&"founder_signed_gpu": "res://resources/data/collectibles/founder_signed_gpu.tres",
	&"full_art_secret": "res://resources/data/collectibles/full_art_secret.tres",
	&"genesis_coin_7": "res://resources/data/collectibles/genesis_coin_7.tres",
	&"gilded_kiss": "res://resources/data/collectibles/gilded_kiss.tres",
	&"gold_foil_promo": "res://resources/data/collectibles/gold_foil_promo.tres",
	&"grandmaster_deck": "res://resources/data/collectibles/grandmaster_deck.tres",
	&"gullwing_classic": "res://resources/data/collectibles/gullwing_classic.tres",
	&"halving_relic": "res://resources/data/collectibles/halving_relic.tres",
	&"holy_dragon_gem": "res://resources/data/collectibles/holy_dragon_gem.tres",
	&"illustrator_award": "res://resources/data/collectibles/illustrator_award.tres",
	&"inference_asic_v1": "res://resources/data/collectibles/inference_asic_v1.tres",
	&"ink_mountains": "res://resources/data/collectibles/ink_mountains.tres",
	&"lab_prototype_accel": "res://resources/data/collectibles/lab_prototype_accel.tres",
	&"last_v12_manual": "res://resources/data/collectibles/last_v12_manual.tres",
	&"le_mans_winner": "res://resources/data/collectibles/le_mans_winner.tres",
	&"liquid_cooled_proto": "res://resources/data/collectibles/liquid_cooled_proto.tres",
	&"lost_wallet_fragment": "res://resources/data/collectibles/lost_wallet_fragment.tres",
	&"mascot_card_zero": "res://resources/data/collectibles/mascot_card_zero.tres",
	&"master_self_portrait": "res://resources/data/collectibles/master_self_portrait.tres",
	&"melting_clocks": "res://resources/data/collectibles/melting_clocks.tres",
	&"meme_shiba_genesis": "res://resources/data/collectibles/meme_shiba_genesis.tres",
	&"midnight_comet_le": "res://resources/data/collectibles/midnight_comet_le.tres",
	&"miner_signed_board": "res://resources/data/collectibles/miner_signed_board.tres",
	&"neuromorphic_chip": "res://resources/data/collectibles/neuromorphic_chip.tres",
	&"night_cafe": "res://resources/data/collectibles/night_cafe.tres",
	&"overclock_record_card": "res://resources/data/collectibles/overclock_record_card.tres",
	&"phantom_gt": "res://resources/data/collectibles/phantom_gt.tres",
	&"photonic_accel_proto": "res://resources/data/collectibles/photonic_accel_proto.tres",
	&"pixel_ape_0001": "res://resources/data/collectibles/pixel_ape_0001.tres",
	&"pop_can_grid": "res://resources/data/collectibles/pop_can_grid.tres",
	&"prototype_mule": "res://resources/data/collectibles/prototype_mule.tres",
	&"quantum_resist_coin": "res://resources/data/collectibles/quantum_resist_coin.tres",
	&"rally_legend": "res://resources/data/collectibles/rally_legend.tres",
	&"retired_mining_card": "res://resources/data/collectibles/retired_mining_card.tres",
	&"retro_gamer_gpu": "res://resources/data/collectibles/retro_gamer_gpu.tres",
	&"royal_limousine": "res://resources/data/collectibles/royal_limousine.tres",
	&"salvator_cosmos": "res://resources/data/collectibles/salvator_cosmos.tres",
	&"schoolyard_champ": "res://resources/data/collectibles/schoolyard_champ.tres",
	&"sealed_starter": "res://resources/data/collectibles/sealed_starter.tres",
	&"shadow_knight_alpha": "res://resources/data/collectibles/shadow_knight_alpha.tres",
	&"signed_artist_holo": "res://resources/data/collectibles/signed_artist_holo.tres",
	&"silver_arrow_classic": "res://resources/data/collectibles/silver_arrow_classic.tres",
	&"solar_concept": "res://resources/data/collectibles/solar_concept.tres",
	&"stablecoin_proto": "res://resources/data/collectibles/stablecoin_proto.tres",
	&"starry_vortex": "res://resources/data/collectibles/starry_vortex.tres",
	&"tournament_champion": "res://resources/data/collectibles/tournament_champion.tres",
	&"track_only_extreme": "res://resources/data/collectibles/track_only_extreme.tres",
	&"turbine_concept": "res://resources/data/collectibles/turbine_concept.tres",
	&"wafer_scale_relic": "res://resources/data/collectibles/wafer_scale_relic.tres",
	&"water_garden": "res://resources/data/collectibles/water_garden.tres",
	&"weeping_lady": "res://resources/data/collectibles/weeping_lady.tres",
	&"zero_block_relic": "res://resources/data/collectibles/zero_block_relic.tres",
}
## 类别展示顺序 (auction / cabinet 分组), 内部再按 2070 封顶价 cheap → expensive。
const CATEGORY_ORDER: Array[StringName] = [
	&"crypto", &"trading_card", &"ai_hardware", &"supercar", &"painting",
]

const TROPHY_PATHS: Dictionary = {
	&"charity_bronze":     "res://resources/data/trophies/charity_bronze.tres",
	&"charity_silver":     "res://resources/data/trophies/charity_silver.tres",
	&"charity_global":     "res://resources/data/trophies/charity_global.tres",
	&"leaderboard_first":  "res://resources/data/trophies/leaderboard_first.tres",
	&"universe_answer":    "res://resources/data/trophies/universe_answer.tres",
}
const TROPHY_ORDER: Array[StringName] = [
	&"charity_bronze", &"charity_silver", &"charity_global",
	&"leaderboard_first", &"universe_answer",
]

## Sale skim (抽成) on the current market price. Per design §3.
const SELL_FEE: float = 0.15

var _specs: Dictionary = {}     # id -> CollectibleSpec
var _trophies: Dictionary = {}  # id -> TrophySpec

# 拍卖行轮换 (design/办公室与收藏系统设计.md §8.3)。lineup 槽位数 + 刷新周期 (周)。
# 由 auction_tuning.tres 在 _ready 装载 (保留大写名, 同 EconomySystem 范式); 下方是
# 缺文件时的回退默认。
const AUCTION_TUNING_PATH: String = "res://resources/data/collectibles/auction_tuning.tres"
var AUCTION_SLOTS: int = 8
var AUCTION_REFRESH_WEEKS: int = 4

func _ready() -> void:
	_load_tables()
	_load_auction_tuning()
	CommandBus.register(&"collection.buy", _on_buy)
	CommandBus.register(&"collection.sell", _on_sell)
	EventBus.phase_started.connect(_on_phase)

func _load_auction_tuning() -> void:
	if not ResourceLoader.exists(AUCTION_TUNING_PATH):
		return
	# 鸭子类型 (同 EconomySystem 读 tuning), 不裸引用 class_name → 不依赖全局类缓存。
	var t = load(AUCTION_TUNING_PATH)
	if t != null and "slots" in t and "refresh_weeks" in t:
		AUCTION_SLOTS = maxi(1, int(t.slots))
		AUCTION_REFRESH_WEEKS = maxi(1, int(t.refresh_weeks))

func _on_phase(phase: StringName, _turn: int) -> void:
	# 每 AUCTION_REFRESH_WEEKS 周在 action 相位重 roll 一次拍卖 lineup。
	if phase == &"action":
		_maybe_refresh_auction()

func _load_tables() -> void:
	_specs.clear()
	for id in COLLECTIBLE_PATHS.keys():
		var spec = load(COLLECTIBLE_PATHS[id])
		if spec is CollectibleSpec:
			if spec.id != id:
				Log.warn(&"collection", "collectible_id_mismatch", {
					expected = id, actual = spec.id,
				})
			_specs[spec.id] = spec
		else:
			Log.warn(&"collection", "collectible_spec_missing", {
				id = id, path = COLLECTIBLE_PATHS[id],
			})
	Log.info(&"collection", "collectible specs loaded", {count = _specs.size()})
	_trophies.clear()
	for id in TROPHY_PATHS.keys():
		var t := load(TROPHY_PATHS[id])
		if t is TrophySpec:
			_trophies[id] = t
		else:
			Log.warn(&"collection", "trophy_spec_missing", {id = id})

# ---- collectibles -------------------------------------------------------

func all_specs() -> Array:
	if _specs.is_empty():
		_load_tables()
	var out: Array = _specs.values()
	# 按 (类别顺序, 2070 封顶价 升序, id) 稳定排序。
	out.sort_custom(_compare_specs)
	return out

func _cap_price(spec: CollectibleSpec) -> int:
	var prices: Array = spec.curve_prices
	return int(prices[prices.size() - 1]) if not prices.is_empty() else 0

func _category_rank(category: StringName) -> int:
	var i: int = CATEGORY_ORDER.find(category)
	return i if i >= 0 else CATEGORY_ORDER.size()

func _compare_specs(a: CollectibleSpec, b: CollectibleSpec) -> bool:
	var ca: int = _category_rank(a.category)
	var cb: int = _category_rank(b.category)
	if ca != cb:
		return ca < cb
	var pa: int = _cap_price(a)
	var pb: int = _cap_price(b)
	if pa != pb:
		return pa < pb
	return String(a.id) < String(b.id)

func spec_for(id: StringName) -> CollectibleSpec:
	if _specs.is_empty():
		_load_tables()
	if _specs.has(id):
		return _specs[id]
	return null

## Current in-game calendar year (GameState.current_date() is "YYYY-MM-DD").
func _current_year() -> int:
	var date: String = GameState.current_date()
	var parts: PackedStringArray = date.split("-")
	if parts.is_empty():
		return 2017
	return parts[0].to_int()

## Market price at the current calendar year: piecewise-linear over the spec
## curve, flat before the first keyframe and capped at the last (2070) keyframe.
func current_price(id: StringName) -> int:
	var spec := spec_for(id)
	if spec == null:
		return 0
	return _interp_price(spec, _current_year())

func _interp_price(spec: CollectibleSpec, year: int) -> int:
	var years: Array = spec.curve_years
	var prices: Array = spec.curve_prices
	var n: int = mini(years.size(), prices.size())
	if n == 0:
		return 0
	if year <= int(years[0]):
		return int(prices[0])
	if year >= int(years[n - 1]):
		return int(prices[n - 1])  # 2070 cap
	for i in range(n - 1):
		var y0: int = int(years[i])
		var y1: int = int(years[i + 1])
		if year >= y0 and year <= y1 and y1 > y0:
			var p0: float = float(prices[i])
			var p1: float = float(prices[i + 1])
			var t: float = float(year - y0) / float(y1 - y0)
			return int(round(p0 + t * (p1 - p0)))
	return int(prices[n - 1])

func is_owned(id: StringName) -> bool:
	return GameState.owned_collectibles.has(id)

func bought_price(id: StringName) -> int:
	return int(GameState.owned_collectibles.get(id, 0))

## The current rotating auction lineup (un-owned specs only), sorted for display.
## Lazily (re)rolls when empty or stale. Per design §8.3.
func available_lots() -> Array:
	_maybe_refresh_auction()
	var out: Array = []
	for id in GameState.auction_lineup:
		var spec := spec_for(StringName(id))
		if spec != null and not is_owned(spec.id):
			out.append(spec)
	out.sort_custom(_compare_specs)
	return out

## (Re)roll the auction lineup if it's empty or the refresh window has elapsed.
func _maybe_refresh_auction(force: bool = false) -> void:
	var elapsed: int = int(GameState.turn) - int(GameState.auction_refreshed_turn)
	var due: bool = force \
			or int(GameState.auction_refreshed_turn) < 0 \
			or (GameState.auction_lineup as Array).is_empty() \
			or elapsed >= AUCTION_REFRESH_WEEKS
	if not due:
		return
	var avail: Array = []
	for spec in all_specs():
		if not is_owned(spec.id):
			avail.append(spec)
	GameState.auction_lineup = roll_auction_lineup(avail, GameState.rng())
	GameState.auction_refreshed_turn = int(GameState.turn)
	Log.info(&"collection", "auction refreshed", {
		turn = GameState.turn, lots = GameState.auction_lineup.size(),
	})

## Pick up to AUCTION_SLOTS ids from `available` (Array[CollectibleSpec]):
## guarantee one per category present (weighted within category) for diversity,
## then fill the rest weighted by appear_weight. Returns ≤ SLOTS unique ids.
## Per design §8.3. `rng` is a RandomNumberGenerator (seedable for tests).
func roll_auction_lineup(available: Array, rng) -> Array:
	if available.size() <= AUCTION_SLOTS:
		var all_ids: Array = []
		for s in available:
			all_ids.append(s.id)
		return all_ids
	var pool: Array = available.duplicate()
	var by_cat: Dictionary = {}
	for s in pool:
		if not by_cat.has(s.category):
			by_cat[s.category] = []
		by_cat[s.category].append(s)
	var lineup: Array = []
	# 1. diversity — one weighted pick per category present (in stable order).
	for cat in CATEGORY_ORDER:
		if lineup.size() >= AUCTION_SLOTS:
			break
		if by_cat.has(cat) and not (by_cat[cat] as Array).is_empty():
			var pick = _weighted_pick(by_cat[cat], rng)
			lineup.append(pick.id)
			pool.erase(pick)
	# 2. fill remaining slots from the rest of the pool, weighted.
	while lineup.size() < AUCTION_SLOTS and not pool.is_empty():
		var pick2 = _weighted_pick(pool, rng)
		lineup.append(pick2.id)
		pool.erase(pick2)
	return lineup

func _appear_weight(spec) -> float:
	var w: float = float(spec.appear_weight) if "appear_weight" in spec else 1.0
	return maxf(0.0001, w)

func _weighted_pick(arr: Array, rng):
	var total: float = 0.0
	for s in arr:
		total += _appear_weight(s)
	var r: float = rng.randf() * total
	var acc: float = 0.0
	for s in arr:
		acc += _appear_weight(s)
		if r <= acc:
			return s
	return arr[arr.size() - 1]

## Specs not currently owned — full inventory (cabinet / tests; auction uses the
## rotating available_lots()).
func unowned_specs() -> Array:
	var out: Array = []
	for spec in all_specs():
		if not is_owned(spec.id):
			out.append(spec)
	return out

## Specs currently owned — the cabinet.
func owned_specs() -> Array:
	var out: Array = []
	for spec in all_specs():
		if is_owned(spec.id):
			out.append(spec)
	return out

# ---- trophies (display framework; award sources wired later) ------------

func all_trophy_specs() -> Array:
	if _trophies.is_empty():
		_load_tables()
	var out: Array = []
	for id in TROPHY_ORDER:
		if _trophies.has(id):
			out.append(_trophies[id])
	return out

func is_trophy_earned(id: StringName) -> bool:
	return GameState.trophies.has(id)

## Idempotently award a trophy. Returns true only on the first award. Detecting
## systems (charity / market / simulation) call this; the trophy desk reads
## GameState.trophies. Unknown trophy ids are ignored. Per design/办公室与收藏系统设计.md §4.
func award_trophy(id: StringName) -> bool:
	if _trophies.is_empty():
		_load_tables()
	if not _trophies.has(id):
		Log.warn(&"collection", "award_unknown_trophy", {id = id})
		return false
	if GameState.trophies.has(id):
		return false
	GameState.trophies.append(id)
	Log.info(&"collection", "trophy awarded", {id = id})
	EventBus.trophy_awarded.emit(id)
	return true

# ---- commands -----------------------------------------------------------

## collection.buy {collectible_id} — buy at current market price (sink). Blocks
## buying into negative cash (economy.spend itself allows negatives).
func _on_buy(p: Dictionary) -> Dictionary:
	var id: StringName = StringName(p.get(&"collectible_id", &""))
	var spec := spec_for(id)
	if spec == null:
		return {ok = false, error = &"unknown_collectible"}
	if is_owned(id):
		return {ok = false, error = &"already_owned"}
	var price: int = current_price(id)
	if price > GameState.cash:
		return {ok = false, error = &"insufficient_cash"}
	CommandBus.send(&"economy.spend", {
		cost = {&"cash": price}, reason = &"collectible_purchase",
	})
	GameState.owned_collectibles[id] = price
	Log.info(&"collection", "collectible bought", {id = id, price = price})
	EventBus.collectible_bought.emit(id, price)
	return {ok = true, price = price}

## collection.sell {collectible_id} — sell at current market price minus SELL_FEE.
func _on_sell(p: Dictionary) -> Dictionary:
	var id: StringName = StringName(p.get(&"collectible_id", &""))
	if not is_owned(id):
		return {ok = false, error = &"not_owned"}
	var price: int = current_price(id)
	var proceeds: int = int(round(float(price) * (1.0 - SELL_FEE)))
	CommandBus.send(&"economy.award", {
		amount = proceeds, reason = &"collectible_sale",
	})
	GameState.owned_collectibles.erase(id)
	Log.info(&"collection", "collectible sold", {id = id, proceeds = proceeds})
	EventBus.collectible_sold.emit(id, proceeds)
	return {ok = true, proceeds = proceeds}
