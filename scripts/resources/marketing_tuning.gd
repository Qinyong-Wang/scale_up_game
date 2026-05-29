class_name MarketingTuning
extends Resource

## MarketingSystem tunable knobs. Stored at resources/data/marketing/tuning.tres.
## Per design/营销系统设计.md §6 + design/平衡参数.md §MarketingSystem.
## v7 PR-F (2026-05): fame_boost_per_money deleted with the fame field.

@export var max_concurrent_campaigns: int = 5
## 营销活动占用的营销员工数 (硬性要求 + 锁定, 见 design/营销系统设计.md §4)。
## 随周预算增长: required = clamp(min + floor(weekly_budget / budget_per_extra_staff), min, max)。
## 默认: 至少 2 人, 每 +¥10万/周 多 1 人, 最多 8 人 (¥60万/周+ 才吃满)。
## 没有足够空闲营销员工就不能开新活动 — 并发活动数被营销人头自然限制。
@export var min_staff_per_campaign: int = 2
@export var max_staff_per_campaign: int = 8
@export var budget_per_extra_staff: int = 100000
