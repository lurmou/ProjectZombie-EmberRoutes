-- Background stock maintenance service.
-- Bounded evaluation, lifecycle scheduling, and settlement warehouse synchronization.
local Probe=require "EmberRoutesProbe/Boot"
local StockStore=require "EmberRoutesProbe/StockStore"
local StockRule=require "EmberRoutesProbe/StockRule"
local Ledger=require "EmberRoutesProbe/SettlementLedger"
local Index=require "EmberRoutesProbe/WarehouseIndex"
local Registry=require "EmberRoutesProbe/ContainerRegistry"
local Production=require "EmberRoutesProbe/Production"
local Recipe=require "EmberRoutesProbe/ProductionRecipe"
local Surfaces=require "EmberRoutesProbe/CraftSurfaces"
local Driver=require "EmberRoutesProbe/Driver"
local Work=require "EmberRoutesProbe/Work"
local Signals=require "EmberRoutesProbe/LaborSignals"
local Membership=require "EmberRoutesProbe/SettlementMembership"
local Log=require "EmberRoutesProbe/Log"
local Runtime=require 'EmberRoutesProbe/TaskRuntime'

local StockService={}

local watchers={}         -- settlementId -> unwatch function
local dirtyRules={}       -- ruleId -> true
local ruleQueue={}        -- array of ruleId
local ruleStates={}       -- ruleId -> cached status object
local lastEvaluated={}    -- ruleId -> gameSeconds
local overlapCache={}     -- fullType -> boolean (is overlapping)
local overlapChecked=0    -- gameSeconds
local pausedForSave=false
local subscribers={}      -- token -> callback
local queuedCycles={}     -- transient admission receipts; never persisted

local function gameSeconds()
    if getGameTime and getGameTime() then
        return getGameTime():getWorldAgeHours()*3600
    end
    if getTimestampMs then
        return getTimestampMs()/1000
    end
    return 0
end

local function isPaused()
    if UIManager and UIManager.isGamePaused and UIManager.isGamePaused() then return true end
    if getGameTime and getGameTime() and getGameTime().getTrueMultiplier and getGameTime():getTrueMultiplier()==0 then return true end
    return false
end

