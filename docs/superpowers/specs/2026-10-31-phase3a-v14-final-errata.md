# Phase 3A v1.5 Final Errata：无旧档迁移与业务接入执行基准
# (Phase 3A v1.5 Final Errata & Execution Baseline)

> 修订：2026-11-01｜原始设计基线：`d43404dc`｜本轮审查基线：`dc8e17c`｜状态：B.5 待独立验收；Stage C 冻结｜分支：`phase-3a-consolidation`

---

本修订与[主规格 v1.5](2026-10-31-phase3a-job-contract-standardization-design.md#0-当前执行裁决2026-11-01覆盖旧稿冲突内容)共同执行。用户已取消旧档迁移；旧文件名只保留链接，不表示继续实施 v1.4 的 F4。主路线与阶段门禁以主规格第 0 节及 [BACKLOG](../../BACKLOG.md) 为准。

## 目录
1. [开工四条不可逾越红线 (Iron Invariants)](#1-开工四条不可逾越红线-iron-invariants)
2. [F1: CRAFT/HAUL 新 Validator 与 JobStore.valid 核心接入](#2-f1-crafthaul-新-validator-与-jobstorevalid-核心接入)
3. [F2: 创建事务防重复接管 (acquireNew) 与统一 mutateJob](#3-f2-创建事务防重复接管-acquirenew-与统一-mutatejob)
4. [F3: Quarantine 内核不可伪造所有权与持久化闭环](#4-f3-quarantine-内核不可伪造所有权与持久化闭环)
5. [F4: 支持格式校验与写入前拒绝](#5-f4-支持格式校验与写入前拒绝)
6. [F5: CRAFT COMMITTING 规范与 Scope Fence 8大入口全量拦截](#6-f5-craft-committing-规范与-scope-fence-8大入口全量拦截)
7. [F6: 状态机 RUNNING -> STOPPING -> SETTLING 全 Provider 严格适配](#7-f6-状态机-running---stopping---settling-全-provider-严格适配)
8. [F7: BusinessJobs 全库写权限清理与调用点完整迁移表](#8-f7-businessjobs-全库写权限清理与调用点完整迁移表)
9. [F8: TaskArbiter 恢复仲裁器与非 Job 意图接入](#9-f8-taskarbiter-恢复仲裁器与非-job-意图接入)
10. [F9: 冷启动完整恢复链路与 T01~T33 压力断言闭环](#10-f9-冷启动完整恢复链路与-t01t33-压力断言闭环)

---

## 1. 开工四条不可逾越红线 (Iron Invariants)

1. **红线 1 (F2 唯一新创防接管)**：`LaborStore.createClaimedJob` 必须调用专用的 `claims:acquireNew(...)`，严禁复用恢复任务时的同 ID 继承逻辑。遇到已有 `taskId` 立即拒绝，杜绝 `JobStore.create` 遇 `JOB_EXISTS` 报错时在回滚中误释放已存在的合法 Token；
2. **红线 2 (F4 无旧档迁移与写入前拒绝)**：受支持格式保留正常保存恢复；不支持的历史格式在任何写入、清理或覆盖之前拒绝。禁止导入、Staging、迁移指纹、旧账本替换及自动清理；不得把 ModData 内存写入说成磁盘事务；
3. **红线 3 (F1 JobStore 核心挂接)**：`CraftJobRecord.valid(job)` 与 `HaulJobRecord.valid(job)` 必须硬编码嵌入 [JobStore.lua:valid()](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/shared/EmberRoutesProbe/JobStore.lua#L34)，任何创建、更新与打开操作均受其强约束；
4. **红线 4 (F5 全覆盖安全围栏)**：Scope Quarantine Fence 必须覆盖全部 8 类入口（`PublicWork`、`LogisticsService`、`DeliveryService`、`CraftingService`、`Cooking`、`FieldWork`、通用 Job 创建入口、通用 Job 恢复入口），未决产物对账完成前严禁任何新工单渗漏。

---

## 2. F1: CRAFT/HAUL 新 Validator 与 JobStore.valid 核心接入

### 2.1 独立标准 Job Validator
在 `shared/EmberRoutesProbe/` 目录新增标准 Job 专用验证器：

```lua
-- shared/EmberRoutesProbe/CraftJobRecord.lua
local Validate = require 'EmberRoutesProbe/Validate'
local R = {}

function R.activeClaims(p)
    if p.released == true or require('EmberRoutesProbe/ProductionYield').assetFree(p) then
        return {}
    end
    local res = {}
    if p.benchId and p.phase ~= 'CONFIRMED' and p.phase ~= 'RETURNING' and p.phase ~= 'DONE' then
        res[#res+1] = "craft-surface:" .. p.benchId
    end
    for _, m in ipairs(p.materials or {}) do
        if not m.consumed then res[#res+1] = "item:" .. m.id end
    end
    for _, t in ipairs(p.tools or {}) do res[#res+1] = "item:" .. t.id end
    for _, o in ipairs(p.outputs or {}) do
        if not o.delivered then res[#res+1] = "item:" .. o.id end
    end
    for _, h in ipairs(p.held or {}) do res[#res+1] = "item:" .. h.id end
    return res
end

function R.valid(job)
    if type(job) ~= 'table' or job.providerType ~= 'CRAFT' or type(job.payload) ~= 'table' then return false end
    local p = job.payload
    if p.format ~= 4 or not Validate.integer(p.sequence, 0) or type(p.claims) ~= 'table' then return false end
    if not Validate.stringId(p.recipeId) or not Validate.integer(p.target, 1) or not Validate.integer(p.produced, 0) then return false end
    
    -- 终态严格无 claims
    if job.state == 'DONE' or job.state == 'CANCELLED' then
        if #p.claims > 0 or p.released ~= true then return false end
    end
    
    -- activeClaims 一致性检查
    local expected = R.activeClaims(p)
    if #p.claims ~= #expected then return false end
    local seen = {}
    for _, k in ipairs(p.claims) do seen[k] = true end
    for _, k in ipairs(expected) do if not seen[k] then return false end end
    return true
end

return R
```

```lua
-- shared/EmberRoutesProbe/HaulJobRecord.lua
local Validate = require 'EmberRoutesProbe/Validate'
local R = {}

function R.activeClaims(p)
    if p.state == 'DONE' or p.state == 'CANCELLED' then return {} end
    local res = {}
    if p.format == 3 then
        for _, l in ipairs(p.manifest or {}) do
            if l.custodyState ~= 'DELIVERED' and l.custodyState ~= 'WITHDRAWN' then
                res[#res+1] = "item:" .. l.itemId
            end
        end
    end
    return res
end

function R.valid(job)
    if type(job) ~= 'table' or job.providerType ~= 'HAUL' or type(job.payload) ~= 'table' then return false end
    local p = job.payload
    if p.format ~= 3 or not Validate.integer(p.sequence, 0) or type(p.claims) ~= 'table' then return false end
    if not Validate.stringId(p.source) or not Validate.stringId(p.destination) or type(p.manifest) ~= 'table' then return false end
    
    -- 终态严格无 claims 与容量预约
    if job.state == 'DONE' or job.state == 'CANCELLED' then
        if #p.claims > 0 or p.reservation ~= nil then return false end
    end
    
    -- activeClaims 一致性检查
    local expected = R.activeClaims(p)
    if #p.claims ~= #expected then return false end
    local seen = {}
    for _, k in ipairs(p.claims) do seen[k] = true end
    for _, k in ipairs(expected) do if not seen[k] then return false end end
    return true
end

return R
```

### 2.2 核心接入：修改 `JobStore.lua:valid()`
在 [JobStore.lua:34-43](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/shared/EmberRoutesProbe/JobStore.lua#L34-L43) 明确接入：
```lua
local function valid(job)
    local basic = type(job)=='table' and id(job.id) and id(job.npcId) and id(job.providerType)
        and id(job.scopeId) and integer(job.revision) and job.revision>0 and states[job.state]
        and (job.effects=='KNOWN' or job.effects=='UNKNOWN') and type(job.obligations)=='table'
        and type(job.payload)=='table' and (not job.orderId or id(job.orderId))
        and (not terminal[job.state] or (job.effects=='KNOWN' and empty(job.obligations) and #(job.payload.claims or {}) == 0))
    return basic
        and (job.providerType ~= 'COOKING' or require('EmberRoutesProbe/CookingRecord').valid(job))
        and (job.providerType ~= 'FIELD_WORK' or require('EmberRoutesProbe/FieldRecord').valid(job))
        and (job.providerType ~= 'ACTIVITY' or require('EmberRoutesProbe/ActivityRecord').valid(job))
        and (job.providerType ~= 'CRAFT' or require('EmberRoutesProbe/CraftJobRecord').valid(job))
        and (job.providerType ~= 'HAUL' or require('EmberRoutesProbe/HaulJobRecord').valid(job))
end
```

---

## 3. F2: 创建事务防重复接管 (acquireNew) 与统一 mutateJob

### 3.1 `LaborClaims:acquireNew` 绝不接管旧 Token
修改 [LaborClaims.lua](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/shared/EmberRoutesProbe/LaborClaims.lua)：
```lua
function methods:acquireNew(taskId, generation, resources)
    -- 核心铁律：禁止接管已有 taskId，防止重复创建时污染或误删旧 Token
    for _, token in pairs(self.owners) do
        if token.taskId == taskId then
            return nil, "TASK_ALREADY_HAS_CLAIMS"
        end
    end
    for _, key in ipairs(resources) do
        local owner = self.owners[key]
        if owner then return nil, "ITEM_RESERVED" end
    end
    local token = { taskId = taskId, generation = generation, resources = resources }
    for _, key in ipairs(resources) do self.owners[key] = token end
    if #resources > 0 then self.revision = self.revision + 1 end
    return token
end
```

### 3.2 统一创建原子入口：`LaborStore.createClaimedJob`
```lua
function Store.createClaimedJob(job)
    if not JobStore.valid(job) or job.state ~= 'PREPARING' or job.revision ~= 1 then
        return false, 'INVALID_JOB_ENVELOPE'
    end
    local claimsInstance = Store.claimsInstance()
    local p = job.payload
    local keys = p.claims or {}
    
    -- 1. 采用 acquireNew 杜绝冒充接管
    local token, why = claimsInstance:acquireNew(job.id, job.businessGeneration or 0, keys)
    if not token then return false, 'CLAIMS_ACQUIRE_FAILED:' .. tostring(why) end
    
    -- 2. 容量预约
    if p.reservation and p.reservation.items then
        for itemId, amt in pairs(p.reservation.items) do
            if not claimsInstance:reserve(token, p.reservation.key, itemId, amt) then
                claimsInstance:release(token) -- 回滚全部 Claims
                return false, 'CAPACITY_RESERVE_FAILED'
            end
        end
    end
    
    -- 3. 提交 JobStore 创建
    local store = TaskJobs.current()
    local ok, err = store:create(job)
    if not ok then
        claimsInstance:release(token) -- 完整回滚！
        return false, 'JOB_CREATE_FAILED_ROLLED_BACK:' .. tostring(err)
    end
    
    claimsTokens[job.id] = token
    return true, job.id
end
```

### 3.3 统一状态、资源与容量变动：`LaborStore.mutateJob`
```lua
function Store.mutateJob(jobId, expectedRevision, proposedPayload, mutation)
    local store = TaskJobs.current()
    local job = store:get(jobId)
    if not job or job.revision ~= expectedRevision then return false, 'STALE_REVISION' end
    local claimsInstance = Store.claimsInstance()
    local token = claimsTokens[jobId]
    if not token then return false, 'NO_RUNTIME_TOKEN' end
    
    -- 1. 资源增加 (ADD)
    if mutation and mutation.addKeys and #mutation.addKeys > 0 then
        local ok, why = claimsInstance:extend(token, mutation.addKeys)
        if not ok then return false, 'EXTEND_FAILED:' .. tostring(why) end
    end
    
    -- 2. 容量变动
    if mutation and mutation.capacityChanges then
        -- 统一增占容量
    end
    
    -- 3. 核心 CAS 更新
    local patch = { payload = proposedPayload }
    if mutation and mutation.state then patch.state = mutation.state end
    if mutation and mutation.effects then patch.effects = mutation.effects end
    if mutation and mutation.businessGeneration then
        patch.businessGeneration = mutation.businessGeneration
    end
    
    local okCAS, nextRev = store:update(jobId, expectedRevision, patch)
    if not okCAS then
        Store.quarantineResource(jobId .. ":mutation_fail", "CAS_FAILED", {jobId=jobId, rev=expectedRevision})
        return false, 'CAS_FAILED_ISOLATED:' .. tostring(nextRev)
    end
    
    -- 4. 资源释放 (REMOVE) - 仅在 CAS 成功后缩减
    if mutation and mutation.removeKeys and #mutation.removeKeys > 0 then
        claimsInstance:shrink(token, mutation.removeKeys)
    end
    
    return true, nextRev
end
```

---

## 4. F3: Quarantine 内核不可伪造所有权与持久化闭环

1. **不可伪造所有权特征**：
   `owner.kind == "SYSTEM_QUARANTINE"` 固化在 `LaborClaims.lua`，普通 acquire/extend 见此特征直接阻断（`RESOURCE_SYSTEM_QUARANTINED`）；
2. **持久化唯一写入入口**：
   `LaborStore.quarantineResource(key, reason, evidence)` 负责写入 `root.quarantineResources[key]`，并在读档 `Store.data()` 时作为首要步骤优先恢复全局 Claims；
3. **API 完全隔离**：
   `Store.owner(itemId)`、`Store.resourceOwner(key)` 仅返回只读快照；`Store.claimsVersion()` 仅返回整数版本号 `claims.revision`。

---

## 5. F4: 支持格式校验与写入前拒绝

全面旧账本迁移已由用户撤销。不得开发 `JobMigration`、迁移状态机、指纹或旧账本清理；新世界初始化和已有支持格式正常保存恢复继续保留。

默认保证当前受支持存档格式的正常保存与恢复。对于明确不支持的历史格式，不要求迁移兼容；必须在任何数据写入之前识别并明确拒绝加载，不得自动修改、清理或覆盖原始数据。严格最早入口仍需验证，不能把规格修订当作运行门禁已实现。

不提前删除 Production / Haul 仍在调用的旧接口。先完成真实调用切换、新建世界验收及无调用证明，再删除对应旧写路径。

---

## 6. F5: CRAFT COMMITTING 规范与 Scope Fence 8大入口全量拦截

### 6.1 CRAFT 制作前强制 COMMITTING
物理制作动作前，必须经 CAS 将阶段写为 `phase = 'COMMITTING'` 并落盘。若断电重进产物未决，触发 Scope Fence。

### 6.2 八大入口全量拦截清单
必须在以下 8 处代码第一行统一接入 `Dispatcher.canDispatchScope(scopeId)`：
1. `PublicWork.lua:eligible` (公共工单派发入口)；
2. `LogisticsService.lua:request` (物流调度入口)；
3. `DeliveryService.lua:submit` (配送调度入口)；
4. `CraftingService.lua:execute` (手动制作执行入口)；
5. `CookingService.lua:eligible` (烹饪派发入口)；
6. `FieldWork.lua:submit` (现场劳动入队入口)；
7. `LaborStore.createClaimedJob` (通用 Job 创建入口)；
8. `TaskResume.lua:restoreCandidate` (通用 Job 恢复与重新派发入口)。

---

## 7. F6: 状态机 RUNNING -> STOPPING -> SETTLING 全 Provider 严格适配

修改 [CookingService.lua:348,576](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/CookingService.lua#L348) 与 [FieldWork.lua:131,309](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/FieldWork.lua#L131)：
物理完成时统一先通过 `STOPPING` 停稳，核验 `body.snapshot().nativeStopped` 之后再推进到 `SETTLING`。

---

## 8. F7: BusinessJobs 全库写权限清理与调用点完整迁移表

1. 拆分 `BusinessJobLifecycle.lua` 暂存退役；
2. `BusinessJobs.lua` 彻底剥离写权限，只提供基于 `JobStore.current():get(jobId)` 的 Detached 只读查询；
3. 清理 [HaulAgent.lua:45](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/HaulAgent.lua#L45) 与 [Production.lua:88](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/Production.lua#L88) 的直接写 Payload，全部改走 `Store.mutateJob` CAS 事务。

---

## 9. F8: TaskArbiter 恢复仲裁器与非 Job 意图接入

若现有恢复入口需要集中候选优先级，仅以纯候选仲裁接入；是否新增 `TaskArbiter.lua` 由真实调用链证明，不能另建活动任务表、身体控制权或库存权威。该后续项不得扩充到当前 B.5 收尾。目标矩阵：
- Priority 1: `SELF_CARE`（生理危急）；
- Priority 2: 随从跟随 / 睡眠指令；
- Priority 3: 必须交付责任（`HAUL` CARRIED/RECONCILE）；
- Priority 4: 已认领物料的制作；
- Priority 5: 普通待认领工单。
维持 TaskRuntime 单执行体约束。

---

## 10. F9: 冷启动完整恢复链路与 T01~T33 压力断言闭环

严格维持 [TaskPersistence.lua:Save.load()](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/TaskPersistence.lua#L43) 六段式恢复序：
`支持格式最早只读校验（不迁移）` $\rightarrow$ `Membership/Stock/Care` $\rightarrow$ `Craft.prepareRecovery` $\rightarrow$ `Quarantine+Store.data(Claims)` $\rightarrow$ `FieldWork/PublicWork/Activity` $\rightarrow$ `Runtime Admission`。

---

当前执行以 v1.5 无迁移范围为准。规格不证明实现；B.5 通过独立验收后才解冻 Stage C，后续不再先扩充通用框架。
