-- TEST ONLY: frozen 9ebe06f LaborJobCommit.lua; never loaded by production.
-- Synchronous resource/record commit. Domain policy comes from contracts.
local Contracts=require 'EmberRoutesProbe/JobContracts'
local M={}
function M.install(Store,state,nextAuthoritativeClaimId,cleanToken)
function Store.createClaimedJob(job)
    Store.data()
    -- Allocate persistent non-reusable claimId at the authoritative state.root level:
    -- NEVER allow external caller to inject arbitrary/old claimId!
    local persistentClaimId = nextAuthoritativeClaimId(state.root, (type(job) == "table" and job.id) or "claim")
    if type(job) == "table" then
	job.claimId = persistentClaimId
    end
    local JobStore=require('EmberRoutesProbe/JobStore')
    if not JobStore.validate(job) or job.state~='PREPARING' or job.revision~=1 then
	return false,'INVALID_JOB_ENVELOPE'
    end
    if state.claims then state.claims.nextClaimSeq = math.max(state.claims.nextClaimSeq or 1, state.root.nextClaimSeq + 1) end

    local p=job.payload
    local keys=p.claims or {}
    local token,why=state.claims:acquireNew(job.id,p.sequence or job.generation or 0,keys,job)
    if not token then return false,'CLAIMS_ACQUIRE_FAILED:'..tostring(why) end
    if p.reservation and type(p.reservation)=='table' then
	local r=p.reservation
	if type(r.items)=='table' then
	    for itemId,amt in pairs(r.items) do
		local okRes=state.claims:reserve(token,r.key,itemId,amt,r.free)
		if not okRes then
		    state.claims:release(token)
		    return false,'CAPACITY_RESERVE_FAILED'
		end
	    end
	elseif r.itemId and r.amount then
	    local okRes=state.claims:reserve(token,r.key,r.itemId,r.amount,r.free)
	    if not okRes then
		state.claims:release(token)
		return false,'CAPACITY_RESERVE_FAILED'
	    end
	end
    end
    local TaskJobs=require('EmberRoutesProbe/TaskJobs')
    local store=TaskJobs.current()
    local ok,err=store:create(job)
    if not ok then
	state.claims:release(token)
	return false,'JOB_CREATE_FAILED_ROLLED_BACK:'..tostring(err)
    end
    state.tokens[job.id] = token
    local rule=Contracts.get(job.providerType)
    local bucket=rule and rule.tokenBucket
    if bucket then state[bucket..'Tokens'][job.id]=token end
    return true, job.id
