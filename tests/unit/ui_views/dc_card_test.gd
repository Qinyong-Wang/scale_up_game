extends GutTest

## DcCard avatar fallback (bug: 云租用数据中心卡片无 facility 图标时, 回退显示
## 机房名首字母, 看着像人物头像而非数据中心)。
## 期望: 缺图时 fallback_text 为空 → Avatar 用 datacenter glyph "▣"。

const DcCard := preload("res://scenes/ui/views/infra_view/dc_card.gd")

func _make_dc(ownership: StringName, facility: StringName) -> Datacenter:
	var dc := Datacenter.new()
	dc.id = &"dc_test"
	dc.display_name = "我的云算力"
	dc.ownership = ownership
	dc.facility_spec_id = facility
	return dc

func test_cloud_dc_without_icon_uses_glyph_fallback() -> void:
	var dc := _make_dc(&"cloud", &"")
	var data: Dictionary = DcCard._build(dc, "", "GPU", "电网")
	assert_eq(data["avatar"]["fallback_text"], "",
		"缺图时 fallback_text 应为空, 让 Avatar 走 datacenter glyph 而非名字首字母")
	assert_eq(StringName(data["avatar"]["kind"]), &"datacenter")

func test_facility_dc_with_icon_keeps_texture() -> void:
	var dc := _make_dc(&"owned", &"facility_pod")
	var tex := PlaceholderTexture2D.new()
	var data: Dictionary = DcCard._build(dc, "8 卡机柜", "GPU", "电网", "", tex)
	assert_eq(data["avatar"]["texture"], tex, "有图标时应贴图")

func test_cloud_facility_icon_asset_exists() -> void:
	# 云租用 DC 用的专属图标必须存在且能加载 (main._facility_icon_path 引用它)。
	const PATH := "res://assets/sprites/ui/infra/facility-cloud.png"
	assert_true(ResourceLoader.exists(PATH), "云算力图标缺失: %s" % PATH)
	assert_true(load(PATH) is Texture2D, "云算力图标应为 Texture2D")
