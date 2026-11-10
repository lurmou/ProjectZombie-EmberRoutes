-- HaulingProvider.retained (P4, provider-lifecycle): an NPC still holding an
-- unfinished HAUL Job must be retained out of new ordinary work.
--
-- Regression guard for the stale-`hauling`-table leak: entries in the
-- module-level `hauling` table are only deleted by reconcile on DONE, so
-- CANCELLED / job-swapped entries survive. retained() must therefore match
-- the CURRENT record (Work.record, i.e. HaulJobs.record scanning JobStore)
-- by jobId + state, never match the table on npcId alone.
package.path = "Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;Contents/mods/EmberRoutesProbe/42/media/lua/client/?.lua;" .. package.path

local mockWorkRecord = nil

package.loaded['EmberRoutesProbe/Logistics/DeliveryService'] = {
    discover = function(env) end,
    hasWork = function() return false end,
    claim = function(sel, npcId, jobId, env) return "QUEUED" end,
    advance = function(env) end
}
package.loaded['EmberRoutesProbe/Logistics/LogisticsService'] = {
    publicOffer = function(actor, entry, npc) return nil end
}
package.loaded['EmberRoutesProbe/Work/Work'] = {
    allowAutomation = function(npcId) end,
    assign = function(actor, npcId, intent) return "QUEUED" end,
    record = function(npcId) return mockWorkRecord end
}
package.loaded['EmberRoutesProbe/Runtime/TaskRuntime'] = {
    current = function()
        return { status = function(self, npcId, jobId) return false end }
    end
}

local HaulingProvider = require 'EmberRoutesProbe/Hauling/HaulingProvider'
assert(type(HaulingProvider.retained) == 'function', "Provider must implement retained(npcId) per P4")

-- 1. No current HAUL record: nothing to retain.
assert(HaulingProvider.retained('npc_1') == false, "no record must not retain")

-- 2. Unfinished job retains.
mockWorkRecord = { id = 'job_1', state = 'RUNNING' }
assert(HaulingProvider.retained('npc_1') == true, "RUNNING job must retain")

-- 3. Paused claimed job retains (the spec scenario: a paused haul must not
-- be misread as idle and handed leisure/fitness work).
mockWorkRecord = { id = 'job_1', state = 'PAUSED' }
assert(HaulingProvider.retained('npc_1') == true, "PAUSED job must retain")

-- 4. DONE does not retain.
mockWorkRecord = { id = 'job_1', state = 'DONE' }
assert(HaulingProvider.retained('npc_1') == false, "DONE job must not retain")

-- 5. CANCELLED does not retain.
mockWorkRecord = { id = 'job_1', state = 'CANCELLED' }
assert(HaulingProvider.retained('npc_1') == false, "CANCELLED job must not retain")

-- 6. Stale `hauling` entry must not retain once its job is DONE. The entry
-- is written by the LOGISTICS claim path below and is still in the table
-- here (reconcile was not called); only the current record's state decides.
local mockDirectory = {
    upsert = function(self, key, rev, cat, scope) return { key = key, jobId = nil } end,
    release = function(self, key, ticket, opts) return true end
}
local env = { actor = {}, entry = { id = 'settlement_1' }, npc = {}, candidates = {}, directory = mockDirectory }
local selected = {
    key = 'haul:src_box:Base.Apple',
    intent = { source = 'src_box', items = { 'Base.Apple' } },
}
local res = HaulingProvider.claim(selected, 'npc_2', 'job_old', env)
assert(res == 'QUEUED', "LOGISTICS claim must queue so the hauling entry is written")
assert(HaulingProvider.hasWork() == true, "hauling entry must be tracked after claim")
mockWorkRecord = { id = 'job_old', state = 'DONE' }
assert(HaulingProvider.retained('npc_2') == false,
    "DONE record must not retain even though its hauling entry is still tracked")
-- Simulate the swap: the NPC's current record is now a different, DONE job.
mockWorkRecord = { id = 'job_new', state = 'DONE' }
assert(HaulingProvider.retained('npc_2') == false,
    "stale entry + DONE current record must not retain (jobId mismatch)")
-- And the converse: a different, unfinished current job retains on its own
-- merits, not because of the stale entry.
mockWorkRecord = { id = 'job_new', state = 'RUNNING' }
assert(HaulingProvider.retained('npc_2') == true,
    "unfinished current job must retain even after a job swap")

-- 7. Stale entry with no current record at all must not retain: no
-- unfinished HAUL Job is provable. (Keeping the directory offer in that
-- case is reconcile's responsibility, not retained's.)
mockWorkRecord = nil
assert(HaulingProvider.retained('npc_2') == false,
    "stale entry + missing record must not retain")

-- 8. Registry wiring: retained is an accepted optional hook and
-- Registry.retained follows it.
local Registry = require 'EmberRoutesProbe/Work/PublicWorkProviders'
Registry.reset()
local ok, err = Registry.register(HaulingProvider)
assert(ok == true, "hauling provider must register with retained hook: " .. tostring(err))
mockWorkRecord = { id = 'job_1', state = 'RUNNING' }
assert(Registry.retained('npc_1') == true, "Registry.retained must see the unfinished haul job")
mockWorkRecord = { id = 'job_1', state = 'CANCELLED' }
assert(Registry.retained('npc_1') == false, "Registry.retained must release after CANCELLED")
Registry.reset()

print("PASS: haul-provider-retained-test")
