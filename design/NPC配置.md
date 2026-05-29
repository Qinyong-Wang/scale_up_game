# NPC 配置

> **目的**: 列出 23 家 NPC 公司的身份定位、所在榜单, 以及 release 时间线的总规则。
> **读者**: 想加 NPC、调整时间线、或在 .tres 里改具体数值的人。
> **状态**: 🟢 与 `MarketSystem._install_default_npcs` (.tres 加载路径) 同步。
> **v8 PR-H (2026-05)**: NPC 改为"产品时间线驱动" — 每家公司在 .tres 里写整条 release 时间线 (2018-2042+), 删除原 step jump / perturbation / distillation 机制。详见 `竞争对手系统设计.md`。
> **v9 PR-I (2026-05)**: 删除独立的 OS 模板表 (`OpenSourceModelTemplate` + `resources/data/models/os/*.tres`), **OS 模型集合 ≡ 7 家 `is_open_source = true` NPC 的 `release_kind = pretrain` releases**。`research.download_open_source` 与 `infra.deploy_open_source_model` 参数从 `template_id` 改为 `release_id`, 走 `MarketSystem.find_release` 反查。详见 §2.6。

NPC 是 MarketSystem 唯一的"对手", 在排行榜里和玩家模型同台。
玩家不直接与 NPC 互动, 只通过名次差距、新闻提示 (`npc_released` 信号) 感受到压力。

---

## 0. 命名规范

- 公司名: 动物族化名 (玩法设计 §0bis), 不出现真实公司名。
- 模型名: 公司名前缀 + 版本号, 含中间小版本 `.1 / .5 / .7` (例 "Orca-4", "Orca-4.5", "Orca-4o", "Orca-5")。
- 现实对照: 仅作设计师注释 (例 "≈ GPT-4"), 不进入 .tres / UI / 代码。

---

## 1. 23 家公司全景

### 1.1 总榜 (5 家, 出现在 `total`; 同时按阵营自动出现在 `closed_source` / `open_source` 展示榜)

| id | 显示名 | 阵营 | 身份 (一句话) | 上的细分榜 |
|---|---|---|---|---|
| `npc_orca_lab` | OrcaLab | closed | 行业总冠军, 通用 + 推理双标杆, 集群最大 (≈ OpenAI) | sub_general, sub_reasoning, sub_agent |
| `npc_raven_ai` | RavenAI | closed | 推理王 / 安全派, 节奏稳但晚一拍 (≈ Anthropic) | sub_reasoning |
| `npc_tiger_studio` | Tiger Studio | closed | 多模态王, 用 bamboo (TPU 化名) 自研生态 (≈ Google DeepMind) | sub_multimodal |
| `npc_falcon_inc` | Falcon Inc | closed | 工程派, 起步晚但暴力堆卡, code/agent 双强 (≈ xAI/Meta) | sub_code, sub_agent |
| `npc_wolf_research` | Wolf Research | **open** | 开源旗手, 总榜级模型免费放, 落后闭源 SOTA 25-35 周 (≈ Meta-AI) | sub_general |

### 1.2 sub_general 专精 (3 家, 不上 total)

| id | 显示名 | 阵营 | 身份 |
|---|---|---|---|
| `npc_sparrow_chat` | Sparrow Chat | closed | 大众聊天助手, 高频小迭代, 总能在 sub_general 前三 |
| `npc_hare_express` | Hare Express | closed | "快 + 便宜"路线, 永远小一档但 release 节奏快 |
| `npc_finch_open` | Finch Open | **open** | 社区聊天开源旗手, 落后同档闭源 30 周 |

### 1.3 sub_code 专精 (4 家)

| id | 显示名 | 阵营 | 身份 |
|---|---|---|---|
| `npc_ant_quickcode` | Ant QuickCode | **open** | 开源 code 专精, 模型小但 code 数据集精 |
| `npc_termite_devkit` | Termite Devkit | closed | IDE 集成 / 仓库级补全, code + agent 联动专精 |
| `npc_bamboo_compiler` | Bamboo Compiler | closed | 用 bamboo TPU, code + reasoning 双强 |
| `npc_lynx_devnet` | Lynx Devnet | **open** | 开源仓库代理 / CI 修复社区, code + agent 衔接但主打 sub_code |

