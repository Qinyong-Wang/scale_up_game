extends GutTest

## MarketingSystem table-driven loading.
## Per design/营销系统设计.md §6.
## v7 PR-F2 (2026-05): fame_boost_per_money 字段已与 fame 一起删, 对应断言移除。


func test_marketing_tuning_tres_loads() -> void:
	var r := load("res://resources/data/marketing/tuning.tres")
	assert_true(r is MarketingTuning, "tuning.tres did not load as MarketingTuning")

func test_marketing_tuning_values_match_balance_doc() -> void:
	var t: MarketingTuning = load("res://resources/data/marketing/tuning.tres")
	assert_eq(int(t.max_concurrent_campaigns), 5)

func test_runtime_max_concurrent_campaigns_from_table() -> void:
	assert_eq(int(MarketingSystem.MAX_CONCURRENT_CAMPAIGNS), 5)
