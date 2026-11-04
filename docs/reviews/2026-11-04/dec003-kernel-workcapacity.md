# DEC-003 kernel work-capacity — OPEN，回归门禁停止

2026-11-04。基线 `phase-3a-consolidation` / `47de22cad68e35b797c67627987d6866f5f1885f`，叠加用户指定的 COOKING 部分迁移脏树。完整读取外部 brief `~/workspace/goals/emberroutes-npc-realism/files/dec003-kernel-workcapacity-brief.md`，以本轮用户实施授权覆盖其“准备稿不改代码”状态。未 reset、discard、revert、commit、push。没有重新读取在线需求，不宣称同步；本段实施用户已明确批准的合同。

**未完成、不可称通过门禁。** Java 扩展、adapter 删除旧分支、定向模型及 foundation 拆分已落盘。规定回归的 COOKING 文件第 197 行失败，按用户指令停止实现，未改旧回归断言、未注册 COOKING `capacityMutable=true`。因此当前生产 contract 对容量 publish 仍 fail-closed；这是待审查中间树，不能作为已启用功能发布。

Java compilation、real bridge calls、in-game parity、disk save/reload、performance 均 **UNVERIFIED**：本环境无 JDK（`command -v javac` 无结果）、无游戏。宿主模型通过不证明 Java 执行。

## 文件与修改范围

本轮仅修改两个 Java 文件、`LaborDomainAdapters.lua` 的 `replaceCooking`、拆分 `cooking-foundation-test.lua`；新增定向测试、独立 test-only workcapacity host fixture 和本文；导航与 BACKLOG 仅增加本段状态。起始脏树的 CookingAgent / CookingService / CookingBudget 和已有测试、oracle、证据不回退。`transferCooking`、`availableCooking`、`finishCooking`、CookingJobRecovery、身份分配、SELF_CARE retire、其他域生产实现均不改。

源码路径缩写：J=`java/src/main/java/emberroutes/probe/`；C=`Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/`；S=`Contents/mods/EmberRoutesProbe/42/media/lua/shared/EmberRoutesProbe/`。下述行号均重新读取当前源码；旧行号以起始树为准的地方明确注明。

## brief 引用复核与根因证据

| brief 引用 | 当前核查与结论 |
|---|---|
| J/LaborCommitKernel:20–57、98–107、111、116–122 | 起始树实际对应 Tx、物品容量校验/快照触发/执行；工作承诺缺失属实。后续修正后的关键行号见下方七项表。 |
| J/ClaimsKernel:18–20、88–101、105–113、124–133 | 桶/条目工厂、全量释放、物品恢复属实；新增前 reserveMany 实际 :124 起，新增后 :139–146。物品方法未改。 |
| S/LaborClaims:432–451、453–471、485–501、505–516、518–522 | 实读 reserve/releaseCapacity/restore/restoreWork/availableWork，数据及运算属实。**差异**：Lua restoreWork 不拒绝空字符串；用户本轮明确要求 Java 非空，按明确合同实现，不冒称逐字符等价。 |
| C/CookingCapacity:13–36 | 引用有效：resource 是 cooking:capacity:taskId，payload 是 endpointId/amount；reserve 预检，delivered 仅改草稿，release 经 publish。 |
| C/LaborDomainAdapters:50–102 | 起始树 :50–69 无容量 kernel 路径、:70–97 legacy、:99–102 只读函数有效；当前 replaceCooking :45–71 合流，availableCooking :72–75。 |
| S/BuiltinJobContracts:9–14、15、43 | COOKING 未启用、FIELD_WORK/HAUL 已启用属实；本轮未修改。 |
| S/LaborKernelAvailability | :3–12 三桥入口逐一验证，缺桥 fail-closed 属实。 |
| foundation:28–55、50、155–203 | 起始原文件有效；另发现 **:111–117 的交付 quota 断言也依赖内核**，一并迁移，未丢失。逐条映射见后表。 |
| C/LaborStore:180–182 | **引用含义漂移**：这是 identity collision 的 quarantine 容量记录，不是普通恢复。普通恢复由 :296 调 LaborRecovery，再调 CookingJobRecovery:3–39，后者 :24 调 restoreWork。共享桶结论由该实际链与 Claims.available 支持。 |
| 既有 COOKING 段文档 | 已读 [原段证据](dec003-cooking-migration.md)，保留其 transfer/recovery/identity/retire 开放范围；其中容量硬停止描述是本轮修改前状态，不能作为本轮启用证据。 |

