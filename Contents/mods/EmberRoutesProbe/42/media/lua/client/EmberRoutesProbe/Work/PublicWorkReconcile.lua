-- Reconcile / retire-settled pass for PublicWork (split of PublicWork.lua).
-- Providers reconcile their offers, then DONE/CANCELLED orders whose
-- exact Job is closed are retired and their receipts restored.
local S=require 'EmberRoutesProbe/Work/PublicWorkState'
local Clock = require 'EmberRoutesProbe/Kernel/Clock'
local Service=S.Service
local Providers=require 'EmberRoutesProbe/Work/PublicWorkProviders'
local Runtime=require 'EmberRoutesProbe/Runtime/TaskRuntime'
local OrderQuery=require 'EmberRoutesProbe/Work/OrderQuery'
local Signals=require 'EmberRoutesProbe/Work/LaborSignals'

local function reconcile()
    for _,p in ipairs(Providers.all()) do
        if p.reconcile then p.reconcile({orders=S.data.orders,directory=S.directory,catalogEpoch=S.catalogEpoch,signal=S.signal}) end
    end
end
-- A DONE order with neither a job nor craft progress retires only when the
-- provider its category names says so (cooking settles its own jobs).
local function retiresUnclaimed(o)
    local owner=o.category and Providers.get(o.category)
    return owner and owner.retireUnclaimed and owner.retireUnclaimed(o) or false
end
function Service.retireSettled(limit)
    S.load()
    local any=false
    for _,p in ipairs(Providers.all()) do
        if p.hasWork and p.hasWork() then any=true break end
    end
    if not any then return 0 end
    local runtime=Runtime.current()
    if not runtime or not runtime:accepting() or S.world.executionSave and S.world.executionSave.state=='BLOCKED' then return 0 end
    reconcile()
    if not any then return 0 end -- Hauling offer release still runs without public craft orders.
    local Jobs=require 'EmberRoutesProbe/Work/BusinessJobs'
    local count=0
    for id,o in pairs(S.data.orders) do
        local settled=o.state=='DONE' or o.state=='CANCELLED'
        -- An unclaimed cancellation has never acquired originals. Claimed
        -- work must prove its exact Job is closed, not merely absent.
        if settled and (o.jobId and Jobs.canRetire(o.jobId,id)
            or not o.jobId and (not o.craftProgress and (o.state=='CANCELLED' or retiresUnclaimed(o))
                or o.craftProgress and (Jobs.canRetire(o.craftProgress.settledJobId,id)
                    or Jobs.record(o.craftProgress.settledJobId,'CRAFT')==nil))) then
            if not o.jobId or Jobs.retire(o.jobId,id) then
                local request=S.requestFor(o.requestId)
                if not request then
                    request={requestId=o.requestId} S.data.requests[#S.data.requests+1]=request
                    if #S.data.requests>128 then table.remove(S.data.requests,1) end
                end
                request.orderId,request.settlementId,request.recipeId=o.id,o.settlementId,o.recipeId
                request.quantity,request.surfaceId=o.quantity,o.surfaceId
                S.directory:release('craft:'..id,o.jobId,{effects='KNOWN',obligationsCleared=true})
                S.directory:withdraw('craft:'..id)
                for _,r in pairs(S.data.rules) do if r.activeOrder==id then
                    r.activeOrder=nil r.nextCheck=Clock.nowMs()+2000
                    require('EmberRoutesProbe/Warehouse/WarehouseIndex').refresh(r.settlementId,false)
                end end
                Providers.orderRetired(id,S.readyWorkers)
                for key in pairs(S.retryAt) do if string.sub(key,1,#id+1)==id..':' then S.retryAt[key]=nil end end
                S.data.orders[id]=nil count=count+1
                if count>=limit then break end
            end
        end
    end
    if count>0 then OrderQuery.invalidate() Signals.changed() end
    return count
end

return {reconcile=reconcile}
