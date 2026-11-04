# DEC-003 CRAFT / Production migration 2/7

2026-11-04；起点 `phase-3a-consolidation` / `37edb7ef21682531399aac8bcae5afdae0874976`，起始 `git status --short` 为空。按用户 brief → [Phase 1 契约](dec003-phase1-contract.md) → [HAUL pattern](dec003-haul-migration.md) 顺序读取。本轮仅执行已批准 CRAFT 范围，未作需求设计或宣称同步在线需求。无 commit / push；供父任务审核工作树 diff。DEC-003 总体仍 OPEN。

## Step 0：逐项重核与 reference drift

以下行号除特别标注外均指本轮最终文件。仓库绝对根目录为 `/home/hatch/workspace/repos/ProjectZombie-EmberRoutes`；`C/` 表示 `Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/`，`S/` 表示同级 `shared/EmberRoutesProbe/`。通过 `git show 9ebe06f:<path>`、`git show 37edb7e:<path>` 与当前源码逐项核对 brief 列出的所有提交位置，未以 Phase 0 行号直接编辑。

| brief 位置 | Phase 0 → 起始 HEAD | 本轮结果 / 最终位置 |
|---|---|---|
| ProductionJobs create / commit | `C/ProductionJobs.lua:83 / :53` 均未移动 | 原已调用 `Store.createClaimedJob` / `Store.mutateJob`，沿用 Phase 1 桥；不重复建立事务 |
| claim / valid / replace / beginEffect / observe | `:100 / :110 / :114 / :122 / :137` 均未移动 | 仍为 Lua policy + 唯一 commit funnel |
| observe failure direct publish | `:177` 未移动；quarantine 在 `:169` | 删除这两类写入；现 `:166` 为 fail-fast / reload 注释及 draft invalidation |
| prepareRecovery | 入口 `:182`、直接 update `:198 / :201` 均未移动 | 入口现 `:172`，`:174` 强制发布 Store，`:190 / :194` kernel mutate |
| CraftJobRecovery conflict / acquire failure | `C/CraftJobRecovery.lua:15 / :21` 均未移动 | 预发布重建，明确保留例外，文件未改 |
| claimCraft / validCraft | `C/LaborDomainAdapters.lua:276 / :286` 均未移动 | same-fact acquire / revision+generation guard，文件未改 |
| shared identity | `C/LaborStore.lua:30` 未移动；collision scan ensure 调用 `:117→:118` | shared open，未改 |
| rebuild invocation / publish | `LaborStore.lua:295→:296`、`:330→:331` | 注意 HAUL 文档曾写 publish `:336`，本 HEAD 实际 `:331`；domainState 发布 `:337`，HAUL drain `:345`；全部未改 |
| shared commit create / mutate / cancel | `C/LaborJobCommit.lua:5→:17 / :54→:44 / Phase 0 无 cancel→:54` | 旧公共 Lua 实现已由 Phase 1 移除；不再删公共代码。dispatch `:26 / :51 / :61` |

ProductionJobs 在两个基线间内容相同，故冻结 `37edb7e` 作为旧领域 oracle；旧公共事务 oracle 沿用已存在的 `9ebe06f` test-only fixture。

## 七项歧义的决定与证据

