extends GutTest

## Tests for UITheme — design token constants and the resources/ui/theme.tres
## loading flow. Per design/UI视觉系统设计.md §2 + §3.
##
## 约定:
##   - 所有视觉常量集中在 UITheme autoload, UI 代码不再硬编码颜色/字号/尺寸.
##   - resources/ui/theme.tres 装控件 StyleBox/字号映射, install() 把它合进
##     ThemeDB.default_theme, 这样所有 Control 默认就长成深色科技感.

const THEME_PATH := "res://resources/ui/theme.tres"
const DIALOG_TITLE_FONT_TYPES: Array[StringName] = [
	&"Window",
	&"AcceptDialog",
	&"ConfirmationDialog",
	&"FileDialog",
	&"PopupPanel",
]
const DROPDOWN_BUTTON_TYPES: Array[StringName] = [
	&"OptionButton",
	&"MenuButton",
]
const LIGHT_BUTTON_TYPES: Array[StringName] = [
	&"Button",
	&"OptionButton",
	&"MenuButton",
]
const CHECK_TYPES: Array[StringName] = [
	&"CheckBox",
	&"CheckButton",
]

# ─── §2.1 颜色 ─────────────────────────────────────────────────

func test_color_tokens_match_design_doc() -> void:
	# Google Cloud 控制台调色板, 与 design/UI视觉系统设计.md §2.1 一致。
	assert_eq(UITheme.BG_BASE, Color("#f1f3f4"))
	assert_eq(UITheme.BG_SURFACE, Color("#ffffff"))
	assert_eq(UITheme.BG_ELEVATED, Color("#e8eaed"))
	assert_eq(UITheme.BORDER_SUBTLE, Color("#dadce0"))
	assert_eq(UITheme.BORDER_STRONG, Color("#9aa0a6"))
	assert_eq(UITheme.TEXT_PRIMARY, Color("#202124"))
	assert_eq(UITheme.TEXT_SECONDARY, Color("#5f6368"))
	assert_eq(UITheme.TEXT_DISABLED, Color("#9aa0a6"))
	assert_eq(UITheme.ACCENT_PRIMARY, Color("#1e8e3e"))
	assert_eq(UITheme.ACCENT_WARNING, Color("#e37400"))
	assert_eq(UITheme.ACCENT_DANGER, Color("#d93025"))
	# 品牌走黑灰白: 交互主调改炭黑, 激活浅底改浅灰 (原 Google blue 已去)。
	assert_eq(UITheme.ACCENT_INFO, Color("#202124"))
	assert_eq(UITheme.ACCENT_INFO_SUBTLE, Color("#e8eaed"))

func test_rank_honor_colors_defined() -> void:
	# 荣耀榜单前 3 名奖章用色 (design/竞争对手系统设计.md §8)。
	assert_eq(UITheme.RANK_GOLD, Color("#f4b400"))
	assert_eq(UITheme.RANK_SILVER, Color("#bdc1c6"))
	assert_eq(UITheme.RANK_BRONZE, Color("#cd7f32"))
	# 三色彼此可区分 (金 ≠ 银 ≠ 铜)。
	assert_ne(UITheme.RANK_GOLD, UITheme.RANK_SILVER)
	assert_ne(UITheme.RANK_SILVER, UITheme.RANK_BRONZE)

# ─── §2.2 字号阶 ───────────────────────────────────────────────

func test_font_size_scale_matches_design_doc() -> void:
	assert_eq(UITheme.FS_XS, 11)
	assert_eq(UITheme.FS_SM, 12)
	assert_eq(UITheme.FS_BASE, 13)
	assert_eq(UITheme.FS_MD, 15)
	assert_eq(UITheme.FS_LG, 18)
	assert_eq(UITheme.FS_XL, 22)
	assert_eq(UITheme.FS_XXL, 28)

func test_legacy_default_font_size_alias_kept() -> void:
	# 旧字段 DEFAULT_FONT_SIZE 仍被 install() 引用, 必须等于新的 FS_BASE.
	assert_eq(UITheme.DEFAULT_FONT_SIZE, UITheme.FS_BASE)

