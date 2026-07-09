# 设计文档索引

本目录是 *Scaling Up* 的设计文档总入口。每篇文档讲清楚**一件事**的意图、规则、数值与验收标准；代码实现以这些文档为契约。

## 约定

- 一律使用**中文**散文 + 英文代码标识符。
- 文件命名：设计文档用**中文**（如 `游戏基础架构设计.md`），索引、工具类用**英文**（如 `index.md`）。
- 每篇文档开头写**一句话目的**，结尾留**未决问题 / TODO**。
- 修改任何系统行为前，先回到本目录更新对应文档（见 `CLAUDE.md` 中的 TDD 工作流第 1 步）。
- 新文档创建后，回到本索引登记。

## 文档清单

### 基础

- [游戏基础架构设计.md](游戏基础架构设计.md) — Autoload 四件套(GameState / EventBus / CommandBus / TurnManager)、状态切片所有权、回合相位、Resource 规范、持久化、UI 交互、测试与命名约定。
- [开发调试设计.md](开发调试设计.md) — `Log` autoload v0 (级别 + 类别过滤 + captured/console sink); 未实现的 caller-frame / 多 sink / F2-F5 快捷键 / BusInspector 收在 §12。**严禁裸 `print`, 统一走 `Log.*`**。
- [UI适配设计.md](UI适配设计.md) — 主 HUD 对齐已实现系统能力: 模型评估/发布/改价、基建资源化展示、数据市场扫描、科技效果摘要、产品类型解锁。
- [UI视觉系统设计.md](UI视觉系统设计.md) — 视觉骨架: 设计 token (深色科技感色板/字号/间距) + 侧栏 Dashboard 布局 + 卡片墙 + FilterBar + 右抽屉; 组件清单与从 TabContainer 的迁移路径。
- [图片素材管线设计.md](图片素材管线设计.md) — AI 生成图片进入项目的 harness 契约: raw / prompt / pipeline-meta 可追溯, 本地去背裁切验收, 接受后的 PNG 才进入 `assets/sprites/`。
- [图片素材生成流程.md](图片素材生成流程.md) — 配套操作手册: 角色分工 + 风格一致性 + prompt 写法 (含 19 档机房建筑 subject 清单) + 去哪生成 + harness 后处理命令 + agent 用 Read 读图 inspection + 接受接入路径。
- [国际化设计.md](国际化设计.md) — i18n 管道: Godot CSV 翻译 + tr() + 英文首次启动默认值 + zh_CN fallback; key 命名约定与"何时该 tr/不该 tr"边界; 旧代码跟随 tab 迁移。
- [音频系统设计.md](音频系统设计.md) — 背景音乐 (BGM) + 按钮点击音效 (SFX): `MusicPlayer` 顺序循环播放纯乐器曲目, `SfxPlayer` 自动注册按钮并播放短 click; 设置里可分别开关 (走 `Preferences.music_enabled/sfx_enabled` 持久化, 单消费者故不走 EventBus); 曲目由 `tools/generate_music.py` 离线 (Vertex AI) 生成入库, 真实模型名仅在生成工具里。

### 玩法总览

- [玩法设计.md](玩法设计.md) — 跨系统总图: 资源/资产二分模型、相位与触发时机、玩法 ↔ 系统对应表、各系统详设入口。
- [系统耦合矩阵.md](系统耦合矩阵.md) — 业务 system 的命令矩阵 / 切片读关系 / 信号链 / 隐性耦合审视, 解耦评估。
- [出身系统设计.md](出身系统设计.md) — 起始页 (新游戏 / 继续 / 读档 / 设置 / 退出) + 新游戏取名 + 三种「出身」(ML 科学家 / 连续创业者 / 知名网红, 每种有得有失, 通过 `FounderSystem` 钩进招聘 / 经济 / 用户三系统) + 选公司标志 (程序化预设标记, 顶栏品牌) + 选创始人头像 (写到「玩家自己」这位 lead)。

### 各系统详设

