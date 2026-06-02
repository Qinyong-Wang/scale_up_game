extends Control

## v1 HUD with a TabContainer covering all 13 systems.
## Per design/玩法设计.md §2.
##
## Layout:
##   - top bar: 回合 / 现金 / 名声 / 用户 / 模型 + [存档] [推进回合]
##   - tabs:    总览 / 经济 / 招聘 / 员工 / 基建 / 数据 / 模型 / 科技 /
##             任务 / 竞争对手 / 产品 / 营销 / 营收 / 事件
##   - status:  bottom-aligned message strip
##
## Discipline (design/游戏基础架构设计.md §7):
##   - Reads come straight from GameState.
##   - Writes go through CommandBus.
##   - Tabs subscribe to EventBus and call _refresh on every mutation.

const TEMPLATE_SPARROW_S := &"train_sparrow_s"
const TEMPLATE_DATA_COLLECTION := &"data_collection_default"
const TEMPLATE_POSTTRAIN := &"posttrain_general"
const TEMPLATE_EVALUATE := &"evaluate_general"
const DATASET_TEMPLATES_DIR := "res://resources/data/datasets"

const POWER_ORDER: Array[StringName] = [&"grid", &"solar", &"wind", &"nuclear", &"coal"]

const PretrainDialog := preload("res://scenes/ui/pretrain_dialog/pretrain_dialog.gd")
const NewDatacenterDialog := preload("res://scenes/ui/new_datacenter_dialog/new_datacenter_dialog.gd")
const NewProductDialog := preload("res://scenes/ui/new_product_dialog/new_product_dialog.gd")
const ResearchDialog := preload("res://scenes/ui/research_dialog/research_dialog.gd")
const LoanDialog := preload("res://scenes/ui/loan_dialog/loan_dialog.gd")
const PriceEditDialog := preload("res://scenes/ui/price_edit_dialog/price_edit_dialog.gd")
const FundingDialog := preload("res://scenes/ui/funding_dialog/funding_dialog.gd")
const SaveLoadDialog := preload("res://scenes/ui/save_load_dialog/save_load_dialog.gd")
const SettingsDialog := preload("res://scenes/ui/settings_dialog/settings_dialog.gd")
const CollectiblesDialog := preload("res://scenes/ui/collectibles_dialog/collectibles_dialog.gd")
const HonorDialog := preload("res://scenes/ui/honor_dialog/honor_dialog.gd")
const TutorialDialog := preload("res://scenes/ui/tutorial_dialog/tutorial_dialog.gd")

const START_SCENE := "res://scenes/start_screen/start_screen.tscn"

const StatChipScene := preload("res://scenes/ui/components/stat_chip/stat_chip.tscn")
const IconButtonScene := preload("res://scenes/ui/components/icon_button/icon_button.tscn")
const SidebarItemScene := preload("res://scenes/ui/components/sidebar_item/sidebar_item.tscn")
const SidebarGroupScene := preload("res://scenes/ui/components/sidebar_group/sidebar_group.tscn")
const DrawerScene := preload("res://scenes/ui/components/drawer/drawer.tscn")
const ModelViewScene := preload("res://scenes/ui/views/model_view/model_view.tscn")
const HiringViewScene := preload("res://scenes/ui/views/hiring_view/hiring_view.tscn")
const StaffViewScene := preload("res://scenes/ui/views/staff_view/staff_view.tscn")
const InfraViewScene := preload("res://scenes/ui/views/infra_view/infra_view.tscn")
const ProductViewScene := preload("res://scenes/ui/views/product_view/product_view.tscn")
const RevenueViewScene := preload("res://scenes/ui/views/revenue_view/revenue_view.tscn")
const DatasetViewScene := preload("res://scenes/ui/views/dataset_view/dataset_view.tscn")
const TasksViewScene := preload("res://scenes/ui/views/tasks_view/tasks_view.tscn")
const EventViewScene := preload("res://scenes/ui/views/event_view/event_view.tscn")
const TechViewScene := preload("res://scenes/ui/views/tech_view/tech_view.tscn")
const MarketingViewScene := preload("res://scenes/ui/views/marketing_view/marketing_view.tscn")
const CharityViewScene := preload("res://scenes/ui/views/charity/charity_view.tscn")
const OfficeViewScene := preload("res://scenes/ui/views/office/office_view.tscn")
const AuctionViewScene := preload("res://scenes/ui/views/auction/auction_view.tscn")
const LeaderboardViewScene := preload("res://scenes/ui/views/leaderboard_view/leaderboard_view.tscn")
const HelpViewScene := preload("res://scenes/ui/views/help_view/help_view.tscn")

# Sidebar nav 配置 (design/UI视觉系统设计.md §6)。
# nav_id 是稳定的语义键; tab_title 用来反查 TabContainer 当前 tab 索引,
# 试点期 (§10 step 4) SidebarItem 点击仍驱动 _tabs.current_tab 切换。
# `icon` 是 Material Icons 字体 (assets/fonts/icons.ttf) 的码点; 渲染时
# char() 转字符并套图标字体。注释里是对应的 Material Icons 名。
# `label` / `group_title` 是 i18n key (国际化设计 §2bis), 渲染时 tr()。
# `tab` 仍是中文 — 它是隐藏的 TabContainer 节点名 (tabs_visible=false),
# 只用于 _populate_nav_to_tab_index 反查索引, 不上屏, 不必翻译。
const SIDEBAR_NAV: Array = [
	{
		"group_title": "NAV_OPERATIONS",
		"items": [
			{"id": &"overview",     "icon": 0xe871, "label": "NAV_OVERVIEW", "tab": "总览"},  # dashboard
			{"id": &"economy",      "icon": 0xe84f, "label": "NAV_ECONOMY",  "tab": "经济"},  # account_balance
			{"id": &"hiring",       "icon": 0xe7fe, "label": "NAV_HIRING",   "tab": "招聘"},  # person_add
			{"id": &"staff",        "icon": 0xf233, "label": "NAV_STAFF",    "tab": "员工"},  # groups
			{"id": &"tasks",        "icon": 0xe6b1, "label": "NAV_TASKS",    "tab": "任务"},  # checklist
			{"id": &"events",       "icon": 0xe7f4, "label": "NAV_EVENTS",   "tab": "事件"},  # notifications
		],
	},
	{
		"group_title": "NAV_RND",
		"items": [
			{"id": &"models",       "icon": 0xf06c, "label": "NAV_MODELS",   "tab": "模型"},  # smart_toy
			{"id": &"infra",        "icon": 0xe875, "label": "NAV_INFRA",    "tab": "基建"},  # dns
			{"id": &"dataset",      "icon": 0xf8ee, "label": "NAV_DATASET",  "tab": "数据"},  # dataset
			{"id": &"tech",         "icon": 0xea4b, "label": "NAV_TECH",     "tab": "科技"},  # science
		],
	},
	{
		"group_title": "NAV_GROUP_MARKET",
		"items": [
			{"id": &"product",      "icon": 0xe1bd, "label": "NAV_PRODUCT",      "tab": "产品"},  # widgets
			{"id": &"marketing",    "icon": 0xef49, "label": "NAV_MARKETING",    "tab": "营销"},  # campaign
			{"id": &"market_rank",  "icon": 0xf20c, "label": "NAV_MARKET",       "tab": "竞争对手"},  # leaderboard
			{"id": &"monetization", "icon": 0xef63, "label": "NAV_MONETIZATION", "tab": "营收"},  # payments
		],
	},
	{
		"group_title": "NAV_GROUP_OTHER",
		"items": [
			{"id": &"office",       "icon": 0xea65, "label": "NAV_OFFICE",       "tab": "办公室"},  # emoji_events
			{"id": &"auction",      "icon": 0xea3f, "label": "NAV_AUCTION",      "tab": "拍卖行"},  # gavel
			{"id": &"charity",      "icon": 0xe87d, "label": "NAV_CHARITY",      "tab": "慈善"},  # favorite
			{"id": &"help",         "icon": 0xe887, "label": "NAV_HELP",         "tab": "帮助"},  # help
		],
	},
]

# Header labels.
var _turn_label: Label
var _cash_label: Label
var _users_label: Label
var _models_label: Label
var _status_label: Label

# Per-tab content roots — refreshed on every event.
var _tabs: TabContainer
var _tab_overview: VBoxContainer
var _tab_economy: VBoxContainer
var _tab_hiring: VBoxContainer
var _tab_staff: VBoxContainer
var _tab_infra: VBoxContainer
var _tab_dataset: VBoxContainer
var _tab_research: VBoxContainer
var _tab_tech: VBoxContainer
var _tab_tasks: VBoxContainer
var _tab_market: VBoxContainer
var _tab_product: VBoxContainer
var _tab_marketing: VBoxContainer
var _tab_revenue: VBoxContainer
var _tab_event: VBoxContainer
var _tab_charity: VBoxContainer
var _tab_office: VBoxContainer
var _tab_auction: VBoxContainer
var _tab_help: VBoxContainer

# ---- 新 shell (§10 step 4) -------------------------------------------------
var _top_bar: Control          # 顶栏 (Logo + 5 StatChip + 3 IconButton)
var _company_label: Label      # 顶栏左侧公司名 (玩家在新游戏时取的名字)
var _sidebar: Control          # 侧栏 VBox (4 SidebarGroup × 18 SidebarItem)
var _main_panel: Control       # 主区, 包 _tabs
var _drawer_host: Control      # 右抽屉 (Drawer 实例)

# StatChip 引用, 顶栏指标。
var _chip_turn: Control
var _chip_cash: Control
var _chip_cashflow: Control
var _chip_paid_users: Control
var _chip_compute: Control

# 顶栏「推进回合」按钮 — pending 事件未处理完时禁用 (事件系统设计.md §2)。
var _advance_btn: Button
# 顶栏「存档」按钮 — 存 ref 以便语言切换时重设文案。
var _save_btn: Button
# 顶栏「设置」按钮 — 游戏内打开 SettingsDialog (切语言 / 自动存档)。
var _settings_btn: Button

# SidebarItem 引用, nav_id → SidebarItem。
var _sidebar_items: Dictionary = {}
# SidebarGroup 引用, 按 SIDEBAR_NAV 顺序; 语言切换时重设组标题。
var _sidebar_groups: Array = []
# nav_id → TabContainer index, _build_sidebar 时一次性算好, 避免运行时字符串查找。
var _nav_to_tab_index: Dictionary = {}

# §10 step 5: 模型 tab 试点的 ModelCardView 实例。
var _model_view: Control
# §10 step 6: 招聘 tab 试点的 HiringView 实例。
var _hiring_view: Control
# 员工 tab 的 StaffView 实例 (招聘界面拆分出的「在册」一半)。
var _staff_view: Control
# §10 step 6 (第二批): 基建 tab 试点的 InfraView 实例。
var _infra_view: Control
# §10 step 6 (第三批): 产品 tab 试点的 ProductView 实例。
var _product_view: Control
# 营收 tab 视图 (营收系统设计 §6bis): 可折叠分组 + 占比条。
var _revenue_view: Control
# §10 step 6 (第四批): dataset/tasks/event/tech 试点 view 实例。
var _dataset_view: Control
var _tasks_view: Control
var _event_view: Control
var _tech_view: Control
# v7 PR-F2: 营销 tab 试点视图实例。
var _marketing_view: Control
# 慈善 tab 视图实例 (见 design/慈善系统设计.md §8)。
var _charity_view: Control
# 办公室 tab 视图实例 (见 design/办公室与收藏系统设计.md §8)。
var _office_view: Control
# 拍卖行 tab 视图实例。
var _auction_view: Control
# 竞争对手 tab 的 LeaderboardView 实例 (荣耀榜单, 见 design/竞争对手系统设计.md §8)。
var _leaderboard_view: Control
# 帮助 tab 的 HelpView 实例 (系统说明, 见 design/教程与帮助系统设计.md §2)。
var _help_view: Control
# 当前激活的 nav_id。
var _active_nav: StringName = &"overview"
# U-5: 竞争对手 tab 当前选中的榜单。默认总榜, 玩家点其他按钮切换。
var _active_market_board: StringName = &"total"

# 上回合现金快照, 用于算周净流 delta。
var _last_turn_cash: int = -1
var _last_turn_for_delta: int = -1
var _refresh_pending: bool = false
var _refresh_count_for_test: int = 0
# 破产终局只弹一次 Game Over 弹窗 (cash_too_deep 可能每周重复触发)。见 §4.2。
var _game_over_shown: bool = false
# 破产预警弹窗每段赤字只弹一次; cash 回正后 (streak 归零再起新一段) 自动复位。
var _bankruptcy_warned: bool = false
# 宇宙模拟终局提示只弹一次; 结果本身由办公室里的 answer_box 打开。
var _universe_answer_prompt_shown: bool = false

func _ready() -> void:
	# 截图 / 调试用: AGI_LOCALE=en 强制界面语言 (不写盘, 不碰玩家持久化偏好)。
	if OS.has_environment("AGI_LOCALE"):
		TranslationServer.set_locale(OS.get_environment("AGI_LOCALE"))
	_apply_theme()
	_ensure_player_scientist_joined()
	_build_ui()
	_subscribe_events()
	_refresh()

	# 新游戏开局弹一次新手引导 (教程与帮助系统设计.md §1): 仅当起始页置了 pending_intro、
	# 玩家没勾「不再显示」、且非截图/自动跑模式。无论是否弹都清零 (一次性会话标志)。
	var show_intro := GameState.pending_intro and not Preferences.skip_intro
	GameState.pending_intro = false

	if OS.has_environment("AGI_AUTOPLAY"):
		_autoplay.call_deferred()
	elif OS.has_environment("AGI_SCREENSHOT"):
		_screenshot_and_quit.call_deferred()
	elif show_intro:
		_show_intro_tutorial.call_deferred()
	# When both env vars are set, _autoplay chains into _screenshot_and_quit at
	# its tail so the captured frame reflects the post-autoplay state.

func _subscribe_events() -> void:
	# Anything that mutates user-visible state triggers a refresh.
	EventBus.turn_resolved.connect(_on_turn_resolved)
	EventBus.resources_changed.connect(func(_d, _r): _request_refresh())
	EventBus.cash_changed.connect(func(_d, _r): _request_refresh())
	EventBus.debt_changed.connect(func(_d, _r): _request_refresh())
	EventBus.equity_changed.connect(func(_d): _request_refresh())
	EventBus.loan_taken.connect(func(_id): _request_refresh())
	EventBus.loan_repaid.connect(func(_id, _f): _request_refresh())
	EventBus.funding_completed.connect(func(_a, _d, _v): _request_refresh())
	EventBus.ledger_rolled.connect(func(_t, _s): _request_refresh())
	EventBus.bankruptcy_warning.connect(_on_bankruptcy_warning)
	EventBus.bankruptcy_triggered.connect(_on_bankruptcy_triggered)
	EventBus.paid_users_changed.connect(func(_d, _t): _request_refresh())
	EventBus.users_resolved.connect(func(_t, _d): _request_refresh())
	EventBus.token_demand_changed.connect(func(_m, _v): _request_refresh())

	EventBus.task_started.connect(func(_id, _sub): _request_refresh())
	EventBus.task_progress.connect(func(_id, _e, _t): _request_refresh())
	EventBus.task_completed.connect(func(_id, _sub, _p): _request_refresh())
	EventBus.task_cancelled.connect(func(_id, _r): _request_refresh())
	EventBus.task_delayed.connect(func(_id, _t): _request_refresh())
	EventBus.task_resources_locked.connect(func(_id, _l): _request_refresh())
	EventBus.task_resources_released.connect(func(_id, _r): _request_refresh())

	EventBus.lead_hired.connect(func(_id): _request_refresh())
	EventBus.lead_fired.connect(func(_id): _request_refresh())
	EventBus.lead_locked.connect(func(_id, _t): _request_refresh())
	EventBus.lead_released.connect(func(_id): _request_refresh())
	EventBus.lead_assigned.connect(func(_id, _p): _request_refresh())
	EventBus.lead_unassigned.connect(func(_id): _request_refresh())
	EventBus.lead_pool_refreshed.connect(func(_p): _request_refresh())
	EventBus.player_scientist_created.connect(func(_id): _request_refresh())
	EventBus.staff_changed.connect(func(_r, _c): _request_refresh())

	EventBus.datacenter_added.connect(func(_id): _request_refresh())
	EventBus.datacenter_removed.connect(func(_id): _request_refresh())
	EventBus.datacenter_status_changed.connect(func(_id, _o, _n): _request_refresh())
	EventBus.construction_progress.connect(func(_id, _r, _t): _request_refresh())
	EventBus.construction_completed.connect(func(_id, _dc): _request_refresh())
	EventBus.gpus_bought.connect(func(_dc, _g, _c, _t): _request_refresh())
	EventBus.gpus_sold.connect(func(_dc, _c, _r): _request_refresh())
	EventBus.dc_compute_recomputed.connect(func(_dc, _t, _i, _s): _request_refresh())
	EventBus.model_deployed.connect(func(_dc, _m): _request_refresh())
	EventBus.open_source_model_deployed.connect(func(_dc, _m): _request_refresh())
	EventBus.model_undeployed.connect(func(_dc, _m): _request_refresh())

	EventBus.dataset_added.connect(func(_id, _s): _request_refresh())
	EventBus.dataset_removed.connect(func(_id): _request_refresh())
	EventBus.dataset_locked.connect(func(_id, _t): _request_refresh())
	EventBus.dataset_released.connect(func(_id): _request_refresh())

	EventBus.model_added.connect(func(_id, _prov): _request_refresh())
	EventBus.model_evaluated.connect(func(_id, _c): _request_refresh())
	EventBus.model_updated.connect(func(_id, _d): _request_refresh())
	EventBus.model_published.connect(func(_id, _o): _request_refresh())
	EventBus.model_unpublished.connect(func(_id): _request_refresh())
	EventBus.model_deleted.connect(func(_id): _request_refresh())
	EventBus.model_price_changed.connect(func(_id, _p): _request_refresh())

	EventBus.tech_unlocked.connect(func(_t, _n): _request_refresh())
	EventBus.tech_research_started.connect(func(_t, _n, _id): _request_refresh())
	EventBus.tech_research_cancelled.connect(func(_t, _n): _request_refresh())

	EventBus.product_created.connect(func(_id): _request_refresh())
	EventBus.product_updated.connect(func(_id, _f): _request_refresh())
	EventBus.product_deleted.connect(func(_id): _request_refresh())
	EventBus.subscribers_changed.connect(func(_id, _d, _t): _request_refresh())
	EventBus.quality_recomputed.connect(func(_id, _q): _request_refresh())

	EventBus.campaign_started.connect(func(_id): _request_refresh())
	EventBus.campaign_terminated.connect(func(_id, _r): _request_refresh())
	EventBus.campaign_progress.connect(func(_id, _r, _t): _request_refresh())

	EventBus.revenue_resolved.connect(func(_t, _b): _request_refresh())

	EventBus.leaderboard_resolved.connect(func(_t): _request_refresh())
	EventBus.player_rank_changed.connect(func(_b, _o, _n): _request_refresh())
	EventBus.npc_released.connect(func(_n, _r, _t): _request_refresh())

	EventBus.event_pushed.connect(func(_id, _c, _t): _request_refresh())
	EventBus.event_resolved.connect(func(_id, _o, _ae): _request_refresh())

	EventBus.charity_completed.connect(func(_c, _a, _cum): _request_refresh())

	EventBus.collectible_bought.connect(func(_id, _p): _request_refresh())
	EventBus.collectible_sold.connect(func(_id, _p): _request_refresh())
	EventBus.trophy_awarded.connect(func(_id): _request_refresh())

	EventBus.simulation_stage_completed.connect(func(_s, _d): _request_refresh())
	EventBus.universe_answer_revealed.connect(_on_universe_answer_revealed)

	EventBus.save_loaded.connect(func(): _request_refresh())

	# i18n: 语言切换 → 重渲染全部 tab + 顶栏 + 侧栏导航 (国际化设计 §11.2)。
	EventBus.locale_changed.connect(func(_loc): _on_locale_changed())

# ---- autoplay / screenshot ---------------------------------------------

func _autoplay() -> void:
	await get_tree().process_frame
	# Scripted "rational player" demo. Walks the full v1 loop end-to-end so the
	# resulting screenshot shows a populated game state (cash growing, fame
	# accruing, leaderboard ranked, product live, funding event resolved).

	# 1. Hire a balanced founding team. Seed fixed leads (signing fee 0) so the
	#    autoplay is deterministic regardless of lead_pool RNG.
	# Per design/招聘系统设计.md §5.4: 至少需要 chief_scientist / ml_research_lead /
	# eval_lead / data_scientist / chief_engineer 才能跑完整循环 (pretrain /
	# posttrain / evaluate / data_collection / product)。
	for cfg in [
		{id = &"auto_cs", spec = &"chief_scientist",  level = &"S", ability = 92.0},
		{id = &"auto_ce", spec = &"chief_engineer",   level = &"A", ability = 80.0},
		{id = &"auto_ml", spec = &"ml_research_lead", level = &"A", ability = 75.0},
		{id = &"auto_ev", spec = &"eval_lead",        level = &"B", ability = 65.0},
		{id = &"auto_ds", spec = &"data_scientist",   level = &"B", ability = 65.0},
	]:
		var l := Lead.new()
		l.id = cfg.id
		l.display_name = "Auto " + String(cfg.spec)
		l.specialty = cfg.spec
		l.level = cfg.level
		l.ability = cfg.ability
		l.signing_fee = 0
		l.weekly_salary = 1_150
		GameState.leads.append(l)
	CommandBus.send(&"hiring.adjust_staff", {role = &"ml_eng", delta = 4})
	CommandBus.send(&"hiring.adjust_staff", {role = &"ops",   delta = 1})

	# 2. Download an OS model — instant published candidate, no training needed.
	# v9 PR-I: 第一条 OS pretrain release (Wolf-1) 在 turn 215; autoplay 是 demo
	# (截图用), 直接把 turn 推到 335 让 Wolf-3 (405B dense) 可用.
	if GameState.turn < 335:
		GameState.turn = 335
	var dl: Dictionary = CommandBus.send(&"research.download_open_source",
			{release_id = &"release_wolf_3"})
	var wolf_id: StringName = dl.get(&"model_id", &"")

	# 3. Stand up infra: a pod facility for training + a solo facility for
	#    serving. Buy GPUs into each so they can do real work.
	var fac_train: Dictionary = CommandBus.send(&"infra.rent_facility",
			{facility_spec_id = &"facility_pod", power_supply_id = &"grid"})
	if fac_train.ok:
		CommandBus.send(&"infra.buy_gpus",
				{dc_id = fac_train.dc_id, gpu_id = &"cypress_t0", count = 4})
	var fac_serve: Dictionary = CommandBus.send(&"infra.rent_facility",
			{facility_spec_id = &"facility_solo", power_supply_id = &"grid"})
	if fac_serve.ok:
		CommandBus.send(&"infra.buy_gpus",
				{dc_id = fac_serve.dc_id, gpu_id = &"cypress_t0", count = 1})

	# 4. Publish wolf_os as open source and deploy it to the serving DC.
	if wolf_id != &"":
		CommandBus.send(&"research.publish_model",
				{model_id = wolf_id, is_open_source = true, per_token_price = 0.000001})
		if fac_serve.ok:
			CommandBus.send(&"infra.deploy_model",
					{dc_id = fac_serve.dc_id, model_id = wolf_id})

	# 5. Acquire a training dataset and create a chatbot product on wolf_os.
	CommandBus.send(&"dataset.acquire_open", {template_id = &"web_corpus_v1"})
	var chatbot_product_id: StringName = &""
	if wolf_id != &"":
		var pr: Dictionary = CommandBus.send(&"product.create", {
			type = &"chatbot",
			display_name = "OpenChat Pro",
			lead_id = &"auto_ce",
			bound_model_id = wolf_id,
			subscription_price = 5,
			staff = {&"ml_eng": 1},
			auto_track_latest = true,
		})
		if pr.ok:
			chatbot_product_id = StringName(pr.get(&"product_id", &""))

	# 6. Launch a small marketing campaign 锁 chatbot 产品 (v7 PR-F3).
	if chatbot_product_id != &"":
		CommandBus.send(&"marketing.start_campaign", {
			display_name = "Launch",
			weekly_budget = 1_840,
			total_weeks = 26,
			target_product_id = chatbot_product_id,
		})

	# 7. Advance ~8 weeks. Auto-accept any funding-round event that pops in.
	for i in range(8):
		await get_tree().process_frame
		TurnManager.advance()
		_autoplay_handle_pending_events()

	# 8. Force one more refresh so all tab labels reflect the final state, then
	#    chain into the screenshot if requested. Await a few frames inline so
	#    the renderer flushes the new label text into the framebuffer before
	#    we grab the viewport image.
	_refresh()
	if OS.has_environment("AGI_SCREENSHOT"):
		for i in range(12):
			await get_tree().process_frame
		await _screenshot_and_quit()

