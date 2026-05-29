# Art Tools

本目录放图片素材开发期 harness。运行时资源只读取 `assets/sprites/` 下接受后的 PNG, 不依赖本目录的 raw / prompt / meta。

全流程 (写 prompt → 出图 → 后处理 → 读图验收 → 接入) 见 `design/图片素材生成流程.md`; harness 契约见 `design/图片素材管线设计.md`。

依赖装在本目录 venv (gitignore): `python3 -m venv .venv && ./.venv/bin/pip install replicate pillow requests`。

## `generate.py`

调 Replicate 文生图模型按内置批次出 raw 图 (洋红底), 可 `--process` 链式跑 harness。真实模型名只在本脚本里。鉴权: `export REPLICATE_API_TOKEN=...` 或 `tools/art/.env`。

```bash
./.venv/bin/python generate.py --list                          # 看批次与 prompt
./.venv/bin/python generate.py --probe                          # 自检模型真实入参
./.venv/bin/python generate.py --batch infra_buildings --process   # 19 档机房 (含微型星球), 生成+后处理
./.venv/bin/python generate.py --only facility-solo --process       # 单档端到端
./.venv/bin/python generate.py --batch founders --process           # 8 张创始人头像 (portrait_real 风格)
./.venv/bin/python generate.py --batch office_room                   # 办公室房间背景 (scene 风格, 16:9, 不去背)
./.venv/bin/python generate.py --batch office_props                  # 办公室透明精灵 (prop 风格: desk / trophy)
./.venv/bin/python generate.py --batch collectibles --process        # 63 件拍卖收藏 (crypto/卡牌/AI硬件/超跑, icon 风格 + flood_bg)
./.venv/bin/python generate.py --batch collectibles_art --process    # 15 幅名画 (collectible_painting 风格 + flood_bg)
```

拍卖行收藏品 (见 `design/办公室与收藏系统设计.md §8/§9`): 两批合计 78 件, label 形如 `collectible-<id>` (`<id>` 即 `CollectibleSpec.id`)。**逐件**出图, 接受时落 `assets/sprites/ui/collectible/<id>.png` (类目 `collectible`, key=id), 由 `IconRegistry.collectible_icon(id)` 读取。crypto/trading_card/ai_hardware/supercar 走 `icon` 风格; painting 内容含人物/风景 (与 icon 的 no-people/scenery 冲突), 单列 `collectibles_art` 用 `collectible_painting` 风格 (画框名画作为孤立物体)。两批都开 `flood_bg`: flux 常无视 magenta 底画成深蓝/浅灰, 先四角漫水重染再去背 (名画的金框是连通屏障, 漫水不会吃进画心)。trading_card 提示词须强调"矩形卡片本体", 否则 flux 只画卡里的怪物。接入用 `tools/art/copy_collectibles.sh` (runs/ → assets/, 连字符还原下划线)。

营销界面通用 campaign 缩略图用单图 label `marketing-campaign`, 接受后落 `assets/sprites/ui/marketing/campaign.png` (类目 `marketing`, key=`campaign`), 由 `IconRegistry.marketing_icon(&"campaign")` 读取。该图是卡片头像素材, 仍走洋红底 → `process_asset.py single` → 128px 透明 PNG 的 harness 契约。

风格 (`_STYLES`): `icon` 孤立图标 / `portrait[_real]` 头像 / `logo` 标志 / **`scene`** 铺满场景背景 (无 magenta, 宽幅, 配 `aspect`) / **`prop`** 同 icon 但去掉 baked 投影 (投影会在主体与洋红间拉出渐变, 抠不干净)。`scene` 批次**不走 `--process`** (无 chroma-key): 直接缩放 raw → `assets/`。

办公室 (见 `design/办公室与收藏系统设计.md §8.1`): `office-room-bg` 是**第一人称**房间场景 (落地窗+湖+极简, **近处办公桌+电脑+远处茶几烤进画面**), 缩到 1280 宽落 `assets/sprites/ui/office/room-bg.png` (OfficeView 按等比 FIT 居中铺, 锚点贴桌/几面)。`office_props` 批 (prop 风格无投影) 出**逐荣誉**精灵: `office-trophy-<id>` (奖杯, 摆茶几) / `office-medal-<id>` (奖章, 摆桌面), 走 `process_asset.py single --flood-bg --component-mode all` (多部件保全, 暖色离洋红近用偏低 `--flood-bg-tol ~85`、`--threshold ~195` 杀封闭洋红) 去背落 `office/<form>-<id>.png`; `IconRegistry.office_texture()` 读取。

