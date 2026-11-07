-- TEST ONLY: frozen ef41485 ACTIVITY adapters; no production consumer.
local A={}
function A.install(Store,state,ensureEntityClaimId,cleanToken,scopeAllowed)
function Store.claimActivity(job)
    Store.data()
    local saved=state.root.taskJobs.byId[job.id]
    if not require('EmberRoutesProbe/Activity/ActivityRecord').valid(saved) or saved.npcId~=job.npcId
	or saved.effects~='KNOWN' or saved.payload.sequence~=job.payload.sequence then return nil,'STALE_ACTIVITY_ATTEMPT' end
    local claimId = ensureEntityClaimId(state.root, saved, job.id)
    local token,why=state.claims:acquire(job.id,job.payload.sequence,saved.payload.claims, { claimId = claimId })
    if token then state.activityTokens[job.id]=token end return token,why
end
function Store.settleActivityWedged(job)
    Store.data() local saved=state.root.taskJobs.byId[job.id]
    if not saved or saved.providerType~='ACTIVITY' or saved.npcId~=job.npcId then return false end
    if not (saved.state=='RECONCILE_REQUIRED' or saved.effects=='UNKNOWN') then return false end
    for _ in pairs(saved.obligations) do return false end
    local p={} for k,v in pairs(saved.payload) do p[k]=v end p.claims={} p.stopped=true
    if not require('EmberRoutesProbe/Runtime/TaskJobs').current():update(job.id,saved.revision,
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
    if not require('EmberRoutesProbe/Runtime/TaskJobs').current():update(job.id,saved.revision,{payload=p}) then return false,'JOB_CHANGED' end
    state.claims:release(token) cleanToken(job.id) return true
end
end
return A
