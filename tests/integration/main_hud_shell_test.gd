extends GutTest

## 主 HUD 的 4 区域 shell 集成契约。
## 对应 design/UI视觉系统设计.md §4 + §5 + §6 + §10 step 4。
##
## 试点期约定:
##   - TabContainer 仍然存在 (作 fallback), 但 tabs_visible = false。
##   - 侧栏 SidebarItem 点击驱动 _tabs.current_tab 切换, 还没真正分离视图。
##   - 抽屉默认隐藏, 等命令打开。
##
## 这层契约只验证 *骨架*, 不验证每个 tab 内的卡片渲染 (那是后续 §10 step 5 +)。

const Main := preload("res://scenes/main/main.gd")

var _hud

func before_each() -> void:
	TranslationServer.set_locale("zh_CN")
	GameState.reset()
	_seed_eval_lead_for_happy_path()
	_hud = Main.new()
	add_child_autofree(_hud)
	await get_tree().process_frame

func _seed_eval_lead_for_happy_path() -> void:
	# main_hud_layout_test 同样的 seed: 让 evaluate_general task 能 happy-path 启动。
	var l := Lead.new()
	l.id = &"lead_eval_zero_shell"
	l.specialty = &"eval_lead"
	l.level = &"C"
	l.ability = 0.0
	l.signing_fee = 0
	l.weekly_salary = 0
	GameState.leads.append(l)

# ─── 4 区域存在 ─────────────────────────────────────────────

func test_shell_has_top_bar_node() -> void:
	assert_not_null(_hud._top_bar, "_top_bar 必须存在")

func test_shell_has_sidebar_node() -> void:
	assert_not_null(_hud._sidebar, "_sidebar 必须存在")

func test_sidebar_uses_surface_rail_style() -> void:
	# design §6: 侧栏是白色工作台侧轨, 右侧 1px 分隔线把导航从工作区里切出来。
	assert_true(_hud.sidebar_panel_bg_color_for_test().is_equal_approx(UITheme.BG_SURFACE),
		"侧栏 panel 应是 BG_SURFACE 白底")
	assert_eq(_hud.sidebar_panel_right_border_for_test(), 1,
		"侧栏右侧应有 1px 分隔线")

func test_shell_has_main_panel_node() -> void:
	assert_not_null(_hud._main_panel, "_main_panel 必须存在")

func test_shell_has_drawer_host_node() -> void:
	assert_not_null(_hud._drawer_host, "_drawer_host 必须存在")

# ─── 顶栏: 5 个 StatChip ──────────────────────────────────────

func test_top_bar_has_five_stat_chips() -> void:
	# design §5: 回合 / 现金 / 周净流 / 付费用户 / 算力 (已发布 chip 已移除)
	assert_eq(_hud.get_top_bar_chip_count(), 5,
		"顶栏应当有 5 个 StatChip, 实际 %d" % _hud.get_top_bar_chip_count())

func test_top_bar_uses_dark_glass_surface() -> void:
	# design §5: 顶栏改成深色烟熏玻璃条 (TOPBAR_GLASS_BASE 实底 + 底部 1px 玻璃细边)。
	var sb: StyleBox = _hud._top_bar.get_theme_stylebox(&"panel")
	assert_true(sb is StyleBoxFlat, "顶栏 panel stylebox 应为 StyleBoxFlat")
	if sb is StyleBoxFlat:
		var flat := sb as StyleBoxFlat
		assert_true(flat.bg_color.is_equal_approx(UITheme.TOPBAR_GLASS_BASE),
			"顶栏背景应为深色玻璃底 TOPBAR_GLASS_BASE, 实际 %s" % flat.bg_color)
		assert_eq(flat.border_width_bottom, 1,
			"顶栏应只有底部 1px 分隔线")
		assert_true(flat.border_color.is_equal_approx(UITheme.TOPBAR_GLASS_BORDER),
			"顶栏分隔线应为玻璃细边 TOPBAR_GLASS_BORDER")

