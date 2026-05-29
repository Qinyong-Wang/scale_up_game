extends PanelContainer

## LeaderboardRow — 荣耀榜单单行 (design/竞争对手系统设计.md §8)。
##
## 布局 (HBox, 垂直居中):
##   [名次奖章] [头像] [名称 / 公司]  …spacer…  [得分] [奖励]
##   前 3 名奖章 金/银/铜 (RANK_GOLD/SILVER/BRONZE); 第 4 名起灰底数字, 不抢镜。
##   玩家自己的行: 浅灰高亮底 (ACCENT_INFO_SUBTLE) + 左侧炭黑条 + 名称旁「你」徽章。
##
## 纯渲染组件 — 不调 tr(), 不持业务系统引用; 文案全部由调用方 (LeaderboardView)
## 传入 set_data(dict)。颜色一律走 UITheme token。

const AvatarScene := preload("res://scenes/ui/components/avatar/avatar.tscn")
const BadgeScene  := preload("res://scenes/ui/components/badge/badge.tscn")

const _ROW_MIN_H := 44
const _MEDAL_SIDE := 30
const _AVATAR_SIDE := 30
const _PLAYER_BORDER_W := 3

var _bg: StyleBoxFlat
var _medal_panel: PanelContainer
var _medal_bg: StyleBoxFlat
var _medal_label: Label
var _avatar: Control
var _name_label: Label
var _company_label: Label
var _you_badge: Control
var _score_label: Label
var _reward_label: Label

var _is_player := false

# set_data 在 _ready 之前调用时缓冲, _ready 后补 apply (同 SectionHeader 约定)。
var _pending_data: Dictionary = {}

func _ready() -> void:
	custom_minimum_size.y = max(custom_minimum_size.y, _ROW_MIN_H)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_bg = StyleBoxFlat.new()
	_bg.bg_color = UITheme.BG_SURFACE
	_bg.corner_radius_top_left = UITheme.R_SM
	_bg.corner_radius_top_right = UITheme.R_SM
	_bg.corner_radius_bottom_left = UITheme.R_SM
	_bg.corner_radius_bottom_right = UITheme.R_SM
	_bg.content_margin_left = UITheme.S_3
	_bg.content_margin_right = UITheme.S_3
	_bg.content_margin_top = UITheme.S_1
	_bg.content_margin_bottom = UITheme.S_1
	add_theme_stylebox_override(&"panel", _bg)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override(&"separation", UITheme.S_3)
	add_child(hb)

	# ─── 名次奖章 (圆形色块 + 数字) ─────────────────────────
	_medal_panel = PanelContainer.new()
	_medal_panel.custom_minimum_size = Vector2(_MEDAL_SIDE, _MEDAL_SIDE)
	_medal_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_medal_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_medal_bg = StyleBoxFlat.new()
	_medal_bg.bg_color = UITheme.BG_ELEVATED
	var r := int(_MEDAL_SIDE / 2.0)
	_medal_bg.corner_radius_top_left = r
	_medal_bg.corner_radius_top_right = r
	_medal_bg.corner_radius_bottom_left = r
	_medal_bg.corner_radius_bottom_right = r
	_medal_panel.add_theme_stylebox_override(&"panel", _medal_bg)
	_medal_label = Label.new()
	_medal_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_medal_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_medal_label.add_theme_font_override(&"font", UITheme.get_ui_font_bold())
	_medal_label.add_theme_font_size_override(&"font_size", UITheme.FS_SM)
	_medal_panel.add_child(_medal_label)
	hb.add_child(_medal_panel)

	# ─── 头像 ───────────────────────────────────────────────
	_avatar = AvatarScene.instantiate()
	_avatar.custom_minimum_size = Vector2(_AVATAR_SIDE, _AVATAR_SIDE)
	_avatar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(_avatar)

	# ─── 名称列 (名称 + 「你」徽章 / 公司) ─────────────────
	var name_col := VBoxContainer.new()
	name_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_col.add_theme_constant_override(&"separation", 0)
	hb.add_child(name_col)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override(&"separation", UITheme.S_2)
	name_col.add_child(name_row)
	_name_label = Label.new()
	_name_label.add_theme_font_size_override(&"font_size", UITheme.FS_MD)
	_name_label.add_theme_color_override(&"font_color", UITheme.TEXT_PRIMARY)
	name_row.add_child(_name_label)
	_you_badge = BadgeScene.instantiate()
	_you_badge.visible = false
	name_row.add_child(_you_badge)

	_company_label = Label.new()
	_company_label.add_theme_font_size_override(&"font_size", UITheme.FS_SM)
	_company_label.add_theme_color_override(&"font_color", UITheme.TEXT_SECONDARY)
	_company_label.visible = false
	name_col.add_child(_company_label)

	# ─── 得分 ───────────────────────────────────────────────
	_score_label = Label.new()
	_score_label.add_theme_font_override(&"font", UITheme.get_ui_font_bold())
	_score_label.add_theme_font_size_override(&"font_size", UITheme.FS_MD)
	_score_label.add_theme_color_override(&"font_color", UITheme.TEXT_PRIMARY)
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_score_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_score_label.custom_minimum_size = Vector2(64, 0)
	hb.add_child(_score_label)

	# ─── 奖励 (名次引流加成, 展示榜为空) ────────────────────
	_reward_label = Label.new()
	_reward_label.add_theme_font_size_override(&"font_size", UITheme.FS_SM)
	_reward_label.add_theme_color_override(&"font_color", UITheme.TEXT_SECONDARY)
	_reward_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_reward_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_reward_label.visible = false
	hb.add_child(_reward_label)

	if not _pending_data.is_empty():
		var d := _pending_data
		_pending_data = {}
		set_data(d)

