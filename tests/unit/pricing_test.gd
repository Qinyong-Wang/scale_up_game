extends GutTest

## v6 PR-E (2026-05): pricing system unit tests — base_price /
## guidance_price / weekly_growth_rate / yearly baseline cache. Per
## design/平衡参数.md §ResearchSystem + design/研究系统设计.md §4.4.


# cypress_t0 at turn 0 (released at turn 0, only GPU in past-year window
# fallback at year 0): per_card_inference_tflops = 37.5, native_cluster_eff
# = 0.85, maintenance_per_week = 4, grid.weekly_cost_per_card = 24 (2026-05),
# cypress_t0.power_factor = 0.66 → 电费 = 24 × 0.66 = 15.84,
# purchase_price = 5200, GPU_AMORTIZATION_WEEKS = 156 (3 年, CapEx 摊销).
# weekly_cost = 4 + 24×0.66 + 5200/156 = 53.17...
# $_per_TFLOP_second = weekly_cost / (37.5 × 604800 × 0.85)
const _EXPECTED_T0_DOLLAR_PER_TFS: float = \
		(4.0 + 24.0 * 0.66 + 5200.0 / 156.0) / (37.5 * 604_800.0 * 0.85)

# 7B-equivalent flops_per_token = 2 × 7000 (M) × 1.0 (active) × 1e6 = 1.4e10.
const _FPT_7B: float = 1.4e10

func before_each() -> void:
	GameState.reset()
	# Force a baseline cache miss so each test gets a fresh snapshot.
	ResearchSystem._baseline_cache = {year = -1, value = 0.0}

func _make_model_with_fpt(fpt: float, is_open_source: bool = false) -> Model:
	var m := Model.new()
	m.id = &"m_test"
	m.arch = &"ant_v1"
	m.status = &"published"
	m.flops_per_token = fpt
	m.is_open_source = is_open_source
	m.per_token_price = 0.0
	GameState.models.append(m)
	return m

# ---- base_price_per_token ----------------------------------------------

func test_base_price_zero_when_fpt_zero() -> void:
	# Defensive: a model with no flops_per_token can't be costed; return 0.
	var m: Model = _make_model_with_fpt(0.0)
	assert_almost_eq(ResearchSystem.base_price_per_token(m), 0.0, 1e-20)

func test_base_price_7b_at_turn_0_matches_t0_gpu() -> void:
	# 7B fpt = 1.4e10 → base = $_per_TFLOP_second × 1.4e10 / 1e12
	#                        = $_per_TFLOP_second × 0.014
	GameState.turn = 0
	var m: Model = _make_model_with_fpt(_FPT_7B)
	var expected: float = _EXPECTED_T0_DOLLAR_PER_TFS * _FPT_7B / 1.0e12
	assert_almost_eq(ResearchSystem.base_price_per_token(m), expected, expected * 0.001)

func test_base_price_scales_linearly_with_fpt() -> void:
	# 10× larger model → 10× base price (per token costs more compute).
	GameState.turn = 0
	var small: Model = _make_model_with_fpt(_FPT_7B)
	var large: Model = _make_model_with_fpt(_FPT_7B * 10.0)
	assert_almost_eq(
		ResearchSystem.base_price_per_token(large),
		ResearchSystem.base_price_per_token(small) * 10.0,
		ResearchSystem.base_price_per_token(small) * 0.001)

# ---- guidance_price_per_token ------------------------------------------

func test_guidance_price_open_source_is_5x_base() -> void:
	GameState.turn = 0
	var m: Model = _make_model_with_fpt(_FPT_7B, true)
	assert_almost_eq(
		ResearchSystem.guidance_price_per_token(m),
		ResearchSystem.base_price_per_token(m) * 5.0,
		1e-12)

func test_guidance_price_closed_source_is_100x_base() -> void:
	GameState.turn = 0
	var m: Model = _make_model_with_fpt(_FPT_7B, false)
	assert_almost_eq(
		ResearchSystem.guidance_price_per_token(m),
		ResearchSystem.base_price_per_token(m) * 100.0,
		1e-12)

