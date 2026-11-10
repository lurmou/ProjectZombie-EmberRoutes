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
-- JobStore job state, keyed by job id. Production peek is
-- Jobs.current():peek(id); the mock mirrors that call shape (colon call).
local mockJobs = {}
package.loaded['EmberRoutesProbe/Runtime/TaskJobs'] = {
    current = function()
        return { peek = function(_, id) return mockJobs[id] end }
    end
}

package.loaded['EmberRoutesProbe/Logistics/DeliveryService'] = {
    discover = function(env) end,
    hasWork = function() return false end,
    claim = function(sel, npcId, jobId, env) return "QUEUED" end,
    advance = function(env) end
}
-- Whether Logistics.preparePublic succeeds; blocksDecision only resumes a
-- LOGISTICS haul when this is true.
local preparePublicResult = true
package.loaded['EmberRoutesProbe/Logistics/LogisticsService'] = {
    publicOffer = function(actor, entry, npc) return nil end,
    preparePublic = function(actor, entry) return preparePublicResult end
}
local resumeForCalls = 0
package.loaded['EmberRoutesProbe/Work/Work'] = {
    allowAutomation = function(npcId) end,
    assign = function(actor, npcId, intent) return "QUEUED" end,
    record = function(npcId) return mockWorkRecord end,
    resumeFor = function(actor, npcId) resumeForCalls = resumeForCalls + 1 end
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

-- 8. Faithful cancel: the production cancel path (HaulJobs.cancel ->
-- Store.cancelJob -> LaborCommitKernel.cancel) writes the JOB state to
-- CANCELLED and leaves the payload state untouched (PAUSED here, exactly
-- as the kernel leaves it). retained must judge the JobStore job state,
-- not the payload state, or the NPC stays retained until the retirement
-- sweep retires the job. The old payload-only check returns true here.
mockWorkRecord = { id = 'job_1', state = 'PAUSED' }
mockJobs['job_1'] = { id = 'job_1', state = 'CANCELLED' }
assert(HaulingProvider.retained('npc_1') == false,
    "CANCELLED job with PAUSED payload must not retain (job state decides)")
mockJobs['job_1'] = { id = 'job_1', state = 'SUSPENDED' }
assert(HaulingProvider.retained('npc_1') == true,
    "SUSPENDED job with PAUSED payload must retain")
mockJobs['job_1'] = { id = 'job_1', state = 'DONE' }
assert(HaulingProvider.retained('npc_1') == false,
    "DONE job with PAUSED payload must not retain")
mockJobs['job_1'] = { id = 'job_1', state = 'RUNNING' }
assert(HaulingProvider.retained('npc_1') == true,
    "RUNNING job with PAUSED payload must retain")
mockJobs['job_1'] = nil

-- 9. Registry wiring: retained is an accepted optional hook and
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

-- 10. blocksDecision: same payload/job-state split as retained. A
-- cancelled LOGISTICS haul (payload PAUSED, job CANCELLED) must NOT block
-- a new decision and must NOT be resumed -- resuming would re-launch a
-- cancelled job, because HaulAgent.resume launches on any non-DONE
-- payload. The LOGISTICS recovery path itself is preserved for live jobs.
local decisionEntry = { id = 'settlement_1' }
local function logisticsRecord(state, jobState)
    mockWorkRecord = { id = 'job_1', state = state, producer = 'LOGISTICS',
        settlementId = 'settlement_1' }
    mockJobs['job_1'] = jobState and { id = 'job_1', state = jobState } or nil
    resumeForCalls = 0
end

-- 10a. No record: nothing to block.
mockWorkRecord = nil
assert(HaulingProvider.blocksDecision({}, 'npc_1', decisionEntry) == false,
    "no record must not block a decision")

-- 10b. Payload DONE: does not block (pre-existing behaviour).
mockWorkRecord = { id = 'job_1', state = 'DONE' }
assert(HaulingProvider.blocksDecision({}, 'npc_1', decisionEntry) == false,
    "DONE payload must not block a decision")

-- 10c. Faithful cancel: payload PAUSED, job CANCELLED. Must not block and
-- must not resume -- the old payload-only check returned true here and
-- called resumeFor on the cancelled haul.
logisticsRecord('PAUSED', 'CANCELLED')
assert(HaulingProvider.blocksDecision({}, 'npc_1', decisionEntry) == false,
    "CANCELLED job with PAUSED payload must not block a decision (job state decides)")
assert(resumeForCalls == 0,
    "CANCELLED job must not be resumed")

-- 10d. Same payload, job DONE: also releases immediately.
logisticsRecord('PAUSED', 'DONE')
assert(HaulingProvider.blocksDecision({}, 'npc_1', decisionEntry) == false,
    "DONE job with PAUSED payload must not block a decision")
assert(resumeForCalls == 0, "DONE job must not be resumed")

-- 10e. Live LOGISTICS haul: still blocks AND resumes (recovery path
-- preserved exactly as before).
logisticsRecord('PAUSED', 'RUNNING')
assert(HaulingProvider.blocksDecision({}, 'npc_1', decisionEntry) == true,
    "live LOGISTICS haul must still block a new decision")
assert(resumeForCalls == 1, "live LOGISTICS haul must still be resumed")

-- 10f. Live non-LOGISTICS haul: blocks but does not resume.
mockWorkRecord = { id = 'job_1', state = 'RUNNING', producer = 'FIELD',
    settlementId = 'settlement_1' }
mockJobs['job_1'] = { id = 'job_1', state = 'RUNNING' }
resumeForCalls = 0
assert(HaulingProvider.blocksDecision({}, 'npc_1', decisionEntry) == true,
    "live non-LOGISTICS haul must still block a new decision")
assert(resumeForCalls == 0, "non-LOGISTICS haul must not be resumed")

-- 10g. Job missing from JobStore: fail-closed, still blocks (same
-- philosophy as retained/reconcile -- a missing job cannot prove the
-- haul is finished).
logisticsRecord('PAUSED', nil)
assert(HaulingProvider.blocksDecision({}, 'npc_1', decisionEntry) == true,
    "PAUSED payload with missing job must still block (fail-closed)")

-- 10h. Registry wiring: Registry.blocksDecision follows the provider.
Registry.reset()
local ok2, err2 = Registry.register(HaulingProvider)
assert(ok2 == true, "hauling provider must register with blocksDecision hook: " .. tostring(err2))
logisticsRecord('PAUSED', 'CANCELLED')
assert(Registry.blocksDecision({}, 'npc_1', decisionEntry) == false,
    "Registry.blocksDecision must release after CANCELLED")
logisticsRecord('PAUSED', 'RUNNING')
assert(Registry.blocksDecision({}, 'npc_1', decisionEntry) == true,
    "Registry.blocksDecision must block a live LOGISTICS haul")
Registry.reset()

print("PASS: haul-provider-retained-test")
