-- Current legacy adapter reconstruction, not an old-save migration.
local M={}
function M.restore(c)
    local current=c.current
    local rebuilt=c.rebuilt
    local newTokens=c.newTokens
    local rebuiltNative=c.rebuiltNative
    local hasConflict=c.hasConflict
    local ensureEntityClaimId=c.ensureEntityClaimId
    local nativeRecords=c.nativeRecords
    local CraftRecord=c.CraftRecord

	for npcId, record in pairs(nativeRecords()) do
	    if (record.format == 1 or record.format == 2 or record.format == 3) and not record.released then
		local other
		for _,j in pairs(current.taskJobs and current.taskJobs.byId or {}) do
		    if j.providerType=='HAUL' and j.npcId==npcId and j.state~='DONE' and j.state~='CANCELLED' then other=j break end
		end
		if other then
		    record.released = true
		else
		    local resKeys = CraftRecord.resources(record)
		    if hasConflict(resKeys) then
			record.uncertain=true record.state='PAUSED' record.reason='RESOURCE_COLLISION'
		    else
			local claimId = ensureEntityClaimId(current, record, record.id)
			local token = rebuilt:acquire(record.id, record.generation, resKeys, { claimId = claimId })
			if not token or newTokens[record.id] or rebuiltNative[record.id] then
			    record.released = true
			else
			    rebuiltNative[record.id] = token
			end
		    end
		end
	    end
	end


end
return M