1. **取消入口：沿用 commit-to-CANCELLED，kernel mutate；没有新增 cancel API。** `C/ProductionJobs.lua:43` 仅在 `released` 时派生终态，`:48`、`:62`、`:70` 保留 SETTLING → CANCELLED 两次 mutate。全仓搜索 ProductionJobs 依赖仅 `Production.lua`、`ProductionActions.lua`、`CraftProbe.lua`。实际设置 CRAFT CANCELLED 的业务写只有：`C/Production.lua:72` rejectUncollected → `:73` commit（stopAdapter 的 persist `:94` 调用，要求 bodyStopped/KNOWN、无产出、逐原件仍在仓库）；以及 `:348` finish → `:358` returnOnly CANCELLED → `:361` released → `:366` changed → `:109` commit。用户入口 `C/CraftingService.lua:160/:162` 接受 return，`CraftProbe.lua:32` 转 Production.execute；`Production.lua:625/:648/:650` 标识显式取消/returnOnly。恢复的 return 候选 `:149`、activity-yield 强制 return `:629` 进入相同 finish 链；未取消的 MANUAL yield 走 `:350` 的 continuation，不强行终结。stop 入口 `:657` / pause `:134/:139` 只暂停，不等于取消。`C/PublicWork.lua:382` 已认领 Job 拒绝订单命令，`:384` 只取消尚无 Job 的 Order；不是额外 Job cancel。`Store.cancelJob` 存在于公共桥 `LaborJobCommit.lua:54`，但 CRAFT 当前零调用；KNOWN/空义务/空 claims 由 `S/JobStore.lua` 终态校验和 cancel 守卫保留，不绕过。
2. **Observe 提交失败：明确 cut 为 fail-fast + reload-from-save。** 原 `ProductionJobs.lua:166–177` quarantine 输出并再次直接发布 UNKNOWN，既非 Phase 1 事务，也不能按普通可回滚效果处理。本轮删除该整段，不转换成另一条隔离状态机。现 `:158` 只有一次业务 commit；`:161` 保留已 APPLIED 的 post-commit changed 识别；`:166–169` 返回原错误并将当前 execution draft 标为 failed。不反写旧 Job、不新增持久 receipt/队列/恢复 authority。**契约变化**：失败的已知输出不再补写 quarantine provenance，原生消耗/产物不会因 Lua 拒绝提交而撤销；必须重载最后存档，不承诺可继续或零损失。显式 `complete=false` 的领域观察仍按 `:156–157` 请求原有 UNKNOWN/RECONCILE_REQUIRED，并通过正常 kernel commit；这与 commit 失败后的第二次 safety publish 不同。现有 observation receipt/idempotency 业务契约保留，不新增内核 receipt。
3. **恢复时序：先发布再 kernel；预发布例外明确保留。** `C/TaskPersistence.lua:49–52` 先 HAUL.prepareRecovery（其 `HaulJobs.lua:200` 调 Store.data），再 Craft.prepareRecovery。独立入口 `CraftProbe.lua:12–18` 原来只有 legacy 存在才提前 Store.data，因此不能仅依靠 Save.load 调用顺序。本轮 `ProductionJobs.lua:174` 无条件先 Store.data；`LaborStore.lua:296` 调同步 LaborRecovery，`:331/:337` 完成 root/claims/token 发布，返回之后才 `ProductionJobs.lua:190/:194` mutate。不是在 Store 构建回调中重入，所以不新增 pendingCraft 队列。`C/CraftJobRecovery.lua:3/:15/:21` 是 `LaborStore.lua:296` 同步调用的**预发布重建状态写**（原 root 的重建转换，确实改动持久表，不是普通只读索引）。按 brief 明确许可留在重建阶段，未强行 kernel 化；成功 acquire 是同事实索引重建。该例外未删除，后续跨领域 cold recovery 仍 OPEN。冲突/无 token 的已发布 Production recovery 使用 payload-only mutate，保留持久 claims，不发送资源变更；Phase 1 已允许此路径。失败抛带统一错误/evidence 的 load 错误，不标记 recoveredWorld，不静默继续；没有重试事务机制。
4. **多步提交：完整保留每步 revision。** `ProductionJobs.lua:46–51` nextState、`:62–80` 循环仍逐步 kernel mutate；没有证明中间状态不可观察，所以不合并。主链 DONE `RUNNING rev5 → SETTLING rev6 → DONE rev7`；恢复正常 `RUNNING → STOPPING → SUSPENDED` 也保留两次 CAS。成功一步后失败不会反写已提交步骤。
5. **身份：不迁移 shared allocation。** brief 所说 claimCraft ensure 分支与实际源码不符：Phase 0 与本 HEAD 的 `LaborDomainAdapters.lua:283` 均直接用 `saved.claimId` acquire，**没有** ensureEntityClaimId。实际分配在 `LaborStore.lua:30`（多个域共享）、全局 collision scan `:118` 和 `CraftJobRecovery.lua:18` 的预发布重建调用。没有证明可单独修改的 CRAFT-only allocation 实现；全部原样保留为 shared open。新建 CRAFT 的权威 claimId 则已由 kernel create 分配，沿用现有契约。
6. **工具 key 集合：Job 与 custody 分离。** `S/CraftJobRecord.lua:21–62`：released 或 Yield.assetFree 时空集合；否则 bench 在非 CONFIRMED/RETURNING/DONE 时为 `craft-surface:<benchId>`，未 consumed materials 为 `item:<id>`，**tools 中每个合法 ID 都是 `item:<id>`**，未 delivered outputs 为 `item:<id>`，held 为 `item:<id>`（包含尚未成为本工序 tool 的链资源）。不存在 Job 的 `tool:<id>` / custodyId key。`S/CraftRecord.lua:55` 起逐列表 seen 校验防重复资产。`C/LaborStore.lua:657` claimCustody 使用独立 custody 记录，`:685` 同样为 `item:<itemId>` claims（由独立 custodyId/token 持有，不是额外 tool key）；`:700/:718/:743/:759/:773` releaseCustody / assignToolUse / assignToolReturn / abortToolReturn / completeCustodyReturn 均未改。这些不是 Job 提交，也未作为 DEC-004 迁移。
7. **容量：N/A。** `ProductionJobs.lua:70–71` mutation 只有 addKeys/removeKeys/state/effects/obligations；恢复 `:190/:194` 也没有 capacity。`S/BuiltinJobContracts.lua:21` CRAFT 未注册 capacityMutable（只有 HAUL 注册）；本轮没有 capacity=false/releaseItemId/station capacity 命令。`ProductionCarry`/物理容器可容纳判断是业务选择，不是 kernel capacity reservation。parity 每个快照仍比较空 capacity 表，输出通过 addKeys 认领，不混为容量。

