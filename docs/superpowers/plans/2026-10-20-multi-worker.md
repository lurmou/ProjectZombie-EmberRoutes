# Multi-worker Foundation Implementation Plan

日期2026-10-20；状态：本地实施/检查/打包完成，双NPC游戏实测待验。用户授权本会话主代理实施；不派代理、不自动提交。

**Goal:** 多NPC独立载体/任务/预留/调度/恢复内核，以显式搬运验证。
**Architecture:** Java每载体实例+ID注册与旧API门面；Lua任务账本/集中资源声明/每NPC执行器，全局轮转预算。
**Tech Stack:** PZ42.21.0、ZombieBuddy2.3.4、原版TimedAction/Kahlua。
**Spec:** [已批准设计](../specs/2026-10-20-multi-worker-design.md)

## Global Constraints

SP唯一权威、稳定npcId/taskId、原实例转移；暂停/移除不释放未知货物；执行前复验；旧存档单次迁移；CN/EN对齐；不能用替身宣称真实双NPC通过。

## Review Focus

旧全局状态残留；选中变化令动作串号；认领部分成功后泄漏；保存/死亡后货物被重复分配；多NPC推进预算变成每人独立预算。对应测试进入各任务。

### Task 1: Carrier ownership and persistence
- [x] 抽CarrierRuntime、ProbeRuntime注册门面、ProbePersistence按slot存储及旧记录迁移；ID命令/查询/选择入口、共享生命周期预算。
- [x] 当前基线构建、纯注册/生命周期隔离与旧安全门禁检查。

### Task 2: Labor authority and execution
- [x] 新增任务账本/Claims/全局调度，Work执行器实例化与单任务迁移，原转移闭包加任务代次/容量声明校验，移动用显式NPC绑定。
- [x] 两执行器争用/容量/暂停/旧回调/迁移/持货恢复/预算检查，保留旧显式路线回归。

### Task 3: Integration and delivery
- [x] 随从/保存/探针取消范围按NPC隔离；旧菜单桥接选中NPC、新增多个载体/任务测试入口及双语结果。
- [x] 完整Lua/Java/Kahlua回归、preflight/release-check/doclink、0.12.0构建/包比对；本地进度与集中实机说明。

结果见[实现与本地证据](../../reviews/2026-10-20/probe-0.12.0-multi-worker.md)；[七组真实双NPC实测](../../testing/single-player-multi-worker.md)待用户执行，不以替身测试标记通过。
