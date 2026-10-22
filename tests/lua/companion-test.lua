package.path = "Contents/mods/EmberRoutesProbe/42/media/lua/client/?.lua;" .. package.path
package.path = "Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;" .. package.path
DebugLog = { log = function(message) print(message) end }
local assertions, time, id, present, refuse, moves, stops = 0, 0, "npc-1", true, false, 0, 0
local function check(value, message) assertions = assertions + 1 assert(value, message) end
local function body(x)
    local npc = { x = x, y = 0, z = 0, motion = "IDLE" }
    function npc:getX() return self.x end
    function npc:getY() return self.y end
    function npc:getZ() return self.z end
    return npc
end
local npc = body(0)
local actor = body(6)
function getSpecificPlayer() return actor end
actor.dead, actor.speech = false, {}
function actor:isDead() return self.dead end
function actor:Say(value) self.speech[#self.speech + 1] = value end
function getTimestampMs() return time end
function getText(key) return key end
local nativeTarget
EmberRoutesProbeJava = {
    controlledCarrier = function() if present and not actor.dead then return npc end end,
    carrierPresent = function(expected) return present and npc == expected end,
    carrierId = function(expected) return present and npc == expected and id or "" end,
    motionResult = function(expected) return expected.motion end,
    stopCarrier = function(expected) stops = stops + 1 expected.motion = "STOPPED" return true end,
    command = function(command, _, x, y, z)
        check(command == "move", "adapter submits only native move intent")
        if refuse then return "INVALID_TILE" end
        moves, npc.motion = moves + 1, "MOVING"
        nativeTarget = { x = x, y = y, z = z }
        return "MOVE_REQUESTED"
    end,
}
local jobsCancelled = 0
local Probe = { ready = true, build = { prefix = "TEST" }, hasJava = function() return true end }
function Probe.cancelAll(reason)
    if Probe.cancelCompanion then Probe.cancelCompanion(reason) end
    jobsCancelled = jobsCancelled + 1
end
package.loaded["EmberRoutesProbe/Boot"] = Probe
local Driver = require "EmberRoutesProbe/Driver"
local Companion = require "EmberRoutesProbe/Companion"
local realPrint = print
print = function() end
local function tick(at) time = at Companion.tick() end
Companion.execute(actor, "follow")
check(Companion.mode == "FOLLOW" and Companion.home.x == 0, "first follow captures home and starts mode")
check(jobsCancelled == 1, "new order cancels previous executor")
tick(0)
check(moves == 1 and nativeTarget.x == actor.x, "controller submits follow intent through driver")
tick(100)
tick(500)
check(moves == 1, "no per-frame path restart")
npc.x = 5
tick(1000)
check(npc.motion == "STOPPED" and Companion.mode == "FOLLOW", "nearby follower stops but keeps follow order")
Companion.execute(actor, "home")
check(Companion.mode == "RETURNING" and nativeTarget.x == 0, "return uses captured home")
npc.x, npc.motion = 0, "REACHED"
tick(1500)
check(Companion.mode == "HOLD" and Companion.reason == "HOME_REACHED", "return finishes in hold")
Companion.execute(actor, "follow")
Companion.execute(actor, "hold")
local heldMoves = moves
tick(10000)
check(Companion.mode == "HOLD" and moves == heldMoves, "hold does not spontaneously restart")
Companion.execute(actor, "follow")
actor.x = 100
tick(11000)
check(Companion.mode == "BLOCKED" and Companion.reason == "LEADER_TOO_FAR", "far leader blocks without teleport")
actor.x = 6
Companion.execute(actor, "follow")
actor.dead = true
tick(12000)
check(Companion.mode == "HOLD" and npc.motion == "STOPPED", "leader death cancels movement")
actor.dead = false
Companion.execute(actor, "follow")
Probe.cancelCompanion("HAUL_ORDER")
check(Companion.mode == "HOLD" and Companion.reason == "HAUL_ORDER", "work handoff cancels follow")
Companion.execute(actor, "home")
npc.motion = "TIMEOUT"
tick(13000)
check(Companion.mode == "BLOCKED" and Companion.reason == "HOME_TIMEOUT", "home path failure is terminal")
local previous = Driver.bind(actor)
Companion.execute(actor, "follow")
npc, id = body(1), "npc-2"
local beforeReplacementTick = moves
tick(14000)
check(Companion.mode == "HOLD" and moves == beforeReplacementTick, "stale order cannot move a replacement NPC")
check(Driver.move(previous, actor, {x=3,y=0,z=0}) == "STALE_NPC", "adapter rejects old stable ID")
Companion.execute(actor, "home")
check(Companion.home == nil and actor.speech[#actor.speech]:find("HOME_NOT_SET"), "old home does not transfer to new NPC")
Companion.execute(actor, "sethome")
check(Companion.home.npcId == "npc-2" and Companion.home.x == 1, "home binds to new NPC UUID")
local snapshot = Driver.snapshot(Driver.bind(actor), actor)
snapshot.x = 1234
check(npc.x == 1 and snapshot.id == id and snapshot.handle == nil, "public snapshot is scalar data, not mutable carrier")
check(Driver.capabilities().mode == "SINGLE_PLAYER" and not Driver.capabilities().multiplayer, "reserved interface does not claim MP support")
refuse = true
Companion.execute(actor, "follow")
for _, at in ipairs({15000, 16500, 18000}) do tick(at) end
check(Companion.mode == "BLOCKED" and Companion.reason == "REQUEST_FAILURE_LIMIT", "three refused paths stop controller")
local blockedMoves = moves
tick(30000)
check(moves == blockedMoves, "blocked mode never retries forever")
refuse = false
Companion.execute(actor, "follow")
local saved = Companion.exportState()
check(saved.mode == "FOLLOW" and saved.id == "npc-2" and saved.hasHome and saved.homeX == 1,
    "export captures intent and home for stable identity")
saved.homeX = 9
check(Companion.home.x == 1 and saved.handle == nil and saved.actor == nil, "export contains detached scalars only")
Probe.cancelCompanion("SAVE")
local resumeMoves = moves
check(Companion.restoreState(actor, saved) and Companion.mode == "FOLLOW" and moves == resumeMoves,
    "restore follow builds fresh policy without replaying old native path")
check(Companion.home.x == 9 and Companion.home.npcId == "npc-2", "restored home binds to current stable UUID")
saved.mode = "RETURNING"
Companion.restoreState(actor, saved)
check(Companion.mode == "RETURNING" and moves == resumeMoves + 1 and nativeTarget.x == 9,
    "restore return creates a newly validated move request")
saved.id = "old-npc"
check(not Companion.restoreState(actor, saved), "persisted intent cannot bind replacement character")
saved.id, saved.mode, saved.hasHome = "npc-2", "HOLD", false
Companion.restoreState(actor, saved)
check(Companion.mode == "HOLD" and Companion.home == nil, "hold without anchor does not invent a home")
present = false
tick(31000)
check(Companion.binding == nil and Companion.home == nil, "inactive controller releases removed carrier references")
Probe.resetCompanion()
check(Companion.binding == nil and Companion.home == nil and Companion.mode == "HOLD", "world reset releases bindings and home")
print = realPrint
print("PASS " .. assertions .. " companion/driver assertions; native fakes NOT runtime evidence")
