local DeliveryService = require 'EmberRoutesProbe/Logistics/DeliveryService'
local Logistics = require 'EmberRoutesProbe/Logistics/LogisticsService'
local Work = require 'EmberRoutesProbe/Work/Work'
local Runtime = require 'EmberRoutesProbe/Runtime/TaskRuntime'

local hauling = {}

local HaulingProvider = {
    category = 'hauling',
    defaultPriority = 3,
    priorityRequired = true,
}

function HaulingProvider.reset()
    hauling = {}
end

function HaulingProvider.discover(env)
    DeliveryService.discover(env)
    local intent = Logistics.publicOffer(env.actor, env.entry, env.npc)
    if intent then
        local key = 'haul:' .. intent.source .. ':' .. tostring(intent.items[1])
        local dir = env.directory
        if dir then
            local offer = dir:upsert(key, 1, 'hauling', env.entry.id)
            if offer and not offer.jobId then
                env.candidates[#env.candidates + 1] = {
                    key = key,
                    revision = 1,
                    category = 'hauling',
                    allowed = true,
                    score = 0,
                    intent = intent
                }
            end
        end
    end
end

-- A refused haul claim is rolled back only when no Job under its id still
-- holds anything. HaulJobs.claim can create the Job and then fail its commit,
-- and ERROR is a caught exception with unknown effects; neither is declared.
local function leftNoJob(jobId)
    local job = require('EmberRoutesProbe/Runtime/TaskJobs').current():peek(jobId)
    if not job then return true end
    if job.state ~= 'DONE' and job.state ~= 'CANCELLED' then return false end
    for _ in pairs(job.obligations or {}) do return false end
    return not (job.payload and job.payload.claims and #job.payload.claims > 0)
end

function HaulingProvider.claim(selected, npcId, jobId, env)
    local result
    if selected.delivery then
        result = DeliveryService.claim(selected, npcId, jobId, env)
    else
        if not env.directory then return 'OFFER_CHANGED', 'ROLLED_BACK' end
        Work.allowAutomation(npcId)
        selected.intent.jobId = jobId
        result = Work.assign(env.actor, npcId, selected.intent)
        if result == 'QUEUED' or result == 'STARTED' then
            hauling[selected.key] = { npcId = npcId, jobId = jobId, directory = env.directory }
        end
    end
    if result == 'QUEUED' or result == 'STARTED' or result == 'ERROR' or not leftNoJob(jobId) then return result end
    return result, 'ROLLED_BACK'
end

function HaulingProvider.reconcile()
    local Log = require 'EmberRoutesProbe/Kernel/Log'
    for key, h in pairs(hauling) do
        local r = Work.record(h.npcId)
        if r and r.id == h.jobId and r.state == 'DONE' then
            if h.directory:release(key, h.jobId, { effects = 'KNOWN', obligationsCleared = true }) then
                hauling[key] = nil
            end
        elseif (not r or r.id ~= h.jobId) and not Runtime.current():status(h.npcId, h.jobId) then
            -- Missing business record or dead session CANNOT prove effects are known or obligations cleared.
            -- Retain responsibility and enter diagnostic state instead of falsely releasing the directory offer.
            -- Announce the transition once: repeating it every cycle only floods the log with
            -- the same unresolved responsibility.
            if h.state ~= 'RECONCILE_REQUIRED' or h.reason ~= 'HAUL_RECORD_MISSING' then
                h.state = 'RECONCILE_REQUIRED'
                h.reason = 'HAUL_RECORD_MISSING'
                if Log and Log.write then
                    Log.write('HAUL', 'RECONCILE_REQUIRED npc=' .. h.npcId .. ' job=' .. h.jobId .. ' reason=HAUL_RECORD_MISSING')
                end
            end
        end
    end
end

function HaulingProvider.advance(env)
    DeliveryService.advance(env)
end

function HaulingProvider.hasWork()
    if DeliveryService.hasWork() then return true end
    for _ in pairs(hauling) do return true end
    return false
end

function HaulingProvider.blocksDecision(actor,npcId,entry)
    local current=Work.record(npcId)
    if not current or current.state=='DONE' then return false end
    if current.producer=='LOGISTICS' and current.settlementId==entry.id
        and not current.controlUncertain and not current.manualPaused
        and Logistics.preparePublic(actor,entry) then
        Work.resumeFor(actor,npcId)
    end
    return true
end
return HaulingProvider
