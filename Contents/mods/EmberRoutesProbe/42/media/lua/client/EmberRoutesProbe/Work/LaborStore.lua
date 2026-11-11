local Registry=require "EmberRoutesProbe/Warehouse/ContainerRegistry"
local JobState=require 'EmberRoutesProbe/Kernel/JobState'
local Templates=require 'EmberRoutesProbe/Kernel/ModDataTemplates'
local Claims=require "EmberRoutesProbe/Kernel/LaborClaims"
local CraftRetirement=require "EmberRoutesProbe/Crafting/CraftLegacyRecovery"
local Manifest=require 'EmberRoutesProbe/Hauling/HaulManifest'
local Evidence=require 'EmberRoutesProbe/Warehouse/QuarantineEvidence'
local Store={}
local root,claims,tokens
local domainState={}
local personalTokens={}
local cookingTokens={}
local activityTokens={}
local fieldTokens={}
local custodyTokens={}
local recoveredGenerations={}
local recent={}
local function legacyRecords()
    return CraftRetirement.records(Registry.data())
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
        local rebuilt,newTokens=Claims.new(),{}
        local pendingHaul={}
        local pendingPersonal={}
        -- Domain recoveries that only need a forced state/effects write. They are
        -- collected here and applied through JobStore:adopt after root and token
        -- caches are published, so no recovery path writes a live Job record.
        local pendingAdopt={}
        -- Missing root fields take the template values; the version itself was
        -- already gated by the Registry load entry.
        Templates.fill(current,Templates.templates.workLabor)

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
		if type(job)=='table' and not JobState.isTerminal(job.state) then
		    candidate(job,id,job.payload.claims,job)
		end
	    end
	    for id,entry in pairs(current.toolCustody and current.toolCustody.byId or {}) do
		if type(entry)=='table' then candidate(entry,id,entry.claims) end
	    end
	    for id,r in pairs(legacyRecords()) do
		if CraftRetirement.retained(r,current.taskJobs.byId[id]) then
		    candidate(r,id,CraftRetirement.resources(r),current.taskJobs and current.taskJobs.byId[id])
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
			local rule=require('EmberRoutesProbe/Kernel/JobContracts').get(e.job.providerType)
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

        for id, record in pairs(legacyRecords()) do
	    if CraftRetirement.retained(record,current.taskJobs.byId[id]) then
                for _, key in ipairs(CraftRetirement.resources(record)) do
                    if type(key) == "string" then
                        recordClaimant(key, { kind = "NATIVE_CRAFT", id = id, record = record })
                    end
                end
            end
        end

        if current.taskJobs and current.taskJobs.byId then
            for id, job in pairs(current.taskJobs.byId) do
                if type(job) == "table" and not JobState.isTerminal(job.state) and type(job.payload) == 'table' and type(job.payload.claims) == 'table' then
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

        CraftRetirement.restore({current=current,rebuilt=rebuilt,newTokens=newTokens,
            hasConflict=hasConflict,ensureEntityClaimId=ensureEntityClaimId})

        local rebuiltPersonal = {}
        local rebuiltCooking = {}
        local rebuiltActivity = {}
        local rebuiltField = {}
        local rebuiltCraft = {}
        local rebuiltHaul = {}

	-- Keep each recovery phase in its own Lua function. PZ Debug records
	-- every declared local (including expired scopes) in a 200-slot table.
	-- This synchronous phase preserves scan order and shared claim authority.
	require('EmberRoutesProbe/Work/BuiltinLaborRecovery').install()
	require('EmberRoutesProbe/Work/LaborRecovery').restore({pendingPersonal=pendingPersonal,pendingAdopt=pendingAdopt,
	queueAdopt=function(jobId,patch) pendingAdopt[#pendingAdopt+1]={id=jobId,patch=patch} end,
	pendingHaul=pendingHaul,current=current,rebuilt=rebuilt,hasConflict=hasConflict,ensureEntityClaimId=ensureEntityClaimId,rebuiltPersonal=rebuiltPersonal,rebuiltCooking=rebuiltCooking,rebuiltActivity=rebuiltActivity,rebuiltField=rebuiltField,rebuiltCraft=rebuiltCraft,rebuiltHaul=rebuiltHaul,newTokens=newTokens})

        local rebuiltCustody = {}
        local custodyByNpc,custodyByItem={},{}
        -- The custody document carries its own version key. A missing table is
        -- created from the template; a wrong version, or a non-empty table
        -- without one, is refused with an explicit code instead of being
        -- silently replaced by an empty document.
        local custody=current.toolCustody
        if custody==nil then
            custody=Templates.fresh('toolCustody') current.toolCustody=custody
        else
            local okCustody,whyCustody=Templates.open(custody,Templates.templates.toolCustody,'TOOL_CUSTODY_FORMAT_UNSUPPORTED')
            if not okCustody then error(whyCustody) end
            if type(custody.byId)~='table' then error('TOOL_CUSTODY_FORMAT_UNSUPPORTED') end
        end
        do
            local CustodyRecord = require('EmberRoutesProbe/Field/ToolCustodyRecord')
            for id, entry in pairs(custody.byId) do
                -- A physical PUT may already have happened. Keep the exact return
                -- identity/intent until a controlled stop and original observation.
                if not CustodyRecord.valid(entry) or entry.id~=id or custodyByItem[entry.itemId] then
                    error('TOOL_CUSTODY_RECORD_INVALID')
                end
                -- Only byId owns custody. Serialization need not preserve aliases
                -- in the two persisted lookup caches; rebuild them before use.
                local npcId=tostring(entry.npcId)
                custodyByNpc[npcId]=custodyByNpc[npcId] or {}
                custodyByNpc[npcId][id]=entry custodyByItem[entry.itemId]=entry
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
        end
        current.toolCustody.byNpc,current.toolCustody.byItem=custodyByNpc,custodyByItem
        -- Publish the cache only after the entire ledger passed validation.
        current.nextClaimSeq = math.max(current.nextClaimSeq or 1, rebuilt.nextClaimSeq or 1)
        root,claims,tokens=current,rebuilt,newTokens
        personalTokens=rebuiltPersonal
        cookingTokens=rebuiltCooking
        activityTokens=rebuiltActivity
        fieldTokens=rebuiltField
        custodyTokens=rebuiltCustody
	domainState.root,domainState.claims,domainState.tokens=root,claims,tokens
	domainState.personalTokens=personalTokens
	domainState.cookingTokens,domainState.activityTokens,domainState.fieldTokens=cookingTokens,activityTokens,fieldTokens
        recoveredGenerations={}
        recent={}
        -- Invocation-local ordered cold-recovery work, NOT a persistent recovery
        -- queue. Root and all token caches are published before any kernel call.
        -- SELF_CARE's cold proposals are invocation-local, not saved receipts.
        -- A rejected published commit stops recovery; reload the saved world.
        for _,intent in ipairs(pendingPersonal) do
            local ok,why,evidence=require('EmberRoutesProbe/SelfCare/SelfCareCommit').update(
                intent.id,intent.revision,intent.patch)
            if not ok then error('PERSONAL_COLD_RECOVERY_FAILED:'..tostring(why)..':'..tostring(evidence)) end
            if intent.release then
                local token=Store.getToken(intent.id)
                if token then claims:release(token) end
                tokens[intent.id]=nil personalTokens[intent.id]=nil
                claims.tokensByTaskId[intent.id]=nil
            end
        end
        domainState.haulRecoveryFailures={}
        for _,intent in ipairs(pendingHaul) do
            local job=require('EmberRoutesProbe/Runtime/TaskJobs').current():get(intent.id)
            local ok,why,evidence=Store.mutateJob(intent.id,intent.revision,job.payload,
                {state='RECONCILE_REQUIRED',effects='UNKNOWN'})
            if ok and intent.failedToken then
                -- Same pre-existing failed-reconstruction release, only after CAS.
                -- Persistent claims remain on UNKNOWN Job for diagnosis/rebuild.
                rebuilt:release(intent.failedToken)
            elseif not ok then
                domainState.haulRecoveryFailures[#domainState.haulRecoveryFailures+1]={
                    id=intent.id,reason=intent.reason,error=why,evidence=evidence}
            end
        end
        -- Forced cold-recovery writes. Applied last, after every token cache and
        -- the rebuilt authority are published, so adopt() sees the final record.
        -- A rejected adopt stops recovery: a half-adopted world must be reloaded.
        if #pendingAdopt>0 then
            local jobs=require('EmberRoutesProbe/Runtime/TaskJobs').current()
            for _,intent in ipairs(pendingAdopt) do
                local ok,why=jobs:adopt(intent.id,intent.patch)
                if not ok then error('COLD_ADOPT_FAILED:'..tostring(why)..':'..tostring(intent.id)) end
            end
        end
    end
    return root
end
-- Load/rebuild trigger for callers that need LaborStore published but do not
-- need the root table itself. Store.data() still returns the raw root for the
-- load entry's own use; cross-domain callers must use this or another named
-- entry instead of indexing the returned table.
function Store.ensureLoaded() Store.data() end
function Store.haulRecoveryDiagnosis() return domainState.haulRecoveryFailures end
function Store.record(npcId)
    Store.data()
    return require('EmberRoutesProbe/Hauling/HaulJobs').record(npcId)
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
-- Production read for HaulJobs: snapshot copy of one job's reserved items in
-- one capacity bucket (nil when the bucket/entry holds nothing). Callers get
-- a copy, never the live claims table.
function Store.capacityEntries(key, jobId)
    Store.data()
    if not key or not jobId then return nil end
    local bucket=claims.capacity and claims.capacity[key]
    local entry=bucket and bucket.entries and bucket.entries[jobId]
    local items=entry and entry.items
    if not items then return nil end
    local copy={} for id,amount in pairs(items) do copy[id]=amount end return copy
end
-- Production read for the Java delivery bridge: the live owners table.
-- Java (deliverySelectSlice) reads only; Lua side must never write through
-- it. Use Store.owner(itemId)/Store.resourceOwner(key) for Lua-side reads.
function Store.claimOwners() Store.data() return claims.owners end
-- Production read for custody displays and providers: detached shallow
-- copies of every custody record, sorted by id. Callers get copies, never
-- the live toolCustody.byId map.
function Store.custodyEntries()
    Store.data()
    local result={}
    local custodyStore=root.toolCustody
    if custodyStore and custodyStore.byId then
        for _,entry in pairs(custodyStore.byId) do
            local copy={} for key,value in pairs(entry) do copy[key]=value end
            result[#result+1]=copy
        end
    end
    table.sort(result,function(a,b) return a.id<b.id end)
    return result
end
-- Production read for providers that only need to know whether any custody
-- exists at all (no allocation, no record exposure).
function Store.hasCustody()
    Store.data()
    local custodyStore=root.toolCustody
    return custodyStore~=nil and custodyStore.byId~=nil and next(custodyStore.byId)~=nil or false
end
-- Test-only narrow entries. The raw claims instance used to be exposed here
-- (claimsInstanceForTests); tests now use these instead, so no caller outside
-- LaborStore can read or write the live owners/capacity tables, acquire or
-- release tokens, or compare instance identity directly.
function Store.capacityTotalForTests(key)
    Store.data()
    local bucket=key and claims.capacity and claims.capacity[key]
    return bucket and bucket.total or nil
end
function Store.nextClaimSeqForTests()
    Store.data()
    return root.nextClaimSeq
end
function Store.acquireForTests(taskId,generation,keys)
    Store.data()
    return claims:acquire(taskId,generation,keys)
end
function Store.acquireNewForTests(taskId,generation,keys)
    Store.data()
    return claims:acquireNew(taskId,generation,keys)
end
function Store.releaseTokenForTests(token)
    Store.data()
    claims:release(token)
    return true
end
function Store.canShrinkForTests(token,keys)
    Store.data()
    return claims:canShrink(token,keys)
end
function Store.shrinkForTests(token,keys)
    Store.data()
    return claims:shrink(token,keys)
end
-- Memory-only fault injection: drops one owner from claims memory without
-- touching the persisted quarantine record, to simulate the inconsistency a
-- failed release must survive.
function Store.dropOwnerForTests(key)
    Store.data()
    claims.owners[key]=nil
    return true
end
-- Memory-only fault injection: installs a caller-supplied owner record for
-- one key, to simulate a later owner arriving between a CAS check and a
-- shrink. The table is stored as given; production code never sees it.
function Store.setOwnerForTests(key,owner)
    Store.data()
    claims.owners[key]=owner
    return true
end
-- Identity probe without exposing the object: the live claims table's address
-- string is unique among live objects, so a cold boot that builds a fresh
-- instance yields a different id while the old instance is still referenced.
function Store.claimsInstanceIdForTests() Store.data() return tostring(claims) end
function Store.restoreQuarantineForTests(key,record)
    Store.data()
    return claims:restoreQuarantine(key,record or (root.quarantineResources and root.quarantineResources[key]))
end
-- Deliberate malformed-world fixture: rewrites the persisted record's
-- original participant so the next cold boot must detect the collision.
-- Not an application mutation API.
function Store.setQuarantineOriginalTaskForTests(key,originalTaskId)
    Store.data()
    local q=root.quarantineResources and root.quarantineResources[key]
    if not q then return false end
    q.originalTaskId=originalTaskId
    return true
end
function Store.quarantineKeysForTests()
    Store.data()
    local result={}
    if root.quarantineResources then
        for key in pairs(root.quarantineResources) do result[#result+1]=key end
    end
    table.sort(result)
    return result
end
local function cleanToken(jobId)
    if not jobId then return end
    if tokens then tokens[jobId] = nil end
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
    return tokens[jobId] or personalTokens[jobId] or cookingTokens[jobId] or activityTokens[jobId] or fieldTokens[jobId] or (custodyTokens and custodyTokens[jobId])
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
function Store.hasTaskClaims(taskId)
    Store.data()
    if tokens[taskId] or personalTokens[taskId] or cookingTokens[taskId] then return true end
    for _,token in pairs(claims.owners) do if token.taskId==taskId then return true end end
    for _,bucket in pairs(claims.capacity) do if bucket.entries[taskId] then return true end end
    return false
end
function Store.recoveryGeneration(jobId)
    Store.data() local stamp=recoveredGenerations[jobId]
    return stamp and {before=stamp.before,after=stamp.after} or nil
end
local function scopeAllowed(jobId,scopeId)
    local store=require('EmberRoutesProbe/Runtime/TaskJobs').current()
    local job=store:peek(jobId)
    return not store:scopeBlocked(job and job.scopeId or scopeId or 'local-world',jobId)
end
function Store.claim(record)
    if record.format==3 then return require('EmberRoutesProbe/Hauling/HaulJobs').claim(record) end
    return nil,'TASK_FORMAT_UNSUPPORTED'
end
function Store.settleHaulLines(record,token,generation,settlements)
    if record.format==3 then return require('EmberRoutesProbe/Hauling/HaulJobs').settle(record,token,generation,settlements) end
    return false,'TASK_FORMAT_UNSUPPORTED'
end
function Store.publish(record)
    if record.format==3 then return require('EmberRoutesProbe/Hauling/HaulJobs').commit(record) end
    return false,'TASK_FORMAT_UNSUPPORTED'
end
function Store.valid(record,generation,token)
    if not scopeAllowed(record.id,record.settlementId) then return false end
    if record.format==3 then return require('EmberRoutesProbe/Hauling/HaulJobs').valid(record,generation,token) end
    return false
end
function Store.pause(record)
    local token=Store.claim(record) return token
end
function Store.capacity(token,itemId,key,amount,free)
    Store.data()
    local j=token and root.taskJobs.byId[token.taskId]
    if j and j.providerType=='HAUL' and j.payload.format==3 and j.payload.executor=='ENTITY' then
	local r=require('EmberRoutesProbe/Hauling/HaulJobs').record(j.npcId)
	return require('EmberRoutesProbe/Hauling/HaulJobs').capacity(r,key,{[itemId]=amount},free)
    end
    return claims:reserve(token,key,itemId,amount,free)
end
function Store.releaseCapacity(token,itemId)
    Store.data()
    local j=token and root.taskJobs.byId[token.taskId]
    if j and j.providerType=='HAUL' and j.payload.format==3 and j.payload.executor=='ENTITY' then
	local r=require('EmberRoutesProbe/Hauling/HaulJobs').record(j.npcId)
	return require('EmberRoutesProbe/Hauling/HaulJobs').releaseCapacity(r,itemId)
    end
    if not token then return end
    claims:releaseCapacity(token,itemId)
end
function Store.availableCapacity(key,free) Store.data() return claims:available(key,free) end
function Store.availableFor(token,key,itemId,free) Store.data() return claims:availableFor(token,key,itemId,free) end
function Store.finish(record)
    if record.format==3 then
	local ok,why=require('EmberRoutesProbe/Hauling/HaulJobs').finish(record)
	if ok and record.producer=='LOGISTICS' and record.delivered==#record.items then recent[record.npcId]={id=record.id,settlementId=record.settlementId,sourceMode=record.sourceMode,delivered=record.delivered,total=#record.items} end
	return ok,why
    end
    return false,'TASK_FORMAT_UNSUPPORTED'
end
function Store.clear(npcId)
    local record=Store.record(npcId) if not record then return true end
    if record.format~=3 then return false,'TASK_FORMAT_UNSUPPORTED' end
    -- Absence from the carrier is not source/receipt proof. A paused draft
    -- with outstanding originals cannot be discarded by this command.
    if record.activeAttempt or record.controlUncertain or #Manifest.claimItemIds(record)>0 then return false,'HAUL_OBLIGATION_RETAINED' end
    local ok,why=Store.finish(record)
    if not ok then return false,why end
    recent[npcId]=nil return true
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
        custodyStore=Templates.fresh('toolCustody')
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
    if not require('EmberRoutesProbe/Field/ToolCustodyRecord').valid(entry) then
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
    local Registry=require('EmberRoutesProbe/Warehouse/ContainerRegistry')
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
-- Death is a custody settlement, not a state: a dead carrier's custodies can
-- never transition again (no recovery path consumes them), so keeping their
-- item claims would brick those tools for every future worker. Release them;
-- the physical items are unaffected and become claimable again if they ever
-- re-enter a container or inventory scan.
function Store.settleNpcDeath(npcId)
    Store.data()
    npcId=tostring(npcId)
    local list=Store.custodyForNpc(npcId)
    local released=0
    for _,c in ipairs(list) do if Store.releaseCustody(c.id) then released=released+1 end end
    return released
end
require('EmberRoutesProbe/Work/LaborJobCommit').install(Store,domainState,nextAuthoritativeClaimId,cleanToken)
require('EmberRoutesProbe/Work/LaborDomainAdapters').install(Store,domainState,ensureEntityClaimId,cleanToken,scopeAllowed)
return Store