## 调用链、责任与保留边界

- 创建/认领：`Production.lua:618` → `ProductionJobs.create:83` → Store.createClaimedJob → `LaborJobCommit.lua:26` laborCreate；create 后 `:96` commit RUNNING。claim `:100` 前后两次 same-fact `Store.claimCraft`，在中间提交新 sequence，保留 resumed generation fence。
- commit 调用清单：`Production.lua:73/:109/:134/:649/:706/:718`；create `:618`，claim `:643`，replace `:214/:261/:378/:406/:510/:532`；`ProductionActions.lua:153/:183` beginEffect/observe。全部通过 ProductionJobs 的唯一 Store 桥；valid 为只读 guard。没有 Lua 事务 fallback、threshold gate 或新 Java 业务规则。
- 正常释放：`Production.lua:340` 原生转移后 Allocation.settle，`:348–365` finish 由业务证明原件清算，`ProductionJobs.lua:43/:70` 将空 claims/KNOWN/空 obligations 与终态一并提交，kernel terminal cleanup 释放 token。宿主模拟物理效果，不将它当成游戏证据。
- 异常打断：`Production.lua:75–99` stopAdapter / `:125` pause；`ProductionJobs.lua:172` 读档派生暂停/保留未知效果，经 kernel。未把 timeout、身体停止或 token 消失当作资产结清。
- Supply/routing 未改：`S/ProductionAllocation.lua:4/:12/:18` 只改传入 draft/row；`C/Production.lua:320–322` assign 后 changed → `:109` commit；`C/ProductionRouting.lua:38` 只修改传入 row；调用方 `Production.lua:484–488` 在规划完成后通过 changed funnel 提交。ProductionSupply 的 plan 是 draft 与 location 缓存；没有独立 Job 持久写入。选择/排序/recipe/tool 策略全部留 Lua。
- 删除生产旧路径：ProductionJobs 中已无 JobStore.update 或 quarantineResource；仅测试 oracle 保留。共享 LaborStore/LaborJobCommit、其他域、HAUL、CraftLegacyRecovery、JobStore.removeSettled、工具 custody 均未改。没有 DEC-004、商队或 NPC 行为变更。

