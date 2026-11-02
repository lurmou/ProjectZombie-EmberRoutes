-- Cooking domain reconstruction; called only after global collision scanning.
local M={}
function M.restore(context)
    local current=context.current
    local rebuilt=context.rebuilt
    local hasConflict=context.hasConflict
    local ensureEntityClaimId=context.ensureEntityClaimId
    local rebuiltCooking=context.rebuiltCooking
		for id, job in pairs(current.taskJobs.byId) do
		    if job.providerType == 'COOKING' then
			if not require('EmberRoutesProbe/CookingRecord').valid(job) then error('COOKING_RECORD_INVALID') end
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
				    local cap = job.payload.capacity
				    if cap and not rebuilt:restoreWork(token, cap.endpointId, cap.amount) then
					job.state = 'RECONCILE_REQUIRED'
					job.effects = 'UNKNOWN'
					rebuilt:release(token)
				    else
					rebuiltCooking[id] = token
				    end
				end
			    end
			end
		    end
		end


end
return M
