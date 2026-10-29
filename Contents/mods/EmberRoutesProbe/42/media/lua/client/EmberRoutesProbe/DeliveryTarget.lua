-- Dynamic player adapter for the existing haul Job/session/claims pipeline.
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local Ledger=require 'EmberRoutesProbe/SettlementLedger'
local Producers=require 'EmberRoutesProbe/LaborProducers'
local Geometry=require 'EmberRoutesProbe/SettlementGeometry'
local Transfer=require 'EmberRoutesProbe/WorkTransfer'
local D={}
local function service() return require 'EmberRoutesProbe/DeliveryService' end
function D.order(r) return service().order(r.orderId) end
function D.allowed(r)
    local o=D.order(r)
    local e=Ledger.get(r.settlementId)
    local m=require('EmberRoutesProbe/MembershipService').view(r.npcId)
    return o and o.jobId==r.id and o.npcId==r.npcId and o.requesterId==r.requesterId
        and o.settlementId==r.settlementId and e and e.factionId==Ledger.data().factionId
        and m and m.settlementId==e.id and m.factionId==e.factionId
end
function D.endpoint(c)
    local o=D.order(c.job)
    local actor=o and service().actor(o,c.actor)
    if not actor then return end
    return {id='player:'..o.requesterId,playerId=o.requesterId,object=actor,container=actor:getInventory()}
end
function D.endpointValid(c,e)
    local current=D.endpoint(c)
    return current and e and e.playerId==current.playerId and e.object==current.object and e.container==current.container
end
function D.observe(c)
    local r=c.job local e=Ledger.get(r.settlementId) local o=D.order(r)
    local target=D.endpoint(c)
    if not e or not o or o.cancelled or not D.allowed(r) or not target
        or service().distanceToSettlement(e,c.actor:getX(),c.actor:getY())>50 then r.returning=true end
    local now=getTimestampMs()
    local p=target and {x=c.actor:getX(),y=c.actor:getY(),z=c.actor:getZ()} or nil
    local old=c.playerPosition
    if not p or not old or p.x~=old.x or p.y~=old.y or p.z~=old.z
        or c.actor.isPlayerMoving and c.actor:isPlayerMoving() then c.playerStoppedAt=now end
    c.playerPosition=p
    if c.body and now>=(c.nextThreat or 0) then
        c.nextThreat=now+500
        local sneak=false
        if e and not Geometry.inside(e,c.npc:getX(),c.npc:getY()) then
            local spotted=c.npc.getSpottedList and c.npc:getSpottedList()
            -- Fresh observed list + CanSee, never a global proximity list.
            if not spotted or not c.npc.CanSee or spotted:size()>64 then return false,'DELIVERY_OBSERVATION_UNAVAILABLE' end
            for i=0,spotted:size()-1 do
                local z=spotted:get(i)
                if z and instanceof(z,'IsoZombie') and not z:isDead() and c.npc:CanSee(z) then sneak=true break end
            end
        end
        if not c.body.sneak(sneak) then return false,'CONTROL_REQUIRED' end
    end
    return true
end
function D.still(c)
    local p=c.playerPosition local actor=c.actor
    return p and not actor:isDead() and p.x==actor:getX() and p.y==actor:getY() and p.z==actor:getZ()
        and not (actor.isPlayerMoving and actor:isPlayerMoving())
        and c.playerStoppedAt and getTimestampMs()-c.playerStoppedAt>=500
end
function D.room(c,item)
    local e=D.endpoint(c) if not e then return false end
    return e.container:hasRoomFor(c.actor,item)
        and c.actor:getMaxWeight()-c.actor:getInventoryWeight()>=item:getUnequippedWeight()
end
function D.handoff(c,e,item)
    local o=D.order(c.job) local area=Ledger.get(c.job.settlementId)
    local snapshot=c.body and c.body.snapshot()
    -- The owned transfer itself sets native action bit 4. It must not invalidate
    -- its own isValid/perform; every movement/path/posture bit must still be zero.
    local attempt=c.job.activeAttempt
    local stopped=snapshot and snapshot.available and (snapshot.nativeStopped
        or snapshot.nativeMask==4 and attempt and attempt.kind=='PUT' and attempt.itemId==item:getID())
    return not c.job.returning and o and not o.cancelled and area and D.allowed(c.job)
        and service().distanceToSettlement(area,c.actor:getX(),c.actor:getY())<=50
        and D.endpointValid(c,e) and D.still(c) and Transfer.reachable(c.npc,e)
        and stopped and D.room(c,item)
end
function D.move(c)
    local point,lastRequest
    local function poll()
        if c.job.returning or not D.endpoint(c) then return 'FAILED','DELIVERY_TARGET_CHANGED' end
        local e=D.endpoint(c) local actor=c.actor local now=getTimestampMs()
        if Transfer.reachable(c.npc,e) then
            if not c.body.stop() then return 'FAILED','CONTROL_REQUIRED' end
            local snapshot=c.body.snapshot()
            return snapshot.available and snapshot.nativeStopped and 'PASSED' or 'WAIT'
        end
        local moved=not point or math.floor(actor:getZ())~=math.floor(point.z)
            or (actor:getX()-point.x)^2+(actor:getY()-point.y)^2>=1
        local motion=EmberRoutesProbeJava.motionResult(c.npc)
        if not point or moved and now-lastRequest>=1000 then
            point={x=actor:getX(),y=actor:getY(),z=actor:getZ()} lastRequest=now
            local result=require('EmberRoutesProbe/Driver').move({handle=c.npc,id=c.job.npcId},actor,point,c.body)
            if not string.find(result,'^MOVE_REQUESTED') then return 'FAILED',result end
        elseif motion~='MOVING' and now-lastRequest>=1000 then return 'FAILED','DELIVERY_PATH_BLOCKED' end
        return 'WAIT'
    end
    return {timeout=185000,start=function() return poll() end,poll=poll}
end
function D.returnTarget(c,item)
    local e=Registry.resolve(c.job.source,'put',c.job.scopeId)
    local area=Ledger.get(c.job.settlementId)
    local p=e and Registry.describe(e.id)
    if e and area and p and Geometry.inside(area,p.x,p.y) and Registry.logistics(e)=='STORAGE'
        and Registry.accepts(e,item) and e.container:hasRoomFor(c.npc,item)
        and require('EmberRoutesProbe/LaborStore').availableFor(c.token,e.id,item:getID(),e.container:getFreeCapacity(c.npc))>=item:getUnequippedWeight() then return e end
end
Producers.register('DELIVERY',{
    check=function(c) return not not D.allowed(c.job) end,
    transfer=function(c,item,from,to)
        if not D.allowed(c.job) then return false end
        local own=c.npc:getInventory()
        if to==own then
            local o=D.order(c.job)
            local source=Registry.resolve(c.job.source,'take',c.job.scopeId)
            return not c.job.returning and o and not o.cancelled and source and source.container==from
                and Registry.logistics(source)=='STORAGE' and Producers.freeCarry(c.npc)>=item:getUnequippedWeight()
        end
        if c.destination and c.destination.playerId then return from==own and D.handoff(c.deliveryContext or c,c.destination,item) end
        local target=c.destination and Registry.revalidate(c.destination,'put',c.job.scopeId)
        local p=target and Registry.describe(target.id) local area=Ledger.get(c.job.settlementId)
        return c.job.returning and from==own and target and to==target.container and p and area
            and Geometry.inside(area,p.x,p.y) and Registry.logistics(target)=='STORAGE' and Registry.accepts(target,item)
    end})
return D