func test_hero_font_scale_is_larger_than_console_body() -> void:
	# 全屏 / hero 字号档 (起始页等单焦点页面), 必须明显大于控制台正文档,
	# 否则放满屏会偏小 (design/UI视觉系统设计.md §2 字号双档制)。
	assert_gt(UITheme.FS_HERO, UITheme.FS_XXL,
		"hero 主标题必须比控制台最大字号 FS_XXL 还大")
	assert_gt(UITheme.FS_HERO_SUB, UITheme.FS_MD,
		"hero 副标题 / 主按钮字号必须比控制台卡片标题大")
	assert_gt(UITheme.FS_HERO, UITheme.FS_HERO_SUB,
		"hero 主标题必须比 hero 副标题大")

# ─── §2.3 圆角 / 间距 ─────────────────────────────────────────

func test_radius_scale() -> void:
	assert_eq(UITheme.R_SM, 4)
	assert_eq(UITheme.R_MD, 8)
	assert_eq(UITheme.R_LG, 12)

func test_spacing_scale_is_4_based() -> void:
	assert_eq(UITheme.S_1, 4)
	assert_eq(UITheme.S_2, 8)
	assert_eq(UITheme.S_3, 12)
	assert_eq(UITheme.S_4, 16)
	assert_eq(UITheme.S_5, 20)
	assert_eq(UITheme.S_6, 24)
	assert_eq(UITheme.S_8, 32)
	assert_eq(UITheme.S_10, 40)

# ─── §2.4 关键尺寸 ─────────────────────────────────────────────

func test_layout_size_tokens() -> void:
	assert_eq(UITheme.TOP_BAR_H, 48)
	assert_eq(UITheme.SIDEBAR_W, 220)
	assert_eq(UITheme.SIDEBAR_W_COLLAPSED, 56)
	assert_eq(UITheme.SIDEBAR_ITEM_H, 38)
	assert_eq(UITheme.SIDEBAR_ICON_TILE, 28)
	assert_eq(UITheme.SIDEBAR_ICON_GLYPH_SIZE, 20)
	assert_eq(UITheme.SIDEBAR_ACTIVE_BAR_W, 3)
	assert_eq(UITheme.DRAWER_W, 360)
	assert_eq(UITheme.CARD_AVATAR_SIZE, 112)   # 紧凑缩略图, 把空间还给文字 (§8.3)
	assert_eq(UITheme.CARD_MIN_W, 336)         # 更紧凑, 一屏多放
	assert_eq(UITheme.CARD_MIN_H, 196)
	assert_eq(UITheme.BUTTON_H, 32)
	assert_eq(UITheme.CREATE_BUTTON_H, 40)
	assert_eq(UITheme.CHIP_H, 28)
	assert_gt(UITheme.LIST_MAX_W, 0)           # 竖排列表 / 行宽收口上限 (§9)

# ─── §9bis 高 DPI 缩放 ────────────────────────────────────────

func test_compute_ui_scale_is_1_at_1080p() -> void:
	# 设计基准 1080p → 不缩放。
	assert_almost_eq(UITheme.compute_ui_scale(1080.0), 1.0, 0.0001)

func test_compute_ui_scale_grows_with_resolution() -> void:
	# 1440p ≈ 1.33, 2160p = 2.0 (design/UI视觉系统设计.md §9bis)。
	assert_almost_eq(UITheme.compute_ui_scale(1440.0), 1440.0 / 1080.0, 0.0001)
	assert_almost_eq(UITheme.compute_ui_scale(2160.0), 2.0, 0.0001)
	assert_gt(UITheme.compute_ui_scale(1440.0), UITheme.compute_ui_scale(1080.0),
		"分辨率越高缩放越大")

func test_compute_ui_scale_clamps_below_base_to_1() -> void:
	# 低于 1080 不缩小, 否则更小屏字更小 (clamp 下限 1.0)。
	assert_almost_eq(UITheme.compute_ui_scale(720.0), 1.0, 0.0001)

func test_compute_ui_scale_caps_at_max() -> void:
	assert_almost_eq(UITheme.compute_ui_scale(100000.0), UITheme.MAX_UI_SCALE, 0.0001)

func test_effective_ui_scale_uses_manual_override_when_set() -> void:
	var saved: float = Preferences.ui_scale
	Preferences.ui_scale = 1.75
	assert_almost_eq(UITheme.effective_ui_scale(), 1.75, 0.0001,
		"ui_scale>0 时 effective 应直接用手动档")
	Preferences.ui_scale = 0.0
	assert_gte(UITheme.effective_ui_scale(), 1.0,
		"自动档 effective 不应小于 1.0")
	Preferences.ui_scale = saved

# ─── §2.5 z-order ─────────────────────────────────────────────

