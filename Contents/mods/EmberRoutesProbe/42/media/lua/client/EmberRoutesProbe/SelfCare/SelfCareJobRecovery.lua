-- Cold rebuild only: defer fact changes until LaborStore publishes its caches.
-- Records are read as detached copies; nothing here writes the Kernel ledger.
local M={}
function M.restore(context)
    local jobs=require('EmberRoutesProbe/Runtime/TaskJobs').current()
    local Record=require 'EmberRoutesProbe/SelfCare/SelfCareRecord'
    local function queue(job,patch,release)
        context.pendingPersonal[#context.pendingPersonal+1]={id=job.id,revision=job.revision,
            patch=patch,release=release}
    end
    for _, id in ipairs(jobs:keys()) do
        if jobs:providerType(id)=='SELF_CARE' then
            local job=jobs:get(id)
            if not Record.valid(job) then error('PERSONAL_RECORD_INVALID') end
            local member=require('EmberRoutesProbe/Settlement/MembershipService').view(job.npcId)
            if not member or member.retired then
                -- Record.death reads and rewrites the payload it is handed; that
                -- is a copy, so the result is carried back through the queue.
                local retained=Record.death(job)
                queue(job,{payload=job.payload,state=job.state,effects=job.effects},not retained)
            elseif #job.payload.claims>0 and job.state~='DONE' and job.state~='CANCELLED' then
                if context.hasConflict(job.payload.claims) then
                    queue(job,{state='RECONCILE_REQUIRED',effects='UNKNOWN'})
                else
                    -- ensureEntityClaimId may mint an id onto the copy it was
                    -- handed; claimId is outside the personal commit patch, so
                    -- the change is applied through adopt instead of being lost.
                    local before=job.claimId
                    local claimId=context.ensureEntityClaimId(context.current,job,id)
                    if job.claimId~=before then context.queueAdopt(id,{claimId=job.claimId}) end
                    local token=context.rebuilt:acquire(id,job.payload.sequence,job.payload.claims,{claimId=claimId})
                    if token then context.rebuiltPersonal[id]=token
                    else queue(job,{state='RECONCILE_REQUIRED',effects='UNKNOWN'}) end
                end
            end
        end
    end
end
return M
