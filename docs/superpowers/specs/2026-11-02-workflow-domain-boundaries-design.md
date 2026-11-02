# 普通工作公共契约与 FIELD 职责拆分

> 日期：2026-11-02｜状态：用户已确认方向并授权开始；逐批实施与验证，不代表全业务验收通过。
> 基线：`phase-3a-consolidation@4a8c57c` 加本地未提交修改。外部 v3.0 审核稿是参考候审材料，本文件只落实本轮已确认范围，不整体批准其中的自述授权。

## 1. 决定与范围

用户确认：统一普通工作的安全、需求解释和只读展示契约，各领域独立决定实际步骤；认可拆分 FieldWork 的职责，允许保留薄的 FIELD 入口。与 [NPC 唯一架构](2026-10-22-npc-behavior-architecture-design.md)、[统一任务协议](2026-10-23-unified-task-dispatch-design.md) 和 [Phase 3A](2026-10-31-phase3a-job-contract-standardization-design.md) 共同执行。

不新建统一 Workflow 执行引擎、第二个 Runtime、第二份资产账本或 UI 框架。已有 CookingAgent BT、HaulAgent 动态路线、Production/BOM 保留各自决策权。只有两个真实业务的前提、失败和责任语义一致时才提取公共代码。

在线唯一需求已于本轮审核读取；人工制作的玩家配方与必要工作台创建门禁维持现行契约。需求缺工具、材料、执行人员不应被误解释为需求不存在。不扩充建设、医疗、维修或商队功能。

## 2. 现有事实和首批选择

- FieldWork 原 `submit` 同时创建运行上下文、校验成员/政策、提供移动适配、构建 Runtime spec、推进 FIELD 阶段并处理停止持久化；`provider/advance/prepareRecovery` 另负责接单、恢复及退役。
- 原 `spec.tick` 在 WORK 成功后固定进入 COLLECT/DELIVER，只有货物阶段完成后调用 `def.continue`。FieldProviders.continue 会替换目标并清空 assets；改变决策时机前必须先保留未结原件。
- 创建认领链：FieldWork.provider.claim → JobStore.create → LaborStore.claimField → Runtime.submit；正常释放链：spec.stopAdapter.persist → LaborStore.finishField → Directory.release / removeSettled；中断链：TaskBusinessStop → SUSPENDED 或 RECONCILE_REQUIRED → prepareRecovery / wake。
- CookingContext 已有将运行事实提交、停止适配与业务动作分开的组合做法；借鉴边界，不复制其烹饪专有状态。

比较：直接修改大函数能较快改变续作，但难以区分结构移动与行为回归；一次建立全业务 Core 则会重复现有安全设施。因此先进行有明确调用方的 FIELD 等价拆分，再单独实施业务策略变化。

## 3. 首批模块合同：等价拆分

| 模块 | 责任与接口 | 不拥有 |
|---|---|---|
| FieldWork | 保留 provider/offer/retained/wake/advance/prepareRecovery；submit 执行准入后组合 Context 和 Session，保存世界局部 live/handle、重试与冷却 | 不再内联上下文及 spec 实现 |
| FieldContext | `new(actor, job, binding, def, root) -> context 或 nil`；认领现有 FIELD token，提供 same/change/unknown/valid/move 和成员清债模式 | 不建持久表、Session、独立调度 |
| FieldSession | `spec(context, def, cooldowns) -> TaskRuntime spec`；现有 start/tick/finished、TaskBusinessStop、persistFailure | 不调用 Runtime.submit、不保存 live 索引、不创建第二身体授权 |
| FieldSupplies / FieldCargo / FieldOperations | 保留现有工具准备、实物取放、原版效果核对 | 不接管公共派工或持久资产裁决 |

Context 中 job 为当前 detached Job；change 仍经 LaborStore.replaceField。root 用于同世界校验；cooldowns 是 FieldWork 拥有的世界局部表，由 Session 在原有失败结清点写入。模块级不新增可变世界状态。

本批保持：全部公开 FieldWork API、Runtime spec 标志、守卫顺序、100ms tick/500ms 校验缓存/500ms advance/5s 重试/10s 失败冷却、所有状态与 reason、原生效果核对和停止回执、FieldRecord format=1、JobStore 与 byNpc 契约、现有阶段推进顺序。新模块沿现有模块 require，无原生 API 新增。

本批不将固定阶段包装为新的公共协议。其暂时保留仅用于隔离等价拆分与后续行为变更；完成本批不能宣称已解决连续作业或动态 UI。

## 4. 后续业务批次与门禁

