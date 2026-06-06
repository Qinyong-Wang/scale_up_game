extends GutTest

## Main HUD tab structure & button placement.
## Per design/任务系统设计.md §5.1 + 研究系统设计.md §5.1 + 数据集系统设计.md §5.1.
##
## 约定:
##   - 「模型」tab 是 ResearchSystem 的入口, 含 "训练新模型..." (打开 PretrainDialog).
##   - 「数据」tab 含 "开始采集..." 启动 data_collection task.
##   - 「任务」tab 只展示进度 / 取消, 不再有 "启动新任务" 区块.

const Main := preload("res://scenes/main/main.gd")
const NewProductDialog := preload("res://scenes/ui/new_product_dialog/new_product_dialog.gd")
const StatChipScript := preload("res://scenes/ui/components/stat_chip/stat_chip.gd")

# v9 PR-I: OS models come from OS NPC pretrain releases. Tests use Wolf-3 (turn 330,
# 405B dense, capability g=65/c=52/r=55/m=35/a=15) as the canonical download target.
const _OS_TEST_RELEASE: StringName = &"release_wolf_3"
const _OS_TEST_TURN: int = 335

var _hud

func before_each() -> void:
	GameState.reset()
	# v9 PR-I: jump turn past the first OS pretrain release so download_open_source
	# succeeds. Most tests in this file publish wolf_os to set up a product/HUD scenario.
	GameState.turn = _OS_TEST_TURN
	# Per design/招聘系统设计.md §5.4: evaluate 强制 eval_lead; main HUD 上点"开始评估"
	# 会自动取 idle eval_lead 绑给 task. 给 happy-path 测试 seed 一个.
	_seed_zero_eval_lead()
	_hud = Main.new()
	add_child_autofree(_hud)
	# Force _ready and let _refresh populate tabs.
	await get_tree().process_frame

func _seed_zero_eval_lead() -> StringName:
	var l := Lead.new()
	l.id = &"lead_eval_zero_hud"
	l.specialty = &"eval_lead"
	l.level = &"C"
	l.ability = 0.0
	l.signing_fee = 0
	l.weekly_salary = 0
	GameState.leads.append(l)
	return l.id

func _tab_titles() -> PackedStringArray:
	var out := PackedStringArray()
	var tabs: TabContainer = _hud._tabs
	for i in range(tabs.get_tab_count()):
		out.append(tabs.get_tab_title(i))
	return out

func _all_button_texts(root: Node) -> PackedStringArray:
	var out := PackedStringArray()
	for child in root.get_children():
		if child is Button:
			out.append(child.text)
		out.append_array(_all_button_texts(child))
	return out

func _all_label_texts(root: Node) -> PackedStringArray:
	var out := PackedStringArray()
	for child in root.get_children():
		if child is Label:
			out.append(child.text)
		out.append_array(_all_label_texts(child))
	return out

func _has_text_containing(texts: PackedStringArray, needle: String) -> bool:
	for t in texts:
		if String(t).find(needle) != -1:
			return true
	return false

func _all_nodes_with_meta(root: Node, key: StringName, value) -> Array:
	var out: Array = []
	for child in root.get_children():
		if child.has_meta(key) and child.get_meta(key) == value:
			out.append(child)
		out.append_array(_all_nodes_with_meta(child, key, value))
	return out

func _all_nodes_with_script(root: Node, script: Script) -> Array:
	var out: Array = []
	for child in root.get_children():
		if child.get_script() == script:
			out.append(child)
		out.append_array(_all_nodes_with_script(child, script))
	return out

func _first_label_exact(root: Node, text: String) -> Label:
	for child in root.get_children():
		if child is Label and String(child.text) == text:
			return child
		var nested := _first_label_exact(child, text)
		if nested != null:
			return nested
	return null

func _first_button_containing(root: Node, needle: String) -> Button:
	for child in root.get_children():
		if child is Button and String(child.text).find(needle) != -1:
			return child
		var nested := _first_button_containing(child, needle)
		if nested != null:
			return nested
	return null

func test_default_theme_installs_cjk_font_for_new_controls() -> void:
	var label := Label.new()
	var expected_font: Font = UITheme.get_ui_font()
	var actual_font: Font = label.get_theme_font(&"font")
	assert_not_null(expected_font, "UITheme should load the development CJK font")
	assert_not_null(actual_font, "fresh Label should resolve a theme font")
	assert_eq(actual_font.get_font_name(), expected_font.get_font_name(),
		"fresh controls should use UITheme font before text is assigned")
	label.free()

func test_tab_titles_use_model_not_research() -> void:
	var titles := _tab_titles()
	assert_does_not_have(titles, "研究", "tab 'research' renamed to 'model'")
	assert_has(titles, "模型", "model tab present")

func test_top_bar_uses_weekly_turn_label() -> void:
	assert_true(String(_hud._turn_label.text).find("周") != -1,
		"turn label should present turns as weeks")

