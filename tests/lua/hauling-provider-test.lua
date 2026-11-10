package.path = "Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;Contents/mods/EmberRoutesProbe/42/media/lua/client/?.lua;" .. package.path

local mockWorkAssigned = nil
local mockWorkRecord = nil
local mockDeliveryDiscovered = false
local mockDeliveryHasWork = false
local mockDeliveryClaimed = false
local mockAssignResult = nil

-- Mock dependencies
package.loaded['EmberRoutesProbe/Logistics/DeliveryService'] = {
    discover = function(env) mockDeliveryDiscovered = true end,
    hasWork = function() return mockDeliveryHasWork end,
    claim = function(sel, npcId, jobId, env)
        mockDeliveryClaimed = true
        return "QUEUED"
    end,
    advance = function(env) end
}

local mockOfferIntent = nil
package.loaded['EmberRoutesProbe/Logistics/LogisticsService'] = {
    publicOffer = function(actor, entry, npc)
        return mockOfferIntent
    end
}

package.loaded['EmberRoutesProbe/Work/Work'] = {
    allowAutomation = function(npcId) end,
    assign = function(actor, npcId, intent)
        mockWorkAssigned = { npcId = npcId, intent = intent }
        return mockAssignResult or "QUEUED"
    end,
    record = function(npcId)
        return mockWorkRecord
    end
}

package.loaded['EmberRoutesProbe/Runtime/TaskRuntime'] = {
    current = function()
        return {
            status = function(self, npcId, jobId) return false end
        }
    end
}

local upsertedKey, releasedKey, releasedTicket = nil, nil, nil
local releaseAllowed = true
local mockDirectory = {
    upsert = function(self, key, rev, cat, scope)
        upsertedKey = key
        return { key = key, jobId = nil }
    end,
    release = function(self, key, ticket, opts)
        releasedKey = key
        releasedTicket = ticket
        return releaseAllowed
    end
}

local HaulingProvider = require 'EmberRoutesProbe/Hauling/HaulingProvider'
assert(package.loaded['EmberRoutesProbe/Work/PublicWork'] == nil, "provider must load without its coordinator")

-- Test 1: Provider contract definition
assert(HaulingProvider.category == 'hauling', "Provider category must be hauling")
assert(HaulingProvider.defaultPriority == 3, "Provider defaultPriority must be 3")
assert(type(HaulingProvider.discover) == 'function', "Provider must implement discover")
assert(type(HaulingProvider.claim) == 'function', "Provider must implement claim")
assert(type(HaulingProvider.reconcile) == 'function', "Provider must implement reconcile")
assert(type(HaulingProvider.advance) == 'function', "Provider must implement advance")
assert(type(HaulingProvider.hasWork) == 'function', "Provider must implement hasWork")

-- Test 2: hasWork
assert(HaulingProvider.hasWork() == false, "Initially has no work")
mockDeliveryHasWork = true
assert(HaulingProvider.hasWork() == true, "hasWork is true when DeliveryService has work")
mockDeliveryHasWork = false
assert(HaulingProvider.hasWork() == false, "hasWork false when empty")

