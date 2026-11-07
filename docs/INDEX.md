# EmberRoutes 全局架构地图与任务路由表
# (Architecture Map & Task Routing Hub)

> 更新：2026-11-06｜版本：v2.0.0 (五层 AI 工程上下文体系规范版)
> 遵循规范：[docs/architecture/ai-engineering-context-system-spec.md](architecture/ai-engineering-context-system-spec.md)
> 定位：Layer 2 全局导航中枢。**AI 在承接任何开发任务前，必须首先查阅本页的《核心任务路由表》**。

---

## 1. 核心准则与最高红线 (Layer 1 宪法索引)

| 文档 | 职责与最高约束 |
|---|---|
| [AGENTS.md](../AGENTS.md) | **项目最高宪法**：专注单人模式、完全不要兼容代码与转发壳、资产唯一权威、UI 零 GC 与生命周期铁律 |
| [anti-patching.md](../.agents/rules/anti-patching.md) | **反打补丁铁律**：严禁掩盖问题，必须自上而下追踪至数据模型与职责源头，方案权衡前置 |
| [code-grounding-and-anti-sycophancy.md](../.agents/rules/code-grounding-and-anti-sycophancy.md) | **代码证据前置与反谄媚**：无行号不结论，必须出具创建认领、正常释放、异常打断闭环三要素代码位置 |
| [provider-lifecycle.md](../.agents/rules/provider-lifecycle.md) | **工种生命周期铁律**：契约绝对一致、身体控制单点受控、原件责任四阶段闭环、零虚构降级、释放对称 |
| [DECISIONS.md](../DECISIONS.md) | **核心架构决策日志**：DEC-001 ~ DEC-005 单一事实源与技术分工裁决 |

---

## 2. 系统分层与物理目录拓扑 (System Topology)

代码已全面完成**领域物理目录归拢**（根目录 0 平铺文件），源码分为 `shared`（跨端公共数据模型与规则）与 `client`（客户端独占执行与表现）：

```text
media/lua/
├── shared/EmberRoutesProbe/          # 跨端公共领域层（数据模型、账本、规约）
│   ├── Kernel/                       # 底层调度总线、时间轮、全局工具 (Boot, Log, TaskDirectory, LaborStore)
│   ├── Settlement/                   # 据点几何、领地与成员策略
│   ├── Work/                         # 工种契约、工单数据结构、调度选择器
│   ├── Warehouse/                    # 仓库度量、查询、分类与过滤规则
│   ├── Hauling/                      # 搬运工单与货单数据模型 (HaulJobRecord, HaulManifest)
│   ├── Cooking/                      # 烹饪账本、热量/水资源预算与配方定义
│   ├── Crafting/                     # 制造配方事实、流体与材料模型
│   ├── Field/                        # 农业、伐木、采集的地块与产物记录
│   ├── Activity/                     # 日程、出勤与生活阶段记录
│   ├── Leisure/                      # 闲暇规则与姿态配置
│   └── SelfCare/                     # 医疗、自理与睡眠床位记录
│
└── client/EmberRoutesProbe/          # 客户端执行与表现层（控制器、服务、动作）
    ├── UI/                           # 【表现层】仪表盘、Widgets、卡片、小队 HUD
    ├── Runtime/ & Kernel/            # 【驱动层】身体独占控制器 (Driver, TaskController, TaskRuntime)
    ├── Settlement/                   # 【业务层】据点成员生命周期、小队服务 (SquadService)
    ├── Work/                         # 【调度层】统一工种发现器 (PublicWorkProviders)、工单流水
    ├── Warehouse/                    # 【仓储层】跨容器索引器 (WarehouseIndex)、货架定位器
    ├── Logistics/                    # 【物流层】配送流水线 (DeliveryFlow, LogisticsService)
    ├── Hauling/                      # 【搬运层】搬运状态机与身体动作执行 (Haul, HaulAgent)
    ├── Cooking/                      # 【烹饪层】厨房设施、供水供热与备餐执行
    ├── Crafting/                     # 【制造层】工作台交互、配方执行与产物交付
    ├── Field/                        # 【野外层】农田打理、砍树、采集与产物入仓
    ├── Activity/                     # 【活动层】日程事件泵、场景剧本与出勤仲裁
    ├── Leisure/                      # 【闲暇层】散步、吸烟、健身、坐姿休息动作
    ├── SelfCare/                     # 【自理层】卧床睡眠、急救包扎、自主进食执行
    └── Integration/                  # 【适配层】第三方模组桥接与原生环境适配
```

