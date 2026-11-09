package.path = "Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;Contents/mods/EmberRoutesProbe/42/media/lua/client/?.lua;" .. package.path

local Manifest = require 'EmberRoutesProbe/Hauling/HaulManifest'

-- Test 1: HaulManifest validates multi-source and multi-destination LOGISTICS jobs
local testJob = {
    id = "job-101",
    npcId = "npc-1",
    format = 3,
    producer = "LOGISTICS",
    settlementId = "settlement-1",
    source = "S1",
    destination = "D1",
    items = { 101, 102 },
    plannedCount = 2,
    routeRevision = 0,
    attemptSequence = 0,
    sourceMode = "intake",
    delivered = 0
}
local sources = { ["101"] = "S1", ["102"] = "S2" }
local destinations = { ["101"] = "D1", ["102"] = "D2" }
testJob.manifest = Manifest.create(testJob, nil, sources, destinations)

assert(#testJob.manifest == 2, "Manifest should have 2 lines")
assert(testJob.manifest[1].sourceId == "S1", "Line 1 source should be S1")
assert(testJob.manifest[1].destinationId == "D1", "Line 1 destination should be D1")
assert(testJob.manifest[2].sourceId == "S2", "Line 2 source should be S2")
assert(testJob.manifest[2].destinationId == "D2", "Line 2 destination should be D2")
assert(Manifest.valid(testJob), "LOGISTICS job with multi-source and multi-destination must be valid")

-- Test 2: LogisticsPlanner 一对多 (One-to-Many)
local function mockItem(id, fullType, weight, c)
    local it = { id = id, fullType = fullType, weight = weight, container = c }
    function it:getID() return self.id end
    function it:getFullType() return self.fullType end
    function it:getUnequippedWeight() return self.weight end
    function it:getContainer() return self.container end
    function it:getCategory() return "Item" end
    function it:isFood() return false end
    function it:getDisplayCategory() return "Item" end
    return it
end

local function mockContainer(id, role, filterTypes)
    local items = {}
    local itemList = {
        size = function() return #items end,
        get = function(_, idx) return items[idx + 1] end,
        contains = function(_, item)
            for _, v in ipairs(items) do if v == item then return true end end
            return false
        end
    }
    local c = { id = id, role = role, items = items }
    function c:getItems() return itemList end
    function c:getFreeCapacity() return 50 end
    function c:hasRoomFor() return true end
    return c
end

local containers = {}
local cInput = mockContainer("INPUT_1", "INPUT")
local cFood = mockContainer("D_Food", "STORAGE")
local cAmmo = mockContainer("D_Ammo", "STORAGE")

containers["INPUT_1"] = cInput
containers["D_Food"] = cFood
containers["D_Ammo"] = cAmmo

-- Add items to INPUT_1
local item1 = mockItem(1, "Base.CannedCorn", 1.0, cInput)
local item2 = mockItem(2, "Base.Bullets9mm", 0.5, cInput)
cInput.items[1] = item1
cInput.items[2] = item2

local endpoints = {}
for id, c in pairs(containers) do
    endpoints[id] = {
        id = id,
        container = c,
        object = { getSquare = function() return { getX = function() return 0 end, getY = function() return 0 end, getZ = function() return 0 end } end }
    }
end

package.loaded['EmberRoutesProbe/Warehouse/ContainerRegistry'] = {
    resolve = function(id) return endpoints[id] end,
    revalidate = function(endpoint) return endpoint end,
    logistics = function(endpoint) return containers[endpoint.id].role end,
    describe = function(id) return { x = 0, y = 0, z = 0 } end,
    filter = function(obj, cont)
        for id, c in pairs(containers) do
            if c == cont then
                if id == "D_Food" then return { format = 1, enabled = true, private = false, priority = 3, types = { ["Base.CannedCorn"] = true }, groups = {} } end
                if id == "D_Ammo" then return { format = 1, enabled = true, private = false, priority = 3, types = { ["Base.Bullets9mm"] = true }, groups = {} } end
                return { format = 1, enabled = true, private = false, priority = 3, types = {}, groups = {} }
            end
        end
        return nil
    end,
    accepts = function(endpoint, item)
        if endpoint.id == "D_Food" and item:getFullType() == "Base.CannedCorn" then return true end
        if endpoint.id == "D_Ammo" and item:getFullType() == "Base.Bullets9mm" then return true end
        return false
    end
}

package.loaded['EmberRoutesProbe/Settlement/SettlementMembership'] = {
    query = function() return { "D_Food", "D_Ammo", "INPUT_1" } end
}

package.loaded['EmberRoutesProbe/Work/LaborStore'] = {
    owner = function() return nil end,
    availableCapacity = function(id, free) return free end
}

package.loaded['EmberRoutesProbe/Work/LaborProducers'] = {
    eligible = function() return true end,
    freeCarry = function() return 20.0 end
}

local Planner = require 'EmberRoutesProbe/Logistics/LogisticsPlanner'

local npc = {
    getInventory = function()
        return {
            hasRoomFor = function() return true end,
            getItems = function() return { size = function() return 0 end } end
        }
    end
}

local entry = { id = "settlement-1", revision = 1 }
local settings = { intake = true, tidy = false }
local plan = Planner.new(entry, settings, npc)

local batch, status
for _ = 1, 200 do
    batch, status = plan:step(10)
    if batch or status ~= "WAIT" then break end
end

assert(batch ~= nil, "Planner must return a batch for input items")
assert(#batch.items == 2, "Batch must contain both items (One-to-Many)")
assert(batch.itemDestinations["1"] == "D_Food", "Item 1 destination must be D_Food")
assert(batch.itemDestinations["2"] == "D_Ammo", "Item 2 destination must be D_Ammo")

-- Test 3: LogisticsPlanner 多对一 (Many-to-One)
local cInputA = mockContainer("INPUT_A", "INPUT")
local cInputB = mockContainer("INPUT_B", "INPUT")
containers["INPUT_A"] = cInputA
containers["INPUT_B"] = cInputB
endpoints["INPUT_A"] = { id = "INPUT_A", container = cInputA, object = endpoints["INPUT_1"].object }
endpoints["INPUT_B"] = { id = "INPUT_B", container = cInputB, object = endpoints["INPUT_1"].object }

local itemA = mockItem(10, "Base.CannedCorn", 1.0, cInputA)
local itemB = mockItem(11, "Base.CannedCorn", 1.0, cInputB)
cInputA.items[1] = itemA
cInputB.items[1] = itemB

package.loaded['EmberRoutesProbe/Settlement/SettlementMembership'].query = function()
    return { "D_Food", "INPUT_A", "INPUT_B" }
end

local planMultiSource = Planner.new(entry, settings, npc)
local batchMulti
for _ = 1, 300 do
    batchMulti, status = planMultiSource:step(10)
    if batchMulti or status ~= "WAIT" then break end
end

assert(batchMulti ~= nil, "Planner must return a multi-source batch")
assert(#batchMulti.items == 2, "Batch must aggregate items across both sources (Many-to-One)")
assert(batchMulti.itemSources["10"] == "INPUT_A", "Item 10 source must be INPUT_A")
assert(batchMulti.itemSources["11"] == "INPUT_B", "Item 11 source must be INPUT_B")
assert(batchMulti.destination == "D_Food", "Target destination must be D_Food")

print("PASS: haul-multi-target-test - all One-to-Many and Many-to-One planning and manifest assertions passed")
