# 工具返还目录与冷启动责任闭环计划

> 日期：2026-11-02｜状态：用户授权继续范围内实施；本地顺序执行，保护既有未提交修改。

**Goal:** 返还原件已经到仓但未清偿时可核对恢复；返还完成/安全取消后释放对应目录。

**Architecture:** ToolCustody 保存可校验的返还意图；ToolReturnService 通过唯一 Runtime/Stop 获得停稳后分类原件，不重放物理动作。Provider 仅关联派生 Offer 和已知停止结果，消费后回收。

**Tech Stack:** PZ Lua、Kahlua、现有 LaborStore/TaskRuntime/TaskBusinessStop。

**Spec:** [本轮确认设计](../specs/2026-11-02-workflow-domain-boundaries-design.md)。

## Global Constraints

- 唯一 ToolCustody 持久责任，format=1 新增可选严格 returnIntent；不造第二账本，不迁移历史记录。
- 不因 Session 消失、超时或记录缺失释放；新劳动只能使用 HELD/RESERVED 工具。
- 恢复会话无 transfer 动作；停稳后根据原件/目的地证据清偿或退回 HELD，未知留责。
- Directory 释放必须来自已知停止结果；世界切换只销毁派生关联。

## Review Focus

- 已到仓未清偿：持久目的仓与旧 jobId 保留，恢复不重复 PUT。
- 仍在背包：停稳后才撤销，允许后续新工作使用。
- 未加载/权限变化/原件失踪：留责且不变更目的地冒充完成。
- 返还中断后相同 custody 再次派工：旧 Offer 正常释放。
- 未启动取消与世界切换：分别以终态/世界身份拒绝孤儿和跨世界清偿。

## Task 1：持久意图与恢复

**Files:** ToolCustodyRecord.lua、LaborStore.lua、ToolReturnService.lua、MembershipRuntime.lua；路径根 Contents/mods/EmberRoutesProbe/42/media/lua/shared 或 client/EmberRoutesProbe。

**Interfaces:** `assignToolReturn(custodyId,returnJobId,intent?)`；`ToolReturnService.startFor(actor,npcId,custodyId,returnJobId,scopeId,options?)` 的 options.trackResult 仅启用派生结果跟踪；恢复沿 recoverFor，结果沿 returnResult/forgetResult。

- [x] 添加并复现 PENDING_RETURN 不应被清空、已到仓无重发、未知留责的反例。
- [x] 写入并校验 returnIntent；恢复加载不无条件降级；防止新劳动使用未知/返还中工具。
- [x] 在唯一 Runtime/Stop 会话中恢复核对，已到账/仍持有/不明分别清偿/撤销/留责；成员恢复接通。

## Task 2：目录闭环与后台恢复

**Files:** ToolReturnProvider.lua、ToolReturnService.lua、tests/lua/tool-return-test.lua。

**Interfaces:** Provider.advance(env) 复用公共 advance 节拍；已知 stopped 结果才给 Directory.release 提供 proof；跟踪结果消费后删除。

- [x] 定向测试返还成功/取消目录释放、同 custody 再次认领、未知不释放和跨世界不释放新目录。
- [x] 正式 Provider.claim 追踪返回任务；advance/reconcile 对接结果；有界恢复 PENDING_RETURN，不依赖 UI。

## Task 3：检查与交付

- [x] 运行 tool-return/tool-custody、FIELD 与成员恢复相关 Kahlua 回归，不放宽生产守卫。
- [x] 版本递增、普通/Debug 编译、结构/类型检查、CN/EN及 Markdown 引用与差异检查。
- [x] 更新 BACKLOG/INDEX/证据；区分源码实现、宿主替身和未运行的实机保存重进。

## 执行结果

源码与本批替身/构建检查已执行；发布检查、旧迁移与完整页面夹具仍有失败，不代表全部验收通过。详见[本批证据](../../reviews/2026-11-02/workflow-closure-and-monitor.md)。PZ 实机、性能及总体 B.5 未验收。
