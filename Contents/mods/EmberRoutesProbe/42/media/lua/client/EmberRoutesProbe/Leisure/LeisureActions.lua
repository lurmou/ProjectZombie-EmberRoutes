-- Movement remains outside native timed actions: moving clears native queues.
local Config=require 'EmberRoutesProbe/Leisure/LeisureConfig'
local A={}
-- Action mapping stays data-driven alongside the candidate registry: adding an
-- activity means one builder here and one LeisureRegistry def in LeisureService.
local builders={
    SMOKE=function(c) return require('EmberRoutesProbe/Leisure/LeisureSmoke').new(c) end,
    FITNESS=function(c) return require('EmberRoutesProbe/Leisure/LeisureFitness').new(c) end,
    SOCIAL=function(c) return require('EmberRoutesProbe/Activity/SocialActions').new(c) end,
    SIT=function(c) return {kind='Sequence',children={
        require('EmberRoutesProbe/SelfCare/SelfCareFurniture').move(c,'REST'),
        require('EmberRoutesProbe/Leisure/LeisureSit').new(c)}} end,
}
function A.move(c,point,arrived,reached)
    local moving,deadline=false,nil
    return {kind='Action',run=function()
        if not c.valid() then return 'Failure' end
        local target
        if type(point)=='function' then target=point() else target=point end
        if not target then return 'Failure' end
        local atTarget=math.floor(c.npc:getZ())==target.z and (c.npc:getX()-target.x)^2+(c.npc:getY()-target.y)^2<=0.8^2
        if atTarget and reached then atTarget=reached(target)==true end
        if atTarget then
            if moving and not c.body.stop() then return 'Running' end
            moving=false
            return (not arrived or arrived()) and 'Success' or 'Running'
        end
        if moving then
            -- A parked carrier is not a failed path: hold the step and its clock.
            if require('EmberRoutesProbe/Runtime/Driver').suspended(c.npc) then
                deadline=getTimestampMs()+35000
                return 'Running'
            end
            if getTimestampMs()>deadline or EmberRoutesProbeJava.motionResult(c.npc)~='MOVING' then return 'Failure' end
        elseif c.budget.paths>0 then
            c.budget.paths=c.budget.paths-1
            local ok,result=c.body.move(c.actor,target)
            if not ok or not string.find(result or '','^MOVE_REQUESTED') then return 'Failure' end
            moving=true deadline=getTimestampMs()+35000
        end
        return 'Running'
    end,halt=function() return c.body.stop() end}
end
function A.new(c)
    if c.payload.leisure.roleDuty then return require('EmberRoutesProbe/Activity/ActivityRoleActions').new(c) end
    local l=c.payload.leisure
    if l.zoneVisit then
        local Zones=require 'EmberRoutesProbe/Settlement/SettlementZones'
        local function destination(point)
            if l.zoneVisit.eventId then
                return require('EmberRoutesProbe/Activity/ActivityService').destination(c.payload.settlementId,c.job.npcId,l.zoneVisit,point)
            end
            return Zones.destination(c.payload.settlementId,l.zoneVisit,point)
        end
        local function target()
            if not destination(l.point) then
                c.reason='LIFE_ZONE_CHANGED' return nil
            end
            return l.point
        end
        local move=A.move(c,target,nil,function()
            return destination({x=c.npc:getX(),y=c.npc:getY(),z=math.floor(c.npc:getZ())})
        end)
        return {kind='Action',run=function()
            local result=move.run() if result~='Success' then return result end
            local entry=require('EmberRoutesProbe/Settlement/MembershipService').entry(c.job.npcId,c.payload.settlementId)
            local actual={x=c.npc:getX(),y=c.npc:getY(),z=math.floor(c.npc:getZ())}
            if not entry or not target() or not destination(actual)
                or not require('EmberRoutesProbe/Leisure/LeisureService').standable(entry,l.point,{c.npc}) then
                c.reason='LIFE_ZONE_TARGET_CHANGED' return 'Failure'
            end
            if l.zoneVisit.eventId then
                local binding=require('EmberRoutesProbe/Runtime/Driver').bindId(c.actor,c.job.npcId)
                if not binding or binding.handle~=c.npc
                    or not require('EmberRoutesProbe/Activity/ActivityService').arrived(c.actor,binding,l.zoneVisit,c.job.id) then
                    c.reason='ACTIVITY_ARRIVAL_REJECTED' return 'Failure'
                end
            end
            -- Position fact only: no timed entertainment and no relief reward.
            l.finished=true
            if not c.persist() then l.finished=nil error('LIFE_ZONE_ARRIVAL_NOT_PERSISTED') end
            return 'Success'
        end,halt=move.halt}
    end
    local build=builders[l.activity]
    if build then return build(c) end
    local untilHours,checkedAt
    local look=require('EmberRoutesProbe/Leisure/LeisureLook').new(c)
    local wait=require('EmberRoutesProbe/Leisure/LeisureTimed').new(c,{
        start=function()
            local duration=l.brief and Config.briefMinutes or l.activity=='STROLL' and Config.strollMinutes or Config.observeMinutes
            untilHours=l.ambient and l.untilHours or getGameTime():getWorldAgeHours()+duration/60
            if c.leisureTarget then c.npc:faceThisObject(c.leisureTarget) end
        end,
        update=function()
            look.update()
            if c.leisureTarget then
                -- Target-existence check throttled: it costs a square lookup plus
                -- a container scan per frame otherwise. 500ms staleness only
                -- delays the 'Failure' transition by the same window.
                local now=getTimestampMs()
                if now>=(checkedAt or 0) then
                    checkedAt=now+500
                    local sq=c.leisureTarget:getSquare()
                    if not sq or not sq:getObjects():contains(c.leisureTarget) then return 'Failure' end
                end
            end
            return getGameTime():getWorldAgeHours()>=untilHours and 'Success' or 'Running'
        end,
        complete=function() look.clear() return true end,
        stop=function() look.clear() end})
    if l.point then return {kind='Sequence',children={A.move(c,l.point),wait}} end
    return wait
end
return A
