# DEC-003 COOKING migration 4/7 — OPEN / partial

2026-11-04；基线 `phase-3a-consolidation` / `47de22cad68e35b797c67627987d6866f5f1885f`，起始工作树空。完整读取外部 `~/workspace/goals/emberroutes-npc-realism/files/dec003-cooking-migration-brief.md`，它只是准备资料；本轮按 HEAD 复核入口，沿用 [Phase 1](dec003-phase1-contract.md)、[CRAFT](dec003-craft-migration.md)、[FIELD_WORK](dec003-fieldwork-migration.md) 的 create / diff mutate / cancel 模式。没有新需求设计、在线需求同步声明、Java 或其他域迁移、提交或推送。

**仅无 work-capacity 的运行时提交链已迁移。容量链与 transfer 硬停止，预发布 recovery / shared identity / SELF_CARE retire 均登记开放；不能称 COOKING 完整迁移或关闭 DEC-003。** 保留的容量代码是未迁移的明确业务分支，不是 kernel 失败后的 fallback；kernel 拒绝绝不转回旧事务。

以下 `C/` = `Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/`，`S/` = 同级 `shared/EmberRoutesProbe/`，`J/` = `java/src/main/java/emberroutes/probe/`。仓库根 `/home/hatch/workspace/repos/ProjectZombie-EmberRoutes`。HEAD 列指修改前；最终列指交付工作树。brief 主要提供符号而非旧数字行号，不能伪造漂移量。

## 所有迁移点与 HEAD 引用复核

| 入口 / HEAD 47de22c | 最终 / 分类 |
|---|---|
| S/CookingBudget.lua:34–64 reserve；create :63 | :63 改 Store.createClaimedJob；所有配额/其他任务/stock stamp 守卫保留 |
| C/CookingService.lua:360–431 claim；REQUEST :396、AUTO :417 | 不变；REQUEST book:reserve、AUTO Supply.reserve，均只有上述一个 create endpoint |
| C/CookingSupplyService.lua:87–106 reserve；book:reserve :103 | 未改；真实 cache / claims revision / stamp / population 重验后同一 Budget |
| C/LaborDomainAdapters.lua:6–15 claimCooking | :6–20；same-fact reclaim，清旧 generic token cache；identity 分配仍 OPEN |
| 同文件 :32–39 validCooking / :40–74 replaceCooking | :37–44 / :45–98；:50–69 无容量 diff + kernel；:70–97 容量相关旧事务 OPEN |
| 同文件 :75–78 availableCooking | :99–102，只读 work capacity |
| 同文件 :79–86 finishCooking | :104–114，终态 cleanup；允许 kernel 已清 token，保留记录/NPC/revision/gate；传入 token 时仍 validCooking 验证 |
| C/CookingContext.lua:16–21 publish；:22–31 unknown | 未改，一次 publish 一次 adapter call；无容量时一次 kernel mutate |
| C/CookingAgent.lua:240–252 start | 未改，SUSPENDED→PREPARING→RUNNING 两次 publish；保留每步 revision |
| 同文件 :254–272 completion | 未改；heat closed / OUTPUT DELIVERED / capacity release / claims-duty-station gate 后 SETTLING；capacity release 部分 OPEN |
| C/CookingContext.lua:45–53 pause；:68–90 persist | 未改；STOPPING、SETTLING 后 DONE/CANCELLED、UNKNOWN/暂停各自 publish；容量承载 publish 的例外见下 |
| C/CookingService.lua:346–359 rejectEmpty | :349 SETTLING kernel mutate；:352 cancelJob；有 token :355/:357 经 adapter |
| 同文件 :495–591 command，直接 update :511/:522/:535/:550 | 原行号不变，四处均改 payload-only Store.mutateJob |
| 同文件 command 无 token :578/:583 | 原行号不变，SETTLING mutate + cancelJob；有 token :563/:569 经 adapter |
| C/CookingAgent.lua:286–293 persistFailure | :291 改 Store.mutateJob，不改变 claims/capacity |
| C/CookingHandoff.lua:16–58 → adapter :16–28 transferCooking | Handoff 不变；adapter 最终 :21–33，直接 transfer :26；OPEN kernel-external |
| C/CookingService.lua:104–140 recover rescue；调用 :136 | 未改，四个候选的 duty rescue → Handoff.transfer；OPEN，不冒充 mutate |
| C/CookingJobRecovery.lua:3–38 restore | 未改；:14–15 / :20–21 / :25–26 三组 UNKNOWN 原表写 OPEN |
| C/LaborStore.lua:25–39 allocator / :43 root / :296 restore / :331–340 publish | 未改；shared / pre-publish OPEN；没有 CookingService.prepareRecovery |
| C/CookingService.lua:453–483 retire，SELF_CARE :470 | 未改，跨域 SELF_CARE OPEN；removeSettled :474 kernel-external |
| C/CookingService.lua:209–243 crewScan、:420 ORDER linkage | 未改，仅 publicWork orders；不是 taskJobs |

