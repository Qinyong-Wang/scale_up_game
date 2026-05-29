extends GutTest

## LeaderboardView 单测 — 荣耀榜单 (design/竞争对手系统设计.md §8)。
##
## view 是纯渲染器 (不调 tr()), 直接喂 §8.2 数据契约的 dict, 断言渲染结果, 与
## locale 无关。

const LeaderboardViewScene := preload("res://scenes/ui/views/leaderboard_view/leaderboard_view.tscn")

func _make() -> Control:
	var v: Control = LeaderboardViewScene.instantiate()
	add_child_autofree(v)
	return v

func _entry(rank: int, entry_name: String, company: String, score: String,
		reward: String, is_player: bool) -> Dictionary:
	return {
		"rank": rank,
		"display_name": entry_name,
		"company_name": company,
		"score_text": score,
		"reward_text": reward,
		"is_player": is_player,
		"you_label": "你",
		"seed_id": StringName(entry_name),
	}

func _data(entries: Array, active := &"total") -> Dictionary:
	return {
		"header_title": "排行榜 (玩家总榜名次: #2)",
		"boards": [
			{"id": &"total", "title": "总榜"},
			{"id": &"closed_source", "title": "闭源榜"},
			{"id": &"sub_code", "title": "代码细分榜"},
		],
		"active_board": active,
		"rule_text": "规则: #1: +15%/周",
		"empty_hint": "(空)",
		"entries": entries,
	}

func _sample_entries() -> Array:
	return [
		_entry(1, "Orca-5", "OrcaLab", "96.4", "[+15%/周]", false),
		_entry(2, "我的大模型", "", "94.1", "[+8%/周]", true),
		_entry(3, "Bee-9", "BeeSoft", "91.2", "[+8%/周]", false),
		_entry(4, "Ant-7", "AntCorp", "88.0", "[+1%/周]", false),
	]

# ─── 行渲染 ──────────────────────────────────────────────────

func test_renders_one_row_per_entry() -> void:
	var v := _make()
	v.refresh(_data(_sample_entries()))
	await get_tree().process_frame
	assert_eq(v.get_row_count(), 4, "应当每条 entry 渲染一行")

func test_empty_board_shows_hint_and_no_rows() -> void:
	var v := _make()
	v.refresh(_data([]))
	await get_tree().process_frame
	assert_eq(v.get_row_count(), 0)
	assert_true(v.is_empty_hint_visible(), "空榜应显示提示")

func test_header_title_rendered() -> void:
	var v := _make()
	v.refresh(_data(_sample_entries()))
	await get_tree().process_frame
	assert_ne(v.get_header_title_for_test().find("#2"), -1,
			"hero 标题应含玩家最佳名次")

func test_rule_text_rendered() -> void:
	var v := _make()
	v.refresh(_data(_sample_entries()))
	await get_tree().process_frame
	assert_ne(v.get_rule_text_for_test().find("规则"), -1)

# ─── 名次奖章 (金 / 银 / 铜) ──────────────────────────────────

func test_top3_medals_use_gold_silver_bronze() -> void:
	var v := _make()
	v.refresh(_data(_sample_entries()))
	await get_tree().process_frame
	assert_eq(v.get_row_for_test(0).get_medal_color(), UITheme.RANK_GOLD, "#1 金")
	assert_eq(v.get_row_for_test(1).get_medal_color(), UITheme.RANK_SILVER, "#2 银")
	assert_eq(v.get_row_for_test(2).get_medal_color(), UITheme.RANK_BRONZE, "#3 铜")

func test_rank4_plus_uses_neutral_medal() -> void:
	var v := _make()
	v.refresh(_data(_sample_entries()))
	await get_tree().process_frame
	var c: Color = v.get_row_for_test(3).get_medal_color()
	assert_eq(c, UITheme.BG_ELEVATED, "第 4 名起用中性灰底, 不抢前 3 镜")
	assert_ne(c, UITheme.RANK_GOLD)

func test_medal_shows_rank_number() -> void:
	var v := _make()
	v.refresh(_data(_sample_entries()))
	await get_tree().process_frame
	assert_eq(v.get_row_for_test(0).get_rank_text(), "1")
	assert_eq(v.get_row_for_test(3).get_rank_text(), "4")

# ─── 玩家行高亮 + 「你」徽章 ──────────────────────────────────

