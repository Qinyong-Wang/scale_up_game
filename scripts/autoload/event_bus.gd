extends Node

## Global notification hub. Past-tense signals only; emit and forget.
## Systems and UI subscribe; senders do not consume return values.
## Per design/系统耦合矩阵.md §4.

# Signals are intentionally emitted/connected by other systems, so each
# declaration suppresses Godot's same-class UNUSED_SIGNAL warning.

# Lifecycle
@warning_ignore("unused_signal")
signal state_reset
@warning_ignore("unused_signal")
signal save_loaded

# i18n — emitted by Preferences.set_locale when the UI language changes at
# runtime. main.gd re-renders all tabs / top bar / nav on this. Per
# design/国际化设计.md §11.
@warning_ignore("unused_signal")
signal locale_changed(locale: String)

# Turn
@warning_ignore("unused_signal")
signal phase_started(phase: StringName, turn: int)
@warning_ignore("unused_signal")
signal turn_resolved(turn: int)

# Economy
@warning_ignore("unused_signal")
signal resources_changed(delta: Dictionary, reason: StringName)
@warning_ignore("unused_signal")
signal cash_changed(delta: int, reason: StringName)
@warning_ignore("unused_signal")
signal debt_changed(delta: int, reason: StringName)
@warning_ignore("unused_signal")
signal equity_changed(dilution: float)
@warning_ignore("unused_signal")
signal loan_taken(loan_id: StringName)
@warning_ignore("unused_signal")
signal loan_repaid(loan_id: StringName, fully: bool)
@warning_ignore("unused_signal")
signal funding_completed(amount: int, dilution: float, valuation: int)
## Weekly financial ledger rolled at resolve phase. UI subscribes to refresh
## the financial report. See design/经济系统设计.md §4.8.
@warning_ignore("unused_signal")
signal ledger_rolled(turn: int, snapshot: Dictionary)
@warning_ignore("unused_signal")
signal bankruptcy_warning(reason: StringName, streak: int, threshold: int)
@warning_ignore("unused_signal")
signal bankruptcy_triggered(reason: StringName)

# Hiring
@warning_ignore("unused_signal")
signal lead_hired(lead_id: StringName)
@warning_ignore("unused_signal")
signal lead_fired(lead_id: StringName)
@warning_ignore("unused_signal")
signal lead_locked(lead_id: StringName, task_id: StringName)
@warning_ignore("unused_signal")
signal lead_released(lead_id: StringName)
@warning_ignore("unused_signal")
signal lead_assigned(lead_id: StringName, product_id: StringName)
@warning_ignore("unused_signal")
signal lead_unassigned(lead_id: StringName)
@warning_ignore("unused_signal")
signal staff_changed(role: StringName, new_count: int)
@warning_ignore("unused_signal")
signal lead_pool_refreshed(pool: Array)
@warning_ignore("unused_signal")
signal player_scientist_created(lead_id: StringName)

# Infra
@warning_ignore("unused_signal")
signal datacenter_added(dc_id: StringName)
@warning_ignore("unused_signal")
signal datacenter_removed(dc_id: StringName)
@warning_ignore("unused_signal")
signal datacenter_status_changed(dc_id: StringName, old_status: StringName, new_status: StringName)
@warning_ignore("unused_signal")
signal model_deployed(dc_id: StringName, model_id: StringName)
@warning_ignore("unused_signal")
signal open_source_model_deployed(dc_id: StringName, release_id: StringName)
@warning_ignore("unused_signal")
signal model_undeployed(dc_id: StringName, model_id: StringName)
@warning_ignore("unused_signal")
signal construction_progress(construction_id: StringName, remaining: int, total: int)
@warning_ignore("unused_signal")
signal construction_completed(construction_id: StringName, dc_id: StringName)
@warning_ignore("unused_signal")
signal gpus_bought(dc_id: StringName, gpu_id: StringName, count: int, total_cost: int)
@warning_ignore("unused_signal")
signal gpus_sold(dc_id: StringName, count: int, refund: int)
@warning_ignore("unused_signal")
signal dc_compute_recomputed(dc_id: StringName, train_tflops: float, inference_tflops: float, serving_tokens_per_sec: float)

# Dataset
@warning_ignore("unused_signal")
signal dataset_added(dataset_id: StringName, source: StringName)
@warning_ignore("unused_signal")
signal dataset_removed(dataset_id: StringName)
@warning_ignore("unused_signal")
signal dataset_locked(dataset_id: StringName, task_id: StringName)
@warning_ignore("unused_signal")
signal dataset_released(dataset_id: StringName)
## v2: emitted at half-year boundaries (turn % 26 == 0) so the data panel can
## highlight new arrivals. Per 数据集系统设计 §4 + §6.4.
@warning_ignore("unused_signal")
signal dataset_market_updated(kind: StringName)