全族检索 `Cooking*.lua` 的 create/update/CANCELLED/publish、adapter Cooking 区段与 TaskPersistence，未发现另一个 COOKING create 或 prepareRecovery。迁移后 Service 唯一剩余 `Jobs.current():update` 为 :470 的 SELF_CARE 写；Agent/Budget 的旧直接 Job 写已删除。adapter 直接 update 仅在已分类的 capacity-bearing 分支 :86；transfer :26 另行分类。没有删除共享 LaborStore/LaborJobCommit、其他领域 adapter 或 JobStore.removeSettled。

## 八项边界决定与停止证据

1. **transfer：硬停止 / kernel-external COOKING ownership commit。** `CookingService.recover:127–139` 只对 duty+stopProof 搜救，`CookingHandoff:18–57` 验 runtime 空闲、Record.handoff、revision、RECOVERY 权限、炉具位置/开关/内容与原件/炉具所有权，然后 claimCooking → transferCooking。adapter HEAD :21（最终 :26）调用 `S/JobStore.lua:224–243 transferOwner`，:237–240 发布新 npcId 并改 byNpc 索引。普通 update :187–188 的 patch 白名单没有 npcId；kernel :82–95 检查 claim identity/owner，没有 transfer API。`CookingRecord.lua:363–381` handoff/transferValid 另验 stopped proof、同任务新 owner 与 duty revision；adapter 最终 :29–31 重新 acquire，旧 callback 会被 revision/NPC/token fence 拒绝。该旧 token 轮换不是 kernel transfer 证明，不将 npcId 塞入 payload，不添加 API。原链完整保留开放。

2. **payload-only bypass token：可迁移，无需 claimCooking。** command stop/resume/live-return/held-return 的 `p=Record.copy(job.payload)` 只改 pauseRequested、cancelRequested、reason（Service :507–550），没有改 claims、capacity、assets 或义务。调用 `Store.mutateJob(id,revision,p)`，不发送 addKeys/removeKeys/capacity。persistFailure 的 Agent :287–291 在 c.token 存在时不写；没有 token 时仅 state=SUSPENDED 和 payload.reason。`LaborJobCommit.lua:30–42` 接受 nil mutation；`J/LaborCommitKernel.java:89–93` 无 token 只拒绝资源命令，不拒绝此记录写；有 token 仍执行 :82–95 身份/owner 检查。无须竞争 agent 的 token，不引入 claimCooking deadlock。payload 保留责任不等于已重新认领。stop 先 runtime.stopJob 再 flag、held-return 写 flag 后 recover(actor,旧 job) 的顺序及原先忽略写失败的返回行为保留，未借迁移修业务。后续 session 可能因 command 增 revision 而 stale；本轮不重设计 TaskRuntime，不保证此旧协作时序可继续。