# ---- 顶栏设置入口 (国际化设计 §11.0) ------------------------------------

func test_top_bar_has_settings_button() -> void:
	# 游戏内也要能开设置 (切语言 / 自动存档), 不必退回起始页。
	var btns := _all_button_texts(_hud._top_bar)
	assert_true(_has_text_containing(btns, "设置"),
		"游戏内顶栏应有「设置」按钮")

func test_settings_button_opens_settings_dialog() -> void:
	var btn := _first_button_containing(_hud._top_bar, "设置")
	assert_not_null(btn, "顶栏应有设置按钮")
	btn.emit_signal("pressed")
	await get_tree().process_frame
	# SettingsDialog 作为 HUD 子节点弹出, 标题为 SETTINGS_TITLE。
	var found := false
	for c in _hud.get_children():
		if c is AcceptDialog and String(c.title) == tr("SETTINGS_TITLE"):
			found = true
			break
	assert_true(found, "点击设置按钮应弹出 SettingsDialog")

func test_model_tab_has_pretrain_launcher() -> void:
	var btns := _all_button_texts(_hud._tab_research)
	var found_pretrain := false
	for t in btns:
		if String(t).find("训练新模型") != -1 or String(t).find("启动预训练") != -1:
			found_pretrain = true
			break
	assert_true(found_pretrain, "model tab has a pretrain launcher button")

func test_dataset_tab_has_collection_launcher() -> void:
	var btns := _all_button_texts(_hud._tab_dataset)
	var found := false
	for t in btns:
		if String(t).find("采集") != -1:
			found = true
			break
	assert_true(found, "dataset tab has a data-collection launcher button")

func test_tasks_tab_has_no_launch_section() -> void:
	# The tasks tab should not contain a launcher button (启动 / 采集 / 后训练).
	# It only carries progress bars + a "取消..." button per task.
	var btns := _all_button_texts(_hud._tab_tasks)
	var offenders := PackedStringArray()
	for t in btns:
		var s := String(t)
		if s.find("启动预训练") != -1 \
				or s.find("训练新模型") != -1 \
				or s.find("数据采集") != -1 \
				or s.find("后训练") != -1:
			offenders.append(s)
	assert_eq(offenders.size(), 0,
		"tasks tab should not host launch buttons; found %s" % str(offenders))

func test_model_tab_exposes_evaluate_for_unpublished_models() -> void:
	CommandBus.send(&"research.add_model", {
		arch = &"ant_v1",
		size_params = 120.0,
		flops_per_token = 240_000_000.0,
		input_modalities = [&"text"],
		output_modalities = [&"text"],
		dataset_ids = [],
		display_name = "Test Model",
	})
	_hud._refresh()
	var btn := _first_button_containing(_hud._tab_research, "开始评估")
	assert_not_null(btn, "pretrained/posttrained model cards expose evaluate")
	btn.emit_signal("pressed")
	await get_tree().process_frame
	assert_eq(GameState.active_tasks.size(), 1)
	assert_eq(GameState.active_tasks[0].template_id, &"evaluate_general")

func test_dataset_tab_scans_all_dataset_templates() -> void:
	var labels := _all_label_texts(_hud._tab_dataset)
	assert_true(_has_text_containing(labels, "Math Reasoning Set v1"),
		"dataset market is generated from resources/data/datasets")
	assert_true(_has_text_containing(labels, "Image Corpus v1"),
		"dataset market includes open-source templates beyond the old hardcoded pair")

func test_infra_tab_uses_resource_display_names() -> void:
	# New UI: facility list replaced by "新建数据中心..." button + dialog.
	var btns := _all_button_texts(_hud._tab_infra)
	assert_true(_has_text_containing(btns, "新建数据中心"),
		"infra tab has new-datacenter entry-point button")
	# After renting + buying GPUs the DC card label shows facility & GPU names.
	CommandBus.send(&"infra.rent_facility", {
		facility_spec_id = &"facility_solo",
		power_supply_id = &"grid",
	})
	CommandBus.send(&"infra.buy_gpus", {
		dc_id = GameState.datacenters[0].id,
		gpu_id = &"cypress_t0",
		count = 1,
	})
	_hud._refresh()
	var labels := _all_label_texts(_hud._tab_infra)
	assert_true(_has_text_containing(labels, "单卡桌面"),
		"DC card label shows FacilitySpec.display_name")
	assert_true(_has_text_containing(labels, "Cypress T0"),
		"DC card label shows GPUSpec.display_name")

func test_tech_tab_shows_effect_summary() -> void:
	var labels := _all_label_texts(_hud._tab_tech)
	assert_true(_has_text_containing(labels, "训练 +20%"),
		"available tech nodes show effects_summary, not only internal ids")