func _autoplay_handle_pending_events() -> void:
	if GameState.pending_events.is_empty():
		return
	# Resolve from the front of the FIFO; pick "accept" when present.
	var inst = GameState.pending_events[0]
	var card = _load_card(inst.template_id)
	if card == null:
		return
	if card.category == &"flavor":
		CommandBus.send(&"event.dismiss_flavor", {event_id = inst.id})
		return
	for opt in card.options:
		if String(opt.id) == "accept":
			CommandBus.send(&"event.choose_option",
					{event_id = inst.id, option_id = opt.id})
			return

func _open_drawer_for_screenshot(scenario: String) -> void:
	# 截图测试用; 把抽屉撑开到指定场景。新场景在这里加分支。
	# dialog:<name> 形式触发 modal dialog 截图 (验收浅色主题对 modal 的覆盖)。
	match scenario:
		"deploy_first_dc":
			# 切到 infra tab, 找第一个 idle DC, 触发部署抽屉。
			if _sidebar_items.has(&"infra"):
				_on_sidebar_nav_pressed(&"infra")
			for dc in GameState.datacenters:
				if dc.status == &"idle":
					_open_deploy_drawer_for_dc(dc.id)
					return
		"dialog:new_datacenter":
			if _sidebar_items.has(&"infra"):
				_on_sidebar_nav_pressed(&"infra")
			_on_open_new_datacenter_dialog()
		"dialog:new_campaign":
			if _sidebar_items.has(&"marketing"):
				_on_sidebar_nav_pressed(&"marketing")
			_on_new_campaign_pressed()
		"dialog:new_product":
			if _sidebar_items.has(&"product"):
				_on_sidebar_nav_pressed(&"product")
			_on_open_new_product_dialog()
		"dialog:pretrain":
			if _sidebar_items.has(&"models"):
				_on_sidebar_nav_pressed(&"models")
			_on_open_pretrain_dialog()
		"dialog:loan":
			if _sidebar_items.has(&"economy"):
				_on_sidebar_nav_pressed(&"economy")
			_open_loan_dialog()
		"dialog:funding_angel":
			if _sidebar_items.has(&"economy"):
				_on_sidebar_nav_pressed(&"economy")
			_open_funding_dialog(&"pre_seed")
		"dialog:research_arch":
			if _sidebar_items.has(&"tech"):
				_on_sidebar_nav_pressed(&"tech")
			_open_research_dialog(&"arch", &"ant_v2")
		"dialog:tutorial":
			# 截图验收: 开局新手引导 (多页分步)。
			_show_intro_tutorial()
		"gameover":
			# 截图验收: 直接弹 Game Over 结算弹窗 (经济系统设计 §4.2)。
			_show_game_over_dialog(&"cash_negative_too_long")
		"dialog:posttrain":
			# 截图验收: 造一个未发布模型 + 后训练数据集, 打开后训练对话框 (自动选
			# ml_research_lead), 勾上数据集 → 预览显示"科学家后训练加分"。
			_shot_open_posttrain_dialog()
		"office":
			# 截图验收: 办公室房间。点亮全部荣誉 (桌上 3 枚慈善奖章 铜/银/金 + 茶几 2 个奖杯), 再切到办公室 tab。
			CollectionSystem.award_trophy(&"charity_bronze")
			CollectionSystem.award_trophy(&"charity_silver")
			CollectionSystem.award_trophy(&"charity_global")
			CollectionSystem.award_trophy(&"leaderboard_first")
			CollectionSystem.award_trophy(&"universe_answer")
			if _sidebar_items.has(&"office"):
				_on_sidebar_nav_pressed(&"office")
			_render_office_tab()
			# 截图用: 关掉 autoplay 跑到负现金弹出的破产预警, 别挡住房间。
			for w in get_tree().root.find_children("*", "Window", true, false):
				if w.visible:
					w.hide()
		"dialog:collectibles":
			# 截图验收: 收藏柜 dialog。先塞一件持有藏品 (从拍卖目录取首件), 再开 dialog。
			if _sidebar_items.has(&"office"):
				_on_sidebar_nav_pressed(&"office")
			var lots: Array = CollectionSystem.available_lots()
			if not lots.is_empty():
				var spec = lots[0]
				GameState.owned_collectibles[spec.id] = CollectionSystem.current_price(spec.id)
			_open_collectibles_dialog()
		"dialog:sim_donation":
			# 截图验收: 捐建数据中心 dialog (宇宙阶)。造一座满足门槛的自有空闲未出租 DC
			# (微型星球 + Cypress T3), 切到慈善 tab 再开 dialog。
			if _sidebar_items.has(&"charity"):
				_on_sidebar_nav_pressed(&"charity")
			var planet := Datacenter.new()
			planet.id = &"shot_planet"
			planet.display_name = "微型星球算力中心"
			planet.facility_spec_id = &"facility_planet"
			planet.ownership = &"owned"
			planet.status = &"idle"
			planet.gpu_id = &"cypress_t3"
			planet.gpu_count = 100_000_000
			planet.max_gpu_count = 100_000_000
			planet.train_tflops = 2.0e11
			GameState.datacenters.append(planet)
			GameState.cash = 2_000_000_000_000
			_open_sim_donation_dialog(&"universe")
		_:
			Log.warn(&"ui", "unknown AGI_OPEN_DRAWER scenario", {scenario = scenario})

## 截图脚手架: 备好一个可后训练的模型 + 数据集, 打开后训练对话框并勾选数据集。
func _shot_open_posttrain_dialog() -> void:
	var m := Model.new()
	m.id = &"shot_owl_pt"
	m.display_name = "ShotOwl"
	m.arch = &"ant_v1"
	m.size_params = 8_000.0
	m.capability = {&"general": 55.0, &"code": 40.0, &"reasoning": 48.0,
			&"multimodal": 20.0, &"agent": 10.0}
	m.capability_revealed = true
	m.status = &"evaluated"
	GameState.models.append(m)
	var ds := Dataset.new()
	ds.id = &"shot_pt_ds"
	ds.display_name = "ShotCode SFT"
	ds.kind = &"posttrain"
	ds.target_capability = &"code"
	ds.quality = 0.85
	ds.size = 3.0
	ds.source = &"purchased"
	GameState.datasets.append(ds)
	if _sidebar_items.has(&"models"):
		_on_sidebar_nav_pressed(&"models")
	var dlg: ConfirmationDialog = load(
			"res://scenes/ui/posttrain_dialog/posttrain_dialog.gd").new()
	dlg.set_base_model_id(m.id)
	add_child(dlg)
	dlg.refresh()
	# 勾上第一个数据集 (button_pressed 触发 toggled→_refresh_preview), 让预览给出
	# 真实 delta + 显示"科学家后训练加分"行。
	for entry in dlg._dataset_checkboxes:
		entry.box.button_pressed = true
		break
	dlg.popup_centered()

func _screenshot_and_quit() -> void:
	# AGI_INITIAL_NAV=<nav_id> 让视觉验收截图切到指定 tab; 见侧栏 SIDEBAR_NAV。
	# 例: AGI_INITIAL_NAV=models / infra / hiring / staff / product / dataset / tasks / events / tech。
	if OS.has_environment("AGI_INITIAL_NAV"):
		var nav := StringName(OS.get_environment("AGI_INITIAL_NAV"))
		if _sidebar_items.has(nav):
			_on_sidebar_nav_pressed(nav)
			await get_tree().process_frame
	# AGI_SHOT_REVENUE_DEMO=1: 注入一份代表性营收 breakdown 让营收视图在截图里展满
	# (autoplay 当前经济偏紧, 真营收常为 0)。隐藏弹窗 + 强切到营收 tab。Screenshot-only.
	if OS.has_environment("AGI_SHOT_REVENUE_DEMO"):
		for w in get_tree().root.find_children("*", "Window", true, false):
			if w.visible:
				w.hide()
		_seed_demo_revenue()
		if _sidebar_items.has(&"monetization"):
			_on_sidebar_nav_pressed(&"monetization")
		_render_revenue_tab()
		await get_tree().process_frame
	# AGI_OPEN_DRAWER=<scenario> 让截图带上抽屉打开状态, 验收 Drawer 视觉。
	# 当前支持:
	#   deploy_first_dc — 切 infra tab, 找第一个 idle DC, 触发部署抽屉。
	if OS.has_environment("AGI_OPEN_DRAWER"):
		var scenario := OS.get_environment("AGI_OPEN_DRAWER")
		_open_drawer_for_screenshot(scenario)
		await get_tree().process_frame
	# AGI_SHOT_RENT_ON=1: opt-in rent-out on every eligible idle dc (screenshot-only,
	# to demo the enabled card state — 「停止出租」按钮 + 「出租算力 +$X」收益行)。
	if OS.has_environment("AGI_SHOT_RENT_ON"):
		for dc in GameState.datacenters:
			if dc.ownership != &"cloud" and int(dc.gpu_count) > 0:
				CommandBus.send(&"infra.set_dc_rent_out", {dc_id = dc.id, enabled = true})
		_request_refresh()
		await get_tree().process_frame
	# AGI_SHOT_SCROLL=bottom: dismiss transient popup dialogs (e.g. bankruptcy
	# warning) that would cover content, then scroll the active tab to the bottom
	# so below-the-fold sections (财务账本明细) land in frame. Screenshot-only.
	if OS.has_environment("AGI_SHOT_SCROLL"):
		for w in get_tree().root.find_children("*", "Window", true, false):
			if w.visible:
				w.hide()
		await get_tree().process_frame
		var active: Control = _tabs.get_current_tab_control()
		if active is ScrollContainer and OS.get_environment("AGI_SHOT_SCROLL") == "bottom":
			(active as ScrollContainer).scroll_vertical = 1 << 24
		await get_tree().process_frame
	# Wait a few logic frames so any pending UI updates land, then explicitly
	# wait for the renderer to finish a draw before sampling the framebuffer.
	# Without `frame_post_draw`, get_image() can return a back buffer that
	# predates the latest label text by several ticks.
	for i in range(4):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	Log.info(&"ui", "screenshot_state", {
		turn = GameState.turn,
		cash = GameState.cash,
		users = GameState.paid_users,
		models = GameState.models.size(),
		label = _turn_label.text,
	})
	var img: Image = get_viewport().get_texture().get_image()
	var path := "user://screenshot.png"
	var err := img.save_png(path)
	Log.info(&"ui", "screenshot_saved", {
		error = err,
		path = ProjectSettings.globalize_path(path),
	})
	get_tree().quit(0)

# 仅截图用 (AGI_SHOT_REVENUE_DEMO): 造两组可解析的合成产品 + 一份营收 breakdown,
# 让 RevenueView 展满数据 (KPI / 来源条 / 两个可折叠分组 / 算力需求)。模型名走
# id-as-name 回落, 产品名走真实 Product。进程截完即退, 不影响真实存档。
func _seed_demo_revenue() -> void:
	var demo: Array = [
		{mid = &"Cedar-7B", api_pid = &"demo_cedar_api", api_name = "Cedar 接口",
			api_rev = 5_200_000_000, sub_pid = &"demo_cedar_chat", sub_name = "Cedar 聊天助手",
			sub_rev = 1_200_000_000, demand = 9_200_000_000, api_demand = 4_600_000_000},
		{mid = &"Maple-3B", api_pid = &"demo_maple_api", api_name = "Maple 接口",
			api_rev = 2_800_000_000, sub_pid = &"demo_maple_chat", sub_name = "Maple 编程助手",
			sub_rev = 2_800_000_000, demand = 5_100_000_000, api_demand = 2_550_000_000},
	]
	var api_per_model: Dictionary = {}
	var api_per_product: Dictionary = {}
	var sub_per_product: Dictionary = {}
	var api_total: int = 0
	var sub_total: int = 0
	for d in demo:
		_ensure_demo_product(d.api_pid, d.api_name, &"api", d.mid)
		_ensure_demo_product(d.sub_pid, d.sub_name, &"chatbot", d.mid)
		api_per_model[d.mid] = d.api_rev
		api_per_product[d.api_pid] = d.api_rev
		sub_per_product[d.sub_pid] = d.sub_rev
		api_total += int(d.api_rev)
		sub_total += int(d.sub_rev)
		GameState.token_demand[d.mid] = d.demand
		GameState.api_token_demand[d.mid] = d.api_demand
	GameState.last_revenue_breakdown = {
		turn = GameState.turn,
		api_total = api_total,
		api_per_model = api_per_model,
		api_per_product = api_per_product,
		subscription_total = sub_total,
		subscription_per_product = sub_per_product,
		api_demand_lost = 180_000_000,
	}

func _ensure_demo_product(pid: StringName, display_name: String, type: StringName,
		mid: StringName) -> void:
	for p in GameState.products:
		if p.id == pid:
			return
	var p := Product.new()
	p.id = pid
	p.display_name = display_name
	p.type = type
	p.bound_model_id = mid
	GameState.products.append(p)

# ---- theme --------------------------------------------------------------

func _apply_theme() -> void:
	UITheme.install()
	var t := Theme.new()
	var font: Font = _load_ui_font()
	if font != null:
		t.default_font = font
		t.default_font_size = UITheme.DEFAULT_FONT_SIZE
		UITheme.apply_font_to_theme(t, font)
	elif not _is_test_run():
		Log.error(&"ui", "cjk font failed to load")
	theme = t

func _load_ui_font() -> Font:
	return UITheme.get_ui_font()

func _is_test_run() -> bool:
	for arg in OS.get_cmdline_args():
		if arg.begins_with("-gtest") \
				or arg.begins_with("-gdir") \
				or arg == "--test" \
				or arg.find("gut_cmdln.gd") != -1:
			return true
	return false

# ---- UI construction ----------------------------------------------------

func _build_ui() -> void:
	# 新 shell (UI视觉系统设计.md §4):
	#   Main (Control, 全屏)
	#   └── VBox
	#       ├── TopBar (h=48)
	#       ├── HBox (expand_v)
	#       │   ├── Sidebar (w=220)
	#       │   ├── MainPanel (expand_h, 包 _tabs)
	#       │   └── DrawerHost (w=360, 默认 visible=false)
	#       └── StatusBar
	var root := VBoxContainer.new()
	root.anchor_right = 1.0
	root.anchor_bottom = 1.0
	root.add_theme_constant_override(&"separation", 0)
	add_child(root)

	# 内容区从 y=0 起 (含顶栏背后)。顶栏改成**浮层**覆盖在顶部, 内容在它下方且**背后**,
	# 玻璃顶栏的 shader 采样背后内容做模糊 = 真实 frosted glass。各区靠内部 top inset
	# (= TOP_BAR_H) 让可见内容落在顶栏下方, 同时背景 / 滚动内容仍铺到 y=0 供玻璃模糊。
	var middle := HBoxContainer.new()
	middle.size_flags_vertical = SIZE_EXPAND_FILL
	middle.add_theme_constant_override(&"separation", 0)
	root.add_child(middle)

	middle.add_child(_build_sidebar())
	middle.add_child(_build_main_panel())
	# _build_main_panel 内部建好 _tabs 后, 这里把 nav_id → tab index 索引一次性算好。
	_populate_nav_to_tab_index()
	# 抽屉也要躲开浮动顶栏: 包一层 top margin = TOP_BAR_H, 让抽屉头不被顶栏盖住。
	var drawer_wrap := MarginContainer.new()
	drawer_wrap.add_theme_constant_override(&"margin_top", UITheme.TOP_BAR_H)
	drawer_wrap.add_child(_build_drawer_host())
	middle.add_child(drawer_wrap)

	root.add_child(_build_status_bar())

	# 顶栏浮层: 锚到顶部、全宽、高 TOP_BAR_H, 最后 add_child → 画在内容之上;
	# 其玻璃 shader 采样背后内容做模糊。
	var top := _build_top_bar()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 0
	top.offset_top = 0
	top.offset_right = 0
	top.offset_bottom = UITheme.TOP_BAR_H
	add_child(top)
	# top_bar 进 tree 后内部 StatChip._ready 已跑过, get_value_label() 可用。
	_wire_top_bar_compat_labels()

func _wire_top_bar_compat_labels() -> void:
	# 给旧契约 (_turn_label.text / _cash_label.text 等) 接 StatChip 的内部 value
	# Label。必须在 chip 已进 tree、_ready 已跑后调用, 否则拿到 null。
	if _chip_turn != null:
		_turn_label = _chip_turn.get_value_label()
	if _chip_cash != null:
		_cash_label = _chip_cash.get_value_label()
	if _chip_paid_users != null:
		_users_label = _chip_paid_users.get_value_label()

func _build_top_bar() -> Control:
	var panel := Panel.new()
	panel.custom_minimum_size.y = UITheme.TOP_BAR_H
	# 深色玻璃底: panel stylebox 给实底 + 底部 1px 玻璃细边 (兜底/测试契约); 真正的
	# frosted glass (背景模糊 + 半透明 tint + 高光) 由 _make_top_bar_glass 的 shader 画。
	# 内边距全归零让玻璃层全宽铺满 (full-bleed), 内容左右留白改由 bar 内 edge pad 撑。
	var sb := StyleBoxFlat.new()
	sb.bg_color = UITheme.TOPBAR_GLASS_BASE
	sb.border_color = UITheme.TOPBAR_GLASS_BORDER
	sb.border_width_bottom = 1
	sb.content_margin_left = 0
	sb.content_margin_right = 0
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	panel.add_theme_stylebox_override(&"panel", sb)

	# 玻璃层 (纵向暗渐变 + 顶部高光), 最底覆盖子节点, 内容画在它上面。
	panel.add_child(_make_top_bar_glass())

	var bar := HBoxContainer.new()
	bar.anchor_left = 0.0
	bar.anchor_top = 0.0
	bar.anchor_right = 1.0
	bar.anchor_bottom = 1.0
	bar.offset_left = 0.0
	bar.offset_top = 0.0
	bar.offset_right = 0.0
	bar.offset_bottom = 0.0
	bar.add_theme_constant_override(&"separation", UITheme.S_2)
	bar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(bar)

	# 左边距 (panel margins 已归零, 改用 edge pad 控制内容与窗口边的间距)。
	bar.add_child(_make_top_bar_edge_pad())

	# logo / 公司名 (出身系统设计 §3: 顶栏标题用玩家取的公司名)。
	# 文案在 _refresh_company_label() 同步, 规避 _build_ui 早于 GameState 写入的时序。
	var brand := HBoxContainer.new()
	brand.custom_minimum_size = Vector2(168, 0)
	brand.size_flags_vertical = Control.SIZE_EXPAND_FILL
	brand.add_theme_constant_override(&"separation", UITheme.S_2)
	bar.add_child(brand)

	brand.add_child(_make_top_bar_mark())

	var title := Label.new()
	title.add_theme_font_override(&"font", UITheme.get_ui_font_bold())
	title.add_theme_font_size_override(&"font_size", UITheme.FS_MD)
	# 深色玻璃顶栏 → 公司名走 on-dark 浅色。
	title.add_theme_color_override(&"font_color", UITheme.TEXT_ON_DARK)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.clip_text = true
	brand.add_child(title)
	_company_label = title
	_refresh_company_label()

	# 5 个指标 chip (设计 §5): 顶栏走 flat 仪表簇 — 无描边, 靠块间竖线分隔,
	# size-to-content 不裁字 (大额营收不再被截成省略号)。
	_chip_turn       = _make_stat_chip(0.0, true)
	_chip_cash       = _make_stat_chip(0.0, true)
	_chip_cashflow   = _make_stat_chip(0.0, true)
	_chip_paid_users = _make_stat_chip(0.0, true)
	_chip_compute    = _make_stat_chip(0.0, true)
	# 品牌区与指标簇之间也插一条竖线, 形成「标识 │ 仪表带」的分隔。
	bar.add_child(_make_top_bar_divider())
	for chip in [_chip_turn, _chip_cash, _chip_cashflow, _chip_paid_users, _chip_compute]:
		bar.add_child(chip)
		# 末块后面不再加竖线 (后面紧跟弹性 spacer + 操作按钮)。
		if chip != _chip_compute:
			bar.add_child(_make_top_bar_divider())

	# _turn_label / _cash_label / _users_label 在 _wire_top_bar_compat_labels()
	# 里 wire (必须等 chip 进 tree 后)。
	# _models_label 在新顶栏被删除 (§5), 但代码里还会写 .text — 给一个孤儿
	# Label 兜底, 写入不影响渲染。
	_models_label = Label.new()

	var spacer := Control.new()
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	bar.add_child(spacer)

	# 次要操作走幽灵按钮 (透明无边框), 让右侧不再一排描边方框, 主操作单独跳出来。
	_settings_btn = _make_top_bar_button(tr("SETTINGS_TITLE"), _on_open_settings_dialog, &"ghost")
	bar.add_child(_settings_btn)
	_save_btn = _make_top_bar_button(tr("ACTION_SAVE"), _on_open_save_load_dialog, &"ghost")
	bar.add_child(_save_btn)
	_advance_btn = Button.new()
	_advance_btn.text = _advance_button_text()
	_advance_btn.pressed.connect(_on_advance_pressed)
	_apply_top_bar_button_style(_advance_btn, &"primary")
	bar.add_child(_advance_btn)

	bar.add_child(_make_top_bar_edge_pad())   # 右边距

	_top_bar = panel
	return panel

## 顶栏内容与窗口边的留白 (panel content margins 已归零给玻璃层全宽; 这里补回 S_3)。
func _make_top_bar_edge_pad() -> Control:
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(UITheme.S_3, 0)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return pad

## 顶栏指标簇分隔竖线: 1px 渐变细刻线 — 中段 TOPBAR_GLASS_DIVIDER (亮玻璃白),
## 两端淡入透明, 纵向铺满顶栏, 像深色玻璃上的刻度线。
func _make_top_bar_divider() -> Control:
	var d := _TopBarDivider.new()
	d.custom_minimum_size = Vector2(1, 0)
	d.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	d.size_flags_vertical = Control.SIZE_FILL
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return d