创建认领：S/CookingBudget:63 → C/LaborJobCommit:18–29 → J/LaborCommitKernel:181–216 acquire/create；运行时工作认领见 C/CookingCapacity:19–22 → Context:16–21 → adapter:45–70。正常释放：CookingCapacity:24–36 → adapter workCapacity=false + removeKeys → Java:151–162；终态 Java:174–176 release → ClaimsKernel:99–103 → releaseCapacity:88–97。异常打断：Context:45–53 pause、:68–90 persist 保留容量发布；unknown :22–31 保留责任；CAS 拒绝 Java:168–171 调 Tx.restore:37–62；恢复不成功继续使用原有 PARTIAL_RESTORE 标记，CAS 已达抛错用 :64–67 reload marker，不建立第二权威或恢复队列。

## brief §§3–6 逐点判定

| 提案点 | 代码证明 / 实施与限制 |
|---|---|
| 3.1 set / false / nil 独立于 capacity | CookingCapacity:19–35 明确 set/删除模型；Java:95、115–132、151–160 新增 work 字段；nil 不触碰。原物品命令形状与执行块保留。 |
| 3.1 shape / gate / ownership / target / item conflict | Java:115–132 校验 gate、非空 String、正有限 Number、仅 key/amount 字段；目标和条目冲突在快照前拒绝；:152 在 extend 后校验 cooking 资源，使首次 addKeys 可以建立所有权。set 再校验同一权限。false 也必须有 cooking 资源，并拒绝物品/外来条目。 |
| 3.2 setWorkCapacity 本体 | J/ClaimsKernel:115–127：验权→形状→capacityKey→同一桶→token/count 冲突→缺项 count+1→total-old+new→amount/workAmount/token/capacityKey。复用 :18–20 工厂；恢复直接调用此方法，不复制算术。非空 key 是用户明确的收紧，不改 Lua restoreWork。 |
| 3.2 release | 原 releaseCapacity:88–97 全量使用 claim.amount，count 清零、删 entry、清 token key、bucket.count 减一、空桶删除，未修改；模型验证正常释放与交付零值。 |
| 3.3 snapshot | Java Tx.snapshot 保留 workExists/workAmount/workKey；无旧工作条目不恢复。**FOLLOW-UP 已删除 Java 与宿主模型的 workCount**：记录但不使用没有价值；合法工作条目 count=0 在快照前验证。 |
| 3.3 restore 顺序与失败 | Java:43–60 原 owners/resources→releaseCapacity→逐 item restore 顺序不动，之后仅 workExists 真时调 setWorkCapacity，最后 claims.revision。原 fail marker 不改。定向模型覆盖已存在/不存在与 changed/unchanged CAS 拒绝；Java 执行及抛错恢复路径未验证。 |
| 3.4 注册三前置 | Java/adapter 源码已落盘，定向模型通过；回归未全过，故第三条件不成立。**未实现注册**，不可绕过该条件。 |
| 3.5 publish free | v1 不新增重检；详见下节，真实可达性未证明。 |
| 3.5 shrink | ClaimsKernel:78 仅 item: 清容量；adapter:55–63 显式 false 清桶、removeKeys 清 owners。定向模型覆盖二者同发成功与 CAS 拒绝恢复。 |
| 3.5 cancel | Java:174–176 无 work 命令也 release(token)；定向模型 terminal cancel 单独验证，不需要依赖显式 false。真实 CookingRecord 终态仍要求责任已结清，不为测试放宽。 |
| 4 adapter | :49–70 按 before OR after 构造命令，unchanged 仍带 set；单次 mutate/cancel、失败立即返回、成功非终态重取 token；旧 claims:replace/restoreWork/jobs:update/rollback assert 分支全部删除。 |
| 5.1 失配根因 | Budget:63 已走 kernel create，availability:5 验三入口；起始 foundation 没安装 Store，预测/交付仍直接 jobs:update。不能靠往原文件补桥解决架构分界。 |
| 5.2 拆分 | 30 条纯 Lua 留 foundation，28 条 quota/shared 转定向测试；原 58 条逐一映射。预测和交付更新改用 S.mutateJob，配额创建用真实 Budget→Store.createClaimedJob；共享 Job 创建改用 kernel create，语义不变、调用适配。 |
| 5.3 cases 1–4 | 原 quota 十项及交付两项均在定向测试，真实 Policy/Budget/JobStore 派生；save/reopen 仅同内存根 reopen，不是磁盘存取。 |
| 5.3 cases 5–13 | 原轮次模型64项；FOLLOW-UP 当前宿主模型95项通过（非 Java 执行）。覆盖首次、幂等、缩量/清零/释放、changed/unchanged CAS、共享 HAUL 桶/超满、cancel、target/count/foreign 冲突。count/foreign 另有 setWork 原语定向验证，不声称 Java 真实调用。 |
| 5.3 case 14 | kernel21、HAUL55、FIELD61、CRAFT54 通过；COOKING48 未通过，已停止。 |
| 5.3 case 15 | labor-capacity-commit 既有缺桥失败见原 COOKING 证据；未修改、未复跑，未计入通过数。 |
| 6 代码/数据边界 | Java 原 item 方法、capacity 校验/执行保留，工作复用原 capacity；未引入第二桶。HAUL/FIELD 的 provider contract 不改，回归55/61通过。 |
| 6 contract 边界 | 定向测试检查 candidate COOKING flag 前后 HAUL/FIELD flags 不变，并用真实 HAUL primitive 验证共享空间；FOLLOW-UP 补充 test-only flag 开关前后 HAUL/FIELD 的宿主 change 容量接受/拒绝结果一致；生产注册仍未发生，不能据此宣称生产注册验收。 |
| 6 测试边界 | 旧回归断言零修改；COOKING 一红即停止，未强行满足相冲突断言。 |

