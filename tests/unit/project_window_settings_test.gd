extends GutTest

## Project window settings — default window size + formal minimum.
##
## Per design/UI视觉系统设计.md §9: 默认窗口 1920×1080, 最小正式支持
## 窗口 1280×720。stretch/mode=canvas_items 保证缩放时文字清晰。

func test_default_window_size_is_1080p() -> void:
	assert_eq(int(ProjectSettings.get_setting("display/window/size/viewport_width")), 1920)
	assert_eq(int(ProjectSettings.get_setting("display/window/size/viewport_height")), 1080)

func test_window_minimum_size_matches_formal_support_target() -> void:
	assert_eq(int(ProjectSettings.get_setting("display/window/size/min_width", 0)), 1280)
	assert_eq(int(ProjectSettings.get_setting("display/window/size/min_height", 0)), 720)

func test_stretch_mode_keeps_text_crisp_on_resize() -> void:
	assert_eq(String(ProjectSettings.get_setting("display/window/stretch/mode", "")),
			"canvas_items")
