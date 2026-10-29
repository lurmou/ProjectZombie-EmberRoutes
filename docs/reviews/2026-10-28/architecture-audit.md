# 架构一致性与复用审查（静态）

日期：2026-10-28｜类型：静态源码审查，未运行游戏、未跑测试、未构建、未发布。

## 1. 结论

五层架构（HFSM → 效用仲裁 → 统一控制器 → 小型 BT → 原版动作适配）没有被推翻，四条核心不变量仍守住：身体授权单点、移动单点、资产声明单点、保存屏障单点。问题集中在四处：

1. **扩展点分裂**：同一类"可插拔"需求有 7 套互不兼容的注册表/钩子，协调器仍硬编码 `crafting`。
2. **全局数据面**：唯一 ModData 根表含 11+ 业务域，被 53 个文件直接读写，结清判定因此必须认识所有 provider。
3. **层级倒置**：`shared` 记录模块反向依赖 `client` 持久化适配器，且位于资产账本热路径。
4. **重复与死码**：结清逻辑三份、执行管线两份、校验原语 15 份；约 700 行已实现但无生产调用方的模块仍被测试断言。

不建议重写内核；建议按第 7 节顺序做收口，先低风险机械化项，再动结清与数据面。

## 2. 范围与基线

- 工作区：`version.txt` 0.29.14，HEAD `667c7c2`，`git status` 有 346 个改动项；本审查读的是**工作区源码**，不是 HEAD。
- 规模：`Contents/mods/EmberRoutesProbe/42/media/lua` 239 个 Lua 文件、34,866 行；其中 client 191 文件/30,805 行，`UI/` 49 文件/8,791 行。
- 依赖：静态 `require` 边 1,371 条，10 组循环（全部靠函数内惰性 require 维持）：`LogisticsService↔Work`、`CookingService↔PublicWork`、`CookingContext↔CookingWaterSources`、`CookingContext↔CraftStations`、`SelfCareFurniture↔SleepBed`、`LeisureActions↔SocialActions`、`CookingService→SelfCare→TaskResume`、`BusinessJobs→CraftRecord→LaborStore`、`DeliveryService→DeliveryTarget→HaulAgent→Work→WorkAgent`、`CookingService→LeisureService→PublicWork→SelfCare→SelfCareExecution→StudySeat→StudyService`。
- 对照物：[唯一架构 v1.2](../../superpowers/specs/2026-10-22-npc-behavior-architecture-design.md)、[统一任务协议](../../superpowers/specs/2026-10-23-unified-task-dispatch-design.md)、[BACKLOG](../../BACKLOG.md)。
- 方法：全量 require 图、逐文件反模式扫描（动作队列、移动、ModData、Java 桥、观察者）、函数体去重（273 个函数，0 组完全重复）、导出/引用交叉核对。

## 3. 守住的边界（不要在这些地方"优化"掉）

| 不变量 | 证据 |
|---|---|
| 身体授权唯一 | 只有 `TaskController.lua:71` 调用 `Driver.acquireControl`；`Driver.lua:44-46` 是唯一入口 |
| 移动唯一 | `Driver.lua:50-61` `moveControlled` 是唯一实现，只有 `TaskController.lua:78` 调用；全库无 `npc:walkTo/pathTo` 直调 |
| 队列出口受控 | `ISTimedActionQueue.add/clear` 的生产路径集中在 `TaskController.lua:162,171`；其余为 `if body then ... else` 的旧路径兜底 |
| 资产声明唯一 | `LaborClaims` 统一持有 item/surface/capacity；`CookingCapacity.lua:10-22` 复用了同一 capacity 桶，没有另建冷藏账本 |
| 保存屏障 | `TaskRuntime:beginSave/finishSave` + `TaskController` 冻结 + `TaskPersistence` 回执，`Save.candidate` 只按稳定 kind 恢复 |
| UI 状态 | `UI/State.lua` 浅不可变 + 脏键；`UI/PageLifecycle.lua` 用 activation token 拒绝过期回调 |
| 行为树约束 | `BehaviorTree.lua` 校验深度≤8/节点≤128/禁止复用同一节点，`Running` 时禁止 Fallback 换支 |
| 不伪装可用 | `UI/DefensePage.lua:57,79` 明示 previewBadge、按钮 `setEnable(false)` |

