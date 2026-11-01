local Registry=require "EmberRoutesProbe/ContainerRegistry"
local Claims=require "EmberRoutesProbe/LaborClaims"
local CraftRecord=require "EmberRoutesProbe/CraftRecord"
local Manifest=require 'EmberRoutesProbe/HaulManifest'
local Store={}
local root,ledger,claims,tokens
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
    local crafts=okJobs and BusinessJobs and BusinessJobs.crafts and BusinessJobs.crafts() or {}
    for id,r in pairs(crafts) do
        if r.format == 3 and CraftRecord.valid and not CraftRecord.valid(id,r) then error('CRAFT_RECORD_INVALID') end
    end
    return crafts
end
local function nextAuthoritativeClaimId(rootTable, defaultPrefix)
    rootTable.nextClaimSeq = (rootTable.nextClaimSeq or 0) + 1
    return tostring(defaultPrefix or "claim") .. ":c" .. tostring(rootTable.nextClaimSeq)
end

local function ensureEntityClaimId(rootTable, entity, defaultPrefix)
    if type(entity) == "table" and entity.claimId then
        return entity.claimId
    end
    local cid = nextAuthoritativeClaimId(rootTable, defaultPrefix or (type(entity) == "table" and entity.id) or "claim")
    if type(entity) == "table" then
        entity.claimId = cid
    end
    return cid
end

function Store.data()
    local current=Registry.data()
    if current~=root then
        local data=require('EmberRoutesProbe/BusinessJobs').hauls()
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
                qRecord.interruptedEvidence = qRecord.resolvingEvidence
                qRecord.resolution = nil
                qRecord.resolvingEvidence = nil
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
            if type(record) == "table" and record.format == 3 and not record.released then
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

        local rebuiltNative = {}
        for npcId, record in pairs(nativeRecords()) do
            if record.format == 3 and not record.released then
                local other = data.tasks[data.byNpc[npcId]]
                if other and other.state ~= "DONE" then
                    record.released = true
                else
                    local resKeys = CraftRecord.resources(record)
                    if hasConflict(resKeys) then
                        record.released = true
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

        local rebuiltPersonal = {}
        local rebuiltCooking = {}
        local rebuiltActivity = {}
        local rebuiltField = {}
        local rebuiltCraft = {}
        local rebuiltHaul = {}

        if current.taskJobs and current.taskJobs.byId then
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

            for id, job in pairs(current.taskJobs.byId) do
                if job.providerType == 'ACTIVITY' then
                    if not require('EmberRoutesProbe/ActivityRecord').valid(job) then error('ACTIVITY_RECORD_INVALID') end
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
                                rebuiltActivity[id] = token
                            end
                        end
                    end
                end
            end

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

            for id, job in pairs(current.taskJobs.byId) do
                if job.providerType == 'CRAFT' and job.payload and job.payload.format == 4 then
                    if not require('EmberRoutesProbe/CraftJobRecord').valid(job) then error('CRAFT_JOB_RECORD_INVALID') end
                    if #job.payload.claims > 0 and job.state ~= 'DONE' and job.state ~= 'CANCELLED' then
                        if hasConflict(job.payload.claims) then
                            job.state = 'RECONCILE_REQUIRED'
                            job.effects = 'UNKNOWN'
                        else
                            local claimId = ensureEntityClaimId(current, job, id)
                            local token, reason = rebuilt:acquire(id, job.payload.sequence or 0, job.payload.claims, { claimId = claimId })
                            if not token then
                                job.state = 'RECONCILE_REQUIRED'
                                job.effects = 'UNKNOWN'
                            else
                                rebuiltCraft[id] = token
                                newTokens[id] = token
                            end
                        end
                    end
                end
            end

            for id, job in pairs(current.taskJobs.byId) do
                if job.providerType == 'HAUL' and job.payload and (job.payload.format == 3 or job.payload.format == 1) then
                    if newTokens[id] then
                        rebuiltHaul[id] = newTokens[id]
                    else
                        local isValid = false
                        if job.payload.format == 3 then
                            isValid = require('EmberRoutesProbe/HaulJobRecord').valid(job)
                        elseif job.payload.format == 1 then
                            local p = job.payload
                            isValid = type(p) == 'table' and type(p.items) == 'table' and type(p.source) == 'string' and type(p.destination) == 'string'
                        end
                        if not isValid then
                            job.state = 'RECONCILE_REQUIRED'
                            job.effects = 'UNKNOWN'
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
                                    job.state = 'RECONCILE_REQUIRED'
                                    job.effects = 'UNKNOWN'
                                else
                                    local claimId = ensureEntityClaimId(current, job, id)
                                    local token, reason = rebuilt:acquire(id, job.payload.sequence or 0, claimKeys, { claimId = claimId })
                                    if not token then
                                        job.state = 'RECONCILE_REQUIRED'
                                        job.effects = 'UNKNOWN'
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
                                            job.state = 'RECONCILE_REQUIRED'
                                            job.effects = 'UNKNOWN'
                                            rebuilt:release(token)
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

        local rebuiltCustody = {}
        if current.toolCustody and current.toolCustody.byId then
            local CustodyRecord = require('EmberRoutesProbe/ToolCustodyRecord')
            for id, entry in pairs(current.toolCustody.byId) do
                if entry.state == 'PENDING_RETURN' then
                    entry.state = 'HELD'
                    entry.returnJobId = nil
                end
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
        recoveredGenerations=generations
        recent={}
    end
    return ledger
