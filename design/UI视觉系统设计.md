# UI 视觉系统设计

> **目的**: 锁定主 HUD 的整体布局、视觉风格、可复用组件与迁移路径, 让"卡片化 + 侧栏 Dashboard"改造有统一的契约。
> **读者**: 主 HUD 与各 tab 的实现者; 后续扩展卡片/抽屉/筛选的人。
> **状态**: 🟡 已锁基础四件套 (框架/布局/风格/创建流程), 文档先于实现。
> **与 [UI适配设计.md](UI适配设计.md) 的边界**: 本文档只管 *视觉与交互骨架* (token / 组件 / layout / 迁移), 不重复列举各系统的命令入口; 系统能力暴露由 `UI适配设计.md` 维护。

---

## 1. 设计目标与非目标

### 1.1 目标
- 把当前单场景 `TabContainer + VBox 列表` 升级为 **侧栏 Dashboard + 卡片墙**, 信息密度与可发现性同时提升。
- 主 HUD 仍是 *程序化构建 + 少量 .tscn 子组件*, 不引入第三方 UI 库。
- 所有视觉值收敛到一份 `Theme` 资源 + 一组 token 常量, UI 代码不再散落硬编码颜色/字号。
- 卡片墙原生支持 *筛选 + 搜索 + 排序 + 滚动*, 卡片多到上百也不会失控。
- 创建/编辑流程统一走 *右侧抽屉*, 不再用 Modal 遮挡主区。

### 1.2 非目标
- 不引入第三方 UI 库; 字体策略仍由 `UITheme` autoload 统一管理。
- 不引入像素美术或动画框架; 风格停留在"现代扁平 · 浅色科技感"。
- 不重写已有 Dialog (`PretrainDialog` / `NewDatacenterDialog` 等) 的业务逻辑, 仅做"放到抽屉容器里"的外壳迁移。
- 本轮不做无障碍 (键盘导航 / 高对比模式), 留作后续。

---

## 2. 设计 Token

所有视觉常量 (颜色 / 字号阶 / 圆角 / 间距 / 描边 / 关键尺寸 / z-order) 集中在 `scripts/autoload/ui_theme.gd` 顶端导出, 同时作为 `resources/ui/theme.tres` 的事实源。**具体取值以 `ui_theme.gd` 为准, 本文不重复列表。** 任何 UI 代码引用颜色 / 字号都必须从 `UITheme.XXX` 取值, 不得硬编码。

风格基调: 仿 Google Cloud 控制台布局, 但**品牌走黑灰白单色** —— 浅灰页面底 + 纯白卡片做层级, **炭黑为交互主调 (`ACCENT_INFO`, 现为 `#202124`; 原 Google 蓝已全站去除)**。绿 / 橙 / 红只保留给少量强语义文本 (例如顶栏正负现金、明确危险提示), **不进入侧栏数字和卡片默认样式**; 榜单保留金 / 银 / 铜; 不用阴影, 仅靠表面色差 + 1px 边框分层, 保持扁平科技感。

**中文字体策略 (2026-05)**: UI 默认字体不直接固定到内置 Noto。真实窗口运行时由 `UITheme` 按平台加载系统中文 UI 字体文件:
- macOS 优先 `/System/Library/Fonts/PingFang.ttc`, 失败后回落 `Hiragino Sans GB.ttc` / `STHeiti`;
- Windows 优先 `C:/Windows/Fonts/msyh.ttc` / `msyhbd.ttc`, 失败后回落 `Deng*.ttf` / `simhei.ttf`;
- Linux / 其它平台暂不读宿主字体, 固定使用内置 Noto。

不使用 Godot `SystemFont`: 实测它在 Godot 4.4/macOS 与 headless 场景里仍可能解析到空字体路径并刷 `FreeType: Error loading font: ''`。直接用 `FontFile.load_dynamic_font()` 读存在的系统字体文件更可控。若所有系统字体文件都不存在或加载失败, 立即回落 `assets/fonts/cjk.ttf` / `cjk-bold.ttf`。`assets/fonts/cjk*.ttf` 仍必须随包分发, 是跨平台保证而不是首选观感。headless / GUT 测试环境固定直接用内置 Noto, 避免测试结果受宿主系统字体影响。

**字号双档制**: 上面的字号阶 (`FS_XS`…`FS_XXL`) 是**信息密集型控制台**的正文档, 放在满屏单屏 (起始页 / 出错页等) 上会偏小。为此 `ui_theme.gd` 另设一组**全屏 / hero 字号档** (`FS_HERO` 主标题 / `FS_HERO_SUB` 副标题与主按钮), 专给"单屏一个焦点"的场景, 不与控制台正文混用。

**起始页是唯一的展示型例外**: 它不是控制台, 而是一张品牌欢迎页 (hero), 允许用柔和投影做卡片悬浮 + 大面积留白 + 低透明度品牌色块背景, 以求"专业 + 吸引人"; 但调色板仍只取 `UITheme` token, 不自创颜色。布局细节见 `出身系统设计.md §1`。

量纲格式化 helper (`UITheme.format_compute` / `format_tps` / `format_tokens`): 算力与 token 吞吐 / 计数显示统一走这几个 helper, **按量级自动升档** (TFLOPs↔PFLOPs↔EFLOPs、k↔M↔G↔T), 避免大数据中心显示成读不动的天文数字。具体阈值阶梯以 `ui_theme.gd` 为准。

---

## 3. Theme 资源与 UITheme 改造

- 新增 `resources/ui/theme.tres`: 装 StyleBoxFlat (BG_BASE / BG_SURFACE / BG_ELEVATED + 圆角 + 边框)、字号阶、控件颜色映射。
- `scripts/autoload/ui_theme.gd` 增加: token 常量 (颜色/字号/尺寸); `install()` 时先加载 `theme.tres`, 把字体注入进去再设为 `ThemeDB.default_theme`; 提供 `make_stylebox(kind: StringName)` / `color(token: StringName)` 帮助函数。
- 现有的 `apply_font_to_theme` 保留, 但作为 *最小回退* — 缺失 `theme.tres` 时仍能跑测试。

---

## 4. 整体布局

