extends Node

## UITheme — 视觉系统单例。
##
## 职责 (按 design/UI视觉系统设计.md §2 + §3):
##   1. 暴露设计 token 常量 (颜色 / 字号 / 圆角 / 间距 / 尺寸 / z-order)。
##   2. 注入 CJK 字体到 ThemeDB.default_theme (保留旧契约)。
##   3. 加载 resources/ui/theme.tres 并合并进 default_theme, 让所有 Control
##      默认就长成 Google Cloud 控制台风格 (浅灰底 + Google 蓝交互主调)。
##
## 所有 UI 代码引用颜色 / 字号 / 尺寸都必须从 UITheme.XXX 取值, 严禁硬编码。

## 内置 Noto Sans CJK SC fallback。真实窗口运行时优先按平台加载系统中文 UI 字体文件,
## 这两份随包字体负责跨平台缺字兜底。
const UI_FONT_PATH := "res://assets/fonts/cjk.ttf"
## Bold fallback — 标题 / 区段头 / 顶栏公司名用, 给扁平的单字重 UI 补层级。
const UI_FONT_BOLD_PATH := "res://assets/fonts/cjk-bold.ttf"
## Material Icons 图标字体 — 侧栏导航 / 标签图标按码点渲染。
const UI_ICON_FONT_PATH := "res://assets/fonts/icons.ttf"
const THEME_PATH := "res://resources/ui/theme.tres"
const CONTROL_FONT_TYPES: Array[StringName] = [
	&"Label",
	&"Button",
	&"CheckBox",
	&"CheckButton",
	&"LineEdit",
	&"TextEdit",
	&"OptionButton",
	&"PopupMenu",
	&"MenuButton",
	&"TabBar",
	&"TabContainer",
	&"RichTextLabel",
	&"ItemList",
	&"Tree",
	&"ProgressBar",
	&"TooltipLabel",
	&"Window",
	&"AcceptDialog",
	&"ConfirmationDialog",
	&"FileDialog",
	&"PopupPanel",
]
const TITLE_FONT_TYPES: Array[StringName] = [
	&"Window",
	&"AcceptDialog",
	&"ConfirmationDialog",
	&"FileDialog",
	&"PopupPanel",
]

# ─── §2.1 颜色 (Google Cloud 控制台调色板) ────────────────────

const BG_BASE       := Color("#f1f3f4")  # 页面背景 (Google grey 100)
const BG_SURFACE    := Color("#ffffff")  # 卡片 / 侧栏面板 / 弹窗 (纯白)
const BG_ELEVATED   := Color("#e8eaed")  # hover / 抽屉 / popup (Google grey 200)
const BORDER_SUBTLE := Color("#dadce0")  # 1px 分隔线 / 卡片描边 (Google grey 300)
const BORDER_STRONG := Color("#9aa0a6")  # focus / active (Google grey 500)

const TEXT_PRIMARY   := Color("#202124")  # Google grey 900
const TEXT_SECONDARY := Color("#5f6368")  # Google grey 700
const TEXT_DISABLED  := Color("#9aa0a6")  # Google grey 500

const ACCENT_PRIMARY := Color("#1e8e3e")  # 正向 delta / 进度满档 (Google green 600)
const ACCENT_WARNING := Color("#e37400")  # 警告 / 待处理 (Google orange)
const ACCENT_DANGER  := Color("#d93025")  # 破坏性 / 负向 delta (Google red 600)
const ACCENT_INFO    := Color("#202124")  # 交互主调: 焦点 / 输入 / 链接 / 训练中 (炭黑; 品牌黑灰白, 原 Google blue 已去)
const ACCENT_INFO_SUBTLE := Color("#e8eaed")  # 选中 / 激活项浅灰底 (= BG_ELEVATED; 原浅蓝已去)

# 荣誉色 — 排行榜前 3 名奖章 (荣耀榜单, 见 design/竞争对手系统设计.md §8)。
# 唯一一组暖色, 专给"领奖台"语义; 其它地方一律走上面的 GCP 调色板。
const RANK_GOLD   := Color("#f4b400")  # #1 金
const RANK_SILVER := Color("#bdc1c6")  # #2 银 (Google grey 400)
const RANK_BRONZE := Color("#cd7f32")  # #3 铜

# ─── 顶栏深色玻璃 (见 design/UI视觉系统设计.md §5) ─────────────
# 顶栏改成深色"烟熏玻璃"条: 纵向暗色渐变 (顶亮底暗的玻璃光泽) + 顶部白高光受光边 +
# 底部细分隔线。这是 app 里唯一的深色 chrome, 工作区仍是浅灰; 文字 / 竖线走下面的
# on-dark 档保证对比度。
const TOPBAR_GLASS_BASE    := Color("#202228")  # panel stylebox 实底 (渐变铺在它上面)
const TOPBAR_GLASS_TOP     := Color("#2c2e35")  # 渐变顶 (略亮, 玻璃受光)
const TOPBAR_GLASS_BOTTOM  := Color("#191a1e")  # 渐变底 (近黑)
const TOPBAR_GLASS_HILITE  := Color(1, 1, 1, 0.12)  # 顶部 1px 高光 (玻璃边缘反光)
const TOPBAR_GLASS_BORDER  := Color(1, 1, 1, 0.08)  # 底部 1px 细分隔 (微亮 hairline)
const TOPBAR_GLASS_DIVIDER := Color(1, 1, 1, 0.18)  # 指标簇竖刻线 (亮玻璃刻线)

