-- Stock-policy pass for PublicWork (split of PublicWork.lua).
-- One enabled rule per call, round-robin; creates a refill order
-- through the order API when the observed count is below minimum.
local S=require 'EmberRoutesProbe/Work/PublicWorkState'
local Service=S.Service
local Ledger=require 'EmberRoutesProbe/Settlement/SettlementLedger'

local function stock(actor,now)
    if S.rulesCache.world~=S.data or S.rulesCache.revision~=S.rulesRevision then
        local list={}
        for _,rule in pairs(S.data.rules) do if rule.enabled then list[#list+1]=rule end end
        table.sort(list,function(a,b) return a.id<b.id end)
        S.rulesCache.world,S.rulesCache.revision,S.rulesCache.list=S.data,S.rulesRevision,list
    end
    local rules=S.rulesCache.list
    local needed={}
    for _,rule in ipairs(rules) do needed[rule.settlementId]=true end
    for id,release in pairs(S.stockWatches) do if not needed[id] then release() S.stockWatches[id]=nil end end
    if #rules==0 then return end
    local Index=require 'EmberRoutesProbe/Warehouse/WarehouseIndex'
    for id in pairs(needed) do if not S.stockWatches[id] then
        S.stockWatches[id]=Index.watch(id,function() end)
    end end
    S.ruleCursor=S.ruleCursor%#rules+1 local rule=rules[S.ruleCursor]
    if rule.activeOrder then
        local o=S.data.orders[rule.activeOrder]
        if not o then S.signalRule(rule,'TASK_RECORD_MISSING') return end
        if o.state=='DONE' or o.state=='CANCELLED' then
            rule.activeOrder=nil rule.nextCheck=now+2000 S.signalRule(rule,nil) Index.refresh(rule.settlementId,false)
        else return end
    end
    if now<(rule.nextCheck or 0) then return end rule.nextCheck=now+1000
    -- Overlapping storage must not trigger two policies for the same originals.
    local Membership=require 'EmberRoutesProbe/Settlement/SettlementMembership'
    local seen={}
    for _,other in ipairs(rules) do if other.product==rule.product then
        local entry=Ledger.view(actor,other.settlementId)
        for _,id in ipairs(entry and Membership.query(entry) or {}) do
            if seen[id] and seen[id]~=other.settlementId then S.signalRule(rule,'CONTAINER_OVERLAP') return end
            seen[id]=other.settlementId
        end
    end end
    local observed
    if require('EmberRoutesProbe/Cooking/CookingOrders').describe(rule.recipeId) then
        observed=require('EmberRoutesProbe/Cooking/CookingService').stock(actor,rule)
    else observed=Index.candidates(actor,rule.settlementId,{fullType=rule.product,limit=1}) end
    if not observed or observed.state~='READY' or not observed.complete then S.signalRule(rule,'INVENTORY_UNKNOWN') return end
    rule.knownCount=observed.knownCount
    if observed.knownCount>=rule.minimum then S.signalRule(rule,nil) return end
    for _,o in pairs(S.data.orders) do
        if o.settlementId==rule.settlementId and o.product==rule.product and o.state~='DONE' and o.state~='CANCELLED' then
            S.signalRule(rule,'MANUAL_ORDER_ACTIVE') return
        end
    end
    local cycle=rule.cycle+1
    local result,id=Service.create(actor,rule.settlementId,rule.recipeId,rule.batch,rule.surfaceId,
        Service.requestId(),rule.preferences)
    S.signalRule(rule,result)
    if result=='ORDER_CREATED' then rule.cycle=cycle rule.activeOrder=id S.data.orders[id].policyId=rule.id end
end

return {stock=stock}