func test_top_bar_glass_layer_is_full_rect_shader_overlay() -> void:
	# 真玻璃不是只换深色底: ColorRect shader 要铺满顶栏并采样背后的 screen texture。
	assert_gt(_hud._top_bar.get_child_count(), 0)
	var glass: Node = _hud._top_bar.get_child(0)
	assert_true(glass is ColorRect, "顶栏第一个子节点应是玻璃 ColorRect")
	if glass is ColorRect:
		var rect := glass as ColorRect
		assert_eq(rect.mouse_filter, Control.MOUSE_FILTER_IGNORE)
		assert_eq(rect.anchor_left, 0.0)
		assert_eq(rect.anchor_top, 0.0)
		assert_eq(rect.anchor_right, 1.0)
		assert_eq(rect.anchor_bottom, 1.0)
		assert_true(rect.material is ShaderMaterial,
			"玻璃层应使用 ShaderMaterial 做 frosted glass")

func test_advance_button_is_inverted_light_primary_on_dark() -> void:
	# design §5: 深色玻璃上主操作"推进回合"反白 —— BG_SURFACE 白底 + TEXT_PRIMARY 炭黑字。
	var sb: StyleBox = _hud._advance_btn.get_theme_stylebox(&"normal")
	assert_true(sb is StyleBoxFlat, "推进按钮 normal stylebox 应为 StyleBoxFlat")
	if sb is StyleBoxFlat:
		var flat := sb as StyleBoxFlat
		assert_true(flat.bg_color.is_equal_approx(UITheme.BG_SURFACE),
			"推进按钮应反白 (BG_SURFACE 白底), 实际 %s" % flat.bg_color)
	assert_true(_hud._advance_btn.get_theme_color(&"font_color").is_equal_approx(UITheme.TEXT_PRIMARY),
		"反白主按钮文字应为炭黑 TEXT_PRIMARY")

func test_top_bar_buttons_define_all_interaction_font_colors() -> void:
	for btn in [_hud._advance_btn, _hud._settings_btn, _hud._save_btn]:
		assert_not_null(btn)
		for color_name in [&"font_color", &"font_hover_color", &"font_pressed_color",
				&"font_hover_pressed_color", &"font_focus_color", &"font_disabled_color"]:
			var color := (btn as Button).get_theme_color(color_name)
			assert_false(color.is_equal_approx(UITheme.BG_SURFACE),
				"顶栏按钮 %s 的 %s 不能掉成白字" % [(btn as Button).text, String(color_name)])

func test_top_bar_ghost_buttons_override_focus_and_hover_pressed_styles() -> void:
	# 回归: 设置 / 存档按钮点击后进入 focus 或 hover_pressed 时不能掉回默认白底,
	# 否则浅色 on-dark 文字会看不清。
	for btn in [_hud._settings_btn, _hud._save_btn]:
		assert_true((btn as Button).has_theme_stylebox_override(&"focus"),
			"%s 必须覆盖 focus stylebox" % (btn as Button).text)
		assert_true((btn as Button).has_theme_stylebox_override(&"hover_pressed"),
			"%s 必须覆盖 hover_pressed stylebox" % (btn as Button).text)
		for style_name in [&"focus", &"hover_pressed"]:
			var sb: StyleBox = (btn as Button).get_theme_stylebox(style_name)
			assert_true(sb is StyleBoxFlat,
				"%s/%s 应为 StyleBoxFlat" % [(btn as Button).text, String(style_name)])
			if sb is StyleBoxFlat:
				var flat := sb as StyleBoxFlat
				assert_lt(flat.bg_color.a, 0.25,
					"%s/%s 只能是低透明玻璃底, 实际 %s" % [
						(btn as Button).text, String(style_name), flat.bg_color])

func test_top_bar_turn_chip_shows_week() -> void:
	# 旧契约保留: _turn_label.text 含 "周"。timeline_e2e_test 依赖。
	assert_true(String(_hud._turn_label.text).find("周") != -1,
		"turn chip 文案必须含 '周', 实际: %s" % _hud._turn_label.text)

func test_text_helpers_autowrap_for_text_heavy_tabs() -> void:
	var body: Label = _hud._label("一段很长的经营说明文本, 应该在窄窗口自然换行而不是被裁掉")
	var dim: Label = _hud._dim_label("一段很长的次级说明文本, 也应该保留换行能力")
	assert_eq(body.autowrap_mode, TextServer.AUTOWRAP_WORD_SMART)
	assert_eq(dim.autowrap_mode, TextServer.AUTOWRAP_WORD_SMART)
	assert_true(body.get_theme_color(&"font_color").is_equal_approx(UITheme.TEXT_PRIMARY))
	assert_true(dim.get_theme_color(&"font_color").is_equal_approx(UITheme.TEXT_SECONDARY))

