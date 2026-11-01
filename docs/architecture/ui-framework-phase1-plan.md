# EmberRoutes UI Framework Phase 1 实施计划
# 阶段一：技术债务彻底出清与核心运行时初建

> 状态：待评审实施方案｜编制日期：2026-11-01  
> 依据：[`ui-framework-architecture-spec.md`](ui-framework-architecture-spec.md) 与 [`ui-framework-current-state.md`](ui-framework-current-state.md)  
> 铁律：先治理、后建设；小步快跑，单任务验证，严禁一次性大范围重写。

---

## 一、阶段一总体目标

1. 彻底解决审计报告揭示的组件孤岛、代码重复与生命周期泄漏隐患；
2. 纠正 `PersonnelPage` 对 `Crafting.watch` 的错位依赖，建立科学的生理健康低频节拍；
3. 将现有 `PageLifecycle` 升级为具备自动收割能力的 `LifecycleScope`；
4. 确保在不破坏任何既有游戏功能的前提下，完成全套单元测试与静态检查闭环。

---

## 二、任务清单与实施状态

```
Phase 1 任务看板
├── [已完成] Task 1.1: PublicOrderDialog 接入标准 StepperInput (消除55行手写步进)
├── [已完成] Task 1.2: ActivityScenarioCard 接入 CardPanel.draw (消除手写背景绘制)
├── [已完成] Task 1.3: PersonnelPage 消除双重 project 冗余调用
├── [已完成] Task 1.4: ActivityDialog 消除双轨制，重构为透明转发 Shim
├── [已完成] Task 1.5: 建设自愈型 TooltipManager 并完成 WarehousePage 等页面简化
├── [待实施] Task 1.6: PersonnelPage 错位监听剥离与聚焦刷新改造 (P0)
├── [待实施] Task 1.7: 升级 PageLifecycle 为 LifecycleScope 自动资源管理器 (P1)
└── [待实施] Task 1.8: 阶段一全量回归测试与质量验收 (P0)
```

---

## 三、待实施任务具体拆解方案

### Task 1.6: `PersonnelPage` 错位监听剥离与聚焦刷新改造 (P0)

- **当前代码位置**：
  - 错位监听：[`Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/PersonnelPage.lua:298-305`](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/PersonnelPage.lua#L298-L305)
  - 轮询计时：[`Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/PersonnelPage.lua:577-580`](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/PersonnelPage.lua#L577-L580)
- **痛点与风险**：
  - `PersonnelPage` 为捕获 `WORLD_RESET` 错误地挂在 `Crafting.watch` 上，导致工单变动频繁触发居民全员重新计算；
  - 周期轮询盲目扫描全体居民的生理健康，违背“可见视口优先”原则。
- **重构方案（闭环三要素）**：
  1. **认领/挂载端**：
     - 在 `activate()` 中，移除对 `Crafting.watch` 的挂接，改用据点核心账本（[`SettlementLedger`](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/SettlementLedger.lua)）的观察句柄，仅在据点重置或成员增减时触发结构级更新；
  2. **正常释放端**：
     - 在 `deactivate()` 中注销定时器和账本观察，切出页面后后台立即完全静止；
  3. **分级刷新执行端**：
     - 在 `update()` 中实施分级节拍：
       - **全局慢节拍 (10s)**：检查据点成员清单与大工种分配；
       - **选中项聚焦快节拍 (3~5s)**：若详情抽屉展开，仅对当前 `store.value.selected` 居民更新其动态生理健康（饥饿、受伤、疲劳），绝不全员无差别重算。
- **验收标准**：
  - 打开居民页面，当前选中 NPC 受伤/疲劳如实动态更新；
  - 切换到其他标签（如仓库）后，控制台打桩证明后台 0 轮询；
  - 生产工单增删不再导致居民页面发生无效重算。

---

### Task 1.7: 升级 `PageLifecycle` 为 `LifecycleScope` (P1)

- **当前代码位置**：[`Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/PageLifecycle.lua`](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/PageLifecycle.lua)
- **痛点分析**：
  - 目前各页面仍需要手动处理子抽屉关闭、本地定时器重置等零散资源；
  - 需要统一的作用域（Scope）收割机，使开发者只需 `scope:add(...)` 即可在 `unmount` 时全自动对称释放。
- **重构方案**：
  1. 保留现有的 `activation token` 异步安全门禁；
  2. 扩展 `Lifecycle.createScope(owner)` 机制：
     ```lua
     local scope = Lifecycle.createScope(self)
     scope:watch(watchFn, callback)
     scope:subscribe(store, callback)
     scope:timer(intervalMs, callback)
     scope:own(childDrawerOrDialog)
     ```
  3. 在 `Lifecycle.unmount(page)` 时，统一遍历 `scope.resources` 自动执行清理，彻底杜绝孤儿定时器与内存黑户。
- **验收标准**：
  - 编写 `tests/lua/lifecycle-scope-test.lua`，断言多次异常打断与正常关闭时，挂载的 Watch、Timer、Child 均 100% 被注销。

---

### Task 1.8: 阶段一全量回归测试与质量验收 (P0)

- **执行清单**：
  1. 静态语法与规则门禁：`node ../.workbuddy/tools/pz.mjs lint Contents/mods/EmberRoutesProbe`，保持 0 错误；
  2. 既有单元测试全集回归：
     - `tests/lua/activity-page-test.lua`
     - `tests/lua/activity-dialog-test.lua`
     - `tests/lua/activity-presentation-test.lua`
     - `tests/lua/tooltip-manager-test.lua`
     - `tests/lua/warehouse-ae2-test.lua`
  3. 输出 Phase 1 验收总结报告与性能对照说明。

---

## 四、排期与执行准则

1. **单项交付原则**：每个 Task 单独修改、单独测试、独立验证，禁止跨任务夹带私货；
2. **零退化原则**：每次重构必须保证原版 ISUI 交互、鼠标滚轮、键盘 Esc 关闭等原生体验 100% 正常；
3. **代码证据前置**：在提交变更前必须出具具体代码行号的 diff 与测试运行通过截图/日志。
