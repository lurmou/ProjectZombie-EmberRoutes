# DEC-003 BusinessJobs migration 7/7

2026-11-04。基线 `phase-3a-consolidation` / `95e6f60`。本段收尾方式需先说明：Codex CLI 在上一轮因 5 小时用量限额耗尽而停在只改了生产代码、未写测试和文档的状态（用量页实查：5 小时剩余 0%，2026-11-04 13:17:38 GMT+8 重置；每周剩余 65%）。用户在 WhatsApp 明确授权“只允许这一次你接受收尾”，因此本段的定向测试和本文档由 Muse（父级）直接补完，不走 Codex；生产代码的 2 行改动仍是上一轮 Codex 的，Muse 没有改动它。DEC-003 至此 7/7 域全部完成迁移（带下文保留的 opens），但 Java 编译、真实桥接、实机、磁盘存档/读档、性能仍未验证，须等实机交接。

“商业”一词在此不是商店/贸易玩法。`BusinessJobs` 是已结算任务的收尾适配器：只读查制作/搬运记录，判断已结算任务能否退役，退役时清掉个人恢复引用、删信封、清存档回执。玩家看得见的订单/制作/配送/仓储不在此文件。

## 迁移点（仅一处）

client 前缀均为 `Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/`。

| 文件 / 函数 | 改动 | 未改 |
|---|---|---|
| `BusinessJobs.lua:1` | 新增 `local SelfCareCommit=require 'EmberRoutesProbe/SelfCareCommit'` | 无 |
| `BusinessJobs.lua:80-95` `M.retire` | SELF_CARE resume 写由 `store:update(other.id, other.revision, {payload=other.payload})` 改为 `SelfCareCommit.update(other.id, other.revision, {payload=other.payload})`，payload-only，无资源/键/容量命令；失败返回 false，退役在此停止 | `canRetire`、`retireSettled`、退役顺序（先逐个发 resume 更新，再 `removeSettled`）、`world.executionSave` 回执清理均未改 |
| `BusinessJobs.lua:14-44` `crafts/hauls/records/record` | 未改：只读投影，不产生提交 | — |

`SelfCareCommit.update`（SELF_CARE 段已建）是本段的唯一提交漏斗：先核验 kernel 可用、SELF_CARE 身份与 revision，再把 payload 变化折成 claims diff，走 `Store.mutateJob`（kernel `laborMutate`）。个人 Job 正常不进 DONE/CANCELLED、复用同一 Job id，因此没有发明 cancel/delete API。

## 两个定性决定（brief 的歧义，本段定稿）

### 1. `removeSettled`：决定 (a)，保留，不报迁移

`BusinessJobs.lua:99` 的 `store:removeSettled(id, j.revision)` 仍是 kernel 之外的退役原语。理由：Phase 1 没有 delete API，`JobStore.lua:244-257` 的 `removeSettled` 自身带结算门禁（非个人、终态、KNOWN、零义务、revision 匹配），且 `canRetire` 已在前面做了更严的门禁（无不确定项、无认领、无待处理订单、无进行中身体停止、无保存屏障）。不为本段新建 kernel 退役 API，不把 (a) 说成已迁移。将来如需 kernel 退役 API，须另立一段。

### 2. 回执清理：不是一次事务性提交

`BusinessJobs.lua:96-98` 清 `world.executionSave.byNpc[npcId]` 是直接改 ModData 根表，没有 JobStore 调用、没有 revision。它只随下一次世界保存落盘，不与退役事务绑定。测试只断言根表值被清掉，不声称它与退役原子。

## 终态拒绝：经 kernel 路径证明，不靠直接写

brief 要求证明 kernel mutate 保留 `JOB_TERMINAL` 拒绝。本段测试用 DONE 的个人 Job 直接调 `SelfCareCommit.update`：JobStore CAS 在 host 桥模型里拒绝，返回 `TASK_WRITE_FAILURE`。真实 Java 的对应行为在 `java/src/main/java/emberroutes/probe/LaborCommitKernel.java:170-175`：CAS 失败返回 `TASK_WRITE_FAILURE`，证据为 CAS 原因（即 `JOB_TERMINAL`）。host 桥模型丢掉了这层证据（只返回 `TASK_WRITE_FAILURE`，无 evidence），因此测试断言拒绝本身和 `TASK_WRITE_FAILURE`，并在代码注释里写明证据层差异，不把 host 模型的返回值说成 Java 证明。