func test_top_bar_cashflow_chip_value_not_blank_on_first_refresh() -> void:
	# Bug 5: 旧实现把 value 写死空字符串, 只在第二回合之后才显示 delta_text → 玩家
	# 看到"周净流" chip 永远空白。修复后首次刷新就显示当周净流 (账本/cash delta),
	# 没数据则降级到 "—" 不再空白。
	_hud._refresh()
	var chip = _hud._chip_cashflow
	assert_not_null(chip, "_chip_cashflow 应存在")
	assert_ne(chip.get_value_text().strip_edges(), "",
			"周净流 chip 首次刷新就应有可见值, 实际为空字符串")

func test_top_bar_cashflow_chip_uses_weekly_ledger_when_available() -> void:
	# Bug 5: 优先读 weekly_ledger 的 gross_in - gross_out, 玩家就看到本周真实净流,
	# 而不是只是相邻两 tick 的 cash diff。
	GameState.weekly_ledger = {
		"income": {"monetization": 50_000},
		"expense": {"salary": 12_000},
		"gross_in": 50_000,
		"gross_out": 12_000,
	}
	_hud._refresh()
	var chip = _hud._chip_cashflow
	var text: String = chip.get_value_text()
	assert_true(text.find("38,000") != -1,
			"weekly_ledger 净流 +$38,000 应反映到 chip value, 实际: %s" % text)

func test_top_bar_cashflow_uses_real_economy_ledger_after_revenue_refresh() -> void:
	# 回归: EconomySystem 真实账本用 StringName key。旧 UI 只读 String key,
	# monetization.award 后又被 revenue_resolved 的二次刷新刷回 +$0。
	CommandBus.send(&"economy.spend", {cost = {&"cash": 12_000}, reason = &"salaries"})
	CommandBus.send(&"economy.award", {amount = 50_000, reason = &"monetization"})
	EventBus.revenue_resolved.emit(GameState.turn, {
		api_total = 50_000,
		subscription_total = 0,
	})

	var chip = _hud._chip_cashflow
	var text: String = chip.get_value_text()
	assert_eq(text, "+$38,000",
			"周净流应显示真实账本净额: gross_in 50,000 - gross_out 12,000, 实际: %s" % text)

func test_top_bar_cashflow_keeps_completed_week_after_ledger_roll() -> void:
	# resolve 会把当前账本滚入 ledger_history 并把 weekly_ledger 清零。
	# 顶栏此时仍应展示刚完成这一周的真实净流, 而不是清零后的 +$0。
	CommandBus.send(&"economy.spend", {cost = {&"cash": 12_000}, reason = &"salaries"})
	CommandBus.send(&"economy.award", {amount = 50_000, reason = &"monetization"})
	EventBus.phase_started.emit(&"resolve", GameState.turn)

	var chip = _hud._chip_cashflow
	var text: String = chip.get_value_text()
	assert_eq(text, "+$38,000",
			"账本滚动后应继续显示最近完成周净流 +$38,000, 实际: %s" % text)

func test_hud_batches_refreshes_during_turn_advance() -> void:
	# 后期一周会同步连发扣费 / 任务 / 用户 / 营收 / 排榜等事件。
	# Main 应在 TurnManager.advance() 中合并这些刷新请求, turn_resolved 后只重建一次。
	_hud.reset_refresh_count_for_test()
	var burst := func(phase: StringName, turn: int) -> void:
		if phase != &"action":
			return
		EventBus.cash_changed.emit(-100, &"test")
		EventBus.task_progress.emit(&"task_perf", 1, 2)
		EventBus.leaderboard_resolved.emit(turn)
		EventBus.revenue_resolved.emit(turn, {api_total = 0, subscription_total = 0})
	EventBus.phase_started.connect(burst)

	TurnManager.advance()

	EventBus.phase_started.disconnect(burst)
	assert_eq(_hud.get_refresh_count_for_test(), 1,
			"推进一周中的多次 UI 刷新请求应合并成 1 次实际 _refresh")

