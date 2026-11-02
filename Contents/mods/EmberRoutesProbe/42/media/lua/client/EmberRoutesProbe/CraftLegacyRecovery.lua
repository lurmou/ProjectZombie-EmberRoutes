-- Current legacy adapter reconstruction, not an old-save migration.
local M={}
function M.restore(c)
    local current=c.current
    local data=c.data
    local rebuilt=c.rebuilt
    local newTokens=c.newTokens
    local rebuiltNative=c.rebuiltNative
    local hasConflict=c.hasConflict
    local ensureEntityClaimId=c.ensureEntityClaimId
    local nativeRecords=c.nativeRecords
    local CraftRecord=c.CraftRecord

	for npcId, record in pairs(nativeRecords()) do
	    if (record.format == 1 or record.format == 2 or record.format == 3) and not record.released then
		local other = data.tasks[data.byNpc[npcId]]
		if other and other.state ~= "DONE" then
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
