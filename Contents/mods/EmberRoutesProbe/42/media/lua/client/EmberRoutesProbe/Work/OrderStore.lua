-- Public order ledger: the persisted `root.publicWork` document plus the schema
-- checks that must pass before anything reads it. This module owns no scheduler
-- state, no phase clock and no provider lifecycle; PublicWork resets those.
-- Splitting the two is what lets domain code read orders without depending on
-- the dispatcher.
local S={}
local world,data=nil,nil
local function integer(n,min,max)
    return type(n)=='number' and n==n and n==math.floor(n) and n>=min and n<=max
end
-- Accepted format is format=1. Every rejection names the field group it failed
-- on so a corrupt save is diagnosable from the console line alone.
local function validate(root)
    local value=root.publicWork
    if value and (type(value)~='table' or value.format~=1 or type(value.orders)~='table' or type(value.priorities)~='table') then
        return nil,'PUBLIC_WORK_FORMAT_INVALID'
    end
    value=value or {format=1,sequence=0,orders={},priorities={},rules={}}
    value.rules=value.rules or {}
    value.requests=value.requests or {}
    if type(value.requests)~='table' or #value.requests>128 then return nil,'PUBLIC_REQUEST_INVALID' end
    local requestIds={}
    for _,r in ipairs(value.requests) do
        if type(r)~='table' or type(r.requestId)~='string' or r.requestId=='' or requestIds[r.requestId]
            or (r.orderId~=nil and (type(r.orderId)~='string' or type(r.settlementId)~='string'
                or type(r.recipeId)~='string' or type(r.quantity)~='number')) then
            return nil,'PUBLIC_REQUEST_INVALID'
        end
        requestIds[r.requestId]=true
    end
    if not integer(value.sequence,0,1e12) or type(value.rules)~='table' then return nil,'PUBLIC_WORK_FORMAT_INVALID' end
    for id,p in pairs(value.priorities) do
        if type(id)~='string' or type(p)~='table' or not integer(p.revision,1,1e12) then return nil,'PUBLIC_PRIORITY_INVALID' end
        for k,v in pairs(p) do if k~='revision' and not integer(v,0,4) then return nil,'PUBLIC_PRIORITY_INVALID' end end
    end
    local n=0
    for id,r in pairs(value.rules) do
        n=n+1
        if n>64 or type(r)~='table' or r.id~=id or type(r.settlementId)~='string' or type(r.recipeId)~='string'
            or type(r.product)~='string' or type(r.enabled)~='boolean' or not integer(r.minimum,0,9999)
            or not integer(r.batch,1,9999) or not integer(r.revision,1,1e12) or not integer(r.cycle,0,1e12) then
            return nil,'PUBLIC_RULE_INVALID'
        end
        r.nextCheck=nil -- Wall-clock deadlines are transient, not restored timestamps.
    end
    local CraftYield=require 'EmberRoutesProbe/Crafting/ProductionYield'
    local count=0
    for key,o in pairs(value.orders) do
        count=count+1
        if count>256 or type(o)~='table' or o.id~=key or type(o.settlementId)~='string'
            or type(o.recipeId)~='string' or type(o.requestId)~='string' or type(o.product)~='string'
            or not integer(o.quantity,1,9999) or not integer(o.target,1,1e6) or not integer(o.sequence,1,value.sequence)
            or not integer(o.revision,1,1e12) or type(o.state)~='string'
            or (o.jobId~=nil and (type(o.jobId)~='string' or type(o.npcId)~='string')) then
            return nil,'PUBLIC_ORDER_INVALID'
        end
        if o.category=='cooking' and (not integer(o.delivered or 0,0,o.target)
            or o.pauseRequested~=nil and type(o.pauseRequested)~='boolean'
            or o.cancelRequested~=nil and type(o.cancelRequested)~='boolean'
            or o.stopBatchRequested~=nil and type(o.stopBatchRequested)~='boolean') then
            return nil,'PUBLIC_ORDER_INVALID'
        end
        if o.category~='cooking' and not CraftYield.progress(o.craftProgress,o.target) then
            return nil,'PUBLIC_PROGRESS_INVALID'
        end
        if o.parentOrderId~=nil and (type(o.parentOrderId)~='string' or o.parentOrderId==o.id)
            or o.prerequisiteId~=nil and (type(o.prerequisiteId)~='string' or o.prerequisiteId==o.id) then
            return nil,'PUBLIC_ORDER_INVALID'
        end
    end
    return value
end
-- Caller closes over the returned table. The world identity is exposed so a
-- caller can detect a world swap without keeping its own copy of the pointer.
function S.load(root)
    if root~=world then
        local value,reason=validate(root)
        if not value then error(reason) end
        root.publicWork=value
        world,data=root,value
    end
    return data
end
function S.data() return data end
function S.world() return world end
function S.reset() world,data=nil,nil end
return S
