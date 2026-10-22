local world = dofile("tests/lua/haul-test.lua")
local ctx, npc, actor, Haul = world.ctx, world.npc, world.actor, world.Haul
function getSpecificPlayer() return actor end
local count = 0
local function check(value, message) count = count + 1 assert(value, message) end
EmberRoutesProbeJava.controlledCarrier = function() return npc end
EmberRoutesProbeJava.carrierId = function(expected) return expected == npc and "haul-carrier" or "" end
function ctx.Probe.cancelAll(reason)
    if ctx.Probe.cancelCompanion then ctx.Probe.cancelCompanion(reason) end
    ctx.Actions.cancel(reason)
    Haul.cancel(reason)
end
local Companion = require "EmberRoutesProbe/Companion"
local savedPrint = print
print = function() end
Companion.execute(actor, "follow")
Companion.tick()
check(Companion.mode == "FOLLOW", "start real companion controller")
Haul.execute(actor, "run")
check(Companion.mode == "HOLD" and Haul.busy(), "real haul start takes ownership from follower")
world.tick(2)
Companion.execute(actor, "follow")
check(Companion.mode == "FOLLOW" and Haul.batch.state == "CANCELLED" and npc.actions:isEmpty(), "follow cancels real haul queue before taking ownership")
ctx.Actions.execute(actor, "eat")
check(Companion.mode == "HOLD" and ctx.Actions.isBusy(), "real self-care request takes ownership from follower")
ctx.tick(1)
Companion.execute(actor, "follow")
check(Companion.mode == "FOLLOW" and ctx.Actions.batch.state == "CANCELLED" and npc.actions:isEmpty(), "follow cancels real self-care batch")
ctx.Probe.cancelAll("USER_STOP")
check(Companion.mode == "HOLD" and not Haul.busy() and not ctx.Actions.isBusy(), "global stop releases all executors")
ctx.Actions.execute(actor, "cleanup")
Haul.cleanup()
print = savedPrint
print("PASS " .. count .. " real-controller handoff assertions; native fakes NOT runtime evidence")
