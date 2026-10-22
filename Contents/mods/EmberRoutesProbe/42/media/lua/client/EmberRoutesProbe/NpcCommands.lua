local Probe=require "EmberRoutesProbe/Boot"
local Work=require "EmberRoutesProbe/Work"
local Haul=require "EmberRoutesProbe/Haul"
local Actions=require "EmberRoutesProbe/Actions"
local Commands={}
function Commands.selectWorker(actor,id)
    if EmberRoutesProbeJava.selectCarrier(id) then
        actor:Say(getText("IGUI_EmberRoutesProbe_WorkerSelected",string.sub(id,1,8)))
    end
end

function Commands.execute(actor, command, square)
    if not Probe.ready or not Probe.hasJava() then
        actor:Say(Probe.unavailableMessage())
        return
    end
    local x, y, z = 0, 0, 0
    if square then
        x, y, z = square:getX() + 0.5, square:getY() + 0.5, square:getZ()
    end
    if command == "move" or command == "stop" or command == "remove" then
        Probe.cancelAll(string.upper(command))
        if command == "remove" and not Work.prepareRemoval(actor) then
            actor:Say(getText("IGUI_EmberRoutesProbe_WorkResult") .. " CARGO_RETAINED_RESUME_FIRST")
            return
        end
        if command == "remove" then
            local npc=EmberRoutesProbeJava.carrierFor(EmberRoutesProbeJava.selectedId(),actor)
            if npc and (not Haul.cleanup(npc) or not Actions.cleanupForHaul(npc)) then
                actor:Say(getText("IGUI_EmberRoutesProbe_HaulResult") .. " CLEANUP_BLOCKED")
                return
            end
        end
    end
    local result
    if command=="spawnAdditional" then result=EmberRoutesProbeJava.spawnAdditional(actor,x,y,z)
    else result=EmberRoutesProbeJava.command(command, actor, x, y, z) end
    local code = string.match(result, "^(%u[%u_]*)") or "ERROR"
    actor:Say(getText("IGUI_EmberRoutesProbe_Result") .. " " .. code)
end

return Commands