## 调用链核查（源码，不等于实机）

| 调用方 | 实际路径 / 命令 | 绕过 replaceCooking？ |
|---|---|---|
| coldGate | CookingCargo:146–167 → Capacity.free/reserve:13–22 → Context.publish:16–21 → adapter。无 job 的预检 reserve 返回 true，不生成持久容量。 | 有 job 的提交不绕过 |
| reserve 首次/增长 | capacity:19–22 加稳定 resource、storage；adapter set。已有同目标足额直接返回 true，无新提交。 | 否；足额是无写早退 |
| delivered 缩量 | CookingActions:340 调 Capacity.delivered:24–30 改草稿；Actions leaf:72–83 committing→observe→Record.confirm→Context.publish。剩余正数 set。 | 否 |
| delivered 零 | 同链，删 capacity/storage/resource；adapter false+removeKeys。 | 否 |
| release | Capacity:32–36 → Context.publish，false+removeKeys。 | 否 |
| unknown | Context:22–31 → publish，保留原额 set。 | 否 |
| pause | Context:45–53 RUNNING→STOPPING 经 publish，保留原额 set，再清身体。 | 否 |
| persist | Context:68–90 检查 bodyStopped，非终态保留责任 publish；终态需清 claims/obligations，之后 finish。 | 否；已终态清理不是新 publish |
| 其他 publish | Context:16–21 一律 replaceCooking；adapter 用 before/after 而非 capacityChanged。 | 否 |
| 读档重建 | CookingJobRecovery:24 restoreWork，LaborStore:296 / LaborRecovery 调入。 | **是，明确保留**；预发布恢复与 UNKNOWN 原表写不迁移 |
| handoff | adapter transferCooking:22–34 → jobs:transferCooking，再认领。 | **是，范围外开放** |