func test_z_order_layers_strictly_ordered() -> void:
	# 顶栏与侧栏同层, 抽屉在上, 旧 modal 再上, toast 最高.
	assert_true(UITheme.Z_MAIN < UITheme.Z_TOP_BAR, "main 必须低于 top_bar")
	assert_eq(UITheme.Z_TOP_BAR, UITheme.Z_SIDEBAR)
	assert_true(UITheme.Z_TOP_BAR < UITheme.Z_DRAWER, "drawer 必须高于顶栏/侧栏")
	assert_true(UITheme.Z_DRAWER < UITheme.Z_MODAL_LEGACY, "modal 必须高于 drawer")
	assert_true(UITheme.Z_MODAL_LEGACY < UITheme.Z_TOAST, "toast 必须最高")

# ─── helper: 按 token 名取 token ──────────────────────────────

func test_color_lookup_helper_resolves_known_tokens() -> void:
	assert_eq(UITheme.color(&"bg_base"), UITheme.BG_BASE)
	assert_eq(UITheme.color(&"bg_surface"), UITheme.BG_SURFACE)
	assert_eq(UITheme.color(&"accent_primary"), UITheme.ACCENT_PRIMARY)
	assert_eq(UITheme.color(&"accent_danger"), UITheme.ACCENT_DANGER)
	assert_eq(UITheme.color(&"accent_info_subtle"), UITheme.ACCENT_INFO_SUBTLE)
	assert_eq(UITheme.color(&"text_secondary"), UITheme.TEXT_SECONDARY)
	assert_eq(UITheme.color(&"rank_gold"), UITheme.RANK_GOLD)
	assert_eq(UITheme.color(&"rank_silver"), UITheme.RANK_SILVER)
	assert_eq(UITheme.color(&"rank_bronze"), UITheme.RANK_BRONZE)

func test_color_lookup_helper_unknown_returns_magenta_sentinel() -> void:
	# 未注册的 token 返回 Color.MAGENTA 作为兜底, 方便 UI 上一眼看出拼错.
	assert_eq(UITheme.color(&"no_such_token"), Color.MAGENTA)

func test_font_size_lookup_helper_resolves_known_tokens() -> void:
	assert_eq(UITheme.fs(&"xs"), UITheme.FS_XS)
	assert_eq(UITheme.fs(&"base"), UITheme.FS_BASE)
	assert_eq(UITheme.fs(&"lg"), UITheme.FS_LG)
	assert_eq(UITheme.fs(&"xxl"), UITheme.FS_XXL)

# ─── §3 theme.tres 资源 ────────────────────────────────────────

func test_theme_tres_exists_at_documented_path() -> void:
	assert_true(ResourceLoader.exists(THEME_PATH),
		"design §3 要求存在 " + THEME_PATH)

func test_theme_tres_loads_as_theme() -> void:
	if not ResourceLoader.exists(THEME_PATH):
		pending("theme.tres 还没创建")
		return
	var res: Resource = load(THEME_PATH)
	assert_true(res is Theme, "theme.tres 必须是 Theme 资源")

func test_dialog_embedded_border_fills_title_strip() -> void:
	# 回归: Godot 4.3 把 embedded_border 只画在内容矩形, 标题栏在其上方默认无填充;
	# 必须靠 expand_margin_top + 不透明 bg 把白底向上延伸盖住标题栏, 否则浅色 Dialog
	# 顶部透出背后主界面。Per design/UI视觉系统设计.md §10bis.5。
	if not ResourceLoader.exists(THEME_PATH):
		pending("theme.tres 还没创建")
		return
	var theme: Theme = load(THEME_PATH)
	for t in DIALOG_TITLE_FONT_TYPES:
		var sb: StyleBox = theme.get_stylebox(&"embedded_border", t)
		assert_not_null(sb, "%s 必须有 embedded_border stylebox" % t)
		if sb is StyleBoxFlat:
			assert_gt(sb.get_expand_margin(SIDE_TOP), 0.0,
					"%s 的 embedded_border 必须 expand_margin_top>0 以盖住标题栏" % t)
			assert_almost_eq((sb as StyleBoxFlat).bg_color.a, 1.0, 0.001,
					"%s 标题栏底色必须不透明" % t)

# ─── §3 install() 后视觉应用到 ThemeDB.default_theme ─────────

