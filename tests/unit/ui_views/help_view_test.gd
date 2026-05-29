extends GutTest

## HelpView 视图测试 — master-detail: 左系统列表 + 右说明面板。
## 视图不读 GameState; 内容为内置静态话题, refresh() 即重建文案。
## Per design/教程与帮助系统设计.md §2。

const HelpViewScene := preload("res://scenes/ui/views/help_view/help_view.tscn")
const HelpView := preload("res://scenes/ui/views/help_view/help_view.gd")

var _view: Control

func before_each() -> void:
	_view = HelpViewScene.instantiate()
	add_child_autofree(_view)
	_view.refresh({})

# ─── 话题覆盖 (核心循环优先) ─────────────────────────────────

func test_has_topics() -> void:
	assert_gt(_view.topic_count(), 0, "帮助应至少有一个话题")

func test_covers_core_loop_topics() -> void:
	var ids: Array = _view.topic_ids_for_test()
	for needed in [&"turn", &"training", &"product", &"economy"]:
		assert_true(ids.has(needed), "核心循环缺话题: %s" % needed)

func test_covers_all_player_facing_systems() -> void:
	# 帮助应覆盖侧栏所有玩家面向系统 (含营销 / 竞争 / 事件 / 任务 / 慈善 / 收藏拍卖)。
	var ids: Array = _view.topic_ids_for_test()
	for needed in [&"turn", &"training", &"product", &"marketing", &"competitors",
			&"economy", &"hiring", &"infra", &"dataset", &"tech", &"tasks",
			&"events", &"charity", &"collection"]:
		assert_true(ids.has(needed), "帮助缺系统话题: %s" % needed)

# ─── master-detail 选择 ───────────────────────────────────────

func test_first_topic_selected_by_default() -> void:
	assert_ne(_view.current_detail_title_for_test(), "", "默认应选中首个话题, 标题非空")
	assert_ne(_view.current_detail_body_for_test(), "", "默认选中话题正文非空")

func test_selecting_topic_updates_detail() -> void:
	_view.select_topic_for_test(&"training")
	var t1: String = _view.current_detail_body_for_test()
	_view.select_topic_for_test(&"product")
	var t2: String = _view.current_detail_body_for_test()
	assert_ne(t1, t2, "切换话题后详情正文应不同")

# ─── 重新查看新手引导 ────────────────────────────────────────

func test_replay_button_emits_signal() -> void:
	watch_signals(_view)
	_view.click_replay_for_test()
	assert_signal_emitted(_view, "replay_tutorial_pressed")

# ─── i18n ─────────────────────────────────────────────────────

func test_topic_keys_have_translation() -> void:
	TranslationServer.set_locale("zh_CN")
	for topic in HelpView.TOPICS:
		assert_ne(tr(topic.title), String(topic.title),
				"话题标题 key 无翻译: %s" % topic.title)
		assert_ne(tr(topic.body), String(topic.body),
				"话题正文 key 无翻译: %s" % topic.body)
