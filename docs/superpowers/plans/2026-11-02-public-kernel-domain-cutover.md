# 公共内核与领域边界收敛实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将领域校验、转换和恢复策略移出公共内核，减少重复状态与复制，优先使用适合批处理的 Java 实现。

**Architecture:** 沿用唯一 TaskRuntime/TaskController、JobStore 与 LaborClaims。公共层负责调度、身体会话、通用资源协调和记录提交；领域负责步骤、效果解释和恢复。注册仅连接现有职责，不增加通用工作流执行器。

**Tech Stack:** PZ B42.21.0 安装版 Kahlua、Lua、Java 17、ZombieBuddy；现有构建与测试入口。

**Spec:** 用户本轮明确批准的四项边界；[NPC 唯一架构](../specs/2026-10-22-npc-behavior-architecture-design.md)、[领域边界](../specs/2026-11-02-workflow-domain-boundaries-design.md)。本计划不建立新的产品需求。

## Global Constraints

- 基线 phase-3a-consolidation@eb65db6；开始时工作区干净。
- 保持现行持久格式、校验接受范围、失败原因、守卫顺序、UNKNOWN 范围、资源释放条件与正常保存恢复；任何必要语义变化另行说明，不混入等价重构。
- 当前单人、多 NPC；未来 MP 仅保留边界，不实现服务端鉴权或网络框架。
- 不修改参考项目，不新增工种，不推行统一 PREPARE/WORK/COLLECT/DELIVER 流水线。
- 不将全部 Lua 机械改写为 Java。已安装引擎的批量读取、索引与序列化计算优先 Java；领域流程保留 Lua 注册扩展。
- 运行上下文不得成为第二持久权威；只保留句柄、路径、临时缓存和明确版本的提交草稿。
- 中间批次定向检查；候选实机包前集中一次完整回归与 preflight。实机和规模性能未跑即标未验证。

## Review Focus

- 注册加载顺序和循环 require 不得让存档准入漏掉校验；未知 provider 的现有接受行为不得静默改变。
- 原动作发生后提交失败不得重复执行，旧回调不得释放新会话资源。
- 中断或读档保留携货、工具和炉具责任；业务迁出不改变释放证据。
- Java 与 Lua 复制对中文长度、数字键、循环表、共享子表和非法值的接受范围必须相同。
- 新领域接入不能要求修改 JobStore/LaborStore 的业务类型分支；扩展点缺失要报告，不能退回核心特判。

## 已核对的入口与闭环

路径以下均相对仓库根目录。

- `Contents/mods/EmberRoutesProbe/42/media/lua/shared/EmberRoutesProbe/JobStore.lua:39`：Job envelope 与领域校验；186：更新和复制；211：烹饪交接专用入口。
- `Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/LaborStore.lua:50`：恢复；899：创建认领；950：提交；1026：HAUL 容量专用分支。
- 认领：`HaulJobs.lua:81` 创建 Job 并声明资源。
- 交付：`HaulAgent.lua:50` 核对实际原件位置，56 提交交付凭据；`HaulJobs.lua:140` 检查无未结责任后完成。
- 打断：`HaulAgent.lua:112` 使用 TaskBusinessStop；`HaulJobs.lua:145` 加载恢复。
- 对照业务：`FieldContext.lua:11` 提交、`FieldSession.lua` 停止与结算；`ProductionJobs.lua` 已有独立草稿适配。
- 现有 Java 参考：`InventoryReads.java` 批量读取、`WarehouseFastIndex.java` 索引、`ProbeRuntime.java:78` Lua 桥。已有实现是结构参考，性能需另测。

## 执行状态

用户已批准开始；0.29.21 实施证据见[专题](../../reviews/2026-11-02/public-kernel-domain-cutover.md)。Task 1～4 已接并完成定向验证；Task 5 构建/候选包已完成，完整 LuaLS/preflight 与实机未完成。用户后续明确只做必要检查、不再扩展模拟真实场景测试，覆盖下文例行全套要求。原有门面按仍有真实调用保留，未宣称全兼容路径退役。