### 1.4 sub_reasoning 专精 (3 家)

| id | 显示名 | 阵营 | 身份 |
|---|---|---|---|
| `npc_bee_logic` | Bee Logic | **open** | 开源 reasoning + RL 专精, 论文驱动 |
| `npc_octopus_think` | Octopus Think | closed | 用 octopus MoE 架构, 长思维链专精 |
| `npc_owl_open` | Owl Open | **open** | 学术派 reasoning, 节奏慢但精度高 |

### 1.5 sub_multimodal 专精 (4 家)

| id | 显示名 | 阵营 | 身份 |
|---|---|---|---|
| `npc_dolphin_vision` | Dolphin Vision | closed | 视觉 / 视频专精, 不做纯文本 |
| `npc_whale_audio` | Whale Audio | closed | 音频 / 语音 + 视频, 多模态融合 |
| `npc_beaver_network` | Beaver Network | **open** | 开源多模态社区, 落后同档闭源 30 周 |
| `npc_heron_vision` | Heron Vision | **open** | 开源视觉理解与轻量视频模型社区, 专注 sub_multimodal |

### 1.6 sub_agent 专精 (4 家)

> agent 轴在 paradigm_reasoning_rl (turn 414+) 后才大规模兴起, 这 4 家 2024-2025 才开始发力。

| id | 显示名 | 阵营 | 身份 |
|---|---|---|---|
| `npc_raccoon_ops` | Raccoon Ops | closed | tool use / 浏览器自动化专精 |
| `npc_ant_swarm` | Ant Swarm | closed | 多 agent 协作框架, agent + reasoning 联动 |
| `npc_crow_labs` | Crow Labs | **open** | 开源 agent 旗手, 落后闭源 35 周 |
| `npc_otter_tools` | Otter Tools | **open** | 开源工具调用 / 工作流自动化社区, 小团队高迭代 |

**总数**: 5 家主榜 + 18 家分榜 = **23 家**。
**开源比例**: 10 家 (Wolf, Finch, Ant QuickCode, Lynx, Bee, Owl, Beaver, Heron, Crow, Otter), 占约 43%, 强化开源生态存在感。

---

## 2. release 时间线总规则

每家 NPC 的 `model_releases` 数组写满"从首发到 2042 后"的完整产品线, 在 `resources/data/npcs/<id>.tres` 里以 sub_resource 形式内联。

### 2.1 集群升级节奏 (总榜 5 家)

总榜公司每条 release 的集群 (机房 tier / GPU 化名 / 卡数) 锚定到现实 — 大致每 18-30 个月升一档机房, GPU 化名跟踪现实上市节奏 (`cypress_t0..t3` 对应 V100→A100→H100→B200, 2030 后用假想未来代), 卡数从早期数百张一路上探到后期数百万张。每条 release 的具体集群配置写在 `resources/data/npcs/*.tres` 的 NpcModelRelease 子资源里。

> 顶级 (OrcaLab) 后期可能联训多机房, 总卡数达数百万级。Tiger Studio 用 `bamboo_t*` (TPU 化名) 并行轨道。

### 2.2 集群升级节奏 (分榜 15 家)

分榜公司**比同时代主榜小一档**:
- 主榜 tier 9 (100k 卡) 时, 分榜 tier 8 (30k 卡)。
- 但分榜模型在专精轴上能打到主榜 top-3 水平 (架构 / 数据 / RL 调优更精)。
- 其他 4 轴明显落后。

### 2.3 release 节奏

- **总榜**: 平均 ≥ 2 release / 年, 中后期 2-3 / 年。大版本 (`X / X+1`, `release_kind = pretrain`) 间隔 12-24 个月, 中间填 `X.1 / X.5 / X.7` (`release_kind = posttrain / rlhf / multimodal_posttrain / reasoning_rl / tool_use_posttrain`)。
- **分榜**: 平均 1-1.5 release / 年, 节奏稀疏但每代精度高。
- **开源公司**: 同等技术档位的 release 比闭源对标晚 20-40 周。在 .tres 时间线里**直接体现**, 不需运行时计算。

