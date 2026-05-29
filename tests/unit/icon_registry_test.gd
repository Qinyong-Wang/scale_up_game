extends GutTest

## IconRegistry 接入 — 各模块类型图标都存在且能 load; 缺图/空键回退 null; GPU 按族取图。
## 见 design/图片素材生成流程.md §8。

const EXPECTED := {
	&"dataset": ["text", "image", "code", "audio", "video"],
	&"product": ["chatbot", "agent", "api", "coding_agent", "multimodal_assistant"],
	&"tech":    ["arch", "attention", "loss", "engineering", "application", "context"],
	&"task":    ["pretrain", "posttrain", "evaluate", "data_collection", "tech_research"],
	&"gpu":     ["cypress", "maple", "bamboo"],
	&"power":   ["grid", "green"],
	&"model":   ["dense", "moe", "encoder", "enc_dec", "multimodal"],
	&"event":   ["opportunity", "crisis", "flavor", "routine"],
	&"marketing": ["campaign"],
}

const LEAD_POOL_SIZE := 12

func before_all() -> void:
	IconRegistry.clear_cache_for_test()

func test_all_expected_icons_exist_and_load() -> void:
	for category in EXPECTED:
		for key in EXPECTED[category]:
			var tex := IconRegistry.get_icon(category, StringName(key))
			assert_true(tex is Texture2D,
				"图标缺失或无法 load: %s/%s" % [category, key])

func test_empty_args_return_null() -> void:
	assert_null(IconRegistry.get_icon(&"", &"text"))
	assert_null(IconRegistry.get_icon(&"dataset", &""))

func test_missing_icon_returns_null() -> void:
	assert_null(IconRegistry.get_icon(&"dataset", &"__nope__"),
		"不存在的 key 应返回 null (调用方走回退)")

func test_marketing_icon_loads_campaign_asset() -> void:
	assert_true(IconRegistry.marketing_icon(&"campaign") is Texture2D,
		"营销活动图标应能通过 IconRegistry 读取")
	assert_null(IconRegistry.marketing_icon(&""),
		"空营销图标 key 应回退 null")

func test_gpu_icon_resolves_family_from_id() -> void:
	# cypress_t0..t3 / maple_t1.. / bamboo_t1.. 都按族前缀取同一张图。
	assert_eq(IconRegistry.gpu_icon(&"cypress_t2"), IconRegistry.get_icon(&"gpu", &"cypress"))
	assert_eq(IconRegistry.gpu_icon(&"maple_t1"), IconRegistry.get_icon(&"gpu", &"maple"))
	assert_true(IconRegistry.gpu_icon(&"bamboo_t3") is Texture2D)

# lead 肖像是按人分配的多元肖像池 (portrait-01..12), 不按 specialty。
func test_lead_portrait_pool_all_present() -> void:
	for i in range(1, LEAD_POOL_SIZE + 1):
		assert_true(IconRegistry.get_icon(&"lead", StringName("portrait-%02d" % i)) is Texture2D,
			"肖像池缺图: portrait-%02d" % i)

func test_lead_portrait_deterministic_per_id() -> void:
	var a := IconRegistry.lead_portrait(&"lead_0007")
	var b := IconRegistry.lead_portrait(&"lead_0007")
	assert_eq(a, b, "同一 lead.id 必须永远拿同一张肖像")
	assert_true(a is Texture2D, "lead_portrait 应返回 Texture2D")

func test_lead_portrait_empty_id_returns_null() -> void:
	assert_null(IconRegistry.lead_portrait(&""))

# 创始人专属头像 (新游戏选, 写到 Lead.avatar_id) — 见出身系统设计 §3。
func test_founder_avatar_keys_are_nonempty_and_well_formed() -> void:
	var keys: Array = IconRegistry.founder_avatar_keys()
	assert_gt(keys.size(), 0, "应至少有一个创始人头像可选")
	var seen := {}
	for k in keys:
		assert_true(String(k).begins_with("avatar-"), "头像 key 形如 avatar-NN: %s" % k)
		assert_false(seen.has(k), "头像 key 不能重复: %s" % k)
		seen[k] = true

