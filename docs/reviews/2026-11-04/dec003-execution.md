# DEC-003 执行记录：Phase 0 已盘点，实施未完成

2026-11-04；基线 `phase-3a-consolidation` / `9ebe06f`；起始工作树干净。

**DEC-003 未实现、未验收。本轮只交付入口盘点与明确开放项，未修改生产代码。**
没有阈值移除、Java-only 切换、Java create/cancel、领域迁移或启动门禁接线。现有 Lua 提交仍是生产路径，不能称为已隔离的 host/test reference。没有删除任何旧 Lua 路径，因而没有声称完成迁移 parity。

已先读用户指定 `dec003-brief.md`、`dec003-design-judgment.md`、DECISIONS 的 DEC-003/006，以及 HANDOFF、development-rules、代码证据规则与 BACKLOG。采用 judgment 顺序。没有另行扩展在线需求、NPC 行为、DEC-004、旧档迁移、联机或调度器。

## Phase 0

完整分类见[入口盘点](dec003-entry-inventory.md)：75 个显式 Job 调用/原语位置、六域原始恢复写、CraftLegacyRecovery、LaborStore 身份碰撞/隔离与责任入口、全部 LaborDomainAdapters 操作。

静态扫描的 UI update 与纯 Record 构造不计 Job 写。恢复、补偿、resume-only、removeSettled 均归为提交；没有以“带 revision”或“不是正常提交入口”豁免。没有未分类的已发现 Job 写，所有 kernel 外提交仍显式开放。文档以外生产树未变，最终重跑清单相同；这不是迁移后的 Phase 12 已通过。

## 实施停止点与具体证据

本轮没有完成 Phase 1 契约冻结，因而未越序执行 Phase 2/3 或逐域切换。以下是尚未解决的实现缺口，并非已证明无法修复，也不把缺 JDK 当作禁止写 Java 源码的理由。

1. **Java 增长认领缺失，不能直接切换 HAUL/Production。** `LaborCommitKernel.java:34–45` 只检查 addKeys 集合，`68` 注释后直接进入容量/CAS，未执行 Lua `LaborJobCommit.lua:162–165` 的 claims:extend。无容量 Production 输出新原件认领也经过该入口；简单取消阈值会把未经认领的 payload 发布出去。
2. **回调异常与失败返回不是同一路径。** `KernelValues.java:26–29` 在 pcall 失败时抛 KahluaException。`LaborCommitKernel.java:87–92` 只处理 store:update 返回 false；若回调抛错，之前施加的容量变化没有经过 restore/isolate。不能把现有 false-return 测试当作该异常路径的证据。
3. **restore 自身失败没有契约结果。** Java `LaborCommitKernel.java:12–17` 的 require 与 Lua `LaborJobCommit.lua:186–188、198–200` 的 assert 会直接中断，未返回明确 ROLLBACK_FAILURE。Job/claim/capacity 可能已部分变化；不能改成普通 TASK_WRITE_FAILURE 掩盖。
4. **CAS 成功后资源失败的隔离发布本身也可失败。** `LaborCommitKernel.java:93–95` 忽略第二次 update 的结果；Lua 同类路径 `LaborJobCommit.lua:214–226` 同样没有可证明的恢复闭环。需要同时处理 quarantine callback 抛错和 UNKNOWN 发布失败，不能释放责任后报普通失败。
5. **没有持久提交身份/结果或中断阶段恢复。** 当前 mutate 首先对 revision 做相等检查，成功后的同一请求重试只能得到 STALE_REVISION；create 首先分配 claimId，重复调用不是 prior result。`LaborJobCommit.lua:5–50` 与 `LaborCommitKernel.java:26–100` 无提交 receipt。新增 receipt 必须覆盖参数冲突、pending/完成区分、CAS 前后中断，以及恢复重建所需原件/容量事实；运行时 memo 不能充当 crash safety。
6. **HAUL 全链恢复尚不能接当前在线内核。** `LaborStore.data():42–340` 在构造局部 rebuilt 后才发布 root/claims/domainState。`HaulJobRecovery.lua:23–24、36–43、57–59` 在此期间原地修改 Job，容量恢复失败还释放重建 token。让该回调直接走需要 Store.data/getToken 的 mutate 会重入未发布的恢复；把 raw 写称为非提交则违反同一权威。须建立可供 Java 使用的恢复阶段权威上下文并保留 Lua 判定，再迁 HAUL 全链。该域保持原样并开放；未把它算作 migrated。
7. **cancel 与 SELF_CARE 尚未形成可执行契约。** JobStore 的普通 update 在 `185` 拒绝 terminal，在 `199` 执行状态图；CANCELLED 的 `valid` 还要求 KNOWN/零义务/零 claims (`54`)。个人 Job 是持久 recurring 身份（BuiltinJobContracts:19、SelfCareRecord:1–13），removeSettled 在 JobStore:232 明确拒绝 personal。必须区分任意状态的取消请求、仍持有原件的停止/核对、无责任后的终结，以及个人 episode 正常结束；不能把 cancel 实现为绕过 valid 强制终态或删除 recurring Job。这些现有策略未改。

