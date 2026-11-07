-- Craft domain reconstruction; called only after global collision scanning.
-- Records are read as detached copies and every write is queued, so this pass
-- never mutates the Kernel ledger directly. LaborStore applies the queue through
-- JobStore:adopt once the rebuilt authority is published.
local M={}
function M.restore(context)
    local current=context.current
    local rebuilt=context.rebuilt
    local hasConflict=context.hasConflict
    local ensureEntityClaimId=context.ensureEntityClaimId
    local rebuiltCraft=context.rebuiltCraft
    local newTokens=context.newTokens
    local queueAdopt=context.queueAdopt
    local Record=require 'EmberRoutesProbe/Crafting/CraftJobRecord'
    local jobs=require('EmberRoutesProbe/Runtime/TaskJobs').current()
    for _, id in ipairs(jobs:keys()) do
        if jobs:providerType(id)=='CRAFT' then
            local job=jobs:get(id)
            if job.payload and job.payload.format == 4 then
                if not Record.valid(job) then error('CRAFT_JOB_RECORD_INVALID') end
                if #job.payload.claims > 0 and job.state ~= 'DONE' and job.state ~= 'CANCELLED' then
                    local patch={}
                    if hasConflict(job.payload.claims) then
                        patch.state='RECONCILE_REQUIRED'
                        patch.effects='UNKNOWN'
                    else
                        -- ensureEntityClaimId may mint an id onto the record it
                        -- was handed; that record is a copy, so the change is
                        -- carried back explicitly instead of being dropped.
                        local before=job.claimId
                        local claimId=ensureEntityClaimId(current, job, id)
                        if job.claimId~=before then patch.claimId=job.claimId end
                        local token = rebuilt:acquire(id, job.payload.sequence or 0, job.payload.claims, { claimId = claimId })
                        if not token then
                            patch.state='RECONCILE_REQUIRED'
                            patch.effects='UNKNOWN'
                        else
                            rebuiltCraft[id] = token
                            newTokens[id] = token
                        end
                    end
                    if patch.state or patch.claimId then queueAdopt(id, patch) end
                end
            end
        end
    end
end
return M