# 深色背景上的文字 / 强调 (GCP grey/red/green 300 档, 在暗底上保证对比度)。
const TEXT_ON_DARK           := Color("#e8eaed")  # 暗底主文字 (grey 200)
const TEXT_ON_DARK_SECONDARY := Color("#9aa0a6")  # 暗底次文字 / 标签 (grey 500)
const ACCENT_PRIMARY_ON_DARK := Color("#81c995")  # 暗底正向 delta (green 300)
const ACCENT_DANGER_ON_DARK  := Color("#f28b82")  # 暗底负向 / 危险 (red 300)

# ─── 玩家可选公司标志 (LOGO_MARKS) — 见 design/UI视觉系统设计.md §5.1 ───
# 程序化预设标记: 炭黑圆角方块上居中画一个形状 (取强调色)。颜色是玩家个人品牌的
# 选择, 不改全站「黑灰白」基调; 都得在炭黑底 (TEXT_PRIMARY) 上够亮。
const LOGO_PALETTE := {
	&"teal":   Color("#12b5cb"),
	&"green":  Color("#1e8e3e"),
	&"amber":  Color("#f9ab00"),
	&"orange": Color("#e37400"),
	&"rose":   Color("#d93025"),
	&"violet": Color("#a142f4"),
	&"blue":   Color("#1a73e8"),
	&"cyan":   Color("#24c1e0"),
}
# 有序目录 (形状 × 强调色). id 进存档 (GameState.company_logo), shape 由
# draw_company_logo 识别。&"" 不在表里 — 保留给默认抽象「A」标记 (draw_brand_mark)。
const LOGO_MARKS: Array = [
	{id = &"node_teal",    shape = &"circle",   color = Color("#12b5cb")},
	{id = &"cube_amber",   shape = &"square",   color = Color("#f9ab00")},
	{id = &"gem_violet",   shape = &"diamond",  color = Color("#a142f4")},
	{id = &"peak_green",   shape = &"triangle", color = Color("#1e8e3e")},
	{id = &"hex_cyan",     shape = &"hexagon",  color = Color("#24c1e0")},
	{id = &"spark_orange", shape = &"sparkle",  color = Color("#e37400")},
	{id = &"node_rose",    shape = &"circle",   color = Color("#d93025")},
	{id = &"gem_blue",     shape = &"diamond",  color = Color("#1a73e8")},
	{id = &"peak_amber",   shape = &"triangle", color = Color("#f9ab00")},
]

# ─── §2.2 字号阶 ───────────────────────────────────────────────

const FS_XS   := 11  # 标签 / 徽章
const FS_SM   := 12  # 副文本 / 字段名
const FS_BASE := 13  # 正文
const FS_MD   := 15  # 卡片标题 / 按钮
const FS_LG   := 18  # 区段标题
const FS_XL   := 22  # 页面标题
const FS_XXL  := 28  # 顶栏数字 callout

# 全屏 / hero 字号档 — 给"单屏一个焦点"的展示型页面 (起始页 / 出错页等),
# 比上面的控制台正文档大几档, 放满屏才不显小。不与控制台正文混用。
const FS_HERO     := 64  # hero 主标题 (起始页字标)
const FS_HERO_SUB := 20  # hero 副标题 / 主按钮文字

# 兼容旧字段, 保持等价。
const DEFAULT_FONT_SIZE := FS_BASE

# ─── §2.3 圆角 / 间距 ─────────────────────────────────────────

const R_SM := 4   # chip / button
const R_MD := 8   # card
const R_LG := 12  # drawer / dialog

const S_1  := 4
const S_2  := 8
const S_3  := 12
const S_4  := 16
const S_5  := 20
const S_6  := 24
const S_8  := 32
const S_10 := 40

# ─── §2.4 关键尺寸 ─────────────────────────────────────────────

const TOP_BAR_H           := 48
const SIDEBAR_W           := 220
const SIDEBAR_W_COLLAPSED := 56
const SIDEBAR_ITEM_H      := 38
const SIDEBAR_ICON_TILE   := 28
const SIDEBAR_ICON_GLYPH_SIZE := 20
const SIDEBAR_ACTIVE_BAR_W := 3
const DRAWER_W            := 360
# 卡片紧凑缩略图 (2026-05): 112px 保留视觉锚点, 把横向空间还给标题/字段文字。
# 收紧 (2026-05): 卡片最小宽/高下调, 一屏多放; 允许文字换行撑高 (见 §8.3)。
const CARD_AVATAR_SIZE    := 112
const CARD_MIN_W          := 336
const CARD_MIN_H          := 196
const BUTTON_H            := 32
const CREATE_BUTTON_H     := 40
const CHIP_H              := 28
# 竖排列表 / 看板行宽度收口上限 (见 §9): 排行榜、经济看板行不随窗口铺满整屏。
const LIST_MAX_W          := 720

