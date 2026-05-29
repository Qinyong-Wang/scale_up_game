extends GutTest

## SaveLoadDialog — smoke + slot lifecycle.
## Per design/游戏基础架构设计.md §6.3.1.
##
## headless GUT 不能模拟真实点击, 所以我们直接调脚本暴露的 helper 方法
## (_save_slot / _load_slot / _delete_slot / _refresh_list) 验证状态机。

const SaveLoadDialog := preload("res://scenes/ui/save_load_dialog/save_load_dialog.gd")

const TEST_SAVE_DIR := "user://test_saves_dialog"

var _dlg

func before_each() -> void:
	Save.save_dir = TEST_SAVE_DIR
	# 清理潜在残留。
	for slot in Save.list_slots():
		Save.delete_slot(slot)
	GameState.reset()

func after_each() -> void:
	if _dlg != null:
		_dlg.queue_free()
		_dlg = null
	for slot in Save.list_slots():
		Save.delete_slot(slot)
	Save.save_dir = Save.DEFAULT_SAVE_DIR

func _make_dialog():
	_dlg = SaveLoadDialog.new()
	add_child_autofree(_dlg)
	_dlg.refresh()
	return _dlg

# ---- instantiation ------------------------------------------------------

func test_dialog_instantiates_without_crash() -> void:
	var dlg = _make_dialog()
	assert_not_null(dlg)
	assert_not_null(dlg._slot_list)
	assert_not_null(dlg._new_slot_input)
	assert_not_null(dlg._status_label)

func test_dialog_uses_panelized_save_layout() -> void:
	# 存档界面是玩家安全感入口, 应使用分区面板 + 状态条,
	# 不再是裸输入框和裸列表 (design/游戏基础架构设计.md §6.3.1)。
	var dlg = _make_dialog()
	assert_not_null(dlg._content_scroll, "存档内容应放入 ScrollContainer")
	assert_not_null(dlg._create_section, "存档界面应有「手动存档」面板")
	assert_not_null(dlg._slots_section, "存档界面应有「存档列表」面板")
	assert_not_null(dlg._status_panel, "存档界面应有状态反馈条")
	assert_true(dlg._create_section is PanelContainer)
	assert_true(dlg._slots_section is PanelContainer)
	assert_true(dlg._status_panel is PanelContainer)
	assert_false(dlg._status_panel.visible, "无消息时状态反馈条不应占据视觉空间")

func test_section_titles_are_localized() -> void:
	var dlg = _make_dialog()
	assert_eq(dlg._create_title_label.text, tr("SAVE_SECTION_CREATE"))
	assert_eq(dlg._slots_title_label.text, tr("SAVE_SECTION_SLOTS"))

func test_save_button_uses_create_variant() -> void:
	var dlg = _make_dialog()
	assert_gte(int(dlg._save_btn.custom_minimum_size.y), UITheme.CREATE_BUTTON_H,
		"保存按钮应使用醒目的 create CTA")

func test_empty_save_dir_renders_empty_state() -> void:
	var dlg = _make_dialog()
	# 没存档时 slot_list 没行, 也别崩。
	assert_eq(dlg._row_count(), 0)
	assert_not_null(dlg._empty_state, "无存档时应有正式空状态节点")
	assert_true(dlg._empty_state.visible, "无存档时空状态应可见")

# ---- save ---------------------------------------------------------------

func test_save_new_slot_appends_row_and_writes_file() -> void:
	var dlg = _make_dialog()
	dlg._new_slot_input.text = "alpha"
	dlg._save_slot("alpha")
	assert_true(Save.list_slots().has(&"alpha"))
	assert_gt(dlg._row_count(), 0)
	assert_false(dlg._empty_state.visible, "有存档后空状态应隐藏")
	assert_true(dlg._status_panel.visible, "保存后应显示状态反馈条")
	assert_true(dlg._status_label.text.find("已存档") != -1,
			"status 应提示已存档, 实际: %s" % dlg._status_label.text)