func test_install_keeps_font_contract() -> void:
	# 旧契约保留: 字体仍被注入, 默认字号 = FS_BASE.
	UITheme.install()
	var default_theme := ThemeDB.get_default_theme()
	assert_not_null(default_theme.default_font, "默认字体必须被注入")
	assert_eq(default_theme.default_font_size, UITheme.FS_BASE)

func test_install_disables_system_fallback_on_ui_font() -> void:
	UITheme.install()
	var font := UITheme.get_ui_font()
	assert_not_null(font, "UITheme 必须加载开发期 CJK 字体")
	if font != null and font.has_method("is_allow_system_fallback"):
		assert_false(font.is_allow_system_fallback(),
			"UI 字体必须关闭 system fallback, 避免空系统字体路径刷 FreeType 红字")

func test_preferred_font_files_cover_windows_and_macos_native_cjk() -> void:
	var mac_regular := UITheme.preferred_ui_font_files_for_os("macOS", false)
	var mac_bold := UITheme.preferred_ui_font_files_for_os("macOS", true)
	var win_regular := UITheme.preferred_ui_font_files_for_os("Windows", false)
	var win_bold := UITheme.preferred_ui_font_files_for_os("Windows", true)
	assert_true(_font_candidates_include(mac_regular, "/System/Library/Fonts/PingFang.ttc"),
		"macOS 应优先尝试 PingFang 字体文件")
	assert_true(_font_candidates_include(mac_regular, "/System/Library/Fonts/Hiragino Sans GB.ttc"),
		"macOS 应保留 Hiragino Sans GB 兜底")
	assert_true(_font_candidates_include(mac_bold, "/System/Library/Fonts/Hiragino Sans GB.ttc"),
		"macOS bold 应能使用 Hiragino Sans GB 的 W6 face")
	assert_true(_font_candidates_include(win_regular, "C:/Windows/Fonts/msyh.ttc"),
		"Windows 应优先尝试微软雅黑字体文件")
	assert_true(_font_candidates_include(win_regular, "C:/Windows/Fonts/Deng.ttf"),
		"Windows 应保留等线兜底")
	assert_true(_font_candidates_include(win_bold, "C:/Windows/Fonts/msyhbd.ttc"),
		"Windows bold 应优先尝试微软雅黑 bold 字体文件")

func test_system_font_strategy_only_runs_in_real_windows_or_macos_display() -> void:
	assert_true(UITheme.should_use_system_ui_font("macOS", "macos", false),
		"真实 macOS 窗口运行时应启用系统中文 UI 字体文件")
	assert_true(UITheme.should_use_system_ui_font("Windows", "windows", false),
		"真实 Windows 窗口运行时应启用系统中文 UI 字体文件")
	assert_false(UITheme.should_use_system_ui_font("macOS", "headless", false),
		"headless 下固定用内置字体, 避免测试受宿主系统字体影响")
	assert_false(UITheme.should_use_system_ui_font("Windows", "windows", true),
		"GUT / 测试运行必须固定用内置字体, 保持 hermetic")
	assert_false(UITheme.should_use_system_ui_font("Linux", "x11", false),
		"Linux 字体环境差异太大, 当前先固定用内置 Noto")

func test_headless_test_run_uses_bundled_cjk_font() -> void:
	var font := UITheme.get_ui_font()
	assert_not_null(font, "UITheme 必须返回 UI 字体")
	assert_false(font is SystemFont,
		"GUT/headless 应直接使用内置 Noto, 不走 SystemFont")
	assert_eq(font.get_font_name(), "Noto Sans CJK SC",
		"测试环境默认字体应是随包分发的 Noto Sans CJK SC")

func test_headless_test_run_uses_bundled_bold_cjk_font() -> void:
	var bold := UITheme.get_ui_font_bold()
	assert_not_null(bold, "UITheme 必须返回 bold UI 字体")
	assert_false(bold is SystemFont,
		"GUT/headless 的 bold 字体也应直接使用内置 Noto Bold")
	assert_eq(bold.get_font_name(), "Noto Sans CJK SC",
		"测试环境 bold 字体应来自随包分发的 Noto Sans CJK SC Bold")
	assert_gte(bold.get_font_weight(), 700,
			"内置 bold 字体必须是真 bold 字重")

func _font_candidates_include(candidates: Array[Dictionary], expected_path: String) -> bool:
	for candidate in candidates:
		if String(candidate.get("path", "")) == expected_path:
			return true
	return false

