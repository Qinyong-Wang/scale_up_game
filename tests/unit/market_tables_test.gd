extends GutTest

## MarketSystem table-driven loading.
## Per design/竞争对手系统设计.md §6 + design/平衡参数.md §MarketSystem.
## v8 PR-H (2026-05): npc_perturb_decay / distillation_* knobs deleted along
## with the step-jump + distillation mechanics.

func test_market_tuning_tres_loads() -> void:
	var r := load("res://resources/data/market/tuning.tres")
	assert_true(r is MarketTuning, "tuning.tres did not load as MarketTuning")

func test_market_tuning_history_limit_matches_balance_doc() -> void:
	var t: MarketTuning = load("res://resources/data/market/tuning.tres")
	assert_eq(int(t.history_limit), 36)

func test_runtime_history_limit_from_table() -> void:
	assert_eq(int(MarketSystem.HISTORY_LIMIT), 36)
