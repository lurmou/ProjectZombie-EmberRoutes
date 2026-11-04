# DEC-003 Phase 0 提交入口盘点（未迁移）

基线：`phase-3a-consolidation` / `9ebe06f`，开始时工作树干净。2026-11-04。
范围：EmberRoutesProbe 的 client/shared Lua、Java LaborCommitKernel、原始 Job 别名写、全部 LaborDomainAdapters 操作。
本表是静态分类证据，不是已迁移或 Java 通过的证据。批准顺序与停止点见[执行记录](dec003-execution.md)。

分类标准：改变持久 Job 身份、payload、revision、状态、所有者、恢复授权，或改变其 claims/容量承诺的操作均为**提交**。恢复/回滚/隔离/退役不是豁免。完全只读或将同一已提交事实重建为运行时索引才是**非提交**。一个函数混合两类操作时逐分支分类；含持久写的函数不能整体排除。

## TaskJobs/JobStore 调用与原语（逐位置）

以下链接固定到本轮未修改的生产代码行号。`delete` 方法不存在；实际删除原语是 `removeSettled`。
UI 的 `update()` 方法和 Record 的纯构造函数不是 TaskJobs 写入，未计入。

| 位置 / 操作 | 分类与理由 |
|---|---|
| [ActivityParticipant.lua:41](../../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/ActivityParticipant.lua#L41) `local ok,why=api:create` | 提交：创建/推进参与 Job，或删除已结清持久身份；非 UI 投影。 |
| [ActivityParticipant.lua:48](../../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/ActivityParticipant.lua#L48) `return Jobs.current` | 提交：创建/推进参与 Job，或删除已结清持久身份；非 UI 投影。 |
| [ActivityParticipant.lua:100](../../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/ActivityParticipant.lua#L100) `if job and ` | 提交：创建/推进参与 Job，或删除已结清持久身份；非 UI 投影。 |
| [BusinessJobs.lua:88](../../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/BusinessJobs.lua#L88) `if not store:update` | 提交：SELF_CARE resume 完成标记或持久 Job 退役；有 revision 不等于内核合规。 |
| [BusinessJobs.lua:91](../../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/BusinessJobs.lua#L91) `if not store:removeSettled` | 提交：SELF_CARE resume 完成标记或持久 Job 退役；有 revision 不等于内核合规。 |
| [CookingAgent.lua:291](../../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/CookingAgent.lua#L291) `return Jobs.current` | 提交：将原生执行观察发布到 Job。 |
| [CookingService.lua:349](../../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/CookingService.lua#L349) `local ok,revision=Jobs.current` | 提交：取消、恢复、请求标记、跨 Job resume 或删除已结清 Job；全部持久。 |
| [CookingService.lua:352](../../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/CookingService.lua#L352) `Jobs.current` | 提交：取消、恢复、请求标记、跨 Job resume 或删除已结清 Job；全部持久。 |
| [CookingService.lua:470](../../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/CookingService.lua#L470) `if not Jobs.current` | 提交：取消、恢复、请求标记、跨 Job resume 或删除已结清 Job；全部持久。 |
| [CookingService.lua:474](../../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/CookingService.lua#L474) `if can and Jobs.current` | 提交：取消、恢复、请求标记、跨 Job resume 或删除已结清 Job；全部持久。 |
| [CookingService.lua:511](../../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/CookingService.lua#L511) `local ok=Jobs.current` | 提交：取消、恢复、请求标记、跨 Job resume 或删除已结清 Job；全部持久。 |
| [CookingService.lua:522](../../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/CookingService.lua#L522) `local ok=Jobs.current` | 提交：取消、恢复、请求标记、跨 Job resume 或删除已结清 Job；全部持久。 |
| [CookingService.lua:535](../../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/CookingService.lua#L535) `Jobs.current` | 提交：取消、恢复、请求标记、跨 Job resume 或删除已结清 Job；全部持久。 |
| [CookingService.lua:550](../../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/CookingService.lua#L550) `Jobs.current` | 提交：取消、恢复、请求标记、跨 Job resume 或删除已结清 Job；全部持久。 |
| [CookingService.lua:578](../../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/CookingService.lua#L578) `local ok,revision=Jobs.current` | 提交：取消、恢复、请求标记、跨 Job resume 或删除已结清 Job；全部持久。 |
| [CookingService.lua:583](../../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/CookingService.lua#L583) `Jobs.current` | 提交：取消、恢复、请求标记、跨 Job resume 或删除已结清 Job；全部持久。 |
| [FieldWork.lua:58](../../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/FieldWork.lua#L58) `assert` | 提交：创建/恢复/取消/结清或删除 Job；失败接单补偿也需保留责任。 |
| [FieldWork.lua:82](../../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/FieldWork.lua#L82) `if changed then Jobs.current` | 提交：创建/恢复/取消/结清或删除 Job；失败接单补偿也需保留责任。 |
| [FieldWork.lua:91](../../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/FieldWork.lua#L91) `if Store.finishField` | 提交：创建/恢复/取消/结清或删除 Job；失败接单补偿也需保留责任。 |
| [FieldWork.lua:137](../../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/FieldWork.lua#L137) `local ok,err=Jobs.current` | 提交：创建/恢复/取消/结清或删除 Job；失败接单补偿也需保留责任。 |
| [FieldWork.lua:155](../../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/FieldWork.lua#L155) `assert` | 提交：创建/恢复/取消/结清或删除 Job；失败接单补偿也需保留责任。 |
| [FieldWork.lua:157](../../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/FieldWork.lua#L157) `assert` | 提交：创建/恢复/取消/结清或删除 Job；失败接单补偿也需保留责任。 |
| [HaulJobs.lua:160](../../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/HaulJobs.lua#L160) `assert` | 提交：读档 STOPPING/SUSPENDED/UNKNOWN 发布，不能以恢复尾部为由豁免。 |
| [HaulJobs.lua:162](../../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/HaulJobs.lua#L162) `assert` | 提交：读档 STOPPING/SUSPENDED/UNKNOWN 发布，不能以恢复尾部为由豁免。 |
| [LaborDomainAdapters.lua:21](../../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/LaborDomainAdapters.lua#L21) `local ok,reason=jobs:transferCooking` | 提交：adapter 的 Job 发布/所有者转交；资源更改另见逐 adapter 表。 |
| [LaborDomainAdapters.lua:61](../../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/LaborDomainAdapters.lua#L61) `local changed,why=jobs:update` | 提交：adapter 的 Job 发布/所有者转交；资源更改另见逐 adapter 表。 |
| [LaborDomainAdapters.lua:130](../../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/LaborDomainAdapters.lua#L130) `ok,why=jobs:update` | 提交：adapter 的 Job 发布/所有者转交；资源更改另见逐 adapter 表。 |
| [LaborDomainAdapters.lua:168](../../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/LaborDomainAdapters.lua#L168) `if not require` | 提交：adapter 的 Job 发布/所有者转交；资源更改另见逐 adapter 表。 |
| [LaborDomainAdapters.lua:186](../../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/LaborDomainAdapters.lua#L186) `if not require` | 提交：adapter 的 Job 发布/所有者转交；资源更改另见逐 adapter 表。 |
| [LaborDomainAdapters.lua:213](../../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/LaborDomainAdapters.lua#L213) `return jobs:update` | 提交：adapter 的 Job 发布/所有者转交；资源更改另见逐 adapter 表。 |
| [LaborDomainAdapters.lua:221](../../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/LaborDomainAdapters.lua#L221) `local ok=jobs:update` | 提交：adapter 的 Job 发布/所有者转交；资源更改另见逐 adapter 表。 |
| [LaborDomainAdapters.lua:237](../../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/LaborDomainAdapters.lua#L237) `local ok,reason=jobs:update` | 提交：adapter 的 Job 发布/所有者转交；资源更改另见逐 adapter 表。 |
| [LaborJobCommit.lua:43](../../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/LaborJobCommit.lua#L43) `local ok,err=store:create` | 提交：创建或 CAS 发布、失败隔离都会修改 Job 权威；现有阈值路径不是例外。 |
| [LaborJobCommit.lua:195](../../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/LaborJobCommit.lua#L195) `local okCAS, nextRev = store:update` | 提交：创建或 CAS 发布、失败隔离都会修改 Job 权威；现有阈值路径不是例外。 |
| [LaborJobCommit.lua:210](../../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/LaborJobCommit.lua#L210) `store:update` | 提交：创建或 CAS 发布、失败隔离都会修改 Job 权威；现有阈值路径不是例外。 |
| [LaborJobCommit.lua:225](../../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/LaborJobCommit.lua#L225) `store:update` | 提交：创建或 CAS 发布、失败隔离都会修改 Job 权威；现有阈值路径不是例外。 |
| [LeisureService.lua:393](../../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/LeisureService.lua#L393) `if not jobs:update` | 提交：清除持久 resumeHint，改变下一次发放；本轮禁止改闲暇策略不使该写变成非提交。 |
| [ProductionJobs.lua:177](../../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/ProductionJobs.lua#L177) `Jobs.current` | 提交：失败原生效果记录或读档生命周期修改；UNKNOWN 与恢复写也属于权威提交。 |
| [ProductionJobs.lua:198](../../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/ProductionJobs.lua#L198) `assert` | 提交：失败原生效果记录或读档生命周期修改；UNKNOWN 与恢复写也属于权威提交。 |
| [ProductionJobs.lua:201](../../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/ProductionJobs.lua#L201) `assert` | 提交：失败原生效果记录或读档生命周期修改；UNKNOWN 与恢复写也属于权威提交。 |
| [SelfCare.lua:32](../../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/SelfCare.lua#L32) `if Jobs.current` | 提交：创建个人 Job，发布尝试/claims/义务/恢复事实；补偿写仍是提交。 |
| [SelfCare.lua:97](../../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/SelfCare.lua#L97) `if not Jobs.current` | 提交：创建个人 Job，发布尝试/claims/义务/恢复事实；补偿写仍是提交。 |
| [SelfCare.lua:317](../../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/SelfCare.lua#L317) `local updated,why=Jobs.current` | 提交：创建个人 Job，发布尝试/claims/义务/恢复事实；补偿写仍是提交。 |
| [SelfCare.lua:331](../../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/SelfCare.lua#L331) `Jobs.current` | 提交：创建个人 Job，发布尝试/claims/义务/恢复事实；补偿写仍是提交。 |
| [SelfCare.lua:390](../../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/SelfCare.lua#L390) `if not Jobs.current` | 提交：创建个人 Job，发布尝试/claims/义务/恢复事实；补偿写仍是提交。 |
| [SelfCare.lua:394](../../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/SelfCare.lua#L394) `if not Jobs.current` | 提交：创建个人 Job，发布尝试/claims/义务/恢复事实；补偿写仍是提交。 |
| [SelfCare.lua:405](../../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/SelfCare.lua#L405) `if not Jobs.current` | 提交：创建个人 Job，发布尝试/claims/义务/恢复事实；补偿写仍是提交。 |
| [SelfCare.lua:438](../../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/SelfCare.lua#L438) `if not Jobs.current` | 提交：创建个人 Job，发布尝试/claims/义务/恢复事实；补偿写仍是提交。 |
| [SelfCare.lua:444](../../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/SelfCare.lua#L444) `if not Jobs.current` | 提交：创建个人 Job，发布尝试/claims/义务/恢复事实；补偿写仍是提交。 |
| [SelfCare.lua:448](../../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/SelfCare.lua#L448) `if not Jobs.current` | 提交：创建个人 Job，发布尝试/claims/义务/恢复事实；补偿写仍是提交。 |
| [SelfCare.lua:514](../../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/SelfCare.lua#L514) `if not Jobs.current` | 提交：创建个人 Job，发布尝试/claims/义务/恢复事实；补偿写仍是提交。 |
| [SelfCare.lua:518](../../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/SelfCare.lua#L518) `if not Jobs.current` | 提交：创建个人 Job，发布尝试/claims/义务/恢复事实；补偿写仍是提交。 |
| [SelfCareExecution.lua:73](../../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/SelfCareExecution.lua#L73) `return Jobs.current` | 提交：发布动作效果/义务或生命周期；身体执行与停止不等于结清。 |
| [SelfCareExecution.lua:159](../../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/SelfCareExecution.lua#L159) `if not Jobs.current` | 提交：发布动作效果/义务或生命周期；身体执行与停止不等于结清。 |
| [SelfCareExecution.lua:163](../../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/SelfCareExecution.lua#L163) `if live.state~=state and not Jobs.current` | 提交：发布动作效果/义务或生命周期；身体执行与停止不等于结清。 |
| [SelfCareExecution.lua:203](../../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/SelfCareExecution.lua#L203) `if not Jobs.current` | 提交：发布动作效果/义务或生命周期；身体执行与停止不等于结清。 |
| [SelfCareExecution.lua:206](../../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/SelfCareExecution.lua#L206) `if not Jobs.current` | 提交：发布动作效果/义务或生命周期；身体执行与停止不等于结清。 |
| [SelfCareReconciliation.lua:87](../../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/SelfCareReconciliation.lua#L87) `if not Jobs.current` | 提交：发布核对后的 payload、义务与状态。 |
| [TaskResume.lua:37](../../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/TaskResume.lua#L37) `return Jobs.current` | 提交：发布持久 resume 关系/步骤/代次，影响恢复授权；无 claims 变化也须走内核。 |
| [TaskResume.lua:64](../../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/TaskResume.lua#L64) `return jobs:update` | 提交：发布持久 resume 关系/步骤/代次，影响恢复授权；无 claims 变化也须走内核。 |
| [TaskResume.lua:70](../../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/TaskResume.lua#L70) `return jobs:update` | 提交：发布持久 resume 关系/步骤/代次，影响恢复授权；无 claims 变化也须走内核。 |
| [TaskResume.lua:84](../../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/TaskResume.lua#L84) `return jobs:update` | 提交：发布持久 resume 关系/步骤/代次，影响恢复授权；无 claims 变化也须走内核。 |
| [TaskResume.lua:95](../../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/TaskResume.lua#L95) `return Jobs.current` | 提交：发布持久 resume 关系/步骤/代次，影响恢复授权；无 claims 变化也须走内核。 |
| [TaskResume.lua:113](../../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/TaskResume.lua#L113) `return Jobs.current` | 提交：发布持久 resume 关系/步骤/代次，影响恢复授权；无 claims 变化也须走内核。 |
| [TaskResume.lua:132](../../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/TaskResume.lua#L132) `local ok,why=jobs:update` | 提交：发布持久 resume 关系/步骤/代次，影响恢复授权；无 claims 变化也须走内核。 |
| [TaskResume.lua:141](../../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/TaskResume.lua#L141) `local ok,reason=jobs:update` | 提交：发布持久 resume 关系/步骤/代次，影响恢复授权；无 claims 变化也须走内核。 |
| [TaskResume.lua:149](../../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/TaskResume.lua#L149) `local ok,why=jobs:update` | 提交：发布持久 resume 关系/步骤/代次，影响恢复授权；无 claims 变化也须走内核。 |
| [TaskResume.lua:155](../../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/TaskResume.lua#L155) `local ok,why=jobs:update` | 提交：发布持久 resume 关系/步骤/代次，影响恢复授权；无 claims 变化也须走内核。 |
| [TaskResume.lua:165](../../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/TaskResume.lua#L165) `local ok,reason=jobs:update` | 提交：发布持久 resume 关系/步骤/代次，影响恢复授权；无 claims 变化也须走内核。 |
| [TaskResume.lua:205](../../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/TaskResume.lua#L205) `if not Jobs.current` | 提交：发布持久 resume 关系/步骤/代次，影响恢复授权；无 claims 变化也须走内核。 |
| [CookingBudget.lua:63](../../../Contents/mods/EmberRoutesProbe/42/media/lua/shared/EmberRoutesProbe/CookingBudget.lua#L63) `return jobs:create` | 提交：Lua 配额/供应策略通过后创建 COOKING Job；不能把共享模块视为仅校验。 |
| [JobStore.lua:157](../../../Contents/mods/EmberRoutesProbe/42/media/lua/shared/EmberRoutesProbe/JobStore.lua#L157) `function api:create` | 提交原语定义：创建、CAS、所有者转交、退役的最终持久写；不是另一个领域入口。 |
| [JobStore.lua:182](../../../Contents/mods/EmberRoutesProbe/42/media/lua/shared/EmberRoutesProbe/JobStore.lua#L182) `function api:update` | 提交原语定义：创建、CAS、所有者转交、退役的最终持久写；不是另一个领域入口。 |
| [JobStore.lua:209](../../../Contents/mods/EmberRoutesProbe/42/media/lua/shared/EmberRoutesProbe/JobStore.lua#L209) `function api:transferOwner` | 提交原语定义：创建、CAS、所有者转交、退役的最终持久写；不是另一个领域入口。 |
| [JobStore.lua:229](../../../Contents/mods/EmberRoutesProbe/42/media/lua/shared/EmberRoutesProbe/JobStore.lua#L229) `function api:removeSettled` | 提交原语定义：创建、CAS、所有者转交、退役的最终持久写；不是另一个领域入口。 |

共 **75** 个调用/原语位置；其中 JobStore 定义 4 个，其余 71 个是调用位置。正则扫描只是候选发现；raw 写与 adapter 不能靠该数目覆盖，见下表。

## 原始持久别名写（不是恢复索引）

以下是上表之外的提交，均保持原样且列为开放项；不能宣称全局边界已收敛。

| 位置（client/EmberRoutesProbe，除特别说明） | 分类 / 理由 |
|---|---|
| LaborStore.lua:25–38、117 | 提交：为权威 Job/记录分配并写 claimId、推进持久 nextClaimSeq；不是纯缓存初始化。 |
| LaborStore.lua:150–161 | 提交：碰撞重分配 claimId，直接改 Job state/effects，并调用 domain identityCollision；没有 CAS/revision。 |
| LaborStore.lua:44–76、166–204、260–277 | 提交：隔离记录恢复/转态/碰撞证据发布；其内 rebuilt:restoreQuarantine/quarantine 的运行时索引重建本身非提交。持久隔离变化不能从恢复路径排除。 |
| HaulJobRecovery.lua:23–24、36–43、57–59 | 提交：直接修改持久 state/effects；57–59 在容量恢复失败时释放 token，尚未通过同一内核隔离/恢复。acquire/restore 的同事实索引重建部分非提交。 |
| CraftJobRecovery.lua:15–22 | 提交：碰撞/认领失败直接写 UNKNOWN；成功 acquire 的同事实索引重建部分非提交。 |
| FieldJobRecovery.lua:14–27 | 提交：碰撞/容量恢复失败写 UNKNOWN 并释放 token；成功 acquire/restore 的同事实重建部分非提交。 |
| CookingJobRecovery.lua:14–27 | 提交：碰撞/工位容量恢复失败写 UNKNOWN 并释放 token；成功 acquire/restoreWork 重建部分非提交。工位容量与 HAUL 物品容量不是同一种输入。 |
| ActivityJobRecovery.lua:14–21 | 提交：碰撞/认领失败写 UNKNOWN；成功 acquire 同事实索引重建部分非提交。 |
| SelfCareJobRecovery.lua:13–14、17–24 | 提交：Record.death(job) 直接改变权威 payload/状态，或写 UNKNOWN；成功 acquire 的同事实重建部分非提交。 |
| CraftLegacyRecovery.lua:47–69 | 提交：旧 CRAFT payload 与 envelope 原地修改并 revision+1；禁止本轮扩展旧档迁移，故原样开放。不是当前支持格式内核迁移已完成的证据。 |
| shared/JobStore.lua:98 | 非业务提交：open 已验证根后发布同一 ledger handle；新空 ledger 初始化不创建/删除业务 Job。157–242 的实际发布/删除已纳入前表。 |

`TaskJobs.current()` 仅返回同一 JobStore，订阅与索引绑定非提交。`CookingBudget.view`、BusinessJobs 的 records/crafts/hauls/canRetire、监控/Provider 对 root.taskJobs 的读取非提交；其后续写不能继承该分类。

## LaborDomainAdapters：全部操作逐项分类

行号为 `client/EmberRoutesProbe/LaborDomainAdapters.lua`。所有 `Store.data()` 的首次调用还可能触发上表持久恢复；下列只读分类不豁免其间接恢复写。

| 入口 / 行 | 分类与理由 |
|---|---|
| install / 4 | 非提交：安装函数引用。 |
| claimCooking / 6 | 同已提交 claimId/序列/集合的 token 重建非提交；ensureEntityClaimId 写新身份的分支是提交，开放。 |
| transferCooking / 16 | 提交：持久 NPC 所有权转交后重领 token；不能只改 revision。 |
| validCooking / 32 | 非提交：已有记录/token/scope 守卫。 |
| replaceCooking / 40 | 提交：claims replace、工位容量变化、Job CAS、失败补偿及 token 接续是同一链。 |
| availableCooking / 75 | 非提交：读取可用容量。 |
| finishCooking / 79 | 提交：已验证 SETTLED 后实际解除 claim/token；不能独立于发布和幂等结算。 |
| claimPersonal / 86 | 同事实重建非提交；新 claimId 持久分配分支提交，开放。 |
| claimActivity / 97 | 同事实重建非提交；新 claimId 持久分配分支提交，开放。 |
| claimField / 107 | 同事实重建非提交；新 claimId 持久分配分支提交，开放。 |
| validField / 118 | 非提交：scope/版本/token 守卫。 |
| replaceField / 124 | 提交：replace + Job CAS + 旧集合补偿。 |
| reserveField / 135 | 提交：新增/改变容量承诺，不能因该函数未写 Job 而豁免。 |
| finishField / 139 | 提交：解除 claims，并修改 toolCustody.activeJobId；原件责任不是派生缓存。 |
| settleActivityWedged / 162 | 提交：UNKNOWN 核对后写 SETTLING/KNOWN，再释放位置责任。 |
| validActivity / 174 | 非提交：token、序列、NPC 守卫。 |
| finishActivity / 180 | 提交：清持久 claims，再释放 token。 |
| validPersonal / 189 | 非提交：scope/attempt/token 守卫。 |
| settleDeadPersonal / 198 | 提交：死亡证据发布；保留原件与否来自 Lua Record.deathRetained，Java 不得重新决定。 |
| finishPersonal / 230 | 提交：先清持久 claims，再释放 token。 |
| releasePersonalSeats / 243 | 提交：由已提交 claims/物理退出证据解除家具运行时所有权；不是任意清 token。 |
| extendPersonal / 253 | 提交：原生输出发布后的新原件认领；冲突时必须保留声明核对。 |
| claimHaulJob / 259 | 非提交部分：同 claimId 的运行时重领/代次 fence，不改变已提交集合或容量责任。Store.data 的持久恢复另列。 |
| validHaulJob / 269 | 非提交：只读守卫。 |
| claimCraft / 276 | 非提交部分：同 claimId 的运行时重领/代次 fence；returnOnly 守卫保留 Lua。 |
| validCraft / 286 | 非提交：只读守卫。 |

## LaborStore 转发与原件边界

| 入口 / 行 | 分类与理由 |
|---|---|
| claim / 551、pause / 568 | 提交：可能经 HaulJobs.claim 创建/推进 Job；已有任务单纯同事实重领部分非提交。 |
| settleHaulLines / 555、publish / 559、finish / 592、clear / 600 | 提交：分别发布物品行效果、payload、终态/清理；clear 的原件守卫不能删除。 |
| capacity / 571、releaseCapacity / 580 | 提交：HAUL 转发到 Job 提交；非 HAUL 分支直接改容量，仍是资源提交开放项。 |
| quarantineResource / 409、unquarantineResource / 445 | 提交：持久隔离与原件/容量所有权转移；内核可调用的资源原语，不是内核外自行提交的许可。 |
| claimCustody / 639、releaseCustody / 682、assignToolUse / 700、assignToolReturn / 725、abortToolReturn / 741、completeCustodyReturn / 755、settleNpcDeath / 796 | 原件责任提交：独立 custody 记录写与 Job 使用声明有关；保持既有规则，不能迁成 DEC-004，也不能把其 Job 关联改动归为只读。该组不新增任务，但原件/容量变更仍待同链边界处理。 |
| record / 344、recent / 349、owner/resourceOwner / 371–372、claimsVersion / 373、claimsInstance / 374、getToken / 385、quarantineRecord/quarantineAuditRecord / 437–441、hasTaskClaims / 535、recoveryGeneration / 542、valid / 563、availableCapacity/availableFor / 590–591、canClaimTool/validToolUse / 610–623、custodyForNpc/custodyByItem / 709–721 | 非提交：读取或派生视图；claimsInstance 暴露的是可变 primitive 句柄，调用者对它的写仍按提交分类。首次 data 恢复见前表。 |
| cleanToken / 375 | 终态后派生引用清理本身非提交；其中 claims.tokensByTaskId 删除须由已验证的资源释放授权，不是判定结清的依据。 |

## Phase 0 结果与重跑

75 个显式调用/原语位置已分类；另登记原始恢复写、身份分配、隔离、全部 domain adapter、LaborStore 转发/资源责任操作。没有将恢复、resume-only、删除或纯 revision 写当作边界豁免。
没有发现仍需猜测才能分类的 Job 写；**全部 kernel 外提交都仍开放，未迁移**。这不等于最终边界审计通过。

本轮只改文档，最终树重跑相同扫描，生产源码相同，调用清单无差异。后续改代码必须重新执行全局边界审计；本次 Phase 0 不能替代迁移后的 Phase 12。
