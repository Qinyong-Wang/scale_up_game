extends GutTest

## i18n 管道契约测试。
## 对应 design/国际化设计.md §7。
##
## 单元:
##   - project.godot 注册了 strings.csv 产出的 .translation 文件。
##   - tr("KEY") 在 zh_CN / en 之间正确切换。
##   - 未知 key 返回 key 自身。
##   - en 列空字符串时, en locale 下 fallback 到 zh_CN。

const ZH_TRANSLATION_PATH := "res://resources/i18n/strings.zh.translation"
const EN_TRANSLATION_PATH := "res://resources/i18n/strings.en.translation"

var _saved_locale: String = ""

func before_each() -> void:
	_saved_locale = TranslationServer.get_locale()

func after_each() -> void:
	TranslationServer.set_locale(_saved_locale)

# ─── strings.csv zh 完整性 ────────────────────────────────────

## Godot CSV translation importer 要求每条 key 的 locale 列数与表头一致。
## 英文 value 里出现 ASCII 逗号时必须用标准 CSV 引号包住。
func test_strings_csv_rows_match_header_column_count() -> void:
	var f := FileAccess.open("res://resources/i18n/strings.csv", FileAccess.READ)
	assert_not_null(f, "strings.csv 必须存在")
	var header := f.get_csv_line()
	var expected_columns := header.size()
	var malformed: Array = []
	var line_no := 1
	while not f.eof_reached():
		line_no += 1
		var row := f.get_csv_line()
		if row.size() == 0:
			continue
		if row.size() == 1 and String(row[0]).strip_edges() == "":
			continue
		var key := String(row[0]).strip_edges()
		if key == "" or key.begins_with("#"):
			continue
		if row.size() != expected_columns:
			malformed.append("%s(line %d: %d cols)" % [key, line_no, row.size()])
	f.close()
	assert_eq(malformed.size(), 0,
		"strings.csv 每条有效记录必须是 %d 列: %s"
			% [expected_columns, str(malformed.slice(0, 15))])

## 每个 UI key 都必须有非空 zh 值, 否则该 key 在中文 (默认) locale 下会回落成
## en 或 key 自身 — 即"UI 上出现没中文的英文"。这是 §6ter 守护的反向: 守护测试保证
## 写死的中文可翻译; 这条保证每个翻译 key 都有中文。
func test_every_strings_key_has_nonempty_zh() -> void:
	var f := FileAccess.open("res://resources/i18n/strings.csv", FileAccess.READ)
	assert_not_null(f, "strings.csv 必须存在")
	var header := f.get_csv_line()  # keys,zh,en
	var missing: Array = []
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() < 2:
			continue
		var key := String(row[0]).strip_edges()
		if key == "" or key.begins_with("#"):
			continue
		if String(row[1]).strip_edges() == "":
			missing.append(key)
	f.close()
	assert_eq(missing.size(), 0,
		"%d 个 strings.csv key 缺中文 (zh 列空 → 中文界面显示英文): %s"
			% [missing.size(), str(missing.slice(0, 15))])

# ─── §4 注册 ──────────────────────────────────────────────────

func test_translations_registered_in_project_settings() -> void:
	var paths: PackedStringArray = ProjectSettings.get_setting(
		"internationalization/locale/translations", PackedStringArray())
	assert_gt(paths.size(), 0, "至少注册 1 个翻译文件")
	var as_array := Array(paths)
	assert_true(as_array.has(ZH_TRANSLATION_PATH),
		"必须注册 zh translation: %s" % ZH_TRANSLATION_PATH)

func test_fallback_locale_is_zh_cn() -> void:
	var fallback: String = ProjectSettings.get_setting(
		"internationalization/locale/fallback", "")
	assert_eq(fallback, "zh_CN", "fallback locale 固定 zh_CN")

func test_translation_files_load_as_translation_resources() -> void:
	assert_true(ResourceLoader.exists(ZH_TRANSLATION_PATH))
	var zh: Resource = load(ZH_TRANSLATION_PATH)
	assert_true(zh is Translation, "zh translation 必须是 Translation 资源")

# ─── §5 + §7 lookup 与回落 ────────────────────────────────────

func test_app_title_returns_zh_in_zh_locale() -> void:
	TranslationServer.set_locale("zh_CN")
	assert_eq(tr("APP_TITLE"), "Scaling Up")

