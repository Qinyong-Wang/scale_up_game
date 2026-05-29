extends GutTest

## NewCampaignDialog smoke + happy-path tests. Per design/营销系统设计.md §4.
## v7 PR-F3 (2026-05): type checkbox 删, dialog 改成产品下拉。
## Headless: we don't click buttons; we drive _build_payload and _on_start_pressed
## directly. Mirrors pretrain_dialog_test pattern.

const NewCampaignDialog := preload("res://scenes/ui/new_campaign_dialog/new_campaign_dialog.gd")

var _dlg

var _saved_locale: String

func before_each() -> void:
	GameState.reset()
	_saved_locale = TranslationServer.get_locale()
	# v8: campaigns hard-require + lock marketing staff. Seed a generous idle
	# pool so the dialog's start path and the concurrent-cap test can launch.
	GameState.staff_pool[&"marketing"] = 10

func after_each() -> void:
	TranslationServer.set_locale(_saved_locale)
	if _dlg != null:
		_dlg.queue_free()
		_dlg = null

func _make_product(id: StringName = &"p_chat", type: StringName = &"chatbot",
		bound_model_id: StringName = &"m_test") -> Product:
	var p := Product.new()
	p.id = id
	p.type = type
	p.bound_model_id = bound_model_id
	p.subscription_price = 49
	p.display_name = "Test " + String(id)
	GameState.products.append(p)
	return p

func _make_dialog():
	_dlg = NewCampaignDialog.new()
	add_child_autofree(_dlg)
	_dlg.refresh()
	return _dlg

# ---- instantiation ------------------------------------------------------

func test_dialog_instantiates_and_refresh_does_not_crash() -> void:
	_make_product()
	var dlg = _make_dialog()
	assert_not_null(dlg._name_input)
	assert_not_null(dlg._budget_spin)
	assert_not_null(dlg._weeks_spin)
	assert_not_null(dlg._lead_dropdown)
	assert_not_null(dlg._product_dropdown,
			"v7 PR-F3: dialog 应有产品下拉")
	# 旧字段不再存在。
	assert_false("_fame_boost_checkbox" in dlg)
	assert_false("_type_checkboxes" in dlg,
			"type checkbox 应已删除")

func test_budget_spin_cap_is_twenty_million() -> void:
	# 用户指定: 营销周预算上限 20M (旧 10M). SpinBox.max_value 是唯一闸门
	# (marketing_system.start_campaign 不另设 budget 上限).
	var dlg = _make_dialog()
	assert_eq(int(dlg._budget_spin.max_value), 20_000_000,
			"营销周预算上限应为 20M")
	# 20M 应能真正填进去 (不被 max_value 夹回).
	dlg._budget_spin.value = 20_000_000
	assert_eq(int(dlg._budget_spin.value), 20_000_000)

func test_product_dropdown_lists_existing_products() -> void:
	_make_product(&"p_chat", &"chatbot")
	_make_product(&"p_api", &"api")
	var dlg = _make_dialog()
	assert_eq(dlg._product_dropdown.item_count, 2)

func test_no_products_disables_ok_button() -> void:
	# 玩家没有产品时无法启动 campaign。
	GameState.cash = 1_000_000
	var dlg = _make_dialog()
	dlg._budget_spin.value = 1_000
	dlg._refresh_preview()
	assert_true(dlg.get_ok_button().disabled,
			"没产品时启动按钮应禁用")

# ---- 网红创始人加成在预览里生效 + 显示 (bug: 加成不显示) ----------------

func _attract_number(dlg) -> int:
	# 从「预计每周拉新: ≈ N 人」文本里抠出数字 (去掉非数字)。
	var digits := ""
	for ch in dlg._attract_label.text:
		if ch >= "0" and ch <= "9":
			digits += ch
	return int(digits) if digits != "" else 0