## 4. 破坏架构 / 超出架构的功能

### A1 [P1] `shared` 反向依赖 `client`，且在资产热路径

`shared/EmberRoutesProbe/CraftRecord.lua:107-111` 的 `Record.records(root)` 内联 `require('EmberRoutesProbe/BusinessJobs')`——shared 记录模块直接读 client 持久化适配器。调用方是资产权威 `LaborStore.lua:250,253,256,263,291,341`（claim/replace/release/校验），不是测试。

后果：① 依赖方向倒置，shared 在专服/无 `BusinessJobs` 环境直接抛错；② `CraftRecord` 无法脱库单测，必须带整套 Job 存储；③ 与 `BusinessJobs`、`LaborStore` 构成 require 环（`BusinessJobs→CraftRecord→LaborStore→BusinessJobs`）。

建议：`TaskJobs.current()` 已是"唯一存储句柄"（`TaskJobs.lua:6-14`），把记录读取改为由调用方注入的只读迭代器（`LaborStore` 传入）；`CraftRecord` 只保留 `valid/resources` 纯函数。

### A2 [P1] 全局 ModData 根表是共享可变数据面，扩展点没有隔离

`ContainerRegistry.lua:48-62` 返回同一张根表；实际写入的顶层域名包括 `containers/format`、`rules/orders/requests/publicWork`、`deliveryOrders`、`taskJobs`、`taskRoutes`、`executionSave`、`craftSurfaces`、`stockRules`、`entries/workers`。53 个文件直接 `Registry.data()`（`Production`/`CraftProbe`/`TaskPersistence` 各 10 次，`PublicWork` 8 次）。

典型后果是 `BusinessJobs.canRetire`（`BusinessJobs.lua:96-129`）必须硬编码认识 `world.publicWork.orders`、`world.deliveryOrders.orders`、`SELF_CARE.payload.resume`、`LaborStore` 声明和 runtime 状态，才能判断一个 Job 能否结清。也就是说：**新增一个 provider 必须改中心结清代码**，与"各业务只提供候选/前置/适配/恢复"的契约冲突。

建议：为每个域加薄仓储（`Orders.of(scope)`/`Jobs.byId(id)`/`Delivery.of(npc)`），根表只在仓储内可见；`canRetire` 改为向 provider 询问 `canSettle(jobId)`，中心只做"全部为真"的合并。

### A3 [P1] 结清逻辑三份实现，且共享同一段脆弱补偿

- `PublicWork.lua:553-600`：Order 结清（含 `directory:release`、`request` 回执、规则唤醒）。
- `BusinessJobs.lua:130-164`：Job 结清（含把 `SELF_CARE.payload.resume` 置为 `RESTORED`、清 `executionSave.byNpc`）。
- `CookingService.lua:424-457`：COOKING 结清，**再次实现**同一段 resume 解除（`RESTORED`/`INVALIDATED` 语义略有差异）、同样的 `executionSave.byNpc` 清理、同样的 claims/runtime/directory 前置。
- 入口 `TaskRetirement.lua:11-17` 只是顺序调用三者。

这三份的"允许删除"条件互不相同（`canRetire` 还检查 delivery/public order 引用，cooking 版只查 offer 与 SELF_CARE），任何一处漏改都会出现"一边删了 Job、另一边还引用"或反向的永久滞留。

建议：抽 `Settlement` 策略对象：`retire(jobId)` 由 provider 实现 `canSettle + dischargeRefs`，中心统一做排序、预算、`directory:release`、回执与 `Signals.changed`。这段属于"同一任务只能有一个结算者"红线，改动必须配故障用例。

### A4 [P2] Provider 注册表已存在，但协调器仍按 `crafting` 写死

