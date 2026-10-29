local build = require "EmberRoutesProbe/Build"
local Log = require "EmberRoutesProbe/Log"
local Performance = require 'EmberRoutesProbe/RuntimeMetrics'
-- P1 complete execution path enabled for single-player acceptance. No live toggle.
local Probe = { build = build, ready = false, runtimeReady=false, failureCode = "NOT_STARTED", controlledExecution=true }

local validatedBridge,validatedMode
local function validateJava()
    return EmberRoutesProbeJava and EmberRoutesProbeJava.begin
        and EmberRoutesProbeJava.command and EmberRoutesProbeJava.tick
        and EmberRoutesProbeJava.reset and EmberRoutesProbeJava.clearForSave and EmberRoutesProbeJava.version
        and EmberRoutesProbeJava.actionCarrier and EmberRoutesProbeJava.carrierActive
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
    if code=='LEGACY_TASK_RESET_REQUIRED' or code=='LEGACY_STOCK_RESET_REQUIRED' then return getText('IGUI_EmberRoutesProbe_Public_'..code) end
    if code=='MEMBERSHIP_NEW_WORLD_REQUIRED' or code=='MEMBERSHIP_FORMAT_INVALID' then return getText('IGUI_EmberRoutesProbe_Membership_'..code) end
    return getText("IGUI_EmberRoutesProbe_DriverNotReady") .. " " .. code
end

function Probe.begin()
    validatedBridge,validatedMode=nil,nil
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
            for _,code in ipairs({'LEGACY_TASK_RESET_REQUIRED','LEGACY_STOCK_RESET_REQUIRED','MEMBERSHIP_NEW_WORLD_REQUIRED','MEMBERSHIP_FORMAT_INVALID'}) do
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
    if Probe.tickPersistence then Probe.tickPersistence() end
    if Probe.tickMembership then Probe.tickMembership() end
    if Probe.tickActivities then Probe.tickActivities() end
    if Probe.tickSelfCare then Probe.tickSelfCare() end
    if Probe.tickTasks then Probe.tickTasks() end
    if Probe.tickCrafting then Probe.tickCrafting() end
    if Probe.tickActions then Probe.tickActions() end
    if Probe.tickHaul then Probe.tickHaul() end
    if Probe.tickWork then Probe.tickWork() end
    if Probe.tickCompanion then Probe.tickCompanion() end
    if Probe.tickLogistics then Probe.tickLogistics() end
    if Probe.tickPublicWork then Probe.tickPublicWork() end
    if Probe.tickRetirement then Probe.tickRetirement() end
    if Probe.tickCraftView then Probe.tickCraftView() end
    if Probe.tickDelivery then Probe.tickDelivery() end
    if Probe.ready then EmberRoutesProbeJava.tick() end
end

local services={'Persistence','Membership','Activities','SelfCare','Tasks','Crafting','Actions','Haul','Work','Companion','Logistics','PublicWork','Retirement','CraftView','Delivery'}
local serviceSteps,serviceEpoch
function Probe.tick()
    if not Performance.active() then tickServices() return end
    local started=Performance.now()
    -- Resolve tick functions once per sampling session; string concat per tick
    -- was measurable sampling-scaffold overhead.
    if serviceEpoch~=Performance.epoch() then
        serviceSteps={}
        local seen={}
        local function add(name,fn)
            if fn and type(fn)=='function' and not seen[name] then
                seen[name]=true serviceSteps[#serviceSteps+1]={name,fn}
            end
        end
        for _,name in ipairs(services) do add(name,Probe['tick'..name]) end
        -- Auto-discover any other tick<Service> handler so newly added services are
        -- timed without editing this list. Excludes the internal dispatcher
        -- tickServices and the Probe.tick entry itself (no capital after "tick").
        for k,v in pairs(Probe) do
            if type(k)=='string' and type(v)=='function' then
                local svc=k:match('^tick(%u%w*)$')
                if svc and k~='tickServices' then add(svc,v) end
            end
        end
        serviceEpoch=Performance.epoch()
    end
    for _,step in ipairs(serviceSteps) do
        Performance.measure(step[1],step[2])
    end
    if Probe.ready then Performance.measure('Java',EmberRoutesProbeJava.tick) end
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

if Events and Events.OnGameStart then
    Events.OnGameStart.Add(Probe.begin)
    Events.OnServerStarted.Add(Probe.begin)
    Events.OnTick.Add(Probe.tick)
    Events.OnPreMapLoad.Add(Probe.reset)
    Events.OnSave.Add(Probe.beforeSave)
end
-- Retirement rides the mod's single even-paused dispatcher.
require('EmberRoutesProbe/EvenPaused').add(function()
    if Probe.ready then EmberRoutesProbeJava.retirementTick() end
end)

return Probe
