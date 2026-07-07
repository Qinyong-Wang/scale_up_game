# 字体说明

## UI 字体策略

游戏真实窗口运行时由 `UITheme` 按平台加载系统中文 UI 字体文件作为首选字体:

- macOS: `/System/Library/Fonts/PingFang.ttc` → `Hiragino Sans GB.ttc` → `STHeiti`
- Windows: `C:/Windows/Fonts/msyh.ttc` / `msyhbd.ttc` → `Deng*.ttf` → `simhei.ttf`
- Linux / 其它: 暂不读宿主字体, 固定使用内置 Noto

首选系统字体用于改善中文观感, 但不作为跨平台唯一依赖。若系统字体文件不存在或
`FontFile.load_dynamic_font()` 加载失败, 立即回落下面的 Noto Sans CJK SC 资源。
因此 Windows / macOS 导出包即使匹配不到系统字体路径, 也仍能显示完整中文。
headless / GUT 测试环境固定直接使用内置 Noto, 避免测试受宿主系统字体影响。

## `cjk.ttf` / `cjk-bold.ttf` — Noto Sans CJK SC fallback

- `cjk.ttf` — Noto Sans CJK SC **Regular**, 正文 / 默认字体。
- `cjk-bold.ttf` — Noto Sans CJK SC **Bold**, 标题 / 区段头 / 顶栏公司名 /
  弹窗标题 fallback (`UITheme.get_ui_font_bold()`)。

Noto Sans CJK 是 Google 的开源字体, 风格干净现代, 覆盖中英文与常用符号,
与 GCP 控制台风格的 UI 一致, 可自由分发。

来源: https://github.com/notofonts/noto-cjk → `Sans/OTF/SimplifiedChinese/`

## 许可

SIL Open Font License 1.1 — 自由使用 / 嵌入 / 分发；仓库级登记见
`THIRD_PARTY_NOTICES.md`。

## 导入参数

两个 `.import` 均 `allow_system_fallback=false`。原因: headless / GUT 环境下
Godot 4.3 查系统 fallback 可能得到空字体路径, 控制台会大量刷
`FreeType: Error loading font: ''`。中英文与常用符号应由 Noto 本身覆盖;
如缺字, 优先换更完整的 Noto Sans CJK 包, 不要重新打开 system fallback。

## 为什么仍然保留内置字体

Godot 的 `SystemFont` 会按字体名查找宿主系统字体, 但字体名匹配不是强保证,
且在部分 Godot 4.4/macOS/headless 场景会解析到空字体路径并刷 FreeType 红字。
所以本项目不用 `SystemFont`, 而是直接检查并加载已知系统字体文件。真正的覆盖保证
始终来自随包分发的 `cjk.ttf` / `cjk-bold.ttf`。