`PublicWorkProviders.lua` 只校验 `category/defaultPriority`（45 行），而真正的派工循环里仍有：
`PublicWork.lua:378`（`waiting` 排除 cooking）、`423/426`（`o.category~='cooking'` 才允许预检）、`473`（reconcile 只处理非 cooking 单）、`675-677`（`priorities.crafting` 为 0 时跳过 grace）、`751`（预检硬要求 `priorities.crafting>0`）。

且 `craftingProvider` 本体（`PublicWork.lua:394-502`，约 110 行）连同 Order 持久化、预检池、`ProductionChain` 调用都留在协调器文件内——`PublicWork` 同时是"工单仓储 + 最低存量策略 + crafting provider + 派工协调器"，794 行。

建议：把 `craftingProvider` 迁到独立文件（照 `CookingProvider.lua` 的先例），把"是否参与扫描/预检/结清"变成 provider 声明字段，删掉调用点上的 category 字面量；`PublicWork` 只保留排序、唯一认领、预算与信号。

### A5 [P2] 两条生产执行管线并存：`CraftProbe`（823 行）与 `Production`（637 行）

二者各自实现同一套骨架：`prepare / tick(nextAction) / deliver / finish / stopAdapter / afterSave / tickPending / status`，都用 `WorkTransfer`+`LaborStore`+`Registry`，都在 `CraftProbe.lua:623` 互相转派（`if Production.busy(id) then Production.tick(id)`）。差别是"单材料单工具的手工单"与"多输入+BOM 链的公共单"。

这属于架构 §3.4 明确允许的"先封装为适配叶、逐步迁移"，但现状是**同一语义存在两套实现**，缺陷修复要改两处；近期的加热、液体与冷藏容量能力都只落在 cooking 模块与 `Production` 侧，`CraftProbe` 没有对应能力。

建议：定义 `Pipeline`（收取 → 站内执行 → 产物交付 → 归还），配方差异走 `RecipeAdapter` 策略；保留 `CraftProbe` 作为薄适配器而不是第二台状态机。迁移放在 P4 收口之后，避免与当前未验证的烹饪改动冲突。

### A6 [P2] 服务注册靠裸 `Probe` 字段：76 个字段、依赖 install 顺序

现存 7 套扩展机制，形状各不相同：

| 机制 | 契约形状 | 校验强度 |
|---|---|---|
| `Probe.*` 字段 | 任意（tick/reset/cancel/hook） | 无，靠 Boot 的固定名单 |
| `PublicWorkProviders.register` | `category/defaultPriority + discover/claim/reconcile/idle/hasWork/advance` | 只校验 category 与优先级 |
| `Work.registerExecutor` | `retains/busy/pause/pauseAll/reset` | 断言 key 唯一 |
| `LaborProducers` | `id + {check, transfer}` 转移策略 | 断言 id 唯一与函数存在 |
| `LeisureRegistry.define` | `id/budget/seek` + 返回协议 | 校验 id/budget/seek，重名拒绝 |
| `UI/PageRegistry.register` | `id/module/titleKey/...` | 断言 id/module |
| `EvenPaused.add` | 无参 tick | 无 |

`Probe` 上共有 76 个不同字段（`tickXxx/resetXxx/cancelXxx/prepareXxx` + 能力钩子 `invalidateCare/careBlocksWork/idleStudy/leisureWorkState/...`）。Boot 用固定字符串列表组装（`Boot.lua:130`）并在 `tickServices`（`Boot.lua:112-128`）里按固定顺序调用；各模块在文件末尾直接赋值（如 `Persistence.lua:299`、`PublicWork.lua:799`、`SelfCare.lua:494-514`）。

已有正确做法可复用：`TaskResume.lua:199-206` 用 `local previous=Probe.taskStopped` 做装饰链，`SelfCare.lua:487-491` 继续包裹。但链式与非链式混用（`Probe.invalidateCare=Resume.invalidate` 是裸赋值），一旦某模块被重复 install 或调整加载顺序，钩子会被静默覆盖；`Boot.lua:86-91` 只能靠 `RUNTIME_MODULES_MISSING` 事后补救。