3. **work capacity：硬停止，所有 beforeCap 或 afterCap 的 adapter publish 都留 kernel-external。** `CookingCapacity.lua:19–22` 的 claim 是 `cooking:capacity:<job.id>`，payload 是 `{endpointId,amount}` / obligations.storage。`S/LaborClaims.lua:505–516 restoreWork` 以 batch claim 而非 item claim 验权，存 `{items={},count=0,amount,workAmount}`；无 free 字段，独立于可能被原生配方替换的 ItemID。`J/LaborCommitKernel.java:98–107` 既要求 capacityMutable（S/BuiltinJobContracts.lua:9–14 COOKING 未注册），又要求 `{key,items<number,number>,free}` 或 false/releaseItemId；`J/ClaimsKernel.java:124–131` reserveMany 要逐 item 原件所有权。不能使用虚构 item ID、把 weight 塞 claims 或丢弃 promise。即使容量不变也不能只迁移 claims：kernel Tx :26–31 只 snapshot items、:51–53 restore 先全释放再逐 item restore，**不 snapshot/restore workAmount**；resource CAS 拒绝会丢掉 work promise。因此分支必须覆盖 before/after 任一有 capacity，而非仅 capacityChanged。原 replace/restoreWork/update/rollback 只留在最终 adapter :70–97；没有让该分支先试 kernel 再 fallback。此停止意味着 native coldGate→reserve、带容量 unknown/pause、delivery shrink、release 的 publish 仍可能走旧 Job 写，明确列入开放范围。不能宣布“每个 publish 均已 kernel 化”。

4. **recovery：硬停止 / pre-publish 原表 COOKING commit。** `LaborStore.data:43` 的 current=Registry.data() 是别名，无复制；:296 → `LaborRecovery.lua:11–12` → `BuiltinLaborRecovery.lua:9` 注册的 CookingJobRecovery.restore，后者 :9 遍历 current.taskJobs.byId。冲突 :14–15、acquire 失败 :20–21、restoreWork 失败 :25–26 直接改 state/effects，无 revision 增量。:331–340 再将同一 current 发布为 root/domainState。这些写会到达已发布 store，甚至 Registry 原表已先可见；不是独立 rebuild copy。此时 kernel 重入 Store.data 将再次进入未完成的构建，claims/token authority 尚未发布。按用户停止规则，不强行 kernel、不新增 pendingCooking 队列/authority、不移动跨域恢复阶段。正常 acquire/restoreWork 成功只是同事实索引重建。`TaskPersistence.lua:49–52` 已有其他域 prepareRecovery，COOKING 没有，未发明一个。

5. **shared identity：OPEN shared persistent allocation。** claimCooking 最终 :11 调 `LaborStore.lua:30–39 ensureEntityClaimId`，缺/非法 identity 时 :35–37 分配并写 entity.claimId，:25–27 改 nextClaimSeq；field/personal/activity/cold recovery 共用，不能按 COOKING 单段迁走。kernel create 分配合法 ID 让正常新建 re-claim 返回现有身份，但没有删除异常/恢复分支。未改共享 allocator。新增的 generic→cooking cache 移交仅发生在 COOKING claimCooking :13–17：kernel create 的 Java :180–181 同时写 generic 与 domain cache，Store.getToken :406 优先 generic；re-acquire 后保留旧 generic 会让下一 kernel 取失效 token，故成功 re-claim 清该条 generic，后续仅旋转 cooking cache。没有改共享 lookup 或其他域。

6. **retire：OPEN SELF_CARE-segment commit。** `CookingService.lua:463–470` 仅匹配 other.providerType SELF_CARE，检查 payload.resume.kind COOKING / jobId，写 RESTORED 或 INVALIDATED 再直接 update(other.id)。变更对象属于 SELF_CARE，不是 COOKING；本轮未迁移。:474 removeSettled 是 Phase 1 明确保留的 kernel 外退役，不是漏迁，也没有新 delete API。