func test_product_tab_has_single_create_entry_button() -> void:
	# 新设计 (NewProductDialog): "+ 创建产品..." 是唯一入口, 不再每类型一个按钮.
	var dl: Dictionary = CommandBus.send(&"research.download_open_source",
		{release_id = _OS_TEST_RELEASE})
	assert_true(dl.ok)
	CommandBus.send(&"research.publish_model", {
		model_id = dl.model_id, is_open_source = false, per_token_price = 0.000002})
	_hud._refresh()
	var btns := _all_button_texts(_hud._tab_product)
	assert_true(_has_text_containing(btns, "创建产品"),
		"产品 tab 应有 '+ 创建产品...' 入口按钮")
	# 旧版的 "创建 Chatbot" / "创建 Agent" 按钮不再存在 (移到对话框里).
	assert_false(_has_text_containing(btns, "创建 Chatbot"),
		"旧的 per-type 按钮已替换为对话框, 不应再出现")

func test_new_product_dialog_compiles_and_instantiates() -> void:
	var dlg := NewProductDialog.new()
	add_child_autofree(dlg)
	await get_tree().process_frame
	assert_eq(dlg.title, "新建产品")

func test_new_product_dialog_emits_created_signal() -> void:
	var dl: Dictionary = CommandBus.send(&"research.download_open_source",
		{release_id = _OS_TEST_RELEASE})
	assert_true(dl.ok)
	CommandBus.send(&"research.publish_model", {
		model_id = dl.model_id, is_open_source = false, per_token_price = 0.000002})
	var dlg := NewProductDialog.new()
	add_child_autofree(dlg)
	watch_signals(dlg)
	dlg.setup_create()
	await get_tree().process_frame
	dlg._name_edit.text = "Signal Chat"
	dlg._confirm_create()
	assert_signal_emitted(dlg, "product_created")
	var p: Array = get_signal_parameters(dlg, "product_created")
	assert_ne(String(p[0]), "", "created signal should carry product_id")

func test_product_tab_shows_compute_pool_section_after_publish() -> void:
	# §0bis: 产品 tab 在有 published 模型 + 绑定产品时, 显示"算力池"区块.
	var dl: Dictionary = CommandBus.send(&"research.download_open_source",
		{release_id = _OS_TEST_RELEASE})
	assert_true(dl.ok)
	CommandBus.send(&"research.publish_model", {
		model_id = dl.model_id, is_open_source = false, per_token_price = 0.000002})
	# publish 后 ProductSystem 自动建 api 产品, 算力池区块应当出现并列出该模型.
	_hud._refresh()
	var labels := _all_label_texts(_hud._tab_product)
	assert_true(_has_text_containing(labels, "算力池"),
		"产品 tab 应显示 '算力池 (按模型)' 区块标题")
	# api 产品应以 [API] 标签显示.
	assert_true(_has_text_containing(labels, "[API]"),
		"自动创建的 api 产品应在产品列表中以 [API] 显示")

func test_deploy_public_open_source_model_shows_api_and_price_edit_from_product_tab() -> void:
	var dc: Dictionary = CommandBus.send(&"infra.debug_instant_owned_dc", {
		facility_spec_id = &"facility_solo",
		gpu_id = &"cypress_t0",
	})
	assert_true(dc.ok)
	var deploy: Dictionary = CommandBus.send(&"infra.deploy_open_source_model", {
		dc_id = dc.dc_id,
		release_id = _OS_TEST_RELEASE,
	})
	assert_true(deploy.ok, "deploy public OS: %s" % str(deploy.get(&"error", &"")))
	var mid: StringName = deploy.model_id
	var m = ResearchSystem.find_model(mid)
	assert_not_null(m)
	assert_eq(m.status, &"published")
	var api_pid: StringName = &""
	for p in GameState.products:
		if p.type == &"api" and p.bound_model_id == mid:
			api_pid = p.id
			break
	assert_ne(api_pid, &"", "公共开源部署后应自动创建 API 产品")
	_hud._refresh()
	var labels := _all_label_texts(_hud._tab_product)
	assert_true(_has_text_containing(labels, "[API]"),
		"公共开源部署后的 API 应出现在产品页")
	assert_not_null(_hud._product_view)
	_hud._product_view.click_card_action_for_test(api_pid, &"edit")
	await get_tree().process_frame
	var opened_price_dialog := false
	for c in _hud.get_children():
		if c is ConfirmationDialog and String(c.title) == tr("PRICE_TITLE"):
			opened_price_dialog = true
			break
	assert_true(opened_price_dialog,
		"产品页 API 卡片的编辑动作应打开 API 单价对话框")

