# 执行会话与调度内核

> 更新：2026-11-06｜状态：active｜以当前源码校准。此页是导航与现行契约，不是未来能力承诺；功能完成度见BACKLOG。

## 1. 职责与非职责
Runtime的Controller/Driver裁决身体执行，Kernel提供会话标量、JobStore与可重建目录。Boot/Persistence是装配与引导入口，不能把这些组合代码都称为完全无业务依赖的纯内核。

## 2. 数据权威
ExecutionSessions与TaskController的运行记录瞬态存在；TaskJobs.current()把JobStore绑定当前ContainerRegistry根的taskJobs。TaskDirectory.new()只保存可重建offers，不是物品、地块或存档的唯一锁账本。原件声明由LaborStore和对应业务Job负责。

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

## 6. 源码地图
- [client/EmberRoutesProbe/Runtime/TaskRuntime.lua](../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/Runtime/TaskRuntime.lua)
- [client/EmberRoutesProbe/Runtime/TaskController.lua](../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/Runtime/TaskController.lua)
- [client/EmberRoutesProbe/Runtime/TaskStopEvidence.lua](../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/Runtime/TaskStopEvidence.lua)
- [client/EmberRoutesProbe/Runtime/Driver.lua](../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/Runtime/Driver.lua)
- [client/EmberRoutesProbe/Runtime/TaskJobs.lua](../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/Runtime/TaskJobs.lua)
- [shared/EmberRoutesProbe/Kernel/ExecutionSessions.lua](../../Contents/mods/EmberRoutesProbe/42/media/lua/shared/EmberRoutesProbe/Kernel/ExecutionSessions.lua)
- [shared/EmberRoutesProbe/Kernel/TaskDirectory.lua](../../Contents/mods/EmberRoutesProbe/42/media/lua/shared/EmberRoutesProbe/Kernel/TaskDirectory.lua)

## 7. 验证入口
KahluaLaborTest指定task-controller、task-driver-control、task-runtime及task-companion-runtime；身体审计工具只列调用点，不能自动证明所有权。

## 8. 易错边界
无TaskController.acquire/session:walkTo/queueAction/finish接口。不得从超时、队列空、记录缺失推导原件已结清；TaskStopEvidence校验的是调用方已持久化事实，不保存断点物品清单。

自动化、原生替身、实机、磁盘恢复与性能分开记录；源码存在和构建通过不等于玩法已验收。
