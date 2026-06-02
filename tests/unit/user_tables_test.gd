extends GutTest

## UserSystem table-driven loading.
## Per design/用户系统设计.md §7 + design/平衡参数.md §UserSystem.


func test_user_tuning_tres_loads() -> void:
	var r := load("res://resources/data/user/tuning.tres")
	assert_true(r is UserTuning, "tuning.tres did not load as UserTuning")

func test_user_tuning_values_match_balance_doc() -> void:
	# Canonical values per design/用户系统设计.md §7 + 平衡参数.md §UserSystem.
	var t: UserTuning = load("res://resources/data/user/tuning.tres")
	assert_almost_eq(float(t.total_rank_1_rate), 0.01, 0.0001)
	assert_almost_eq(float(t.total_rank_top3_rate), 0.0, 0.0001)
	assert_almost_eq(float(t.total_rank_below_rate), -0.02, 0.0001)
	assert_almost_eq(float(t.sub_rank_1_rate), 0.0025, 0.0001)
	assert_almost_eq(float(t.sub_rank_top3_rate), 0.0, 0.0001)
	assert_almost_eq(float(t.sub_rank_below_rate), -0.025, 0.0001)
	assert_eq(t.base_curve_knot_turns, [0, 100, 280, 400])
	assert_eq(t.base_curve_knot_values, [0, 100, 10_000, 100_000])
	assert_almost_eq(float(t.base_attraction_rank_1), 1.0, 0.0001)
	assert_almost_eq(float(t.base_attraction_rank_2), 0.5, 0.0001)
	assert_almost_eq(float(t.base_attraction_rank_3), 0.25, 0.0001)
	assert_almost_eq(float(t.base_attraction_rank_else), 0.0, 0.0001)
	assert_eq(int(t.api_tokens_per_sub_per_week), 10_000_000)
	assert_eq(int(t.orphan_product_churn), 5)
	# v12 (2026-05): CAC $40 → $80, conversion_rate 0.025→0.0125. 仍线性.
	assert_almost_eq(float(t.marketing_conversion_rate), 0.0125, 0.0001)

func test_user_tuning_resource_defaults_match_data_table() -> void:
	# 新建 UserTuning 资源时的默认值也必须和 tuning.tres 主表一致, 否则测试夹具
	# 或未来新增 data 资源会悄悄退回旧 2M API 单位。
	var t := UserTuning.new()
	assert_eq(int(t.api_tokens_per_sub_per_week), 10_000_000)
	assert_eq(int(t.orphan_product_churn), 5)
	assert_almost_eq(float(t.marketing_conversion_rate), 0.0125, 0.0001)

func test_runtime_rank_rates_from_table() -> void:
	assert_almost_eq(float(UserSystem.TOTAL_RANK_1_RATE), 0.01, 0.0001)
	assert_almost_eq(float(UserSystem.TOTAL_RANK_BELOW_RATE), -0.02, 0.0001)
	assert_almost_eq(float(UserSystem.SUB_RANK_1_RATE), 0.0025, 0.0001)
	assert_almost_eq(float(UserSystem.SUB_RANK_BELOW_RATE), -0.025, 0.0001)

func test_runtime_base_curve_from_table() -> void:
	assert_eq(UserSystem.BASE_CURVE_KNOT_TURNS, [0, 100, 280, 400])
	assert_eq(UserSystem.BASE_CURVE_KNOT_VALUES, [0, 100, 10_000, 100_000])
	assert_almost_eq(float(UserSystem.BASE_ATTRACTION_RANK_2), 0.5, 0.0001)
	assert_eq(int(UserSystem.API_TOKENS_PER_SUB_PER_WEEK), 10_000_000)
	assert_eq(int(UserSystem.ORPHAN_PRODUCT_CHURN), 5)

func test_runtime_marketing_conversion_rate_from_table() -> void:
	assert_almost_eq(float(UserSystem.MARKETING_CONVERSION_RATE), 0.0125, 0.0001)