## 仪表簇竖刻线: 在 _draw 里铺一张纵向渐变贴图 (1px 宽), 中段实、两端淡出。
## 渐变贴图按 UITheme.TOPBAR_GLASS_DIVIDER 派生, 全部 divider 共用一张 (static 缓存)。
class _TopBarDivider extends Control:
	static var _tex: GradientTexture2D

	func _ready() -> void:
		resized.connect(queue_redraw)

	func _draw() -> void:
		# 居中 1px 竖线, 高度铺满; 渐变在上下两端淡出, 让刻线"悬浮"在仪表带里。
		draw_texture_rect(_get_tex(), Rect2(0.0, 0.0, 1.0, size.y), false)

	static func _get_tex() -> GradientTexture2D:
		if _tex != null:
			return _tex
		var mid: Color = UITheme.TOPBAR_GLASS_DIVIDER
		var clear := Color(mid.r, mid.g, mid.b, 0.0)
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.22, 0.78, 1.0])
		g.colors = PackedColorArray([clear, mid, mid, clear])
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill_from = Vector2(0.0, 0.0)
		t.fill_to = Vector2(0.0, 1.0)   # 纵向渐变
		t.width = 1
		t.height = 64
		_tex = t
		return _tex

## 顶栏深色玻璃覆盖层: 在 _draw 里铺纵向暗渐变 (顶亮底暗的玻璃光泽) + 顶部 1px 白高光。
## 全宽铺满 (panel content margins 已归零); 底部留 1px 不盖, 露出 panel stylebox 的玻璃细边。
## 顶栏 frosted glass: 一张 ColorRect + shader, 采样背后屏幕 (hint_screen_texture)
## 做小半径模糊, 再叠半透明深色 tint (顶亮底暗的玻璃光泽) + 顶部高光 + 底部微暗。
## 因为顶栏是浮层、背后是真实内容, 模糊是真的 (内容往上滚会从玻璃后划过)。
const _TOPBAR_GLASS_SHADER := "shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float blur_px = 6.0;
uniform vec3 tint_top : source_color = vec3(0.16, 0.17, 0.20);
uniform vec3 tint_bottom : source_color = vec3(0.09, 0.10, 0.12);
uniform float tint_alpha = 0.58;
vec3 frost(vec2 uv) {
	vec2 o = (1.0 / vec2(textureSize(screen_tex, 0))) * blur_px;
	vec3 s = texture(screen_tex, uv).rgb * 0.25;
	s += texture(screen_tex, uv + vec2(o.x, 0.0)).rgb * 0.125;
	s += texture(screen_tex, uv + vec2(-o.x, 0.0)).rgb * 0.125;
	s += texture(screen_tex, uv + vec2(0.0, o.y)).rgb * 0.125;
	s += texture(screen_tex, uv + vec2(0.0, -o.y)).rgb * 0.125;
	s += texture(screen_tex, uv + o).rgb * 0.0625;
	s += texture(screen_tex, uv - o).rgb * 0.0625;
	s += texture(screen_tex, uv + vec2(o.x, -o.y)).rgb * 0.0625;
	s += texture(screen_tex, uv + vec2(-o.x, o.y)).rgb * 0.0625;
	return s;
}
void fragment() {
	vec3 backdrop = frost(SCREEN_UV);
	vec3 tint = mix(tint_top, tint_bottom, UV.y);
	vec3 col = mix(backdrop, tint, tint_alpha);
	col += smoothstep(0.22, 0.0, UV.y) * 0.06;   // 顶部受光高光
	col -= smoothstep(0.80, 1.0, UV.y) * 0.05;   // 底部微暗 (玻璃厚度感)
	COLOR = vec4(col, 1.0);
}"

func _make_top_bar_glass() -> Control:
	var rect := ColorRect.new()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.anchor_left = 0.0
	rect.anchor_top = 0.0
	rect.anchor_right = 1.0
	rect.anchor_bottom = 1.0
	rect.offset_left = 0.0
	rect.offset_top = 0.0
	rect.offset_right = 0.0
	rect.offset_bottom = 0.0
	var sh := Shader.new()
	sh.code = _TOPBAR_GLASS_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	rect.material = mat
	return rect

## 推进按钮文案。TOPBAR_ADVANCE 本身已含方向箭头 ("推进回合 →" / "Advance →"),
## 不再额外追加箭头 glyph (否则双箭头)。保留此 helper 集中文案来源 + 随 locale 刷新。
func _advance_button_text() -> String:
	return tr("TOPBAR_ADVANCE")

## 顶栏 28×28 品牌 monogram: 画玩家选的公司标志 (GameState.company_logo);
## 未选 (&"") 时回退到统一的"上升的 A" (与 app 图标 / 起始页标记同源)。
## 几何统一走 UITheme.draw_company_logo, 不在此硬编码。
func _make_top_bar_mark() -> Control:
	var mark := _TopBarMark.new()
	mark.custom_minimum_size = Vector2(28, 28)
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return mark

class _TopBarMark extends Control:
	func _ready() -> void:
		resized.connect(queue_redraw)

	func _draw() -> void:
		UITheme.draw_company_logo(self, Rect2(Vector2.ZERO, size), GameState.company_logo, true)

func _make_top_bar_button(label: String, on_pressed: Callable, kind: StringName) -> Button:
	var b := Button.new()
	b.text = label
	b.pressed.connect(on_pressed)
	_apply_top_bar_button_style(b, kind)
	return b

## 深色玻璃顶栏上的按钮。kind:
##   &"primary" 反白实心 (BG_SURFACE 白底 + 炭黑字), 主 CTA 在暗底上最跳;
##   &"ghost"   透明无框 + on-dark 浅字, hover 浮一层白色低透底 (玻璃压感)。
func _apply_top_bar_button_style(b: Button, kind: StringName) -> void:
	b.custom_minimum_size = Vector2(0, UITheme.BUTTON_H)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_size_override(&"font_size", UITheme.FS_BASE)
	var transparent := Color(0, 0, 0, 0)
	if kind == &"ghost":
		# 幽灵按钮: 静止透明无框, hover/pressed 浮一层白色低透"玻璃压感"底, 浅字。
		var g_hover := Color(1, 1, 1, 0.08)
		var g_pressed := Color(1, 1, 1, 0.14)
		b.add_theme_stylebox_override(&"normal", _make_button_style(transparent, transparent, 0))
		b.add_theme_stylebox_override(&"hover", _make_button_style(g_hover, transparent, 0))
		b.add_theme_stylebox_override(&"pressed", _make_button_style(g_pressed, transparent, 0))
		b.add_theme_stylebox_override(&"hover_pressed", _make_button_style(g_pressed, transparent, 0))
		b.add_theme_stylebox_override(&"focus", _make_button_style(g_hover, transparent, 0))
		b.add_theme_stylebox_override(&"disabled", _make_button_style(transparent, transparent, 0))
		b.add_theme_color_override(&"font_color", UITheme.TEXT_ON_DARK_SECONDARY)
		b.add_theme_color_override(&"font_hover_color", UITheme.TEXT_ON_DARK)
		b.add_theme_color_override(&"font_pressed_color", UITheme.TEXT_ON_DARK)
		b.add_theme_color_override(&"font_hover_pressed_color", UITheme.TEXT_ON_DARK)
		b.add_theme_color_override(&"font_focus_color", UITheme.TEXT_ON_DARK)
		b.add_theme_color_override(&"font_disabled_color", UITheme.TEXT_DISABLED)
		return
	# primary: 反白 — 白底炭黑字, 在暗玻璃上最醒目。白底上 hover/pressed 用 darkened()
	# 派生 (lighten 近白不可见); disabled 回到白色低透玻璃灰。颜色从 token 派生。
	var p_hover: Color = UITheme.BG_SURFACE.darkened(0.06)
	var p_pressed: Color = UITheme.BG_SURFACE.darkened(0.12)
	b.add_theme_stylebox_override(&"normal",
		_make_button_style(UITheme.BG_SURFACE, UITheme.BG_SURFACE))
	b.add_theme_stylebox_override(&"hover",
		_make_button_style(p_hover, p_hover))
	b.add_theme_stylebox_override(&"pressed",
		_make_button_style(p_pressed, p_pressed))
	b.add_theme_stylebox_override(&"hover_pressed",
		_make_button_style(p_pressed, p_pressed))
	b.add_theme_stylebox_override(&"focus",
		_make_button_style(p_hover, UITheme.BG_SURFACE))
	b.add_theme_stylebox_override(&"disabled",
		_make_button_style(Color(1, 1, 1, 0.12), transparent, 0))
	b.add_theme_color_override(&"font_color", UITheme.TEXT_PRIMARY)
	b.add_theme_color_override(&"font_hover_color", UITheme.TEXT_PRIMARY)
	b.add_theme_color_override(&"font_pressed_color", UITheme.TEXT_PRIMARY)
	b.add_theme_color_override(&"font_hover_pressed_color", UITheme.TEXT_PRIMARY)
	b.add_theme_color_override(&"font_focus_color", UITheme.TEXT_PRIMARY)
	b.add_theme_color_override(&"font_disabled_color", UITheme.TEXT_ON_DARK_SECONDARY)

func _make_button_style(bg: Color, border: Color, border_w: int = 1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.border_width_left = border_w
	sb.border_width_top = border_w
	sb.border_width_right = border_w
	sb.border_width_bottom = border_w
	sb.corner_radius_top_left = UITheme.R_SM
	sb.corner_radius_top_right = UITheme.R_SM
	sb.corner_radius_bottom_right = UITheme.R_SM
	sb.corner_radius_bottom_left = UITheme.R_SM
	sb.content_margin_left = UITheme.S_3
	sb.content_margin_right = UITheme.S_3
	sb.content_margin_top = UITheme.S_1
	sb.content_margin_bottom = UITheme.S_1
	return sb

func _make_stat_chip(min_width: float = 104.0, flat: bool = false) -> Control:
	var c: Control = StatChipScene.instantiate()
	if flat:
		c.set_flat(true)
		c.custom_minimum_size = Vector2(min_width, 0.0)
	else:
		c.custom_minimum_size = Vector2(min_width, 36.0)
	return c

func _build_sidebar() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = UITheme.SIDEBAR_W
	var sb := StyleBoxFlat.new()
	sb.bg_color = UITheme.BG_SURFACE
	sb.border_color = UITheme.BORDER_SUBTLE
	sb.border_width_right = 1
	sb.content_margin_left = UITheme.S_2
	sb.content_margin_right = UITheme.S_2
	# 顶栏是浮层: 侧栏背景铺到 y=0 (供玻璃模糊), 但导航项 top inset 到顶栏下方。
	sb.content_margin_top = UITheme.S_3 + UITheme.TOP_BAR_H
	sb.content_margin_bottom = UITheme.S_3
	panel.add_theme_stylebox_override(&"panel", sb)

	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", UITheme.S_3)
	panel.add_child(v)

	_sidebar_items.clear()
	_sidebar_groups.clear()
	for group_cfg in SIDEBAR_NAV:
		var group: Control = SidebarGroupScene.instantiate()
		v.add_child(group)
		_sidebar_groups.append(group)
		group.set_title(tr(String(group_cfg.group_title)))
		for item_cfg in (group_cfg.items as Array):
			var item: Control = SidebarItemScene.instantiate()
			group.add_item(item)
			# set_data 必须在 add_child 之后, item._ready 才跑过。
			item.set_data(
				char(int(item_cfg.icon)),
				tr(String(item_cfg.label)),
				StringName(item_cfg.id),
				-1,
			)
			var nav_id: StringName = StringName(item_cfg.id)
			item.nav_pressed.connect(_on_sidebar_nav_pressed)
			_sidebar_items[nav_id] = item

	# 默认激活 overview。
	_set_active_nav(&"overview")

	_sidebar = panel
	return panel

func _build_main_panel() -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = SIZE_EXPAND_FILL
	panel.size_flags_vertical = SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = UITheme.BG_BASE
	sb.content_margin_left = UITheme.S_4
	sb.content_margin_right = UITheme.S_4
	sb.content_margin_top = UITheme.S_3
	sb.content_margin_bottom = UITheme.S_3
	panel.add_theme_stylebox_override(&"panel", sb)

	panel.add_child(_build_tabs())
	_main_panel = panel
	return panel

func _build_tabs() -> Control:
	_tabs = TabContainer.new()
	_tabs.size_flags_horizontal = SIZE_EXPAND_FILL
	_tabs.size_flags_vertical = SIZE_EXPAND_FILL
	_tabs.tabs_visible = false  # §10 step 4: 侧栏接管导航, tab bar 不再显形
	_tabs.add_child(_make_tab("总览", "_tab_overview"))
	_tabs.add_child(_make_tab("经济", "_tab_economy"))
	_tabs.add_child(_make_tab("招聘", "_tab_hiring"))
	_tabs.add_child(_make_tab("员工", "_tab_staff"))
	_tabs.add_child(_make_tab("基建", "_tab_infra"))
	_tabs.add_child(_make_tab("数据", "_tab_dataset"))
	_tabs.add_child(_make_tab("模型", "_tab_research"))
	_tabs.add_child(_make_tab("科技", "_tab_tech"))
	_tabs.add_child(_make_tab("任务", "_tab_tasks"))
	_tabs.add_child(_make_tab("竞争对手", "_tab_market"))
	_tabs.add_child(_make_tab("产品", "_tab_product"))
	_tabs.add_child(_make_tab("营销", "_tab_marketing"))
	_tabs.add_child(_make_tab("营收", "_tab_revenue"))
	_tabs.add_child(_make_tab("事件", "_tab_event"))
	_tabs.add_child(_make_tab("慈善", "_tab_charity"))
	_tabs.add_child(_make_tab("办公室", "_tab_office"))
	_tabs.add_child(_make_tab("拍卖行", "_tab_auction"))
	_tabs.add_child(_make_tab("帮助", "_tab_help"))
	return _tabs

func _make_tab(title: String, field: String) -> Control:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	# outer 不被 _clear() 清 (refresh 只清 col): 在 col 之上放一个 TOP_BAR_H 高的顶部
	# 占位, 让首屏内容落在浮动玻璃顶栏下方; 往下滚时内容会从顶栏背后划过 → 玻璃模糊。
	var outer := VBoxContainer.new()
	outer.size_flags_horizontal = SIZE_EXPAND_FILL
	outer.add_theme_constant_override(&"separation", 0)
	scroll.add_child(outer)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(0, UITheme.TOP_BAR_H)
	outer.add_child(pad)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = SIZE_EXPAND_FILL
	col.add_theme_constant_override(&"separation", 8)
	outer.add_child(col)
	set(field, col)
	return scroll

func _build_drawer_host() -> Control:
	_drawer_host = DrawerScene.instantiate()
	# secondary 默认走 取消 语义, 自动关抽屉; primary 由各业务处自己监听。
	_drawer_host.secondary_pressed.connect(func(_id): _drawer_host.close())
	return _drawer_host

func _build_status_bar() -> Control:
	_status_label = Label.new()
	_status_label.size_flags_horizontal = SIZE_EXPAND_FILL
	_status_label.add_theme_color_override(&"font_color", UITheme.TEXT_SECONDARY)
	return _status_label

# ---- sidebar nav --------------------------------------------------------

func _on_sidebar_nav_pressed(nav_id: StringName) -> void:
	_set_active_nav(nav_id)
	if _tabs == null or not _nav_to_tab_index.has(nav_id):
		return
	_tabs.current_tab = int(_nav_to_tab_index[nav_id])

func _switch_to_pending_events(reason: StringName) -> bool:
	if GameState.pending_events.is_empty():
		return false
	Log.info(&"ui", "switch_to_pending_events",
			{reason = reason, count = GameState.pending_events.size()})
	_on_sidebar_nav_pressed(&"events")
	return true

func _set_active_nav(nav_id: StringName) -> void:
	_active_nav = nav_id
	for id in _sidebar_items.keys():
		var item: Control = _sidebar_items[id]
		if item != null and item.has_method(&"set_active"):
			item.set_active(id == nav_id)

# §10 step 7 (硬编码清理): build 时把 nav_id 映射到 TabContainer 索引,
# 避免点导航时跑字符串查找。SIDEBAR_NAV 的 "tab" 字段做中转 — 用 tab title
# 比对 _tabs.get_tab_title(i)。
func _populate_nav_to_tab_index() -> void:
	_nav_to_tab_index.clear()
	if _tabs == null:
		return
	for group_cfg in SIDEBAR_NAV:
		for item_cfg in (group_cfg.items as Array):
			var title := String(item_cfg.tab)
			for i in range(_tabs.get_tab_count()):
				if _tabs.get_tab_title(i) == title:
					_nav_to_tab_index[StringName(item_cfg.id)] = i
					break

# ---- refresh dispatcher -------------------------------------------------

func _request_refresh() -> void:
	if TurnManager.is_advancing():
		_refresh_pending = true
		return
	_refresh()

func _on_turn_resolved(_turn: int) -> void:
	if _refresh_pending:
		_refresh_pending = false
	_refresh()

## 语言切换: 重设侧栏导航文案 + 重渲染全部 tab + 顶栏。view 都是 "pull" 模型、
## refresh() 整段重建, 重渲染即拿到新 locale 下的 tr(...)。tab 标题节点名隐藏
## (tabs_visible=false), 不必刷。Per 国际化设计 §11.2。
func _on_locale_changed() -> void:
	_refresh_nav_labels()
	_refresh()

## 语言切换后重设侧栏组标题 + 每项 label。set_data 的 badge 传 -1, 随后由
## _refresh() → _refresh_sidebar_badges() 还原事件徽章。
func _refresh_nav_labels() -> void:
	for gi in range(SIDEBAR_NAV.size()):
		var group_cfg: Dictionary = SIDEBAR_NAV[gi]
		if gi < _sidebar_groups.size() and _sidebar_groups[gi] != null:
			_sidebar_groups[gi].set_title(tr(String(group_cfg.group_title)))
		for item_cfg in (group_cfg.items as Array):
			var nav_id := StringName(item_cfg.id)
			if _sidebar_items.has(nav_id):
				_sidebar_items[nav_id].set_data(
					char(int(item_cfg.icon)),
					tr(String(item_cfg.label)),
					nav_id,
					-1,
				)

func _refresh() -> void:
	_refresh_count_for_test += 1
	_refresh_top_bar()
	_refresh_sidebar_badges()
	_render_overview_tab()
	_render_economy_tab()
	_render_hiring_tab()
	_render_staff_tab()
	_render_infra_tab()
	_render_dataset_tab()
	_render_research_tab()
	_render_tech_tab()
	_render_tasks_tab()
	_render_market_tab()
	_render_product_tab()
	_render_marketing_tab()
	_render_revenue_tab()
	_render_event_tab()
	_render_charity_tab()
	_render_office_tab()
	_render_auction_tab()
	_render_help_tab()

func _ensure_player_scientist_joined() -> void:
	for l in GameState.leads:
		if l.is_player_scientist:
			return
	var display_name: String = GameState.player_name.strip_edges()
	if display_name == "":
		display_name = "创始人"
	var payload: Dictionary = {display_name = display_name}
	if GameState.founder_avatar != &"":
		payload.avatar_id = GameState.founder_avatar
	var r: Dictionary = CommandBus.send(&"hiring.create_player_scientist", payload)
	if not bool(r.get(&"ok", false)):
		Log.warn(&"hiring", "auto_player_scientist_failed",
				{error = r.get(&"error", &"unknown")})

# ---- top bar refresh ----------------------------------------------------

## 顶栏公司名 = 玩家在新游戏取的名字; 未取名 (旧档 / 默认局) 回退 "Scaling Up"。
func _refresh_company_label() -> void:
	if _company_label == null:
		return
	_company_label.text = GameState.company_name if GameState.company_name != "" else "Scaling Up"

## 侧栏 badge: 事件项显示待处理事件数, 任务项显示进行中任务数, 让玩家不开对应
## tab 也知道「有事件发生 / 有任务在跑」。
func _refresh_sidebar_badges() -> void:
	if _sidebar_items.has(&"events"):
		_sidebar_items[&"events"].set_badge(GameState.pending_events.size())
	if _sidebar_items.has(&"tasks"):
		_sidebar_items[&"tasks"].set_badge(GameState.active_tasks.size())

## 「推进回合」按钮: pending 事件未处理完时门禁拦截 (事件系统设计.md §2)。
func _on_advance_pressed() -> void:
	if not TurnManager.can_advance():
		Log.info(&"turn", "advance_blocked_pending_events",
				{count = GameState.pending_events.size()})
		_switch_to_pending_events(&"advance_blocked")
		return
	TurnManager.advance()
	_switch_to_pending_events(&"advance_completed")

func _refresh_top_bar() -> void:
	_refresh_company_label()
	if _advance_btn != null:
		# 文案随 locale 刷新 (语言切换走 _refresh → 此处)。
		_advance_btn.text = _advance_button_text()
		# pending 事件未处理完 → 禁用推进, 必须先做完选择。
		_advance_btn.disabled = not TurnManager.can_advance()
	if _save_btn != null:
		_save_btn.text = tr("ACTION_SAVE")
	if _settings_btn != null:
		_settings_btn.text = tr("SETTINGS_TITLE")
	# StatChip.set_data(label, value, delta, delta_text)
	if _chip_turn != null:
		_chip_turn.set_data(tr("TOPBAR_TURN"), TurnManager.turn_label(), NAN, "")
	if _chip_cash != null:
		# 顶栏防溢出: 走 compact (≥100万缩 1.2M/3.4B); 保留 "$-" 前缀供 chip 负值染红。
		_chip_cash.set_data(tr("TOPBAR_CASH"), "$%s" % UITheme.format_money_compact(GameState.cash), NAN, "")
	if _chip_cashflow != null:
		# 周净流: 优先读 GameState.weekly_ledger (本周已发生的 gross_in - gross_out)。
		# 没账本时退到"本周现金 - 上周现金" delta; 仍没有基线就显示 "—" 而不是空白。
		var value_text: String = _weekly_net_flow_value_text()
		var delta: float = NAN
		var delta_text := ""
		var cur_turn: int = GameState.turn
		if _last_turn_for_delta >= 0 and cur_turn > _last_turn_for_delta:
			delta = float(GameState.cash - _last_turn_cash)
			var sign_str := "+" if delta >= 0 else ""
			delta_text = "%s$%s" % [sign_str, UITheme.format_money_compact(int(delta))]
		_chip_cashflow.set_data(tr("TOPBAR_NET_CASHFLOW"), value_text, delta, delta_text)
		_last_turn_cash = GameState.cash
		_last_turn_for_delta = cur_turn
	if _chip_paid_users != null:
		_chip_paid_users.set_data(tr("TOPBAR_PAID_USERS"), UITheme.format_money_compact(GameState.paid_users), NAN, "")
	if _chip_compute != null:
		_chip_compute.set_data(tr("TOPBAR_COMPUTE"), _total_compute_label(), NAN, "")

## 顶栏「周净流」显示真实财务账本净额。
## 进行中的一周读 weekly_ledger; resolve 后 weekly_ledger 会清零, 此时读
## ledger_history[0] 的刚完成周快照。都不可用才退到 cash delta / "—"。
func _weekly_net_flow_value_text() -> String:
	var ledger: Dictionary = GameState.weekly_ledger if GameState.weekly_ledger is Dictionary else {}
	if _ledger_has_activity(ledger):
		return _format_ledger_net_flow(ledger)
	var history: Array = GameState.ledger_history if GameState.ledger_history is Array else []
	if not history.is_empty() and history[0] is Dictionary:
		var last_completed: Dictionary = history[0]
		if _ledger_has_activity(last_completed) or _ledger_has_gross_key(last_completed):
			return _format_ledger_net_flow(last_completed)
	if _last_turn_for_delta >= 0:
		var delta: int = GameState.cash - _last_turn_cash
		var sign_str2: String = "+" if delta >= 0 else "-"
		return "%s$%s" % [sign_str2, UITheme.format_money_compact(absi(delta))]
	return "—"

func _ledger_has_activity(ledger: Dictionary) -> bool:
	return _ledger_int(ledger, &"gross_in") != 0 or _ledger_int(ledger, &"gross_out") != 0

func _ledger_has_gross_key(ledger: Dictionary) -> bool:
	return ledger.has(&"gross_in") or ledger.has("gross_in") \
			or ledger.has(&"gross_out") or ledger.has("gross_out")

func _ledger_int(ledger: Dictionary, key: StringName) -> int:
	if ledger.has(key):
		return int(ledger.get(key, 0))
	var text_key := String(key)
	return int(ledger.get(text_key, 0))

func _format_ledger_net_flow(ledger: Dictionary) -> String:
	var net: int = _ledger_int(ledger, &"gross_in") - _ledger_int(ledger, &"gross_out")
	var sign_str: String = "+" if net >= 0 else "-"
	# compact: <100万精确 (账本 +$38,000 等仍逐字符), ≥100万缩 1.2M/3.4B 防溢出。
	return "%s$%s" % [sign_str, UITheme.format_money_compact(absi(net))]

func _total_compute_label() -> String:
	# 顶栏「算力」走 MonetizationSystem.total_effective_serving_tps —— 把
	# arch.inference_coef + chief_engineer lead 加成包进去, 与算力池每行的
	# t/s 之和对齐。见 design/营收系统设计.md §3.1 (capacity 单一来源)。
	return UITheme.format_tps(MonetizationSystem.total_effective_serving_tps())

# ---- introspection (集成测试用) -------------------------------------------

func get_top_bar_chip_count() -> int:
	var n := 0
	for chip in [_chip_turn, _chip_cash, _chip_cashflow, _chip_paid_users, _chip_compute]:
		if chip != null:
			n += 1
	return n

func reset_refresh_count_for_test() -> void:
	_refresh_count_for_test = 0

func get_refresh_count_for_test() -> int:
	return _refresh_count_for_test

func get_sidebar_group_count() -> int:
	return SIDEBAR_NAV.size()

func get_sidebar_item_count() -> int:
	return _sidebar_items.size()

func get_sidebar_group_titles() -> Array:
	var out: Array = []
	for group in _sidebar_groups:
		if group != null and group.has_method(&"get_title_text"):
			out.append(group.get_title_text())
	return out

func sidebar_panel_bg_color_for_test() -> Color:
	if _sidebar == null:
		return Color.MAGENTA
	var sb := _sidebar.get_theme_stylebox(&"panel")
	if sb is StyleBoxFlat:
		return (sb as StyleBoxFlat).bg_color
	return Color.MAGENTA

func sidebar_panel_right_border_for_test() -> int:
	if _sidebar == null:
		return -1
	var sb := _sidebar.get_theme_stylebox(&"panel")
	if sb is StyleBoxFlat:
		return (sb as StyleBoxFlat).border_width_right
	return -1

func has_sidebar_item(nav_id: StringName) -> bool:
	return _sidebar_items.has(nav_id)

func click_sidebar_for_test(nav_id: StringName) -> void:
	if _sidebar_items.has(nav_id):
		_on_sidebar_nav_pressed(nav_id)

func is_sidebar_item_active(nav_id: StringName) -> bool:
	if not _sidebar_items.has(nav_id):
		return false
	var item: Control = _sidebar_items[nav_id]
	if item != null and item.has_method(&"is_active"):
		return item.is_active()
	return false

func sidebar_icon_tile_bg_for_test(nav_id: StringName) -> Color:
	if not _sidebar_items.has(nav_id):
		return Color.MAGENTA
	var item: Control = _sidebar_items[nav_id]
	if item != null and item.has_method(&"get_icon_tile_bg_color"):
		return item.get_icon_tile_bg_color()
	return Color.MAGENTA

func sidebar_icon_color_for_test(nav_id: StringName) -> Color:
	if not _sidebar_items.has(nav_id):
		return Color.MAGENTA
	var item: Control = _sidebar_items[nav_id]
	if item != null and item.has_method(&"get_icon_color"):
		return item.get_icon_color()
	return Color.MAGENTA

## 测试 introspection: 某侧栏项当前 badge 文本 ("" = 无 badge)。
func sidebar_badge_text_for_test(nav_id: StringName) -> String:
	if not _sidebar_items.has(nav_id):
		return ""
	var item: Control = _sidebar_items[nav_id]
	if item != null and item.has_method(&"get_badge_text"):
		return item.get_badge_text()
	return ""

# ---- overview tab -------------------------------------------------------

func _render_overview_tab() -> void:
	_clear(_tab_overview)
	_tab_overview.add_child(_make_section(tr("SECTION_OVERVIEW_COMPANY")))
	var kpis := HBoxContainer.new()
	kpis.add_theme_constant_override(&"separation", UITheme.S_3)
	kpis.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_tab_overview.add_child(kpis)
	_add_stat_chip(kpis, tr("TOPBAR_TURN"), TurnManager.turn_label())
	_add_stat_chip(kpis, tr("TOPBAR_CASH"), "$%s" % _format_money(GameState.cash))
	_add_stat_chip(kpis, tr("TOPBAR_PAID_USERS"), _format_money(GameState.paid_users))

	# U-1: "下一步" 引导. 扫几个常见瓶颈, 给玩家一条最高优先级的提示。
	# 新手不知下一步该干啥时, 这条比纯资产清单有用得多。
	_tab_overview.add_child(_make_section(tr("SECTION_OVERVIEW_NEXT_STEPS")))
	var hints_panel := _make_surface_panel(&"overview_next_steps_panel")
	hints_panel.custom_minimum_size.x = float(UITheme.LIST_MAX_W)
	var hints_col := VBoxContainer.new()
	hints_col.add_theme_constant_override(&"separation", UITheme.S_2)
	hints_panel.add_child(hints_col)
	for hint_text in _build_next_step_hints():
		hints_col.add_child(_make_hint_row(hint_text))
	_tab_overview.add_child(hints_panel)

	_tab_overview.add_child(_make_section(tr("SECTION_OVERVIEW_ASSETS")))
	_tab_overview.add_child(_make_key_value_table([
		{label = tr("OV_ASSET_TEAM"), value = tr("OV_LEADS") % [
			GameState.leads.size(), GameState.lead_pool.size(),
			_sum_dict(GameState.staff_pool), _sum_dict(GameState.staff_busy)]},
		{label = tr("OV_ASSET_INFRA"), value = tr("OV_DC") % [
			GameState.datacenters.size(), GameState.construction_queue.size()]},
		{label = tr("OV_ASSET_RESEARCH"), value = tr("OV_DS_MODELS") % [
			GameState.datasets.size(), GameState.models.size(), _published_count()]},
		{label = tr("OV_ASSET_MARKET"), value = tr("OV_PROD") % [
			GameState.products.size(), GameState.campaigns.size(), GameState.loans.size()]},
		{label = tr("OV_ASSET_FLOW"), value = tr("OV_TASKS_EVENTS") % [
			GameState.active_tasks.size(), GameState.pending_events.size()]},
	], &"overview_assets_table"))

# U-1: 按优先级返回最多 3 条"下一步"提示。空数组 → 给"运营顺畅"的默认信息。
# 优先级: 待处理事件 > 算力不足 > 无产品 > 无 published 模型 > 无 DC > 无 lead > 默认。
func _build_next_step_hints() -> Array:
	var hints: Array = []
	# 最高优先: 资金为负。必须排在一切正向提示之前, 且让 hints 非空 —— 这样永远
	# 不会落到"运营顺畅"。连续为负跨过预警阈值 (§4.2) 时升级为"本局将结束"。
	if GameState.cash < 0:
		if GameState.bankruptcy_streak >= EconomySystem.BANKRUPTCY_WARN_STREAK:
			hints.append(tr("OV_HINT_BANKRUPTCY_CRITICAL") % [
				GameState.bankruptcy_streak, EconomySystem.BANKRUPTCY_STREAK_LIMIT])
		else:
			hints.append(tr("OV_HINT_CASH_NEGATIVE"))
	if GameState.pending_events.size() > 0:
		hints.append(tr("OV_HINT_EVENTS") % \
				GameState.pending_events.size())
	# 算力警示: 任何 published 模型的 sub demand > capacity 即提示。
	if _any_model_capacity_short():
		hints.append(tr("OV_HINT_COMPUTE"))
	if GameState.products.is_empty() and _published_count() > 0:
		hints.append(tr("OV_HINT_NO_PRODUCT"))
	if _published_count() == 0 and not GameState.models.is_empty():
		hints.append(tr("OV_HINT_UNPUBLISHED"))
	if GameState.datacenters.is_empty() and GameState.construction_queue.is_empty():
		hints.append(tr("OV_HINT_NO_DC"))
	if GameState.leads.is_empty():
		hints.append(tr("OV_HINT_NO_LEAD"))
	if hints.is_empty():
		hints.append(tr("OV_HINT_SMOOTH"))
	return hints.slice(0, 3)

func _any_model_capacity_short() -> bool:
	for m in GameState.models:
		if m.status != &"published":
			continue
		var capacity: int = _capacity_for_model(m)
		var demand: int = int(GameState.token_demand.get(m.id, 0))
		if capacity > 0 and demand > capacity:
			return true
		if capacity == 0 and demand > 0:
			return true
	return false

# ---- economy tab --------------------------------------------------------
# 经济 tab v2 (2026-05): 顶部 cash/debt/equity 汇总, 然后:
#   1. 融资 (8 轮顺序卡片, 玩家自发触发)
#   2. 贷款 (信用面板 + 申请按钮 + 当前贷款列表)
#   3. 财务报表 (上周收支明细 + 最近 12 周表格)

func _render_economy_tab() -> void:
	_clear(_tab_economy)
	_render_economy_summary()
	_tab_economy.add_child(_make_section(tr("SECTION_ECONOMY_FUNDING")))
	_render_funding_rounds()
	_tab_economy.add_child(_make_section(tr("SECTION_ECONOMY_LOANS")))
	_render_loans_section()
	_tab_economy.add_child(_make_section(tr("SECTION_ECONOMY_LAST_WEEK")))
	_render_last_week_ledger()
	_tab_economy.add_child(_make_section(tr("SECTION_ECONOMY_FINANCE_12W")))
	_render_ledger_history()

func _render_economy_summary() -> void:
	_tab_economy.add_child(_make_section(tr("SECTION_ECONOMY_CASH_DEBT_EQUITY")))
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", UITheme.S_3)
	row.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_tab_economy.add_child(row)
	_add_stat_chip(row, tr("TOPBAR_CASH"), "$%s" % _format_money(GameState.cash))
	_add_stat_chip(row, tr("ECO_KPI_DEBT"), "$%s" % _format_money(GameState.debt),
		tr("ECO_KPI_LOANS") % GameState.loans.size())
	_add_stat_chip(row, tr("ECO_KPI_FOUNDER_EQUITY"),
		"%.1f%%" % (float(GameState.equity.founder) * 100.0),
		tr("ECO_KPI_INVESTORS") % (float(GameState.equity.investors) * 100.0))
	_add_stat_chip(row, tr("ECO_KPI_BANKRUPTCY"),
		"%d / %d" % [GameState.bankruptcy_streak, EconomySystem.BANKRUPTCY_STREAK_LIMIT])

func _render_funding_rounds() -> void:
	var preview: Dictionary = CommandBus.send(&"economy.preview_funding_rounds", {})
	if not preview.get(&"ok", false):
		_tab_economy.add_child(_dim_label(tr("ECO_FUNDING_LOAD_FAILED")))
		return
	for entry in preview.rounds:
		_tab_economy.add_child(_make_funding_round_row(entry))

func _make_funding_round_row(entry: Dictionary) -> Control:
	# 看板行收口到 LIST_MAX_W 并左对齐, 不随窗口铺满整屏 (见 design §9)。
	var box := PanelContainer.new()
	box.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	box.custom_minimum_size.x = float(UITheme.LIST_MAX_W)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 12)
	box.add_child(row)
	var status: StringName = entry.status
	var name_lbl := Label.new()
	name_lbl.text = tr(String(entry.display_name))
	name_lbl.add_theme_font_size_override(&"font_size", 15)
	name_lbl.custom_minimum_size = Vector2(120, 0)
	row.add_child(name_lbl)
	var detail := Label.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.text = tr("ECO_FUNDING_DETAIL") % [
		_format_money(int(entry.amount_min)), _format_money(int(entry.amount_max)),
		float(entry.dilution_min) * 100.0, float(entry.dilution_max) * 100.0,
		tr(String(entry.unlock_summary))]
	row.add_child(detail)
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(120, 0)
	match status:
		&"accepted":
			btn.text = tr("BTN_FUNDING_DONE")
			btn.disabled = true
			name_lbl.modulate = Color(0.55, 0.85, 0.55)
		&"available":
			btn.text = tr("BTN_FUNDING_ACCEPT")
			var round_id: StringName = entry.round
			btn.pressed.connect(func(): _open_funding_dialog(round_id))
		_:  # locked
			btn.text = tr("BTN_FUNDING_LOCKED")
			btn.disabled = true
			detail.modulate = Color(0.7, 0.7, 0.7)
	row.add_child(btn)
	return box

