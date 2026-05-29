extends AcceptDialog

## CollectiblesDialog — 收藏柜 (点击办公室房间里的电脑打开)。Per design/办公室与收藏系统设计.md §8.2。
##
## 列出玩家持有的收藏品 (买入价 / 当前市价 / 浮动盈亏 + 「卖出」按钮), 空则空状态提示。
## dialog 不读 GameState; main.gd refresh({cabinet}) 接 dict。「卖出」emit
## sell_pressed(collectible_id) → main collection.sell 成功后即时重渲染。买入仍走拍卖行 tab。
##
## 信号: sell_pressed(collectible_id)

signal sell_pressed(collectible_id: StringName)

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
var _scroll: ScrollContainer
var _body: HFlowContainer
var _empty: Label
var _cards: Dictionary = {}  # id → Card (测试 introspection)

func _ready() -> void:
	title = tr("OFFICE_CABINET_SECTION")
	# 收藏卡是 360×220 的 Card, 一行放得下 2 列 + 余量; 受最小窗口约束 (≤1240×680)。
	min_size = Vector2i(880, 560)
	get_ok_button().text = tr("ACTION_CLOSE")

	var root := VBoxContainer.new()
	root.add_theme_constant_override(&"separation", UITheme.S_3)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(root)

	_section = SectionHeaderScene.instantiate()
	root.add_child(_section)
	_section.set_data(tr("OFFICE_CABINET_SECTION"), 0, "", &"")

	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.custom_minimum_size = Vector2(860, 460)
	root.add_child(_scroll)

	_body = HFlowContainer.new()
	_body.add_theme_constant_override(&"h_separation", UITheme.S_3)
	_body.add_theme_constant_override(&"v_separation", UITheme.S_3)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_body)

	_empty = Label.new()
	_empty.text = tr("OFFICE_CABINET_EMPTY")
	_empty.add_theme_color_override(&"font_color", UITheme.TEXT_SECONDARY)
	_body.add_child(_empty)

func refresh(data: Dictionary) -> void:
	var cabinet: Array = data.get("cabinet", [])
	# 卖出抽成比例 (SELL_FEE), 由 main 从 CollectionSystem.SELL_FEE 传入; 缺省 0 = 不收/不显示。
	var sell_fee: float = clampf(float(data.get("sell_fee", 0.0)), 0.0, 1.0)
	for child in _body.get_children():
		if child == _empty:
			continue
		_body.remove_child(child)
		child.queue_free()
	_cards.clear()
	_empty.visible = cabinet.is_empty()
	_section.set_data(tr("OFFICE_CABINET_SECTION"), cabinet.size(), "", &"")
	for c in cabinet:
		var cid: StringName = StringName(c.get("id", &""))
		var card: Control = CardScene.instantiate()
		_body.add_child(card)
		var bought: int = int(c.get("bought_price", 0))
		var price: int = int(c.get("current_price", 0))
		var pnl: int = price - bought
		# 到手回款 = 市价扣抽成; 抽成额 = 市价 − 回款 (与 CollectionSystem._on_sell 同口径)。
		var proceeds: int = int(round(float(price) * (1.0 - sell_fee)))
		var fee_amount: int = price - proceeds
		var fields: Array = [
			{"label": tr("OFFICE_FIELD_BOUGHT"), "value": "$" + _money(bought)},
			{"label": tr("OFFICE_FIELD_PRICE"), "value": "$" + _money(price)},
			{"label": tr("OFFICE_FIELD_PNL"), "value": _pnl_text(pnl)},
		]
		if sell_fee > 0.0:
			fields.append({"label": tr("OFFICE_FIELD_SELL_FEE"),
				"value": "%d%% · -$%s" % [int(round(sell_fee * 100.0)), _money(fee_amount)]})
		# 按钮直接写到手回款 (与拍卖行「买入 $x」对称); 无抽成时回款=市价。
		var sell_label: String = (tr("OFFICE_SELL_BTN_FMT") % _money(proceeds)) if sell_fee > 0.0 \
			else tr("OFFICE_SELL_BTN")
		card.set_data({
			"title": tr(String(c.get("display_name", String(cid)))),
			"subtitle": tr(String(c.get("description", ""))),
			"avatar": {"texture": IconRegistry.collectible_icon(cid), "fallback_text": String(cid),
				"seed_id": cid, "kind": &"collectible"},
			"status": {"label": _category_label(StringName(c.get("category", &""))), "kind": &"neutral"},
			"fields": fields,
			"actions": [{"id": &"sell", "label": sell_label}],
		})
		card.action_pressed.connect(_on_card_action.bind(cid))
		_cards[cid] = card

# ---- helpers ------------------------------------------------------------

func _category_label(category: StringName) -> String:
	if _CATEGORY_KEY.has(category):
		return tr(_CATEGORY_KEY[category])
	return String(category)

func _pnl_text(pnl: int) -> String:
	if pnl >= 0:
		return "+$" + _money(pnl)
	return "-$" + _money(-pnl)

func _on_card_action(action_id: StringName, cid: StringName) -> void:
	if action_id == &"sell":
		sell_pressed.emit(cid)

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

func get_cabinet_card_count_for_test() -> int:
	return _cards.size()

func click_sell_for_test(cid: StringName) -> void:
	var c: Control = _cards.get(cid, null)
	if c != null and c.has_method(&"click_action_for_test"):
		c.click_action_for_test(&"sell")