func test_get_ui_font_bold_returns_a_font() -> void:
	# bold 字重给标题 / 区段头补层级 (design/UI视觉系统设计.md §2.2)。
	var bold := UITheme.get_ui_font_bold()
	assert_not_null(bold, "UITheme 必须能加载 bold 字重字体")
	assert_true(bold is Font, "get_ui_font_bold() 必须返回 Font")

func test_get_icon_font_returns_a_font() -> void:
	# Material Icons 图标字体, 侧栏导航图标按码点渲染。
	var icon_font := UITheme.get_icon_font()
	assert_not_null(icon_font, "UITheme 必须能加载 Material Icons 图标字体")
	assert_true(icon_font is Font, "get_icon_font() 必须返回 Font")

func test_install_applies_cjk_font_to_dialog_title_fonts() -> void:
	# 弹窗标题不走普通 Label/font; 必须显式覆盖 title_font (用 bold 字重)。
	UITheme.install()
	var expected_font := UITheme.get_ui_font_bold()
	var default_theme := ThemeDB.get_default_theme()
	assert_not_null(expected_font, "UITheme 必须加载 bold 字重字体")
	for control_type in DIALOG_TITLE_FONT_TYPES:
		var actual_font := default_theme.get_font(&"title_font", control_type)
		assert_not_null(actual_font,
			"%s/title_font 必须能解析到字体" % String(control_type))
		if expected_font != null and actual_font != null:
			assert_eq(actual_font.get_font_name(), expected_font.get_font_name(),
				"%s/title_font 必须使用 UITheme CJK 字体" % String(control_type))
		assert_eq(default_theme.get_font_size(&"title_font_size", control_type), UITheme.FS_MD,
			"%s/title_font_size 必须与弹窗标题字号约定一致" % String(control_type))

func test_install_applies_panel_surface_from_theme_tres() -> void:
	# theme.tres 提供 Panel/PanelContainer 的深色 StyleBoxFlat (BG_SURFACE).
	# install() 完成后, 任意 Panel 取 stylebox 应当拿到这个深色背景.
	UITheme.install()
	var default_theme := ThemeDB.get_default_theme()
	var sb := default_theme.get_stylebox(&"panel", &"PanelContainer")
	assert_true(sb is StyleBoxFlat,
		"PanelContainer 的 panel stylebox 必须是 StyleBoxFlat (来自 theme.tres)")
	if sb is StyleBoxFlat:
		var flat := sb as StyleBoxFlat
		# Theme 序列化把 Color 截到 6 位有效数字, 回读会有亚千分之一的浮点
		# 漂移; 视觉上完全一致, 用 is_equal_approx 而不是 ==。
		assert_true(flat.bg_color.is_equal_approx(UITheme.BG_SURFACE),
			"PanelContainer 默认背景必须近似等于 BG_SURFACE, 实际 %s" % flat.bg_color)
		assert_eq(flat.corner_radius_top_left, UITheme.R_MD)
		assert_eq(flat.corner_radius_top_right, UITheme.R_MD)

func test_button_pressed_style_has_downward_nudge() -> void:
	var theme: Theme = load(THEME_PATH)
	var normal := theme.get_stylebox(&"normal", &"Button")
	var pressed := theme.get_stylebox(&"pressed", &"Button")
	assert_true(normal is StyleBoxFlat, "Button/normal 应是 StyleBoxFlat")
	assert_true(pressed is StyleBoxFlat, "Button/pressed 应是 StyleBoxFlat")
	if normal is StyleBoxFlat and pressed is StyleBoxFlat:
		var n := normal as StyleBoxFlat
		var p := pressed as StyleBoxFlat
		assert_gt(int(p.content_margin_top), int(n.content_margin_top),
			"pressed top margin 应多 1px, 做视觉下压")
		assert_lt(int(p.content_margin_bottom), int(n.content_margin_bottom),
			"pressed bottom margin 应少 1px, 总高度保持稳定")

func test_light_button_text_states_remain_readable_on_white() -> void:
	var theme: Theme = load(THEME_PATH)
	for control_type in LIGHT_BUTTON_TYPES:
		for color_name in [&"font_color", &"font_hover_color", &"font_pressed_color",
				&"font_hover_pressed_color", &"font_focus_color"]:
			assert_true(theme.has_color(color_name, control_type),
				"%s/%s 必须显式设置, 避免白底按钮掉回白字" % [String(control_type), String(color_name)])
			if theme.has_color(color_name, control_type):
				assert_false(theme.get_color(color_name, control_type).is_equal_approx(UITheme.BG_SURFACE),
					"%s/%s 不能是白色, 否则浅色按钮文字不可见" % [String(control_type), String(color_name)])
		assert_true(theme.has_color(&"font_disabled_color", control_type),
			"%s/font_disabled_color 必须显式设置" % String(control_type))

