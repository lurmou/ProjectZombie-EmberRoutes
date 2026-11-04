# DEC-003 FIELD_WORK migration 3/7

2026-11-04；基线 `phase-3a-consolidation` / `7a36667`。起始 `git status --short` 空，HEAD/branch 均符合指定。仅实施用户明确批准的 FIELD_WORK 分段，依据完整阅读的外部 segment brief 与 [Phase 1 契约](dec003-phase1-contract.md)。没有新需求评审或 NPC 行为设计，没有宣称同步在线需求。**运行时提交链已转换；分段仍 OPEN：预发布恢复原表写入与共享 identity 分配未迁移。** 无提交、无推送。

## 引用复核与漂移

以下源码路径的共同前缀是 `Contents/mods/EmberRoutesProbe/42/media/lua/`；未标 shared 的模块位于 `client/EmberRoutesProbe/`。先用 `git show HEAD:<path>` 在指定 HEAD 逐项复核，随后才修改。brief 的大多数入口只有符号而无精确旧行号，不能伪造数值漂移量；其唯一明确的 Save.load 51/52 行仍准确。

| brief 入口 | HEAD 7a36667 实际位置 | 本轮最终位置 / 分类 |
|---|---|---|
| FieldContext C.change / unknown / recoveryOnly | FieldContext.lua:11–16 / 18–24 / 27–40 | 行号不变；统一 replaceField |
| session start 两步 | FieldSession.lua:11–15 | 未修改，逐调用 kernel |
| tick SETTLING / approach count / cargo rescue | FieldSession.lua:17–53；三次失败分支33–40 | 未修改，逐调用 kernel |
| stop persist / tool release / terminal | FieldSession.lua:80–109 / 96 / 100–105 | 未修改，terminal CANCELLED 由 adapter 分发 cancel |
| persistFailure | FieldSession.lua:112–118 | 未修改，经 C.change |
| provider create / token failure 两次 update | FieldWork.lua:137 / 155,157 | 140 / 160,162；kernel create / mutate+cancel |
| prepareRecovery asserted update | FieldWork.lua:49–62，写58–59 | 位置不变，kernel mutate |
| advance replace / direct cancel / retirement | FieldWork.lua:81 / 82 / 91 | 81 / 83 / 94；replace+cancel / kernel 外退役 |
| claimField / validField | LaborDomainAdapters.lua:107 / 118 | 不变；re-claim / read guard，identity 例外见下 |
| replaceField | LaborDomainAdapters.lua:124–134 | 124–140；替换为 diff + kernel |
| reserveField / finishField | LaborDomainAdapters.lua:135 / 139 | 141 / 145；promise / terminal cleanup |
| delivery reserve / payload / release | FieldCargo.lua:164–170 / 61–64 | 164–171 / 61–63；容量命令映射 |
| recovery conflict / acquire failure / capacity failure | FieldJobRecovery.lua:13–15 / 19–21 / 24–27 | 未修改；三条 UNKNOWN 原表写均 OPEN |
| restore 调用与 publish | LaborStore.lua:42–43,295–296,331–340 | 未修改；不是独立副本 |
| Save.load Store.data → prepareRecovery | TaskPersistence.lua:49–52 | 51/52 不漂移；HAUL 49 已先触发 publication |

CRAFT 完成后并未改变上述 FIELD 符号的性质；不能借 CRAFT 的预发布恢复分类把 FIELD 的原表别名认作副本。FieldOperations、FieldActions、FieldSupplies、FieldWorkflow 内的 Job 变化均经 `c.change`，搜索 FIELD 全族未发现额外 `Jobs:create/update` 提交口；托管记录与原生效果不属于 Job CAS。

## 七项歧义决定及证据

