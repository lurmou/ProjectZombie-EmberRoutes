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
local Log=require 'EmberRoutesProbe/Log'
local Probe=require 'EmberRoutesProbe/Boot'
local Service={}
local world,data,directory,cursor,nextTick,orderCursor=nil,nil,nil,0,0,0
local hauling={}
local stockWatches,ruleCursor={},0
local evaluations,retryAt={},{}
local faultWorld
local function load()
    local root=Registry.data()
    if root~=world then
        for _,release in pairs(stockWatches) do release() end stockWatches={} ruleCursor=0
        if root.maintainStock and root.maintainStock.rules then
            for _ in pairs(root.maintainStock.rules) do error('LEGACY_STOCK_RESET_REQUIRED') end
        end
        local value=root.publicWork
        if value and (type(value)~='table' or value.format~=1 or type(value.orders)~='table' or type(value.priorities)~='table') then error('PUBLIC_WORK_FORMAT_INVALID') end
        value=value or {format=1,sequence=0,orders={},priorities={},rules={}}
        value.rules=value.rules or {}
        local function integer(n,min,max) return type(n)=='number' and n==n and n==math.floor(n) and n>=min and n<=max end
        if not integer(value.sequence,0,1e12) or type(value.rules)~='table' then error('PUBLIC_WORK_FORMAT_INVALID') end
        for id,p in pairs(value.priorities) do
            if type(id)~='string' or type(p)~='table' or not integer(p.crafting,0,4)
                or not integer(p.hauling,0,4) or not integer(p.revision,1,1e12) then error('PUBLIC_PRIORITY_INVALID') end
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
        end
        root.publicWork=value world,data=root,value directory=Directory.new()
        for _,e in pairs(evaluations) do e.request:cancel() end
        evaluations,retryAt={},{} faultWorld=nil
        cursor,nextTick,orderCursor=0,0,0 hauling={}
    end
    return data
end
function Service.prepareRecovery() load() end
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
function Service.priorities(npcId)
    local p=load().priorities[npcId] or {}
    return {crafting=p.crafting==nil and 3 or p.crafting,hauling=p.hauling==nil and 3 or p.hauling,revision=p.revision or 0}
end
function Service.setPriorities(actor,scope,npcId,values,revision)
    local available,blocked=Service.available() if not available then return blocked end
    local entry,reason=Ledger.view(actor,scope) if not entry then return reason end
    local binding=Driver.bindId(actor,npcId)
    if not binding or not Geometry.inside(entry,binding.handle:getX(),binding.handle:getY()) then return 'NPC_OUTSIDE_SETTLEMENT' end
    if type(values)~='table' then return 'INVALID_PRIORITY' end
    for _,key in ipairs({'crafting','hauling'}) do
        local value=values[key]
        if type(value)~='number' or value~=math.floor(value) or value<0 or value>4 then return 'INVALID_PRIORITY' end
    end
    local previous=Service.priorities(npcId) if previous.revision~=revision then return 'PRIORITY_CHANGED' end
    load().priorities[npcId]={crafting=values.crafting,hauling=values.hauling,revision=revision+1}
    Signals.changed(npcId) return 'PRIORITY_SAVED'
end
function Service.setPriority(actor,scope,npcId,category,value)
    local entry,reason=Ledger.view(actor,scope) if not entry then return reason end
    if category~='crafting' and category~='hauling' or type(value)~='number' or value~=math.floor(value) or value<0 or value>4 then return 'INVALID_PRIORITY' end
    local binding=Driver.bindId(actor,npcId)
    if not binding or not Geometry.inside(entry,binding.handle:getX(),binding.handle:getY()) then return 'NPC_OUTSIDE_SETTLEMENT' end
    local p=Service.priorities(npcId) p[category]=value
    return Service.setPriorities(actor,scope,npcId,p,p.revision)
