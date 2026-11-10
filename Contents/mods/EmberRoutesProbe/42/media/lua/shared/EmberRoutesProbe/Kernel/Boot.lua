local build = require "EmberRoutesProbe/Kernel/Build"
local Log = require "EmberRoutesProbe/Kernel/Log"
local Performance = require 'EmberRoutesProbe/Kernel/RuntimeMetrics'
-- P1 complete execution path enabled for single-player acceptance. No live toggle.
local Probe = { build = build, ready = false, runtimeReady=false, failureCode = "NOT_STARTED", controlledExecution=true }

local validatedBridge,validatedMode
local function validateJava()
    return EmberRoutesProbeJava and EmberRoutesProbeJava.begin
        and EmberRoutesProbeJava.command and EmberRoutesProbeJava.tick
        and EmberRoutesProbeJava.reset and EmberRoutesProbeJava.clearForSave and EmberRoutesProbeJava.version
        and EmberRoutesProbeJava.actionCarrier and EmberRoutesProbeJava.carrierActive
        and EmberRoutesProbeJava.followWithControl
        and EmberRoutesProbeJava.followMetrics
        and EmberRoutesProbeJava.moveSeatWithControl and EmberRoutesProbeJava.reachedSeat
        and EmberRoutesProbeJava.moveBedWithControl and EmberRoutesProbeJava.bedPoseReady
        and EmberRoutesProbeJava.furniturePoseWithControl and EmberRoutesProbeJava.moveSleepSeatWithControl
        and EmberRoutesProbeJava.floorSleepSafe
        and EmberRoutesProbeJava.reposeWithControl and EmberRoutesProbeJava.reposeAtWithControl
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
        and (Probe.controlledExecution~=true or (EmberRoutesProbeJava.captureCheckpointFor
            and EmberRoutesProbeJava.saveBodyReady and EmberRoutesProbeJava.armSaveReceipt
            and EmberRoutesProbeJava.verifySaveReceipt and EmberRoutesProbeJava.restoreCheckpointFor
            and EmberRoutesProbeJava.acquireBodyControl and EmberRoutesProbeJava.releaseBodyControl
            and EmberRoutesProbeJava.moveWithControl and EmberRoutesProbeJava.stopWithControl
            and EmberRoutesProbeJava.bodyStopMask and EmberRoutesProbeJava.freezeBodyControl
            and EmberRoutesProbeJava.thawBodyControl and EmberRoutesProbeJava.retireBodyControl
            and EmberRoutesProbeJava.removeIdleCarrier and EmberRoutesProbeJava.ownedCarrierId))
end

function Probe.hasJava()
    -- Native extension capabilities are immutable during a running world.
    -- Never cache a missing capability; begin() always performs a fresh audit.
    if validatedBridge and validatedBridge==EmberRoutesProbeJava and validatedMode==Probe.controlledExecution then return true end
    return validateJava()
end

function Probe.unavailableCode()
    if not Probe.hasJava() then return "MISSING_JAVA" end
    return Probe.failureCode
end

function Probe.unavailableMessage()
    local code = Probe.unavailableCode()
    if code == "MISSING_JAVA" then return getText("IGUI_EmberRoutesProbe_MissingJava") end
    if code == "VERSION_MISMATCH" then return getText("IGUI_EmberRoutesProbe_VersionMismatch") end
    if code=='LEGACY_TASK_RESET_REQUIRED' then return getText('IGUI_EmberRoutesProbe_Public_'..code) end
    if code=='MEMBERSHIP_NEW_WORLD_REQUIRED' or code=='MEMBERSHIP_FORMAT_INVALID' then return getText('IGUI_EmberRoutesProbe_Membership_'..code) end
    return getText("IGUI_EmberRoutesProbe_DriverNotReady") .. " " .. code
end