func test_nav_keys_switch_with_locale() -> void:
	TranslationServer.set_locale("zh_CN")
	assert_eq(tr("NAV_OPERATIONS"), "运营")
	assert_eq(tr("NAV_RND"), "研发")
	assert_eq(tr("NAV_MARKET"), "竞争对手")
	TranslationServer.set_locale("en")
	assert_eq(tr("NAV_OPERATIONS"), "Operations")
	assert_eq(tr("NAV_RND"), "R&D")
	assert_eq(tr("NAV_MARKET"), "Competitors")

func test_locale_switch_is_reversible() -> void:
	TranslationServer.set_locale("zh_CN")
	var first := tr("NAV_OPERATIONS")
	TranslationServer.set_locale("en")
	TranslationServer.set_locale("zh_CN")
	assert_eq(tr("NAV_OPERATIONS"), first,
		"切到 en 再切回 zh_CN 应当与第一次一致")

func test_unknown_key_returns_itself() -> void:
	TranslationServer.set_locale("zh_CN")
	var missing := &"__no_such_key_dont_define__"
	assert_eq(tr(missing), str(missing))

func test_en_empty_falls_back_to_zh() -> void:
	# design §5 + §7: en 列空字符串视同未翻译, en locale 下回落到 zh_CN
	# 而不是返回 key. 用 seed key _PIPELINE_FALLBACK_SMOKE 固化这条契约。
	TranslationServer.set_locale("en")
	var v := tr("_PIPELINE_FALLBACK_SMOKE")
	assert_eq(v, "回落冒烟",
		"en 列空时必须 fallback 到 zh; 实际取到: %s" % v)

func test_action_keys_available_in_both_locales() -> void:
	TranslationServer.set_locale("zh_CN")
	assert_eq(tr("ACTION_NEW"), "新建")
	assert_eq(tr("ACTION_CANCEL"), "取消")
	assert_eq(tr("ACTION_CONFIRM"), "确认")
	TranslationServer.set_locale("en")
	assert_eq(tr("ACTION_NEW"), "New")
	assert_eq(tr("ACTION_CANCEL"), "Cancel")
	assert_eq(tr("ACTION_CONFIRM"), "Confirm")

func test_staff_infra_role_label_is_software_engineer() -> void:
	TranslationServer.set_locale("zh_CN")
	assert_eq(tr("STAFF_ROLE_INFRA_ENG"), "软件工程师")
	TranslationServer.set_locale("en")
	assert_eq(tr("STAFF_ROLE_INFRA_ENG"), "Software Engineer")

# ─── 下拉框文案补翻译 (问题4) ────────────────────────────────

func test_dc_ownership_labels_translate() -> void:
	TranslationServer.set_locale("zh_CN")
	assert_eq(tr("DC_OWNERSHIP_RENTED"), "租用")
	assert_eq(tr("DC_OWNERSHIP_OWNED"), "自建")
	assert_eq(tr("DC_OWNERSHIP_CLOUD"), "云算力")
	TranslationServer.set_locale("en")
	assert_eq(tr("DC_OWNERSHIP_RENTED"), "Rented")
	assert_eq(tr("DC_OWNERSHIP_CLOUD"), "Cloud")

func test_product_type_label_keys_cover_all_types_and_translate() -> void:
	# 每个产品类型都要有 i18n 短标签 key, 且 key 必须有翻译 (非原样返回)。
	TranslationServer.set_locale("en")
	for type_id in ProductSystem.TYPE_PATHS.keys():
		assert_true(ProductSystem.TYPE_LABEL_KEY.has(type_id),
				"产品类型缺 i18n 标签 key: %s" % type_id)
		var key: String = ProductSystem.TYPE_LABEL_KEY[type_id]
		assert_ne(tr(key), key, "产品类型标签 key 无翻译 (原样返回): %s" % key)

func test_gameover_and_lead_bonus_keys_translate() -> void:
	TranslationServer.set_locale("zh_CN")
	assert_eq(tr("GAMEOVER_TITLE"), "游戏结束")
	assert_ne(tr("BANKRUPTCY_WARN_BODY"), "BANKRUPTCY_WARN_BODY")
	assert_ne(tr("OV_HINT_CASH_NEGATIVE"), "OV_HINT_CASH_NEGATIVE")
	assert_ne(tr("POST_LEAD_BONUS"), "POST_LEAD_BONUS")
	TranslationServer.set_locale("en")
	assert_eq(tr("GAMEOVER_TITLE"), "Game Over")
	assert_ne(tr("POST_LEAD_BONUS"), "POST_LEAD_BONUS")