建议：`ServiceRegistry.register{id, order, tick, reset, beginSave, hooks={...}}`，重复注册直接报错；装饰语义显式化为 `hooks.append('taskStopped', fn)`。收益是可枚举、可断言顺序、可在测试里替换。

### A7 [P3] UI 层不闭合

- 约 10 个 UI 模块放在 `client/EmberRoutesProbe/` 根而非 `UI/`：`SettlementDashboard`(221)、`StorageFilterPanel`(212)、`SettlementMenu`(172)、`StorageTabs`(158)、`NpcDebugMenu`(368)、`MembershipMenu`(222)、`LogisticsMenu`(70)、`ContainerMenu`(43)、`ReposeMenu`(42)、`DebugMenu`(75)。
- UI 直接读 Java 桥：`UI/StockRules.lua:393-394` 用 `EmberRoutesProbeJava.workerCount/workerIdAt` 枚举 NPC，绕过业务投影。
- 页面自己读原生技能：`UI/PersonnelPage.lua:408-464` 每 1.5 秒（`:674-677`）为**全员**读 `getPerkLevel`/健康/职业，再 `setState`（订阅回调已 project）后又显式 `self:project(...)`（`:463`）→ 重复投影，且无视 `PersonnelService.lua:15-45` 已实现的"按 npcId 缓存、`LevelPerk` 失效"懒加载。这是 2026-10-24 审查第 3 条的**未修复项**。

### A8 [P3] 与已批准 UI 架构冲突、但已被记录为待决

架构 §3.3.1/11.x 要求"取消独立配方字典下单页，收敛为仓储点击弹窗 + 原版制作菜单委托"。当前存在完整配方浏览器：`UI/CraftingPage.lua:36-48`（recipes/orders/maintainStock 三视图）→ `UI/CraftingBrowser.lua`（226 行，搜索/分类/分页）→ `UI/CraftingDraft.lua`（569 行）+ `UI/RecipeGrid.lua`，以及 857 行的 `UI/PublicOrderDialog.lua`（多 tab 向导，而非"紧凑步进弹窗"）。

BACKLOG 已记录"用户 2026-10-27 要求重新讨论下单界面，现有实现暂不改"。因此这不是擅自扩张，而是**悬置的架构冲突**：要么在下次 UI 决策时明确保留并修订架构，要么按架构裁剪。当前状态不能同时声称两者。

### A9 [P3] 诊断/夹具代码与生产代码同层

`Actions.lua`(400)、`Haul.lua`(389)、`PersistenceSamples.lua` 直接在 `container:AddItem/Remove`（`Actions.lua:72,97`、`Haul.lua:74,243`），并注册进 `Probe` 常驻 tick。架构 §6 允许诊断，但这些是**第二套可执行路径**，靠 `isDebugEnabled()`/调试菜单分隔，缺少编译期或沙箱开关隔离。建议合并到单一 `Debug` 模块并把夹具动作排除在正式 `Actions` 之外。

## 5. 应复用而未复用