```
┌──────────────────────────────────────────────────────────────┐
│  TopBar (48px)                                                │
│  [logo] [指标 chip ×6]                       [推进][存档][读]  │
├──────────┬───────────────────────────────────────────────────┤
│ Sidebar  │  PageHeader                                        │
│ (220px)  │  ┌─ 标题 ──── FilterBar ─── + 新建 ─┐              │
│  ▾ 运营  │  └────────────────────────────────────┘             │
│   概览   │  ScrollContainer                                   │
│   经济   │  ┌─ HFlowContainer ──────────────────────────┐    │
│   招聘   │  │ Card  Card  Card  Card  Card  Card        │    │
│   任务   │  │ Card  Card  Card  Card  Card              │    │
│   事件   │  └────────────────────────────────────────────┘    │
│  ▾ 研发  │                                                    │
│   模型   │                                                    │
│   基建   │                                                    │
│   数据   │                                                    │
│   科技   │                                                    │
│  ▾ 市场  │                                                    │
│   产品   │                                                    │
│   营销   │                                              ┌─ Drawer (360px, 浮于主区右侧)
│   市场   │                                              │ 标题  ×
│   营收   │                                              │ 表单…
└──────────┴──────────────────────────────────────────────┴────┘
```

- **顶栏**和**侧栏**绝对定位、不滚动; 主区与抽屉占剩余空间。
- 主区根节点是 `ScrollContainer`, 内含 `VBoxContainer` (PageHeader + 卡片墙)。
- 抽屉打开时**不遮挡**侧栏与顶栏, 仅压缩主区宽度 (主区 `margin_right = DRAWER_W` 动画过渡)。

---

## 5. 顶栏指标

顶栏做成**深色烟熏玻璃条** (smoked-glass bar) + 指标仪表簇 —— 暗底、纵向玻璃光泽、竖线分隔、浅色读数, 是全站唯一的深色 chrome (工作区仍是浅灰), 给顶栏一点重量和科技感:
- **真实 frosted glass**: 顶栏是**浮层** (`PRESET_TOP_WIDE` 锚到顶部、最后 add_child 画在最上层), 内容区 (侧栏 / 主区 / 抽屉) 背景铺到 `y=0` 且**在顶栏背后**; 可见内容靠各区 top inset (`= TOP_BAR_H`) 落到顶栏下方 —— 主区每个 tab 的 ScrollContainer 在 `col` 之上垫一个 `TOP_BAR_H` 高的占位 (放在 `_clear()` 不会清的 outer 里), 往下滚时内容从顶栏背后划过。玻璃由 `_make_top_bar_glass()` 的 canvas shader 实现: 采样 `hint_screen_texture` 做小半径模糊 (texel 步长用 `1.0/textureSize`, **不是** `SCREEN_PIXEL_SIZE` —— canvas_item 无此内建), 再叠半透明深色 tint (`tint_alpha≈0.58`, 顶亮底暗) + 顶部柔光高光 + 底部微暗。玻璃层必须是 `ColorRect` 且 `PRESET_FULL_RECT` 铺满顶栏, 在内容 HBox 之前添加, `mouse_filter=IGNORE`, 避免出现只有 stylebox 深色底、没有真正玻璃采样的假效果。panel stylebox 仍给 `TOPBAR_GLASS_BASE` 实底 + 底部 1px `TOPBAR_GLASS_BORDER` 作兜底/测试契约。
- 顶栏为深色, 故内部文字 / 竖线 / ghost 按钮一律走 `*_ON_DARK` / `TOPBAR_GLASS_*` 档 (浅色), 不用工作区那套深灰 token。
- 左侧品牌区: 28×28 品牌 monogram + 公司名 (bold, 宽度稳定避免刷新挤动)。monogram 是统一的「Ascent A」品牌标记 —— **黑灰白单色**: 白色山峰双腿 (上升, `BG_SURFACE`) + 灰色横杠 (增长 / 数据曲线, `BORDER_STRONG`) 叠在炭黑圆角方块 (`TEXT_PRIMARY`) 上, 与 app 图标 (`icon.svg`)、起始页 hero 标记同源。字标「Scaling Up」同样走黑灰白 (Scaling 炭黑 / Up 取灰)。几何与配色的事实源是 `UITheme.draw_brand_mark()`, 三处 (顶栏 / 起始页 / 图标) 共用, 不各自硬编码。macOS 发布包必须同时带原生 `icon.icns` 并在本机 `export_presets.cfg` 的 `application/icon` 指向它, 避免只靠 SVG 自动转换时 Finder / Dock 偶发显示为空图标。**全站去蓝**: `ACCENT_INFO` 已由 Google 蓝改为炭黑 `#202124`、`ACCENT_INFO_SUBTLE` 改为浅灰 `#e8eaed`, 所有交互态 (主按钮 / 焦点 / 输入 / 链接 / 选中 / 训练中) 随 token 自动变单色; 深色主按钮的 hover/pressed 改用 `lightened()` 派生 (darken 在近黑上不可见)。

### 5.1 玩家可选公司标志 (LOGO_MARKS)

新游戏时玩家可为公司选一个**程序化预设标记**, 顶栏 monogram 据 `GameState.company_logo` 绘制 (默认 `&""` = 上面的「Ascent A」, 即不选时与旧档行为一致)。

