local DeliveryService = require 'EmberRoutesProbe/DeliveryService'
local Logistics = require 'EmberRoutesProbe/LogisticsService'
local Work = require 'EmberRoutesProbe/Work'
local Runtime = require 'EmberRoutesProbe/TaskRuntime'

local hauling = {}

local HaulingProvider = {
    category = 'hauling',
    defaultPriority = 3,
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

function HaulingProvider.claim(selected, npcId, jobId, env)
    if selected.delivery then
        return DeliveryService.claim(selected, npcId, jobId, env)
    end
    if not env.directory then return 'OFFER_CHANGED' end
    Work.allowAutomation(npcId)
    selected.intent.jobId = jobId
    local result = Work.assign(env.actor, npcId, selected.intent)
    if result == 'QUEUED' or result == 'STARTED' then
        hauling[selected.key] = { npcId = npcId, jobId = jobId, directory = env.directory }
    end
    return result
end

function HaulingProvider.reconcile()
    local Log = require 'EmberRoutesProbe/Log'
    for key, h in pairs(hauling) do
        local r = Work.record(h.npcId)
        if r and r.id == h.jobId and r.state == 'DONE' then
            if h.directory:release(key, h.jobId, { effects = 'KNOWN', obligationsCleared = true }) then
                hauling[key] = nil
            end
        elseif (not r or r.id ~= h.jobId) and not Runtime.current():status(h.npcId, h.jobId) then
            -- Missing business record or dead session CANNOT prove effects are known or obligations cleared.
            -- Retain responsibility and enter diagnostic state instead of falsely releasing the directory offer.
            h.state = 'RECONCILE_REQUIRED'
            h.reason = 'HAUL_RECORD_MISSING'
            if Log and Log.write then
                Log.write('HAUL', 'RECONCILE_REQUIRED npc=' .. h.npcId .. ' job=' .. h.jobId .. ' reason=HAUL_RECORD_MISSING')
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

return HaulingProvider
