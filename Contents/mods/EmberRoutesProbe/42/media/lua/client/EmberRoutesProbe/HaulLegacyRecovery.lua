-- Current legacy adapter reconstruction, not an old-save migration.
local M={}
local Manifest=require 'EmberRoutesProbe/HaulManifest'
function M.restore(c)
    local current=c.current
    local data=c.data
    local rebuilt=c.rebuilt
    local newTokens=c.newTokens
    local hasConflict=c.hasConflict
    local ensureEntityClaimId=c.ensureEntityClaimId
    local resources=c.resources
	-- Pass 2: Controlled recovery & schema-safe demotion
	for id, record in pairs(data.tasks) do
	    if type(record) ~= "table" then
		-- Non-table corrupted record! Safe isolation without indexing non-table:
		current.corruptedTasks = current.corruptedTasks or {}
		current.corruptedTasks[id] = {
		    id = id,
		    raw = record,
		    at = (os and os.time and os.time() or 0)
		}
		data.tasks[id] = nil
		if data.byNpc then
		    for nId, mappedId in pairs(data.byNpc) do
			if mappedId == id then data.byNpc[nId] = nil end
		    end
		end
		if current.taskJobs and current.taskJobs.byId and current.taskJobs.byId[id] then
		    local env = current.taskJobs.byId[id]
		    env.state = "RECONCILE_REQUIRED"
		    env.effects = "UNKNOWN"
		    if type(env.payload) == "table" then
			env.payload.state = "PAUSED"
			env.payload.reason = "CORRUPTED_TASK_RECORD"
			env.payload.uncertain = true
		    end
		end
	    else
		local isRecordValid = type(id) == "string" and record.id == id and type(record.npcId) == "string"
		    and (record.state == 'DONE' or data.byNpc[record.npcId] == id) and (record.format == 1 or Manifest.valid(record)) and record.kind == "EXPLICIT_TRANSFER"
		    and record.executor == "ENTITY" and record.scopeId == "local-world" and type(record.items) == "table"
		    and #record.items <= 30 and (record.state == "RUNNING" or record.state == "PAUSED" or record.state == "DONE")
		    and (not record.generation or (type(record.generation) == "number" and record.generation >= 0
			and record.generation == math.floor(record.generation) and record.generation ~= math.huge))

		if not isRecordValid then
		    record.state = "PAUSED"
		    record.reason = "SCHEMA_INVALID"
		    record.uncertain = true
		    if current.taskJobs and current.taskJobs.byId and current.taskJobs.byId[id] then
			local env = current.taskJobs.byId[id]
			env.state = "RECONCILE_REQUIRED"
			env.effects = "UNKNOWN"
			if type(env.payload) == "table" then
			    env.payload.state = "PAUSED"
			    env.payload.reason = "SCHEMA_INVALID"
			    env.payload.uncertain = true
			end
		    end
		else
		    local itemsValid = true
		    for _, itemId in ipairs(record.items) do
			if type(itemId) ~= "number" or itemId ~= itemId or itemId == math.huge or itemId == -math.huge then
			    itemsValid = false
			    break
			end
		    end
		    if not itemsValid then
			record.state = "PAUSED"
			record.reason = "ITEMS_CORRUPTED"
			record.uncertain = true
			if current.taskJobs and current.taskJobs.byId and current.taskJobs.byId[id] then
			    local env = current.taskJobs.byId[id]
			    env.state = "RECONCILE_REQUIRED"
			    env.effects = "UNKNOWN"
			    if type(env.payload) == "table" then
				env.payload.state = "PAUSED"
				env.payload.reason = "ITEMS_CORRUPTED"
				env.payload.uncertain = true
			    end
			end
		    else
			local resourceKeys = resources(record)
			if record.state ~= "DONE" and #resourceKeys > 0 then
			    if hasConflict(resourceKeys) then
				record.state = "PAUSED"
				record.reason = "CLAIM_CONFLICT"
				record.uncertain = true
				if current.taskJobs and current.taskJobs.byId and current.taskJobs.byId[id] then
				    local env = current.taskJobs.byId[id]
				    env.state = "RECONCILE_REQUIRED"
				    env.effects = "UNKNOWN"
				    if type(env.payload) == "table" then
					env.payload.state = "PAUSED"
					env.payload.reason = "CLAIM_CONFLICT"
					env.payload.uncertain = true
				    end
				end
			    else
				local claimId = ensureEntityClaimId(current, record, id)
				local token = rebuilt:acquire(id, (record.generation or 0) + 1, resourceKeys, { claimId = claimId })
				if not token then
				    record.state = "PAUSED"
				    record.reason = "CLAIM_CONFLICT"
				    record.uncertain = true
				    if current.taskJobs and current.taskJobs.byId and current.taskJobs.byId[id] then
					local env = current.taskJobs.byId[id]
					env.state = "RECONCILE_REQUIRED"
					env.effects = "UNKNOWN"
					if type(env.payload) == "table" then
					    env.payload.state = "PAUSED"
					    env.payload.reason = "CLAIM_CONFLICT"
					    env.payload.uncertain = true
					end
				    end
				else
				    newTokens[id] = token
				    local r = record.reservation
				    if r and type(r) == "table" then
					if r.format == 2 and type(r.items) == "table" then
					    for itemId, amount in pairs(r.items) do
						if not rebuilt:restore(token, r.key, itemId, amount) then
						    record.state = "PAUSED"
						    record.reason = "CAPACITY_CONFLICT"
						    break
						end
					    end
					elseif r.itemId and r.amount then
					    rebuilt:restore(token, r.key, r.itemId, r.amount)
					end
				    end
				end
			    end
			end
		    end
		end
	    end
	end
	for npcId, id in pairs(data.byNpc) do
	    if not data.tasks[id] or data.tasks[id].npcId ~= npcId then error("TASK_INDEX_INVALID") end
	end


end
return M