func test_new_product_dialog_disables_unmet_type_options() -> void:
	# 新设计 §0bis: NewProductDialog 的类型下拉里, 未达阈值的产品置灰并显示原因.
	# 用 wolf_os (general 偏低, 不够 reasoning≥50) → "agent" 应被置灰.
	const Dialog := preload("res://scenes/ui/new_product_dialog/new_product_dialog.gd")
	var dl: Dictionary = CommandBus.send(&"research.download_open_source",
		{release_id = _OS_TEST_RELEASE})
	CommandBus.send(&"research.publish_model", {
		model_id = dl.model_id, is_open_source = false, per_token_price = 0.000002})
	var dlg = Dialog.new()
	add_child_autofree(dlg)
	dlg.setup_create()
	await get_tree().process_frame
	var dropdown: OptionButton = dlg._type_dropdown
	# 找到 agent 那一项, 应当 disabled.
	var found_agent_disabled: bool = false
	var found_chatbot_enabled: bool = false
	for i in range(dropdown.item_count):
		var meta = dropdown.get_item_metadata(i)
		var text: String = dropdown.get_item_text(i)
		if meta == &"agent":
			# wolf_os 应不满足 agent (tool_use 未解锁或 reasoning<50).
			assert_true(dropdown.is_item_disabled(i),
				"agent 类型应在下拉里置灰 (locked)")
			# 锁定项的 label 应带原因摘要.
			assert_true(text.find("(") != -1 and text.find(")") != -1,
				"locked 项 label 应含括号说明原因: %s" % text)
			found_agent_disabled = true
		if meta == &"chatbot":
			# wolf_os 的 general 应过 chatbot 阈值 (general≥30).
			assert_false(dropdown.is_item_disabled(i),
				"chatbot 类型应在下拉里可选")
			found_chatbot_enabled = true
	assert_true(found_agent_disabled, "下拉应包含 agent 项")
	assert_true(found_chatbot_enabled, "下拉应包含 chatbot 项")

func test_new_product_dialog_create_defaults_price_to_guidance() -> void:
	# D-12: 创建产品时, 订阅价默认 = ProductTypeSpec.subscription_price_guidance,
	# 避免老硬编码 $99 把玩家钉死在惩罚区 (chatbot guidance 是 $20)。
	const Dialog := preload("res://scenes/ui/new_product_dialog/new_product_dialog.gd")
	var dl: Dictionary = CommandBus.send(&"research.download_open_source",
		{release_id = _OS_TEST_RELEASE})
	CommandBus.send(&"research.publish_model", {
		model_id = dl.model_id, is_open_source = false, per_token_price = 0.000002})
	var dlg = Dialog.new()
	add_child_autofree(dlg)
	dlg.setup_create()
	await get_tree().process_frame
	# 选 chatbot 类型 (guidance = 20).
	var chatbot_idx: int = -1
	for i in range(dlg._type_dropdown.item_count):
		if dlg._type_dropdown.get_item_metadata(i) == &"chatbot":
			chatbot_idx = i
			break
	assert_gt(chatbot_idx, -1)
	dlg._type_dropdown.select(chatbot_idx)
	dlg._on_type_changed()
	var spec: ProductTypeSpec = ProductSystem.get_type_spec(&"chatbot")
	assert_eq(int(dlg._price_spinbox.value), int(spec.subscription_price_guidance),
			"chatbot 默认订阅价应取 guidance, 而不是写死的 99")

func test_new_product_dialog_preview_uses_weekly_token_tps() -> void:
	# chatbot: 250k tokens/周 ÷ 604800 ≈ 0.4 t/s。旧月秒口径会显示 0.1 t/s。
	const Dialog := preload("res://scenes/ui/new_product_dialog/new_product_dialog.gd")
	var dl: Dictionary = CommandBus.send(&"research.download_open_source",
		{release_id = _OS_TEST_RELEASE})
	CommandBus.send(&"research.publish_model", {
		model_id = dl.model_id, is_open_source = false, per_token_price = 0.000002})
	var dlg = Dialog.new()
	add_child_autofree(dlg)
	dlg.setup_create()
	await get_tree().process_frame
	var chatbot_idx: int = -1
	for i in range(dlg._type_dropdown.item_count):
		if dlg._type_dropdown.get_item_metadata(i) == &"chatbot":
			chatbot_idx = i
			break
	assert_gt(chatbot_idx, -1)
	dlg._type_dropdown.select(chatbot_idx)
	dlg._on_type_changed()
	assert_true(String(dlg._preview_label.text).find("0.4 t/s") != -1,
			"新建产品预览应按每周 token 折算 t/s, 实际: %s" % dlg._preview_label.text)

