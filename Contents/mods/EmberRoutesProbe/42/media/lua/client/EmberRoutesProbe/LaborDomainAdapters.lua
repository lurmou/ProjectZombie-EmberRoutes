-- Domain-specific execution adapters over the existing owner's tables.
-- No world loop, authority, token cache or persistent root is created here.
local A={}
function A.install(Store,state,ensureEntityClaimId,cleanToken,scopeAllowed)
-- Ordinary cooking Jobs share the same resource graph as hauling/crafting/care.
function Store.claimCooking(job)
    Store.data()
    local saved=state.root.taskJobs.byId[job.id]
    if not require('EmberRoutesProbe/CookingRecord').valid(saved) or saved.npcId~=job.npcId
	or saved.revision~=job.revision or saved.payload.phase=='SETTLED' then return nil,'COOKING_JOB_CHANGED' end
    local claimId = ensureEntityClaimId(state.root, saved, saved.id)
    local token,why=state.claims:acquire(saved.id,saved.payload.sequence,saved.payload.claims, { claimId = claimId })
    if token then state.cookingTokens[saved.id]=token end
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
    local claimId = ensureEntityClaimId(state.root, saved, saved.id)
    state.cookingTokens[job.id]=assert(state.claims:acquire(job.id,saved.payload.sequence,saved.payload.claims, { claimId = claimId }))
    return saved
end
-- Side-effect-free scope admission; own unresolved Job may only use its
-- existing business guards (e.g. return originals), never replay native craft.

function Store.validCooking(job,token,key)
    if not scopeAllowed(job.id,job.scopeId) then return false end
    Store.data()
    local saved=state.root.taskJobs.byId[job.id]
    return saved and saved.providerType=='COOKING' and saved.npcId==job.npcId and saved.revision==job.revision
	and token and state.cookingTokens[job.id]==token and token.generation==saved.payload.sequence
	and (not key or state.claims:valid(token,key)) or false