func test_slot_row_uses_card_style_and_action_group() -> void:
	Save.write(&"alpha")
	var dlg = _make_dialog()
	var row: Control = null
	for child in dlg._slot_list.get_children():
		if String(child.get_meta("slot_id", "")) == "alpha":
			row = child as Control
			break
	assert_not_null(row, "应能找到 alpha 存档行")
	var sb: StyleBox = row.get_theme_stylebox(&"panel")
	assert_true(sb is StyleBoxFlat, "slot 行应是卡片式 StyleBoxFlat")
	if sb is StyleBoxFlat:
		assert_eq((sb as StyleBoxFlat).corner_radius_top_left, UITheme.R_MD,
			"slot 行应有中等圆角")
	assert_true(dlg._slot_has_action_button(&"alpha", tr("SAVE_LOAD_BTN")),
		"slot 行应有读取按钮")
	assert_true(dlg._slot_has_action_button(&"alpha", tr("SAVE_OVERWRITE")),
		"slot 行应有覆盖按钮")

func test_save_sanitizes_slot_name() -> void:
	var dlg = _make_dialog()
	# 中文 / 空格 / 特殊符号 → 全被剥离, 落到 fallback。
	var sanitized: String = dlg._sanitize_slot_name(" 我的存档!! ")
	# 应只剩 a-z 0-9 _ - (这里中文/!/空格都不允许)。
	assert_eq(sanitized, "", "应全部剥离非法字符")

func test_save_empty_name_falls_back_to_manual_turn() -> void:
	GameState.turn = 7
	var dlg = _make_dialog()
	dlg._save_slot("")
	# 落到 manual_7。
	assert_true(Save.list_slots().has(&"manual_7"),
			"空名应 fallback 到 manual_<turn>, slots=%s" % str(Save.list_slots()))

func test_save_overwrite_existing_slot_keeps_one_file() -> void:
	var dlg = _make_dialog()
	dlg._save_slot("beta")
	GameState.turn = 5  # 改一下状态再覆盖, 验证 turn 字段被更新。
	dlg._save_slot("beta")
	var slots := Save.list_slots()
	var count := 0
	for s in slots:
		if s == &"beta":
			count += 1
	assert_eq(count, 1, "覆盖后只剩一个 beta")
	# 读回来 turn 应该是 5。
	GameState.turn = 999
	Save.read(&"beta")
	assert_eq(GameState.turn, 5)

# ---- load ---------------------------------------------------------------

func test_load_existing_slot_restores_state_and_status() -> void:
	GameState.cash = 12345
	Save.write(&"gamma")
	GameState.cash = 0
	var dlg = _make_dialog()
	dlg._load_slot(&"gamma")
	assert_eq(GameState.cash, 12345)
	assert_true(dlg._status_label.text.find("已读档") != -1,
			"status 应提示已读档, 实际: %s" % dlg._status_label.text)

func test_load_missing_slot_surfaces_error_in_dialog() -> void:
	var dlg = _make_dialog()
	dlg._load_slot(&"nonexistent_slot_xyz")
	# 失败提示应留在 status_label 里。
	assert_true(dlg._status_label.text.find("失败") != -1
			or dlg._status_label.text.find("not_found") != -1,
			"status 应展示失败原因, 实际: %s" % dlg._status_label.text)

func test_load_corrupted_slot_surfaces_error() -> void:
	# 手写一个坏 JSON。
	Save._ensure_dir()
	var path: String = "%s/%s.json" % [Save.save_dir, "broken"]
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("{not valid json")
	f.close()
	var dlg = _make_dialog()
	dlg._load_slot(&"broken")
	assert_true(dlg._status_label.text.find("失败") != -1
			or dlg._status_label.text.find("corrupted") != -1)

# ---- delete -------------------------------------------------------------

func test_delete_slot_removes_file_and_row() -> void:
	Save.write(&"delta")
	var dlg = _make_dialog()
	assert_gt(dlg._row_count(), 0)
	dlg._delete_slot(&"delta")
	assert_false(Save.list_slots().has(&"delta"))
	assert_eq(dlg._row_count(), 0)

func test_autosave_row_has_no_delete_button() -> void:
	# 直接写一个 autosave。
	Save.write(Save.AUTOSAVE_SLOT)
	var dlg = _make_dialog()
	# autosave 行应该没有 delete 按钮 (UI 不允许玩家手动删自动档)。
	assert_false(dlg._slot_has_delete_button(Save.AUTOSAVE_SLOT),
			"autosave 不应允许手动删除")

# ---- refresh -----------------------------------------------------------

func test_refresh_after_save_loaded_signal_repopulates() -> void:
	var dlg = _make_dialog()
	assert_eq(dlg._row_count(), 0)
	Save.write(&"eps")
	dlg.refresh()
	assert_eq(dlg._row_count(), 1)
