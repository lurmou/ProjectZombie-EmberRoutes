-- Persisted maintain-stock store. Attached to the Registry/Work root ModData.
-- Manages CRUD commands, rule limits, unique keys, and atomic cycle links.
local Registry=require "EmberRoutesProbe/ContainerRegistry"
local Ledger=require "EmberRoutesProbe/SettlementLedger"
local StockRule=require "EmberRoutesProbe/StockRule"

local StockStore={}

local function copyRule(r)
    if not r then return nil end
    local copy={
        id=r.id,
        settlementId=r.settlementId,
        fullType=r.fullType,
        recipeId=r.recipeId,
        recipeSignature=r.recipeSignature,
        npcId=r.npcId,
        surfaceId=r.surfaceId,
        minimum=r.minimum,
        enabled=r.enabled==true,
        revision=r.revision or 0,
        nextCycle=r.nextCycle or 1,
        deleting=r.deleting==true
    }
    if r.activeCycle then
        local c=r.activeCycle
        copy.activeCycle={
            sequence=c.sequence,
            taskId=c.taskId,
            ruleRevision=c.ruleRevision,
            phase=c.phase,
            requested=c.requested,
            snapshotRevision=c.snapshotRevision,
            settlementRevision=c.settlementRevision
        }
    end
    return copy
end

function StockStore.data()
    local root=Registry.data()
    local store=root.maintainStock
    if not store then
        store={format=1,revision=0,rules={}}
        root.maintainStock=store
    elseif store.format~=1 or type(store.rules)~="table" then
        error("STOCK_STORE_CORRUPTED")
    end
    return store
end

function StockStore.get(ruleId)
    if type(ruleId)~="string" then return nil end
    local store=StockStore.data()
    return copyRule(store.rules[ruleId])
end

