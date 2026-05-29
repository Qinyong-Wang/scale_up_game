class_name UserTuning
extends Resource

## UserSystem tunable knobs. Stored at resources/data/user/tuning.tres.
## Per design/用户系统设计.md §6 + design/平衡参数.md §UserSystem.
##
## v7 PR-F (2026-05): pure rank-driven demand. fame-era knobs (attract_k1/k2,
## churn_k, base_churn_rate, quality_base, token_per_user_per_month,
## token_base_per_fame) have been deleted with the fame field.

# --- Rank bonus rates (additive per-week) ---
@export var total_rank_1_rate: float = 0.01       # 总榜第一: +1%/周 (v11: ×0.5)
@export var total_rank_top3_rate: float = 0.0     # 总榜前三 (2/3): 0
@export var total_rank_below_rate: float = -0.02  # 总榜 4+/未上榜: -2%/周 (v11: ×0.5)
@export var sub_rank_1_rate: float = 0.0025       # 子榜第一: +0.25%/周 (v11: ×0.5)
@export var sub_rank_top3_rate: float = 0.0
@export var sub_rank_below_rate: float = -0.025   # 子榜 4+/未上榜: -2.5%/周 (v11: ×0.5)

# --- Piecewise-linear base demand curve knots (turn, value) ---
# Default: (0, 0) → (100, 100) → (280, 10K) → (400, 100K), clamp at 100K above 400.
@export var base_curve_knot_turns: Array[int] = [0, 100, 280, 400]
@export var base_curve_knot_values: Array[int] = [0, 100, 10_000, 100_000]
# Per-rank multiplier on the curve. Indices: 1, 2, 3, "else".
@export var base_attraction_rank_1: float = 1.0
@export var base_attraction_rank_2: float = 0.5
@export var base_attraction_rank_3: float = 0.25
@export var base_attraction_rank_else: float = 0.0

# --- API product token unit conversion ---
@export var api_tokens_per_sub_per_week: int = 2_000_000

# --- Orphan product churn (bound model unpublished) ---
@export var orphan_product_churn: int = 5

# --- Marketing CAC (linear) ---
@export var marketing_conversion_rate: float = 0.0125  # v12: CAC $40→$80 (×2)