- 事实源 `UITheme.LOGO_MARKS`: 一个有序数组, 每项 `{id, shape, color}`。`shape` ∈ 程序化形状集 (`circle / square / diamond / triangle / hexagon / sparkle`), `color` 取一组在炭黑底上够亮的强调色 (`UITheme.LOGO_PALETTE`)。**不引入位图 logo 文件**, 全部 `UITheme.draw_company_logo()` 画出来。
- `draw_company_logo(ci, rect, logo_id, draw_background=true)`: `logo_id` 为 `&""` 或未知时回退到 `draw_brand_mark()` (经典 A); 否则在炭黑圆角方块上居中画该形状 (取强调色)。顶栏标记、新游戏标志网格共用本函数, 不各自硬编码几何。
- 颜色仅是玩家**个人品牌**的选择, 不改变全站「黑灰白」基调 (基调指 app 自身 UI; 公司 logo 允许彩色)。
- 指标用 `StatChip`, 顶栏走它的 **flat 变体** (`set_flat(true)`): 去掉每块的边框/底色/圆角, 改用块间 **1px 渐变细刻线** (中段 `TOPBAR_GLASS_DIVIDER` 亮玻璃白、上下淡入透明、纵向铺满, 像玻璃上的刻度线) 分隔成仪表簇; value 字号提到 `FS_MD` (15) 粗体当主读数 (深色玻璃上走 `TEXT_ON_DARK`), label 仍 `FS_XS` (11) 浅灰 (`TEXT_ON_DARK_SECONDARY`)。flat 变体即"顶栏深色玻璃上下文", 文字自动走 on-dark 档。**默认 `StatChip` 仍是白底描边的独立卡** (营收 tab 复用, 深灰文字), flat 只是顶栏 opt-in, 不改默认契约。一排 5 项: 回合 (周 + 年)、现金、周净流、付费用户、算力 (旧"已发布模型数"chip 已移除)。具体 chip 集合与值来源以 `main.gd` 的顶栏装配为准。**默认 `StatChip` 仍是白底描边的独立卡** (营收 tab 复用), flat 只是顶栏 opt-in, 不改默认契约。一排 5 项: 回合 (周 + 年)、现金、周净流、付费用户、算力 (旧"已发布模型数"chip 已移除)。具体 chip 集合与值来源以 `main.gd` 的顶栏装配为准。
- **金额防溢出**: 顶栏现金 / 周净流 / 付费用户走 `UITheme.format_money_compact()` —— `< 100 万`保持千分位精确 (`-272,360`), `≥ 100 万`缩成 `1.2M / 3.4B / 5.6T`, 配合 flat chip 不裁字 (value 不 clip, size-to-content), 大额营收不再被截断成省略号。其它页面 (经济明细 / 贷款 / 结算) 仍用精确 `_format_money`, 不缩写。
- 状态语义 (深色玻璃上用 on-dark 档): 现金为负 value 用 `ACCENT_DANGER_ON_DARK`; 周净流正 / 负分别用 `ACCENT_PRIMARY_ON_DARK` / `ACCENT_DANGER_ON_DARK`, 无数据显示 `—`。周净流读真实 `GameState.weekly_ledger` 净流 (当前账本已滚入历史并清空时改读 `ledger_history[0]` 快照), 不能退化成相邻两次 UI 刷新的 cash delta。
- 右侧操作区 (深色玻璃语境): 主操作"推进回合"**反白实心按钮** —— `BG_SURFACE` 白底 + `TEXT_PRIMARY` 炭黑字, 在暗底上最跳, 当主 CTA (`TOPBAR_ADVANCE` 文案自带 `→`); hover/pressed 在白底上 `darkened()` 派生。次要操作"设置 / 存档"为**幽灵按钮** (透明无边框, `TEXT_ON_DARK_SECONDARY` 浅字, hover 才上一层白色低透底 = 玻璃压感), 主次分明; pending 事件导致推进禁用时主按钮回到玻璃灰态。
- 「推进回合」是事件流的唯一强节奏入口: 若玩家点击后本周 `action` 相位产生 pending 事件, HUD 应在推进同步结束后自动选中侧栏 `events` 并显示事件页, 不要求玩家先注意到侧栏 badge 再手动跳转。若处理函数被调用时已经存在 pending 事件, 不推进, 直接选中事件页作为门禁反馈。

---

## 6. 侧栏分组与导航项

侧栏是主 HUD 的「工作台侧轨」: 白色 surface rail + 右侧 1px 分隔线, 在浅灰工作区上形成稳定的导航锚点。导航项不再只是文字列表, 而是**紧凑胶囊行 + 独立 icon tile**; icon 是每个系统的第一视觉识别, 必须比文字更稳、更清楚。

18 个入口按业务语义分 4 组, 每组可折叠:

```
▾ 运营  (6)
  · 概览   overview
  · 经济   economy
  · 招聘   hiring
  · 员工   staff
  · 任务   tasks
  · 事件   events

▾ 研发  (4)
  · 模型   models             ← 即 ResearchSystem, HUD 名"模型"
  · 基建   infra
  · 数据   dataset
  · 科技   tech

▾ 市场  (4)
  · 产品   product
  · 营销   marketing
  · 市场   market_rank        ← 排行榜
  · 营收   monetization

▾ 其他  (4)
  · 办公室 office
  · 拍卖行 auction
  · 慈善   charity
  · 帮助   help
```

- 侧栏顶部由浮层 TopBar 承载公司标志; 侧栏内容从 `TOP_BAR_H + S_3` 开始, 让背景延伸到顶栏背后供玻璃采样。
- 每个 `SidebarItem`: 固定高度 `SIDEBAR_ITEM_H`; 左侧 3px active rail; 中间 `SIDEBAR_ICON_TILE` 正方形 icon tile; 右侧 label + 未读/进行中徽章 (e.g. 任务进行中数、未读事件数)。
- icon 渲染必须走 `assets/fonts/icons.ttf` 的 Material Icons 字体码点, 字号固定为 `SIDEBAR_ICON_GLYPH_SIZE`。缺字体时可退回普通字形, 但布局仍保持 tile 尺寸。
- 默认态: icon tile 为白底 + 浅边框, glyph / label 走 `TEXT_SECONDARY`, 行背景透明。
- hover 态: 行背景升到 `BG_SURFACE`, icon tile 升到 `BG_ELEVATED`, 保持无阴影。
- 选中态: 左侧 3px `ACCENT_INFO` rail 常驻占位 (未选中透明, 不造成布局跳动) + 行背景 `ACCENT_INFO_SUBTLE`; icon tile 反白为 `ACCENT_INFO` 底 + `BG_SURFACE` glyph; label 用 bold + `TEXT_PRIMARY`。
- 任务 / 事件等数字徽章一律用单色: `TEXT_PRIMARY` 炭黑底 + `BG_SURFACE` 白字, 不使用 warning 黄 / 橙色, 避免侧栏局部跳色。
- 侧栏折叠 (`SIDEBAR_W_COLLAPSED=56`) 时只显示 icon, label 走 tooltip。

---

## 7. 可复用组件清单

每个组件放在 `scenes/ui/components/<name>/`, 配 `.tscn` + `.gd`, 在 `tests/unit/ui_components/` 给一个最小实例化冒烟。

