-- Haul domain reconstruction; called only after global collision scanning.
local M={}
function M.restore(context)
    local function reconcile(id,job,reason)
        -- Commit, per Phase 0 inventory. Never publish into a half-built Store.
        context.pendingHaul[#context.pendingHaul+1]={id=id,revision=job.revision,reason=reason}
    end
    local current=context.current
    local rebuilt=context.rebuilt
    local hasConflict=context.hasConflict
    local ensureEntityClaimId=context.ensureEntityClaimId
    local rebuiltHaul=context.rebuiltHaul
    local newTokens=context.newTokens
		for id, job in pairs(current.taskJobs.byId) do
		    if job.providerType == 'HAUL' and job.payload and (job.payload.format == 3 or job.payload.format == 1) then
			if newTokens[id] then
			    rebuiltHaul[id] = newTokens[id]
			else
			    local isValid = false
			    if job.payload.format == 3 then
				isValid = require('EmberRoutesProbe/Hauling/HaulJobRecord').valid(job)
			    elseif job.payload.format == 1 then
				local p = job.payload
				isValid = type(p) == 'table' and type(p.items) == 'table' and type(p.source) == 'string' and type(p.destination) == 'string'
			    end
			    if not isValid then
				reconcile(id,job,'HAUL_RECORD_INVALID')
			    else
				local claimKeys = job.payload.claims
				if not claimKeys and job.payload.items then
				    claimKeys = {}
				    for _, itId in ipairs(job.payload.items) do
					claimKeys[#claimKeys + 1] = "item:" .. itId
				    end
				end
				claimKeys = claimKeys or {}
				if #claimKeys > 0 and job.state ~= 'DONE' and job.state ~= 'CANCELLED' then
				    if hasConflict(claimKeys) then
					reconcile(id,job,'HAUL_CLAIM_CONFLICT')
				    else
					local claimId = ensureEntityClaimId(current, job, id)
					local token, reason = rebuilt:acquire(id, job.payload.sequence or 0, claimKeys, { claimId = claimId })
					if not token then
					    reconcile(id,job,'HAUL_ACQUIRE_FAILED:'..tostring(reason))
					else
					    local r = job.payload.reservation
					    local okCap = true
					    if r and type(r) == 'table' then
						if type(r.items) == 'table' then
						    for itemId, amount in pairs(r.items) do
							if not rebuilt:restore(token, r.key, itemId, amount) then okCap = false break end
						    end
						elseif r.itemId and r.amount then
						    if not rebuilt:restore(token, r.key, r.itemId, r.amount) then okCap = false end
						end
					    end
					    if not okCap then
						reconcile(id,job,'HAUL_CAPACITY_RESTORE_FAILED')
                        -- Failed reconstruction cleanup is deferred with its commit.
                        context.pendingHaul[#context.pendingHaul].failedToken=token
					    else
						rebuiltHaul[id] = token
						newTokens[id] = token
					    end
					end
				    end
				end
			    end
			end
		    end
		end
end
return M