# 头像美术已接入 assets/sprites/ui/founder/ — 每个 key 都应能 load (防误删/漏导)。
func test_founder_avatar_pool_all_present() -> void:
	for k in IconRegistry.founder_avatar_keys():
		assert_true(IconRegistry.founder_avatar(k) is Texture2D,
			"创始人头像缺图: %s" % k)

func test_lead_texture_empty_avatar_falls_back_to_portrait_pool() -> void:
	# avatar_id 为空 (普通 lead) → 走按 id 哈希的多元肖像池。
	assert_eq(IconRegistry.lead_texture(&"lead_0007", &""),
		IconRegistry.lead_portrait(&"lead_0007"))

func test_lead_texture_prefers_explicit_avatar_id() -> void:
	# avatar_id 非空 (玩家创始人) → 走 founder 类目, 不退回肖像池。
	# (美术未就位时两边都可能是 null, 但必须取自 founder 而非 lead 类目)。
	assert_eq(IconRegistry.lead_texture(&"player_self", &"avatar-01"),
		IconRegistry.founder_avatar(&"avatar-01"))

# 不同 id 应散布到多张肖像 (而非全撞同一张), 验证"公司里人人不同"。
func test_lead_portrait_distributes_across_pool() -> void:
	var seen := {}
	for i in range(60):
		var tex := IconRegistry.lead_portrait(StringName("lead_%04d" % i))
		if tex != null:
			seen[tex.resource_path] = true
	assert_gt(seen.size(), 6, "60 个不同 id 至少应散到 >6 张肖像, 实际 %d" % seen.size())

# 模型架构族归类 (model.arch → 5 族之一)。
func test_model_arch_family_mapping() -> void:
	assert_eq(IconRegistry.arch_family(&"ant_v1"), &"dense")
	assert_eq(IconRegistry.arch_family(&"octopus_sparse"), &"moe")
	assert_eq(IconRegistry.arch_family(&"octopus_super_sparse"), &"moe")
	assert_eq(IconRegistry.arch_family(&"bert_encoder"), &"encoder")
	assert_eq(IconRegistry.arch_family(&"t5_enc_dec"), &"enc_dec")
	assert_eq(IconRegistry.arch_family(&"dit_v1"), &"multimodal")
	assert_eq(IconRegistry.arch_family(&""), &"dense")
	assert_true(IconRegistry.model_icon(&"ant_v1") is Texture2D)

# 每个 arch 科技节点都应归到一个有图的族 (防 arch 新增后 model_icon 落空)。
func test_every_arch_node_maps_to_existing_family() -> void:
	var dir := DirAccess.open("res://resources/data/tech/arch")
	assert_not_null(dir, "arch 节点目录应存在")
	if dir == null:
		return
	for f in dir.get_files():
		if not f.ends_with(".tres"):
			continue
		var arch_id := f.get_basename()
		assert_true(IconRegistry.model_icon(StringName(arch_id)) is Texture2D,
			"arch %s 归族后无图" % arch_id)

# ─── 收藏品逐件图标 (办公室与收藏系统设计 §8) ──────────────────
# 收藏品按**逐件** id 取图 (assets/sprites/ui/collectible/<id>.png), 不按类别复用。

func test_collectible_icon_empty_and_missing_return_null() -> void:
	assert_null(IconRegistry.collectible_icon(&""), "空 id 应回退 null")
	assert_null(IconRegistry.collectible_icon(&"__nope__"), "不存在的收藏 id 应回退 null")

# 每件 collectible .tres 都应有逐件图标 (防漏出图 / 漏导入)。auction_tuning.tres
# 与 collectible spec 同放 collectibles/ 但不是收藏品, 跳过。
func test_every_collectible_has_per_item_icon() -> void:
	var dir := DirAccess.open("res://resources/data/collectibles")
	assert_not_null(dir, "收藏品目录应存在")
	if dir == null:
		return
	var checked := 0
	for f in dir.get_files():
		if not f.ends_with(".tres") or f == "auction_tuning.tres":
			continue
		var cid := f.get_basename()
		assert_true(IconRegistry.collectible_icon(StringName(cid)) is Texture2D,
			"收藏品 %s 缺逐件图标 assets/sprites/ui/collectible/%s.png" % [cid, cid])
		checked += 1
	assert_gt(checked, 70, "应覆盖全部 ~78 件收藏 (实查 %d)" % checked)
