# DEC-003 SELF_CARE migration 6/7

2026-11-04。基线 `phase-3a-consolidation` / `a16eb0b903ea681149df95996d0d48655f7efa60`；开始时 `git status --short` 无输出，分支/HEAD 符合用户要求。完整读取用户 brief，以下位置重新核对当前代码，不沿用 brief 的旧行号。本段为 **OPEN / partial**：运行时入口已接 kernel，shared identity、BusinessJobs 最后一段与冷恢复转换缺口仍开放。未提交、未推送。

本轮执行用户明确授权的领域迁移，不作新需求设计；未读取或宣称同步在线需求。沿用 [Phase 1](dec003-phase1-contract.md)，不修改 Java、kernel bridge、其他领域策略、TaskRuntime、NPC 行为或 DEC-004。

## 数据模型与提交闭环

以下文件简称的 client 前缀均为 `Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/`；shared 前缀为同层 `shared/EmberRoutesProbe/`。行号对应本轮工作树；未改文件亦与 HEAD 实读比对。

- 创建/认领：shared `SelfCareRecord.lua:11–14` 定义 format 1、PREPARING、revision 1、IDLE、sequence 0、claims `{}`、obligations `{}`。client `SelfCare.lua:29–36` 按 NPC 查找现有身份，仅不存在时 createClaimedJob；失败只重查，不盲目再 create。shared `JobStore.lua:161–163` 拒绝 PERSONAL_JOB_EXISTS。`SelfCareCommit.lua:5–31` 仅映射 SELF_CARE patch 为 mutate + addKeys/removeKeys；claims 变化且无 token 时，先对**当前事实**调用 claimPersonal，随后由 kernel 执行资源变化。缺桥在任何认领之前拒绝。
- 正常释放：`SelfCare.lua:95–102` idle 先 mutate IDLE/清义务，再 finishPersonal；`LaborDomainAdapters.lua:240–249` 保留同 attempt、KNOWN、零义务门禁，mutate 清 claims，成功后才 release token/cleanToken。释放没有合并入 Job CAS。
- 异常打断：`SelfCareExecution.lua:112–176,252–289` 的 finish/persistFailure/stopAdapter 保留观察证据、IDLE/SETTLING/UNKNOWN 判定及逐步提交；`SelfCare.lua:505–525` prepareRecovery 与 `SelfCareReconciliation.lua:9–93` 处理无停止事实的恢复。责任不是通过超时、消失或清内存解除。
- 反复身份：shared `SelfCareRecord.lua:150–159` 的 begin 要求 KNOWN、IDLE、零义务、零 claims；返回 `sequence+1`、`attemptId=job.id..':'..sequence`，不创建新 job。SUSPENDED 是可继续使用的个人身份，不是可退役记录。

## 每个迁移点

