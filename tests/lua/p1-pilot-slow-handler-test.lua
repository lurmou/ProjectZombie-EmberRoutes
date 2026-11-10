-- P0 pilot: slow-handler naming (Viewpoint/Smooth Frames).
-- Run from the repo root: lua5.1 tests/lua/p1-pilot-slow-handler-test.lua
-- A single domain tick at or above TickConfig.slowHandlerMs (8ms) writes
-- one structured RUNTIME_PERF SLOW_HANDLER line (domain, ms, NPC count);
-- below threshold nothing is written; repeats from the same domain inside
-- slowHandlerLogCooldownMs are dropped. Naming fires on the ordinary
-- unmeasured Boot dispatch -- not only inside a 20s sampling session,
-- where the numbers otherwise sit in a table nobody reads mid-game.
-- Performance sampling itself is unchanged: rows/END summary still record
-- the same calls, totals and maxima.
package.path = "Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;" .. package.path
local checks = 0
local function check(value, message) checks = checks + 1 assert(value, message) end
local logs = {}
DebugLog = { log = function(message) logs[#logs + 1] = message end }
function getText(key) return key end
package.loaded["EmberRoutesProbe/Kernel/Build"] = { version = "test", prefix = "TEST" }

local callbacks = {}
Events = {}
for _, name in ipairs({ "OnGameStart", "OnServerStarted", "OnTick", "OnTickEvenPaused", "OnPreMapLoad", "OnSave" }) do
    Events[name] = { Add = function(fn) callbacks[name] = fn end }
end

-- Controllable diagnostic clock (ns) and NPC count.
local nanos, npcCount = 0, 7
local javaTicks = 0
EmberRoutesProbeJava = {
    tick = function() javaTicks = javaTicks + 1 end,
    diagnosticTimeNanos = function() return nanos end,
    workerCount = function() return npcCount end,
    cadenceIs60Hz = function() return true end,
    cadenceIs15Hz = function() return true end,
    cadenceIs5Hz = function() return true end,
    cadenceIs1Hz = function() return true end,
}

local Metrics = require "EmberRoutesProbe/Kernel/RuntimeMetrics"
local TickConfig = require "EmberRoutesProbe/Kernel/TickConfig"
check(TickConfig.slowHandlerMs == 8, "threshold lives in TickConfig at 8ms, not scattered")
check(TickConfig.slowHandlerLogCooldownMs == 5000, "per-domain log throttle lives in TickConfig at 5000ms")

local function slowLines()
    local found = {}
    for _, line in ipairs(logs) do
        if string.find(line, "SLOW_HANDLER", 1, true) then found[#found + 1] = line end
    end
    return found
end

-- 1. reportSlow: below threshold writes nothing; at threshold writes one
-- structured line with domain, cost and NPC count.
check(Metrics.reportSlow("Tasks", 7.999, 1000) == false, "7.999ms is below threshold")
check(#slowLines() == 0, "below threshold writes no line")
check(Metrics.reportSlow("Tasks", 8, 1000) == true, "exactly 8ms names the domain")
local lines = slowLines()
check(#lines == 1, "one line for one slow tick")
check(string.find(lines[1], "RUNTIME_PERF SLOW_HANDLER", 1, true) ~= nil, "line uses the RUNTIME_PERF category and SLOW_HANDLER event")
check(string.find(lines[1], "domain=Tasks", 1, true) ~= nil, "line names the domain")
check(string.find(lines[1], "ms=8.000", 1, true) ~= nil, "line carries the cost in ms")
check(string.find(lines[1], "npcs=7", 1, true) ~= nil, "line carries the NPC count")

-- 2. Throttle: same domain inside the cooldown is dropped; another domain
-- is not; the same domain at the cooldown boundary logs again.
check(Metrics.reportSlow("Tasks", 12, 1000 + 4999) == false, "same domain 4999ms later is throttled")
check(Metrics.reportSlow("Work", 9, 1000 + 4999) == true, "another domain is throttled independently")
check(#slowLines() == 2, "throttled repeat adds no line, other domain adds one")
check(Metrics.reportSlow("Tasks", 12, 1000 + 5000) == true, "same domain at the 5000ms boundary logs again")
check(#slowLines() == 3, "boundary repeat adds one line")

-- 3. reset() clears the throttle so a new world starts with a fresh budget.
Metrics.reset()
check(Metrics.reportSlow("Tasks", 9, 1000 + 5001) == true, "reset clears per-domain throttle state")
check(#slowLines() == 4, "post-reset slow tick logs again")

-- 4. No bridge workerCount: the line still names the domain with npcs=0
-- instead of failing the log call.
EmberRoutesProbeJava.workerCount = nil
check(Metrics.reportSlow("Haul", 20, 0) == true, "slow tick without workerCount still logs")
check(string.find(slowLines()[#slowLines()], "npcs=0", 1, true) ~= nil, "missing workerCount reads as npcs=0")
EmberRoutesProbeJava.workerCount = function() return npcCount end

-- 5. measure() still records the same sampling rows, and now also names a
-- slow measured domain; a fast measured domain stays silent.
Metrics.reset()
logs = {}
check(Metrics.start() == true, "sampling session starts")
Metrics.measure("Work", function() nanos = nanos + 10000000 end) -- 10ms slow
Metrics.measure("Work", function() nanos = nanos + 1000000 end) -- 1ms fast
local measuredSlow = slowLines()
check(#measuredSlow == 1, "slow measured domain is named once")
check(string.find(measuredSlow[1], "domain=Work", 1, true) ~= nil, "measured slow line names Work")
check(string.find(measuredSlow[1], "ms=10.000", 1, true) ~= nil, "measured slow line carries 10ms")
nanos = nanos + 21000000000
Metrics.finishTick(nanos / 1000000)
local result = Metrics.result()
check(result ~= nil and result.rows.Work.calls == 2, "sampling still records both measured calls")
check(result.rows.Work.max >= 10 and result.rows.Work.max < 10.001, "sampling still records the 10ms max")
check(result.rows.Work.total >= 11 and result.rows.Work.total < 11.001, "sampling still records the 11ms total")
Metrics.reset()
check(Metrics.result() == nil, "reset still drops the sample")

-- 6. Boot dispatch, unmeasured path (no sampling session): a slow hook is
-- named with its label, a fast hook is not, repeats are throttled, and
-- every hook still runs every tick.
local Probe = dofile("Contents/mods/EmberRoutesProbe/42/media/lua/shared/EmberRoutesProbe/Kernel/Boot.lua")
Probe.ready = true
logs = {}
nanos = 0
local ran = {}
Probe.tickTasks = function() ran[#ran + 1] = "Tasks" nanos = nanos + 12000000 end -- 12ms slow
Probe.tickWork = function() ran[#ran + 1] = "Work" nanos = nanos + 1000000 end -- 1ms fast
check(Metrics.active() == false, "no sampling session: unmeasured dispatch")
callbacks.OnTick()
check(#ran == 2 and ran[1] == "Tasks" and ran[2] == "Work", "unmeasured tick still runs both hooks")
local dispatched = slowLines()
check(#dispatched == 1, "unmeasured slow hook writes one line")
check(string.find(dispatched[1], "domain=Tasks", 1, true) ~= nil, "dispatch line names Tasks")
check(string.find(dispatched[1], "ms=12.000", 1, true) ~= nil, "dispatch line carries 12ms")
check(string.find(dispatched[1], "npcs=7", 1, true) ~= nil, "dispatch line carries the NPC count")
callbacks.OnTick()
check(#ran == 4, "second tick still runs both hooks")
check(#slowLines() == 1, "second slow tick inside the cooldown does not re-log")
nanos = nanos + 5000000000 -- 5000ms later
callbacks.OnTick()
check(#ran == 6, "third tick still runs both hooks")
check(#slowLines() == 2, "slow tick after the cooldown logs again")

-- 7. No diagnostic clock on the bridge: the unmeasured dispatch runs the
-- hooks unchanged, with no timing and no crash.
EmberRoutesProbeJava.diagnosticTimeNanos = nil
local before = #ran
callbacks.OnTick()
check(#ran == before + 2, "bridgeless-clock tick still runs both hooks")
check(#slowLines() == 2, "no diagnostic clock means no slow lines")
EmberRoutesProbeJava.diagnosticTimeNanos = function() return nanos end

print("PASS " .. checks .. " slow-handler naming assertions")
