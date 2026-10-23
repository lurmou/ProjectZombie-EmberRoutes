local count, normal, paused, jobs, cleared, cancelled = 0, 0, 0, 0, 0, 0
package.path = "Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;" .. package.path
DebugLog = { log = function(message) print(message) end }
local function check(value, message) count = count + 1 assert(value, message) end
local callbacks = {}
Events = {}
for _, name in ipairs({"OnGameStart", "OnServerStarted", "OnTick", "OnTickEvenPaused", "OnPreMapLoad", "OnSave"}) do
    Events[name] = { Add = function(fn) callbacks[name] = fn end }
end
SandboxVars = { EmberRoutes = { CarrierProbe = true } }
package.loaded["EmberRoutesProbe/Build"] = { version = "test", prefix = "TEST" }
function getText(key) return key end
local function stub() end
EmberRoutesProbeJava = {
    begin = function() return "READY" end, version = function() return "test" end,
    tick = function() normal = normal + 1 end,
    retirementTick = function() paused = paused + 1 end,
    command = stub, reset = function() return "REMOVAL_PENDING" end,
    clearForSave = function() cleared = cleared + 1 end,
    actionCarrier = stub, carrierActive = stub, carrierPresent = stub, motionResult = stub,
    stopCarrier = stub, controlledCarrier = stub, carrierId = stub,
    saveCheckpoint = stub, restoreCheckpoint = stub, blockCheckpoint = stub, reportCheckpoint = stub,
    checkpointMode = stub, checkpointHasHome = stub, checkpointHomeX = stub, checkpointHomeY = stub, checkpointHomeZ = stub,
    commandFor=stub,carrierFor=stub,selectedId=stub,spawnAdditional=stub,selectCarrier=stub,
    workerCount=stub,workerIdAt=stub,saveCheckpointFor=stub,blockAllCheckpoints=stub,
}
local Probe = dofile("Contents/mods/EmberRoutesProbe/42/media/lua/shared/EmberRoutesProbe/Boot.lua")
Probe.controlledExecution=false -- Explicit legacy lifecycle fixture; activation has a separate regression.
Probe.tickActions = function() jobs = jobs + 1 end
Probe.tickHaul = Probe.tickActions
Probe.tickCompanion = Probe.tickActions
Probe.cancelActions = function() cancelled = cancelled + 1 end
Probe.cancelHaul, Probe.cancelCompanion = Probe.cancelActions, Probe.cancelActions
callbacks.OnTickEvenPaused()
check(paused == 0, "paused cleanup does nothing before bridge begin")
callbacks.OnGameStart()
check(Probe.ready, "version-matched bridge starts")
callbacks.OnTickEvenPaused()
check(paused == 1 and jobs == 0 and normal == 0, "pause only calls dedicated cleanup/timer hook")
callbacks.OnTick()
check(normal == 1 and jobs == 3, "ordinary tick remains the only job dispatcher")
callbacks.OnPreMapLoad()
check(cancelled == 3 and Probe.ready, "reset cancels every executor but retains pending cleanup")
callbacks.OnTickEvenPaused()
check(paused == 2 and jobs == 3, "pending retirement can progress while paused without dispatching jobs")
Probe.cleanupHaul = function() return false end
local savedPrint = print
print = function() end
callbacks.OnSave()
print = savedPrint
check(cleared == 0, "blocked fixture cleanup does not initiate carrier deletion")
Probe.cleanupHaul = function() return true end
callbacks.OnSave()
check(cleared == 1, "save can initiate retirement after successful fixture cleanup")
EmberRoutesProbeJava.begin = function() return "BASELINE_CHANGED actual=override" end
callbacks.OnGameStart()
check(Probe.hasJava() and not Probe.ready and not Probe.restorePending, "loaded Java with rejected baseline is not an absent interface")
check(Probe.unavailableCode() == "BASELINE_CHANGED", "actual startup rejection code retained")
check(Probe.unavailableMessage():find("DriverNotReady") and Probe.unavailableMessage():find("BASELINE_CHANGED"),
    "UI reports driver refusal and its cause")
local pausedBeforeRefusal = paused
callbacks.OnTickEvenPaused()
check(paused == pausedBeforeRefusal, "refused driver remains stopped")
EmberRoutesProbeJava.version = function() return "old-version" end
callbacks.OnGameStart()
check(Probe.unavailableCode() == "VERSION_MISMATCH" and Probe.unavailableMessage():find("VersionMismatch"),
    "mixed Lua/JAR versions have their own diagnosis")
EmberRoutesProbeJava.version = function() return "test" end
local saveMethod = EmberRoutesProbeJava.saveCheckpoint
EmberRoutesProbeJava.saveCheckpoint = nil
callbacks.OnGameStart()
check(Probe.unavailableCode() == "MISSING_JAVA" and Probe.unavailableMessage():find("MissingJava"),
    "missing required exposed method still reports interface failure")
EmberRoutesProbeJava.saveCheckpoint = saveMethod
EmberRoutesProbeJava.begin = function() return "READY restored" end
callbacks.OnGameStart()
check(Probe.ready and Probe.restorePending and Probe.failureCode == "READY", "successful begin clears prior startup failure")
print("PASS " .. count .. " boot pause/lifecycle assertions; engine event cadence NOT simulated")