function Probe.begin()
    validatedBridge,validatedMode=nil,nil
    -- Independent fail-closed commit admission; does not alter body startup.
    local kernel=require 'EmberRoutesProbe/Kernel/LaborKernelAvailability'
    local available,diagnosis=kernel.validate()
    if not available then Log.write('KERNEL_UNAVAILABLE',diagnosis) end
    Performance.reset()
    Probe.ready = false
    Probe.runtimeReady = false
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
    local canExecute=string.sub(result,1,5)=='READY' and Probe.enabled
    if canExecute and Probe.controlledExecution==true
        and not (Probe.prepareTaskRecovery and Probe.beginTasks and Probe.tickTasks and Probe.resetTasks
            and Probe.savePersistentCarrier and Probe.beforeStockSave and Probe.afterStockSave and Probe.resetStock) then
        Probe.ready=false Probe.restorePending=false Probe.failureCode='RUNTIME_MODULES_MISSING'
        Log.write('BOOT','RUNTIME_MODULES_MISSING controlled execution not started')
        return
    end
    if canExecute and Probe.prepareTaskRecovery then
        local ok,reason=pcall(Probe.prepareTaskRecovery)
        if not ok then
            Probe.ready=false Probe.restorePending=false Probe.failureCode='RECOVERY_RECORDS_INVALID'
            for _,code in ipairs({'LEGACY_TASK_RESET_REQUIRED','MEMBERSHIP_NEW_WORLD_REQUIRED','MEMBERSHIP_FORMAT_INVALID'}) do
                if string.find(tostring(reason),code,1,true) then Probe.failureCode=code end
            end
            if Probe.beforeStockSave then Probe.beforeStockSave() end
            Log.write('BOOT','RECOVERY_RECORDS_INVALID '..tostring(reason))
        end
    end
    -- RESET_REQUIRED keeps native retirement ticking, never opens task admission.
    Probe.runtimeReady=canExecute and Probe.ready
    if Probe.ready then validatedBridge,validatedMode=EmberRoutesProbeJava,Probe.controlledExecution end
    if Probe.runtimeReady and Probe.beginTasks then Probe.beginTasks() end
    if Probe.runtimeReady and Probe.controlledExecution==true then
        Log.write('BOOT','RUNTIME controlledExecution=true recovery=READY')
    end
end

local function tickServices()
    if Probe.ready and EmberRoutesProbeJava then EmberRoutesProbeJava.tick() end
    local is60 = not EmberRoutesProbeJava or not EmberRoutesProbeJava.cadenceIs60Hz or EmberRoutesProbeJava.cadenceIs60Hz()
    local is15 = not EmberRoutesProbeJava or not EmberRoutesProbeJava.cadenceIs15Hz or EmberRoutesProbeJava.cadenceIs15Hz()
    local is5 = not EmberRoutesProbeJava or not EmberRoutesProbeJava.cadenceIs5Hz or EmberRoutesProbeJava.cadenceIs5Hz()
    local is1 = not EmberRoutesProbeJava or not EmberRoutesProbeJava.cadenceIs1Hz or EmberRoutesProbeJava.cadenceIs1Hz()

    -- 60Hz: Locomotion, direct actions and task session execution
    if is60 then
        if Probe.tickTasks then Probe.tickTasks() end
        if Probe.tickActions then Probe.tickActions() end
    end

    -- 15Hz: Work, delivery, hauling, crafting
    if is15 then
        if Probe.tickWork then Probe.tickWork() end
        if Probe.tickHaul then Probe.tickHaul() end
        if Probe.tickDelivery then Probe.tickDelivery() end
        if Probe.tickCrafting then Probe.tickCrafting() end
    end

    -- 5Hz: Self-care, leisure, public work dispatch, logistics, craft view & read
    if is5 then
        if Probe.tickSelfCare then Probe.tickSelfCare() end
        if Probe.tickActivities then Probe.tickActivities() end
        if Probe.tickPublicWork then Probe.tickPublicWork() end
        if Probe.tickLogistics then Probe.tickLogistics() end
        if Probe.tickCraftView then Probe.tickCraftView() end
        if Probe.tickCraftRead then Probe.tickCraftRead() end
    end

    -- 1Hz: Membership validation, persistence heartbeat, settled task retirement
    if is1 then
        if Probe.tickMembership then Probe.tickMembership() end
        if Probe.tickPersistence then Probe.tickPersistence() end
        if Probe.tickRetirement then Probe.tickRetirement() end
    end
