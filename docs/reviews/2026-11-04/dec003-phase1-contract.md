# DEC-003 Phase 1：kernel core 契约与验证

2026-11-04；基线 `phase-3a-consolidation` / `9ebe06f`。第二遍仅修订已在工作树中的 Phase 1 kernel diff；保留第一遍及 Phase 0 未提交改动。用户指定 `~/workspace/goals/emberroutes-npc-realism/files/dec003-phase1-revised.md` 的 **Current-architecture safety cuts** 为权威，覆盖该文旧 Cut 段与本契约第一遍的 isolate / UNKNOWN publish 描述。**DEC-003 OPEN；无领域迁移，无提交/推送。** 本轮执行明确批准的 cuts，未作新需求设计或宣称同步在线需求。

## 冻结接口与职责

Lua `LaborStore.createClaimedJob(job)`、`mutateJob(id, expectedRevision, payload, mutation)`、`cancelJob(id, expectedRevision, payload, mutation)` 返回 `ok, result, evidence`。成功 result 分别为 Job ID、新 revision、新 revision；失败 result 为 `STALE_REVISION / INVALID_REQUEST / CLAIM_FAILURE / CAPACITY_FAILURE / TASK_WRITE_FAILURE / KERNEL_UNAVAILABLE / ROLLBACK_FAILURE`，具体原因在 evidence。无 DUPLICATE_COMMIT。

- Lua bridge 负责一次入口形状校验；JobStore 保留记录、领域 validate/transition 与取消守卫，不在 Java 加业务规则。Java 只保留版本、runtime token 注册/身份/所有权、重复 additions、add/remove 重叠、已占用 additions 等可见正确性检查及容量命令最小类型检查。底层 Claims 原语既有资源/容量约束仍保留，未重建它们。
- 删除 Java `sameItems`、`reservationMatches`、完整 proposedPayload.claims 集合相等校验、proposed reservation 与命令精确匹配及无命令时 reservation 相等校验。Java 不再证明 payload 与资源命令精确一致；调用者与 Lua 领域契约对此负责，这是明确收紧后的保证边界，不把旧 mismatch 行为作为验收。
- 容量从 mutation 命令自身 key/items/free 应用，支持既有 `false` 全释放与 `releaseItemId` 单项释放。检查 table、key/string、items/table、item ID/数值、amount/数值、free/数值；capacityMutable 注册契约沿用原路径。无 token 只允许无资源命令的记录写，不授权资源变更。
- 创建：Lua validate 草稿、PREPARING/revision 1；Java 分配 claimId（覆盖输入）、认领、容量、create，随后发布派生 token 缓存。保留逐项 reserve 的创建语义，不引入 mutate reserveMany 的既有 30 项限制。创建重试可能分配新 claimId。
- mutate/cancel：**check → extend → capacity → shrink → CAS**。CAS 是最后的权威 Job 写；后面仅终态 token release/cleanup（create 为 token 缓存发布）。正常 DONE 经 mutate；没有 kernel delete API。
- cancel 共用事务，最终调用 JobStore:cancel，可从任意非终态请求；KNOWN、零义务、零 claims 的守卫仍由 Lua 执行。拒绝返回 TASK_WRITE_FAILURE，evidence 为 CANCEL_BLOCKED_*。不强制清责任终结。SELF_CARE recurring 持久身份不能通过 delete 替代正常结束/取消；JobStore:removeSettled 仍为 kernel 外持久退役提交，未迁移。

## 删除与简化的安全机制

**删除 kernel commit path 的隔离状态机，保留其他领域的既有 quarantine 数据与谓词。** `Tx.mark`、owner.quarantineResource 调用链、isolationFailed、failureKeys、diagnostic/finish、reconcilePublished/publishFailure 及失败后的第二次 store:update 全部移除。内核不写 quarantine 表，不写 RECONCILE_REQUIRED/UNKNOWN 失败状态，不建恢复队列。ClaimsKernel 的 SYSTEM_QUARANTINE / mine / releaseQuarantineCapacity 仍供未迁移领域使用，本轮该文件未修改；kernel remove 必须当前 owner==token，不能借 shrink 进入 quarantine 清理分支。

仅保留一次调用内资源快照与一次 restore：资源变化前记录 token.resources、容量 key/items、claims revision；CAS 前失败或 CAS 明确 false 时，恢复原 owner/resource 列表与容量，清除本次 additions，并恢复派生 claims revision。不得覆盖 foreign owner；恢复自身失败即返回 ROLLBACK_FAILURE，evidence 中的 RECONCILE_REQUIRED:PARTIAL_RESTORE **只是字符串**，Job 保持原 revision/state，不重试、不隔离、不再发布。快照不是持久 receipt，也不是可调用的恢复协议。创建失败仅释放本次 token；claimId 序列不回退。资源列表仍复制，避免 token.resources 与持久 payload 别名导致 CAS 前改写 Job。