1. 工具返还闭环：明确目录 Offer 的创建/释放所有者；持久 ToolCustody 与内存 ToolReturnRecord 分开；冷启动复核原件在 NPC、合法目的仓或位置未知，不能无条件把 PENDING_RETURN 当作尚未转移。补齐已到仓未清偿、中断再派工、死亡/失踪留责证据后再合入。本批拆分不改变返还语义。
2. Demand/Feasibility + 清洁可见闭环：已加载区域源观察独立于 NPC 空闲、工具与优先级；观察覆盖与角色资格分开；诊断只读且未知不能算零。接回现有 PublicWork，不新建派工器。UI 复用 PageLifecycle/Widgets 和现有监控服务，按 dirty 派生快照。
3. FIELD 自主步骤：领域在真实效果归账后选择继续、补给、收集、回仓或等待。先分离目标锁与未结原件，再提前连续作业；所有新工具申请失败可回滚，旧货物和托管不可被替换。清洁零产物、地面原木与满载、农业水耗、forage 精确 icon 分别验收。
4. HAUL/DELIVERY、CRAFT/COOKING 接入统一观察与动态投影；复用已有 Job/Manifest/BT/BOM，按业务保留专属回执和义务。没有两业务等价证据不新建公共过渡函数。

每个后续批次先以实际代码细化文件和接口；本轮不预写虚构的世界观察/恢复 API。新的 Schema/释放语义变化分别标记为契约变化或缺陷修复，不能冒充等价拆分。

## 5. 续接细化与安全基线

### 2026-11-02 续接：FIELD 领域步骤先行

用户要求继续 FIELD 职责拆分。当前批次先退出 Session 中的固定阶段决策，工具返还及 Demand/UI 保留为后续独立批次。此顺序调整不撤销其安全缺口，也不授权绕过工具责任。

- 新增 FIELD 专属 `FieldWorkflow.step(c, def)`，返回 Running/Success/Failure；只决定 FIELD 的准备、作业、续作或货物处理，不构造 Session，不成为跨业务 Core。
- FieldSession.tick 仅做活跃性、节拍和领域结果收束；将流程交给 FieldWorkflow。Success 仍是结算申请，只有原停止/持久责任校验通过才进入终态。
- PREPARE 的 Running/转入 WORK 不解释为整单结束；WORK 后没有未结原件、holding、capacity、toolSupply 时可直接续作或申请结清，不制造空 COLLECT/DELIVER。存在货物则按现有逐原件交付执行，产量/容量未证实时不提前扩大有货批次。
- 续作只在已确认 workDone、effects=KNOWN、无未完成 attempt、无 holding/capacity/toolSupply 时换目标。以 Discovery.claim 的真实分型复验代替通用 Discovery.object 假设；同格不同 icon 可独立接续。
- 换目标只替换已完成目标 Claim，保留非目标 claims 和全部原件记录；新目标所需工具准备必须进入 PREPARE。提交失败释放本次新建而未生效的托管，不能释放原有工具/货物责任。新目标复位 workDone/attempt/spotted，防止沿用上一个 icon 的发现记账。
- FieldWork 仍有真实接单/恢复/退役所有权，不机械删除或改名。删除须先完整替换全部运行/恢复调用并验收；本批不满足删除条件，不宣布旧文件已退休。

### 必须保留的安全基线

### 工具返还实施细化（2026-11-02，沿已授权缺陷修复范围）

返还责任继续由 ToolCustody 唯一持久保存，不另建 Job/资产表。format=1 增加可选且严格校验的 `returnIntent={format=1,jobId,destinationId,scopeId}`，在物理动作前记录；没有意图的旧记录仍可读取，但不能猜测其返还目的地或自动视为未转移。加载保留 PENDING_RETURN/returnJobId，不再无证据降为 HELD。

ToolReturnService 的恢复只核对原意图，不重放 PUT。通过正常非抢占 Runtime Session 和既有 TaskBusinessStop 得到停稳证据后：原件实际在已记录合法目标仓则清偿；仍在 NPC 背包则撤销本次返还并回到 HELD；不可观察或原件不明则 RECONCILE_REQUIRED 留责。当前无法解析的目标不切换为另一个仓库来假证明到账。新劳动不能使用 PENDING_RETURN/RECONCILE_REQUIRED/DEAD_CARRIER 工具。

Provider 保存本世界 Offer 与对应执行结果的派生关联；Service 只对 Provider 请求追踪的返还保存有限内存终态证据，已知停稳并清偿/退回持久托管后 Provider.advance 释放目录并消费结果。未知结果不释放，换世界丢弃派生关联但不改旧世界持久责任。成员恢复和普通派工后台均能触达待恢复返还，扫描分片、有节拍；不依赖打开 UI。

这是对无条件降级恢复和目录泄漏的缺陷修复，改变其原失败处理；不记为等价重构。原动作和身体停止继续复用现有适配，未实机不宣传恢复已验收。

