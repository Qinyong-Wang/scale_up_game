# Scaling Up

一款以「经营 AI 模型公司」为题材的 2D 模拟经营游戏，每周一回合，使用 **Godot 4** 开发。

## 语言约定

- `AGENTS.md` 与 `design/` 下所有设计文档**一律使用中文**，节省上下文。
- 代码、提交信息、Godot 自带文件保持英文。

## 目录结构

```
project.godot          Godot 工程入口
icon.svg               应用图标
icon.icns              macOS 原生应用图标
icon.ico               Windows 原生应用图标
scenes/                按功能划分（不按资源类型）
  main/                根场景 Main
  ui/                  HUD、面板、弹窗
    pretrain_dialog/   启动预训练对话框 (PretrainDialog)
  office/              公司办公场景
scripts/
  autoload/            全局单例：GameState / EventBus / TurnManager / CommandBus / Log / UITheme
  systems/             业务系统：economy / hiring / infra / dataset / research /
                        tech_tree / task / market / user / product / monetization /
                        marketing / event / founder / charity / collection / simulation
                        辅助：icon_registry / name_romanizer / person_name
  resources/           自定义 Resource 类型脚本：model / lead / datacenter /
                        facility_construction / facility_spec / gpu_spec / gpu_batch /
                        power_supply_spec / dataset / dataset_template /
                        product / product_type_spec /
                        campaign / loan / npc_company / leaderboard_entry /
                        event_card / event_option / event_effect / event_instance /
                        tech_node / task_template / task_instance / collectible_spec /
                        charity_cause_spec / simulation_stage_spec
resources/             静态数据 .tres
  data/
    tasks/             任务模板 (pretrain/posttrain/evaluate/data_collection/tech_research/charity/simulation)
    infra/
      facilities/      机房规模档位 19 档 (solo / pod / rack_* / room / hall / floor / building_*/ campus_* / metropolis / space_* / planet)
      gpus/            GPU 型号 (cypress_t0-t3, maple_t1-t3, bamboo_t1-t4)
      power/           供电方式 (grid/green; 旧 solar/wind/nuclear/coal 读档迁移)
    datasets/          数据集模板 (开源 / 商业)
    products/types/    产品类型模板 (api/chatbot/agent/multimodal_assistant/coding_agent)
    tech/              科技树节点 (arch / attention / loss / engineering / application / context; 旧 inference/agent 别名兼容期保留)
    codenames/         化名词库 (animals.txt / plants.txt)
    events/            事件卡牌 (routine / crisis / opportunity / flavor)
    npcs/              NPC 公司预设 (23 家, 取代旧的 _install_default_npcs 硬编码)
assets/
  sprites/
    ui/start_screen/   起始页全屏宣传背景图
  fonts/  audio/
addons/
  gut/                 GUT 测试框架
tests/                 自动化测试
  unit/                单元测试
  integration/         系统集成测试
design/                设计文档（中文）
docs/                  开发文档（环境配置 / 构建发布 / 端到端调试）
  media/readme/        GitHub README 用封面图与界面截图
tools/                 一次性脚本与诊断工具（如 font_diag.gd）
```

## 约定

- 场景优先组织：每个功能拥有自己的文件夹，里面放场景与该场景独占的资源。
- 跨系统通信走 `EventBus` 信号，不要互相直接持有节点引用。
- 持久化游戏状态放在 `GameState` 单例；推进回合统一通过 `TurnManager`。
- 资源文件优先 `.tres`，避免 `.res`。
- 如果新增了重要的文件，需要更新cluade.md的目录结构，和每个文件的index.md
- 代码逻辑要写logging，方便debug。
- 必须要先读相应模块和系统的设计文档，再开始实现。
- **化名规范** (玩法设计 §0bis / 公共枚举表 §16): 所有 GPU / 模型 / 架构 / NPC 公司命名**只用化名** (植物 / 动物族), 真实品牌 (NVIDIA, AMD, GPT, Llama, A100, H100 ...) **不出现**在代码、`.tres`、UI 文案中。设计文档可写"≈ X" 注释做对照, 仅注释用。
- **真实量纲**: 涉及算力 / 训练 / 推理的数值用 `FLOPs` / `TFLOPs` / `B tokens` / `tokens/s` 这些真实单位, 不再用抽象的 "compute_unit" / "throughput"。我们数值系统设计尽量靠近现实世界。

## 工作流：测试驱动开发（TDD）

修改任何功能都必须按以下顺序推进，**不允许跳步**：

1. **改设计文档** — 在 `design/` 下更新或新增对应文档，先把意图、规则、数值写清楚。
2. **写/改测试用例** — 在 `tests/` 下新增或修改测试，覆盖新行为；此时测试应当**失败**。
3. **写代码 / 资源** — 在 `scripts/`、`scenes/`、`resources/` 下实现，目标是让上一步的测试通过。
4. **跑单元测试** — 单个系统 / 单个脚本的测试全部通过。
5. **跑系统集成测试** — 跨系统、含回合推进与 `EventBus` 的端到端测试通过。
6. **提交（commit）** — 一次提交包含上述 1–5 的所有改动；提交信息说明「改了什么 + 为什么」。

如果某一步发现前面的设计或测试有问题，回到对应步骤修正后重新往下走，而不是在后面的步骤里打补丁。
