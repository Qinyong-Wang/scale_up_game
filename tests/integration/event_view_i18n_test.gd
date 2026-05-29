extends GutTest

## 端到端: 真实事件 .tres + 真实翻译产物 + 真实 EventSystem 后果预览 + event_view 拼装,
## 在 en locale 下整条选项按钮文案不应残留中文 (对应 国际化设计.md §6bis)。
##
## 复刻 main.gd._build_event_view_data 的选项构造 (裸 label + 单独 consequence),
## 钉死: 切英文后事件选项按钮 = 翻译后标签 + 翻译后后果, 无 CJK。

const EventViewScene := preload("res://scenes/ui/views/event_view/event_view.tscn")

var _cjk := RegEx.new()

func before_all() -> void:
	_cjk.compile("[\\x{4e00}-\\x{9fff}]")

func after_each() -> void:
	TranslationServer.set_locale("zh_CN")  # 恢复基线, 防泄漏

# 复刻 main.gd._build_event_view_data 对单张卡的选项构造。
func _build_options(card) -> Array:
	var options: Array = []
	for opt in card.options:
		options.append({
			"id": opt.id,
			"label": opt.label,
			"consequence": EventSystem.describe_option_consequence(opt),
		})
	return options

func test_choice_event_option_buttons_fully_english_in_en_locale() -> void:
	GameState.reset()
	GameState.cash = 1_000_000  # 让 economy_spend pct 后果有确定金额
	var card := EventSystem._load_card(&"board_coup")
	assert_not_null(card, "board_coup.tres 应可加载")

	TranslationServer.set_locale("en")
	var ev := {
		"id": &"board_coup",
		"template_id": &"board_coup",
		"category": card.category,
		"title": card.title,
		"body": card.body,
		"options": _build_options(card),
	}
	var v: Control = EventViewScene.instantiate()
	add_child_autofree(v)
	v.refresh({"pending": [ev], "history": []})
	await get_tree().process_frame

	var btns: PackedStringArray = v.all_button_texts_for_test()
	assert_gt(btns.size(), 0, "应渲染出选项按钮")
	for t in btns:
		assert_null(_cjk.search(String(t)),
			"en locale 下事件选项按钮不应残留中文: '%s'" % String(t))
	# 后果预览 (UI 层 strings.csv) 与标签 (内容层 content.csv) 都得翻到英文。
	var joined := "\n".join(btns)
	assert_true(joined.find("Spend") != -1 or joined.find("Subscribers") != -1,
		"应出现已翻译的后果预览, 实际: %s" % joined)
