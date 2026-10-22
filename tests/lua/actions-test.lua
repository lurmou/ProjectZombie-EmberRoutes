-- Test only our orchestration/ownership boundaries, with deliberately small native fakes.
-- These fakes are NOT evidence for game animation, Eat/DrinkFluid or transfer compatibility.
package.path = "Contents/mods/EmberRoutesProbe/42/media/lua/client/?.lua;" .. package.path
package.path = "Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;" .. package.path
DebugLog = { log = function(message) print(message) end }
local assertions, clock, active = 0, 0, true
local function check(value, message) assertions = assertions + 1 assert(value, message) end
local logs = {}
local realPrint = print
print = function(message) logs[#logs + 1] = message end
function getTimestampMs() return clock end
function getText(key) return key end
CharacterStat = { HUNGER = "hunger", THIRST = "thirst" }
local function list(t)
    function t:contains(value) for _, x in ipairs(self) do if x == value then return true end end return false end
    function t:isEmpty() return #self == 0 end
    function t:size() return #self end
    function t:get(i) return self[i + 1] end
    return t
end
local nextID = 0
local newContainer
local function item(kind)
    nextID = nextID + 1
    local o = { id = nextID, kind = kind, condition = 3, mod = {}, hunger = -0.3 }
    function o:getContainer() return self.container end
    function o:getUnequippedWeight() return self.weight or 1 end
    function o:getID() return self.id end
    function o:getName() return self.kind end
    function o:getCondition() return self.condition end
    function o:getConditionMax() return 3 end
    function o:setCondition(value) self.condition = value end
    function o:getModData() return self.mod end
    function o:getHungChange() return self.hunger end
    function o:getBaseHunger() return -0.3 end
    function o:getInventory() return self.bag end
    function o:getFluidContainer() return self.fluid end
    if kind == "Base.Bag_Schoolbag" then o.bag = newContainer() end
    if kind == "Base.WaterBottle" then
        o.fluid = { amount = 1 }
        function o.fluid:getAmount() return self.amount end
    end
    return o
end
newContainer = function()
    local c = { items = list({}) }
    function c:getItems() return self.items end
    function c:hasRoomFor() return not self.full end
    function c:getFreeCapacity() return self.full and 0 or 1000-#self.items end
    function c:AddItem(kind)
        local value = item(kind)
        self.items[#self.items + 1] = value
        value.container = self
        return value
    end
    function c:Remove(value)
        for i, x in ipairs(self.items) do
            if x == value then table.remove(self.items, i) value.container = nil return end
        end
    end
    return c
end
local npc = { root = newContainer(), actions = list({}), stats = {} }
function npc:getInventory() return self.root end
function npc:getCharacterActions() return self.actions end
function npc:getStats() return self.stats end
function npc.stats:set(key, value) self[key] = value end
function npc.stats:get(key) return self[key] end
function npc:getBodyDamage() return { getOverallBodyHealth = function() return 100 end } end
local actor = { speech = {} }
function actor:Say(message) self.speech[#self.speech + 1] = message end
function actor:isDead() return false end
local userItem = npc.root:AddItem("UNRELATED_ITEM")
local Probe = { ready = true, build = { version = "test", prefix = "TEST" }, hasJava = function() return true end }
package.loaded["EmberRoutesProbe/Boot"] = Probe
EmberRoutesProbeJava = {
    actionCarrier = function() if active then return npc end end,
    carrierActive = function(expected) return active and expected == npc end,
}
local queued
ISTimedActionQueue = { queues = {} }
function ISTimedActionQueue.add(action)
    queued = action
    npc.actions[1] = action
    action.action = action
    action.started = true
    if action.startActionAnim then action:startActionAnim() end
end
function ISTimedActionQueue.hasAction(action) return queued == action end
function ISTimedActionQueue.clear()
    if queued then queued:stop() end
    queued = nil
    npc.actions[1] = nil
end
local function native(kind, character, value, source, dest)
    local a = { kind = kind, character = character, item = value, source = source, dest = dest, delta = 0 }
    function a:isStarted() return self.started end
    function a:getJobDelta() return self.delta end
    function a:isValid() return true end
    function a:startActionAnim()
        if (self.source and self.source.world) or (self.dest and self.dest.world) then self.selectedContainer = self.dest end
    end
    function a:update() assert(not self.selectedContainer, "NPC attempted to select real player loot UI") end
    local function effects(self, fraction)
        if self.kind == "eat" then
            local used = 0.3 * 0.25 * fraction
            self.item.hunger = self.item.hunger + used
            npc.stats.hunger = npc.stats.hunger - used
        elseif self.kind == "drink" then
            local used = self.item.fluid.amount * 0.25 * fraction
            self.item.fluid.amount = self.item.fluid.amount - used
            npc.stats.thirst = npc.stats.thirst - used * 0.5
        elseif fraction == 1 then
            self.source:Remove(self.item)
            self.dest.items[#self.dest.items + 1] = self.item
            self.item.container = self.dest
        end
    end
    function a:stop()
        if self.kind ~= "transfer" then effects(self, self.delta) end
        queued = nil
        npc.actions[1] = nil
    end
    function a:perform()
        assert(not self.selectedContainer, "NPC performed using real player loot UI")
        effects(self, 1)
        queued = nil
        npc.actions[1] = nil
    end
    return a
end
ISEatFoodAction = { new = function(_, character, value) return native("eat", character, value) end }
ISDrinkFluidAction = { new = function(_, character, value) return native("drink", character, value) end }
ISInventoryTransferAction = { new = function(_, character, value, source, dest) return native("transfer", character, value, source, dest) end }
for _, name in ipairs({ "ISTimedActionQueue", "ISEatFoodAction", "ISDrinkFluidAction", "ISInventoryTransferAction" }) do
    package.loaded["TimedActions/" .. name] = true
end
local Actions = require "EmberRoutesProbe/Actions"
local function tick(count)
    for _ = 1, count do
        clock = clock + 100
        if queued then
            if queued.update then queued:update() end
            queued.delta = math.min(1, queued.delta + 0.1)
            if queued.delta >= 1 then queued:perform() end
        end
        Actions.tick()
    end
end
Actions.execute(actor, "suite")
local firstFixtures = Actions.fixtures
Actions.execute(actor, "suite")
check(Actions.fixtures == firstFixtures and actor.speech[#actor.speech]:find("BUSY"), "duplicate request cannot allocate more fixtures")
tick(300)
check(Actions.batch.state == "PASSED" and #Actions.batch.records == 10, "all ten orchestration paths run")
check(Actions.fixtures.cargo:getContainer() == npc.root, "round trip ends with same object in root")
check(npc.root:getItems():contains(userItem), "player/untracked assets untouched")
local count = #Actions.batch.records
tick(50)
check(#Actions.batch.records == count and not queued, "idle does not repeat work")
Actions.execute(actor, "suite")
check(Actions.fixtures ~= firstFixtures, "next batch disposes old fixtures and owns fresh set")
tick(2)
Actions.execute(actor, "cancel")
check(Actions.batch.state == "CANCELLED" and not queued, "explicit cancellation stops native queue")
Actions.execute(actor, "eat")
tick(2)
active = false
Actions.tick()
check(Actions.batch.state == "CANCELLED" and not queued, "lifecycle interruption stops queue")
check(Actions.fixtures == nil, "lifecycle cleanup releases fixture references")
check(npc.root:getItems():contains(userItem), "cleanup retains unrelated root item")
active = true
Actions.execute(actor, "prepare")
local f = Actions.fixtures
local foreign = f.bag:AddItem("USER_ASSET")
Actions.execute(actor, "cleanup")
check(Actions.fixtures == f and foreign:getContainer() == f.bag, "unknown bag contents block deletion")
f.bag:Remove(foreign)
Actions.execute(actor, "cleanup")
check(Actions.fixtures == nil and #npc.root:getItems() == 1, "explicit cleanup removes exactly fixture items")
Actions.execute(actor, "prepare")
f = Actions.fixtures
local unexpected = newContainer()
npc.root:Remove(f.cargo)
f.cargo.container = unexpected
unexpected.items[1] = f.cargo
Actions.execute(actor, "cleanup")
check(Actions.fixtures == f and unexpected.items[1] == f.cargo, "unexpected ownership blocks cleanup")
active = false
local oldLogs = #logs
tick(100)
check(#logs == oldLogs, "blocked cleanup cannot scan and log every tick")
active = true
local beforeHealthCheck = npc.getBodyDamage
function npc:getBodyDamage() return { getOverallBodyHealth = function() return 75 end } end
local hungerBefore = npc.stats.hunger
Actions.execute(actor, "suite")
check(actor.speech[#actor.speech] == "IGUI_EmberRoutesProbe_ActionInjured", "injured action start reports reason immediately")
check(Actions.fixtures == f and npc.stats.hunger == hungerBefore and not Actions.isBusy(),
    "injured start does not replace fixtures, reset needs or create an action")
npc.getBodyDamage = beforeHealthCheck
active = false
print = realPrint
print("PASS " .. assertions .. " Lua action orchestration assertions; native fakes NOT runtime evidence")
return { npc = npc, actor = actor, Probe = Probe, Actions = Actions, tick = tick, logs = logs,
    newContainer = newContainer, list = list, setActive = function(value) active = value end }