接入: `founders` 批的 label 形如 `founder-avatar-NN`, 接受时落到 `assets/sprites/ui/founder/avatar-NN.png`
(类目 `founder`, key `avatar-NN`), 由 `IconRegistry.founder_avatar()` 读取。见 `design/出身系统设计.md §3`。

公司标志 (`brand-NN`) 与任务图 (`task/<subtype>.png`) 不再走 `generate.py` 的 AI raw 图 + 去背链路;
它们由 `build_deterministic_ui_icons.py` 确定性绘制, 避免新游戏选择网格 / 顶栏 / 任务卡小尺寸下出现线稿残缺。
公司标志落 `assets/sprites/ui/brand/brand-NN.png` (类目 `brand`, key `brand-NN`), 由
`IconRegistry.company_logo_texture()` 读取、`UITheme.draw_company_logo` 叠到浅灰圆角底上绘制。
任务图落 `assets/sprites/ui/task/<subtype>.png`, 由 `IconRegistry.get_icon(&"task", subtype)` 读取。
见 `design/出身系统设计.md §2` 与 `design/图片素材管线设计.md §4.6`。

写实头像 (`portrait_real`) 批开了 `flood_bg`: flux 常无视 prompt 里的 magenta 底,
把背景画成灰 / 浅色, harness 先从四角连通域漫水把它重染成洋红再去背 (见 `process_asset.py --flood-bg`)。

## `build_deterministic_ui_icons.py`

直接绘制 128×128 RGBA 透明 PNG, 用于需要精确、小尺寸可读的功能图标。

```bash
python3 tools/art/build_deterministic_ui_icons.py                 # 重建 brand + task
python3 tools/art/build_deterministic_ui_icons.py --category brand # 只重建公司标志
python3 tools/art/build_deterministic_ui_icons.py --category task  # 只重建任务图
```

输出会覆盖 `assets/sprites/ui/brand/*.png` 与 `assets/sprites/ui/task/*.png`。提交前跑
`tests.unit.tools.test_qa_assets` 的 alpha 填充率检查, 再用 `qa_assets.py contact --category brand|task`
看 checkerboard contact sheet。

## `process_asset.py`

用途:

- `single`: 单张 UI 图标 / 卡片缩略图去背、裁切、居中、写 `pipeline-meta.json`。`--flood-bg` 先从四角连通域漫水把非洋红底重染成洋红再去背 (写实肖像 / 标志这种 flux 爱画灰底的批次用)。
- `sheet`: 固定行列图标包切格、去背、按 label 导出、拼透明预览合图。

示例:

```bash
python3 tools/art/process_asset.py single \
  --input tools/art/runs/model-sparrow/raw.png \
  --output-dir tools/art/runs/model-sparrow \
  --name model-sparrow \
  --size 96 \
  --component-mode largest \
  --reject-edge-touch \
  --prompt-file tools/art/runs/model-sparrow/prompt.txt
```

```bash
python3 tools/art/process_asset.py sheet \
  --input tools/art/runs/product-icons/raw.png \
  --output-dir tools/art/runs/product-icons \
  --rows 2 \
  --cols 2 \
  --labels chatbot,agent,multimodal,coding-agent \
  --size 96 \
  --component-mode largest \
  --reject-edge-touch
```

验收契约见 `design/图片素材管线设计.md`。

## `qa_assets.py`

对已经接入 `assets/sprites/ui/` 的 PNG 做 checkerboard contact sheet, 或用现有
`tools/art/runs/<label>/raw.png` 重新走安全 sampled 去背后覆盖回运行时素材。

```bash
python3 tools/art/qa_assets.py contact --output-dir /tmp/agi-assets-contact
python3 tools/art/qa_assets.py repair --report /tmp/agi-assets-repair-report.json
python3 tools/art/qa_assets.py repair --category founder
```

`repair` 默认跳过 `office/room-bg.png` 这类场景背景, 其余方形 UI 素材统一使用低容差
sampled 去背 (默认不超过 45), 重点避免头像、奖杯、收藏品、浅色气泡 / 纸张被高容差抠出透明缺块。
