local Sites=require 'EmberRoutesProbe/ReposeSites'
local Furniture={}
local function near(npc,object)
    local s=object:getSquare() local current=npc:getCurrentSquare()
    return current and current:getZ()==s:getZ() and math.abs(current:getX()-s:getX())+math.abs(current:getY()-s:getY())<=1
        and current:canReachTo(s)
end
function Furniture.seat(c,proof,maxPathLength,sleep)
    local moving,deadline,busyUntil=false,nil,nil
    return {kind='Action',run=function()
        if not c.valid() then return 'Failure' end
        local site,why=Sites.resolve(proof,c.actor,c.npc,c.job.npcId,sleep and 'SLEEP' or 'REST',c.job.id)
        if not site then c.reason=why return 'Failure' end
        if moving then
            local result=EmberRoutesProbeJava.motionResult(c.npc)
            if result=='REACHED' then
                if EmberRoutesProbeJava.reachedSeat(c.npc)~=site.object then c.reason='SITE_CHANGED' return 'Failure' end
                return 'Success'
            end
            if result~='MOVING' or getTimestampMs()>deadline then c.reason='SITE_PATH_FAILED' return 'Failure' end
        elseif c.budget.paths>0 then
            c.budget.paths=c.budget.paths-1
            local ok,result=c.body.move(c.actor,{furniture=site.object,maxPathLength=maxPathLength,sleep=sleep})
            if result=='MOVE_REQUESTED_SEAT' then
                moving=true deadline=getTimestampMs()+180000
            elseif result=='NATIVE_ACTION_BUSY' then
                busyUntil=busyUntil or (getTimestampMs()+3000)
                if getTimestampMs()>busyUntil then c.reason='NATIVE_ACTION_BUSY' return 'Failure' end
            else
                c.reason='SITE_PATH_FAILED'
                return 'Failure'
            end

        end
        return 'Running'
    end,halt=function() return c.body.stop() end}
end
function Furniture.move(c,seatKind)
    if c.payload.kind=='SLEEP' then return require('EmberRoutesProbe/SleepBed').move(c) end
    if seatKind=='REST' and c.payload.kind=='LEISURE' then -- Full native furniture approach. A neighboring square is never arrival proof.
        return Furniture.seat(c,c.payload.site)
    end
    local moving,deadline,busyUntil=false,nil,nil
    return {kind='Action',run=function()
        if not c.valid() then return 'Failure' end
        local site,why=Sites.resolve(c.payload.site,c.actor,c.npc,c.job.npcId,seatKind or c.payload.kind,c.job.id)
        if not site then c.reason=why return 'Failure' end
        if near(c.npc,site.object) then
            if not c.body.stop() then c.reason='SITE_PATH_FAILED' return 'Failure' end
            return 'Success'
        end
        if moving then
            local result=EmberRoutesProbeJava.motionResult(c.npc)
            if result=='REACHED' then c.reason='SITE_PATH_FAILED' return 'Failure' end
            if result~='MOVING' or getTimestampMs()>deadline then c.reason='SITE_PATH_FAILED' return 'Failure' end
            return 'Running'
        end
        if c.budget.paths<1 then return 'Running' end
        c.budget.paths=c.budget.paths-1
        local square=site.object:getSquare() local excluded={} local chosen
        for _=1,8 do
            local adjacent=AdjacentFreeTileFinder.Find(square,c.npc,excluded)
            if not adjacent then break end
            if adjacent:getZ()==square:getZ() and math.abs(adjacent:getX()-square:getX())+math.abs(adjacent:getY()-square:getY())==1
                and adjacent:TreatAsSolidFloor() and not adjacent:isSolid() and not adjacent:isSolidTrans()
                and adjacent:canReachTo(square) then chosen=adjacent break end
            excluded[#excluded+1]=adjacent
        end
        if not chosen then c.reason='SITE_PATH_FAILED' return 'Failure' end
        local ok,result=c.body.move(c.actor,{x=chosen:getX()+0.5,y=chosen:getY()+0.5,z=chosen:getZ()})
        if not ok or type(result)~='string' or not string.find(result,'^MOVE_REQUESTED') then c.reason='SITE_PATH_FAILED' return 'Failure' end
        moving=true deadline=getTimestampMs()+185000
        return 'Running'
    end}
end
return Furniture
