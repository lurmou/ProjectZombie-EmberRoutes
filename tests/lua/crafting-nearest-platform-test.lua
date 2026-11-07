package.path = "Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;Contents/mods/EmberRoutesProbe/42/media/lua/client/?.lua;tests/lua/?.lua;" .. package.path

local checks = 0
local function check(cond, msg)
    checks = checks + 1
    assert(cond, msg or "assertion failed at check " .. checks)
end

-- =========================================================================
-- Part 1: Test Surfaces.findNearest
-- =========================================================================
local root = { craftSurfaces = {} }
package.loaded['EmberRoutesProbe/Warehouse/ContainerRegistry'] = {
    data = function() return root end,
    id = function() return 'gen_id_' .. checks end
}
package.loaded['EmberRoutesProbe/Settlement/SettlementLedger'] = {
    at = function() return {{ id = 'settlement_1' }} end,
    view = function() return { id = 'settlement_1' } end
}
package.loaded['EmberRoutesProbe/Settlement/SettlementGeometry'] = {
    inside = function() return true end
}

-- Mock PZ world / cell / squares
local cellObjects = {}
local mockCell = {
    getGridSquare = function(self, x, y, z)
        local key = x .. ':' .. y .. ':' .. z
        if not cellObjects[key] then
            local square = {
                getX = function() return x end,
                getY = function() return y end,
                getZ = function() return z end,
                getObjects = function(self) return self.objs end,
                objs = {
                    contains = function(self, o)
                        for _, obj in ipairs(self.list) do if obj == o then return true end end
                        return false
                    end,
                    size = function(self) return #self.list end,
                    get = function(self, i) return self.list[i + 1] end,
                    list = {}
                }
            }
            cellObjects[key] = square
        end
        return cellObjects[key]
    end
}
_G.getCell = function() return mockCell end