### 2.4 release 类型 (release_kind)

| 值 | 语义 | 是否需要填 params / cluster |
|---|---|---|
| `&"pretrain"` | 全量预训练, 大版本 | 必填 |
| `&"posttrain"` | 通用后训 (SFT) | 可不填, 沿用前版 |
| `&"rlhf"` | RLHF / DPO 对齐 | 可不填 |
| `&"multimodal_posttrain"` | 多模态后训 (gpt-4o 式) | 可不填 |
| `&"reasoning_rl"` | 推理 RL (o1/R1 式) | 可不填 |
| `&"tool_use_posttrain"` | tool use / agent 后训 | 可不填 |

> `release_kind` 只影响 UI / 叙事; 排行榜只看 `capability` 5 轴。

### 2.5 capability 数值锚点

NPC release 的 5 轴 capability 直接写在 .tres 里, 取值锚定到 `research_system / task_system §6.7` 的 evaluate 公式 — 同年代、同 params/tokens 量级的玩家自训模型评分应大致对齐, 让 NPC 时间线与玩家成长曲线落在同一坐标系。具体数值见 `resources/data/npcs/*.tres`。5 轴中 general / code / reasoning 是基础, multimodal / agent 是后期解锁 (multimodal 2022+, agent 2024+), 早期 release 这两轴接近 0。

### 2.6 release 与"可下载/可部署 OS 模型" (v9 PR-I)

玩家通过两条入口消费 NPC 时间线里的开源 release:

| 入口 | 命令 | 语义 |
|---|---|---|
| 模型 tab "下载开源模型..." | `research.download_open_source {release_id}` | 实例化 `NpcModelRelease` → `Model` (`status = evaluated, provenance = downloaded_os, source_release_id = release_id`), 进 `GameState.models`, 可发布/部署/做产品 |
| 基础设施 tab "Serving → 公共开源模型" | `infra.deploy_open_source_model {release_id}` | 先经 `research.ensure_open_source_release_published` 物化/复用并开源发布该 release, 自动建 API 产品, 再让 dc 服务对应 model (`serving_target_kind = &"owned_model"`, `deployed_model_id = model_id`) |

**资格规则** (两条入口共用):
- `npc.is_open_source == true`
- `release.release_kind == &"pretrain"` (后训类 release 没有 cluster/params 信息, 不能下载)
- `release.release_turn <= GameState.turn`

不满足任一条返回错误 `unknown_release / not_open_source / not_pretrain / not_released_yet`。

**冷启动**: turn 0-214 没有任何 OS NPC 首发, 两条入口都返 `not_released_yet`。UI (main.gd serving 抽屉 + 模型 tab 下载按钮) 据此显示「暂无可用开源模型」/ 置灰按钮。**首个可下载 release 是 Wolf-1 (turn 215, 2021Q3)**。

**flops_per_token 派生**: download 路径下, 开源 NPC release 的 flops_per_token 由 release 的 params / active_params 经 `Model.infer_flops_per_token` 派生, 与玩家自训模型用同一套公式, 不再硬编码。架构 / 集群 / 训练周数 / 数据 token 都是 .tres 里写明的, 玩家可以在「下载对话框」里看到完整出身。

---

## 3. 资源字段语义

类与字段定义以代码实现为准 (`scripts/resources/npc_company.gd`, `scripts/resources/npc_model_release.gd`)。本节只描述每个字段的语义与取值规范, 不复制类签名。

### 3.1 NpcCompany

| 字段 | 类型 | 语义 |
|---|---|---|
| `id` | StringName | NPC 全局唯一 id, 例 `npc_orca_lab` |
| `display_name` | String | UI 显示, 例 "OrcaLab" |
| `is_open_source` | bool | 决定该公司归属 `closed_source` 还是 `open_source` 主榜 |
| `board_membership` | Array[StringName] | 总榜资格 + 细分榜子集; 5 主榜公司含 `closed_source` 或 `open_source` + 可选细分榜; 分榜公司只含一个 `sub_*`。`closed_source` / `open_source` 展示榜按 `is_open_source` 自动收录所有已首发 NPC, 不要求这里显式写 source 标签 |
| `model_releases` | Array[NpcModelRelease] | 整条产品时间线, 按 `release_turn` 升序排, 在 .tres 中以 sub_resource 形式内联 |
| `current_release_id` (派生) | StringName | 运行时由 MarketSystem 每周更新, 不需要在 .tres 写入 |
| `model_capability` (派生) | Dictionary | = current_release.capability 的缓存, 同上 |