func test_guidance_price_downloaded_os_treated_as_open_source() -> void:
	# Even is_open_source = false, provenance == downloaded_os triggers OS path.
	GameState.turn = 0
	var m: Model = _make_model_with_fpt(_FPT_7B, false)
	m.provenance = &"downloaded_os"
	assert_almost_eq(
		ResearchSystem.guidance_price_per_token(m),
		ResearchSystem.base_price_per_token(m) * 5.0,
		1e-12)

# ---- weekly_growth_rate -------------------------------------------------

func _rate_at_ratio(ratio: float, is_open_source: bool = true) -> float:
	# Compose a model and a price s.t. price / guidance == ratio.
	GameState.turn = 0
	var m: Model = _make_model_with_fpt(_FPT_7B, is_open_source)
	var guidance: float = ResearchSystem.guidance_price_per_token(m)
	m.per_token_price = guidance * ratio
	return ResearchSystem.weekly_growth_rate(m)

func test_growth_rate_zero_price_is_max_bonus() -> void:
	# v11: 各档 ×0.5。+4% → +2%。
	assert_almost_eq(_rate_at_ratio(0.0), 0.02, 1e-9)

func test_growth_rate_at_06_is_max_bonus() -> void:
	assert_almost_eq(_rate_at_ratio(0.6), 0.02, 1e-9)

func test_growth_rate_at_08_is_2pct() -> void:
	# v11: 0.05 - 0.05 × 0.8 = 0.01
	assert_almost_eq(_rate_at_ratio(0.8), 0.01, 1e-9)

func test_growth_rate_at_09_is_1pct() -> void:
	# v11: 0.05 - 0.05 × 0.9 = 0.005
	assert_almost_eq(_rate_at_ratio(0.9), 0.005, 1e-9)

func test_growth_rate_at_guidance_is_zero() -> void:
	assert_almost_eq(_rate_at_ratio(1.0), 0.0, 1e-9)

func test_growth_rate_at_15_is_minus_10pct() -> void:
	# v11: -0.10 × (1.5 - 1.0) = -0.05
	assert_almost_eq(_rate_at_ratio(1.5), -0.05, 1e-9)

func test_growth_rate_at_20_is_minus_20pct() -> void:
	# v11: -0.10 × (2.0 - 1.0) = -0.10
	assert_almost_eq(_rate_at_ratio(2.0), -0.10, 1e-9)

func test_growth_rate_at_25_is_cliff() -> void:
	# r >= 2.5 returns the sentinel -1.0 (cliff). UserSystem treats this as
	# "zero this week, multiplier preserved". Use 2.5001 not 2.5: guidance×ratio
	# /guidance round-trips just under 2.5 on some base prices (float knife-edge,
	# see test_preview_growth_rate_open_source_uses_os_guidance). Stay inside.
	assert_almost_eq(_rate_at_ratio(2.5001), -1.0, 1e-9)

func test_growth_rate_above_25_stays_cliff() -> void:
	assert_almost_eq(_rate_at_ratio(5.0), -1.0, 1e-9)

func test_growth_rate_returns_zero_when_guidance_zero() -> void:
	# fpt=0 → guidance=0; defensive: rate must not divide by zero.
	GameState.turn = 0
	var m: Model = _make_model_with_fpt(0.0)
	m.per_token_price = 1.0
	assert_almost_eq(ResearchSystem.weekly_growth_rate(m), 0.0, 1e-12)

# ---- yearly baseline cache + last-year-best logic ----------------------

func test_baseline_caches_within_a_year() -> void:
	GameState.turn = 5
	var m: Model = _make_model_with_fpt(_FPT_7B)
	var first: float = ResearchSystem.base_price_per_token(m)
	# Mutate the cache and confirm same-year call returns the mutated value
	# (proving we hit cache).
	ResearchSystem._baseline_cache.value = 999.0
	var second: float = ResearchSystem.base_price_per_token(m)
	assert_almost_eq(second, 999.0 * _FPT_7B / 1.0e12, 1e-9)
	# Sanity: first call was the real value (not the mutated one).
	assert_ne(first, second)

