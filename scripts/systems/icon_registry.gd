class_name IconRegistry
extends RefCounted

## 统一 UI 图标注册表 — 按 (category, key) 取 `assets/sprites/ui/<category>/<key>.png` 贴图。
##
## 让各 view / card 不再各写一份 load(): 数据集按 modality、产品按 type、任务按 subtype、
## 科技按 tree、GPU 按植物族、供电按 id、lead 按 specialty 取图。
## 缺图 / 资源不存在 → null (调用方 Avatar 走 seed 配色 + glyph 回退, 不报错)。
## 生成与文件约定见 design/图片素材生成流程.md §8。

const _BASE := "res://assets/sprites/ui/%s/%s.png"

# path -> Texture2D | null; 进程内缓存, 避免每次刷新重 load。
static var _cache: Dictionary = {}

## category 例: &"dataset" / &"product" / &"task" / &"tech" / &"gpu" / &"power" / &"lead" / &"marketing"。
## key 为该类下的具体键 (modality / type / subtype / tree / 植物族 / 供电 id / specialty)。
static func get_icon(category: StringName, key: StringName) -> Texture2D:
	if String(category).is_empty() or String(key).is_empty():
		return null
	var path: String = _BASE % [category, key]
	if _cache.has(path):
		return _cache[path]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	_cache[path] = tex
	return tex

## GPU 图标按植物族 (cypress/maple/bamboo) 复用; 从 gpu_id (如 cypress_t2) 取族前缀。
static func gpu_icon(gpu_id: StringName) -> Texture2D:
	var s := String(gpu_id)
	var us := s.find("_")
	var family: String = s.substr(0, us) if us != -1 else s
	return get_icon(&"gpu", StringName(family))

# lead 肖像是按人分配的**多元肖像池** (性别均衡 + 族裔/年龄多样), 不按 specialty。
# 同一 lead.id 永远拿同一张; 不同 id 均匀散到池子里, 一家公司里人人不同。
const _LEAD_POOL_SIZE := 12

# 每张肖像的族裔/性别 (0-based, 与 lead_portrait_index 对齐: 第 i 项描述 portrait-(i+1))。
# region 取值见 PersonName.REGIONS; gender ∈ {male, female}。具体长相 (脸/发/年龄)
# 是 tools/art/generate.py 的 leads 批次生成提示词, 这里只记取名要用的族裔/性别。
# 取名靠这张表让"名跟随脸" (见 design/招聘系统设计.md §1.3); western 一池覆盖所有
# Anglophone 头像 (白人/黑人/…), 不按肤色细分。改动 portrait 提示词时同步这里。
const LEAD_PORTRAIT_DEMOGRAPHICS: Array[Dictionary] = [
	{region = &"east_asian", gender = &"female"},      # portrait-01 East Asian woman
	{region = &"western", gender = &"male"},           # portrait-02 Black man
	{region = &"western", gender = &"male"},           # portrait-03 white man
	{region = &"south_asian", gender = &"female"},     # portrait-04 South Asian woman
	{region = &"western", gender = &"female"},          # portrait-05 white woman
	{region = &"western", gender = &"female"},          # portrait-06 Black woman
	{region = &"hispanic", gender = &"male"},          # portrait-07 Hispanic man
	{region = &"middle_eastern", gender = &"male"},    # portrait-08 Middle Eastern man
	{region = &"east_asian", gender = &"male"},        # portrait-09 East Asian man
	{region = &"hispanic", gender = &"female"},        # portrait-10 Latina woman
	{region = &"western", gender = &"male"},           # portrait-11 white man (bald)
	{region = &"southeast_asian", gender = &"female"}, # portrait-12 Southeast Asian woman
]

## seed_id (通常 lead.id) 落到肖像池的 0-based 索引; 空 → -1。取名与取图共用它,
## 保证"名跟随脸" (HiringSystem 用 lead_demographics 取名, 这里取图)。
static func lead_portrait_index(seed_id: StringName) -> int:
	var s := String(seed_id)
	if s.is_empty():
		return -1
	return _stable_hash(s) % _LEAD_POOL_SIZE

## seed_id 通常传 lead.id; 空 → null (回退 glyph)。
static func lead_portrait(seed_id: StringName) -> Texture2D:
	var idx: int = lead_portrait_index(seed_id)
	if idx < 0:
		return null
	return get_icon(&"lead", StringName("portrait-%02d" % (idx + 1)))

## seed_id 对应肖像的 {region, gender}; 空 id → {} (调用方回退 east_asian/female)。
static func lead_demographics(seed_id: StringName) -> Dictionary:
	var idx: int = lead_portrait_index(seed_id)
	if idx < 0:
		return {}
	return LEAD_PORTRAIT_DEMOGRAPHICS[idx]

# 创始人专属头像 (新游戏玩家选, 写到 Lead.avatar_id) — 与肖像池分开的一组图,
# 文件 assets/sprites/ui/founder/avatar-NN.png。见 design/出身系统设计.md §3。
const _FOUNDER_AVATAR_COUNT := 8

## 新游戏头像网格用: 返回全部可选 key (avatar-01..NN), 与美术是否就位无关。
static func founder_avatar_keys() -> Array:
	var keys: Array = []
	for i in range(1, _FOUNDER_AVATAR_COUNT + 1):
		keys.append(StringName("avatar-%02d" % i))
	return keys