func test_new_product_dialog_edit_mode_prefills_fields() -> void:
	# §0bis: setup_edit(product_id) 把表单填好, type 锁死.
	const Dialog := preload("res://scenes/ui/new_product_dialog/new_product_dialog.gd")
	var dl: Dictionary = CommandBus.send(&"research.download_open_source",
		{release_id = _OS_TEST_RELEASE})
	CommandBus.send(&"research.publish_model", {
		model_id = dl.model_id, is_open_source = false, per_token_price = 0.000002})
	# 用 product.create 显式建一个 chatbot, 拿它的 id 进 edit 模式.
	var cr: Dictionary = CommandBus.send(&"product.create", {
		type = &"chatbot", bound_model_id = dl.model_id,
		display_name = "My Chat", subscription_price = 49})
	assert_true(cr.ok, "chatbot create: %s" % str(cr))
	var pid: StringName = cr.product_id
	var dlg = Dialog.new()
	add_child_autofree(dlg)
	dlg.setup_edit(pid)
	await get_tree().process_frame
	assert_eq(dlg._name_edit.text, "My Chat", "edit 模式应填回 display_name")
	assert_eq(int(dlg._price_spinbox.value), 49, "edit 模式应填回 subscription_price")
	assert_true(dlg._type_dropdown.disabled, "edit 模式 type 下拉不可改")

func test_product_tab_pool_label_red_when_capacity_zero() -> void:
	# §0bis 视觉警告: 没部署 DC 时, 算力池 header label 应当变红 (font_color override).
	var dl: Dictionary = CommandBus.send(&"research.download_open_source",
		{release_id = _OS_TEST_RELEASE})
	CommandBus.send(&"research.publish_model", {
		model_id = dl.model_id, is_open_source = false, per_token_price = 0.000002})
	# publish 后 auto-create 了 api 产品 → 该 model 有"绑定", 进入算力池区块.
	# 但没有任何 dc 部署该 model → capacity = 0 → label 应红.
	_hud._refresh()
	# 找 _tab_product 里第一个含"容量 0 t/s"的 Label.
	var matched: Label = _find_label_containing(_hud._tab_product, "容量 0 t/s")
	assert_not_null(matched, "应当出现 capacity=0 的算力池 label")
	# Godot Label 用 font_color theme override 改色. 我们 main.gd 把它设为红.
	var col: Color = matched.get_theme_color(&"font_color")
	# 红色: r > 0.9 且 g < 0.7 (默认白色或暗色都不会满足).
	assert_gt(col.r, 0.9, "capacity=0 header 应红色 (got %s)" % str(col))
	assert_lt(col.g, 0.7, "capacity=0 header 应红色")

func _find_label_containing(root: Node, needle: String) -> Label:
	for child in root.get_children():
		if child is Label and String(child.text).find(needle) != -1:
			return child
		var nested := _find_label_containing(child, needle)
		if nested != null:
			return nested
	return null

func test_new_product_dialog_api_disabled_when_all_models_covered() -> void:
	# §0bis: 所有 published 模型已开 api 时, api 类型项置灰.
	# wolf_os 发布后 ProductSystem 会自动建 api 产品, 所以这是默认 path.
	const Dialog := preload("res://scenes/ui/new_product_dialog/new_product_dialog.gd")
	var dl: Dictionary = CommandBus.send(&"research.download_open_source",
		{release_id = _OS_TEST_RELEASE})
	CommandBus.send(&"research.publish_model", {
		model_id = dl.model_id, is_open_source = false, per_token_price = 0.000002})
	# 验证 api 产品已自动创建.
	var has_api: bool = false
	for p in GameState.products:
		if p.type == &"api":
			has_api = true
			break
	assert_true(has_api, "publish 后应有 auto-created api 产品")
	var dlg = Dialog.new()
	add_child_autofree(dlg)
	dlg.setup_create()
	await get_tree().process_frame
	var dropdown: OptionButton = dlg._type_dropdown
	for i in range(dropdown.item_count):
		if dropdown.get_item_metadata(i) == &"api":
			assert_true(dropdown.is_item_disabled(i),
				"所有 published 模型都已开 api 时, 下拉里 api 应置灰")
			return
	fail_test("下拉应包含 api 项")

func test_revenue_tab_shows_api_per_product_breakdown() -> void:
	# §0bis: 营收 tab 应展示 api_per_product 细分 (UI 需要 find_product 命中,
	# 所以先 publish 一个模型让 ProductSystem 自动建 api 产品, 再注入 breakdown).
	# UI 显示契约: 行文本应当展示 model.display_name / product.display_name,
	# 不应当只裸露 raw id (玩家看到 `model_xxx` 没意义)。
	var dl: Dictionary = CommandBus.send(&"research.download_open_source",
		{release_id = _OS_TEST_RELEASE})
	assert_true(dl.ok)
	var mid: StringName = dl.model_id
	var model_name: String = ResearchSystem.find_model(mid).display_name
	assert_ne(model_name, "", "测试前提: 模型应有 display_name")
	CommandBus.send(&"research.publish_model", {
		model_id = mid, is_open_source = false, per_token_price = 0.000002})
	# 找到 auto-created api 产品 id.
	var api_pid: StringName = &""
	var api_product_name: String = ""
	for p in GameState.products:
		if p.type == &"api" and p.bound_model_id == mid:
			api_pid = p.id
			api_product_name = p.display_name
			break
	assert_ne(String(api_pid), "", "publish 后应有 auto-created api 产品")
	GameState.last_revenue_breakdown = {
		&"turn": 1,
		&"api_total": 500,
		&"api_per_model": {mid: 500},
		&"api_per_product": {api_pid: 500},
		&"subscription_total": 0,
		&"subscription_per_product": {},
		&"api_demand_lost": 0,
	}
	_hud._refresh()
	var labels := _all_label_texts(_hud._tab_revenue)
	assert_true(_has_text_containing(labels, model_name),
		"breakdown 显示 model display_name 而非 raw id")
	assert_true(_has_text_containing(labels, api_product_name),
		"breakdown 应展开到 api_per_product, 用 product display_name")

