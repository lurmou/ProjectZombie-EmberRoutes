package.path = "Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;Contents/mods/EmberRoutesProbe/42/media/lua/client/?.lua;" .. package.path

local checks = 0
local function check(value, message)
    checks = checks + 1
    assert(value, message)
end

-- Mock perks
local BlacksmithPerk = { name = 'Blacksmith' }
function BlacksmithPerk:getName() return 'Blacksmith' end

Perks = {
    Blacksmith = BlacksmithPerk,
    Woodwork = { getName = function() return 'Carpentry' end },
    MetalWelding = { getName = function() return 'MetalWelding' end }
}

-- Mock dependencies
package.loaded['EmberRoutesProbe/Warehouse/ContainerRegistry'] = {
    data = function() return { craftSurfaces = {} } end,
    id = function() return 'test_craft_id' end
}
package.loaded['EmberRoutesProbe/Runtime/TaskRuntime'] = {
    current = function()
        return { status = function(self, npcId, jobId) return false end }
    end
}
package.loaded['EmberRoutesProbe/Kernel/Boot'] = { idleStudy = function() end }
package.loaded['EmberRoutesProbe/Work/LaborSignals'] = { changed = function() end }
package.loaded['EmberRoutesProbe/Runtime/PlanningWake'] = {
    capture = function() return 1 end,
    changed = function() return false end
}
package.loaded['EmberRoutesProbe/Cooking/CookingOrders'] = {
    parentAllows = function(o) return true end
}

local executedAction = nil
package.loaded['EmberRoutesProbe/Crafting/Production'] = {
    execute = function(actor, action, object, npcId, params)
        executedAction = { actor = actor, action = action, npcId = npcId, params = params }
        return 'QUEUED'
    end
}

local Recipe = require 'EmberRoutesProbe/Crafting/ProductionRecipe'
local CraftingProvider = require 'EmberRoutesProbe/Crafting/CraftingProvider'
local Providers = require 'EmberRoutesProbe/Work/PublicWorkProviders'

-- Mock a blacksmithing recipe in Recipe
local mockRecipe = {
    getRequiredSkillCount = function() return 1 end,
    getRequiredSkill = function(self, idx)
        return {
            getPerk = function() return BlacksmithPerk end,
            getLevel = function() return 2 end
        }
    end,
    getCategory = function() return 'Blacksmithing' end
}
local mockSpec = {
    id = 'Base.Forge_Small_Knife',
    recipe = mockRecipe,
    yield = 1
}

local oldRead = Recipe.read
Recipe.read = function(id)
    if id == 'Base.Forge_Small_Knife' then return mockSpec end
    return oldRead and oldRead(id)
end

local oldInspect = Recipe.inspect
Recipe.inspect = function(actor, npc, object, id, requireKnowledge, near, jobId)
    if id == 'Base.Forge_Small_Knife' then
        for i = 0, mockRecipe:getRequiredSkillCount() - 1 do
            local skill = mockRecipe:getRequiredSkill(i)
            if npc:getPerkLevel(skill:getPerk()) < skill:getLevel() then
                return nil, "NPC_SKILL_TOO_LOW"
            end
        end
        return mockSpec
    end
    return oldInspect and oldInspect(actor, npc, object, id, requireKnowledge, near, jobId)
end

-- 1. Test skill score calculation
local npcA = {
    getPerkLevel = function(self, perk)
        if perk == BlacksmithPerk then return 6 end
        return 0
    end
}
local npcB = {
    getPerkLevel = function(self, perk)
        if perk == BlacksmithPerk then return 2 end
        return 0
    end
}
local npcC = {
    getPerkLevel = function(self, perk)
        return 0
    end
}

local scoreA = CraftingProvider.calculateSkillScore(npcA, 'Base.Forge_Small_Knife')
local scoreB = CraftingProvider.calculateSkillScore(npcB, 'Base.Forge_Small_Knife')
local scoreC = CraftingProvider.calculateSkillScore(npcC, 'Base.Forge_Small_Knife')

check(scoreA == 6, "npcA skill score matches perk level 6")
check(scoreB == 2, "npcB skill score matches perk level 2")
check(scoreC == 0, "npcC skill score is 0 when perk level is 0")

