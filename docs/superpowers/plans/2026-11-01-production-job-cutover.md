# Production 统一 Job 切换准备与实施计划

> 日期：2026-11-01｜源码基线：`7eb736c`｜状态：已按用户后续授权实施 Production/Haul 切换；集中开发验收进行中，B.5 与实机未宣布通过。

**Goal:** 将真实 Production 手动制作和公共制作统一接入 JobStore/LaborClaims，保留原生效果、取消、活动让位、BOM 连续制作与正常保存恢复。
**Architecture:** JobStore 是唯一持久 Job 权威，LaborClaims 是唯一资源权威，Production/ProductionActions 执行物理动作并提供事实。沿现有业务模块切换，不创建通用 Provider 基类、第二调度器、通用事务协调层或新历史账本。
**Spec:** [Phase 3A v1.5](../specs/2026-10-31-phase3a-job-contract-standardization-design.md)，其中第 0 节的当前范围覆盖旧稿冲突要求；不把开发期掉电/强杀零损失恢复纳入本轮。

## 实施门禁与边界

- 用户后续明确“生产未切换实机验证什么？先做完吧”：先完成 Production、Haul 及必要结清，再集中实机验收。此决定覆盖原 Stage C 实施冻结；不等于 B.5 已通过。
- 不迁移旧档；但不能删除仍由当前业务调用的 format=3 恢复、claimNative、finishNative、BusinessJobs。
- 切片只做必要定向检查；正式实机前集中跑一次完整回归。Codex 主导准备和进度；按此前明确选择，本地用户负责实际操作游戏，外部 AI 负责独立审查、验收设计和结果判定。外部聊天当前没有本机游戏控制能力；实际操作者变更须明确记录。单测/内存复制不替代磁盘保存重进。
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

## 原生效果提交契约草案（Stage C 实施前审查门禁，未实现）

以下明确上述第 3 个接缝的目标协议，不能据此宣称当前代码已支持。普通可撤销提案仍使用 mutateJob；不可逆效果的观察结果必须由 CRAFT 业务入口专门核对，不能让前端任意提交 ItemID。该入口仍写 JobStore 与现有 Quarantine，不建第二份 Job 或通用事务系统。

### A. 调用 native 前必须已经留有责任

在 `job.payload.nativeAttempt` 内保留一份当前尝试，包含 format、稳定 attemptId、执行 sequence、recipeId/signature、输入和保留工具的 ItemID 以及状态。attemptId 在原生调用前产生并随 Job CAS 提交，不是 claimId；不得修改 job.id 或拼接身份后缀。数量和字符串使用 CRAFT 已有上限，不增加无界历史。

只有保存 `nativeAttempt.state=COMMITTING`、业务 phase=COMMITTING、effects=UNKNOWN 成功，并重新核对世界、Job、attemptId、sequence、body/session、Token 与输入实物后，才允许调用一次原生制作。CAS 被拒绝就不调用 native。COMMITTING 是效果可能发生的责任，不代表已经完成，更不能在读档后自动再做一次。

未完成的 nativeAttempt 禁止进入 DONE/CANCELLED、清空相关 obligations 或正常退役；停止/取消保留它并进入停止/核对路径。具体字段由 CraftJobRecord 校验，不能以任意额外顶层字段绕过 Validator。

### B. native 返回后的事实结构

无论 native 正常返回还是抛错，都尝试观察真实产物、消费和工具，形成一份有界的事实回执：attemptId、输出 ItemID/fullType 列表、实际消费的输入 ID、保留工具验证结果、native 是否正常返回、观察是否完整、有限长度的异常原因。不存 item/userdata、Token、函数或异常对象。产物计数只在成功确认此尝试时增加一次。

同 attemptId 的相同回执幂等；不同回执不能覆盖前一回执或被当作重试成功。保留冲突事实并进入核对，且为每个已观察到的原件登记保护；不能只凭 attemptId 相同就丢弃新观察到的 ItemID。旧尝试结清前不能覆盖为下一次尝试。

### C. 四条结果的持久责任

| 结果 | Job 与现有隔离记录必须保留的事实 | 后续执行 |
|---|---|---|
| 正常观察、Claim 扩展和 CAS 成功 | nativeAttempt 回执、实际产物/消费、对应 claims 同步写入；确认完成后才增加 produced 并推进 CONFIRMED | 刷新上下文；按真实交付继续，不重复 native |
| native 已发生，Claim 扩展冲突 | 不能把 `EXTEND_FAILED` 当作效果回滚。对所有已知产物用现有 quarantineResource 保留来源 Job/claimId/attemptId/sequence 和有界回执；Job 保留 COMMITTING 或转 RECONCILE_REQUIRED/UNKNOWN | 不选择资源赢家，不释放旧责任，不自动制作 |
| native 已发生，原 revision 的 CAS 被拒绝 | 不覆盖新 Job。先在现有隔离记录保留已观察产物及来源事实；若最新 Job 仍是同世界/身份/attemptId/sequence 的未结清尝试，允许一次仅合并此回执、保留并发停止/取消事实的 CAS；再次拒绝即停止重试，隔离记录继续持责 | 不拿最新 revision 盲目重放旧提案；不同尝试/已终态不得由旧回调覆写 |
| native 抛错或观察不完整 | 保留 COMMITTING、已知物品 ID 与不完整标记，effects=UNKNOWN；不得推定没有产物或已全部消费 | 不正常释放，不自动重做；未知产物范围按下述限制处理 |

