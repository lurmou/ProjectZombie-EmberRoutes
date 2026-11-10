-- P1 pilot: event subscription dedup (read-load re-registration).
-- Run from the repo root: lua5.1 tests/lua/p1-pilot-event-dedup-test.lua
-- The engine never dedupes Events.X.Add (zombie/Lua/Event$Add is a bare
-- ArrayList.add), so a callback added twice fires twice. Boot subscribes
-- through Kernel/EventBus.subscribeOnce with stable string keys, and its
-- retirement handler through EventBus.runOnce, so:
--   * two save loads (two OnGameStart fires) keep one callback per event;
--   * a second Boot file execution in the same Lua state -- the only
--     re-registration path left, since begin()/reset() contain no Add and
--     require caches the module -- also keeps one callback per event, and
--     one retirement handler on the even-paused dispatcher.
-- Normal startup is unchanged: one load still subscribes all five engine
-- events, begin still runs, reset and save still fire.
package.path = "Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;" .. package.path
local checks = 0
local function check(value, message) checks = checks + 1 assert(value, message) end
DebugLog = { log = function(message) end }
package.loaded["EmberRoutesProbe/Kernel/Build"] = { version = "test", prefix = "TEST" }
function getText(key) return key end
SandboxVars = { EmberRoutes = { CarrierProbe = true } }
-- Advancing clock: every even-paused fire runs its handlers (readMs=50).
local now = 0
function getTimestampMs() now = now + 1000 return now end