end
function Service.create(actor,scope,recipeId,quantity,surfaceId,requestId)
    local available,blocked=Service.available() if not available then return blocked end
    local entry,reason=Ledger.view(actor,scope) if not entry then return reason end
    if type(requestId)~='string' or requestId=='' or #requestId>256 then return 'REQUEST_ID_REQUIRED' end
    if type(quantity)~='number' or quantity~=math.floor(quantity) or quantity<1 or quantity>9999 then return 'INVALID_QUANTITY' end
    local spec,why=Recipe.read(recipeId) if not spec then return why end
    if not actor:isRecipeKnown(spec.recipe,true) then return 'PLAYER_RECIPE_UNKNOWN' end
    local surface
    if spec.surface then
        local saved=(Registry.data().craftSurfaces or {})[surfaceId]
        if not saved or not Geometry.inside(entry,saved.x,saved.y) then return 'CRAFT_SURFACE_REQUIRED' end
        surface,why=Surfaces.resolve(saved,surfaceId) if not surface then return why end
    else surfaceId=nil end
    local store=load()
    for _,o in pairs(store.orders) do
        if o.requestId==requestId then
            if o.settlementId~=scope or o.recipeId~=recipeId or o.quantity~=quantity or o.surfaceId~=surfaceId then return 'REQUEST_CONFLICT' end
            return 'ORDER_CREATED',o.id
        end
    end
    local count=0 for _ in pairs(store.orders) do count=count+1 end
    if count>=256 then return 'ORDER_LIMIT' end
    store.sequence=store.sequence+1 local id=Registry.id()
    store.orders[id]={id=id,requestId=requestId,settlementId=scope,requester=actor:getUsername(),recipeId=recipeId,
        name=spec.name,product=spec.product,quantity=quantity,target=math.ceil(quantity/spec.yield)*spec.yield,
        surfaceId=surfaceId,sequence=store.sequence,revision=1,state='WAITING',reason='WAITING_CLAIM'}
    Signals.changed() return 'ORDER_CREATED',id
