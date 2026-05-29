extends GutTest

## PersonName: 按族裔 + 性别生成人名。见 design/招聘系统设计.md §1.3。
## 关键约束: east_asian 出中文 "姓名"; 其余出纯 ASCII 拉丁 "Given Surname";
## gender 选男/女名池; 同 seed 可重现; 未知 region/gender 安全回退。

const _N := 40  # 每组采样次数, 覆盖池子

func _rng(s: int = 1) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r

func _has_cjk(s: String) -> bool:
	for ch in s:
		if ch.unicode_at(0) >= 0x4E00 and ch.unicode_at(0) <= 0x9FFF:
			return true
	return false

func _is_ascii(s: String) -> bool:
	for ch in s:
		if ch.unicode_at(0) > 127:
			return false
	return true

# ── 池子完整性 ────────────────────────────────────────────────────

func test_all_regions_have_nonempty_pools() -> void:
	for region in PersonName.REGIONS:
		assert_false(PersonName.surnames_for(region).is_empty(),
				"%s 姓氏池不能为空" % region)
		assert_false(PersonName.given_for(region, &"male").is_empty(),
				"%s 男名池不能为空" % region)
		assert_false(PersonName.given_for(region, &"female").is_empty(),
				"%s 女名池不能为空" % region)

# ── east_asian: 中文 "姓名", 无空格 ───────────────────────────────

func test_east_asian_is_chinese_surname_plus_given() -> void:
	for gender in [&"male", &"female"]:
		var rng := _rng(7)
		var given_pool: Array = PersonName.given_for(&"east_asian", gender)
		for i in range(_N):
			var name := PersonName.generate(&"east_asian", gender, rng)
			assert_false(name.is_empty(), "中文名不能为空")
			assert_eq(name.find(" "), -1, "中文名不应含空格: %s" % name)
			assert_true(_has_cjk(name), "east_asian 名应是中文: %s" % name)
			var surname: String = name.substr(0, 1)
			assert_true(PersonName.EAST_ASIAN_SURNAMES.has(surname),
					"姓 %s 应在东亚姓氏池 (full=%s)" % [surname, name])
			assert_true(given_pool.has(name.substr(1)),
					"名 %s 应在 %s 名池 (full=%s)" % [name.substr(1), gender, name])

# ── 其余 region: 纯 ASCII "Given Surname", 单空格两段 ──────────────

func test_latin_regions_are_ascii_given_space_surname() -> void:
	for region in [&"western", &"south_asian", &"hispanic", &"middle_eastern", &"southeast_asian"]:
		for gender in [&"male", &"female"]:
			var rng := _rng(13)
			var surname_pool: Array = PersonName.surnames_for(region)
			var given_pool: Array = PersonName.given_for(region, gender)
			for i in range(_N):
				var name := PersonName.generate(region, gender, rng)
				assert_false(name.is_empty(), "%s 名不能为空" % region)
				assert_true(_is_ascii(name), "%s 名应纯 ASCII (防字体缺字): %s" % [region, name])
				assert_false(_has_cjk(name), "%s 名不应含中文: %s" % [region, name])
				var parts := name.split(" ", false)
				assert_eq(parts.size(), 2, "%s 名应为 'Given Surname' 两段: %s" % [region, name])
				assert_true(given_pool.has(parts[0]),
						"%s/%s given %s 应在名池 (full=%s)" % [region, gender, parts[0], name])
				assert_true(surname_pool.has(parts[1]),
						"%s surname %s 应在姓氏池 (full=%s)" % [region, parts[1], name])

# ── gender: 女名只来自女名池, 反之亦然 (上面已隐含, 这里显式守护回退) ──

func test_unknown_gender_falls_back_to_female() -> void:
	assert_eq(PersonName.given_for(&"western", &"nonbinary"), PersonName.WESTERN_GIVEN_FEMALE,
			"未知 gender 应回退女名池")

func test_unknown_region_falls_back_to_east_asian() -> void:
	# 未知 region → east_asian 风格 (中文姓+名), 保证总能取到名。
	var rng := _rng(3)
	assert_eq(PersonName.surnames_for(&"atlantis"), PersonName.EAST_ASIAN_SURNAMES)
	var name := PersonName.generate(&"atlantis", &"male", rng)
	assert_true(_has_cjk(name), "未知 region 应回退中文名: %s" % name)

# ── 确定性: 同 seed → 同名 ────────────────────────────────────────

func test_deterministic_under_same_seed() -> void:
	for region in PersonName.REGIONS:
		for gender in [&"male", &"female"]:
			var a := PersonName.generate(region, gender, _rng(99))
			var b := PersonName.generate(region, gender, _rng(99))
			assert_eq(a, b, "%s/%s 同 seed 必须重现" % [region, gender])

# ── 与 NameRomanizer 衔接: 东亚名能完整罗马化 (无残留中文) ─────────

func test_east_asian_names_fully_romanize_under_en() -> void:
	TranslationServer.set_locale("en")
	var rng := _rng(55)
	for gender in [&"male", &"female"]:
		for i in range(_N):
			var name := PersonName.generate(&"east_asian", gender, rng)
			var out := NameRomanizer.localized(name)
			assert_false(_has_cjk(out), "罗马化后残留中文: %s → %s" % [name, out])

func after_each() -> void:
	TranslationServer.set_locale("zh_CN")