1. **预发布 UNKNOWN：停止该部分，不强制 kernel。** `LaborStore.lua:43` 的 `current=Registry.data()` 没有复制。296 将同一表传给 `LaborRecovery.restore`；`LaborRecovery.lua:11` 调用已注册的领域回调，`BuiltinLaborRecovery.lua:11` 注册 FieldJobRecovery。后者8–10迭代 `current.taskJobs.byId`，14–15、20–21、25–26直接修改原 Job；331又把该 `current` 发布为 root。因此这些写入会到达发布后的 store，而且 Registry 原表已经可见，不能称为“仅 rebuild 副本”。直接在回调调用 kernel 会重新进入未完成的 `Store.data()`，没有可用的已发布 claims/token authority。用户禁止强制预发布 kernel、新恢复队列/authority；本轮不复制 HAUL 的专用队列、不移动或重做恢复阶段。三条写入完整登记为 **OPEN kernel-external FIELD commit**，没有假称已迁移或无影响。定向测试验证 UNKNOWN 原表可见且 revision 不变。
2. **统一 mutate SETTLING → cancel CANCELLED。** Job 模型为 providerType FIELD_WORK、format 1、revision 整数、effects KNOWN/UNKNOWN、obligations map、payload.claims list。`shared/EmberRoutesProbe/JobStore.lua` 的 `api:cancel` 保留 KNOWN / 空义务 / 空 claims 守卫；`shared/EmberRoutesProbe/FieldRecord.lua:48–52` 继续要求 phase SETTLED、无 holding/capacity/toolSupply、所有 assets DELIVERED。FieldWork.lua:158–162先清 payload/义务并 mutate，再 cancel；advance 76–83同样先清 claims/义务、mutate，再 cancel。Session 先在 FieldSession.lua:83–88持久 SETTLING，终态 edit 100–105在 replaceField 136分发同一个 `Store.cancelJob`。没有第三种取消 API。Java LaborCommitKernel.java:78 本来也将 state CANCELLED 归为 cancel；显式调用使入口一致。普通 DONE 仍用 mutate。
3. **容量有精确映射。** `endpoint.id,itemId,amount,freeCapacity` → `{key=endpoint.id,items={[itemId]=amount},free=freeCapacity}`。FieldCargo.lua:164–170保留 `reserveField` 的即时容量 promise；该函数只 reserve，不写 Job。随后的 `c.change(edit,capacity)` 把同一容量命令交 kernel；同 token/item 的 reserveMany 幂等覆盖原 promise，不将容量放入 claims。`LaborCommitKernel.java:98–105,115–124` 支持 key/items/free、releaseItemId 与 false；ClaimsKernel.java:124–131 用自有原件声明和 free 约束 reserveMany。仅 FIELD 注册 `capacityMutable=true`（shared/BuiltinJobContracts.lua:15），使用既有能力注册门禁，不绕过门禁。显式 releaseCapacity 变为 `c.change(clear,false)`，交付 shrink 的 item removal 也会释放该 item 的容量（ClaimsKernel.java:78）；FIELD 不需另发 releaseItemId 命令。预约后 Job 提交失败仍按原调用方170释放尚未成为持久记录的 promise。**有意的失败契约变化**：已记录容量的释放与 Job CAS 统一事务，CAS 明确拒绝时恢复旧 promise；旧链先释放再更新可能使记录/容量分离。没有改容量选择、交付判断或 free 的含义。
4. **工具释放顺序不变。** FieldSession.lua:95–105先 `FieldSupplies.releaseUncollected` 再终态 change。FieldSupplies.lua:139–170先收集原件观察，随后将已持工具 custody.state 改 HELD，未取工具调用 releaseCustody；这类独立托管写立即可见，函数也可能部分释放后失败。终态 mutate/cancel stale 或明确拒绝时，kernel 只恢复本次 claims/capacity，不恢复前置 custody；Job 仍在前一 revision/state，可能仍声明 toolSupply，而预先释放已可见。保留该顺序，失败停止并重载最后存档，不在当前会话自动补偿或重试；符合指定 Phase 1 fail-fast 边界。定向注入 terminal cancel 拒绝，证明 Job 保留 SETTLING/toolSupply、custody 已为 HELD、只有一次终态尝试。无磁盘重载保证。
5. **每次 change 都单独提交。** FieldSession.lua:13 SUSPENDED→PREPARING、14→RUNNING 两次调用各增 revision；stop persist 83–88和100–105也各提交。UNKNOWN、persistFailure、approachFails、cargo rescue、recoveryOnly 都继续经同一 C.change。未折叠图或把中间状态视为不可观察。
6. **共享身份分配留 OPEN。** claimField 的 LaborDomainAdapters.lua:113调用共享 `ensureEntityClaimId`；LaborStore.lua:30–39在缺失/不合法 identity 时分配并直接写 entity.claimId，25–27修改序列。cooking、personal、activity 以及 cold recovery 共用它，不能在 FIELD 单段迁移。kernel create 已分配合法 FIELD claimId，正常 re-claim 返回现有身份，但不代表共享异常分支已消失；未修改 LaborStore 或共享 allocator。
7. **取消入口穷举。** FIELD 全族搜索 CANCELLED 与 create/update：只有 provider token-failure（FieldWork.lua:153–163）、advance runtime REJECTED/CANCELLED（74–85）、session abandon（FieldSession.lua:49及65–68设标记，100–105终态）。它们分别经 mutate+cancel、mutate+cancel、session SETTLING mutate+adapter cancel；没有遗留直接 JobStore cancellation。advance 携 toolSupply 或 capacity 的终态提案仍会被 FieldRecord 拒绝；未借迁移清理其托管或放宽门禁。该拒绝原先被 direct update 忽略，现在第二步失败 assert 为 fail-fast：属于明确的失败契约收敛，而不是等价重构。此业务缺口 OPEN。