func _open_funding_dialog(round_id: StringName) -> void:
	var dlg: FundingDialog = FundingDialog.new()
	add_child(dlg)
	dlg.funding_accepted.connect(func(_r, _a, _d):
		_set_status(tr("ECO_FUNDING_DONE") % String(_r)))
	dlg.confirmed.connect(func(): dlg.queue_free())
	dlg.canceled.connect(func(): dlg.queue_free())
	dlg.close_requested.connect(func(): dlg.queue_free())
	dlg.open_for_round(round_id)

func _render_loans_section() -> void:
	var preview: Dictionary = CommandBus.send(&"economy.preview_credit", {})
	_tab_economy.add_child(_label(tr("ECO_CREDIT") % [
		String(preview.rating), _format_money(int(preview.max_loan)),
		float(preview.rate) * 100.0]))
	var apply_btn := Button.new()
	apply_btn.text = tr("BTN_APPLY_LOAN")
	# 收紧到内容宽并左对齐, 否则按钮占满整屏宽 (见 design §9)。
	apply_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	apply_btn.disabled = int(preview.get(&"max_loan", 0)) <= 0
	apply_btn.pressed.connect(_open_loan_dialog)
	_tab_economy.add_child(apply_btn)
	if GameState.loans.is_empty():
		_tab_economy.add_child(_dim_label(tr("ECO_NO_LOANS")))
		return
	for loan in GameState.loans:
		_tab_economy.add_child(_make_loan_row(loan))

func _open_loan_dialog() -> void:
	var dlg: LoanDialog = LoanDialog.new()
	add_child(dlg)
	dlg.loan_taken.connect(func(_id): _set_status(tr("ECO_LOAN_OK") % String(_id)))
	dlg.confirmed.connect(func(): dlg.queue_free())
	dlg.canceled.connect(func(): dlg.queue_free())
	dlg.close_requested.connect(func(): dlg.queue_free())
	dlg.refresh()
	dlg.popup_centered()

func _make_loan_row(loan) -> Control:
	# 看板行收口到 LIST_MAX_W 并左对齐 (见 design §9)。
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)
	row.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	row.custom_minimum_size.x = float(UITheme.LIST_MAX_W)
	var info := Label.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.text = tr("ECO_LOAN_ROW") % [
		String(loan.id), _format_money(loan.principal_remaining),
		loan.weeks_remaining, loan.weekly_interest_rate * 100.0]
	row.add_child(info)
	var loan_id: StringName = loan.id
	var remaining: int = loan.principal_remaining
	var pay_full := Button.new()
	pay_full.text = tr("BTN_REPAY_FULL") % _format_money(remaining)
	pay_full.disabled = remaining <= 0 or GameState.cash < remaining
	pay_full.pressed.connect(func():
		_call(&"economy.repay_loan",
				{loan_id = loan_id, amount = remaining}, tr("ECO_REPAY")))
	row.add_child(pay_full)
	return row

func _render_last_week_ledger() -> void:
	var ledger: Dictionary = _last_completed_ledger()
	if ledger.is_empty():
		_tab_economy.add_child(_dim_label(tr("ECO_NO_LAST_WEEK")))
		return
	var income: Dictionary = _ledger_dict(ledger, &"income")
	var expense: Dictionary = _ledger_dict(ledger, &"expense")
	_tab_economy.add_child(_dim_label(tr("WEEK_N") % _ledger_int(ledger, &"turn")))
	if income.is_empty() and expense.is_empty() and not _ledger_has_activity(ledger):
		_tab_economy.add_child(_dim_label(tr("ECO_NO_IO")))
		return
	var tables := HBoxContainer.new()
	tables.add_theme_constant_override(&"separation", UITheme.S_3)
	tables.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	tables.add_child(_make_ledger_detail_table(
		tr("ECO_INCOME"), income, true, _ledger_int(ledger, &"gross_in"),
		&"last_week_income_table"))
	tables.add_child(_make_ledger_detail_table(
		tr("ECO_EXPENSE"), expense, false, _ledger_int(ledger, &"gross_out"),
		&"last_week_expense_table"))
	_tab_economy.add_child(tables)
	var net: int = _ledger_int(ledger, &"gross_in") - _ledger_int(ledger, &"gross_out")
	var net_lbl := _label(tr("ECO_NET_FLOW") % [
		"+" if net >= 0 else "-", _format_money(absi(net))])
	net_lbl.add_theme_color_override(&"font_color",
			UITheme.ACCENT_PRIMARY if net >= 0 else UITheme.ACCENT_DANGER)
	net_lbl.add_theme_font_override(&"font", UITheme.get_ui_font_bold())
	_tab_economy.add_child(net_lbl)

func _last_completed_ledger() -> Dictionary:
	var history: Array = GameState.ledger_history if GameState.ledger_history is Array else []
	if history.is_empty():
		return {}
	var first = history[0]
	if first is Dictionary:
		return first
	return {}

func _ledger_dict(ledger: Dictionary, key: StringName) -> Dictionary:
	var value = null
	if ledger.has(key):
		value = ledger.get(key)
	else:
		value = ledger.get(String(key), null)
	if value is Dictionary:
		return value
	return {}

func _sorted_ledger_category_keys(entries: Dictionary) -> Array:
	var out: Array = []
	for key in entries.keys():
		out.append(String(key))
	out.sort()
	return out

func _ledger_category_amount(entries: Dictionary, key_text: String) -> int:
	if entries.has(key_text):
		return int(entries.get(key_text, 0))
	var key_name := StringName(key_text)
	return int(entries.get(key_name, 0))

func _render_ledger_history() -> void:
	var history: Array = GameState.ledger_history
	if history.is_empty():
		_tab_economy.add_child(_dim_label(tr("ECO_NO_HISTORY")))
		return
	var panel := _make_surface_panel(&"ledger_history_table")
	panel.custom_minimum_size.x = float(UITheme.LIST_MAX_W)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override(&"h_separation", UITheme.S_4)
	grid.add_theme_constant_override(&"v_separation", UITheme.S_1)
	for header in [tr("ECO_COL_WEEK"), tr("ECO_COL_INCOME"), tr("ECO_COL_EXPENSE"), tr("ECO_COL_NET"), tr("ECO_COL_CASH")]:
		grid.add_child(_table_cell(header, 112.0, HORIZONTAL_ALIGNMENT_RIGHT,
			UITheme.TEXT_SECONDARY, true))
	for entry in history:
		var t: int = int(entry.get(&"turn", 0))
		var gin: int = int(entry.get(&"gross_in", 0))
		var gout: int = int(entry.get(&"gross_out", 0))
		var net: int = gin - gout
		var ec: int = int(entry.get(&"ending_cash", 0))
		grid.add_child(_table_cell(tr("WEEK_N") % t, 112.0, HORIZONTAL_ALIGNMENT_RIGHT))
		grid.add_child(_table_cell("+$%s" % _format_money(gin), 112.0,
			HORIZONTAL_ALIGNMENT_RIGHT, UITheme.ACCENT_PRIMARY))
		grid.add_child(_table_cell("-$%s" % _format_money(gout), 112.0,
			HORIZONTAL_ALIGNMENT_RIGHT, UITheme.ACCENT_DANGER))
		grid.add_child(_table_cell("%s$%s" % [
			"+" if net >= 0 else "-", _format_money(absi(net))],
			112.0, HORIZONTAL_ALIGNMENT_RIGHT,
			UITheme.ACCENT_PRIMARY if net >= 0 else UITheme.ACCENT_DANGER, true))
		grid.add_child(_table_cell("$%s" % _format_money(ec), 112.0,
			HORIZONTAL_ALIGNMENT_RIGHT))
	panel.add_child(grid)
	_tab_economy.add_child(panel)

# ---- hiring tab ---------------------------------------------------------

## Specialty → 所属系统 (中文短标签) 显示分组。Per design/招聘系统设计.md §5.1.
# 值为 i18n key (const 不能调 tr); _specialty_label() 翻成当前 locale。
const _SPECIALTY_GROUP: Dictionary = {
	&"chief_scientist":  "SPEC_GROUP_CHIEF_SCIENTIST",
	&"ml_research_lead": "SPEC_GROUP_ML_RESEARCH_LEAD",
	&"eval_lead":        "SPEC_GROUP_EVAL_LEAD",
	&"chief_engineer":   "SPEC_GROUP_CHIEF_ENGINEER",
	&"data_scientist":   "SPEC_GROUP_DATA_SCIENTIST",
	&"marketing_lead":   "SPEC_GROUP_MARKETING_LEAD",
	&"founder":          "SPEC_GROUP_FOUNDER",
}

## Specialty 展示名 (值为 i18n key)。
const _SPECIALTY_CN: Dictionary = {
	&"chief_scientist":  "SPEC_NAME_CHIEF_SCIENTIST",
	&"ml_research_lead": "SPEC_NAME_ML_RESEARCH_LEAD",
	&"eval_lead":        "SPEC_NAME_EVAL_LEAD",
	&"chief_engineer":   "SPEC_NAME_CHIEF_ENGINEER",
	&"data_scientist":   "SPEC_NAME_DATA_SCIENTIST",
	&"marketing_lead":   "SPEC_NAME_MARKETING_LEAD",
	&"founder":          "LEAD_FOUNDER",
}

## 普通员工职能 (GameState.STAFF_ROLES) → 展示名 i18n key。
# 值为 i18n key (const 不能调 tr); _staff_role_label() 翻成当前 locale。
# 修复前员工 tab "员工 (按职能)" 直接显示枚举名 (ml_eng / infra_eng …), 未翻译。
const _STAFF_ROLE_NAME: Dictionary = {
	&"ml_eng":     "STAFF_ROLE_ML_ENG",
	&"infra_eng":  "STAFF_ROLE_INFRA_ENG",
	&"data_eng":   "STAFF_ROLE_DATA_ENG",
	&"marketing":  "STAFF_ROLE_MARKETING",
	&"ops":        "STAFF_ROLE_OPS",
}

## bonus key 的中文标签 + 是否按 ability 百分比展示。Per 招聘系统设计 §1.1.
##   类型 "speed": 显示 +X% (减少工期)
##   类型 "score": 显示 +X% (加分)
##   类型 "raw_add": 显示 +abs_value (不乘 ability)
# label 为 i18n key (const 不能调 tr); _format_lead_bonuses() 翻。
const _BONUS_INFO: Dictionary = {
	&"pretrain_speed":         {label = "BONUS_PRETRAIN_SPEED",        kind = "speed"},
	&"pretrain_score_bonus":   {label = "BONUS_PRETRAIN_SCORE",        kind = "score"},
	&"posttrain_speed":        {label = "BONUS_POSTTRAIN_SPEED",       kind = "speed"},
	&"posttrain_score_bonus":  {label = "BONUS_POSTTRAIN_SCORE",       kind = "score"},
	&"evaluate_speed":         {label = "BONUS_EVALUATE_SPEED",        kind = "speed"},
	&"evaluate_score_bonus":   {label = "BONUS_EVALUATE_SCORE",        kind = "score"},
	&"research_speed":         {label = "BONUS_RESEARCH_SPEED",        kind = "speed"},
	&"data_collection_speed":  {label = "BONUS_DATA_COLLECTION_SPEED", kind = "speed"},
	&"data_quality_add":       {label = "BONUS_DATA_QUALITY",          kind = "score"},
	&"cluster_eff_add":        {label = "BONUS_CLUSTER_EFF",           kind = "raw_add"},
	&"product_throughput":     {label = "BONUS_PRODUCT_THROUGHPUT",    kind = "speed"},
	&"campaign_efficiency":    {label = "BONUS_CAMPAIGN_EFFICIENCY",   kind = "speed"},
}

