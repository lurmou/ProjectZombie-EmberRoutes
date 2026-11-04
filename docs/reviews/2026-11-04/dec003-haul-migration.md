# DEC-003 HAUL migration — 2026-11-04

基线：`b7f8cb1`（kernel core `59c7944`）；本轮仅 HAUL，未提交、未推送。依据用户提供的 haul migration brief → Phase 1 revised → design judgment（按 revised 裁剪）。这是已有批准范围的迁移，不是新架构设计；未重新同步在线需求。其余六域未迁移，DEC-003 **未完成**。

## 生产链与所有权证据

路径均相对仓库根目录，Lua 前缀为 `Contents/mods/EmberRoutesProbe/42/media/lua/`。

| 环节 | 文件/行与数据契约 | 本轮结果 |
|---|---|---|
| 领域 draft / 创建认领 | `client/EmberRoutesProbe/HaulJobs.lua:110`：generation→sequence，`HaulJobRecord.activeClaims` 从未结清 manifest 逐 ItemID 生成 claims，创建 HAUL/PREPARING/revision=1；成功后普通 commit 到 RUNNING/revision=2 | 继续使用唯一 `Store.createClaimedJob`，不另建 Lua 资源事务 |
| entry shape / 领域策略 | `client/EmberRoutesProbe/LaborJobCommit.lua:18` 创建先 `JobStore.validate`，`:30` mutate/cancel intent 形状；`shared/EmberRoutesProbe/BuiltinJobContracts.lua:34` HAUL 注册；`HaulJobRecord.lua:44` 校验 format=3、claims、manifest、reservation 与终态；`:115` transition 保留 activeAttempt/controlUncertain；`JobStore.lua:14` 状态图 | 业务规则全部留在 Lua，Java 未改 |
| 容量载荷一致性 | `HaulJobs.lua:48` 对比 capacity command 推导的预约和 draft.reservation；`:85` 失败返回 `INVALID_REQUEST` + `CAPACITY_PAYLOAD_MISMATCH` | 旧公共 Lua 路径独有的拒绝策略移至 HAUL 入口；不复制到 Java，不恢复公共 Lua fallback |
| mutate / 实际调用位置 | `HaulJobs.lua:97` → `LaborJobCommit.lua:51` → `invoke('laborMutate',...)` → `EmberRoutesProbeJava.laborMutate` → `LaborCommitKernel.mutate/change` (`java/src/main/java/emberroutes/probe/LaborCommitKernel.java:64`) | Java 源调用链已核对；宿主只执行到具名入口替身，**真实 Java 调用 UNVERIFIED** |
| create / cancel 桥 | `LaborJobCommit.lua:26` laborCreate、`:61` laborCancel；Java `LaborCommitKernel.java:147` create、`:67` cancel | 没有阈值分支、Lua 生产替代事务或新 Java 业务规则 |
| 正常交付与释放 | `HaulJobs.lua:156` settle 仅接受 DELIVERED 有 destinationId/attemptId 回执或可撤回的 UNCOLLECTED；`:173` finish 拒绝未知/attempt/未结清原件，SETTLING→DONE，经 kernel shrink/terminal cleanup | ItemID、物品实例状态、claims、capacity 在快照中比较；物理动作实机未验证 |
| 显式 Job cancel | `HaulJobs.lua:181` 新终态入口，原件/控制未结清拒绝；资源命令与 KNOWN/空 obligations 一次提交到 `Store.cancelJob` | 资产已结清可从 RUNNING 直接 CANCELLED；取消拒绝恢复 draft reservation。身体停止/订单取消仍沿既有暂停、实物归还及正常 finish 链，不将停止当资产释放证据 |
| 异常/读档 | `HaulJobs.lua:198` 先 Store.data；既有 `LaborStore.lua:336` 发布 root/claims/tokens 后 `:345` 顺序 drain pendingHaul，再 HAUL 的 STOPPING/SUSPENDED 或原有 UNKNOWN 状态意图经 `Store.mutateJob`；`TaskPersistence.lua:49` 检查恢复返回值 | 删除旧 HAUL 两处 `jobs:update`；失败中止 load，不悄悄继续。无 token 的同事实恢复按 kernel 既有规则不发送资源命令，保留持久责任；不跳过 kernel 门禁 |

`LaborDomainAdapters.lua:259` claimHaulJob 为同 claimId/同已提交集合的运行时认领与代次 fence；`:269` validHaulJob 为只读守卫，不是另一个持久提交入口。`HaulJobRecovery.restore` 的 acquire/restore 为索引重建；冲突意图仍走已有内存 pendingHaul，未新增持久队列。`record/adopt/reset` 是派生 draft 缓存；终态相同 draft 的 `JOB_TERMINAL` 返回为既有只读 no-op，不是重新提交。六域其他 adapter 写入保持 Phase 0 OPEN 分类，本轮不改。

## 宿主 parity 方法与结果

`tests/lua/dec003-haul-migration-test.lua` 使用真实 JobStore、HaulManifest、HaulJobRecord、LaborClaims、LaborJobCommit。旧侧为只在测试目录加载的冻结源码：

- `fixtures/dec003-pre-kernel-commit.lua`：`9ebe06f` 公共旧 Lua 提交器，保留原文（另加 TEST ONLY 说明）。
- `fixtures/dec003-pre-kernel-haul.lua`：`b7f8cb1` HAUL 旧链，包括原直接恢复发布。
- 新侧 `fixtures/dec003-kernel-host.lua`：明确标识的 Lua Phase 1 顺序模型，用真实 claims/JobStore 执行资源变化与 CAS；通过真实 Lua facade 的 laborCreate/laborMutate/laborCancel 入口计数确认 dispatch。**它没有加载 JVM，不证明 Java 实现执行、编译或 parity。**

