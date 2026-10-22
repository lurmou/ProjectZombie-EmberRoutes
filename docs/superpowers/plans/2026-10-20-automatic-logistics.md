# Automatic Logistics Implementation Plan

日期2026-10-20；状态：实现及本地检查完成，真实游戏待验。用户明确要求主代理继续实施，不派代理，不自动提交。

**Goal:** 据点共享自动入库和错放整理，不逐NPC设置源/目标。
**Architecture:** 配置/纯路由索引/有界规划/会话调度分离，精确物品意图交接Work，生产者守卫复核原资产。
**Tech Stack:** Lua/Kahlua、PZ42.21.0、ZombieBuddy2.3.4，当前原版TimedAction。
**Spec:** [双模式设计](../specs/2026-10-20-automatic-logistics-design.md)

## Global Constraints

SP权威、稳定npcId/taskId/settlementId、原实例转移；不读私有/未标记；名单/模式与会话分开；全局64规划单位/100ms、每箱2000/每轮20000；每批同源同目标、按负重/容量组批，上限30件；CN/EN成对，游戏实测另记。

## Review Focus

两模式循环；两据点/多工人重复认领；旧候选规则撤销；持货时停止/保存导致丢归属；手动命令被自动抢回。各项进入控制器回归，不拿界面统计结算资产。

### Task 1: Pure route policy and shared configuration
- [x] 新建shared/SortPolicy.lua：input/tidy来源语义、目标规则精度、类型/分类反向索引和有界候选游标；tests/lua/sort-policy-test.lua。
- [x] 新建client/LogisticsStore.lua，Registry新增物流用途命令/DTO；据点命令授权、持久化纯标量模式与名单。

### Task 2: Executor handoff and lifecycle
- [x] shared/LaborProducers.lua注册守卫与原版角色负重上限；Work.assign(actor,npcId,intent)/resumeFor、不覆盖手动任务和货物；自动工单延迟切片校验，效果前调用守卫。WorkBatch负责装货/卸货阶段；Claims/Store支持批次原子预留、逐件释放及旧单件记录兼容。
- [x] 新建client/LogisticsPlanner.lua和LogisticsService.lua：共享预算/池轮转、精确候选、原工单恢复、事件唤醒/低频重扫、停止/人工接管和重置。
- [x] Java按ID移动允许256格已加载目标，超时按距离20..180秒；保留诊断/出生/恢复门禁。
- [x] 两工人自动分拣/整理/停止/撤权/保存/失败重试回归，原69搬运和48多工人回归；此项为宿主替身控制器检查，真实游戏仍待验。

### Task 3: Menus and release
- [x] 新建client/LogisticsMenu.lua，接据点和容器现有菜单，CN/EN成对；无新物理终端家具要求。
- [x] 全Lua/Java/真实Kahlua、modscan/preflight/release-check/doclink，0.13.0包一致性；本地进度/集中测试说明。

本轮结果见[实现与检查记录](../../reviews/2026-10-20/probe-0.13.0-automatic-logistics.md)，实机待按[集中验收](../../testing/single-player-automatic-logistics.md)执行。
