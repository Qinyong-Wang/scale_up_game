extends GutTest

## 导出包回归烟雾测试。
## 覆盖过去只在编译版里暴露的风险: 静态资源加载、NPC 时间线、事件页 pending 展示。
## Per design/游戏基础架构设计.md §8.5。

const Main := preload("res://scenes/main/main.gd")

func before_each() -> void:
	TranslationServer.set_locale("zh_CN")
	GameState.reset()

func test_cold_start_static_data_survives_export_style_loading() -> void:
	var pretrain: Dictionary = CommandBus.send(&"dataset.list_market", {
		kind = &"pretrain",
	})
	assert_true(pretrain.ok)
	assert_gt((pretrain.items as Array).size(), 5,
		"冷启动数据市场应有多个预训练数据集; 打包版不能因为资源枚举失败而近似为空")

	var posttrain: Dictionary = CommandBus.send(&"dataset.list_market", {
		kind = &"posttrain",
	})
	assert_true(posttrain.ok)
	assert_eq((posttrain.items as Array).size(), 0,
		"第 0 周后训练市场可以为空; 后训练内容通过未来 release gate 开放")
	assert_gt(DatasetSystem.POSTTRAIN_PATHS.size(), 0,
		"后训练模板仍必须登记在显式路径表, 避免导出包资源缺失")
	GameState.turn = GameState.date_to_turn("2020-06-12")
	posttrain = CommandBus.send(&"dataset.list_market", {kind = &"posttrain"})
	assert_true(posttrain.ok)
	assert_gt((posttrain.items as Array).size(), 0,
		"推进到未来年份后, 后训练数据市场应非空")
	GameState.turn = 0

	var lots: Array = CollectionSystem.available_lots()
	assert_gt(lots.size(), 0,
		"拍卖行冷启动应能从显式路径表加载收藏品, 不能为空")
	assert_eq(lots.size(), CollectionSystem.AUCTION_SLOTS,
		"库存充足时拍卖行应填满当前轮换槽位")

	assert_gt(GameState.npc_companies.size(), 20,
		"竞争对手 roster 应从显式 NPC 路径表装载, 不能回退成空或极少量 seed")
	assert_gt(EventSystem.EVENTS.size(), 50,
		"事件库应由显式 EVENTS 表提供足够内容")

func test_npc_timeline_and_leaderboard_advance_after_load() -> void:
	var wolf_start = _find_npc(&"npc_wolf_research")
	assert_not_null(wolf_start)
	var start_release: StringName = wolf_start.current_release_id

	GameState.turn = GameState.date_to_turn("2024-06-12")
	EventBus.save_loaded.emit()

	var released_count: int = 0
	for npc in GameState.npc_companies:
		if npc.current_release_id != &"":
			released_count += 1
	assert_gt(released_count, 10,
		"读档/冷启动到未来年份后, NPC 时间线应推进到对应 release")
	var wolf_future = _find_npc(&"npc_wolf_research")
	assert_not_null(wolf_future)
	assert_ne(wolf_future.current_release_id, &"",
		"代表性 NPC 应在未来年份拥有当前 release")
	assert_ne(wolf_future.current_release_id, start_release,
		"代表性 NPC 的 release 应随时间线推进, 不能停在开局 seed")

	var total_board: Array = GameState.leaderboard.get(&"total", [])
	var npc_entries: int = 0
	var named_release_entries: int = 0
	for entry in total_board:
		if entry.entity_type != &"npc":
			continue
		npc_entries += 1
		if String(entry.company_name) != "" and String(entry.display_name) != "":
			named_release_entries += 1
	assert_gt(npc_entries, 0,
		"排行榜总榜应包含已发布的竞争对手")
	assert_eq(named_release_entries, npc_entries,
		"NPC 榜单条目应带公司名和 release 模型名, 避免编译版只显示静态占位")

func test_main_event_page_renders_existing_pending_event() -> void:
	var r: Dictionary = CommandBus.send(&"event.trigger_card", {
		template_id = &"debug_test_offer",
	})
	assert_true(r.ok)
	assert_eq(GameState.pending_events.size(), 1)

	var hud = Main.new()
	add_child_autofree(hud)
	await get_tree().process_frame

	assert_not_null(hud._event_view,
		"主 HUD 刷新时应创建事件视图")
	var button_texts: PackedStringArray = hud._event_view.all_button_texts_for_test()
	var label_texts: PackedStringArray = hud._event_view.all_label_texts_for_test()
	assert_gt(button_texts.size(), 0,
		"有 pending event 时事件页必须渲染可推进的按钮")
	assert_gt(label_texts.size(), 0,
		"有 pending event 时事件页必须渲染事件正文")
	assert_eq(hud.sidebar_badge_text_for_test(&"events"), "1",
		"侧栏事件徽章应和 pending_events 数量一致")

func _find_npc(npc_id: StringName):
	for npc in GameState.npc_companies:
		if npc.id == npc_id:
			return npc
	return null
