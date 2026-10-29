-- Head targets update infrequently; native animation performs the blending.
-- This adapter is only used while the existing activity owns the body.
local Config=require 'EmberRoutesProbe/LeisureConfig'
local L={}
function L.new(c)
    local nextAt=0 local enabled=false
    local function retained() return c.sameAttempt() and c.body.retained() end
    return {
        update=function()
            if not retained() or not c.valid() or getTimestampMs()<nextAt then return end
            nextAt=getTimestampMs()+Config.lookIntervalMs
            if c.npc.setHeadLookAround and c.npc.setHeadLookAroundDirection then
                c.npc:setHeadLookAround(true)
                c.npc:setHeadLookAroundDirection((ZombRand(141)-70)/100,0)
                enabled=true
            end
        end,
        clear=function()
            if not enabled or not retained() then return end
            c.npc:setHeadLookAroundDirection(0,0) c.npc:setHeadLookAround(false)
            enabled=false
        end,
    }
end
return L