func test_baseline_recomputes_on_year_boundary() -> void:
	GameState.turn = 5
	var m: Model = _make_model_with_fpt(_FPT_7B)
	var y0: float = ResearchSystem.base_price_per_token(m)
	# Cross into year 1 (turn ≥ 52). Same set of GPUs already released by
	# turn 0 still applies, but the past-year window now includes year 0
	# itself — cypress_t0 (release_turn=0) falls inside [0, 52), so the
	# baseline value is still cypress_t0-based and matches y0.
	GameState.turn = 60
	var y1: float = ResearchSystem.base_price_per_token(m)
	assert_almost_eq(y1, y0, y0 * 0.001,
			"cypress_t0 dominates both year 0 and year 1 windows")

func test_baseline_picks_best_inference_gpu_released_in_past_year() -> void:
	# At year 4 start (turn 208), the past-year window [156, 208) contains
	# cypress_t1 (release_turn=152 — just outside, NO) and bamboo_t2 (205, YES).
	# Walk forward to a window that definitively contains a new GPU.
	# Past year window at turn 208 = [156, 208); only bamboo_t2 (205) released
	# in that span (cypress_t1=152 is BEFORE 156). Best inference TFLOPs in
	# window = bamboo_t2 = 90 TFLOPs (v11 bamboo rebalance).
	GameState.turn = 208
	var m: Model = _make_model_with_fpt(_FPT_7B)
	# Expected base price uses bamboo_t2 spec: maintenance=6, grid=24,
	# bamboo_t2.power_factor=0.98 → 电费 = 24 × 0.98 = 23.52,
	# infer_tflops=90, native_cluster_eff=0.88 (v11 bamboo rebalance),
	# purchase_price=7540 摊销 156 周 (CapEx).
	var expected_tfs: float = (6.0 + 24.0 * 0.98 + 7540.0 / 156.0) \
			/ (90.0 * 604_800.0 * 0.88)
	var expected_base: float = expected_tfs * _FPT_7B / 1.0e12
	assert_almost_eq(ResearchSystem.base_price_per_token(m), expected_base,
			expected_base * 0.01)

func test_base_price_clamps_moe_sparsity_at_8x() -> void:
	# 2026-05: 算 cost 时 active_param_ratio 必须 clamp 到 ≥ 0.125 (8×).
	# octopus_sparse (0.05) / super_sparse (0.025) 仍按 0.125 算 base, 不让
	# 玩家研究到 super_sparse 后 base 塌一个数量级. 见 design/平衡参数.md.
	GameState.turn = 0
	# 模拟 super_sparse 模型: 100B 总参数, 2.5% active → fpt = 2 × 100e9 × 0.025
	# = 5e9. 但 cost 应该按 active=0.125 算 → effective fpt = 2 × 100e9 × 0.125
	# = 2.5e10 (5× raw fpt).
	var super_sparse := Model.new()
	super_sparse.id = &"m_super"
	super_sparse.arch = &"octopus_super_sparse"
	super_sparse.status = &"published"
	super_sparse.size_params = 100_000.0  # 100B in M units
	super_sparse.active_param_ratio = 0.025
	super_sparse.flops_per_token = 5.0e9
	super_sparse.is_open_source = false
	GameState.models.append(super_sparse)

	# Dense 等效: 同 size_params 但 active=0.125, fpt = 2 × 100e9 × 0.125 = 2.5e10.
	var dense_floor := Model.new()
	dense_floor.id = &"m_floor"
	dense_floor.arch = &"octopus_v2"  # active=0.125 表中
	dense_floor.status = &"published"
	dense_floor.size_params = 100_000.0
	dense_floor.active_param_ratio = 0.125
	dense_floor.flops_per_token = 2.5e10
	dense_floor.is_open_source = false
	GameState.models.append(dense_floor)

	var p_super: float = ResearchSystem.base_price_per_token(super_sparse)
	var p_floor: float = ResearchSystem.base_price_per_token(dense_floor)
	# Cap 生效 → 两者 base 应当相等 (super_sparse 抬到 0.125 等效).
	assert_almost_eq(p_super, p_floor, p_floor * 0.001,
			"octopus_super_sparse 应被 clamp 到 8× MoE, base 与 active=0.125 等效 (super=%s floor=%s)"
					% [p_super, p_floor])