## 宿主 parity 与测试 oracle

新 `tests/lua/dec003-craft-migration-test.lua` 使用真实 JobStore / CraftJobRecord / CraftRecord / LaborClaims / LaborDomainAdapters / LaborJobCommit。

- 旧侧：新增 `fixtures/dec003-pre-kernel-production.lua` 是 `37edb7e` ProductionJobs 完整冻结源码，仅加 TEST ONLY 注释；公共旧事务使用现有 `fixtures/dec003-pre-kernel-commit.lua`。生产没有引用这些 oracle。
- 新侧：新增 `fixtures/dec003-craft-kernel-host.lua` 从 HAUL 的 Phase 1 宿主模型派生，明确标记 TEST ONLY / NOT Java。额外模拟 `java/.../ClaimsKernel.java:52` 的 extend 前资源列表复制、`LaborCommitKernel.java:25–55` 的一次 restore claims revision；不修改 HAUL fixture。该复制很关键：真实 Lua adapter acquire 的 token.resources 可别名已保存 payload.claims，Lua extend 原语直接 append，Java extend 则先复制。测试曾因模型遗漏复制而失败，修正测试模型后通过；没有改生产或放宽守卫。
- 主链：create PREPARING rev1 → RUNNING rev2 → claim rev3 → beginEffect COMMITTING rev4 → observe APPLIED rev5 → SETTLING rev6 → DONE rev7。逐阶段比较完整 Job/revision/claimId/nativeAttempt/observation、claims owners 与 token resources/generation、空 capacity、ItemID/位置/condition；in-flight COMMITTING 保留 UNKNOWN，原件仅由明确宿主模拟消耗/产出/交付。新输出 item:3 在 observe 事务中 extend，消耗 item:1 shrink，工具 item:2 保留至结清。
- stale：两个实现均在 M.commit 的领域 fence 返回 PRODUCTION_JOB_CHANGED，完整快照维持外部提交后的 revision，新增输出未部分认领；比较 error 与无写入/无 rollback 的结果。
- 其他定向：两类 recovery parity（正常、COMMITTING 且无重建 token）；发布门禁/每 world 一次；取消的两步 mutate；resumed sequence；replace CAS 拒绝恢复 draft 与 claims；observe CAS 拒绝仅一次 rollback，不 quarantine/第二次发布，draft 不再 valid；缺桥 create/recovery fail-closed；CraftJobRecovery conflict 明确预发布写、无 kernel call。observe 失败与旧 isolation 不做虚假同态：它是上文明确声明的 Phase 1 cut。

## 实际验证结果

运行精确工具 `/home/hatch/workspace/tools/lua-5.4.8/src/lua`，环境：

```sh
LUA_PATH="Contents/mods/EmberRoutesProbe/42/media/lua/client/?.lua;Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;;" /home/hatch/workspace/tools/lua-5.4.8/src/lua tests/lua/<name>-test.lua
```

20 个定向文件：**10 PASS / 2 assertion FAIL / 8 BLOCKED（含旧 API、宿主替身不完整）**。测试本身未为取得通过而修改。