end
function Store.record(npcId)
    local data=Store.data() return data.tasks[data.byNpc[npcId]]
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
function Store.quarantineResource(key,reason,evidence)
    Store.data()
    local ok, owner = claims:quarantine(key)
    if not ok then return false, "QUARANTINE_FAILED" end
    if root then
        root.quarantineResources=root.quarantineResources or {}
        root.quarantineResources[key]={
            status="ACTIVE",
            reason=reason or "UNKNOWN",
            evidence=evidence,
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
    if qRec then
        if qRec.status == "RESOLVED" then
            return true -- idempotent
        end
        qRec.status = "RESOLVING"
        qRec.resolution = resObj
        qRec.resolvingEvidence = evidObj
        qRec.resolvingAt = (os and os.time and os.time() or 0)
    end

    local ok, err = claims:unquarantine(key, resObj)
    if not ok then
        -- Failure recovery: retain persistent quarantine record and restore ACTIVE status!
        if qRec then
            qRec.status = "ACTIVE"
            qRec.resolution = nil
            qRec.resolvingEvidence = nil
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
            resolution = resObj,
            evidence = evidObj,
            at = now,
            capacityAction = resObj.capacityAction or "RELEASE",
            recipientTaskId = (resObj.targetToken or resObj.recipientToken) and (resObj.targetToken or resObj.recipientToken).taskId
        }
        root.quarantineResources[key] = nil
    end
    return true
end
function Store.createClaimedJob(job)
    local JobStore=require('EmberRoutesProbe/JobStore')
    if not JobStore.validate(job) or job.state~='PREPARING' or job.revision~=1 then
        return false,'INVALID_JOB_ENVELOPE'
    end
    Store.data()
    -- Allocate persistent non-reusable claimId at the authoritative root level:
    -- NEVER allow external caller to inject arbitrary/old claimId!
    local persistentClaimId = nextAuthoritativeClaimId(root, job.id)
    job.claimId = persistentClaimId
    if claims then claims.nextClaimSeq = math.max(claims.nextClaimSeq or 1, root.nextClaimSeq + 1) end

    local p=job.payload
    local keys=p.claims or {}
    local token,why=claims:acquireNew(job.id,p.sequence or job.generation or 0,keys,job)
    if not token then return false,'CLAIMS_ACQUIRE_FAILED:'..tostring(why) end
    if p.reservation and type(p.reservation)=='table' then
        local r=p.reservation
        if type(r.items)=='table' then
            for itemId,amt in pairs(r.items) do
                local okRes=claims:reserve(token,r.key,itemId,amt,r.free)
                if not okRes then
                    claims:release(token)
                    return false,'CAPACITY_RESERVE_FAILED'
                end
            end
        elseif r.itemId and r.amount then
            local okRes=claims:reserve(token,r.key,r.itemId,r.amount,r.free)
            if not okRes then
                claims:release(token)
                return false,'CAPACITY_RESERVE_FAILED'
            end
        end
    end
    local TaskJobs=require('EmberRoutesProbe/TaskJobs')
    local store=TaskJobs.current()
    local ok,err=store:create(job)
    if not ok then
        claims:release(token)
        return false,'JOB_CREATE_FAILED_ROLLED_BACK:'..tostring(err)
    end
    tokens[job.id] = token
    if job.providerType == 'COOKING' then cookingTokens[job.id] = token
    elseif job.providerType == 'FIELD_WORK' then fieldTokens[job.id] = token
    elseif job.providerType == 'SELF_CARE' then personalTokens[job.id] = token
    elseif job.providerType == 'ACTIVITY' then activityTokens[job.id] = token
    end
    return true, job.id