end
function Store.replaceCooking(job,token,proposed)
    if not Store.validCooking(job,token) or proposed.id~=job.id or proposed.npcId~=job.npcId
	or proposed.scopeId~=job.scopeId or proposed.revision~=job.revision
	or not require('EmberRoutesProbe/CookingRecord').valid(proposed) then return false,'COOKING_JOB_CHANGED' end
    local old={} for _,key in ipairs(token.resources) do old[#old+1]=key end
    -- Pure coordination, no yield or native effect between replace and publish.
    -- Conflict rejection leaves both the durable Job and all old owners intact.
    local ok,reason=state.claims:replace(token,proposed.payload.claims)
    if not ok then return false,reason end
    local beforeCap,afterCap=job.payload.capacity,proposed.payload.capacity
    local capacityChanged=(beforeCap and beforeCap.endpointId)~=(afterCap and afterCap.endpointId)
	or (beforeCap and beforeCap.amount)~=(afterCap and afterCap.amount)
    if capacityChanged then
	state.claims:releaseCapacity(token)
	if afterCap and not state.claims:restoreWork(token,afterCap.endpointId,afterCap.amount) then
	    assert(state.claims:replace(token,old),'COOKING_CLAIM_ROLLBACK_FAILED')
	    if beforeCap then assert(state.claims:restoreWork(token,beforeCap.endpointId,beforeCap.amount)) end
	    return false,'COOKING_CAPACITY_INVALID'
	end
    end
    local jobs=require('EmberRoutesProbe/TaskJobs').current()
    local changed,why=jobs:update(job.id,job.revision,{payload=proposed.payload,effects=proposed.effects,
	obligations=proposed.obligations,state=proposed.state})
    if not changed then
	if capacityChanged then state.claims:releaseCapacity(token) end
	assert(state.claims:replace(token,old),'COOKING_CLAIM_ROLLBACK_FAILED')
	if capacityChanged and beforeCap then assert(state.claims:restoreWork(token,beforeCap.endpointId,beforeCap.amount)) end
	return false,why
    end
    local saved=jobs:get(job.id)
    local claimId = ensureEntityClaimId(state.root, saved, saved.id)
    local nextToken=assert(state.claims:acquire(job.id,saved.payload.sequence,saved.payload.claims, { claimId = claimId }))
    state.cookingTokens[job.id]=nextToken
    return true,saved,nextToken
end
function Store.availableCooking(job,token,key,free)
    if not Store.validCooking(job,token) then return 0 end
    return state.claims:availableWork(token,key,free)
end
function Store.finishCooking(job,token)
    if not Store.validCooking(job,token) then return false,'COOKING_JOB_CHANGED' end
    local saved=state.root.taskJobs.byId[job.id]
    if not require('EmberRoutesProbe/CookingRecord').valid(saved) or saved.payload.phase~='SETTLED'
	or saved.effects~='KNOWN' or #saved.payload.claims>0 then return false,'COOKING_OBLIGATION_RETAINED' end
    state.claims:release(token) cleanToken(job.id) return true
end
function Store.claimPersonal(job)
    Store.data()
    local saved=state.root.taskJobs.byId[job.id]
    if not require('EmberRoutesProbe/SelfCareRecord').valid(saved)
	or saved.npcId~=job.npcId or saved.payload.attemptId~=job.payload.attemptId
	or saved.payload.sequence~=job.payload.sequence then return nil,'STALE_PERSONAL_ATTEMPT' end
    local claimId = ensureEntityClaimId(state.root, saved, job.id)
    local token,reason=state.claims:acquire(job.id,job.payload.sequence,saved.payload.claims, { claimId = claimId })
    if token then state.personalTokens[job.id]=token end
    return token,reason
end
function Store.claimActivity(job)
    Store.data()
    local saved=state.root.taskJobs.byId[job.id]
    if not require('EmberRoutesProbe/ActivityRecord').valid(saved) or saved.npcId~=job.npcId
	or saved.effects~='KNOWN' or saved.payload.sequence~=job.payload.sequence then return nil,'STALE_ACTIVITY_ATTEMPT' end
    local claimId = ensureEntityClaimId(state.root, saved, job.id)
    local token,why=state.claims:acquire(job.id,job.payload.sequence,saved.payload.claims, { claimId = claimId })
    if token then state.activityTokens[job.id]=token end return token,why
end
-- Field adapters share this same resource authority with cooking/haul/care.
function Store.claimField(job)
    Store.data()
    local saved=state.root.taskJobs.byId[job.id]
    if not saved or saved.providerType~='FIELD_WORK' or saved.revision~=job.revision
        or not require('EmberRoutesProbe/FieldRecord').valid(saved) or saved.effects~='KNOWN'
        or saved.payload.phase=='SETTLED' then return nil,'FIELD_JOB_CHANGED' end
    local claimId = ensureEntityClaimId(state.root, saved, job.id)
    local token,why=state.claims:acquire(job.id,saved.payload.sequence,saved.payload.claims, { claimId = claimId })
    if token then state.fieldTokens[job.id]=token end
    return token,why
end
function Store.validField(job,token,key)
    if not scopeAllowed(job.id,job.scopeId) then return false end
    Store.data() local saved=state.root.taskJobs.byId[job.id]
    return saved and saved.providerType=='FIELD_WORK' and saved.revision==job.revision
	and state.fieldTokens[job.id]==token and token~=nil and (not key or state.claims:valid(token,key)) or false
end
function Store.replaceField(job,token,proposed)
    if not Store.validField(job,token) or not require('EmberRoutesProbe/FieldRecord').valid(proposed) then return false,'FIELD_JOB_CHANGED' end
    local old=job.payload.claims
    local ok,why=state.claims:replace(token,proposed.payload.claims)
    if not ok then return false,why end
    local jobs=require('EmberRoutesProbe/TaskJobs').current()
    ok,why=jobs:update(job.id,job.revision,{state=proposed.state,effects=proposed.effects,
	obligations=proposed.obligations,payload=proposed.payload})
    if not ok then assert(state.claims:replace(token,old),'FIELD_CLAIM_ROLLBACK_FAILED') return false,why end
    return true,jobs:get(job.id)
end
function Store.reserveField(job,token,key,itemId,amount,free)
    if not Store.validField(job,token) then return false,'FIELD_JOB_CHANGED' end
    return state.claims:reserve(token,key,itemId,amount,free)
end
function Store.finishField(job)
    Store.data() local saved=state.root.taskJobs.byId[job.id]
    if not saved or saved.providerType~='FIELD_WORK' or saved.effects~='KNOWN'
	or (saved.state~='DONE' and saved.state~='CANCELLED') or #saved.payload.claims>0 then return false end
    for _ in pairs(saved.obligations) do return false end
    local token=state.fieldTokens[job.id]
    if token then state.claims:release(token) cleanToken(job.id) end
    if state.root.toolCustody and state.root.toolCustody.byId then
	for _,c in pairs(state.root.toolCustody.byId) do
	    if c.activeJobId==job.id then c.activeJobId=nil end
	end
    end
    return true
end
-- The one exit for an ACTIVITY participant Job whose effects can no longer be
-- proven (load recovery marked it UNKNOWN, or its carrier died mid-session).
-- Business evidence, checked by the caller before this runs: the scene is
-- closing or the member withdrawn, the runtime holds no state for the job,
-- the personal side has no pending cleanup, and the job holds no obligations.
-- An ACTIVITY job's only claim is a placement tile - never an item original -
-- so releasing it under those facts cannot strand custody. Mirrors
-- finishActivity's write-then-release order; the caller then completes the
-- normal settle tail, which writes the terminal state as CANCELLED.
function Store.settleActivityWedged(job)
    Store.data() local saved=state.root.taskJobs.byId[job.id]
    if not saved or saved.providerType~='ACTIVITY' or saved.npcId~=job.npcId then return false end
    if not (saved.state=='RECONCILE_REQUIRED' or saved.effects=='UNKNOWN') then return false end
    for _ in pairs(saved.obligations) do return false end
    local p={} for k,v in pairs(saved.payload) do p[k]=v end p.claims={} p.stopped=true
    if not require('EmberRoutesProbe/TaskJobs').current():update(job.id,saved.revision,
        {payload=p,state='SETTLING',effects='KNOWN'}) then return false end
    local token=state.activityTokens[job.id]
    if token then state.claims:release(token) cleanToken(job.id) end
    return true
end
function Store.validActivity(job,token)
    if not scopeAllowed(job.id,job.scopeId) then return false end
    Store.data() local saved=state.root.taskJobs.byId[job.id]
    return saved and token and state.activityTokens[job.id]==token and token.generation==saved.payload.sequence
	and saved.npcId==job.npcId and saved.payload.sequence==job.payload.sequence or false
end
function Store.finishActivity(job,token)
    if not Store.validActivity(job,token) then return false,'STALE_ACTIVITY_ATTEMPT' end
    local saved=state.root.taskJobs.byId[job.id]
    if saved.effects~='KNOWN' then return false,'ACTIVITY_EFFECT_UNKNOWN' end
    for _ in pairs(saved.obligations) do return false,'ACTIVITY_OBLIGATION_RETAINED' end
    local p={} for k,v in pairs(saved.payload) do p[k]=v end p.claims={}
    if not require('EmberRoutesProbe/TaskJobs').current():update(job.id,saved.revision,{payload=p}) then return false,'JOB_CHANGED' end
    state.claims:release(token) cleanToken(job.id) return true
end
function Store.validPersonal(job,token,key)
    if not scopeAllowed(job.id,job.scopeId) then return false end
    Store.data()
    local saved=state.root.taskJobs.byId[job.id]
    return saved and saved.npcId==job.npcId and saved.payload.attemptId==job.payload.attemptId
	and token and state.personalTokens[job.id]==token and token.generation==saved.payload.sequence
	and (not key or state.claims:valid(token,key)) or false
end
-- Called from membership retirement / personal stop, never from a timer.
function Store.settleDeadPersonal(job,bodyStopped)
    Store.data()
    local jobs=require('EmberRoutesProbe/TaskJobs').current()
    local saved=jobs:get(job.id)
    local Record=require 'EmberRoutesProbe/SelfCareRecord'
    if not Record.valid(saved) or saved.npcId~=job.npcId then return false end
    local member=require('EmberRoutesProbe/MembershipService').view(saved.npcId)
    if member and not member.retired then return false end
    local runtime=require('EmberRoutesProbe/TaskRuntime').current()
    local retained=Record.deathRetained(saved)
    -- A live callback can still publish facts: never clear behind its back.
    if not retained and bodyStopped~=true and runtime and runtime:status(saved.npcId,saved.id) then
        local p=saved.payload p.reason='NPC_DIED'
        if p.kind then p.step='RECONCILE_REQUIRED' end
        assert(Record.valid(saved),'PERSONAL_RECORD_INVALID')
        return jobs:update(saved.id,saved.revision,{payload=p,effects='UNKNOWN',state='RECONCILE_REQUIRED'})
    end
    local proposed=jobs:get(saved.id)
    Record.death(proposed)
    -- Normal JobStore transitions remain in force, including RUNNING's fence.
    if proposed.state=='SUSPENDED' and saved.state~='SUSPENDED'
        and saved.state~='PREPARING' and saved.state~='STOPPING' and saved.state~='SETTLING'
        and saved.state~='RECONCILE_REQUIRED' then return false end
    local ok=jobs:update(saved.id,saved.revision,{payload=proposed.payload,
        effects=proposed.effects,state=proposed.state})
    if not ok then return false end
    if not retained then
        local token=state.personalTokens[saved.id]
        if token then state.claims:release(token) cleanToken(saved.id) end
    end
    return true
end
function Store.finishPersonal(job,token)
    if not Store.validPersonal(job,token) then return false,'STALE_PERSONAL_ATTEMPT' end
    local saved=state.root.taskJobs.byId[job.id]
    if saved.effects~='KNOWN' then return false,'PERSONAL_EFFECT_UNKNOWN' end
    for _ in pairs(saved.obligations) do return false,'PERSONAL_OBLIGATION_RETAINED' end
    local jobs=require('EmberRoutesProbe/TaskJobs').current()
    local payload=jobs:get(job.id).payload payload.claims={}
    local ok,reason=jobs:update(job.id,saved.revision,{payload=payload})
    if not ok then return false,reason end
    state.claims:release(token) cleanToken(job.id) return true
end
-- Only release furniture keys after the caller has physical exit evidence.
-- Item custody remains exactly as declared in the same Job.
function Store.releasePersonalSeats(job,token)
    if not Store.validPersonal(job,token) then return false,'STALE_PERSONAL_ATTEMPT' end
    local saved=state.root.taskJobs.byId[job.id]
    local keep={} local present={}
    for _,key in ipairs(saved.payload.claims) do keep[#keep+1]=key present[key]=true end
    for _,key in ipairs(token.resources) do
	if not present[key] and string.sub(key,1,7)~='repose:' then return false,'ITEM_CLAIM_RETAINED' end
    end
    return state.claims:replace(token,keep)
end
function Store.extendPersonal(job,token)
    if not Store.validPersonal(job,token) then return false,'STALE_PERSONAL_ATTEMPT' end
    -- Publish native outputs before extending the in-memory claim. A conflict
    -- retains the durable declaration for reconciliation, never deletes output.
    return state.claims:extend(token,state.root.taskJobs.byId[job.id].payload.claims)
end
function Store.claimHaulJob(job)
    Store.data()
    local saved=state.root.taskJobs.byId[job.id]
    if not saved or saved.providerType~='HAUL' or saved.payload.format~=3 or saved.payload.executor~='ENTITY'
	or saved.revision~=job.revision or saved.npcId~=job.npcId or saved.effects=='UNKNOWN'
	or saved.state=='DONE' or saved.state=='CANCELLED' then return nil,'HAUL_JOB_CHANGED' end
    local token,why=state.claims:acquire(saved.id,saved.payload.sequence,saved.payload.claims,{claimId=saved.claimId})
    if token then state.tokens[saved.id]=token end
    return token,why
end
function Store.validHaulJob(job,token,key)
    if not scopeAllowed(job.id,job.scopeId) then return false end
    Store.data() local saved=state.root.taskJobs.byId[job.id]
    return saved and saved.providerType=='HAUL' and saved.revision==job.revision
	and token and state.tokens[job.id]==token and token.generation==saved.payload.sequence
	and (not key or state.claims:valid(token,key)) or false
end
function Store.claimCraft(job,returnOnly)
    Store.data()
    local saved=state.root.taskJobs.byId[job.id]
    if not saved or saved.providerType~='CRAFT' or saved.payload.executor~='PRODUCTION'
	or saved.revision~=job.revision or saved.npcId~=job.npcId or saved.effects=='UNKNOWN' and not returnOnly
	or saved.state=='DONE' or saved.state=='CANCELLED' then return nil,'CRAFT_JOB_CHANGED' end
    local token,why=state.claims:acquire(saved.id,saved.payload.sequence,saved.payload.claims,{claimId=saved.claimId})
    if token then state.tokens[saved.id]=token end
    return token,why
end
function Store.validCraft(job,token,key)
    if not scopeAllowed(job.id,job.scopeId) then return false end
    Store.data()
    local saved=state.root.taskJobs.byId[job.id]
    return saved and saved.providerType=='CRAFT' and saved.revision==job.revision
	and saved.npcId==job.npcId and token and state.tokens[job.id]==token
	and token.generation==saved.payload.sequence and (not key or state.claims:valid(token,key)) or false
end

end
return A