依用户停止条件，不能将上述 callback/restore/恢复缺口强行作为已合规路径迁移。**剩余工作是实施工作，不是只等实机验收；父任务不能凭本记录合并为 DEC-003 完成。**

## Phase 1 待落实的契约清单（未冻结）

保持 `mutateJob(jobId, expectedRevision, proposedPayload, mutation)`；入口形状、domain draft/transition/graph 留 Lua。Java 必须重读当前状态、复验 revision/owner/resource、CAS、恢复/隔离并返回权威结果。

- revision 必须严格递增；期望版本不匹配不能覆盖，保留在途效果/原件责任。
- 创建是独立请求，没有 old revision：Lua 验证创建 envelope 与领域准入，Java 分配权威 claimId、认领/预留/写初始 Job；失败补偿和幂等不能分散给调用者。
- 取消独立于 ordinary update，从任何状态可接收，但不以“取消被接受”证明原件已结清；Lua 产出的停止/核对/终结意图需精确定义，不能迁业务判断到 Java。
- 至少统一 STALE_REVISION、INVALID_REQUEST、CLAIM_FAILURE、CAPACITY_FAILURE、TASK_WRITE_FAILURE、ROLLBACK_FAILURE、KERNEL_UNAVAILABLE、DUPLICATE_COMMIT。须定义 duplicate 的既往 ok/result 与 duplicate 标志如何并存；不能覆盖原始失败或把 rollback failure 降级。
- claims replace/extend/shrink、物品容量与工位容量、原件效果发布/恢复，以及同事实 token 重建要分别有输入契约，不能仅因表形状相近而统一业务。
- Boot availability 应独立于整模组 ready：检查 EmberRoutesProbeJava/laborMutate/laborCreate/cancel 及所用依赖；提交入口统一以 AVAILABLE/UNAVAILABLE fail-closed。当前 Boot.validateJava:8–35 没有这些内核门禁。不能先切换再补 boot。

## 每域结果（无 migrated 域）

所有域的 Java 实际运行证明、同起点故障对照、完整 job/revision/claim/capacity/item/in-flight/quarantine/error/rollback 对照均 **UNVERIFIED / NOT RUN**；没有用 Java 日志或 Lua 替身冒充实际 Java 调用。