func test_hud_refreshes_immediately_outside_turn_advance() -> void:
	_hud.reset_refresh_count_for_test()
	EventBus.cash_changed.emit(-100, &"test")
	assert_eq(_hud.get_refresh_count_for_test(), 1,
			"非回合推进中的普通事件仍应即时刷新, 保持按钮/对话框反馈直接")

func test_advance_switches_to_events_tab_when_event_is_pushed() -> void:
	# 玩家点「推进回合」后若 action 相位产生待处理事件, HUD 应直接把玩家带去事件页。
	_hud.click_sidebar_for_test(&"overview")
	var push_event := func(phase: StringName, _turn: int) -> void:
		if phase != &"action":
			return
		CommandBus.send(&"event.trigger_card", {template_id = &"debug_test_offer"})
	EventBus.phase_started.connect(push_event)

	_hud._on_advance_pressed()

	EventBus.phase_started.disconnect(push_event)
	await get_tree().process_frame
	assert_gt(GameState.pending_events.size(), 0,
			"测试夹具应在推进中推入 pending 事件")
	assert_eq(_hud._tabs.get_tab_title(_hud._tabs.current_tab), "事件",
			"推进后有待处理事件时应自动切到事件 tab")
	assert_true(_hud.is_sidebar_item_active(&"events"),
			"侧栏 active 态也应跟随切到 events")

func test_blocked_advance_switches_to_events_tab_for_existing_pending() -> void:
	var r: Dictionary = CommandBus.send(&"event.trigger_card", {template_id = &"debug_test_offer"})
	assert_true(r.ok, "测试应能预置一个 pending 事件")
	_hud.click_sidebar_for_test(&"overview")

	_hud._on_advance_pressed()

	assert_eq(GameState.turn, 0, "已有 pending 事件时不应推进回合")
	assert_eq(_hud._tabs.get_tab_title(_hud._tabs.current_tab), "事件",
			"已有 pending 事件时点击推进处理函数应切到事件 tab 提示玩家处理")

func test_event_tab_shows_placeholder_when_pending_template_is_missing() -> void:
	var inst := EventInstance.new()
	inst.id = &"event_missing_template"
	inst.template_id = &"missing_template_for_test"
	GameState.pending_events.append(inst)
	_hud._refresh()
	await get_tree().process_frame
	var labels: PackedStringArray = _hud._event_view.all_label_texts_for_test()
	var has_placeholder := false
	for text in labels:
		if String(text).find("事件模板缺失") != -1:
			has_placeholder = true
	assert_true(has_placeholder,
		"pending event 缺模板时事件页也必须显示占位卡, 实际 labels: %s" % str(labels))
	_hud._event_view.click_dismiss_for_test(&"event_missing_template")
	await get_tree().process_frame
	assert_eq(GameState.pending_events.size(), 0,
		"缺模板占位事件也应能点「知道了」清掉, 避免永久卡住推进")

func test_event_card_choice_defers_resolution_until_next_frame() -> void:
	var r: Dictionary = CommandBus.send(&"event.trigger_card", {template_id = &"routine_coffee_machine"})
	assert_true(r.ok, "测试应能预置 routine_coffee_machine 事件")
	_hud.click_sidebar_for_test(&"events")
	_hud._refresh()
	await get_tree().process_frame

	_hud.reset_refresh_count_for_test()
	_hud._event_view.click_option_for_test(StringName(r.event_id), &"instant")

	assert_eq(GameState.pending_events.size(), 1,
		"事件卡 action 不应在按钮 pressed 同帧内结算并触发 HUD 重建")
	assert_eq(_hud.get_refresh_count_for_test(), 0,
		"事件卡 action 同帧不应因 event_resolved 刷新并释放当前卡片")
	await get_tree().process_frame
	assert_eq(GameState.pending_events.size(), 0,
		"下一帧应正常处理事件选项")
	assert_gt(_hud.get_refresh_count_for_test(), 0,
		"下一帧 event_resolved 后 HUD 应刷新")

