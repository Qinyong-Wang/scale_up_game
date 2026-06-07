class_name EventCard
extends Resource

## Static template for a draftable event. Stored under resources/data/events/.
## Per design/事件系统设计.md §1.
##
## v7 PR-F (2026-05): fame field deleted; trigger conditions use revenue +
## rank in place of the legacy `requires_fame_min` gate.

@export var id: StringName
@export var category: StringName  # &"opportunity" / &"crisis" / &"flavor" / &"routine"
@export var title: String = ""
@export var body: String = ""

# Trigger conditions (AND)
@export var min_turn: int = 0
@export var requires_unlocks: Array[StringName] = []
@export var requires_cash_min: int = -2147483648
# v7 PR-F new triggers
@export var requires_revenue_min: int = 0       # min quarterly_revenue; 0 = no gate
@export var requires_rank_max: int = 0          # min best player rank on `total` board; 0 = no gate
# v10 (2026-05) state gates — 每张卡都要贴合当前局势, 见 事件系统设计.md §1/§4.3.
@export var requires_datacenter: bool = false       # 至少 1 个数据中心
@export var requires_product: bool = false          # 至少 1 个产品
@export var requires_published_model: bool = false  # 至少 1 个 status==published 模型
@export var requires_lead_min: int = 0              # leads 数量下限
@export var requires_staff_min: int = 0             # staff_pool 各 role 求和下限
@export var requires_dataset_min: int = 0           # datasets 数量下限
@export var requires_paid_users_min: int = 0        # paid_users 下限
@export var weight: int = 10
# Authored in design months; EventSystem converts to weekly turns on trigger.
@export var cooldown_months: int = 12
# v11/v17: 单卡触发次数; 0 = 使用 EventSystem 的全局 3 次硬上限。
# 重大 drama / 黑色幽默卡设为 1 (一辈子只来一次), 比硬塞
# cooldown_months=9999 更语义化。计数存 GameState.event_trigger_counts, 见
# 事件系统设计.md §4.7。
@export var max_triggers: int = 0

@export var options: Array[Resource] = []  # Array[EventOption]
# v12: 无选择 flavor / 历史档案卡的被动后果。dismiss_flavor 时结算, 普通
# 选项事件仍使用 EventOption.effects。
@export var passive_effects: Array[Resource] = []  # Array[EventEffect]
