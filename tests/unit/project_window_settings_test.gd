extends GutTest

## Project window settings — default window size + formal minimum.
##
## Per design/UI视觉系统设计.md §9: 默认窗口 1920×1080, 最小正式支持
## 窗口 1280×720。macOS 导出全屏下关闭 Godot 自动 stretch, 缩放交给 UITheme
## 的 content_scale_factor, 避免菜单被虚拟画布裁切。

func test_default_window_size_is_1080p() -> void:
	assert_eq(int(ProjectSettings.get_setting("display/window/size/viewport_width")), 1920)
	assert_eq(int(ProjectSettings.get_setting("display/window/size/viewport_height")), 1080)

func test_window_minimum_size_matches_formal_support_target() -> void:
	assert_eq(int(ProjectSettings.get_setting("display/window/size/min_width", 0)), 1280)
	assert_eq(int(ProjectSettings.get_setting("display/window/size/min_height", 0)), 720)

func test_stretch_mode_is_disabled_to_avoid_fullscreen_menu_clipping() -> void:
	assert_eq(String(ProjectSettings.get_setting("display/window/stretch/mode", "")),
			"disabled")