- [经济系统设计.md](经济系统设计.md) — 钱的中枢, spend/award/loan/funding, cash 允许为负, 破产判定; **8 轮融资** (pre_seed/seed/A/B/C/D/E/F, ¥500k ~ ¥80B) 玩家自发触发 (不再走事件; v9.1 无顺序锁, conditions 满足即可跳轮), 玩家持股 50% 上限; 周度财务报表 (账本 12 周历史 + 上周收支明细表格); 周度税务 (企业所得税 25% 免征 100w + AI/UBI 税 1B 门槛上 20%, 经营性净利润为基、亏损结转)。
- [招聘系统设计.md](招聘系统设计.md) — lead (具名) + staff (聚合); 6 种 specialty 在 4 象限 (pretrain / posttrain / research / marketing) 提供 bonus; 工资数量级对标真实 AI lab (ml_eng 350k/年, lead C 1M/年起, S 12M+/年); 玩家本人可作为 founder-scientist 加入 leads (免费, 不可解雇, 一局一个)。
- [基础设施系统设计.md](基础设施系统设计.md) — **机房 + GPU 二元资产**: facility 决定容量/场地, GPU (cypress/maple/bamboo, **t0..t4**) 单独购买并按 10%/年复利二手卖出; 一机房只装一种 GPU; 供电方式 (grid/green) 影响电费 / 集群效率; 公共开源 release 可在基建 tab 直接 Serving, 并自动物化为 downloaded_os published model + API 产品; 真实量纲 (TFLOPs / token-per-sec); engineering 树乘数下沉到 `dc.serving_tokens_per_sec`.
- [数据集系统设计.md](数据集系统设计.md) — 三渠道获取 (开源/购买/采集), 训练时被 task 锁定; 开局含 starter_* 小公开数据集, 用于冷启动训练. **v7 PR-G** 每份数据集带 `modality` (text/image/audio/video; 旧 code 按 text 兼容), pretrain 训练时校验有效 `ds.modality ∈ model.input_modalities ∪ {text}`; DatasetCollectionDialog 自采也让玩家选模态, 代码专精通过 coverage tag 表达; 后训练自采可勾选监控员工日常工作数据, 小幅提高产出 quality.
- [研究系统设计.md](研究系统设计.md) — **模型训练系统** (文件名暂保留), HUD tab 名「模型」; 4 状态 (pretrained / posttrained / evaluated / published), capability 必须 evaluate 后才显示; `download_open_source` 与基建公共开源部署都会产生 `provenance=downloaded_os` 模型, 后者通过 `ensure_open_source_release_published` 幂等物化并自动发布. **v5 (PR-C)** PretrainDialog **A/B/C/D 四轴**: 架构族 / 注意力 / Loss / 上下文长度, 每个轴独立选择. **v2.1 (2026-05)** PosttrainDialog 预览与 `research.posttrain_apply` 共用 `ResearchSystem.simulate_posttrain` 纯函数.
- [科技树系统设计.md](科技树系统设计.md) — **6 棵** DAG (v7 PR-G 加 context 子树): arch / attention / loss / engineering / application / **context** (D 轴可解锁档位 4k→32k→200k→1M→10M, 解锁后 PretrainDialog 可选 + evaluate agent 维度加成). v11 清理未消费节点: application 只保留 `tool_use / fox_code_specialist`, engineering 删除只产训练效率的节点, arch 删除无消费的模态头节点. **arch 陷阱节点** 现在是有限 scale: BERT 线 `bert_encoder cap=30 → roberta 38 → electra 45 → deberta 52 → bert_scale 60 → bert_giant 64`, T5 线 `t5_enc_dec 45 → ul2_enc_dec 58`; 玩家能涨分但会撞范式天花板. 另有 **multimodal_method 子链** (cross_train / dit_v1 / pixel_ar / native_multimodal), **reasoning RL 子链** (dpo/rlvr/o1_rl), **2030+ 未来节点** (world_model_v1/embodied_v1/bit2_quant/analog_compute/infinite_attn). 节点用动物化名 / 学术缩写; UI 显示数值化 effects_summary; 通过 task.start 研究, 不可逆. **v6 (PR-D)** 历史化时间线: 节点时长 24-48 周 + 强制前置链 + 每节点声明 `min_researchers / min_engineers / min_gpu_count`; 「研究」按钮打开 ResearchDialog 让玩家选 lead/研究员/工程师/datacenter, 研究期间锁 dc.
- [任务系统设计.md](任务系统设计.md) — **7** 子类型 (pretrain/posttrain/**evaluate**/data_collection/tech_research/charity/simulation) 通用框架, 完成时 fan-out 派发; 模型生命周期 task **base_cost = 0**, 资源占用即成本; preview 返回 modifier_breakdown 供训练弹窗显示 buff/debuff; scaling law 用真实量纲 (FLOPs / TFLOPs / B tokens); **v4 (PR-B)** MoE 训练只走 active params (compute = 6×N_active×D); **v5 (PR-C)** scaling_law 公式加 attention/loss/context 4 轴乘子; 启动入口分散在模型/数据/科技/慈善 tab, 「任务」tab 仅展示进度与取消, subtype 标题必须全部走 i18n.
- [竞争对手系统设计.md](竞争对手系统设计.md) — 排行榜 (`total` 主榜 + closed/open + 5 个细分榜) + 23 家 NPC (5 主榜 + 18 家分榜, 其中 10 家开源) 时间线驱动 (每家 .tres 写整条 release 时间线到 2042+, 含 `.1/.5/.7` 中间版本), `LeaderboardEntry` 显示「模型名 — 公司名」. **v8 PR-H** 删除 step jump / perturbation / 蒸馏机制, 改为"产品时间线驱动" — NPC 当前能力 = 最新已发布 release 的 capability.
- [用户系统设计.md](用户系统设计.md) — paid_users + token_demand 派生计算器, 无切片 (资源型)。
- [产品系统设计.md](产品系统设计.md) — **简化版**: 类型由 capability 阈值解锁, 默认绑最新 published 模型 (auto_track_latest), 每用户每周固定 token 用量; chatbot / agent / multimodal_assistant / coding_agent 通过 ProductTypeSpec 资源扩展。
- [营收系统设计.md](营收系统设计.md) — 周度结算 API + 订阅营收, 纯结算器, 通过 users_resolved 信号驱动. **v4 (PR-B)** 不再二次乘 engineering 乘数, 改为直接读 `dc.serving_tokens_per_sec` (基础设施已下沉). **§6bis** 营收 tab = `RevenueView` (可折叠分组 + 横向占比条 `share_bar`), 纯展示, 数据由 `main._build_revenue_view_data()` 拉取.
- [营销系统设计.md](营销系统设计.md) — campaign 持续 N 周, 周度扣预算, 加成 UserSystem 的用户增长。
- [事件系统设计.md](事件系统设计.md) — 机会 / 危机 / flavor 三类卡牌, effect dispatch 模式调用所有系统。
- [宇宙模拟工程设计.md](宇宙模拟工程设计.md) — 慈善三期 capstone: 5 级递进模拟阶梯(气象→海洋→地球→太阳系→宇宙), 每级要**真选一座自有、空闲、未对外出租的 DC 永久捐出去**(门槛按单座 DC 的 `min_train_tflops` 真实训练算力, 弹 `SimulationDonationDialog` 单选 DC) **+ 巨额捐助 cost(递增到 ¥1T) + 时间 weeks**; 终局=装满 Cypress T3 的 100M 卡微型星球(planet)那一座 DC。逐级解锁, 复用 `TaskSystem`(子类型 `simulation`), 跑完宇宙级揭晓终极答案 **42**, 弹窗提示去办公室, 并摆出二期 `universe_answer` 终极答案盒。`SimulationSystem` + `SimulationStageSpec`; `simulation.start_stage {dc_id}`(永久移除 DC) `/complete_stage`; 资金可抵税。
- [办公室与收藏系统设计.md](办公室与收藏系统设计.md) — 慈善二期: 「办公室」tab = **房间场景**(背景+办公桌+电脑, 点击电脑开**收藏柜 dialog**=持有收藏品可卖; 摆放**已获得**的奖章 / 奖杯 / 终极答案盒) + 独立**拍卖行** tab(目录按市价买)。收藏品 = 增值资产 + sink: 市价随游戏日历沿增值曲线上涨、**2070 封顶**, 卖出按市价扣抽成(`SELL_FEE`)。`CollectionSystem` 加载 `CollectibleSpec`(类别/曲线 keyframes)与 `TrophySpec`; `collection.buy/sell` 即时命令; 荣誉授予来源已接(登顶总榜 / 慈善全球档 / 宇宙「42」答案盒); 房间美术先程序化占位, 真图落 `assets/sprites/ui/office/`; 收藏品卡缩略图**逐件**出图落 `assets/sprites/ui/collectible/<id>.png`(`IconRegistry.collectible_icon`); 金额一律用全局 `$`(不用 ¥); 化名规范(虚构收藏名)。
- [慈善系统设计.md](慈善系统设计.md) — 后期 money sink: 向 3 个公益方向 (生物科学 / 基础超算 / 失业援助) 做**阶梯式捐助**, 每次捐助是 `TaskSystem` 的 `charity` 子类型任务 (启动当周一次性扣费 + 全额抵税, **完成时**才激活小而封顶的直接加成: S 级权重 / 估值乘子 / 营销转化率乘子, 无声誉中间层, 范式抄 `FounderSystem`)。**三档顺序爬梯、每档只能捐一次**(`charity_tier_done` 记已完成档数, 取档/加成只看它; `charity_donated` 只做累计展示; 越级/重捐/已有进行中任务都拒)。分三期: ①核心 sink ②办公室荣誉+拍卖行 ③宇宙模拟 capstone (真捐一座算力中心 + 巨额现金 → 长任务 → 终极答案 "42")。
- [教程与帮助系统设计.md](教程与帮助系统设计.md) — 新手上手两件套: ①开局**多页分步引导** `TutorialDialog` (欢迎/回合制 → 训练模型流程 → 创建&影响产品流程 → 指引帮助; 「不再显示」勾选经 `finished` 信号落 `Preferences.skip_intro`; 靠会话态 `GameState.pending_intro` 仅新游戏弹、不入存档); ②右侧导航「其他」组的**帮助** view (master-detail: 左系统列表 + 右 `RichTextLabel` 说明, 覆盖全部 14 个玩家面向系统, 顶部「重新查看新手引导」复用对话框)。引导弹窗与帮助 view 都订阅 `locale_changed`, 开着也实时切中/英。

