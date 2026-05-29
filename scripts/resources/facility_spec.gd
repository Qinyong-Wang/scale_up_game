class_name FacilitySpec
extends Resource

## Static template for a facility tier (机房规模档位).
## Stored under resources/data/infra/facilities/*.tres.
## Per design/基础设施系统设计.md §1 + design/平衡参数.md FacilitySpec table.
##
## A facility decides only the physical building (max GPU capacity, build
## time, land/rent costs, cash unlock). GPUs are a separate asset bought
## independently after the facility is online. v7 PR-F (2026-05): unlock
## gating is purely cash-based; the legacy `unlock_fame_required` field is
## gone (fame field deleted).
##
## All recurring cost fields are PER-WEEK (1 turn = 1 week).
## solo/pod/rack (≤72 cards) are home/office setups with land_weekly_cost = 0.

@export var id: StringName
@export var display_name: String = ""
@export var tier_index: int = 1                     # 1..19 (含太空 tier 16/17/18 + 微型星球 19)
@export var max_gpu_count: int = 1
@export var build_weeks: int = 0                    # weeks to self-build
@export var land_weekly_cost: int = 0               # owned weekly land/cooling/etc (¥/week)
@export var land_build_cost: int = 0                # one-shot self-build cost (¥; 40% of total, GPU is the other 60%)
@export var rent_weekly_cost: int = 0               # rented weekly cost (¥/week; no GPU); zero upfront
# v7 PR-F: cash gate; large tiers require this much cash on hand to rent/build.
@export var unlock_cash_required: int = 0

# 太空数据中心训练加速 (2026-05): 训练算力乘子加成 (0.10 = +10%)。真空辐射散热
# → 无热降频, 只加训练 (烘焙进 InfraSystem._recompute_compute 的 train_tflops),
# 不影响推理。地面档为 0; 太空档 space_s/m/l +10/15/20%, planet +20%。
# UI (DC 卡片 + 预训练 DC 下拉) 经 InfraSystem.facility_train_bonus 单独显示。
# 见 design/基础设施系统设计.md §1.5 / §4.1。
@export var train_speed_bonus: float = 0.0

# 可选建筑图标 (2026-05): 显示在 DC 卡片头像 + 新建数据中心档位预览。
# 见 design/图片素材生成流程.md §8。空 / 资源缺失时 UI 回退到 seed 配色 + glyph。
@export var icon_path: String = ""

## 加载建筑图标贴图; 路径为空或资源不存在时返回 null (调用方走回退, 不报错)。
func load_icon() -> Texture2D:
	if icon_path.is_empty():
		return null
	if not ResourceLoader.exists(icon_path):
		return null
	return load(icon_path) as Texture2D