| 文件 / 函数 / 当前位置 | 调用者及映射 |
|---|---|
| `SelfCare.lua:29–36` personal | advance 三种候选入口；直接 create 删除，换 createClaimedJob；保留一个 NPC 一个身份 |
| `SelfCare.lua:95–102` idle | settle 的 CANDIDATE_NOT_STARTED / PERSONAL_STOPPED；mutate 后 finishPersonal，两个 revision |
| `SelfCare.lua:304–335` LEISURE attempt | begin 的 REQUESTED mutate；失败恢复 before payload 仍单独 mutate；未合并 finishPersonal |
| `SelfCare.lua:387–409` REST/SLEEP attempt | REQUESTED mutate、claim 失败恢复、submit 失败清 claims 后恢复 before payload；全部走 Commit.update |
| `SelfCare.lua:425–455` EAT/DRINK/STUDY attempt | payload + RETURN_ORIGINALS 的 mutate；rollback 先清义务、finishPersonal、再恢复 before payload/obligations，保留分步 revision |
| `SelfCare.lua:505–525` prepareRecovery | retired/dead 委托 live settleDeadPersonal；LEISURE STOP_CONFIRMED 与 ACTING UNKNOWN 分别 mutate |
| `SelfCareExecution.lua:67–75` c.persist | 所有 leaves 的持久事实写；从 live job 保留 resume，payload/effects/obligations 统一 mutate |
| `SelfCareExecution.lua:99–110` claimOutputs | native output 已生成，记录 item ID 后由 c.persist 的 addKeys 事务认领；extendPersonal 只核验，无第二次资源写 |
| `SelfCareExecution.lua:112–176` finish | 首次 persist、finishPersonal 清 claims、RUNNING→STOPPING、→SUSPENDED/RECONCILE_REQUIRED 均为独立 mutate；活动结果投影不充当释放证据 |
| `SelfCareExecution.lua:197–211` start | 必要的 SUSPENDED→PREPARING、→RUNNING、ACTING/SETTLING persist 逐步 mutate；STOP_NOT_CONFIRMED 与 PERSONAL_CLAIM_CONFLICT 留 Lua |
| `SelfCareExecution.lua:252–289` stop paths | persistFailure/stopAdapter 最终调用同一 finish；retired/dead 委托 settleDeadPersonal；不把 Runtime handle CANCELLED 写成个人 Job CANCELLED |
| `SelfCareReconciliation.lua:9–93` M.run | 仍先做 detached 扫描/证据门禁和 claimPersonal；最后 KNOWN/SUSPENDED mutate，IDLE 时再 finishPersonal |
| `SelfCareJobRecovery.lua:3–30` M.restore | death、claim conflict、acquire failure 不再原表改 Job，生成本次调用的 detached proposal；成功 acquire 仅重建同事实 token |
| `LaborStore.lua:46–47,297,330–358` | 只增加 SELF_CARE 本次调用的 pendingPersonal；完整 root/token cache 发布后按序 Commit.update，非 retained death 成功后 release/清派生 token；失败抛 PERSONAL_COLD_RECOVERY_FAILED，不自动补偿、重试或隔离 |
| `LaborDomainAdapters.lua:87–96` claimPersonal | 同事实 acquire 未改；ensureEntityClaimId 新身份分支明确保留 shared open，见后文 |
| `LaborDomainAdapters.lua:199–205` validPersonal | scope/attempt/token guard，非提交，未转换 |
| `LaborDomainAdapters.lua:208–238` settleDeadPersonal | live death 的 UNKNOWN 分支与 Record.death(proposed) 分支均 mutate；保留 SUSPENDED 转换 fence，非 retained 时仅 CAS 成功后释放 |
| `LaborDomainAdapters.lua:240–249` finishPersonal | 清 claims mutate + removeKeys；KNOWN/零义务与 post-CAS release 不变 |
| `LaborDomainAdapters.lua:253–271` seats / extend | 原 claims:replace / extend 删除；所有现有调用均先 persist，资源变更折叠到那个 mutate，adapter 保留 guard/一致性核验 |
| `TaskResume.lua:33–38` invalidate | 也是个人 payload 写，连同 prepare/stopped/resume/recovery 一次迁移；epoch 账表不是 Job，未改其策略 |
| `TaskResume.lua:51–85` prepare | 当前为空/MEMBERSHIP_RETURN/普通 predecessor 分支三个 payload mutate |
| `TaskResume.lua:87–114` stopped | RESTORE_QUEUED→RESTORED/BLOCKED，以及 REQUESTED 的确认/失效/拒绝，两个写入口均 mutate |
| `TaskResume.lua:116–170` resume | ACTIVE 确认、COMPANION queued、COOKING/FIELD 失效与 queued、PRODUCTION/TRANSFER queued，共五个写入口，目标均 SELF_CARE；business Job 自身状态不改 |
| `TaskResume.lua:172–210` prepareRecovery | receipt 经 stopped funnel；TRANSFER generation remap mutate，校验及代际证据留 Lua |
| `CookingService.lua:463–470` retire | 仅 SELF_CARE resume 的 RESTORED/INVALIDATED 写接 Commit.update；烹饪自身 retire/removeSettled 不改 |
| `LeisureService.lua:435–444` consumeResume | 运行时全局复查发现 brief 未列的个人 resumeHint 写；SelfCare.advance 的 need/恢复候选调用此处；只将该条 Job 写接 Commit.update，清 hint 的业务条件不变 |

