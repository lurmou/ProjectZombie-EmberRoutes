# EmberRoutes UI Framework Phase 1 实施计划 (修正版)
# 阶段一：技术债务出清与轻量运行时基石落地

> 状态：基于 Post Phase 0 Review 修正方案｜修订日期：2026-11-01
> 依据：[`ui-framework-architecture-spec.md`](ui-framework-architecture-spec.md)、[`ui-framework-current-state.md`](ui-framework-current-state.md) 与 [`ui-framework-phase1-review.md`](ui-framework-phase1-review.md)
> 铁律：反谄媚、代码证据前置、三要素闭环；单任务验证，严禁跨任务夹带私货。

---

## 一、阶段一总体目标与调整后原则

1. **先治理后建设**：彻底解决 TooltipManager 的生命周期闭环缺陷，纠正新组件违反零 GC 规范的问题；
2. **所有权先于调度**：必须先建立 `LifecycleScope`（区分 ActivationScope 与 PageLifetimeScope），再接入 `RefreshScheduler`，确保所有定时任务具备清晰的销毁责任人；
3. **实事求是解耦**：严禁未经源码求证将 `Crafting.watch` 替换为 `SettlementLedger`；三级分离居民名册（事件）、静态档案（缓存）与动态生理健康（聚焦快节拍）；
4. **全套自动化测试闭环**：每个任务必须伴随专门的测试用例，全生命周期断言验证。

---

## 二、调整后的任务看板

```
Phase 1 任务看板 (修正版)
├── [已完成] Task 1.1: PublicOrderDialog 接入标准 StepperInput (消除55行手写步进)
├── [已完成] Task 1.2: ActivityScenarioCard 接入 CardPanel.draw (消除手写背景绘制)
├── [已完成] Task 1.3: PersonnelPage 消除双重 project 冗余调用
├── [已完成] Task 1.4: ActivityDialog 消除双轨制，重构为透明转发 Shim
├── [已实施] Task 1.5A: TooltipManager 架构修正与双层生命周期对齐 (P0 - 核心重构与仓储补丁完成)
├── [待实施] Task 1.5B: 新组件 Static Draw 零 GC 规范合规化 (P1)
├── [待实施] Task 1.6: LifecycleScope 双层作用域基础设施落地 (P0)
├── [待实施] Task 1.7: RefreshScheduler 统一调度器建设 (P0)
├── [待实施] Task 1.8: PersonnelPage 刷新重构与数据模型三级解耦 (P0)
└── [待实施] Task 1.9: 阶段一全量回归测试与质量验收 (P0)
```

---

## 三、待实施任务具体拆解方案

### Task 1.5A: TooltipManager 架构修正与双层生命周期对齐 (P0 - 已实施，完成收尾补丁)
- **代码位置**：[`Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/TooltipManager.lua`](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/TooltipManager.lua)
- **痛点分析**：
  1. `clearOwner` 仅将 `registry[widget].owner` 置空，未移除条目，产生强引用内存泄漏；
  2. `clearOwner` 抹除 `owners[owner]`，但 ISUI 控件切页不重新走 `createChildren()`，导致再次激活后失去所有权追踪，产生不可清理的“幽灵 Tooltip”；
  3. L127-158 充斥仓库、居民页面的硬编码业务字段，破坏框架通用性。
- **重构方案（闭环三要素）**：
  1. **职责正交拆分**：
     - `Manager.dismissOwner(owner)`：页面切出（`deactivate`）调用，仅将当前处于 visible 状态的 tooltipUI 设为 false，保留注册表与所有权关系；
     - `Manager.unregisterOwner(owner)`：页面真正注销（`dispose`）调用，彻底清空 `owners`、从 `registry` 移除、还原原生 hook；
  2. **消除业务硬编码与通用祖先链追踪**：移除 `owner.details` 等特例属性判断，改由通用所有权链递归或显式 owner 登记；
  3. **PZ Kahlua 运行时兼容**：使用 `pairs` 代替不存在的全局 `next` 进行空表安全检测；
  4. **收尾补丁落地**：
     - `WarehousePage:deactivate()` 接入 `cartDrawer:dispose()`，并在 `dispose()` 中完整对称释放；
     - `WarehousePage` 的 4 个原生物理控件（自动划区、帮助、购物车、容器汇总按钮）显式调用 `Tooltip.attach(..., "prerender", self)`。
- **验收标准与落地证据**：
  - `tests/lua/tooltip-manager-test.lua`（47 项生命周期回归断言 + Section 16 仓储抽屉与控件反复切换集成测试，全部通过）；
  - JVM `tests/java/KahluaUiTextTest.java` 跑通真机 Kahlua 虚拟机验证；
  - `tests/lua/delivery-cart-test.lua` 断言 `WarehousePage:deactivate()` 触发 `cartDrawer:dispose()` 且清理引用。

---

