extends GutTest

## 顶栏「算力」必须 = 算力池每行 t/s 之和。
## 见 design/营收系统设计.md §3.1。
##
## 历史 bug: 顶栏直接 Σ dc.serving_tokens_per_sec, 池子走
## MonetizationSystem.compute_capacity_for_model (含 arch.inference_coef +
## chief_engineer lead 加成)。arch_coef != 1 或者有 chief_engineer 时, 顶栏
## 比池子小 10%-50%, 玩家盯着两个数字直觉就觉得"对不上"。

const Main := preload("res://scenes/main/main.gd")

const SECONDS_PER_WEEK: int = 604_800

var _hud

func before_each() -> void:
	GameState.reset()
	_hud = Main.new()
	add_child_autofree(_hud)
	await get_tree().process_frame

func _make_published_model(id: StringName, arch: StringName) -> Model:
	var m := Model.new()
	m.id = id
	m.display_name = String(id)
	m.arch = arch
	m.capability = {&"general": 60.0}
	m.status = &"published"
	m.is_open_source = false
	m.per_token_price = 0.0001
	m.flops_per_token = 1.4e10
	GameState.models.append(m)
	return m

func _make_serving_dc(id: StringName, model_id: StringName, tps: float) -> Datacenter:
	var dc := Datacenter.new()
	dc.id = id
	dc.facility_spec_id = &"facility_solo"
	dc.status = &"serving"
	dc.deployed_model_id = model_id
	dc.serving_target_kind = &"owned_model"
	dc.serving_target_id = model_id
	dc.serving_tokens_per_sec = tps
	GameState.datacenters.append(dc)
	return dc

func _make_subscription_product(id: StringName, model_id: StringName, subs: int = 1) -> Product:
	var p := Product.new()
	p.id = id
	p.display_name = String(id)
	p.type = &"chatbot"
	p.subscribers = subs
	p.subscription_price = 99
	p.bound_model_id = model_id
	GameState.products.append(p)
	return p

# 把顶栏文字里的 t/s 数字抠出来 (e.g. "1.1k t/s" → 1100.0; "100 t/s" → 100.0).
# format_tps 用 k/M/G 升档, 这里反推。
func _parse_tps_from_text(text: String) -> float:
	var t := text.strip_edges()
	# 截到 " t/s" 之前
	var idx := t.find("t/s")
	if idx < 0:
		return -1.0
	var num_part := t.substr(0, idx).strip_edges()
	var mult: float = 1.0
	if num_part.ends_with("k"):
		mult = 1_000.0
		num_part = num_part.substr(0, num_part.length() - 1)
	elif num_part.ends_with("M"):
		mult = 1_000_000.0
		num_part = num_part.substr(0, num_part.length() - 1)
	elif num_part.ends_with("G"):
		mult = 1_000_000_000.0
		num_part = num_part.substr(0, num_part.length() - 1)
	return num_part.to_float() * mult

func test_top_bar_compute_equals_sum_of_pool_rows_with_default_arch() -> void:
	# ant_v1 arch_coef=1.0, 无 chief_engineer lead → 顶栏 = 原始 = 实效。
	var m := _make_published_model(&"m_default", &"ant_v1")
	_make_serving_dc(&"dc_1", m.id, 100.0)
	_make_serving_dc(&"dc_2", m.id, 200.0)
	_make_subscription_product(&"p_1", m.id)

	_hud._refresh()
	var chip_text: String = _hud._chip_compute.get_value_label().text
	var top_tps: float = _parse_tps_from_text(chip_text)
	var data: Dictionary = _hud._build_product_view_data()
	var pool_sum: float = 0.0
	for row in data.get("pool_rows", []):
		pool_sum += float(int(row["capacity"])) / float(SECONDS_PER_WEEK)
	assert_almost_eq(top_tps, pool_sum, 0.5,
			"顶栏 %.1f t/s 应 = 算力池之和 %.1f t/s" % [top_tps, pool_sum])

func test_top_bar_includes_arch_inference_coef_bonus() -> void:
	# ant_v2 arch_coef=1.1, 顶栏应也乘进去, 与池子对齐。
	var m := _make_published_model(&"m_v2", &"ant_v2")
	_make_serving_dc(&"dc_v2", m.id, 100.0)
	_make_subscription_product(&"p_v2", m.id)

	_hud._refresh()
	var chip_text: String = _hud._chip_compute.get_value_label().text
	var top_tps: float = _parse_tps_from_text(chip_text)
	var data: Dictionary = _hud._build_product_view_data()
	var pool_sum: float = 0.0
	for row in data.get("pool_rows", []):
		pool_sum += float(int(row["capacity"])) / float(SECONDS_PER_WEEK)
	assert_almost_eq(top_tps, pool_sum, 0.5,
			"顶栏 %.1f 应 = 池子 %.1f (arch_coef 1.1 应都进顶栏)" % [top_tps, pool_sum])
	# Sanity: 实效 > 原始 100 t/s。
	assert_gt(top_tps, 100.0, "ant_v2 arch_coef=1.1, 100 t/s 原始应升到 ~110 t/s 实效")

func test_top_bar_includes_unattached_dc_raw_tps() -> void:
	# 一个 dc 没绑任何 published 模型 (e.g. 下载的 OS), 顶栏应仍计入它的原始 t/s。
	var dc := Datacenter.new()
	dc.id = &"dc_os"
	dc.facility_spec_id = &"facility_solo"
	dc.status = &"serving"
	dc.deployed_model_id = &"some_os_release"   # 不在 GameState.models
	dc.serving_tokens_per_sec = 500.0
	GameState.datacenters.append(dc)

	_hud._refresh()
	var chip_text: String = _hud._chip_compute.get_value_label().text
	var top_tps: float = _parse_tps_from_text(chip_text)
	assert_almost_eq(top_tps, 500.0, 1.0,
			"未识别 deployed 的 dc 顶栏应按原始 t/s 计 (实际 %.1f)" % top_tps)