## key 为 avatar-NN; 缺图 → null (调用方 Avatar 走 seed 配色 + 首字母回退)。
static func founder_avatar(key: StringName) -> Texture2D:
	return get_icon(&"founder", key)

# 公司标志贴图 (新游戏可选品牌标记, 2026-05 重做) — 确定性生成的抽象 logo 标记,
# 文件 assets/sprites/ui/brand/brand-NN.png。见 design/出身系统设计.md §2 +
# UITheme.draw_company_logo (叠到浅灰圆角底上绘制; 缺图回退程序化 A)。
const _BRAND_LOGO_COUNT := 14

## 新游戏标志网格用: 返回全部可选品牌标记 key (brand-01..NN), 与美术是否就位无关。
static func company_logo_keys() -> Array:
	var keys: Array = []
	for i in range(1, _BRAND_LOGO_COUNT + 1):
		keys.append(StringName("brand-%02d" % i))
	return keys

## key 为 brand-NN; 缺图 → null (调用方 UITheme.draw_company_logo 回退到程序化 A)。
static func company_logo_texture(key: StringName) -> Texture2D:
	return get_icon(&"brand", key)

# 办公室房间贴图 (key: room-bg / desk / computer / trophy), 文件
# assets/sprites/ui/office/<key>.png。本期房间用程序化占位, 真图就位后自动替换;
# 缺图 → null (OfficeView 回退到 _draw 占位)。见 design/办公室与收藏系统设计.md §8。
static func office_texture(key: StringName) -> Texture2D:
	return get_icon(&"office", key)

# 收藏品**逐件**缩略图 (key = CollectibleSpec.id), 文件
# assets/sprites/ui/collectible/<id>.png。拍卖行 lot 卡与收藏柜藏品卡用作头像;
# 每件收藏一张独立图标 (不按类别复用)。缺图 → null (Avatar 回退 seed 配色 + 首字母)。
# 见 design/办公室与收藏系统设计.md §8。
static func collectible_icon(collectible_id: StringName) -> Texture2D:
	return get_icon(&"collectible", collectible_id)

# 营销活动通用缩略图 (key = campaign), 文件 assets/sprites/ui/marketing/<key>.png。
# 缺图 → null (Avatar 回退 seed 配色 + 首字母)。
static func marketing_icon(key: StringName) -> Texture2D:
	return get_icon(&"marketing", key)

# 慈善公益方向图标 (key = CharityCauseSpec.id: bio_science / fundamental_compute /
# social_welfare), 文件 assets/sprites/ui/charity/<id>.png。慈善 tab 方向卡用作头像。
# 缺图 → null (Avatar 回退 seed 配色 + 首字母)。见 design/图片素材生成流程.md §8bis。
static func charity_icon(cause_id: StringName) -> Texture2D:
	return get_icon(&"charity", cause_id)

# 宇宙模拟阶梯图标 (key = SimulationStageSpec.id: weather / ocean / earth /
# solar_system / universe), 文件 assets/sprites/ui/simulation/<id>.png。模拟阶梯卡用。
# 缺图 → null (Avatar 回退 seed 配色 + 首字母)。
static func simulation_icon(stage_id: StringName) -> Texture2D:
	return get_icon(&"simulation", stage_id)

## lead 头像统一入口: 有显式 avatar_id (玩家创始人) → 取 founder 头像;
## 否则按 lead.id 哈希散到多元肖像池。空 avatar_id 是普通 lead 的常态。
static func lead_texture(seed_id: StringName, avatar_id: StringName) -> Texture2D:
	if not String(avatar_id).is_empty():
		return founder_avatar(avatar_id)
	return lead_portrait(seed_id)

# 模型图标按**架构族**复用: model.arch 是具体科技节点 id (ant_v1/octopus_sparse/
# bert_encoder…, 二十多个), 太多不逐个出图; 归到 5 个族之一 (dense/moe/encoder/
# enc_dec/multimodal)。归类靠 arch id 关键词, 认不出的默认 dense。
static func model_icon(arch: StringName) -> Texture2D:
	return get_icon(&"model", arch_family(arch))

static func arch_family(arch: StringName) -> StringName:
	var a := String(arch).to_lower()
	if a.is_empty():
		return &"dense"
	if a.find("sparse") != -1 or a.find("moe") != -1:
		return &"moe"
	if a.find("enc_dec") != -1 or a.begins_with("t5") or a.begins_with("ul2"):
		return &"enc_dec"
	if a.find("encoder") != -1 or a.begins_with("bert") or a.begins_with("roberta") \
			or a.begins_with("electra") or a.begins_with("deberta"):
		return &"encoder"
	if a.find("dit") != -1 or a.find("pixel") != -1 or a.find("multimodal") != -1 \
			or a.find("audio") != -1 or a.find("cross_train") != -1:
		return &"multimodal"
	return &"dense"

# FNV-1a 32-bit — 同 Avatar._stable_hash, 单字符输入也能均匀分布。
static func _stable_hash(s: String) -> int:
	var h: int = 2166136261
	for c in s.to_utf8_buffer():
		h = (h ^ c) & 0xFFFFFFFF
		h = (h * 16777619) & 0xFFFFFFFF
	return h

## 测试用: 清缓存 (改资源后强制重 load)。
static func clear_cache_for_test() -> void:
	_cache.clear()
