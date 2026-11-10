-- One ordinary-work selector/claim coordinator. Providers discover/evaluate;
-- TaskRuntime alone grants bodies and LaborStore alone grants physical assets.
local Registry=require 'EmberRoutesProbe/Warehouse/ContainerRegistry'
local Ledger=require 'EmberRoutesProbe/Settlement/SettlementLedger'
local Geometry=require 'EmberRoutesProbe/Settlement/SettlementGeometry'
-- Posting filter for decide, loaded here so decide never loads it mid-tick.
-- MembershipPosting only loads SettlementZones and ContainerRegistry, so
-- this adds no load cycle with PublicWork.
local PostingFilter=require 'EmberRoutesProbe/Settlement/MembershipPosting'
local Driver=require 'EmberRoutesProbe/Runtime/Driver'
local Runtime=require 'EmberRoutesProbe/Runtime/TaskRuntime'
local Work=require 'EmberRoutesProbe/Work/Work'
local Companion=require 'EmberRoutesProbe/Settlement/Companion'
local Production=require 'EmberRoutesProbe/Crafting/Production'
local Recipe=require 'EmberRoutesProbe/Crafting/ProductionRecipe'
local Surfaces=require 'EmberRoutesProbe/Crafting/CraftSurfaces'
local Signals=require 'EmberRoutesProbe/Work/LaborSignals'
local Selector=require 'EmberRoutesProbe/Work/WorkSelector'
local NeedsObserver=require 'EmberRoutesProbe/SelfCare/NeedsObserver'
local NeedsPolicy=require 'EmberRoutesProbe/SelfCare/NeedsPolicy'
local Directory=require 'EmberRoutesProbe/Kernel/TaskDirectory'
local Providers=require 'EmberRoutesProbe/Work/PublicWorkProviders'
-- Persisted order document and its schema checks, kept apart from the scheduler
-- so domain code can read orders without depending on dispatch internals.
local OrderStore=require 'EmberRoutesProbe/Work/OrderStore'
-- Read-only order projection; the command side below forwards to it.
local OrderQuery=require 'EmberRoutesProbe/Work/OrderQuery'
local Log=require 'EmberRoutesProbe/Kernel/Log'
local Probe=require 'EmberRoutesProbe/Kernel/Boot'
local TaskJobs=require 'EmberRoutesProbe/Runtime/TaskJobs'
local JobStore=require 'EmberRoutesProbe/Kernel/JobStore'
local Metrics=require 'EmberRoutesProbe/Kernel/DispatchMetrics'
local Wake=require 'EmberRoutesProbe/Runtime/PlanningWake'
local Config=require 'EmberRoutesProbe/Kernel/TickConfig'
local Constants=require 'EmberRoutesProbe/Kernel/Constants'
local Perf=require 'EmberRoutesProbe/Kernel/RuntimeMetrics'
local Gate=require 'EmberRoutesProbe/Kernel/RuntimeGate'
-- Load order only: these provider trees have loaded here since before the
-- manifest; moving them would reorder module load side effects (unverified).
require 'EmberRoutesProbe/Hauling/HaulingProvider'
require 'EmberRoutesProbe/Crafting/CraftingProvider'
local IdleDiscovery=require 'EmberRoutesProbe/Work/IdleDiscovery'
local CraftYield=require 'EmberRoutesProbe/Crafting/ProductionYield'
local idle=IdleDiscovery.new()
local catalogEpoch,retryWake,idleStudyTargets={},{},{}
local Service={}
local world,data,directory,cursor,nextTick,orderCursor=nil,nil,nil,0,0,0
-- Per-worker decision failures. Declared here because load() resets it.
local workerFaults={}
local nextPrecheck,nextWake,observedWake,dispatchDirty=0,0,nil,true
-- The wake counter costs a bridge call per read; polling it at the same cadence
-- as the dirty-driven wake path loses nothing, since that path waits 100 ms anyway.
local nextWakePoll=0
-- Previous pass produced work or ran live prechecks. Drives the adaptive
-- discovery period; a quiet settlement does not need 500 ms scanning.
local discoveryActive=false
-- Provider advance eligibility, decided on discovery passes and held between them.
local providerDue=false
-- Responsibility sync and policy checks keep their own cadence instead of
-- riding every discovery frame.
local nextReconcile,nextStock=0,0
local discoverName={}
-- Per-worker decision phase. A stable id hash spreads decision due times across
-- the discovery window, so one frame no longer runs several full provider
-- scans back to back. That concentration, not the per-scan cost, is what
-- produced the multi-hundred-millisecond peaks.
local decideAt,decidePhase={},{}
local function decidePhaseMs(id)
    local phase=decidePhase[id]
    if phase then return phase end
    local acc=0
    for i=1,#id do acc=(acc*31+string.byte(id,i))%100003 end
    phase=acc%Config.discoveryMs
    decidePhase[id]=phase
    return phase
end
local Business,Members
local function business()
    Business=Business or require 'EmberRoutesProbe/Work/BusinessJobs'
    return Business
end
local workerBackoff={}
if Signals.watch then
    Signals.watch(function(id)
        dispatchDirty=true
        if id then idle:clear(id) workerBackoff[id]=nil else workerBackoff={} end
    end)
end
-- hauling state encapsulated in HaulingProvider
local stockWatches,ruleCursor={},0
local retryAt={}
local metrics=Metrics.new()
local readyWorkers={}
local tickOps,tickSlices=0,0
-- A single failed pass isolates this world for a short cooldown and then
-- retries; only repeated consecutive failures lock dispatch for good. Locking
-- on the first exception turned one transient fault into a permanent outage.
local FAULT_RETRY_MS,FAULT_LIMIT=1000,5
local faultWorld,faultUntil
local faultCount=0
local leisureStops,careWaking={},{}
local pendingReservations={}
-- NPC sleep (P0 pilot, cross-game Factorio §1.3): sleeping[npcId] records
-- a quiet NPC's recheck time, entry stamp and discovery watch. A sleeping
-- NPC skips only the provider discovery pass; the gates above decide and
-- advanceReservations still run every pass. wakeSignal captures the
-- dispatch-dirty flag at advance() entry (advance clears it before the
-- decision loop), so a labor signal since the last pass wakes sleepers.
local sleeping={}
local wakeSignal=false
-- Wake predicate offers: every need kind counts, at its unchanged
-- NeedsPolicy enter threshold (choose() never reads warn). A missing or
-- unreadable sample fails open and wakes, never sleeps.
local WAKE_OFFERS={MEDICAL=true,EAT=true,DRINK=true,REST=true,SLEEP=true}
-- Enabled-rule projection with a stable id order; rebuilt only when the rule
-- set changes (saveRule bumps the revision) or the world root is replaced.
local rulesCache={world=nil,revision=-1,list={}}
local rulesRevision=0
local function load()
    local root=Registry.data()
    if root~=world then
        for _,release in pairs(stockWatches) do release() end stockWatches={} ruleCursor=0
        idle=IdleDiscovery.new() catalogEpoch,retryWake,idleStudyTargets={},{},{}
        data=OrderStore.load(root)
        world=root directory=Directory.new()
        Providers.resetWorld()
        retryAt={} leisureStops={} careWaking={} pendingReservations={} sleeping={} faultWorld=nil faultUntil=nil faultCount=0
        metrics=Metrics.new() readyWorkers={}
        cursor,nextTick,orderCursor=0,0,0
        nextPrecheck,nextWake,observedWake,dispatchDirty=0,0,nil,true
        nextWakePoll=0 discoveryActive=false providerDue=false workerFaults={}
        nextReconcile,nextStock=0,0
        decideAt,decidePhase={},{} workerBackoff={} Members=nil
    end
    return data
