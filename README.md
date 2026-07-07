<div align="center">
  <img src="icon.svg" alt="Scaling Up app icon" width="96">
  <h1>Scaling Up</h1>
  <p><strong>经营 AI 模型公司，一周一回合。</strong></p>
  <p>
    <a href="https://github.com/Qinyong-Wang/scale_up_game/releases/latest"><img alt="Latest release" src="https://img.shields.io/badge/release-v0.1.1--alpha.2-202124"></a>
    <img alt="Godot 4.4.1" src="https://img.shields.io/badge/Godot-4.4.1-478cbf">
    <a href="LICENSE"><img alt="License: GPL-3.0-only" src="https://img.shields.io/badge/license-GPL--3.0--only-202124"></a>
    <img alt="Platforms: macOS and Windows" src="https://img.shields.io/badge/platform-macOS%20%7C%20Windows-666666">
  </p>
  <p>
    <a href="#游戏与玩法">游戏与玩法</a> ·
    <a href="#下载试玩">下载试玩</a> ·
    <a href="#开始-vibe-game-developing">Vibe Game Developing</a> ·
    <a href="#english">English</a>
  </p>
</div>

![Scaling Up cover](docs/media/readme/cover.png)

## 游戏与玩法

**Scaling Up** 是一款以「经营 AI 模型公司」为题材的 2D 模拟经营游戏。玩家从 2017 年的早期实验室起步，以每周一回合推进公司发展：训练模型、建设算力、招募人才、上线产品、融资求生，并在长期经营中把一家小团队带向更大的技术野心。

你面对的不是单一数值增长，而是一组会互相拉扯的经营系统：现金流决定扩张速度，算力决定训练节奏，模型能力影响产品增长，人才结构改变研发效率，事件会在最紧张的时候打乱计划。

| 玩法系统 | 你会做的决定 |
|---|---|
| 每周经营 | 工资、机房成本、任务进度、用户增长、营收与突发事件按周结算。 |
| 模型生命周期 | 预训练、后训练、评估、发布、定价与服务能力会共同决定产品表现。 |
| 算力基础设施 | 租赁或自建数据中心，购买 GPU 化名型号，选择供电方式，并在训练与推理之间分配资源。 |
| 人才与组织 | 招募不同专长的 lead 与 staff，用团队能力影响训练、研究、营销和运营。 |
| 产品与商业化 | 发布 API、聊天产品、智能体、多模态助手和代码助手，通过订阅与调用量获得收入。 |
| 科技树与长期目标 | 沿架构、注意力、损失函数、工程优化、应用能力和上下文长度六条线推进研发。 |
| 事件、公益和收藏 | 机会、危机、融资、慈善项目、办公室荣誉与收藏品共同构成长线经营叙事。 |

游戏中的 GPU、模型、架构和公司命名采用植物 / 动物化名，避免在代码、资源和 UI 中直接出现现实品牌名。训练和推理使用 FLOPs、TFLOPs、B tokens、tokens/s 等真实单位，数值系统尽量贴近现实工程尺度。

## 下载试玩

