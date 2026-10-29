-- Seated idle on settlement furniture: native REST flags through the same
-- body capability and leave protocol as P2 repose, bounded by game time.
-- Stats are observed only; this leaf never adds or subtracts them itself.
local Sites=require 'EmberRoutesProbe/ReposeSites'
local Config=require 'EmberRoutesProbe/LeisureConfig'
local S={}
function S.new(c)
    local l=c.payload.leisure local untilHours,posture,leaving
    local continuity=require('EmberRoutesProbe/LeisureContinuity').new(c)
    local function leave(completed)
        if not c.sameAttempt() or not c.body.retained() then return false end
        if posture and not posture.leave() then return false end
        if not c.body.repose('REST',false) or c.npc:isAsleep() or c.npc:isResting() then return false end
        if l.started then
            if completed then l.finished=true else l.stopped=true end
            if not c.persist() then error('SIT_PERSIST_FAILED') end
        end
        return true
    end
    return {kind='Action',run=function()
        if not c.valid() then return 'Failure' end
        local site,why=Sites.resolve(c.payload.site,c.actor,c.npc,c.job.npcId,'REST',c.job.id)
        if not site then
            c.reason=why
            if l.started and not leave(false) then c.effects='UNKNOWN' end
            return 'Failure'
        end
        if not l.started then
            if c.npc:isAsleep() or c.npc:isResting() then c.reason='SIT_ALREADY_REPOSING' return 'Failure' end
            untilHours=getGameTime():getWorldAgeHours()+Config.sitMinutes/60
            -- Fence the possibly effectful native entry before calling it.
            l.started=true l.untilHours=untilHours
            if not c.persist() then error('SIT_PERSIST_FAILED') end
            if not c.body.repose('REST',true,site.object,site.quality) then
                l.started=nil c.effects='UNKNOWN'
                if not c.persist() then error('SIT_PERSIST_FAILED') end
                return 'Failure'
            end
            posture=require('EmberRoutesProbe/LeisurePosture').new(c,site.object)
            return 'Running'
        end
        if leaving then return leave(true) and 'Success' or 'Running' end
        if posture and not l.seated then
            local state=posture.enter()
            if state=='Failure' then return 'Failure' end
            if state~='Success' then return 'Running' end
            l.seated=true l.untilHours=getGameTime():getWorldAgeHours()+Config.sitMinutes/60
            continuity.start()
            if not c.persist() then error('SIT_PERSIST_FAILED') end
        end
        if not c.npc:isResting() then
            c.reason='SIT_INTERRUPTED'
            if not leave(false) then c.effects='UNKNOWN' end
            return 'Failure'
        end
        continuity.tick()
        if getGameTime():getWorldAgeHours()>=(l.untilHours or untilHours or math.huge) and continuity.boundary() then
            leaving=true
            return leave(true) and 'Success' or 'Running'
        end
        return 'Running'
    end,halt=function() if l.started then return leave(false) end return true end}
end
return S