end
function Service.prepareRecovery() load() end
-- Bounded intent receipts, not work history. Unknown/evicted tokens cannot be
-- replayed as a new order. Active orders remain independently idempotent.
function Service.requestId()
    local requests=load().requests local id=Registry.id()
    requests[#requests+1]={requestId=id}
    if #requests>128 then table.remove(requests,1) end
    return id
end
local function requestFor(id)
    for _,r in ipairs(load().requests) do if r.requestId==id then return r end end
end
local function sameRequest(o,scope,recipeId,quantity,surfaceId)
    return o.settlementId==scope and o.recipeId==recipeId and o.quantity==quantity and o.surfaceId==surfaceId
end
function Service.available()
    if faultWorld==Registry.data() then return false,'DISPATCH_BLOCKED' end
    -- During the cooldown the dispatcher is isolated too, so public mutation
    -- stays blocked even though the world has not been locked permanently.
    if faultUntil and getTimestampMs()<faultUntil then return false,'DISPATCH_BLOCKED' end
    if not Probe.ready or not Probe.runtimeReady then return false,Probe.failureCode or 'ADMISSION_CLOSED' end
    return true
end
function Service.rule(scope,product)
    local r=load().rules[scope..':'..product] if not r then return nil end
    local copy={} for k,v in pairs(r) do copy[k]=v end return copy
end
local function signal(o,reason)
    if reason~=o.reason then o.reason=reason o.revision=o.revision+1 Signals.changed() end
end
local function signalRule(rule,reason)
    if rule.reason~=reason then rule.reason=reason Signals.changed() end
end
-- A policy cycle is a live demand only once its Order exists, not when the
-- threshold is merely configured. Ordinary manual orders remain independent.
-- Share the existing demand clock; no second order directory or suppression store.
function Service.nextDemandSequence()
    local store=load()
    store.sequence=store.sequence+1
    return store.sequence
end
function Service.deliveryOverlapReason(o,line) return OrderQuery.deliveryOverlapReason(o,line) end
function Service.outputOverlapReason(orderId,fullType,destinationId) return OrderQuery.outputOverlapReason(orderId,fullType,destinationId) end
function Service.overlapReason(id) return OrderQuery.overlapReason(id) end
-- Public craft/stock demand has no chosen box until its real output assets do.
-- Never infer a destination from product type or the set of accepting boxes.
function Service.rules(scope)
    local list={}
    for _,r in pairs(load().rules) do if r.settlementId==scope then list[#list+1]=Service.rule(scope,r.product) end end
    return list
end
function Service.categories() return Providers.categories() end
function Service.registerProvider(def) return Providers.register(def) end
function Service.provider(category) return Providers.get(category) end
function Service.priorities(npcId) return OrderQuery.priorities(npcId) end
function Service.setPriorities(actor,scope,npcId,values,revision)
    local available,blocked=Service.available() if not available then return blocked end
    local entry,reason=Ledger.view(actor,scope) if not entry then return reason end
    local binding=Driver.bindId(actor,npcId)
    if not binding or not Geometry.inside(entry,binding.handle:getX(),binding.handle:getY()) then return 'NPC_OUTSIDE_SETTLEMENT' end
    if type(values)~='table' then return 'INVALID_PRIORITY' end
    -- Providers declaring priorityRequired must be present; every other key is
    -- optional. One pass per shape, no value validated twice.
    for _,p in ipairs(Providers.all()) do
        if p.priorityRequired then
            local value=values[p.category]
            if type(value)~='number' or value~=math.floor(value) or value<Constants.Priority.MIN or value>Constants.Priority.MAX then return 'INVALID_PRIORITY' end
        end
    end
    for k,value in pairs(values) do
        local p=Providers.get(k)
        if k~='revision' and not (p and p.priorityRequired) then
            if type(value)~='number' or value~=math.floor(value) or value<Constants.Priority.MIN or value>Constants.Priority.MAX then return 'INVALID_PRIORITY' end
        end
    end
    local previous=Service.priorities(npcId) if previous.revision~=revision then return 'PRIORITY_CHANGED' end
    local nextP={revision=revision+1}
    for _,cat in ipairs(Providers.categories()) do
        nextP[cat]=values[cat]~=nil and values[cat] or previous[cat]
    end
    for k,v in pairs(values) do
        if k~='revision' and nextP[k]==nil then nextP[k]=v end
    end
    load().priorities[npcId]=nextP
    if Probe.invalidateStudy then Probe.invalidateStudy(scope,npcId) end
    Signals.changed(npcId) return 'PRIORITY_SAVED'
end
function Service.setPriority(actor,scope,npcId,category,value)
    local entry,reason=Ledger.view(actor,scope) if not entry then return reason end
    if not Providers.has(category) or type(value)~='number' or value~=math.floor(value) or value<Constants.Priority.MIN or value>Constants.Priority.MAX then return 'INVALID_PRIORITY' end
    local binding=Driver.bindId(actor,npcId)
    if not binding or not Geometry.inside(entry,binding.handle:getX(),binding.handle:getY()) then return 'NPC_OUTSIDE_SETTLEMENT' end
    -- priorities() returns a shared read-only projection; copy before editing.
    local current=Service.priorities(npcId)
    local p={}
    for k,v in pairs(current) do p[k]=v end
    p[category]=value
    return Service.setPriorities(actor,scope,npcId,p,current.revision)
end
local function createOrder(actor,scope,recipeId,quantity,surfaceId,requestId,preferences,parent)
    local available,blocked=Service.available() if not available then return blocked end
    local entry,reason=Ledger.view(actor,scope) if not entry then return reason end
    if type(requestId)~='string' or requestId=='' or #requestId>256 then return 'REQUEST_ID_REQUIRED' end
    if type(quantity)~='number' or quantity~=math.floor(quantity) or quantity<1 or quantity>9999 then return 'INVALID_QUANTITY' end
    local cooking=require('EmberRoutesProbe/Cooking/CookingOrders').describe(recipeId)
    local spec=cooking
    local why
    if not spec then spec,why=Recipe.read(recipeId) end
    if not spec then return why end
    -- Deliberate asymmetry: cooking demand is not gated on the player's recipe
    -- knowledge (evolved recipes have no player-knowledge concept, and NPC
    -- learning is the study system's job). Craft orders gate because the
    -- player commissions one specific recipe.
    if not cooking and not parent and not actor:isRecipeKnown(spec.recipe,true) then return 'PLAYER_RECIPE_UNKNOWN' end
    local surface
    if spec.surface then
        if surfaceId then
            local saved=(Registry.data().craftSurfaces or {})[surfaceId]
            if not saved or not Geometry.inside(entry,saved.x,saved.y) then return 'CRAFT_SURFACE_REQUIRED' end
            surface,why=Surfaces.resolve(saved,surfaceId) if not surface then return why end
        else
            surfaceId=nil
        end
    else surfaceId=nil end
    local store=load()
    for _,o in pairs(store.orders) do
        if o.requestId==requestId then
            if not sameRequest(o,scope,recipeId,quantity,surfaceId) then return 'REQUEST_CONFLICT' end
            return 'ORDER_CREATED',o.id
        end
    end
    local request=requestFor(requestId)
    if not request then return 'REQUEST_EXPIRED' end
    if request.orderId then
        if not sameRequest(request,scope,recipeId,quantity,surfaceId) then return 'REQUEST_CONFLICT' end
        return 'ORDER_CREATED',request.orderId
    end
    local count=0 for _ in pairs(store.orders) do count=count+1 end
    if count>=256 then return 'ORDER_LIMIT' end
    store.sequence=store.sequence+1 local id=Registry.id()
    store.orders[id]={id=id,requestId=requestId,settlementId=scope,requester=actor:getUsername(),recipeId=recipeId,
        name=spec.name,product=spec.product,quantity=quantity,target=math.ceil(quantity/spec.yield)*spec.yield,
        surfaceId=surfaceId,sequence=store.sequence,revision=1,state='WAITING',reason='WAITING_CLAIM',preferences=preferences,
        category=cooking and 'cooking' or nil,delivered=cooking and 0 or nil,parentOrderId=parent and parent.id}
    OrderQuery.invalidate()
    catalogEpoch[scope]=(catalogEpoch[scope] or 0)+1
    if Probe.invalidateStudy then Probe.invalidateStudy(scope) end
    Signals.changed() return 'ORDER_CREATED',id
end
function Service.create(actor,scope,recipeId,quantity,surfaceId,requestId,preferences)
    return createOrder(actor,scope,recipeId,quantity,surfaceId,requestId,preferences)
end
-- Called only after the existing bounded BOM found an executable route. One
-- associated demand at a time; its executor owns its own originals and cleanup.
function Service.createPrerequisite(actor,parentId,node)
    local parent=load().orders[parentId]
    if not parent or parent.category~='cooking' or parent.state~='WAITING' or parent.jobId
        or parent.pauseRequested or parent.cancelRequested then return 'TASK_CHANGED' end
    local child=parent.prerequisiteId and data.orders[parent.prerequisiteId]
    if child and child.state~='DONE' and child.state~='CANCELLED' then return 'ORDER_CREATED',child.id end
    if type(node)~='table' or node.recipeId==parent.recipeId then return 'CHAIN_CYCLE' end
    -- A player-cancelled prerequisite for this same node is a decision, not
    -- a gap to refill: never recreate it silently. The parent stalls with
    -- this reason until the player resumes the parent (clears the link) or
    -- cancels it. A different current node is a different need and proceeds.
    if child and child.state=='CANCELLED' and child.recipeId==node.recipeId then return 'PREREQUISITE_CANCELLED',child.id end
    -- A fresh receipt is allocated only when no active predecessor remains.
    local result,id=createOrder(actor,parent.settlementId,node.recipeId,node.requested,node.benchId,
        Service.requestId(),parent.preferences,parent)
    if result=='ORDER_CREATED' then parent.prerequisiteId=id parent.revision=parent.revision+1 end
    return result,id
end
function Service.createDeliveryOrder(actor,scope,items,requestId,destinationId)
    local DeliveryService=require 'EmberRoutesProbe/Logistics/DeliveryService'
    return DeliveryService.createOrder(actor,scope,items,requestId,destinationId)
end
function Service.order(id) return OrderQuery.order(id) end
function Service.orders(scope) return OrderQuery.orders(scope) end
function Service.command(actor,scope,id,revision,action)
    local available,blocked=Service.available() if not available then return blocked end
    local entry,reason=Ledger.view(actor,scope) if not entry then return reason end
    local o=load().orders[id]
    if not o or o.settlementId~=scope or o.revision~=revision then return 'TASK_CHANGED' end
    -- An order whose category names a provider with its own command is handled
    -- there entirely; the rest (no category) are public craft orders, below.
    local owner=o.category and Providers.get(o.category)
    if owner and owner.command then return owner.command(o,action) end
    if o.jobId then return 'ORDER_ALREADY_CLAIMED' end
    if o.state=='CANCELLED' or o.state=='DONE' then return 'TASK_CHANGED' end
    if action=='return' then o.state='CANCELLED' directory:withdraw('craft:'..id)
    elseif action=='stop' then o.state='PAUSED' directory:withdraw('craft:'..id)
    elseif action=='resume' and o.state=='PAUSED' then o.state='WAITING'
    else return 'INVALID_COMMAND' end
    Providers.orderCommanded(id)
    if Probe.invalidateStudy then Probe.invalidateStudy(scope) end
    o.revision=o.revision+1 catalogEpoch[scope]=(catalogEpoch[scope] or 0)+1
    Signals.changed() return 'ORDER_UPDATED'
end
function Service.saveRule(actor,scope,recipeId,minimum,batch,surfaceId,preferences)
    local available,blocked=Service.available() if not available then return blocked end
    local entry,reason=Ledger.view(actor,scope) if not entry then return reason end
    if type(minimum)~='number' or minimum~=math.floor(minimum) or minimum<0 or minimum>9999
        or type(batch)~='number' or batch~=math.floor(batch) or batch<1 or batch>9999 then return 'INVALID_QUANTITY' end
    local cooking=require('EmberRoutesProbe/Cooking/CookingOrders').describe(recipeId)
    local spec=cooking
    local why
    if not spec then spec,why=Recipe.read(recipeId) end
    if not spec then return why end
    if not cooking and not actor:isRecipeKnown(spec.recipe,true) then return 'PLAYER_RECIPE_UNKNOWN' end
    if spec.surface then
        if surfaceId then
            local position=(Registry.data().craftSurfaces or {})[surfaceId]
            if not position or not Geometry.inside(entry,position.x,position.y) or not Surfaces.resolve(position,surfaceId) then return 'CRAFT_SURFACE_REQUIRED' end
        else
            surfaceId=nil
        end
    else surfaceId=nil end
    local rules=load().rules local key=scope..':'..spec.product
    local previous=rules[key] local count=0 for _ in pairs(rules) do count=count+1 end
    if not previous and count>=64 then return 'ORDER_LIMIT' end
    rules[key]={id=key,settlementId=scope,product=spec.product,recipeId=recipeId,minimum=minimum,batch=batch,
        enabled=minimum>0,surfaceId=surfaceId,revision=(previous and previous.revision or 0)+1,
        cycle=previous and previous.cycle or 0,activeOrder=previous and previous.activeOrder,preferences=preferences}
    rulesRevision=rulesRevision+1
    catalogEpoch[scope]=(catalogEpoch[scope] or 0)+1
    Signals.changed() return minimum>0 and 'RULE_SAVED' or 'RULE_DISABLED'
end
local function stock(actor,now)
    if rulesCache.world~=data or rulesCache.revision~=rulesRevision then
        local list={}
        for _,rule in pairs(data.rules) do if rule.enabled then list[#list+1]=rule end end
        table.sort(list,function(a,b) return a.id<b.id end)
        rulesCache.world,rulesCache.revision,rulesCache.list=data,rulesRevision,list
    end
    local rules=rulesCache.list
    local needed={}
    for _,rule in ipairs(rules) do needed[rule.settlementId]=true end
    for id,release in pairs(stockWatches) do if not needed[id] then release() stockWatches[id]=nil end end
    if #rules==0 then return end
    local Index=require 'EmberRoutesProbe/Warehouse/WarehouseIndex'
    for id in pairs(needed) do if not stockWatches[id] then
        stockWatches[id]=Index.watch(id,function() end)
    end end
    ruleCursor=ruleCursor%#rules+1 local rule=rules[ruleCursor]
    if rule.activeOrder then
        local o=data.orders[rule.activeOrder]
        if not o then signalRule(rule,'TASK_RECORD_MISSING') return end
        if o.state=='DONE' or o.state=='CANCELLED' then
            rule.activeOrder=nil rule.nextCheck=now+2000 signalRule(rule,nil) Index.refresh(rule.settlementId,false)
        else return end
    end
    if now<(rule.nextCheck or 0) then return end rule.nextCheck=now+1000
    -- Overlapping storage must not trigger two policies for the same originals.
    local Membership=require 'EmberRoutesProbe/Settlement/SettlementMembership'
    local seen={}
    for _,other in ipairs(rules) do if other.product==rule.product then
        local entry=Ledger.view(actor,other.settlementId)
        for _,id in ipairs(entry and Membership.query(entry) or {}) do
            if seen[id] and seen[id]~=other.settlementId then signalRule(rule,'CONTAINER_OVERLAP') return end
            seen[id]=other.settlementId
        end
    end end
    local observed
    if require('EmberRoutesProbe/Cooking/CookingOrders').describe(rule.recipeId) then
        observed=require('EmberRoutesProbe/Cooking/CookingService').stock(actor,rule)
    else observed=Index.candidates(actor,rule.settlementId,{fullType=rule.product,limit=1}) end
    if not observed or observed.state~='READY' or not observed.complete then signalRule(rule,'INVENTORY_UNKNOWN') return end
    rule.knownCount=observed.knownCount
    if observed.knownCount>=rule.minimum then signalRule(rule,nil) return end
    for _,o in pairs(data.orders) do
        if o.settlementId==rule.settlementId and o.product==rule.product and o.state~='DONE' and o.state~='CANCELLED' then
            signalRule(rule,'MANUAL_ORDER_ACTIVE') return
        end
    end
    local cycle=rule.cycle+1
    local result,id=Service.create(actor,rule.settlementId,rule.recipeId,rule.batch,rule.surfaceId,
        Service.requestId(),rule.preferences)
    signalRule(rule,result)
    if result=='ORDER_CREATED' then rule.cycle=cycle rule.activeOrder=id data.orders[id].policyId=rule.id end
end
local function cool(o,npcId,e,reason,now)
    local count=0 local oldest,deadline
    for id,r in pairs(retryAt) do
        count=count+1 if not deadline or r.untilTime<deadline then oldest,deadline=id,r.untilTime end
    end
    if count>=512 then retryAt[oldest]=nil end
    retryAt[o.id..':'..npcId]={untilTime=now+8000+(o.sequence or 0)%8*997,watch=e.watch,reason=reason}
end
local function retryReady(o,npcId,now)
    local r=retryAt[o.id..':'..npcId]
    if r and r.untilTime>now then retryWake[npcId]=math.min(retryWake[npcId] or math.huge,r.untilTime) end
    return not r or now>=r.untilTime or Wake.changed(r.watch)
end
local function assertRegister(def)
    local ok,err=Providers.register(def)
    if not ok then error('PROVIDER_REGISTRATION_FAILED:'..tostring(err)..':'..tostring(type(def)=='table' and def.category or '?')) end
end
for _,e in ipairs(require('EmberRoutesProbe/Work/LaborManifest').categories) do assertRegister(e.provider()) end

local function reconcile()
    for _,p in ipairs(Providers.all()) do
        if p.reconcile then p.reconcile({orders=data.orders,directory=directory,catalogEpoch=catalogEpoch,signal=signal}) end
    end
end
-- A DONE order with neither a job nor craft progress retires only when the
-- provider its category names says so (cooking settles its own jobs).
local function retiresUnclaimed(o)
    local owner=o.category and Providers.get(o.category)
    return owner and owner.retireUnclaimed and owner.retireUnclaimed(o) or false
end
function Service.retireSettled(limit)
    load()
    local any=false
    for _,p in ipairs(Providers.all()) do
        if p.hasWork and p.hasWork() then any=true break end
    end
    if not any then return 0 end
    local runtime=Runtime.current()
    if not runtime or not runtime:accepting() or world.executionSave and world.executionSave.state=='BLOCKED' then return 0 end
    reconcile()
    if not any then return 0 end -- Hauling offer release still runs without public craft orders.
    local Jobs=require 'EmberRoutesProbe/Work/BusinessJobs'
    local count=0
    for id,o in pairs(data.orders) do
        local settled=o.state=='DONE' or o.state=='CANCELLED'
        -- An unclaimed cancellation has never acquired originals. Claimed
        -- work must prove its exact Job is closed, not merely absent.
        if settled and (o.jobId and Jobs.canRetire(o.jobId,id)
            or not o.jobId and (not o.craftProgress and (o.state=='CANCELLED' or retiresUnclaimed(o))
                or o.craftProgress and (Jobs.canRetire(o.craftProgress.settledJobId,id)
                    or Jobs.record(o.craftProgress.settledJobId,'CRAFT')==nil))) then
            if not o.jobId or Jobs.retire(o.jobId,id) then
                local request=requestFor(o.requestId)
                if not request then
                    request={requestId=o.requestId} data.requests[#data.requests+1]=request
                    if #data.requests>128 then table.remove(data.requests,1) end
                end
                request.orderId,request.settlementId,request.recipeId=o.id,o.settlementId,o.recipeId
                request.quantity,request.surfaceId=o.quantity,o.surfaceId
                directory:release('craft:'..id,o.jobId,{effects='KNOWN',obligationsCleared=true})
                directory:withdraw('craft:'..id)
                for _,r in pairs(data.rules) do if r.activeOrder==id then
                    r.activeOrder=nil r.nextCheck=getTimestampMs()+2000
                    require('EmberRoutesProbe/Warehouse/WarehouseIndex').refresh(r.settlementId,false)
                end end
                Providers.orderRetired(id,readyWorkers)
                for key in pairs(retryAt) do if string.sub(key,1,#id+1)==id..':' then retryAt[key]=nil end end
                data.orders[id]=nil count=count+1
                if count>=limit then break end
            end
        end
    end
    if count>0 then OrderQuery.invalidate() Signals.changed() end
    return count
end
-- Cheap eligibility is shared by discovery and private precheck admission.
local function eligible(actor,npcId,scope)
    if require('EmberRoutesProbe/Activity/ActivityAttendance').blocksOrdinary(npcId) then return end
    local binding=Driver.bindId(actor,npcId)
    -- A parked carrier keeps its binding but must not receive new work: its
    -- world is gone. Already claimed jobs keep running on their own path.
    if binding and Driver.suspended(binding.handle) then return end
    local probing=Probe.careProbeWork and Probe.careProbeWork(npcId)
    local ToolReturnService=require 'EmberRoutesProbe/Field/ToolReturnService'
    local returningInterruptible=ToolReturnService and ToolReturnService.canInterrupt and ToolReturnService.canInterrupt(npcId)
    if not binding or not binding.handle or (Work.busy(npcId) and not returningInterruptible and not probing)
        or Probe.careBlocksWork and Probe.careBlocksWork(npcId) and not probing then return end
    if Providers.retained(npcId) then return end
    local existing=business().crafts()[npcId]
    if existing and not existing.released then return end
    local npc=binding.handle
    if not probing and not returningInterruptible and not npc:getCharacterActions():isEmpty()
        or not require('EmberRoutesProbe/SelfCare/HealthAssessment').canWork(npc) then return end
    Members=Members or require 'EmberRoutesProbe/Settlement/MembershipService'
    local M=Members
    local eligible=M.check(npcId,'WORK',{x=npc:getX(),y=npc:getY(),z=npc:getZ(),scopeId=scope})
    if not eligible.allowed then return end
    local entry=M.entry(npcId,scope)
    if not entry then return end
    return binding,entry
end
-- Stage attribution exists only while a RuntimeMetrics session is active.
-- Outside a session every wrapper is a direct call: no clock, no allocation.
local function measured(name,fn,...)
    if not Perf.active() then return fn(...) end
    local started=Perf.now()
    local a,b,c,d=fn(...)
    Perf.measureSpan(name,started)
    return a,b,c,d
end
local function cancelReservation(npcId,reason)
    local res=pendingReservations[npcId]
    if res then
        pendingReservations[npcId]=nil
        if directory then
            directory:release(res.selected.key,res.jobId,{effects='KNOWN',obligationsCleared=true})
        end
        if reason then
            cool({id=res.selected.key},npcId,{watch=Wake.capture(res.entry)},reason,getTimestampMs())
        end
    end
end
-- The one provider-claim path for direct decisions and promoted reservations.
-- A failed claim releases its offer only on the provider's rollback declaration.
local function claimSelected(actor,npcId,now,selected,jobId,entry)
    idle:clear(npcId)
    Providers.cancelPending(npcId)
    Providers.beforeClaim(selected,npcId)
    local result,declaration
    local provider=Providers.get(selected.category)
    if provider and provider.claim then
        result,declaration=provider.claim(selected,npcId,jobId,{actor=actor,entry=entry,now=now,directory=directory,
            releaseOffer=function(k,j,p) return directory:release(k,j,p) end})
    else
        -- No provider code ran for this offer, so nothing exists to roll back.
        declaration=Providers.CLAIM_ROLLED_BACK
    end
    local retained
    if result~='QUEUED' and result~='STARTED' then
        workerBackoff[npcId]=(workerBackoff[npcId] or 0)+1
        cool({id=selected.key},npcId,{watch=Wake.capture(entry)},result,now)
        retained=Providers.settleFailedClaim(directory,selected.key,jobId,declaration)
    else
        workerBackoff[npcId]=nil
        metrics.claims=metrics.claims+1
    end
    Signals.changed(npcId)
    Log.write('DISPATCH','npc='..npcId..' offer='..selected.key..' job='..jobId..' result='..tostring(result)
        ..(retained and ' OFFER_RETAINED reason='..retained or ''))
end
local function advanceReservations(now,actor)
    for npcId,res in pairs(pendingReservations) do
        local TaskJobs=require 'EmberRoutesProbe/Runtime/TaskJobs'
        local personalJob=TaskJobs and TaskJobs.current():forNpc(npcId,'SELF_CARE')[1]
        if now-res.createdAt>Config.reservationExpiryMs then
            cancelReservation(npcId,'RESERVATION_TIMEOUT')
            workerBackoff[npcId]=(workerBackoff[npcId] or 0)+1
        elseif directory and directory.isWithdrawn and directory:isWithdrawn(res.selected.key) then
            cancelReservation(npcId,'OFFER_WITHDRAWN')
        elseif personalJob and personalJob.payload and personalJob.payload.step=='ACTING'
            and personalJob.payload.kind~='LEISURE' and personalJob.payload.kind~='STUDY' then
            cancelReservation(npcId,'URGENT_SELF_CARE')
        else
            local binding,entry=eligible(actor,npcId,res.selected.scopeId or res.entry.id)
            local probing=Probe.careProbeWork and Probe.careProbeWork(npcId)
            if binding and not probing then
                pendingReservations[npcId]=nil
                -- The reservation's own entry, as before; the fresh one only gates eligibility.
                claimSelected(actor,npcId,now,res.selected,res.jobId,res.entry)
            else
                local bind=Driver.bindId(actor,npcId)
                local fatal=not bind or not bind.handle or Driver.suspended(bind.handle)
                    or (require('EmberRoutesProbe/SelfCare/HealthAssessment').canWork and not require('EmberRoutesProbe/SelfCare/HealthAssessment').canWork(bind.handle))
                    or (require('EmberRoutesProbe/Activity/ActivityAttendance').blocksOrdinary and require('EmberRoutesProbe/Activity/ActivityAttendance').blocksOrdinary(npcId))
                if fatal then
                    cancelReservation(npcId,'WORKER_FATAL_INELIGIBLE')
                else
                    dispatchDirty=true
                    nextWake=math.min(nextWake,now+Config.wakeMs)
                end
            end
        end
    end
end
-- Discovery environment for one provider scan. Built here so decide no longer
-- knows the env's field shape; fields, closures and evaluation order are
-- unchanged from the inline table it replaces.
local function newDiscoverEnv(actor,npc,npcId,entry,priorities,now,candidates,setStudyTarget)
    return {
        actor=actor,npc=npc,npcId=npcId,entry=entry,priorities=priorities,
        now=now,candidates=candidates,
        setStudyTarget=setStudyTarget,
        directory=directory,
        orders=data.orders,
        orderIds=OrderQuery.orderIds(entry.id),
        sequence=data.sequence,
        candidateReady=function(key) return retryReady({id=key},npcId,now) end,
        retryReady=retryReady,
        cool=cool,
        signal=signal,
        upsertOffer=function(key,rev,cat,scope)
            return directory:upsert(key,rev,cat,scope or entry.id)
        end
    }
end
-- Posting filter for one tier's candidates. Marks rejected candidates in
-- place and returns the updated posting reason and acceptance flag.
local function applyPostingFilter(posting,zone,candidates,postingReason,postingAccepted)
    if posting and #candidates>0 then
        for _,candidate in ipairs(candidates) do
            if candidate.allowed~=false then
                local allowed,blocked=PostingFilter.allows(posting,zone,candidate)
                if not allowed then
                    candidate.allowed=false
                    if blocked=='POSTING_TARGET_UNAVAILABLE' then postingReason=blocked end
                elseif candidate.allowed then
                    postingAccepted=true
                end
            end
        end
    end
    return postingReason,postingAccepted
end
local function decide(actor,npcId,now,binding,entry)
    if pendingReservations[npcId] then return end

    if not binding then binding,entry=eligible(actor,npcId) end
    if not binding then Providers.cancelPending(npcId) idle:clear(npcId) cancelReservation(npcId,'ELIGIBLE_FAILED') return end
    local npc=binding.handle
    if Providers.blocksDecision(actor,npcId,entry) then cancelReservation(npcId,'DECISION_BLOCKED') return end
    if Work.hasCargo(actor,npcId) then Providers.cancelPending(npcId) cancelReservation(npcId,'CARGO_INTERRUPT') return end
    if TaskJobs.current():ordinaryCount()>=JobStore.LIMIT then
	Providers.capacityBlocked(npcId,data.orders,signal)
	Providers.cancelPending(npcId) cancelReservation(npcId,'CAPACITY_BLOCKED') return
    end
    local probing=Probe.careProbeWork and Probe.careProbeWork(npcId)
    if not probing then leisureStops[npcId]=nil end
    local priorities=Service.priorities(npcId) local candidates={} local studyTarget
    local member=Members and Members.view and Members.view(npcId)
    local stamp=entry.id..':'..tostring(entry.revision)..':'..tostring(member and member.revision)
        ..':'..tostring(member and member.postingRevision)..':'..tostring(priorities.revision)..':'..tostring(catalogEpoch[entry.id] or 0)
    -- P0 pilot (cross-game RimWorld matrix): per-NPC HAUL/COOKING levels
    -- stored on the member record override the OrderStore priorities for
    -- this decision only. Only explicitly stored keys override; an unset
    -- key leaves the OrderStore value standing, and the stored table is
    -- never written here. Blank (0) means "never do this trade".
    local overrides=Members and Members.workPriorityOverrides and Members.workPriorityOverrides(npcId)
    if overrides and next(overrides) then
        local overlaid=nil
        for cat,v in pairs(overrides) do
            if v~=nil then
                if not overlaid then overlaid={} for k,x in pairs(priorities) do overlaid[k]=x end end
                overlaid[cat]=v
            end
        end
        if overlaid then priorities=overlaid end
    end
    if not Providers.hasPending(npcId) and not idle:due(npcId,now,stamp,Wake.revision and Wake.revision() or 0,Providers.discoveryChanged) then

        for _,provider in ipairs(Providers.all()) do
            if (priorities[provider.category] or 0)>0 and provider.idle then
                provider.idle(npcId,entry,idleStudyTargets[npcId])
            end
        end
        return
    end
    if retryWake[npcId] and retryWake[npcId]<=now then retryWake[npcId]=nil end

    -- P0 pilot (cross-game Sims: low needs degrade first, forced self-care
    -- second). A warn-band NPC keeps working, but HAUL drops one dispatch
    -- tier for this decision only: the stored priorities are untouched
    -- (demoted is a copy), other providers keep their tiers, and HAUL
    -- still runs when nothing else competes (no starvation, no block).
    -- Choice: dispatch deprioritization, NOT output discount -- HAUL
    -- output is physical item movement settled by LaborCommitKernel, so
    -- discounting it would change settlement accounting per trip; tier
    -- demotion is a pure ordering change at the dispatch gate. A missing
    -- or unreadable sample fails open: no demotion, no block. Forced
    -- self-care still runs on its own NeedsPolicy thresholds.
    local sample=NeedsObserver.sample(npc,npcId,now)
    -- NPC sleep (P0 pilot, cross-game Factorio §1.3): the 1Hz light
    -- recheck. A sleeper wakes when the world changed since it fell asleep
    -- (entry stamp: orders/priorities/member/catalog), a labor signal
    -- arrived, a provider precheck holds work for it, its discovery
    -- dependencies changed, its sample is unreadable (fail open), or a need
    -- crossed its unchanged enter threshold. Quiet sleepers recheck again
    -- in npcSleepRecheckMs; past npcSleepMaxMs a full discovery pass runs
    -- anyway, so no wake-condition gap can stall dispatch past the old
    -- idle-sleep bound. The gates above and advanceReservations still ran.
    if sleeping[npcId] then
        local s=sleeping[npcId]
        local wake=s.stamp~=stamp or wakeSignal or Providers.hasPending(npcId) or not sample
            or (s.watch and Providers.discoveryChanged(s.watch))
            or NeedsPolicy.choose(sample,nil,{safe=true},WAKE_OFFERS)~=nil
        if not wake and now-s.enteredAt<Config.npcSleepMaxMs then
            s.untilTime=now+Config.npcSleepRecheckMs
            return
        end
        sleeping[npcId]=nil
    end
    if sample and NeedsPolicy.warned(sample) then
        local haul=priorities.hauling
        if haul and haul>=1 and haul<4 then
            local demoted={} for k,v in pairs(priorities) do demoted[k]=v end
            demoted.hauling=haul+1
            priorities=demoted
        end
    end

    local envDiscover=newDiscoverEnv(actor,npc,npcId,entry,priorities,now,candidates,function(t) studyTarget=t end)
    -- P0 pilot (cross-game RimWorld matrix): one discovery pass over all
    -- eligible providers, ordered by effective priority ascending, then
    -- provider registration order; selection is a single global utility
    -- choose over that pool. This replaces the tier-by-tier loop (discover
    -- tier 1, stop at the first tier holding a candidate), the RimWorld
    -- "finish this priority before the next" shape: a tier-1 HAUL candidate
    -- no longer keeps lower-tier providers from being discovered at all,
    -- and same-tier candidates compete on score in one pool. One decide
    -- still dispatches at most one job; the queue is never drained here.
    -- env.priority is now each provider's own effective priority (the tier
    -- loop set it to the tier index, which was the same value per provider).
    local regIndex={}
    for i,cat in ipairs(Providers.categories()) do regIndex[cat]=i end
    local orderedProviders={}
    for _,provider in ipairs(Providers.all()) do
        local p=priorities[provider.category] or 0
        if p>=1 and p<=4 and provider.discover then orderedProviders[#orderedProviders+1]=provider end
    end
    table.sort(orderedProviders,function(a,b)
        local pa,pb=priorities[a.category] or 0,priorities[b.category] or 0
        if pa~=pb then return pa<pb end
        return (regIndex[a.category] or 0)<(regIndex[b.category] or 0)
    end)

    local posting=member and member.posting
    local zone,why=posting and PostingFilter.zone(posting,entry)
    local postingReason=why or (posting and (priorities[posting.category] or 0)==0 and 'POSTING_PRIORITY_ZERO' or 'POSTING_NO_ELIGIBLE_WORK')
    local postingAccepted=false

    local selected,jobId
    if #orderedProviders>0 then
        for _,provider in ipairs(orderedProviders) do
            envDiscover.priority=priorities[provider.category] or 0
            if Perf.active() then
                local name=discoverName[provider.category]
                if not name then name='PublicWork.discover:'..provider.category discoverName[provider.category]=name end
                measured(name,provider.discover,envDiscover)
            else
                provider.discover(envDiscover)
            end
        end

        postingReason,postingAccepted=applyPostingFilter(posting,zone,candidates,postingReason,postingAccepted)

        if #candidates>0 then
            local firstMap=OrderQuery.firstLiveByProduct()
            for _,candidate in ipairs(candidates) do
                if candidate.allowed~=false then
                    local order=candidate.order or candidate.orderId and data.orders[candidate.orderId]
                    local reason=order and OrderQuery.reasonFor(order,firstMap)
                    if reason then candidate.allowed=false signal(order,reason) end
                    if not retryReady({id=candidate.key},npcId,now) then candidate.allowed=false end
                end
            end
        end

        if Providers.holdSelection(envDiscover) then return end

        for _=1,3 do
            selected=Selector.choose(candidates,priorities)
            if not selected then break end
            jobId=Registry.id()
            if directory:claim(selected.key,selected.revision,npcId,jobId) then break end
            cool({id=selected.key},npcId,{watch=Wake.capture(entry)},'CLAIM_BUSY',now)
            selected.allowed=false selected=nil
        end
    end

    if posting and Members.notePosting then
        if postingAccepted then Members.notePosting(npcId,nil) else Members.notePosting(npcId,postingReason) end
    end

    if not selected then
            workerBackoff[npcId]=(workerBackoff[npcId] or 0)+1
            local orders=OrderQuery.orderIds(entry.id)
	    local complete,scanWatch=Providers.scanStatus(npcId,orders)
            if envDiscover.pending then complete=false end
            idleStudyTargets[npcId]=studyTarget
            idle:empty(npcId,now,stamp,Wake.revision and Wake.revision() or 0,scanWatch,
		complete and not Providers.hasPending(npcId),retryWake[npcId])
            if not probing and complete and not Providers.hasPending(npcId) and Probe.idleLeisure then
                Probe.idleLeisure(npcId,entry)
            end
            for _,provider in ipairs(Providers.all()) do
		if not probing and (priorities[provider.category] or 0)>0 and not Providers.hasPending(npcId) and provider.idle then
                    provider.idle(npcId,entry,studyTarget)
                end
            end
            -- NPC sleep entry (P0 pilot): one complete empty discovery with
            -- no pending work and no over-threshold need puts this NPC to
            -- sleep at once (no 10s wait like the IdleDiscovery sleep).
            -- Probing NPCs (leisure probe) and unreadable samples never
            -- sleep; a need already past enter keeps the NPC on the normal
            -- backoff cadence instead. Leisure was already offered above,
            -- so sleeping only paces the next offer, it never starves it.
            if not probing and complete and not Providers.hasPending(npcId) and sample
                and not NeedsPolicy.choose(sample,nil,{safe=true},WAKE_OFFERS) then
                sleeping[npcId]={untilTime=now+Config.npcSleepRecheckMs,stamp=stamp,watch=scanWatch,enteredAt=now}
                -- The pilot sleep subsumes the IdleDiscovery sleep for this
                -- NPC: clear its row so the 10s-empty clock cannot arm the
                -- old 15s sleep and interpose between 1Hz rechecks. The
                -- pilot's own npcSleepMaxMs cap is the bound instead. NPCs
                -- that never enter pilot sleep keep the old mechanism.
                idle:clear(npcId)
            end
            return
    end

    if probing then
        pendingReservations[npcId]={selected=selected,jobId=jobId,entry=entry,createdAt=now}
        if now>=(leisureStops[npcId] or 0) then
            leisureStops[npcId]=now+Config.socialRoundMs
            if Probe.leisureWorkReady then Probe.leisureWorkReady(npcId,jobId) end
        end
        careWaking[npcId]=true
        idle:clear(npcId)
        dispatchDirty=true
        nextWake=math.min(nextWake,now+Config.wakeMs)
        return
    end
    claimSelected(actor,npcId,now,selected,jobId,entry)
end

-- Precheck adapters are hoisted: rebuilding seven closures on every 50 ms pass
-- was pure garbage with no behavioural benefit.
local function precheckEligible(a,id,scope) return eligible(a,id,scope) end
local function precheckHasCargo(a,id) return Work.hasCargo(a,id) end
local function precheckRecord(id) return Work.record(id) end
local function precheckPriorities(id) return Service.priorities(id) end
local function precheckReady(id) readyWorkers[#readyWorkers+1]=id end
-- One faulty carrier must not abort the whole dispatch pass. Each decision is
-- isolated; its error is rate-limited per worker so a stuck one cannot flood
-- the log every pass.
local WORKER_FAULT_LOG_MS=10000
local function safeDecide(actor,npcId,now,binding,entry)
    local ok,err=pcall(decide,actor,npcId,now,binding,entry)
    if ok then
        if workerFaults[npcId] then workerFaults[npcId]=nil end
        return
    end
    local row=workerFaults[npcId]
    local count=(row and row.count or 0)+1
    local at=row and row.at
    if not at or now-at>=WORKER_FAULT_LOG_MS then
        workerFaults[npcId]={at=now,count=count}
        Log.write('DISPATCH','WORKER_FAULT npc='..tostring(npcId)..' count='..count..' error='..tostring(err))
    else
        row.count=count
    end
end
local function advance(now,discover,providerDue,precheckDue)
    if not Probe.ready or not Probe.runtimeReady or not Probe.hasJava() or not Gate.isSinglePlayer() then return end
    local runtime=Runtime.current() if not runtime or not runtime:accepting() then return end
    load()
    if world.executionSave and world.executionSave.state=='BLOCKED' then return end
    local actor=getSpecificPlayer(0) if not actor or actor:isDead() then return end
    -- Captured before anything below clears dispatchDirty: a labor signal
    -- since the last discovery pass wakes sleeping NPCs at their recheck.
    wakeSignal=dispatchDirty
    measured('PublicWork.reservations',advanceReservations,now,actor)
    measured('PublicWork.observe',Providers.observeDemand,actor,now,eligible,Service.priorities)
    if providerDue then
        for _,provider in ipairs(Providers.all()) do
            if provider.advance then measured('PublicWork.providerAdvance',provider.advance,{actor=actor,now=now,directory=directory}) end
        end
    end
    if precheckDue and Providers.hasPrechecks() then
	local ops,slices=measured('PublicWork.precheck',Providers.precheck,{
            actor=actor,now=now,orders=data.orders,
            eligible=precheckEligible,hasCargo=precheckHasCargo,record=precheckRecord,
            priorities=precheckPriorities,onReady=precheckReady,cool=cool,signal=signal
        })
        tickOps,tickSlices=ops,slices
        local ready=readyWorkers readyWorkers={}
        if #ready>1 then
            table.sort(ready,function(a,b)
                return Providers.pendingScore(a)>Providers.pendingScore(b)
            end)
        end
	for _,id in ipairs(ready) do if Providers.hasPending(id) then measured('PublicWork.decide',safeDecide,actor,id,now) end end
    end
    if not discover then return end
    nextWake=now+Config.discoveryWakeMs dispatchDirty=false
    nextTick=now+(discoveryActive and Config.discoveryMs or Config.discoveryIdleMs)
    if now>=nextReconcile then nextReconcile=now+Config.reconcileMs measured('PublicWork.reconcile',reconcile) end
    if now>=nextStock then nextStock=now+Config.stockMs measured('PublicWork.stock',stock,actor,now) end
    local startCursor=cursor
    local window=EmberRoutesProbeJava.workerDecisionWindow and EmberRoutesProbeJava.workerDecisionWindow(startCursor,16)
    local count=window and window.count or EmberRoutesProbeJava.workerCount() if count<1 or count>256 then discoveryActive=false return end
    cursor=(cursor+1)%count
    local decisions=0
    for _=1,math.min(16,count) do
        local id=window and window.ids[_] or EmberRoutesProbeJava.workerIdAt((startCursor+_-1)%count)
        local due=decideAt[id]
        if not due then due=now+decidePhaseMs(id) decideAt[id]=due end
        if now>=due then
            local binding,entry=eligible(actor,id)
            if binding then
                measured('PublicWork.decide',safeDecide,actor,id,now,binding,entry)
                decisions=decisions+1
                if decisions>=4 then break end
            end
            -- Carriers far from the player think less often instead of being
            -- dropped: this project has no meta simulation to keep them busy.
            local period=Config.discoveryMs
            if careWaking[id] then
                careWaking[id]=nil
                period=Config.wakeMs
                dispatchDirty=true
                nextWake=now+Config.wakeMs
            elseif sleeping[id] then
                -- A sleeping NPC rechecks at 1Hz, never on the backoff or
                -- remote ladder: stretching the recheck would break the
                -- wake bound, and the recheck itself is only gates plus a
                -- needs sample, no provider scan.
                period=Config.npcSleepRecheckMs
            else
                local backoff=workerBackoff[id] or 0
                if backoff>0 then
                    period=math.max(period,Config.backoffMs[math.min(backoff,3)])
                end
                local handle=binding and binding.handle
                if handle then
                    local radius=Config.workerRemoteRadius
                    local dx=handle:getX()-actor:getX() local dy=handle:getY()-actor:getY()
                    if dx*dx+dy*dy>radius*radius then period=math.max(period,Config.workerRemoteMs) end
                end
            end
            decideAt[id]=now+period
        end
    end
    -- Any decision this pass, or live precheck work, keeps the fast period.
    discoveryActive=decisions>0 or tickOps>0
end
function Service.metrics() return metrics:snapshot() end
-- Diagnostic/test seam: recheck time of a sleeping NPC, nil when awake.
function Service.sleeping(npcId) local s=sleeping[npcId] return s and s.untilTime or nil end
function Service.tick()
    local now=getTimestampMs()
    if now>=nextWakePoll then
        nextWakePoll=now+Config.wakeMs
        local revision=Wake.revision and Wake.revision()
        if revision~=observedWake then observedWake=revision dispatchDirty=true end
    end
    for _ in pairs(pendingReservations) do
        dispatchDirty=true
        nextWake=math.min(nextWake,now+Config.wakeMs)
        break
    end
    local discover=now>=nextTick or (dispatchDirty and now>=nextWake)
    if not discover and now<nextPrecheck then return end
    local precheckDue=now>=nextPrecheck
    if precheckDue then
        nextPrecheck=now+Config.precheckMs
        -- hasWork walks every order of every provider. Re-evaluating it on all
        -- twenty 50 ms passes bought nothing: a provider only gains work through
        -- a signal, and that signal wakes discovery within 100 ms anyway. Decide
        -- it on discovery passes and keep advancing in between.
        if discover then
            providerDue=false
            for _,p in ipairs(Providers.all()) do
                if p.advance and p.hasWork and p.hasWork() then providerDue=true break end
            end
        end
    end
    if not discover and not providerDue and not Providers.hasPrechecks() then return end
    if faultWorld==Registry.data() then return end
    if faultUntil and now<faultUntil then return end
    tickOps,tickSlices=0,0
    local ok,reason=pcall(advance,now,discover,providerDue,precheckDue)
    metrics:record(getTimestampMs()-now,tickOps,tickSlices)
    if ok then
        faultCount=0 faultUntil=nil
    else
        faultCount=faultCount+1
        faultUntil=now+FAULT_RETRY_MS
        if faultCount>=FAULT_LIMIT then faultWorld=Registry.data() end
        Log.write('DISPATCH','DISPATCH_BLOCKED '..tostring(reason)..' failures='..faultCount
            ..(faultWorld and ' state=LOCKED' or ' state=RETRY'))
    end
end
function Service.hasReservation(npcId)
    return pendingReservations[npcId]~=nil
end
function Service.cancelReservation(npcId)
    cancelReservation(npcId,'MANUAL_CANCEL')
end
-- NOTE (F-01): `Probe.publicDispatch` is a "PublicWork has loaded" flag, not a
-- runtime feature toggle. Setting it here (module-load side effect, alongside
-- installing the real dispatch entry `Probe.tickPublicWork`) is the only place
-- in production code that writes it, and nothing ever writes it back to
-- false/nil -- so in production it is always true once this file loads. The
-- `false`/nil branches guarded by it only exist for tests (stub Boot tables).
-- There is no private fallback: the private dispatch paths were deleted
-- (F-05), so if this line never runs the flag stays nil and public dispatch
-- simply never engages -- preparePublic/publicOffer fail closed and
-- LogisticsService.start reports DRIVER_UNAVAILABLE.
Probe.publicDispatch=true Probe.tickPublicWork=Service.tick
Probe.hasPendingWork=Service.hasReservation
Probe.cancelReservation=Service.cancelReservation
return Service