# ─── §9bis 高 DPI 缩放 (见 design/UI视觉系统设计.md §9bis) ─────
# 设计基准高度 1080p; 实际窗口更高时按比例放大 content_scale_factor, 低于不缩小。
const BASE_VIEWPORT_H := 1080.0
const MAX_UI_SCALE    := 2.5   # 超大屏封顶, 防止 UI 占满到不可用

# ─── §2.5 z-order ─────────────────────────────────────────────

const Z_MAIN         := 0
const Z_TOP_BAR      := 100
const Z_SIDEBAR      := 100
const Z_DRAWER       := 200
const Z_MODAL_LEGACY := 300
const Z_TOAST        := 400

# ─── lookup tables (供 helper 查询) ──────────────────────────

const _COLOR_TABLE: Dictionary = {
	&"bg_base":         BG_BASE,
	&"bg_surface":      BG_SURFACE,
	&"bg_elevated":     BG_ELEVATED,
	&"border_subtle":   BORDER_SUBTLE,
	&"border_strong":   BORDER_STRONG,
	&"text_primary":    TEXT_PRIMARY,
	&"text_secondary":  TEXT_SECONDARY,
	&"text_disabled":   TEXT_DISABLED,
	&"accent_primary": ACCENT_PRIMARY,
	&"accent_warning": ACCENT_WARNING,
	&"accent_danger":  ACCENT_DANGER,
	&"accent_info":    ACCENT_INFO,
	&"accent_info_subtle": ACCENT_INFO_SUBTLE,
	&"rank_gold":      RANK_GOLD,
	&"rank_silver":    RANK_SILVER,
	&"rank_bronze":    RANK_BRONZE,
}

const _FS_TABLE: Dictionary = {
	&"xs":   FS_XS,
	&"sm":   FS_SM,
	&"base": FS_BASE,
	&"md":   FS_MD,
	&"lg":   FS_LG,
	&"xl":   FS_XL,
	&"xxl":  FS_XXL,
}

var _font: Font
var _font_bold: Font
var _font_icon: Font
var _font_fallback: Font
var _font_bold_fallback: Font

# ─── 生命周期 ─────────────────────────────────────────────────

func _ready() -> void:
	install()
	# 显示缩放 / 窗口模式只在真实运行时应用; 测试运行不动 headless 窗口 (保持 hermetic)。
	if not _is_test_run():
		apply_window_mode()
		apply_display_scale()
		var w := get_window()
		if w != null and not w.size_changed.is_connected(apply_display_scale):
			# 窗口尺寸变化 (含全屏切换) → 自动档随分辨率重算缩放。
			w.size_changed.connect(apply_display_scale)

func install() -> void:
	# 1. 字体: 先注入 CJK 字体, 保留旧契约。
	var font := get_ui_font()
	var default_theme := ThemeDB.get_default_theme()
	if default_theme == null:
		Log.warn(&"ui", "default theme unavailable")
		return
	if font != null:
		default_theme.default_font = font
		default_theme.default_font_size = FS_BASE
		apply_font_to_theme(default_theme, font)
	else:
		Log.warn(&"ui", "ui font unavailable", {path = UI_FONT_PATH})

	# 2. 视觉主题: 合并 theme.tres 进 default_theme。
	#    Theme.merge_with() 把对方的所有控件 / 颜色 / 字号 / stylebox override
	#    复制到自身, 已有的 key 被覆盖, 没有的保持不变 — 正好是我们要的。
	if ResourceLoader.exists(THEME_PATH):
		var visual_theme: Theme = load(THEME_PATH)
		if visual_theme is Theme:
			default_theme.merge_with(visual_theme)
			if font != null:
				apply_font_to_theme(default_theme, font)
		else:
			Log.warn(&"ui", "theme.tres not a Theme", {path = THEME_PATH})
	else:
		Log.warn(&"ui", "theme.tres missing", {path = THEME_PATH})

func get_ui_font() -> Font:
	if _font != null:
		return _font
	_font_fallback = _load_font_file(UI_FONT_PATH)
	var platform_font := _load_platform_ui_font(false) if _should_use_system_ui_font() else null
	_font = platform_font if platform_font != null else _font_fallback
	return _font

## Material Icons 图标字体 (assets/fonts/icons.ttf)。侧栏 / 标签的图标用它,
## 按码点 char(0xXXXX) 渲染。缺文件时返回 null, 调用方判空。
func get_icon_font() -> Font:
	if _font_icon != null:
		return _font_icon
	if ResourceLoader.exists(UI_ICON_FONT_PATH):
		var res: Resource = load(UI_ICON_FONT_PATH)
		if res is Font:
			_font_icon = res
			_prepare_ui_font(_font_icon)
	return _font_icon

