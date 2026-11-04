-- TEST ONLY cooking section frozen HEAD 47de22c; never loaded by production.
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

end
return A