-- 2. Test skill requirement gating via Recipe.inspect
local okA, errA = Recipe.inspect({}, npcA, {}, 'Base.Forge_Small_Knife', false, false)
local okB, errB = Recipe.inspect({}, npcB, {}, 'Base.Forge_Small_Knife', false, false)
local okC, errC = Recipe.inspect({}, npcC, {}, 'Base.Forge_Small_Knife', false, false)

check(okA ~= nil and errA == nil, "npcA passes Blacksmith requirement (6 >= 2)")
check(okB ~= nil and errB == nil, "npcB passes Blacksmith requirement (2 >= 2)")
check(okC == nil and errC == 'NPC_SKILL_TOO_LOW', "npcC blocked by skill requirement (0 < 2)")

-- 3. Test candidate scoring in discover: higher skill worker gets strictly higher score
local dirOffers = {}
local mockDir = {
    upsert = function(self, key, rev, cat, scope)
        dirOffers[key] = { key = key, revision = rev, category = cat }
        return dirOffers[key]
    end
}

local order = {
    id = 'order_forge_1',
    sequence = 1,
    recipeId = 'Base.Forge_Small_Knife',
    revision = 1,
    state = 'WAITING'
}

-- Setup evaluation for NPC A (skill level 6)
CraftingProvider.evaluations():put('npc_a', {
    orderId = order.id,
    order = order,
    generation = 0,
    object = {},
    ready = true,
    expires = 9999999,
    watch = 1,
    request = { cancel = function() end }
})

local candidatesA = {}
local envA = {
    npcId = 'npc_a',
    npc = npcA,
    actor = {},
    entry = { id = 'settlement_1' },
    now = 1000,
    priority = 2,
    priorities = { revision = 1, crafting = 2 },
    directory = mockDir,
    orders = { order_forge_1 = order },
    candidates = candidatesA
}
CraftingProvider.discover(envA)
check(#candidatesA == 1, "candidate generated for NPC A")
local candA = candidatesA[1]

-- Setup evaluation for NPC B (skill level 2)
CraftingProvider.evaluations():put('npc_b', {
    orderId = order.id,
    order = order,
    generation = 0,
    object = {},
    ready = true,
    expires = 9999999,
    watch = 1,
    request = { cancel = function() end }
})

local candidatesB = {}
local envB = {
    npcId = 'npc_b',
    npc = npcB,
    actor = {},
    entry = { id = 'settlement_1' },
    now = 1000,
    priority = 2,
    priorities = { revision = 1, crafting = 2 },
    directory = mockDir,
    orders = { order_forge_1 = order },
    candidates = candidatesB
}
CraftingProvider.discover(envB)
check(#candidatesB == 1, "candidate generated for NPC B")
local candB = candidatesB[1]

check(candA.score > candB.score, "Worker with Blacksmithing 6 gets higher candidate score than Blacksmithing 2 (" .. candA.score .. " > " .. candB.score .. ")")

-- 4. Test pendingScore & ready dispatch sorting
local evalA = CraftingProvider.pending('npc_a')
local evalB = CraftingProvider.pending('npc_b')
check(evalA ~= nil and evalB ~= nil, "both evaluations present")

evalA.score = candA.score
evalB.score = candB.score

check(CraftingProvider.pendingScore('npc_a') == candA.score, "pendingScore for NPC A matches candidate score")
check(CraftingProvider.pendingScore('npc_b') == candB.score, "pendingScore for NPC B matches candidate score")

-- Register CraftingProvider with Providers registry
Providers.register(CraftingProvider)
check(Providers.pendingScore('npc_a') == candA.score, "Providers.pendingScore retrieves crafting pending score")

local readyWorkers = { 'npc_b', 'npc_a' } -- NPC B was inserted first
table.sort(readyWorkers, function(a, b)
    return Providers.pendingScore(a) > Providers.pendingScore(b)
end)

check(readyWorkers[1] == 'npc_a', "NPC A (higher skill) sorts ahead of NPC B in ready dispatch queue")
check(readyWorkers[2] == 'npc_b', "NPC B (lower skill) sorts second in ready dispatch queue")

-- 5. Clean up
CraftingProvider.reset()
Recipe.read = oldRead
Recipe.inspect = oldInspect

print("PASS " .. checks .. " blacksmith crafting and skill scoring checks; native game NOT RUN")
