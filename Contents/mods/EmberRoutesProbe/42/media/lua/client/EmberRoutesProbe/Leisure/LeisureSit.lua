-- Seated idle on settlement furniture: native REST flags through the same
-- body capability and leave protocol as P2 repose, bounded by game time.
-- SIT itself observes stats only; its optional conversation uses shared social effects.
local Sites=require 'EmberRoutesProbe/SelfCare/ReposeSites'
local Config=require 'EmberRoutesProbe/Leisure/LeisureConfig'
local Social=require 'EmberRoutesProbe/Activity/SocialCoordinator'
local S={}
function S.new(c)
    local l=c.payload.leisure local untilHours,posture,leaving
    local continuity=require('EmberRoutesProbe/Leisure/LeisureContinuity').new(c)
    local conversation,hooks,socialEnded
    -- Pairs are ephemeral; a restored SIT never replays a stored conversation.
    if l.seatedSocial then l.seatedSocial=nil end
    local id,attempt=c.job.npcId,c.payload.attemptId
    local function current()
        return conversation and Social.view(conversation.socialId,id,attempt,getTimestampMs())
    end
    local function endSocial(success)
        if not conversation then return end
        if hooks then hooks.stop() end
        if not success then Social.cancel(conversation.socialId,id,attempt) end
        -- No social body action is owned here: stopping this overlay is synchronous.
        -- This releases only the pair, never the SIT claim or its Session.
        Social.release(conversation.socialId,id,attempt,true)
        local service=require 'EmberRoutesProbe/Leisure/LeisureService'
        c.payload.leisureMemory=require('EmberRoutesProbe/Leisure/LeisurePolicy').remember(
            c.payload.leisureMemory,'SOCIAL',getGameTime():getWorldAgeHours(),success==true)
        -- An expired SIT takes its usual completion pause in Service.finished.
        if success and getGameTime():getWorldAgeHours()<(l.untilHours or math.huge) then
            c.payload.leisureMemory=service.pause(c.payload.leisureMemory)
        end
        l.seatedSocial=nil conversation=nil hooks=nil socialEnded=true
        if not c.persist() then error('SIT_SOCIAL_PERSIST_FAILED') end
    end
    local function socialTick()
        socialEnded=false
        if conversation and not require('EmberRoutesProbe/Leisure/LeisureService').seatedSocialAllowed(c) then
            endSocial(false) return false
        end
        if not conversation then
            local key=require('EmberRoutesProbe/Leisure/LeisureService').seatedSocial(c)
            if key and Social.accept(key,id,attempt,getTimestampMs()) then
                conversation={socialId=key} l.seatedSocial=conversation
                hooks=require('EmberRoutesProbe/Activity/SocialActions').conversation(c,conversation,current)
                if not c.persist() then error('SIT_SOCIAL_PERSIST_FAILED') end
            end
        end
        if not conversation then return false end
        local row=current()
        if not row then endSocial(false) return false end
        local other=require('EmberRoutesProbe/Runtime/Driver').bindId(c.actor,row.other)
        if row.ready and other and EmberRoutesProbeJava.socialVisible(c.npc,other.handle) then
            Social.arrive(conversation.socialId,id,attempt,getGameTime():getWorldAgeHours())
            row=current()
        end
        if row and row.phase=='CONVERSE' then
            local state=hooks.update()
            if state=='Failure' then endSocial(false) return false end
            if state=='Success' then
                if not hooks.complete() then endSocial(false) return false end
                endSocial(true) return false
            end
        end
        return true
    end
    local function leave(completed)
        if not c.sameAttempt() or not c.body.retained() then return false end
        endSocial(false) Social.withdraw(id)
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
            posture=require('EmberRoutesProbe/Leisure/LeisurePosture').new(c,site.object)
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
        if socialTick() then return 'Running' end
        if getGameTime():getWorldAgeHours()>=(l.untilHours or untilHours or math.huge) and (socialEnded or continuity.boundary()) then
            leaving=true
            return leave(true) and 'Success' or 'Running'
        end
        return 'Running'
    end,halt=function() if l.started then return leave(false) end return true end}
end
return S