生产代码不引用 tests/lua/fixtures；旧 direct create/update 仅以 a16eb0b 测试 oracle 保留。Shared LaborJobCommit、Java、JobStore.removeSettled 没有删除或改写。

额外的明确缺陷修复：旧 LEISURE submit 拒绝分支忽略 finishPersonal 和恢复 before 的失败（HEAD SelfCare.lua:329–331）。本轮 `SelfCare.lua:332–334` 检查结果，分别抛 PERSONAL_RELEASE_FAILED / PERSONAL_ROLLBACK_FAILED，阻止把失败回滚当成功继续执行；不新增恢复状态或重试。这与等价入口替换分开记录。

## 七项歧义与容量决定

### 1. Cancel / 正常结束 / 删除：kernel cancel N/A

逐调用者核对：

| 意图/调用者 | 当前证据 | 结果 |
|---|---|---|
| settle 放弃未开始候选、原生效果已结清 | `SelfCare.lua:104–121` → idle → finishPersonal | IDLE + SUSPENDED 身份保留，mutate |
| 提交拒绝、准备失败 | `SelfCare.lua:327–335,395–409,444–455` rollback | 恢复同 job 的 before，不取消身份 |
| 原生正常结束、halt、persistFailure | `SelfCareExecution.lua:112–176,252–289` | IDLE/SETTLING/UNKNOWN，mutate |
| REMOVE | `Work.lua:147–152` → `SelfCare.prepareRemoval:77–85` → Runtime.stopJob | 仅 gate；有 runtime 则请求停止并返回 false，无删除 |
| danger / user sleep / needs / social invite / study reevaluation / error | `SelfCare.lua:206,221,225,233,492` → Runtime.stopJob → execution finish | 停一个 attempt，mutate |
| leisure work-ready | `LeisureService.lua:73–82` → Runtime.stopJob → execution finish | 身份继续存在，mutate |
| membership retirement / death | `SelfCare.lua:509–512,534–541`、`SelfCareExecution.lua:174–175` → settleDeadPersonal；冷恢复单列 | retained/非 retained 都是 mutate，不是 cancel |
| predecessor settled / user supersede / business retire | `TaskResume.lua:33–38,87–114,116–170`、`CookingService.lua:463–470`、`BusinessJobs.lua:84–89` | 只改变个人 resume 关系，不终结个人 Job |
| Runtime pending cancellation / replacement / save stop | `TaskRuntime.lua:122–145` 的 CANCELLED 是 handle result；active 走 controller stop 与 spec.persist | 不是个人 Job 的终态；未新增 cancel 映射 |

运行时 grep SelfCare*.lua、SelfCareRecord.lua 未找到个人 Job DONE/CANCELLED 赋值或 delete/removeSettled。`BusinessJobs.lua:48–54` canRetire 只接受 CRAFT/HAUL，`:103` retireSettled 跳过 SELF_CARE；shared `JobStore.lua:244–249` removeSettled 首先拒绝 personalJob。没有发现额外删除/退役个人身份的调用者；removeSettled **未迁移**，也从来不适用个人 Job。

### 2. TaskResume / BusinessJobs 所有权

TaskResume 全部个人写与 CookingService 的个人 retire 写由本段拥有。`BusinessJobs.lua:84–89`（尤其 `:88`）RESTORE_QUEUED→RESTORED **正式留给 BusinessJobs 最后一段**，不在本段重复转换。最后一段应复用 SelfCareCommit 更新目标个人 Job，不能再次迁移 TaskResume 或更改个人 recurring 终态。此处是有名的 kernel-external SELF_CARE commit OPEN；见本段开放项。业务任务自己的 PAUSED/SELF_CARE 与 removeSettled 不属于本段。

### 3. 多次结束提交

