-- Cold rebuild only: defer fact changes until LaborStore publishes its caches.
local M={}
function M.restore(context)
    local jobs=require('EmberRoutesProbe/TaskJobs').current()
    local Record=require 'EmberRoutesProbe/SelfCareRecord'
    local function queue(job,patch,release)
        context.pendingPersonal[#context.pendingPersonal+1]={id=job.id,revision=job.revision,
            patch=patch,release=release}
    end
    for id,job in pairs(context.current.taskJobs.byId) do
        if job.providerType=='SELF_CARE' then
            if not Record.valid(job) then error('PERSONAL_RECORD_INVALID') end
            local member=require('EmberRoutesProbe/MembershipService').view(job.npcId)
            if not member or member.retired then
                local proposed=jobs:get(id)
                local retained=Record.death(proposed)
                queue(job,{payload=proposed.payload,state=proposed.state,effects=proposed.effects},not retained)
            elseif #job.payload.claims>0 and job.state~='DONE' and job.state~='CANCELLED' then
                if context.hasConflict(job.payload.claims) then
                    queue(job,{state='RECONCILE_REQUIRED',effects='UNKNOWN'})
                else
                    local claimId=context.ensureEntityClaimId(context.current,job,id)
                    local token=context.rebuilt:acquire(id,job.payload.sequence,job.payload.claims,{claimId=claimId})
                    if token then context.rebuiltPersonal[id]=token
                    else queue(job,{state='RECONCILE_REQUIRED',effects='UNKNOWN'}) end
                end
            end
        end
    end
end
return M
