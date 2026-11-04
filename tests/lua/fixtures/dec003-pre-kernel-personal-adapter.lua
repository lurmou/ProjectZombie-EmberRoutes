-- TEST ONLY: a16eb0b PERSONAL adapter baseline.
local A={}
function A.install(Store,state,ensureEntityClaimId,cleanToken,scopeAllowed)
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

end
return A
