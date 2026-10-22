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
    return binding and EmberRoutesProbeJava.carrierPresent(binding.handle)
        and EmberRoutesProbeJava.carrierId(binding.handle) == binding.id
end

function Driver.stop(binding)
    if not Driver.valid(binding) then return false end
    return EmberRoutesProbeJava.stopCarrier(binding.handle)
end

function Driver.move(binding, actor, point)
    if not Driver.valid(binding) then return "STALE_NPC" end
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
