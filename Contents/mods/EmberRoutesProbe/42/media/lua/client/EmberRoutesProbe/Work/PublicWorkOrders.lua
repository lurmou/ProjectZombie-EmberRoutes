-- Public order / rule API for PublicWork (split of PublicWork.lua).
-- Order creation, prerequisites, delivery orders, commands, stock
-- rules and priority writes. Reads and writes the shared state in
-- PublicWorkState; the dispatch engine itself lives in the sibling
-- PublicWork*.lua modules.
local S=require 'EmberRoutesProbe/Work/PublicWorkState'
local Service=S.Service
local Registry=require 'EmberRoutesProbe/Warehouse/ContainerRegistry'
local Ledger=require 'EmberRoutesProbe/Settlement/SettlementLedger'
local Geometry=require 'EmberRoutesProbe/Settlement/SettlementGeometry'
local Driver=require 'EmberRoutesProbe/Runtime/Driver'
local Recipe=require 'EmberRoutesProbe/Crafting/ProductionRecipe'
local Surfaces=require 'EmberRoutesProbe/Crafting/CraftSurfaces'
local OrderQuery=require 'EmberRoutesProbe/Work/OrderQuery'
local Providers=require 'EmberRoutesProbe/Work/PublicWorkProviders'
local Constants=require 'EmberRoutesProbe/Kernel/Constants'
local Probe=require 'EmberRoutesProbe/Kernel/Boot'
local Signals=require 'EmberRoutesProbe/Work/LaborSignals'

-- Bounded intent receipts, not work history. Unknown/evicted tokens cannot be
-- replayed as a new order. Active orders remain independently idempotent.
function Service.requestId()
    local requests=S.load().requests local id=Registry.id()
    requests[#requests+1]={requestId=id}
    if #requests>128 then table.remove(requests,1) end
    return id
end

-- A policy cycle is a live demand only once its Order exists, not when the
-- threshold is merely configured. Ordinary manual orders remain independent.
-- Share the existing demand clock; no second order directory or suppression store.
function Service.nextDemandSequence()
    local store=S.load()
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
    for _,r in pairs(S.load().rules) do if r.settlementId==scope then list[#list+1]=Service.rule(scope,r.product) end end
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
    S.load().priorities[npcId]=nextP
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
    local store=S.load()
    for _,o in pairs(store.orders) do
        if o.requestId==requestId then
            if not S.sameRequest(o,scope,recipeId,quantity,surfaceId) then return 'REQUEST_CONFLICT' end
            return 'ORDER_CREATED',o.id
        end
    end
    local request=S.requestFor(requestId)
    if not request then return 'REQUEST_EXPIRED' end
    if request.orderId then
        if not S.sameRequest(request,scope,recipeId,quantity,surfaceId) then return 'REQUEST_CONFLICT' end
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
    S.catalogEpoch[scope]=(S.catalogEpoch[scope] or 0)+1
    if Probe.invalidateStudy then Probe.invalidateStudy(scope) end
    Signals.changed() return 'ORDER_CREATED',id
end
function Service.create(actor,scope,recipeId,quantity,surfaceId,requestId,preferences)
    return createOrder(actor,scope,recipeId,quantity,surfaceId,requestId,preferences)
end

-- Called only after the existing bounded BOM found an executable route. One
-- associated demand at a time; its executor owns its own originals and cleanup.
function Service.createPrerequisite(actor,parentId,node)
    local parent=S.load().orders[parentId]
    if not parent or parent.category~='cooking' or parent.state~='WAITING' or parent.jobId
        or parent.pauseRequested or parent.cancelRequested then return 'TASK_CHANGED' end
    local child=parent.prerequisiteId and S.data.orders[parent.prerequisiteId]
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
    local o=S.load().orders[id]
    if not o or o.settlementId~=scope or o.revision~=revision then return 'TASK_CHANGED' end
    -- An order whose category names a provider with its own command is handled
    -- there entirely; the rest (no category) are public craft orders, below.
    local owner=o.category and Providers.get(o.category)
    if owner and owner.command then return owner.command(o,action) end
    if o.jobId then return 'ORDER_ALREADY_CLAIMED' end
    if o.state=='CANCELLED' or o.state=='DONE' then return 'TASK_CHANGED' end
    if action=='return' then o.state='CANCELLED' S.directory:withdraw('craft:'..id)
    elseif action=='stop' then o.state='PAUSED' S.directory:withdraw('craft:'..id)
    elseif action=='resume' and o.state=='PAUSED' then o.state='WAITING'
    else return 'INVALID_COMMAND' end
    Providers.orderCommanded(id)
    if Probe.invalidateStudy then Probe.invalidateStudy(scope) end
    o.revision=o.revision+1 S.catalogEpoch[scope]=(S.catalogEpoch[scope] or 0)+1
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
    local rules=S.load().rules local key=scope..':'..spec.product
    local previous=rules[key] local count=0 for _ in pairs(rules) do count=count+1 end
    if not previous and count>=64 then return 'ORDER_LIMIT' end
    rules[key]={id=key,settlementId=scope,product=spec.product,recipeId=recipeId,minimum=minimum,batch=batch,
        enabled=minimum>0,surfaceId=surfaceId,revision=(previous and previous.revision or 0)+1,
        cycle=previous and previous.cycle or 0,activeOrder=previous and previous.activeOrder,preferences=preferences}
    S.rulesRevision=S.rulesRevision+1
    S.catalogEpoch[scope]=(S.catalogEpoch[scope] or 0)+1
    Signals.changed() return minimum>0 and 'RULE_SAVED' or 'RULE_DISABLED'
end

return Service