两个旧实现仅为测试 oracle，生产文件不引用它们。生产旧 HAUL 直接发布路径已删除，不保留 fallback。

| 对照/定向项 | 证据与结果 |
|---|---|
| 主链 | 创建 rev1→RUNNING rev2→容量 rev3→在途 rev4→settle rev5→SETTLING rev6→DONE rev7；逐快照对比完整 Job（含 revision、claimId、manifest、activeAttempt）、owner、capacity、ItemID/位置/condition |
| 在途工作 | item2 CARRIED + PUT attempt 在 rev4 完整保存，effects UNKNOWN，资源仍认领；只在宿主模拟交付后清 attempt/提交 receipts。提交本身不移动、不删除重建物品 |
| stale revision | 同 rev4 状态使用 rev3 意图，双方 STALE_REVISION，Job/claims/capacity/items/attempt 均不变 |
| capacity-payload mismatch | 同 rev4 状态，command item1=99 与 reservation item1=2 不同；旧公共路径 CAPACITY_PAYLOAD_MISMATCH，新 HAUL 入口 INVALID_REQUEST + 对应诊断；无资源或 revision 写入。错误码转换是明确的 Phase 1 契约变化，比较时归一为 INVALID_REQUEST |
| 容量不足 | 同 rev4 状态，将 item1 预约改为50但 free=5；旧 CAPACITY_RESERVED，新 CAPACITY_FAILURE，按 Phase 1 归一比较；权威与 draft reservation 恢复，item2 attempt 未丢失 |
| DONE/重试限制 | 完成释放 claims/capacity/token。以最后成功提交的旧 revision 重试相同终态意图→STALE_REVISION，不缓存 prior result、不建 receipt。崩溃或提交后不确定失败接受**重载最后存档**；磁盘重载未在此执行 |
| recovery parity | 原直接 Lua 恢复 vs kernel 宿主：普通 STOPPING/SUSPENDED；以及有 TAKE attempt、重建冲突后无 token 的 UNKNOWN 恢复。完整快照相同，持久 claims/在途事实保留；恢复每 world 一次 |
| cancel | 有责任拒绝无变化；原件经宿主模拟撤回后从 RUNNING 调 laborCancel，rev2→3/CANCELLED，资源释放。新 Phase 1 cancel 不要求旧 SETTLING 前置，这是明确的已批准契约接入，不伪称旧 API 同态 |
| 回滚 | 强制 JobStore.update 拒绝，pre-CAS 容量操作恢复一次，原 job/revision/owner/capacity/items 不变；cancel CAS 拒绝同样恢复预约与 draft。没有新增 quarantine/隔离/重试状态机 |
| 其他入口 | 缺桥 KERNEL_UNAVAILABLE；坏创建 INVALID_REQUEST；坏领域记录在 Lua JobStore 拒绝为 TASK_WRITE_FAILURE；addKeys 事务内扩展、单项/全量容量释放 |

宿主模型不覆盖 Java 回调异常包装或 Java restore 实现的正确性；不拿它替代已有真实 Java 测试或实机测试。没有新增 receipt、持久恢复队列、穷尽恢复分支、TaskRuntime 重设计。

## 本轮验证

运行时 Lua 5.4.6；以下命令均使用：

```sh
export LUA_PATH='Contents/mods/EmberRoutesProbe/42/media/lua/client/?.lua;Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;;'
lua tests/lua/dec003-haul-migration-test.lua
lua tests/lua/dec003-haul-recovery-boundary-test.lua
lua tests/lua/dec003-kernel-boundary-test.lua
lua tests/lua/hauling-provider-test.lua
lua -e 'unpack=table.unpack; dofile("tests/lua/haul-test.lua")'
```

- PASS：迁移宿主 55 checks；旧/新主链、stale、mismatch、容量失败及 recovery parity。
- PASS：既有 HAUL enqueue/publication/order/failure diagnosis；既有 DEC003 Lua boundary 21 checks。
- PASS：hauling-provider；世界 haul 54 assertions（包含其依赖 action 16 assertions），均为 native fakes。世界 haul 原始 Lua 5.4 启动因全局 unpack 缺失失败；只在宿主启动命令映射 `unpack=table.unpack` 后重跑通过，未修改测试/生产语义。
- BLOCKED：`haul-routing-test.lua`、`delivery-service-test.lua` 均在依赖 `multi-worker-test.lua:2` 读取不存在的 `tests/lua/work-test.lua` 时退出，未执行对应回归断言。未补造生产无关夹具、未删除失败用例。
- PASS：本轮全部6份新/改 Lua 文件分别 `luac -p`；`git diff --check`（含新增文本单独空白检查）。未跑全套。
- **UNVERIFIED**：Java 编译（无 javac）、真实 Java bridge calls、真实 Java kernel parity、Kahlua/游戏内 parity、正常磁盘保存重载、实机故障恢复、游戏内性能。未宣称性能提升或崩溃安全。

迁移实现未遇到需绕过 Phase 1 门禁或重建 safety 状态机的阻塞。父任务复核尚需补缺失 routing/delivery 夹具后的定向回归，以及上述真实 Java/实机验证；六域和全局 DEC-003 验收仍 OPEN。未开展 DEC-004、商队、NPC 行为、游荡或社交。
