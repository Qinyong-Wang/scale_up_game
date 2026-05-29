extends GutTest

## UserSystem table-driven loading.
## Per design/用户系统设计.md §7 + design/平衡参数.md §UserSystem.


func test_user_tuning_tres_loads() -> void:
	var r := load("res://resources/data/user/tuning.tres")
	assert_true(r is UserTuning, "tuning.tres did not load as UserTuning")

func test_user_tuning_values_match_balance_doc() -> void:
	# Canonical values per design/用户系统设计.md §7 + 平衡参数.md §UserSystem.
	var t: UserTuning = load("res://resources/data/user/tuning.tres")
	assert_almost_eq(float(t.attract_k1), 1.0, 0.001)
	assert_almost_eq(float(t.attract_k2), 1.0, 0.0001)
	assert_almost_eq(float(t.churn_k), 0.05, 0.0001)
	assert_almost_eq(float(t.quality_base), 0.6, 0.001)
	assert_eq(int(t.token_per_user_per_month), 2000)
	# v3 (2026-05): API 需求公式整体 ×100, 提升 API 营收占比.
	# Per 用户系统设计.md §7 + 平衡参数.md §UserSystem.
	assert_almost_eq(float(t.token_base_per_fame), 15_000_000.0, 0.001)
	# v3 (2026-05): CAC $20 → $40, conversion_rate halved. 营销保持线性.
	# v12 (2026-05): CAC $40 → $80, conversion_rate 再 halved (0.025→0.0125). 仍线性.
	assert_almost_eq(float(t.marketing_conversion_rate), 0.0125, 0.0001)

func test_runtime_attract_k1_from_table() -> void:
	# UserSystem.ATTRACT_K1 et al. populated from the tres at _ready.
	assert_almost_eq(float(UserSystem.ATTRACT_K1), 1.0, 0.001)

func test_runtime_churn_k_from_table() -> void:
	assert_almost_eq(float(UserSystem.CHURN_K), 0.05, 0.0001)

func test_runtime_marketing_conversion_rate_from_table() -> void:
	assert_almost_eq(float(UserSystem.MARKETING_CONVERSION_RATE), 0.0125, 0.0001)