end
function Service.orders(scope)
    local rows={}
    for _,o in pairs(load().orders) do
        if o.settlementId==scope then local r={} for k,v in pairs(o) do r[k]=v end rows[#rows+1]=r end
    end
    table.sort(rows,function(a,b) return a.sequence<b.sequence end) return rows
end
function Service.command(actor,scope,id,revision,action)
    local available,blocked=Service.available() if not available then return blocked end
    local entry,reason=Ledger.view(actor,scope) if not entry then return reason end
    local o=load().orders[id]
    if not o or o.settlementId~=scope or o.revision~=revision then return 'TASK_CHANGED' end
    if o.jobId then return 'ORDER_ALREADY_CLAIMED' end
    if o.state=='CANCELLED' or o.state=='DONE' then return 'TASK_CHANGED' end
    if action=='return' then o.state='CANCELLED' directory:withdraw('craft:'..id)
    elseif action=='stop' then o.state='PAUSED' directory:withdraw('craft:'..id)
    elseif action=='resume' and o.state=='PAUSED' then o.state='WAITING'
    else return 'INVALID_COMMAND' end
    o.revision=o.revision+1 Signals.changed() return 'ORDER_UPDATED'
end
function Service.saveRule(actor,scope,recipeId,minimum,batch,surfaceId)
    local available,blocked=Service.available() if not available then return blocked end
    local entry,reason=Ledger.view(actor,scope) if not entry then return reason end
    if type(minimum)~='number' or minimum~=math.floor(minimum) or minimum<0 or minimum>9999
        or type(batch)~='number' or batch~=math.floor(batch) or batch<1 or batch>9999 then return 'INVALID_QUANTITY' end
    local spec,why=Recipe.read(recipeId) if not spec then return why end
    if not actor:isRecipeKnown(spec.recipe,true) then return 'PLAYER_RECIPE_UNKNOWN' end
    if spec.surface then
        local position=(Registry.data().craftSurfaces or {})[surfaceId]
        if not position or not Geometry.inside(entry,position.x,position.y) or not Surfaces.resolve(position,surfaceId) then return 'CRAFT_SURFACE_REQUIRED' end
    else surfaceId=nil end
    local rules=load().rules local key=scope..':'..spec.product
    local previous=rules[key] local count=0 for _ in pairs(rules) do count=count+1 end
    if not previous and count>=64 then return 'ORDER_LIMIT' end
    rules[key]={id=key,settlementId=scope,product=spec.product,recipeId=recipeId,minimum=minimum,batch=batch,
        enabled=minimum>0,surfaceId=surfaceId,revision=(previous and previous.revision or 0)+1,
        cycle=previous and previous.cycle or 0,activeOrder=previous and previous.activeOrder}
    Signals.changed() return minimum>0 and 'RULE_SAVED' or 'RULE_DISABLED'
end
local function stock(actor,now)
    local needed,rules={},{}
    for _,rule in pairs(data.rules) do if rule.enabled then rules[#rules+1]=rule needed[rule.settlementId]=true end end
    for id,release in pairs(stockWatches) do if not needed[id] then release() stockWatches[id]=nil end end
    if #rules==0 then return end
    local Index=require 'EmberRoutesProbe/WarehouseIndex'
    for id in pairs(needed) do if not stockWatches[id] then
        stockWatches[id]=Index.watch(id,function() end)
    end end
    table.sort(rules,function(a,b) return a.id<b.id end)
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
    local observed=Index.candidates(actor,rule.settlementId,{fullType=rule.product,limit=1})
    if not observed or observed.state~='READY' or not observed.complete then rule.reason='INVENTORY_UNKNOWN' return end
    rule.knownCount=observed.knownCount rule.reason=nil
    if observed.knownCount>=rule.minimum then return end
    for _,o in pairs(data.orders) do
        if o.settlementId==rule.settlementId and o.product==rule.product and o.state~='DONE' and o.state~='CANCELLED' then return end
    end
    local cycle=rule.cycle+1
    local result,id=Service.create(actor,rule.settlementId,rule.recipeId,rule.batch,rule.surfaceId,
        'stock:'..rule.id..':'..rule.revision..':'..cycle)
    rule.reason=result
    if result=='ORDER_CREATED' then rule.cycle=cycle rule.activeOrder=id data.orders[id].policyId=rule.id end
end
local function reconcile()
    local jobs=require('EmberRoutesProbe/BusinessJobs').records('CRAFT')
    for _,o in pairs(data.orders) do
        if o.jobId then
            local r=jobs[o.jobId]
            if r then
                local state=r.released and (r.state=='DONE' and 'DONE' or 'CANCELLED') or r.state
                if o.state~=state then o.state=state o.revision=o.revision+1 Signals.changed(o.npcId) end
                signal(o,r.reason)
            elseif not Runtime.current():status(o.npcId,o.jobId) then
                -- An accepted-but-never-started request owns no originals. Do
                -- not reassign an already published Job missing from its index.
                local saved=(Registry.data().taskJobs or {byId={}}).byId[o.jobId]
                if saved then o.state='RECONCILE_REQUIRED' signal(o,'JOB_INDEX_CONFLICT')
                else
                    directory:release('craft:'..o.id,o.jobId,{effects='KNOWN',obligationsCleared=true})
                    o.jobId=nil o.npcId=nil o.state='WAITING' signal(o,'WAITING_CLAIM')
                end
            end
        end
    end
    for key,h in pairs(hauling) do
        local r=Work.record(h.npcId)
        if r and r.id==h.jobId and r.state=='DONE' then
            directory:release(key,h.jobId,{effects='KNOWN',obligationsCleared=true}) hauling[key]=nil
        elseif (not r or r.id~=h.jobId) and not Runtime.current():status(h.npcId,h.jobId) then
            directory:release(key,h.jobId,{effects='KNOWN',obligationsCleared=true}) hauling[key]=nil
        end
    end
end
local function advance()
    if not Probe.ready or not Probe.runtimeReady or not Probe.hasJava() or isClient() or isServer() then return end
    local runtime=Runtime.current() if not runtime or not runtime:accepting() then return end
    load() local now=getTimestampMs() if now<nextTick then return end nextTick=now+200
    reconcile()
    local actor=getSpecificPlayer(0) if not actor or actor:isDead() then return end
    stock(actor,now)
    local count=EmberRoutesProbeJava.workerCount() if count<1 or count>256 then return end
    cursor=cursor%count+1 local npcId=EmberRoutesProbeJava.workerIdAt(cursor-1)
    local binding=Driver.bindId(actor,npcId) if not binding then return end local npc=binding.handle
    local existing=require('EmberRoutesProbe/BusinessJobs').crafts()[npcId]
    if existing and not existing.released or Work.busy(npcId) or Companion.exportState(npcId).mode~='HOLD'
        or not npc:getCharacterActions():isEmpty() or npc:getBodyDamage():getOverallBodyHealth()<95 then return end
    local entries=Ledger.at(npc:getX(),npc:getY()) if #entries~=1 then return end
    local entry=Ledger.view(actor,entries[1].id) if not entry then return end
    local current=Work.record(npcId)
    local Logistics=require 'EmberRoutesProbe/LogisticsService'
    -- An owned recovery obligation comes before seeking new public work, even
    -- with cargo. User pauses and unknown effects are never auto-resumed.
    if current and current.state~='DONE' then
        if current.producer=='LOGISTICS' and current.settlementId==entry.id
            and (current.reason=='SAVE' or current.reason=='LOAD_RECOVERY')
            and not current.controlUncertain and Logistics.preparePublic(actor,entry) then
            Work.resumeFor(actor,npcId)
        end
        return
    end
    if Work.hasCargo(actor,npcId) then return end
    local jobs=Registry.data().taskJobs local countJobs=0
    for _ in pairs(jobs and jobs.byId or {}) do countJobs=countJobs+1 end
    if countJobs>=require('EmberRoutesProbe/JobStore').LIMIT then
        for _,o in pairs(data.orders) do if not o.jobId and o.state=='WAITING' then signal(o,'JOB_LIMIT') end end
        return
    end
    local priorities=Service.priorities(npcId) local candidates={}
    local orders=Service.orders(entry.id)
    -- Four globally bounded, read-only provider evaluations at most. Each turn
    -- advances only this NPC's one existing request (32 inventory/planner steps).
    -- Missing materials do not allocate a body, Job or physical claims.
    for id,e in pairs(evaluations) do
        if Work.busy(id) or not Driver.bindId(actor,id) or Companion.exportState(id).mode~='HOLD' then e.request:cancel() evaluations[id]=nil end
    end
    local evaluation=evaluations[npcId]
    if evaluation then
        local o=data.orders[evaluation.orderId]
        if not o or o.jobId or o.state~='WAITING' or o.revision~=evaluation.revision or priorities.crafting==0 then
            evaluation.request:cancel() evaluations[npcId]=nil
        else
            local plan,reason=evaluation.request:step()
            if plan or reason then
                evaluation.request:cancel() evaluations[npcId]=nil
                if plan then
                    local offer=directory:upsert('craft:'..o.id,o.revision,'crafting',entry.id)
                    if offer and not offer.jobId then candidates[#candidates+1]={key=offer.key,category='crafting',allowed=true,
                        score=1/(o.sequence+1),order=o,object=evaluation.object,revision=offer.revision} end
                else signal(o,reason) retryAt[o.id]=now+2000 end
            end
        end
    end
    -- At most three craft evaluations plus one bounded haul discovery per NPC.
    for _=1,math.min(3,#orders) do
        orderCursor=orderCursor%#orders+1 local o=data.orders[orders[orderCursor].id]
        if not o.jobId and o.state=='WAITING' and priorities.crafting>0 then
            local object,reason
            if o.surfaceId then object,reason=Surfaces.resolve((Registry.data().craftSurfaces or {})[o.surfaceId],o.surfaceId) end
            local spec,why
            if not reason then spec,why=Recipe.inspect(actor,npc,object,o.recipeId,true,false) end
            if spec then
                local n=0 for _ in pairs(evaluations) do n=n+1 end
                if #candidates==0 and not evaluations[npcId] and n<4 and now>=(retryAt[o.id] or 0) then
                    evaluations[npcId]={orderId=o.id,revision=o.revision,object=object,
                        request=require('EmberRoutesProbe/ProductionChain').new(actor,npc,entry,o.recipeId,o.quantity,object,'offer:'..o.id)}
                end
            else signal(o,reason or why) end
        end
    end
    if priorities.hauling>0 then
        local intent=require('EmberRoutesProbe/LogisticsService').publicOffer(actor,entry,npc)
        if intent then
            local key='haul:'..intent.source..':'..tostring(intent.items[1])
            local offer=directory:upsert(key,1,'hauling',entry.id)
            if offer and not offer.jobId then candidates[#candidates+1]={key=key,revision=1,category='hauling',allowed=true,score=0,intent=intent} end
        end
    end
    local selected,jobId
    for _=1,3 do
        selected=Selector.choose(candidates,priorities) if not selected then return end
        jobId=Registry.id()
        if directory:claim(selected.key,selected.revision,npcId,jobId) then break end
        selected.allowed=false selected=nil
    end
    if not selected then return end
    if evaluations[npcId] then evaluations[npcId].request:cancel() evaluations[npcId]=nil end
    local result
    if selected.order then
        local o=selected.order o.jobId,o.npcId,o.state=jobId,npcId,'CLAIMING' o.revision=o.revision+1
        result=Production.execute(actor,'run',selected.object,npcId,{recipeId=o.recipeId,quantity=o.quantity,
            settlementId=entry.id,taskId=jobId,orderId=o.id,chain=true,nonPreemptive=true})
        if result~='QUEUED' then o.jobId=nil o.npcId=nil o.state='WAITING' signal(o,result) end
    else
        -- HOLD + no unfinished obligation + enabled work policy is the new
        -- ordinary-work admission; discard the old logistics pool's sticky
        -- manual flag only here, after the shared gates and unique claim.
        Work.allowAutomation(npcId)
        selected.intent.jobId=jobId result=Work.assign(actor,npcId,selected.intent)
        if result=='QUEUED' or result=='STARTED' then hauling[selected.key]={npcId=npcId,jobId=jobId} end
    end
    if result~='QUEUED' and result~='STARTED' then directory:release(selected.key,jobId,{effects='KNOWN',obligationsCleared=true}) end
    Signals.changed(npcId) Log.write('DISPATCH','npc='..npcId..' offer='..selected.key..' job='..jobId..' result='..tostring(result))
end
function Service.tick()
    if faultWorld==Registry.data() then return end
    local ok,reason=pcall(advance)
    if not ok then
        -- Gate further dispatch after a backend fault; retained Jobs/claims are
        -- left available for inspection. Never retry an unknown partial effect.
        faultWorld=Registry.data()
        Log.write('DISPATCH','DISPATCH_BLOCKED '..tostring(reason))
    end
end
Probe.publicDispatch=true Probe.tickPublicWork=Service.tick
return Service