## Bold 字重字体; 缺文件时回退到常规字体, 调用方无需判空。
func get_ui_font_bold() -> Font:
	if _font_bold != null:
		return _font_bold
	_font_bold_fallback = _load_font_file(UI_FONT_BOLD_PATH)
	var platform_font := _load_platform_ui_font(true) if _should_use_system_ui_font() else null
	_font_bold = platform_font if platform_font != null else _font_bold_fallback
	if _font_bold == null:
		_font_bold = get_ui_font()
	return _font_bold

## 平台原生中文 UI 字体文件候选。真实运行时按顺序找第一个存在且可加载的文件;
## 测试可传入 os_name/bold 固化 Windows / macOS 契约。
func preferred_ui_font_files_for_os(os_name: String, bold: bool = false) -> Array[Dictionary]:
	match os_name:
		"macOS":
			if bold:
				return [
					{path = "/System/Library/Fonts/PingFang.ttc", face = 0, weight = 700},
					{path = "/System/Library/Fonts/Hiragino Sans GB.ttc", face = 2, weight = 700},
					{path = "/System/Library/Fonts/STHeiti Medium.ttc", face = 0, weight = 700},
				]
			return [
				{path = "/System/Library/Fonts/PingFang.ttc", face = 0, weight = 400},
				{path = "/System/Library/Fonts/Hiragino Sans GB.ttc", face = 0, weight = 400},
				{path = "/System/Library/Fonts/STHeiti Light.ttc", face = 0, weight = 400},
				{path = "/System/Library/Fonts/STHeiti Medium.ttc", face = 0, weight = 400},
			]
		"Windows":
			if bold:
				return [
					{path = "C:/Windows/Fonts/msyhbd.ttc", face = 0, weight = 700},
					{path = "C:/Windows/Fonts/Dengb.ttf", face = 0, weight = 700},
					{path = "C:/Windows/Fonts/simhei.ttf", face = 0, weight = 700},
				]
			return [
				{path = "C:/Windows/Fonts/msyh.ttc", face = 0, weight = 400},
				{path = "C:/Windows/Fonts/Deng.ttf", face = 0, weight = 400},
				{path = "C:/Windows/Fonts/simhei.ttf", face = 0, weight = 400},
			]
		_:
			return []

func should_use_system_ui_font(os_name: String, display_name: String, is_test: bool) -> bool:
	if is_test:
		return false
	if display_name == "headless":
		return false
	return os_name == "macOS" or os_name == "Windows"

func _should_use_system_ui_font() -> bool:
	return should_use_system_ui_font(OS.get_name(), DisplayServer.get_name(), _is_test_run())

func _load_font_file(path: String) -> Font:
	if not ResourceLoader.exists(path):
		return null
	var res: Resource = load(path)
	if res is Font:
		var font := res as Font
		_prepare_ui_font(font)
		return font
	return null

func _load_platform_ui_font(bold: bool) -> Font:
	for candidate in preferred_ui_font_files_for_os(OS.get_name(), bold):
		var path := String(candidate.get("path", ""))
		if path == "" or not FileAccess.file_exists(path):
			continue
		var font := FontFile.new()
		var err := font.load_dynamic_font(path)
		if err != OK:
			continue
		var face_index := int(candidate.get("face", 0))
		if face_index > 0 and font.get_face_count() > face_index:
			font.set_face_index(0, face_index)
		font.set_font_weight(int(candidate.get("weight", 700 if bold else 400)))
		_prepare_ui_font(font)
		if font.has_char(0x6e38) and font.has_char(0x0041):
			Log.info(&"ui", "loaded platform ui font", {
				path = path,
				face = face_index,
				weight = font.get_font_weight(),
				name = font.get_font_name(),
			})
			return font
	return null

func _prepare_ui_font(font: Font) -> void:
	if font != null and font.has_method("set_allow_system_fallback"):
		font.set_allow_system_fallback(false)

func apply_font_to_theme(t: Theme, font: Font = null) -> void:
	var resolved_font := font
	if resolved_font == null:
		resolved_font = get_ui_font()
	if t == null or resolved_font == null:
		return
	_prepare_ui_font(resolved_font)
	for control_type in CONTROL_FONT_TYPES:
		t.set_font(&"font", control_type, resolved_font)
		t.set_font_size(&"font_size", control_type, FS_BASE)
	# 弹窗 / 面板标题用 bold 字重 — 和正文拉开层级 (GCP 控制台风格)。
	var bold_font := get_ui_font_bold()
	for control_type in TITLE_FONT_TYPES:
		t.set_font(&"title_font", control_type, bold_font)
		t.set_font_size(&"title_font_size", control_type, FS_MD)
	t.set_font(&"font_separator", &"PopupMenu", resolved_font)

# ─── 公共 helper ──────────────────────────────────────────────

## 按 token 名取颜色; 未注册的返回 Color.MAGENTA 作为兜底, 方便 UI 上一眼
## 看出拼错 token 名。
func color(token: StringName) -> Color:
	if _COLOR_TABLE.has(token):
		return _COLOR_TABLE[token]
	Log.warn(&"ui", "unknown color token", {token = token})
	return Color.MAGENTA

