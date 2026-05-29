extends GutTest

## NewGameDialog — 取名 + 选出身 + 确认发信号。
## Per design/出身系统设计.md §2.
## headless GUT 不能模拟点击, 直接调脚本 helper (_set_names / _select_origin /
## _on_start_pressed)。

const NewGameDialog := preload("res://scenes/ui/new_game_dialog/new_game_dialog.gd")

var _dlg

func before_each() -> void:
	GameState.reset()
	_dlg = NewGameDialog.new()
	add_child_autofree(_dlg)

func test_dialog_instantiates_with_inputs_and_three_origin_cards() -> void:
	assert_not_null(_dlg._player_input)
	assert_not_null(_dlg._company_input)
	assert_eq(_dlg._origin_cards.size(), 3)

func test_dialog_is_wide_enough_for_three_columns() -> void:
	# 做大 + 三栏并排 → 宽度需明显更宽, 但不超过最小支持窗口 (1280×720)。
	assert_gte(_dlg.min_size.x, 1000,
		"三栏布局对话框应足够宽, 实际: %d" % int(_dlg.min_size.x))
	assert_gte(_dlg.min_size.y, 600,
		"新游戏对话框高度应足够展示三栏内容, 实际: %d" % int(_dlg.min_size.y))
	assert_lte(_dlg.min_size.x, 1280,
		"新游戏对话框不能超过最小支持窗口宽度, 实际: %d" % int(_dlg.min_size.x))
	assert_lte(_dlg.min_size.y, 720,
		"新游戏对话框不能超过最小支持窗口高度, 实际: %d" % int(_dlg.min_size.y))

func test_dialog_uses_panelized_identity_layout() -> void:
	# 开局身份选择应像正式面板, 不是裸三栏 + 分隔线。
	assert_not_null(_dlg._shell_panel, "新游戏对话框应有浅色 shell 面板")
	assert_not_null(_dlg._identity_section, "左栏身份区应是 PanelContainer")
	assert_not_null(_dlg._avatar_section, "中栏头像区应是 PanelContainer")
	assert_not_null(_dlg._brand_section, "右栏品牌区应是 PanelContainer")
	assert_not_null(_dlg._preview_panel, "右栏应有独立预览卡")
	assert_true(_dlg._identity_section is PanelContainer)
	assert_true(_dlg._avatar_section is PanelContainer)
	assert_true(_dlg._brand_section is PanelContainer)
	assert_true(_dlg._preview_panel is PanelContainer)

func test_section_titles_use_clear_bold_typography() -> void:
	assert_gte(_dlg._section_title_labels.size(), 3)
	for title in _dlg._section_title_labels:
		assert_gte(title.get_theme_font_size(&"font_size"), UITheme.FS_LG,
			"分区标题字号应足够清楚: %s" % title.text)
		assert_eq(title.get_theme_font(&"font"), UITheme.get_ui_font_bold(),
			"分区标题应使用 bold 字体: %s" % title.text)

func test_name_placeholders_prompt_required_input() -> void:
	assert_eq(_dlg._player_input.placeholder_text, tr("NEWGAME_PLAYER_PLACEHOLDER"))
	assert_eq(_dlg._company_input.placeholder_text, tr("NEWGAME_COMPANY_PLACEHOLDER"))
	assert_false(_dlg._player_input.placeholder_text.contains("留空"))
	assert_false(_dlg._company_input.placeholder_text.to_lower().contains("blank"))

func test_name_inputs_use_readable_placeholder_contrast() -> void:
	assert_eq(_dlg._player_input.get_theme_color(&"font_placeholder_color").to_html(),
		UITheme.TEXT_SECONDARY.to_html())
	assert_eq(_dlg._company_input.get_theme_color(&"font_placeholder_color").to_html(),
		UITheme.TEXT_SECONDARY.to_html())
	assert_gte(_dlg._player_input.get_theme_font_size(&"font_size"), UITheme.FS_BASE)
	assert_gte(_dlg._company_input.get_theme_font_size(&"font_size"), UITheme.FS_BASE)

func test_start_disabled_until_required_names_present() -> void:
	assert_true(_dlg.get_ok_button().disabled,
		"未填写创始人和公司名称时不能开始游戏")
	assert_true(_dlg._name_error_label.visible,
		"必填提示应可见")
	_dlg._set_names("阿黄", "")
	assert_true(_dlg.get_ok_button().disabled,
		"缺公司名称时不能开始游戏")
	_dlg._set_names("", "蚂蚁智算")
	assert_true(_dlg.get_ok_button().disabled,
		"缺创始人名称时不能开始游戏")
	_dlg._set_names("阿黄", "蚂蚁智算")
	assert_false(_dlg.get_ok_button().disabled,
		"两个名称都填写后才能开始游戏")
	assert_false(_dlg._name_error_label.visible,
		"名称有效后必填提示应隐藏")

func test_first_origin_selected_by_default() -> void:
	assert_ne(_dlg._selected_origin, &"")

func test_select_origin_updates_selection() -> void:
	_dlg._select_origin(&"influencer")
	assert_eq(_dlg._selected_origin, &"influencer")

func test_origin_cards_use_readable_typography() -> void:
	assert_eq(_dlg._origin_title_labels.size(), 3)
	assert_eq(_dlg._origin_body_labels.size(), 9)
	for title in _dlg._origin_title_labels.values():
		assert_gte(title.get_theme_font_size(&"font_size"), UITheme.FS_LG)
		assert_eq(title.get_theme_font(&"font"), UITheme.get_ui_font_bold())
	for body in _dlg._origin_body_labels:
		assert_gte(body.get_theme_font_size(&"font_size"), UITheme.FS_BASE,
			"出身卡正文不能使用过小字号: %s" % body.text)