func test_overview_tab_uses_styled_dashboard_blocks() -> void:
	# UI视觉系统设计 §8.3: 概览不再是裸 Label 堆叠, 顶部用 KPI 卡,
	# 下一步建议和资产清单用带边框的看板块承载。
	GameState.cash = 1_250_000
	GameState.paid_users = 42_000
	_hud._refresh()
	var kpi_flows := _all_nodes_with_meta(_hud._tab_overview, &"ui_role", &"overview_kpi_flow")
	assert_gt(kpi_flows.size(), 0,
		"概览 KPI 应使用可折行流式容器, 避免窄窗口裁切大数字")
	if not kpi_flows.is_empty():
		assert_true(kpi_flows[0] is HFlowContainer,
			"概览 KPI 容器应为 HFlowContainer")
	var chips: Array = _all_nodes_with_script(_hud._tab_overview, StatChipScript)
	assert_gte(chips.size(), 3, "概览顶部应至少有 3 块 StatChip KPI")
	for chip in chips:
		assert_gte((chip as Control).custom_minimum_size.x, 220.0,
			"概览 KPI chip 应给周次+日期和大额数字留出宽度, 不靠省略号")
	var hint_panels := _all_nodes_with_meta(_hud._tab_overview, &"ui_role", &"overview_next_steps_panel")
	assert_gt(hint_panels.size(), 0,
		"下一步建议应在样式化提示面板内")
	if not hint_panels.is_empty():
		assert_eq((hint_panels[0] as Control).custom_minimum_size.x, 0.0,
			"下一步建议面板不应强制 720px 最小宽, 由外层可用宽度决定换行")
	assert_gt(_all_nodes_with_meta(_hud._tab_overview, &"ui_role", &"overview_assets_table").size(), 0,
		"资产清单应使用样式化字段表")
	var asset_flows := _all_nodes_with_meta(_hud._tab_overview, &"ui_role", &"overview_assets_flow")
	assert_gt(asset_flows.size(), 0,
		"资产清单应使用可折行字段块, 不再用固定两列硬宽表格")
	if not asset_flows.is_empty():
		assert_true(asset_flows[0] is HFlowContainer,
			"资产清单字段块容器应为 HFlowContainer")
	var asset_blocks := _all_nodes_with_meta(_hud._tab_overview, &"ui_role", &"overview_asset_block")
	assert_gte(asset_blocks.size(), 5,
		"资产清单每个字段块都应可测试地标记出来")
	for node in asset_blocks:
		assert_gte((node as Control).custom_minimum_size.x, 300.0,
			"资产字段块应给中文短语和数字留出完整阅读宽度")
	var asset_values := _all_nodes_with_meta(_hud._tab_overview, &"ui_role", &"overview_asset_value")
	assert_gte(asset_values.size(), 5,
		"资产清单每个 value label 都应可测试地标记出来")
	for node in asset_values:
		var lbl := node as Label
		assert_not_null(lbl, "资产 value 节点应为 Label")
		if lbl == null:
			continue
		assert_false(lbl.clip_text, "资产 value label 不应裁字")
		assert_eq(lbl.text_overrun_behavior, TextServer.OVERRUN_NO_TRIMMING,
			"资产 value label 不应使用省略号")
		assert_eq(lbl.autowrap_mode, TextServer.AUTOWRAP_WORD_SMART,
			"资产 value label 应智能换行")

func test_economy_tab_shows_last_week_category_detail_with_one_time_expense() -> void:
	# 经济系统设计 §4.8: 经济页明细读最近完成周 ledger_history[0],
	# 并按类目列出收入/支出；一次性支出也必须出现在明细里。
	GameState.weekly_ledger = {
		&"income": {"本周测试收入": 1},
		&"expense": {"本周任务周费": 2},
		&"gross_in": 1,
		&"gross_out": 2,
	}
	GameState.ledger_history = [{
		&"turn": 7,
		&"income": {"ECO_CAT_REVENUE": 120_000},
		&"expense": {"ECO_CAT_FACILITY_BUILD": 200_000, "ECO_CAT_GPU_PURCHASE": 80_000},
		&"gross_in": 120_000,
		&"gross_out": 280_000,
		&"ending_cash": 900_000,
	}]
	_hud._refresh()
	var labels := _all_label_texts(_hud._tab_economy)
	assert_true(_has_text_containing(labels, "上周收支明细"),
		"经济页应把分类明细标题改成上周收支明细")
	assert_true(_has_text_containing(labels, "第 7 周"),
		"上周明细应标注来自 ledger_history[0] 的周次")
	assert_true(_has_text_containing(labels, "产品营收"),
		"上周收入类目应显示")
	assert_true(_has_text_containing(labels, "机房建设"),
		"一次性支出类目应显示在上周支出明细里")
	assert_true(_has_text_containing(labels, "GPU 采购"),
		"一次性 GPU 采购也应显示在上周支出明细里")
	assert_false(_has_text_containing(labels, "本周任务周费"),
		"经济页明细不应混入进行中本周账本")