最新试玩版见 [GitHub Releases](https://github.com/Qinyong-Wang/scale_up_game/releases/latest)。

| 平台 | 下载文件 | 运行方式 |
|---|---|---|
| macOS | `Scaling-Up-0.1.1-alpha.zip` | 解压后运行 `Scaling-Up.app`。未签名版本首次打开时可能需要右键选择“打开”。 |
| Windows x86_64 | `Scaling-Up-0.1.1-alpha-windows-x86_64.zip` | 解压后保持 `Scaling-Up.exe` 与 `Scaling-Up.pck` 在同一目录，再运行 `Scaling-Up.exe`。 |

| 当前试玩包 | 游戏版本 | 引擎 | 语言 | 许可证 |
|---|---|---|---|---|
| `v0.1.1-alpha.2` | `0.1.1-alpha` | Godot `4.4.1 stable` | 中文默认，英文翻译管线 | `GPL-3.0-only` |

## 开始 Vibe Game Developing

如果你想把游戏改成更符合自己口味的版本，这个仓库可以当作一套可扩展的 Godot 经营游戏骨架：内容数据放在 `.tres` 资源里，核心系统按业务拆分，设计文档和测试用例可以帮助你判断改动有没有破坏经营闭环。

```bash
git clone https://github.com/Qinyong-Wang/scale_up_game.git scaling-up
cd scaling-up
godot --headless --import
godot --path .
```

| 想改什么 | 推荐入口 |
|---|---|
| 调整数值、事件、产品、数据集 | `resources/data/` 下的 `.tres` 静态数据 |
| 改经营规则或新增系统 | 先看 `design/`，再改 `scripts/systems/` 与 `tests/` |
| 改 UI、面板和玩家流程 | `scenes/`、`scripts/autoload/ui_theme.gd`、`resources/i18n/` |
| 做自己的构建或发布包 | [docs/构建与发布.md](docs/构建与发布.md) |
| 调试端到端流程 | [docs/端到端调试.md](docs/端到端调试.md) |

干净 clone 后如果要跑测试，需要本地安装 GUT：

```bash
mkdir -p addons
cd addons
git clone --depth 1 --branch godot_4 https://github.com/bitwes/Gut.git gut
```

安装后在 Godot 编辑器中启用插件：`Project -> Project Settings -> Plugins -> GUT -> Enable`。

## 界面预览 / Screenshots

| 起始页 / Start Screen | 模型管理 / Model Management |
|---|---|
| <img src="docs/media/readme/start-screen.png" alt="Scaling Up start screen" width="480"> | <img src="docs/media/readme/models-panel.png" alt="Model management screen" width="480"> |

| 基建与算力 / Infrastructure | 科技树 / Tech Tree |
|---|---|
| <img src="docs/media/readme/infra-panel.png" alt="Infrastructure management screen" width="480"> | <img src="docs/media/readme/tech-panel.png" alt="Technology tree screen" width="480"> |

| 办公室 / Office |
|---|
| <img src="docs/media/readme/office-panel.png" alt="Office screen" width="720"> |

## 当前状态

这是一个开发中的 alpha 版本。当前已经具备核心经营闭环：

- 起始页、新游戏、存读档、设置与新手引导
- 主 HUD 与多 tab 管理界面
- 经济、招聘、基建、数据集、研究、任务、科技树、市场、用户、产品、营收、营销、事件、慈善、收藏、宇宙模拟等系统
- 中文默认、英文翻译管线
- GUT 单元测试与集成测试

平衡性、内容量、正式发行流程和跨平台导出仍在持续迭代。

## 开发细节

### 环境要求

- Godot Engine **4.4.1 stable**
- Git
- GUT 9.x Godot 4 兼容版，用于测试，需本地安装到 `addons/gut/`
- Godot 4.4.1 macOS / Windows 导出模板，仅打包时需要

macOS 上的完整安装说明见 [docs/开发环境配置.md](docs/开发环境配置.md)，打包配置见 [docs/构建与发布.md](docs/构建与发布.md)。

也可以在 Godot 编辑器中扫描并导入本目录。主场景为 `res://scenes/start_screen/start_screen.tscn`。

### 运行测试

单元测试：

```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit
```

集成测试：

```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests/integration -gexit
```

只跑某个测试文件：

```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd -gselect=start_screen_test.gd -gexit
```

更多调试方法见 [docs/端到端调试.md](docs/端到端调试.md)。

### 构建

当前首发导出目标是 macOS 与 Windows x86_64。发布流程、版本号约定和导出预设说明见 [docs/构建与发布.md](docs/构建与发布.md)。

简化流程：

```bash
# 先在 Godot 编辑器里创建本地 export_presets.cfg
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests/integration -gexit
mkdir -p build/macos
godot --headless --path . --export-release "macOS" build/macos/Scaling-Up.app
mkdir -p build/windows
godot --headless --path . --export-release "Windows Desktop" build/windows/Scaling-Up.exe
```

### 项目结构

```text
project.godot          Godot 工程入口
README.md              GitHub 项目介绍与快速开始
LICENSE                GNU GPL v3.0 许可证文本
THIRD_PARTY_NOTICES.md 第三方组件与素材说明
CLAUDE.md / AGENTS.md  协作约定、目录职责与开发工作流
scenes/                场景与 UI，按功能组织
scripts/               Autoload、业务系统与 Resource 脚本
resources/             .tres 静态数据、i18n 与主题资源
assets/                字体、图片、音频等运行时素材
tests/                 GUT 单元测试与集成测试
design/                中文设计文档
docs/                  开发、调试、构建与发布文档；media/readme 存放 README 展示图
tools/                 一次性脚本、素材管线与诊断工具
```

更完整的工程约定见 [CLAUDE.md](CLAUDE.md)，系统设计入口见 [design/index.md](design/index.md)。

### 开发约定

- 修改功能前先更新对应 `design/` 文档，再写测试，最后实现代码。
- 跨系统通信走 `EventBus`，持久化状态放在 `GameState`，推进回合统一通过 `TurnManager`。
- 代码、Godot 文件和提交信息使用英文；`design/` 与协作文档使用中文。
- 面向玩家的文案走 i18n 管线，不在 UI 代码中硬编码中文。
- 资源文件优先使用 `.tres`。

## 许可证

本项目采用 [GNU General Public License v3.0 only](LICENSE) (`GPL-3.0-only`) 发布。

第三方组件、字体与素材说明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

---

## English

<div align="center">
  <img src="icon.svg" alt="Scaling Up app icon" width="96">
  <h1>Scaling Up</h1>
  <p><strong>Run an AI model company, one week at a time.</strong></p>
  <p>
    <a href="https://github.com/Qinyong-Wang/scale_up_game/releases/latest"><img alt="Latest release" src="https://img.shields.io/badge/release-v0.1.1--alpha.2-202124"></a>
    <img alt="Godot 4.4.1" src="https://img.shields.io/badge/Godot-4.4.1-478cbf">
    <a href="LICENSE"><img alt="License: GPL-3.0-only" src="https://img.shields.io/badge/license-GPL--3.0--only-202124"></a>
    <img alt="Platforms: macOS and Windows" src="https://img.shields.io/badge/platform-macOS%20%7C%20Windows-666666">
  </p>
  <p>
    <a href="#game-and-systems">Game and Systems</a> ·
    <a href="#download">Download</a> ·
    <a href="#vibe-game-developing">Vibe Game Developing</a> ·
    <a href="#screenshots">Screenshots</a> ·
    <a href="#developer-details">Developer Details</a>
  </p>
</div>

![Scaling Up cover](docs/media/readme/cover.png)

## Game and Systems

**Scaling Up** is a 2D management simulation game about building an AI model company from a small 2017 lab into a serious technology player. Each turn is one week: train models, build compute infrastructure, hire specialists, launch products, manage cash, and react to events while the company grows from a fragile lab into an ambitious technical organization.

The core fantasy is not just watching numbers go up. You are balancing systems that push against each other: cash controls expansion speed, compute controls training pace, model quality shapes product growth, staff composition changes execution, and events can disrupt a plan right when the runway gets tight.

| System | Decisions You Make |
|---|---|
| Weekly operations | Payroll, facility costs, task progress, user growth, revenue, and events resolve every week. |
| Model lifecycle | Pretrain, posttrain, evaluate, publish, price, and serve models. Capability drives product unlocks, adoption, and operating pressure. |
| Compute infrastructure | Rent or build datacenters, buy fictional GPU codenames, choose power supplies, and split capacity between training and serving. |
| Organization | Recruit leads and staff with different specialties to improve research, training, marketing, and operations. |
| Products | Launch APIs, chatbots, agents, multimodal assistants, and coding agents, then monetize through subscriptions and usage. |
| Tech tree and long-term goals | Advance through architecture, attention, loss, engineering, application, and context-length research lines. |
| Events, charity, and collection | Opportunities, crises, fundraising, charity projects, office honors, and collectibles create the long-run company story. |

Training and inference use real units such as FLOPs, TFLOPs, B tokens, and tokens/s instead of abstract compute points. GPU, model, architecture, and company names use fictional plant / animal codenames; real brand names are intentionally avoided in code, resources, and UI copy.

## Download

The latest playable build is available on [GitHub Releases](https://github.com/Qinyong-Wang/scale_up_game/releases/latest).

| Current playable release | Game version | Engine | Languages | Platforms | License |
|---|---|---|---|---|---|
| `v0.1.1-alpha.2` | `0.1.1-alpha` | Godot `4.4.1 stable` | Chinese default, English pipeline | macOS, Windows x86_64 | `GPL-3.0-only` |

| Platform | Asset | Notes |
|---|---|---|
| macOS | `Scaling-Up-0.1.1-alpha.zip` | Unzip and run `Scaling-Up.app`. The current build is unsigned, so first launch may require right-clicking and choosing "Open". |
| Windows x86_64 | `Scaling-Up-0.1.1-alpha-windows-x86_64.zip` | Unzip and keep `Scaling-Up.exe` and `Scaling-Up.pck` in the same folder before running the game. |

## Vibe Game Developing

If you want to make the game fit your own taste, this repo is meant to be approachable as a Godot management-game foundation. Content lives in `.tres` data files, gameplay systems are split by business domain, and the design docs plus tests give you a way to check whether your changes still preserve the management loop.

```bash
git clone https://github.com/Qinyong-Wang/scale_up_game.git scaling-up
cd scaling-up
godot --headless --import
godot --path .
```

| Goal | Start Here |
|---|---|
| Tune numbers, events, products, and datasets | `.tres` data under `resources/data/` |
| Change rules or add systems | Read `design/`, then edit `scripts/systems/` and `tests/` |
| Change UI, panels, and player flow | `scenes/`, `scripts/autoload/ui_theme.gd`, and `resources/i18n/` |
| Make your own build or release package | [docs/构建与发布.md](docs/构建与发布.md) |
| Debug end-to-end flows | [docs/端到端调试.md](docs/端到端调试.md) |

After a clean clone, install GUT locally if you want to run tests:

```bash
mkdir -p addons
cd addons
git clone --depth 1 --branch godot_4 https://github.com/bitwes/Gut.git gut
```

Then enable it in the editor: `Project -> Project Settings -> Plugins -> GUT -> Enable`.

## Screenshots

| Start Screen | Model Management |
|---|---|
| <img src="docs/media/readme/start-screen.png" alt="Scaling Up start screen" width="480"> | <img src="docs/media/readme/models-panel.png" alt="Model management screen" width="480"> |

| Infrastructure | Tech Tree |
|---|---|
| <img src="docs/media/readme/infra-panel.png" alt="Infrastructure management screen" width="480"> | <img src="docs/media/readme/tech-panel.png" alt="Technology tree screen" width="480"> |

| Office |
|---|
| <img src="docs/media/readme/office-panel.png" alt="Office screen" width="720"> |

## Current Status

Scaling Up is an alpha-stage project with the core management loop already in place.

| Ready Today | Still Evolving |
|---|---|
| Start screen, new game flow, save/load, settings, tutorial | Balance tuning and long-run pacing |
| Main HUD with multi-tab management views | More content, events, and late-game goals |
| Economy, hiring, infrastructure, datasets, research, tasks, products, revenue, marketing, charity, collection, and simulation systems | Release automation and broader platform coverage |
| GUT unit and integration test coverage | Visual regression automation |

## Developer Details

### Requirements

- Godot Engine **4.4.1 stable**
- Git
- GUT 9.x for Godot 4, installed locally at `addons/gut/`
- Godot 4.4.1 macOS / Windows export templates, only needed for packaging

For macOS setup details, see [docs/开发环境配置.md](docs/开发环境配置.md). For packaging, see [docs/构建与发布.md](docs/构建与发布.md).

You can also import the folder from the Godot editor. The main scene is `res://scenes/start_screen/start_screen.tscn`.

### Running Tests

Unit tests:

```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit
```

Integration tests:

```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests/integration -gexit
```

Run one test file:

```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd -gselect=start_screen_test.gd -gexit
```

For more debugging workflows, see [docs/端到端调试.md](docs/端到端调试.md).

### Build

The first export targets are macOS and Windows x86_64. Release steps, versioning, and export preset notes are documented in [docs/构建与发布.md](docs/构建与发布.md).

Short version:

```bash
# Create a local export_presets.cfg in the Godot editor first.
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests/integration -gexit
mkdir -p build/macos
godot --headless --path . --export-release "macOS" build/macos/Scaling-Up.app
mkdir -p build/windows
godot --headless --path . --export-release "Windows Desktop" build/windows/Scaling-Up.exe
```

### Project Layout

```text
project.godot          Godot project entry
README.md              GitHub overview and quick start
LICENSE                GNU GPL v3.0 license text
THIRD_PARTY_NOTICES.md Third-party component and asset notices
CLAUDE.md / AGENTS.md  Collaboration rules, directory ownership, and workflow
scenes/                Feature-organized scenes and UI
scripts/               Autoloads, gameplay systems, and Resource scripts
resources/             .tres static data, i18n, and theme resources
assets/                Runtime fonts, sprites, and audio
tests/                 GUT unit and integration tests
design/                Chinese design documents
docs/                  Development, debugging, build, release docs, and README media
tools/                 One-off scripts, asset pipeline, and diagnostics
```

See [CLAUDE.md](CLAUDE.md) for the full project conventions and [design/index.md](design/index.md) for the system design index.

### Development Notes

- Update the relevant `design/` document before changing behavior, then write tests, then implement.
- Use `EventBus` for cross-system communication. Persistent state belongs in `GameState`; weekly progression goes through `TurnManager`.
- Code, Godot files, and commit messages are written in English. `design/` and collaboration docs are written in Chinese.
- Player-facing copy should go through the i18n pipeline instead of being hardcoded in UI scripts.
- Prefer `.tres` resources over `.res`.

## License

This project is licensed under the [GNU General Public License v3.0 only](LICENSE) (`GPL-3.0-only`).

Third-party component, font, and asset notices are listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
