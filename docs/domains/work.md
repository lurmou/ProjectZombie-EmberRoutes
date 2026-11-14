# 公共工作与工种调度

> 更新：2026-11-06｜状态：active｜以当前源码校准。此页是导航与现行契约，不是未来能力承诺；功能完成度见BACKLOG。

## 1. 职责与非职责
PublicWork负责资格、候选发现/选择、目录认领与Provider组合；领域负责内部物理步骤/效果/原件，不把所有工种塞进同一通用状态机。

## 2. 数据权威
原件责任由 shared/Kernel/ObligationLedger 统一记录，ObligationTypes 校验领域证据；资源 Claims 与 Job 业务进度分别保留，不能替代责任结清。工具托管由 client/Field/ToolCustody 提交；JobStore/TaskJobs统一Job封包，TaskDirectory只是可重建候选。没有独立EmberRoutes_LaborSchedule存档键这一约定，实际配置由PublicWork.data等源码定义。

## 3. 现行生命周期
PublicWork构造envDiscover并调用discover；选择候选后自己生成jobId并directory:claim，再调用领域claim。QUEUED/STARTED接手；拒绝时只有领域claim返回第二个值`'ROLLED_BACK'`（本次认领未留下业务效果）才释放offer，否则保留分配并记录`OFFER_RETAINED reason=CLAIM_ROLLBACK_UNDECLARED`（见[生命周期规则](../../.agents/rules/provider-lifecycle.md)第5条）。`createClaimedJob`的`TASK_WRITE_FAILURE`与`ROLLBACK_FAILURE`默认按效果未知不声明；唯一例外是证据精确等于`JobStore.create`写入前拒绝码（如据点门`CRAFT_SCOPE_RECONCILE_REQUIRED`），由`LaborJobCommit.createEffectsUnknown`统一判断，field与cooking已采用，据点门关着时offer因此被释放而不是留到读档（2026-11-10契约变化，代码层，未实机验证）。领域持续推进/核对并凭KNOWN且义务清偿证明释放目录。未知效果、死亡或会话消失留责而非无条件release。

## 4. 真实接口入口
- `PublicWorkProviders.register(def) / get(category) / all()`
- `provider.discover(envDiscover)`
- `provider.claim(selected,npcId,jobId,env)`
- `provider.advance(env) / reconcile() / hasWork()`

参数和返回细节以链接中的生产调用方/定义为准；这里不定义第二套API，也不为手册示例添加兼容别名。

## 5. 依赖边界
业务模块不引用UI；原版UI接入由Integration负责。shared只依赖实际存在的shared模块；客户端执行/账本组合放client。跨业务调用须经当前公开服务，已有组合依赖不等于所有内部文件都能任意引用。身体只通过TaskRuntime/TaskController/Driver当前授权链执行。

## 6. 源码地图
- [client/EmberRoutesProbe/Work/PublicWork.lua](../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/Work/PublicWork.lua)
- [client/EmberRoutesProbe/Work/PublicWorkProviders.lua](../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/Work/PublicWorkProviders.lua)
- [client/EmberRoutesProbe/Work/LaborManifest.lua](../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/Work/LaborManifest.lua)
- [client/EmberRoutesProbe/Work/LaborStore.lua](../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/Work/LaborStore.lua)
- [client/EmberRoutesProbe/Field/FarmingProvider.lua](../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/Field/FarmingProvider.lua)
- [client/EmberRoutesProbe/Hauling/HaulingProvider.lua](../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/Hauling/HaulingProvider.lua)
- [shared/EmberRoutesProbe/Kernel/TaskDirectory.lua](../../Contents/mods/EmberRoutesProbe/42/media/lua/shared/EmberRoutesProbe/Kernel/TaskDirectory.lua)

## 7. 验证入口
KahluaLaborTest 默认套件为 labor-core、sort-policy、logistics、multi-worker、companion、persistence、boot-pause；public-work、tool-return、labor-wiring-order 及相应 Provider 用例需显式点跑（`--all` 会跑全部 `*-test.lua`）。类别中英文成对，运行check-i18n/check-architecture。测试所需原版依赖替身必须符合生产契约。

## 8. 易错边界
`PublicWorkProviders.register`校验category/defaultPriority，并要求discover与claim是函数；其余可选钩子若存在也须是函数，但不强制实现。内置工种注册失败时PublicWork加载即报错（`PROVIDER_REGISTRATION_FAILED`）。内置工种元数据在 shared/Kernel/BuiltinJobContracts 中经 DomainRegistry 声明并在启动后封存；Provider 的声明顺序决定 categories 枚举及派发平局。LaborManifest 仅保留恢复/监视装配，jobKinds 顺序决定读档恢复顺序；`tests/lua/labor-wiring-order-test.lua`锁定这两种顺序。JobContracts条目仍在`shared/.../Kernel/BuiltinJobContracts.lua`，PolicyDef仍由`client/EmberRoutesProbe.lua`加载。discover通过env发布而非返回候选数组；不能把reconcile(jobId,outcome)或无条件目录释放写成正式协议。

P4（代码层，未实机验证）起PublicWork内核不再点名工种调用领域：eligible问`Providers.retained`，换世界调`Providers.resetWorld`（各工种`reset`），订单命令交给category工种的`command`或扇出`orderCommanded`，退役用`retireUnclaimed`与`orderRetired`，必填优先级读`priorityRequired`；钩子说明见[add-provider](../../.agents/skills/add-provider/SKILL.md)。仍留在内核的是订单创建的cooking/制作分流（`PublicWorkOrders.lua` 的 createOrder、createPrerequisite、saveRule与stock的CookingOrders.describe）、无category订单即制作订单的`craft:`键与`CRAFT`记录核对。`tools/check-architecture.py`的`KERNEL_CATEGORY_LITERAL_COUNT`锁定PublicWork里的带引号工种名个数（现为0），`PUBWORK_ORDERS_LITERAL_COUNT`锁定PublicWorkOrders的2个订单分流，注册表`PublicWorkProviders.lua`基线为0；三者只减不增。同一脚本按Lua作用域检查对未声明local的赋值，现有15个名字记在`GLOBAL_WRITE_BASELINE`，同样只减不增。`tests/lua/public-work-kernel-hooks-test.lua`锁定这些路径的守卫顺序与效果。

自动化、原生替身、实机、磁盘恢复与性能分开记录；源码存在和构建通过不等于玩法已验收。

新增涉及原件的领域，应在自身 shared JobObligationContract 中声明责任与 Job 的对应关系、结清及退休证据，经 BuiltinJobContracts 装配入 JobContracts；不能回到 JobStore 增加领域分支。Claims 写入包括冷恢复统一经 Java 实现，LaborClaims 仅保留调用协议与只读查询。物流服务 LOGISTICS_STOPPED 暂停可在服务重新启用后恢复；公共派工、暂停、健康与成员守卫继续生效，不自动解除停服务。
