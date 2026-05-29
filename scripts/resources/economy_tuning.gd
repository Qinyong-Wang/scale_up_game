class_name EconomyTuning
extends Resource

## EconomySystem tunable knobs. Stored at resources/data/economy/tuning.tres.
## Per design/经济系统设计.md §7 + design/平衡参数.md §EconomySystem.
## Loaded by EconomySystem._load_tables() at _ready into instance vars of
## the same name (BANKRUPTCY_STREAK_LIMIT, BASE_INTEREST_RATE, etc.).
## starting_cash is the authoritative source for GameState.STARTING_CASH.

@export var starting_cash: int = 1_000_000

@export var bankruptcy_streak_limit: int = 12
## 预警阈值 (< limit): streak 跨过它时 UI 明确提醒「游戏将结束」。见 §4.2。
@export var bankruptcy_warn_streak: int = 8
@export var bankruptcy_depth_floor: int = -1_000_000
@export var bankruptcy_depth_k: float = 3.0
@export var bankruptcy_depth_l: float = 0.5

@export var base_interest_rate: float = 0.01
@export var max_loan_beta: float = 2.0
@export var max_loan_gamma: float = 3.0
## Hard ceiling on _max_loan() regardless of β/γ formula. Late-game revenue +
## net-cash can otherwise push the formula into hundreds of billions, which
## isn't what "single-bank credit line" looks like. Default $20B.
@export var max_loan_absolute_cap: int = 20_000_000_000
## Longest loan contract the bank will underwrite. 156 weeks = 3 years
## because the game calendar uses 52 turns per year.
@export var max_loan_term_weeks: int = 156
@export var loan_id_start_year: int = 2026

@export var valuation_base: int = 500_000
@export var valuation_multiplier: float = 2.0
@export var valuation_cash_coef: float = 0.3
# v7 PR-F: rank_premium replaces the v6 fame_normalizer in the valuation formula.
# +50% for total board rank 1, +25% for rank 2-3, +10% for rank 4-10, else 0.
@export var rank_premium_rank_1: float = 0.50
@export var rank_premium_rank_top3: float = 0.25
@export var rank_premium_rank_top10: float = 0.10
@export var portfolio_bonus_per_model: float = 0.05
@export var founder_min_stake: float = 0.5

@export var burn_window_weeks: int = 3
@export var revenue_window_weeks: int = 12

# 周度税务 (design/经济系统设计.md §4.9). 税基 = 当周经营性净利润 (融资 / 债务
# 本金排除, 利息可抵), 经亏损结转抵减后分两档征:
#   企业所得税: 超过 corp_tax_exemption 的部分 × corp_tax_rate
#   AI 税(UBI): 超过 ai_tax_threshold 的部分再 × ai_tax_rate
@export var corp_tax_rate: float = 0.25
@export var corp_tax_exemption: int = 1_000_000
@export var ai_tax_rate: float = 0.20
@export var ai_tax_threshold: int = 1_000_000_000
