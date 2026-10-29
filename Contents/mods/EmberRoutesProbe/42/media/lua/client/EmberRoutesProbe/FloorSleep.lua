-- Ground fallback inside the existing personal Job and resource claims.
local Membership=require 'EmberRoutesProbe/MembershipService'
local Geometry=require 'EmberRoutesProbe/SettlementGeometry'
local Store=require 'EmberRoutesProbe/LaborStore'
local F={}
function F.key(p) return 'repose:floor:'..p.x..':'..p.y..':'..p.z end
function F.scan(npc,id)
    local entry=Membership.entry(id)
    local revision=entry and entry.revision
    local points={}
    local x,y,z=math.floor(npc:getX()),math.floor(npc:getY()),math.floor(npc:getZ())
    for radius=0,4 do
        for dx=-radius,radius do for dy=-radius,radius do
            if math.max(math.abs(dx),math.abs(dy))==radius then
                points[#points+1]={x=x+dx,y=y+dy,z=z}
            end
        end end
    end
    local index=1
    return {step=function(_,budget)
        local current=Membership.entry(id)
        if not entry or not current or current.id~=entry.id or current.revision~=revision then return nil,true end
        for _=1,budget do
            local p=points[index] index=index+1
            if not p then return nil,true end
            if Geometry.inside(entry,p.x,p.y) and not Store.resourceOwner(F.key(p))
                and EmberRoutesProbeJava.floorSleepSafe(npc,p.x,p.y,p.z) then
                p.settlementId=entry.id return p,true
            end
        end
        return nil,false
    end}
end
function F.valid(c)
    local p=c.payload.floorSite
    local entry=Membership.entry(c.job.npcId)
    local claim=p and Store.resourceOwner(F.key(p))
    return p and entry and entry.id==p.settlementId and Geometry.inside(entry,p.x,p.y)
        and claim and claim.taskId==c.job.id and EmberRoutesProbeJava.floorSleepSafe(c.npc,p.x,p.y,p.z)
end
function F.move(c)
    local moving=false
    return {kind='Action',run=function()
        if not c.valid() or not F.valid(c) then c.reason='FLOOR_SITE_CHANGED' return 'Failure' end
        local p=c.payload.floorSite
        if math.floor(c.npc:getX())==p.x and math.floor(c.npc:getY())==p.y and math.floor(c.npc:getZ())==p.z then
            return 'Success'
        end
        if moving then
            if EmberRoutesProbeJava.motionResult(c.npc)~='MOVING' then c.reason='FLOOR_PATH_FAILED' return 'Failure' end
        elseif c.budget.paths>0 then
            c.budget.paths=c.budget.paths-1
            local ok=c.body.move(c.actor,{x=p.x+0.5,y=p.y+0.5,z=p.z})
            if not ok then c.reason='FLOOR_PATH_FAILED' return 'Failure' end
            moving=true
        end
        return 'Running'
    end,halt=function() return c.body.stop() end}
end
function F.posture(c)
    local deadline,started
    return {enter=function()
        if not c.valid() or not F.valid(c) then c.reason='FLOOR_SITE_CHANGED' return 'Failure' end
        deadline=deadline or getTimestampMs()+12000
        if getTimestampMs()>deadline then c.reason='FLOOR_POSE_TIMEOUT' return 'Failure' end
        if not started then
            if not c.body.furniture(nil,'FLOOR') then return 'Running' end
            started=true
        end
        return EmberRoutesProbeJava.bedPoseReady(c.npc,'Asleep') and 'Success' or 'Running'
    end,leave=function()
        if not c.sameAttempt() or not c.body.retained() or not c.body.stop() then return false end
        return not c.npc:isSitOnGround() and c.npc:getCurrentActionContextStateName()=='idle'
    end}
end
return F