未证明中间状态不可观察，因此不合并。新测试实际 service 路径的 revisions：1 create IDLE；2 REQUESTED；3 STOP_CONFIRMED；4 RUNNING；5 ACTING；6 IDLE（claims 仍声明）；7 finishPersonal 清 claims；8 STOPPING；9 SUSPENDED。release 在第 7 次 CAS 后发生。下一 attempt 在同 job 上继续 revision 10 REQUESTED / sequence 2，再写 STOP_CONFIRMED。SUSPENDED→PREPARING 在下一次 start 另有 revision；测试不把它退役或创建新身份。

### 4. 独立 claims 写调用链

brief 漏列 extendPersonal 的 StudySeat/StudyRelief 调用；本轮重新 grep 全树并逐链核对：

- `SelfCareExecution.lua:99–110` claimOutputs：追加 outputs → c.persist → extendPersonal。
- `StudySeat.lua:78–87`：readingSite/claims → c.persist → extendPersonal；失败回退自己的候选信息，仍经 c.persist。
- `StudyRelief.lua:58–59`：floor key → c.persist → extendPersonal。
- `StudyRelief.lua:70–73`：personal item → c.persist → extendPersonal。
- `StudySeat.lua:8–25` release：物理退出门禁 → 清 readingSite/seat claims → c.persist → releasePersonalSeats；调用者为 release、clearSeat/halt/exit，以及 Execution.finish 的已退出证据分支。
- `StudyRelief.lua:24–29`：成功完成 floor sleep → 去 floor key → persist（调用 c.persist）→ releasePersonalSeats。

没有不配对的独立资源写调用者。所有 add/remove 均进入 c.persist 的同一次 kernel mutate；原 adapter 改为只读 guard，未新建独立 mutate 或重复 revision。StudySeat/StudyRelief 本身不改，不把其他 SelfCare leaves 接到 kernel。

这是 Phase 1 事务契约要求的顺序变化：旧链先发布声明、再 extend/replace；新链物理 native output 仍先发生，资源 extend/shrink 在 CAS 内，失败恢复原 Job/claims。不会删除或按类型重建原件/输出。**CAS 前拒绝不再持久发布一个未认领的 output 声明**；物理 output 已生成但 commit 失败时，本段不能提供持久 receipt 或零损失保证，应按 Phase 1 限制诊断/重载最后存档；没有添加隐藏表、UNKNOWN 失败二次发布或“成功”兜底。真实 native failure 链未实机验证。

### 5. Shared identity：保留 OPEN

`LaborDomainAdapters.lua:93` claimPersonal → `LaborStore.lua:30–39` ensureEntityClaimId：无合法身份才分配并直接写 entity.claimId；相同函数服务 cooking/activity/field 等，不能只为 SELF_CARE 改共享分配。新 kernel create 正常路径已经分配 claimId，不要求调用此分支，但当前共享恢复/分配入口仍存在。

`LaborStore.lua:149–162` identity collision 分配新 claimId，并可原表写 Job 的 RECONCILE_REQUIRED/UNKNOWN；同一 candidates 循环服务多个领域。本段未改、未声称迁移。正常同事实 acquire 与 validPersonal 非提交；custody 的 claim/release/assignToolUse/assignToolReturn 不转换。

### 6. 冷恢复与已发布恢复

HEAD `LaborStore.data` 在原 `:296` 调用 SelfCareJobRecovery，再在原 `:330–339` 发布 root/claims/domainState。原 restore 的 death/conflict/acquire-failure 原表写属于**发布前重建阶段中的事实变更**，不是 live settleDeadPersonal。当前 `SelfCareJobRecovery.lua:6–25` 仅排 detached proposals，`LaborStore.lua:330–358` 发布所有 cache 后才 mutate；pendingPersonal 为本次调用局部变量，不保存、不建 receipt/recovery authority。成功 acquire 是同事实重建，保留。