func test_base_price_does_not_clamp_above_floor() -> void:
	# octopus_v1 (active=0.25) > 0.125 → 不动. base 应低于 octopus_v2 (active=0.125).
	GameState.turn = 0
	var quarter := Model.new()
	quarter.id = &"m_q"
	quarter.arch = &"octopus_v1"
	quarter.status = &"published"
	quarter.size_params = 100_000.0
	quarter.active_param_ratio = 0.25
	quarter.flops_per_token = 2.0 * 100_000.0 * 0.25 * 1.0e6  # = 5e10
	quarter.is_open_source = false
	GameState.models.append(quarter)
	var p_q: float = ResearchSystem.base_price_per_token(quarter)

	var eighth := Model.new()
	eighth.id = &"m_e"
	eighth.arch = &"octopus_v2"
	eighth.status = &"published"
	eighth.size_params = 100_000.0
	eighth.active_param_ratio = 0.125
	eighth.flops_per_token = 2.0 * 100_000.0 * 0.125 * 1.0e6  # = 2.5e10
	eighth.is_open_source = false
	GameState.models.append(eighth)
	var p_e: float = ResearchSystem.base_price_per_token(eighth)
	# active=0.25 比 0.125 多一倍 flops, base 也应该约 2×.
	assert_almost_eq(p_q, p_e * 2.0, p_e * 0.01,
			"active=0.25 base 应为 active=0.125 的 2× (cap 不应该触发)")

func test_baseline_includes_capex_amortization() -> void:
	# 2026-05 CapEx 摊销: weekly_cost 必须包含 purchase_price / 156。
	# cypress_t0 purchase_price=5200 → 摊销项 = 33.33 ¥/周, 占总成本约 63%。
	# 如果有人退回到 maint+power-only 公式, baseline 会塌到 opex/denom,
	# 这个 ratio assertion 直接抓出来。opex = maint 4 + 电费 24×0.66 = 19.84。
	GameState.turn = 0
	var m: Model = _make_model_with_fpt(_FPT_7B)
	var got: float = ResearchSystem.base_price_per_token(m)
	var opex_only: float = 19.84 / (37.5 * 604_800.0 * 0.85) * _FPT_7B / 1.0e12
	# 含 CapEx 后必须显著高于纯 OpEx (≈ 2.4×).
	assert_gt(got, opex_only * 2.0,
			"base_price 必须含 CapEx 摊销, 比纯 OpEx 高 >2×; 实际 %s vs opex %s"
					% [got, opex_only])

func test_baseline_fallback_when_no_gpu_in_past_year() -> void:
	# At year 0 start (turn 0), past-year window = [-52, 0) — empty. Fallback
	# picks the best GPU released by turn 0 (= cypress_t0, the only one).
	GameState.turn = 0
	var m: Model = _make_model_with_fpt(_FPT_7B)
	var expected: float = _EXPECTED_T0_DOLLAR_PER_TFS * _FPT_7B / 1.0e12
	assert_almost_eq(ResearchSystem.base_price_per_token(m), expected,
			expected * 0.001)

# ---- research.preview_pricing (v8 PR-I) --------------------------------
# Per design/研究系统设计.md §4.8: PretrainDialog feeds flops_per_token from
# task.preview into research.preview_pricing → {base_price, guidance_open,
# guidance_closed}. Decouples preview from a stub Model.

func test_preview_pricing_returns_base_and_both_guidances() -> void:
	GameState.turn = 0
	var r: Dictionary = CommandBus.send(&"research.preview_pricing",
			{flops_per_token = _FPT_7B})
	assert_true(r.ok)
	var expected_base: float = _EXPECTED_T0_DOLLAR_PER_TFS * _FPT_7B / 1.0e12
	assert_almost_eq(float(r.base_price), expected_base, expected_base * 0.001)
	assert_almost_eq(float(r.guidance_open), expected_base * 5.0,
			expected_base * 0.001)
	assert_almost_eq(float(r.guidance_closed), expected_base * 100.0,
			expected_base * 0.001)