### Task 1.5B: 新组件 Static Draw 零 GC 规范合规化 (P1)
- **代码位置**：
  - 看板组件：[`Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/ActivityAtmosphereBoard.lua`](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/ActivityAtmosphereBoard.lua)
  - 页面行绘制：[`Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/ActivityPage.lua:579`](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/ActivityPage.lua#L579)
- **痛点分析**：
  - 绘制循环内每帧分配 table（如 `{ r = 0.25, g = 0.75, b = 0.45, a = 1 }`）、每帧拼接字符串、每帧调用 Java JNI `getTextManager():MeasureStringX`；
  - 在 Draw 函数内调用 `getGameTime():getWorldAgeHours()` 实时计算进度条百分比，违反 Presentation 职责边界。
- **重构方案**：
  1. 颜色常量全部收口到 `Theme.lua` 静态常量令牌（如 `Theme.status.READY`, `Theme.activity.GATHERING` 等）；
  2. 文本拼接与时间差计算前置到 `ActivityPresentation.lua` ViewModel 派生快照中；
  3. 文本宽度调用 `UICache` 预先测量并存储在 row 数据模型中；
  4. `ActivityPage.drawRow` 的状态标签接入标准 `SemanticBadge.draw`，消除手写 `drawRect`。
- **验收标准**：
  - 编写 `tests/lua/atmosphere-board-zero-gc-test.lua`，静态断言与运行时 mock 拦截证明 `drawStrip` 与 `drawResidentCard` 执行过程中 0 次 table 分配、0 次 JNI 测量。

---

### Task 1.6: LifecycleScope 双层作用域基础设施落地 (P0)
- **代码位置**：[`Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/PageLifecycle.lua`](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/PageLifecycle.lua)
- **架构设计（双层生命周期）**：
  1. **`ActivationScope`（切页会话生命周期）**：
     - 随 `page:activate()` 创建，随 `page:deactivate()` 销毁；
     - 托管：Service Watch 订阅、Scheduler 周期任务、临时 Modal / 抽屉关闭、Tooltip Dismiss；
     - 异步门禁：持有当前 `activation token`，任何异步结果在 token 过期后直接丢弃；
  2. **`PageLifetimeScope`（页面实例生命周期）**：
     - 随 `page:initialise()` 创建，随 `page:dispose()` 销毁；
     - 托管：子控件所有权、Tooltip 注册引用（Unregister）、本地 Store 实例；
  3. **契约 API**：
     ```lua
     local scope = PageLifecycle.createActivationScope(page)
     scope:watch(watchFn, callback)
     scope:schedule(cadence, taskFn)
     scope:own(childDrawerOrModal)
     scope:dispose()
     ```
- **验收标准**：
  - 编写 `tests/lua/lifecycle-scope-test.lua`，验证页面切出时 Watch 立即注销、Scheduler 停止；再次切入时可重新注册，销毁时资源彻底清空。

---

### Task 1.7: RefreshScheduler 统一调度器建设 (P0)
- **新文件**：`Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/Scheduler.lua`
- **核心规约**：
  1. **三级节拍**：
     - `FAST = 3000`（3秒：视口内选中实体的高频动态生理健康采样）；
     - `SLOW = 10000`（10秒：列表慢速同步与版本巡检）；
  2. **可见性门禁**：
     - 每次调度前检查 `owner.active` 与 `owner:getIsVisible()`，未激活或隐藏页面**绝对静止**；
  3. **Dirty 合并**：
     - `Scheduler.markDirty(key, batchFn)`，将同一帧内多次事件通知合并为下一渲染帧前单次派发；
  4. **错误隔离**：
     - 单次任务 `pcall` 执行，抛错自动退避，不影响其他调度任务与主循环。
- **验收标准**：
  - 编写 `tests/lua/scheduler-test.lua`，验证合并派发、未激活静止、错误隔离断言通过。

---

### Task 1.8: PersonnelPage 刷新重构与数据模型三级解耦 (P0)
- **代码位置**：
  - [`UI/PersonnelPage.lua`](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/PersonnelPage.lua)
  - [`PersonnelService.lua`](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/PersonnelService.lua)
- **痛点与事实**：
  - 严禁假借 `SettlementLedger`（不感知居民变动与 WORLD_RESET）；
  - `enrichWorkers` 每 5 秒对全体居民进行 Java JNI body damage 与 4 项 CharacterStat 深度扫描。
- **重构方案**：
  1. **数据三级解耦**：
     - **名册结构 (Level 1)**：通过 `MembershipService` 与 `PublicWork` 驱动，事件触发；
     - **静态技能档案 (Level 2)**：利用 `PersonnelService` 内部闭包 `cache[id].value`（由内部 `static(handle)` 产出）永久缓存，LevelPerk 或角色研习完成时按需置脏；
     - **动态健康生理 (Level 3)**：
       - 列表项仅展示极轻量的标量健康标记，不进行全员深度 JNI 扫描；
       - `PersonnelPage` 主页面右侧具有常驻的生理检查器（Physiological Inspector，`self.info`），因此在页面处于激活状态且有居民选中（`selected`）时，通过 Scheduler FAST 节拍（3~5s）采样当前选中居民的生理指标（生命值、流血、感染、饥饿、口渴、疲劳等）；
       - 当详情抽屉（DossierDrawer）进一步展开时，通过 `PersonnelService.details` 采样心情（Mood: STRESS/UNHAPPINESS/BOREDOM/PANIC）与日常日程（Study/Leisure）；
       - 页面切出（`deactivate`）时完全停止一切采样。
  2. **调度接入**：
     - 移除 `PersonnelPage:update` 中的 `self.nextSyncCheck` 手写轮询；
     - `ActivityPage` 的 1 秒 `Service.revision` 轮询统一接入 Scheduler SLOW 节拍；
     - 页面 `deactivate` 时由 `ActivationScope` 自动暂停采样。
- **验收标准**：
  - 编写 `tests/lua/personnel-refresh-test.lua`，断言主页面仅对当前聚焦居民进行生理采样；无聚焦或切页后后台 0 采样。

---

### Task 1.9: 阶段一全量回归测试与质量验收 (P0)
- **执行清单**：
  1. 静态语法与代码门禁：`node ../.workbuddy/tools/pz.mjs lint Contents/mods/EmberRoutesProbe`，保持 0 错误；
  2. 文档断链检查：`node ../.workbuddy/tools/pz.mjs doclink docs/architecture/ui-framework-phase1-review.md` 等相关文档 0 断链；
  3. 全量单元测试（新旧全部通过）；
  4. 输出阶段一实施与质量复核报告。
