extends GutTest

## PriceEditDialog smoke — 验证对话框装载 + 预览 + 改价命令链路.
## 见 design/研究系统设计.md §4.8.
##
## 不模拟实际点击 (headless GUT 不支持), 但验证:
##   - 脚本能解析 / 实例化;
##   - refresh(model) 读 ResearchSystem 数据后不崩;
##   - 预览路径 (research.preview_growth_rate) 接好;
##   - _on_confirm_pressed 走 research.set_api_price 改价。

const PriceEditDialog := preload("res://scenes/ui/price_edit_dialog/price_edit_dialog.gd")

var _dlg

func before_each() -> void:
	GameState.reset()
	# 强制 ResearchSystem baseline cache 重算, 防止跨测污染。
	ResearchSystem._baseline_cache = {year = -1, value = 0.0}

func after_each() -> void:
	if _dlg != null:
		_dlg.queue_free()
		_dlg = null

func _make_published_model(price_per_token: float, is_open_source: bool = false) -> Model:
	var m := Model.new()
	m.id = &"m_pub"
	m.display_name = "sparrow-pub"
	m.arch = &"ant_v1"
	m.size_params = 7000.0
	m.flops_per_token = 1.4e10  # 7B equivalent dense
	m.status = &"published"
	m.is_open_source = is_open_source
	m.per_token_price = price_per_token
	m.provenance = &"trained"
	GameState.models.append(m)
	return m

func _make_dialog():
	_dlg = PriceEditDialog.new()
	add_child_autofree(_dlg)
	return _dlg

func test_dialog_instantiates_and_refresh_does_not_crash() -> void:
	var m: Model = _make_published_model(0.000002, false)
	var dlg = _make_dialog()
	dlg.refresh(m)
	assert_not_null(dlg._price_spin)
	# 单位转换: per_token_price = 2e-6 → 2.0 $/M tok.
	assert_almost_eq(float(dlg._price_spin.value), 2.0, 0.001)

func test_refresh_displays_base_and_guidance_labels() -> void:
	var m: Model = _make_published_model(0.000002, false)
	var dlg = _make_dialog()
	dlg.refresh(m)
	# Closed source → title label should say "闭源" not "开源".
	assert_true(dlg._title_label.text.find("闭源") != -1,
			"闭源模型的标题应标 闭源, 实际: %s" % dlg._title_label.text)
	# 推理成本 / 指导价 行始终展示价格.
	assert_true(dlg._current_label.text.find("推理成本") != -1
			and dlg._current_label.text.find("指导价") != -1,
			"current_label 应同时显示 推理成本 / 指导价, 实际: %s" % dlg._current_label.text)
	assert_true(dlg._current_label.text.find("$") != -1)

func test_open_source_label_shows_open() -> void:
	var m: Model = _make_published_model(0.000002, true)
	var dlg = _make_dialog()
	dlg.refresh(m)
	assert_true(dlg._title_label.text.find("开源") != -1)

func test_preview_label_updates_on_price_change() -> void:
	var m: Model = _make_published_model(0.000002, false)
	var dlg = _make_dialog()
	dlg.refresh(m)
	# Bump price way above guidance to force cliff.
	var guidance: float = ResearchSystem.guidance_price_per_token(m)
	dlg._price_spin.value = guidance * 3.0 * 1_000_000.0
	dlg._refresh_preview()
	assert_true(dlg._warning_label.text.find("需求归零") != -1,
			"3× guidance 应触发需求归零警告, 实际 warning=%s preview=%s"
				% [dlg._warning_label.text, dlg._preview_label.text])
	assert_eq(dlg._warning_label.text.find("cliff"), -1,
			"玩家可见文案不应泄露 'cliff' 内部术语")

func test_preview_shows_growth_bonus_below_06x_guidance() -> void:
	var m: Model = _make_published_model(0.000002, false)
	var dlg = _make_dialog()
	dlg.refresh(m)
	var guidance: float = ResearchSystem.guidance_price_per_token(m)
	# 价格 = 0.5 × guidance → ratio = 0.5 → +4%/周.
	dlg._price_spin.value = guidance * 0.5 * 1_000_000.0
	dlg._refresh_preview()
	assert_true(dlg._preview_label.text.find("+4") != -1
			or dlg._preview_label.text.find("增益区") != -1,
			"低于指导价应显示增益区, 实际: %s" % dlg._preview_label.text)

func test_confirm_dispatches_set_api_price() -> void:
	var m: Model = _make_published_model(0.000002, false)
	var dlg = _make_dialog()
	dlg.refresh(m)
	# 设新价 5 $/M tok = 5e-6 $/tok.
	dlg._price_spin.value = 5.0
	var emitted: Array = []
	dlg.price_updated.connect(func(id, applied): emitted.append([id, applied]))
	dlg._on_confirm_pressed()
	assert_eq(emitted.size(), 1)
	assert_eq(emitted[0][0], &"m_pub")
	assert_almost_eq(float(emitted[0][1]), 5.0e-6, 1.0e-9)
	# 模型上的价格也确实改了.
	assert_almost_eq(float(m.per_token_price), 5.0e-6, 1.0e-9)

func test_negative_zero_price_clamps_to_floor() -> void:
	# SpinBox 配置 min_value = 0, 玩家输 0 → applied_price = 0 (research 只 floor).
	var m: Model = _make_published_model(0.000002, false)
	var dlg = _make_dialog()
	dlg.refresh(m)
	dlg._price_spin.value = 0.0
	dlg._on_confirm_pressed()
	assert_almost_eq(float(m.per_token_price), 0.0, 1.0e-12)

# ---- layout / scroll ----------------------------------------------------

func test_dialog_content_is_in_scroll_container() -> void:
	# Per design/研究系统设计.md §4.8 + 玩家反馈: 改价 dialog 内容会被裁。
	# 表单装在 ScrollContainer 里, 超出 dialog 高度时可滚, 避免按钮被推出视口。
	var dlg = _make_dialog()
	var found_scroll: ScrollContainer = _find_first_descendant(dlg, ScrollContainer)
	assert_not_null(found_scroll, "PriceEditDialog 必须有 ScrollContainer 包内容")

func test_dialog_min_size_fits_content() -> void:
	# 三栏内容 + chrome 至少需要 ~280px 高, 否则 OK/Cancel 按钮会盖住 warning。
	var dlg = _make_dialog()
	assert_gte(int(dlg.min_size.y), 280,
			"min_size.y 至少 280, 实际: %d" % int(dlg.min_size.y))

func _find_first_descendant(root: Node, type) -> Node:
	for c in root.get_children():
		if is_instance_of(c, type):
			return c
		var found := _find_first_descendant(c, type)
		if found != null:
			return found
	return null