`TaskPersistence.lua:51` Store.data 在 `:55` prepareCareRecovery **之前**。`SelfCare.lua:544–547` 先调用 Resume.prepareRecovery 再 Service.prepareRecovery，因此 LEISURE STOP_CONFIRMED 和 ACTING UNKNOWN 都是 published commit，直接经 kernel，不进冷队列。

**硬停止 / 转换缺口**：Record.death 非 retained 分支（shared `SelfCareRecord.lua:136–148`）要求 SUSPENDED；如果存档 Job 仍 RUNNING，shared `JobStore.lua:13,199` 拒绝直接 RUNNING→SUSPENDED。旧冷恢复靠原表 mutation 绕过此 fence；本段不允许继续绕过，也没有证据授权编造 STOPPING/停止事实。此组合的 proposal 会返回 TASK_WRITE_FAILURE，`LaborStore.lua:351` 明确中止恢复，原 Job 保留；定向测试验证拒绝。该分支不能宣称 parity 已完成；需最后的恢复契约审查解决。retained death→RECONCILE_REQUIRED、冲突/失败 UNKNOWN 走正常允许转换。其他不允许转换同样 fail-closed，不增加例外。

### 7. 同身份 invariant 与容量 N/A

定向主链断言两个 attempt 使用同一个 `personal` ID，sequence 0→1→2、attemptId personal:1→personal:2，forNpc 只有一个个人身份；没有 DONE/CANCELLED/delete。

本轮执行 `rg -n 'capacity'` 于 client 的 `SelfCare*.lua TaskResume.lua StudySeat.lua StudyRelief.lua`，无匹配（exit 1）。另实读 PERSONAL adapter `:87–96,199–271` 未见 reserve/releaseCapacity 或 capacity 命令；claims 只有有限 item/家具/活动位置 keys，shared `SelfCareRecord.lua:22` 上限 16。本段 capacity **N/A**，没有新增 capacityMutable 或 Java 命令。

## Interrupted attempt 与 RETURN_ORIGINALS

ACTING 没有 stopped fact → Service.prepareRecovery (`SelfCare.lua:518–522`) 写 payload.step RECONCILE_REQUIRED、effects UNKNOWN、Job.state RECONCILE_REQUIRED，保留 RETURN_ORIGINALS 与 claims。Reconciliation.run 先拒绝仍有 runtime/body、无绑定、queue 不可用/忙、sleep/rest/sit 未退出；核对 token.resources 是 declared claims 的子集，且只接受对应 sourceId/itemId 的 RETURN_ORIGINALS（`:10–43`）。分预算扫描每个原 ID（`:44–72`），Execution.reconcile 做纯观察分类（`:13–50`），不能重放消费或效果。

证据齐全才清 readingSite、重建 RETURN_ORIGINALS、置 SETTLING（有原件来源时）或 IDLE，再 mutate KNOWN/SUSPENDED（`:73–90`）；有 RETURN_ORIGINALS 时不调用 finishPersonal，原件 claims 和义务保留到真实 returns 结清。本轮定向测试实际运行了这条 Lua 链，确认 UNKNOWN→KNOWN 后 obligation.itemId=11 与 item:11 claim 都仍存在；不是实机或磁盘保存证明。

## 验证记录

从 repo root 使用 `/home/hatch/workspace/tools/lua-5.4.8/src/lua`，环境：

```sh
LUA_PATH='Contents/mods/EmberRoutesProbe/42/media/lua/client/?.lua;Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;;'
```