## 按 token 名取字号; 未注册的返回 FS_BASE。
func fs(token: StringName) -> int:
	if _FS_TABLE.has(token):
		return _FS_TABLE[token]
	Log.warn(&"ui", "unknown font_size token", {token = token})
	return FS_BASE

## 常用按钮变体。新 UI 优先用这里, 避免每个场景手写 StyleBox 状态。
## variant: secondary(default) / primary / create / ghost / danger / success / toolbar。
func apply_button_variant(button: BaseButton, variant: StringName = &"secondary") -> void:
	if button == null:
		return
	var v := variant
	if v == &"" or v == &"default":
		v = &"secondary"
	button.custom_minimum_size.y = maxf(button.custom_minimum_size.y, float(BUTTON_H))
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override(&"font_size", FS_BASE)
	match v:
		&"create":
			button.custom_minimum_size.y = maxf(button.custom_minimum_size.y, float(CREATE_BUTTON_H))
			button.add_theme_font_override(&"font", get_ui_font_bold())
			button.add_theme_font_size_override(&"font_size", FS_MD)
			_apply_button_palette(button,
				ACCENT_INFO,
				ACCENT_INFO.lightened(0.14),
				ACCENT_INFO.lightened(0.24),
				ACCENT_INFO,
				BG_SURFACE,
				TEXT_DISABLED,
				1,
				S_4,
				S_2)
		&"primary":
			_apply_button_palette(button,
				ACCENT_INFO,
				ACCENT_INFO.lightened(0.12),
				ACCENT_INFO.lightened(0.20),
				ACCENT_INFO,
				BG_SURFACE,
				TEXT_DISABLED)
		&"danger":
			_apply_button_palette(button,
				ACCENT_DANGER,
				ACCENT_DANGER.lightened(0.10),
				ACCENT_DANGER.darkened(0.08),
				ACCENT_DANGER,
				BG_SURFACE,
				TEXT_DISABLED)
		&"success":
			_apply_button_palette(button,
				ACCENT_PRIMARY,
				ACCENT_PRIMARY.lightened(0.10),
				ACCENT_PRIMARY.darkened(0.08),
				ACCENT_PRIMARY,
				BG_SURFACE,
				TEXT_DISABLED)
		&"ghost":
			_apply_button_palette(button,
				Color(0, 0, 0, 0),
				ACCENT_INFO_SUBTLE,
				BG_ELEVATED,
				Color(0, 0, 0, 0),
				TEXT_PRIMARY,
				TEXT_DISABLED,
				0)
		&"toolbar":
			button.custom_minimum_size.y = maxf(button.custom_minimum_size.y, float(CHIP_H))
			button.add_theme_font_size_override(&"font_size", FS_SM)
			_apply_button_palette(button,
				BG_SURFACE,
				BG_ELEVATED,
				BG_SURFACE.lerp(ACCENT_INFO, 0.14),
				BORDER_SUBTLE,
				TEXT_PRIMARY,
				TEXT_DISABLED,
				1,
				S_2,
				S_1)
		_:
			_apply_button_palette(button,
				BG_SURFACE,
				BG_ELEVATED,
				BG_SURFACE.lerp(ACCENT_INFO, 0.14),
				BORDER_SUBTLE,
				TEXT_PRIMARY,
				TEXT_DISABLED)

func _apply_button_palette(
		button: BaseButton,
		normal_bg: Color,
		hover_bg: Color,
		pressed_bg: Color,
		border: Color,
		font: Color,
		disabled_font: Color,
		border_w: int = 1,
		x_margin: int = S_3,
		y_margin: int = S_2) -> void:
	var disabled_bg: Color = BG_SURFACE if normal_bg.a > 0.0 else Color(0, 0, 0, 0)
	button.add_theme_stylebox_override(&"normal",
		_button_box(normal_bg, border, border_w, x_margin, y_margin))
	button.add_theme_stylebox_override(&"hover",
		_button_box(hover_bg, border if border_w > 0 else Color(0, 0, 0, 0), border_w, x_margin, y_margin))
	button.add_theme_stylebox_override(&"pressed",
		_button_box(pressed_bg, border if border_w > 0 else Color(0, 0, 0, 0), border_w, x_margin, y_margin, true))
	button.add_theme_stylebox_override(&"focus",
		_button_box(hover_bg, ACCENT_INFO, max(1, border_w), x_margin, y_margin))
	button.add_theme_stylebox_override(&"disabled",
		_button_box(disabled_bg, BORDER_SUBTLE if border_w > 0 else Color(0, 0, 0, 0), border_w, x_margin, y_margin))
	for color_name in [&"font_color", &"font_hover_color", &"font_hover_pressed_color", &"font_pressed_color", &"font_focus_color"]:
		button.add_theme_color_override(color_name, font)
	button.add_theme_color_override(&"font_disabled_color", disabled_font)

