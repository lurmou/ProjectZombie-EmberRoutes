-- One ordinary-work selector/claim coordinator. Providers discover/evaluate;
-- TaskRuntime alone grants bodies and LaborStore alone grants physical assets.
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local Ledger=require 'EmberRoutesProbe/SettlementLedger'
local Geometry=require 'EmberRoutesProbe/SettlementGeometry'
local Driver=require 'EmberRoutesProbe/Driver'
local Runtime=require 'EmberRoutesProbe/TaskRuntime'
local Work=require 'EmberRoutesProbe/Work'
local Companion=require 'EmberRoutesProbe/Companion'
local Production=require 'EmberRoutesProbe/Production'
local Recipe=require 'EmberRoutesProbe/ProductionRecipe'
local Surfaces=require 'EmberRoutesProbe/CraftSurfaces'
local Signals=require 'EmberRoutesProbe/LaborSignals'
local Selector=require 'EmberRoutesProbe/WorkSelector'
local Directory=require 'EmberRoutesProbe/TaskDirectory'
local Providers=require 'EmberRoutesProbe/PublicWorkProviders'
local Log=require 'EmberRoutesProbe/Log'
local Probe=require 'EmberRoutesProbe/Boot'
local Queue=require 'EmberRoutesProbe/PrecheckQueue'
local TaskJobs=require 'EmberRoutesProbe/TaskJobs'
local JobStore=require 'EmberRoutesProbe/JobStore'
local Metrics=require 'EmberRoutesProbe/DispatchMetrics'
local Wake=require 'EmberRoutesProbe/PlanningWake'
local Config=require 'EmberRoutesProbe/TickConfig'
local Gate=require 'EmberRoutesProbe/RuntimeGate'
local HaulingProvider=require 'EmberRoutesProbe/HaulingProvider'
local CraftingProvider=require 'EmberRoutesProbe/CraftingProvider'
local IdleDiscovery=require 'EmberRoutesProbe/IdleDiscovery'
local CraftYield=require 'EmberRoutesProbe/ProductionYield'
local idle=IdleDiscovery.new()
local catalogEpoch,retryWake,idleStudyTargets={},{},{}
local Service={}
local world,data,directory,cursor,nextTick,orderCursor=nil,nil,nil,0,0,0
local nextPrecheck,nextWake,observedWake,dispatchDirty=0,0,nil,true
local Business,Members
local function business()
    Business=Business or require 'EmberRoutesProbe/BusinessJobs'
    return Business