- CRAFT format=4 / HAUL format=3 已经由 ProductionJobs/HaulJobs 使用 createClaimedJob 与 mutateJob；执行草稿不成为持久表第二写入口。新工作协议复用这些设施。
- JobStore.scopeBlocked 对未决制作结果实施作用域隔离。身体可停稳、自理可继续和普通工作可准入是不同事实；本次不缩小隔离范围。若需缩小，须单独证明未知 ItemID 不会被其他任务消费。
- 不支持历史格式在写入前拒绝并保留数据与原件；不开发通用旧档迁移。已有批准的有界升级仅适用其指定范围。
- 唯一身体仍经 TaskRuntime/TaskController；原件与工具责任仍经 LaborStore/LaborClaims/领域记录。旧会话不能下发新动作；已发生效果不能因回调过期丢弃。
- UI 投影和 demand 摘要不反向成为订单、资产或恢复依据。关闭页面只释放订阅和视图资源，不停止后台业务。
- provider-lifecycle 中 PREPARE/WORK/COLLECT/DELIVER/SETTLED 按本轮用户确认解释为按业务适用性覆盖责任；没有产物不强制收集或交付，有产物不能省略原件责任。本批仍保持原有实际阶段。

## 6. 首批验证与验收边界

### 清洁需求与动态步骤的首个完整接入

独立清洁源观察接在现有 PublicWork.advance 的 workerCount 分支之前，沿 FieldSpatial 已有据点 chunk 预算与 Java cleaningScanStains 观察已加载世界。没有 NPC 或优先级0不停止该观察；只保留有界坐标事实、覆盖时效和版本，不创建 Job/Claim，不伪造 forage 或离线目标。有限扫描始终报告 PARTIAL；未加载旧点标记 STALE，不能按零处理；已明确消失的已加载点才删除。活 Job 已认领的同一血迹不重复算待派需求。

执行条件另按现有 eligible/工作矩阵和 ToolDiscovery 实际角色检查分片核对，至少一条已验证候选路径可报告可派发；全体检查未完成时不宣布全局缺货。ToolDiscovery 的失败提供缺失角色、占用、观察不足和预算信息，但不申请托管。派工仍沿原 PublicWork，不以展示快照代替最终认领。无人时明确无执行者，不伪造 NPC 背包物资诊断。

OrderMonitorService 合并只读待派清洁需求和实际 Job 投影，订阅变更仅标脏，页面继续使用现有 PageLifecycle 和 Widgets。FIELD workflow.steps 由当前准备/作业/真实 GROUND、HELD、DELIVERED 与不确定状态派生；无货物不造收集/交付步骤，未执行步骤不因索引在当前步骤之前就画成已完成。Cards 签名包含步骤内容、状态、进度及版本，动态步骤变化即使 phase不变也能刷新。渲染仍只消费缓存，不在绘制内扫描世界或测量新文本。

该接入先覆盖已批准清洁反例，不冒充其他领域 Demand 或完整动态历史已经完成。

### 现行业务只读步骤接入

制作与搬运/配送分别使用领域只读 Projector，烹饪继续在 CookingMonitor 中投影，不修改执行算法。公共 Cards 只消费 workflow.steps 的标量 key/labelKey/status/progress 和版本，不判断业务下一步。没有足够完成证据时保留 PLANNED/ACTIVE/BLOCKED/UNCERTAIN，不能只因 phase 向后推进就把之前步骤画绿。

CRAFT 只以 nativeAttempt 的已确认观察/已产生原件证明本次配方效果，以逐原件 delivered 证明交付，以 released 和现行守卫证明责任结清；BOM 是独立依赖摘要，不转成原版动作队列。HAUL 以 Manifest 各原件状态与 deliveryReceipt 表示领取/交付，不把 WITHDRAWN 当已领取或已交付，改道/等待显示为独立当前条件，不倒退已交付事实。COOKING 从当前 phase、attempt.receipt、heat.closed/aborted、各原件 custody 与 duty 生成适用步骤；炉具监管可以在没有当前 Session 时继续显示未结责任，不把“无人执行”当作关火或清偿。

复用 field-work、field-actions、field-spatial、field-forage、field-tool-supply、field-continuous-batch 的安装版 Kahlua 测试。重点覆盖认领冲突、正常结清、已知停止、UNKNOWN 留责、成员变更清债和世界切换；不新增照抄实现的结构测试。

执行 Lua 结构/类型检查、普通及 Core.debug=true 安装版编译、相关 Markdown 引用检查与 diff whitespace 检查。修改代码时递增模组版本；正式实机包交付前集中构建和完整检查，本次中间拆分不重复全套。

静态、宿主和 PZ 实机证据分别登记。首批通过只证明拆分后的既有接缝回归，不证明原生动作、存档重进、崩溃窗口或性能提升。总体进度维护 BACKLOG，本文件不追加版本流水。
