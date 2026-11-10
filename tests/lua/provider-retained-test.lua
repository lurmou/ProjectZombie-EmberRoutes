-- CraftingProvider.retained + ToolReturnProvider.retained (P4, P1 registry):
-- an NPC still holding an unfinished job of the provider's own kind must be
-- retained out of new ordinary work; finished jobs, other kinds' jobs, and
-- a tool with no live return task must not retain.
-- Crafting judges the live JobStore record through the JobState registry
-- (same read as FieldWork/CookingService); ToolReturn judges its live task
-- (startFor records it until the task stops or finishes).
package.path = "Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;Contents/mods/EmberRoutesProbe/42/media/lua/client/?.lua;" .. package.path

local n = 0
local function check(v, msg) n = n + 1 assert(v, msg) end

-- ---- Crafting: JobStore jobs, keyed by npc ----
local jobsByNpc = {}
package.loaded['EmberRoutesProbe/Runtime/TaskJobs'] = {
    current = function()
        return {
            visitNpc = function(_, npcId, visitor)
                for _, j in ipairs(jobsByNpc[npcId] or {}) do visitor(j) end
            end,
        }
    end,
}
package.loaded['EmberRoutesProbe/Warehouse/ContainerRegistry'] = {
    data = function() return { craftSurfaces = {} } end,
    id = function() return 'test_craft_id' end,
}
package.loaded['EmberRoutesProbe/Runtime/TaskRuntime'] = {
    current = function()
        return { status = function(_, _, _) return false end }
    end,
}
package.loaded['EmberRoutesProbe/Kernel/Boot'] = { idleStudy = function() end }
package.loaded['EmberRoutesProbe/Work/LaborSignals'] = { changed = function() end }
package.loaded['EmberRoutesProbe/Runtime/PlanningWake'] = {
    capture = function() return 1 end,
    changed = function() return false end,
}
package.loaded['EmberRoutesProbe/Cooking/CookingOrders'] = {
    parentAllows = function(_) return true end,
}
package.loaded['EmberRoutesProbe/Crafting/Production'] = {
    execute = function() return 'QUEUED' end,
}

local CraftingProvider = require 'EmberRoutesProbe/Crafting/CraftingProvider'
check(type(CraftingProvider.retained) == 'function', 'crafting must implement retained(npcId) per P4')

local function craftJob(state, kind)
    return { id = 'craft-1', npcId = 'npc1', providerType = kind or 'CRAFT', state = state }
end
check(CraftingProvider.retained('npc1') == false, 'no CRAFT job must not retain')
jobsByNpc.npc1 = { craftJob('RUNNING') }
check(CraftingProvider.retained('npc1') == true, 'RUNNING CRAFT job must retain')
jobsByNpc.npc1 = { craftJob('SUSPENDED') }
check(CraftingProvider.retained('npc1') == true, 'SUSPENDED CRAFT job must retain')
jobsByNpc.npc1 = { craftJob('PREPARING') }
check(CraftingProvider.retained('npc1') == true, 'PREPARING CRAFT job must retain')
jobsByNpc.npc1 = { craftJob('DONE') }
check(CraftingProvider.retained('npc1') == false, 'DONE CRAFT job must not retain')
jobsByNpc.npc1 = { craftJob('CANCELLED') }
check(CraftingProvider.retained('npc1') == false, 'CANCELLED CRAFT job must not retain')
jobsByNpc.npc1 = { craftJob('RUNNING', 'HAUL') }
check(CraftingProvider.retained('npc1') == false, 'another kind’s RUNNING job must not retain crafting')
jobsByNpc.npc1 = { craftJob('BOGUS') }
check(CraftingProvider.retained('npc1') == true, 'unknown job state must not be mistaken for finished')
jobsByNpc.npc1 = { craftJob('DONE'), craftJob('RUNNING') }
check(CraftingProvider.retained('npc1') == true, 'one unfinished job retains even beside a DONE one')
jobsByNpc.npc1 = {}
check(CraftingProvider.retained('npc2') == false, 'unrelated NPC must not retain')

-- ---- ToolReturn: live return task, keyed by npc ----
local liveTasks = {}
package.loaded['EmberRoutesProbe/Work/LaborStore'] = {
    custodyForNpc = function() return {} end,
}
package.loaded['EmberRoutesProbe/Field/ToolReturnService'] = {
    liveTask = function(npcId) return liveTasks[npcId] end,
    canInterrupt = function() return false end,
    reconcile = function() end,
}
package.loaded['EmberRoutesProbe/Warehouse/ContainerRegistry'] = {
    data = function() return {} end,
}

local ToolReturnProvider = require 'EmberRoutesProbe/Field/ToolReturnProvider'
check(type(ToolReturnProvider.retained) == 'function', 'toolReturn must implement retained(npcId) per P4')
check(ToolReturnProvider.retained('npc1') == false, 'no live return task must not retain')
liveTasks.npc1 = { returnJobId = 'tool-1' }
check(ToolReturnProvider.retained('npc1') == true, 'live return task must retain')
check(ToolReturnProvider.retained('npc2') == false, 'another NPC’s live return must not retain this one')
liveTasks.npc1 = nil
check(ToolReturnProvider.retained('npc1') == false, 'finished return task must not retain')

-- ---- Registry wiring: retained is required, and Registry.retained follows it ----
local Registry = require 'EmberRoutesProbe/Work/PublicWorkProviders'
Registry.reset()
local ok, err = Registry.register(CraftingProvider)
check(ok, 'crafting registers with retained: ' .. tostring(err))
ok, err = Registry.register(ToolReturnProvider)
check(ok, 'toolReturn registers with retained: ' .. tostring(err))
jobsByNpc.npc1 = { craftJob('RUNNING') }
check(Registry.retained('npc1') == true, 'registry retains while the CRAFT job is unfinished')
jobsByNpc.npc1 = { craftJob('DONE') }
liveTasks.npc1 = { returnJobId = 'tool-1' }
check(Registry.retained('npc1') == true, 'registry retains while the return task is live')
jobsByNpc.npc1 = { craftJob('DONE') }
liveTasks.npc1 = nil
check(Registry.retained('npc1') == false, 'registry releases once both jobs are finished')
Registry.reset()

print('PASS ' .. n .. ' provider retained checks (crafting + toolReturn)')
