-- A selected kitchen constrains preparation as well as stove discovery.
local Zones=require 'EmberRoutesProbe/SettlementZones'
local Policy=require 'EmberRoutesProbe/JobPolicyService'
local K={}
function K.leaf(c)
    local id,revision,zone,point,requested,deadline
    local areaIndex,x,y,attempts=1,nil,nil,0
    return {kind='Action',run=function()
        local wanted=Policy.get(c.job.scopeId,'cooking').kitchenZoneId
        if not wanted or wanted=='' then return 'Success' end
        local current=Zones.get(wanted)
        if not current or not current.enabled or current.settlementId~=c.job.scopeId then
            c.reason='KITCHEN_ZONE_UNAVAILABLE' return 'Failure'
        end
        if id~=wanted or revision~=current.revision then
            id,revision,zone,point,requested=wanted,current.revision,current,nil,false
            areaIndex,x,y,attempts=1,nil,nil,0
        end
        if Zones.contains(zone,c.npc:getX(),c.npc:getY(),c.npc:getZ()) then
            local snapshot=c.body.snapshot()
            if not snapshot.nativeStopped then c.body.stop() return 'Running' end
            return 'Success'
        end
        if requested then
            local status=EmberRoutesProbeJava.motionResult(c.npc)
            if status=='MOVING' and getTimestampMs()<deadline then return 'Running' end
            requested,point=false,nil attempts=attempts+1
            if attempts>=8 then c.reason='KITCHEN_UNREACHABLE' return 'Failure' end
        end
        if not point then
            local allowance=math.min(16,c.budget.scan or 0) c.budget.scan=(c.budget.scan or 0)-allowance
            for _=1,allowance do
                local a=zone.areas[areaIndex]
                if not a then c.reason='KITCHEN_NO_WORKSPACE' return 'Failure' end
                x,y=x or a.x,y or a.y
                local px,py=x,y x=x+1
                if x>=a.x+a.w then x=a.x y=y+1 end
                if y>=a.y+a.h then areaIndex=areaIndex+1 x=nil y=nil end
                local sq=getCell():getGridSquare(px,py,a.z or 0)
                if sq and sq:TreatAsSolidFloor() and not sq:isSolid() and not sq:isSolidTrans() then
                    point={x=px+0.5,y=py+0.5,z=a.z or 0} break
                end
            end
            if not point then return 'Running' end
        end
        local snapshot=c.body.snapshot()
        if not snapshot.nativeStopped then c.body.stop() return 'Running' end
        local ok,result=c.body.move(c.actor,point)
        if not ok or type(result)~='string' or not string.find(result,'^MOVE_REQUESTED') then
            c.reason=result or 'KITCHEN_MOVE_FAILED' return 'Failure'
        end
        requested=true deadline=getTimestampMs()+185000 return 'Running'
    end}
end
return K
