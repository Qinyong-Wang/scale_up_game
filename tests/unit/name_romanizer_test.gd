extends GutTest

## NameRomanizer: 中文真名 → 拼音 + locale 感知显示。见 design/国际化设计.md §12。

func after_each() -> void:
	# 切 locale 的用例自己恢复 zh_CN, 防顺序相关 flaky (见 i18n 测试约定)。
	TranslationServer.set_locale("zh_CN")

# ── romanize: 代表性中文名 → 期望拼音 ──────────────────────────

func test_romanize_single_char_given() -> void:
	assert_eq(NameRomanizer.romanize("王伟"), "Wang Wei")
	assert_eq(NameRomanizer.romanize("李静"), "Li Jing")
	assert_eq(NameRomanizer.romanize("赵磊"), "Zhao Lei")

func test_romanize_two_char_given() -> void:
	assert_eq(NameRomanizer.romanize("李婉清"), "Li Wanqing")
	assert_eq(NameRomanizer.romanize("张子墨"), "Zhang Zimo")
	assert_eq(NameRomanizer.romanize("陈皓然"), "Chen Haoran")
	assert_eq(NameRomanizer.romanize("周知行"), "Zhou Zhixing")

func test_romanize_passthrough_unknown_chars() -> void:
	# 默认创始人名 / 玩家英文名 / 空串 — 表外字整串原样返回, 不半翻。
	assert_eq(NameRomanizer.romanize("创始人"), "创始人")
	assert_eq(NameRomanizer.romanize("Alice"), "Alice")
	assert_eq(NameRomanizer.romanize(""), "")
	# 姓认得但名里有表外字 → 仍整串 passthrough。
	assert_eq(NameRomanizer.romanize("王小明"), "王小明")

# ── localized: locale 感知 ───────────────────────────────────

func test_localized_keeps_chinese_under_zh() -> void:
	TranslationServer.set_locale("zh_CN")
	assert_eq(NameRomanizer.localized("王伟"), "王伟")

func test_localized_pinyin_under_en() -> void:
	TranslationServer.set_locale("en")
	assert_eq(NameRomanizer.localized("王伟"), "Wang Wei")
	assert_eq(NameRomanizer.localized("李婉清"), "Li Wanqing")

# ── 守护: 东亚姓池 / 名池每个字都有拼音映射 ───────────────────
# 防以后往 PersonName 东亚池里加字却忘了补 _PINYIN, 导致该名在 en 下露中文。
# (非东亚名是拉丁字母, 不走拼音表, 无需守护。)

func _east_asian_given() -> PackedStringArray:
	var g := PackedStringArray()
	g.append_array(PersonName.EAST_ASIAN_GIVEN_MALE)
	g.append_array(PersonName.EAST_ASIAN_GIVEN_FEMALE)
	return g

func test_every_pool_char_has_pinyin() -> void:
	var pool := PackedStringArray()
	pool.append_array(PersonName.EAST_ASIAN_SURNAMES)
	pool.append_array(_east_asian_given())
	var missing := PackedStringArray()
	for entry in pool:
		for ch in entry:
			if String(NameRomanizer._PINYIN.get(ch, "")).is_empty():
				missing.append(ch)
	assert_eq(missing.size(), 0,
			"东亚姓/名池字缺拼音映射 (补 NameRomanizer._PINYIN): %s" % ", ".join(missing))

func test_every_generated_name_fully_romanized() -> void:
	# 任取东亚池组合, 罗马化后不应残留中文 (=没走 passthrough)。
	TranslationServer.set_locale("en")
	for surname in PersonName.EAST_ASIAN_SURNAMES:
		for given in _east_asian_given():
			var out := NameRomanizer.localized(String(surname) + String(given))
			assert_false(_has_cjk(out), "残留中文: %s%s → %s" % [surname, given, out])

func _has_cjk(s: String) -> bool:
	for ch in s:
		if ch.unicode_at(0) >= 0x4E00 and ch.unicode_at(0) <= 0x9FFF:
			return true
	return false