func _specialty_label(spec: StringName) -> String:
	var cn: String = tr(_SPECIALTY_CN.get(spec, String(spec)))
	var group_key: String = _SPECIALTY_GROUP.get(spec, "")
	if group_key == "":
		return cn
	return "%s · %s" % [cn, tr(group_key)]

func _staff_role_label(role: StringName) -> String:
	return tr(_STAFF_ROLE_NAME.get(role, String(role)))

## 给一位 lead 算出按当前 ability 计算的 bonus 列表字符串。Per 招聘系统设计 §5.1.
func _format_lead_bonuses(lead) -> String:
	var table: Dictionary = HiringSystem.LEAD_BONUS_TABLE.get(lead.specialty, {})
	if table.is_empty():
		return tr("LEAD_NO_BONUS")
	var parts: Array = []
	var ability_ratio: float = float(lead.ability) / 100.0
	for key in table.keys():
		var coef: float = float(table[key])
		var info: Dictionary = _BONUS_INFO.get(key, {label = String(key), kind = "score"})
		var label: String = tr(info.get(&"label", String(key)))
		match String(info.get(&"kind", "score")):
			"raw_add":
				parts.append("%s +%.2f" % [label, coef])
			_:
				var pct: int = int(round(ability_ratio * coef * 100.0))
				parts.append("%s +%d%%" % [label, pct])
	return ", ".join(parts)

func _render_hiring_tab() -> void:
	# 招聘 tab — HiringView 只管「招新」: 候选 Lead 池。
	# view 单实例, 第一次进来时 instantiate; 之后只调 refresh()。
	if _hiring_view == null:
		_clear(_tab_hiring)
		_hiring_view = HiringViewScene.instantiate()
		_tab_hiring.add_child(_hiring_view)
		_hiring_view.lead_action.connect(_on_hiring_lead_action)
	_hiring_view.refresh(_build_hiring_view_data())

func _render_staff_tab() -> void:
	# 员工 tab — StaffView 管「在册」: 创始人状态 + 已签约 Lead + staff 增减 + 工资合计。
	# 与 HiringView 共用 _build_hiring_view_data() 的同一份 data dict。
	if _staff_view == null:
		_clear(_tab_staff)
		_staff_view = StaffViewScene.instantiate()
		_tab_staff.add_child(_staff_view)
		_staff_view.lead_action.connect(_on_hiring_lead_action)
		_staff_view.staff_adjust.connect(_on_hiring_staff_adjust)
	_staff_view.refresh(_build_hiring_view_data())

func _build_hiring_view_data() -> Dictionary:
	# 把 GameState + HiringSystem 的状态打包成 HiringView.refresh() 期望的 dict。
	# bonus_text / status_text 在这里集中预算, view 不再访问 GameState。
	var has_founder: bool = false
	for l in GameState.leads:
		if l.is_player_scientist:
			has_founder = true
			break
	var bonus_text: Dictionary = {}
	var status_text: Dictionary = {}
	for l in GameState.lead_pool:
		bonus_text[l.id] = _format_lead_bonuses(l)
	for l in GameState.leads:
		bonus_text[l.id] = _format_lead_bonuses(l)
		status_text[l.id] = _hired_lead_status_text(l)
	var staff_rows: Array = []
	var staff_weekly_total: int = 0
	for role in GameState.STAFF_ROLES:
		var pool: int = int(GameState.staff_pool.get(role, 0))
		var busy: int = int(GameState.staff_busy.get(role, 0))
		var per_week: int = int(HiringSystem.SALARY_PER_ROLE.get(role, 0))
		staff_weekly_total += pool * per_week
		staff_rows.append({
			"role": role,
			"label": _staff_role_label(role),
			"pool": pool,
			"busy": busy,
			"per_week": per_week,
		})
	var lead_weekly_total: int = 0
	for l in GameState.leads:
		lead_weekly_total += int(l.weekly_salary)
	return {
		"has_founder": has_founder,
		"pool": GameState.lead_pool,
		"hired": GameState.leads,
		"specialty_order": [&"chief_scientist", &"ml_research_lead", &"eval_lead",
				&"chief_engineer", &"data_scientist", &"marketing_lead"],
		"specialty_labels": _hiring_specialty_labels(),
		"bonus_text": bonus_text,
		"status_text": status_text,
		"staff_rows": staff_rows,
		"weekly_totals": {
			"lead": lead_weekly_total,
			"staff": staff_weekly_total,
			"total": lead_weekly_total + staff_weekly_total,
		},
	}

func _hiring_specialty_labels() -> Dictionary:
	var out: Dictionary = {}
	for spec in [&"chief_scientist", &"ml_research_lead", &"eval_lead",
			&"chief_engineer", &"data_scientist", &"marketing_lead"]:
		out[spec] = _specialty_label(spec)
	return out

func _hired_lead_status_text(l) -> String:
	if l.is_player_scientist:
		return tr("LEAD_FOUNDER_FULL")
	if l.locked_by_task_id != &"":
		return tr("LEAD_LOCKED_BY") % String(l.locked_by_task_id)
	if l.assigned_to_product_id != &"":
		return tr("LEAD_BUSY_ON") % String(l.assigned_to_product_id)
	return "idle"

# ---- HiringView 信号 dispatch ----

func _on_hiring_lead_action(lead_id: StringName, action_id: StringName) -> void:
	match action_id:
		&"hire":
			_call(&"hiring.hire_lead", {pool_lead_id = lead_id}, tr("LEAD_SIGN"))
		&"fire":
			_call(&"hiring.fire_lead", {lead_id = lead_id}, tr("LEAD_FIRE"))
		_:
			Log.warn(&"ui", "unknown hiring_view lead_action", {action = action_id})

func _on_hiring_staff_adjust(role: StringName, delta: int) -> void:
	var label := tr("CALL_STAFF_ADD") if delta > 0 else tr("CALL_STAFF_REMOVE")
	_call(&"hiring.adjust_staff", {role = role, delta = delta}, label)

# 旧的 _make_pool_lead_row / _make_hired_lead_row 已被 HiringView + lead_card.gd 取代 (§10 step 6)。

# ---- infra tab ----------------------------------------------------------

func _render_infra_tab() -> void:
	# §10 step 6 (基建): 用 InfraView 取代旧的列表布局。
	if _infra_view == null:
		_clear(_tab_infra)
		_infra_view = InfraViewScene.instantiate()
		_tab_infra.add_child(_infra_view)
		_infra_view.new_dc_pressed.connect(_on_open_new_datacenter_dialog)
		_infra_view.dc_action.connect(_on_infra_dc_action)
	_infra_view.refresh(_build_infra_view_data())

func _build_infra_view_data() -> Dictionary:
	var facility_labels: Dictionary = {}
	var facility_icons: Dictionary = {}
	var facility_train_bonuses: Dictionary = {}
	var gpu_labels: Dictionary = {}
	var power_labels: Dictionary = {}
	var serving_target_labels: Dictionary = {}
	# 闲置 owned dc 的每周净租金 (出租到算力平台, 扣 22% 平台费后); 0 不入表。
	var dc_rental_net: Dictionary = {}
	for dc in GameState.datacenters:
		# 用 String 键: 云租用 DC 的 facility_spec_id 是空 StringName, 而
		# Dictionary 对 &"" 的 has/get 恒失败 (见 memory godot-empty-stringname-dict-key),
		# 会让云图标取不到。String("") 当键正常。
		var fid_sn: StringName = dc.facility_spec_id
		var fid: String = String(fid_sn)
		if not facility_labels.has(fid):
			facility_labels[fid] = _facility_display_name(fid_sn)
			facility_icons[fid] = _facility_icon_path(fid_sn)
			facility_train_bonuses[fid] = InfraSystem.facility_train_bonus(fid_sn)
		var gid: StringName = dc.gpu_id
		if String(gid) != "" and not gpu_labels.has(gid):
			gpu_labels[gid] = _gpu_display_name(gid)
		var pid: StringName = dc.power_supply
		if not power_labels.has(pid):
			power_labels[pid] = _power_display_name(pid)
		var target_label: String = _serving_target_display(dc)
		if target_label != "":
			serving_target_labels[dc.id] = target_label
		var rental_net: int = InfraSystem.dc_rental_net_weekly(dc)
		if rental_net > 0:
			dc_rental_net[dc.id] = rental_net
	var queue: Array = []
	for c in GameState.construction_queue:
		var spec_id: StringName = StringName(c.facility_spec_id) if "facility_spec_id" in c else StringName(c.spec_id)
		var power_id: StringName = StringName(c.power_supply) if "power_supply" in c else &"grid"
		var queued_gpu_id: StringName = StringName(c.gpu_id) if "gpu_id" in c else &""
		queue.append({
			"id": c.id,
			"facility_label": _facility_display_name(spec_id),
			"facility_icon": _facility_icon_path(spec_id),
			"power_label": _power_display_name(power_id),
			"gpu_label": _gpu_display_name(queued_gpu_id) if String(queued_gpu_id) != "" else "",
			"weeks_remaining": int(c.weeks_remaining),
			"total_weeks": int(c.total_weeks),
		})
	return {
		"datacenters": GameState.datacenters,
		"facility_labels": facility_labels,
		"facility_icons": facility_icons,
		"facility_train_bonuses": facility_train_bonuses,
		"gpu_labels": gpu_labels,
		"power_labels": power_labels,
		"serving_target_labels": serving_target_labels,
		"dc_rental_net": dc_rental_net,
		"construction_queue": queue,
	}

func _on_infra_dc_action(dc_id: StringName, action_id: StringName) -> void:
	match action_id:
		&"deploy":
			_open_deploy_drawer_for_dc(dc_id)
		&"terminate":
			_call(&"infra.terminate_dc", {dc_id = dc_id}, tr("CALL_TERMINATE_DC"))
		&"undeploy":
			_call(&"infra.undeploy_model", {dc_id = dc_id}, tr("DC_UNDEPLOY"))
		&"rent_out":
			_call(&"infra.set_dc_rent_out", {dc_id = dc_id, enabled = true}, tr("DC_RENT_OUT"))
			_request_refresh()
		&"stop_rent_out":
			_call(&"infra.set_dc_rent_out", {dc_id = dc_id, enabled = false}, tr("DC_STOP_RENT_OUT"))
			_request_refresh()
		_:
			Log.warn(&"ui", "unknown infra_view dc_action", {action = action_id})

# 打开右抽屉, 列出可部署目标 (玩家已发布模型 + 公共开源模板)。
# 点击某项即直接调 deploy 命令并关抽屉。
func _open_deploy_drawer_for_dc(dc_id: StringName) -> void:
	if _drawer_host == null:
		return
	var content := VBoxContainer.new()
	content.add_theme_constant_override(&"separation", UITheme.S_2)
	var any := false
	# 玩家已发布模型。
	var published_models: Array = GameState.models.filter(func(m): return m.status == &"published")
	if not published_models.is_empty():
		content.add_child(_drawer_section_label(tr("DRAWER_MY_PUBLISHED")))
		for m in published_models:
			var mid: StringName = m.id
			var tps: String = _preview_tps_label(dc_id, mid, &"")
			var btn := Button.new()
			btn.text = tr("DRAWER_OWN_MODEL") % [_model_display_name(mid), tps]
			btn.pressed.connect(func():
				_call(&"infra.deploy_model", {dc_id = dc_id, model_id = mid},
					tr("CALL_DEPLOY") % [_model_display_name(mid), dc_id])
				_drawer_host.close())
			content.add_child(btn)
			any = true
	# v9 PR-I: 公共开源模型 = OS NPC 的 pretrain releases.
	var downloadable: Array = MarketSystem.list_downloadable_releases(GameState.turn)
	content.add_child(_drawer_section_label(tr("DRAWER_PUBLIC_OS")))
	if downloadable.is_empty():
		var l := Label.new()
		l.text = tr("DRAWER_NO_OS")
		l.add_theme_color_override(&"font_color", UITheme.TEXT_SECONDARY)
		content.add_child(l)
	else:
		for entry in downloadable:
			var rid: StringName = entry.release.id
			var npc_name: String = String(entry.npc_display_name)
			var rname: String = String(entry.release.display_name)
			var tps: String = _preview_tps_label(dc_id, &"", rid)
			var btn := Button.new()
			btn.text = tr("DRAWER_OS_MODEL") % [rname, npc_name, tps]
			btn.pressed.connect(func():
				_call(&"infra.deploy_open_source_model", {dc_id = dc_id, release_id = rid},
					tr("CALL_SERVE") % [rid, dc_id])
				_drawer_host.close())
			content.add_child(btn)
			any = true
	if not any:
		var l := Label.new()
		l.text = tr("DRAWER_NO_DEPLOYABLE")
		l.add_theme_color_override(&"font_color", UITheme.TEXT_SECONDARY)
		content.add_child(l)
	_drawer_host.open({
		"title": tr("DRAWER_DEPLOY_TITLE") % _datacenter_display_name(dc_id),
		"content": content,
		"secondary": {"label": tr("ACTION_CANCEL"), "action_id": &"cancel"},
	})

func _drawer_section_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override(&"font_color", UITheme.TEXT_SECONDARY)
	l.add_theme_font_size_override(&"font_size", UITheme.FS_SM)
	return l

# ---- dataset tab --------------------------------------------------------
# v2 (2026-05): split market + 我的 by kind (pretrain / posttrain). The data
# collection button only shows under pretrain (data_collection currently emits
# pretrain datasets; posttrain collection is a future feature).

var _dataset_active_kind: StringName = &"pretrain"

# 数据 tab kind 配色 / tooltip 文案已迁入 DatasetView。

func _render_dataset_tab() -> void:
	# §10 step 6 (数据): 用 DatasetView 取代旧的列表布局。
	if _dataset_view == null:
		_clear(_tab_dataset)
		_dataset_view = DatasetViewScene.instantiate()
		_tab_dataset.add_child(_dataset_view)
		_dataset_view.kind_switched.connect(func(k: StringName):
			_dataset_active_kind = k
			_render_dataset_tab())
		_dataset_view.template_action.connect(_on_dataset_template_action)
		_dataset_view.dataset_action.connect(_on_dataset_action)
		_dataset_view.collect_pressed.connect(_on_collect_data_pressed)
	_dataset_view.refresh({
		"active_kind": _dataset_active_kind,
		"market_templates": _load_dataset_templates_for_kind(_dataset_active_kind),
		"owned_datasets": GameState.datasets,
	})

func _on_dataset_template_action(template_id: StringName, action_id: StringName) -> void:
	match action_id:
		&"acquire":
			_call(&"dataset.acquire_open", {template_id = template_id}, tr("CALL_ACQUIRE") % template_id)
		&"purchase":
			_call(&"dataset.purchase", {template_id = template_id}, tr("CALL_PURCHASE") % template_id)
		_:
			Log.warn(&"ui", "unknown dataset_view template_action", {action = action_id})

func _on_dataset_action(dataset_id: StringName, action_id: StringName) -> void:
	if action_id == &"delete":
		_call(&"dataset.delete", {dataset_id = dataset_id}, tr("CALL_DELETE_DS"))
	else:
		Log.warn(&"ui", "unknown dataset_view dataset_action", {action = action_id})

func _load_dataset_templates_for_kind(kind: StringName) -> Array:
	var r: Dictionary = CommandBus.send(&"dataset.list_market", {kind = kind})
	if not r.ok:
		return []
	var items: Array = r.items.duplicate()
	items.sort_custom(func(a, b): return String(a.display_name) < String(b.display_name))
	return items

# ---- model tab ----------------------------------------------------------

func _render_research_tab() -> void:
	# §10 step 5: 模型 tab 试点 — 用 ModelCardView 取代旧的列表布局。
	# view 单实例, 第一次进来时 instantiate; 之后只调 refresh()。
	if _model_view == null:
		_clear(_tab_research)
		_model_view = ModelViewScene.instantiate()
		_tab_research.add_child(_model_view)
		_model_view.new_model_pressed.connect(_on_open_pretrain_dialog)
		_model_view.model_action.connect(_on_model_view_action)
	# Array vs Array[Model]: GameState.models 是 Array, refresh 收 Array。
	_model_view.refresh(GameState.models)

func _on_model_view_action(model_id: StringName, action_id: StringName) -> void:
	match action_id:
		&"evaluate":
			_on_evaluate_pressed(model_id)
		&"posttrain":
			_on_posttrain_pressed(model_id)
		&"publish_closed":
			_call(&"research.publish_model",
				{model_id = model_id, is_open_source = false, per_token_price = 0.000002},
				tr("CALL_PUBLISH_CLOSED"))
		&"publish_open":
			_call(&"research.publish_model",
				{model_id = model_id, is_open_source = true, per_token_price = 0.000001},
				tr("CALL_PUBLISH_OPEN"))
		&"price_edit":
			_open_price_edit_dialog(model_id)
		&"unpublish":
			_call(&"research.unpublish_model", {model_id = model_id}, tr("MODEL_UNPUBLISH"))
		&"delete":
			_call(&"research.delete_model", {model_id = model_id}, tr("CALL_DELETE_MODEL"))
		_:
			Log.warn(&"ui", "unknown model_view action", {action = action_id})

# ---- tech tab -----------------------------------------------------------

func _render_tech_tab() -> void:
	# §10 step 6 (科技): 用 TechView 取代旧的列表布局。
	if _tech_view == null:
		_clear(_tab_tech)
		_tech_view = TechViewScene.instantiate()
		_tab_tech.add_child(_tech_view)
		_tech_view.research_requested.connect(_open_research_dialog)
	_tech_view.refresh(_build_tech_view_data())

func _build_tech_view_data() -> Dictionary:
	# 树状布局 (design/科技树系统设计.md §3bis): 枚举每棵树的全部节点, 各自标四态
	# (unlocked / researching / available / locked), 附 prerequisites 供画布连线。
	var trees: Array = []
	for tree in GameState.TECH_TREES:
		var nodes: Array = []
		for node_id in TechTreeSystem.nodes_in_tree(tree):
			var nid: StringName = StringName(node_id)
			var n: TechNode = TechTreeSystem.get_node_template(nid)
			nodes.append({
				"id": nid,
				"display_name": _tech_node_display(n, nid),
				"effects_summary": _tech_node_effects(n),
				"state": _tech_node_state(tree, nid, n),
				"prerequisites": n.prerequisites if n != null else [],
				"research_months": n.research_months if n != null else 0,
				"research_cost": n.research_cost if n != null else 0,
				# U-9: 研究节点不收钱, 但要研究员 / 工程师 / 卡集群。
				"min_researchers": n.min_researchers if n != null else 0,
				"min_engineers": n.min_engineers if n != null else 0,
				"min_gpu_count": n.min_gpu_count if n != null else 0,
			})
		trees.append({
			"tree": tree,
			"display": _tree_display_name(tree),
			"nodes": nodes,
		})
	return {"trees": trees}

func _tech_node_state(tree: StringName, nid: StringName, n: TechNode) -> StringName:
	if TechTreeSystem.is_unlocked(tree, nid):
		return &"unlocked"
	if GameState.researching_nodes.get(tree, {}).has(nid):
		return &"researching"
	if n != null:
		for pre in n.prerequisites:
			if not TechTreeSystem.is_unlocked(tree, pre):
				return &"locked"
	return &"available"

# ---- tasks tab ----------------------------------------------------------

func _render_tasks_tab() -> void:
	# §10 step 6 (任务): 用 TasksView 取代旧的列表布局。
	if _tasks_view == null:
		_clear(_tab_tasks)
		_tasks_view = TasksViewScene.instantiate()
		_tab_tasks.add_child(_tasks_view)
		_tasks_view.task_action.connect(_on_tasks_view_action)
	_tasks_view.refresh(GameState.active_tasks)

func _on_tasks_view_action(task_id: StringName, action_id: StringName) -> void:
	if action_id == &"cancel":
		_call(&"task.cancel", {task_id = task_id}, tr("CALL_CANCEL_TASK"))
	else:
		Log.warn(&"ui", "unknown tasks_view action", {action = action_id})

# ---- 竞争对手 tab -------------------------------------------------------

## 玩家在 `total` 榜上的最佳 (最小) 名次, 没有上榜模型时返回 "—"。
func _best_total_rank_label() -> String:
	var best: int = 0
	var board: Array = GameState.leaderboard.get(&"total", [])
	for entry in board:
		if entry.entity_type == &"player_model":
			if best == 0 or entry.rank < best:
				best = entry.rank
	if best == 0:
		return "—"
	return "#%d" % best

func _render_market_tab() -> void:
	# 竞争对手: 荣耀榜单 view (design/竞争对手系统设计.md §8) 取代旧的文本逐行渲染。
	# 强化行 + 前 3 名金/银/铜奖章 + 玩家行高亮「你」徽章。
	if _leaderboard_view == null:
		_clear(_tab_market)
		_leaderboard_view = LeaderboardViewScene.instantiate()
		_tab_market.add_child(_leaderboard_view)
		_leaderboard_view.board_selected.connect(func(bid: StringName):
			_active_market_board = bid
			_render_market_tab())
	_leaderboard_view.refresh(_build_leaderboard_view_data())

## 装配 LeaderboardView 的 pull-model 数据 (见 design/竞争对手系统设计.md §8.2)。
## view 是纯渲染器, 文案 / 名次奖励都在这里 tr() / 计算好后传入。
func _build_leaderboard_view_data() -> Dictionary:
	# 值为 i18n key, 取用处 tr() (国际化设计 §2bis)。
	var board_titles: Dictionary = {
		&"total":          "BOARD_TOTAL",
		&"closed_source":  "BOARD_CLOSED_SOURCE",
		&"open_source":    "BOARD_OPEN_SOURCE",
		&"sub_general":    "BOARD_SUB_GENERAL",
		&"sub_code":       "BOARD_SUB_CODE",
		&"sub_reasoning":  "BOARD_SUB_REASONING",
		&"sub_multimodal": "BOARD_SUB_MULTIMODAL",
		&"sub_agent":      "BOARD_SUB_AGENT",
	}
	const _BOARD_ORDER: Array[StringName] = [&"total", &"closed_source", &"open_source",
			&"sub_general", &"sub_code", &"sub_reasoning", &"sub_multimodal", &"sub_agent"]
	var boards: Array = []
	for bid in _BOARD_ORDER:
		boards.append({"id": bid, "title": tr(String(board_titles.get(bid, String(bid))))})

	var board_id: StringName = _active_market_board
	var you_label: String = tr("MARKET_YOU_BADGE")
	var entries_out: Array = []
	for entry in GameState.leaderboard.get(board_id, []):
		entries_out.append({
			"rank": entry.rank,
			"display_name": entry.display_name,
			"company_name": entry.company_name,
			"score_text": "%.1f" % entry.capability_score,
			"reward_text": _rank_bonus_for_board(board_id, entry.rank),
			"is_player": entry.entity_type == &"player_model",
			"you_label": you_label,
			"seed_id": entry.entity_id,
		})
	return {
		"header_title": tr("SECTION_MARKET_LEADERBOARD") % _best_total_rank_label(),
		"boards": boards,
		"active_board": board_id,
		"rule_text": tr("MARKET_RULE_PREFIX") + _board_bonus_rule(board_id),
		"empty_hint": tr("MARKET_EMPTY"),
		"entries": entries_out,
	}

