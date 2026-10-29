-- Native rest/sleep flags, controlled by the same body capability. Stats is
-- observed only; this leaf never adds endurance or subtracts fatigue itself.
local Repose={}
local function value(c)
    return c.npc:getStats():get(c.payload.kind=='REST' and CharacterStat.ENDURANCE or CharacterStat.FATIGUE)
end
local function number(v) return type(v)=='number' and v==v and v>=0 and v<=1 end
function Repose.new(c)
    local fact=c.payload.repose
    local posture,closing
    local function save()
        c.payload.repose=fact
        if not c.persist() then error('PERSONAL_REPOSE_NOT_PERSISTED') end
    end
    local function leave(completed)
        if not c.sameAttempt() or not c.body.retained() then return false end
        if posture and not posture.leave() then return false end
        local exited=c.body.repose(c.payload.kind,false)
        if c.npc:isAsleep() or c.npc:isResting() then return false end
        -- Native wake effects are known before the subsequent pose-only exit.
        -- The controller still holds the bed/body until the native mask clears.
        if fact and not fact.finished then
            fact.after=value(c) fact.finished=true fact.completed=completed==true
            if not number(fact.after) then c.effects='UNKNOWN' end
            fact.effects=c.effects save()
            if c.payload.kind=='SLEEP' then
                require('EmberRoutesProbe/Log').write('CARE','SLEEP_WAKE npc='..tostring(c.job and c.job.npcId)
                    ..' completed='..tostring(completed)..' fatigue='..tostring(fact.after))
            end
        end
        return exited
    end
    return {kind='Action',run=function()
        if not c.valid() then return 'Failure' end
        if closing~=nil then
            if not leave(closing) then return 'Running' end
            return closing and 'Success' or 'Failure'
        end
        local site
        if c.payload.site then
            local why
            site,why=require('EmberRoutesProbe/ReposeSites').resolve(c.payload.site,c.actor,c.npc,c.job.npcId,c.payload.kind,c.job.id)
            if not site then
                c.reason=why
                -- Native posture exit can span frames; the stop adapter owns
                -- that drain. A pending get-up is not an unknown stat effect.
                leave(false)
                return 'Failure'
            end
        end
        if not fact then
            if c.payload.kind=='SLEEP' and site then
                posture=posture or require('EmberRoutesProbe/SleepBed').posture(c,site.object)
                local state=posture.enter()
                if state~='Success' then return state end
            elseif c.payload.kind=='SLEEP' and c.payload.floorSite then
                posture=posture or require('EmberRoutesProbe/FloorSleep').posture(c)
                local state=posture.enter()
                if state~='Success' then return state end
            end
            local before=value(c)
            if not number(before) or c.npc:isAsleep() or c.npc:isResting() then return 'Failure' end
            fact={attemptId=c.payload.attemptId,kind=c.payload.kind,before=before,
                started=true,effects='KNOWN',gameStart=getGameTime():getWorldAgeHours()}
            save() -- Fence a possibly effectful native entry before calling it.
            if not c.body.repose(c.payload.kind,true,posture and posture.object or site and site.object,site and site.quality) then c.effects='UNKNOWN' save() return 'Failure' end
            if c.payload.kind=='SLEEP' then
                require('EmberRoutesProbe/Log').write('CARE','SLEEP_START npc='..tostring(c.job and c.job.npcId)
                    ..' onBed='..tostring(posture~=nil))
            end
            return 'Running'
        end
        if fact.attemptId~=c.payload.attemptId or fact.kind~=c.payload.kind or fact.effects~='KNOWN' then
            c.effects='UNKNOWN' return 'Failure'
        end
        if fact.finished then return 'Success' end
        local current=value(c)
        if not number(current) then c.effects='UNKNOWN' return 'Failure' end
        local satisfied=c.payload.kind=='REST' and current>=0.80 or c.payload.kind=='SLEEP' and current<=0.25
        local still=c.payload.kind=='REST' and c.npc:isResting() or c.payload.kind=='SLEEP' and c.npc:isAsleep()
        local hours=getGameTime():getWorldAgeHours()-fact.gameStart
        if satisfied or not still or hours>=8 then
            if not satisfied then c.reason=still and 'NATIVE_REPOSE_TIMEOUT' or 'NATIVE_REPOSE_INTERRUPTED' end
            closing=satisfied
            if not leave(satisfied) then return 'Running' end
            return satisfied and 'Success' or 'Failure'
        end
        return 'Running'
    end,halt=function() return leave(false) end}
end
return Repose