| 域（按批准顺序） | draft/入口与当前路径 | claim/容量/原件/在途及具体失败开放项 |
|---|---|---|
| HAUL | HaulJobs.claim:81–102 创建草稿，commit:46–80 经 createClaimedJob/mutateJob；仍按容量/资源数分叉。 | manifest/activeAttempt 与物品 claims/reservation 均须保持；容量切换失败、CAS 成功后 shrink 失败及恢复 token 失败未达新契约。完整迁移停止，写原样保留。 |
| CRAFT / Production | ProductionJobs.create:83–103、commit:51–81；当前无 capacity 命令，始终 Lua。 | 原件 materials/tools/outputs 与 nativeAttempt 不能丢；Java addKeys 缺失会破坏输出认领。N/A 容量仅限该在线 mutate 无容量命令，不能推断所有责任不涉及容量。在前序 HAUL 后待迁。 |
| FIELD_WORK | FieldWork:137 直接 create；replaceField:124、reserveField:135、finishField:139。 | 工具托管、目标 claims、物品容量均有责任；接单认领失败在 FieldWork:155/157 写 SETTLING/CANCELLED，尚未原子化。待前序后处理。 |
| COOKING | shared CookingBudget.reserve:34–63 创建，client CookingService/CookingAgent + LaborDomainAdapters.claim/transfer/replace/finish。 | assets、工位容量、监管义务与持久恢复；replaceCooking:47–68 的 rollback assert 仍开放。客户端桥未另验，不能由 shared 通过推断。 |
| ACTIVITY | ActivityParticipant:41 create、48 update；adapter:162/180。 | 位置 claim 是资源，item 通常 N/A（参与 Job 位置责任；不能代表个人活动物品无责任）。UNKNOWN/wedged settle 后释放必须有既有业务证据；未迁。 |
| SELF_CARE | SelfCareRecord.create + SelfCare:32；SelfCareExecution、Reconciliation、TaskResume、LeisureService 的持久写一并属于该链。 | 食物/书/座位/原生 outputs 与 episode、resume 责任不可丢；finishPersonal 的写后释放、死亡保留与回滚失败均待迁；无 delete 替代 recurring 正常结束。 |
| BusinessJobs（最后） | retire:78–98；88 resume update、91 removeSettled。 | revision-only 不足：须保留 canRetire 的原件/在途/恢复守卫，跨个人 resume 提交与退役失败不能隐去。未迁。 |

没有 migrated 域，所以不存在可报告为通过的 revision 前后、回滚、幂等或 Java 执行 walkthrough。所有旧 Lua 实现仍在原生产位置，**不是“已保留为仅测试参考”**。

## 定向验证与原始输出

Codex binary：`/home/hatch/.local/bin/codex`；`codex --version` 输出 `codex-cli 0.166.0`，伴随 PATH alias 只读警告，命令退出 0。没有另启 Codex 子任务或子代理。
`codex exec --help` 明示：无 PROMPT 参数或用 `-` 时从 stdin 读；同时提供 PROMPT 与管道 stdin 时附加为 `<stdin>` 块。本轮读取已提供的任务文本，没有重新通过 stdin 启动执行，也不宣称验证了外层启动器的输入字节。

实际尝试（只定向，无全套）：

```text
$ env LUA_PATH='Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;Contents/mods/EmberRoutesProbe/42/media/lua/client/?.lua;;' lua5.4 tests/lua/labor-capacity-commit-test.lua
env: ‘lua5.4’: No such file or directory
exit 127 — NOT RUN

$ env LUA_PATH='Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;Contents/mods/EmberRoutesProbe/42/media/lua/client/?.lua;;' lua5.4 tests/lua/production-chain-test.lua
env: ‘lua5.4’: No such file or directory
exit 127 — NOT RUN（不能当作 non-capacity Java Production 证明）

$ luac -v
/bin/bash: line 1: luac: command not found
$ java -version
/bin/bash: line 2: java: command not found
$ javac -version
/bin/bash: line 3: javac: command not found
```

无修改 Lua 文件，因此“每个修改 Lua 文件的 luac -p”范围为空；不将缺失工具记为语法 PASS。Java 编译、真实游戏桥注册、Java callback 故障路径、游戏内 parity、磁盘中断恢复、性能重测均 **UNVERIFIED**。性能未来仍须在游戏中对照原 whole-store port 基线；不得用恢复 Lua 路径解决回归。

本轮文件：本执行记录、入口盘点、docs/BACKLOG.md 对应开放项、docs/INDEX.md 导航。最终 diff/链接/边界重查结果在本记录下方补记。没有 git commit 或 git push。

最终检查实际输出：

```text
PASS 77 relative file links (path existence only; no game/semantic verification)
PASS final inventory re-scan: 75/75 locations listed; production/Java/tests unchanged
$ git diff --check
(no output; exit 0)
```

链接检查为 Python 路径存在性检查，未运行仓库外 `.workbuddy` 的 doclink 命令；不声称检查了 Markdown anchor 语义。最终工作区仅 4 份 Markdown 文档变更；HEAD 保持 `9ebe06f`。
