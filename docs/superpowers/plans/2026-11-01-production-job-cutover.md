# Production 统一 Job 切换准备与实施计划

> 日期：2026-11-01｜源码基线：`7eb736c`｜状态：准备完成，尚未实施；B.5 外部复审未收到，Stage C 仍冻结。

**Goal:** 将真实 Production 手动制作和公共制作统一接入 JobStore/LaborClaims，保留原生效果、取消、活动让位、BOM 连续制作与正常保存恢复。
**Architecture:** JobStore 是唯一持久 Job 权威，LaborClaims 是唯一资源权威，Production/ProductionActions 执行物理动作并提供事实。沿现有业务模块切换，不创建通用 Provider 基类、第二调度器、通用事务协调层或新历史账本。
**Spec:** [Phase 3A v1.5](../specs/2026-10-31-phase3a-job-contract-standardization-design.md)，其中第 0 节的当前范围覆盖旧稿冲突要求；不把开发期掉电/强杀零损失恢复纳入本轮。

## 实施门禁与边界

- B.5 的外部复审和既定验收条件未完成；本文件只准备真实调用迁移，不授权宣布 B.5 关闭或提前修改生产路径。
- 不迁移旧档；但不能删除仍由当前业务调用的 format=3 恢复、claimNative、finishNative、BusinessJobs。
- 切片只做必要定向检查；正式实机前集中跑一次完整回归。实机验收由用户执行，单测/内存复制不替代磁盘保存重进。
- 生产切换验证后才停用对应旧写调用；物理删除旧入口还须全库无调用证明及实机验收。CraftProbe 的独立探针路径不能被顺手删除。
- 以下是按现有契约推导的实施准备；涉及校验接受范围、释放时点、物理效果提交方式的变化必须单独复审，不能混入等价改名。

## 真实闭环与调用迁移表

路径均为基线源码位置，改动后以函数定位为准。

| 环节 | 当前证据 | 切换要求 |
|---|---|---|
| 手动/公共入口 | `CraftingProvider.claim:188` 调 `Production.execute`；`Production.execute:547` 经 Runtime.submit | 保留唯一身体执行入口及成员授权，手动/公共两条入口都切换；Order 需求状态仍由订单系统负责 |
| 创建/认领 | `Production:493-507` 构造 format=3、claimNative、publishCraft | 完整 CRAFT Job 在 createClaimedJob 创建并认领；失败无孤儿 Job/Claim，不使用当前 create 返回的 jobId 冒充 Token |
| 规划/资源变更 | `Production:190-209,273-313,391-425`；`LaborStore.replaceNative:1298` | 从已持久 Job 的副本构建完整提案，计算 Claims 增删，调用 mutateJob；失败前不能先污染原 Job |
| 原生副作用 | `ProductionActions:131-159` 先 COMMITTING，原生制作后枚举 outputs/consumed，再 extendNative | 制作前提交意图并通过当前性守卫；制作后保存真实 ItemID 与消费事实，失败不能丢产物事实或重放制作 |
| 到账/正常释放 | `Production:229-271,338-427` 逐件实际归还后 finishNative | Provider 提供原件到账证据，再以 SETTLING → DONE/CANCELLED 结清 Job；UNKNOWN 不释放，不按已停止身体推断资产已还 |
| 打断 | `Production.stopAdapter:73`、`pause:114` 经 TaskBusinessStop | 保留停止身体与确认效果顺序；STOPPING → SUSPENDED/RECONCILE_REQUIRED 经 Job CAS，原件责任保留 |
| 恢复/续做 | `CraftProbe.prepareRecovery:65`、`Production.afterSave:608`、`LaborStore:566` | 保持 Job ID/claimId，读取当前已支持 Job；sequence 变化须与 Token 代次一致，不能复用 acquireNew 假装恢复 |
| 查询/退役 | `BusinessJobs:22-90,139`、`CraftProbe.status:814`、`Production.findRootOrders:688` | 查询支持新的权威 Job，禁止 flush/refresh 为新 CRAFT 回写第二状态；未切换的其他业务查询继续工作 |

## 已发现的接缝与取舍

### 1. format=4 不是 format=3 改数字

`CraftRecord.valid:9-70` 验证 requester、signature、数量、材料 slot/source、产物类型、BOM 链与 continuation；`CraftJobRecord.valid:64-151` 主要验证 sequence、claims 和资源数组，尚不等同于真实 Production 的完整业务契约。

实施时应保留真实业务所需的校验，而不是让物理执行接受缺字段的最小测试对象。优先复用纯业务字段校验，单独标明 format=4 校验接受范围收紧；不以复制 format=3 的可变持久记录作为过渡权威。相关测试夹具随生产契约适配，不放宽生产守卫。