## v7 PR-F3+: 排行榜每榜的规则说明 (总榜 / 子榜不同档位).
## 总榜额外有「base attraction 引流」加成 — 仅 top 3 享有时间曲线倍率。
func _board_bonus_rule(board_id: StringName) -> String:
	match board_id:
		&"total":
			return (tr("MARKET_RULE_TOTAL") % [
				_fmt_pct_signed(UserSystem.TOTAL_RANK_1_RATE),
				_fmt_pct_signed(UserSystem.TOTAL_RANK_TOP3_RATE),
				_fmt_pct_signed(UserSystem.TOTAL_RANK_BELOW_RATE),
			])
		&"closed_source", &"open_source":
			# 这两个榜是「展示用」, 不直接驱动需求 (UserSystem 走 total + sub_*)。
			return tr("MARKET_RULE_DISPLAY")
		_:
			# sub_* 榜.
			return tr("MARKET_RULE_SUB") % [
				_fmt_pct_signed(UserSystem.SUB_RANK_1_RATE),
				_fmt_pct_signed(UserSystem.SUB_RANK_TOP3_RATE),
				_fmt_pct_signed(UserSystem.SUB_RANK_BELOW_RATE),
			]

func _rank_bonus_for_board(board_id: StringName, rank: int) -> String:
	# 闭源 / 开源是展示榜, 不直接驱动需求 — 行不带标注。
	if board_id == &"closed_source" or board_id == &"open_source":
		return ""
	var rate: float = 0.0
	if board_id == &"total":
		if rank == 1:
			rate = UserSystem.TOTAL_RANK_1_RATE
		elif rank <= 3:
			rate = UserSystem.TOTAL_RANK_TOP3_RATE
		else:
			rate = UserSystem.TOTAL_RANK_BELOW_RATE
	else:
		if rank == 1:
			rate = UserSystem.SUB_RANK_1_RATE
		elif rank <= 3:
			rate = UserSystem.SUB_RANK_TOP3_RATE
		else:
			rate = UserSystem.SUB_RANK_BELOW_RATE
	# Append base-attraction multiplier hint for total board top 3.
	var extra: String = ""
	if board_id == &"total" and rank >= 1 and rank <= 3:
		var mult: float = 0.0
		if rank == 1: mult = UserSystem.BASE_ATTRACTION_RANK_1
		elif rank == 2: mult = UserSystem.BASE_ATTRACTION_RANK_2
		elif rank == 3: mult = UserSystem.BASE_ATTRACTION_RANK_3
		if mult > 0.0:
			extra = tr("RATE_INFLOW") % mult
	return tr("RATE_BRACKET") % [_fmt_pct_signed(rate), extra]

func _fmt_pct_signed(r: float) -> String:
	var pct: float = r * 100.0
	if pct == 0.0:
		return "0%"
	var sign_str: String = "+" if pct > 0.0 else ""
	var formatted: String = "%.1f" % pct
	if formatted.ends_with(".0"):
		formatted = formatted.substr(0, formatted.length() - 2)
	return sign_str + formatted + "%"

# ---- product tab --------------------------------------------------------

func _render_product_tab() -> void:
	# §10 step 6 (产品): 用 ProductView 取代旧的列表布局。
	if _product_view == null:
		_clear(_tab_product)
		_product_view = ProductViewScene.instantiate()
		_tab_product.add_child(_product_view)
		_product_view.new_product_pressed.connect(_on_open_new_product_dialog)
		_product_view.product_action.connect(_on_product_view_action)
		# U-2: 算力警告快捷跳转 → 切到基建 tab。
		_product_view.infra_shortcut_pressed.connect(func():
			if _sidebar_items.has(&"infra"):
				_on_sidebar_nav_pressed(&"infra"))
	_product_view.refresh(_build_product_view_data())

func _build_product_view_data() -> Dictionary:
	# 算力池行: 按 published 模型, 仅当该模型有绑定 product 时入榜。
	var pool_rows: Array = []
	for m in GameState.models:
		if m.status != &"published":
			continue
		var bound := _products_for_model(m.id)
		if bound.is_empty():
			continue
		var capacity: int = _capacity_for_model(m)
		var demand: int = int(GameState.token_demand.get(m.id, 0))
		var api_demand: int = int(GameState.api_token_demand.get(m.id, 0))
		var sub_demand: int = max(0, demand - api_demand)
		var util: float = 0.0 if capacity <= 0 else float(demand) / float(capacity) * 100.0
		pool_rows.append({
			"model_id": m.id,
			"display_name": m.display_name if m.display_name != "" else String(m.id),
			"capacity": capacity,
			"demand": demand,
			"sub_demand": sub_demand,
			"api_demand": api_demand,
			"util_pct": util,
		})
	# api 产品需要的预算字段。
	var api_price_by_model: Dictionary = {}
	var api_demand_per_product: Dictionary = {}
	var last_revenue_per_product: Dictionary = {}
	var sub_tps_per_product: Dictionary = {}
	var model_labels: Dictionary = {}
	# v8 PR-I — ProductCard 定价上下文 (推理成本 / 指导价 / 参考订阅价)。
	var api_pricing_per_product: Dictionary = {}
	var sub_guidance_per_product: Dictionary = {}
	# v7 PR-F3+ — 每周增长率分解 (let player see why a product is up/down)。
	var rate_breakdown_per_product: Dictionary = {}
	var lr: Dictionary = GameState.last_revenue_breakdown
	for p in GameState.products:
		if "bound_model_id" in p and p.bound_model_id != &"":
			model_labels[p.bound_model_id] = _model_display_name(p.bound_model_id)
		rate_breakdown_per_product[p.id] = UserSystem.compute_rate_breakdown(p)
		if "type" in p and p.type == &"api":
			api_price_by_model[p.bound_model_id] = _model_api_price(p.bound_model_id)
			api_demand_per_product[p.id] = _per_api_product_demand(p)
			last_revenue_per_product[p.id] = int(lr.get(&"api_per_product", {}).get(p.id, 0)) \
				if lr.has(&"api_per_product") else 0
			var bound = ResearchSystem.find_model(p.bound_model_id)
			if bound != null and float(bound.flops_per_token) > 0.0:
				api_pricing_per_product[p.id] = {
					&"base_price": ResearchSystem.base_price_per_token(bound),
					&"guidance_price": ResearchSystem.guidance_price_per_token(bound),
				}
		else:
			sub_tps_per_product[p.id] = int(p.subscribers) * _tokens_per_user_for_type(p.type)
			var spec: ProductTypeSpec = ProductSystem.get_type_spec(StringName(p.type))
			if spec != null:
				sub_guidance_per_product[p.id] = int(spec.subscription_price_guidance)
	return {
		"has_published_model": _first_published_model() != &"",
		"pool_rows": pool_rows,
		"products": GameState.products,
		"api_price_by_model": api_price_by_model,
		"api_demand_per_product": api_demand_per_product,
		"last_revenue_per_product": last_revenue_per_product,
		"sub_tps_per_product": sub_tps_per_product,
		"model_labels": model_labels,
		"api_pricing_per_product": api_pricing_per_product,
		"sub_guidance_per_product": sub_guidance_per_product,
		"rate_breakdown_per_product": rate_breakdown_per_product,
	}

func _on_product_view_action(product_id: StringName, action_id: StringName) -> void:
	match action_id:
		&"edit":
			var prod := ProductSystem.find_product(product_id)
			if prod != null and prod.type == &"api":
				_open_price_edit_dialog(prod.bound_model_id)
			else:
				_on_open_edit_product_dialog(product_id)
		&"delete":
			_call(&"product.delete", {product_id = product_id}, tr("CALL_DELETE_PRODUCT"))
		_:
			Log.warn(&"ui", "unknown product_view action", {action = action_id})

# _apply_util_color 已迁入 product_view (§10 step 6 第三批)。

# ---- marketing tab ------------------------------------------------------

func _render_marketing_tab() -> void:
	# v7 PR-F2: 用 MarketingView 试点视图 (design/营销系统设计.md §7) 取代
	# 旧的 inline 列表布局。view 自身不读 GameState; 我们这里把切片转 dict。
	if _marketing_view == null:
		_clear(_tab_marketing)
		_marketing_view = MarketingViewScene.instantiate()
		_tab_marketing.add_child(_marketing_view)
		_marketing_view.new_campaign_pressed.connect(_on_new_campaign_pressed)
		_marketing_view.terminate_campaign_pressed.connect(
				func(cid: StringName):
					_call(&"marketing.terminate_campaign", {campaign_id = cid}, tr("CALL_TERMINATE_CAMPAIGN")))
	_marketing_view.refresh(_build_marketing_view_data())

func _build_marketing_view_data() -> Dictionary:
	# v7 PR-F3: campaign 锁单 product; 渲染把 target_product_id 翻成 label。
	var cap: int = MarketingSystem.MAX_CONCURRENT_CAMPAIGNS
	var active: int = GameState.campaigns.size()
	var can_create: bool = active < cap and not GameState.products.is_empty()
	var reason: String = ""
	if active >= cap:
		reason = tr("CAMPAIGN_CAP_REASON") % [active, cap]
	elif GameState.products.is_empty():
		reason = tr("CAMPAIGN_NO_PRODUCT_REASON")
	var rows: Array = []
	var conv: float = UserSystem.MARKETING_CONVERSION_RATE
	# 创始人出身加成 (网红 user_growth_multiplier) 会放大本周正向用户净增 —
	# 营销拉新是其中一部分, 所以预期人数计入它, 让 UI 与实际增长一致。
	var founder_mult: float = FounderSystem.user_growth_multiplier()
	for c in GameState.campaigns:
		var target_id: StringName = c.target_product_id if "target_product_id" in c else &""
		var prod = ProductSystem.find_product(target_id) if target_id != &"" else null
		var is_api: bool = prod != null and "type" in prod and prod.type == &"api"
		var target_label: String = _product_label(prod) if prod != null else tr("PRODUCT_LABEL_DELETED")
		var lead_mult: float = _marketing_lead_mult(c.lead_id if "lead_id" in c else &"")
		var per_week: int = int(round(float(c.weekly_budget) * conv * lead_mult * founder_mult))
		rows.append({
			id = c.id,
			display_name = c.display_name,
			weekly_budget = c.weekly_budget,
			remaining_weeks = c.remaining_weeks,
			total_weeks = c.total_weeks,
			target_product_id = target_id,
			target_product_label = target_label,
			target_is_api = is_api,
			lead_label = _marketing_lead_label(c.lead_id if "lead_id" in c else &""),
			lead_mult = lead_mult,
			expected_per_week = per_week,
		})
	return {
		cap = cap,
		active_count = active,
		can_create = can_create,
		create_disabled_reason = reason,
		campaigns = rows,
		founder_mult = founder_mult,
	}

func _product_label(prod) -> String:
	if prod == null:
		return tr("PRODUCT_LABEL_UNKNOWN")
	var disp_name: String = String(prod.display_name) if "display_name" in prod \
			and not String(prod.display_name).is_empty() else String(prod.id)
	var ptype: String = _product_type_label(StringName(prod.type)) if "type" in prod else "?"
	var bound: String = _model_display_name(prod.bound_model_id) if "bound_model_id" in prod \
			and prod.bound_model_id != &"" else tr("CAMPAIGN_UNBOUND")
	return tr("PRODUCT_LABEL_FMT") % [disp_name, ptype, bound]

func _product_type_label(type_id: StringName) -> String:
	match type_id:
		&"chatbot":
			return tr("PRODUCT_TYPE_CHATBOT")
		&"agent":
			return tr("PRODUCT_TYPE_AGENT")
		&"api":
			return "API"
		&"multimodal_assistant":
			return tr("PRODUCT_TYPE_MULTIMODAL")
		&"coding_agent":
			return tr("PRODUCT_TYPE_CODING")
		_:
			return String(type_id).replace("_", " ")

func _marketing_lead_mult(lead_id: StringName) -> float:
	if lead_id == &"":
		return 1.0
	var lead = HiringSystem.find_lead(lead_id)
	if lead == null or lead.specialty != &"marketing_lead":
		return 1.0
	var table: Dictionary = HiringSystem.LEAD_BONUS_TABLE.get(&"marketing_lead", {})
	var coef: float = float(table.get(&"campaign_efficiency", 0.0))
	return 1.0 + (float(lead.ability) / 100.0) * coef

func _marketing_lead_label(lead_id: StringName) -> String:
	if lead_id == &"":
		return tr("MSG_NONE")
	var lead = HiringSystem.find_lead(lead_id)
	if lead == null:
		return tr("MARKETING_LEAD_GONE")
	# 用 specialty 名 + 友好等级, 不再露出 raw 枚举 (marketing_lead/S ...)。
	var spec_cn: String = tr(_SPECIALTY_CN.get(lead.specialty, String(lead.specialty)))
	return tr("LEAD_LABEL_FULL") % [NameRomanizer.localized(lead.display_name),
			spec_cn, String(lead.level), float(lead.ability)]

# ---- charity tab --------------------------------------------------------

func _render_charity_tab() -> void:
	# 慈善 tab (design/慈善系统设计.md §8)。view 不读 GameState; 这里把 CharitySystem
	# spec + 当前累计 + 进行中的 charity 任务转 dict。
	if _charity_view == null:
		_clear(_tab_charity)
		_charity_view = CharityViewScene.instantiate()
		_tab_charity.add_child(_charity_view)
		_charity_view.donate_pressed.connect(
				func(cause_id: StringName, tier_index: int):
					_call(&"charity.start_donation",
							{cause_id = cause_id, tier_index = tier_index},
							tr("CALL_CHARITY_DONATE")))
		_charity_view.sim_start_pressed.connect(_open_sim_donation_dialog)
	_charity_view.refresh(_build_charity_view_data())

func _build_charity_view_data() -> Dictionary:
	var causes: Array = []
	for spec in CharitySystem.all_specs():
		var cid: StringName = spec.id
		var in_prog: Array = []
		for t in GameState.active_tasks:
			if t.subtype != &"charity":
				continue
			var pc: Dictionary = t.completion_payload
			var pc_cause: StringName = StringName(pc.get(&"cause_id", pc.get("cause_id", &"")))
			if pc_cause != cid:
				continue
			in_prog.append({
				amount = int(pc.get(&"amount", pc.get("amount", 0))),
				remaining = maxi(0, int(t.total_weeks) - int(t.elapsed_weeks)),
				total = int(t.total_weeks),
			})
		causes.append({
			id = cid,
			display_name = spec.display_name,
			description = spec.description,
			effect_kind = spec.effect_kind,
			current_tier_index = CharitySystem.current_tier_index(cid),
			current_bonus = CharitySystem.current_bonus(cid),
			donated = CharitySystem.donated_for(cid),
			tier_done = CharitySystem.tier_done(cid),
			donating = not in_prog.is_empty(),
			tier_amounts = spec.tier_amounts,
			tier_labels = spec.tier_labels,
			tier_bonuses = spec.tier_bonuses,
			in_progress = in_prog,
		})
	return {cash = GameState.cash, causes = causes,
			simulation = _build_simulation_view_data()}

func _build_simulation_view_data() -> Dictionary:
	# 宇宙模拟工程阶梯 (design/宇宙模拟工程设计.md §8)。门槛 = 能捐出一座
	# 满足 FLOPs 的自有空闲未出租 DC + 现金。
	var sdone: int = SimulationSystem.stages_done()
	# 找进行中的 simulation 任务 (一次只跑一级)。
	var running_stage: StringName = &""
	var running_remaining: int = 0
	for t in GameState.active_tasks:
		if t.subtype == &"simulation":
			var pc: Dictionary = t.completion_payload
			running_stage = StringName(pc.get(&"stage_id", pc.get("stage_id", &"")))
			running_remaining = maxi(0, int(t.total_weeks) - int(t.elapsed_weeks))
			break
	var stages: Array = []
	for spec in SimulationSystem.all_stages():
		var status: String = "locked"
		if spec.id == running_stage:
			status = "running"
		elif int(spec.order) < sdone:
			status = "done"
		elif int(spec.order) == sdone:
			status = "available"
		var can_start: bool = false
		var gate: String = ""
		if status == "available" and running_stage == &"":
			var compute_ok: bool = not SimulationSystem.eligible_datacenters(spec).is_empty()
			var cash_ok: bool = int(spec.cost) <= GameState.cash
			can_start = compute_ok and cash_ok
			if not compute_ok:
				gate = tr("SIM_GATE_COMPUTE")
			elif not cash_ok:
				gate = tr("SIM_GATE_CASH")
		stages.append({
			id = spec.id,
			display_name = spec.display_name,
			description = spec.description,
			order = int(spec.order),
			cost = int(spec.cost),
			weeks = int(spec.weeks),
			min_tflops = float(spec.min_train_tflops),
			status = status,
			can_start = can_start,
			gate_reason = gate,
			remaining_weeks = running_remaining if status == "running" else 0,
		})
	return {
		stages_done = sdone,
		total = SimulationSystem.total_stages(),
		revealed = SimulationSystem.universe_revealed(),
		stages = stages,
	}

const SimDonationDialogScript := preload(
		"res://scenes/ui/simulation_donation_dialog/simulation_donation_dialog.gd")

## 弹出捐建数据中心对话框: 列出满足该阶梯 FLOPs 门槛的自有空闲未出租 DC 供玩家单选捐出。
## 确认 → simulation.start_stage {dc_id} (永久消耗该 DC)。Per 宇宙模拟工程设计.md §8。
func _open_sim_donation_dialog(stage_id: StringName) -> void:
	var spec := SimulationSystem.spec_for(stage_id)
	if spec == null:
		return
	var dcs: Array = []
	for dc in SimulationSystem.eligible_datacenters(spec):
		dcs.append({
			id = dc.id,
			display_name = dc.display_label(),
			gpu_count = int(dc.gpu_count),
			train_tflops = float(dc.train_tflops),
			gpu_id = dc.gpu_id,
		})
	var dlg := SimDonationDialogScript.new()
	add_child(dlg)
	dlg.confirmed_dc.connect(func(dc_id: StringName):
		_call(&"simulation.start_stage", {dc_id = dc_id}, tr("CALL_SIM_START"))
		dlg.queue_free())
	dlg.canceled.connect(func(): dlg.queue_free())
	dlg.close_requested.connect(func(): dlg.queue_free())
	dlg.open_for_stage({
		display_name = spec.display_name,
		min_train_tflops = float(spec.min_train_tflops),
		cost = int(spec.cost),
		weeks = int(spec.weeks),
	}, dcs)
	dlg.popup_centered()

func _on_universe_answer_revealed() -> void:
	_request_refresh()
	_show_universe_answer_prompt()

func _show_universe_answer_prompt() -> void:
	if _universe_answer_prompt_shown:
		return
	_universe_answer_prompt_shown = true
	Log.info(&"main", "universe_answer_prompt", {turn = GameState.turn})
	var dlg := AcceptDialog.new()
	dlg.title = tr("SIM_REVEAL_TITLE")
	dlg.dialog_text = tr("SIM_REVEAL_BODY")
	dlg.dialog_autowrap = true
	dlg.min_size = Vector2i(520, 170)
	dlg.get_ok_button().text = tr("SIM_REVEAL_OK")
	dlg.confirmed.connect(func():
		dlg.queue_free()
		_focus_office_for_universe_answer())
	dlg.canceled.connect(dlg.queue_free, CONNECT_ONE_SHOT)
	dlg.close_requested.connect(dlg.queue_free, CONNECT_ONE_SHOT)
	add_child(dlg)
	dlg.popup_centered()

func _focus_office_for_universe_answer() -> void:
	if _sidebar_items.has(&"office"):
		_on_sidebar_nav_pressed(&"office")
	_render_office_tab()

# ---- office tab ---------------------------------------------------------

func _render_office_tab() -> void:
	# 办公室第一人称房间 (design/办公室与收藏系统设计.md §8.1): 点电脑屏幕 → 收藏柜 dialog
	# (§8.2); 点桌上奖章 / 茶几奖杯 → 荣誉信息 dialog。买入仍走拍卖行 tab。
	if _office_view == null:
		_clear(_tab_office)
		_office_view = OfficeViewScene.instantiate()
		_tab_office.add_child(_office_view)
		_office_view.computer_pressed.connect(_open_collectibles_dialog)
		_office_view.honor_pressed.connect(_open_honor_dialog)
	_office_view.refresh(_build_office_view_data())

func _build_office_view_data() -> Dictionary:
	# 房间陈列 earned 奖杯/奖章。传全部 spec + earned + form, 由视图按 form 分桌面/茶几。
	var trophies: Array = []
	for t in CollectionSystem.all_trophy_specs():
		trophies.append({
			id = t.id,
			display_name = t.display_name,
			description = t.description,
			unlock_hint = t.unlock_hint,
			form = t.form,
			earned = CollectionSystem.is_trophy_earned(t.id),
		})
	return {trophies = trophies}

# 荣誉信息 dialog (点击办公室奖章/奖杯打开): 名 + 描述 + flavor 叙事文案。
func _open_honor_dialog(trophy_id: StringName) -> void:
	var spec: TrophySpec = null
	for t in CollectionSystem.all_trophy_specs():
		if t.id == trophy_id:
			spec = t
			break
	if spec == null:
		Log.warn(&"ui", "honor_dialog_unknown_trophy", {id = trophy_id})
		return
	var dlg: HonorDialog = HonorDialog.new()
	add_child(dlg)
	dlg.confirmed.connect(func(): dlg.queue_free())
	dlg.close_requested.connect(func(): dlg.queue_free())
	dlg.refresh({
		name = tr(spec.display_name),
		description = tr(spec.description),
		flavor = tr(spec.flavor),
	})
	dlg.popup_centered()

# 收藏柜 dialog (点击办公室电脑打开): 持有藏品 + 卖出。买入在拍卖行 tab。
func _open_collectibles_dialog() -> void:
	var dlg: CollectiblesDialog = CollectiblesDialog.new()
	add_child(dlg)
	dlg.sell_pressed.connect(
			func(cid: StringName):
				_call(&"collection.sell", {collectible_id = cid}, tr("CALL_COLLECTION_SELL"))
				dlg.refresh(_build_cabinet_data()))
	dlg.confirmed.connect(func(): dlg.queue_free())
	dlg.close_requested.connect(func(): dlg.queue_free())
	dlg.refresh(_build_cabinet_data())
	dlg.popup_centered()

func _build_cabinet_data() -> Dictionary:
	var cabinet: Array = []
	for spec in CollectionSystem.owned_specs():
		cabinet.append({
			id = spec.id,
			display_name = spec.display_name,
			description = spec.description,
			category = spec.category,
			bought_price = CollectionSystem.bought_price(spec.id),
			current_price = CollectionSystem.current_price(spec.id),
		})
	return {cabinet = cabinet, sell_fee = CollectionSystem.SELL_FEE}

func _render_auction_tab() -> void:
	# 拍卖行 (design/办公室与收藏系统设计.md §8): 目录按当前市价买入。
	if _auction_view == null:
		_clear(_tab_auction)
		_auction_view = AuctionViewScene.instantiate()
		_tab_auction.add_child(_auction_view)
		_auction_view.buy_pressed.connect(
				func(cid: StringName):
					_call(&"collection.buy", {collectible_id = cid}, tr("CALL_COLLECTION_BUY")))
	_auction_view.refresh(_build_auction_view_data())

