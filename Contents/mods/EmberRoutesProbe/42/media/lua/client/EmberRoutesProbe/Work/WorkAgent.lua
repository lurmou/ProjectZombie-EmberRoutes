-- Per-NPC work agent. Autonomous logistics and delivery execute exclusively
-- through the format=3 HaulAgent and the JobStore commit protocol.
-- The early explicit-transfer probe executor (route source/destination
-- marking, format=1 records, live-payload publication) was removed with its
-- menus; it is not a supported work path.
local Store=require "EmberRoutesProbe/Work/LaborStore"
local HaulAgent=require 'EmberRoutesProbe/Hauling/HaulAgent'
local Factory={}
function Factory.new(npcId)
    local routed=HaulAgent.new(npcId)
    local Work={}
    function Work.busy() return routed.busy() end
    function Work.stopAdapter(controller,ticket) return routed.stopAdapter(controller,ticket) end
    function Work.pause(reason,owned) return routed.pause(reason,owned) end
    function Work.assign(actor,intent)
        if intent and (intent.producer=='LOGISTICS' or intent.producer=='DELIVERY') then
            return routed.assign(actor,intent)
        end
        return 'TASK_FORMAT_UNSUPPORTED'
    end
    function Work.resume(actor,nonPreemptive) return routed.resume(actor,nonPreemptive) end
    function Work.hasCargo(actor) return routed.hasCargo(actor) end
    function Work.tick() return routed.tick() end
    function Work.reset() return routed.reset() end
    function Work.prepareRemoval(actor)
        if not Store.record(npcId) then return true end
        if routed.hasCargo(actor) then return false end
        routed.pause("REMOVE")
        return Store.clear(npcId)
    end
    function Work.execute(actor,command)
        if command=='resume' then return routed.resume(actor,false) end
        if command=='pause' then routed.pause("USER") return "PAUSED" end
        if command=='clear' then
            routed.pause("CLEAR")
            if routed.hasCargo(actor) then return "CARGO_RETAINED_RESUME_FIRST" end
            local ok,why=Store.clear(npcId)
            return ok and "TASK_CLEARED" or why
        end
        return "TASK_FORMAT_UNSUPPORTED"
    end
    return Work
end
return Factory