func test_hud_rerenders_on_locale_changed() -> void:
	# 切语言 → 重渲染全部 tab, 让 tr(...) 在新 locale 下重新求值 (国际化设计 §11.2)。
	_hud.reset_refresh_count_for_test()
	EventBus.locale_changed.emit("en")
	assert_eq(_hud.get_refresh_count_for_test(), 1,
			"locale_changed 应触发一次 _refresh 重建全部 tab")

	# ─── 侧栏: 4 组 18 项 ────────────────────────────────────────

func test_sidebar_has_four_groups() -> void:
	assert_eq(_hud.get_sidebar_group_count(), 4,
		"侧栏应当有 4 组, 实际 %d" % _hud.get_sidebar_group_count())

func test_sidebar_has_eighteen_items() -> void:
	# 运营 6 + 研发 4 + 市场 4 + 其他 4 = 18 (其他 = 办公室 / 拍卖行 / 慈善 / 帮助)。
	assert_eq(_hud.get_sidebar_item_count(), 18,
		"侧栏应当有 18 个导航项, 实际 %d" % _hud.get_sidebar_item_count())

func test_sidebar_group_titles_in_order() -> void:
	var titles: Array = _hud.get_sidebar_group_titles()
	assert_eq(titles.size(), 4)
	assert_true(String(titles[0]).find("运营") != -1, "第一组应当含 '运营'")
	assert_true(String(titles[1]).find("研发") != -1, "第二组应当含 '研发'")
	assert_true(String(titles[2]).find("市场") != -1, "第三组应当含 '市场'")
	assert_true(String(titles[3]).find("其他") != -1, "第四组应当含 '其他'")

func test_sidebar_group_titles_localize_to_en() -> void:
	# 侧栏导航走 tr() (国际化设计 §2bis): 切到 en 后重设导航文案应显示英文。
	# tab 节点名 (隐藏) 仍是中文, 由其它 tab-title 测试钉住。
	var saved := TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	_hud._refresh_nav_labels()
	var titles: Array = _hud.get_sidebar_group_titles()
	TranslationServer.set_locale(saved)
	assert_true(String(titles[0]).to_lower().find("operations") != -1,
		"en 下第一组应为 Operations, 实际: %s" % titles[0])
	assert_true(String(titles[2]).to_lower().find("market") != -1,
		"en 下第三组应为 Market, 实际: %s" % titles[2])

func test_sidebar_models_item_exists() -> void:
	# 关键 nav id (后续 §10 step 5 需要打开模型视图)。
	assert_true(_hud.has_sidebar_item(&"models"))
	assert_true(_hud.has_sidebar_item(&"infra"))
	assert_true(_hud.has_sidebar_item(&"overview"))

# ─── 侧栏点击切 tab ─────────────────────────────────────────

func test_clicking_models_nav_switches_tab_to_models() -> void:
	# 试点期约定 (§10 step 4): SidebarItem 点击驱动 _tabs.current_tab 切到对应 tab。
	# 模型 tab 在 _build_tabs() 里位置可能变, 用 tab title 反查。
	_hud.click_sidebar_for_test(&"models")
	await get_tree().process_frame
	var current_title: String = _hud._tabs.get_tab_title(_hud._tabs.current_tab)
	assert_eq(current_title, "模型",
		"点 models 应当切到 '模型' tab, 实际: %s" % current_title)

func test_clicking_infra_nav_switches_tab_to_infra() -> void:
	_hud.click_sidebar_for_test(&"infra")
	await get_tree().process_frame
	assert_eq(_hud._tabs.get_tab_title(_hud._tabs.current_tab), "基建")

func test_clicking_staff_nav_switches_tab_to_staff() -> void:
	# 招聘界面拆分: 新增的「员工」导航项应切到 '员工' tab。
	_hud.click_sidebar_for_test(&"staff")
	await get_tree().process_frame
	assert_eq(_hud._tabs.get_tab_title(_hud._tabs.current_tab), "员工")

func test_sidebar_active_state_follows_selection() -> void:
	_hud.click_sidebar_for_test(&"models")
	await get_tree().process_frame
	assert_true(_hud.is_sidebar_item_active(&"models"))
	assert_false(_hud.is_sidebar_item_active(&"overview"))
	_hud.click_sidebar_for_test(&"overview")
	await get_tree().process_frame
	assert_true(_hud.is_sidebar_item_active(&"overview"))
	assert_false(_hud.is_sidebar_item_active(&"models"))