## 3.5 结论与 retained opens

v1 不透传 free、不加 publish-time 重检。Capacity.reserve 的 free 预检与 publish 之间，同桶 HAUL 占用可能变化；这是 **KNOWN LIMITATION：kernel 不保证 publish-time capacity sufficiency（发布时容量充足）** 的已知竞态窗口，源码支持窗口存在，**实机可达性/交错时机未证明**。Context.publish 只有 c/proposed 参数，不带 endpoint/free；扩展签名与 publish-time 上限拒绝属另行契约变化，不在本段强加。

单 token 的 item/work 混合条目不获支持：set 拒绝非零 count、非空 items 及不合法工作条目；相同桶的不同 taskId 工作/物品共享 total。removeKeys 本身不清 cooking 桶，必须配 false；取消 terminal release 是独立清理保障。未引入持久恢复队列，未伪造 ItemID。

保留开放：COOKING contract 未启用；旧 COOKING 回归第197、200行要求 legacy 路径，与新合同冲突，需后续明确授权调整该回归的容量部分或重新划定无容量门禁后再续做，**本轮未改**。transferCooking、CookingJobRecovery 预发布写/重建、共享身份分配、CookingService SELF_CARE retire 原有开放不变。Java 编译、桥值类型映射/实际执行、恢复抛错、原生烹饪/停止、游戏 parity、磁盘保存重载、性能及竞态均未证明，不用宿主模型替代。

## 检查记录

统一 `LUA_PATH='Contents/mods/EmberRoutesProbe/42/media/lua/client/?.lua;Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;;'`；解释器 `/home/hatch/workspace/tools/lua-5.4.8/src/lua`，语法检查同目录 luac。

| 检查 | 本轮结果 |
|---|---|
| directed core（Java 后、adapter 前） | PASS 27；Lua 新模型，非 Java |
| directed 完整（当前 FOLLOW-UP，宿主 Lua 模型层） | PASS 95；含原断言28条及模型/adapter补充；candidate contract 仅在测试进程启用，结束恢复原值 |
| foundation 独立 | PASS 30；无桥 shim |
| kernel boundary | PASS 21 |
| HAUL | PASS 55 |
| FIELD_WORK | PASS 61 |
| CRAFT | PASS 54 |
| COOKING | FAIL，:197 `classified legacy capacity promise preserved`；未得到48项通过。下一条:200也要求 unchanged publish 不调桥，执行尚未到达，不能算实际第二失败。 |
| luac | FOLLOW-UP 对包含起始脏树的全部 changed/new Lua 逐文件检查通过（见本轮记录） |
| git diff --check | 通过；段文档本地链接存在性检查通过；adapter 在 replaceCooking 以外与起始脏树逐字一致；无提交推送 |
| labor-capacity-commit | 本轮未运行，既有失败来源见原段证据，保持范围外 |
| Java/真桥/游戏/磁盘/性能 | UNVERIFIED |

host fixture 独立实现 work set 算术、快照及 restore 顺序；真实 Lua Claims/JobStore/LaborJobCommit 参与。它仍是宿主模型，不是完整 JVM/回调异常模拟器。shared rebuild 通过真实 CookingJobRecovery 在新内存 Claims 上重建；替代原测试的模块重载夹具装配，保留“恢复原件/容量、旧 token 无效”的断言，但不声称完整 LaborStore boot、collision 扫描或磁盘重载已验证。测试中 scopeAllowed / native endpoint/body 等是明确替身；未放宽 Record、revision、终态和 ownership 生产守卫。

## FOLLOW-UP：七项独立评审修正（当前树）

本节覆盖上文旧行号与旧轮次结果；原 foundation 映射中的 directed 行号保留为历史迁移定位，以 assertion message 核对当前文件。生产 COOKING capability 仍未注册，测试文件开头明确为 **test-only capability switch**，最终恢复 originalMutable 并有计数断言（core 早退路径也恢复并断言）。这不是以生产 gate 测试生产 gate。