## Walkthrough 与责任闭环

创建/认领：FieldWork.lua:120–140保留 provider target、工具需求、目标 keys、PREPARING revision1 / KNOWN / work=true / format1，实际提交改 `Store.createClaimedJob`。kernel 认领后，145–153仍分配 toolUse 并同事实 re-claim，不额外写 Job。创建失败仍回滚本轮 custody；如遇 Phase 1 的 CAS 已到达/回调抛错限制，必须重载存档，不能解释为没有持久变化。

正常运行：FieldContext.lua:11–16 → LaborDomainAdapters.lua:124–139；依据 token.resources 与 proposed.claims 计算 add/remove，交 kernel 执行 check→extend→capacity→shrink→CAS。删除旧 claims:replace / jobs:update / rollback assert，使用既有 kernel 一次 restore / ROLLBACK_FAILURE marker；无 fallback、隔离链、持久 receipt。业务 workflow 和 approach failure 计数未改。容量通过 FIELD adapter 第四参数传入，C.change 第二参数只传命令，不产生额外 Job 提交。

正常释放：原件交付依旧在 FieldCargo.lua:79–90观察，确认后记 DELIVERED、删除 item claim；stop persist 在 FieldSession.lua:100–105清 phase/claims/义务/toolSupply 再终态 kernel。kernel 终态 CAS 后释放 token；FieldWork.lua:94仍在终态后执行 finishField，清 toolCustody.activeJobId，再 `removeSettled`。finishField 与 removeSettled 未改为 kernel 命令。

异常/恢复：FieldSession.lua:56–118保留 pause STOPPING、body stop、settle、UNKNOWN 与 SUSPENDED/RECONCILE_REQUIRED 路径，经 session funnel 各自提交。FieldWork.prepareRecovery:49–62在已发布 root 用 mutate 标记 LOAD_RECOVERY，dispatched PREPARED attempt 变 UNKNOWN；无强制内部 Store.data publication。TaskPersistence.lua:49 HAUL.prepareRecovery 已内部 Store.data，51再调用是同 root 幂等，52才 FIELD；FIELD 重复调用不再匹配已转出的 state。只有上文三条 FieldJobRecovery 预发布写与共享 allocator 为已分类例外。

## 定向宿主 parity

新增 `tests/lua/dec003-fieldwork-migration-test.lua`；旧 FieldWork/FieldCargo 冻结于 `tests/lua/fixtures/dec003-pre-kernel-fieldwork.lua`、`dec003-pre-kernel-fieldcargo.lua`（精确 HEAD 内容，加 provenance 注释）；旧 FIELD replace 仅在测试内保留。生产不加载 oracle。新路径经真实 LaborJobCommit admission/dispatch、真实 JobStore/Claims、真实 FieldContext/Session/Workflow/Supplies/Cargo；Java bridge 用独立 FIELD host model。原生工具在身、库存转移和 TaskBusinessStop 的 persist 回调边界为明确替身；没有声称动作/身体控制实机通过。

同初始 state、相同 item11、tool22、target，逐点比较完整 Job（包括 revision、claims、toolSupply、phase、assets、holding、effects）、owner 身份、容量 key/items/amount、custody 与原件位置：

| 点 | revision | state / phase | 容量与原件 |
|---|---:|---|---|
| claim/create | 1 | PREPARING / PREPARE | target claim、toolSupply、work=true |
| start | 2 | RUNNING / PREPARE | 无容量 |
| supplied/workflow output | 5 | RUNNING / DELIVER | item11 HELD、有 item claim、toolSupply nil |
| reserveField + change | 6 | RUNNING / DELIVER | stock/items[11]=2，free=10 |
| cargo observe + release | 8 | RUNNING / DELIVER | item11 DELIVERED，实际宿主位置 stock，容量空 |
| workflow success | 9 | SETTLING / DELIVER | effect KNOWN |
| stop persist 两步 | 11 | DONE / SETTLED | 空 claims/义务、无 holding/capacity/toolSupply |
| finishField | 11 | DONE / SETTLED | activeJobId 清除 |

主链 error=nil、rollback 未触发；终态之前及之后快照 old/kernel 全等。kernel 比旧链更早清除终态 runtime token 是 Phase 1 规定的派生缓存清理，不是持久差异；最终 finishField 后一致。

失败证明：stale session c.change 在 Lua revision guard 拒绝，两个路径均无部分 claims/Job 发布；另注入 adapter admission 后 revision 竞争，kernel 返回 STALE_REVISION，保留竞争方已提交的 state/revision、无 proposed additions。注入 CAS 明确拒绝时 TASK_WRITE_FAILURE，单次 host restore，完整 snapshot 恢复；不发布 UNKNOWN、不 quarantine。统一错误码相对旧 JOB_CHANGED/底层错误为已批准契约变化。claim-token-failure old/new 均到 CANCELLED revision3；新链 SETTLING mutate+cancel，真正 token 丢失/失去 ownership 不绕过 gate，fail-fast。prepareRecovery UNKNOWN old/new 均到 RECONCILE_REQUIRED，attempt UNKNOWN，重复调用不再提交。另覆盖 SUSPENDED start 两次 revision、advance reject+外部退役、session abandon、终态前 custody release 后 CAS 失败、missing bridge fail-closed。

