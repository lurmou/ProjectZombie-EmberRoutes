-- Read-only projection of the public order ledger. Every function here answers a
-- question about orders and nothing else: no scheduler state, no phase clocks, no
-- provider lifecycle. That is what lets domain code depend on it while PublicWork
-- stays free to change its dispatch internals.
local Registry=require 'EmberRoutesProbe/Warehouse/ContainerRegistry'
local Providers=require 'EmberRoutesProbe/Work/PublicWorkProviders'
local OrderStore=require 'EmberRoutesProbe/Work/OrderStore'
local CraftYield=require 'EmberRoutesProbe/Crafting/ProductionYield'
local Q={}
local Business
local function business()
    Business=Business or require 'EmberRoutesProbe/Work/BusinessJobs'
    return Business
end
-- Both caches key off the ledger table identity: a world swap replaces the
-- document, so a stale index can never survive one.
local cachedLedger
local ordersScopes,prioritiesCache={},{}
local function ledger()
    local d=OrderStore.data()
    if d~=cachedLedger then
        cachedLedger=d
        ordersScopes,prioritiesCache={},{}
    end
    return d
end
-- Called by the command side after any change to the order key set.
function Q.invalidate()
    -- Only the order-id projection depends on the key set. Priority entries
    -- already validate against their live priority table and revision, so a
    -- blanket flush there just forced every NPC to rebuild on the next pass.
    ordersScopes={}
end
-- Id+sequence projection of one settlement's orders for the decide scan. The
-- decision loop reads live order fields by id; only the iteration order needs
-- materializing, and only when order keys actually change.
local function orderIds(scope)
    local ids=ordersScopes[scope]
    if ids then return ids end
    ids={}
    for _,o in pairs(ledger().orders) do
        if o.settlementId==scope then ids[#ids+1]={id=o.id,sequence=o.sequence} end
    end
    table.sort(ids,function(a,b) return a.sequence<b.sequence end)
    ordersScopes[scope]=ids
    return ids
end
local function live(o)
    return o.state~='DONE' and o.state~='CANCELLED' and not o.cancelled and not o.parentOrderId
end
-- Public craft/stock demand has no chosen box until its real output assets do.
-- Never infer a destination from product type or the set of accepting boxes.
local function outputHasDestination(o,destinationId)
    -- Destination resolvability does not depend on the asset, so resolve once
    -- instead of on every row.
    if not Registry.resolve(destinationId,'put','local-world') then return false end
    local r=o.jobId and business().record and business().record(o.jobId,'CRAFT')
    for _,asset in ipairs(r and r.outputs or {}) do
        if asset.fullType==o.product and asset.destination==destinationId then return true end
    end
    -- Prior batch transfer facts remain relevant while the same demand is live.
    for _,asset in ipairs(r and r.outputAllocation and r.outputAllocation.assets or {}) do
        for _,target in ipairs(asset.fullType==o.product and asset.targets or {}) do
            if target.destinationId==destinationId then return true end
        end
    end
    return false
end
function Q.deliveryOverlapReason(o,line)
    if not o.destinationId or not o.overlapSequence or not live(o) then return end
    for _,other in pairs(ledger().orders) do
        if live(other) and other.settlementId==o.settlementId and other.product==line.fullType
            and other.sequence<o.overlapSequence and outputHasDestination(other,o.destinationId) then
            return other.policyId and 'CYCLE_ACTIVE' or 'MANUAL_ORDER_ACTIVE'
        end
    end
end
-- Called at the existing public output transfer boundary once routing has
-- selected a real box. Unknown destinations never block production by type alone.
function Q.outputOverlapReason(orderId,fullType,destinationId)
    local o=ledger().orders[orderId]
    if not o or not live(o) or o.product~=fullType or not Registry.resolve(destinationId,'put','local-world') then return end
    local deliveries=Registry.data().deliveryOrders
    for _,other in pairs(deliveries and deliveries.orders or {}) do
        if live(other) and other.overlapSequence and other.overlapSequence<o.sequence
            and other.settlementId==o.settlementId and other.destinationId==destinationId then
            for _,line in ipairs(other.items) do
                if line.fullType==fullType and line.delivered<line.quantity then return 'MANUAL_ORDER_ACTIVE' end
            end
        end
    end
end
-- One settlement:product -> earliest live order index for a whole list read.
-- Without it every row rescans all orders, which is O(n^2) on the UI list path.
local function firstLiveByProduct()
    local map={}
    for _,other in pairs(ledger().orders) do
        if other.state~='DONE' and other.state~='CANCELLED' and not other.parentOrderId then
            local key=other.settlementId..':'..tostring(other.product)
            local current=map[key]
            if not current or other.sequence<current.sequence then map[key]=other end
        end
    end
    return map
end
local function reasonOf(o,firstMap)
    if o.state=='DONE' or o.state=='CANCELLED' or o.parentOrderId then return end
    local deliveries=Registry.data().deliveryOrders
    for _,delivery in pairs(deliveries and deliveries.orders or {}) do
        if delivery.destinationId and outputHasDestination(o,delivery.destinationId) then
            local reason=Q.outputOverlapReason(o.id,o.product,delivery.destinationId)
            if reason then return reason end
        end
    end
    local first
    if firstMap then
        first=firstMap[o.settlementId..':'..tostring(o.product)]
    else
        for _,other in pairs(ledger().orders) do
            if other.settlementId==o.settlementId and other.product==o.product
                and other.state~='DONE' and other.state~='CANCELLED' and not other.parentOrderId
                and (not first or other.sequence<first.sequence) then first=other end
        end
    end
    if first and first~=o and not o.parentOrderId and (first.policyId~=nil)~=(o.policyId~=nil) then
        return first.policyId and 'CYCLE_ACTIVE' or 'MANUAL_ORDER_ACTIVE'
    end
end
function Q.overlapReason(id)
    local o=ledger().orders[id]
    return o and reasonOf(o)
end
-- Exposed for the decide scan, which already holds the order it wants to test.
function Q.reasonFor(o,firstMap) return reasonOf(o,firstMap) end
function Q.firstLiveByProduct() return firstLiveByProduct() end
function Q.orderIds(scope) return orderIds(scope) end
function Q.order(id)
    local o=ledger().orders[id] if not o then return end
    local copy={} for k,v in pairs(o) do copy[k]=k=='craftProgress' and CraftYield.copy(v) or v end copy.reason=reasonOf(o) or copy.reason return copy
end
function Q.orders(scope)
    if scope==nil then return {} end
    local firstMap=firstLiveByProduct()
    local rows={}
    for _,key in ipairs(orderIds(scope)) do
        local o=ledger().orders[key.id]
        if o then local r={} for k,v in pairs(o) do r[k]=k=='craftProgress' and CraftYield.copy(v) or v end r.reason=reasonOf(o,firstMap) or r.reason rows[#rows+1]=r end
    end
    return rows
end
function Q.categories() return Providers.categories() end
function Q.priorities(npcId)
    local p=ledger().priorities[npcId] or {}
    local revision=p.revision or 0
    local cached=prioritiesCache[npcId]
    if cached and cached.source==p and cached.revision==revision then return cached.value end
    local result={revision=revision}
    for _,cat in ipairs(Providers.categories()) do
        local def=Providers.get(cat)
        result[cat]=p[cat]==nil and (def and def.defaultPriority or 3) or p[cat]
    end
    if result.crafting==nil then result.crafting=p.crafting==nil and 3 or p.crafting end
    if result.hauling==nil then result.hauling=p.hauling==nil and 3 or p.hauling end
    prioritiesCache[npcId]={source=p,revision=revision,value=result}
    return result
end
return Q