此外，CraftRecord.resources 直到结清仍持有工具/产物/工位；CraftJobRecord.activeClaims 会按 consumed、delivered、phase 提前排除部分声明。这涉及释放时点，必须绑定原生消费及到账证据，不是等价重构。

### 2. 副本、revision 与执行代次必须一起切换

`Production:157-164,578-585` 依赖 record 表引用相等和 generation。不能改用 detached copy 后继续沿用指针相等，也不能只检查 jobId。

上下文保存当前 Job 副本；自身成功提交后刷新副本和 expectedRevision；旧动作仍须受世界、Job 身份、执行 sequence、body/session 和资源 Token 守卫。revision 是提交版本，sequence 是执行代次，不能每次普通字段提交都把它们机械同步。恢复/续做时，LaborStore 必须核对已持久 Job 后更新认领代次；不得仅修改 sequence 而留下旧 Token。

当前 CookingContext 的副本刷新与停止顺序可作为第二条真实业务的参考（`CookingContext:6-28,34-90`）；它不证明 Production 的产物冲突路径已经解决，不复制 Cooking 的业务规则。

### 3. 不可逆效果后不能走可撤销提案的同一失败解释

`mutateJob:1012-1014` 在 Claims 扩展失败时先返回，没有发布 proposedPayload。直接把 ProductionActions 的 post-effect extendNative 替换成 mutateJob，无法保证新产物事实被记录。

因此区分两类调用：

- 原生副作用前的规划、换资源：冲突时拒绝提案，保持旧事实和旧责任。
- 原生副作用后的观察结果：完整捕获产物 ItemID、消费和异常事实；通过现有唯一 Job/Claims 边界保留责任，碰撞时进入 UNKNOWN/RECONCILE 与已有隔离保护，禁止回滚物理事实或自动重试制作。

这是 Production 必须补齐的业务提交契约，实施前须明确成功、Claim 冲突、CAS 拒绝及异常后仍有实际产物四条结果的持久事实。不得为解决它另建全局事务引擎；也不得无证据宣称现有 mutateJob 已足够。

## 实施任务（待解冻后按顺序进行）

- [ ] **1. 固定真实 CRAFT 业务契约。** 在 CraftJobRecord/CraftRecord 与 ProductionYield 的现有纯契约中明确 format=4 完整字段、sequence、phase/Job state、活动让位和终态责任。把上述接受范围与释放时点变化单独列入 Diff 说明。
- [ ] **2. 切换创建和查询。** Production 经 createClaimedJob 创建，使用 TaskJobs 取得权威 Job 副本；同步 CraftingProvider、CraftProbe 转发/状态与 BusinessJobs 的 CRAFT 查询。保留未切换探针与 Haul 路径，不删除 BusinessJobs 整文件。
- [ ] **3. 切换普通资源变更和恢复。** 替换 Production 的 replaceNative 调用与直接持久写；每次提交刷新上下文。LaborStore 明确同 Job 的恢复认领与新创建的区别；旧回调不能沿用新代次 Token。
- [ ] **4. 切换原生效果与交付。** ProductionActions 在调用真实 native 前持久化 COMMITTING；真实消费、产物及交付结果进入同一权威 Job；按上一节四条结果验证，失败不重放、不丢失新原件责任。
- [ ] **5. 接通停止、结清、活动续做、保存恢复。** 修改 Production 的 stopAdapter/pause/finish/afterSave/tickPending；同步公共订单观察者及 TaskRetirement 对新 Job 的消费，不引入第二业务完成判断。
- [ ] **6. 定向验收与旧写调用核验。** 优先现有 task-production-runtime-test、production-chain-test、production-three-batch-test、activity-craft-yield-test、crafting-provider-test；按实际改动选相关用例，不逐步跑全套。测试必须经过真实 Service/Provider 创建，不把直接构造 Job 当作真实接入证明。

## 可审查的交付条件

1. 手动与公共制作确实调用 createClaimedJob/mutateJob，并验证原生物品变化、取消归还、BOM 多批次和活动让位。
2. 原生效果发生后 Claim 冲突或 CAS 失败，产物事实仍被保存、原件受保护；旧回调不能再次制作或覆写较新事实。
3. 同一当前格式存档保存重进后，身份、责任、工具及产物一致；宿主用例与 PZ 实机分别记录。
4. 全库检查 Production 不再调用 claimNative/replaceNative/extendNative/finishNative/publishCraft/refresh 作为持久写入口；其他仍在用的旧入口不提前删除。
5. Stage C/3B 的必要结清和退役规则由真实两链逐步核对；不把通用资源框架、自动迁移或任意崩溃零损失加入本轮门槛。

## 本轮准备结果

完成源码调用链核查与计划自审；未改生产源码、未执行测试套件，未解冻 Stage C。尚无 B.5 外部复审结论和 PZ 实机证据。本文的接口接缝是后续实施必须处理的现有差异，不是新增 B.5 安全框架任务。
