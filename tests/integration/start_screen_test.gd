extends GutTest

## StartScreen — 起始页菜单 + 继续游戏可用性 + 新游戏写入 GameState。
## Per design/出身系统设计.md §1.
## _enter_game 在测试环境下不真正切场景 (StartScreen._is_test_run 守卫)。

const StartScreen := preload("res://scenes/start_screen/start_screen.gd")
const TEST_SAVE_DIR := "user://test_saves_start"

var _screen

func before_each() -> void:
	Save.save_dir = TEST_SAVE_DIR
	for slot in Save.list_slots():
		Save.delete_slot(slot)
	GameState.reset()

func after_each() -> void:
	if _screen != null:
		_screen.queue_free()
		_screen = null
	for slot in Save.list_slots():
		Save.delete_slot(slot)
	Save.save_dir = Save.DEFAULT_SAVE_DIR

func _make_screen():
	_screen = StartScreen.new()
	add_child_autofree(_screen)
	return _screen

# ---- 菜单结构 -----------------------------------------------------------

func test_screen_builds_five_menu_buttons() -> void:
	var s = _make_screen()
	assert_not_null(s._new_game_btn)
	assert_not_null(s._continue_btn)
	assert_not_null(s._load_btn)
	assert_not_null(s._settings_btn)
	assert_not_null(s._quit_btn)

func test_title_uses_hero_font_size() -> void:
	# 起始页是品牌欢迎页, 标题必须走 hero 大字号 (design/出身系统设计.md §1),
	# 不能回退成控制台正文档那种放满屏会偏小的字号。
	var s = _make_screen()
	assert_not_null(s._title_label, "起始页应持有标题 Label 引用")
	assert_eq(s._title_label.get_theme_font_size(&"font_size"), UITheme.FS_HERO,
		"标题字号必须等于 hero 主标题档 FS_HERO")

func test_hero_layout_uses_promo_background_image() -> void:
	# 起始页题材感由全屏宣传底图承载, 不再靠右侧小排行榜装饰面板。
	var s = _make_screen()
	assert_not_null(s._hero_card, "起始页应有主操作面板引用")
	assert_not_null(s._background_image, "起始页应创建全屏背景 TextureRect")
	assert_not_null(s._background_image.texture, "起始页背景贴图应可加载")
	assert_eq(s._background_image.texture.resource_path, StartScreen.START_BACKGROUND_PATH)
	assert_eq(s._background_image.stretch_mode, TextureRect.STRETCH_KEEP_ASPECT_COVERED,
		"背景图应 cover 铺满窗口, 不能留黑边")
	assert_eq(s._background_image.mouse_filter, Control.MOUSE_FILTER_IGNORE,
		"背景图是纯装饰, 不应拦截鼠标")

func test_hero_card_uses_translucent_surface() -> void:
	# 主面板要像欢迎页玻璃/磨砂面板, 不是完全不透明的旧白卡。
	var s = _make_screen()
	var sb: StyleBox = s._hero_card.get_theme_stylebox(&"panel")
	assert_true(sb is StyleBoxFlat, "主操作面板应使用 StyleBoxFlat")
	if sb is StyleBoxFlat:
		var flat := sb as StyleBoxFlat
		assert_lt(flat.bg_color.a, 1.0, "主操作面板底色应有透明度")
		assert_gt(flat.shadow_size, 0, "主操作面板应有柔和投影")

# ---- 继续游戏可用性 -----------------------------------------------------

func test_continue_disabled_when_no_save() -> void:
	var s = _make_screen()
	assert_true(s._continue_btn.disabled)

func test_continue_enabled_when_save_exists() -> void:
	Save.write(&"slot_a")
	var s = _make_screen()
	assert_false(s._continue_btn.disabled)

func test_latest_slot_empty_when_no_save() -> void:
	var s = _make_screen()
	assert_eq(s._latest_slot(), &"")

func test_latest_slot_prefers_autosave() -> void:
	Save.write(&"manual_one")
	Save.write(Save.AUTOSAVE_SLOT)
	var s = _make_screen()
	assert_eq(s._latest_slot(), Save.AUTOSAVE_SLOT)

# ---- 新游戏写入 GameState ----------------------------------------------

func test_new_game_confirmed_writes_founder_profile() -> void:
	var s = _make_screen()
	s._on_new_game_confirmed("阿黄", "蚂蚁智算", &"scientist", &"gem_violet", &"avatar-03")
	assert_eq(GameState.player_name, "阿黄")
	assert_eq(GameState.company_name, "蚂蚁智算")
	assert_eq(GameState.founder_origin, &"scientist")
	assert_eq(GameState.company_logo, &"gem_violet")
	assert_eq(GameState.founder_avatar, &"avatar-03")