| 组件 | 路径 | 职责 |
|---|---|---|
| `Avatar` | `components/avatar/` | 头像 / 缩略图槽: 有 texture 就贴图, 无 texture 时回退到 *seed 哈希配色 + 文字 / glyph*; 让 lead / model / datacenter 卡片在真实立绘到位前先有占位 |
| `Card` | `components/card/` | 通用卡片骨架: header (avatar + title + status badge) / body (字段网格) / footer (动作按钮一排) |
| `StatChip` | `components/stat_chip/` | 顶栏指标: icon + label + value + 可选 delta |
| `Badge` | `components/badge/` | 状态徽章, 10 种语义色档 (按 kind 取色), 覆盖 `pretrained/posttrained/evaluated/published/training/idle` 等模型与任务状态 |
| `SectionHeader` | `components/section_header/` | 主区标题: title + 计数 + 操作按钮 (e.g. "+ 新建模型") |
| `FilterBar` | `components/filter_bar/` | 状态 pills (多选) + 搜索框 + 排序下拉, 见 §8 |
| `IconButton` | `components/icon_button/` | 32×32 / 28×28 图标按钮 |
| `SidebarItem` | `components/sidebar_item/` | 侧栏导航项 (icon + label + 徽章) |
| `SidebarGroup` | `components/sidebar_group/` | 侧栏分组标题 + 折叠箭头 |
| `Drawer` | `components/drawer/` | 右抽屉容器: 标题 + 关闭按钮 + 内容插槽 + 底部按钮条 |
| `EmptyState` | `components/empty_state/` | 空状态: icon + 文案 + CTA |

每个组件**只暴露纯数据 setter** (e.g. `Card.set_data({title, subtitle, status, fields, actions})`), 不持有业务系统引用, 业务系统通过 `EventBus` 信号驱动外层 ViewModel 重新组装数据。

`SectionHeader.action_pressed` 必须延迟到下一帧发出。它经常用来打开 Dialog / Drawer 或触发主区重建, 如果在 Button 的 `pressed` 输入回调内同步改动节点树, Viewport 可能在 `_push_unhandled_input_internal` 阶段遇到已经离树的节点并报错。

`Card.action_pressed` 也必须延迟到下一帧发出。Card footer 的按钮常用于选择事件选项、发布模型、删除资产等会触发 `EventBus` 刷新的动作; 若在 `BaseButton.pressed` 回调栈内同步发出业务信号, 主 HUD 可能立即 `_refresh()` 并重建当前卡片, 导致导出包在按钮输入处理尚未结束时访问已释放/半释放的 UI 节点。组件测试必须钉住: 点击 action 后同帧不 emit, 下一帧才 emit。

**i18n 约定** (详见 [国际化设计.md](国际化设计.md)): 组件本身不调 `tr()`, 字符串由调用方传入已翻译值; 调用方应当在组装数据时用 `tr("KEY")` 取译文。`Avatar.fallback_text` 也属于"调用方传入", glyph 与 seed_id 不参与翻译。

### 7.1 按钮手感与常用变体

全站按钮统一收敛到两层:
- **默认 Theme**: `resources/ui/theme.tres` 给 `Button / OptionButton / MenuButton` 设明确的 normal / hover / pressed / focus / disabled 状态。pressed 状态必须比 hover 更深, 并通过同总内边距的 top/bottom 偏移做 1px 下压感; disabled 保持可读但低权重。
- **按钮文字对比**: 所有浅色 / 反白按钮状态都必须显式设置 `font_color / font_hover_color / font_pressed_color / font_hover_pressed_color / font_focus_color / font_disabled_color`。白底或近白底上的按钮文字必须保持 `TEXT_PRIMARY` 或 `TEXT_DISABLED`, 不得掉回 Godot 默认白字。
- **常用变体 helper**: `UITheme.apply_button_variant(button, variant)` 提供 `secondary` (默认描边)、`primary` (主操作实心炭黑)、`ghost` (透明辅助)、`danger` (破坏性红)、`success` (正向绿)、`toolbar` (紧凑工具按钮)。新 UI 不应手写一组 StyleBox, 先用变体 helper; 特殊场景如深色玻璃顶栏可局部 override。
- **新建类 CTA**: 所有创建新资产 / 新任务的入口 (例如「训练新模型」「新建数据中心」「创建产品」「开始采集」「新建活动」) 统一使用 `create` 变体, 比普通 `primary` 更醒目: 高度不低于 40px、bold 字重、实心炭黑底、左右留白更大, 但仍保持内容宽 (`SIZE_SHRINK_BEGIN` 或标题栏右侧自然宽度), 不横向铺满整屏。该变体只用于“产生新东西”的入口, 卡片 footer 的日常操作继续用 Card 自己的主次规则。
- **Toggle / CheckBox**: `CheckButton` 和 `CheckBox` 不依赖 Godot 默认深色主题图标; theme 必须提供 checked / unchecked / disabled 图标。开启态要有可见深色轨道或深色勾选框, 关闭态要有可见边框, 让玩家在设置面板里能看清点击区域。
- **触感反馈**: `SfxPlayer` 自动注册进入场景树的 `BaseButton`, 设置手型光标, `button_down/button_up` 做极轻微缩放回弹, `pressed` 播放短点击音。音频细节见 [音频系统设计.md](音频系统设计.md)。

### 7.2 训练类 Dialog 视觉契约

预训练 / 后训练是高风险、高成本操作, Dialog 不能再呈现成裸 Label 长表单。训练类 Dialog 统一采用**配置 / 预览双面板**结构:

- 外层为 `HBoxContainer`, 左侧配置、右侧预览, 两侧各自使用 `PanelContainer + ScrollContainer`; 宽屏下始终能一边调参一边看结果。
- 面板用 `BG_SURFACE` 白底、`BORDER_SUBTLE` 1px 描边、`R_MD/R_LG` 圆角、`S_4` 内边距。面板标题用 bold `TEXT_PRIMARY`, 辅助说明用 `TEXT_SECONDARY`。
- 预览区不能是一串裸文本, 必须按语义分组: 概览 / 资源与时长 / 训练修正 / 能力预估 / 警告。每组用浅灰 `BG_BASE` 子面板承载, 重要数字使用 `ACCENT_INFO` 或 `ACCENT_PRIMARY`, 风险使用 `ACCENT_DANGER`。
- 后训练 Dialog 与预训练保持同构: 左侧展示基础模型、机房、数据集、Lead; 右侧展示时长、GPU 门槛、数据集输入、增益、净分与完成后能力。
- 底部启动按钮使用 `create` 变体, 取消按钮使用 `secondary`; 业务校验、预览计算、CommandBus payload 不因视觉改造改变。

