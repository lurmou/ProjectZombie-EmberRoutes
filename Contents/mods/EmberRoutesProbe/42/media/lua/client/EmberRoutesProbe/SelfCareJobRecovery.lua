-- SelfCare domain reconstruction; called only after global collision scanning.
local M={}
function M.restore(context)
    local current=context.current
    local rebuilt=context.rebuilt
    local hasConflict=context.hasConflict
    local ensureEntityClaimId=context.ensureEntityClaimId
    local rebuiltPersonal=context.rebuiltPersonal
		for id, job in pairs(current.taskJobs.byId) do
		    if job.providerType == 'SELF_CARE' then
			if not require('EmberRoutesProbe/SelfCareRecord').valid(job) then error('PERSONAL_RECORD_INVALID') end
			if #job.payload.claims > 0 and job.state ~= 'DONE' and job.state ~= 'CANCELLED' then
			    if hasConflict(job.payload.claims) then
				job.state = 'RECONCILE_REQUIRED'
				job.effects = 'UNKNOWN'
			    else
				local claimId = ensureEntityClaimId(current, job, id)
				local token, reason = rebuilt:acquire(id, job.payload.sequence, job.payload.claims, { claimId = claimId })
				if not token then
				    job.state = 'RECONCILE_REQUIRED'
				    job.effects = 'UNKNOWN'
				else
				    rebuiltPersonal[id] = token
				end
			    end
			end
		    end
		end


end
return M