func test_checkbox_and_checkbutton_icons_are_light_theme_safe() -> void:
	var theme: Theme = load(THEME_PATH)
	for control_type in CHECK_TYPES:
		for icon_name in [&"checked", &"unchecked", &"checked_disabled", &"unchecked_disabled"]:
			assert_true(theme.has_icon(icon_name, control_type),
				"%s/%s 必须由浅色主题显式提供, 不能依赖默认深色图标" %
				[String(control_type), String(icon_name)])
			if theme.has_icon(icon_name, control_type):
				var icon := theme.get_icon(icon_name, control_type)
				assert_gte(icon.get_width(), 16,
					"%s/%s 宽度应足够形成可点击视觉锚点" %
					[String(control_type), String(icon_name)])
				assert_gte(icon.get_height(), 16,
					"%s/%s 高度应足够形成可点击视觉锚点" %
					[String(control_type), String(icon_name)])

func test_apply_button_variant_primary_styles_button() -> void:
	var b := Button.new()
	add_child_autofree(b)
	UITheme.apply_button_variant(b, &"primary")
	assert_gte(int(b.custom_minimum_size.y), UITheme.BUTTON_H,
		"常用按钮变体应保证点击目标高度")
	var normal := b.get_theme_stylebox(&"normal")
	assert_true(normal is StyleBoxFlat, "primary normal style 应是 StyleBoxFlat")
	if normal is StyleBoxFlat:
		assert_true((normal as StyleBoxFlat).bg_color.is_equal_approx(UITheme.ACCENT_INFO),
			"primary 应使用炭黑实心底")
	assert_true(b.get_theme_color(&"font_color").is_equal_approx(UITheme.BG_SURFACE),
		"primary 字色应为白色表面色")

func test_apply_button_variant_create_styles_prominent_cta() -> void:
	var b := Button.new()
	add_child_autofree(b)
	UITheme.apply_button_variant(b, &"create")
	assert_gte(int(b.custom_minimum_size.y), UITheme.CREATE_BUTTON_H,
		"create 变体用于新建类 CTA, 点击目标应明显高于普通按钮")
	assert_eq(b.get_theme_font_size(&"font_size"), UITheme.FS_MD,
		"create 变体字号应比普通按钮更醒目")
	var normal := b.get_theme_stylebox(&"normal")
	assert_true(normal is StyleBoxFlat, "create normal style 应是 StyleBoxFlat")
	if normal is StyleBoxFlat:
		assert_true((normal as StyleBoxFlat).bg_color.is_equal_approx(UITheme.ACCENT_INFO),
			"create CTA 应沿用炭黑实心主色")
		assert_gt(int((normal as StyleBoxFlat).content_margin_left), UITheme.S_3,
			"create CTA 左右留白应大于普通按钮")
	assert_true(b.get_theme_color(&"font_color").is_equal_approx(UITheme.BG_SURFACE),
		"create CTA 字色应为白色表面色")

func test_dialog_embedded_title_area_is_opaque_and_sized() -> void:
	var theme: Theme = load(THEME_PATH)
	for control_type in DIALOG_TITLE_FONT_TYPES:
		assert_true(theme.has_constant(&"title_height", control_type),
			"%s/title_height 必须显式设置, 避免 Dialog 顶部透明" % String(control_type))
		assert_gte(theme.get_constant(&"title_height", control_type), UITheme.BUTTON_H,
			"%s/title_height 必须至少容纳标题和关闭按钮" % String(control_type))
		for style_name in [&"embedded_border", &"embedded_unfocused_border"]:
			var sb := theme.get_stylebox(style_name, control_type)
			assert_true(sb is StyleBoxFlat,
				"%s/%s 必须是 StyleBoxFlat" % [String(control_type), String(style_name)])
			if sb is StyleBoxFlat:
				var flat := sb as StyleBoxFlat
				assert_true(flat.bg_color.a >= 0.99,
					"%s/%s 背景必须不透明" % [String(control_type), String(style_name)])
				assert_gte(int(flat.content_margin_top), UITheme.S_10,
					"%s/%s 顶部内容边距必须覆盖标题栏" % [String(control_type), String(style_name)])

