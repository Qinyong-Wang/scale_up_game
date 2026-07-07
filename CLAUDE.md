# Scaling Up

一款以「经营 AI 模型公司」为题材的 2D 模拟经营游戏，每周一回合，使用 **Godot 4.4** 开发。

## 语言约定

- `CLAUDE.md` 与 `design/` 下所有设计文档**一律使用中文**，节省上下文。
- 代码、提交信息、Godot 自带文件保持英文。

## 目录结构

> 详细说明以代码与各 `design/*.md`、`index.md` 为准；此处只列目录职责。

```
project.godot          Godot 工程入口
README.md              GitHub 项目介绍与快速开始
LICENSE                GNU GPL v3.0 许可证文本
THIRD_PARTY_NOTICES.md 第三方组件与素材说明
CLAUDE_en.md           CLAUDE.md 的英文参考翻译
icon.svg               应用图标
icon.icns              macOS 原生应用图标（export_presets.cfg 的 application/icon）
icon.ico               Windows 原生应用图标（export_presets.cfg 的 application/icon）
scenes/                按功能划分（不按资源类型）
  start_screen/        起始页 StartScreen (工程 main_scene)
  main/                根场景 Main
  ui/                  HUD、面板、弹窗
    *_dialog/          各类对话框: pretrain / new_game / new_datacenter /
                        dataset_collection / new_campaign / research / save_load /
                        settings / collectibles (办公室电脑打开的收藏柜) /
                        honor (点击办公室奖章/奖杯打开的荣誉信息框) /
                        tutorial (新游戏开局的多页分步新手引导, 帮助 view 顶部可复用)
    views/             各 tab 视图: model / hiring / staff / infra / product /
                        revenue / dataset / tasks / event / tech / leaderboard / charity / office /
                        help (右侧导航的帮助: 系统说明 master-detail)
    components/        UI 视觉组件 (见 design/UI视觉系统设计.md §7): avatar / badge /
                        stat_chip / section_header / filter_bar / card / icon_button /
                        empty_state / sidebar_item / sidebar_group / drawer / capacity_pie /
                        share_bar (横向占比条)
  office/              公司办公场景
scripts/
  autoload/            全局单例: GameState / EventBus / TurnManager / CommandBus /
                        Log / UITheme / Preferences / MusicPlayer / SfxPlayer
  systems/             业务系统: economy / hiring / infra / dataset / research /
                        tech_tree / task / market / user / product / monetization /
                        marketing / event / founder / charity / collection /
                        simulation / name_romanizer / person_name / icon_registry
  resources/           自定义 Resource 类型脚本 (model / lead / datacenter / gpu_spec /
                        dataset / product / campaign / event_card / tech_node /
                        task_template / *_tuning 等)
resources/             静态数据 .tres
  data/
    tasks/             任务模板
    infra/             facilities 机房档位 / gpus GPU 型号 / power 供电方式
    hiring/            lead 等级 / 员工月薪 / lead 加成 / pool_config
    economy/           tuning / funding_rounds 融资轮
    market/            竞争对手 tuning
    user/              用户系统 tuning
    marketing/         营销系统 tuning
    founders/          出身数值表 (scientist/entrepreneur/influencer)
    datasets/          数据集模板 (开源 / 商业)
    products/types/    产品类型模板
    tech/              科技树节点: arch / attention / loss / engineering / application / context
    codenames/         化名词库 (animals.txt / plants.txt)
	    events/            事件卡牌 (含一次性黑色幽默事件)
    charity/           公益方向 (causes: bio_science / fundamental_compute / social_welfare)
    collectibles/      收藏品 (AI训练卡/炎兽闪卡/创世币/超跑/名画, 增值曲线+2070上限)
    trophies/          荣誉桌奖杯 spec (展示框架)
    simulation/        宇宙模拟阶梯 (气象/海洋/地球/太阳系/宇宙, 慈善三期 capstone)
    npcs/              NPC 公司预设 (由 tools/build_npc_timelines.py 生成)
  ui/                  视觉资产 (theme.tres, 由 tools/build_theme.gd 生成)
  i18n/                翻译源 strings.csv + content.csv → .translation
                        (生成与规则见 design/国际化设计.md)
assets/
  sprites/              运行时图片素材
    ui/                 运行时 UI 图标 / 卡片缩略图 PNG (product/task/event/marketing 等)
      start_screen/     起始页全屏宣传背景图
  fonts/
  audio/music/         背景音乐 BGM (15 首 .mp3, 由 tools/generate_music.py 经 Replicate MusicGen 生成)
addons/gut/            GUT 测试框架
tests/                 自动化测试: unit / integration / support
design/                设计文档（中文）
docs/                  开发文档（环境配置 / 构建发布 / 端到端调试）
  media/readme/        GitHub README 用封面图与界面截图
tools/                 一次性脚本与诊断工具 (process_asset.py / qa_assets.py / build_theme.gd /
                        build_translations.gd / extract_content_strings.py /
                        build_npc_timelines.py / build_event_cards.py /
                        build_collectibles.py / build_deterministic_ui_icons.py /
                        generate_music.py / screenshot.sh)
```

## 约定

- 场景优先组织：每个功能拥有自己的文件夹，里面放场景与该场景独占的资源。
- 跨系统通信走 `EventBus` 信号，不要互相直接持有节点引用。
- 持久化游戏状态放在 `GameState` 单例；推进回合统一通过 `TurnManager`。
- 资源文件优先 `.tres`，避免 `.res`。
- 如果新增了重要的文件，需要更新cluade.md的目录结构，和每个文件的index.md
- 代码逻辑要写logging，方便debug。
- 我们以代码实现为准，design里面的文档只是方便理解和high level系统设计
- 游戏数据（数值表、模板、预设等）以 `resources/data/` 下的 `.tres` 为准，design 文档里的数值只作参考。
- **化名规范** (玩法设计 §0bis / 公共枚举表 §16): 所有 GPU / 模型 / 架构 / NPC 公司命名**只用化名** (植物 / 动物族), 真实品牌 (NVIDIA, AMD, GPT, Llama, A100, H100 ...) **不出现**在代码、`.tres`、UI 文案中。设计文档可写"≈ X" 注释做对照, 仅注释用。
- **真实量纲**: 涉及算力 / 训练 / 推理的数值用 `FLOPs` / `TFLOPs` / `B tokens` / `tokens/s` 这些真实单位, 不再用抽象的 "compute_unit" / "throughput"。我们数值系统设计尽量靠近现实世界。

## 工作流：测试驱动开发（TDD）

修改任何功能都必须按以下顺序推进，**不允许跳步**：

1. **改设计文档** — 在 `design/` 下更新或新增对应文档，只写high level把意图、规则。数值很多放在data文件夹。
2. **写/改测试用例** — 在 `tests/` 下新增或修改测试，覆盖新行为；此时测试应当**失败**。
3. **写代码 / 资源** — 在 `scripts/`、`scenes/`、`resources/` 下实现，目标是让上一步的测试通过。
4. **跑单元测试** — 单个系统 / 单个脚本的测试全部通过。
5. **跑系统集成测试** — 跨系统、含回合推进与 `EventBus` 的端到端测试通过。
6. 对于有UI界面的改动需要截图进行验证和测试

如果某一步发现前面的设计或测试有问题，回到对应步骤修正后重新往下走，而不是在后面的步骤里打补丁。

**多语言（i18n）**：任何新写的人面文案都必须走 `tr()`，不要硬编码中文。具体怎么加/改翻译（UI 文案走 `strings.csv`、游戏内容走 `.tres`→`content.csv`、生成命令、测试约束）见 `design/国际化设计.md §8`。