| 编号 | 重复内容 | 位置 | 建议 |
|---|---|---|---|
| B1 | `integer/finite/itemId/stringId` 校验原语 | 15+ 文件各自实现，界值不同：`ContainerRegistry.lua:71`(≤1e7)、`CraftRecord.lua:6`、`JobStore.lua:14`、`ReposeRecord.lua:4`、`SelfCareRecord.lua:7`、`PublicWork.lua:90`、`DeliveryService.lua:10`、`HaulManifest.lua:12`(9007199254740991)… | 抽 `shared/Validate.lua`（`integer(v,min,max)`、`finite`、`stringId`、`itemId`）；记录模块只写字段表 |
| B2 | 单人守卫 | 21 处 `isClient(`（18 处 `isClient() or isServer()`，3 处 `not isClient() and not isServer()`）：`ContainerRegistry.lua:184,211`、`PublicWork.lua:738`、`Persistence.lua:193`… | `RuntimeGate.singlePlayer(actor)` 返回统一 reason，顺带统一 `actor:isDead()` |
| B3 | 步进器 | `UI/PublicOrderDialog.lua:181-233` 手写 `makeStepper` + 两个 onclick，而 `UI/StepperInput.lua`（161 行）**零引用** | 采用 `StepperInput` 或删除它；两者并存是最坏状态 |
| B4 | 优先级编辑 | `UI/PersonnelPage.lua` 内联矩阵编辑，`UI/WorkPriorityDialog.lua`（61 行）**不可达**（`SettlementDashboard.lua:193` 只切页签） | 择一保留 |
| B5 | 网格键位/手柄导航 | `UI/RecipeGrid.lua:68-84`、`UI/WarehouseGrid.lua:299-334`、`UI/CraftingDraft.lua` 各一份 `move/onJoypadDir*` | 抽 `GridNavigator` mixin（纯函数：坐标→索引） |
| B6 | 记录 `valid()` 样板 | `CookingRecord.valid` 约 200 行（`:112-317`）、`SelfCareRecord.valid`（全文 127 行）、`HaulManifest.valid`、`StockRule.validate` 各写一遍字段枚举与上限 | 声明式字段表 + 通用校验器（B1 之上） |
| B7 | 结清/解除引用 | 见 A3 | 见 A3 |
| B8 | 预览 | **已正确复用**：`PublicPreview` → `CraftingService.preview` → `CraftingPreview`，没有第二套 | 保持，作为其它扩展点的范本 |

## 6. 死代码与"测试保活"

| 模块 | 行数 | 状态 |
|---|---|---|
| `shared/EmberRoutesProbe/LiquidRegistry.lua` | 321 | 生产零引用；仅 `sim-warehouse-journey-test.lua:276`、`warehouse-query-test.lua:4` 断言它。固定水源识别实际走 `CookingWaterSources.lua`，`isWaterShutOff` 全库只此一份实现 → 测试给了"该能力可用"的假信号 |
| `client/EmberRoutesProbe/CookingRecovery.lua` | 85 | 仅 `cooking-heat-test.lua:14` 引用 |
| `UI/StepperInput.lua` | 161 | 零引用（见 B3） |
| `UI/Summary.lua` | 69 | 零引用（只被自己 require StatMeter） |
| `UI/WorkPriorityDialog.lua` | 61 | 不可达（见 B4） |

合计约 700 行。建议：删除或接线，二者择一；同时修正引用它们的测试，避免"全套断言通过"掩盖无生产调用。

## 7. 建议顺序（按风险/收益）

1. **零行为变更**：删死码或接线（6）；`Validate`（B1）；`RuntimeGate`（B2）；UI 文件归位（A7 前半）。
2. **低风险结构**：`ServiceRegistry`（A6）；`craftingProvider` 拆文件 + 去 category 字面量（A4）；`CanRetire` 改为 provider 询问（A2 的最小切片）。
3. **需要故障用例**：结清三合一（A3）；仓储边界（A2 完整版）。必须覆盖：暂停持货、UNKNOWN 效果、`reconcile` 后重复通知、保存屏障内结清。
4. **延后**：`CraftProbe`→`Production` 合并（A5），放在 P4 烹饪收口与实机验收之后，避免叠加未验证改动。
5. **需用户决策**：下单 UI 与配方字典页（A8）。

## 8. 未验证边界

- 本轮只做静态阅读与脚本化依赖/引用统计，**未运行 Kahlua 断言、未构建、未进游戏、未做性能采样**；文中的性能影响均为结构推断，不是实测。
- 未复核 Java 侧（27 个源文件）与当前安装 JAR 哈希；`EmberRoutesProbeJava` 的调用分布在 47 个 Lua 文件，只统计了数量与位置，未逐接口核对契约。
- 死代码判定基于静态引用（含测试目录）；若存在运行时字符串拼接 `require`（例如 `require('EmberRoutesProbe/UI/'..module)` 这类动态形式），已单独核对 `PageRegistry`/`Probe` 路径，其余仍可能漏判。
- 循环依赖是否真的在运行期安全，只按"惰性 require 位于函数内"判断，未做加载顺序实测。