隔离证据以 `来源 Job + attemptId + resourceKey` 关联。相同事实重报不得反复追加事件直到撞上 64 条上限；不同事实不能通过去重被吞掉。该幂等性属于 CRAFT 结果提交调用边界，不修改既有 Quarantine 所有权规则，也不把 RETAIN 误当成原件 Token 转交机制（它当前处理的是隔离容量）。

CAS 成功后的观察者可能触发停止；上下文应重新读取当前权威状态，不以刚提交的旧副本覆盖后续事实。旧世界回调不能向新世界写同名 ItemID；原生调用前的世界/执行守卫及正常保存屏障必须保持，本文不承诺任意世界切换中途或强杀的零损失。

### D. 读档判定与已知未具备能力

- 完整、已确认的回执：重建责任并继续交付；不调用同一次 native。
- COMMITTING/UNKNOWN、仅有隔离回执或回执冲突：保持核对状态，恢复系统隔离，禁止自动重放；正常解除仍须完整证据与实物核对。
- 缺记录、动作已停止、输入不见了或超时均不能证明制作成功或责任结清。
- 本轮源码检索没有找到已落地的 Scope Quarantine Fence 模块/统一作用域准入链；不能引用旧规格第 8 节就宣称未知 ItemID 已全部保护。如果观察失败到无法确定产物集合，现有按 key 隔离不能证明作用域内所有未知产物安全。本轮在 JobStore 中建立由未决 nativeAttempt 派生的 scope 索引，创建及执行 Token 守卫拒绝同作用域其他 Job；自身返还仍须业务证据，禁止重放。索引随提交更新、冷启动重建，不另建持久账本。门禁只约束本模组接入路径，不约束玩家或其他模组直接操作。

前置契约复审必须核对：调用前 CAS 拒绝不执行、同尝试回执幂等、Claim 冲突保存产物事实、CAS 拒绝不覆写新事实、取消与回执竞争、读档不重放，以及观察不完整的明确阻断路径。上述契约已随本轮业务切换实施，接受独立审查；不追加 B.5 通用框架。

## 实施任务（用户已授权真实业务切换）

- [x] **1. 固定真实 CRAFT 业务契约。** 在 CraftJobRecord/CraftRecord 与 ProductionYield 的现有纯契约中明确 format=4 完整字段、sequence、phase/Job state、活动让位和终态责任。把上述接受范围与释放时点变化单独列入 Diff 说明。
- [x] **2. 切换创建和查询。** Production 经 createClaimedJob 创建，使用 TaskJobs 取得权威 Job 副本；同步 CraftingProvider、CraftProbe 转发/状态与 BusinessJobs 的 CRAFT 查询。保留未切换探针与 Haul 路径，不删除 BusinessJobs 整文件。
- [x] **3. 切换普通资源变更和恢复。** 替换 Production 的 replaceNative 调用与直接持久写；每次提交刷新上下文。LaborStore 明确同 Job 的恢复认领与新创建的区别；旧回调不能沿用新代次 Token。
- [x] **4. 切换原生效果与交付。** ProductionActions 在调用真实 native 前持久化 COMMITTING；真实消费、产物及交付结果进入同一权威 Job；按上一节四条结果验证，失败不重放、不丢失新原件责任。
- [x] **5. 接通停止、结清、活动续做、保存恢复。** 修改 Production 的 stopAdapter/pause/finish/afterSave/tickPending；同步公共订单观察者及 TaskRetirement 对新 Job 的消费，不引入第二业务完成判断。
- [x] **6. 定向验收与旧写调用核验。** 优先现有 task-production-runtime-test、production-chain-test、production-three-batch-test、activity-craft-yield-test、crafting-provider-test；按实际改动选相关用例，不逐步跑全套。测试必须经过真实 Service/Provider 创建，不把直接构造 Job 当作真实接入证明。

## 可审查的交付条件

1. 手动与公共制作确实调用 createClaimedJob/mutateJob，并验证原生物品变化、取消归还、BOM 多批次和活动让位。
2. 原生效果发生后 Claim 冲突或 CAS 失败，产物事实仍被保存、原件受保护；旧回调不能再次制作或覆写较新事实。
3. 同一当前格式存档保存重进后，身份、责任、工具及产物一致；宿主用例与 PZ 实机分别记录。
4. 全库检查 Production 不再调用 claimNative/replaceNative/extendNative/finishNative/publishCraft/refresh 作为持久写入口；其他仍在用的旧入口不提前删除。
5. Stage C/3B 的必要结清和退役规则由真实两链逐步核对；不把通用资源框架、自动迁移或任意崩溃零损失加入本轮门槛。

## 本轮实施结果

ProductionJobs/HaulJobs 保存脱离式执行草稿，经 createClaimedJob/mutateJob 写入唯一 JobStore。真实 Production 与自主物流/配送已切换，公共订单和必要结清/退役仍由原业务证据驱动。旧探针入口仍有调用，保留至实机后再按无调用证据退役。测试与边界见[本轮证据](../../reviews/2026-11-01/production-haul-cutover.md)。