### 7.3 设置 Dialog 视觉契约

设置弹窗属于高频入口, 但不是业务表单; 它应当像一个小型偏好面板, 而不是裸控件纵向堆叠:

- 弹窗最小尺寸约 `680×480`, 内容区可滚动, 低分辨率下不挤压控件。
- 内容按 `显示 / 音频 / 系统` 三个分区面板组织; 每块面板有标题行、浅灰描边、`R_MD` 圆角与 `S_4` 内边距。
- 语言按钮使用分段控件排布; 音量滑块所在行必须横向铺开, 不缩成很短的控件。
- 返回主菜单仍在系统分区底部, 只在 `allow_return_to_menu=true` 时显示, 与确认弹窗流程保持不变。

### 7.4 存档 Dialog 视觉契约

存档 / 读档弹窗是玩家安全感入口, 必须清楚、稳定、可扫读:

- 弹窗最小尺寸约 `880×640`, 内容区使用 `ScrollContainer`, 低分辨率下不挤压 slot 卡片。
- 顶部「手动存档」与中部「存档列表」各自用 `PanelContainer` 承载, 白底、浅边、`R_MD` 圆角、`S_4` 内边距。
- slot 行必须是卡片行: 左侧 slot 信息与标签, 右侧动作用按钮组; `autosave` 使用浅灰底和自动标签, 删除按钮隐藏。
- 空存档目录必须显示空状态面板, 而不是一块空白列表。
- 底部状态反馈放在浅灰状态条里, 成功用次级文字, 失败用危险色; 业务命令仍全部走 `Save` / `EventBus.save_loaded`。

### 7.5 新游戏 Dialog 视觉契约

`NewGameDialog` 是开局第一段身份建立, 要比普通表单更有仪式感, 但仍保持模拟经营工具的清晰度:

- 弹窗内容使用浅色 shell 面板承载, 内部三栏各自是 `PanelContainer` 分区, 不使用裸分隔线拼接。
- 区段标题统一 bold + `FS_LG`; 出身卡标题 bold, 说明 / 优劣势正文不小于 `FS_BASE`, 避免中文在高 DPI / 小窗口下发灰发糊。
- 头像瓦片使用画廊式尺寸, Logo 瓦片使用紧凑网格; 两者选中态都必须有 2px 深色描边, 不能只靠浅色背景表示。
- 预览卡是右栏视觉锚点: 大头像 + 大 Logo + 公司名 / 创始人 / 出身, 字体层级必须明显, 公司名使用 bold + `FS_XL`。
- 所有输入框、按钮、卡片边距取 `UITheme` token; 1280×720 最小窗口下不横向滚动、不裁掉主要文字。

---

## 8. FilterBar 与卡片墙交互规范

### 8.1 FilterBar 结构

```
┌─ FilterBar ─────────────────────────────────────────────────┐
│ [全部] [训练中] [已评估] [已发布]   🔍 搜索化名…   排序 ▾   │
└──────────────────────────────────────────────────────────────┘
```

- **状态 pills**: 多选, 第一个"全部"互斥其余; pill 选中态用 `ACCENT_PRIMARY` 背景。pill 集合由各 tab 注入。pill 文案可带计数 `(N)`, tab 在 refresh 时调 `update_pill_counts` 刷新而不重置选中。基建 tab 注入**三条**筛选条 (均带计数, 不需要搜索框时 tab 调 `set_search_visible(false)` 收起), 逐条**取交集 (AND)**: ① ownership `全部 / 租用 / 自建`; ② 卡数量 `全部 / ≤72 卡 / ≤8k 卡 / >8k 卡`; ③ 运行状态 `全部 / 空闲 / 训练中 / 推理中` (按 `Datacenter.status` 三态)。
- **基建 DcCard 信息**: 卡片副标题为 `机房档位 · 租用/自建`; 字段区列出 GPU 型号×卡数、供电方式、容量、训练/推理算力、周成本、在跑目标 — 避免把过长信息塞进副标题被省略号截断。
- **基建自建队列信息**: 「自建中」区段使用紧凑在建卡片, 不使用纯文本行。每项包含建筑缩略图、`自建中` 徽章、机房档位、供电、可选预装 GPU、剩余/总周数与进度条; 卡片宽度与普通资产卡对齐, 但高度更紧凑, 让玩家一眼看到工程进度与将上线的规模。
- **搜索框**: 实时筛选 (本地, 不走命令总线); 占位文本随上下文变 (模型 tab: "搜索化名"; 招聘 tab: "搜索 lead 姓名/专长")。
- **排序下拉**: 选项与 pill 一样由 tab 注入。默认排序: 模型 tab 按 `created_turn` 倒序, 招聘按 ability 倒序, 基建按 dc id。

### 8.2 卡片墙

- 主区根: `ScrollContainer`, 垂直滚动。滚动条样式见 Theme StyleBox (细 6px, 仅 hover 时显形)。
- 卡片容器: `HFlowContainer`, 每张卡片 `CARD_MIN_W × CARD_MIN_H`, 容器宽度变化时自动折行。
- 卡片数 == 0 时, 替换为 `EmptyState` (e.g. "还没有模型 · 立即训练第一个模型 →")。
- 卡片排序/筛选变化时**只重排子节点顺序与可见性**, 不销毁重建 (节省 GC)。

### 8.3 卡片骨架 (Card)

卡片三段式: top accent rail / header (avatar + title + status badge) / body (字段 key-value 行, 可含进度条) / footer (动作按钮一排, ≤4 显示按钮其余进 ⋯ 菜单)。主操作按钮直接铺在卡片底部。具体装配见 `components/card/`。