func set_data(d: Dictionary) -> void:
	if _name_label == null:
		_pending_data = d
		return
	var rank: int = int(d.get("rank", 0))
	_is_player = bool(d.get("is_player", false))

	_medal_label.text = str(rank) if rank > 0 else "—"
	_medal_bg.bg_color = _medal_color_for_rank(rank)
	_medal_label.add_theme_color_override(&"font_color", _medal_text_color_for_rank(rank))

	_name_label.text = String(d.get("display_name", ""))

	var company: String = String(d.get("company_name", ""))
	_company_label.text = company
	_company_label.visible = not company.is_empty()

	_score_label.text = String(d.get("score_text", ""))

	var reward: String = String(d.get("reward_text", ""))
	_reward_label.text = reward
	_reward_label.visible = not reward.is_empty()

	_avatar.set_data(
		null,
		String(d.get("display_name", "")),
		StringName(d.get("seed_id", &"")),
		&"model",
	)

	var you_label: String = String(d.get("you_label", ""))
	if _is_player and not you_label.is_empty():
		_you_badge.set_data(you_label, &"info")
		_you_badge.visible = true
	else:
		_you_badge.visible = false

	# 玩家行高亮: 浅蓝底 + 左侧蓝条; 其它行白底无边。
	if _is_player:
		_bg.bg_color = UITheme.ACCENT_INFO_SUBTLE
		_bg.border_width_left = _PLAYER_BORDER_W
		_bg.border_color = UITheme.ACCENT_INFO
	else:
		_bg.bg_color = UITheme.BG_SURFACE
		_bg.border_width_left = 0

# 名次奖章底色: 前 3 名金/银/铜, 其余中性灰。
func _medal_color_for_rank(rank: int) -> Color:
	match rank:
		1: return UITheme.RANK_GOLD
		2: return UITheme.RANK_SILVER
		3: return UITheme.RANK_BRONZE
		_: return UITheme.BG_ELEVATED

# 奖章数字色: 前 3 名暖底上用深字保证对比, 其余用次级灰。
func _medal_text_color_for_rank(rank: int) -> Color:
	if rank >= 1 and rank <= 3:
		return UITheme.TEXT_PRIMARY
	return UITheme.TEXT_SECONDARY

# ─── 测试 introspection ──────────────────────────────────────

func get_rank_text() -> String:
	return _medal_label.text if _medal_label != null else ""

func get_medal_color() -> Color:
	return _medal_bg.bg_color if _medal_bg != null else Color.MAGENTA

func get_name_text() -> String:
	return _name_label.text if _name_label != null else ""

func get_company_text() -> String:
	return _company_label.text if _company_label != null else ""

func is_company_visible() -> bool:
	return _company_label != null and _company_label.visible

func get_score_text() -> String:
	return _score_label.text if _score_label != null else ""

func get_reward_text() -> String:
	return _reward_label.text if _reward_label != null else ""

func is_reward_visible() -> bool:
	return _reward_label != null and _reward_label.visible

func is_player_highlighted() -> bool:
	return _bg != null and _bg.bg_color.is_equal_approx(UITheme.ACCENT_INFO_SUBTLE)

func has_you_badge() -> bool:
	return _you_badge != null and _you_badge.visible

func get_you_badge_text() -> String:
	if _you_badge == null or not _you_badge.has_method(&"get_label_text"):
		return ""
	return _you_badge.get_label_text()