local function notifySubscribers(settlementId)
    local snapshot=StockService.status(nil,settlementId)
    local dead={}
    for token,cb in pairs(subscribers) do
        if not token.settlementId or token.settlementId==settlementId then
            local ok,err=pcall(cb,snapshot)
            if not ok then dead[#dead+1]=token Log.write("STOCK","SUBSCRIBER_ERROR "..tostring(err)) end
        end
    end
    for _,token in ipairs(dead) do subscribers[token]=nil end
end

function StockService.markDirty(ruleId)
    if ruleId then
        dirtyRules[ruleId]=true
    else
        for _,r in ipairs(StockStore.list()) do dirtyRules[r.id]=true end
    end
end

local function syncWatchers()
    local needed={}
    local all=StockStore.list()
    for _,r in ipairs(all) do
        if r.enabled or r.activeCycle~=nil then
            needed[r.settlementId]=true
        end
    end
    -- Add missing watchers
    for sId in pairs(needed) do
        if not watchers[sId] then
            local unwatch=Index.watch(sId,function(snapshot)
                if snapshot.state=="READY" then
                    for _,r in ipairs(StockStore.list(sId)) do dirtyRules[r.id]=true end
                    notifySubscribers(sId)
                end
            end)
            if unwatch then watchers[sId]=unwatch end
        end
    end
    -- Remove unneeded watchers
    for sId,unwatch in pairs(watchers) do
        if not needed[sId] then
            unwatch()
            watchers[sId]=nil
        end
    end
end

-- Checks if two settlements with enabled rules for the same product share any container
local function checkOverlap(fullType)
    local now=gameSeconds()
    if now-overlapChecked<5 and overlapCache[fullType]~=nil then
        return overlapCache[fullType]
    end
    overlapChecked=now

    local settlementsWithRule={}
    for _,r in ipairs(StockStore.list()) do
        if r.fullType==fullType and r.enabled and not r.deleting then
            settlementsWithRule[r.settlementId]=true
        end
    end

    local count=0
    local sList={}
    for sId in pairs(settlementsWithRule) do count=count+1 sList[#sList+1]=sId end
    if count<=1 then
        overlapCache[fullType]=false
        return false
    end

    -- Compare container ID sets between settlements
    local seenContainers={}
    for _,sId in ipairs(sList) do
        local entry=Ledger.data().entries[sId]
        if entry then
            local members=Membership.query(entry) or {}
            for _,cId in ipairs(members) do
                if seenContainers[cId] and seenContainers[cId]~=sId then
                    overlapCache[fullType]=true
                    return true
                end
                seenContainers[cId]=sId
            end
        end
    end

    overlapCache[fullType]=false
    return false
end

-- Early settle check for in-flight production order
function StockService.checkEarlySettle(c)
    local r=c.record
    if not r or not r.origin or r.origin.kind~="MAINTAIN_STOCK" then return false end
    local ruleId=r.origin.ruleId
    local rule=StockStore.get(ruleId)
    if not rule or rule.deleting or not rule.enabled then
        return true -- Early settle if rule removed or disabled
    end

    local cand=Index.candidates(c.actor,r.settlementId,{fullType=r.product,limit=1})
    if cand and cand.state=="READY" and cand.complete then
        local P=cand.knownCount or 0
        if P>=rule.minimum then
            Log.write("STOCK","EARLY_SETTLE rule="..ruleId.." P="..P.." target="..rule.minimum)
            return true
        end
    end
    return false
end
Production.earlySettleCheck=StockService.checkEarlySettle

-- Evaluates a single rule and dispatches if needed
local function evaluateRule(actor,r)
    local now=gameSeconds()
    lastEvaluated[r.id]=now
    dirtyRules[r.id]=nil

    -- If active cycle is running, check if production order finished
    if r.activeCycle then
        local cycle=r.activeCycle
        local probeRecord=require('EmberRoutesProbe/BusinessJobs').crafts()[r.npcId]
        if probeRecord and probeRecord.id==cycle.taskId then
            if cycle.phase=='PREPARED' then StockStore.attachCycle(r.id,cycle.taskId) end
            queuedCycles[r.id]=nil
            if probeRecord.released then
                local outcome=probeRecord.state=="CANCELLED" and "CANCELLED" or "DONE"
                StockStore.settleCycle(r.id,cycle.taskId,outcome)
                Index.refresh(r.settlementId,false)
                ruleStates[r.id]={state="SETTLED",reason="CYCLE_CONCLUDED",rule=r}
                return true
            elseif probeRecord.uncertain or probeRecord.phase=="RECONCILE_REQUIRED" then
                StockStore.settleCycle(r.id,cycle.taskId,"RECONCILE_REQUIRED")
                ruleStates[r.id]={state="RECONCILE_REQUIRED",reason="RECONCILE_REQUIRED",rule=r}
                return false
            else
                ruleStates[r.id]={state="RESTOCKING",reason="CYCLE_ACTIVE",rule=r,taskId=cycle.taskId}
                return false
            end
        elseif cycle.phase=="PREPARED" then
            local queued=queuedCycles[r.id]
            if queued and queued.root==Registry.data() and queued.taskId==cycle.taskId then
                local state=queued.runtime:inspect(queued.handle)
                if r.deleting or not r.enabled then queued.runtime:stopJob(r.npcId,cycle.taskId,'STOCK_RULE_CHANGED')
                elseif state and (state.state=='PENDING' or state.state=='QUEUED' or state.state=='ACTIVE' or state.state=='STOPPING') then
                    ruleStates[r.id]={state='RESTOCKING',reason='QUEUED',rule=r,taskId=cycle.taskId}
                    return false
                end
            end
            queuedCycles[r.id]=nil
            -- Orphan PREPARED cycle without a production record; abort to prevent permanent deadlock
            StockStore.abortPrepared(r.id,cycle.taskId)
            ruleStates[r.id]={state="WAIT_INVENTORY",reason="CYCLE_PREPARED_RECOVERED",rule=r}
            return false
        else
            -- Cycle lost or completed without probe record
            StockStore.settleCycle(r.id,cycle.taskId,"DONE")
            Index.refresh(r.settlementId,false)
            return true
        end
    end

    if r.deleting then
        ruleStates[r.id]={state="DELETING",reason="RULE_DELETING",rule=r}
        return false
    end
    if not r.enabled then
        ruleStates[r.id]={state="DISABLED",reason="RULE_DISABLED",rule=r}
        return false
    end

    -- Multi-settlement scope overlap guard
    if checkOverlap(r.fullType) then
        ruleStates[r.id]={state="SCOPE_OVERLAP",reason="CONTAINER_OVERLAP",rule=r}
        return false
    end

    -- Query inventory
    local cand=Index.candidates(actor,r.settlementId,{fullType=r.fullType,limit=1})
    local inventory={
        state=cand and cand.state or "UPDATING",
        complete=cand and cand.complete==true or false,
        count=cand and cand.knownCount or 0
    }

    -- Query existing manual root orders
    local orders=Production.findRootOrders(r.settlementId,r.fullType)

    -- Recipe yield
    local spec=Recipe.read(r.recipeId)
    local yield=spec and spec.yield or 1

    local eval=StockRule.evaluate(r,inventory,orders,yield)
    ruleStates[r.id]={
        state=eval.state,
        reason=eval.reason,
        rule=r,
        knownCount=eval.knownCount or inventory.count,
        minimum=r.minimum,
        deficit=eval.deficit or 0,
        requested=eval.requested or 0,
        target=eval.target or 0
    }

    if eval.state~="DEFICIT" then
        return false
    end

    -- State is DEFICIT: verify NPC availability before attempting dispatch
    local binding=Driver.bindId(actor,r.npcId)
    if not binding or not binding.handle then
        ruleStates[r.id].state="WAIT_WORKER"
        ruleStates[r.id].reason="WORKER_UNAVAILABLE"
        return false
    end
    local npc=binding.handle
    if npc:isDead() or npc:getBodyDamage():getOverallBodyHealth()<95 then
        ruleStates[r.id].state="WAIT_WORKER"
        ruleStates[r.id].reason="WORKER_INJURED"
        return false
    end
    if Production.busy(r.npcId) or Work.busy(r.npcId) then
        ruleStates[r.id].state="WAIT_WORKER"
        ruleStates[r.id].reason="WORKER_BUSY"
        return false
    end
    if not npc:getCharacterActions():isEmpty() then
        ruleStates[r.id].state="WAIT_WORKER"
        ruleStates[r.id].reason="NATIVE_ACTION_BUSY"
        return false
    end

    -- Resolve crafting surface if required
    local surfaceObj
    if spec and spec.surface then
        if not r.surfaceId then
            ruleStates[r.id].state="WAIT_SURFACE"
            ruleStates[r.id].reason="SURFACE_REQUIRED"
            return false
        end
        local surfacePos=(Registry.data().craftSurfaces or {})[r.surfaceId]
        if not surfacePos then
            ruleStates[r.id].state="WAIT_SURFACE"
            ruleStates[r.id].reason="SURFACE_NOT_FOUND"
            return false
        end
        local resolved,why=Surfaces.resolve(surfacePos,r.surfaceId)
        if not resolved then
            ruleStates[r.id].state="WAIT_SURFACE"
            ruleStates[r.id].reason=why or "SURFACE_UNAVAILABLE"
            return false
        end
        surfaceObj=resolved
    end

    -- Prepare cycle atomically
    local taskId=Registry.id()
    local prepOk,prepErr=StockStore.prepareCycle(r.id,taskId,eval.requested,cand and cand.revision,cand and cand.settlementRevision)
    if not prepOk then
        Log.write("STOCK","PREPARE_CYCLE_FAILED rule="..r.id.." why="..tostring(prepErr))
        return false
    end

    -- Dispatch to Production
    local options={
        taskId=taskId,
        recipeId=r.recipeId,
        quantity=eval.requested,
        chain=true,
        nonPreemptive=true,
        settlementId=r.settlementId,
        origin={kind="MAINTAIN_STOCK",ruleId=r.id,cycleSequence=prepOk.sequence}
    }
    local result,handle=Production.execute(actor,"run",surfaceObj,r.npcId,options)
    if result=='QUEUED' and handle then
        local runtime=Runtime.current()
        queuedCycles[r.id]={root=Registry.data(),taskId=taskId,handle=handle,runtime=runtime}
        ruleStates[r.id]={state='RESTOCKING',reason='QUEUED',rule=r,taskId=taskId}
        return true
    end
    if result=="STARTED" then
        StockStore.attachCycle(r.id,taskId)
        ruleStates[r.id]={state="RESTOCKING",reason="DISPATCHED",rule=r,taskId=taskId}
        Log.write("STOCK","CYCLE_STARTED rule="..r.id.." task="..taskId.." qty="..eval.requested)
        return true
    else
        StockStore.abortPrepared(r.id,taskId)
        ruleStates[r.id]={state="WAIT_WORKER",reason=result,rule=r}
        Log.write("STOCK","DISPATCH_REJECTED rule="..r.id.." reason="..tostring(result))
        return false
    end
end

-- Tick hook: executes bounded evaluations per tick
function StockService.tick()
    if Probe.publicDispatch then return end -- Legacy fixed-NPC rules never dispatch.
    if isPaused() or pausedForSave then return end
    syncWatchers()

    local actor=getSpecificPlayer and getSpecificPlayer(0)
    if not actor then return end

    local now=gameSeconds()
    local allRules=StockStore.list()

    -- Enqueue dirty rules or low-frequency waiting rules (60s throttle)
    for _,r in ipairs(allRules) do
        local last=lastEvaluated[r.id] or 0
        if dirtyRules[r.id] or (now-last>=60) then
            dirtyRules[r.id]=true
            local found=false
            for _,qId in ipairs(ruleQueue) do if qId==r.id then found=true break end end
            if not found then ruleQueue[#ruleQueue+1]=r.id end
        end
    end

    -- Bounded tick: max 4 rules evaluated, max 1 order dispatched
    local evaluatedCount=0
    local dispatchedCount=0

    while #ruleQueue>0 and evaluatedCount<4 do
        local ruleId=table.remove(ruleQueue,1)
        local rule=StockStore.get(ruleId)
        if rule then
            evaluatedCount=evaluatedCount+1
            local dispatched=evaluateRule(actor,rule)
            if dispatched then
                dispatchedCount=dispatchedCount+1
                if dispatchedCount>=1 then break end
            end
        end
    end
end

-- Save barrier: pauses dispatch before saving
function StockService.beforeSave()
    pausedForSave=true
end

-- Resume after save
function StockService.afterSave()
    pausedForSave=false
    StockService.markDirty()
end

-- Reset on world exit/load
function StockService.reset()
    for _,unwatch in pairs(watchers) do unwatch() end
    watchers={}
    dirtyRules={}
    ruleQueue={}
    ruleStates={}
    lastEvaluated={}
    overlapCache={}
    overlapChecked=0
    pausedForSave=false
    subscribers={}
    queuedCycles={}
end

-- Status query / subscription for UI
function StockService.status(actor,settlementId)
    local rules=StockStore.list(settlementId)
    local list={}
    for _,r in ipairs(rules) do
        local st=ruleStates[r.id] or {state="WAIT_INVENTORY",reason="PENDING_EVALUATION",rule=r}
        list[#list+1]={
            id=r.id,
            settlementId=r.settlementId,
            fullType=r.fullType,
            recipeId=r.recipeId,
            recipeSignature=r.recipeSignature,
            npcId=r.npcId,
            surfaceId=r.surfaceId,
            minimum=r.minimum,
            enabled=r.enabled,
            revision=r.revision,
            deleting=r.deleting,
            activeCycle=r.activeCycle,
            state=st.state,
            reason=st.reason,
            knownCount=st.knownCount or 0,
            deficit=st.deficit or 0,
            requested=st.requested or 0,
            target=st.target or 0
        }
    end
    table.sort(list,function(a,b) return a.id<b.id end)
    return {settlementId=settlementId,rules=list}
end

function StockService.watch(actor,settlementId,callback)
    local token={actor=actor,settlementId=settlementId}
    subscribers[token]=callback
    StockService.markDirty()
    pcall(callback,StockService.status(actor,settlementId))
    return function() subscribers[token]=nil end
end

-- Wire signals and events
Signals.watch(function() StockService.markDirty() end)
Registry.listeners[#Registry.listeners+1]=function() StockService.markDirty() end
if Registry.inventoryListeners then
    Registry.inventoryListeners[#Registry.inventoryListeners+1]=function() StockService.markDirty() end
end

local tickEvent=Events.OnTickEvenPaused or Events.OnTick
if tickEvent then tickEvent.Add(StockService.tick) end
-- Persistence owns ordering; independent OnSave listeners could pause AFTER resume.
Probe.beforeStockSave,Probe.afterStockSave,Probe.resetStock=StockService.beforeSave,StockService.afterSave,StockService.reset

return StockService
