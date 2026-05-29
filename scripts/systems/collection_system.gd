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

# 收藏品 .tres 由 tools/build_collectibles.py 生成 (每类 15-25 件), 数量多, 运行时
# 扫目录加载 (同 MarketSystem 扫 npcs 目录的范式), 不再硬编码路径。
const COLLECTIBLE_DIR: String = "res://resources/data/collectibles/"
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
	# 扫 collectibles 目录加载全部 CollectibleSpec (同 MarketSystem._load_npc_tres_dir)。
	var dir := DirAccess.open(COLLECTIBLE_DIR)
	if dir != null:
		dir.list_dir_begin()
		var fname: String = dir.get_next()
		while fname != "":
			# auction_tuning.tres 同目录但不是收藏品 spec, 跳过 (is 检查也会挡, 这里显式跳)。
			if not dir.current_is_dir() and fname.ends_with(".tres") \
					and fname != "auction_tuning.tres":
				var spec = load(COLLECTIBLE_DIR + fname)
				if spec is CollectibleSpec:
					_specs[spec.id] = spec
			fname = dir.get_next()
		dir.list_dir_end()
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