local function createMockBench(id, x, y, z, usingPlayer, excluded)
    local modData = { EmberRoutesCraftProbeBenchId = id, EmberRoutesExcluded = excluded or nil }
    local bench = {
        isGenericCraftingSurface = function() return true end,
        getModData = function() return modData end,
        getSquare = function() return mockCell:getGridSquare(x, y, z) end,
        getUsingPlayer = function() return usingPlayer end
    }
    local sq = mockCell:getGridSquare(x, y, z)
    sq.objs.list[#sq.objs.list + 1] = bench
    root.craftSurfaces[id] = { x = x, y = y, z = z }
    return bench
end

local Surfaces = require 'EmberRoutesProbe/Crafting/CraftSurfaces'
local entry = { id = 'settlement_1' }

-- 1.1 Empty surfaces in settlement
local noneObj, noneErr = Surfaces.findNearest(entry, { getX = function() return 0 end, getY = function() return 0 end, getZ = function() return 0 end })
check(noneObj == nil and noneErr == 'CRAFT_SURFACE_REQUIRED', 'findNearest returns CRAFT_SURFACE_REQUIRED when no surfaces registered')

-- 1.2 Add surfaces: benchFar at (100, 100, 0), benchNear at (10, 10, 0)
local benchFar = createMockBench('bench_far', 100, 100, 0)
local benchNear = createMockBench('bench_near', 10, 10, 0)

local mockNpc = {
    getX = function() return 0 end,
    getY = function() return 0 end,
    getZ = function() return 0 end
}

local nearestObj, nearestErr, nearestId = Surfaces.findNearest(entry, mockNpc)
check(nearestObj == benchNear and nearestErr == nil and nearestId == 'bench_near', 'findNearest picks bench_near over benchFar')

-- 1.3 When benchNear is occupied by another NPC, fallback to benchFar
local otherNpc = {}
benchNear.getUsingPlayer = function() return otherNpc end
local fallbackObj, fallbackErr, fallbackId = Surfaces.findNearest(entry, mockNpc)
check(fallbackObj == benchFar and fallbackErr == nil and fallbackId == 'bench_far', 'findNearest skips occupied bench and chooses next nearest')

-- 1.4 If occupied bench is used by current NPC, current NPC can use it
benchNear.getUsingPlayer = function() return mockNpc end
local reacquiredObj, reacquiredErr, reacquiredId = Surfaces.findNearest(entry, mockNpc)
check(reacquiredObj == benchNear and reacquiredErr == nil and reacquiredId == 'bench_near', 'findNearest allows bench if current user is the NPC')

-- 1.5 Excluded bench is skipped
benchNear.getUsingPlayer = function() return nil end
benchNear:getModData().EmberRoutesExcluded = true
local unexcludedObj, unexcludedErr, unexcludedId = Surfaces.findNearest(entry, mockNpc)
check(unexcludedObj == benchFar and unexcludedErr == nil and unexcludedId == 'bench_far', 'findNearest skips excluded bench')

-- 1.6 Unloaded squares report SURFACE_UNLOADED
local oldGrid = mockCell.getGridSquare
mockCell.getGridSquare = function() return nil end
local unloadedObj, unloadedErr = Surfaces.findNearest(entry, mockNpc)
check(unloadedObj == nil and unloadedErr == 'SURFACE_UNLOADED', 'findNearest reports SURFACE_UNLOADED when chunks not loaded')
mockCell.getGridSquare = oldGrid

-- =========================================================================
-- Part 2: Test PublicWork.create with surfaceId == nil for surface recipe
-- =========================================================================
local surfaceRecipe = {
    recipe = { getName = function() return 'table_recipe' end },
    id = 'recipe_table',
    name = 'Table Recipe',
    product = 'Base.WoodItem',
    yield = 1,
    surface = true
}
package.loaded['EmberRoutesProbe/Crafting/ProductionRecipe'] = {
    read = function(id) return surfaceRecipe end,
    inspect = function(actor, npc, object, id, req, near)
        if not object then return nil, 'CRAFT_SURFACE_REQUIRED' end
        return surfaceRecipe
    end
}
package.loaded['EmberRoutesProbe/Kernel/Boot'] = { ready = true, runtimeReady = true, publicDispatch = true, hasJava = function() return true end }
package.loaded['EmberRoutesProbe/Work/LaborSignals'] = { changed = function() end }
package.loaded['EmberRoutesProbe/Runtime/PlanningWake'] = {
    capture = function() return 1 end,
    changed = function() return false end
}
package.loaded['EmberRoutesProbe/Cooking/CookingOrders'] = { describe = function() return nil end, parentAllows = function() return true end }
package.loaded['EmberRoutesProbe/Work/Work'] = { busy = function() return false end, hasCargo = function() return false end, record = function() return nil end }
package.loaded['EmberRoutesProbe/Runtime/TaskRuntime'] = { current = function() return { accepting = function() return true end, status = function() return nil end } end }
package.loaded['EmberRoutesProbe/Settlement/Companion'] = { exportState = function() return { mode = 'HOLD' } end }
package.loaded['EmberRoutesProbe/Work/BusinessJobs'] = { records = function() return {} end, crafts = function() return {} end, flush = function() end }
package.loaded['EmberRoutesProbe/Logistics/LogisticsService'] = { publicOffer = function() return nil end, preparePublic = function() return true end }
package.loaded['EmberRoutesProbe/Runtime/Driver'] = { bindId = function(_, id) return { handle = mockNpc } end }
package.loaded['EmberRoutesProbe/Crafting/ProductionChain'] = { new = function() return { step = function() return { nodes = {} } end, cancel = function() end } end }
package.loaded['EmberRoutesProbe/Crafting/Production'] = { execute = function() return 'QUEUED' end }
package.loaded['EmberRoutesProbe/Kernel/Log'] = { write = function() end }
package.loaded['EmberRoutesProbe/Work/LaborStore'] = { custodyForNpc = function() return {} end }
package.loaded['EmberRoutesProbe/Settlement/SettlementMembership'] = { query = function() return {'crate'} end }
package.loaded['EmberRoutesProbe/Field/ToolReturnService'] = {
    canInterrupt = function() return false end,
    reconcile = function() end,
    returnResult = function() end,
    liveTask = function() end,
    forgetResult = function() end,
    startFor = function() end
}

local actor = {
    getUsername = function() return 'tester' end,
    isRecipeKnown = function() return true end
}

local Public = require 'EmberRoutesProbe/Work/PublicWork'

-- 2.1 Create order without surfaceId (surfaceId == nil)
local status, orderId = Public.create(actor, 'settlement_1', 'recipe_table', 5, nil, Public.requestId())
check(status == 'ORDER_CREATED', 'Public.create accepts surfaceId == nil for surface recipe')
local savedOrder = Public.order(orderId)
check(savedOrder ~= nil and savedOrder.surfaceId == nil, 'order has surfaceId == nil')
check(savedOrder.quantity == 5, 'order quantity is 5')

-- 2.2 Create order with specific valid surfaceId
benchNear:getModData().EmberRoutesExcluded = nil
local status2, orderId2 = Public.create(actor, 'settlement_1', 'recipe_table', 3, 'bench_near', Public.requestId())
check(status2 == 'ORDER_CREATED', 'Public.create accepts valid surfaceId')
local savedOrder2 = Public.order(orderId2)
check(savedOrder2 ~= nil and savedOrder2.surfaceId == 'bench_near', 'order has surfaceId == bench_near')

-- 2.3 Save stock rule without surfaceId (surfaceId == nil)
local ruleStatus = Public.saveRule(actor, 'settlement_1', 'recipe_table', 10, 5, nil)
check(ruleStatus == 'RULE_SAVED', 'Public.saveRule accepts surfaceId == nil for surface recipe')
local savedRule = Public.rule('settlement_1', 'Base.WoodItem')
check(savedRule ~= nil and savedRule.surfaceId == nil, 'saved rule has surfaceId == nil')

-- =========================================================================
-- Part 3: Test CraftingProvider.discover dynamic nearest platform resolution
-- =========================================================================
local CraftingProvider = require 'EmberRoutesProbe/Crafting/CraftingProvider'
CraftingProvider.reset()

local env = {
    actor = actor,
    npc = mockNpc,
    npcId = 'npc_tester',
    entry = entry,
    now = 1000,
    sequence = 1,
    priorities = { revision = 1 },
    priority = 3,
    orderIds = { orderId },
    orders = { [orderId] = savedOrder },
    candidates = {},
    cool = function(o, id, watch, why) print("cool called why: " .. tostring(why)) end,
    signal = function(o, why) print("signal called why: " .. tostring(why)) end,
    directory = {
        upsert = function(self, key, rev, cat, scope)
            return { key = key, revision = rev }
        end
    }
}

-- Discover should find nearest bench (benchNear at 10,10 vs benchFar at 100,100)
CraftingProvider.discover(env)
local eval = CraftingProvider.pending('npc_tester')
check(eval ~= nil, 'evaluation queued for unanchored craft order')
check(eval.object == benchNear, 'evaluation automatically chose bench_near as nearest platform')

print("PASS: crafting-nearest-platform-test (" .. checks .. " assertions)")