### 依赖流向单向铁律
$$\text{UI (表现)} \longrightarrow \text{Domain Services (业务)} \longrightarrow \text{Kernel / Runtime (底层驱动与存储)}$$
* **严禁反向依赖**：底层或业务域严禁 `require "EmberRoutesProbe/UI/..."`；
* **严禁越权控制身体**：全库仅允许通过 `TaskController` / `Driver` 获取身体独占授权，严禁业务服务直调 `ISTimedActionQueue.add`。

---

## 3. 核心任务路由表 (Task Routing Table)

> **AI 开发第一步**：根据用户任务意图，在下表中查找匹配项，**优先加载对应的 L3 契约文档与核心源码**，杜绝盲目漫游全库。

| 开发任务意图 | 目标物理领域 | 必读契约文档 (L3) | 核心代码入口 (Code Grounding) | 必测用例与工具 (L5) |
| :--- | :--- | :--- | :--- | :--- |
| **新增/修改工作工种**<br>(Provider) | `Work/`<br>`Kernel/` | [provider-lifecycle.md](../.agents/rules/provider-lifecycle.md)<br>[domains/work.md](domains/work.md) | `client/.../Work/PublicWorkProviders.lua`<br>`client/.../Work/LaborStore.lua` | `KahluaLaborTest`<br>`tools/audit-npc-control.mjs` |
| **调整仓储与物流配送**<br>(Warehouse & Delivery) | `Warehouse/`<br>`Logistics/` | [domains/logistics.md](domains/logistics.md)<br>[仓储架构](settlement-storage-architecture.md) | `client/.../Warehouse/WarehouseIndex.lua`<br>`client/.../Logistics/DeliveryService.lua` | `tests/lua/warehouse-*-test.lua`<br>`tests/lua/storage-panel-test.lua` |
| **修改搬运状态机与货单**<br>(Hauling) | `Hauling/` | [domains/logistics.md](domains/logistics.md)<br>[领域收敛设计](superpowers/specs/2026-11-04-domain-layout-design.md) | `client/.../Hauling/Haul.lua`<br>`client/.../Hauling/HaulJobs.lua` | `tests/lua/work-transfer-*-test.lua`<br>`tests/lua/batch-test.lua` |
| **修改烹饪/厨房/水源加注**<br>(Cooking & Water) | `Cooking/` | [domains/cooking.md](domains/cooking.md)<br>[P4 烹饪设计](superpowers/specs/2026-10-26-p4-cooking-and-supervision-design.md) | `client/.../Cooking/CookingActions.lua`<br>`client/.../Cooking/CookingService.lua` | `tests/lua/cooking-*-test.lua` |
| **工坊制造与递归生产**<br>(Crafting & Production) | `Crafting/` | [domains/crafting.md](domains/crafting.md)<br>[递归生产链设计](superpowers/specs/2026-10-22-production-chain-design.md) | `client/.../Crafting/CraftingService.lua`<br>`client/.../Crafting/CraftStations.lua` | `tests/lua/crafting-*-test.lua` |
| **调整农林与野外采集**<br>(Farming/Forage/Tree) | `Field/` | [domains/field.md](domains/field.md) | `client/.../Field/FieldOperations.lua`<br>`client/.../Field/FarmingProvider.lua` | `tests/lua/field-*-test.lua` |
| **修改日程排班与集会事件**<br>(Activity & Schedule) | `Activity/` | [domains/activity.md](domains/activity.md)<br>[社区活动设计](superpowers/specs/2026-10-28-a3-a4-community-activities-design.md) | `client/.../Activity/ActivityService.lua`<br>`client/.../Activity/ActivityPump.lua` | `tests/lua/activity-*-test.lua` |
| **生理自理、医疗与睡眠**<br>(SelfCare & Sleep) | `SelfCare/`<br>`Leisure/` | [domains/selfcare.md](domains/selfcare.md) | `client/.../SelfCare/SelfCare.lua`<br>`client/.../SelfCare/MedicalCare.lua` | `tests/lua/study-ui-boundary-test.lua` |
| **调整据点成员与生活区**<br>(Settlement & Zones) | `Settlement/` | [domains/settlement.md](domains/settlement.md)<br>[据点归属设计](superpowers/specs/2026-10-25-npc-settlement-membership-design.md) | `client/.../Settlement/MembershipLifecycle.lua`<br>`shared/.../Settlement/SettlementGeometry.lua` | `tests/lua/membership-*-test.lua` |
| **小队跟随与战术 HUD**<br>(Squad & Companion) | `Settlement/`<br>`UI/` | [小队跟随设计](superpowers/specs/2026-11-05-companion-squad-follow-design.md)<br>[小队 HUD 设计](superpowers/specs/2026-11-06-squad-command-ui-design.md) | `client/.../Settlement/SquadService.lua`<br>`client/.../UI/SquadHUD.lua` | `tests/lua/squad-*-test.lua`<br>`java/.../FollowLocomotionTest.java` |
| **修改或开发 UI 页面**<br>(UI & Widgets) | `UI/` | [前端设计方向](architecture/frontend-design-principles.md)<br> [domains/ui.md](domains/ui.md)<br>[UI 运行时规范](architecture/ui-framework-architecture-spec.md) | `client/.../UI/SettlementDashboard.lua`<br>`client/.../UI/CachedList.lua` | `tools/test-ui-kahlua.ps1`<br>`tests/lua/settlement-overview-ui-test.lua` |
| **修改底层驱动与身体控制**<br>(Driver & Controller) | `Runtime/`<br>`Kernel/` | [domains/kernel.md](domains/kernel.md)<br>[原生位移设计](superpowers/specs/2026-11-05-native-npc-movement-design.md) | `client/.../Runtime/Driver.lua`<br>`client/.../Runtime/TaskController.lua` | `tests/lua/task-controller-test.lua`<br>`tests/lua/task-driver-control-test.lua` |
| **新增/修改双语翻译文本**<br>(Translate & i18n) | `Translate/` | [architecture/i18n-invariants.md](architecture/i18n-invariants.md) | `shared/Translate/CN/IG_UI.json`<br>`shared/Translate/EN/IG_UI.json` | `python tools/check-i18n.py`<br>`tools/build-probe.ps1` |

