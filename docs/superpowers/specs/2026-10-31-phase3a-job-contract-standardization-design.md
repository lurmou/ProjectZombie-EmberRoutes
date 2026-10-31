# 阶段 3A 设计规格书：工单契约标准化与 BusinessJobs 去特权化 (v1.4 最终基准版)
# (Phase 3A: Job Contract Standardization & BusinessJobs Deprivileging)

> 日期：2026-10-31｜版本：v1.4 (最终基准冻结稿)｜状态：FINAL SPECIFICATION FOR BASELINE FREEZE｜基线：HEAD `d43404dc`｜适用：EmberRoutes 阶段 3 基础设施收敛

---

## 目录
1. [基线事实与核心版本概念澄清 (P0-1)](#1-基线事实与核心版本概念澄清-p0-1)
2. [标准 Job Schema 与不可逾越状态机 (P0-1)](#2-标准-job-schema-与不可逾越状态机-p0-1)
3. [统一 Job 创建与 Claim 变动协议 (P0-2)](#3-统一-job-创建与-claim-变动协议-p0-2)
4. [CRAFT 与 HAUL 状态感知资源映射 (P0-3)](#4-craft-与-haul-状态感知资源映射-p0-3)
5. [Quarantine 全局不可伪造所有权与冷启动恢复 (P0-4)](#5-quarantine-全局不可伪造所有权与冷启动恢复-p0-4)
6. [全量旧账本迁移与局部整表暂存替换 (P0-5)](#6-全量旧账本迁移与局部整表暂存替换-p0-5)
7. [BusinessJobs 全面去特权化与全库调用点重构 (P0-6)](#7-businessjobs-全面去特权化与全库调用点重构-p0-6)
8. [物理操作、Job CAS 与 Runtime Claims 的三层故障恢复模型](#8-物理操作-job-cas-与-runtime-claims-的三层故障恢复模型)
9. [单 NPC 单活动运行时与任务恢复仲裁](#9-单-npc-单活动运行时与任务恢复仲裁)
10. [冷启动绝对顺序与硬门禁屏障](#10-冷启动绝对顺序与硬门禁屏障)
11. [全生命周期压力测试矩阵 (T01~T03, T17~T33)](#11-全生命周期压力测试矩阵-t01t03-t17t33)

---

## 1. 基线事实与核心版本概念澄清 (P0-1)

经过第二轮终审核验，当前系统存在四个不同维度的版本与代次概念，在 v1.4 中确立严格正交的单一职责：

| 字段名称 | 归属层级 | 唯一核心职责 | 变动规则 |
|---|---|---|---|
| **`root.jobContractVersion`** | 全局 ModData 根表 | 标记整模组工单基础设施契约版本 | 仅由数据迁移屏障一次性写入（=2），未达标阻断打开 |
| **`taskJobs.format`** | JobStore 存储容器 | 标记 `root.taskJobs` 字典自身的容器格式 | 固定为 1（由 `JobStore.open` 严格校验） |
| **`job.revision`** | Job 公共包络 | CAS 乐观并发控制锁版本 | 每次调用 `JobStore:update` 时自增 1 |
| **`job.businessGeneration`** | Job 公共包络 / 载荷 | 执行代次与回调隔离防护标记 | 角色分配、物理打断或重进恢复时递增，隔离过期回调 |
| **`payload.format`** | 工种专有私有载荷 | 标记各 Provider 业务 Schema 演进版本 | CRAFT=4, HAUL=3, FIELD_WORK=1, COOKING=1 |
| **`payload.sequence`** | 工种专有私有载荷 | 载荷内部状态跃迁与认领时序 | 每次资源变更或业务 phase 推进时递增 |

---

## 2. 标准 Job Schema 与不可逾越状态机 (P0-1)

严格对齐 [JobStore.lua](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/shared/EmberRoutesProbe/JobStore.lua) 的物理约束，补齐专有校验与终态约束：

### 2.1 公共包络规范 (Standard Job Envelope)
```lua
-- root.taskJobs.byId[jobId] 标准包络
{
    id = "uuid",                     -- [必需, string, 长度<=256] 稳定主键
    npcId = "uuid",                  -- [必需, string, 长度<=256] 执行人角色 ID (严格要求 string，杜绝 number)
    providerType = "STRING",         -- [必需, string] 'FIELD_WORK'|'CRAFT'|'HAUL'|'COOKING'|'SELF_CARE'|'ACTIVITY'
    scopeId = "settlement-uuid",     -- [必需, string] 据点 ID 或 'local-world'
    orderId = "order-uuid" | nil,    -- [可选, string] 上层订单关联 ID
    revision = 1,                    -- [必需, integer, >=1] CAS 乐观锁版本号
    state = "PREPARING",             -- [必需] PREPARING | RUNNING | STOPPING | SUSPENDED | SETTLING | DONE | CANCELLED | RECONCILE_REQUIRED
    effects = "KNOWN",               -- [必需] 'KNOWN' | 'UNKNOWN'
    obligations = {},                -- [必需, table] 跨工单持久责任字典，终态必须为空
    businessGeneration = 0,          -- [必需, integer, >=0] 执行代次标记 (保留用于回调隔离)
    payload = {                      -- [必需, table] 业务私有载荷
        format = 1,                  -- 载荷格式版本
        sequence = 0,                -- 载荷内部时序计数器
        claims = {},                 -- [权威排他原件键列表] 如 {"item:1001", "craft-surface:bench_1"}
        target = {},                 -- 空间或实体目标
        ...
    }
}
```

### 2.2 不可逾越的状态机流转表
消除 v1.3 中的状态跃迁矛盾，严格执行：
```
PREPARING   --> RUNNING | SUSPENDED | SETTLING | RECONCILE_REQUIRED
RUNNING     --> STOPPING | RECONCILE_REQUIRED  (注: 严禁从 RUNNING 直接跳入 SETTLING 或 SUSPENDED)
STOPPING    --> SUSPENDED | SETTLING | RECONCILE_REQUIRED
SUSPENDED   --> PREPARING | SETTLING | RECONCILE_REQUIRED
SETTLING    --> DONE | CANCELLED | SUSPENDED | RECONCILE_REQUIRED
RECONCILE_REQUIRED --> SUSPENDED | SETTLING
DONE / CANCELLED   --> (终态无出边)
```

### 2.3 JobStore.valid() 终态硬性约束与 Validator 挂接
在 [JobStore.lua:valid(job)](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/shared/EmberRoutesProbe/JobStore.lua#L34) 中增加终态无资源占用不变量与工种验证器：
1. **终态无责任不变量**：
   ```lua
   if terminal[job.state] then
       if job.effects ~= 'KNOWN' or not empty(job.obligations) or #(job.payload.claims or {}) > 0 then
           return false -- 终态必须清空 claims，严禁残留物理原件责任
       end
   end
   ```
2. **挂接 CRAFT 与 HAUL 专有 Validator**：
   ```lua
   and (job.providerType ~= 'CRAFT' or require('EmberRoutesProbe/CraftRecord').valid(job))
   and (job.providerType ~= 'HAUL' or require('EmberRoutesProbe/HaulManifest').validJob(job))
   ```

---

## 3. 统一 Job 创建与 Claim 变动协议 (P0-2)

彻底解决“Job 写入与 Runtime Claim 割裂”以及“仅支持 shrink 无法覆盖全生命周期”的重大缺陷，建立覆盖全工种的统一事务入口：

### 3.1 统一创建原子事务：`LaborStore.createClaimedJob(job)`
任何 Provider（CRAFT、HAUL、FIELD_WORK 等）创建需要占用资源的新工单时，**严禁直接调用 `JobStore:create`**，必须经由原子事务：

```mermaid
sequenceDiagram
    participant P as Provider / Planner
    participant LS as LaborStore (Authority)
    participant LC as LaborClaims (Memory)
    participant TJ as JobStore (ModData)

    P->>LS: createClaimedJob(jobSpec)
    activate LS
    Note over LS: 1. 静态数据合规性校验
    LS->>LS: assert(valid(jobSpec) and jobSpec.state == 'PREPARING')
    
    Note over LS: 2. 运行时独占探测 (All-or-Nothing)
    LS->>LC: acquire(jobSpec.id, jobSpec.businessGeneration, jobSpec.payload.claims)
    alt Claims 探测冲突 (某原件已被占或隔离)
        LC-->>LS: nil, reason
        LS-->>P: false, "CLAIM_CONFLICT:" .. reason
    else Claims 认领成功
        LC-->>LS: token
        
        Note over LS: 3. 写入持久化存储
        LS->>TJ: create(jobSpec)
        alt 持久化写入成功
            TJ-->>LS: true
            LS-->>P: true, jobSpec.id
        else 持久化写入失败 (如超过 512 限制/序列化失败)
            TJ-->>LS: false, why
            Note over LS: 4. 补偿回滚: 释放全部 Claims 与容量
            LS->>LC: release(token)
            LS-->>P: false, "PERSISTENCE_FAILED_ROLLED_BACK:" .. why
        end
    end
    deactivate LS
```

### 3.2 统一状态与资源变动事务：`LaborStore.mutateJobClaims`
统一处理资源增加、释放、替换及容量变更，确保业务字段（`manifest`, `outputs`, `reservation`）与 `claims` 在同一次 CAS 中原子落盘：

```lua
-- LaborStore.lua 统一资源变动核心
function Store.mutateJobClaims(jobId, expectedRevision, proposedPayload, mutationKind, mutationKeys)
    -- mutationKind: 'ADD' | 'REMOVE' | 'REPLACE'
    local store = TaskJobs.current()
    local job = store:get(jobId)
    if not job or job.revision ~= expectedRevision then return false, 'STALE_REVISION' end
    local token = claimsTokens[jobId]
    
    if mutationKind == 'ADD' then
        -- 先保护，后持久化
        local ok, why = Claims:extend(token, mutationKeys)
        if not ok then return false, 'EXTEND_LOCK_FAILED:' .. tostring(why) end
        local okCAS, nextRev = store:update(jobId, expectedRevision, { payload = proposedPayload })
        if not okCAS then
            -- CAS 失败保持 Token 保护，转入安全暂停核查，绝不遗漏新产物
            job.state = 'SUSPENDED' job.effects = 'UNKNOWN'
            store:update(jobId, expectedRevision, { state = 'SUSPENDED', effects = 'UNKNOWN' })
            return false, 'CAS_FAILED_RETAINED_LOCK'
        end
        return true, nextRev
        
    elseif mutationKind == 'REMOVE' then
        -- 先持久化，后释放
        local okCAS, nextRev = store:update(jobId, expectedRevision, { payload = proposedPayload })
        if not okCAS then return false, 'PERSISTENCE_FAILED_TOKEN_RETAINED' end
        -- 持久化成功后缩减内存 Token
        Claims:shrink(token, mutationKeys)
        return true, nextRev
        
    elseif mutationKind == 'REPLACE' then
        -- 先取并集，写持久化，再收缩旧差集
        local addKeys, dropKeys = diffSets(token.resources, mutationKeys)
        local ok, why = Claims:extend(token, addKeys)
        if not ok then return false, 'REPLACE_EXTEND_FAILED:' .. tostring(why) end
        local okCAS, nextRev = store:update(jobId, expectedRevision, { payload = proposedPayload })
        if not okCAS then return false, 'REPLACE_CAS_FAILED' end
        Claims:shrink(token, dropKeys)
        return true, nextRev
    end
end
```

### 3.3 全 Provider 现有路径收敛矩阵
彻底改造 [LaborStore.lua](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/LaborStore.lua) 中全部 11 处分散的变更逻辑：
- `claimNative` / `extendNative` / `replaceNative` / `finishNative` $\rightarrow$ 统一委托 `createClaimedJob` 与 `mutateJobClaims`；
- `claim` / `upgradeHaul` / `settleHaulLines` $\rightarrow$ 统一委托 `mutateJobClaims`；
- `replaceCooking` / `replaceField` $\rightarrow$ 统一委托 `mutateJobClaims`；
- `releasePersonalSeats` / `finishPersonal` / `finishActivity` $\rightarrow$ 严格执行“先 CAS 更新 `job.payload.claims`，后 `Claims:shrink/release`”。

---

## 4. CRAFT 与 HAUL 状态感知资源映射 (P0-3)

针对已释放工单依然计算出工作台等资源的历史缺陷，废除粗暴的 `resources()` 强等式，确立**状态感知的资源映射权威**：

### 4.1 CRAFT 状态感知提取器：`CraftRecord.activeClaims(r)`
```lua
function CraftRecord.activeClaims(r)
    -- 1. 已明确释放或属于 assetFree 纯手工工单：必须无资源声明
    if r.released == true or require('EmberRoutesProbe/ProductionYield').assetFree(r) then
        return {}
    end
    
    local result = {}
    -- 2. 仅在未完成制作时锁定工作台表面
    if r.benchId and r.phase ~= 'CONFIRMED' and r.phase ~= 'RETURNING' and r.phase ~= 'DONE' then
        result[#result+1] = "craft-surface:" .. r.benchId
    end
    
    -- 3. 未消耗材料
    for _, m in ipairs(r.materials or {}) do
        if not m.consumed then result[#result+1] = "item:" .. m.id end
    end
    -- 4. 正在使用的工具 (3A 保留，待 3C 转 Custody)
    for _, t in ipairs(r.tools or {}) do result[#result+1] = "item:" .. t.id end
    -- 5. 已生成但未交付的产物
    for _, o in ipairs(r.outputs or {}) do
        if not o.delivered then result[#result+1] = "item:" .. o.id end
    end
    -- 6. 多步骤暂存中间件
    for _, h in ipairs(r.held or {}) do result[#result+1] = "item:" .. h.id end
    
    return result
end
```

### 4.2 HAUL 状态感知提取器：`HaulManifest.activeClaims(r)`
```lua
function HaulManifest.activeClaims(r)
    if r.state == 'DONE' or r.state == 'CANCELLED' then return {} end
    local result = {}
    if r.format == 2 then
        for _, l in ipairs(r.manifest or {}) do
            -- 仅对未送达、未撤回的受保护原件持有 Claims
            if l.custodyState ~= 'DELIVERED' and l.custodyState ~= 'WITHDRAWN' then
                result[#result+1] = "item:" .. l.itemId
            end
        end
    else
        -- format=1 兼容：仅在非终态时持有未结算物品
        for _, id in ipairs(r.items or {}) do result[#result+1] = "item:" .. id end
    end
    return result
end
```

- **一致性强制断言**：在任何非终态，必须恒成立：`job.payload.claims ≡ Provider.activeClaims(job.payload)`。

---

## 5. Quarantine 全局不可伪造所有权与冷启动恢复 (P0-4)

### 5.1 隔离所有权下沉至 LaborClaims 内核
彻底杜绝外部模块直接侵入 `claims.owners` 表或直接获取可变 Claims 单例。在 [LaborClaims.lua](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/shared/EmberRoutesProbe/LaborClaims.lua) 内部实现不可伪造的系统隔离锁：

```lua
-- LaborClaims.lua 内核方法
local SYSTEM_QUARANTINE_TOKEN = { taskId = "SYSTEM_QUARANTINE", generation = -1, resources = {} }

function methods:quarantine(key, reason)
    local existing = self.owners[key]
    if existing and existing == SYSTEM_QUARANTINE_TOKEN then return true end
    -- 强制剥夺并占有所有权，普通 Job 的 release/shrink 无法解除
    self.owners[key] = SYSTEM_QUARANTINE_TOKEN
    self.revision = self.revision + 1
    return true
end

function methods:isQuarantined(key)
    return self.owners[key] == SYSTEM_QUARANTINE_TOKEN
end
```

### 5.2 严格 API 隔离（消除原始 Token 与可变 Claims 泄漏）
改造 [LaborStore.lua](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/LaborStore.lua) 中向外暴露可变引用的危险接口：
- `Store.owner(itemId)` $\rightarrow$ **返回只读脱水快照** `{ taskId = owner.taskId, isQuarantined = ... }`，严禁返回内部 Token 引用；
- `Store.resourceOwner(key)` $\rightarrow$ 返回只读快照；
- `Store.claimsVersion()` $\rightarrow$ **仅返回整数版本号 `claims.revision`**，严禁返回 `claims` 自身实例。

### 5.3 双遍扫描全覆盖 (Two-Pass Scan) 与双向冻结
在 `LaborStore.data()` 重建全流程中覆盖所有资源（Job、ToolCustody、历史 Quarantine）：

```mermaid
flowchart TD
    Start[读档触发 Store.data] --> CleanClaims[1. Claims.new 初始化内存锁]
    CleanClaims --> ReInjectQ[2. 优先恢复 root.quarantineResources 隔离锁]
    ReInjectQ --> Pass1[3. Pass 1 扫描: 收集全部活跃 Job 与 Custody 的 claims]
    Pass1 --> BuildMap[建立 resourceKey 到声明者列表映射: usage[key] = {owner1, owner2}]
    BuildMap --> Pass2[4. Pass 2 裁决: 遍历 usage 映射]
    Pass2 --> Conflict{声明者数量 > 1 ?}
    Conflict -- 是 (发生冲突) --> DualFreeze[双向冻结: 双方任务打上 RECONCILE_REQUIRED / UNKNOWN<br/>并将该 key 立即调用 Claims:quarantine 锁定]
    Conflict -- 否 (独占合法) --> NormalAcquire[为唯一合法者执行 Claims:acquire]
    DualFreeze --> Finish
    NormalAcquire --> Finish[5. 发布全新不可变 Claims 快照]
```

- **覆盖 ToolCustody 冲突**：若冲突双方为 `Job` 与 `ToolCustody`，将该 Job 置为 `RECONCILE_REQUIRED`，并将 `ToolCustody` 的状态置为 `RECONCILE_REQUIRED`，涉事原件立即隔离；
- **覆盖终态 Job 冲突**：若涉及已处于 `DONE` 的记录，调用专用隔离转移接口将终态异常记录移入 `root.quarantineJobs`，绝不假定普通 CAS 可修改终态记录。

---

## 6. 全量旧账本迁移与局部整表暂存替换 (P0-5)

### 6.1 全量旧账本识别与清理矩阵
完整处理所有会触发 [JobStore.lua:legacy()](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/shared/EmberRoutesProbe/JobStore.lua#L44) 报错（`LEGACY_TASK_RESET_REQUIRED`）的旧结构：

| 旧结构路径 | 业务来源 | 迁移转换逻辑 | 清理终态 |
|---|---|---|---|
| **`root.craftProbes`** | 旧版手工制作探针 | 提取其中的旧工单，转化为标准 CRAFT Job | 迁移完成后置 `root.craftProbes = nil` |
| **`root.labor.tasks`** | 旧版现场与搬运任务 | 提取旧搬运任务，转化为标准 HAUL Job | 迁移完成后置 `root.labor = nil` |
| **`root.job`** | 最早期单工单原语 | 提取单任务事实并转化为规范 Job | 迁移完成后置 `root.job = nil` |
| **`root.taskRoutes`** | 关联搬运路线数据 | 规范化并迁移至 `root.taskRoutes` 规范格式 | 保留路线几何事实 |

### 6.2 局部整表暂存与一次性提交 (Atomic Staging Replacement)
彻底杜绝边遍历边向活动账本修改的隐患：

```lua
-- JobMigration.lua 局部暂存与单次替换
function JobMigration.upgrade(root)
    if root.jobContractVersion and root.jobContractVersion >= 2 then return true end
    
    local stagedTaskJobs = { format = 1, byId = {} }
    local fingerprinted = {}
    
    -- 1. 在独立 staging 结构中装配所有候选 Job
    for id, oldCraft in pairs(collectOldCrafts(root)) do
        local job = assembleStandardCraftJob(oldCraft)
        stagedTaskJobs.byId[job.id] = job
        fingerprinted[job.id] = calculateFingerprint(job)
    end
    for id, oldHaul in pairs(collectOldHauls(root)) do
        local job = assembleStandardHaulJob(oldHaul)
        stagedTaskJobs.byId[job.id] = job
        fingerprinted[job.id] = calculateFingerprint(job)
    end
    
    -- 2. 全量预检 (验证 Envelope 合法性、ID 唯一性、无序列化陷阱)
    for id, job in pairs(stagedTaskJobs.byId) do
        assert(JobStore.validateDetached(job), "MIGRATION_VALIDATION_FAILED: " .. id)
    end
    
    -- 3. 一次性原子表替换 (Single Atomic Replacement)
    root.taskJobs = stagedTaskJobs
    root.migrationFingerprints = fingerprinted
    
    -- 4. 清理旧结构，防止触发 legacy() 崩溃
    root.craftProbes = nil
    root.labor = nil
    root.job = nil
    
    -- 5. 写入契约版本号封板
    root.jobContractVersion = 2
    return true
end
```

### 6.3 确定性 ID 命名空间与断点续迁证明
1. **确定性命名空间主键**：
   - 旧 CRAFT 生成主键：`"craft:" .. oldRecord.id`；
   - 旧 HAUL 生成主键：`"haul:" .. oldRecord.id`；
   - 杜绝不同历史账本之间的 ID 碰撞。
2. **断点崩溃恢复证明**：
   若在步骤 3 替换后、步骤 5 写版本前掉电，重进时根据 `root.migrationFingerprints` 严格核对全量字段（格式、阶段、资源、generation、交付状态）。指纹 100% 吻合则判定为已完整就绪，安全补写版本号；指纹不吻合直接转入 `quarantineJobs`。

---

## 7. BusinessJobs 全面去特权化与全库调用点重构 (P0-6)

### 7.1 架构职责彻底剥离与只读化
将原本臃肿的 `BusinessJobs.lua` 拆分为职责明确的单向依赖结构：
- **`BusinessJobs.lua`（仅提供只读查询投影）**：
  - 彻底删除 `flush()`、`refresh()`、`publishCraft()`、`publishHaul()`；
  - 彻底移除对 `j.state`、`j.revision`、`j.payload = r` 的内存直接写入；
  - 查询接口全部返回由 `JobStore` 产出的 Detached Copy：
    - `BusinessJobs.get(jobId)`
    - `BusinessJobs.records(providerType)`
    - `BusinessJobs.forNpc(npcId)`
    - `BusinessJobs.activeForNpc(npcId, providerType)`
- **`BusinessJobLifecycle.lua`（临时收敛退役过渡逻辑）**：
  - 暂时存放 `canRetire(jobId)` 与 `retire(jobId)` 业务检查，由 `TaskRetirement.lua` 受控调用，待 3B 彻底收口。

### 7.2 现有直接写 Payload 隐患全面清理表

| 涉事文件 | 原有直接写代码 | 3A 规范重构方案 |
|---|---|---|
| [HaulAgent.lua:45](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/HaulAgent.lua#L45) | `line.custodyState = 'CARRIED'`<br/>`r.activeAttempt = nil` | 改为调用 `LaborStore.mutateJobClaims(jobId, rev, updatedPayload, 'REMOVE', ...)` CAS 更新 |
| [Production.lua:88](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/Production.lua#L88) | 原地修改 `r.phase`、`r.uncertain` | 改为调用 `updateJobPayload(jobId, rev, editFn)` 提交 CAS 更新 |
| [TaskPersistence.lua:48](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/TaskPersistence.lua#L48) | `BusinessJobs.flush()` | **彻底删除此调用**，持久化 facts 随每次 CAS 实时安全落盘 |
| [LaborStore.lua](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/LaborStore.lua) | 直接穿透读 `root.taskJobs.byId` | 改为通过 `TaskJobs.current():records()` 只读接口遍历 |

---

## 8. 物理操作、Job CAS 与 Runtime Claims 的三层故障恢复模型

严格遵循三层故障恢复模型，杜绝把内存 CAS 误认为磁盘事务：

### 8.1 CRAFT 制作新产物故障与 Scope Quarantine Fence
在制作 `COMMITTING` 阶段，原生动作消耗了材料并产出了新物品 B：
1. **正常路径**：
   新物品 B 生成 $\rightarrow$ 确认其物理 ItemID $\rightarrow$ `mutateJobClaims(..., 'ADD', {"item:B"})` 提交 CAS 更新并扩展 Token $\rightarrow$ 状态推进为 `CONFIRMED`；
2. **故障窗口应对 (Scope Quarantine Fence)**：
   若原生制作完成，但 CAS 尚未提交成功游戏即遭遇掉电或崩溃：
   - 读档恢复时，由于无法在旧 claims 中找到新产物 B，且原材料已被物理扣减，系统检测到物理事实与 Job 声明不符；
   - **立即触发 Scope Quarantine Fence**：将该 Job 标记为 `RECONCILE_REQUIRED` 与 `effects = 'UNKNOWN'`，并在该据点（`scopeId`）设立安全围栏，暂时挂起涉及该制作台的后续派工，记录日志 `NEW_PRODUCT_UNRECONCILED`，等待离线对账探针核对物品归属，**绝不放任新产物脱保流失**。

---

## 9. 单 NPC 单活动运行时与任务恢复仲裁

### 9.1 责任持有与执行候选分离
- **`retainedJobsForNpc(npcId)`**：返回该 NPC 持有的所有尚未结清物理责任的 Job 列表（包括 `SUSPENDED`、`SETTLING` 等）；
- **`executionCandidateForNpc(npcId)`**：根据仲裁矩阵选出**唯一一个**允许进入 `TaskRuntime` 激活身体的候选 Job。

### 9.2 确定性恢复仲裁矩阵 (Deterministic Arbitration Matrix)
当一个 NPC 关联多个可恢复 Job 时，禁止使用 `pairs()` 遍历顺序，严格按以下确定性次序仲裁：
1. **Priority 1 (生命安全自理)**：`SELF_CARE`（危急吃喝治疗）；
2. **Priority 2 (玩家命令与抢占)**：随从跟随、去睡觉等用户显式指令；
3. **Priority 3 (必须完结的物理责任)**：手持未交付物品的 `HAUL`（`holding`）或处于 `DELIVER` 阶段的 `FIELD_WORK`；
4. **Priority 4 (已认领材料的制作)**：处于 `CRAFTING` / `COMMITTING` 阶段的 `CRAFT`；
5. **Priority 5 (普通可重新认领的外勤)**：处于 `PREPARING` 的 `FIELD_WORK`。
若同级存在多个候选且无法决出优先级，**全部保持 SUSPENDED 并记录诊断**，绝不允许并发执行。

---

## 10. 冷启动绝对顺序与硬门禁屏障

### 10.1 冷启动执行顺序锁定
在 [TaskPersistence.lua:Save.load()](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/TaskPersistence.lua#L43) 中严格遵循以下次序：
```
1. JobMigration.upgrade(Registry.data())   -- [阶段 0: 全量旧账本迁移与整表原子替换]
2. Probe.prepareMembershipRecovery()        -- [阶段 1: 会员与归属恢复]
3. Craft.prepareRecovery()                  -- [阶段 2: 规范化恢复 - 必须使用 CAS 提交暂停]
4. Store.data()                             -- [阶段 3: 恢复 Quarantine 锁并双遍扫描重建全部 Claims]
5. FieldWork.prepareRecovery()              -- [阶段 4: 现场任务恢复]
6. Runtime 开放准入门禁                    -- [阶段 5: 调度器启动]
```

### 10.2 TaskJobs.current() 强制门禁
在 [TaskJobs.lua:current()](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/TaskJobs.lua) 增加入口强断言：
```lua
function TaskJobs.current()
    local root = Registry.data()
    if root.jobContractVersion ~= 2 or not root.taskJobs or root.taskJobs.format ~= 1 then
        error(string.format("TASK_JOBS_UNINITIALIZED_OR_CORRUPT: version=%s format=%s", 
            tostring(root.jobContractVersion), tostring(root.taskJobs and root.taskJobs.format)))
    end
    return JobStore.open(root)
end
```
杜绝在未迁移或数据损坏时静默创建空账本。

---

## 11. 全生命周期压力测试矩阵 (T01~T03, T17~T33)

实施完毕后必须在脱库测试环境与游戏环境中 100% 通过以下 20 项断言：

| 编号 | 测试用例分类 | 核心断言与破坏性注入场景 |
|---|---|---|
| **T01** | 全量旧存档升级 | 加载旧版 CRAFT(1/2/3) 与 HAUL(1/2)，断言 materials, tools, outputs, held, surface 与 manifest 100% 进入 claims，无一脱保。 |
| **T02** | 迁移幂等与防重 | 连续多次调用升级屏障，版本号锁定为 2，断言不产生新 Job，不产生多余 CAS revision 自增。 |
| **T03** | 资源互斥排他 | 材料或工作台被 Job A 认领后，Job B 在 DISCOVER 阶段认领该资源直接被拒绝并退避。 |
| **T17** | Custody 与退役解耦 | CRAFT Job 结清退役注销，NPC 背包中的工具 Custody 完好无损，不随 Job 删除而丢失。 |
| **T18** | **创建补偿全回滚** | 模拟 `LaborClaims:acquire` 成功但在 `store:create` 时抛错，断言调用 `Claims:release` 100% 释放全部 Claims 与容量。 |
| **T19** | **迁移断点全边界重试** | 分别在“局部暂存完成但未替换”、“新账本替换完成版本未写”等 4 个断点注入崩溃，二次启动验证无损收敛。 |
| **T20** | CRAFT 复杂资产保护 | 验证处于 CRAFTING 阶段的工单升级后，未消耗材料、产物与正在使用的工具均在 claims 中受保护，且区分 `assetFree`。 |
| **T21** | HAUL 增量交付存盘 | 搬运 5 件物品，送仓 2 件，存盘退出重进，读档后 claims 仅恢复剩余 3 件，已入库 2 件绝不重新上锁。 |
| **T22** | **跨层一致性与故障围栏**| 注入两个故障窗口（物理完成 CAS 未成、CAS 成功 shrink 未成），并在 CRAFT 产物未决时断言触发 Scope Quarantine Fence。 |
| **T23** | 多 Job 与单 Runtime | 验证同一 NPC 持有 SUSPENDED、PREPARING、DONE 多个 Job 共存，但在 TaskRuntime 中任何时刻仅允许最多一个物理执行。 |
| **T24** | **全实体隔离双向冻结** | 模拟 Job 与 Job、以及 Job 与 ToolCustody 发生原件冲突，验证双方全部进入 RECONCILE_REQUIRED，涉事资源全局隔离。 |
| **T25** | CAS 失败锁不丢 | 模拟材料扣减时 CAS update 遭遇版本冲突失败，断言原件责任与内存 Token 绝不静默丢弃，维持锁保护。 |
| **T26** | **Envelope 容错隔离** | 注入包含循环引用或字段损坏的非法 Job，验证 `Store.open` 成功打开其余健康 Job，并将坏单隔离到 `quarantineJobs`。 |
| **T27** | **未迁移访问硬门禁** | 在 `root.jobContractVersion ~= 2` 时直接调用 `TaskJobs.current()`，验证其抛出迁移门禁异常并拒绝暴露账本。 |
| **T28** | **Payload 只读副本保护**| 外部代码尝试直接修改 `BusinessJobs.get(id).payload` 的属性，验证 `JobStore` 中的底层持久化数据不受任何影响。 |
| **T29** | **终态无 claims 约束** | 验证处于 `released` 的 CRAFT 和已交付的 HAUL 工单，其 `payload.claims` 必须强制为空，否则 `JobStore.valid` 拒绝。 |
| **T30** | **全旧账本迁移完整性** | 验证旧 `root.job`、`root.labor.tasks`、旧 `craftProbes` 全部无损迁入 `taskJobs`，且完全消除 `legacy()` 报错。 |
| **T31** | **Quarantine 重进持久性**| 隔离某资源后存盘退出重进，验证 `Store.data()` 重建 Claims 时该资源依然直接处于不可认领状态。 |
| **T32** | **隔离权限绝对防绕过** | 针对处于隔离状态的原件，验证普通 Job、ToolCustody 以及所有 Provider 的认领入口均直接报 `ITEM_RESERVED` 被阻断。 |
| **T33** | **多物品容量预约一致性**| 针对 HAUL format=2 的多物品容量预约，验证 CAS 变更、存盘重进、部分交付时容量恢复均保持 100% 一致。 |
