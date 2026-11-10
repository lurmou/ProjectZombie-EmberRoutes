-- Internal registry for public ordinary-work providers.
-- Each provider contributes discovery, claim execution, reconcile, and optional
-- idle/clean routines for a distinct workCategory (e.g. 'crafting', 'hauling', 'cooking').
-- Two fields are mandatory and loud: `defaultPriority` (the explicit fan-out
-- rank, 0-4) and `retained` (P4: true while this provider still holds one of
-- the worker's unfinished Jobs). A provider without either is rejected at
-- registration instead of being silently skipped by the retained gate.
-- Fan-out order is derived from the explicit fields, never from the order
-- register happened to be called in: `order` below is kept sorted by
-- (defaultPriority, category). `registrationOrder` keeps the stable
-- registration sequence behind categories(), which UI lists and saved
-- priority sets enumerate.
local Registry={}
local defs={}
local order={}
local registrationOrder={}
local allCache

-- Sorted insert position for a def in `order`.
local function insertSorted(category)
    local def=defs[category]
    local i=1
    while i<=#order do
        local other=defs[order[i]]
        if def.defaultPriority<other.defaultPriority
            or def.defaultPriority==other.defaultPriority and category<order[i] then break end
        i=i+1
    end
    table.insert(order,i,category)
end

function Registry.register(def)
    if type(def)~='table' or type(def.category)~='string' or #def.category<1 or #def.category>32 then
        return false,'PROVIDER_INVALID'
    end
    -- defaultPriority is required: no silent `or 3` fallback anywhere.
    if def.defaultPriority==nil then
        return false,'PROVIDER_MISSING_PRIORITY'
    end
    if type(def.defaultPriority)~='number' or def.defaultPriority~=def.defaultPriority
        or def.defaultPriority~=math.floor(def.defaultPriority)
        or def.defaultPriority<0 or def.defaultPriority>4 then
        return false,'PROVIDER_INVALID'
    end
    if type(def.discover)~='function' then
        return false,'PROVIDER_MISSING_DISCOVER'
    end
    if type(def.claim)~='function' then
        return false,'PROVIDER_MISSING_CLAIM'
    end
    -- retained is required: a provider that cannot answer "do I still hold
    -- this worker's unfinished Job" must not register at all. A present but
    -- non-function value keeps the hook-type error so the failure names it.
    if def.retained==nil then
        return false,'PROVIDER_MISSING_RETAINED'
    end
    if type(def.retained)~='function' then
        return false,'PROVIDER_HOOK_NOT_FUNCTION:retained'
    end
    -- priorityRequired: every saved priority set must carry this category.
    if def.priorityRequired~=nil and type(def.priorityRequired)~='boolean' then
        return false,'PROVIDER_INVALID'
    end
    -- Optional hooks: if present, must be functions.
    local optHooks={'advance','reconcile','idle','step','hasWork','reset','cancel',
        'scanStatus','precheck','hasPrechecks','capacityBlocked','blocksDecision',
        'holdSelection','pendingScore','pending','beforeClaim','observeDemand',
        'command','orderCommanded','retireUnclaimed','orderRetired'}
    for _,hook in ipairs(optHooks) do
        if def[hook]~=nil and type(def[hook])~='function' then
            return false,'PROVIDER_HOOK_NOT_FUNCTION:'..hook
        end
    end
    if not defs[def.category] then
        registrationOrder[#registrationOrder+1]=def.category
    else
        for i,cat in ipairs(order) do if cat==def.category then table.remove(order,i) break end end
    end
    defs[def.category]=def
    insertSorted(def.category)
    allCache=nil
    return true
end

function Registry.get(category)
    return defs[category]
end

function Registry.has(category)
    return defs[category]~=nil
end

function Registry.categories()
    -- Stable registration sequence: UI lists and saved priority sets
    -- enumerate this, so a provider's explicit priority never reorders them.
    local copy={}
    for i,cat in ipairs(registrationOrder) do copy[i]=cat end
    return copy
end

-- Read-only provider list in explicit priority order (defaultPriority, then
-- category), reused until the registry changes. Every caller only iterates
-- it, and it is rebuilt on register/reset, so no caller can observe a stale
-- or shared mutation.
function Registry.all()
    if allCache then return allCache end
    local list={}
    for _,cat in ipairs(order) do list[#list+1]=defs[cat] end
    allCache=list
    return list
end

-- Optional domain scheduling hooks; no domain names or execution strategy here.
function Registry.observeDemand(actor,now,eligible,priorities)
    for _,kind in ipairs(order) do local p=defs[kind]
	if p.observeDemand then p.observeDemand(actor,now,eligible,priorities) end
    end
end
function Registry.cancelPending(npcId)
    for _,kind in ipairs(order) do local p=defs[kind] if p.cancel then p.cancel(npcId) end end
end
function Registry.pendingScore(npcId)
    -- Highest score wins. Registration order used to decide the tie (first
    -- positive), which made an implicit listing order act as a priority.
    local best=0
    for _,kind in ipairs(order) do local p=defs[kind]
        if p.pendingScore then
            local s=p.pendingScore(npcId)
            if s and s>best then best=s end
        end
    end
    return best
end
function Registry.hasPending(npcId)
    for _,kind in ipairs(order) do local p=defs[kind] if p.pending and p.pending(npcId) then return true end end
    return false
end
-- A player command changed a public order handled by the kernel (one with no
-- owning provider command); providers drop any plan built for it.
function Registry.orderCommanded(orderId)
    for _,kind in ipairs(order) do local p=defs[kind] if p.orderCommanded then p.orderCommanded(orderId) end end
end
-- A settled public order left the order document; readyWorkers is the
-- kernel's current precheck-ready list.
function Registry.orderRetired(orderId,readyWorkers)
    for _,kind in ipairs(order) do local p=defs[kind] if p.orderRetired then p.orderRetired(orderId,readyWorkers) end end
end
-- World root replaced: each provider drops its own per-world caches. Not
-- Registry.reset below, which clears the registrations themselves.
function Registry.resetWorld()
    for _,kind in ipairs(order) do local p=defs[kind] if p.reset then p.reset() end end
end
-- A provider still holding this worker's unfinished job keeps it out of new
-- ordinary work. Every registered provider answers retained (registration
-- rejects one that cannot), so no holder can be silently skipped.
function Registry.retained(npcId)
    for _,kind in ipairs(order) do local p=defs[kind] if p.retained and p.retained(npcId) then return true end end
    return false
end
function Registry.capacityBlocked(npcId,orders,signal)
    for _,kind in ipairs(order) do local p=defs[kind] if p.capacityBlocked then p.capacityBlocked(npcId,orders,signal) end end
end
function Registry.blocksDecision(actor,npcId,entry)
    for _,kind in ipairs(order) do local p=defs[kind]
	if p.blocksDecision and p.blocksDecision(actor,npcId,entry) then return true end
    end
    return false
end
function Registry.holdSelection(env)
    for _,kind in ipairs(order) do local p=defs[kind] if p.holdSelection and p.holdSelection(env) then return true end end
    return false
end
function Registry.scanStatus(npcId,orders)
    local complete,watch,group=true,nil,nil
    for _,kind in ipairs(order) do local p=defs[kind]
	if p.scanStatus then
	    local done,dependency=p.scanStatus(npcId,orders)
	    if not done then complete=false end
	    if dependency then
		if not watch then watch=dependency
		else
		    group=group or {providerWatches={watch}}
		    group.providerWatches[#group.providerWatches+1]=dependency
		end
	    end
	end
    end
    return complete,group or watch
end
function Registry.discoveryChanged(watch)
    local Wake=require 'EmberRoutesProbe/Runtime/PlanningWake'
    if watch and watch.providerWatches then
	for _,dependency in ipairs(watch.providerWatches) do if Wake.changed(dependency) then return true end end
	return false
    end
    return Wake.changed(watch)
end
-- Claim failure contract. When provider.claim does not return QUEUED/STARTED,
-- it returns CLAIM_ROLLED_BACK as its second value only if the failed claim
-- left no business effects of its own (nothing created, or all undone). Only
-- that declaration lets the coordinator release the directory offer; without
-- it the offer stays allocated and the returned reason is the diagnosis.
Registry.CLAIM_ROLLED_BACK='ROLLED_BACK'
function Registry.settleFailedClaim(directory,key,jobId,declaration)
    if declaration~=Registry.CLAIM_ROLLED_BACK then return 'CLAIM_ROLLBACK_UNDECLARED' end
    local released,why=directory:release(key,jobId,{effects='KNOWN',obligationsCleared=true})
    if not released then return why or 'OFFER_RELEASE_FAILED' end
    return nil
end
function Registry.beforeClaim(selected,npcId)
    for _,kind in ipairs(order) do local p=defs[kind] if p.beforeClaim then p.beforeClaim(selected,npcId) end end
end
function Registry.hasPrechecks()
    for _,kind in ipairs(order) do local p=defs[kind] if p.hasPrechecks and p.hasPrechecks() then return true end end
    return false
end
function Registry.precheck(env)
    local ops,slices=0,0
    for _,kind in ipairs(order) do local p=defs[kind]
	if p.hasPrechecks and p.hasPrechecks() and p.precheck then
	    local a,b=p.precheck(env) ops=ops+(a or 0) slices=slices+(b or 0)
	end
    end
    return ops,slices
end

function Registry.reset()
    defs={}
    order={}
    registrationOrder={}
    allCache=nil
end

return Registry
