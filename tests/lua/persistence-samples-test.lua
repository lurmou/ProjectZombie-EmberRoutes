package.path = "Contents/mods/EmberRoutesProbe/42/media/lua/client/?.lua;Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;" .. package.path
DebugLog = { log = function() end }
function getText(key) return key end
local count, nextId = 0, 1
local logs = {}
DebugLog.log = function(message) logs[#logs + 1] = message end
local function check(ok, message) count = count + 1 assert(ok, message) end
local function list()
    local out = {}
    function out:size() return #self end
    function out:get(i) return self[i + 1] end
    function out:getItemByIndex(i) return self[i + 1] end
    return out
end
local container
container = function()
    local c = { items = list() }
    function c:getItems() return self.items end
    function c:AddItem(kind)
        nextId = nextId + 1
        local item = { id = nextId, data = {}, condition = 3, name = kind, container = self }
        function item:getID() return self.id end
        function item:getModData() return self.data end
        function item:getCondition() return self.condition end
        function item:getConditionMax() return 3 end
        function item:setCondition(value) self.condition = value end
        function item:setName(value) self.name = value end
        function item:getDisplayName() return self.name end
        function item:setCustomName(value) self.customName = value end
        function item:getName()
            if self.fluid then return "fluid-generated UI name" end
            if self.condition < 3 then return "worn " .. self.name end
            return self.name
        end
        function item:getContainer() return self.container end
        if kind == "Base.Bag_Schoolbag" then
            item.bag = container()
            function item:getInventory() return self.bag end
        elseif kind == "Base.WaterBottle" then
            item.fluid = { amount = 1 }
            function item.fluid:getAmount() return self.amount end
            function item:getFluidContainer() return self.fluid end
        end
        self.items[#self.items + 1] = item
        return item
    end
    function c:Remove(item)
        for i, value in ipairs(self.items) do
            if value == item then table.remove(self.items, i) item.container = nil return end
        end
    end
    return c
end
local npc = { data = {}, root = container(), worn = list(), attached = list() }
function npc:getInventory() return self.root end
function npc:getModData() return self.data end
function npc:getPrimaryHandItem() return self.primary end
function npc:setPrimaryHandItem(item) self.primary = item end
function npc:getSecondaryHandItem() return self.secondary end
function npc:setSecondaryHandItem(item) self.secondary = item end
function npc:getWornItems() return self.worn end
function npc:getAttachedItems() return self.attached end
npc.damage = { health = 100 }
function npc.damage:getOverallBodyHealth() return self.health end
function npc.damage:RestoreToFullHealth() self.health = 100 end
function npc:getBodyDamage() return self.damage end
local Samples = require "EmberRoutesProbe/PersistenceSamples"
check(Samples.check(npc, "npc-1") == "SAMPLE_ABSENT_OR_STALE", "missing sample is reported")
local unrelated = npc.root:AddItem("USER_PROPERTY")
check(Samples.prepare(npc, "npc-1") == "SAMPLE_PREPARED", "create durable samples")
local mark = npc.data.EmberRoutesPersistenceSample
check(mark.ready and npc.root.items:size() == 3 and npc.primary:getID() == mark.pieces.pencil, "root bag, hand pencil and unrelated item retained")
local bag = npc.root.items[2]
check(bag:getInventory():getItems():get(0):getID() == mark.pieces.water, "water is nested under tracked bag")
local lastId = nextId
check(Samples.prepare(npc, "npc-1") == "SAMPLE_EXISTS" and nextId == lastId, "repeat preparation cannot create extra samples")
check(Samples.check(npc, "npc-1") == "SAMPLE_PASSED", "verify IDs, names, conditions, fluid, token and hand identity")
check(bag.bag.items[1]:getName() ~= mark.names.water and npc.primary:getName() ~= mark.names.pencil,
    "fixture reproduces B42 fluid name override and condition prefix")
check(npc.primary.customName and bag.customName, "new renamed samples use vanilla custom-name flag")
check(Samples.check(npc, "replacement") == "SAMPLE_ABSENT_OR_STALE", "sample cannot follow replacement NPC")
local originalCondition = npc.primary.condition
npc.primary.condition = 1
check(Samples.check(npc, "npc-1") == "SAMPLE_FAILED", "state change fails verification")
check(logs[#logs]:find("pencil_condition expected="), "failed sample reports the exact mismatched field")
npc.primary.condition = originalCondition
local oldName = bag.bag.items[1].name
bag.bag.items[1].name = "unexpected raw name"
check(Samples.check(npc, "npc-1") == "SAMPLE_FAILED" and logs[#logs]:find("water_name expected="),
    "real water custom-name change still fails; UI normalization does not bypass identity checks")
bag.bag.items[1].name = oldName
local foreign = bag.bag:AddItem("FOREIGN_ITEM")
check(Samples.cleanup(npc, "npc-1") == "SAMPLE_CLEANUP_BLOCKED_FOREIGN_ITEM", "foreign contents prevent destructive cleanup")
check(foreign.container == bag.bag and mark.ready, "failed cleanup keeps all ownership")
bag.bag:Remove(foreign)
npc.worn[1] = bag
check(Samples.cleanup(npc, "npc-1") == "SAMPLE_CLEANUP_BLOCKED_EQUIPPED", "worn bag cannot leave dangling equipment pointer")
npc.worn[1] = nil
check(Samples.cleanup(npc, "npc-1") == "SAMPLE_CLEANED", "clean exact sample instances")
check(npc.root.items:size() == 1 and npc.root.items[1] == unrelated and npc.primary == nil, "foreign root asset survives and own hand reference cleared")
check(npc.data.EmberRoutesPersistenceSample == nil, "cleanup releases durable marker")
check(Samples.prepare(npc, "npc-2") == "SAMPLE_PREPARED", "new samples can be explicitly prepared after cleanup")
local markerBefore, itemCountBefore = npc.data.EmberRoutesPersistenceSample, npc.root.items:size()
npc.damage.health = 75
check(Samples.recover(npc, "npc-2") == "TEST_HEALTH_RESTORED" and npc.damage.health == 100,
    "explicit test preparation restores only the supplied NPC body")
check(npc.data.EmberRoutesPersistenceSample == markerBefore and npc.root.items:size() == itemCountBefore,
    "test recovery preserves sample marker and existing inventory instances")
print("PASS " .. count .. " persistence sample assertions; native serialization NOT simulated")