# Research
# `provenance` is &"trained" for player-trained models, &"downloaded_os" for
# models materialised from open-source templates. Per 公共枚举表.md §6bis.
@warning_ignore("unused_signal")
signal model_added(model_id: StringName, provenance: StringName)
@warning_ignore("unused_signal")
signal model_updated(model_id: StringName, capability_delta: Dictionary)
@warning_ignore("unused_signal")
signal model_evaluated(model_id: StringName, capability: Dictionary)
@warning_ignore("unused_signal")
signal model_published(model_id: StringName, is_open_source: bool)
@warning_ignore("unused_signal")
signal model_unpublished(model_id: StringName)
@warning_ignore("unused_signal")
signal model_deleted(model_id: StringName)
@warning_ignore("unused_signal")
signal model_price_changed(model_id: StringName, new_price: float)

# Tech tree
@warning_ignore("unused_signal")
signal tech_research_started(tree: StringName, node_id: StringName, task_id: StringName)
@warning_ignore("unused_signal")
signal tech_unlocked(tree: StringName, node_id: StringName)
@warning_ignore("unused_signal")
signal tech_research_cancelled(tree: StringName, node_id: StringName)

# Tasks
@warning_ignore("unused_signal")
signal task_started(id: StringName, subtype: StringName)
@warning_ignore("unused_signal")
signal task_progress(id: StringName, elapsed: int, total: int)
@warning_ignore("unused_signal")
signal task_completed(id: StringName, subtype: StringName, payload: Dictionary)
@warning_ignore("unused_signal")
signal task_cancelled(id: StringName, refund: int)
@warning_ignore("unused_signal")
signal task_resources_locked(id: StringName, locked: Dictionary)
@warning_ignore("unused_signal")
signal task_resources_released(id: StringName, released: Dictionary)
@warning_ignore("unused_signal")
signal task_delayed(id: StringName, new_total: int)

# Market / Competitors
@warning_ignore("unused_signal")
signal leaderboard_resolved(turn: int)
# v7 PR-F (2026-05): `fame_changed` signal deleted (fame field is gone).
@warning_ignore("unused_signal")
signal player_rank_changed(board: StringName, old_rank: int, new_rank: int)
# v8 PR-H (2026-05): `npc_distilled` deleted (distillation removed); replaced
# by `npc_released` (timeline-driven product launches drive narrative).
@warning_ignore("unused_signal")
signal npc_released(npc_id: StringName, release_id: StringName, release_turn: int)

# User
@warning_ignore("unused_signal")
signal users_resolved(turn: int, paid_users_delta: int)
@warning_ignore("unused_signal")
signal token_demand_changed(model_id: StringName, new_value: int)
@warning_ignore("unused_signal")
signal paid_users_changed(delta: int, new_total: int)

# Product
@warning_ignore("unused_signal")
signal product_created(product_id: StringName)
@warning_ignore("unused_signal")
signal product_updated(product_id: StringName, changed_fields: Array)
@warning_ignore("unused_signal")
signal product_deleted(product_id: StringName)
@warning_ignore("unused_signal")
signal subscribers_changed(product_id: StringName, delta: int, new_total: int)
@warning_ignore("unused_signal")
signal quality_recomputed(product_id: StringName, new_quality: float)

# Monetization
@warning_ignore("unused_signal")
signal revenue_resolved(turn: int, breakdown: Dictionary)

# Marketing
@warning_ignore("unused_signal")
signal campaign_started(campaign_id: StringName)
@warning_ignore("unused_signal")
signal campaign_terminated(campaign_id: StringName, reason: StringName)
@warning_ignore("unused_signal")
signal campaign_progress(campaign_id: StringName, remaining: int, total: int)

# Events
@warning_ignore("unused_signal")
signal event_pushed(event_id: StringName, category: StringName, title: String)
@warning_ignore("unused_signal")
signal event_resolved(event_id: StringName, option_id: StringName, applied_effects: Array)

# Charity — emitted by CharitySystem when a charity task completes and the
# donation is credited to its cause (the capped buff activates at this point).
# Per design/慈善系统设计.md §7.
@warning_ignore("unused_signal")
signal charity_completed(cause_id: StringName, amount: int, cumulative: int)

# Office / Collection — CollectionSystem auction buy / cabinet sale + trophy
# awards. Per design/办公室与收藏系统设计.md §7. (trophy_awarded is declared now;
# its award sources are wired in a later phase.)
@warning_ignore("unused_signal")
signal collectible_bought(collectible_id: StringName, price: int)
@warning_ignore("unused_signal")
signal collectible_sold(collectible_id: StringName, proceeds: int)
@warning_ignore("unused_signal")
signal trophy_awarded(trophy_id: StringName)

# Universe simulation capstone (慈善三期). Per design/宇宙模拟工程设计.md §7.
@warning_ignore("unused_signal")
signal simulation_stage_completed(stage_id: StringName, stages_done: int)
@warning_ignore("unused_signal")
signal universe_answer_revealed()