end
function Store.mutateJob(jobId, expectedRevision, proposedPayload, mutation)
    Store.data()
    local TaskJobs = require('EmberRoutesProbe/TaskJobs')
    local store = TaskJobs.current()
    local job = store:get(jobId)
    if not job or job.revision ~= expectedRevision then return false, 'STALE_REVISION' end
    local token = Store.getToken(jobId)
    if not token then return false, 'NO_RUNTIME_TOKEN' end
    if type(proposedPayload) ~= 'table' then return false, 'PROPOSED_PAYLOAD_INVALID' end

    local addKeys = mutation and mutation.addKeys
    local removeKeys = mutation and mutation.removeKeys

    -- 1. Mutually exclusive validation: addKeys ∩ removeKeys must be empty
    if addKeys and removeKeys and #addKeys > 0 and #removeKeys > 0 then
        local removeSet = {}
        for _, k in ipairs(removeKeys) do removeSet[k] = true end
        for _, k in ipairs(addKeys) do
            if removeSet[k] then
                return false, 'MUTATION_KEYS_MUTUALLY_EXCLUSIVE_VIOLATION'
            end
        end
    end

    -- 2. Reject addKeys containing resources already held by this token
    if addKeys and #addKeys > 0 then
        local currentOwned = {}
        for _, k in ipairs(token.resources or {}) do currentOwned[k] = true end
        for _, k in ipairs(addKeys) do
            if currentOwned[k] then
                return false, 'ADD_KEYS_ALREADY_OWNED'
            end
        end
    end

    -- 3. Verify addKeys / removeKeys and proposedPayload.claims consistency
    if proposedPayload.claims ~= nil then
        local expectedClaims = {}
        for _, k in ipairs(token.resources or {}) do expectedClaims[k] = true end
        if removeKeys then
            for _, k in ipairs(removeKeys) do expectedClaims[k] = nil end
        end
        if addKeys then
            for _, k in ipairs(addKeys) do expectedClaims[k] = true end
        end

        local proposedSet = {}
        for _, k in ipairs(proposedPayload.claims) do
            if proposedSet[k] then return false, 'RESOURCE_DUPLICATED' end
            proposedSet[k] = true
        end
        for k in pairs(expectedClaims) do
            if not proposedSet[k] then return false, 'CLAIMS_PAYLOAD_MISMATCH' end
        end
        for k in pairs(proposedSet) do
            if not expectedClaims[k] then return false, 'CLAIMS_PAYLOAD_MISMATCH' end
        end
    end

    -- 4. Preflight shrink BEFORE any CAS or key extension
    if removeKeys and #removeKeys > 0 then
        local okCanShrink, whyCanShrink = claims:canShrink(token, removeKeys)
        if not okCanShrink then
            return false, 'SHRINK_FAILED:' .. tostring(whyCanShrink)
        end
    end

    -- 5. Extend addKeys
    if addKeys and #addKeys > 0 then
        local okExt, whyExt = claims:extend(token, addKeys)
        if not okExt then return false, 'EXTEND_FAILED:' .. tostring(whyExt) end
    end

    -- 6. CAS store:update
    local patch = { payload = proposedPayload }
    if mutation and mutation.state then patch.state = mutation.state end
    if mutation and mutation.effects then patch.effects = mutation.effects end
    if mutation and mutation.obligations then patch.obligations = mutation.obligations end
    local okCAS, nextRev = store:update(jobId, expectedRevision, patch)
    if not okCAS then
        if addKeys and #addKeys > 0 then
            for _, addKey in ipairs(addKeys) do
                Store.quarantineResource(addKey, "CAS_FAILED", {
                    jobId = jobId,
                    rev = expectedRevision,
                    why = tostring(nextRev)
                })
            end
        end
        store:update(jobId, expectedRevision, { state = 'RECONCILE_REQUIRED', effects = 'UNKNOWN' })
        return false, 'CAS_FAILED_ISOLATED:' .. tostring(nextRev)
    end

    -- 7. Shrink removeKeys post-CAS
    if removeKeys and #removeKeys > 0 then
        local okShrink, whyShrink = claims:shrink(token, removeKeys)
        if not okShrink then
            for _, remKey in ipairs(removeKeys) do
                Store.quarantineResource(remKey, "SHRINK_POST_CAS_FAIL", {
                    jobId = jobId,
                    rev = nextRev,
                    why = tostring(whyShrink)
                })
            end
            store:update(jobId, nextRev, { state = 'RECONCILE_REQUIRED', effects = 'UNKNOWN' })
            return false, 'SHRINK_FAILED_ISOLATED:' .. tostring(whyShrink)
        end
    end

    -- 8. Terminal cleanup
    if patch.state == 'DONE' or patch.state == 'CANCELLED' then
        claims:release(token)
        cleanToken(jobId)
    end
    return true, nextRev
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
-- Ordinary cooking Jobs share the same resource graph as hauling/crafting/care.
function Store.claimCooking(job)
    Store.data()
    local saved=root.taskJobs.byId[job.id]
    if not require('EmberRoutesProbe/CookingRecord').valid(saved) or saved.npcId~=job.npcId
        or saved.revision~=job.revision or saved.payload.phase=='SETTLED' then return nil,'COOKING_JOB_CHANGED' end
    local claimId = ensureEntityClaimId(root, saved, saved.id)
    local token,why=claims:acquire(saved.id,saved.payload.sequence,saved.payload.claims, { claimId = claimId })
    if token then cookingTokens[saved.id]=token end
    return token,why
