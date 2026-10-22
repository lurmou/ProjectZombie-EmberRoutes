local build = require "EmberRoutesProbe/Build"
local Log = require "EmberRoutesProbe/Log"
local Probe = { build = build, ready = false, failureCode = "NOT_STARTED" }

function Probe.hasJava()
    return EmberRoutesProbeJava and EmberRoutesProbeJava.begin
        and EmberRoutesProbeJava.command and EmberRoutesProbeJava.tick
        and EmberRoutesProbeJava.reset and EmberRoutesProbeJava.clearForSave and EmberRoutesProbeJava.version
        and EmberRoutesProbeJava.actionCarrier and EmberRoutesProbeJava.carrierActive
        and EmberRoutesProbeJava.carrierPresent and EmberRoutesProbeJava.motionResult and EmberRoutesProbeJava.stopCarrier
        and EmberRoutesProbeJava.controlledCarrier and EmberRoutesProbeJava.carrierId and EmberRoutesProbeJava.retirementTick
        and EmberRoutesProbeJava.saveCheckpoint and EmberRoutesProbeJava.restoreCheckpoint
        and EmberRoutesProbeJava.blockCheckpoint and EmberRoutesProbeJava.reportCheckpoint
        and EmberRoutesProbeJava.checkpointMode and EmberRoutesProbeJava.checkpointHasHome
        and EmberRoutesProbeJava.checkpointHomeX and EmberRoutesProbeJava.checkpointHomeY and EmberRoutesProbeJava.checkpointHomeZ
        and EmberRoutesProbeJava.commandFor and EmberRoutesProbeJava.carrierFor and EmberRoutesProbeJava.selectedId
        and EmberRoutesProbeJava.spawnAdditional and EmberRoutesProbeJava.selectCarrier
        and EmberRoutesProbeJava.workerCount and EmberRoutesProbeJava.workerIdAt
        and EmberRoutesProbeJava.saveCheckpointFor and EmberRoutesProbeJava.blockAllCheckpoints
end

function Probe.unavailableCode()
    if not Probe.hasJava() then return "MISSING_JAVA" end
    return Probe.failureCode
end

function Probe.unavailableMessage()
    local code = Probe.unavailableCode()
    if code == "MISSING_JAVA" then return getText("IGUI_EmberRoutesProbe_MissingJava") end
    if code == "VERSION_MISMATCH" then return getText("IGUI_EmberRoutesProbe_VersionMismatch") end
    return getText("IGUI_EmberRoutesProbe_DriverNotReady") .. " " .. code
end

function Probe.begin()
    Probe.ready = false
    Probe.restorePending = false
    Probe.failureCode = "NOT_STARTED"
    if not Probe.hasJava() then
        Probe.failureCode = "MISSING_JAVA"
        Log.write("BOOT", getText("IGUI_EmberRoutesProbe_MissingJava"))
        return
    end
    if EmberRoutesProbeJava.version() ~= build.version then
        Probe.failureCode = "VERSION_MISMATCH"
        Log.write("BOOT", getText("IGUI_EmberRoutesProbe_VersionMismatch"))
        return
    end
    local enabled = SandboxVars and SandboxVars.EmberRoutes
        and SandboxVars.EmberRoutes.CarrierProbe == true
    Probe.enabled=enabled==true
    local result = EmberRoutesProbeJava.begin(enabled == true)
    Probe.failureCode = string.match(result, "^(%u[%u_]*)") or "BOOT_FAILED"
    Probe.restorePending = string.sub(result, 1, 5) == "READY" and enabled == true
    Probe.ready = string.sub(result, 1, 5) == "READY"
        or string.sub(result, 1, 14) == "RESET_REQUIRED"
end

function Probe.tick()
    if Probe.tickPersistence then Probe.tickPersistence() end
    if Probe.tickCrafting then Probe.tickCrafting() end
    if Probe.tickActions then Probe.tickActions() end
    if Probe.tickHaul then Probe.tickHaul() end
    if Probe.tickWork then Probe.tickWork() end
    if Probe.tickCompanion then Probe.tickCompanion() end
    if Probe.tickLogistics then Probe.tickLogistics() end
    if Probe.tickCraftView then Probe.tickCraftView() end
    if Probe.ready then EmberRoutesProbeJava.tick() end
end

function Probe.cancelAll(reason, npcId)
    npcId=npcId or (EmberRoutesProbeJava.selectedId and EmberRoutesProbeJava.selectedId())
    if Probe.cancelWork then Probe.cancelWork(reason,npcId) end
    if Probe.cancelCompanion then Probe.cancelCompanion(reason,npcId) end
    if Probe.cancelActions then Probe.cancelActions(reason,npcId) end
    if Probe.cancelHaul then Probe.cancelHaul(reason,npcId) end
end

function Probe.cancelEvery(reason)
    if Probe.pauseAllWork then Probe.pauseAllWork(reason)
    elseif Probe.cancelWork then Probe.cancelWork(reason) end
    if Probe.cancelEveryCompanion then Probe.cancelEveryCompanion(reason)
    elseif Probe.cancelCompanion then Probe.cancelCompanion(reason) end
    if Probe.cancelActions then Probe.cancelActions(reason) end
    if Probe.cancelHaul then Probe.cancelHaul(reason) end
end

function Probe.reset()
    Probe.restorePending = false
    if Probe.resetPersistence then Probe.resetPersistence() end
    if Probe.resetLogistics then Probe.resetLogistics() end
    Probe.cancelEvery("WORLD_RESET")
    if Probe.resetCompanion then Probe.resetCompanion() end
    if Probe.resetHaul then Probe.resetHaul() end
    if Probe.resetWork then Probe.resetWork() end
    if Probe.ready and Probe.hasJava() then
        local result = EmberRoutesProbeJava.reset()
        -- Continue bounded retirement while the old body is still owned.
        Probe.ready = string.sub(result, 1, 15) == "REMOVAL_PENDING"
            or string.sub(result, 1, 14) == "CLEANUP_FAILED"
    else
        Probe.ready = false
    end
end

function Probe.beforeSave()
    if Probe.savePersistentCarrier then Probe.savePersistentCarrier() return end
    -- No client persistence module in MP; this branch only retains legacy cleanup.
    Probe.cancelEvery("SAVE")
    if Probe.cleanupHaul and not Probe.cleanupHaul() then
        Log.write("SAVE_CLEANUP_BLOCKED", "haul fixtures retained; manual cleanup required")
        return
    end
    if Probe.ready and Probe.hasJava() then
        EmberRoutesProbeJava.clearForSave()
    end
end

Events.OnGameStart.Add(Probe.begin)
Events.OnServerStarted.Add(Probe.begin)
Events.OnTick.Add(Probe.tick)
-- Current GameWindow emits this only on the paused game-state path.
-- Never run action batches or companion movement from this callback.
if Events.OnTickEvenPaused then
    Events.OnTickEvenPaused.Add(function()
        if Probe.ready then EmberRoutesProbeJava.retirementTick() end
    end)
end
Events.OnPreMapLoad.Add(Probe.reset)
Events.OnSave.Add(Probe.beforeSave)

return Probe