7. **ORDER / Job：不是提交口。** Service :420 的 o 来自 `CookingOrders.get:72–74` 的 root.publicWork.orders；:209–243 的 crewScan 同样遍历 world.publicWork.orders，只改 o.state/reason/revision 或 `Orders.wait:16–19`。没有将 o 放入 taskJobs。Job 的 payload.source/sourceId 仅连接需求；Orders.settle :102–128 只读取 Job 并改 order（:122 清 jobId、累计 delivered），不改 JobStore。Service offers/retained 是本模块目录保留缓存。Orders.command :76–101 可以调用 runtime.stopJob；该 runtime stop 产生的 session Job publish 属于下面取消/暂停链，不能把它误记为 ORDER 直接 Job 写。

8. **取消入口穷举：迁移范围统一 mutate SETTLING → kernel cancel CANCELLED。** rejectEmpty 两个调用者是 Service.claim :426 token 失败、:428 prepared replace 失败；有 token 经 adapter 两步，无 token 先 :348 验 KNOWN、空 claims/assets、无 task claims，再 :349 mutate、:352 cancel。kernel create 本来就发布一个空 token；若 re-claim 失败而该 cache 仍在，hasTaskClaims :555 会挡住补偿（OPEN admission-retention case），不删除 cache 假装无责任。定向测试明确模拟真正 token loss 后才执行 no-token path。command return-live :531–538 / held :546–554 仅 flag，recover :118–125 转 settleOnly；not-live/not-held :557–585 token 分支经 adapter SETTLING + cancel，无 token 且空 claims 分支 mutate + cancel。Agent :56 的 settleOnly、heat :222 的 aborted 设置 c.cancelled；completion :254–271 验效果/归还后 SETTLING，Context.persist :79–84 在 completed+KNOWN+空 claims/义务+无 duty/station 后 CANCELLED，由 adapter 最终 :59 调 cancelJob。其他驱动 settleOnly 的 recovery 包括 duty、priority=0、work 不允许（Service :124）、用户/ORDER cancelRequested/stopBatchRequested（:118）；Orders.command stop/return 可 runtime-stop，再通过上述 recovery 重建 session。wake :102 / 普通暂停本身不是终态取消。kernel cancel 仍用 JobStore :217–220 的 KNOWN/空义务/空 claims 守卫及 CookingRecord :310–315 终态 gate；没有第三个 API，也未清责任以强过门禁。容量承载步骤的未迁移例外已在第3项穷尽分类；符合终态 gate 的最后无容量 CANCELLED 走 kernel。

## 创建、释放与异常闭环（限定迁移范围）

创建：Service.claim REQUEST :396 或 AUTO :417 → Supply.reserve :103 → Budget.reserve :63 → Store.createClaimedJob → LaborJobCommit :17–26 → Java create。PREPARING/revision1、空 assets/claims、sequence0 与 quota 守卫留 Lua；然后 claimCooking + replaceCooking prepared，用 addKeys 在 kernel 内先认领再 CAS。不提前发布新原件、不复制 REQUEST/AUTO 两套 create。

正常运行/释放：无容量 adapter 保留 Record.valid、scope/NPC/revision fence，token.resources 与 proposed.claims diff 为 add/remove，经 kernel check→extend→shrink→CAS；每次成功非终态重新 acquire 对应 sequence 的 token，保留 generation fence。Context.publish 不另增一次提交；DONE mutate、CANCELLED cancel 后 Java 释放/clean token，finishCooking 再做对称、幂等 cleanup，不能再要求已清掉的 token cache。finish 仍验终态、NPC、revision、Record、SETTLED/KNOWN/空 claims；如果提供 token 仍验证 validCooking。无容量旧 replace/update/rollback 路径已删除；共享事务没有删除。

