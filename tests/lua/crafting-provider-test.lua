package.path = "Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;Contents/mods/EmberRoutesProbe/42/media/lua/client/?.lua;" .. package.path

-- Mock dependencies
package.loaded['EmberRoutesProbe/ContainerRegistry'] = {
    data = function() return { craftSurfaces = {} } end,
    id = function() return 'test_craft_id' end
}
package.loaded['EmberRoutesProbe/TaskRuntime'] = {
    current = function()
        return { status = function(self, npcId, jobId) return false end }
    end
}
package.loaded['EmberRoutesProbe/Boot'] = { idleStudy = function() end }
package.loaded['EmberRoutesProbe/LaborSignals'] = { changed = function() end }
package.loaded['EmberRoutesProbe/PlanningWake'] = {
    capture = function() return 1 end,
    changed = function() return false end
}
package.loaded['EmberRoutesProbe/CookingOrders'] = {
    parentAllows = function(o) return true end
}

local executedAction = nil
package.loaded['EmberRoutesProbe/Production'] = {
    execute = function(actor, action, object, npcId, params)
        executedAction = { actor = actor, action = action, npcId = npcId, params = params }
        return 'QUEUED'
    end
}

local CraftingProvider = require 'EmberRoutesProbe/CraftingProvider'

-- 1. Contract definition
assert(CraftingProvider.category == 'crafting', "category must be crafting")
assert(CraftingProvider.defaultPriority == 3, "defaultPriority must be 3")
assert(type(CraftingProvider.discover) == 'function', "discover must be function")
assert(type(CraftingProvider.claim) == 'function', "claim must be function")
assert(type(CraftingProvider.reconcile) == 'function', "reconcile must be function")
assert(type(CraftingProvider.idle) == 'function', "idle must be function")
assert(type(CraftingProvider.hasWork) == 'function', "hasWork must be function")
assert(type(CraftingProvider.step) == 'function', "step must be function")

-- 2. Pending and Cancel lifecycle
assert(CraftingProvider.pending('npc_test') == nil, "initially not pending")
CraftingProvider.evaluations():put('npc_test', { orderId = 'order_1', order = { id = 'order_1' }, request = { cancel = function() end } })
assert(CraftingProvider.pending('npc_test') ~= nil, "pending returns evaluation")
assert(CraftingProvider.evaluations():size() == 1, "size is 1")

CraftingProvider.cancel('npc_test')
assert(CraftingProvider.pending('npc_test') == nil, "cancel clears pending")
assert(CraftingProvider.evaluations():size() == 0, "size is 0 after cancel")

-- 3. Cleanup order
local readyWorkers = { 'npc_a', 'npc_b' }
CraftingProvider.evaluations():put('npc_a', { orderId = 'order_target', request = { cancel = function() end } })
CraftingProvider.evaluations():put('npc_b', { orderId = 'order_other', request = { cancel = function() end } })
CraftingProvider.cleanupOrder('order_target', readyWorkers)
assert(CraftingProvider.pending('npc_a') == nil, "order_target was cleaned up")
assert(CraftingProvider.pending('npc_b') ~= nil, "order_other remains")
CraftingProvider.reset()
assert(CraftingProvider.evaluations():size() == 0, "reset clears all")

-- 4. Claim execution
local mockOrder = {
    id = 'order_100',
    recipeId = 'Base.MakeAxe',
    quantity = 1,
    state = 'WAITING',
    revision = 1
}
local claimEnv = {
    actor = {},
    entry = { id = 'settlement_1' },
    now = 1000,
    cool = function() end,
    signal = function() end
}
local claimRes = CraftingProvider.claim({ order = mockOrder, object = nil }, 'npc_crafter', 'job_craft_1', claimEnv)
assert(claimRes == 'QUEUED', "claim returns QUEUED")
assert(mockOrder.jobId == 'job_craft_1', "jobId recorded")
assert(mockOrder.npcId == 'npc_crafter', "npcId recorded")
assert(mockOrder.state == 'CLAIMING', "state transitioned to CLAIMING")
assert(executedAction ~= nil and executedAction.params.recipeId == 'Base.MakeAxe', "Production.execute called with params")

-- 5. Scan status
local complete, watch = CraftingProvider.scanStatus('npc_scan', { 'order_1' })
assert(complete == true, "empty scan status is complete")

print("PASS: crafting-provider-test")
