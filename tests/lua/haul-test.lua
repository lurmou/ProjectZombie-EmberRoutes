-- Port fakes exercise only our world-haul orchestration, not engine compatibility.
local ctx = dofile("tests/lua/actions-test.lua")
local npc, actor = ctx.npc, ctx.actor
ctx.setActive(true)
local old = ctx.Actions.fixtures
old.cargo:getContainer():Remove(old.cargo)
npc.root.items[#npc.root.items + 1] = old.cargo
old.cargo.container = npc.root
ctx.Actions.execute(actor, "cleanup")
local assertions = 0
local function check(value, message) assertions = assertions + 1 assert(value, message) end
local squares = {}
local function square(x, y, z)
    for _, existing in ipairs(squares) do if existing.x == x and existing.y == y and existing.z == z then return existing end end
    local s = { x = x, y = y, z = z, objects = ctx.list({}) }
    function s:getX() return self.x end
    function s:getY() return self.y end
    function s:getZ() return self.z end
    function s:getObjects() return self.objects end
    function s:canReachTo(other) return not other.blocked end
    function s:TreatAsSolidFloor() return not self.noFloor end
    function s:isSolid() return self.solid == true end
    function s:isSolidTrans() return self.solidTrans == true end
    squares[#squares + 1] = s
    return s
end
local function object(x)
    local o = { square = square(x, 0, 0), container = ctx.newContainer(), data = {} }
    o.square.objects[1] = o
    o.container.world = true
    function o:getSquare() return self.square end
    function o:getContainer() return self.container end
    function o:getModData() return self.data end
    return o
end
local source, destination = object(4), object(12)
local unrelated = destination.container:AddItem("USER_PROPERTY")
local cell = {}
function cell:getGridSquare(x, y, z)
    for _, s in ipairs(squares) do if s.x == x and s.y == y and s.z == z then return s end end
end
function getCell() return cell end
function isClient() return false end
function isServer() return false end
local uuid = 0
function getRandomUUID() uuid = uuid + 1 return "uuid-" .. uuid end
npc.x, npc.y, npc.z = 0.5, 0.5, 0
function npc:getX() return self.x end
function npc:getY() return self.y end
function npc:getZ() return self.z end
function npc:getCurrentSquare() return square(math.floor(self.x), math.floor(self.y), self.z) end
function npc:faceThisObject() end
actor.x = 4.5
function actor:getX() return self.x end
function actor:getY() return 0.5 end
function actor:getZ() return 0 end
local alive, moving, motion, target, frames, failMove = true, false, "IDLE", nil, 0, false
EmberRoutesProbeJava.carrierPresent = function(expected) return alive and expected == npc end
EmberRoutesProbeJava.carrierActive = function(expected) return alive and expected == npc and not moving end
EmberRoutesProbeJava.actionCarrier = function() if alive and not moving then return npc end end
EmberRoutesProbeJava.motionResult = function() return motion end
EmberRoutesProbeJava.command = function(command, _, x, y, z)
    check(command == "move", "haul only issues a checked move intent")
    target, frames, moving, motion = { x, y, z }, 3, true, "MOVING"
    return "MOVE_REQUESTED"
end
EmberRoutesProbeJava.stopCarrier = function()
    moving, motion = false, "STOPPED"
    ISTimedActionQueue.clear(npc)
    return true
end
luautils = { getCorrectSquareForWall = function(_, s) return s end }
AdjacentFreeTileFinder = { Find = function(s) return square(s.x - 1, s.y, s.z) end }
local Haul = require "EmberRoutesProbe/Haul"
local realPrint = print
print = function() end
local function tick(count)
    for _ = 1, count do
        ctx.tick(1)
        if moving then
            frames = frames - 1
            if frames == 0 then
                if failMove then moving, motion = false, "FAILED" failMove = false
                else npc.x, npc.y, npc.z = unpack(target) moving, motion = false, "REACHED" end
            end
        end
        Haul.tick()
    end
end
Haul.execute(actor, "run")
check(not Haul.batch, "untagged containers cannot start a job")
Haul.execute(actor, "source", source)
actor.x = 12.5
Haul.execute(actor, "destination", destination)
local nativeBodyDamage = npc.getBodyDamage
local health = 75
function npc:getBodyDamage() return { getOverallBodyHealth = function() return health end } end
local sourceBefore = #source.container.items
Haul.execute(actor, "run")
check(not Haul.busy() and #source.container.items == sourceBefore and #Haul.fixtures == 0,
    "injured start rejected before creating fixtures or movement")
check(actor.speech[#actor.speech] == "IGUI_EmberRoutesProbe_HaulInjured", "injured start is visible instead of reporting started")
health = 100
Haul.execute(actor, "run")
local fixtures = Haul.fixtures
Haul.execute(actor, "run")
check(Haul.fixtures == fixtures and #fixtures == 3, "repeated request cannot mint more fixtures")
ctx.Actions.execute(actor, "eat")
check(not ctx.Actions.isBusy(), "self-care cannot compete with hauling")
tick(400)
check(Haul.batch.state == "PASSED" and #Haul.batch.records == 17, "all seventeen world route steps complete")
check(destination.container.items:contains(unrelated), "destination's original property preserved")
for _, f in ipairs(fixtures) do
    check(f.item:getContainer() == source.container and f.item:getID() == f.id, "same instance returned to source")
end
local resultCount = #Haul.batch.records
tick(50)
check(#Haul.batch.records == resultCount, "completed route cannot repeat")
Haul.execute(actor, "run")
tick(2)
health = 75
tick(1)
check(Haul.batch.state == "CANCELLED" and Haul.batch.reason == "INJURED" and not moving,
    "injury during running job cancels native path and retains its actual reason")
check(actor.speech[#actor.speech] == "IGUI_EmberRoutesProbe_HaulInjured", "running interruption shows injury reason immediately")
health = 100
Haul.execute(actor, "cleanup")
Haul.execute(actor, "run")
tick(3)
Haul.execute(actor, "cancel")
check(Haul.batch.state == "CANCELLED" and not moving and npc.actions:isEmpty(), "explicit cancellation stops movement and actions")
for _, f in ipairs(Haul.fixtures) do check(f.item:getContainer() ~= nil, "cancel retains actual items") end
Haul.execute(actor, "cleanup")
check(#Haul.fixtures == 0 and #source.container.items == 0, "cleanup removes only fixtures")
destination.container.full = true
Haul.execute(actor, "run")
tick(200)
check(Haul.batch.state ~= "PASSED" and not Haul.busy(), "full destination cannot be reported as complete")
for _, f in ipairs(Haul.fixtures) do check(f.item:getContainer() ~= destination.container, "capacity failure never forces insertion") end
destination.container.full = false
Haul.execute(actor, "cleanup")
Haul.execute(actor, "run")
tick(2)
Haul.execute(actor, "untag", destination)
tick(1)
check(Haul.batch.state == "CANCELLED" and not moving, "tag revocation interrupts immediately")
Haul.execute(actor, "cleanup")
actor.x = 12.5
Haul.execute(actor, "destination", destination)
Haul.execute(actor, "run")
tick(2)
destination.square.objects[1] = nil
tick(1)
check(Haul.batch.state == "CANCELLED", "removed container cannot accept settlement")
destination.square.objects[1] = destination
Haul.execute(actor, "cleanup")
Haul.execute(actor, "run")
tick(2)
alive = false
tick(1)
check(Haul.batch.state == "CANCELLED" and not moving, "carrier invalidation stops the job")
Haul.execute(actor, "cleanup")
check(destination.container.items:contains(unrelated), "all interrupted routes leave original property intact")
alive = true
Haul.execute(actor, "run")
tick(2)
local fixture = Haul.fixtures[1]
fixture.item:getModData().EmberRoutesHaulFixture = "TAMPERED"
tick(200)
check(Haul.batch.state == "FAILED", "changed instance state cannot pass transfer verification")
check(fixture.item:getContainer() == source.container, "instance changes are rejected before native mutation")
check(not Haul.cleanup(), "changed fixture identity blocks disposal")
fixture.item:getModData().EmberRoutesHaulFixture = fixture.token
check(Haul.cleanup(), "restored identity allows explicit cleanup")
npc.x = 0.5
failMove = true
Haul.execute(actor, "run")
tick(20)
check(Haul.batch.state == "FAILED" and #Haul.batch.records == 1, "native path failure stops before any item transfer")
for _, f in ipairs(Haul.fixtures) do check(f.item:getContainer() == source.container, "path failure retains source contents") end
Haul.execute(actor, "cleanup")
npc.x = 3.5
Haul.execute(actor, "run")
tick(2)
local lastFixture = Haul.fixtures[1]
source.data.EmberRoutesProbeContainer.role = nil
ctx.tick(15) -- native completion attempted before Haul.tick can observe the revocation
check(lastFixture.item:getContainer() == source.container, "late revocation blocks mutation at native perform boundary")
check(npc.actions:isEmpty(), "late revocation closes native queue")
Haul.tick()
check(Haul.batch.state == "CANCELLED", "late-revoked job never reports success")
source.data.EmberRoutesProbeContainer.role = "source"
Haul.execute(actor, "cleanup")
local originalFind, originalCommand = AdjacentFreeTileFinder.Find, EmberRoutesProbeJava.command
local rejectedTile, alternateTile = square(source.square.x - 1, 0, 0), square(source.square.x + 1, 0, 0)
rejectedTile.solidTrans = true
local findCalls = 0
AdjacentFreeTileFinder.Find = function(_, _, excluded)
    findCalls = findCalls + 1
    for _, candidate in ipairs({ rejectedTile, alternateTile }) do
        local skip = false
        for _, rejected in ipairs(excluded or {}) do if rejected == candidate then skip = true end end
        if not skip then return candidate end
    end
end
npc.x, npc.y, npc.z = 0.5, 0.5, 0
Haul.execute(actor, "run")
tick(1)
check(moving and target[1] == alternateTile.x + 0.5 and findCalls == 2,
    "native finder solidtrans candidate excluded; alternate loaded floor requested")
Haul.execute(actor, "cancel")
Haul.execute(actor, "cleanup")
alternateTile.noFloor, findCalls = true, 0
Haul.execute(actor, "run")
tick(1)
check(Haul.batch.state == "FAILED" and Haul.batch.reason == "NO_WALKABLE_ADJACENT_TILE" and findCalls <= 8,
    "all unsuitable candidates fail with bounded search and a specific reason")
for _, fixture in ipairs(Haul.fixtures) do check(fixture.item:getContainer() == source.container, "failed approach preserves original source instance") end
Haul.execute(actor, "cleanup")
alternateTile.noFloor, rejectedTile.solidTrans = false, false
EmberRoutesProbeJava.command = function() return "INVALID_TILE loaded walkable floor required" end
Haul.execute(actor, "run")
check(pcall(Haul.batch.tick, Haul.batch, getTimestampMs()), "native movement refusal does not throw out of batch start")
check(Haul.batch.state == "FAILED" and Haul.batch.reason:find("^INVALID_TILE") and #Haul.batch.records == 1,
    "native movement refusal remains a failed step rather than generic ERROR cancellation")
Haul.execute(actor, "cleanup")
AdjacentFreeTileFinder.Find, EmberRoutesProbeJava.command = originalFind, originalCommand
npc.getBodyDamage = nativeBodyDamage
print = realPrint
print("PASS " .. assertions .. " Lua world haul assertions; native fakes NOT runtime evidence")
return { ctx = ctx, Haul = Haul, npc = npc, actor = actor, tick = tick }
