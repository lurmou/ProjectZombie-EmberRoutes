# 执行会话与调度内核

> 更新：2026-11-06｜状态：active｜以当前源码校准。此页是导航与现行契约，不是未来能力承诺；功能完成度见BACKLOG。

## 1. 职责与非职责
Runtime的Controller/Driver裁决身体执行，Kernel提供会话标量、JobStore与可重建目录。Boot/Persistence是装配与引导入口，不能把这些组合代码都称为完全无业务依赖的纯内核。

## 2. 数据权威
ExecutionSessions与TaskController的运行记录瞬态存在；TaskJobs.current()把JobStore绑定当前ContainerRegistry根的taskJobs。TaskDirectory.new()只保存可重建offers，不是物品、地块或存档的唯一锁账本。原件 Claims 与独立 ObligationLedger 分别建模，领域证据由 ObligationTypes 验证。正式根 v2 必须包含有效账本；旧根拒绝并保留。Job、义务与令牌经 Java 受控同步发布后通知；未知提交故障由 CommitFence 阻止后续业务推进，但不阻止当前身体请求停止。

## 3. 现行生命周期
运行时submit完整spec→校验/排队→Controller.request→attachDriver取得generation授权→start/tick→请求停止→observeStop确认身体和effects→persistEffects→TaskStopEvidence.validate→释放控制并确认会话停止。可释放身体但仍保留UNKNOWN业务义务；不保证任意高优先级可立即剥夺令牌。

## 4. 真实接口入口
- `TaskRuntime.current():submit(spec)`
- `TaskController.new():request(npcId,jobId,kind,adapter)`
- `controller:attachDriver(ticket,binding) / requestStop(ticket,reason)`
- `Driver.acquireControl(binding,jobId,generation)`
- `TaskDirectory.new():upsert(key,revision,category,scopeId)`
- `directory:claim(key,revision,npcId,jobId)`
- `directory:release(key,jobId,proof)`

参数和返回细节以链接中的生产调用方/定义为准；这里不定义第二套API，也不为手册示例添加兼容别名。

## 5. 依赖边界
业务模块不引用UI；原版UI接入由Integration负责。shared只依赖实际存在的shared模块；客户端执行/账本组合放client。跨业务调用须经当前公开服务，已有组合依赖不等于所有内部文件都能任意引用。身体只通过TaskRuntime/TaskController/Driver当前授权链执行。

`tools/check-architecture.py` 强制三条规则：shared 不得 require 客户端；业务域不得 require UI（Integration 除外）；Kernel 不得 require 同层其他领域。其余同层跨域边由 `DOMAIN_EDGE_BASELINE` 冻结（当前 126 条），新增边失败、删除边须同步下调基线。该基线记录现状（包括 Runtime 对业务域的读取和业务域互引），不代表无环或已完成分层。

## 6. 源码地图
- Java 身体桥接：[BodyBridgeContract.java](../../java/src/main/java/emberroutes/probe/BodyBridgeContract.java) 集中定义正式休息种类、家具阶段和停稳信号；ProbeRuntime 仅在原有授权围栏内转换内部枚举，公开参数/返回仍为 Lua 已使用的字符串、数值和原生句柄。`STOP_UNAVAILABLE=-1` 与 `STOPPED=0` 含义不同；身体停稳不证明业务效果或资产责任已结清。ProbeBridgeSurfaceTest 冻结 119 个公开静态入口的完整签名（方法名、返回类型、有序参数类型），并检查无重载、内部 `log` 保持包可见、已删除的转发方法不回流。
- Java 原生身体：[NpcLocomotion.java](../../java/src/main/java/emberroutes/probe/NpcLocomotion.java) 持有每身体的移动/跟随执行状态；[ProbeMovement.java](../../java/src/main/java/emberroutes/probe/ProbeMovement.java) 保持无引擎依赖的移动生命周期；[NpcPosture.java](../../java/src/main/java/emberroutes/probe/NpcPosture.java) 持有床姿、地板姿态、家具足迹和物理退出证据；[ProbeNpc.java](../../java/src/main/java/emberroutes/probe/ProbeNpc.java) 保留引擎覆写、原生根运动消费、停稳聚合与全身停止协调。Java 桥继续经 ProbeRuntime 的现有授权入口，不从业务侧直接调用组件。
- [client/EmberRoutesProbe/Runtime/TaskRuntime.lua](../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/Runtime/TaskRuntime.lua)
- [client/EmberRoutesProbe/Runtime/TaskController.lua](../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/Runtime/TaskController.lua)
- [client/EmberRoutesProbe/Runtime/TaskStopEvidence.lua](../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/Runtime/TaskStopEvidence.lua)
- [client/EmberRoutesProbe/Runtime/Driver.lua](../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/Runtime/Driver.lua)
- [client/EmberRoutesProbe/Runtime/TaskJobs.lua](../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/Runtime/TaskJobs.lua)
- [shared/EmberRoutesProbe/Kernel/ExecutionSessions.lua](../../Contents/mods/EmberRoutesProbe/42/media/lua/shared/EmberRoutesProbe/Kernel/ExecutionSessions.lua)
- [shared/EmberRoutesProbe/Kernel/TaskDirectory.lua](../../Contents/mods/EmberRoutesProbe/42/media/lua/shared/EmberRoutesProbe/Kernel/TaskDirectory.lua)

## 7. 验证入口
KahluaLaborTest 默认套件为 labor-core、sort-policy、logistics、multi-worker、companion、persistence、boot-pause；task-controller、task-driver-control、task-runtime、task-companion-runtime 需显式点跑（`--all` 会跑全部 `*-test.lua`）。身体审计工具只列调用点，不能自动证明所有权。

## 8. 易错边界
无TaskController.acquire/session:walkTo/queueAction/finish接口。不得从超时、队列空、记录缺失推导原件已结清；TaskStopEvidence校验的是调用方已持久化事实，不保存断点物品清单。

自动化、原生替身、实机、磁盘恢复与性能分开记录；源码存在和构建通过不等于玩法已验收。

## Claims 与领域义务边界

LaborClaims 只适配调用及提供只读查询，认领、更新、容量、隔离、隔离恢复与释放统一调用 Java ClaimsKernel/ClaimsRecovery。缺少 claimsCommand 明确拒绝，无 Lua 写实现。LaborCommitKernel 负责事务发布和单次撤销；Lua 不直接改 claims 图缓存。Claims 表仍为同一运行时图，不增加持久权威。

JobStore 强制执行通用 Job/npc/claim/终态约束；领域 shared JobObligationContract 提供 obligationRecord（逐责任一致性）、obligationGuard（Job 反向引用）、validateObligationOperation（结清证据）、retireObligation（结清记录退休）。操作证据按注册顺序全部核对，防止错领域责任绕过拒绝；退休回调只来自当前 Job 契约。创建、更新、认领恢复和转移仍在原门禁位置执行。blocksScope 的拒绝原因由契约 scopeBlockedReason 声明并登记 errorCodes，公共内核不反查制作清单取得原因。

当前证据见[claims 与领域契约收敛](../reviews/2026-11-14/claims-contract-convergence.md)。