## Task 1：领域记录契约注册，移出 JobStore 的类型判断

**Files:**
- Create: `Contents/mods/EmberRoutesProbe/42/media/lua/shared/EmberRoutesProbe/JobContracts.lua`
- Create: 同目录 `BuiltinJobContracts.lua`（唯一内置业务装配入口）
- Modify: 同目录 `JobStore.lua`
- Test: `tests/lua/job-store-test.lua`、`phase3a-validator-test.lua`、`cooking-handoff-test.lua`

**Interfaces:**
- `JobContracts.register(providerType, contract)`：登记领域函数，不保存世界状态；重复注册明确拒绝，内置装配幂等。
- contract 提供 `validate(job)`、`transition(old,next)`、`blocksScope(job)`、`transferValid(old,next)` 及 `persistentPersonal` 分类；领域校验错误原因保留原值。
- `BuiltinJobContracts.install()`：在 Store.check/open/validate 使用契约前完成装配；加载 Record 时采用惰性 require，避免模块初始化环。
- 无登记业务保留现有 envelope-only 行为，不能将“严格注册”夹带为存档接受范围变化。

- [x] 记录现有 CRAFT/HAUL/COOKING/FIELD/ACTIVITY/SELF_CARE 路径与格式分支，保留其先后顺序。
- [x] 将现有业务选择代码原样移到装配模块，JobStore 只调用契约；现有 transferCooking 先作为兼容门面委托通用受控交接，不提前删除调用方。
- [x] 以现有测试验证创建、状态转换、scopeBlocked、交接、删除和加载；补一个注册领域的集成用例，证明无需修改核心即可校验和转换。
- [x] 拒绝范围与失败原因对比通过后，移除核心内业务类型字符串判断；个人索引按契约分类维持现有限额与行为。

## Task 2：资源提交与领域适配分离

**Files:**
- Modify: `Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/LaborStore.lua`
- Create: 同目录 `LaborJobCommit.lua`（通用认领/提交算法）
- Create: 同目录 `LaborDomainAdapters.lua`（现有领域适配装配）
- Modify: 同目录 `HaulJobs.lua`、`ProductionJobs.lua`、`FieldContext.lua` 及实际 Cooking/Activity/SelfCare 调用方
- Test: `phase3a-stage-b-test.lua`、`hauling-provider-test.lua`、`haul-routing-test.lua`、`field-work-test.lua`、`tool-return-test.lua`

**Interfaces:**
- `LaborJobCommit.create(context,job)` / `mutate(context,jobId,expectedRevision,payload,mutation)`；context 注入现有唯一 claims、JobStore、token 索引和隔离操作，不自行加载领域服务或建立账本。
- capacity 命令仍使用现有 `{key,items,free}`、`{releaseItemId}`、false；其是否允许由领域契约决定，公共层只处理通用容量与提交次序。
- 各领域适配保留现有公开 API 与返回值，迁移后门面只转发。迁完真实调用、恢复与测试后才退役兼容代码。

- [x] 先迁出算法，按当前顺序保留 claim/容量预检、extend、reserve、CAS、shrink、终态释放及失败隔离。
- [x] 迁出各业务记录选择和专用适配；token 只在同一所有者处管理，不让适配器保存第二份权威映射。
- [x] 对照搬运与制作两条真实链验证认领冲突、交付、取消、旧回调和提交失败；再覆盖 FIELD/烹饪/生活调用适配。
- [x] 对持有物与效果不明路径运行定向回归，保持实际责任不因结构迁移释放。

## Task 3：恢复归领域，运行状态与持久事实收敛

**Files:**
- Modify: `LaborStore.lua`、`HaulJobs.lua`、`ProductionJobs.lua`、`FieldWork.lua` 及现有 Cooking/SelfCare/Activity 恢复模块
- Create: `Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/LaborRecovery.lua`（仅公共恢复次序与冲突仲裁）
- Test: `phase3a-stage-b-test.lua`、`haul-routing-test.lua`、`field-continuous-batch-test.lua`、`cooking-handoff-test.lua`、`tool-return-test.lua`

