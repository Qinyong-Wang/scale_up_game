extends GutTest

## TutorialDialog 测试: 多页分步导航 + 「不再显示」勾选经 finished 信号上抛。
## dialog 不写 Preferences (由 main.gd 落盘), 故测试无副作用。
## Per design/教程与帮助系统设计.md §1。

const TutorialDialog := preload("res://scenes/ui/tutorial_dialog/tutorial_dialog.gd")

var _dlg

func before_each() -> void:
	TranslationServer.set_locale("zh_CN")
	_dlg = TutorialDialog.new()
	add_child_autofree(_dlg)

func after_each() -> void:
	# 切 locale 的测试别把 en 泄漏给下游 UI 测试 (memory: i18n 测试钉 zh_CN)。
	TranslationServer.set_locale("zh_CN")

# ─── 多页导航 ─────────────────────────────────────────────────

func test_has_multiple_pages() -> void:
	assert_gt(_dlg.page_count(), 1, "新手引导应是多页")

func test_starts_on_first_page() -> void:
	assert_eq(_dlg.current_page_index(), 0)

func test_go_next_advances() -> void:
	_dlg.go_next()
	assert_eq(_dlg.current_page_index(), 1)

func test_go_prev_goes_back() -> void:
	_dlg.go_next()
	_dlg.go_next()
	_dlg.go_prev()
	assert_eq(_dlg.current_page_index(), 1)

func test_go_prev_clamped_at_first() -> void:
	_dlg.go_prev()
	assert_eq(_dlg.current_page_index(), 0, "首页再上一步应钉在 0")

func test_go_next_clamped_at_last() -> void:
	for _i in range(_dlg.page_count() + 3):
		_dlg.go_next()
	assert_eq(_dlg.current_page_index(), _dlg.page_count() - 1,
			"末页再下一步应钉在最后一页")

func test_each_page_has_title_and_body() -> void:
	for i in range(_dlg.page_count()):
		_dlg.go_to_page_for_test(i)
		assert_ne(_dlg.current_title_for_test(), "", "第 %d 页标题非空" % i)
		assert_ne(_dlg.current_body_for_test(), "", "第 %d 页正文非空" % i)

func test_page_keys_have_translation() -> void:
	# 基线 locale zh_CN: 已定义 key 的 tr() 返回中文 (≠ key 本身)。
	TranslationServer.set_locale("zh_CN")
	for page in TutorialDialog.PAGES:
		assert_ne(tr(page.title), String(page.title),
				"标题 key 无翻译: %s" % page.title)
		assert_ne(tr(page.body), String(page.body),
				"正文 key 无翻译: %s" % page.body)

# ─── 「不再显示」+ finished 信号 ──────────────────────────────

func test_skip_unchecked_by_default() -> void:
	assert_false(_dlg.is_skip_checked(), "默认不勾「不再显示」")

func test_finish_emits_finished_false_when_unchecked() -> void:
	watch_signals(_dlg)
	_go_to_last()
	_dlg.confirm_for_test()
	assert_signal_emitted_with_parameters(_dlg, "finished", [false])

func test_finish_emits_finished_true_when_checked() -> void:
	watch_signals(_dlg)
	_dlg.set_skip_checked(true)
	_go_to_last()
	_dlg.confirm_for_test()
	assert_signal_emitted_with_parameters(_dlg, "finished", [true])

func test_confirm_before_last_page_does_not_finish() -> void:
	# 非末页点「下一步」只翻页, 不应 emit finished。
	watch_signals(_dlg)
	_dlg.confirm_for_test()
	assert_signal_not_emitted(_dlg, "finished",
			"非末页确认不应结束引导")
	assert_eq(_dlg.current_page_index(), 1, "非末页确认应前进一页")

func _go_to_last() -> void:
	_dlg.go_to_page_for_test(_dlg.page_count() - 1)

# ─── 实时切语言 (开着对话框时) ────────────────────────────────

func test_locale_switch_refreshes_open_dialog() -> void:
	_dlg.go_to_page_for_test(1)
	TranslationServer.set_locale("zh_CN")
	EventBus.locale_changed.emit("zh_CN")
	var zh_title: String = _dlg.current_title_for_test()
	var zh_body: String = _dlg.current_body_for_test()
	TranslationServer.set_locale("en")
	EventBus.locale_changed.emit("en")
	var en_title: String = _dlg.current_title_for_test()
	var en_body: String = _dlg.current_body_for_test()
	assert_ne(zh_title, en_title, "切语言应实时刷新当前页标题")
	assert_ne(zh_body, en_body, "切语言应实时刷新当前页正文")
	assert_eq(en_title, "Training a model", "en 下第 2 页标题应为英文")