func test_player_row_highlighted_with_you_badge() -> void:
	var v := _make()
	v.refresh(_data(_sample_entries()))
	await get_tree().process_frame
	var player_row: Node = v.get_row_for_test(1)  # rank 2 = 玩家
	assert_true(player_row.is_player_highlighted(), "玩家行应高亮 (浅蓝底)")
	assert_true(player_row.has_you_badge(), "玩家行应带「你」徽章")
	assert_eq(player_row.get_you_badge_text(), "你")

func test_npc_rows_not_highlighted_no_you_badge() -> void:
	var v := _make()
	v.refresh(_data(_sample_entries()))
	await get_tree().process_frame
	for idx in [0, 2, 3]:
		var row: Node = v.get_row_for_test(idx)
		assert_false(row.is_player_highlighted(), "NPC 行不高亮 (idx %d)" % idx)
		assert_false(row.has_you_badge(), "NPC 行不带「你」徽章 (idx %d)" % idx)

# ─── 名称 / 公司 / 得分 / 奖励 ────────────────────────────────

func test_npc_row_shows_company_player_row_hides_it() -> void:
	var v := _make()
	v.refresh(_data(_sample_entries()))
	await get_tree().process_frame
	var npc_row: Node = v.get_row_for_test(0)
	assert_eq(npc_row.get_company_text(), "OrcaLab")
	assert_true(npc_row.is_company_visible(), "NPC 行显示公司名")
	var player_row: Node = v.get_row_for_test(1)
	assert_false(player_row.is_company_visible(), "玩家行 company 留空, 不显示")

func test_score_and_reward_rendered() -> void:
	var v := _make()
	v.refresh(_data(_sample_entries()))
	await get_tree().process_frame
	var row: Node = v.get_row_for_test(0)
	assert_eq(row.get_score_text(), "96.4")
	assert_ne(row.get_reward_text().find("+15%"), -1)
	assert_true(row.is_reward_visible())

func test_reward_hidden_when_empty() -> void:
	# 展示榜 (闭源 / 开源) 不带名次奖励, reward_text 为空 → 不显示。
	var v := _make()
	var entries := [_entry(1, "Orca-5", "OrcaLab", "96.4", "", false)]
	v.refresh(_data(entries, &"closed_source"))
	await get_tree().process_frame
	assert_false(v.get_row_for_test(0).is_reward_visible(),
			"reward_text 为空时不显示奖励")

# ─── 榜单切换 picker ─────────────────────────────────────────

func test_picker_renders_a_button_per_board() -> void:
	var v := _make()
	v.refresh(_data(_sample_entries()))
	await get_tree().process_frame
	var ids: Array = v.picker_board_ids_for_test()
	assert_true(ids.has(&"total"))
	assert_true(ids.has(&"closed_source"))
	assert_true(ids.has(&"sub_code"))

func test_picker_marks_active_board() -> void:
	var v := _make()
	v.refresh(_data(_sample_entries(), &"sub_code"))
	await get_tree().process_frame
	assert_eq(v.active_board_for_test(), &"sub_code", "当前榜按钮应为按下态")

func test_picker_emits_board_selected() -> void:
	var v := _make()
	v.refresh(_data(_sample_entries()))
	await get_tree().process_frame
	watch_signals(v)
	v.click_board_for_test(&"sub_code")
	assert_signal_emitted_with_parameters(v, "board_selected", [&"sub_code"])

# ─── 重渲染稳定性 ────────────────────────────────────────────

func test_refresh_twice_resets_rows() -> void:
	var v := _make()
	v.refresh(_data(_sample_entries()))
	await get_tree().process_frame
	v.refresh(_data([_entry(1, "Solo", "SoloCo", "10.0", "", false)]))
	await get_tree().process_frame
	assert_eq(v.get_row_count(), 1, "二次 refresh 应重置行, 不叠加")
	assert_eq(v.get_row_for_test(0).get_name_text(), "Solo")

# ─── 宽度收口 (design/UI视觉系统设计.md §9) ───────────────────

func test_leaderboard_width_is_capped_not_full_screen() -> void:
	# 竖排榜单不该横向铺满整屏; 收口到 LIST_MAX_W 并左对齐。
	var v := _make()
	v.refresh(_data(_sample_entries()))
	await get_tree().process_frame
	assert_ne(v.size_flags_horizontal, Control.SIZE_EXPAND_FILL,
		"排行榜视图不应 EXPAND_FILL 铺满整屏")
	assert_eq(v.custom_minimum_size.x, float(UITheme.LIST_MAX_W),
		"排行榜视图宽度应收口到 LIST_MAX_W")