| 用例 `tests/lua/*-test.lua` | 结果 |
|---|---|
| dec003-selfcare-migration | PASS 54 assertions；真实 SelfCare/Execution/Resume/PERSONAL adapters/JobStore/Claims + 测试桥模型 |
| dec003-kernel-boundary | PASS 21 |
| dec003-haul-migration | PASS 55 |
| dec003-craft-migration | PASS 54 |
| dec003-fieldwork-migration | PASS 61 |
| dec003-cooking-migration | PASS 49 |
| dec003-kernel-workcapacity | PASS 95 |
| dec003-activity-migration | PASS 120 |
| self-care-repose | PASS 10 + native seating handoff（后者未输出单独计数） |
| self-care-observation | PASS 15 |
| self-care-actions | PASS 13 |
| p3-study | PASS 累计 33（先输出 27，后累计到 33，不相加） |
| self-care-resume | BLOCKED：原 fixture 没有 Phase 1 bridge；当前首断言 :27 失败；a16eb0b 独立 archive 上 PASS 27。没有用 Lua fallback 放宽生产 |
| self-care-service | BLOCKED：原 fixture 仅 worker bridge，无 labor bridge；当前 :56 断言失败；a16eb0b archive 上 PASS 12 + 两组未单列计数检查 |
| self-care-loop | BLOCKED：当前缺 labor bridge，:99 start 返回 JOB_CHANGED；a16eb0b archive 也 FAIL，但位置是 :129 completed-personal-release 断言。现有 fixture 未提供完整会员/内核环境，未改断言，不能宣称该旧回归通过或当前失败位置是既有失败 |

必需八份共 **509 assertions**（54+21+55+54+61+49+95+120），全部通过。额外四份通过，三份旧环境阻塞；原始命令的三次非零退出保留如上，未记为通过。HEAD 对照在 `/tmp/dec003-selfcare-head` 由 `git archive HEAD` 解出并独立运行，没有修改工作区或 HEAD。

新定向测试通过：旧/新完整业务 Job 快照、逐步 revisions、claims、同身份跨 attempt；实际拒绝 submit 后恢复 before payload/义务；stale revision 保持竞争者 revision、before payload、无部分 claims；output CAS 拒绝恢复 claims；座位增减；interrupted obligation；冷 proposal 不写原 Job；冷 RUNNING death fence。物理库存/动作使用替身，主链不声称完整 native consumption parity。旧 create 到第一次 claim 前没有 claimId，新 create 时就分配；比较业务快照时明确忽略此一个 Phase 1 预期元数据差异，不忽略业务字段或 revision。

`luac -p`（指定 Lua 5.4.8 编译器）覆盖每份修改/新建 Lua；`git diff --check`；新增文档链接本地目标检查：15 份 Lua 全部 PASS，diff 检查无输出，新增文档链接目标存在。测试 oracle 仅存在 tests/lua/fixtures，生产没有引用。没有执行 Java 测试。

## 仍开放与未验证

1. **BusinessJobs 最后一段拥有**：`BusinessJobs.lua:88` 的个人 resume payload direct update，正式 deferred；没有悄悄漏掉，也没有重复迁移。其他 BusinessJobs Job/retire 路径本轮不改。
2. **共享 identity/collision**：`LaborStore.lua:30–39,149–162` / `LaborDomainAdapters.lua:93`；跨域原表写保留 OPEN，不能称所有 SELF_CARE kernel-external 写都已清零。
3. **冷非 retained RUNNING death**：`SelfCareJobRecovery.lua:15–17` → `LaborStore.lua:348–351` → shared `JobStore.lua:199` 拒绝；没有绕过或新增 cancel/delete/停止事实。其余调用若触发不允许转换同样明确失败，不补状态。
4. **Phase 1 已接受的失败边界**：CAS callback 抛错、restore 自身失败、CAS 后 cleanup 失败不能通过业务 rollback 保证还原；native output 已发生而提交拒绝也无持久 receipt。仅遵守现有单人 fail-fast/最后存档重载限制，未重建隔离/恢复状态机；实际恢复效果未验证。
5. **旧回归 fixture 缺口**：上表三份未通过，不由本段削弱 guard、删除断言或假称 fixture 通过来关闭。

**Java compilation、真实 bridge calls、in-game parity、disk save/reload、in-game performance 全部 UNVERIFIED（本环境无 JDK、无游戏）**。Lua host 模型不证明 Java/Kahlua 契约、引擎效果、性能、零损失或崩溃安全。`JobStore:removeSettled` 仍 kernel-external，未迁移、未删除、从未用于个人任务。DEC-003 整体未关闭。
