-- Existing native emote/chat primitives, inside the original personal Session.
-- No quality/mood/resource effects; valid elapsed role time is the only result.
local A={}
function A.new(c)
    local l=c.payload.leisure local ref=c.payload.activityRef
    local elapsed,lastHours,lastReal=0,nil,nil
    local nextGesture,gestureAt=0,nil
    local cached,checkedAt=nil,0
    local Scripted=require 'EmberRoutesProbe/ActivityScripted'
    local paused=_G.isGamePaused
    local function clear()
        if c.sameAttempt() and c.body.retained() then
            c.npc:setVariable('EmotePlaying',false) c.npc:clearVariable('emote')
        end
    end
    return require('EmberRoutesProbe/LeisureTimed').new(c,{
        start=function() lastHours=getGameTime():getWorldAgeHours() lastReal=getTimestampMs() end,
        update=function()
            local event=Scripted.current(c.job.npcId,ref) if not event then return 'Failure' end
            local now,hours=getTimestampMs(),getGameTime():getWorldAgeHours()
            if lastReal and now<lastReal then checkedAt=0 end
            if now>=checkedAt then cached=Scripted.view(c.actor,c.job.npcId,ref) checkedAt=now+500 end
            if not cached or not cached.target then return 'Failure' end
            local stage=event.stage
            local beginAt,endAt=stage.sharedStart,stage.sharedEnd
            c.npc:faceLocationF(cached.target.x,cached.target.y)
            if beginAt and lastHours and lastReal and now>lastReal and now-lastReal<=1000 and hours>=lastHours
                and not (paused and paused()) then
                elapsed=elapsed+math.max(0,math.min(hours,endAt)-math.max(lastHours,beginAt))
            end
            lastHours=math.max(lastHours or hours,hours) lastReal=now
            if not beginAt then return 'Running' end
            if gestureAt and now-gestureAt>=3000 then clear() gestureAt=nil end
            if now>=nextGesture then
                clear() c.npc:playEmote('yes') gestureAt=now nextGesture=now+6000
                if l.roleDuty=='ROLE_SPEAK' then c.npc:addLineChatElement(getText('IGUI_EmberRoutesProbe_socialLine'..tostring(ZombRand(3)+1))) end
            end
            if hours>=endAt then return elapsed+0.0000001>=event.durationHours and 'Success' or 'Failure' end
            return 'Running'
        end,
        complete=function() l.roleHours=math.min(elapsed,24) clear() return true end,
        stop=function() l.roleHours=math.min(elapsed,24) clear() end})
end
return A
