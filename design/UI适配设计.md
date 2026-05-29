# UI适配设计

> **目的**: 让当前主 HUD 对齐已经实现的 13 个系统与静态资源, 把能玩的路径暴露出来, 避免 UI 仍停留在旧的硬编码演示按钮。
> **读者**: 主界面维护者, 以及检查 UI 是否覆盖现有系统能力的人。
> **状态**: 🟢 已对齐 13 系统; 主 HUD 已是侧栏 Dashboard + 卡片墙 (视觉骨架见 `UI视觉系统设计.md`), 9/13 tab 迁卡片化 view。

---

## 1. 设计目标

- 主 HUD 程序化构建, 已采用侧栏 Dashboard + 卡片墙骨架; 多数 tab 迁到 `scenes/ui/views/` 下的独立 view, 服务调试与纵切试玩。
- UI 读 `GameState`, 写操作全部走 `CommandBus`, 状态变化通过 `EventBus` 触发刷新。
- 入口覆盖已实现系统的真实命令, 尽量从 `.tres` 静态资源读显示名、数值与可解锁内容, 少写固定按钮。
- UI 文案遵守化名规范, 不出现真实品牌或真实模型名。
- 所有“创建新东西”的主入口统一做成醒目的 `create` CTA: 模型页「训练新模型」、基建页「新建数据中心」、产品页「创建产品」、数据页「开始采集」、营销页「新建活动」都应明显强于同页普通操作, 但保持内容宽不铺满整屏。

---

## 2. 本轮适配范围

### 2.1 顶栏与刷新

顶栏展示回合、现金、周净流、总榜排名、付费用户、算力。周净流以经济系统 `weekly_ledger` 净额为准 (账本已滚入历史时改读 `ledger_history[0]` 快照); 同一回合内多次刷新须幂等显示同一净额, 不退化成 cash delta。v7 PR-F 后 `fame` 字段与 `fame_changed` 信号已删除, 主 HUD 不订阅旧信号, 排名刷新依赖 `leaderboard_resolved` / `player_rank_changed`。主 HUD 订阅所有影响可见状态的事件。

**回合推进刷新合并 (2026-05)**: `TurnManager.advance()` 一周内会同步连发多类事件 (扣费、任务进度、排行榜、用户、营收、账本等)。这些事件仍必须保持业务顺序与完整发出, 但 `Main` 不应在每个中间事件上立刻重建所有 tab。推进中 (`TurnManager.is_advancing() == true`) 的 HUD 刷新请求只置 dirty 标记; 到 `turn_resolved` 时统一 `_refresh()` 一次。非推进中的玩家操作、读档、对话框命令仍即时刷新, 保持 UI 反馈直接。

玩家点击按钮后, `_call()` / `_report()` 除了写状态条, 还要依赖信号触发刷新。若某命令已经发出对应信号, UI 不需要额外写状态。

### 2.2 模型 tab

模型 tab 是模型训练系统 (`ResearchSystem`) 与模型生命周期任务的入口, 只管理玩家自训模型, 不提供"下载开源模型"。卡片动作按钮随模型状态变化 (未评估态可评估 / 后训 / 删除, 已评估态加发布, 已发布态改价 / 下架), 具体映射以 `model_view` 代码为准。

`开始评估` 直接启动 `task.start` 的 `evaluate_general` 模板 (MVP 一键启动, 不强制选数据中心 / 数据集; 完整评估对话框后续补)。

模型卡片显示状态、架构、参数量、模态、能力 (未评估显示 `??`, `capability_stale` 附"评估已过期"提示)、API 单价与改价快捷按钮、已部署数据中心与已绑定产品列表。

`训练新模型` 对话框 (`PretrainDialog`) 按 4 轴 (架构 / 注意力 / 损失 / 上下文, 各取已解锁科技节点) + 参数量选择。`task.preview` 返回的 `modifier_breakdown` 要在对话框里显式展示各项 buff/debuff。

### 2.3 基建 tab

基建 tab 从 `InfraSystem` 的 facility / GPU / 供电 `.tres` 渲染卡片: 机房卡显示规模 / 容量 / 租金 / 自建工期与成本; GPU 加卡按已上市型号显示单价与算力 (买卡支持 idle/training/serving, 卖卡仅 idle)。部署目标分"我的已发布模型"与"公共开源模型"两组, 公共开源 release 部署时会自动物化为 downloaded_os published model, 因而产品页随后能看到对应 API。

### 2.4 数据 tab

数据 tab 从数据集 `.tres` 扫描市场: 开源模板可"获取", 商业模板显示价格可"购买", 已拥有的进"我的数据集"。市场与我的数据集都用 `Card` 卡片墙渲染, 动作按钮与对应数据集留在同一卡片内, 卡片在 `HFlowContainer` 折行 (1280×720 下约 3 列)。

### 2.5 科技 tab

科技 tab 通过 `tech.list_available` + `TechTreeSystem.get_node_template()` 渲染可研究节点 (显示名 / 效果摘要 / 成本 / 时长 / 状态)。启动研究走 `tech.start_research`; v6 PR-D 起「研究」按钮打开 `ResearchDialog` 让玩家选 lead + 研究员 + 工程师 + datacenter, 校验通过才发命令 (详见 [科技树系统设计.md §5.2](科技树系统设计.md))。

### 2.6 产品 tab

产品 tab 用 `product.list_unlocked_types` 渲染可创建产品类型, 创建时默认绑定首个已发布模型与该类型默认订阅价; lead / staff 可选 (ProductSystem 支持无 lead)。已上线产品提供下架与改价快捷按钮。算力池指标用紧凑 token/s 格式。产品创建 / 编辑对话框须能被 `main.gd` preload 干净编译, helper 用显式 Resource 类型避免 GDScript 4 启动推断失败。

### 2.7 其他 tab

经济、招聘、市场、营收、事件 tab 以状态展示与已有快捷命令为主, 补齐刷新订阅与显示细节即可。营销 tab 已迁到卡片化 `marketing_view` (campaign 卡片 + 新建活动入口)。

---

## 3. 验收标准

- 主 HUD 的 tab 仍覆盖 13 个系统, 且模型 tab 名为「模型」。
- 模型卡片在 `pretrained` / `posttrained` 状态显示并能触发"开始评估"。
- 数据 tab 从静态数据集模板渲染按钮, 至少能看到多个市场模板。
- 基建 tab 使用资源显示名渲染机房与 GPU, 不再只显示内部 id。
- 科技 tab 显示可研究节点的 `effects_summary`。
- 产品 tab 只显示当前确实解锁的产品类型创建按钮。
- 集成测试覆盖上述行为, 单测与集成测试通过。

---

## 4. 未决问题 / TODO

- posttrain / evaluate / data_collection / tech_research 仍需要专门对话框; posttrain/evaluate 也要显示 preview buff/debuff。
- 基建的完整租/建机房弹窗要允许选择 13 档机房与 5 种供电方式。
- 产品创建/编辑需要正式表单, 支持选择模型、lead、staff、价格与名称。
- 主 HUD 未来应拆分为多个 UI 子场景, 但当前纵切阶段先保持一个文件便于快速调试。