end
function Store.mutateJob(jobId, expectedRevision, proposedPayload, mutation)
    Store.data()
    local TaskJobs = require('EmberRoutesProbe/TaskJobs')
    local store = TaskJobs.current()
    -- Batch capacity mutations amortize the Lua/Java boundary. Small updates
    -- retain the Lua path: host measurements found a whole-store port slower.
    local batchToken=state.claims.tokensByTaskId and state.claims.tokensByTaskId[jobId]
    if mutation and mutation.capacity~=nil and batchToken and #batchToken.resources>=4
	and EmberRoutesProbeJava and EmberRoutesProbeJava.laborMutate then
	local r=EmberRoutesProbeJava.laborMutate(store,Store,state.claims,Contracts,cleanToken,jobId,expectedRevision,proposedPayload,mutation)
	return r.ok,r.result
    end
    local job = store:get(jobId)
    if not job or job.revision ~= expectedRevision then return false, 'STALE_REVISION' end
    local token = Store.getToken(jobId)
    if not token then return false, 'NO_RUNTIME_TOKEN' end
    if type(proposedPayload) ~= 'table' then return false, 'PROPOSED_PAYLOAD_INVALID' end

    local addKeys = mutation and mutation.addKeys
    local removeKeys = mutation and mutation.removeKeys
    if addKeys then
	local seen={}
	for _,key in ipairs(addKeys) do
	    if seen[key] then return false,'RESOURCE_DUPLICATED' end
	    seen[key]=true
	end
    end

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
	local okCanShrink, whyCanShrink = state.claims:canShrink(token, removeKeys)
	if not okCanShrink then
	    return false, 'SHRINK_FAILED:' .. tostring(whyCanShrink)
	end
    end

    -- Capacity commands must describe exactly the proposed persistent facts.
    -- Reject before extend/reserve/CAS, so invalid commands have no side effects.
    if mutation and mutation.capacity~=nil then
	local cap=mutation.capacity
	if not (Contracts.get(job.providerType) or {}).capacityMutable or addKeys and #addKeys>0
	    or cap~=false and type(cap)~='table' then return false,'CAPACITY_MUTATION_UNSUPPORTED' end
	local expected={}
	local bucket=token.capacityKey and state.claims.capacity[token.capacityKey]
	local prior=bucket and bucket.entries[token.taskId]
	if prior then for id,amount in pairs(prior.items) do expected[id]=amount end end
	local key=token.capacityKey
	if cap==false then expected={} key=nil
	elseif cap.releaseItemId then expected[cap.releaseItemId]=nil
	else expected=cap.items key=cap.key if type(expected)~='table' then return false,'CAPACITY_PAYLOAD_MISMATCH' end end
	local reservation=proposedPayload.reservation
	local any=false
	for id,amount in pairs(expected) do
	    any=true
	    if not reservation or reservation.key~=key or not reservation.items or reservation.items[id]~=amount then return false,'CAPACITY_PAYLOAD_MISMATCH' end
	end
	if reservation then
	    if not any then return false,'CAPACITY_PAYLOAD_MISMATCH' end
	    for id,amount in pairs(reservation.items or {}) do if expected[id]~=amount then return false,'CAPACITY_PAYLOAD_MISMATCH' end end
	end
    end

    -- 5. Extend addKeys
    if addKeys and #addKeys > 0 then
	local okExt, whyExt = state.claims:extend(token, addKeys)
	if not okExt then return false, 'EXTEND_FAILED:' .. tostring(whyExt) end
    end

    local beforeCapacity
    if mutation and mutation.capacity~=nil then
	-- Haul reservations change in this same no-yield authority call, never
	-- through a provider's mutable persistent table. No resource growth here.
	local bucket=token.capacityKey and state.claims.capacity[token.capacityKey]
	local previous=bucket and bucket.entries[token.taskId]
	beforeCapacity={key=token.capacityKey,items={}}
	if previous then for id,amount in pairs(previous.items) do beforeCapacity.items[id]=amount end end
	local cap=mutation.capacity
	local ok,why=true
	if cap==false then state.claims:releaseCapacity(token)
	elseif cap.releaseItemId then state.claims:releaseCapacity(token,cap.releaseItemId)
	else
	    if token.capacityKey and token.capacityKey~=cap.key then state.claims:releaseCapacity(token) end
	    ok,why=state.claims:reserveMany(token,cap.key,cap.items,cap.free)
	end
	if not ok then
	    state.claims:releaseCapacity(token)
	    if beforeCapacity.key then for id,amount in pairs(beforeCapacity.items) do assert(state.claims:restore(token,beforeCapacity.key,id,amount)) end end
	    return false,why
	end
    end
    -- 6. CAS store:update
    local patch = { payload = proposedPayload }
    if mutation and mutation.state then patch.state = mutation.state end
    if mutation and mutation.effects then patch.effects = mutation.effects end
    if mutation and mutation.obligations then patch.obligations = mutation.obligations end
    local okCAS, nextRev = store:update(jobId, expectedRevision, patch)
    if not okCAS then
	if beforeCapacity then
	    state.claims:releaseCapacity(token)
	    if beforeCapacity.key then for id,amount in pairs(beforeCapacity.items) do assert(state.claims:restore(token,beforeCapacity.key,id,amount)) end end
	end
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
	local okShrink, whyShrink = state.claims:shrink(token, removeKeys)
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
	state.claims:release(token)
	cleanToken(jobId)
    end
    return true, nextRev
end

end
return M
