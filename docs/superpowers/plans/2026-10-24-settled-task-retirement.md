# 结清工单清理实施计划

**Goal:** 按用户2026-10-24批准的建议，工单结清即消失，历史不再耗尽派工容量。

**Architecture:** 保留唯一架构；JobStore提供受限终态删除，BusinessJobs检查身体、声明及恢复关系，PublicWork先结清公共关联再删除记录。不删除物品、不把未知效果或未归还责任视为完成。个人持续自理记录不属于工单历史。

**Tech Stack:** PZ42.21.0 Kahlua Lua、现有TaskRuntime/LaborStore。

**Spec:** 唯一架构第5节及本轮用户已批准的“结清删除、未结保留、少量有界技术回执”规则；用户授权直接实施，无重复确认。

## 约束与审阅重点

- 删除必须等身体会话与候选都结束，效果已知、声明和容量责任已释放；暂停/核对/未交付保留。
- 公共Order先核对其Job，删除前清目录及最低存量activeOrder；不能让缺失Job被误认为应重新派单。
- 公共请求采用最多128个签发/完成技术回执。只有仍有效的签发请求或现有活动单可重试；回执过期拒绝，不把迟到请求当新意图。
- 完成与取消的旧格式1新任务记录按同一证据安全清理；不迁入旧craftProbes/labor格式。
- 持续自理保留；未完成恢复引用和保存屏障阻止删除。已完成回调只持有旧执行现场，不能重建Job。

## Task 1：受限终态清理

Files: JobStore.lua、BusinessJobs.lua、LaborStore.lua；tests/lua/job-store-test.lua、settled-task-retirement-test.lua。

- [x] JobStore.removeSettled(id,revision)仅移除KNOWN且无义务终态，原位更新唯一索引和计数。
- [x] LaborStore提供只读hasTaskClaims；BusinessJobs.retire检查Runtime、恢复引用、公共关联及业务完成事实，清派生索引和无效保存引用。
- [x] 验证完成/取消、未释放声明、UNKNOWN、恢复依赖、同NPC后续任务及循环超过原上限。

## Task 2：公共工单与交付接线

Files: PublicWork.lua、Boot.lua、UI/PublicOrderDialog.lua、CN/EN翻译；相关公共调度/监控/保存测试。

- [x] 增加有界请求签发与完成回执；UI及存量自动委托使用签发token，重试不重复下单，过期拒绝。
- [x] 公共协调结清Order、目录、存量引用后清理Job；无公共Order的完成制作/搬运也自动清理。每200ms有界维护，不在动作回调栈删除。
- [x] 验证重复请求/迟到回调/正常保存读档、取消未归还及存量下一周期，运行必要回归、构建、preflight、release-check及doclink。

不提交含并行改动的整体Git提交；阶段结果登记原BACKLOG与专题证据。