-- Test 3: discover without intent
local env = {
    actor = {},
    entry = { id = 'settlement_1' },
    npc = {},
    candidates = {},
    directory = mockDirectory
}
HaulingProvider.discover(env)
assert(mockDeliveryDiscovered == true, "discover forwards to DeliveryService")
assert(#env.candidates == 0, "No candidates without logistics offer")

-- Test 4: discover with publicOffer
mockOfferIntent = { source = 'src_box', items = { 'Base.Apple' } }
HaulingProvider.discover(env)
assert(#env.candidates == 1, "Candidate added")
assert(env.candidates[1].key == 'haul:src_box:Base.Apple', "Candidate key matches offer")
assert(upsertedKey == 'haul:src_box:Base.Apple', "Directory upsert was called")

-- Test 5: claim standard haul
local selected = env.candidates[1]
local res = HaulingProvider.claim(selected, 'npc_1', 'job_haul_1', env)
assert(res == 'QUEUED', "Claim returns QUEUED")
assert(mockWorkAssigned ~= nil and mockWorkAssigned.npcId == 'npc_1', "Work assigned to npc_1")
assert(HaulingProvider.hasWork() == true, "hasWork true while hauling is active")
mockWorkRecord = { id = 'job_haul_1', state = 'RUNNING' }
HaulingProvider.reconcile()
assert(releasedKey == nil and HaulingProvider.hasWork(), "unfinished work retains its directory claim")

-- Test 6: reconcile with job done
mockWorkRecord = { id = 'job_haul_1', state = 'DONE' }
releaseAllowed = false
HaulingProvider.reconcile()
assert(HaulingProvider.hasWork(), "failed directory release retains the receipt for retry")
releaseAllowed = true
-- The caller's next context must not redirect an earlier claim's release.
env.directory = { release = function() error('wrong directory') end }
HaulingProvider.reconcile()
assert(releasedKey == 'haul:src_box:Base.Apple', "Released offer on reconcile done")
assert(releasedTicket == 'job_haul_1', "Released ticket matches jobId")
assert(HaulingProvider.hasWork() == false, "hauling record was cleared")

-- Test 6b: reconcile with missing record but persistent taskJob exists -> must NOT release obligations
package.loaded['EmberRoutesProbe/Warehouse/ContainerRegistry'] = {
    data = function() return { taskJobs = { byId = { ['job_haul_suspect'] = { id = 'job_haul_suspect' } } } } end
}
package.loaded['EmberRoutesProbe/Kernel/Log'] = { write = function() end }
releasedKey = nil
env.directory = mockDirectory
HaulingProvider.claim(selected, 'npc_suspect', 'job_haul_suspect', env)
mockWorkRecord = nil -- session vanished
HaulingProvider.reconcile()
assert(releasedKey == nil, "Must not release directory when persistent job exists without DONE proof")
assert(HaulingProvider.hasWork() == true, "Must retain hauling tracking for suspected unclosed job")
HaulingProvider.reset()

-- Test 7: reset
env.directory = mockDirectory
HaulingProvider.claim(selected, 'npc_2', 'job_haul_2', env)
assert(HaulingProvider.hasWork() == true)
HaulingProvider.reset()
assert(HaulingProvider.hasWork() == false, "reset clears all active hauling items")
mockWorkAssigned = nil
assert(HaulingProvider.claim(selected, 'npc_3', 'job_haul_3', {}) == 'OFFER_CHANGED'
    and mockWorkAssigned == nil, "missing directory cannot start physical work")
local _, declared = HaulingProvider.claim(selected, 'npc_3', 'job_haul_3', {})
assert(declared == 'ROLLED_BACK', "refusal before any work declares its rollback")

-- Test 8 (P2): a refusal after the haul Job was created must not declare a rollback.
local storedJobs = {}
package.loaded['EmberRoutesProbe/Runtime/TaskJobs'] = {
    current = function() return { peek = function(_, id) return storedJobs[id] end } end
}
mockAssignResult = 'HAUL_TRANSITION_UNRESOLVED'
storedJobs['job_haul_4'] = { id = 'job_haul_4', state = 'PREPARING', obligations = { business = true }, payload = { claims = { 'item:1' } } }
local result4, declared4 = HaulingProvider.claim(selected, 'npc_4', 'job_haul_4', env)
assert(result4 == 'HAUL_TRANSITION_UNRESOLVED' and declared4 == nil, "created Job keeps the offer: no rollback declaration")
assert(HaulingProvider.hasWork() == false, "refused claim is not tracked as active hauling")
-- Same refusal with no Job left behind declares the rollback.
local result5, declared5 = HaulingProvider.claim(selected, 'npc_5', 'job_haul_5', env)
assert(result5 == 'HAUL_TRANSITION_UNRESOLVED' and declared5 == 'ROLLED_BACK', "refusal with no Job declares rollback")
-- A settled Job with nothing held also counts as rolled back.
storedJobs['job_haul_6'] = { id = 'job_haul_6', state = 'DONE', obligations = {}, payload = { claims = {} } }
local _, declared6 = HaulingProvider.claim(selected, 'npc_6', 'job_haul_6', env)
assert(declared6 == 'ROLLED_BACK', "settled empty Job declares rollback")
-- ERROR is a caught exception with unknown effects.
mockAssignResult = 'ERROR'
local _, declared7 = HaulingProvider.claim(selected, 'npc_7', 'job_haul_7', env)
assert(declared7 == nil, "ERROR never declares rollback")
mockAssignResult = nil
package.loaded['EmberRoutesProbe/Runtime/TaskJobs'] = nil

print("PASS: hauling-provider-test")