func _render_help_tab() -> void:
	# 帮助 (design/教程与帮助系统设计.md §2): 系统说明 master-detail; 顶部按钮复用新手引导。
	# 静态内容, 不读 GameState; refresh({}) 仅在语言切换时重渲染文案。
	if _help_view == null:
		_clear(_tab_help)
		_help_view = HelpViewScene.instantiate()
		_tab_help.add_child(_help_view)
		_help_view.replay_tutorial_pressed.connect(_show_intro_tutorial)
	_help_view.refresh({})

## 弹出新游戏新手引导 (多页分步)。开局自动调一次 (见 _ready), 也可在帮助 view 顶部
## 手动重看。「不再显示」勾选经 finished 信号落 Preferences (组件本身不碰全局态)。
func _show_intro_tutorial() -> void:
	var dlg: TutorialDialog = TutorialDialog.new()
	add_child(dlg)
	# 注意: 不接 confirmed → queue_free, 因为 confirmed 每次「下一步」都会 fire (会把翻页
	# 中的对话框提前释放)。真正关闭只在末页 (finished) 或 取消/关闭 (X/Esc) 时发生。
	dlg.finished.connect(func(dont_show_again: bool):
		Preferences.set_skip_intro(dont_show_again)
		dlg.queue_free())
	dlg.canceled.connect(func(): dlg.queue_free())
	dlg.close_requested.connect(func(): dlg.queue_free())
	dlg.open()

func _build_auction_view_data() -> Dictionary:
	var cash: int = GameState.cash
	var auction: Array = []
	for spec in CollectionSystem.available_lots():
		var price: int = CollectionSystem.current_price(spec.id)
		auction.append({
			id = spec.id,
			display_name = spec.display_name,
			description = spec.description,
			category = spec.category,
			price = price,
			affordable = price <= cash,
		})
	return {cash = cash, auction = auction}

# ---- revenue tab --------------------------------------------------------

func _render_revenue_tab() -> void:
	# 营收系统设计 §6bis: 用 RevenueView (可折叠分组 + 占比条) 取代旧的内联文本行。
	if _revenue_view == null:
		_clear(_tab_revenue)
		_revenue_view = RevenueViewScene.instantiate()
		_tab_revenue.add_child(_revenue_view)
	_revenue_view.refresh(_build_revenue_view_data())

# 把 last_revenue_breakdown 整理成 RevenueView 要的形状: 按 bound_model 聚合 API +
# 订阅营收, 每组带 api/sub 小计与产品明细行。用带引号 String key (与视图 .get(...)
# 一致, 规避 String/StringName key 歧义, 见 product_view 同款约定)。
func _build_revenue_view_data() -> Dictionary:
	var br: Dictionary = GameState.last_revenue_breakdown
	if br.is_empty():
		return {"settled": false}
	var api_total: int = int(br.get(&"api_total", 0))
	var sub_total: int = int(br.get(&"subscription_total", 0))
	var api_per_model: Dictionary = br.get(&"api_per_model", {})
	var api_per_product: Dictionary = br.get(&"api_per_product", {})
	var sub_per_product: Dictionary = br.get(&"subscription_per_product", {})

	var by_model: Dictionary = {}
	var order: Array = []
	var ensure := func(mid: StringName) -> Dictionary:
		if not by_model.has(mid):
			by_model[mid] = {
				"display_name": _model_display_name(mid),
				"total": 0, "api": 0, "sub": 0, "products": [],
			}
			order.append(mid)
		return by_model[mid]

	# API: api_per_model 给每模型 api 小计; api_per_product 给产品明细行。
	for mid in api_per_model.keys():
		var amt: int = int(api_per_model[mid])
		if amt <= 0:
			continue
		var g: Dictionary = ensure.call(StringName(mid))
		g["total"] = int(g["total"]) + amt
		g["api"] = int(g["api"]) + amt
	for pid in api_per_product.keys():
		var amt: int = int(api_per_product[pid])
		if amt <= 0:
			continue
		var prod = ProductSystem.find_product(pid)
		if prod == null:
			continue
		var g: Dictionary = ensure.call(StringName(prod.bound_model_id))
		g["products"].append({
			"name": _product_display_name(pid), "kind": &"api", "amount": amt})

	# 订阅: sub_per_product 同时给模型小计与产品明细。
	for pid in sub_per_product.keys():
		var amt: int = int(sub_per_product[pid])
		if amt <= 0:
			continue
		var prod = ProductSystem.find_product(pid)
		var mid: StringName = StringName(prod.bound_model_id) if prod != null else &""
		var g: Dictionary = ensure.call(mid)
		g["total"] = int(g["total"]) + amt
		g["sub"] = int(g["sub"]) + amt
		g["products"].append({
			"name": _product_display_name(pid), "kind": &"sub", "amount": amt})

	# 跳过 0 营收分组; 组内产品按额降序; 分组整体按总额降序 (大头在上)。
	var groups: Array = []
	for mid in order:
		var g: Dictionary = by_model[mid]
		if int(g["total"]) <= 0:
			continue
		var products: Array = g["products"]
		products.sort_custom(func(a, b): return int(a["amount"]) > int(b["amount"]))
		groups.append({
			"model_id": mid,
			"display_name": g["display_name"],
			"total": int(g["total"]),
			"api": int(g["api"]),
			"sub": int(g["sub"]),
			"products": products,
		})
	groups.sort_custom(func(a, b): return int(a["total"]) > int(b["total"]))

	# 算力需求 (按模型)。
	var demand_rows: Array = []
	for mid in GameState.token_demand.keys():
		var total: int = int(GameState.token_demand[mid])
		var api_part: int = int(GameState.api_token_demand.get(mid, 0))
		var sub_part: int = maxi(0, total - api_part)
		demand_rows.append({
			"display_name": _model_display_name(mid),
			"total": total, "sub": sub_part, "api": api_part})

	return {
		"settled": true,
		"turn": int(br.get(&"turn", -1)),
		"api_total": api_total,
		"sub_total": sub_total,
		"grand_total": api_total + sub_total,
		"api_demand_lost": int(br.get(&"api_demand_lost", 0)),
		"groups": groups,
		"demand_rows": demand_rows,
	}

func _model_display_name(model_id) -> String:
	var m = ResearchSystem.find_model(model_id)
	if m != null and String(m.display_name) != "":
		return String(m.display_name)
	return String(model_id)

func _datacenter_display_name(dc_id: StringName) -> String:
	for dc in GameState.datacenters:
		if StringName(dc.id) == dc_id:
			return dc.display_label()  # locale 感知 (含云租名 + 旧档 id 后缀裁剪)
	return String(dc_id)

func _product_display_name(product_id) -> String:
	var p = ProductSystem.find_product(product_id)
	if p != null and String(p.display_name) != "":
		return String(p.display_name)
	return String(product_id)

# ---- event tab ----------------------------------------------------------

func _render_event_tab() -> void:
	# §10 step 6 (事件): 用 EventView 取代旧的列表布局。
	if _event_view == null:
		_clear(_tab_event)
		_event_view = EventViewScene.instantiate()
		_tab_event.add_child(_event_view)
		_event_view.option_selected.connect(_on_event_option_selected)
		_event_view.flavor_dismissed.connect(_on_event_flavor_dismissed)
	_event_view.refresh(_build_event_view_data())

func _build_event_view_data() -> Dictionary:
	var pending: Array = []
	for inst in GameState.pending_events:
		var card = _load_card(inst.template_id)
		if card == null:
			pending.append({
				"id": inst.id,
				"template_id": inst.template_id,
				"category": &"flavor",
				"title": "EVENT_MISSING_TITLE",
				"body": tr("EVENT_MISSING_BODY") % String(inst.template_id),
				"options": [],
				"dismiss_consequence": "",
			})
			continue
		var options: Array = []
		for opt in card.options:
			# 裸 label (内容层) 与后果预览 (UI 层) 分开传, 由 view 各自翻译再拼,
			# 否则拼好的复合串不是任何 key 会整条回落中文 (见 国际化设计.md §6bis)。
			options.append({
				"id": opt.id,
				"label": opt.label,
				"consequence": EventSystem.describe_option_consequence(opt),
			})
		pending.append({
			"id": inst.id,
			"template_id": inst.template_id,
			"category": card.category,
			"title": card.title,
			"body": card.body,
			"options": options,
			"dismiss_consequence": EventSystem.describe_effects_consequence(card.passive_effects),
		})
	var history: Array = []
	for inst in GameState.event_history:
		var hist_card = _load_card(inst.template_id)
		history.append({
			"template_id": inst.template_id,
			"chosen_option_id": inst.chosen_option_id,
			"title": hist_card.title if hist_card != null else String(inst.template_id),
			"chosen_label": _event_option_display_label(hist_card, inst.chosen_option_id),
			"resolved_at_turn": inst.resolved_at_turn,
		})
	return {"pending": pending, "history": history}

func _event_option_display_label(card, option_id: StringName) -> String:
	if card == null:
		return String(option_id)
	for opt in card.options:
		if StringName(opt.id) == option_id:
			return String(opt.label)
	return String(option_id)

func _on_event_option_selected(event_id: StringName, option_id: StringName) -> void:
	_call(&"event.choose_option", {event_id = event_id, option_id = option_id},
		tr("CALL_EVENT_CHOICE") % option_id)

func _on_event_flavor_dismissed(event_id: StringName) -> void:
	_call(&"event.dismiss_flavor", {event_id = event_id}, tr("CALL_EVENT_DISMISS"))

# ---- task launcher helpers ---------------------------------------------

func _find_idle_lead(specialty: StringName) -> StringName:
	for l in GameState.leads:
		if l.is_idle() and l.specialty == specialty:
			return l.id
	return &""

func _on_open_pretrain_dialog() -> void:
	# Per design/任务系统设计.md §5.1.1 — single entry point for pretrain.
	# Build a fresh dialog each time so it reads current GameState slices.
	var dlg := PretrainDialog.new()
	add_child(dlg)
	dlg.task_started_via_dialog.connect(func(r: Dictionary):
		var turns: int = int(r.get(&"total_weeks", 0))
		_set_status(tr("TOAST_PRETRAIN_STARTED") % [String(r.get(&"task_id", &"")), turns]))
	dlg.close_requested.connect(func(): dlg.queue_free())
	dlg.refresh()
	# 预训练是核心操作, 表单 + 预览两栏并排, 给足空间 — 占视口 ~82%。
	dlg.popup_centered_ratio(0.82)

func _on_open_new_datacenter_dialog() -> void:
	var dlg := NewDatacenterDialog.new()
	add_child(dlg)
	dlg.datacenter_created.connect(func(dc_id: StringName):
		_set_status(tr("TOAST_DC_CREATED") % String(dc_id)))
	dlg.close_requested.connect(func(): dlg.queue_free())
	dlg.refresh()
	dlg.popup_centered()

func _on_open_new_product_dialog() -> void:
	var dlg := NewProductDialog.new()
	add_child(dlg)
	dlg.product_created.connect(func(pid: StringName):
		_set_status(tr("TOAST_PRODUCT_LIVE") % String(pid)))
	dlg.close_requested.connect(func(): dlg.queue_free())
	dlg.setup_create()
	dlg.popup_centered()

func _open_research_dialog(tree: StringName, node_id: StringName) -> void:
	# v6 (PR-D): replaces the inline "研究" button. The dialog gathers
	# lead + ml_eng + infra_eng + datacenter before sending tech.start_research.
	# Per design/科技树系统设计.md §5.2.
	var dlg := ResearchDialog.new()
	dlg.setup(tree, node_id)
	add_child(dlg)
	dlg.task_started_via_dialog.connect(func(r: Dictionary):
		var turns: int = int(r.get(&"total_weeks", 0))
		_set_status(tr("TOAST_RESEARCH_STARTED") % [String(node_id), turns]))
	dlg.close_requested.connect(func(): dlg.queue_free())
	dlg.popup_centered()

func _on_open_edit_product_dialog(product_id: StringName) -> void:
	var dlg := NewProductDialog.new()
	add_child(dlg)
	dlg.product_edited.connect(func(pid: StringName):
		_set_status(tr("TOAST_PRODUCT_SAVED") % String(pid)))
	dlg.close_requested.connect(func(): dlg.queue_free())
	dlg.setup_edit(product_id)
	dlg.popup_centered()

func _on_collect_data_pressed() -> void:
	# v2.1: open DatasetCollectionDialog (per design/数据集系统设计.md §5.1ter)
	# instead of the legacy single-shot collect call.
	var dlg: ConfirmationDialog = load("res://scenes/ui/dataset_collection_dialog/dataset_collection_dialog.gd").new()
	add_child(dlg)
	dlg.set_initial_kind(_dataset_active_kind)
	dlg.refresh()
	dlg.task_started_via_dialog.connect(func(r):
		_report(r, tr("TASK_SUBTYPE_DATA_COLLECTION"))
		dlg.queue_free())
	dlg.canceled.connect(func(): dlg.queue_free())
	dlg.popup_centered()

func _on_new_campaign_pressed() -> void:
	# Open NewCampaignDialog. Per design/营销系统设计.md §5.2.
	var dlg: ConfirmationDialog = load("res://scenes/ui/new_campaign_dialog/new_campaign_dialog.gd").new()
	add_child(dlg)
	dlg.refresh()
	dlg.campaign_started_via_dialog.connect(func(r):
		_report(r, tr("CALL_START_CAMPAIGN"))
		dlg.queue_free())
	dlg.canceled.connect(func(): dlg.queue_free())
	dlg.popup_centered()

## v2: 打开 PosttrainDialog 让玩家选 DC + 多个 posttrain dataset + 可选 lead.
## Per design/研究系统设计.md §5.3 (v2).
func _on_posttrain_pressed(model_id: StringName) -> void:
	var dlg: ConfirmationDialog = load("res://scenes/ui/posttrain_dialog/posttrain_dialog.gd").new()
	dlg.set_base_model_id(model_id)
	add_child(dlg)
	dlg.refresh()
	dlg.task_started_via_dialog.connect(func(r):
		_report(r, tr("CALL_POSTTRAIN") % model_id)
		dlg.queue_free())
	dlg.canceled.connect(func(): dlg.queue_free())
	dlg.popup_centered()

func _on_evaluate_pressed(model_id: StringName) -> void:
	# Per design/招聘系统设计.md §5.4 + §2 (2026-05): evaluate 强制 eval_lead.
	# 玩家本人 (is_player_scientist) 也算匹配 (但无加成)。优先取真正的 eval_lead,
	# 没有时退到创始人, 都没有时 toast 提示。
	var lid: StringName = _first_idle_lead_matching(&"eval_lead")
	if lid == &"":
		_set_status(tr("TOAST_EVAL_FAILED_NO_LEAD"), true)
		return
	var r: Dictionary = CommandBus.send(&"task.start", {
		template_id = TEMPLATE_EVALUATE,
		lead_ids = [lid], staff = {},
		base_model_id = model_id,
	})
	_report(r, tr("CALL_EVALUATE") % model_id)

## 优先返回 specialty 严格匹配的 idle lead; 找不到则返回 idle 的创始人 (万能,
## 无加成); 都没有返回 &""。
func _first_idle_lead_matching(specialty: StringName) -> StringName:
	var founder_id: StringName = &""
	for l in GameState.leads:
		if not l.is_idle():
			continue
		if l.is_player_scientist:
			if founder_id == &"":
				founder_id = l.id
			continue
		if l.specialty == specialty:
			return l.id
	return founder_id

func _open_price_edit_dialog(model_id: StringName) -> void:
	# v8 PR-I — 取代旧的 price_up / price_down 按钮 (multiplier 改价)。
	# 打开 PriceEditDialog, 让玩家用输入框敲新价 ($/M tok) 并实时看到
	# 定价比 + 周需求增长预览。详见 design/研究系统设计.md §4.8。
	var m = ResearchSystem.find_model(model_id)
	if m == null:
		_set_status(tr("TOAST_PRICE_FAILED_UNKNOWN"), true)
		return
	var dlg: PriceEditDialog = PriceEditDialog.new()
	add_child(dlg)
	dlg.price_updated.connect(func(_id, applied):
		_set_status(tr("TOAST_PRICE_UPDATED") % _format_per_token_price(float(applied))))
	dlg.confirmed.connect(func(): dlg.queue_free())
	dlg.canceled.connect(func(): dlg.queue_free())
	dlg.close_requested.connect(func(): dlg.queue_free())
	dlg.refresh(m)
	dlg.popup_centered()

func _on_create_product_pressed(type_id: StringName) -> void:
	var spec: ProductTypeSpec = ProductSystem.get_type_spec(type_id)
	if spec == null:
		_set_status(tr("TOAST_CREATE_FAILED_TYPE"), true)
		return
	var model_id: StringName = _first_published_model_for_type(type_id)
	if model_id == &"":
		_set_status(tr("TOAST_CREATE_FAILED_NO_MODEL"), true)
		return
	if type_id == &"api":
		# §0bis: api 不需要 lead/staff/价格; bound_model 是唯一参数.
		var r_api: Dictionary = CommandBus.send(&"product.create", {
			type = &"api",
			bound_model_id = model_id,
		})
		if r_api.ok:
			_set_status(tr("TOAST_CREATE_API_OK") % String(model_id))
		else:
			_set_status(tr("TOAST_CREATE_API_FAILED") % String(r_api.get(&"error", &"unknown")), true)
		return
	var payload: Dictionary = {
		type = type_id,
		display_name = "%s Pro" % spec.display_name,
		bound_model_id = model_id,
		subscription_price = spec.default_subscription_price,
		staff = {},
		auto_track_latest = true,
	}
	var lead_id: StringName = _find_idle_lead(&"chief_engineer")
	if lead_id != &"":
		payload[&"lead_id"] = lead_id
	var r: Dictionary = CommandBus.send(&"product.create", payload)
	if r.ok:
		_set_status(tr("TOAST_CREATE_OK") % spec.display_name)
	else:
		_set_status(tr("TOAST_CREATE_FAILED") % [
			spec.display_name, String(r.get(&"error", &"unknown"))], true)

func _on_adjust_product_price(product_id: StringName, delta: int) -> void:
	var p = ProductSystem.find_product(product_id)
	if p == null:
		_set_status(tr("TOAST_PRODUCT_PRICE_FAILED"), true)
		return
	var next_price: int = maxi(0, int(p.subscription_price) + delta)
	_call(&"product.update", {
		product_id = product_id,
		fields = {price = next_price},
	}, tr("CALL_PRICE_EDIT_PRODUCT"))

func _on_create_chatbot_pressed() -> void:
	var lead_id: StringName = _find_idle_lead(&"chief_engineer")
	if lead_id == &"":
		_set_status(tr("TOAST_NO_CHIEF_ENGINEER"), true)
		return
	var model_id: StringName = _first_published_model()
	if model_id == &"":
		_set_status(tr("TOAST_NO_PUBLISHED_MODEL"), true)
		return
	var r: Dictionary = CommandBus.send(&"product.create", {
		type = &"chatbot",
		display_name = "ChatBot Pro",
		bound_model_id = model_id,
		subscription_price = 5,
		lead_id = lead_id,
		staff = {},
	})
	_report(r, tr("CALL_CREATE_CHATBOT"))

func _on_create_agent_pressed() -> void:
	var lead_id: StringName = _find_idle_lead(&"chief_engineer")
	if lead_id == &"":
		_set_status(tr("TOAST_NO_CHIEF_ENGINEER"), true)
		return
	var model_id: StringName = _first_published_model()
	if model_id == &"":
		_set_status(tr("TOAST_NO_PUBLISHED_MODEL"), true)
		return
	var r: Dictionary = CommandBus.send(&"product.create", {
		type = &"agent",
		display_name = "AgentX",
		bound_model_id = model_id,
		subscription_price = 25,
		lead_id = lead_id,
		staff = {},
	})
	_report(r, tr("CALL_CREATE_AGENT"))

# ---- save / load dialog -------------------------------------------------

func _on_open_save_load_dialog() -> void:
	var dlg: SaveLoadDialog = SaveLoadDialog.new()
	add_child(dlg)
	dlg.confirmed.connect(func(): dlg.queue_free())
	dlg.canceled.connect(func(): dlg.queue_free())
	dlg.close_requested.connect(func(): dlg.queue_free())
	dlg.open()

# ---- settings dialog ----------------------------------------------------

## 游戏内顶栏「设置」按钮 — 与起始页共用 SettingsDialog (国际化设计 §11.0)。
## 游戏内额外开放「返回主菜单」入口 (allow_return_to_menu, 起始页保持隐藏)。
func _on_open_settings_dialog() -> void:
	var dlg: SettingsDialog = SettingsDialog.new()
	add_child(dlg)
	dlg.allow_return_to_menu = true
	dlg.return_to_menu_requested.connect(_on_return_to_main_menu)
	dlg.confirmed.connect(func(): dlg.queue_free())
	dlg.canceled.connect(func(): dlg.queue_free())
	dlg.close_requested.connect(func(): dlg.queue_free())
	dlg.open()

## 玩家在设置弹窗确认「返回主菜单」: 先把当前进度写入 autosave (可从「继续游戏」
## 恢复, 不误丢进度), 再切回起始页。测试运行下跳过真正切场景 (出身系统设计 §1)。
func _on_return_to_main_menu() -> void:
	Save.write(Save.AUTOSAVE_SLOT)
	Log.info(&"main", "return_to_main_menu", {turn = GameState.turn})
	if _is_test_run():
		return
	get_tree().change_scene_to_file(START_SCENE)

# ---- 破产预警 / Game Over (经济系统设计 §4.2) ---------------------------

## resolve 相位每周 cash<0 都会 emit bankruptcy_warning。跨过预警阈值且尚未濒临
## limit 时弹一次"游戏将结束"提醒; cash 回正后 (新一段赤字 streak<warn) 自动复位,
## 下一段危机会重新提醒。
func _on_bankruptcy_warning(reason: StringName, streak: int, _threshold: int) -> void:
	_request_refresh()
	if reason != &"cash_negative":
		return  # 深度线 (cash_too_deep) 直接走 triggered, 不在这里弹预警
	if streak < EconomySystem.BANKRUPTCY_WARN_STREAK:
		_bankruptcy_warned = false
		return
	if streak >= EconomySystem.BANKRUPTCY_STREAK_LIMIT:
		return  # 本周即 game over, 交给 _on_bankruptcy_triggered
	if _bankruptcy_warned or _game_over_shown:
		return
	_bankruptcy_warned = true
	_show_bankruptcy_warning_dialog(streak)

func _on_bankruptcy_triggered(reason: StringName) -> void:
	_request_refresh()
	_show_game_over_dialog(reason)

func _show_bankruptcy_warning_dialog(streak: int) -> void:
	var dlg := AcceptDialog.new()
	dlg.title = tr("BANKRUPTCY_WARN_TITLE")
	dlg.dialog_text = tr("BANKRUPTCY_WARN_BODY") % [
		streak, EconomySystem.BANKRUPTCY_STREAK_LIMIT]
	dlg.dialog_autowrap = true
	dlg.get_ok_button().text = tr("ACTION_OK")  # 否则是 Godot 默认英文 "OK"
	# 撑宽, 否则窄到把标题"破产预警"裁成"破产预"。
	dlg.min_size = Vector2i(460, 150)
	dlg.confirmed.connect(dlg.queue_free)
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered()

## 终局: 弹一次 Game Over 结算弹窗。确认 → 删 autosave (死局不可"继续") → 起始页。
## 系统层只发 bankruptcy_triggered, 切场景在这里 (headless 测试下跳过)。
func _show_game_over_dialog(reason: StringName) -> void:
	if _game_over_shown:
		return
	_game_over_shown = true
	Log.info(&"main", "game_over", {
		reason = reason, turn = GameState.turn, cash = GameState.cash})
	var dlg := AcceptDialog.new()
	dlg.title = tr("GAMEOVER_TITLE")
	dlg.dialog_text = tr("GAMEOVER_BODY") % [
		GameState.turn, _format_money(GameState.cash), _gameover_reason_text(reason)]
	dlg.dialog_autowrap = true
	dlg.exclusive = true
	dlg.min_size = Vector2i(520, 180)
	dlg.get_ok_button().text = tr("GAMEOVER_OK")
	dlg.confirmed.connect(_on_game_over_confirmed, CONNECT_ONE_SHOT)
	dlg.canceled.connect(_on_game_over_confirmed, CONNECT_ONE_SHOT)
	add_child(dlg)
	dlg.popup_centered()