func test_preview_pricing_zero_fpt_returns_error() -> void:
	var r: Dictionary = CommandBus.send(&"research.preview_pricing",
			{flops_per_token = 0.0})
	assert_false(r.ok)
	assert_eq(r.error, &"invalid_flops")

func test_preview_pricing_negative_fpt_returns_error() -> void:
	var r: Dictionary = CommandBus.send(&"research.preview_pricing",
			{flops_per_token = -1.0e9})
	assert_false(r.ok)
	assert_eq(r.error, &"invalid_flops")

# ---- research.preview_growth_rate (v8 PR-I) ----------------------------
# Used by PriceEditDialog: player types a candidate price, UI calls this to
# show expected weekly demand growth. Same elasticity curve as §4.4, just
# parameterised by (fpt, price, is_open_source) instead of a Model object.

func test_preview_growth_rate_at_guidance_neutral() -> void:
	# Price exactly at guidance → ratio = 1.0 → rate = 0.
	GameState.turn = 0
	var base: float = _EXPECTED_T0_DOLLAR_PER_TFS * _FPT_7B / 1.0e12
	var guidance_closed: float = base * 100.0
	var r: Dictionary = CommandBus.send(&"research.preview_growth_rate", {
		flops_per_token = _FPT_7B,
		per_token_price = guidance_closed,
		is_open_source = false,
	})
	assert_true(r.ok)
	assert_almost_eq(float(r.ratio_to_guidance), 1.0, 0.001)
	assert_almost_eq(float(r.rate), 0.0, 0.001)

func test_preview_growth_rate_below_growth_zone_returns_plus_four_pct() -> void:
	# Price ≤ 0.6 × guidance → rate = +0.02 (v11 ×0.5).
	GameState.turn = 0
	var base: float = _EXPECTED_T0_DOLLAR_PER_TFS * _FPT_7B / 1.0e12
	var r: Dictionary = CommandBus.send(&"research.preview_growth_rate", {
		flops_per_token = _FPT_7B,
		per_token_price = base * 100.0 * 0.5,
		is_open_source = false,
	})
	assert_true(r.ok)
	assert_almost_eq(float(r.rate), 0.02, 0.001)

func test_preview_growth_rate_cliff_at_2_5x() -> void:
	# Price ≥ 2.5 × guidance → cliff (-1.0).
	GameState.turn = 0
	var base: float = _EXPECTED_T0_DOLLAR_PER_TFS * _FPT_7B / 1.0e12
	var r: Dictionary = CommandBus.send(&"research.preview_growth_rate", {
		flops_per_token = _FPT_7B,
		per_token_price = base * 100.0 * 3.0,
		is_open_source = false,
	})
	assert_true(r.ok)
	assert_almost_eq(float(r.rate), -1.0, 0.001)

func test_preview_growth_rate_open_source_uses_os_guidance() -> void:
	# Same price but is_open_source=true → 20× larger ratio (guidance is 5×
	# instead of 100× base) → cliff territory.
	GameState.turn = 0
	var base: float = _EXPECTED_T0_DOLLAR_PER_TFS * _FPT_7B / 1.0e12
	var r_os: Dictionary = CommandBus.send(&"research.preview_growth_rate", {
		flops_per_token = _FPT_7B,
		# 2.51 × OS guidance (=5×) → just over the 2.5 cliff. Was base*12.5 (exactly
		# 2.5×) which floated to 2.4999999 once base price shifted — keep it robustly
		# above the boundary instead of sitting on the float knife-edge.
		per_token_price = base * 12.55,
		is_open_source = true,
	})
	var r_closed: Dictionary = CommandBus.send(&"research.preview_growth_rate", {
		flops_per_token = _FPT_7B,
		per_token_price = base * 12.55,  # 0.1255 × closed guidance (=100×) → +0.02
		is_open_source = false,
	})
	assert_true(r_os.ok and r_closed.ok)
	assert_almost_eq(float(r_os.rate), -1.0, 0.001)
	assert_almost_eq(float(r_closed.rate), 0.02, 0.001)
