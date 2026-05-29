extends GutTest

## NewDatacenterDialog 建筑预览图 — 自建模式选档位显示该建筑图, 云模式隐藏。
## 见 design/图片素材生成流程.md §8。Headless: 直接驱动模式切换 + 读私有字段
## (镜像 new_campaign_dialog_test 模式)。

const NewDatacenterDialog := preload("res://scenes/ui/new_datacenter_dialog/new_datacenter_dialog.gd")

var _dlg

func before_each() -> void:
	GameState.reset()
	GameState.cash = 1_000_000_000_000   # 解锁全部档位, 避免 disabled 项干扰 select(0)
	_dlg = NewDatacenterDialog.new()
	add_child_autofree(_dlg)
	_dlg.refresh()

func after_each() -> void:
	_dlg = null

func test_dialog_builds_preview_node() -> void:
	assert_not_null(_dlg._facility_preview, "应有建筑预览 TextureRect")
	assert_not_null(_dlg._facility_preview_row, "应有预览行容器")

func test_build_mode_shows_facility_preview() -> void:
	_dlg._mode_build.button_pressed = true
	_dlg._on_mode_changed()
	await get_tree().process_frame
	assert_true(_dlg._facility_preview_row.visible, "自建模式应显示预览行")
	assert_not_null(_dlg._facility_preview.texture, "选中档位应有建筑预览图")
	assert_true(_dlg._facility_preview.texture is Texture2D, "预览应是 Texture2D")

func test_cloud_mode_hides_facility_preview() -> void:
	_dlg._mode_cloud.button_pressed = true
	_dlg._on_mode_changed()
	await get_tree().process_frame
	assert_false(_dlg._facility_preview_row.visible, "云模式应隐藏建筑预览行")