**Interfaces:**
- 领域 `recover(job,context)` 返回原有恢复决定与声明描述；公共恢复负责全局冲突先扫描、后重建，不能逐领域先到先得。
- 恢复 context 只提供当前唯一 root、claims 与受控提交函数，不授权领域直接释放其他任务声明。
- 保留原 envelope state 与领域 phase 的职责区别；删除的只能是可派生镜像，不以改名掩盖双状态。HAUL 当前 payload.state 暂不删字段，先由一个领域函数统一维护兼容表示。

- [x] 逐段迁出 Store.data 的领域恢复解释，保留 claimId 冲突预扫描和 UNKNOWN 隔离顺序。
- [x] 为每个迁出的领域核对创建、物理清偿、暂停、死亡与读档五条实际调用；记录仍有适配职责的旧入口，禁止仅按文件名删除。
- [x] 将 HaulJobs 多次转换提交收敛到领域合法转换计划；减少重复复制，但保留公共转换序列及每个可观察通知，通知变化须单独说明。
- [x] FIELD 继续持工具续批，COOKING 保留无会话炉具义务，HAUL 保留携货等待/改道；相关用例通过后再退役旧实现。

## Task 4：Java 计算路径与复制成本收敛

**Files:**
- Create: `java/src/main/java/emberroutes/probe/JobData.java`
- Modify: `java/src/main/java/emberroutes/probe/ProbeRuntime.java`
- Modify: `JobStore.lua` 及必要的 ProductionJobs/HaulJobs 提交调用
- Test: `tests/java/emberroutes/probe/JobDataTest.java`、`tests/java/KahluaLaborTest.java`、`tests/lua/job-store-test.lua`
- Modify: `tools/build-probe.ps1`（纳入实际 Kahlua Java 用例）

**Interfaces:**
- `JobData.copy(KahluaTable source)`：与现有 detached 的序列化接受范围等价；使用安装 JAR 的 KahluaTableIterator 与 J2SEPlatform 建表，不持有跨调用业务记录。
- `ProbeRuntime.jobDataCopy(KahluaTable source)`：一次跨语言调用完成有界复制；无引擎实体扫描和回调。
- 8192 节点、16 层、16384 Lua 字符串长度及键约束均保持现有语义；在安装 Kahlua 中确认中文字符串长度规则后编码，不能直接假设 Java UTF-16 或 UTF-8。

- [x] 先 javap 核对安装 JAR 的表迭代/键值类型；以现有 Java 表处理为参考，不猜 API。
- [x] 在相同安装 VM 对比 Lua/Java 的正常与拒绝样本，包括共享子表、环、非有限数值、中文和边界深度；不提供 Java 缺失时静默放宽的路径。
- [x] JobStore.update 用浅层候选构造加一次有界最终复制，避免先深拷贝旧 payload 再替换；领域校验保持只读。
- [x] 对真实大小的 Job payload 测量复制次数、分配趋势与耗时；保留原 Java 批量扫描路径，只有新增热点证据时才扩展扫描下沉。
- [x] 如 Java 路径未达到兼容和成本目标，报告具体结果并保留等价 Lua 实现，不宣传性能提升。

## Task 5：完整候选交付

**Files:** 版本三处、`docs/BACKLOG.md` 对应执行表、`docs/INDEX.md` 对应导航、本计划及专题证据。

- [ ] 汇总定向回归，确认无未处理的新失败；集中运行完整回归/preflight、Lua 普通与 Debug 编译、Java 构建、LuaLS、lint 与 CN/EN 一致性检查。
- [x] 递增版本并生成候选包，核对包与工作区；不上传工坊。
- [x] 报告已移出的业务分支、仍保留的真实适配入口、实际测试结果和未验证项。
- [ ] 实机集中验证搬运→自理→续工、FIELD 工具续批、烹饪监管、取消及正常保存重进；性能报告使用同场景基线，不以宿主测试代替实机数据。