function StockStore.list(settlementId)
    local store=StockStore.data()
    local result={}
    for _,r in pairs(store.rules) do
        if not settlementId or r.settlementId==settlementId then
            result[#result+1]=copyRule(r)
        end
    end
    table.sort(result,function(a,b) return a.id<b.id end)
    return result
end

function StockStore.findByProduct(settlementId,fullType)
    if type(settlementId)~="string" or type(fullType)~="string" then return nil end
    local store=StockStore.data()
    for _,r in pairs(store.rules) do
        if r.settlementId==settlementId and r.fullType==fullType and not r.deleting then
            return copyRule(r)
        end
    end
    return nil
end

function StockStore.count(settlementId)
    local store=StockStore.data()
    local count=0
    for _,r in pairs(store.rules) do
        if not settlementId or r.settlementId==settlementId then
            if not r.deleting then count=count+1 end
        end
    end
    return count
end

function StockStore.countGlobal()
    return StockStore.count(nil)
end

-- Command execution (actor-authorized, atomic)
function StockStore.command(actor,settlementId,cmd,payload)
    if isClient() or isServer() then return nil,"DRIVER_UNAVAILABLE" end
    if not Ledger.authorized(actor) then return nil,"DRIVER_UNAVAILABLE" end
    local entry=Ledger.data().entries[settlementId]
    if not entry then return nil,"SETTLEMENT_MISSING" end
    if entry.factionId~=Ledger.data().factionId then return nil,"ACCESS_DENIED" end

    local store=StockStore.data()
    payload=payload or {}

    if cmd=="create" then
        if StockStore.count(settlementId)>=32 then return nil,"SETTLEMENT_LIMIT_REACHED" end
        if StockStore.countGlobal()>=128 then return nil,"GLOBAL_LIMIT_REACHED" end

        local existing=StockStore.findByProduct(settlementId,payload.fullType)
        if existing then return nil,"DUPLICATE_PRODUCT_RULE" end

        local id=Registry.id()
        local rule={
            id=id,
            settlementId=settlementId,
            fullType=payload.fullType,
            recipeId=payload.recipeId,
            recipeSignature=payload.recipeSignature,
            npcId=payload.npcId,
            surfaceId=payload.surfaceId,
            minimum=payload.minimum,
            enabled=payload.enabled~=false,
            revision=1,
            nextCycle=1,
            deleting=false
        }
        if not StockRule.validate(rule) then
            return nil,"INVALID_RULE_PARAMETERS"
        end

        store.rules[id]=rule
        store.revision=store.revision+1
        return id

    elseif cmd=="update" then
        local r=store.rules[payload.ruleId]
        if not r or r.settlementId~=settlementId then return nil,"RULE_NOT_FOUND" end
        if r.deleting then return nil,"RULE_DELETING" end
        if payload.expectedRevision and r.revision~=payload.expectedRevision then
            return nil,"REVISION_MISMATCH"
        end
        local m=payload.minimum
        if type(m)~="number" or m<1 or m>9999 or m~=math.floor(m) then
            return nil,"INVALID_MINIMUM"
        end
        r.minimum=m
        r.revision=r.revision+1
        store.revision=store.revision+1
        return "RULE_UPDATED"

    elseif cmd=="enable" or cmd=="disable" then
        local r=store.rules[payload.ruleId]
        if not r or r.settlementId~=settlementId then return nil,"RULE_NOT_FOUND" end
        if r.deleting then return nil,"RULE_DELETING" end
        if payload.expectedRevision and r.revision~=payload.expectedRevision then
            return nil,"REVISION_MISMATCH"
        end
        r.enabled=cmd=="enable"
        r.revision=r.revision+1
        store.revision=store.revision+1
        return "RULE_STATUS_CHANGED"

    elseif cmd=="delete" then
        local r=store.rules[payload.ruleId]
        if not r or r.settlementId~=settlementId then return nil,"RULE_NOT_FOUND" end
        if payload.expectedRevision and r.revision~=payload.expectedRevision then
            return nil,"REVISION_MISMATCH"
        end
        if r.activeCycle==nil then
            store.rules[payload.ruleId]=nil
            store.revision=store.revision+1
            return "RULE_DELETED"
        else
            r.deleting=true
            r.enabled=false
            r.revision=r.revision+1
            store.revision=store.revision+1
            return "RULE_DELETING"
        end

    elseif cmd=="retry" then
        local r=store.rules[payload.ruleId]
        if not r or r.settlementId~=settlementId then return nil,"RULE_NOT_FOUND" end
        if r.activeCycle and r.activeCycle.phase=="RECONCILE_REQUIRED" then
            -- Retry requires user explicit confirmation; transitions back to ATTACHED to re-evaluate
            r.activeCycle.phase="ATTACHED"
            r.revision=r.revision+1
            store.revision=store.revision+1
            return "RETRY_ACCEPTED"
        end
        return "RETRY_NOOP"

    else
        return nil,"UNKNOWN_COMMAND"
    end
end

-- Cycle Lifecycle hooks (invoked by StockService)
function StockStore.prepareCycle(ruleId,taskId,requested,snapshotRevision,settlementRevision)
    local store=StockStore.data()
    local r=store.rules[ruleId]
    if not r or r.activeCycle~=nil or r.deleting or not r.enabled then
        return nil,"CANNOT_PREPARE_CYCLE"
    end
    r.activeCycle={
        sequence=r.nextCycle,
        taskId=taskId,
        ruleRevision=r.revision,
        phase="PREPARED",
        requested=requested,
        snapshotRevision=snapshotRevision,
        settlementRevision=settlementRevision
    }
    r.nextCycle=r.nextCycle+1
    store.revision=store.revision+1
    return r.activeCycle
end

function StockStore.attachCycle(ruleId,taskId)
    local store=StockStore.data()
    local r=store.rules[ruleId]
    if not r or not r.activeCycle or r.activeCycle.taskId~=taskId or r.activeCycle.phase~="PREPARED" then
        return false,"INVALID_ATTACH"
    end
    r.activeCycle.phase="ATTACHED"
    store.revision=store.revision+1
    return true
end

function StockStore.abortPrepared(ruleId,taskId)
    local store=StockStore.data()
    local r=store.rules[ruleId]
    if not r or not r.activeCycle or r.activeCycle.taskId~=taskId or r.activeCycle.phase~="PREPARED" then
        return false
    end
    r.activeCycle=nil
    if r.deleting then
        store.rules[ruleId]=nil
    end
    store.revision=store.revision+1
    return true
end

function StockStore.settleCycle(ruleId,taskId,outcome)
    local store=StockStore.data()
    local r=store.rules[ruleId]
    if not r or not r.activeCycle or r.activeCycle.taskId~=taskId then
        return false,"CYCLE_NOT_FOUND"
    end
    if outcome=="DONE" or outcome=="CANCELLED" then
        r.activeCycle=nil
        if r.deleting then
            store.rules[ruleId]=nil
        end
        store.revision=store.revision+1
        return true
    elseif outcome=="RECONCILE_REQUIRED" then
        r.activeCycle.phase="RECONCILE_REQUIRED"
        store.revision=store.revision+1
        return true
    end
    return false,"INVALID_OUTCOME"
end

return StockStore