---

## 4. 模块职责与数据权威矩阵 (Module Authority Matrix)

| 领域模块 | 核心职责 | 持久化数据权威 (Single Source of Truth) | 严禁行为 (Anti-Patterns) |
| :--- | :--- | :--- | :--- |
| **Kernel / Runtime** | 物理身体独占控制、任务生命周期分发、心跳轮询 | `TaskJobs` / `JobStore` / `ExecutionSessions`（Job与会话分开） | 严禁跳过授权直接向 `ISTimedActionQueue` 塞动作 |
| **Settlement** | 据点边界、生活子区、成员资格与床位分配 | `SettlementLedger.data()` / `MembershipService` | 严禁无据点归属的角色执行据点公共维护 |
| **Work** | 公共工作工单管理、工种可用性判定与候选派发 | `LaborStore.lua`<br>`JobStore.lua` | 严禁不具备工具/地块条件时伪造完成 |
| **Warehouse** | 跨容器物品读写、空间度量、分类规则过滤 | `ContainerRegistry` / `StorageFilter`配置与世界容器实体 | 严禁未申请认领（Claim）直接扣减/传送物品 |
| **Logistics / Haul**| 物流需求呼叫、货单生成、物理搬运执行 | `HaulJobRecord.lua`<br>`HaulManifest.lua` | 严禁产物滞留个人背包；动作结束不等于结清 |
| **Cooking** | 厨房监管、食谱计算、水源与热量供给 | `CookingRecord.lua` | 严禁无水源/容器时虚构产物 |
| **Field** | 农作物打理、成熟收获、树木砍伐、野外采集 | `FieldRecord.lua`<br>原生植物/树木实体 | 严禁砍倒树后直接标记 DONE（木材必须交付入库） |
| **Activity** | 社区集会、角色轮值、场景剧本与出勤仲裁 | `ActivityRecord.lua` | 严禁强制打断正在进行的紧急自理/重伤治疗 |
| **Leisure** | NPC 闲暇行为（吸烟、看书、闲聊、散步） | `SelfCareRecord`中的闲暇事实 + 瞬态观察 | 严禁在有紧急工作或警报时强行占用身体 |
| **SelfCare** | 饥饿进食、重伤卧床急救、疲劳睡眠 | `SelfCareRecord.lua`<br>角色原生健康状态 | 不得用睡眠动画代替姿态准入与真实需求效果证据 |
| **UI** | 纯只读数据投影、用户操作意图提交 | **无业务数据权威**（消费Service；显示偏好由专用服务保存） | 严禁直接写入 ModData；严禁在 render 阶段分配 table |