end
function Store.transferCooking(job,token,npcId)
    if not Store.validCooking(job,token) then return nil,'COOKING_JOB_CHANGED' end
    local proposed,why=require('EmberRoutesProbe/CookingRecord').handoff(job,npcId)
    if not proposed then return nil,why end
    local jobs=require('EmberRoutesProbe/TaskJobs').current()
    local ok,reason=jobs:transferCooking(job.id,job.revision,proposed)
    if not ok then return nil,reason end
    -- Same Job/resource set throughout. Old callbacks fail revision/NPC/token checks.
    local saved=jobs:get(job.id)
    local claimId = ensureEntityClaimId(root, saved, saved.id)
    cookingTokens[job.id]=assert(claims:acquire(job.id,saved.payload.sequence,saved.payload.claims, { claimId = claimId }))
    return saved
end
function Store.validCooking(job,token,key)
    Store.data()
    local saved=root.taskJobs.byId[job.id]
    return saved and saved.providerType=='COOKING' and saved.npcId==job.npcId and saved.revision==job.revision
        and token and cookingTokens[job.id]==token and token.generation==saved.payload.sequence
        and (not key or claims:valid(token,key)) or false
end
function Store.replaceCooking(job,token,proposed)
    if not Store.validCooking(job,token) or proposed.id~=job.id or proposed.npcId~=job.npcId
        or proposed.scopeId~=job.scopeId or proposed.revision~=job.revision
        or not require('EmberRoutesProbe/CookingRecord').valid(proposed) then return false,'COOKING_JOB_CHANGED' end
    local old={} for _,key in ipairs(token.resources) do old[#old+1]=key end
    -- Pure coordination, no yield or native effect between replace and publish.
    -- Conflict rejection leaves both the durable Job and all old owners intact.
    local ok,reason=claims:replace(token,proposed.payload.claims)
    if not ok then return false,reason end
    local beforeCap,afterCap=job.payload.capacity,proposed.payload.capacity
    local capacityChanged=(beforeCap and beforeCap.endpointId)~=(afterCap and afterCap.endpointId)
        or (beforeCap and beforeCap.amount)~=(afterCap and afterCap.amount)
    if capacityChanged then
        claims:releaseCapacity(token)
        if afterCap and not claims:restoreWork(token,afterCap.endpointId,afterCap.amount) then
            assert(claims:replace(token,old),'COOKING_CLAIM_ROLLBACK_FAILED')
            if beforeCap then assert(claims:restoreWork(token,beforeCap.endpointId,beforeCap.amount)) end
            return false,'COOKING_CAPACITY_INVALID'
        end
    end
    local jobs=require('EmberRoutesProbe/TaskJobs').current()
    local changed,why=jobs:update(job.id,job.revision,{payload=proposed.payload,effects=proposed.effects,
        obligations=proposed.obligations,state=proposed.state})
    if not changed then
        if capacityChanged then claims:releaseCapacity(token) end
        assert(claims:replace(token,old),'COOKING_CLAIM_ROLLBACK_FAILED')
        if capacityChanged and beforeCap then assert(claims:restoreWork(token,beforeCap.endpointId,beforeCap.amount)) end
        return false,why
    end
    local saved=jobs:get(job.id)
    local claimId = ensureEntityClaimId(root, saved, saved.id)
    local nextToken=assert(claims:acquire(job.id,saved.payload.sequence,saved.payload.claims, { claimId = claimId }))
    cookingTokens[job.id]=nextToken
    return true,saved,nextToken
end
function Store.availableCooking(job,token,key,free)
    if not Store.validCooking(job,token) then return 0 end
    return claims:availableWork(token,key,free)
end
function Store.finishCooking(job,token)
    if not Store.validCooking(job,token) then return false,'COOKING_JOB_CHANGED' end
    local saved=root.taskJobs.byId[job.id]
    if not require('EmberRoutesProbe/CookingRecord').valid(saved) or saved.payload.phase~='SETTLED'
        or saved.effects~='KNOWN' or #saved.payload.claims>0 then return false,'COOKING_OBLIGATION_RETAINED' end
    claims:release(token) cleanToken(job.id) return true
end
function Store.claimPersonal(job)
    Store.data()
    local saved=root.taskJobs.byId[job.id]
    if not require('EmberRoutesProbe/SelfCareRecord').valid(saved)
        or saved.npcId~=job.npcId or saved.payload.attemptId~=job.payload.attemptId
        or saved.payload.sequence~=job.payload.sequence then return nil,'STALE_PERSONAL_ATTEMPT' end
    local claimId = ensureEntityClaimId(root, saved, job.id)
    local token,reason=claims:acquire(job.id,job.payload.sequence,saved.payload.claims, { claimId = claimId })
    if token then personalTokens[job.id]=token end
    return token,reason
end
function Store.claimActivity(job)
    Store.data()
    local saved=root.taskJobs.byId[job.id]
    if not require('EmberRoutesProbe/ActivityRecord').valid(saved) or saved.npcId~=job.npcId
        or saved.effects~='KNOWN' or saved.payload.sequence~=job.payload.sequence then return nil,'STALE_ACTIVITY_ATTEMPT' end
    local claimId = ensureEntityClaimId(root, saved, job.id)
    local token,why=claims:acquire(job.id,job.payload.sequence,saved.payload.claims, { claimId = claimId })
    if token then activityTokens[job.id]=token end return token,why
end
-- Field adapters share this same resource authority with cooking/haul/care.
function Store.claimField(job)
    Store.data()
    local saved=root.taskJobs.byId[job.id]
    if not saved or saved.providerType~='FIELD_WORK' or saved.revision~=job.revision then return nil,'FIELD_JOB_CHANGED' end
    local claimId = ensureEntityClaimId(root, saved, job.id)
    local token,why=claims:acquire(job.id,saved.payload.sequence,saved.payload.claims, { claimId = claimId })
    if token then fieldTokens[job.id]=token end
    return token,why
end
function Store.validField(job,token,key)
    Store.data() local saved=root.taskJobs.byId[job.id]
    return saved and saved.providerType=='FIELD_WORK' and saved.revision==job.revision
        and fieldTokens[job.id]==token and token~=nil and (not key or claims:valid(token,key)) or false
end
function Store.replaceField(job,token,proposed)
    if not Store.validField(job,token) or not require('EmberRoutesProbe/FieldRecord').valid(proposed) then return false,'FIELD_JOB_CHANGED' end
    local old=job.payload.claims
    local ok,why=claims:replace(token,proposed.payload.claims)
    if not ok then return false,why end
    local jobs=require('EmberRoutesProbe/TaskJobs').current()
    ok,why=jobs:update(job.id,job.revision,{state=proposed.state,effects=proposed.effects,
        obligations=proposed.obligations,payload=proposed.payload})
    if not ok then assert(claims:replace(token,old),'FIELD_CLAIM_ROLLBACK_FAILED') return false,why end
    return true,jobs:get(job.id)
end
function Store.reserveField(job,token,key,itemId,amount,free)
    if not Store.validField(job,token) then return false,'FIELD_JOB_CHANGED' end
    return claims:reserve(token,key,itemId,amount,free)
end
function Store.finishField(job)
    Store.data() local saved=root.taskJobs.byId[job.id]
    if not saved or saved.providerType~='FIELD_WORK' or saved.effects~='KNOWN'
        or (saved.state~='DONE' and saved.state~='CANCELLED') or #saved.payload.claims>0 then return false end
    for _ in pairs(saved.obligations) do return false end
    local token=fieldTokens[job.id]
    if token then claims:release(token) cleanToken(job.id) end
    if root.toolCustody and root.toolCustody.byId then
        for _,c in pairs(root.toolCustody.byId) do
            if c.activeJobId==job.id then c.activeJobId=nil end
        end
    end
    return true
end
function Store.validActivity(job,token)
    Store.data() local saved=root.taskJobs.byId[job.id]
    return saved and token and activityTokens[job.id]==token and token.generation==saved.payload.sequence
        and saved.npcId==job.npcId and saved.payload.sequence==job.payload.sequence or false
end
function Store.finishActivity(job,token)
    if not Store.validActivity(job,token) then return false,'STALE_ACTIVITY_ATTEMPT' end
    local saved=root.taskJobs.byId[job.id]
    if saved.effects~='KNOWN' then return false,'ACTIVITY_EFFECT_UNKNOWN' end
    for _ in pairs(saved.obligations) do return false,'ACTIVITY_OBLIGATION_RETAINED' end
    local p={} for k,v in pairs(saved.payload) do p[k]=v end p.claims={}
    if not require('EmberRoutesProbe/TaskJobs').current():update(job.id,saved.revision,{payload=p}) then return false,'JOB_CHANGED' end
    claims:release(token) cleanToken(job.id) return true
end
function Store.validPersonal(job,token,key)
    Store.data()
    local saved=root.taskJobs.byId[job.id]
    return saved and saved.npcId==job.npcId and saved.payload.attemptId==job.payload.attemptId
        and token and personalTokens[job.id]==token and token.generation==saved.payload.sequence
        and (not key or claims:valid(token,key)) or false
end
function Store.finishPersonal(job,token)
    if not Store.validPersonal(job,token) then return false,'STALE_PERSONAL_ATTEMPT' end
    local saved=root.taskJobs.byId[job.id]
    if saved.effects~='KNOWN' then return false,'PERSONAL_EFFECT_UNKNOWN' end
    for _ in pairs(saved.obligations) do return false,'PERSONAL_OBLIGATION_RETAINED' end
    local jobs=require('EmberRoutesProbe/TaskJobs').current()
    local payload=jobs:get(job.id).payload payload.claims={}
    local ok,reason=jobs:update(job.id,saved.revision,{payload=payload})
    if not ok then return false,reason end
    claims:release(token) cleanToken(job.id) return true
end
-- Only release furniture keys after the caller has physical exit evidence.
-- Item custody remains exactly as declared in the same Job.
function Store.releasePersonalSeats(job,token)
    if not Store.validPersonal(job,token) then return false,'STALE_PERSONAL_ATTEMPT' end
    local saved=root.taskJobs.byId[job.id]
    local keep={} local present={}
    for _,key in ipairs(saved.payload.claims) do keep[#keep+1]=key present[key]=true end
    for _,key in ipairs(token.resources) do
        if not present[key] and string.sub(key,1,7)~='repose:' then return false,'ITEM_CLAIM_RETAINED' end
    end
    return claims:replace(token,keep)
end
function Store.extendPersonal(job,token)
    if not Store.validPersonal(job,token) then return false,'STALE_PERSONAL_ATTEMPT' end
    -- Publish native outputs before extending the in-memory claim. A conflict
    -- retains the durable declaration for reconciliation, never deletes output.
    return claims:extend(token,root.taskJobs.byId[job.id].payload.claims)
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
    return Store.record(record.npcId)==record and record.state=="RUNNING" and record.generation==generation
        and tokens[record.id]==token
end
function Store.pause(record)
    local token=Store.claim(record) return token
end
function Store.capacity(token,itemId,key,amount,free)
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
    Store.data() local ok,reason=claims:reserveMany(token,key,weights,free)
    if ok then
        local copy={} for id,amount in pairs(weights) do copy[id]=amount end
        ledger.tasks[token.taskId].reservation={format=2,key=key,items=copy}
    end
    return ok,reason
end
function Store.finish(record)
    Store.data()
    if record.state=="DONE" and record.producer=="LOGISTICS" and record.delivered==#record.items then
        recent[record.npcId]={id=record.id,settlementId=record.settlementId,sourceMode=record.sourceMode,
            delivered=record.delivered,total=#record.items}
    end
    claims:release(tokens[record.id]) cleanToken(record.id) record.reservation=nil record.generation=(record.generation or 0)+1
end
function Store.clear(npcId)
    local record=Store.record(npcId) if not record then return end
    Store.finish(record) record.state='DONE' record.reason='CLEARED'
    require('EmberRoutesProbe/BusinessJobs').removeHaul(record)
    require('EmberRoutesProbe/BusinessJobs').flush()
    recent[npcId]=nil
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
        if c and tostring(c.npcId)==npcId and owner.taskId==c.id then return true end
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
        if c and tostring(c.npcId)==npcId and owner.taskId==c.id and c.activeJobId==jobId and c.state~='PENDING_RETURN' then
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
function Store.assignToolReturn(custodyId,returnJobId)
    Store.data()
    local custodyStore=root.toolCustody
    local entry=custodyStore and custodyStore.byId and custodyStore.byId[custodyId]
    if not entry then return false,'CUSTODY_NOT_FOUND' end
    if entry.state~='HELD' and entry.state~='RESERVED' then return false,'INVALID_CUSTODY_STATE' end
    if entry.returnJobId and entry.returnJobId~=returnJobId then return false,'ALREADY_RETURNING' end
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
    if entry.returnJobId==returnJobId and entry.state=='PENDING_RETURN' then
        entry.state='HELD'
        entry.returnJobId=nil
        return true
    end
    return false,'NOT_IN_RETURN_STATE'
end
function Store.completeCustodyReturn(custodyId,returnJobId,destinationId,item)
    Store.data()
    local custodyStore=root.toolCustody
    local entry=custodyStore and custodyStore.byId and custodyStore.byId[custodyId]
    if not entry then return false,'CUSTODY_NOT_FOUND' end
    if entry.returnJobId~=returnJobId or entry.state~='PENDING_RETURN' then
        return false,'RETURN_JOB_MISMATCH'
    end
    if not item or item:getID()~=entry.itemId then
        return false,'RETURN_ITEM_MISMATCH'
    end
    local Registry=require('EmberRoutesProbe/ContainerRegistry')
    local endpoint=Registry.resolve(destinationId,'put','local-world')
    if not endpoint or not endpoint.container then
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
return Store
