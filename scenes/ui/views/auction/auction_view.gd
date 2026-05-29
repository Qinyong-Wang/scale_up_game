extends VBoxContainer

## AuctionView — 「拍卖行」tab 视图。Per design/办公室与收藏系统设计.md §8。
##
## 从办公室拆出的拍卖目录: 上架未持有的具名 lot, 按当前市价买入(买不起置灰)。
## 视图不读 GameState; refresh(data) 接 dict。
##
## 信号:
##   buy_pressed(collectible_id)

signal buy_pressed(collectible_id: StringName)

const SectionHeaderScene := preload("res://scenes/ui/components/section_header/section_header.tscn")
const CardScene := preload("res://scenes/ui/components/card/card.tscn")

const _CATEGORY_KEY: Dictionary = {
	&"ai_hardware": "CAT_AI_HARDWARE",
	&"trading_card": "CAT_TRADING_CARD",
	&"crypto": "CAT_CRYPTO",
	&"supercar": "CAT_SUPERCAR",
	&"painting": "CAT_PAINTING",
}

var _section: Control
var _body: HFlowContainer
var _empty: Label
var _cards: Dictionary = {}

func _ready() -> void:
	add_theme_constant_override(&"separation", UITheme.S_4)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	_section = SectionHeaderScene.instantiate()
	add_child(_section)
	_section.set_data(tr("OFFICE_AUCTION_SECTION"), 0, "", &"")
	_body = HFlowContainer.new()
	_body.add_theme_constant_override(&"h_separation", UITheme.S_3)
	_body.add_theme_constant_override(&"v_separation", UITheme.S_3)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_body)
	_empty = Label.new()
	_empty.text = tr("OFFICE_AUCTION_EMPTY")
	_empty.add_theme_color_override(&"font_color", UITheme.TEXT_SECONDARY)
	_body.add_child(_empty)

func refresh(data: Dictionary) -> void:
	var auction: Array = data.get("auction", [])
	for child in _body.get_children():
		if child == _empty:
			continue
		_body.remove_child(child)
		child.queue_free()
	_cards.clear()
	_empty.visible = auction.is_empty()
	_section.set_data(tr("OFFICE_AUCTION_SECTION"), auction.size(), "", &"")
	for c in auction:
		var cid: StringName = StringName(c.get("id", &""))
		var card: Control = CardScene.instantiate()
		_body.add_child(card)
		var price: int = int(c.get("price", 0))
		card.set_data({
			"title": tr(String(c.get("display_name", String(cid)))),
			"subtitle": tr(String(c.get("description", ""))),
			"avatar": {"texture": IconRegistry.collectible_icon(cid), "fallback_text": String(cid),
				"seed_id": cid, "kind": &"collectible"},
			"status": {"label": _category_label(StringName(c.get("category", &""))), "kind": &"neutral"},
			"fields": [
				{"label": tr("OFFICE_FIELD_PRICE"), "value": "$" + _money(price)},
			],
			"actions": [{
				"id": &"buy",
				"label": tr("OFFICE_BUY_BTN") % _money(price),
				"disabled": not bool(c.get("affordable", true)),
			}],
		})
		card.action_pressed.connect(_on_action.bind(cid))
		_cards[cid] = card

func _category_label(category: StringName) -> String:
	if _CATEGORY_KEY.has(category):
		return tr(_CATEGORY_KEY[category])
	return String(category)

func _on_action(action_id: StringName, cid: StringName) -> void:
	if action_id == &"buy":
		buy_pressed.emit(cid)

func _money(n: int) -> String:
	var v: int = absi(n)
	var s: String = str(v)
	var out: String = ""
	var i: int = s.length()
	while i > 3:
		out = "," + s.substr(i - 3, 3) + out
		i -= 3
	out = s.substr(0, i) + out
	return out

# ─── 测试 introspection ──────────────────────────────────────

func get_card_count_for_test() -> int:
	return _cards.size()

func get_card_for_test(cid: StringName) -> Control:
	return _cards.get(cid, null)

func click_buy_for_test(cid: StringName) -> void:
	var c: Control = _cards.get(cid, null)
	if c != null and c.has_method(&"click_action_for_test"):
		c.click_action_for_test(&"buy")