| 测试文件（tests/lua/ 下） | 结果 |
|---|---|
| dec003-craft-migration-test.lua | PASS 54 checks（旧/新 parity 与以上边界） |
| dec003-kernel-boundary-test.lua | PASS 21 checks |
| dec003-haul-recovery-boundary-test.lua | PASS；未打印断言数，enqueue/publication/order/failure diagnosis |
| production-chain-test.lua | PASS 18 checks |
| production-carry-test.lua | PASS 26 checks |
| crafting-provider-test.lua | PASS；未打印断言数 |
| vanilla-crafting-hook-test.lua | PASS 13 checks |
| gate-c-cross-target-test.lua | PASS 14 checks；真实 ProductionSupply/CraftSupply/ProductionRouting/Allocation，native transfer 模拟 |
| gate-c-tool-reload-test.lua | PASS 20 checks；内存模拟，非磁盘重载 |
| planning-budget-test.lua | PASS 51 checks |
| production-three-batch-test.lua / task-production-runtime-test.lua / activity-craft-yield-test.lua | BLOCKED；缺 tests/lua/craft-probe-test.lua，未运行对应断言 |
| crafting-edge-visibility-test.lua / crafting-chain-width-test.lua | BLOCKED；settlement-tabs-test.lua:136 依赖缺失的游戏 ISUI/ISTickBox.lua |
| haul-routing-test.lua | BLOCKED；multi-worker-test.lua:2 依赖缺 tests/lua/work-test.lua，未补造夹具 |
| sim-production-journey-test.lua | BLOCKED；原启动缺 global unpack；仅启动命令加 unpack=table.unpack 重跑，仍在 UI/StepperInput.lua:94 因替身缺 setOnlyNumbers 退出，未改生产/UI/测试 |
| craft-record-test.lua | BLOCKED；:27 调用已不存在的 CraftRecord.valid，测试仍基于 format1/2 旧 API |
| crafting-catalog-test.lua | FAIL；:27 首 slice 4 native recipes 断言失败 |
| craft-stations-index-test.lua | FAIL；:25 bounded CraftBench discovery 断言失败；其依赖 repose-sites 26 checks 通过不算该文件通过 |

有打印计数的通过项共 **217 checks**，另 2 个 PASS 文件未报告计数。catalog、stations、craft-record 用 `package.preload` 指向冻结的原 ProductionJobs 入口再次运行，失败完全相同；它们不因本轮修改而取得新的通过结论。未删除失败用例或更改期望。

本轮全部 4 份新增/修改 Lua 文件使用指定 `src/luac -p`；`git diff --check`，新增文本单独 whitespace 检查及生产无 oracle 引用检查，结果记录于交付。未跑完整回归。

## 开放项、停止与 UNVERIFIED

没有遇到要求绕过 Phase 1 门禁、重建 cut safety state machine 或 redesign TaskRuntime 的实施阻塞。恢复 pre-publish failure writes 和 shared identity 按 brief 保留为明确开放项，不能声称整个 CRAFT 相关持久写入口已全部迁走。以上失败/阻塞回归仍需父任务处理环境或历史测试契约；本轮不扩大领域范围。

**UNVERIFIED：Java compilation；真实 Java bridge calls / Java kernel parity；in-game parity（含原生动作与组合故障）；disk save/reload；performance。** 未执行 Java 或游戏，不从 Lua host/model 的通过借用任何 Java、存档可靠性、实机或性能结论。observe fail-fast 后重载最后存档仍是公开恢复要求，本轮未实际验证磁盘恢复。

## 交付文件

Tracked 修改：

- `Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/ProductionJobs.lua`
- `docs/BACKLOG.md`
- `docs/INDEX.md`

新增（未暂存）：

- `docs/reviews/2026-11-04/dec003-craft-migration.md`
- `tests/lua/dec003-craft-migration-test.lua`
- `tests/lua/fixtures/dec003-pre-kernel-production.lua`
- `tests/lua/fixtures/dec003-craft-kernel-host.lua`

静态结果：4/4 Lua 文件 `luac -p` PASS；tracked diff 与所有新增文本 whitespace PASS；生产 oracle 引用 0。标准 `.workbuddy/tools/pz.mjs` 在当前工作区不可用（搜索无该工具），故 doclink 命令未运行；改用本地 Markdown 相对链接存在性检查，检查三份变更文档的文件链接，不验证在线链接或正文一致性。

相对文件链接检查结果：本段文档2/2及 BACKLOG/INDEX 新增链接通过；三份文档共214处引用中有5处既有 history 快照链接缺文件（BACKLOG 2处、INDEX 3处），未扩大修复范围。标准 doclink 未运行，不将替代检查报告为其通过。