| 项 | 当前实施 / 证据 |
|---|---|
| 1 entry 类型与 workCount | J/ClaimsKernel:114–119 定义工作条目：workAmount 存在、items 空、count 为数字0、entry.token 与 cooking owner 均为本 token、所在桶 key 等于 token.capacityKey。J/LaborCommitKernel:128–132 在 snapshot :138 前返回 CAPACITY_FAILURE / CAPACITY_ENTRY_INVALID；无 workAmount 的物品条目仍 CAPACITY_UNAVAILABLE。宿主镜像并验证 mixed、items-only、foreign-entry-token、foreign-owner、wrong-bucket，桶与 owners 不变。Java Tx 与模型均删除 workCount。false 无旧 capacityKey 为空释放，新增定向证明。为返回明确 entry 证据，work 命令的全资源 owner 校验位于 entry 校验之后、快照之前；无 work 命令的原 owner 守卫位置保持。 |
| 2 幂等与先验后写 | J/ClaimsKernel:123–130 为 owner→非空 key/有限正 amount→target→entry conflict，:127 的新桶仅局部创建；:131 后才写 count/total/entry/capacityKey。原算术已符合 `total-old+new`，未为幂等杜撰修复；本轮只补 entry 类型约束。宿主直接 set 两次保持同桶、total=3/count=1；新 key 的 bad shape、target mismatch、foreign owner 全无桶/无 token key 改变；已有桶 item/foreign/混合冲突保留原额。 |
| 3 跨域隔离 | 宿主测试 cooking4/free6→HAUL4拒绝、HAUL2成功；HAUL4/free6→真实 production Capacity.reserve4 预检拒绝、reserve2成功。双方 CAS refusal 各验证另一域 entry 身份/数额、共享 total/count 与双方 owners；双方 release 分别保留对方，cancel 无 work 命令且有 HAUL 时仅清 cooking。HAUL publish 使用 host-model change() + 最小 CAS store，明确不是 HAUL adapter 或 JVM。HAUL/FIELD flag 与 capacity 接受/拒绝结果在进程内 cooking 开关前后相同。 |
| 4 注册区分 | test-only 开关有头注释、结束恢复断言；BuiltinJobContracts 未改。**PENDING**：待 cooking-migration :197 决定解决并正式注册后，必须从头重跑完整 kernel21 / HAUL55 / FIELD61 / CRAFT54 / 经该决定更新的 cooking-migration / workcapacity / foundation30；当前 pre-registration 结果不算最终验收。 |
| 5 顺序与恢复 | 固定 Java 顺序（J/LaborCommitKernel:139–171）与 host mirror 均为 **extend → item capacity → workCapacity → shrink → CAS**。既有成功 replace/release、CAS failure replace/release 已证明宿主 owners 与桶金额/清空一致。本轮新增 work amount 已变为2后注入 shrink failure，验证恢复旧3及 owners。见下方证伪说明。 |
| 6 三层验收 | 所有 PASS 数字均为宿主 Lua 模型/接缝或纯 Lua 层。模型只证明命令构造及模型语义；Java 与实机分层如下，不能互相替代。 |
| 7 数值与限制 | Java change :118–120 和 set :124–125 均具非空 key、finite-positive amount 校验。publish 空 key / NaN / +infinity（math.huge）/ zero 原有覆盖，新增 negative；无缺失时不重复增测。cancel+HAUL 补齐。v1 无 publish free 保证，保留 KNOWN LIMITATION。 |

**两处证伪 / 有界替代：**