## 定向测试

`tests/lua/dec003-businessjobs-migration-test.lua`，48 断言，全部通过（Lua host 桥模型，非 Java、非实机）。CRAFT 目标用 format 3（`BuiltinJobContracts` 对 format 1/2/3 只做退役准入，不要求完整制作记录；`canRetire` 的 format 4 制作量核对因此不适用），经 PREPARING→RUNNING→SETTLING→DONE 的普通 JobStore 转移进入结算态。

- 主链：已结算 CRAFT + 一个 `RESTORE_QUEUED` SELF_CARE resume → retire 为真，resume 变 `RESTORED` 且 revision +1（恰好一次 kernel mutate），目标信封消失，回执清掉，第二遍退役为假且不再写。
- `canRetire == false` 不写：认领被占的已结算任务退役为假，目标保留。
- 终态拒绝：DONE 个人 Job 的 `SelfCareCommit.update` 经 kernel 路径被拒，revision 不变（见上节证据说明）。
- 陈旧 revision：并发赢家在 `mutateJob` 内先把个人 revision 顶上去，resume 提交报 STALE，retire 在 `removeSettled` 之前停住；目标保留，resume 仍是 `RESTORE_QUEUED`，没有被错误标成 `RESTORED`。这证明了“resume 失败 → 不删目标”的顺序，resume 更新本身是逐个发、失败即停。
- 批量：无个人 resume 的已结算任务经 `retireSettled` 退役。

## 回归（本地 Lua 5.4.8，host 模型）

- 本段定向：48 PASS
- `task-business-stop-test.lua`：14 PASS
- 已迁移域：SELF_CARE 54、ACTIVITY 120、COOKING 49、FIELD_WORK 61、HAUL 55、CRAFT 54、kernel 边界 21、工作容量 95 PASS
- `luac -p BusinessJobs.lua` 通过，`git diff --check` 通过

## 预存失败（不是本段回归）

`tests/lua/settled-task-retirement-test.lua` 在本段前后都失败：它调用的 `Business.publishCraft`/`flush` 在当前 `BusinessJobs` 里已不存在（HEAD `95e6f60` 的该文件 grep 为 0 命中），是旧 API 退役后未更新的测试，不是本段 2 行改动造成的。本段新测试覆盖了当前 API 的主链和失败路径，旧测试的处置留给实机证据后的测试套件整合，不在本段删测试来凑通过。

## 保留的 opens（DEC-003 全域，不在本段强行收口）

- `removeSettled` 的 kernel 退役 API（见上，决定 a）
- 跨域共享身份分配/冲突修复（各段共有的 open）
- 预发布恢复写（CRAFT/FIELD_WORK/COOKING/ACTIVITY/SELF_CARE 的 JobRecovery 在 `Store.data` 发布前写 UNKNOWN）的全局恢复阶段边界与最终恢复契约复审，含 SELF_CARE 非保留 RUNNING 死亡缺口
- `transferCooking` 的 kernel 外所有权转移
- HAUL `M.cancel` 尚无生产调用者
- FIELD 终态门禁对仍带 toolSupply/capacity 的 advance-拒绝任务的业务缺口
- `claimCooking` 清通用 token 缓存背后的通用/域 token 查找优先级根因
- 坐姿社交的 `if not seated` 表现分支抽到会话表现代理（下次动社交代码时）
- 测试夹具债：缺 `tests/lua/work-test.lua`、Windows 原版路径夹具、未适配的配送取消-返还期望、部分直接测试的桥夹具不完整
- 本段未验证：Java 编译、真实桥接、实机表现、磁盘存档/读档中途退役、性能

DEC-003 域迁移至此收口，下一段是实机测试交接，不再是域迁移。