异常：Context.unknown、pause STOPPING、stop persist SUSPENDED/RECONCILE_REQUIRED 保留各自业务 gate/原因与 stopProof。persist :71–73 **先** release waterSource / CraftStations lease，再 :82 或 :89 publish。前置 custody/lease cleanup 可能已可见而 terminal mutate stale/拒绝，kernel 不回滚外部 cleanup；保留原顺序，失败不建第二条补偿链，重载最后存档（未实测）。容量分支不借本轮修改现有失败处理；transfer/recovery/shared allocator 也未剪裁。Phase 1 callback throw/post-CAS cleanup/restore failure 的公开 marker 限制继续适用。

**有意契约变化**：取消从旧 update 转为 cancel（明确执行 Phase 1 cancel gate）；普通资源事务失败统一 kernel error/single restore，无容量分支不再旧 Lua rollback assert。kernel 缺失 fail-closed，不提供生产 fallback。正常持久快照除 create 时 claimId 更早注入外与旧链 parity；不宣称所有故障语义等价。

## 定向 parity 与真实测试范围

新增 `tests/lua/dec003-cooking-migration-test.lua`，旧侧仅加载三个 test-only `fixtures/dec003-pre-kernel-cooking-{service,budget,adapter}.lua`：service/budget 是精确 HEAD 内容加 provenance 注释，adapter 是 HEAD Cooking 区段（安装函数在 claimPersonal 前截断）。生产零引用 oracle。新侧复用既有 FIELD kernel host model，真实 LaborJobCommit / JobStore / Claims / CookingService.claim / CookingBudget / CookingSupplyService / Context / Agent.new/start；host 的 field token bucket 在本测试中别名 cooking bucket，未修改 FIELD fixture 或生产注册。

菜单/recipe 准备、MealSupplyIndex 原生扫描、NPC/body/native effects、TaskBusinessStop 回调驱动是明确替身。REQUEST 用 raw profile 观察 seam，真实 Service REQUEST 分支调用 Evolved.prepare 替身生成受 Record.valid 验证的 raw manifest；这不是原生配方组合能力证明。AUTO 用真实 SupplyService.observe/reserve cache、quota/demand/stamp 校验，同样的 kernel create。没有把模拟输出 DELIVERY 当作执行了原生 craft/heat。

| 对照快照 | revision / state | phase / assets / claims |
|---|---|---|
| REQUEST admission create | 1 PREPARING | PREPARING，空资产/claims；旧 JobStore 内分配 claimId，新 kernel 在 CAS 前注入 |
| claimCooking + prepared replace | 2 PREPARING | raw OUTPUT SOURCE item11，item:11 已认领 |
| Agent.start | 3 RUNNING | 每步真实 publish；另测 SUSPENDED start +2 revisions |
| 外部 revision 竞争 | 4 RUNNING | Context stale 拒绝，无 item12 部分发布 |
| 宿主观察交付 + SETTLING | 5 SETTLING | item11 DELIVERED effective=.3，空 claims |
| stop persist + finish | 6 DONE | SETTLED、KNOWN、空 claims/义务，token/owner 清除 |

五个完整 Job 快照 old/new 相等（create draft 的 claimId 注入时机单独断言并对齐后比较）。**容量主链 N/A 是停止范围，不是证明 native chain 不需要容量**；before/after capacity 都为空才能进入迁移路径。另测 capacity reserve 与保留 unchanged workAmount 的 publish 不调用 kernel，promise total=4 未丢；这是保留分支分类证据，不能算容量迁移通过。

共 **48 check 断言**，另有控制流/构造 assert 不计入48：真实 REQUEST/AUTO claim、AUTO 仅一次 laborCreate、prepared ownership、start、stale Context（Lua fence + adapter 之后 kernel STALE_REVISION 各一例）、完整 Job/claims 不部分发布、DONE finish、真正无 token rejectEmpty SETTLING→CANCELLED、command live-return flag→settleOnly session→CANCELLED/laborCancel、SUSPENDED 两步 start、无 token persistFailure 保留 claims、容量开放分支。

## 实际检查、失败与复现

从仓库根使用指定工具，无 system lua，无 Lua stdin/REPL：