func test_dropdown_hover_pressed_text_colors_are_explicit() -> void:
	var theme: Theme = load(THEME_PATH)
	for control_type in DROPDOWN_BUTTON_TYPES:
		assert_true(theme.has_color(&"font_hover_pressed_color", control_type),
			"%s 必须显式设置 hover+pressed 字色" % String(control_type))
		assert_true(theme.has_color(&"font_focus_color", control_type),
			"%s 必须显式设置 focus 字色" % String(control_type))
		if theme.has_color(&"font_hover_pressed_color", control_type):
			assert_true(theme.get_color(&"font_hover_pressed_color", control_type).is_equal_approx(UITheme.TEXT_PRIMARY),
				"%s hover+pressed 字色应保持可读" % String(control_type))

func test_popup_menu_hover_and_selected_text_colors_are_explicit() -> void:
	var theme: Theme = load(THEME_PATH)
	for color_name in [&"font_hover_color", &"font_selected_color", &"font_selected_hover_color"]:
		assert_true(theme.has_color(color_name, &"PopupMenu"),
			"PopupMenu/%s 必须显式设置, 避免 hover 后文字不可见" % String(color_name))
		if theme.has_color(color_name, &"PopupMenu"):
			assert_true(theme.get_color(color_name, &"PopupMenu").is_equal_approx(UITheme.TEXT_PRIMARY),
				"PopupMenu/%s 应保持 TEXT_PRIMARY" % String(color_name))

# ─── 算力格式化 helper ────────────────────────────────────────

func test_format_compute_picks_magnitude_unit() -> void:
	# ≥100 TFLOPs 取整; <100 留 1 位小数。
	assert_eq(UITheme.format_compute(12.5), "12.5 TFLOPs")
	assert_eq(UITheme.format_compute(278.0), "278 TFLOPs")
	assert_eq(UITheme.format_compute(999.0), "999 TFLOPs")
	# ≥1e3 TFLOPs → PFLOPs。
	assert_eq(UITheme.format_compute(1000.0), "1.00 PFLOPs")
	assert_eq(UITheme.format_compute(2500.0), "2.50 PFLOPs")
	assert_eq(UITheme.format_compute(20000.0), "20.00 PFLOPs")
	# ≥1e6 TFLOPs → EFLOPs (大数据中心: 8000 卡 × 2500 TFLOPs = 20e6)。
	assert_eq(UITheme.format_compute(1.0e6), "1.00 EFLOPs")
	assert_eq(UITheme.format_compute(20.0e6), "20.00 EFLOPs")

func test_format_compute_handles_zero_and_negative() -> void:
	assert_eq(UITheme.format_compute(0.0), "0.0 TFLOPs")
	# 量级判定按绝对值, 负号保留。
	assert_eq(UITheme.format_compute(-5000.0), "-5.00 PFLOPs")

# ─── token 吞吐 / 计数格式化 helper ───────────────────────────

func test_format_tps_picks_magnitude_unit() -> void:
	# ≤0 → 0 t/s; <10 留 1 位小数; <1e3 取整; 之后自动升档 k → M → G。
	assert_eq(UITheme.format_tps(0.0), "0 t/s")
	assert_eq(UITheme.format_tps(5.0), "5.0 t/s")
	assert_eq(UITheme.format_tps(150.0), "150 t/s")
	assert_eq(UITheme.format_tps(2500.0), "2.5k t/s")
	assert_eq(UITheme.format_tps(3_400_000.0), "3.4M t/s")
	assert_eq(UITheme.format_tps(7_200_000_000.0), "7.2G t/s")

func test_format_tokens_picks_magnitude_unit() -> void:
	# <1e3 原值; 之后自动升档 k → M → G → T (不带 tokens 后缀)。
	assert_eq(UITheme.format_tokens(500.0), "500")
	assert_eq(UITheme.format_tokens(51_840_000.0), "51.8M")
	assert_eq(UITheme.format_tokens(2_300_000_000.0), "2.3G")
	assert_eq(UITheme.format_tokens(4_500_000_000_000.0), "4.5T")

func test_format_money_compact_keeps_exact_below_one_million() -> void:
	# 顶栏防溢出: <100 万保持千分位精确 (符号前置, 与 _format_money 行为一致),
	# 让 +$38,000 这类账本数仍精确显示。
	assert_eq(UITheme.format_money_compact(0), "0")
	assert_eq(UITheme.format_money_compact(38_000), "38,000")
	assert_eq(UITheme.format_money_compact(-272_360), "-272,360")
	assert_eq(UITheme.format_money_compact(999_999), "999,999")

