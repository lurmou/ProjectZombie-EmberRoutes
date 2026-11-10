-- Equivalence probe for the table-driven tick dispatch (P1 probe-tick).
-- Locks the pre-change dispatch contract from main 7459747:
--   call order per cadence tier, cadence gating, Performance.measure labels,
--   missing-key silent skip -- for both the unmeasured tickServices path
--   (Performance inactive) and the measured Probe.tick path.
-- tickDelivery is intentionally absent from the expected order: the key is
-- nilled at load by DeliveryService and no production writer registers it
-- (p1-probe-deadkeys); even a registered tickDelivery must never be called.
local count = 0
local function check(value, message) count = count + 1 assert(value, message) end
local function checkSeq(actual, expected, message)
    count = count + 1
    assert(#actual == #expected, message .. " (length " .. #actual .. " vs " .. #expected .. ")")
    for i = 1, #expected do
        assert(actual[i] == expected[i], message .. " (position " .. i .. ": " .. tostring(actual[i]) .. " vs " .. expected[i] .. ")")
    end
end

package.path = "Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;" .. package.path
DebugLog = { log = function(message) print(message) end }
function getText(key) return key end

-- Controllable cadence gates; Java tick is a plain counter.
local gates = { hz60 = true, hz15 = true, hz5 = true, hz1 = true }
local javaTicks = 0
local javaTickFn
EmberRoutesProbeJava = {
    tick = function() javaTicks = javaTicks + 1 end,
    cadenceIs60Hz = function() return gates.hz60 end,
    cadenceIs15Hz = function() return gates.hz15 end,
    cadenceIs5Hz = function() return gates.hz5 end,
    cadenceIs1Hz = function() return gates.hz1 end,
}
javaTickFn = EmberRoutesProbeJava.tick

-- Recording fake Performance: observes exactly what Probe.tick measures.
local perfActive, perfNow = false, 0
local perfCalls, finishCalls = {}, {}
package.loaded["EmberRoutesProbe/Kernel/Build"] = { version = "test", prefix = "TEST" }
package.loaded["EmberRoutesProbe/Kernel/Log"] = { write = function() end }
package.loaded["EmberRoutesProbe/Kernel/RuntimeMetrics"] = {
    active = function() return perfActive end,
    now = function() perfNow = perfNow + 1 return perfNow end,
    measure = function(label, fn) perfCalls[#perfCalls + 1] = { label = label, fn = fn } fn() end,
    finishTick = function(started) finishCalls[#finishCalls + 1] = started end,
    reset = function() end,
}

local callbacks = {}
Events = {}
for _, name in ipairs({ "OnGameStart", "OnServerStarted", "OnTick", "OnPreMapLoad", "OnSave" }) do
    Events[name] = { Add = function(fn) callbacks[name] = fn end }
end

local Probe = dofile("Contents/mods/EmberRoutesProbe/42/media/lua/shared/EmberRoutesProbe/Kernel/Boot.lua")
Probe.ready = true
check(callbacks.OnTick == Probe.tick, "OnTick still dispatches Probe.tick")

-- Expected dispatch order, verbatim from the pre-change code (minus the
-- dead tickDelivery): 60Hz Tasks/Actions, 15Hz Work/Haul/Crafting,
-- 5Hz SelfCare/Activities/PublicWork/Logistics/CraftView/CraftRead,
-- 1Hz Membership/Persistence/Retirement.
local ALL_KEYS = { "tickTasks", "tickActions", "tickWork", "tickHaul", "tickCrafting",
    "tickSelfCare", "tickActivities", "tickPublicWork", "tickLogistics", "tickCraftView",
    "tickCraftRead", "tickMembership", "tickPersistence", "tickRetirement" }
local ALL_LABELS = { "Tasks", "Actions", "Work", "Haul", "Crafting",
    "SelfCare", "Activities", "PublicWork", "Logistics", "CraftView",
    "CraftRead", "Membership", "Persistence", "Retirement" }

local calls = {}
local function registerAll()
    -- Deliberately register in reverse order: dispatch order must come from
    -- the table, never from registration order.
    for i = #ALL_KEYS, 1, -1 do
        local key = ALL_KEYS[i]
        Probe[key] = function() calls[#calls + 1] = key end
    end
    -- Dead key: registered, but must never be dispatched.
    Probe.tickDelivery = function() calls[#calls + 1] = "tickDelivery" end
end
local function resetState()
    calls, perfCalls, finishCalls = {}, {}, {}
    javaTicks = 0
    gates.hz60, gates.hz15, gates.hz5, gates.hz1 = true, true, true, true
end

-- 1. Unmeasured path (Performance inactive): full order, no measure calls.
registerAll()
resetState()
callbacks.OnTick()
check(javaTicks == 1, "unmeasured tick still runs the Java tick first")
checkSeq(calls, ALL_KEYS, "unmeasured path calls hooks in original order")
check(#perfCalls == 0 and #finishCalls == 0, "unmeasured path records no measures")

-- 2. Measured path (Performance active): same order, same labels, Java first.
perfActive = true
resetState()
callbacks.OnTick()
checkSeq(calls, ALL_KEYS, "measured path calls hooks in original order")
check(#perfCalls == #ALL_KEYS + 1, "measured path measures Java plus every hook")
check(perfCalls[1].label == "Java" and perfCalls[1].fn == javaTickFn, "Java tick measured first with label Java")
for i = 1, #ALL_KEYS do
    check(perfCalls[i + 1].label == ALL_LABELS[i], "hook " .. ALL_KEYS[i] .. " measured with label " .. ALL_LABELS[i])
    check(perfCalls[i + 1].fn == Probe[ALL_KEYS[i]], "measured fn for " .. ALL_LABELS[i] .. " is the registered hook")
end
check(#finishCalls == 1 and finishCalls[1] == 1, "measured tick finishes once with the started timestamp")
perfActive = false

-- 3. Cadence gating: each closed gate skips exactly its tier, nothing else.
resetState()
gates.hz15 = false
callbacks.OnTick()
checkSeq(calls, { "tickTasks", "tickActions", "tickSelfCare", "tickActivities", "tickPublicWork",
    "tickLogistics", "tickCraftView", "tickCraftRead", "tickMembership", "tickPersistence", "tickRetirement" },
    "closed 15Hz gate skips only Work/Haul/Crafting")
resetState()
gates.hz60, gates.hz15, gates.hz5, gates.hz1 = false, false, false, false
callbacks.OnTick()
check(#calls == 0 and javaTicks == 1, "all gates closed runs only the Java tick")
resetState()
gates.hz1 = false
callbacks.OnTick()
check(#calls == 11 and calls[#calls] == "tickCraftRead", "closed 1Hz gate drops Membership/Persistence/Retirement tail")

-- 4. Missing keys are silently skipped, in order, on both paths.
Probe.tickHaul, Probe.tickCraftRead, Probe.tickMembership = nil, nil, nil
resetState()
callbacks.OnTick()
checkSeq(calls, { "tickTasks", "tickActions", "tickWork", "tickCrafting", "tickSelfCare",
    "tickActivities", "tickPublicWork", "tickLogistics", "tickCraftView", "tickPersistence", "tickRetirement" },
    "unmeasured path skips missing keys without disturbing order")
perfActive = true
resetState()
callbacks.OnTick()
check(#perfCalls == 12, "measured path measures only present hooks plus Java")
local labels = {}
for _, entry in ipairs(perfCalls) do labels[#labels + 1] = entry.label end
checkSeq(labels, { "Java", "Tasks", "Actions", "Work", "Crafting", "SelfCare", "Activities",
    "PublicWork", "Logistics", "CraftView", "Persistence", "Retirement" },
    "measured labels skip missing keys in order")
perfActive = false
registerAll()

-- 5. Java tick follows Probe.ready; hooks do not depend on it.
Probe.ready = false
resetState()
callbacks.OnTick()
check(javaTicks == 0, "Java tick skipped while not ready")
checkSeq(calls, ALL_KEYS, "hooks still dispatch while not ready")
Probe.ready = true

-- 6. No Java bridge at all: gates default open, hooks still dispatch.
local savedJava = EmberRoutesProbeJava
EmberRoutesProbeJava = nil
resetState()
callbacks.OnTick()
check(javaTicks == 0, "no Java tick without a bridge")
checkSeq(calls, ALL_KEYS, "all gates default open without a bridge")
EmberRoutesProbeJava = savedJava

-- 7. Hot path allocates nothing per tick: with the GC stopped, counter-only
-- hooks and the unmeasured path, 1000 ticks must not grow memory at all.
for _, key in ipairs(ALL_KEYS) do
    Probe[key] = function() javaTicks = javaTicks + 1 end
end
Probe.tickDelivery = function() javaTicks = javaTicks + 1 end
collectgarbage("stop")
local before = collectgarbage("count")
for _ = 1, 1000 do callbacks.OnTick() end
local after = collectgarbage("count")
collectgarbage("restart")
check(after == before, "1000 unmeasured ticks allocate nothing (KB " .. tostring(before) .. " -> " .. tostring(after) .. ")")

print("PASS " .. count .. " probe tick-dispatch equivalence assertions")
