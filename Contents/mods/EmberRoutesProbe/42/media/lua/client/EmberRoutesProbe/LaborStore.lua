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
local recoveredGenerations={}
local recent={}
local function resources(record)
    local result={} for _,id in ipairs(Manifest.claimItemIds(record)) do result[#result+1]="item:"..id end return result
end
local function nativeRecords()
    local okJobs,BusinessJobs=pcall(require,'EmberRoutesProbe/BusinessJobs')
    local crafts=okJobs and BusinessJobs and BusinessJobs.crafts and BusinessJobs.crafts() or {}
    for id,r in pairs(crafts) do
        if CraftRecord.valid and not CraftRecord.valid(id,r) then error('CRAFT_RECORD_INVALID') end
    end
    return crafts
end
function Store.data()
    local current=Registry.data()
    if current~=root then
        local data=require('EmberRoutesProbe/BusinessJobs').hauls()
        local rebuilt,newTokens=Claims.new(),{}
        for id,record in pairs(data.tasks) do
            if type(record)~="table" or type(id)~="string" or record.id~=id or type(record.npcId)~="string"
                or (record.state~='DONE' and data.byNpc[record.npcId]~=id) or (record.format~=1 and not Manifest.valid(record)) or record.kind~="EXPLICIT_TRANSFER"
                or record.executor~="ENTITY" or record.scopeId~="local-world" or type(record.items)~="table"
                or #record.items>30 or (record.state~="RUNNING" and record.state~="PAUSED" and record.state~="DONE")
                or (record.generation and (type(record.generation)~="number" or record.generation<0
                    or record.generation~=math.floor(record.generation) or record.generation==math.huge)) then error("TASK_RECORD_INVALID") end
            for _,itemId in ipairs(record.items) do
                if type(itemId)~="number" or itemId~=itemId or itemId==math.huge or itemId==-math.huge then error("TASK_ITEM_INVALID") end
            end
            local resourceKeys=resources(record)
            if record.state~="DONE" and #resourceKeys>0 then
                local token=rebuilt:acquire(id,(record.generation or 0)+1,resourceKeys)
                if not token then error("TASK_CLAIM_CONFLICT") end newTokens[id]=token
                local r=record.reservation
                if r then
                    if type(r)~="table" then error("TASK_RESERVATION_INVALID") end
                    if r.format==2 and type(r.items)=="table" then
                        for itemId,amount in pairs(r.items) do
                            if not rebuilt:restore(token,r.key,itemId,amount) then error("TASK_RESERVATION_INVALID") end
                        end
                    elseif r.format~=nil or not rebuilt:restore(token,r.key,r.itemId,r.amount) then error("TASK_RESERVATION_INVALID") end
                end
            end
        end
        for npcId,id in pairs(data.byNpc) do
            if not data.tasks[id] or data.tasks[id].npcId~=npcId then error("TASK_INDEX_INVALID") end
        end
        local rebuiltNative={}
        for npcId,record in pairs(nativeRecords()) do
            if not record.released then
                local other=data.tasks[data.byNpc[npcId]]
                if other and other.state~="DONE" then error("NPC_TASK_CONFLICT") end
                local token=rebuilt:acquire(record.id,record.generation,CraftRecord.resources(record))
                if not token or newTokens[record.id] or rebuiltNative[record.id] then error("CRAFT_CLAIM_CONFLICT") end
                rebuiltNative[record.id]=token
            end
        end
        local rebuiltPersonal={}
        for id,job in pairs(current.taskJobs.byId) do
            if job.providerType=='SELF_CARE' then
                if not require('EmberRoutesProbe/SelfCareRecord').valid(job) then error('PERSONAL_RECORD_INVALID') end
                if #job.payload.claims>0 then
                    local token,reason=rebuilt:acquire(id,job.payload.sequence,job.payload.claims)
                    if not token then error(reason) end
                    rebuiltPersonal[id]=token
                end
            end
        end
        local rebuiltCooking={}
        for id,job in pairs(current.taskJobs.byId) do
            if job.providerType=='COOKING' then
                if not require('EmberRoutesProbe/CookingRecord').valid(job) then error('COOKING_RECORD_INVALID') end
                if #job.payload.claims>0 then
                    local token,reason=rebuilt:acquire(id,job.payload.sequence,job.payload.claims)
                    if not token then error(reason or 'COOKING_CLAIM_CONFLICT') end
                    local cap=job.payload.capacity
                    if cap and not rebuilt:restoreWork(token,cap.endpointId,cap.amount) then error('COOKING_CAPACITY_INVALID') end
                    rebuiltCooking[id]=token
                end
            end
        end
        local rebuiltActivity={}
        for id,job in pairs(current.taskJobs.byId) do
            if job.providerType=='ACTIVITY' then
                if not require('EmberRoutesProbe/ActivityRecord').valid(job) then error('ACTIVITY_RECORD_INVALID') end
                if #job.payload.claims>0 then
                    local token,reason=rebuilt:acquire(id,job.payload.sequence,job.payload.claims)
                    if not token then error(reason or 'ACTIVITY_CLAIM_CONFLICT') end
                    rebuiltActivity[id]=token
                end
            end
        end
        local rebuiltField={}
        for id,job in pairs(current.taskJobs.byId) do
            if job.providerType=='FIELD_WORK' then
                if not require('EmberRoutesProbe/FieldRecord').valid(job) then error('FIELD_RECORD_INVALID') end
                local token,why=rebuilt:acquire(id,job.payload.sequence,job.payload.claims)
                if not token then error(why or 'FIELD_CLAIM_CONFLICT') end
                rebuiltField[id]=token
                local cap=job.payload.capacity
                if cap and not rebuilt:restore(token,cap.key,cap.itemId,cap.amount) then error('FIELD_CAPACITY_INVALID') end
            end
        end
        -- Publish the cache only after the entire ledger passed validation.
        local generations={}
        for id,record in pairs(data.tasks) do
            generations[id]={before=record.generation or 0,after=(record.generation or 0)+1}
            record.generation=(record.generation or 0)+1
            if record.state=="RUNNING" then record.state="PAUSED" record.reason="LOAD_RECOVERY" end
        end
        require('EmberRoutesProbe/BusinessJobs').flush()
        root,ledger,claims,tokens=current,data,rebuilt,newTokens
        nativeTokens=rebuiltNative
        personalTokens=rebuiltPersonal
        cookingTokens=rebuiltCooking
        activityTokens=rebuiltActivity
        fieldTokens=rebuiltField
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
function Store.owner(itemId) Store.data() return claims.owners["item:"..itemId] end
function Store.resourceOwner(key) Store.data() return claims.owners[key] end
-- Cheap observation fence, including ordinary hauling/crafting/personal claims.
-- Identity also changes after a world/ledger rebuild. Not a second asset ledger.
function Store.claimsVersion() Store.data() return claims,claims.revision end
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
    local token,why=claims:acquire(saved.id,saved.payload.sequence,saved.payload.claims)
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
    cookingTokens[job.id]=assert(claims:acquire(job.id,saved.payload.sequence,saved.payload.claims))
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
    local nextToken=assert(claims:acquire(job.id,saved.payload.sequence,saved.payload.claims))
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
    claims:release(token) cookingTokens[job.id]=nil return true
end
function Store.claimPersonal(job)
    Store.data()
    local saved=root.taskJobs.byId[job.id]
    if not require('EmberRoutesProbe/SelfCareRecord').valid(saved)
        or saved.npcId~=job.npcId or saved.payload.attemptId~=job.payload.attemptId
        or saved.payload.sequence~=job.payload.sequence then return nil,'STALE_PERSONAL_ATTEMPT' end
    local token,reason=claims:acquire(job.id,job.payload.sequence,saved.payload.claims)
    if token then personalTokens[job.id]=token end
    return token,reason
end
function Store.claimActivity(job)
    Store.data()
    local saved=root.taskJobs.byId[job.id]
    if not require('EmberRoutesProbe/ActivityRecord').valid(saved) or saved.npcId~=job.npcId
        or saved.effects~='KNOWN' or saved.payload.sequence~=job.payload.sequence then return nil,'STALE_ACTIVITY_ATTEMPT' end
    local token,why=claims:acquire(job.id,job.payload.sequence,saved.payload.claims)
    if token then activityTokens[job.id]=token end return token,why
end
-- Field adapters share this same resource authority with cooking/haul/care.
function Store.claimField(job)
    Store.data()
    local saved=root.taskJobs.byId[job.id]
    if not saved or saved.providerType~='FIELD_WORK' or saved.revision~=job.revision then return nil,'FIELD_JOB_CHANGED' end
    local token,why=claims:acquire(job.id,saved.payload.sequence,saved.payload.claims)
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
    if token then claims:release(token) fieldTokens[job.id]=nil end
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
    claims:release(token) activityTokens[job.id]=nil return true
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
    claims:release(token) personalTokens[job.id]=nil return true
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
    local token,reason=claims:acquire(record.id,record.generation,CraftRecord.resources(record))
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
    Store.data() claims:release(nativeTokens[record.id]) nativeTokens[record.id]=nil
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
    local token,reason=claims:acquire(record.id,generation,resources(record))
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
    claims:release(tokens[record.id]) tokens[record.id]=nil record.reservation=nil record.generation=(record.generation or 0)+1
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
return Store