func test_economy_tab_last_week_detail_is_styled_table_with_aligned_amounts() -> void:
	# UI视觉系统设计 §8.3 + 经济系统设计 §4.8: 上周明细用有表头的表格,
	# 金额独立成列并右对齐, 不再拼在同一个 Label 里。
	GameState.ledger_history = [{
		&"turn": 8,
		&"income": {"ECO_CAT_REVENUE": 120_000},
		&"expense": {"ECO_CAT_FACILITY_BUILD": 200_000, "ECO_CAT_GPU_PURCHASE": 80_000},
		&"gross_in": 120_000,
		&"gross_out": 280_000,
		&"ending_cash": 900_000,
	}]
	_hud._refresh()
	assert_gt(_all_nodes_with_meta(_hud._tab_economy, &"ui_role", &"last_week_income_table").size(), 0,
		"收入明细应渲染为表格容器")
	assert_gt(_all_nodes_with_meta(_hud._tab_economy, &"ui_role", &"last_week_expense_table").size(), 0,
		"支出明细应渲染为表格容器")
	assert_gt(_all_nodes_with_meta(_hud._tab_economy, &"ui_role", &"ledger_history_table").size(), 0,
		"12 周历史应渲染为表格容器")
	var income_amount := _first_label_exact(_hud._tab_economy, "+$120,000")
	var labels := _all_label_texts(_hud._tab_economy)
	var build_amount := _first_label_exact(_hud._tab_economy, "-$200,000")
	assert_not_null(income_amount, "收入金额应是独立 Label")
	assert_not_null(build_amount, "支出金额应使用 ASCII '-' 且独立成列")
	assert_false(_has_text_containing(labels, "−"),
		"经济明细不应使用数学负号, 避免部分平台字体显示乱码")
	if income_amount != null:
		assert_eq(income_amount.horizontal_alignment, HORIZONTAL_ALIGNMENT_RIGHT,
			"收入金额列应右对齐")
		assert_true(income_amount.get_theme_color(&"font_color").is_equal_approx(UITheme.ACCENT_PRIMARY),
			"收入金额应使用正向语义色")
	if build_amount != null:
		assert_eq(build_amount.horizontal_alignment, HORIZONTAL_ALIGNMENT_RIGHT,
			"支出金额列应右对齐")
		assert_true(build_amount.get_theme_color(&"font_color").is_equal_approx(UITheme.ACCENT_DANGER),
			"支出金额应使用危险语义色")

# ---- 招聘 tab UI (设计 §5.1 / §5.2) -------------------------------------

func test_hiring_tab_lead_pool_shows_bonus_line() -> void:
	# Per 招聘系统设计.md §5.1: 候选池每条 lead 必须显示 "加成: ..." 行,
	# 让玩家看清这位 lead 具体提供什么数值。
	var l := Lead.new()
	l.id = &"pool_cs_1"
	l.display_name = "Alice"
	l.specialty = &"chief_scientist"
	l.level = &"S"
	l.ability = 92.0
	l.signing_fee = 80_000
	l.weekly_salary = 1_800
	GameState.lead_pool.append(l)
	_hud._refresh()
	var labels := _all_label_texts(_hud._tab_hiring)
	assert_true(_has_text_containing(labels, "加成:"),
		"candidate lead row should expose a 加成 prefix line")
	assert_true(_has_text_containing(labels, "预训练加速"),
		"chief_scientist pretrain_speed should render as 预训练加速 label")

func test_hiring_tab_lead_pool_groups_by_specialty() -> void:
	# Per 招聘系统设计.md §5.1: 候选池按 specialty / 所属系统分组展示,
	# 让玩家一眼看出每条 lead 属于哪个系统。
	var l1 := Lead.new()
	l1.id = &"pool_ml_1"; l1.specialty = &"ml_research_lead"; l1.level = &"A"; l1.ability = 75.0
	GameState.lead_pool.append(l1)
	var l2 := Lead.new()
	l2.id = &"pool_ds_1"; l2.specialty = &"data_scientist"; l2.level = &"B"; l2.ability = 60.0
	GameState.lead_pool.append(l2)
	_hud._refresh()
	var labels := _all_label_texts(_hud._tab_hiring)
	assert_true(_has_text_containing(labels, "后训练"),
		"ml_research_lead should be grouped under 后训练")
	assert_true(_has_text_containing(labels, "数据采集"),
		"data_scientist should be grouped under 数据采集")

