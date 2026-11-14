# Claims 与领域契约收敛实施计划

Goal：完成用户批准的失败测试收口、claims 单实现及 JobStore 领域校验下沉。沿用 DEC-003 与当前 v2 世界格式，不增加兼容、玩法或联机能力。

Architecture：Lua LaborClaims 只适配调用/只读查询，Java ClaimsKernel 执行认领、容量、隔离和重建操作；Java 提交继续裁决发布与回滚。各领域 shared 义务契约提供记录一致性、结清和退休证明，JobStore 在所有原入口强制执行通用守卫与契约。

Tech Stack：安装版 Kahlua、Java 17、Lua。

依据：DECISIONS.md DEC-003，2026-11-13-architecture-convergence.md；用户在本轮明确授权前三项。

## 边界与代码证据

- 创建/认领：LaborDomainAdapters.claimCooking（原第7行）、LaborClaims.acquire/acquireNew 与 LaborCommitKernel.create。
- 正常释放：LaborDomainAdapters.finishCooking（原第73行）、ClaimsKernel.release/shrink；结清仍需 Job 和义务回执。
- 异常/恢复：LaborStore.data（原第44行）隔离/冷重建、LaborCommitKernel.Tx.restore、CommitFence；不改变 UNKNOWN 留责。
- JobStore.obligationGuard（原第20行）与 update 义务操作检查（原第410行）按领域迁出；通用终态、npc、claim、Job 归属检查顺序保留。

## 实施

- [x] 定位默认测试失败，按当前正式调用与完整替身契约修复，不放宽生产守卫。
- [x] Java 补齐 Lua 独有 claims 操作，薄 Lua 适配；单一桥面入口按固定操作派发，缺桥明确拒绝，无 Lua 写 fallback。保留严格提交扩展与幂等增补的不同前置条件。
- [x] 五个领域提供义务检查回调，JobContracts 校验回调形状；JobStore 在原守卫位置调用，领域错误码与 scope 阻断原因归契约。
- [x] 定向覆盖令牌轮换、容量、隔离、冷恢复、拒绝无写、结清与退休；一次最终构建与相关回归。
- [x] 更新 BACKLOG、导航和证据，分别记录自动检查与未实机/磁盘/性能验证。

## 审查重点

旧 token 不得释放新 owner；隔离容量不得因重载重复计算或消失；Java 缺失不得回退 Lua；未知效果不得结清；领域钩子不得绕过通用守卫。跨记录复制与磁盘事务不在本轮优化范围。

不切分支、不提交、不推送。保留当前所有既有脏改动。按用户既有授权直接实施，不重复审批内部步骤。

## 完成记录

0.29.62 BUILD_OK；最终 classes 上 31 组相关检查全部通过，Python 上下文门禁 42 项通过。两项旧失败及 boot 暂停夹具已收口，物流测试另暴露并修复停止服务后无法恢复的生产缺陷。详细语义区分、当前边界与未验证项见[本轮证据](../../reviews/2026-11-14/claims-contract-convergence.md)。main 未提交工作区，未推送；游戏实机、真实磁盘恢复与性能未验证。
