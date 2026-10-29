-- Durable batch space promise in the existing LaborClaims capacity buckets.
local Record=require 'EmberRoutesProbe/CookingRecord'
local Context=require 'EmberRoutesProbe/CookingContext'
local Store=require 'EmberRoutesProbe/LaborStore'
local Policy=require 'EmberRoutesProbe/CookingPolicy'
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local C={}
function C.free(c,endpoint)
    local free=endpoint.container:getFreeCapacity(c.npc)
    if c.job and c.token and Context.current(c) then return Store.availableCooking(c.job,c.token,endpoint.id,free) end
    return Store.availableCapacity(endpoint.id,free)
end
function C.reserve(c,endpoint,weight)
    if not c.job then return true end
    if not Context.active(c) or c.job.effects~='KNOWN' or not Policy.finite(weight) or weight<=0
        or not Registry.revalidate(endpoint,'put','local-world') or C.free(c,endpoint)+Policy.epsilon<weight then return false end
    local cap=c.job.payload.capacity
    if cap and cap.endpointId==endpoint.id and cap.amount>=weight then return true end
    local j=Record.copy(c.job)
    if not cap then j.payload.claims[#j.payload.claims+1]='cooking:capacity:'..j.id end
    j.payload.capacity={endpointId=endpoint.id,amount=weight} j.obligations.storage=true
    return Context.publish(c,j)
end
function C.delivered(job,endpointId,weight)
    local cap=job.payload.capacity
    if not cap or cap.endpointId~=endpointId then return end
    local remaining=math.max(0,cap.amount-weight)
    if remaining>Policy.epsilon then cap.amount=remaining return end
    job.payload.capacity=nil job.obligations.storage=nil
    for i,key in ipairs(job.payload.claims) do if key=='cooking:capacity:'..job.id then table.remove(job.payload.claims,i) break end end
end
function C.release(c)
    if not c.job.payload.capacity then return true end
    if not Context.current(c) or c.job.effects~='KNOWN' then return false end
    local j=Record.copy(c.job) C.delivered(j,j.payload.capacity.endpointId,j.payload.capacity.amount)
    return Context.publish(c,j)
end
return C
