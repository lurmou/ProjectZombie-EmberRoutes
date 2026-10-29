-- Furniture sleep follows the verified NPCFW furniture branch: native seating
-- establishes the anchor, owned sleep clips return to it before native get-up.
-- This module never computes GetOnBed approach offsets or overrides its turns.
local B={}
function B.move(c)
    return require('EmberRoutesProbe/SelfCareFurniture').seat(c,c.payload.site,nil,true)
end
function B.posture(c,bed)
    local seat=require('EmberRoutesProbe/LeisurePosture').new(c,bed)
    local started,deadline=false,nil
    local function owned() return c.sameAttempt() and c.body.retained() end
    return {object=bed,enter=function()
        if not owned() or not c.valid() then return 'Failure' end
        deadline=deadline or getTimestampMs()+20000
        if getTimestampMs()>deadline then c.reason='SLEEP_POSE_TIMEOUT' return 'Failure' end
        if not started then
            local state=seat.enter()
            if state~='Success' then return state end
            -- Native Rest establishes seating; sleep owns the subsequent effects.
            if not c.body.repose('REST',false) then return 'Running' end
            if not c.body.furniture(bed,'LIE') then return 'Running' end
            started=true
            return 'Running'
        end
        return EmberRoutesProbeJava.bedPoseReady(c.npc,'Asleep') and 'Success' or 'Running'
    end,leave=function()
        if not owned() then return false end
        if not started and not seat.leave() then return false end
        -- Stop owns reverse sleep -> original seat -> original get-up. Do not
        -- call seat.leave while a lying clip still owns the root transform.
        return c.body.stop()
    end}
end
return B
