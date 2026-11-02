-- Field domain reconstruction; called only after global collision scanning.
local M={}
function M.restore(context)
    local current=context.current
    local rebuilt=context.rebuilt
    local hasConflict=context.hasConflict
    local ensureEntityClaimId=context.ensureEntityClaimId
    local rebuiltField=context.rebuiltField
		for id, job in pairs(current.taskJobs.byId) do
		    if job.providerType == 'FIELD_WORK' then
			if not require('EmberRoutesProbe/FieldRecord').valid(job) then error('FIELD_RECORD_INVALID') end
			if #job.payload.claims > 0 and job.state ~= 'DONE' and job.state ~= 'CANCELLED' then
			    if hasConflict(job.payload.claims) then
				job.state = 'RECONCILE_REQUIRED'
				job.effects = 'UNKNOWN'
			    else
				local claimId = ensureEntityClaimId(current, job, id)
				local token, why = rebuilt:acquire(id, job.payload.sequence, job.payload.claims, { claimId = claimId })
				if not token then
				    job.state = 'RECONCILE_REQUIRED'
				    job.effects = 'UNKNOWN'
				else
				    local cap = job.payload.capacity
				    if cap and not rebuilt:restore(token, cap.key, cap.itemId, cap.amount) then
					job.state = 'RECONCILE_REQUIRED'
					job.effects = 'UNKNOWN'
					rebuilt:release(token)
				    else
					rebuiltField[id] = token
				    end
				end
			    end
			end
		    end
		end


end
return M