func test_format_money_compact_abbreviates_large_magnitudes() -> void:
	# ≥100 万缩成 1.2M / 3.4B / 5.6T (.0 去尾), 负号前置; 大额营收不再撑破 chip。
	assert_eq(UITheme.format_money_compact(1_000_000), "1M")
	assert_eq(UITheme.format_money_compact(1_200_000), "1.2M")
	assert_eq(UITheme.format_money_compact(-2_500_000), "-2.5M")
	assert_eq(UITheme.format_money_compact(3_400_000_000), "3.4B")
	assert_eq(UITheme.format_money_compact(5_600_000_000_000), "5.6T")

# ─── 品牌标记 (Ascent A) 绘制 helper ──────────────────────────

## 在自己的 _draw() 期间调 draw_brand_mark, 模拟起始页 / 顶栏的真实绘制路径。
class _MarkProbe extends Control:
	var drew := false
	func _draw() -> void:
		UITheme.draw_brand_mark(self, Rect2(Vector2.ZERO, size), true)
		drew = true

func test_draw_brand_mark_zero_size_is_safe() -> void:
	# 布局未落定 (size = 0) 时直接 return, 不触发任何 draw_* 调用, 不应崩。
	var c := Control.new()
	add_child_autofree(c)
	UITheme.draw_brand_mark(c, Rect2(Vector2.ZERO, Vector2.ZERO), true)
	UITheme.draw_brand_mark(c, Rect2(Vector2.ZERO, Vector2.ZERO), false)
	assert_true(true, "zero-size 调用安全返回")

func test_draw_brand_mark_renders_in_draw_context() -> void:
	# 起始页 _LogoMark / 顶栏 _TopBarMark 都在 _draw 里调本 helper, 这里验证
	# 该路径能正常跑完一帧绘制而不报错。
	var probe := _MarkProbe.new()
	probe.size = Vector2(88, 88)
	add_child_autofree(probe)
	probe.queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(probe.drew, "_draw 必须被调用并完成 draw_brand_mark")

# ─── 玩家可选公司标志 (LOGO_MARKS) ───────────────────────────

## 在自己的 _draw() 期间调 draw_company_logo, 模拟顶栏 / 新游戏网格的真实绘制路径。
class _LogoProbe extends Control:
	var drew := false
	var logo_id: StringName = &""
	func _draw() -> void:
		UITheme.draw_company_logo(self, Rect2(Vector2.ZERO, size), logo_id, true)
		drew = true

func test_logo_marks_catalog_well_formed() -> void:
	assert_gt(UITheme.LOGO_MARKS.size(), 0, "应有可选公司标志")
	var ids := {}
	for m in UITheme.LOGO_MARKS:
		assert_true(m.has("id") and m.has("shape") and m.has("color"),
			"每个标志需含 id/shape/color: %s" % m)
		assert_ne(StringName(m["id"]), &"", "标志 id 不能为空 (&\"\" 保留给默认 A 标记)")
		assert_false(ids.has(m["id"]), "标志 id 不能重复: %s" % m["id"])
		ids[m["id"]] = true
		assert_true(m["color"] is Color, "color 必须是 Color: %s" % m)

func test_draw_company_logo_zero_size_is_safe() -> void:
	var c := Control.new()
	add_child_autofree(c)
	UITheme.draw_company_logo(c, Rect2(Vector2.ZERO, Vector2.ZERO), &"", true)
	UITheme.draw_company_logo(c, Rect2(Vector2.ZERO, Vector2.ZERO),
		StringName(UITheme.LOGO_MARKS[0]["id"]), true)
	assert_true(true, "zero-size 调用安全返回")

func test_draw_company_logo_renders_known_id() -> void:
	var probe := _LogoProbe.new()
	probe.logo_id = StringName(UITheme.LOGO_MARKS[0]["id"])
	probe.size = Vector2(88, 88)
	add_child_autofree(probe)
	probe.queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(probe.drew, "_draw 必须跑完 draw_company_logo (已知 id)")

func test_draw_company_logo_unknown_id_falls_back_without_crash() -> void:
	# 未知 / 空 id → 回退经典 A 标记, 不崩。
	var probe := _LogoProbe.new()
	probe.logo_id = &"__nope__"
	probe.size = Vector2(88, 88)
	add_child_autofree(probe)
	probe.queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(probe.drew, "未知 id 也应安全跑完绘制")