### 3.2 NpcModelRelease

| 字段 | 类型 | 语义 |
|---|---|---|
| `id` | StringName | release 全局唯一 id, 例 `release_orca_5` (前缀 `release_` + 模型名 kebab) |
| `display_name` | String | UI 显示, 例 "Orca-5" |
| `release_turn` | int | 发布回合 (= 何时这条 release 开始计入排行榜) |
| `capability` | Dictionary | 5 轴 {general, code, reasoning, multimodal, agent}, 数值锚点见 §2.5 |
| `release_kind` | StringName | `pretrain` / `posttrain` / `rlhf` / `multimodal_posttrain` / `reasoning_rl` / `tool_use_posttrain`; 仅 UI/叙事用, 排行榜不消费 |
| `cluster_gpu_id` | StringName | 训练用 GPU 化名 (`cypress_t0..t3` / `bamboo_t1..t4` / 未来代) |
| `cluster_gpu_count` | int | 训练集群卡数 |
| `training_weeks` | int | 训练周数 (20-30 为典型) |
| `params_b` | float | 参数量, B 为单位 (例 1500.0 = 1.5T) |
| `active_params_b` | float | MoE 激活参数; dense 模型直接等于 params_b |
| `dataset_tokens_b` | float | 训练 token, B 为单位 (例 13000.0 = 13T) |
| `arch_codename` | StringName | 架构化名, 例 `ant_v4` (dense) / `octopus_v2` (MoE) |

`release_kind = pretrain` 时上述 cluster / params / tokens / arch 字段全部必填; 后训类 (`posttrain` 等) 可填 0 / 空, UI 据此显示 "基于上一版后训" 而不重复列集群参数。

---

## 4. 加 NPC / 改时间线的步骤

1. **改设计文档**: 在 `NPC配置.md §1` 加一行身份描述。
2. **改/加 .tres**: 在 `resources/data/npcs/` 加 `npc_<id>.tres`, 或在已有文件里加 sub_resource。
3. **跑测试**: `tests/unit/market_system_test.gd::test_default_npcs_seeded_23` 调整数量断言, `test_release_timeline_advances` 验证 release_turn 顺序。
4. **特殊事件触发** (可选): 如果新 NPC 有"收购 / 合并 / 倒闭"剧情, 在 `EventSystem` 加事件卡, 通过 `retired: bool` 字段让 MarketSystem 跳过排榜。

---

## 5. 未决问题

- [ ] **新 NPC 进入**: 当前 23 家从 turn 0 起就在 roster 里 (虽然首发可能很晚, 例 OrcaLab turn 70)。是否需要"中途新公司成立"事件 (例 2028 出现一家 AI 创业公司)? 目前 23 家覆盖全部生态, 没强需求。
- [ ] **NPC 倒闭 / 收购**: `retired: bool` 字段未实现。设计中。
- [ ] **paradigm event 与 NPC 时间线一致性**: 4 张 paradigm 事件卡 (turn 282/297/366/414) 应在叙事上 "对应"某个 NPC 那时的大版本发布; 现在 paradigm 事件改为纯叙事 (`竞争对手系统设计.md §7`), 但叙事文本应引用具体 NPC release 名 (例 "OrcaLab 发布 Orca-Chat", "RavenAI 发布 Raven-2 with RLHF")。当前事件 .tres 还是泛文案, 待润色。
- [ ] **release 自动生成助手**: 23 家 × 30-40 release ≈ 690-920 行配置, 改一次数值很重。考虑用 `tools/build_npc_releases.gd` 从一份 csv / yaml 模板生成 .tres? 当前手写。
