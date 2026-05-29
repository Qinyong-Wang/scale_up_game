extends GutTest

## IconRegistry 肖像族裔/性别表 — 取名靠它让"名跟随脸"。见 design/招聘系统设计.md §1.3。
## (放独立文件: 与 icon_registry_test.gd 解耦, 后者归 founder 头像那条线。)

const LEAD_POOL_SIZE := 12

# 索引: 取名 (HiringSystem) 与取图 (lead_portrait) 共用同一哈希, 否则名/脸对不上。
func test_portrait_index_deterministic_and_in_range() -> void:
	var a := IconRegistry.lead_portrait_index(&"lead_0007")
	var b := IconRegistry.lead_portrait_index(&"lead_0007")
	assert_eq(a, b, "同一 id 索引必须稳定")
	assert_between(a, 0, LEAD_POOL_SIZE - 1, "索引应落在 0..%d" % (LEAD_POOL_SIZE - 1))

func test_portrait_index_empty_id_negative() -> void:
	assert_eq(IconRegistry.lead_portrait_index(&""), -1, "空 id → -1")

# 12 张全覆盖, region 合法 (∈ PersonName.REGIONS), gender ∈ {male, female}。
func test_demographics_table_complete_and_valid() -> void:
	assert_eq(IconRegistry.LEAD_PORTRAIT_DEMOGRAPHICS.size(), LEAD_POOL_SIZE,
			"族裔表应与肖像池等长 (%d)" % LEAD_POOL_SIZE)
	for entry in IconRegistry.LEAD_PORTRAIT_DEMOGRAPHICS:
		assert_true(PersonName.REGIONS.has(entry.get(&"region")),
				"region %s 应是合法 PersonName.REGIONS" % entry.get(&"region"))
		assert_true(entry.get(&"gender") in [&"male", &"female"],
				"gender %s 应是 male/female" % entry.get(&"gender"))

# lead_demographics(id) 必须等于该 id 落到的索引处的表项。
func test_demographics_matches_index() -> void:
	for i in range(40):
		var id := StringName("lead_%04d" % i)
		var idx := IconRegistry.lead_portrait_index(id)
		var demo := IconRegistry.lead_demographics(id)
		assert_eq(demo, IconRegistry.LEAD_PORTRAIT_DEMOGRAPHICS[idx],
				"%s 的 demographics 应等于索引 %d 处表项" % [id, idx])

func test_demographics_empty_id_returns_empty() -> void:
	assert_eq(IconRegistry.lead_demographics(&""), {}, "空 id → {} (调用方回退)")

# 表里出现的每个 region 都能被 PersonName 取到名 (防表里写了 PersonName 没有的 region)。
func test_every_table_region_generates_a_name() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	for entry in IconRegistry.LEAD_PORTRAIT_DEMOGRAPHICS:
		var name := PersonName.generate(entry.get(&"region"), entry.get(&"gender"), rng)
		assert_false(name.is_empty(),
				"region %s 取不到名 (PersonName 缺该 region 的池?)" % entry.get(&"region"))