end
if Signals.watch then Signals.watch(function(id) dispatchDirty=true if id then idle:clear(id) end end) end
-- hauling state encapsulated in HaulingProvider
local stockWatches,ruleCursor={},0
local retryAt={}
local metrics=Metrics.new()
local readyWorkers={}
local tickOps,tickSlices=0,0
local faultWorld
-- Id+sequence projection of one settlement's orders for the decide scan. The
-- decision loop reads live order fields by id; only the iteration order needs
-- materializing, and only when order keys actually change.
local leisureStops={}
local ordersIdsCache={world=nil,dirty=true,scopes={}}
-- Enabled-rule projection with a stable id order; rebuilt only when the rule
-- set changes (saveRule bumps the revision) or the world root is replaced.
local rulesCache={world=nil,revision=-1,list={}}
local rulesRevision=0
local function orderIds(scope)
    if ordersIdsCache.dirty or ordersIdsCache.world~=data then
        ordersIdsCache.world,ordersIdsCache.dirty,ordersIdsCache.scopes=data,false,{}
    end
    if ordersIdsCache.scopes[scope] then return ordersIdsCache.scopes[scope] end
    local ids={}
    for _,o in pairs(data.orders) do
        if o.settlementId==scope then ids[#ids+1]={id=o.id,sequence=o.sequence} end
    end
    table.sort(ids,function(a,b) return a.sequence<b.sequence end)
    ordersIdsCache.scopes[scope]=ids
    return ids
end
local function load()
    local root=Registry.data()
    if root~=world then
        for _,release in pairs(stockWatches) do release() end stockWatches={} ruleCursor=0
        if root.maintainStock and root.maintainStock.rules then
            for _ in pairs(root.maintainStock.rules) do error('LEGACY_STOCK_RESET_REQUIRED') end
        end
        decisionScans={}
        idle=IdleDiscovery.new() catalogEpoch,retryWake,idleStudyTargets={},{},{}
        local value=root.publicWork
        if value and (type(value)~='table' or value.format~=1 or type(value.orders)~='table' or type(value.priorities)~='table') then error('PUBLIC_WORK_FORMAT_INVALID') end
        value=value or {format=1,sequence=0,orders={},priorities={},rules={}}
        value.rules=value.rules or {}
        value.requests=value.requests or {}
        if type(value.requests)~='table' or #value.requests>128 then error('PUBLIC_REQUEST_INVALID') end
        local requestIds={}
        for _,r in ipairs(value.requests) do
            if type(r)~='table' or type(r.requestId)~='string' or r.requestId=='' or requestIds[r.requestId]
                or (r.orderId~=nil and (type(r.orderId)~='string' or type(r.settlementId)~='string'
                    or type(r.recipeId)~='string' or type(r.quantity)~='number')) then error('PUBLIC_REQUEST_INVALID') end
            requestIds[r.requestId]=true
        end
        local function integer(n,min,max) return type(n)=='number' and n==n and n==math.floor(n) and n>=min and n<=max end
        if not integer(value.sequence,0,1e12) or type(value.rules)~='table' then error('PUBLIC_WORK_FORMAT_INVALID') end
        for id,p in pairs(value.priorities) do
            if type(id)~='string' or type(p)~='table' or not integer(p.revision,1,1e12) then error('PUBLIC_PRIORITY_INVALID') end
            for k,v in pairs(p) do if k~='revision' and not integer(v,0,4) then error('PUBLIC_PRIORITY_INVALID') end end
        end
        local n=0
        for id,r in pairs(value.rules) do
            n=n+1
            if n>64 or type(r)~='table' or r.id~=id or type(r.settlementId)~='string' or type(r.recipeId)~='string'
                or type(r.product)~='string' or type(r.enabled)~='boolean' or not integer(r.minimum,0,9999)
                or not integer(r.batch,1,9999) or not integer(r.revision,1,1e12) or not integer(r.cycle,0,1e12) then error('PUBLIC_RULE_INVALID') end
            r.nextCheck=nil -- Wall-clock deadlines are transient, not restored timestamps.
        end
        local count=0
        for key,o in pairs(value.orders) do
            count=count+1
            if count>256 or type(o)~='table' or o.id~=key or type(o.settlementId)~='string'
                or type(o.recipeId)~='string' or type(o.requestId)~='string' or type(o.product)~='string'
                or not integer(o.quantity,1,9999) or not integer(o.target,1,1e6) or not integer(o.sequence,1,value.sequence)
                or not integer(o.revision,1,1e12) or type(o.state)~='string'
                or (o.jobId~=nil and (type(o.jobId)~='string' or type(o.npcId)~='string')) then error('PUBLIC_ORDER_INVALID') end
            if o.category=='cooking' and (not integer(o.delivered or 0,0,o.target)
                or o.pauseRequested~=nil and type(o.pauseRequested)~='boolean'
                or o.cancelRequested~=nil and type(o.cancelRequested)~='boolean'
                or o.stopBatchRequested~=nil and type(o.stopBatchRequested)~='boolean') then error('PUBLIC_ORDER_INVALID') end
            if o.category~='cooking' and not CraftYield.progress(o.craftProgress,o.target) then error('PUBLIC_PROGRESS_INVALID') end
            if o.parentOrderId~=nil and (type(o.parentOrderId)~='string' or o.parentOrderId==o.id)
                or o.prerequisiteId~=nil and (type(o.prerequisiteId)~='string' or o.prerequisiteId==o.id) then error('PUBLIC_ORDER_INVALID') end
        end
        root.publicWork=value world,data=root,value directory=Directory.new()
        CraftingProvider.reset()
        retryAt={} leisureStops={} faultWorld=nil
        metrics=Metrics.new() readyWorkers={}
        cursor,nextTick,orderCursor=0,0,0 HaulingProvider.reset()
        nextPrecheck,nextWake,observedWake,dispatchDirty=0,0,nil,true
        Members=nil
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
function Service.categories() return Providers.categories() end
function Service.registerProvider(def) return Providers.register(def) end
function Service.provider(category) return Providers.get(category) end
function Service.priorities(npcId)
    local p=load().priorities[npcId] or {}
    local result={revision=p.revision or 0}
    for _,cat in ipairs(Providers.categories()) do
        local def=Providers.get(cat)
        result[cat]=p[cat]==nil and (def and def.defaultPriority or 3) or p[cat]
    end
    if result.crafting==nil then result.crafting=p.crafting==nil and 3 or p.crafting end
    if result.hauling==nil then result.hauling=p.hauling==nil and 3 or p.hauling end
    return result
end
function Service.setPriorities(actor,scope,npcId,values,revision)
    local available,blocked=Service.available() if not available then return blocked end
    local entry,reason=Ledger.view(actor,scope) if not entry then return reason end
    local binding=Driver.bindId(actor,npcId)
    if not binding or not Geometry.inside(entry,binding.handle:getX(),binding.handle:getY()) then return 'NPC_OUTSIDE_SETTLEMENT' end
    if type(values)~='table' then return 'INVALID_PRIORITY' end
    for k,value in pairs(values) do
        if k~='revision' then
            if type(value)~='number' or value~=math.floor(value) or value<0 or value>4 then return 'INVALID_PRIORITY' end
        end
    end
    for _,key in ipairs({'crafting','hauling'}) do
        local value=values[key]
        if type(value)~='number' or value~=math.floor(value) or value<0 or value>4 then return 'INVALID_PRIORITY' end
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
    if (not Providers.has(category) and category~='crafting' and category~='hauling') or type(value)~='number' or value~=math.floor(value) or value<0 or value>4 then return 'INVALID_PRIORITY' end
    local binding=Driver.bindId(actor,npcId)
    if not binding or not Geometry.inside(entry,binding.handle:getX(),binding.handle:getY()) then return 'NPC_OUTSIDE_SETTLEMENT' end
    local p=Service.priorities(npcId) p[category]=value
    return Service.setPriorities(actor,scope,npcId,p,p.revision)
end
local function createOrder(actor,scope,recipeId,quantity,surfaceId,requestId,preferences,parent)
    local available,blocked=Service.available() if not available then return blocked end
    local entry,reason=Ledger.view(actor,scope) if not entry then return reason end
    if type(requestId)~='string' or requestId=='' or #requestId>256 then return 'REQUEST_ID_REQUIRED' end
    if type(quantity)~='number' or quantity~=math.floor(quantity) or quantity<1 or quantity>9999 then return 'INVALID_QUANTITY' end
    local cooking=require('EmberRoutesProbe/CookingOrders').describe(recipeId)
    local spec=cooking
    local why
    if not spec then spec,why=Recipe.read(recipeId) end
    if not spec then return why end
    if not cooking and not parent and not actor:isRecipeKnown(spec.recipe,true) then return 'PLAYER_RECIPE_UNKNOWN' end
    local surface
    if spec.surface then
        local saved=(Registry.data().craftSurfaces or {})[surfaceId]
        if not saved or not Geometry.inside(entry,saved.x,saved.y) then return 'CRAFT_SURFACE_REQUIRED' end
        surface,why=Surfaces.resolve(saved,surfaceId) if not surface then return why end
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
    ordersIdsCache.dirty=true
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
    -- A fresh receipt is allocated only when no active predecessor remains.
    local result,id=createOrder(actor,parent.settlementId,node.recipeId,node.requested,node.benchId,
        Service.requestId(),parent.preferences,parent)
    if result=='ORDER_CREATED' then parent.prerequisiteId=id parent.revision=parent.revision+1 end
    return result,id
end
function Service.createDeliveryOrder(actor,scope,items,requestId)
    local DeliveryService=require 'EmberRoutesProbe/DeliveryService'
    return DeliveryService.createOrder(actor,scope,items,requestId)
end
function Service.order(id)
    local o=load().orders[id] if not o then return end
    local copy={} for k,v in pairs(o) do copy[k]=k=='craftProgress' and CraftYield.copy(v) or v end return copy
end
function Service.orders(scope)
    load()
    if scope==nil then return {} end
    local rows={}
    for _,key in ipairs(orderIds(scope)) do
        local o=data.orders[key.id]
        if o then local r={} for k,v in pairs(o) do r[k]=k=='craftProgress' and CraftYield.copy(v) or v end rows[#rows+1]=r end
    end
    return rows
end
function Service.command(actor,scope,id,revision,action)
    local available,blocked=Service.available() if not available then return blocked end
    local entry,reason=Ledger.view(actor,scope) if not entry then return reason end
    local o=load().orders[id]
    if not o or o.settlementId~=scope or o.revision~=revision then return 'TASK_CHANGED' end
    if o.category=='cooking' then return require('EmberRoutesProbe/CookingOrders').command(o,action) end
    if o.jobId then return 'ORDER_ALREADY_CLAIMED' end
    if o.state=='CANCELLED' or o.state=='DONE' then return 'TASK_CHANGED' end
    if action=='return' then o.state='CANCELLED' directory:withdraw('craft:'..id)
    elseif action=='stop' then o.state='PAUSED' directory:withdraw('craft:'..id)
    elseif action=='resume' and o.state=='PAUSED' then o.state='WAITING'
    else return 'INVALID_COMMAND' end
    CraftingProvider.bumpGeneration(id)
    if Probe.invalidateStudy then Probe.invalidateStudy(scope) end
    o.revision=o.revision+1 catalogEpoch[scope]=(catalogEpoch[scope] or 0)+1
    Signals.changed() return 'ORDER_UPDATED'
end
function Service.saveRule(actor,scope,recipeId,minimum,batch,surfaceId,preferences)
    local available,blocked=Service.available() if not available then return blocked end
    local entry,reason=Ledger.view(actor,scope) if not entry then return reason end
    if type(minimum)~='number' or minimum~=math.floor(minimum) or minimum<0 or minimum>9999
        or type(batch)~='number' or batch~=math.floor(batch) or batch<1 or batch>9999 then return 'INVALID_QUANTITY' end
    local cooking=require('EmberRoutesProbe/CookingOrders').describe(recipeId)
    local spec=cooking
    local why
    if not spec then spec,why=Recipe.read(recipeId) end
    if not spec then return why end
    if not cooking and not actor:isRecipeKnown(spec.recipe,true) then return 'PLAYER_RECIPE_UNKNOWN' end
    if spec.surface then
        local position=(Registry.data().craftSurfaces or {})[surfaceId]
        if not position or not Geometry.inside(entry,position.x,position.y) or not Surfaces.resolve(position,surfaceId) then return 'CRAFT_SURFACE_REQUIRED' end
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
    local Index=require 'EmberRoutesProbe/WarehouseIndex'
    for id in pairs(needed) do if not stockWatches[id] then
        stockWatches[id]=Index.watch(id,function() end)
    end end
    ruleCursor=ruleCursor%#rules+1 local rule=rules[ruleCursor]
    if rule.activeOrder then
        local o=data.orders[rule.activeOrder]
        if not o or o.state=='DONE' or o.state=='CANCELLED' then
            rule.activeOrder=nil rule.nextCheck=now+2000 Index.refresh(rule.settlementId,false)
        else return end
    end
    if now<(rule.nextCheck or 0) then return end rule.nextCheck=now+1000
    -- Overlapping storage must not trigger two policies for the same originals.
    local Membership=require 'EmberRoutesProbe/SettlementMembership'
    local seen={}
    for _,other in ipairs(rules) do if other.product==rule.product then
        local entry=Ledger.view(actor,other.settlementId)
        for _,id in ipairs(entry and Membership.query(entry) or {}) do
            if seen[id] and seen[id]~=other.settlementId then rule.reason='CONTAINER_OVERLAP' return end
            seen[id]=other.settlementId
        end
    end end
    local observed
    if require('EmberRoutesProbe/CookingOrders').describe(rule.recipeId) then
        observed=require('EmberRoutesProbe/CookingService').stock(actor,rule)
    else observed=Index.candidates(actor,rule.settlementId,{fullType=rule.product,limit=1}) end
    if not observed or observed.state~='READY' or not observed.complete then rule.reason='INVENTORY_UNKNOWN' return end
    rule.knownCount=observed.knownCount rule.reason=nil
    if observed.knownCount>=rule.minimum then return end
    for _,o in pairs(data.orders) do
        if o.settlementId==rule.settlementId and o.product==rule.product and o.state~='DONE' and o.state~='CANCELLED' then return end
    end
    local cycle=rule.cycle+1
    local result,id=Service.create(actor,rule.settlementId,rule.recipeId,rule.batch,rule.surfaceId,
        Service.requestId(),rule.preferences)
    rule.reason=result
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
Providers.register(CraftingProvider)
Providers.register(HaulingProvider)
Providers.register(require 'EmberRoutesProbe/CookingProvider')
Providers.register(require 'EmberRoutesProbe/CleaningProvider')
Providers.register(require 'EmberRoutesProbe/FarmingProvider')
Providers.register(require 'EmberRoutesProbe/LumberjackProvider')
Providers.register(require 'EmberRoutesProbe/ForagerProvider')

local function reconcile()
    for _,p in ipairs(Providers.all()) do
        if p.reconcile then p.reconcile({orders=data.orders,directory=directory,catalogEpoch=catalogEpoch,signal=signal}) end
    end
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
    local Jobs=require 'EmberRoutesProbe/BusinessJobs'
    Jobs.flush()
    local ids={} for id in pairs(data.orders) do ids[#ids+1]=id end table.sort(ids)
    local count=0
    for _,id in ipairs(ids) do
        local o=data.orders[id]
        local settled=o.state=='DONE' or o.state=='CANCELLED'
        -- An unclaimed cancellation has never acquired originals. Claimed
        -- work must prove its exact Job is closed, not merely absent.
        if settled and (o.jobId and Jobs.canRetire(o.jobId,id)
            or not o.jobId and (not o.craftProgress and (o.state=='CANCELLED' or o.category=='cooking' and o.state=='DONE')
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
                    require('EmberRoutesProbe/WarehouseIndex').refresh(r.settlementId,false)
                end end
                CraftingProvider.cleanupOrder(id,readyWorkers)
                for key in pairs(retryAt) do if string.sub(key,1,#id+1)==id..':' then retryAt[key]=nil end end
                data.orders[id]=nil count=count+1
                if count>=limit then break end
            end
        end
    end
    if count>0 then ordersIdsCache.dirty=true Signals.changed() end
    return count
end
-- Cheap eligibility is shared by discovery and private precheck admission.
local function eligible(actor,npcId,scope)
    if require('EmberRoutesProbe/ActivityAttendance').blocksOrdinary(npcId) then return end
    local binding=Driver.bindId(actor,npcId)
    local probing=Probe.careProbeWork and Probe.careProbeWork(npcId)
    if not binding or not binding.handle or Work.busy(npcId)
        or Probe.careBlocksWork and Probe.careBlocksWork(npcId) and not probing then return end
    if require('EmberRoutesProbe/CookingProvider').retained(npcId) then return end
    if require('EmberRoutesProbe/FieldWork').retained(npcId) then return end
    local existing=business().crafts()[npcId]
    if existing and not existing.released then return end
    local npc=binding.handle
    if not probing and not npc:getCharacterActions():isEmpty() or npc:getBodyDamage():getOverallBodyHealth()<95 then return end
    Members=Members or require 'EmberRoutesProbe/MembershipService'
    local M=Members
    local eligible=M.check(npcId,'WORK',{x=npc:getX(),y=npc:getY(),z=npc:getZ(),scopeId=scope})
    if not eligible.allowed then return end
    local entry=M.entry(npcId,scope)
    if not entry then return end
    return binding,entry
end
local function decide(actor,npcId,now,binding,entry)
    if not binding then binding,entry=eligible(actor,npcId) end
    if not binding then CraftingProvider.cancel(npcId) idle:clear(npcId) return end
    local npc=binding.handle
    local current=Work.record(npcId)
    local Logistics=require 'EmberRoutesProbe/LogisticsService'
    if current and current.state~='DONE' then
        if current.producer=='LOGISTICS' and current.settlementId==entry.id
            and (current.reason=='SAVE' or current.reason=='LOAD_RECOVERY')
            and not current.controlUncertain and Logistics.preparePublic(actor,entry) then Work.resumeFor(actor,npcId) end
        return
    end
    if Work.hasCargo(actor,npcId) then CraftingProvider.cancel(npcId) return end
    if TaskJobs.current():ordinaryCount()>=JobStore.LIMIT then
        local e=CraftingProvider.pending(npcId)
        if e and data.orders[e.orderId] then signal(data.orders[e.orderId],'JOB_LIMIT') end
        CraftingProvider.cancel(npcId) return
    end
    local priorities=Service.priorities(npcId) local candidates={} local studyTarget
    local member=Members and Members.view and Members.view(npcId)
    local stamp=entry.id..':'..tostring(entry.revision)..':'..tostring(member and member.revision)
        ..':'..tostring(priorities.revision)..':'..tostring(catalogEpoch[entry.id] or 0)
    if not CraftingProvider.pending(npcId) and not idle:due(npcId,now,stamp,Wake.revision and Wake.revision() or 0,Wake.changed) then
        if Probe.leisureWorkState then Probe.leisureWorkState(npcId,entry,'IDLE') end
        for _,provider in ipairs(Providers.all()) do
            if (priorities[provider.category] or 0)>0 and provider.idle then
                provider.idle(npcId,entry,idleStudyTargets[npcId])
            end
        end
        return
    end
    if retryWake[npcId] and retryWake[npcId]<=now then retryWake[npcId]=nil end

    local envDiscover={
        actor=actor,npc=npc,npcId=npcId,entry=entry,priorities=priorities,
        now=now,candidates=candidates,
        setStudyTarget=function(t) studyTarget=t end,
        directory=directory,
        orders=data.orders,
        orderIds=orderIds(entry.id),
        sequence=data.sequence,
        candidateReady=function(key) return retryReady({id=key},npcId,now) end,
        retryReady=retryReady,
        cool=cool,
        signal=signal,
        upsertOffer=function(key,rev,cat,scope)
            return directory:upsert(key,rev,cat,scope or entry.id)
        end
    }
    for _,provider in ipairs(Providers.all()) do
        local p=priorities[provider.category] or 0
        if p>0 and provider.discover then
            envDiscover.priority=p
            provider.discover(envDiscover)
        end
    end

    for _,candidate in ipairs(candidates) do
        if not retryReady({id=candidate.key},npcId,now) then candidate.allowed=false end
    end
    local pending=CraftingProvider.pending(npcId)
    -- One bounded grace window, without a body reservation.
    if pending and not pending.ready and now-pending.started<250 and priorities.crafting>0 then
        local craftP=priorities.crafting
        local higherOther=false
        for _,c in ipairs(candidates) do
            local p=priorities[c.category]
            if p and p>0 and p<craftP then higherOther=true break end
        end
        if not higherOther then return end
    end
    local selected,jobId
    for _=1,3 do
        selected=Selector.choose(candidates,priorities)
        if not selected then
            local orders=orderIds(entry.id)
            local complete,scanWatch=CraftingProvider.scanStatus(npcId,orders)
            if envDiscover.pending then complete=false end
            idleStudyTargets[npcId]=studyTarget
            idle:empty(npcId,now,stamp,Wake.revision and Wake.revision() or 0,scanWatch,
                complete and not CraftingProvider.pending(npcId),retryWake[npcId])
            if Probe.leisureWorkState then Probe.leisureWorkState(npcId,entry,
                complete and not CraftingProvider.pending(npcId) and 'IDLE' or 'OBSERVING')
            elseif complete and not CraftingProvider.pending(npcId) and Probe.idleLeisure then Probe.idleLeisure(npcId,entry) end
            for _,provider in ipairs(Providers.all()) do
                if (priorities[provider.category] or 0)>0 and not CraftingProvider.pending(npcId) and provider.idle then
                    provider.idle(npcId,entry,studyTarget)
                end
            end
            return
        end
        idle:clear(npcId)
        if Probe.leisureWorkState then Probe.leisureWorkState(npcId,entry,'READY') end
        if Probe.careProbeWork and Probe.careProbeWork(npcId) then
            if now>=(leisureStops[npcId] or 0) then
                leisureStops[npcId]=now+10000
                if Probe.leisureWorkReady then Probe.leisureWorkReady(npcId) end
            end
            return
        end
        jobId=Registry.id()
        if directory:claim(selected.key,selected.revision,npcId,jobId) then break end
        cool({id=selected.key},npcId,{watch=Wake.capture(entry)},'CLAIM_BUSY',now)
        selected.allowed=false selected=nil
    end
    if not selected then return end
    CraftingProvider.cancel(npcId)
    local result
    local provider=Providers.get(selected.category)
    if provider and provider.claim then
        result=provider.claim(selected,npcId,jobId,{actor=actor,entry=entry,now=now,directory=directory,
            releaseOffer=function(k,j,p) return directory:release(k,j,p) end})
    end
    if result~='QUEUED' and result~='STARTED' then
        cool({id=selected.key},npcId,{watch=Wake.capture(entry)},result,now)
        directory:release(selected.key,jobId,{effects='KNOWN',obligationsCleared=true})
    end
    if result=='QUEUED' or result=='STARTED' then metrics.claims=metrics.claims+1 end
    Signals.changed(npcId) Log.write('DISPATCH','npc='..npcId..' offer='..selected.key..' job='..jobId..' result='..tostring(result))
end

local function advance(now,discover,providerDue,precheckDue)
    if not Probe.ready or not Probe.runtimeReady or not Probe.hasJava() or not Gate.isSinglePlayer() then return end
    local runtime=Runtime.current() if not runtime or not runtime:accepting() then return end
    load()
    if world.executionSave and world.executionSave.state=='BLOCKED' then return end
    local actor=getSpecificPlayer(0) if not actor or actor:isDead() then return end
    if providerDue then
        for _,provider in ipairs(Providers.all()) do
            if provider.advance then provider.advance({actor=actor,now=now,directory=directory}) end
        end
    end
    if precheckDue and CraftingProvider.evaluations():size()>0 then
        local ops,slices=CraftingProvider.step({
            actor=actor,now=now,orders=data.orders,
            eligible=function(a,id,scope) return eligible(a,id,scope) end,
            hasCargo=function(a,id) return Work.hasCargo(a,id) end,
            record=function(id) return Work.record(id) end,
            priorities=function(id) return Service.priorities(id) end,
            onReady=function(id) readyWorkers[#readyWorkers+1]=id end,
            cool=cool,signal=signal
        })
        tickOps,tickSlices=ops,slices
        local ready=readyWorkers readyWorkers={}
        for _,id in ipairs(ready) do if CraftingProvider.pending(id) then decide(actor,id,now) end end
    end
    if not discover then return end
    nextTick=now+Config.discoveryMs nextWake=now+100 dispatchDirty=false
    reconcile() stock(actor,now)
    local count=EmberRoutesProbeJava.workerCount() if count<1 or count>256 then return end
    local decisions=0
    for _=1,math.min(16,count) do
        cursor=cursor%count+1 local id=EmberRoutesProbeJava.workerIdAt(cursor-1)
        local binding,entry=eligible(actor,id)
        if binding then decide(actor,id,now,binding,entry) decisions=decisions+1 if decisions>=4 then break end end
    end
end
function Service.metrics() return metrics:snapshot() end
function Service.tick()
    local now=getTimestampMs()
    local revision=Wake.revision and Wake.revision()
    if revision~=observedWake then observedWake=revision dispatchDirty=true end
    local discover=now>=nextTick or (dispatchDirty and now>=nextWake)
    if not discover and now<nextPrecheck then return end
    local precheckDue=now>=nextPrecheck
    local providerDue=false
    if precheckDue then
        nextPrecheck=now+Config.precheckMs
        for _,p in ipairs(Providers.all()) do
            if p.advance and p.hasWork and p.hasWork() then providerDue=true break end
        end
    end
    if not discover and not providerDue and CraftingProvider.evaluations():size()==0 then return end
    if faultWorld==Registry.data() then return end
    tickOps,tickSlices=0,0
    local ok,reason=pcall(advance,now,discover,providerDue,precheckDue)
    metrics:record(getTimestampMs()-now,tickOps,tickSlices)
    if not ok then
        faultWorld=Registry.data()
        Log.write('DISPATCH','DISPATCH_BLOCKED '..tostring(reason))
    end
end
Probe.publicDispatch=true Probe.tickPublicWork=Service.tick
return Service