**经营游戏信息卡风格 (2026-05)**: Card 不是裸白盒, 要像一个可扫读的实体资产:
- 顶部 4px 细色带作为资产锚点, **默认固定为炭黑单色 `ACCENT_INFO`**, 不再按 status kind 染成绿 / 黄 / 红; 色带贴边但跟随卡片圆角。
- Card 内 status badge 默认压成 `neutral` 单色灰阶, 让卡片墙保持黑白灰基调。若少数业务界面确实需要彩色语义, 应由调用方显式传专门组件或显式按钮 kind, 不作为 Card 默认。
- Header 与字段区之间不用重 HSeparator 切割; 字段区改为浅灰 `BG_BASE` 圆角信息面, 每行 `label/value` 在同一个面内排列, 靠灰度和字重建立层级。
- Footer 与正文之间保留轻分隔, 第一颗非破坏性 action 默认提为 primary; `delete/fire/terminate/cancel/unpublish` 等破坏性或撤销类 action 默认降为 secondary 单色描边, 避免卡片墙出现大面积红色。调用方显式传 `kind` 时优先尊重调用方。
- 卡片 `mouse_default_cursor_shape` 使用手型, hover 后边框加深到 `BORDER_STRONG`, 但不加阴影, 保持全站扁平控制台气质。

**紧凑缩略图 (2026-05)**: header 头像槽用 `CARD_AVATAR_SIZE = 112`px, 保留建筑/立绘的视觉锚点, 但把横向空间还给标题、副标题与状态信息。标题列与状态徽章顶对齐贴在图片右侧。无图卡片仍走 Avatar 的 seed 配色 + glyph 回退, glyph 字号按头像尺寸缩放。

**主次层级 + 收紧 (2026-05)**: 卡片信息要有主次, 靠**字重 + 灰度**拉开 (不靠加大字号):
- **标题**用 bold 字重 (`get_ui_font_bold()`), `TEXT_PRIMARY`; **副标题**常规字重 + `TEXT_SECONDARY` (灰)。
- 字段行 `label : value` — **label** 用 `TEXT_SECONDARY` 灰色弱化, **value** 用 bold + `TEXT_PRIMARY` 强调 (值是玩家真正要读的数)。
- 收紧留白: `CARD_MIN_W` 下调到 `336`, `CARD_MIN_H` 下调到 `196`; 卡片面板统一白底 + 1px 浅边 + 8px 圆角 + 12px 内边距, 取消大面积空白, 一屏多放。
- 文字完整性: 标题 / 副标题最多显示 3 行, 字段 value 最多显示 3 行且左对齐智能换行; 宁可卡片按内容略微长高, 不把业务名、数据集覆盖范围、部署目标这类关键文字硬截成省略号。

**文本型界面基线 (2026-05)**: 概览 / 经济 / 纯说明段落仍可保留列表形态, 但不得是裸 Label 堆叠。`main.gd` 的低层文本 helper 默认开启 `AUTOWRAP_WORD_SMART`, 正文走 `FS_BASE + TEXT_PRIMARY`, 次级提示走 `FS_SM + TEXT_SECONDARY`, section 标题走 bold + `FS_LG`; 这样融资、账本、下一步提示等"一堆文本"在窄窗口也能自然换行, 不靠裁字。

**概览 / 经济只读看板样式 (2026-05)**: 这两个旧 tab 仍可由 `main.gd` 程序化构建, 但第一屏必须像仪表盘而不是纯文本:
- 概览顶部用 3 块 KPI 卡展示回合 / 现金 / 付费用户, 下一步建议用带浅色边框的提示面板逐条展示, 资产清单用两列表格化字段块展示。
- 经济顶部用 KPI 卡展示现金 / 负债 / 股权 / 破产压力; “上周收支明细”使用两张有表头的小表格 (收入 / 支出), “最近 12 周财务表”使用 5 列表格。
- 表格金额列右对齐、行高稳定、表头使用次级文字和底色, 小计/净流使用粗体与正负语义色。表格容器宽度收口到内容, 不横向铺满整屏。

**概览响应式修复 (2026-06)**: overview 是玩家打开存档后的默认页, 必须优先保证 1280×720 正式窗口下数字与中文字段完整可读。
- 顶部 KPI 不再使用单行固定宽 `HBoxContainer`; 改用可折行的横向流式容器, 每个 chip 有稳定最小宽, 空间不足时换到下一行而不是裁切现金 / 用户数。
- “下一步”和“资产清单”面板宽度跟随可用空间, 只设置最大视觉宽度, 不用超过可用主区宽度的强制最小宽。
- 资产清单不再用 112/540 这类固定两列硬宽表格; 每个资产分组作为独立字段块, 单块最小宽度约 300px 以上, value label 左对齐智能换行, 禁止省略号裁字。字段块可以按行宽折行, 在窄窗口下垂直增长。

---

## 9. 响应式断点

| 断点 | 行为 |
|---|---|
| `≥ 1400px` | 侧栏展开 220px, 抽屉打开时主区压缩, 卡片每行 4+ |
| `1100–1399px` | 侧栏展开 220px, 抽屉打开时主区压缩, 卡片每行 3 |
| `< 1100px` | 暂不作为正式支持窗口; 可以显示调试画面, 但不保证信息密度与点击目标 |

默认窗口 `1920×1080` (project.godot `viewport_width/height`); 最小正式支持窗口 `1280×720` (`min_width/min_height`)。UI 修复优先保证 1280 下信息可读、操作目标靠近对应对象、主流程不用横向滚动; 更小窗口作为后续响应式专项处理。**2026-06 macOS 导出修复**: ProjectSettings 关闭 Godot 自动 stretch (`display/window/stretch/mode="disabled"`), 不再让全屏时按基准画布自动缩放裁切菜单; 大屏 / 全屏只由 `UITheme.apply_display_scale()` 的 `Window.content_scale_factor` 控制字号与控件缩放。

**列表 / 行宽收口 + 按钮对齐 (2026-05)**: tab 内容挂在 `ScrollContainer → VBox(EXPAND_FILL)` 上, 默认会把竖排列表行、看板行、动作按钮全拉成整屏宽 —— 列表内容铺太宽、行内 label 与右侧按钮被推到屏幕两端、按钮宽到一整屏。规则:
- 竖排列表型视图 (排行榜、经济看板行) 宽度收口到 `LIST_MAX_W`(720) 并左对齐, 不随窗口铺满。
- 行内「信息 + 操作按钮」(如员工 +1/-1) 信息列**不再 `EXPAND_FILL`**, 按钮紧跟信息其后, 不被推到行尾。
- 直接挂在 `VBox` 里的动作按钮 (Button 默认 `SIZE_FILL`) 要设 `SHRINK_BEGIN`, 否则一个按钮占满整屏宽。