```sh
LUA_PATH='Contents/mods/EmberRoutesProbe/42/media/lua/client/?.lua;Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;;' /home/hatch/workspace/tools/lua-5.4.8/src/lua tests/lua/dec003-cooking-migration-test.lua
```

最终定向选择 **10 个测试文件：5 PASS、5 未通过**；有 PASS 数字的合计 **200 checks = 48+21+16+61+54**。未跑整个套件，未修改既有回归或其断言。

| 测试 | 工作树结果 / HEAD 对照 |
|---|---|
| dec003-cooking-migration-test.lua | PASS 48 |
| dec003-kernel-boundary-test.lua | PASS 21 |
| cooking-plan-test.lua | PASS 16 |
| dec003-fieldwork-migration-test.lua | PASS 61；共享 adapter 非 COOKING 区段未改 |
| dec003-craft-migration-test.lua | PASS 54；未改 CRAFT |
| cooking-foundation-test.lua | 原始执行 FAIL :39，独立 quota fixture 未装 kernel bridge，第一次 reserve fail-closed；这是新调用契约导致的夹具适配缺口，不称为既有同一失败。HEAD 能运行第一段，到 :148 缺 work-test.lua 阻塞。定向 parity 已用完整 root/bridge 覆盖 Budget 两入口，未放宽生产 guard |
| cooking-supply-service-test.lua | BLOCKED 缺 tests/lua/work-test.lua；HEAD 相同 |
| cooking-agent-test.lua | BLOCKED 同上，multi-worker→cooking-actions→craft→agent；HEAD 相同 |
| cooking-public-test.lua | BLOCKED 同上，multi-worker→actions→water→evolved→heat→handoff→public；HEAD 相同 |
| labor-capacity-commit-test.lua | FAIL :7 Create claimed HAUL；HEAD 相同，独立 fixture 无 kernel bridge；不修 HAUL |

HEAD 证明：`git archive HEAD Contents/mods/EmberRoutesProbe/42/media/lua tests/lua | tar -x -C /tmp/dec003-cooking-head`，在该只含原 HEAD 的目录以相同 Lua/LUA_PATH 复跑上述五个失败/阻塞文件；未 stash、未重置工作树。临时尝试过 foundation/supply regression bridge runner，foundation 第一个独立 quota root 的重复 reserve 装配不完整，未保留该 runner、未改原断言或宣称通过；供应/agent/public 的缺文件在加载变更生产代码前就阻塞。

全部本轮 **8 份新增/修改 Lua**（4生产、1定向、3 oracle）用指定 `/home/hatch/workspace/tools/lua-5.4.8/src/luac -p` 检查，8/8 PASS；git diff --check 与全部新增文本 whitespace 检查均 PASS。标准 `.workbuddy/tools/pz.mjs` 工具本环境不存在；使用新增 segment/导航链接存在性检查，不把替代检查称为标准 doclink 通过。

## OPEN / 续接与 UNVERIFIED

需父任务决定的 kernel-external commit：work-capacity-bearing replaceCooking（全部 reserve/retain/shrink/release publishes），transferCooking ownership CAS，三组预发布 CookingJobRecovery UNKNOWN 原表写；shared ensureEntityClaimId/nextClaimSeq，SELF_CARE retire resume 写分别留共享/SELF_CARE segment。另有创建后空 token 仍在导致 rejectEmpty 保留、command 与 session revision 时序、前置 lease/custody cleanup 后 CAS 失败的业务/失败边界。removeSettled 是明确 kernel 外退役，不是新增 API 或 fallback。

**UNVERIFIED：Java compilation；real bridge calls / Java kernel parity；in-game parity（含原生 craft/heat/return、duty rescue、agent command 时序）；disk save/reload；performance。** 当前 java/javac 不在 PATH，无游戏；Lua host 不替代这些证据，不宣称性能提升、crash-safe、零损失或完整 COOKING 迁移。没有加入新 API、transfer/delete、quarantine/isolate、持久 receipt/recovery queue、TaskRuntime 重构、其他领域迁移或行为策略修改。
