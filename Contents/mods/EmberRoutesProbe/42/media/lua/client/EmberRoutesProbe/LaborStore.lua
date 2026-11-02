local Registry=require "EmberRoutesProbe/ContainerRegistry"
local Claims=require "EmberRoutesProbe/LaborClaims"
local CraftRecord=require "EmberRoutesProbe/CraftRecord"
local Manifest=require 'EmberRoutesProbe/HaulManifest'
local Evidence=require 'EmberRoutesProbe/QuarantineEvidence'
local Store={}
local root,ledger,claims,tokens
local domainState={}
local nativeTokens={}
local personalTokens={}
local cookingTokens={}
local activityTokens={}
local fieldTokens={}
local custodyTokens={}
local recoveredGenerations={}
local recent={}
local function resources(record)
    local result={} for _,id in ipairs(Manifest.claimItemIds(record)) do result[#result+1]="item:"..id end return result
end
local function nativeRecords()
    local okJobs,BusinessJobs=pcall(require,'EmberRoutesProbe/BusinessJobs')
    local crafts=okJobs and BusinessJobs and BusinessJobs.legacyCrafts and BusinessJobs.legacyCrafts() or {}
    for id,r in pairs(crafts) do
	if (r.format == 1 or r.format == 2 or r.format == 3) and CraftRecord.valid and not CraftRecord.valid(id,r) then error('CRAFT_RECORD_INVALID') end
    end
    return crafts
end
local function validClaimIdFormat(claimId, entityId)
    if type(claimId) ~= "string" then return false end
    local prefix, seq = string.match(claimId, "^(.+):c(%d+)$")
    return prefix ~= nil and seq ~= nil and prefix == tostring(entityId)
end

local function nextAuthoritativeClaimId(rootTable, defaultPrefix)
    rootTable.nextClaimSeq = (rootTable.nextClaimSeq or 0) + 1
    return tostring(defaultPrefix or "claim") .. ":c" .. tostring(rootTable.nextClaimSeq)
end

local function ensureEntityClaimId(rootTable, entity, defaultPrefix)
    local entityId = (type(entity) == "table" and (entity.id or entity.taskId)) or defaultPrefix or "claim"
    if type(entity) == "table" and entity.claimId and validClaimIdFormat(entity.claimId, entityId) then
        return entity.claimId
    end
    local cid = nextAuthoritativeClaimId(rootTable, entityId)
    if type(entity) == "table" then
        entity.claimId = cid
    end
    return cid
end

function Store.data()
    local current=Registry.data()
    if current~=root then
	local data=require('EmberRoutesProbe/BusinessJobs').legacyHauls()
        local rebuilt,newTokens=Claims.new(),{}
        current.quarantineResources = current.quarantineResources or {}

        -- Pass 1: Pre-scan claims across ALL providers to detect overlapping collisions
        -- and register existing Quarantine locks with independent capacity reservations.
        for qKey, qRecord in pairs(current.quarantineResources) do
            if type(qRecord) == "table" and qRecord.status == "RESOLVING" then
                -- Crash recovery: unquarantine resolution was interrupted before commit!
                -- RESOLVING only represents intent, NOT verified settlement.
                -- Revert status to ACTIVE, preserve diagnostic trace, and KEEP QUARANTINE PROTECTED!
                qRecord.status = "ACTIVE"
                qRecord.interruptedResolution = qRecord.resolution
		qRecord.interruptedEvidence,qRecord.interruptedEvidenceReport = Evidence.snapshot(
		    qRecord.resolvingEvidence,qRecord.resolvingEvidenceReport)
                qRecord.resolution = nil
                qRecord.resolvingEvidence = nil
		qRecord.resolvingEvidenceReport = nil
                qRecord.resolvingAt = nil
                rebuilt:restoreQuarantine(qKey, qRecord)
            elseif type(qRecord) == "table" and qRecord.status == "RESOLVED" then
                -- Resolved tombstone: skip/clean from active quarantine
                current.quarantineResources[qKey] = nil
            else
                rebuilt:restoreQuarantine(qKey, type(qRecord) == "table" and qRecord or nil)
            end
        end

        -- Ensure monotonic claim sequence is initialized and preserved across cold boots
        current.nextClaimSeq = current.nextClaimSeq or 1
        rebuilt.nextClaimSeq = current.nextClaimSeq

	local function restoreClaimIdentities()
	    -- Collect the complete identity graph before acquiring ANY token. A
	    -- single-value map would let pairs/provider order choose a winner.
	    local identities, candidates = {}, {}
	    local function identity(cid, taskId, key)
		if not cid then return end
		local g = identities[cid]
		if not g then
		    g = {taskIds={}, resourceKeys={}, count=0}
		    identities[cid] = g
		end
		taskId = taskId or 'SYSTEM_QUARANTINE'
		if not g.taskIds[taskId] then g.taskIds[taskId]=true g.count=g.count+1 end
		if key then g.resourceKeys[key]=true end
            end
	    for key,q in pairs(current.quarantineResources) do
		if type(q)=='table' then identity(q.originalClaimId,q.originalTaskId,key) end
	    end
	    local function candidate(record,id,keys,job)
		candidates[#candidates+1]={record=record,id=id,keys=keys or {},job=job}
	    end
	    for id,job in pairs(current.taskJobs and current.taskJobs.byId or {}) do
		if type(job)=='table' and job.state~='DONE' and job.state~='CANCELLED' then
		    candidate(job,id,job.payload.claims,job)
		end
	    end
	    for id,entry in pairs(current.toolCustody and current.toolCustody.byId or {}) do
		if type(entry)=='table' then candidate(entry,id,entry.claims) end
	    end
	    -- Legacy adapters acquire with payload identities. Count their task ID
	    -- once even when its envelope references the same claim identity.
	    for id,r in pairs(data.tasks) do
		if type(r)=='table' and r.state~='DONE' and type(r.items)=='table' then
		    candidate(r,id,resources(r),current.taskJobs and current.taskJobs.byId[id])
		end
	    end
	    for _,r in pairs(nativeRecords()) do
		if (r.format==1 or r.format==2 or r.format==3) and not r.released then
		    candidate(r,r.id,CraftRecord.resources(r),current.taskJobs and current.taskJobs.byId[r.id])
		end
	    end
	    table.sort(candidates,function(a,b)
		if a.id==b.id then return tostring(a.record.claimId or '') < tostring(b.record.claimId or '') end
		return a.id<b.id
	    end)
	    for _,e in ipairs(candidates) do
		-- Preserve even a mismatched legacy/custody identity long enough to
		-- detect its collision. Repairing it first would erase the evidence.
		e.claimId=type(e.record.claimId)=='string' and e.record.claimId or ensureEntityClaimId(current,e.record,e.id)
		identity(e.claimId,e.id)
		for _,key in ipairs(e.keys) do identity(e.claimId,e.id,key) end
	    end
	    local collisions={}
	    for _,e in ipairs(candidates) do
		local g=identities[e.claimId]
		if g.count>1 then
		    local conflict=collisions[e.id]
		    if not conflict then
			conflict={originalTaskId=e.id,originalClaimId=e.claimId,claimIds={},taskIds={},resourceKeys={}}
			collisions[e.id]=conflict
		    end
		    if e.claimId<conflict.originalClaimId then conflict.originalClaimId=e.claimId end
		    conflict.claimIds[e.claimId]=true
		    for id in pairs(g.taskIds) do conflict.taskIds[id]=true end
		    for key in pairs(g.resourceKeys) do conflict.resourceKeys[key]=true end
		end
	    end
	    local function attachCollision(q,id,conflict)
		local facts,priorReport=Evidence.snapshot(q.evidence,q.evidenceReport)
		if type(facts)~='table' then facts={priorEvidence=facts} end
		if type(facts.identityCollisions)~='table' then
		    facts.priorIdentityCollisions=facts.identityCollisions
		    facts.identityCollisions={}
		end
		facts.identityCollisions[id]=conflict
		q.evidence,q.evidenceReport=Evidence.snapshot(facts,priorReport)
	    end
	    local replacements={}
	    for _,e in ipairs(candidates) do
		local conflict=collisions[e.id]
		if conflict then
		    local cid=replacements[e.id]
		    if not cid then
			repeat cid=nextAuthoritativeClaimId(current,e.id) until not identities[cid]
			replacements[e.id]=cid
		    end
		    e.record.claimId=cid
		    if e.job then
			e.job.claimId=cid
			e.job.state,e.job.effects='RECONCILE_REQUIRED','UNKNOWN'
			local rule=require('EmberRoutesProbe/JobContracts').get(e.job.providerType)
			if rule and rule.identityCollision then rule.identityCollision(e.job) end
		    else
			e.record.reason,e.record.uncertain='CLAIM_IDENTITY_COLLISION',true
		    end
		    -- New identity is legal; the OLD identity and all participants
		    -- remain on persistent system-owned resources. A restart cannot
		    -- turn the rekey into permission to reacquire those originals.
		    for _,key in ipairs(e.keys) do
			local q=current.quarantineResources[key]
			if not q then
			    q={status='ACTIVE',reason='CLAIM_IDENTITY_COLLISION',originalTaskId=e.id,
				originalClaimId=conflict.originalClaimId,originalGeneration=e.record.generation,evidence={}}
			    local p=e.job and e.job.payload or e.record
			    local r=p.reservation
			    local itemId=tonumber(string.match(key,'^item:(%d+)$'))
			    if itemId and r then
				local amount=r.items and r.items[itemId] or r.itemId==itemId and r.amount
				if amount then q.capacityKey,q.capacityItemId,q.capacityAmount=r.key,itemId,amount end
			    end
			    local cap=p.capacity
			    if cap and (itemId and cap.itemId==itemId or key=='cooking:capacity:'..e.id) then
				q.capacityKey,q.capacityItemId,q.capacityAmount=cap.key or cap.endpointId,
				    cap.itemId or key,cap.amount
			    end
			    current.quarantineResources[key]=q
			    rebuilt:restoreQuarantine(key,q)
			end
			attachCollision(q,e.id,conflict)
		    end
		end
	    end
	    -- Also annotate the original quarantine records, including conflicts
	    -- involving a task with no remaining resource keys of its own.
	    for id,conflict in pairs(collisions) do
		for key in pairs(conflict.resourceKeys) do
		    local q=current.quarantineResources[key]
		    if type(q)=='table' then attachCollision(q,id,conflict) end
		end
	    end

        end
	restoreClaimIdentities()

        local resourceClaimants = {}
        local conflictKeys = {}

        local function recordClaimant(key, claimantInfo)
            resourceClaimants[key] = resourceClaimants[key] or {}
            local list = resourceClaimants[key]
            local duplicate = false
            for _, existing in ipairs(list) do
                if existing.id == claimantInfo.id then
                    duplicate = true
                    break
                end
            end
            if not duplicate then
                list[#list + 1] = claimantInfo
                if #list > 1 or current.quarantineResources[key] then
                    conflictKeys[key] = true
                end
            end
        end

        for id, record in pairs(data.tasks) do
            if type(record) == "table" and record.state ~= "DONE" and type(record.items) == "table" then
                for _, itemId in ipairs(record.items) do
                    if type(itemId) == "number" and itemId == itemId and itemId ~= math.huge and itemId ~= -math.huge then
                        recordClaimant("item:" .. tostring(itemId), { kind = "HAUL_TASK", id = id, record = record })
                    end
                end
            end
        end

        for npcId, record in pairs(nativeRecords()) do
	    if type(record) == "table" and (record.format == 1 or record.format == 2 or record.format == 3) and not record.released then
                for _, key in ipairs(CraftRecord.resources(record)) do
                    if type(key) == "string" then
                        recordClaimant(key, { kind = "NATIVE_CRAFT", id = record.id, record = record })
                    end
                end
            end
        end

        if current.taskJobs and current.taskJobs.byId then
            for id, job in pairs(current.taskJobs.byId) do
                if type(job) == "table" and job.state ~= 'DONE' and job.state ~= 'CANCELLED' and type(job.payload) == 'table' and type(job.payload.claims) == 'table' then
                    for _, key in ipairs(job.payload.claims) do
                        if type(key) == "string" then
                            recordClaimant(key, { kind = "JOB", id = id, job = job })
                        end
                    end
                end
            end
        end

        if current.toolCustody and current.toolCustody.byId then
            for id, entry in pairs(current.toolCustody.byId) do
                if type(entry) == "table" and entry.state ~= 'RETURNED' and type(entry.claims) == 'table' then
                    for _, key in ipairs(entry.claims) do
                        if type(key) == "string" then
                            recordClaimant(key, { kind = "CUSTODY", id = id, entry = entry })
                        end
                    end
                end
            end
        end

        for key in pairs(conflictKeys) do
            if not current.quarantineResources[key] then
                local claimantIds = {}
                for _, c in ipairs(resourceClaimants[key] or {}) do claimantIds[#claimantIds + 1] = c.id end
                current.quarantineResources[key] = {
                    reason = "BOOT_CONFLICT",
                    evidence = { claimants = claimantIds },
                    at = (os and os.time and os.time() or 0)
                }
		local q=current.quarantineResources[key]
		q.evidence,q.evidenceReport=Evidence.snapshot(q.evidence)
            end
            rebuilt:quarantine(key)
        end

        local function hasConflict(keys)
            if not keys then return false end
            for _, k in ipairs(keys) do
                if conflictKeys[k] or current.quarantineResources[k] then return true end
            end
            return false
        end

	local legacyContext={current=current,data=data,rebuilt=rebuilt,newTokens=newTokens,hasConflict=hasConflict,ensureEntityClaimId=ensureEntityClaimId,resources=resources,nativeRecords=nativeRecords,CraftRecord=CraftRecord}
	require('EmberRoutesProbe/HaulLegacyRecovery').restore(legacyContext)
	local rebuiltNative={}
	legacyContext.rebuiltNative=rebuiltNative
	require('EmberRoutesProbe/CraftLegacyRecovery').restore(legacyContext)

        local rebuiltPersonal = {}
        local rebuiltCooking = {}
        local rebuiltActivity = {}
        local rebuiltField = {}
        local rebuiltCraft = {}
        local rebuiltHaul = {}

	-- Keep each recovery phase in its own Lua function. PZ Debug records
	-- every declared local (including expired scopes) in a 200-slot table.
	-- This synchronous phase preserves scan order and shared claim authority.
	require('EmberRoutesProbe/BuiltinLaborRecovery').install()
	require('EmberRoutesProbe/LaborRecovery').restore({current=current,rebuilt=rebuilt,hasConflict=hasConflict,ensureEntityClaimId=ensureEntityClaimId,rebuiltPersonal=rebuiltPersonal,rebuiltCooking=rebuiltCooking,rebuiltActivity=rebuiltActivity,rebuiltField=rebuiltField,rebuiltCraft=rebuiltCraft,rebuiltHaul=rebuiltHaul,newTokens=newTokens})

        local rebuiltCustody = {}
        if current.toolCustody and current.toolCustody.byId then
            local CustodyRecord = require('EmberRoutesProbe/ToolCustodyRecord')
            for id, entry in pairs(current.toolCustody.byId) do
                -- A physical PUT may already have happened. Keep the exact return
                -- identity/intent until a controlled stop and original observation.
                if not CustodyRecord.valid(entry) then error('TOOL_CUSTODY_RECORD_INVALID') end
                if hasConflict(entry.claims) then
                    entry.state = 'HELD'
                else
                    local claimId = ensureEntityClaimId(current, entry, id)
                    local token, why = rebuilt:acquire(id, entry.sequence, entry.claims, { claimId = claimId })
                    if not token then
                        entry.state = 'HELD'
                    else
                        rebuiltCustody[id] = token
                    end
                end
            end
        else
            current.toolCustody = { byId = {}, byNpc = {}, byItem = {} }
        end
        -- Publish the cache only after the entire ledger passed validation.
        local generations={}
        for id,record in pairs(data.tasks) do
            generations[id]={before=record.generation or 0,after=(record.generation or 0)+1}
            record.generation=(record.generation or 0)+1
            if record.state=="RUNNING" then record.state="PAUSED" record.reason="LOAD_RECOVERY" end
        end
        require('EmberRoutesProbe/BusinessJobs').flush()
        current.nextClaimSeq = math.max(current.nextClaimSeq or 1, rebuilt.nextClaimSeq or 1)
        root,ledger,claims,tokens=current,data,rebuilt,newTokens
        nativeTokens=rebuiltNative
        personalTokens=rebuiltPersonal
        cookingTokens=rebuiltCooking
        activityTokens=rebuiltActivity
        fieldTokens=rebuiltField
        custodyTokens=rebuiltCustody
	domainState.root,domainState.claims,domainState.tokens=root,claims,tokens
	domainState.nativeTokens,domainState.personalTokens=nativeTokens,personalTokens
	domainState.cookingTokens,domainState.activityTokens,domainState.fieldTokens=cookingTokens,activityTokens,fieldTokens
        recoveredGenerations=generations
        recent={}
    end
    return ledger
end
function Store.record(npcId)
    local data=Store.data()
    local canonical=require('EmberRoutesProbe/HaulJobs').record(npcId)
    local legacy=data.tasks[data.byNpc[npcId]]
    if legacy and legacy.state~='DONE' and (not canonical or canonical.state=='DONE') then return legacy end
    return canonical or legacy
end
-- One UI summary per current NPC, scoped to this world session; no item handles.
function Store.recent(npcId)
    Store.data()
    local saved=recent[npcId]
    if not saved then return nil end
    local copy={} for key,value in pairs(saved) do copy[key]=value end return copy
end
local function snapshotOwner(owner)
    if not owner then return nil end
    if owner.kind=='SYSTEM_QUARANTINE' then
        return {kind='SYSTEM_QUARANTINE',ownerId='SYSTEM_QUARANTINE',taskId='SYSTEM_QUARANTINE'}
    end
    local resCopy={}
    if type(owner.resources)=='table' then
        for i,r in ipairs(owner.resources) do resCopy[i]=r end
    end
    return {
        taskId=owner.taskId,
        generation=owner.generation,
        resources=resCopy,
        capacityKey=owner.capacityKey
    }
end
function Store.owner(itemId) Store.data() return snapshotOwner(claims.owners["item:"..itemId]) end
function Store.resourceOwner(key) Store.data() return snapshotOwner(claims.owners[key]) end
function Store.claimsVersion() Store.data() return claims.revision end
function Store.claimsInstance() Store.data() return claims end
local function cleanToken(jobId)
    if not jobId then return end
    if tokens then tokens[jobId] = nil end
    if nativeTokens then nativeTokens[jobId] = nil end
    if personalTokens then personalTokens[jobId] = nil end
    if cookingTokens then cookingTokens[jobId] = nil end
    if activityTokens then activityTokens[jobId] = nil end
    if fieldTokens then fieldTokens[jobId] = nil end
    if custodyTokens then custodyTokens[jobId] = nil end
    if claims and claims.tokensByTaskId then claims.tokensByTaskId[jobId] = nil end
end
function Store.getToken(jobId)
    Store.data()
    if claims.tokensByTaskId and claims.tokensByTaskId[jobId] then return claims.tokensByTaskId[jobId] end
    return tokens[jobId] or nativeTokens[jobId] or personalTokens[jobId] or cookingTokens[jobId] or activityTokens[jobId] or fieldTokens[jobId] or (custodyTokens and custodyTokens[jobId])
end
local function sealEvidenceEvents(record)
    local history
    if record.evidenceEvents~=nil then history=Evidence.snapshotEvents(record.evidenceEvents)
    else history=Evidence.appendEvent(nil,record.evidence,record.evidenceReport) end
    -- Complete the current event with its latest derived collision/recovery
    -- facts, then freeze that event before a successor is appended/archived.
    local last=history.events[#history.events]
    if last then
	last.evidence,last.report=Evidence.snapshot(record.evidence,record.evidenceReport)
	for _,pair in ipairs({{'interruptedEvidence','interruptedReport'},{'resolvingEvidence','pendingReport'}}) do
	    local field,meta=pair[1],pair[2]
	    if record[field]~=nil or record[field..'Report']~=nil then
		local destination=field=='resolvingEvidence' and 'pendingEvidence' or field
		last[destination],last[meta]=Evidence.snapshot(record[field],record[field..'Report'])
	    end
	end
    end
    return Evidence.snapshotEvents(history)
end
function Store.quarantineResource(key,reason,evidence)
    Store.data()
    local prior=root.quarantineResources and root.quarantineResources[key]
    local history=type(prior)=='table' and sealEvidenceEvents(prior) or nil
    local evidenceEvents,evidenceReport,evidenceFacts=Evidence.appendEvent(history,evidence)
    local ok, owner = claims:quarantine(key)
    if not ok then return false, "QUARANTINE_FAILED" end
    if root then
        root.quarantineResources=root.quarantineResources or {}
        root.quarantineResources[key]={
            status="ACTIVE",
            reason=reason or "UNKNOWN",
	    evidence=evidenceFacts,
	    evidenceReport=evidenceReport,
	    evidenceEvents=evidenceEvents,
            at=(os and os.time and os.time() or 0),
            originalTaskId=owner and owner.originalTaskId,
            originalClaimId=owner and owner.originalClaimId,
            originalGeneration=owner and owner.originalGeneration,
            capacityKey=owner and owner.capacityKey,
            capacityItemId=owner and owner.capacityItemId,
            capacityAmount=owner and owner.capacityAmount
        }
    end
    return true
end
-- Diagnostic/manual-reconciliation views. These never expose persisted tables,
-- migrate legacy records or authorize resource release.
function Store.quarantineRecord(key)
    Store.data()
    return Evidence.snapshotRecord(root.quarantineResources and root.quarantineResources[key])
end
function Store.quarantineAuditRecord(key)
    Store.data()
    return Evidence.snapshotRecord(root.quarantineAudit and root.quarantineAudit[key])
end
function Store.unquarantineResource(key,resolution,evidence)
    Store.data()
    local resObj = resolution
    if type(resolution) == "string" then
        resObj = { reason = resolution }
    elseif type(resolution) ~= "table" then
        resObj = {}
    end
    local evidObj = evidence
    if evidObj == nil and type(resolution) == "table" and resolution.evidence then
        evidObj = resolution.evidence
    end

    local qRec = root and root.quarantineResources and root.quarantineResources[key]
    if (not qRec) and root and root.quarantineAudit and root.quarantineAudit[key] then
        return true -- idempotent: already unquarantined and settled in audit ledger
    end
    if qRec and qRec.status=='RESOLVED' then return true end
    -- Validate BEFORE RESOLVING or any kernel mutation. Inspect legacy evidence
    -- without rewriting it. Incomplete creation/recovery requires reconciliation;
    -- clean replacement input is not permission to erase that responsibility.
    if qRec then
	local _,creationReport=Evidence.snapshot(qRec.evidence,qRec.evidenceReport)
	local _,interruptedReport=Evidence.snapshot(qRec.interruptedEvidence,qRec.interruptedEvidenceReport)
	local _,pendingReport=Evidence.snapshot(qRec.resolvingEvidence,qRec.resolvingEvidenceReport)
	if not creationReport.complete then return false,'QUARANTINE_EVIDENCE_INCOMPLETE',creationReport end
	if not interruptedReport.complete then return false,'QUARANTINE_EVIDENCE_INCOMPLETE',interruptedReport end
	if not pendingReport.complete then return false,'QUARANTINE_EVIDENCE_INCOMPLETE',pendingReport end
	local _,historyReport=Evidence.snapshotEvents(qRec.evidenceEvents)
	if not historyReport.complete then return false,'QUARANTINE_EVIDENCE_INCOMPLETE',historyReport end
    end
    local evidenceFacts,evidenceReport=Evidence.snapshot(evidObj)
    if not evidenceReport.complete then return false,'RESOLUTION_EVIDENCE_INVALID',evidenceReport end
    -- Intent and completed history own separate snapshots, even if an internal
    -- observer retains the removed quarantine record after successful release.
    local auditEvidence,auditEvidenceReport=Evidence.snapshot(evidenceFacts,evidenceReport)
    local auditEvents=qRec and sealEvidenceEvents(qRec) or nil
    -- Resolution is a runtime command and may contain a live Token. Persist a
    -- separate scalar intent/result, never the command table or its handles.
    local resolutionFacts={capacityAction=type(resObj.capacityAction)=='string' and resObj.capacityAction or 'RELEASE'}
    if type(resObj.reason)=='string' then resolutionFacts.reason=resObj.reason end
    if type(resObj.resolvedBy)=='string' then resolutionFacts.resolvedBy=resObj.resolvedBy end
    local recipient=resObj.targetToken or resObj.recipientToken
    if type(recipient)=='table' then
	if type(recipient.taskId)=='string' then resolutionFacts.recipientTaskId=recipient.taskId end
	if type(recipient.claimId)=='string' then resolutionFacts.recipientClaimId=recipient.claimId end
    end
    if qRec then
        if qRec.status == "RESOLVED" then
            return true -- idempotent
        end
        qRec.status = "RESOLVING"
	qRec.resolution = resolutionFacts
	qRec.resolvingEvidence = evidenceFacts
	qRec.resolvingEvidenceReport = evidenceReport
        qRec.resolvingAt = (os and os.time and os.time() or 0)
    end

    local ok, err = claims:unquarantine(key, resObj)
    if not ok then
        -- Failure recovery: retain persistent quarantine record and restore ACTIVE status!
        if qRec then
            qRec.status = "ACTIVE"
            qRec.resolution = nil
            qRec.resolvingEvidence = nil
	    qRec.resolvingEvidenceReport = nil
            qRec.resolvingAt = nil
        end
        return false, err or "UNQUARANTINE_FAILED"
    end

    if root and root.quarantineResources and root.quarantineResources[key] then
        local now = (os and os.time and os.time() or 0)
        root.quarantineAudit = root.quarantineAudit or {}
        root.quarantineAudit[key] = {
            action = "UNQUARANTINE",
            status = "RESOLVED",
	    resolution = resolutionFacts,
	    evidence = auditEvidence,
	    evidenceReport = auditEvidenceReport,
	    evidenceEvents = auditEvents,
            at = now,
	    capacityAction = resolutionFacts.capacityAction,
	    recipientTaskId = resolutionFacts.recipientTaskId,
	    recipientClaimId = resolutionFacts.recipientClaimId
        }
        root.quarantineResources[key] = nil
    end
    return true
end
function Store.updateJobPayload(jobId,expectedRevision,proposedPayload,mutation)
    return Store.mutateJob(jobId,expectedRevision,proposedPayload,mutation)
end
function Store.hasTaskClaims(taskId)
    Store.data()
    if nativeTokens[taskId] or tokens[taskId] or personalTokens[taskId] or cookingTokens[taskId] then return true end
    for _,token in pairs(claims.owners) do if token.taskId==taskId then return true end end
    for _,bucket in pairs(claims.capacity) do if bucket.entries[taskId] then return true end end
    return false
end
function Store.recoveryGeneration(jobId)
    Store.data() local stamp=recoveredGenerations[jobId]
    return stamp and {before=stamp.before,after=stamp.after} or nil
end
local function scopeAllowed(jobId,scopeId)
    local store=require('EmberRoutesProbe/TaskJobs').current()
    local job=store:peek(jobId)
    return not store:scopeBlocked(job and job.scopeId or scopeId or 'local-world',jobId)
end
function Store.claimNative(record)
    Store.data()
    if not CraftRecord.valid(record.npcId,record) or record.released then return nil,"CRAFT_RECORD_INVALID" end
    local other=Store.record(record.npcId)
    if other and other.state~="DONE" then return nil,"NPC_TASK_CONFLICT" end
    local saved=nativeRecords()[record.npcId]
    if saved and saved~=record and not saved.released then return nil,"OTHER_TASK_RETAINED" end
    if ledger.tasks[record.id] then return nil,"TASK_ID_DUPLICATED" end
    for _,otherRecord in pairs(nativeRecords()) do
        if otherRecord~=record and otherRecord.id==record.id then return nil,"TASK_ID_DUPLICATED" end
    end
    local claimId = ensureEntityClaimId(root, record, record.id)
    local token,reason=claims:acquire(record.id,record.generation,CraftRecord.resources(record), { claimId = claimId })
    if token then nativeTokens[record.id]=token end
    return token,reason
end
function Store.validNative(record,token,key)
    if not scopeAllowed(record.id,record.settlementId) then return false end
    Store.data()
    return nativeTokens[record.id]==token and token and token.generation==record.generation
        and nativeRecords()[record.npcId]==record and not record.released
        and (not key or claims:valid(token,key))
end
function Store.extendNative(record,token)
    Store.data()
    -- An already committed native result still belongs to its paused owner.
    -- This only records originals; it never authorizes a stale physical action.
    if nativeTokens[record.id]~=token or nativeRecords()[record.npcId]~=record
        or record.released then return false,"STALE_CLAIM" end
    return claims:extend(token,CraftRecord.resources(record))
end
function Store.finishNative(record)
    Store.data() claims:release(nativeTokens[record.id]) cleanToken(record.id)
end
function Store.replaceNative(record,token,proposed)
    Store.data()
    if not Store.validNative(record,token) or proposed.id~=record.id or proposed.generation~=record.generation
        or proposed.npcId~=record.npcId or not CraftRecord.valid(record.npcId,proposed) then return false,"STALE_CLAIM" end
    local ok,reason=claims:replace(token,CraftRecord.resources(proposed))
    if not ok then return false,reason end
    record.materials,record.tools,record.outputs=proposed.materials,proposed.tools,proposed.outputs
    record.held=proposed.held
    return true
end
function Store.claim(record)
    if record.format==3 then return require('EmberRoutesProbe/HaulJobs').claim(record) end
    Store.data()
    if record.format==2 and #Manifest.claimItemIds(record)==0
        and not (record.producer=='DELIVERY' and record.returnForNextBatch) then return nil,'HAUL_ALREADY_SETTLED' end
    local native=nativeRecords()[record.npcId]
    if native and not native.released then return nil,"OTHER_TASK_RETAINED" end
    local generation=(record.generation or 0)+1
    local claimId = ensureEntityClaimId(root, record, record.id)
    local token,reason=claims:acquire(record.id,generation,resources(record), { claimId = claimId })
    if token then record.generation=generation tokens[record.id]=token end
    return token,reason
end
-- Current shared-Job payload only; never imports pre-Job/unknown legacy data.
function Store.upgradeHaul(record,lines)
    Store.data()
    if Store.record(record.npcId)~=record or record.format~=1 or record.producer~='LOGISTICS'
        or record.controlUncertain or record.state~='PAUSED' then return false,'TASK_CHANGED' end
    local draft={} for k,v in pairs(record) do draft[k]=v end
    draft.format,draft.manifest,draft.plannedCount,draft.routeRevision,draft.attemptSequence=2,lines,#record.items,0,0
    if not Manifest.valid(draft) then return false,'TASK_RECORD_INVALID' end
    local token=tokens[record.id] local drop={}
    for _,l in ipairs(lines) do if not Manifest.pending(l) then drop[#drop+1]='item:'..l.itemId end end
    if not token or not claims:shrink(token,drop) then return false,'STALE_CLAIM' end
    record.format,record.manifest,record.plannedCount,record.routeRevision,record.attemptSequence=2,lines,#record.items,0,0
    record.delivered=Manifest.count(record)
    Store.releaseCapacity(token)
    return true
end
function Store.settleHaulLines(record,token,generation,settlements)
    if record.format==3 then return require('EmberRoutesProbe/HaulJobs').settle(record,token,generation,settlements) end
    Store.data()
    if record.format~=2 or Store.record(record.npcId)~=record or tokens[record.id]~=token
        or record.generation~=generation then return false,'STALE_CLAIM' end
    local changes,keys,seen={},{},{}
    for _,s in ipairs(settlements) do
        local l=Manifest.line(record,s.itemId)
        if not l or seen[s.itemId] or (s.state~='DELIVERED' and s.state~='WITHDRAWN') then return false,'SETTLEMENT_INVALID' end
        seen[s.itemId]=true
        if Manifest.pending(l) then
            if s.state=='WITHDRAWN' and (l.custodyState~='UNCOLLECTED' or record.activeAttempt and record.activeAttempt.itemId==s.itemId)
                or s.state=='DELIVERED' and (not s.receipt or not s.receipt.attemptId or not s.receipt.destinationId) then return false,'SETTLEMENT_INVALID' end
            changes[#changes+1]={line=l,change=s} keys[#keys+1]='item:'..s.itemId
        elseif l.custodyState~=s.state then return false,'SETTLEMENT_CHANGED' end
    end
    local ok,why=claims:shrink(token,keys) if not ok then return false,why end
    for _,row in ipairs(changes) do
        local l,s=row.line,row.change l.custodyState=s.state l.deliveryReceipt=s.receipt
        local reservation=record.reservation
        if reservation and reservation.format==2 then reservation.items[s.itemId]=nil end
    end
    if not token.capacityKey then record.reservation=nil end
    record.delivered,record.withdrawn=Manifest.count(record)
    return true
end
function Store.publish(record)
    if record.format==3 then return require('EmberRoutesProbe/HaulJobs').commit(record) end
    local data=Store.data() local previous=Store.record(record.npcId)
    local native=nativeRecords()[record.npcId]
    if native and not native.released then return false,"OTHER_TASK_RETAINED" end
    if previous and previous~=record then
        if previous.state~="DONE" then return false,"TASK_EXISTS_RESUME_OR_CLEAR" end
        claims:release(tokens[previous.id]) tokens[previous.id]=nil
    end
    return require('EmberRoutesProbe/BusinessJobs').publishHaul(record)
end
function Store.valid(record,generation,token)
    if not scopeAllowed(record.id,record.settlementId) then return false end
    if record.format==3 then return require('EmberRoutesProbe/HaulJobs').valid(record,generation,token) end
    return Store.record(record.npcId)==record and record.state=="RUNNING" and record.generation==generation
        and tokens[record.id]==token
end
function Store.pause(record)
    local token=Store.claim(record) return token
end
function Store.capacity(token,itemId,key,amount,free)
    Store.data()
    local j=token and root.taskJobs.byId[token.taskId]
    if j and j.providerType=='HAUL' and j.payload.format==3 and j.payload.executor=='ENTITY' then
	local r=require('EmberRoutesProbe/HaulJobs').record(j.npcId)
	return require('EmberRoutesProbe/HaulJobs').capacity(r,key,{[itemId]=amount},free)
    end
    Store.data() local ok,reason=claims:reserve(token,key,itemId,amount,free)
    if ok then
        local record=ledger.tasks[token.taskId] local previous=record.reservation
        local reservation=previous and previous.format==2 and previous or {format=2,key=key,items={}}
        if previous and previous.itemId then reservation.items[previous.itemId]=previous.amount end
        reservation.items[itemId]=amount record.reservation=reservation
    end
    return ok,reason
end
function Store.releaseCapacity(token,itemId)
    Store.data()
    local j=token and root.taskJobs.byId[token.taskId]
    if j and j.providerType=='HAUL' and j.payload.format==3 and j.payload.executor=='ENTITY' then
	local r=require('EmberRoutesProbe/HaulJobs').record(j.npcId)
	return require('EmberRoutesProbe/HaulJobs').releaseCapacity(r,itemId)
    end
    Store.data() if not token then return end
    claims:releaseCapacity(token,itemId)
    local record=ledger.tasks[token.taskId]
    if record and tokens[token.taskId]==token then
        local reservation=record.reservation
        if not itemId then record.reservation=nil
        elseif reservation and reservation.format==2 then
            reservation.items[itemId]=nil
            local empty=true for _ in pairs(reservation.items) do empty=false break end
            if empty then record.reservation=nil end
        elseif reservation and reservation.itemId==itemId then record.reservation=nil end
    end
end
function Store.availableCapacity(key,free) Store.data() return claims:available(key,free) end
function Store.availableFor(token,key,itemId,free) Store.data() return claims:availableFor(token,key,itemId,free) end
function Store.capacityBatch(token,key,weights,free)
    Store.data()
    local j=token and root.taskJobs.byId[token.taskId]
    if j and j.providerType=='HAUL' and j.payload.format==3 and j.payload.executor=='ENTITY' then
	local r=require('EmberRoutesProbe/HaulJobs').record(j.npcId)
	return require('EmberRoutesProbe/HaulJobs').capacity(r,key,weights,free)
    end
    Store.data() local ok,reason=claims:reserveMany(token,key,weights,free)
    if ok then
        local copy={} for id,amount in pairs(weights) do copy[id]=amount end
        ledger.tasks[token.taskId].reservation={format=2,key=key,items=copy}
    end
    return ok,reason
end
function Store.finish(record)
    if record.format==3 then
	local ok,why=require('EmberRoutesProbe/HaulJobs').finish(record)
	if ok and record.producer=='LOGISTICS' and record.delivered==#record.items then recent[record.npcId]={id=record.id,settlementId=record.settlementId,sourceMode=record.sourceMode,delivered=record.delivered,total=#record.items} end
	return ok,why
    end
    Store.data()
    if record.state=="DONE" and record.producer=="LOGISTICS" and record.delivered==#record.items then
        recent[record.npcId]={id=record.id,settlementId=record.settlementId,sourceMode=record.sourceMode,
            delivered=record.delivered,total=#record.items}
    end
    claims:release(tokens[record.id]) cleanToken(record.id) record.reservation=nil record.generation=(record.generation or 0)+1
    return true
end
function Store.clear(npcId)
    local record=Store.record(npcId) if not record then return true end
    if record.format==3 then
	-- Absence from the carrier is not source/receipt proof. A paused draft
	-- with outstanding originals cannot be discarded by this legacy command.
	if record.activeAttempt or record.controlUncertain or #Manifest.claimItemIds(record)>0 then return false,'HAUL_OBLIGATION_RETAINED' end
	local ok,why=Store.finish(record)
	if not ok then return false,why end
	recent[npcId]=nil return true
    end
    Store.finish(record) record.state='DONE' record.reason='CLEARED'
    require('EmberRoutesProbe/BusinessJobs').removeHaul(record)
    require('EmberRoutesProbe/BusinessJobs').flush()
    recent[npcId]=nil
    return true
end
function Store.route(npcId)
    local data=Store.data() local route=data.routes[npcId]
    if not route then
        route={}
        if npcId~="" then
            route=data.unassignedRoute or data.routes[""] or route
            data.unassignedRoute=nil data.routes[""]=nil
        end
        data.routes[npcId]=route
    end
    return route
end
function Store.canClaimTool(npcId,itemId)
    Store.data()
    npcId=tostring(npcId)
    local key='item:'..itemId
    local owner=claims.owners[key]
    if not owner then return true end
    if root.toolCustody and root.toolCustody.byItem then
        local c=root.toolCustody.byItem[itemId]
        if c and tostring(c.npcId)==npcId and owner.taskId==c.id
            and (c.state=='HELD' or c.state=='RESERVED') then return true end
    end
    return false
end
function Store.validToolUse(npcId,jobId,itemId)
    Store.data()
    npcId=tostring(npcId)
    local key='item:'..itemId
    local owner=claims.owners[key]
    if not owner then return false end
    if owner.taskId==jobId then return true end
    if root.toolCustody and root.toolCustody.byItem then
        local c=root.toolCustody.byItem[itemId]
        if c and tostring(c.npcId)==npcId and owner.taskId==c.id and c.activeJobId==jobId
            and (c.state=='HELD' or c.state=='RESERVED') then
            return true
        end
    end
    return false
end
function Store.claimCustody(npcId,itemId,role,sourceContainerId,activeJobId)
    Store.data()
    npcId=tostring(npcId)
    local custodyStore=root.toolCustody
    if not custodyStore then
        custodyStore={byId={},byNpc={},byItem={}}
        root.toolCustody=custodyStore
    end
    local custodyId='custody:'..npcId..':'..itemId
    local existing=custodyStore.byId[custodyId]
    if existing then
        if existing.state~='HELD' and existing.state~='RESERVED' then return nil,'TOOL_CUSTODY_UNRESOLVED' end
        if existing.activeJobId and existing.activeJobId~=activeJobId then
            return nil,'TOOL_ALREADY_ASSIGNED'
        end
        existing.activeJobId=activeJobId
        return existing
    end
    local entry={
        format=1,
        id=custodyId,
        npcId=npcId,
        itemId=itemId,
        role=role,
        state='RESERVED',
        sequence=1,
        activeJobId=activeJobId,
        sourceContainerId=sourceContainerId,
        claims={'item:'..itemId}
    }
    if not require('EmberRoutesProbe/ToolCustodyRecord').valid(entry) then
        return nil,'TOOL_CUSTODY_INVALID'
    end
    local claimId = ensureEntityClaimId(root, entry, custodyId)
    local token,why=claims:acquire(custodyId,entry.sequence,entry.claims, { claimId = claimId })
    if not token then return nil,why or 'TOOL_CLAIM_CONFLICT' end
    custodyTokens[custodyId]=token
    custodyStore.byId[custodyId]=entry
    custodyStore.byNpc[npcId]=custodyStore.byNpc[npcId] or {}
    custodyStore.byNpc[npcId][custodyId]=entry
    custodyStore.byItem[itemId]=entry
    return entry
end
function Store.releaseCustody(custodyId)
    Store.data()
    local custodyStore=root.toolCustody
    if not custodyStore or not custodyStore.byId then return false end
    local entry=custodyStore.byId[custodyId]
    if not entry then return false end
    local token=custodyTokens[custodyId]
    if token then
        claims:release(token)
        custodyTokens[custodyId]=nil
    end
    custodyStore.byId[custodyId]=nil
    if custodyStore.byNpc[entry.npcId] then
        custodyStore.byNpc[entry.npcId][custodyId]=nil
    end
    custodyStore.byItem[entry.itemId]=nil
    return true
end
function Store.assignToolUse(custodyId,jobId)
    Store.data()
    local custodyStore=root.toolCustody
    local entry=custodyStore and custodyStore.byId and custodyStore.byId[custodyId]
    if not entry then return false,'CUSTODY_NOT_FOUND' end
    if entry.state~='HELD' and entry.state~='RESERVED' then return false,'TOOL_CUSTODY_UNRESOLVED' end
    entry.activeJobId=jobId
    return true
end
function Store.custodyForNpc(npcId)
    Store.data()
    npcId=tostring(npcId)
    local result={}
    local custodyStore=root.toolCustody
    if custodyStore and custodyStore.byNpc and custodyStore.byNpc[npcId] then
        for _,entry in pairs(custodyStore.byNpc[npcId]) do
            result[#result+1]=entry
        end
    end
    return result
end
function Store.custodyByItem(itemId)
    Store.data()
    return root.toolCustody and root.toolCustody.byItem and root.toolCustody.byItem[itemId] or nil
end
function Store.assignToolReturn(custodyId,returnJobId,intent)
    Store.data()
    local custodyStore=root.toolCustody
    local entry=custodyStore and custodyStore.byId and custodyStore.byId[custodyId]
    if not entry then return false,'CUSTODY_NOT_FOUND' end
    if entry.state~='HELD' and entry.state~='RESERVED' then return false,'INVALID_CUSTODY_STATE' end
    if entry.returnJobId and entry.returnJobId~=returnJobId then return false,'ALREADY_RETURNING' end
    if intent~=nil and (type(intent)~='table' or intent.format~=1 or intent.jobId~=returnJobId
        or type(intent.destinationId)~='string' or intent.destinationId==''
        or type(intent.scopeId)~='string' or intent.scopeId=='') then return false,'RETURN_INTENT_INVALID' end
    entry.returnIntent=intent and {format=1,jobId=returnJobId,destinationId=intent.destinationId,scopeId=intent.scopeId} or nil
    entry.state='PENDING_RETURN'
    entry.returnJobId=returnJobId
    entry.activeJobId=nil
    return true,entry
end
function Store.abortToolReturn(custodyId,returnJobId)
    Store.data()
    local custodyStore=root.toolCustody
    local entry=custodyStore and custodyStore.byId and custodyStore.byId[custodyId]
    if not entry then return false,'CUSTODY_NOT_FOUND' end
    if entry.returnJobId==returnJobId and (entry.state=='PENDING_RETURN'
        or entry.state=='RECONCILE_REQUIRED' and entry.returnIntent~=nil) then
        entry.state='HELD'
        entry.returnJobId=nil
        entry.returnIntent=nil
        return true
    end
    return false,'NOT_IN_RETURN_STATE'
end
function Store.completeCustodyReturn(custodyId,returnJobId,destinationId,item)
    Store.data()
    local custodyStore=root.toolCustody
    local entry=custodyStore and custodyStore.byId and custodyStore.byId[custodyId]
    if not entry then return false,'CUSTODY_NOT_FOUND' end
    if entry.returnJobId~=returnJobId or (entry.state~='PENDING_RETURN'
        and not (entry.state=='RECONCILE_REQUIRED' and entry.returnIntent~=nil)) then
        return false,'RETURN_JOB_MISMATCH'
    end
    if entry.returnIntent and entry.returnIntent.destinationId~=destinationId then return false,'RETURN_DESTINATION_CHANGED' end
    if not item or item:getID()~=entry.itemId then
        return false,'RETURN_ITEM_MISMATCH'
    end
    local Registry=require('EmberRoutesProbe/ContainerRegistry')
    local endpoint=Registry.resolve(destinationId,'put','local-world')
    if not endpoint or not endpoint.container or not Registry.revalidate(endpoint,'put','local-world')
        or Registry.logistics(endpoint)~='STORAGE' then
        return false,'DESTINATION_NOT_RESOLVED'
    end
    local container=endpoint.container
    if item:getContainer()~=container or not container:getItems():contains(item) then
        return false,'ITEM_NOT_IN_DESTINATION'
    end
    local token=custodyTokens[custodyId]
    if token then
        claims:release(token)
        custodyTokens[custodyId]=nil
    end
    custodyStore.byId[custodyId]=nil
    if custodyStore.byNpc[entry.npcId] then
        custodyStore.byNpc[entry.npcId][custodyId]=nil
    end
    custodyStore.byItem[entry.itemId]=nil
    Registry.inventoryChanged(container)
    return true
end
function Store.markNpcCustodiesDead(npcId)
    Store.data()
    npcId=tostring(npcId)
    local list=Store.custodyForNpc(npcId)
    for _,c in ipairs(list) do
        c.state='DEAD_CARRIER'
        c.activeJobId=nil
        c.returnJobId=nil
    end
    return #list
end
require('EmberRoutesProbe/LaborJobCommit').install(Store,domainState,nextAuthoritativeClaimId,cleanToken)
require('EmberRoutesProbe/LaborDomainAdapters').install(Store,domainState,ensureEntityClaimId,cleanToken,scopeAllowed)
return Store
