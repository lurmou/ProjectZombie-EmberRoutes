-- Local authority adapter. A future MP adapter must validate these intents on its authority.
local Driver = {}

function Driver.capabilities()
    return { protocol = 1, mode = "SINGLE_PLAYER", multiplayer = false }
end

function Driver.bind(actor)
    local npc = EmberRoutesProbeJava.controlledCarrier(actor)
    if not npc then return nil end
    local id = EmberRoutesProbeJava.carrierId(npc)
    if not id or id == "" then return nil end
    return { handle = npc, id = id }
end

function Driver.bindId(actor, id)
    local npc
    if EmberRoutesProbeJava.carrierFor then npc = EmberRoutesProbeJava.carrierFor(id, actor)
    else npc = EmberRoutesProbeJava.controlledCarrier(actor) end
    if not npc or EmberRoutesProbeJava.carrierId(npc) ~= id then return nil end
    return {handle=npc, id=id}
end

function Driver.selected(actor)
    if EmberRoutesProbeJava.selectedId then return EmberRoutesProbeJava.selectedId() end
    local binding=Driver.bind(actor) return binding and binding.id or ""
end

function Driver.valid(binding)
    if binding and EmberRoutesProbeJava.bindingValid then
        return EmberRoutesProbeJava.bindingValid(binding.handle,binding.id)
    end
    return binding and EmberRoutesProbeJava.carrierPresent(binding.handle)
        and EmberRoutesProbeJava.carrierId(binding.handle) == binding.id
end

function Driver.stop(binding,body)
    if not Driver.valid(binding) then return false end
    if body then return body.stop() end
    return EmberRoutesProbeJava.stopCarrier(binding.handle)
end

-- Only TaskController supplies generation from its private ExecutionSession.
function Driver.acquireControl(binding,jobId,generation)
    if not Driver.valid(binding) or not EmberRoutesProbeJava.acquireBodyControl then return nil,'CONTROL_UNAVAILABLE' end
    local key=EmberRoutesProbeJava.acquireBodyControl(binding.handle,jobId,generation)
    if not key or key=='' then return nil,'CONTROL_DENIED' end
    return {binding=binding,key=key}
end
function Driver.moveControlled(control,actor,point)
    if not control or not Driver.valid(control.binding) then return 'STALE_NPC' end
    if point.bed then
        return EmberRoutesProbeJava.moveBedWithControl(control.binding.handle,control.key,point.bed,point.locations)
    end
    if point.furniture then
        if point.sleep then
            return EmberRoutesProbeJava.moveSleepSeatWithControl(control.binding.handle,control.key,point.furniture)
        end
        return EmberRoutesProbeJava.moveSeatWithControl(control.binding.handle,control.key,point.furniture,point.maxPathLength or 0)
    end
    return EmberRoutesProbeJava.moveWithControl(control.binding.handle,control.key,actor,point.x,point.y,point.z)
end
function Driver.stopControlled(control)
    return control and Driver.valid(control.binding)
        and EmberRoutesProbeJava.stopWithControl(control.binding.handle,control.key) or false
end
function Driver.reposeControlled(control,kind,enter,object,quality)
    if enter and object then
        return control and Driver.valid(control.binding) and EmberRoutesProbeJava.reposeAtWithControl
            and EmberRoutesProbeJava.reposeAtWithControl(control.binding.handle,control.key,kind,object,quality) or false
    end
    return control and Driver.valid(control.binding) and EmberRoutesProbeJava.reposeWithControl
        and EmberRoutesProbeJava.reposeWithControl(control.binding.handle,control.key,kind,enter) or false
end
function Driver.furnitureControlled(control,object,phase)
    return control and Driver.valid(control.binding) and EmberRoutesProbeJava.furniturePoseWithControl(
        control.binding.handle,control.key,object,phase) or false
end
function Driver.stopEvidence(control)
    if not control or not Driver.valid(control.binding) then return {available=false} end
    local mask=EmberRoutesProbeJava.bodyStopMask(control.binding.handle,control.key)
    -- This says nothing about Lua queued actions or business effects.
    return {available=mask~=nil and mask>=0,nativeMask=mask,nativeStopped=mask==0}
end
function Driver.releaseControl(control)
    return control and Driver.valid(control.binding)
        and EmberRoutesProbeJava.releaseBodyControl(control.binding.handle,control.key) or false
end

function Driver.move(binding, actor, point,body)
    if not Driver.valid(binding) then return "STALE_NPC" end
    if body then
        local ok,result=body.move(actor,point)
        return ok and result or (result or 'CONTROL_REQUIRED')
    end
    if EmberRoutesProbeJava.commandFor then
        return EmberRoutesProbeJava.commandFor(binding.id,"move",actor,point.x,point.y,point.z)
    end
    return EmberRoutesProbeJava.command("move",actor,point.x,point.y,point.z)
end

function Driver.snapshot(binding, actor)
    if not Driver.valid(binding) or not actor or actor:isDead() then return nil end
    local npc = binding.handle
    return { id = binding.id, x = npc:getX(), y = npc:getY(), z = npc:getZ(),
        leaderX = actor:getX(), leaderY = actor:getY(), leaderZ = actor:getZ(),
        motion = EmberRoutesProbeJava.motionResult(npc) }
end

return Driver