func test_staff_tab_staff_row_shows_weekly_cost_on_plus_button() -> void:
	# Per 招聘系统设计.md §5.2/§5.4: 员工增减在「员工」tab; +1 按钮必须显式标注
	# +$X/周, 让玩家在点击前就看到新增成本。
	_hud._refresh()
	var btns := _all_button_texts(_hud._tab_staff)
	# 至少有一个 +1 按钮带 "+$" 周薪标签 (ml_eng / infra_eng / ...).
	assert_true(_has_text_containing(btns, "+1 (+$"),
		"+1 button text should include +$X/周 hint")

func test_staff_tab_shows_total_weekly_salary_line() -> void:
	# Per 招聘系统设计.md §5.2/§5.4: 「员工」tab 底部展示 本周总工资, 拆 lead/staff 两份。
	CommandBus.send(&"hiring.adjust_staff", {role = &"ml_eng", delta = 2})
	_hud._refresh()
	var labels := _all_label_texts(_hud._tab_staff)
	assert_true(_has_text_containing(labels, "本周总工资"),
		"staff tab should expose a 本周总工资 summary line")

# ---- 创始人自动加入 (设计 §2 / §5.1 v2026-06) ----------------------------

func test_main_auto_creates_player_scientist_on_ready() -> void:
	var has_founder := false
	for l in GameState.leads:
		if l.is_player_scientist:
			has_founder = true
			break
	assert_true(has_founder, "进入主 HUD 时创始人应自动加入团队")

func test_hiring_tab_does_not_show_create_founder_button() -> void:
	_hud._refresh()
	var btns := _all_button_texts(_hud._tab_hiring)
	assert_false(_has_text_containing(btns, "成为创始研究员"),
		"开局自动加入 founder 后, 招聘 tab 不应再有手动创建按钮")

func test_staff_tab_shows_auto_joined_founder() -> void:
	_hud._refresh()
	await get_tree().process_frame
	var btns := _all_button_texts(_hud._tab_hiring)
	assert_false(_has_text_containing(btns, "成为创始研究员"),
		"founder 已存在时招聘 tab 不应再有创建按钮")
	var labels := _all_label_texts(_hud._tab_staff)
	assert_true(_has_text_containing(labels, "创始人已加入"),
		"founder 已存在时员工 tab 应显示确认行")
	assert_eq(_hud._staff_view.get_founder_card_count_for_test(), 1,
		"founder 已存在时员工 tab 顶部应显示玩家自己的 founder card")

func test_staff_tab_puts_staff_management_above_hired_leads() -> void:
	# 普通员工水位调整比 lead 解雇更高频, 在员工 tab 中应置于已签约 Lead 之前。
	CommandBus.send(&"hiring.adjust_staff", {role = &"ml_eng", delta = 1})
	_hud._refresh()
	var order: PackedStringArray = _hud._staff_view.section_order_for_test()
	assert_true(order.find("STAFF_BY_ROLE") != -1, "员工 tab 应包含普通员工区")
	assert_true(order.find("STAFF_HIRED_LEADS") != -1, "员工 tab 应包含已签约 Lead 区")
	assert_lt(order.find("STAFF_BY_ROLE"), order.find("STAFF_HIRED_LEADS"),
		"普通员工区应排在已签约 Lead 区上方, 实际: %s" % str(order))

func test_evaluate_flow_uses_founder_when_no_eval_lead() -> void:
	# Per main.gd._first_idle_lead_matching: 没有专精 eval_lead 时退到 founder.
	# 清掉 before_each 里 seed 的真正 eval_lead, 只留创始人。
	GameState.leads.clear()
	CommandBus.send(&"hiring.create_player_scientist", {})
	# 给 _on_evaluate_pressed 一个 pretrained model 来评估。
	CommandBus.send(&"research.add_model", {
		arch = &"ant_v1", size_params = 120.0,
		flops_per_token = 240_000_000.0,
		input_modalities = [&"text"], output_modalities = [&"text"],
		dataset_ids = [], display_name = "FE-Test",
	})
	_hud._refresh()
	var btn := _first_button_containing(_hud._tab_research, "开始评估")
	assert_not_null(btn, "未发布模型卡片应展示开始评估按钮")
	btn.emit_signal("pressed")
	await get_tree().process_frame
	# task.start 应已成功 (founder universal); 否则会因 missing_lead toast 而无 active_task。
	assert_eq(GameState.active_tasks.size(), 1,
			"founder 在场时 evaluate 应能用创始人启动")
	assert_eq(GameState.active_tasks[0].template_id, &"evaluate_general")