## 实际验证与复现

二进制 `/home/hatch/workspace/tools/lua-5.4.8/src/lua`，实际输出 `Lua 5.4.8 Copyright (C) 1994-2025 Lua.org, PUC-Rio`；语法用同目录 `luac -p`。每个用例单独进程，命令均设置：

```sh
LUA_PATH='Contents/mods/EmberRoutesProbe/42/media/lua/client/?.lua;Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;;' /home/hatch/workspace/tools/lua-5.4.8/src/lua tests/lua/dec003-fieldwork-migration-test.lua
```

**stdin handling：所有 Lua 测试与 luac 均直接传文件路径，不用 stdin、不向 REPL 送代码；生成/审计脚本的 Python heredoc 由 shell 传 stdin，不是 Lua 测试结果。** 系统 lua5.4 不作为执行器。

| 检查 | 本轮结果 |
|---|---|
| dec003-fieldwork-migration-test.lua | PASS 61 |
| dec003-kernel-boundary-test.lua | PASS 21 |
| dec003-haul-recovery-boundary-test.lua | PASS（该测试不打印数字计数） |
| dec003-haul-migration-test.lua | PASS 55 |
| dec003-craft-migration-test.lua | PASS 54 |
| field-workflow-test.lua | PASS 20 |
| field-cargo-phase-test.lua | PASS 4 |
| field-actions-test.lua | PASS 13 |
| field-demand-test.lua | PASS 15 |
| field-spatial-test.lua | PASS 15 |
| field-work-test.lua，原始直接运行 | FAIL queued by runtime；未提供 kernel bridge，创建 fail-closed |
| field-tool-supply-test.lua，原始直接运行 | FAIL job created through provider claim；同上 |
| field-continuous-batch-test.lua，原始直接运行 | FAIL job-1 queued；同上 |
| 上述三份不改断言，经独立 fixtures/dec003-field-regression-host.lua runner | PASS 36 / 30 / 55 |
| field-forage-test.lua | BLOCKED：缺 D:/…/media/lua/client/Foraging/ISBaseIcon.lua |

runner 用同一 LUA_PATH，执行 `lua tests/lua/fixtures/dec003-field-regression-host.lua field-work-test`（另两份换名称）。runner 只在测试装配时给实际 LaborJobCommit.install 注入 host bridge，保留其他 Java stub；既有测试文件和预期完全未改。总计13次有 PASS 输出的检查，数值断言合计379（另有 HAUL recovery 不计数）。这不抹掉三次原始运行失败，也不把桥替身当真实 Java。

最终10份变更/新增 Lua 的 `luac -p` 与 `git diff --check` 均 PASS。仓库无 `.workbuddy/tools/pz.mjs`，标准 doclink 无法运行；本段文档及本轮新增导航链接存在性检查 PASS；全文件扫描另发现 INDEX 既有 history/2026-10-24-handoff-before-navigation-cleanup.md 缺失，保留未改，不冒充标准 doclink。

## OPEN / 停止项与 UNVERIFIED

- **硬停止**：FieldJobRecovery 的三条预发布 UNKNOWN 原表写入。不能在不处理 publication/recovery 阶段边界下称为 kernel 迁移；本轮没有授权重建该边界。保留并分类，分段不得标完整关闭。
- shared ensureEntityClaimId / nextClaimSeq 分配仍 OPEN；不删除共享 LaborStore/LaborJobCommit。removeSettled 为合约规定 kernel 外退役，不算漏迁。
- advance rejected/cancelled 若仍有 toolSupply/capacity，terminal gate 会拒绝；不借迁移补托管策略。claim-token failure 如 kernel token/ownership 真已丢失，也拒绝补偿，不无 token 清 claims。
- Phase 1 已公开的 callback throw 是否发布、restore 自身失败、post-CAS cleanup 失败仍只能返回 marker/重载；本段不保证零损失或 crash-safe，不建恢复链。
- **Java compilation、real bridge calls、in-game parity、disk save/reload、performance 均 UNVERIFIED**：当前无 JDK、无游戏；`command -v java/javac` 均无输出。Lua host 结果不能替代其中任何一项。没有性能测量或性能提升结论。
- 无其他领域迁移、DEC-004、商队、NPC 行为、调度器、旧档迁移、多人修改；没有改 HAUL/CRAFT 文件或共享其专用 adapter。