func test_influencer_founder_boosts_expected_per_week() -> void:
	TranslationServer.set_locale("zh_CN")
	GameState.cash = 10_000_000
	_make_product(&"p_sub", &"chatbot")
	var dlg = _make_dialog()
	dlg._budget_spin.value = 100_000   # 大预算让乘子差异在取整后明显

	GameState.founder_origin = &""
	dlg._refresh_preview()
	var neutral := _attract_number(dlg)

	GameState.founder_origin = &"influencer"
	dlg._refresh_preview()
	var influencer := _attract_number(dlg)

	assert_gt(neutral, 0, "中性出身应有正的预计拉新")
	assert_gt(influencer, neutral, "网红出身应放大预计每周拉新")
	# 网红 user_growth_multiplier = 1.3 → 约 1.3×。
	assert_almost_eq(float(influencer) / float(neutral), 1.3, 0.05)

func test_influencer_founder_shown_in_cac_suffix() -> void:
	TranslationServer.set_locale("zh_CN")
	GameState.cash = 10_000_000
	_make_product(&"p_sub", &"chatbot")
	GameState.founder_origin = &"influencer"
	var dlg = _make_dialog()
	dlg._budget_spin.value = 1_000
	dlg._refresh_preview()
	assert_true(dlg._cac_label.text.contains("创始人"),
			"CAC 后缀应标出创始人加成, 实际: %s" % dlg._cac_label.text)

func test_neutral_founder_no_suffix() -> void:
	TranslationServer.set_locale("zh_CN")
	GameState.cash = 10_000_000
	_make_product(&"p_sub", &"chatbot")
	GameState.founder_origin = &""
	var dlg = _make_dialog()
	dlg._budget_spin.value = 1_000
	dlg._refresh_preview()
	assert_false(dlg._cac_label.text.contains("创始人"),
			"无加成出身不应显示创始人后缀, 实际: %s" % dlg._cac_label.text)

# ---- payload construction (no actual command sent) ---------------------

func test_build_payload_includes_target_product_id() -> void:
	var p := _make_product(&"p_chat", &"chatbot")
	var dlg = _make_dialog()
	dlg._budget_spin.value = 5000
	dlg._weeks_spin.value = 10
	dlg._product_dropdown.select(0)
	var payload: Dictionary = dlg._build_payload()
	assert_eq(int(payload.get(&"weekly_budget", 0)), 5000)
	assert_eq(int(payload.get(&"total_weeks", 0)), 10)
	assert_eq(StringName(payload.get(&"target_product_id", &"")), p.id)

func test_build_payload_no_legacy_fields() -> void:
	# v7 PR-F3: 不再写 target_product_types / fame_boost。
	_make_product()
	var dlg = _make_dialog()
	var payload: Dictionary = dlg._build_payload()
	assert_false(payload.has(&"fame_boost"))
	assert_false(payload.has(&"target_product_types"))

func test_build_payload_includes_lead_id_when_selected() -> void:
	_make_product()
	var lead := Lead.new()
	lead.id = &"lead_mk"
	lead.specialty = &"marketing_lead"
	lead.ability = 80.0
	GameState.leads.append(lead)
	var dlg = _make_dialog()
	dlg.refresh()
	assert_true(dlg._lead_dropdown.item_count >= 2)
	dlg._lead_dropdown.select(1)
	var payload: Dictionary = dlg._build_payload()
	assert_eq(payload.get(&"lead_id", &""), lead.id)

# ---- preview ------------------------------------------------------------

func test_preview_calculates_total_investment() -> void:
	_make_product()
	var dlg = _make_dialog()
	dlg._budget_spin.value = 1000
	dlg._weeks_spin.value = 12
	dlg._refresh_preview()
	assert_string_contains(dlg._total_label.text, "12,000")

func test_cac_label_uses_chinese_phrase_not_acronym() -> void:
	# D-15: "CAC" 是营销黑话, UI 改成"获客成本" 让新玩家秒懂。
	_make_product()
	var dlg = _make_dialog()
	dlg._budget_spin.value = 1000
	dlg._weeks_spin.value = 1
	dlg._refresh_preview()
	assert_string_contains(dlg._cac_label.text, "获客成本")
	assert_eq(dlg._cac_label.text.find("CAC"), -1,
			"对话框文案不应保留 'CAC' 缩写, 实际: %s" % dlg._cac_label.text)

func test_preview_subscription_product_shows_users_per_week() -> void:
	# v7 PR-F3: 锁订阅产品时显示「人/周」。
	_make_product(&"p_chat", &"chatbot")
	var dlg = _make_dialog()
	dlg._budget_spin.value = 8000
	dlg._weeks_spin.value = 1
	dlg._refresh_preview()
	# v12: 8000 × 0.0125 = 100 users / week (CAC $80, 预算翻倍才回到 100).
	assert_string_contains(dlg._attract_label.text, "100")
	assert_string_contains(dlg._attract_label.text, "人")