### 9bis. 高 DPI 缩放 (2K / 4K 字号自适应)

设计基准是 1080p。由于 project stretch 已关闭, 大屏 / 高 DPI 缩放只走运行时 `Window.content_scale_factor`。它按显示器高度驱动整体 UI 等比放大, 但不启用 Godot 的画布 stretch, 避免 macOS 导出全屏时菜单按虚拟画布缩放后显示不全。

- **自动档**: `UITheme.compute_ui_scale(window_h)` = `clampf(window_h / 1080, 1.0, MAX_UI_SCALE)`。即 1080p→1.0、1440p→≈1.33、2160p→2.0; 低于 1080 不缩小 (clamp 下限 1.0), 超大屏封顶 `MAX_UI_SCALE`(2.5)。纯函数, 单测覆盖。
- **手动档**: `Preferences.ui_scale` (float, `0.0`=自动) 让玩家在设置里覆盖自动值, 选 `100% / 125% / 150% / 175% / 200%`。`UITheme.effective_ui_scale()` = `ui_scale>0 ? ui_scale : compute_ui_scale(window_h)`。
- **应用**: `UITheme.apply_display_scale()` 写 `get_window().content_scale_factor`; 启动时与 `window.size_changed` (含全屏切换) 时各应用一次, 自动档随分辨率变。Project stretch 保持 disabled, 不和 `content_scale_factor` 叠加。
- **全屏**: `Preferences.fullscreen` (bool) 经 `UITheme.apply_window_mode()` → `DisplayServer.window_set_mode(WINDOW_MODE_FULLSCREEN / WINDOWED)` (borderless 全屏)。设置里一个 `CheckButton` 切换 + 持久化。
- **测试 hermetic**: 缩放 / 窗口模式只在非测试运行下真正应用 (镜像 `Preferences._is_test_run`), 避免动 headless 测试窗口; `compute_ui_scale` 是纯函数照常测。

---

## 10. 迁移路径

按以下顺序推进, 每步独立 commit, 每步对应单测/集成测试:

1. **设计文档** (本文档) — 已完成。
2. **Theme + UITheme 扩展** — 新增 `resources/ui/theme.tres`, `ui_theme.gd` 加 token 常量与 helper; 单测: 启动后 `ThemeDB.default_theme.get_color(...)` 能取到主色。
3. **组件 scaffold** — 按 §7 清单依次写 `.tscn` + `.gd`; 每个组件给一个 `tests/unit/ui_components/<name>_test.gd` 验证 set_data 不崩、信号正确发出。
4. **新主场景骨架** — 改 `scenes/main/main.tscn` 为 顶栏 / 侧栏 / 主区 ScrollContainer / 抽屉容器 四块; `main.gd` 拆出 `TopBarController` / `SidebarController` / `MainPanelController` / `DrawerController`。旧 TabContainer 暂时挂在主区作 fallback。
5. **试点迁移: 模型 tab** —
   - 写 `scenes/ui/views/model_view/` (含 `model_view.tscn` + `model_view.gd` + `model_card.tscn`)
   - FilterBar pills: `pretrained / posttrained / evaluated / published`
   - 搜索: 按 codename 子串匹配
   - 排序: `created_turn ↓ / ability ↓ / size_tier ↑`
   - 创建入口: 把现有 `PretrainDialog` 内容塞进 `Drawer` 槽 (业务逻辑不动, 仅换容器)
   - 验收: 集成测试覆盖"渲染 N 卡片 → 切 filter → 滚到底 → 点评估 → 抽屉关 → 列表刷新"。
6. **扩展到其余 tab** — 招聘 / 基建 / 数据 / 科技 / 产品 / 任务 / 事件 / 营销, 每个 tab 独立 commit + 集成测试; `经济 / 营收 / 市场 / 概览` 主要是只读看板, 卡片化优先级低, 留到最后或保留列表形态。
7. **清理旧 TabContainer 与硬编码** — 全部 tab 迁完后删 `main.gd` 中的 `_tab_*` 字段, 同步更新 `UI适配设计.md` 各 tab 描述。
   - **2026-05 进度 (partial)**: 10/13 tab 已迁卡片化 view (模型/招聘/基建/产品/数据/任务/事件/科技/营销/竞争对手, 见 `scenes/ui/views/`), 3 个未迁 (概览/经济/营收); `_tab_*` 字段保留承载未迁 tab + 已迁 view 的挂载点。
     - **竞争对手 → `leaderboard_view`**: 荣耀榜单 (强化行 + 前 3 名金/银/铜奖章 + 玩家行高亮「你」徽章), 见 `design/竞争对手系统设计.md §8`。新增荣誉色 token `RANK_GOLD / RANK_SILVER / RANK_BRONZE` (取值见 `ui_theme.gd`)。
   - **已做的硬编码清理**: `_nav_id_to_tab_title` 字符串查找 → `_nav_to_tab_index: Dictionary` 一次性 build, 见 `main.gd::_populate_nav_to_tab_index()`。
   - **剩余 3 tab 是否卡片化**: 见 §12 未决问题; 主要是只读看板, 优先级低。

每一步都遵守 `CLAUDE.md` TDD: 改设计 → 改测试 → 改实现 → 单测过 → 集成测过 → commit。

---

## 10bis. 组件实现踩坑 (2026-05 视觉验收回顾)

多个 tab 试点迁完, 跑 `tools/screenshot.sh <nav>` 视觉验收时发现的共性坑, 写在这避免后人重蹈:

### 10bis.1 组件应当继承"对的 Container", 不是 `Control` + 内层 `PRESET_FULL_RECT`

`Control` 不会从子节点冒泡 `get_combined_minimum_size`, 在父 Container (`HBoxContainer` / `VBoxContainer` / `HFlowContainer`) 里会被压成 0×min_size, 内容看似存在但宽度为零, 文字渲染重叠或不可见。

**正确做法**: 组件直接继承能容纳布局的 Container:

| 组件 | 继承 |
|---|---|
| `StatChip` | `HBoxContainer` (一行: label / value / delta) |
| `SectionHeader` | `HBoxContainer` |
| `SidebarItem` | `PanelContainer` (利用 StyleBox 切换 active 态, `_gui_input` 接点击) |
| `Badge` | `PanelContainer` |
| `Card` | `PanelContainer` (保持 `SIZE_SHRINK_BEGIN`, 不要 `SIZE_FILL` 否则在 HFlow 里被横向拉成宽条) |
| `Avatar` | `Control` 可保留 — 它有显式 `custom_minimum_size` |

