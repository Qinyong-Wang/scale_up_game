extends GutTest

## Tests for the Chinchilla data_efficiency multiplier inside
## TaskSystem._compute_capability_measured. Per design/任务系统设计.md §6.7.1
## and 平衡参数.md §evaluate产出.
##
## Formula:
##   optimal_tokens_B = 0.02 × size_params_M
##   ratio = Σ dataset.size / optimal_tokens_B
##   data_efficiency = ratio^0.28        if ratio ≤ 1   (undertrain)
##                    1 + 0.05 × log10(ratio)  if ratio > 1  (overtrain)
##   clamp(data_efficiency, 0, 1.10)


const SIZE_M_800: float = 800.0          # 800M params, optimal = 16 B tokens
const OPTIMAL_800M_B: float = 16.0
const BASE_800M: float = 30.83           # SIZE_TO_CAP_CURVE(800)

func before_each() -> void:
	GameState.reset()

func _make_dataset(id: StringName, size_b: float,
		quality: float = 0.5) -> Dataset:
	var ds := Dataset.new()
	ds.id = id
	ds.kind = &"pretrain"
	# v9 (2026-05): quality=0.5 yields data_quality_factor = clamp(0.5 + 0.5)
	# = 1.0, isolating the Chinchilla data-efficiency factor. (Old v2 used
	# source=&"collected" → ×1.0; that path is now dead since source no longer
	# feeds the formula.)
	ds.source = &"collected"
	ds.size = size_b
	ds.quality = quality
	GameState.datasets.append(ds)
	return ds

func _make_model(size_m: float, dataset_ids: Array) -> Model:
	var m := Model.new()
	m.id = &"m_data_eff"
	m.arch = &"ant_v1"
	m.size_params = size_m
	var typed: Array[StringName] = []
	for d in dataset_ids:
		typed.append(StringName(d))
	m.dataset_ids = typed
	m.input_modalities = [&"text"]
	m.status = &"pretrained"
	GameState.models.append(m)
	return m

func _general(m: Model) -> float:
	return float(TaskSystem._compute_capability_measured(m, null).get(&"general", -1.0))

# ---- core curve ---------------------------------------------------------

func test_optimal_tokens_yields_efficiency_one() -> void:
	# 800M model + 16 B tokens (optimal) → data_efficiency = 1.0 → general == base.
	var ds := _make_dataset(&"ds_opt", OPTIMAL_800M_B)
	var m := _make_model(SIZE_M_800, [ds.id])
	assert_almost_eq(_general(m), BASE_800M, 0.5,
		"at optimal tokens the score should equal the size-curve base")

func test_undertrain_quarter_optimal_drops_to_chinchilla_exponent() -> void:
	# 800M + 4 B tokens (1/4 optimal). efficiency = 0.25 ^ 0.28 = 0.687.
	var ds := _make_dataset(&"ds_under", OPTIMAL_800M_B / 4.0)
	var m := _make_model(SIZE_M_800, [ds.id])
	var expected: float = BASE_800M * pow(0.25, 0.28)
	assert_almost_eq(_general(m), expected, 0.5,
		"undertrain by 4× should follow ratio^0.28")

func test_undertrain_sixteenth_optimal_severely_penalised() -> void:
	# 800M + 1 B tokens (1/16 optimal). efficiency = 0.0625 ^ 0.28 = 0.473.
	var ds := _make_dataset(&"ds_very_under", OPTIMAL_800M_B / 16.0)
	var m := _make_model(SIZE_M_800, [ds.id])
	var expected: float = BASE_800M * pow(0.0625, 0.28)
	assert_almost_eq(_general(m), expected, 0.5,
		"undertrain by 16× should follow ratio^0.28 ≈ 0.47")

func test_overtrain_yields_small_bonus_capped_at_ten_percent() -> void:
	# 800M + 100 B tokens (≈ 6.25× optimal). efficiency = 1 + 0.05 × log10(6.25) ≈ 1.040.
	var ds := _make_dataset(&"ds_over", 100.0)
	var m := _make_model(SIZE_M_800, [ds.id])
	var expected: float = BASE_800M * (1.0 + 0.05 * (log(6.25) / log(10.0)))
	assert_almost_eq(_general(m), expected, 0.5,
		"overtrain by 6.25× should give ~+4% bonus")

func test_overtrain_extreme_clamps_at_efficiency_cap() -> void:
	# 1 000 000 × optimal → uncapped = 1 + 0.05 × 6 = 1.30, clamp to 1.10.
	var ds := _make_dataset(&"ds_flood", OPTIMAL_800M_B * 1_000_000.0)
	var m := _make_model(SIZE_M_800, [ds.id])
	# Score must not exceed BASE × 1.10 (other multipliers all 1.0 in this scenario).
	var capped: float = BASE_800M * 1.10
	var got: float = _general(m)
	assert_true(got <= capped + 0.5,
		"extreme overtrain must clamp at +10%% (got %.2f, cap %.2f)" % [got, capped])

# ---- multi-dataset sum --------------------------------------------------

func test_multiple_datasets_sum_their_tokens() -> void:
	# Three datasets at 4 B each = 12 B total = 0.75 × optimal for 800M.
	# efficiency = 0.75 ^ 0.28 ≈ 0.923. expected = 30.83 × 0.923 = 28.46.
	var sizes: Array = [4.0, 4.0, 4.0]
	var ids: Array = []
	for i in range(sizes.size()):
		var ds := _make_dataset(StringName("ds_%d" % i), sizes[i])
		ids.append(ds.id)
	var m := _make_model(SIZE_M_800, ids)
	var expected: float = BASE_800M * pow(12.0 / OPTIMAL_800M_B, 0.28)
	assert_almost_eq(_general(m), expected, 0.5)

# ---- monotonicity sanity ------------------------------------------------

func test_more_data_never_decreases_capability_within_relevant_range() -> void:
	# Walk tokens from 1 B → 100 B for an 800M model. Capability should be
	# non-decreasing (overtrain bonus is small but positive until cap).
	var prev: float = -1.0
	for tokens in [1.0, 4.0, 8.0, 16.0, 32.0, 64.0, 100.0]:
		GameState.reset()
		var ds := _make_dataset(&"ds_t", float(tokens))
		var m := _make_model(SIZE_M_800, [ds.id])
		var got: float = _general(m)
		assert_true(got >= prev - 0.001,
			"capability dropped from %.3f (prev) to %.3f at %s B tokens" % [prev, got, tokens])
		prev = got
