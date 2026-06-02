class_name GPUSpec
extends Resource

## Static template for a GPU model. Stored under resources/data/infra/gpus/*.tres.
## Per design/基础设施系统设计.md §1 + design/平衡参数.md GPUSpec table.
##
## Naming uses 化名 (codenames): cypress / maple / bamboo brands; tiers t1/t2/t3.

@export var id: StringName
@export var display_name: String = ""
@export var brand: StringName = &""           # &"cypress" / &"maple" / &"bamboo"
@export var tier: StringName = &""            # &"t1" / &"t2" / &"t3"
@export var per_card_tflops: float = 0.0      # FP16/BF16 single-card training TFLOPs
@export var per_card_inference_tflops: float = 0.0  # Sustained single-card inference TFLOPs
                                              # (batched + KV cache + memory-bandwidth bound; ~0.3..1.5%
                                              # of per_card_tflops; design value, not physical peak.
                                              # Used as: inference_tflops × 1e12 / model.flops_per_token = t/s.)
@export var purchase_price: int = 0           # ¥/card, one-shot
@export var maintenance_per_week: int = 0     # ¥/card/week (no power); 1 turn = 1 week
@export var ecosystem_score: float = 1.0      # 0..1, training-throughput multiplier
                                              # (software / framework maturity). Baked into
                                              # dc.train_tflops; penalizes TRAINING only —
                                              # inference stays at full speed.
                                              # cypress 1.0 / maple 0.8 / bamboo 0.6.
@export var native_cluster_eff: float = 0.85  # 0..1
@export var release_turn: int = 0             # turn this GPU goes on sale
@export var rent_weekly_cost: int = 0         # ¥/card/week for cloud GPU rental (no upfront, whole-cluster only)
                                              # 2026-05: = purchase_price / 40 (cloud rents pay off a card in 40 weeks).
@export var power_factor: float = 1.0         # relative power draw; cypress_t1 anchored at 1.0.
                                              # weekly electricity = power.weekly_cost_per_card × power_factor.
                                              # set per 功耗 ∝ 算力^0.45 (perf/watt improves each gen, so
                                              # power grows far slower than compute). See 基础设施系统设计.md §1.5.
