local Social=require 'EmberRoutesProbe/Activity/SocialCoordinator'
local Record=require 'EmberRoutesProbe/Activity/ActivityReliefRecord'
local A={}
function A.conversation(c,l,current)
    local id=c.job.npcId local attempt=c.payload.attemptId
    local nextGesture,gestureAt=0,nil
    local seated=c.payload.leisure.activity=='SIT'
    local function clear()
        if not seated and c.sameAttempt() and c.body.retained() then
            c.npc:setVariable('EmotePlaying',false) c.npc:clearVariable('emote')
        end
    end
    return {

        update=function()
            local row=current() if not row then return 'Failure' end
            if getGameTime():getWorldAgeHours()>=row.ends then return 'Success' end
            local other=require('EmberRoutesProbe/Runtime/Driver').bindId(c.actor,row.other)
            if not other or other.handle:isDead() then return 'Failure' end
            if not EmberRoutesProbeJava.socialVisible(c.npc,other.handle) then return 'Failure' end
            if not seated then c.npc:faceLocationF(other.handle:getX(),other.handle:getY()) end
            local now=getTimestampMs()
            if gestureAt and now-gestureAt>=3000 then clear() gestureAt=nil end
            if now>=nextGesture then
                clear()
                -- Seated emote/turn behavior is unverified; never disturb the seat pose.
                if not seated then c.npc:playEmote('yes') gestureAt=now end
                nextGesture=now+6000
                if c.npc.addLineChatElement then
                    c.npc:addLineChatElement(getText('IGUI_EmberRoutesProbe_socialLine'..tostring(ZombRand(3)+1)))
                end
            end
            return getGameTime():getWorldAgeHours()>=row.ends and 'Success' or 'Running'
        end,
        complete=function()
            if not current() or l.applied then return l.applied==true end
            c.payload.leisure.applying=true if not c.persist() then error('SOCIAL_EFFECT_NOT_PERSISTED') end
            local stats=c.npc:getStats()
            -- Same relief deltas as ActivityReliefRecord: BOREDOM/UNHAPPINESS
            -- are native 0-100 points, STRESS is native 0-1 (see Constants.Stat).
            stats:set(CharacterStat.BOREDOM,math.max(0,stats:get(CharacterStat.BOREDOM)-Record.BOREDOM))
            stats:set(CharacterStat.UNHAPPINESS,math.max(0,stats:get(CharacterStat.UNHAPPINESS)-Record.UNHAPPINESS))
            stats:set(CharacterStat.STRESS,math.max(0,stats:get(CharacterStat.STRESS)-Record.STRESS))
            l.applied=true c.payload.leisure.applying=nil clear() return true
        end,
        stop=function() clear() if not l.applied then Social.cancel(l.socialId,id,attempt) end end}
end
function A.new(c)
    local l=c.payload.leisure local id=c.job.npcId local attempt=c.payload.attemptId
    local function current() return Social.view(l.socialId,id,attempt,getTimestampMs()) end
    local converse=require('EmberRoutesProbe/Leisure/LeisureTimed').new(c,A.conversation(c,l,current))
    local accepted=false
    local move=require('EmberRoutesProbe/Leisure/LeisureActions').move(c,function()
        if not accepted then accepted=Social.accept(l.socialId,id,attempt,getTimestampMs()) end
        local row=accepted and current()
        return row and row.ready and row.point or nil
    end,function()
        local row=current() if not row then return false end
        local other=require('EmberRoutesProbe/Runtime/Driver').bindId(c.actor,row.other)
        if other and EmberRoutesProbeJava.socialVisible(c.npc,other.handle) then
            Social.arrive(l.socialId,id,attempt,getGameTime():getWorldAgeHours())
        end
        row=current() return row and row.phase=='CONVERSE' or false
    end)
    local approach={kind='Action',run=function()
        if not accepted then accepted=Social.accept(l.socialId,id,attempt,getTimestampMs()) end
        local row=accepted and current() if not row then return 'Failure' end
        if not row.ready then return 'Running' end
        return move.run()
    end,halt=function() Social.cancel(l.socialId,id,attempt) return c.body.stop() end}
    return {kind='Sequence',children={approach,converse}}
end
return A