### 参考表 (与代码同步)

- [公共枚举表.md](公共枚举表.md) — 跨系统 StringName (specialty / arch / product.type / effect.kind 等); **§16 命名约定**: GPU 用植物族 (cypress/maple/bamboo), 模型/架构用动物族 (sparrow/orca/ant_v2/octopus_v2 等), 不出现真实品牌名.
- [命令总线表.md](命令总线表.md) — 所有 CommandBus 命令的入参 / 出参 / 错误码 / 所有者.
- [事件总线信号表.md](事件总线信号表.md) — 所有 EventBus 信号 + 订阅方 + 关键信号链.
- [平衡参数.md](平衡参数.md) — 数值常量集中登记, **真实量纲** (FLOPs / TFLOPs / B tokens / token/s); GPU 表 / 供电表 / 训练模板 / LEAD_BONUS_TABLE / 产品类型阈值 / scaling law 常数 / 用户增长 / 贷款利率 等.
- [NPC配置.md](NPC配置.md) — 23 家 NPC 配置 (5 主榜 + 18 家分榜, 其中 10 家开源); 时间线驱动 (每家 .tres 写整条 release 时间线), NPC 当前能力 = 最新已发布 release 的 capability.
- [事件库.md](事件库.md) — 事件卡牌具体内容.