end

function Probe.tick()
    if not Performance.active() then tickServices() return end
    local started=Performance.now()
    if Probe.ready and EmberRoutesProbeJava then Performance.measure("Java",EmberRoutesProbeJava.tick) end
    local is60 = not EmberRoutesProbeJava or not EmberRoutesProbeJava.cadenceIs60Hz or EmberRoutesProbeJava.cadenceIs60Hz()
    local is15 = not EmberRoutesProbeJava or not EmberRoutesProbeJava.cadenceIs15Hz or EmberRoutesProbeJava.cadenceIs15Hz()
    local is5 = not EmberRoutesProbeJava or not EmberRoutesProbeJava.cadenceIs5Hz or EmberRoutesProbeJava.cadenceIs5Hz()
    local is1 = not EmberRoutesProbeJava or not EmberRoutesProbeJava.cadenceIs1Hz or EmberRoutesProbeJava.cadenceIs1Hz()

    if is60 then
        if Probe.tickTasks then Performance.measure("Tasks", Probe.tickTasks) end
        if Probe.tickActions then Performance.measure("Actions", Probe.tickActions) end
    end

    if is15 then
        if Probe.tickWork then Performance.measure("Work", Probe.tickWork) end
        if Probe.tickHaul then Performance.measure("Haul", Probe.tickHaul) end
        if Probe.tickDelivery then Performance.measure("Delivery", Probe.tickDelivery) end
        if Probe.tickCrafting then Performance.measure("Crafting", Probe.tickCrafting) end
    end

    if is5 then
        if Probe.tickSelfCare then Performance.measure("SelfCare", Probe.tickSelfCare) end
        if Probe.tickActivities then Performance.measure("Activities", Probe.tickActivities) end
        if Probe.tickPublicWork then Performance.measure("PublicWork", Probe.tickPublicWork) end
        if Probe.tickLogistics then Performance.measure("Logistics", Probe.tickLogistics) end
        if Probe.tickCraftView then Performance.measure("CraftView", Probe.tickCraftView) end
        if Probe.tickCraftRead then Performance.measure("CraftRead", Probe.tickCraftRead) end
    end

    if is1 then
        if Probe.tickMembership then Performance.measure("Membership", Probe.tickMembership) end
        if Probe.tickPersistence then Performance.measure("Persistence", Probe.tickPersistence) end
        if Probe.tickRetirement then Performance.measure("Retirement", Probe.tickRetirement) end
    end
    Performance.finishTick(started)
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
    validatedBridge,validatedMode=nil,nil
    Performance.reset()
    if Probe.resetMembership then Probe.resetMembership() end
    if Probe.resetDelivery then Probe.resetDelivery() end
    Probe.runtimeReady = false
    Probe.restorePending = false
    if Probe.resetTasks then Probe.resetTasks() end
    if Probe.resetSelfCare then Probe.resetSelfCare() end
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
    -- No client persistence module in MP; this branch only runs save cleanup.
    Probe.cancelEvery("SAVE")
    if Probe.cleanupHaul and not Probe.cleanupHaul() then
        Log.write("SAVE_CLEANUP_BLOCKED", "haul fixtures retained; manual cleanup required")
        return
    end
    if Probe.ready and Probe.hasJava() then
        EmberRoutesProbeJava.clearForSave()
    end
end

if Events and Events.OnGameStart then
    Events.OnGameStart.Add(Probe.begin)
    Events.OnServerStarted.Add(Probe.begin)
    Events.OnTick.Add(Probe.tick)
    Events.OnPreMapLoad.Add(Probe.reset)
    Events.OnSave.Add(Probe.beforeSave)
end
-- Retirement rides the mod's single even-paused dispatcher.
require('EmberRoutesProbe/Kernel/EvenPaused').add(function()
    if Probe.ready then EmberRoutesProbeJava.retirementTick() end
end)

return Probe