func test_sidebar_active_icon_tile_is_reversed() -> void:
	# design §6: 当前页 icon 用深色 tile + 反白 glyph, 比普通文字列表更有导航识别度。
	_hud.click_sidebar_for_test(&"models")
	await get_tree().process_frame
	assert_true(_hud.sidebar_icon_tile_bg_for_test(&"models").is_equal_approx(UITheme.ACCENT_INFO),
		"选中的 models icon tile 应为炭黑底")
	assert_true(_hud.sidebar_icon_color_for_test(&"models").is_equal_approx(UITheme.BG_SURFACE),
		"选中的 models icon glyph 应反白")
	assert_true(_hud.sidebar_icon_tile_bg_for_test(&"overview").is_equal_approx(UITheme.BG_SURFACE),
		"未选中的 overview icon tile 应回到白底")

# ─── 侧栏事件 badge ─────────────────────────────────────────

func test_events_sidebar_badge_hidden_when_no_pending() -> void:
	_hud._refresh()
	await get_tree().process_frame
	assert_eq(_hud.sidebar_badge_text_for_test(&"events"), "",
		"无待处理事件时, 事件项不应有 badge")

func test_events_sidebar_badge_shows_pending_count() -> void:
	for i in range(2):
		var inst := EventInstance.new()
		inst.id = StringName("ev_test_%d" % i)
		inst.template_id = &"debug_test_offer"
		GameState.pending_events.append(inst)
	_hud._refresh()
	await get_tree().process_frame
	assert_eq(_hud.sidebar_badge_text_for_test(&"events"), "2",
		"2 个待处理事件 → 事件项 badge 应显示 '2'")

# ─── 员工职能名走 tr() (修复: "员工 (按职能)" 曾直出枚举名 ml_eng) ─────────

func test_staff_rows_use_translated_role_labels() -> void:
	# main.gd 组装 staff_rows 时, label 应是翻译后的职能名 (经 _staff_role_label),
	# 不再是未翻译的枚举名 (ml_eng / infra_eng …)。locale 已在 before_each 钉 zh_CN。
	GameState.staff_pool[&"ml_eng"] = 2
	var data: Dictionary = _hud._build_hiring_view_data()
	var ml_label := ""
	for row in (data.get("staff_rows", []) as Array):
		if StringName(row.get("role", &"")) == &"ml_eng":
			ml_label = String(row.get("label", ""))
	assert_eq(ml_label, tr("STAFF_ROLE_ML_ENG"),
		"ml_eng 行 label 应等于 tr(\"STAFF_ROLE_ML_ENG\")")
	assert_ne(ml_label, "ml_eng",
		"label 不应是未翻译的枚举名 ml_eng")

# ─── 抽屉默认隐藏 ────────────────────────────────────────────

func test_drawer_starts_hidden() -> void:
	assert_false(_hud._drawer_host.visible, "抽屉初始必须隐藏")

# ─── TabContainer fallback: tab 数 / tab 名 不变 ─────────────

func test_tab_container_has_eighteen_tabs() -> void:
	assert_eq(_hud._tabs.get_tab_count(), 18,
		"TabContainer 承载 18 tab (其他组 = 办公室 / 拍卖行 / 慈善 / 帮助)")

func test_tab_bar_is_hidden() -> void:
	# 新 layout 用侧栏导航, 顶部 tab bar 不再可见。
	assert_false(_hud._tabs.tabs_visible,
		"启用侧栏后 TabContainer 的 tab bar 应隐藏")

# ─── 帮助导航 (教程与帮助 §2) ────────────────────────────────

func test_sidebar_has_help_nav_item() -> void:
	assert_true(_hud._sidebar_items.has(&"help"),
		"右侧导航应有「帮助」项")

func test_help_nav_switches_to_help_tab_and_renders_view() -> void:
	_hud._on_sidebar_nav_pressed(&"help")
	assert_not_null(_hud._help_view, "切到帮助 nav 应实例化 HelpView")
	assert_true(_hud._help_view.topic_count() > 0,
		"HelpView 应渲染出帮助话题")
