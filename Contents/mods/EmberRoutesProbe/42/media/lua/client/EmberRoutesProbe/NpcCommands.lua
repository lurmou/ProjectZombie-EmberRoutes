local Probe=require "EmberRoutesProbe/Boot"
local Work=require "EmberRoutesProbe/Work"
local Haul=require "EmberRoutesProbe/Haul"
local Actions=require "EmberRoutesProbe/Actions"
local Runtime=require 'EmberRoutesProbe/TaskRuntime'
local Diagnostic=require 'EmberRoutesProbe/TaskDiagnostic'
local Driver=require 'EmberRoutesProbe/Driver'
local Commands={}
local function controlled(actor,command,point)
    local id=Driver.selected(actor)
    local runtime=Runtime.current()
    if not runtime then return 'ADMISSION_CLOSED' end
    if command=='stop' then
        Work.pause('STOP',id)
        local stopped=runtime:stop(id,'STOP')
        return stopped and 'STOP_REQUESTED' or 'ALREADY_STOPPED'
    elseif command=='move' then
        local result=Diagnostic.submit(actor,'MOVE',{
            validate=function() return point~=nil end,
            start=function(c)
                local ok,why=c.body.move(actor,point) c.result=why
                return ok and type(why)=='string' and string.find(why,'^MOVE_REQUESTED')~=nil,why
            end,
            tick=function(c)
                local motion=EmberRoutesProbeJava.motionResult(c.npc)
                if motion~='MOVING' then c.done=true c.result=motion end
            end,
            finished=function(c) return c.done==true end,
            pause=function() end,evidence=function() return {effects='KNOWN',ids={}} end})
        if result=='QUEUED' then Work.pause('MOVE',id) end
        return result
    end
    if not Work.prepareRemoval(actor,id) then return 'CARGO_OR_CONTROL_RETAINED' end
    local binding=Driver.bindId(actor,id)
    if not binding then return 'CARRIER_UNAVAILABLE' end
    if (Actions.fixtures and Actions.fixtures.npc==binding.handle) or (Haul.npc==binding.handle and #Haul.fixtures>0) then
        return 'DIAGNOSTIC_CLEANUP_REQUIRED'
    end
    local recovery=require('EmberRoutesProbe/ContainerRegistry').data().diagnosticRecovery
    if recovery and (recovery.format~=1 or type(recovery.byNpc)~='table' or recovery.byNpc[id]) then return 'DIAGNOSTIC_RECONCILE_REQUIRED' end
    local q=ISTimedActionQueue.queues[binding.handle]
    if q and (type(q.queue)~='table' or #q.queue>0 or q.current~=nil) then return 'LUA_QUEUE_NOT_STOPPED' end
    if not EmberRoutesProbeJava.removeIdleCarrier then return 'CONTROL_API_UNAVAILABLE' end
    return EmberRoutesProbeJava.removeIdleCarrier(id,binding.handle,actor)
end
function Commands.selectWorker(actor,id)
    if EmberRoutesProbeJava.selectCarrier(id) then
        local name=require('EmberRoutesProbe/DisplayNames').name(id)
        actor:Say(getText("IGUI_EmberRoutesProbe_WorkerSelected",name))
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
    if Probe.controlledExecution==true and (command=='move' or command=='stop' or command=='remove') then
        local stableId=Driver.selected(actor)
        local point=square and {x=x,y=y,z=z} or nil
        local result=controlled(actor,command,point)
        if command=='remove' and type(result)=='string' and (string.find(result,'^REMOVED') or string.find(result,'^ABSENT')) then
            local clean=#require('EmberRoutesProbe/MembershipRuntime').obligations(stableId)==0
            require('EmberRoutesProbe/MembershipService').retire(stableId,clean)
        end
        actor:Say(getText('IGUI_EmberRoutesProbe_Result')..' '..tostring(result))
        return result
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
    if command=='spawn' or command=='spawnAdditional' then
        local id=Driver.selected(actor)
        if Driver.bindId(actor,id) then require('EmberRoutesProbe/MembershipService').register(id) end
    end
    actor:Say(getText("IGUI_EmberRoutesProbe_Result") .. " " .. code)
    return result
end

return Commands