func _on_game_over_confirmed() -> void:
	Save.delete_slot(Save.AUTOSAVE_SLOT)
	Log.info(&"main", "game_over_return_menu", {turn = GameState.turn})
	if _is_test_run():
		return
	get_tree().change_scene_to_file(START_SCENE)

func _gameover_reason_text(reason: StringName) -> String:
	if reason == &"cash_too_deep":
		return tr("GAMEOVER_REASON_DEEP")
	return tr("GAMEOVER_REASON_NEGATIVE")

# ---- low-level UI helpers -----------------------------------------------

func _add_stat_chip(parent: Control, label_text: String, value_text: String,
		delta_text: String = "") -> Control:
	var chip: Control = StatChipScene.instantiate()
	chip.custom_minimum_size = Vector2(164.0, 0.0)
	parent.add_child(chip)
	if delta_text.is_empty():
		chip.set_data(label_text, value_text, NAN, "")
	else:
		chip.set_data(label_text, value_text, 0.0, delta_text)
	return chip

func _make_surface_panel(role: StringName = &"") -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	panel.add_theme_stylebox_override(&"panel", _make_surface_style())
	if role != &"":
		panel.set_meta(&"ui_role", role)
	return panel

func _make_surface_style(bg: Color = UITheme.BG_SURFACE) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = UITheme.BORDER_SUBTLE
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(UITheme.R_MD)
	sb.content_margin_left = UITheme.S_3
	sb.content_margin_right = UITheme.S_3
	sb.content_margin_top = UITheme.S_3
	sb.content_margin_bottom = UITheme.S_3
	return sb

func _make_hint_row(text: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", UITheme.S_2)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var marker := Label.new()
	marker.text = "→"
	marker.add_theme_font_override(&"font", UITheme.get_ui_font_bold())
	marker.add_theme_color_override(&"font_color", UITheme.ACCENT_INFO)
	marker.custom_minimum_size = Vector2(18.0, 0.0)
	row.add_child(marker)
	var body := _label(text)
	body.add_theme_color_override(&"font_color", UITheme.TEXT_PRIMARY)
	row.add_child(body)
	return row

func _make_key_value_table(rows: Array, role: StringName) -> Control:
	var panel := _make_surface_panel(role)
	panel.custom_minimum_size.x = float(UITheme.LIST_MAX_W)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override(&"h_separation", UITheme.S_4)
	grid.add_theme_constant_override(&"v_separation", UITheme.S_2)
	panel.add_child(grid)
	for row in rows:
		var label_text := String(row.get("label", ""))
		var value_text := String(row.get("value", ""))
		grid.add_child(_table_cell(label_text, 112.0, HORIZONTAL_ALIGNMENT_LEFT,
			UITheme.TEXT_SECONDARY, true))
		grid.add_child(_table_cell(value_text, 540.0, HORIZONTAL_ALIGNMENT_LEFT,
			UITheme.TEXT_PRIMARY))
	return panel

func _make_ledger_detail_table(title: String, entries: Dictionary, is_income: bool,
		subtotal: int, role: StringName) -> Control:
	var panel := _make_surface_panel(role)
	panel.custom_minimum_size.x = 340.0
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", UITheme.S_2)
	panel.add_child(col)

	var title_lbl := _table_cell(title, 304.0, HORIZONTAL_ALIGNMENT_LEFT,
		UITheme.TEXT_PRIMARY, true)
	title_lbl.add_theme_font_size_override(&"font_size", UITheme.FS_MD)
	col.add_child(title_lbl)
	col.add_child(_make_two_col_row(tr("ECO_TABLE_CATEGORY"), tr("ECO_TABLE_AMOUNT"),
		UITheme.TEXT_SECONDARY, true, true))

	var amount_color := UITheme.ACCENT_PRIMARY if is_income else UITheme.ACCENT_DANGER
	var sign := "+" if is_income else "-"
	var empty_text := tr("ECO_NO_INCOME") if is_income else tr("ECO_NO_EXPENSE")
	if entries.is_empty():
		col.add_child(_make_two_col_row(empty_text.strip_edges(), "",
			UITheme.TEXT_SECONDARY))
	else:
		for k in _sorted_ledger_category_keys(entries):
			# k 是 ECO_CAT_* 语义 key (账本分组用), 显示时 tr 成当前语言。
			col.add_child(_make_two_col_row(tr(k),
				"%s$%s" % [sign, _format_money(_ledger_category_amount(entries, k))],
				amount_color))
	col.add_child(HSeparator.new())
	col.add_child(_make_two_col_row(tr("ECO_TABLE_SUBTOTAL"),
		"%s$%s" % [sign, _format_money(subtotal)], amount_color, true))
	return panel

func _make_two_col_row(left_text: String, right_text: String,
		right_color: Color = UITheme.TEXT_PRIMARY, bold: bool = false,
		header: bool = false) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", UITheme.S_3)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if header:
		var bg := PanelContainer.new()
		bg.add_theme_stylebox_override(&"panel", _make_surface_style(UITheme.BG_ELEVATED))
		row.add_child(_table_cell(left_text, 164.0, HORIZONTAL_ALIGNMENT_LEFT,
			UITheme.TEXT_SECONDARY, true))
		row.add_child(_table_cell(right_text, 116.0, HORIZONTAL_ALIGNMENT_RIGHT,
			UITheme.TEXT_SECONDARY, true))
		bg.add_child(row)
		return bg
	row.add_child(_table_cell(left_text, 164.0, HORIZONTAL_ALIGNMENT_LEFT,
		UITheme.TEXT_PRIMARY if not header else UITheme.TEXT_SECONDARY, bold))
	row.add_child(_table_cell(right_text, 116.0, HORIZONTAL_ALIGNMENT_RIGHT,
		right_color, bold))
	return row

func _table_cell(text: String, width: float,
		align: int = HORIZONTAL_ALIGNMENT_LEFT,
		color: Color = UITheme.TEXT_PRIMARY,
		bold: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(width, 24.0)
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override(&"font_size", UITheme.FS_BASE)
	l.add_theme_color_override(&"font_color", color)
	if bold:
		l.add_theme_font_override(&"font", UITheme.get_ui_font_bold())
	return l

func _make_section(text: String) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", UITheme.S_1)
	var l := Label.new()
	l.text = text
	l.add_theme_font_override(&"font", UITheme.get_ui_font_bold())
	l.add_theme_font_size_override(&"font_size", UITheme.FS_LG)
	l.add_theme_color_override(&"font_color", UITheme.TEXT_PRIMARY)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(l)
	col.add_child(HSeparator.new())
	return col

func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override(&"font_size", UITheme.FS_BASE)
	l.add_theme_color_override(&"font_color", UITheme.TEXT_PRIMARY)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l

func _dim_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override(&"font_size", UITheme.FS_SM)
	l.add_theme_color_override(&"font_color", UITheme.TEXT_SECONDARY)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l

func _make_button(label: String, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.text = label
	UITheme.apply_button_variant(b, &"secondary")
	b.pressed.connect(on_pressed)
	return b

func _clear(node: Node) -> void:
	for c in node.get_children():
		c.queue_free()

func _call(cmd: StringName, payload: Dictionary, label: String) -> void:
	var r: Dictionary = CommandBus.send(cmd, payload)
	if r.ok:
		_set_status(tr("CALL_OK") % label)
	else:
		_set_status(tr("CALL_FAILED") % [label, String(r.get(&"error", &"unknown"))], true)

func _report(r: Dictionary, label: String) -> void:
	if r.ok:
		var turns: int = int(r.get(&"total_weeks", 0))
		_set_status(tr("REPORT_STARTED") % [label, String(r.get(&"task_id", &"")), turns])
	else:
		_set_status(tr("CALL_FAILED") % [label, String(r.get(&"error", &"unknown"))], true)

func _set_status(text: String, is_error: bool = false) -> void:
	_status_label.text = text
	_status_label.add_theme_color_override(
		&"font_color", UITheme.ACCENT_DANGER if is_error else UITheme.TEXT_SECONDARY)

## Pretty-print per-token price as "$X/M tokens" since real prices are in the
## 1e-7..1e-5 USD range — too small to display meaningfully as raw $/token.
func _format_per_token_price(p: float) -> String:
	if p <= 0.0:
		return tr("FMT_FREE")
	var per_million: float = p * 1_000_000.0
	if per_million >= 1.0:
		return "$%.2f/M tok" % per_million
	return "$%.3f/M tok" % per_million

func _format_flops_per_token(fpt: float) -> String:
	if fpt <= 0.0:
		return tr("FMT_UNKNOWN_FLOPS")
	if fpt >= 1.0e12:
		return "%.3f TFLOPs/tok" % (fpt / 1.0e12)
	if fpt >= 1.0e9:
		return "%.1f GFLOPs/tok" % (fpt / 1.0e9)
	if fpt >= 1.0e6:
		return "%.1f MFLOPs/tok" % (fpt / 1.0e6)
	return "%.0f FLOPs/tok" % fpt

func _format_money(n) -> String:
	var v: int = int(n)
	var s: String = str(absi(v))
	var out: String = ""
	var i: int = s.length()
	while i > 3:
		out = "," + s.substr(i - 3, 3) + out
		i -= 3
	out = s.substr(0, i) + out
	return ("-" + out) if v < 0 else out

const SECONDS_PER_WEEK: int = 604_800

# 把"周度 tokens" 换成"t/s + 周度 tokens" 给玩家直观看。1 turn = 1 week,
# `GameState.token_demand` / `api_demand_lost` / capacity 都是 tokens/周
# (见 design/营收系统设计.md §4)。t/s 与周量级都走 UITheme 统一格式化。
func _format_tps(tokens_per_week: int) -> String:
	if tokens_per_week <= 0:
		return "0 t/s"
	var tps: float = float(tokens_per_week) / float(SECONDS_PER_WEEK)
	return tr("FMT_TPS") % [
		UITheme.format_tps(tps), UITheme.format_tokens(tokens_per_week)]

# UI capacity 直接走 MonetizationSystem.compute_capacity_for_model — 它是
# 营收结算的唯一来源, UI 不允许在这里重写公式 (见 design/营收系统设计.md §3.1)。
# 历史事故: 旧版用 SECONDS_PER_MONTH + 又乘了一次 engineering 树乘数 (v4 PR-B
# 后该乘数已下沉到 dc.serving_tokens_per_sec), 导致 util_pct 显示只有真实值
# 的 ~23%, 玩家看不出算力已饱和, 营收按实际截断却没有警告。
func _capacity_for_model(m) -> int:
	return int(MonetizationSystem.compute_capacity_for_model(m))

# v3: deploy 按钮上的 "→ X tok/s" 预览; 调 infra.preview_deploy_capacity.
# v9 PR-I: 二选一传 model_id 或 release_id (OS NPC pretrain release).
func _preview_tps_label(dc_id: StringName, model_id: StringName, release_id: StringName) -> String:
	var args: Dictionary = {dc_id = dc_id}
	if model_id != &"":
		args[&"model_id"] = model_id
	elif release_id != &"":
		args[&"release_id"] = release_id
	else:
		return ""
	var r: Dictionary = CommandBus.send(&"infra.preview_deploy_capacity", args)
	if not r.get(&"ok", false):
		return ""
	var tps: float = float(r.get(&"tokens_per_sec", 0.0))
	if tps <= 0.0:
		return "(0 t/s)"
	return "(→ %s)" % UITheme.format_tps(tps)

# 与 UserSystem._tokens_per_user_for 一致但更短: 直接读 .tres, 失败 fallback.
func _tokens_per_user_for_type(type_id: StringName) -> int:
	if type_id == &"api":
		return 0
	var path := "res://resources/data/products/types/%s.tres" % String(type_id)
	if ResourceLoader.exists(path):
		var res := load(path)
		if res != null and "tokens_per_user_per_month" in res:
			return int(res.tokens_per_user_per_month)
	return 0

func _model_api_price(model_id: StringName) -> float:
	for m in GameState.models:
		if m.id == model_id:
			return float(m.per_token_price)
	return 0.0

# 该 api 产品的 t/s demand: api_token_demand[m] 在多 api 共绑时 1/N 等分.
func _per_api_product_demand(api_prod) -> int:
	var total: int = int(GameState.api_token_demand.get(api_prod.bound_model_id, 0))
	var n: int = 0
	for p in GameState.products:
		if p.type == &"api" and p.bound_model_id == api_prod.bound_model_id:
			n += 1
	if n == 0:
		return 0
	return int(floor(float(total) / float(n)))

func _sum_dict(d: Dictionary) -> int:
	var s: int = 0
	for v in d.values():
		s += int(v)
	return s

func _published_count() -> int:
	var n: int = 0
	for m in GameState.models:
		if m.status == &"published":
			n += 1
	return n

func _first_published_model() -> StringName:
	for m in GameState.models:
		if m.status == &"published":
			return m.id
	return &""

func _first_published_model_for_type(type_id: StringName) -> StringName:
	var spec: ProductTypeSpec = ProductSystem.get_type_spec(type_id)
	if spec == null:
		return &""
	# §0bis api 特殊: 找一个还没开 api 的 published 模型, 否则 duplicate_api_product.
	if type_id == &"api":
		return _first_published_model_without_api()
	for m in GameState.models:
		if m.status == &"published" and _model_meets_product_type(m, spec):
			return m.id
	return &""

# §0bis: 选第一个 published 但未开 api 产品的模型.
func _first_published_model_without_api() -> StringName:
	for m in GameState.models:
		if m.status != &"published":
			continue
		var has_api: bool = false
		for prod in GameState.products:
			if prod.type == &"api" and prod.bound_model_id == m.id:
				has_api = true
				break
		if not has_api:
			return m.id
	return &""

func _model_meets_product_type(m, spec: ProductTypeSpec) -> bool:
	if spec.application_node_required != &"":
		var unlocked: Dictionary = CommandBus.send(&"tech.is_unlocked", {
			tree = &"application",
			node_id = spec.application_node_required,
		})
		if not bool(unlocked.get(&"unlocked", false)):
			return false
	for axis in spec.unlock_thresholds.keys():
		if float(m.capability.get(axis, 0.0)) < float(spec.unlock_thresholds[axis]):
			return false
	return true

func _first_unlocked_dataset() -> StringName:
	for ds in GameState.datasets:
		if ds.locked_by_task_id == &"":
			return ds.id
	return &""

func _model_capability_text(m) -> String:
	var caps: Dictionary = m.displayable_capability() if m.has_method("displayable_capability") else m.capability
	if caps.is_empty():
		return tr("MODEL_CAP_NA")
	var out := _caps_str(caps)
	if bool(m.capability_stale):
		out += tr("MODEL_EVAL_STALE_SUFFIX")
	return out

func _serving_dcs_for_model(model_id: StringName) -> Array:
	var out: Array = []
	for dc in GameState.datacenters:
		if dc.deployed_model_id == model_id:
			out.append(String(dc.id))
	return out

func _serving_target_display(dc) -> String:
	if dc.serving_target_kind == &"open_source_model":
		return tr("DC_SERVE_OS_PREFIX") + " " + _os_model_display_name(dc.serving_target_id)
	if dc.serving_target_kind == &"owned_model" and dc.serving_target_id != &"":
		return _model_display_name(dc.serving_target_id)
	if dc.deployed_model_id != &"":
		return _model_display_name(dc.deployed_model_id)
	return String(dc.serving_target_id)

func _products_for_model(model_id: StringName) -> Array:
	var out: Array = []
	for p in GameState.products:
		if p.bound_model_id == model_id:
			out.append(String(p.display_name))
	return out

## v2 (2026-05): Templates are now split into pretrain/posttrain Resource
## subclasses under resources/data/datasets/{pretrain,posttrain}/{open_source,
## purchased}/. Source-of-truth lookup is `dataset.list_market`, which also
## filters by released_at_week and already-owned. Returns plain dicts (NOT
## Resource instances) shaped like the legacy DatasetTemplate fields.
func _load_dataset_templates() -> Array:
	var r: Dictionary = CommandBus.send(&"dataset.list_market", {})
	if not r.ok:
		return []
	var items: Array = r.items.duplicate()
	items.sort_custom(func(a, b): return String(a.display_name) < String(b.display_name))
	return items

func _owns_dataset(template_id: StringName) -> bool:
	for ds in GameState.datasets:
		if ds.id == template_id:
			return true
	return false

func _facility_ids_by_tier() -> Array:
	var ids: Array = []
	for id in InfraSystem.FACILITY_SPECS.keys():
		ids.append(StringName(id))
	ids.sort_custom(func(a, b):
		var sa: FacilitySpec = _load_facility_spec(a)
		var sb: FacilitySpec = _load_facility_spec(b)
		var ta: int = sa.tier_index if sa != null else 999
		var tb: int = sb.tier_index if sb != null else 999
		return ta < tb)
	return ids

func _released_gpu_ids() -> Array:
	var ids: Array = []
	for id in InfraSystem.GPU_SPECS.keys():
		var gpu: GPUSpec = _load_gpu_spec(StringName(id))
		if gpu != null and gpu.release_turn <= GameState.turn:
			ids.append(StringName(id))
	ids.sort_custom(func(a, b):
		var ga: GPUSpec = _load_gpu_spec(a)
		var gb: GPUSpec = _load_gpu_spec(b)
		var ra: int = ga.release_turn if ga != null else 99999
		var rb: int = gb.release_turn if gb != null else 99999
		if ra == rb:
			return String(a) < String(b)
		return ra < rb)
	return ids

func _load_facility_spec(spec_id: StringName) -> FacilitySpec:
	var path: String = InfraSystem.FACILITY_SPECS.get(spec_id, "")
	if path == "":
		return null
	var res := load(path)
	if res is FacilitySpec:
		return res
	return null

func _load_gpu_spec(gpu_id: StringName) -> GPUSpec:
	var path: String = InfraSystem.GPU_SPECS.get(gpu_id, "")
	if path == "":
		return null
	var res := load(path)
	if res is GPUSpec:
		return res
	return null

func _load_power_spec(power_id: StringName) -> PowerSupplySpec:
	var path: String = InfraSystem.POWER_SPECS.get(power_id, "")
	if path == "":
		return null
	var res := load(path)
	if res is PowerSupplySpec:
		return res
	return null

# 设施/GPU/供电的 display_name 是 .tres 内容 (源串当 key, 见 国际化设计 §2bis);
# tr() 在 en 下取 content 译文, 非内容串原样返回。
func _facility_display_name(spec_id: StringName) -> String:
	var spec: FacilitySpec = _load_facility_spec(spec_id)
	return tr(spec.display_name) if spec != null else String(spec_id)

# 建筑图标路径 (infra view 卡片头像用); 无 spec / 未配图 → 空串 (view 走回退)。
# 云租用 DC 无 facility (spec_id 为空) → 用云算力专属图标, 而不是机房档位图。
const CLOUD_FACILITY_ICON := "res://assets/sprites/ui/infra/facility-cloud.png"

func _facility_icon_path(spec_id: StringName) -> String:
	if String(spec_id) == "":
		return CLOUD_FACILITY_ICON
	var spec: FacilitySpec = _load_facility_spec(spec_id)
	return spec.icon_path if spec != null else ""

func _gpu_display_name(gpu_id: StringName) -> String:
	var spec: GPUSpec = _load_gpu_spec(gpu_id)
	return tr(spec.display_name) if spec != null else String(gpu_id)

func _power_display_name(power_id: StringName) -> String:
	var spec: PowerSupplySpec = _load_power_spec(power_id)
	return tr(spec.display_name) if spec != null else String(power_id)

func _power_summary() -> String:
	var parts: Array = []
	for power_id in POWER_ORDER:
		var spec: PowerSupplySpec = _load_power_spec(power_id)
		if spec != null:
			parts.append(tr("DC_POWER_DETAIL") % [
				spec.display_name,
				_format_money(spec.weekly_cost_per_card),
				spec.efficiency_modifier,
			])
	return " / ".join(parts)

func _os_model_display_name(release_id: StringName) -> String:
	# v9 PR-I: OS "model" id is now an NPC release id; resolve via MarketSystem.
	var found: Dictionary = MarketSystem.find_release(release_id)
	if found.get(&"ok", false):
		return String(found.release.display_name)
	return String(release_id)

func _product_type_display_name(type_id: StringName) -> String:
	var spec: ProductTypeSpec = ProductSystem.get_type_spec(type_id)
	return spec.display_name if spec != null else String(type_id)

func _tree_display_name(tree: StringName) -> String:
	match tree:
		&"arch": return tr("TECH_TREE_ARCH")
		&"attention": return tr("TECH_TREE_ATTENTION")
		&"loss": return tr("TECH_TREE_LOSS")
		&"engineering": return tr("TECH_TREE_ENGINEERING")
		&"application": return tr("TECH_TREE_APPLICATION")
		&"context": return tr("TECH_TREE_CONTEXT")
		_: return String(tree)

func _tech_node_display(node: TechNode, fallback_id: StringName) -> String:
	if node != null and node.display_name != "":
		# tr() 取 content 译文 (源串当 key); _sanitize 再做 zh-only 的术语本地化。
		return _sanitize_tech_text(tr(node.display_name))
	return String(fallback_id)

func _tech_node_effects(node: TechNode) -> String:
	if node != null and node.effects_summary != "":
		return _sanitize_tech_text(tr(node.effects_summary))
	return tr("TECH_NO_EFFECT")

func _sanitize_tech_text(text: String) -> String:
	var out := text
	var start := out.find(" (~")
	while start != -1:
		var end := out.find(")", start)
		if end == -1:
			break
		out = out.substr(0, start) + out.substr(end + 1)
		start = out.find(" (~")
	# 下面这组英文术语→中文的替换只在中文 locale 做; en 下保留英文 (content 译文已是英文)。
	if not TranslationServer.get_locale().begins_with("zh"):
		return out.strip_edges()
	out = out.replace("multimodal_method=cross_train", "跨模态训练")
	out = out.replace("multimodal_method=diffusion_ar", "扩散自回归")
	out = out.replace("multimodal_method=pixel_ar", "像素自回归")
	out = out.replace("multimodal_method=native_ar", "原生多模态自回归")
	out = out.replace("Dense Scaling", "稠密扩展")
	out = out.replace("MoE Routing", "专家路由")
	out = out.replace("Sparse MoE", "稀疏 MoE")
	out = out.replace("BERT", "Bee")
	out = out.replace("RoBERTa", "Raven")
	out = out.replace("CLIP 风格", "对齐风格")
	out = out.replace("Diffusion Transformer (DiT)", "扩散 Transformer")
	out = out.replace("ELECTRA", "Elm")
	out = out.replace("DeBERTa", "Deodar")
	out = out.replace("image 输出", "图像输出")
	out = out.replace("audio", "音频")
	out = out.replace("capability", "能力")
	out = out.replace("agent", "智能体")
	return out.strip_edges()

func _caps_str(d: Dictionary) -> String:
	var parts: Array = []
	for k in d.keys():
		parts.append("%s %d" % [String(k), int(d[k])])
	return "  ".join(parts)

func _sn_join(arr: Array) -> String:
	var parts: Array = []
	for v in arr:
		parts.append(String(v))
	return ",".join(parts)

func _load_card(template_id: StringName):
	return EventSystem._load_card(template_id)
