extends AcceptDialog

## TutorialDialog — 新游戏开局的多页分步新手引导。Per design/教程与帮助系统设计.md §1。
##
## 多页: 每页 {title, body} 两个 i18n key (正文 cell 内用字面 \n 换行, build_translations
## 会转真实换行)。OK 按钮非末页文案为「下一步」、末页为「开始游戏」; 另加一个「上一步」
## 自定义按钮 (首页禁用); 底部「不再显示」勾选 + 页码。
##
## 对话框不写 Preferences —— 末页确认时 emit finished(dont_show_again: bool), 由 main.gd
## 负责落 Preferences.set_skip_intro(...) 并 queue_free (仿 HonorDialog "组件不碰全局态")。

signal finished(dont_show_again: bool)

# 页序: 欢迎/回合制 → 训练模型 → 创建&影响产品 → 指引帮助。文案在 strings.csv (HELP/TUTORIAL_*)。
const PAGES: Array = [
	{title = "TUTORIAL_P1_TITLE", body = "TUTORIAL_P1_BODY"},
	{title = "TUTORIAL_P2_TITLE", body = "TUTORIAL_P2_BODY"},
	{title = "TUTORIAL_P3_TITLE", body = "TUTORIAL_P3_BODY"},
	{title = "TUTORIAL_P4_TITLE", body = "TUTORIAL_P4_BODY"},
]

var _page: int = 0
var _title_label: Label
var _body: RichTextLabel
var _page_indicator: Label
var _skip_check: CheckBox
var _prev_btn: Button

func _ready() -> void:
	title = tr("TUTORIAL_TITLE")
	dialog_hide_on_ok = false  # OK 用来翻页, 只有末页才真正关闭
	min_size = Vector2i(720, 540)

	# 「上一步」自定义按钮 (OK 左侧)。custom_action 信号带 action StringName。
	_prev_btn = add_button(tr("TUTORIAL_PREV"), false, "prev")

	var root := VBoxContainer.new()
	root.add_theme_constant_override(&"separation", UITheme.S_3)
	add_child(root)

	_title_label = Label.new()
	_title_label.add_theme_font_override(&"font", UITheme.get_ui_font_bold())
	_title_label.add_theme_font_size_override(&"font_size", UITheme.FS_XL)
	_title_label.add_theme_color_override(&"font_color", UITheme.TEXT_PRIMARY)
	root.add_child(_title_label)

	# 正文套定高 ScrollContainer, 避免长文把 OK/上一步按钮顶出窗口 (memory)。
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 340)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	_body = RichTextLabel.new()
	_body.bbcode_enabled = false
	_body.fit_content = true
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.custom_minimum_size = Vector2(660, 0)
	_body.add_theme_font_size_override(&"normal_font_size", UITheme.FS_MD)
	_body.add_theme_color_override(&"default_color", UITheme.TEXT_PRIMARY)
	scroll.add_child(_body)

	# 底部: 页码 (左) + 「不再显示」(右)。
	var footer := HBoxContainer.new()
	footer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(footer)
	_page_indicator = Label.new()
	_page_indicator.add_theme_color_override(&"font_color", UITheme.TEXT_SECONDARY)
	footer.add_child(_page_indicator)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	_skip_check = CheckBox.new()
	_skip_check.text = tr("TUTORIAL_SKIP")
	footer.add_child(_skip_check)

	confirmed.connect(_on_confirm)
	custom_action.connect(_on_custom_action)
	# 开着对话框时切语言即时刷新 (对齐 SettingsDialog)。关闭时随节点释放自动断开。
	EventBus.locale_changed.connect(_on_locale_changed)
	_render_page()

## 实时切语言: 重设静态文案 (标题 / 上一步 / 不再显示) + 重渲染当前页。
func _on_locale_changed(_loc: String = "") -> void:
	title = tr("TUTORIAL_TITLE")
	if _prev_btn != null:
		_prev_btn.text = tr("TUTORIAL_PREV")
	if _skip_check != null:
		_skip_check.text = tr("TUTORIAL_SKIP")
	_render_page()

# ─── 导航 ─────────────────────────────────────────────────────

func _on_custom_action(action: StringName) -> void:
	if action == &"prev":
		go_prev()

func _on_confirm() -> void:
	# OK 按钮: 非末页 → 翻到下一页; 末页 → 结束引导。
	if _page < PAGES.size() - 1:
		go_next()
	else:
		finished.emit(is_skip_checked())
		hide()

func go_next() -> void:
	go_to_page_for_test(_page + 1)

func go_prev() -> void:
	go_to_page_for_test(_page - 1)

func _render_page() -> void:
	var p: Dictionary = PAGES[_page]
	_title_label.text = tr(String(p.title))
	_body.text = tr(String(p.body))
	_page_indicator.text = tr("TUTORIAL_PAGE_FMT") % [_page + 1, PAGES.size()]
	get_ok_button().text = (tr("TUTORIAL_START") if _page == PAGES.size() - 1
			else tr("TUTORIAL_NEXT"))
	if _prev_btn != null:
		_prev_btn.disabled = (_page == 0)

# ─── 打开 ─────────────────────────────────────────────────────

func open() -> void:
	go_to_page_for_test(0)
	popup_centered()

# ─── 测试 introspection ───────────────────────────────────────

func page_count() -> int:
	return PAGES.size()

func current_page_index() -> int:
	return _page

func go_to_page_for_test(i: int) -> void:
	_page = clampi(i, 0, PAGES.size() - 1)
	_render_page()

func set_skip_checked(on: bool) -> void:
	if _skip_check != null:
		_skip_check.button_pressed = on

func is_skip_checked() -> bool:
	return _skip_check != null and _skip_check.button_pressed

func current_title_for_test() -> String:
	return _title_label.text if _title_label != null else ""

func current_body_for_test() -> String:
	return _body.text if _body != null else ""

func confirm_for_test() -> void:
	_on_confirm()
