# 清洁需求独立观察与动态监控计划

> 日期：2026-11-02｜状态：继续执行已确认范围；本地顺序实施，不提交/推送。

**Goal:** 无人/缺工具/工种禁用时仍显示可信清洁需求；FIELD 卡片只显示真实适用步骤。

**Architecture:** FieldDemand 在现有 PublicWork 节拍观察源事实，分片核对候选条件；ToolDiscovery 提供只读失败证据。OrderMonitorService 和 FIELD Projector 提供版本化快照，Cards 消费动态步骤，不新增 UI 框架。

**Tech Stack:** PZ Lua/Kahlua、现有 Java 扫描桥、ISUI/Widgets。

**Spec:** [确认设计](../specs/2026-11-02-workflow-domain-boundaries-design.md)。

## Global Constraints

- 仅已加载、有界清洁源观察；PARTIAL/STALE 明示，不伪造全图/forage。
- 不创建空 Job 或申请工具/物品；最终派工仍需原守卫复验。
- 无 NPC 仍观察；角色/优先级/工具独立核对；未知不当缺货。
- UI 订阅标脏、隐藏释放，绘制只读缓存；CN/EN 成对。

## Review Focus

- 0 NPC / 全部优先级0：源事实仍存在，无身体/资源副作用。
- 跨预算或仓库未加载：OBSERVING，不能全局缺工具。
- 已认领目标/目标消失/卸载：分别排除待派计数、删除已证实消失、保留陈旧事实。
- 步骤变化但 phase未变：缓存签名变化；未执行步骤不假完成。
- 世界切换及页面关闭：旧回调不污染新世界，观察不依赖页面存活。

## Task 1：FIELD 动态投影

**Files:** FieldWorkMonitor.lua、UI/OrderMonitorCards.lua、tests/lua/order-monitor-view-test.lua。

**Interfaces:** FIELD row.workflow={viewRevision,steps}；row.stages 为同一只读步骤序列，steps 含 key/labelKey/status/progress；保留其他业务旧显示回退。

- [x] 添加动态步骤签名、显式步骤状态与无产物无货物轨道反例。
- [x] FIELD 从真实准备、作业和原件事实投影；Cards 消费显式状态并签名全部依赖。

## Task 2：独立源观察与条件诊断

**Files:** 新增 FieldDemand.lua，修改 ToolDiscovery.lua、PublicWork.lua、OrderMonitorService.lua；新增 tests/lua/field-demand-test.lua。

**Interfaces:** FieldDemand.advance(actor,now,eligible,priorities) 在现有公共派工内调用；FieldDemand.rows(scopeId) 返回派生快照，发布使用现有 LaborSignals。ToolDiscovery.findSupplies 返回原 plan，并额外返回失败原因/缺失角色，不改变认领 API。

- [x] 测试无人、禁用、缺工具、预算未知、已认领、目标消失/卸载/换世界。
- [x] 实现分片源观察、角色预检及只读卡片；从 workerCount分支前调用，不引入独立 ticker。
- [x] 接入现有 monitor/status/watch；补齐调用契约所需测试替身。

## Task 3：验证

- [x] CN/EN、Kahlua 定向 UI/派工/FIELD/工具回归与双模式编译、结构/类型检查。
- [x] BACKLOG/INDEX/证据登记实际边界；完整候选集中构建，不以宿主冒充实机。

## 执行结果

源码与本批替身/构建检查已执行；发布检查、旧迁移与完整页面夹具仍有失败，不代表全部验收通过。详见[本批证据](../../reviews/2026-11-02/workflow-closure-and-monitor.md)。PZ 实机、性能及总体 B.5 未验收。