CAS 成功后仅 terminal release/cleanup 或 create token 缓存发布可能失败。返回原错误类别与 CAS_REACHED_RELOAD_FROM_SAVE 证据；已提交 Job/revision 保留，不补偿、不隔离、不写新状态。**CAS callback 先发布再抛错同样无法判定是否已写入**：只返回失败标记，禁止反写旧 Job 或重试事务。callback 在发布前抛错也无法区分，可能留有临时资源变化；这是公开限制，恢复方式为重载最后存档。普通 CAS 前拒绝有单次 restore；restore 本身失败不承诺“什么都没发生”。不宣称 crash-safe/零损失。

create catch 中的特殊 token 重新发现分支也删除；没有 callback 的 acquireNew 不再靠 catch 二次扫描认领进行恢复。没有新增 Lua callback、每次提交持久日志、receipt/memo/duplicate cache、持久恢复队列、穷尽恢复链或 recovery authority 框架。成功后重试返回 STALE_REVISION 是接受的单人限制。

## 第一遍保留的边界

`LaborKernelAvailability.validate` / Boot 的 commit-only fail-closed 保留，缺桥返回 KERNEL_UNAVAILABLE，不访问 Store、不分配 ID、不退回 Lua 提交。Java callback try/catch 与 Lua bridge pcall 保留，不把全模组启动封死。

HAUL cold recovery 的 invocation-local 排队、Store.data 发布后按序应用及失败诊断保留，第二遍未修改 HaulJobRecovery/LaborStore；无新恢复期 authority 或持久队列。既有暂存 token 在提交成功后释放。它仍是第一遍已批准的有限适配，不代表 HAUL 领域迁移。

直接沿用 [Phase 0 写入口分类](dec003-entry-inventory.md)。LaborDomainAdapters 全部提交例外仍 OPEN，第二遍未改 adapter、调度、领域策略或业务规则。

## 第二遍定向验证

实际运行（仅 directed）：

- `LUA_PATH='Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;Contents/mods/EmberRoutesProbe/42/media/lua/client/?.lua;;' lua tests/lua/dec003-kernel-boundary-test.lua`：**PASS 21**。测试文件及断言未改；这是 Lua admission/dispatch 与真实 JobStore 守卫检查，不是 Java 执行。
- 同环境运行 `tests/lua/dec003-haul-recovery-boundary-test.lua`：**PASS** enqueue/publication/order/failure diagnosis。测试及断言未改；桥仍为替身。
- 第二遍修改的 `LaborJobCommit.lua`、`dec003-java-kernel-test.lua`：`luac -p` **PASS**；`git diff --check` **PASS**。
- `tests/lua/dec003-java-kernel-test.lua`：**NOT RUN（无 Java/JDK）**。已将 capacity-payload mismatch 拒绝改为 invalid capacity shape → INVALID_REQUEST；删除 post-CAS shrink/UNKNOWN 二次发布预期，改为 shrink 在 CAS 前、拒绝后 owners/容量恢复；新增 terminal cleanup 抛错保留 CAS、单次 restore 失败只返回 marker 且原 Job revision/state 不变。保留主链、stale、callback throw、cancel blocked、创建容量回滚及 >30 项创建覆盖。只能通过实际 Java/Kahlua bridge 执行，不能用 Lua 替身冒充通过。

Java 编译、实际 Java 定向用例、真实游戏 Exposer 注册/调用、游戏内 parity/performance 全部 **UNVERIFIED**。`java-labor-cost.lua` 所需 Java/Kahlua 与游戏均不可用，未测量性能，不宣称提升。

## 开放项与范围限制

- 在上述 cuts 下无法保证 CAS callback throw 的提交判定、restore 自身失败的完整还原、post-CAS cleanup 的一致完成；均停止自动恢复，重载最后存档。未为它们重新引入切掉的机制。
- 领域级 quarantine/UNKNOWN/reconcile、legacy/cold recovery、身份碰撞、adapter 补偿、个人 recurring episode/持久退役仍需后续逐项裁剪/迁移与 parity，**本轮仅登记，不迁移**。ClaimsKernel 保留其他消费者所需原语，不能当作全局安全机制已删除。
- DEC-004、商队、多人、离屏、业务规则入 Java、新调度/规划器、旧档迁移全部未启动。Phase 1 此次交付不代表 DEC-003 完成。

第二遍仅修改本契约、BACKLOG 的 DEC-003 行、LaborCommitKernel.java、LaborJobCommit.lua、dec003-java-kernel-test.lua；其他工作树差异为第一遍/起始改动，未重建。