func _button_box(
		bg: Color,
		border: Color,
		border_w: int = 1,
		x_margin: int = S_3,
		y_margin: int = S_2,
		pressed_nudge: bool = false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(R_SM)
	sb.content_margin_left = x_margin
	sb.content_margin_right = x_margin
	if pressed_nudge:
		sb.content_margin_top = y_margin + 1
		sb.content_margin_bottom = max(0, y_margin - 1)
	else:
		sb.content_margin_top = y_margin
		sb.content_margin_bottom = y_margin
	return sb

# ─── §9bis 高 DPI 缩放 / 窗口模式 (见 design/UI视觉系统设计.md §9bis) ──

## 自动档缩放: 按窗口像素高度算 content_scale_factor。1080p→1.0, 1440p→≈1.33,
## 2160p→2.0; 低于基准不缩小 (下限 1.0), 超大屏封顶 MAX_UI_SCALE。纯函数, 供单测。
func compute_ui_scale(window_px_height: float) -> float:
	return clampf(window_px_height / BASE_VIEWPORT_H, 1.0, MAX_UI_SCALE)

## 实际生效缩放: 手动档 (Preferences.ui_scale>0) 优先, 否则按当前窗口高度自动算。
func effective_ui_scale() -> float:
	if Preferences.ui_scale > 0.0:
		return Preferences.ui_scale
	var w := get_window()
	var h: float = float(w.size.y) if w != null else BASE_VIEWPORT_H
	return compute_ui_scale(h)

## 把生效缩放写到根窗口的 content_scale_factor。Project stretch 保持 disabled,
## 避免 macOS 全屏时与画布自动缩放叠加导致菜单裁切。
func apply_display_scale() -> void:
	if _is_test_run():
		return
	var w := get_window()
	if w == null:
		return
	w.content_scale_factor = effective_ui_scale()

## 按 Preferences.fullscreen 切窗口模式 (borderless 全屏 / 窗口化)。
func apply_window_mode() -> void:
	if _is_test_run():
		return
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if Preferences.fullscreen \
		else DisplayServer.WINDOW_MODE_WINDOWED
	DisplayServer.window_set_mode(mode)

## 设置入口: 切手动缩放档 (0 = 自动) — 持久化 + 立即重应用。
func set_ui_scale(v: float) -> void:
	Preferences.set_ui_scale(v)
	apply_display_scale()

## 设置入口: 切全屏 — 持久化 + 切窗口模式 + 重应用缩放 (窗口尺寸变了)。
func set_fullscreen(on: bool) -> void:
	Preferences.set_fullscreen(on)
	apply_window_mode()
	apply_display_scale()

## 镜像 Preferences._is_test_run: 测试运行下不真正动窗口 / 缩放。
func _is_test_run() -> bool:
	for arg in OS.get_cmdline_args():
		if arg.begins_with("-gtest") or arg.begins_with("-gdir") \
				or arg == "--test" or arg.find("gut_cmdln.gd") != -1:
			return true
	return false

## 把以 TFLOPs 为单位的算力数值格式化为带合适量级单位的字符串。
## 1 PFLOPs = 1e3 TFLOPs; 1 EFLOPs = 1e6 TFLOPs。基建 / 训练 / GPU 规格等
## 所有算力 UI 统一走这个, 大数据中心不再显示成几百万 TFLOPs 的读不动的数字。
## 量级: ≥1e6 TFLOPs → EFLOPs; ≥1e3 → PFLOPs; ≥100 → 整数 TFLOPs; 否则 1 位小数。
func format_compute(tflops: float) -> String:
	var v: float = absf(tflops)
	if v >= 1.0e6:
		return "%.2f EFLOPs" % (tflops / 1.0e6)
	if v >= 1.0e3:
		return "%.2f PFLOPs" % (tflops / 1.0e3)
	if v >= 100.0:
		return "%.0f TFLOPs" % tflops
	return "%.1f TFLOPs" % tflops

## 把 token 吞吐率 (tokens/秒) 格式化为带量级单位的字符串。所有营收 / 顶栏 /
## 产品 UI 的 t/s 显示统一走这个, 大数值自动升档 k → M → G, 不再卡在 k。
## 量级: ≥1e9 → G t/s; ≥1e6 → M t/s; ≥1e3 → k t/s; ≥10 → 整数 t/s; 否则 1 位小数。
func format_tps(tps: float) -> String:
	if tps <= 0.0:
		return "0 t/s"
	if tps >= 1.0e9:
		return "%.1fG t/s" % (tps / 1.0e9)
	if tps >= 1.0e6:
		return "%.1fM t/s" % (tps / 1.0e6)
	if tps >= 1.0e3:
		return "%.1fk t/s" % (tps / 1.0e3)
	if tps >= 10.0:
		return "%.0f t/s" % tps
	return "%.1f t/s" % tps

## 把 token 计数 (累计用量 / 月度吞吐量等) 格式化为带量级单位的字符串。
## 量级: ≥1e12 → T; ≥1e9 → G; ≥1e6 → M; ≥1e3 → k; 否则原值。不带 "tokens" 后缀,
## 调用方自己补单位 (如 "tok/月")。
func format_tokens(n: float) -> String:
	var v: float = absf(n)
	if v >= 1.0e12:
		return "%.1fT" % (n / 1.0e12)
	if v >= 1.0e9:
		return "%.1fG" % (n / 1.0e9)
	if v >= 1.0e6:
		return "%.1fM" % (n / 1.0e6)
	if v >= 1.0e3:
		return "%.1fk" % (n / 1.0e3)
	return "%d" % int(n)

## 顶栏金额防溢出格式化 (见 design/UI视觉系统设计.md §5)。
## <100 万: 保持千分位精确 ("-272,360"), 让账本数 (+$38,000) 仍精确显示;
## ≥100 万: 缩成 "1.2M / 3.4B / 5.6T" (.0 去尾), 配合 flat chip 不裁字, 大额不撑破。
## 返回不含 $ 的数字串, 负号前置 — 与 main._format_money 在 <100 万区间逐字符一致。
## 注意: 只给顶栏现金 / 周净流 / 付费用户用; 经济明细 / 贷款仍走精确 _format_money。
func format_money_compact(n) -> String:
	var v: int = int(round(float(n)))
	if absi(v) < 1_000_000:
		return _group_thousands(v)
	var sign_str: String = "-" if v < 0 else ""
	var av: float = absf(float(v))
	if av >= 1.0e12:
		return "%s%sT" % [sign_str, _trim_decimal(av / 1.0e12)]
	if av >= 1.0e9:
		return "%s%sB" % [sign_str, _trim_decimal(av / 1.0e9)]
	return "%s%sM" % [sign_str, _trim_decimal(av / 1.0e6)]

## "%.1f" 但去掉无意义的 .0 尾 (1.0 → "1", 1.2 → "1.2")。
func _trim_decimal(x: float) -> String:
	var s: String = "%.1f" % x
	if s.ends_with(".0"):
		return s.substr(0, s.length() - 2)
	return s

## 千分位分组, 负号前置 (与 main._format_money 同算法, 这里做事实源)。
func _group_thousands(v: int) -> String:
	var s: String = str(absi(v))
	var out: String = ""
	var i: int = s.length()
	while i > 3:
		out = "," + s.substr(i - 3, 3) + out
		i -= 3
	out = s.substr(0, i) + out
	return ("-" + out) if v < 0 else out

# ─── 品牌标记 (Ascent A) ─────────────────────────────────────
## 把"上升的 A"品牌标记画进给定 CanvasItem 的 rect, 与 app 图标 (icon.svg) 同一套
## 几何与黑灰白配色: 白色山峰双腿 (BG_SURFACE) = 上升, 灰色横杠 (BORDER_STRONG) =
## 增长 / 数据曲线, 叠在炭黑圆角方块 (TEXT_PRIMARY) 上。
## 起始页 hero 标记与顶栏 monogram 共用本函数, 保证品牌跨场景一致。
##
## 必须在 ci 自己的 _draw() 期间调用 (内部走 ci 的 draw_* 方法)。锚点取自
## icon.svg 的 128 viewBox 归一化值; 颜色全部取 token, 不写颜色字面量。
## draw_background=true 先铺炭黑圆角方块 (TEXT_PRIMARY), 适合白底场景 (起始页卡 / 顶栏)。
func draw_brand_mark(ci: CanvasItem, rect: Rect2, draw_background: bool = true) -> void:
	var s: float = minf(rect.size.x, rect.size.y)
	if s <= 0.0:
		return
	# 按短边取正方形并在 rect 内居中。
	var o: Vector2 = rect.position + (rect.size - Vector2(s, s)) * 0.5
	if draw_background:
		var sb := StyleBoxFlat.new()
		sb.bg_color = TEXT_PRIMARY
		sb.set_corner_radius_all(int(round(s * 0.22)))
		sb.draw(ci.get_canvas_item(), Rect2(o, Vector2(s, s)))
	# 炭黑底上的「上升 A」: 白腿 + 灰横杠 (起始页 hero / app 图标).
	_draw_a_glyph(ci, o, s, BG_SURFACE, BORDER_STRONG)

## 「上升的 A」字形 (icon.svg 的 128 viewBox 归一化值)。stroke = A 双腿色,
## bar = 上升横杠色。底框由调用方决定 (炭黑 hero / 浅灰公司标志底)。
func _draw_a_glyph(ci: CanvasItem, o: Vector2, s: float, stroke: Color, bar_color: Color) -> void:
	var apex: Vector2   = o + Vector2(0.5000, 0.1875) * s
	var base_l: Vector2 = o + Vector2(0.2188, 0.8125) * s
	var base_r: Vector2 = o + Vector2(0.7813, 0.8125) * s
	var bar_l: Vector2  = o + Vector2(0.3438, 0.5781) * s
	var bar_r: Vector2  = o + Vector2(0.6250, 0.4531) * s
	var aw: float = maxf(s * 0.1016, 2.0)  # A 杆宽 (≈ icon 的 13/128)
	var gw: float = maxf(s * 0.0859, 1.5)  # 横杠宽 (≈ icon 的 11/128)
	ci.draw_line(base_l, apex, stroke, aw, true)
	ci.draw_line(apex, base_r, stroke, aw, true)
	ci.draw_circle(apex, aw * 0.5, stroke)
	ci.draw_circle(base_l, aw * 0.5, stroke)
	ci.draw_circle(base_r, aw * 0.5, stroke)
	# 上升横杠 (增长 / 数据曲线), 盖在腿之上。
	ci.draw_line(bar_l, bar_r, bar_color, gw, true)
	ci.draw_circle(bar_l, gw * 0.5, bar_color)
	ci.draw_circle(bar_r, gw * 0.5, bar_color)

## 玩家可选公司标志 (见 §5.1)。logo_id 为 LOGO_MARKS 里的 id; &"" 或未知 → 回退到
## 经典「A」标记 (draw_brand_mark), 保证旧档 / 默认局与之前一致。
## 必须在 ci 自己的 _draw() 期间调用。draw_background=true 先铺炭黑圆角方块。
func draw_company_logo(ci: CanvasItem, rect: Rect2, logo_id: StringName, draw_background: bool = true) -> void:
	var s: float = minf(rect.size.x, rect.size.y)
	if s <= 0.0:
		return
	var o: Vector2 = rect.position + (rect.size - Vector2(s, s)) * 0.5
	# 浅灰圆角底 (不再用炭黑) — 适配全站浅色 UI; 顶栏 / 选择网格都在浅底上。
	if draw_background:
		_draw_logo_bg(ci, o, s)
	# 品牌贴图 (brand-NN, 确定性生成的 logo 标记): 居中贴图, 留四周边距。
	# 缺图 (美术未就位 / 旧档形状 id / 默认 &"") → 落到下面的程序化路径。
	var tex: Texture2D = IconRegistry.company_logo_texture(logo_id)
	if tex != null:
		var m: float = s * 0.14  # 贴图四周留白, 不顶满圆角底
		ci.draw_texture_rect(tex, Rect2(o + Vector2(m, m), Vector2(s, s) - Vector2(m, m) * 2.0), false)
		return
	# 默认 / 未知 → 深色「上升 A」(浅底上可读, 绿色增长横杠)。
	var mark: Dictionary = _logo_mark(logo_id)
	if mark.is_empty():
		_draw_a_glyph(ci, o, s, TEXT_PRIMARY, ACCENT_PRIMARY)
		return
	# 旧档程序化形状标记 (LOGO_MARKS) — 向后兼容, 取强调色画形状。
	var center: Vector2 = o + Vector2(s, s) * 0.5
	var r: float = s * 0.30  # 形状外接半径; 留出四周边距。
	var col: Color = mark["color"]
	_draw_logo_shape(ci, StringName(mark["shape"]), center, r, col)

## 公司标志公用浅灰圆角底 (贴图 / 程序化形状 / 默认 A 共用)。描细边在纯白卡上界定。
func _draw_logo_bg(ci: CanvasItem, o: Vector2, s: float) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG_ELEVATED
	sb.border_color = BORDER_SUBTLE
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(int(round(s * 0.22)))
	sb.draw(ci.get_canvas_item(), Rect2(o, Vector2(s, s)))

func _logo_mark(logo_id: StringName) -> Dictionary:
	if String(logo_id).is_empty():
		return {}
	for m in LOGO_MARKS:
		if StringName(m["id"]) == logo_id:
			return m
	return {}

func _draw_logo_shape(ci: CanvasItem, shape: StringName, center: Vector2, r: float, col: Color) -> void:
	match shape:
		&"circle":
			ci.draw_circle(center, r, col)
		&"square":
			var half := r * 0.86
			ci.draw_rect(Rect2(center - Vector2(half, half), Vector2(half, half) * 2.0), col)
		&"diamond":
			ci.draw_colored_polygon(PackedVector2Array([
				center + Vector2(0, -r), center + Vector2(r, 0),
				center + Vector2(0, r), center + Vector2(-r, 0)]), col)
		&"triangle":
			ci.draw_colored_polygon(_regular_polygon(center, r, 3, -PI / 2.0), col)
		&"hexagon":
			ci.draw_colored_polygon(_regular_polygon(center, r, 6, -PI / 2.0), col)
		&"sparkle":
			ci.draw_colored_polygon(_star_polygon(center, r, r * 0.42, 4, -PI / 2.0), col)
		_:
			ci.draw_circle(center, r, col)

func _regular_polygon(center: Vector2, r: float, sides: int, rot: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(sides):
		var a: float = rot + TAU * float(i) / float(sides)
		pts.append(center + Vector2(cos(a), sin(a)) * r)
	return pts

func _star_polygon(center: Vector2, outer: float, inner: float, points: int, rot: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var n: int = points * 2
	for i in range(n):
		var a: float = rot + PI * float(i) / float(points)
		var rad: float = outer if i % 2 == 0 else inner
		pts.append(center + Vector2(cos(a), sin(a)) * rad)
	return pts