-- Engine-faithful Events stub: Add appends with no dedup, fire calls
-- every registered callback in order and returns the invocation count.
local lists = {}
Events = {}
for _, name in ipairs({ "OnGameStart", "OnServerStarted", "OnTick", "OnTickEvenPaused", "OnPreMapLoad", "OnSave" }) do
    lists[name] = {}
    Events[name] = { Add = function(fn) lists[name][#lists[name] + 1] = fn end }
end
local function fire(name)
    local n = 0
    for _, fn in ipairs(lists[name]) do fn() n = n + 1 end
    return n
end
local function listeners(name) return #lists[name] end

-- EventBus unit checks on a fresh fake event.
local EventBus = require "EmberRoutesProbe/Kernel/EventBus"
local fake = { added = {} }
fake.Add = function(fn) fake.added[#fake.added + 1] = fn end
local firstRuns, secondRuns = 0, 0
local first = function() firstRuns = firstRuns + 1 end
local second = function() secondRuns = secondRuns + 1 end
check(EventBus.subscribeOnce(fake, "k", first) == true, "first subscribe registers")
check(EventBus.subscribeOnce(fake, "k", first) == false, "same key+fn does not re-register")
check(EventBus.subscribeOnce(fake, "k", second) == false, "same key with a fresh closure does not re-register")
check(#fake.added == 1 and fake.added[1] == first, "first registration wins")
check(EventBus.subscribeOnce(fake, "other", second) == true, "a different key is a different subscription")
check(#fake.added == 2, "second key adds its own callback")
for _, fn in ipairs(fake.added) do fn() end
check(firstRuns == 1 and secondRuns == 1, "each registered callback fires once")
check(EventBus.subscribeOnce(nil, "k", first) == false, "nil event is rejected")
check(EventBus.subscribeOnce(fake, "k2", nil) == false, "nil callback is rejected")
check(EventBus.subscribeOnce({}, "k3", first) == false, "event without Add is rejected")
check(EventBus.subscribeOnce(fake, 7, first) == false, "non-string key is rejected")
local ran = 0
check(EventBus.runOnce("once", function() ran = ran + 1 end) == true, "runOnce runs the first time")
check(EventBus.runOnce("once", function() ran = ran + 1 end) == false, "runOnce skips the second time")
check(ran == 1, "runOnce body ran exactly once")

-- Boot integration: bridge stub copied from boot-pause-test, plus counters.
local javaTicks, retireTicks, cleared, cancelled = 0, 0, 0, 0
local function stub() end
EmberRoutesProbeJava = {
    moveSeatWithControl = stub, reachedSeat = stub,
    followWithControl = stub, followMetrics = stub, moveBedWithControl = stub, bedPoseReady = stub,
    furniturePoseWithControl = stub, moveSleepSeatWithControl = stub, floorSleepSafe = stub,
    begin = function() return "READY" end, version = function() return "test" end,
    tick = function() javaTicks = javaTicks + 1 end,
    retirementTick = function() retireTicks = retireTicks + 1 end,
    command = stub, reset = function() return "REMOVAL_PENDING" end,
    clearForSave = function() cleared = cleared + 1 end,
    actionCarrier = stub, carrierActive = stub, carrierPresent = stub, motionResult = stub,
    reposeWithControl = stub, reposeAtWithControl = stub,
    stopCarrier = stub, controlledCarrier = stub, carrierId = stub,
    saveCheckpoint = stub, restoreCheckpoint = stub, blockCheckpoint = stub, reportCheckpoint = stub,
    checkpointMode = stub, checkpointHasHome = stub, checkpointHomeX = stub, checkpointHomeY = stub, checkpointHomeZ = stub,
    commandFor = stub, carrierFor = stub, ownedCarrierId = stub, selectedId = stub, spawnAdditional = stub, selectCarrier = stub,
    workerCount = stub, workerIdAt = stub, saveCheckpointFor = stub, blockAllCheckpoints = stub,
}
local bootPath = "Contents/mods/EmberRoutesProbe/42/media/lua/shared/EmberRoutesProbe/Kernel/Boot.lua"

local Probe1 = dofile(bootPath)
Probe1.controlledExecution = false -- Explicit legacy lifecycle fixture, as in boot-pause-test.
for _, name in ipairs({ "OnGameStart", "OnServerStarted", "OnTick", "OnPreMapLoad", "OnSave" }) do
    check(listeners(name) == 1, "one load subscribes " .. name .. " exactly once")
end
check(listeners("OnTickEvenPaused") == 1, "one load subscribes the even-paused dispatcher exactly once")

-- Two save loads: begin runs per load by design, subscriptions stay single.
check(fire("OnGameStart") == 1, "first load fires begin once")
check(Probe1.ready, "version-matched bridge starts")
check(fire("OnGameStart") == 1, "second load still fires begin once")
for _, name in ipairs({ "OnGameStart", "OnServerStarted", "OnTick", "OnPreMapLoad", "OnSave" }) do
    check(listeners(name) == 1, "two loads keep " .. name .. " at one subscription")
end
local before = javaTicks
check(fire("OnTick") == 1 and javaTicks - before == 1, "one tick fire runs the Java tick once after two loads")
before = retireTicks
check(fire("OnTickEvenPaused") == 1 and retireTicks - before == 1, "one even-paused fire runs retirement once after two loads")

-- Second Boot file execution in the same Lua state: no second registration.
local Probe2 = dofile(bootPath)
Probe2.controlledExecution = false
for _, name in ipairs({ "OnGameStart", "OnServerStarted", "OnTick", "OnPreMapLoad", "OnSave" }) do
    check(listeners(name) == 1, "re-executed Boot keeps " .. name .. " at one subscription")
end
check(listeners("OnTickEvenPaused") == 1, "re-executed Boot keeps the even-paused dispatcher at one subscription")
-- One more load after re-execution: both Probes would be live if the guard
-- had failed, so the tick and retirement counts expose any duplicate.
check(fire("OnGameStart") == 1, "load after re-execution still fires begin once")
before = javaTicks
check(fire("OnTick") == 1 and javaTicks - before == 1, "one tick fire runs the Java tick once after re-execution")
before = retireTicks
check(fire("OnTickEvenPaused") == 1 and retireTicks - before == 1, "one even-paused fire runs retirement once after re-execution")

-- Regression: reset and save are still wired to the live Probe.
Probe1.registerCancel("Actions", function() cancelled = cancelled + 1 end)
Probe1.registerCancel("Haul", function() cancelled = cancelled + 1 end)
Probe1.registerCancel("Companion", function() cancelled = cancelled + 1 end)
check(fire("OnPreMapLoad") == 1 and cancelled == 3 and Probe1.ready, "reset cancels every executor but retains pending cleanup")
Probe1.cleanupHaul = function() return true end
check(fire("OnSave") == 1 and cleared == 1, "save still reaches the bridge cleanup")

print("PASS " .. checks .. " event-dedup assertions")