---

## 5. 现行架构规格与历史档案索引 (Specs & Plans)

### 5.1 NPC 行为与任务基础设施
- [统一任务调度协议 (2026-10-23)](superpowers/specs/2026-10-23-unified-task-dispatch-design.md)
- [Phase 3A 任务标准化主规格 (2026-10-31)](superpowers/specs/2026-10-31-phase3a-job-contract-standardization-design.md)
- [工作流领域边界拆分设计 (2026-11-02)](superpowers/specs/2026-11-02-workflow-domain-boundaries-design.md)
- [领域目录与 Java 桥收敛设计 (2026-11-04)](superpowers/specs/2026-11-04-domain-layout-design.md)
- [原生 NPC 位移执行设计 (2026-11-05)](superpowers/specs/2026-11-05-native-npc-movement-design.md)
- [能力闭环逐项补全设计 (2026-11-05)](superpowers/specs/2026-11-05-capability-closure-design.md)

### 5.2 小队与随从系统
- [小队跟随核心设计 (2026-11-05)](superpowers/specs/2026-11-05-companion-squad-follow-design.md)
- [小队 HUD 命令交互设计 (2026-11-06)](superpowers/specs/2026-11-06-squad-command-ui-design.md)

### 5.3 据点业务与领域系统
- [据点归属设计 (2026-10-25)](superpowers/specs/2026-10-25-npc-settlement-membership-design.md)
- [仓储配送重构设计 (2026-10-27)](superpowers/specs/2026-10-27-delivery-rebuild-design.md)
- [P4 烹饪与设施监管设计 (2026-10-26)](superpowers/specs/2026-10-26-p4-cooking-and-supervision-design.md)
- [P3 人员研习设计 (2026-10-24)](superpowers/specs/2026-10-24-p3-personnel-study-design.md)
- [P3.5 闲暇与社交设计 (2026-10-24)](superpowers/specs/2026-10-24-p3.5-leisure-social-fitness-design.md)
- [社区活动设计 (2026-10-28)](superpowers/specs/2026-10-28-a3-a4-community-activities-design.md)

### 5.4 UI 基础设施与仓储底层
- [LayoutHost 与仓储工具栏试点证据](reviews/2026-11-07/layout-host.md)：显式叶子适配、求解/应用失败重试、原生 CN/EN 截图；旧仓储测试失败与实机差额分别记录。
- [声明式布局 Phase 1 收口证据](reviews/2026-11-07/declarative-layout.md)：固定根归属、统一销毁、136 项安装版 Kahlua 定向检查及最终构建；原生与性能未验证。
- [全项目前端视觉与交互设计方向](architecture/frontend-design-principles.md)：适用于所有界面，基础交互与视觉验收不后置。
- [原版 UI 实时调试工具](tools/native-ui-preview.md)：真实控件/页面源码、保存自动重建、鼠标定位与同代截图；业务夹具、输入/中文/像素一致性边界见说明。
- [UI 表现层领域契约 (Layer 3)](domains/ui.md)
- [UI 运行时框架规范](architecture/ui-framework-architecture-spec.md)
- [据点 UI 收敛主规格 (2026-11-05)](superpowers/specs/2026-11-05-ui-consolidation-design.md)
- [仓储读取基础架构](settlement-storage-architecture.md)
- [国际化双语闭环铁律](architecture/i18n-invariants.md)

### 5.5 活跃实施计划
- [声明式布局后续任务与最终方案（待确认）](superpowers/plans/2026-11-07-declarative-layout-followup.md)：Phase 1 收口、Host 显式适配、仓储工具栏试点与验收；Phase 2 接口待确认，尚未实施。
- [工程上下文校准](superpowers/plans/2026-11-06-context-calibration.md)：现行契约/手册/静态门禁已对齐，见[0.29.54检查与失败边界](reviews/2026-11-06/context-calibration.md)。
- [能力缺口补全计划 (2026-11-05)](superpowers/plans/2026-11-05-capability-gap-closure.md)
- [小队跟随实施计划 (2026-11-05)](superpowers/plans/2026-11-05-companion-squad-follow.md)
- [小队 HUD 基础计划 (2026-11-06)](superpowers/plans/2026-11-06-squad-hud-foundation.md)