# ---- 公司标志 + 创始人头像选择 (出身系统设计 §2) -------------------------

func test_dialog_has_logo_and_avatar_pickers() -> void:
	# 标志网格含默认 A (&"") + 各 AI 品牌标记; 头像网格含创始人头像。
	assert_gt(_dlg._logo_cards.size(), 1, "应有默认 A + 多个品牌标志可选")
	assert_gt(_dlg._avatar_cards.size(), 0, "应有创始人头像可选")

func test_logo_grid_uses_brand_keys_plus_default() -> void:
	# 默认 A (&"") + IconRegistry.company_logo_keys() 全部 brand-NN。
	# 注: 空 StringName 作 dict key 时 Dictionary.has(&"") 恒 false (Godot 量纲),
	# 故默认 A 用 keys() 里的空串判定, 不用 has()。
	var has_default := false
	for k in _dlg._logo_cards.keys():
		if String(k) == "":
			has_default = true
	assert_true(has_default, "标志网格应含默认 A (空 logo id)")
	for k in IconRegistry.company_logo_keys():
		assert_true(_dlg._logo_cards.has(k), "标志网格应含品牌 key %s" % k)
	assert_eq(_dlg._logo_cards.size(), IconRegistry.company_logo_keys().size() + 1)

func test_default_logo_is_classic_and_avatar_is_first() -> void:
	# 默认标志 = 经典 A (&""); 默认头像 = 第一个可选 key, 保证开始游戏永远合法。
	assert_eq(_dlg._selected_logo, &"")
	assert_eq(_dlg._selected_avatar, IconRegistry.founder_avatar_keys()[0])

func test_select_logo_and_avatar_update_selection() -> void:
	var logo_id: StringName = IconRegistry.company_logo_keys()[0]
	_dlg._select_logo(logo_id)
	assert_eq(_dlg._selected_logo, logo_id)
	var av: StringName = IconRegistry.founder_avatar_keys()[1]
	_dlg._select_avatar(av)
	assert_eq(_dlg._selected_avatar, av)

# ---- 实时预览卡 (右栏) ---------------------------------------------------

func test_preview_reflects_company_name_and_player() -> void:
	_dlg._set_names("阿黄", "蚂蚁智算")
	assert_eq(_dlg._preview_company_lbl.text, "蚂蚁智算",
		"预览卡公司名应跟随输入")
	assert_true(_dlg._preview_sub_lbl.text.contains("阿黄"),
		"预览卡副行应含创始人名, 实际: %s" % _dlg._preview_sub_lbl.text)

func test_preview_logo_and_avatar_follow_selection() -> void:
	var logo_id: StringName = IconRegistry.company_logo_keys()[1]
	_dlg._select_logo(logo_id)
	assert_eq(_dlg._preview_logo_tile.logo_id, logo_id,
		"预览标志应跟随所选 logo")
	var av: StringName = IconRegistry.founder_avatar_keys()[2]
	_dlg._select_avatar(av)
	assert_eq(_dlg._preview_avatar_key, av,
		"预览头像应跟随所选头像 key")

func test_preview_card_uses_large_readable_identity() -> void:
	assert_gte(_dlg._preview_company_lbl.get_theme_font_size(&"font_size"), UITheme.FS_XL)
	assert_eq(_dlg._preview_company_lbl.get_theme_font(&"font"), UITheme.get_ui_font_bold())
	assert_gte(_dlg._preview_logo_tile.custom_minimum_size.x, 84.0,
		"预览 Logo 应明显大于网格小瓦片")
	assert_gte(_dlg._preview_avatar.custom_minimum_size.x, 84.0,
		"预览头像应明显大于普通缩略图")

func test_start_emits_signal_with_names_and_origin() -> void:
	_dlg._set_names("阿黄", "蚂蚁智算")
	_dlg._select_origin(&"entrepreneur")
	watch_signals(_dlg)
	_dlg._on_start_pressed()
	assert_signal_emitted(_dlg, "start_requested")
	var p: Array = get_signal_parameters(_dlg, "start_requested")
	assert_eq(p[0], "阿黄")
	assert_eq(p[1], "蚂蚁智算")
	assert_eq(p[2], &"entrepreneur")

func test_start_emits_signal_with_logo_and_avatar() -> void:
	_dlg._set_names("阿黄", "蚂蚁智算")
	_dlg._select_origin(&"entrepreneur")
	var logo_id: StringName = StringName(UITheme.LOGO_MARKS[1]["id"])
	var av: StringName = IconRegistry.founder_avatar_keys()[2]
	_dlg._select_logo(logo_id)
	_dlg._select_avatar(av)
	watch_signals(_dlg)
	_dlg._on_start_pressed()
	var p: Array = get_signal_parameters(_dlg, "start_requested")
	assert_eq(p[3], logo_id, "start_requested 第 4 个参数应是公司标志 id")
	assert_eq(p[4], av, "start_requested 第 5 个参数应是创始人头像 key")

func test_empty_names_do_not_emit_start_requested() -> void:
	_dlg._set_names("", "   ")
	watch_signals(_dlg)
	_dlg._on_start_pressed()
	assert_signal_not_emitted(_dlg, "start_requested")
	assert_true(_dlg._name_error_label.visible,
		"直接触发开始时仍应拦截空名称")