- “reverse likewise”如果解释成 raw kernel setWork 的 free 拒绝，则被 v1 决策与源码证伪：setWorkCapacity 参数仅 self/token/key/amount（J/ClaimsKernel:122），无 free 输入或 free 检查；容量准入由 production `CookingCapacity.reserve` :16 的 `C.free` 预检执行。反向测试已使用这层，未编写错误的 raw-kernel free 拒绝期望。
- “用不属于 token 的 removeKeys 触发 work 后 shrink failure”被 Java 的 **快照前** remove owner 检查（J/LaborCommitKernel:99–100）证伪：必先 RESOURCE_NOT_OWNED，无法走到 work :154 或 shrink :166。不移除这个守卫来迎合测试；模型补镜像检查并断言早拒绝。另用 test-only shrink stub 拒绝一个确实已拥有的 key，记录回调确实见到新 work amount，再断言回滚恢复旧 amount/owners。它证明宿主 work-before-shrink 的 restore 覆盖，不声称真实 Java 已注入故障。

FOLLOW-UP 静态：全部11份 changed/new Lua 的 `luac -p` 与 `git diff --check` 通过；本段本地文档链接存在性检查通过。额外检查 BACKLOG 全文件链接发现既有缺失 `docs/history/2026-10-24-backlog-before-navigation-cleanup.md`（HEAD 同样引用该文件）；未改动该范围外历史链接，不能记录 BACKLOG 全文件 doclink 通过。

### 三层验收清单

| 层 | 本轮实际结果 / 限制 |
|---|---|
| Host Lua model / Lua 接缝 | workcapacity **95**、foundation **30**、kernel boundary **21**、HAUL **55**、FIELD_WORK **61**、CRAFT **54** PASS。cooking-migration 仍在 :197 唯一已观察失败 `classified legacy capacity promise preserved`；执行未越过该点，不将后续断言记作通过。 |
| Java compilation | **UNVERIFIED**：无 javac/JDK。源码检查不是编译。 |
| Real bridge calls | **UNVERIFIED**：宿主 fixture 不调用 JVM。 |
| Java bucket arithmetic | **UNVERIFIED**：宿主算术通过不证明 Java 算术执行。 |
| Java CAS restore / shrink failure restore | **UNVERIFIED**：上述故障注入只在宿主模型。 |
| In-game cooking / delivery / cancel / save-load | 各项均 **UNVERIFIED**：本环境无游戏；内存 JobStore reopen 不是磁盘保存验收。 |
| Performance / publish-time free race | **UNVERIFIED**；kernel **does NOT guarantee publish-time capacity sufficiency**。 |

本轮仅增改 ClaimsKernel.java、LaborCommitKernel.java、workcapacity host fixture、directed test、本文及 BACKLOG 当前行；起始 COOKING partial tree 原样保留，未改禁止范围和旧 cooking-migration 测试，未 commit/push。

## 原 foundation 每条断言映射

原行号来自修改前完整文件，58 条全部唯一映射。`foundation` 指 `tests/lua/cooking-foundation-test.lua`，`directed` 指 `tests/lua/dec003-kernel-workcapacity-test.lua`。普通 assert 用于 fixture 构建；本表枚举所有计数 check 断言。原 :50 预测和 :114 交付更新均通过 production-consistent `Store.mutateJob`，原 :155 创建改为 `Store.createClaimedJob`，不是预期放宽。原 :111–117 属 quota 派生，不能误留在纯 Lua foundation。

