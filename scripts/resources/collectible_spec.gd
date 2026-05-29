class_name CollectibleSpec
extends Resource

## One unique collectible the player can buy at auction and display in the
## office cabinet. Stored at resources/data/collectibles/<id>.tres, loaded by
## CollectionSystem. Per design/办公室与收藏系统设计.md §2.
##
## Market price tracks the in-game calendar: piecewise-linear interpolation over
## (curve_years, curve_prices). The last keyframe is anchored at 2070 and is the
## hard price ceiling (price stays flat after 2070). Names must be fictional
## (化名规范) — no real brands.

@export var id: StringName
## Category: &"ai_hardware" / &"trading_card" / &"crypto" / &"supercar" / &"painting".
@export var category: StringName = &""
@export var display_name: String = ""
@export var description: String = ""

## Ascending keyframe years (first = debut year, last = 2070 = the price cap year).
@export var curve_years: Array[int] = []
## Market price at each keyframe year (parallel to curve_years). Last entry is
## the ceiling (price after 2070 stays here).
@export var curve_prices: Array[int] = []

## Auction appearance weight (rarity). Higher = shows up in the rotating auction
## lineup more often; relic-tier grails carry a low weight so they're rare.
## Per design/办公室与收藏系统设计.md §8.3. Set by build_collectibles.py from price.
@export var appear_weight: float = 1.0