### 10bis.2 `set_data` / `set_title` 在 `_ready` 之前调用时必须 lazy

典型 bug: `_build_sidebar` 里 build sub-tree 然后挂进主区, 但 SidebarGroup 还没进 tree 时调 `set_title`/`add_item` — 内部 Label / `_items_container` 是 null, 调用静默失效, 文案 / 子项都丢。

**正确做法**: 组件内置 `_pending_*` 缓冲变量, `_ready` 时一次性 apply。已在以下组件实现:
- `SectionHeader._pending_data`
- `SidebarItem._pending_data`
- `SidebarGroup._pending_title` + `_pending_items`

新组件遵守同样规范。

### 10bis.3 view 内部不要嵌 `ScrollContainer`

外层 `main.gd::_make_tab` 已经给每个 tab 包了 `ScrollContainer`。view 内部再嵌一层会让内层 scroll 高度被压成 0, 卡片墙看不到。

**正确做法**: view 直接放 `HFlowContainer` (或其它内容), 让外层 scroll 接管滚动。

### 10bis.4 1080p 视觉清理基线

2026-05 截图验收先以 `1920×1080` 为唯一正式修复目标。`1280×720` 仍保留最小窗口设置, 但本轮不为它调整信息密度。

本轮 1080p 截图暴露的 UI 问题统一按以下规则修:
- 卡片标题允许最多两行换行, 不把较长资源名强行压成单行省略号; 字段值允许在必要时换行, 避免按钮 / 数值 / 标签互相挤压。
- 玩家界面不得直接显示内部 id / 枚举, 包括 `model_0001`、`open_source`、`purchased`、`template_id`、`serving_target_id`、`util` 等; 调用方必须传 display label, 组件只渲染已整理好的字符串。
- 数据集来源、模态、标签使用玩家可读中文: 开源 / 商业 / 自采、文本 / 图像 / 代码等; coverage tags 也映射为中文标签。
- 科技树锁定状态使用文字标记, 不依赖 emoji 字体; 单个科技树在 1080p 下尽量压缩横向跨度, 横向滚动只作为大树兜底。
- 产品、基建、事件页的状态 / 目标 / 历史记录必须优先显示业务名称, 只在资源丢失时才回退到内部 id。

### 10bis.5 Dialog / Popup 状态必须显式落在浅色主题上

Godot 默认 `Window` / `AcceptDialog` / `PopupMenu` 的部分状态来自内置深色主题, 不能只覆盖普通 `panel`。浅色主题下必须同时满足:
- Dialog 标题栏区域由 `embedded_border` / `embedded_unfocused_border` 绘制不透明白底, `title_height` 留足标题与关闭按钮空间, 避免顶部透出背后的主界面。**注意 (Godot 4.3)**: 嵌入窗口的 `embedded_border` 只画在「内容矩形」内, 标题栏在其上方且默认无填充, 仅靠 `content_margin_top` **不能**盖住标题栏 → 浅色主题下顶部仍透明。必须给该 stylebox 设 `expand_margin_top` (≈ `title_height`), 把白底向上延伸覆盖整条标题栏。
- `OptionButton` / `MenuButton` 必须显式设置 `font_hover_pressed_color` 与 `font_focus_color`, 点击展开后鼠标仍停在控件上时文字不能退回默认白色。
- `PopupMenu` 的 hover / selected 字色与背景必须成对定义, 背景使用浅灰 (`ACCENT_INFO_SUBTLE` / `BG_ELEVATED`), 字色保持 `TEXT_PRIMARY`, 避免列表项 hover 后文字消失。

---

## 11. 验收标准

- `UITheme` 暴露所有 token 常量, UI 代码不再出现 magic color/font size。
- 启动 `main.tscn` 看到: 顶栏 5 chip + 3 按钮; 左侧栏四组 18 项, icon tile 与选中反白态清晰; 主区显示当前选中 tab 的 `EmptyState` 或卡片墙。
- 模型 tab 渲染玩家所有自训模型卡片, 支持 §8 的全部 filter / search / sort 行为。
- "+ 新建模型"打开右抽屉, 抽屉内的训练表单与旧 `PretrainDialog` 行为一致, 提交后抽屉关、卡片墙刷新。
- 卡片数 ≥ 24 时仍能流畅滚动 (单帧 < 16ms, 用 Godot profiler 验证)。
- 窗口尺寸缩到 900×700 时侧栏自动折叠、卡片自动改 2 列、抽屉仍可用。
- 单测全部通过; 集成测试覆盖模型 tab 试点全链路。
- **截图视觉验收**: `tools/screenshot.sh <nav>` 跑过每个迁过的 tab, 输出图与 [docs/端到端调试.md §2.2 验收清单](../docs/端到端调试.md) 描述一致。每次重大组件改动后回归一次。

---

## 12. 未决问题 / TODO

- 「研究 vs 模型」侧栏命名: 当前 ResearchSystem 的 HUD tab 名是「模型」, 18 项里没有独立"研究"项。若后续要把"科技研究中的任务"做独立视图, 需要在「研发」组追加一项, 届时回来更新 §6。
- 顶栏"算力"指标的具体口径 (汇总 `serving_tokens_per_sec` 还是 `total_tflops`?), 取决于玩家心智模型, 等试点期再敲死。
- 侧栏徽章数据源: 任务进行中数、未读事件数, 需要确认是否已经在 GameState 中可直接读到, 或要在 EventBus 加聚合信号。
- 主区 ScrollContainer 与抽屉的动画 (slide 入 / fade 入) 暂用 `Tween`, 是否引入统一 motion token (duration / easing) 留到组件 scaffold 时决定。
- 公共开源模型在基建 tab Serving 入口的卡片样式 (与玩家自训模型卡共用 `Card` 还是单独派生), 留到基建 tab 迁移阶段决定。
- 4 个未卡片化 tab (概览/经济/营收/市场): 当前结论 (2026-05) 是**保留只读列表形态, 不强求卡片化**。主要是它们 (a) 没有玩家可操作的实体集合, (b) 卡片化 ROI 低。
