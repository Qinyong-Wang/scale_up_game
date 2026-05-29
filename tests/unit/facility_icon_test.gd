extends GutTest

## FacilitySpec 建筑图标接入 — 全部档位都配了存在的建筑图 + load_icon 两条路径。
## 见 design/图片素材生成流程.md §8。

func test_all_facilities_have_existing_icon() -> void:
	for spec_id in InfraSystem.FACILITY_SPECS.keys():
		var path: String = String(InfraSystem.FACILITY_SPECS[spec_id])
		var spec := load(path) as FacilitySpec
		assert_not_null(spec, "facility %s 应能 load" % spec_id)
		if spec == null:
			continue
		assert_false(spec.icon_path.is_empty(), "facility %s 应配 icon_path" % spec_id)
		assert_true(ResourceLoader.exists(spec.icon_path),
			"facility %s 的 icon 资源应存在: %s" % [spec_id, spec.icon_path])
		assert_true(spec.load_icon() is Texture2D,
			"facility %s load_icon() 应返回 Texture2D" % spec_id)

func test_load_icon_null_when_unset() -> void:
	var spec := FacilitySpec.new()
	assert_null(spec.load_icon(), "未配 icon_path 时 load_icon() 应为 null")

func test_load_icon_null_when_file_missing() -> void:
	var spec := FacilitySpec.new()
	spec.icon_path = "res://assets/sprites/ui/infra/__does_not_exist__.png"
	assert_null(spec.load_icon(), "文件缺失时 load_icon() 应为 null (走回退, 不报错)")