func test_preview_api_product_shows_tokens_per_week() -> void:
	_make_product(&"p_api", &"api")
	var dlg = _make_dialog()
	dlg._budget_spin.value = 40_000
	dlg._weeks_spin.value = 1
	dlg._refresh_preview()
	assert_true(dlg._api_demand_label.visible,
			"锁 api 产品时应显示 API token 需求行")
	assert_string_contains(dlg._api_demand_label.text.to_lower(), "tokens")

func test_ok_disabled_when_cash_insufficient_for_one_week() -> void:
	_make_product()
	var dlg = _make_dialog()
	GameState.cash = 100
	dlg._budget_spin.value = 5_000
	dlg._refresh_preview()
	assert_true(dlg.get_ok_button().disabled)

func test_ok_enabled_when_cash_covers_one_week() -> void:
	_make_product()
	var dlg = _make_dialog()
	GameState.cash = 1_000_000
	dlg._budget_spin.value = 5_000
	dlg._weeks_spin.value = 4
	dlg._refresh_preview()
	assert_false(dlg.get_ok_button().disabled)

func test_ok_disabled_when_concurrent_cap_reached() -> void:
	var p := _make_product()
	for i in range(MarketingSystem.MAX_CONCURRENT_CAMPAIGNS):
		CommandBus.send(&"marketing.start_campaign", {
			display_name = "Existing %d" % i, weekly_budget = 1000,
			total_weeks = 2, target_product_id = p.id,
		})
	var dlg = _make_dialog()
	GameState.cash = 1_000_000
	dlg._budget_spin.value = 5_000
	dlg._refresh_preview()
	assert_true(dlg.get_ok_button().disabled,
			"达到并发上限时启动按钮应禁用")

# ---- happy path: dialog → start_campaign --------------------------------

func test_start_pressed_creates_campaign_via_command_bus() -> void:
	GameState.cash = 1_000_000
	var p := _make_product(&"p_chat", &"chatbot")
	var dlg = _make_dialog()
	dlg._budget_spin.value = 2_000
	dlg._weeks_spin.value = 8
	dlg._name_input.text = "Launch wave"
	dlg._product_dropdown.select(0)
	watch_signals(dlg)
	dlg._on_start_pressed()
	assert_eq(GameState.campaigns.size(), 1)
	var c = GameState.campaigns[0]
	assert_eq(c.weekly_budget, 2_000)
	assert_eq(c.total_weeks, 8)
	assert_eq(c.display_name, "Launch wave")
	assert_eq(StringName(c.target_product_id), p.id)
	assert_signal_emitted(dlg, "campaign_started_via_dialog")

func test_lead_dropdown_filters_to_marketing_lead_only() -> void:
	GameState.cash = 1_000_000
	_make_product()
	var bad := Lead.new()
	bad.id = &"lead_pt"
	bad.specialty = &"chief_scientist"
	bad.ability = 80.0
	GameState.leads.append(bad)
	var good := Lead.new()
	good.id = &"lead_mk"
	good.specialty = &"marketing_lead"
	good.ability = 70.0
	GameState.leads.append(good)
	var dlg = _make_dialog()
	dlg.refresh()
	assert_eq(dlg._lead_dropdown.item_count, 2)
	assert_eq(StringName(dlg._lead_dropdown.get_item_metadata(1)), &"lead_mk")

func test_marketing_system_rejects_wrong_specialty_when_lead_id_provided() -> void:
	GameState.cash = 1_000_000
	var p := _make_product()
	var lead := Lead.new()
	lead.id = &"lead_pt"
	lead.specialty = &"chief_scientist"
	lead.ability = 80.0
	GameState.leads.append(lead)
	var r: Dictionary = CommandBus.send(&"marketing.start_campaign", {
		weekly_budget = 1_000,
		total_weeks = 4,
		target_product_id = p.id,
		lead_id = lead.id,
	})
	assert_false(r.ok)
	assert_eq(r.error, &"lead_specialty_mismatch")