| 序号 | 原行 | 新位置 | 原断言语义（原 message） |
|---|---|---|---|
| 1 | 16 | foundation:16 | away members remain; confirmed retired excluded |
| 2 | 18 | foundation:18 | pending transfer still counts old committed base exactly once |
| 3 | 20 | foundation:20 | committed migration changes supply population |
| 4 | 23 | foundation:23 | one person can start one indivisible native batch |
| 5 | 25 | foundation:25 | do not open oversized second pot once minimum reserve exists |
| 6 | 26 | foundation:26 | unknown/NaN supply cannot grant work |
| 7 | 27 | foundation:27 | no population stops new work |
| 8 | 39 | directed:120 | first cook receives finite quota |
| 9 | 40 | directed:121 | same-frame contender cannot use old supply stamp |
| 10 | 41 | directed:122 | duplicate request does not create/replay job |
| 11 | 43 | directed:124 | unconfirmed output retains quota but is not edible or predicted food |
| 12 | 45 | directed:126 | unloaded/incomplete observation is not zero stock |
| 13 | 46 | directed:127 | second cook can cover different remaining deficit |
| 14 | 47 | directed:128 | two reserved batches prevent third full-deficit claim |
| 15 | 50 | directed:131 | verified prediction stays in existing job |
| 16 | 52 | directed:133 | prediction and unknown quota have distinct accounting |
| 17 | 55 | directed:136 | save/reopen derives exactly same allocations from Jobs without second ledger |
| 18 | 62 | foundation:38 | retained originals have matching declarations |
| 19 | 65 | foundation:41 | persist intent before native effect; interrupted commit cannot be called known |
| 20 | 67 | foundation:43 | unfinished commit cannot auto-replay with another attempt |
| 21 | 68 | foundation:44 | duplicate complete cannot enter commit twice |
| 22 | 70 | foundation:46 | cannot clear unknown flag without effect receipt |
| 23 | 72 | foundation:48 | duplicate declaration rejected |
| 24 | 74 | foundation:50 | sparse item manifests rejected |
| 25 | 76 | foundation:52 | held ingredient cannot disappear from declarations |
| 26 | 78 | foundation:54 | unknown or retained originals forbid terminal job |
| 27 | 82 | foundation:58 | observed partial ingredient consumption can resolve unknown effect |
| 28 | 83 | foundation:59 | duplicate receipt cannot complete effect twice |
| 29 | 85 | foundation:61 | unchanged native ingredient is not completion evidence |
| 30 | 87 | foundation:63 | other attempt receipt cannot resolve this operation |
| 31 | 89 | foundation:65 | accepted historical receipt cannot be rewritten |
| 32 | 91 | foundation:67 | unknown effect cannot discard its original responsibility |
| 33 | 93 | foundation:69 | admitted quota cannot grow behind other cooks |
| 34 | 95 | foundation:71 | cyclic native-like data fails bounded copy rather than recursing forever |
| 35 | 106 | foundation:82 | verified shutdown receipt survives clearing furnace obligation |
| 36 | 110 | directed:141 | delivery publishes original identity and actual amount |
| 37 | 112 | directed:143 | delivered meal is not counted in both shared S and old P |
| 38 | 138 | foundation:108 | half cooked pot counts native effective value once |
| 39 | 140 | foundation:110 | positive hunger contribution does not authorize unsafe food |
| 40 | 142 | foundation:112 | frozen food not silently counted as directly edible |
| 41 | 144 | foundation:114 | cooked spice does not become a completed meal |
| 42 | 146 | foundation:116 | missing native effective amount stays unknown, not zero |
| 43 | 155 | directed:148 | cooking stores ordinary durable Jobs |
| 44 | 162 | directed:155 | original acquired through existing shared claims |
| 45 | 164 | directed:157 | other production sees same item owner |
| 46 | 167 | directed:160 | durable transition refusal rejects replacement claims |
| 47 | 168 | directed:161 | failed publish restores old original and token without leaking new claim |
| 48 | 173 | directed:166 | other cook cannot steal retained pot |
| 49 | 174 | directed:167 | claim conflict changes neither durable declaration nor old owner |
| 50 | 178 | directed:171 | new attempt fences old token and revision |
| 51 | 182 | directed:175 | unknown commit persists in same Job and retains original |
| 52 | 184 | directed:177 | unknown original cannot be released |
| 53 | 185 | directed:178 | failed finish keeps shared original protected |
| 54 | 189 | directed:182 | load restores unknown cooking claims before any new allocation |
| 55 | 190 | directed:183 | old in-memory token cannot operate after world claim rebuild |
| 56 | 196 | directed:189 | a durable batch promise shares the existing hauling space budget |
| 57 | 198 | directed:191 | overfull cold storage never invents free space by refunding a clamped promise |
| 58 | 202 | directed:194 | saved cooking promises rebuild before another worker can reserve the destination |
