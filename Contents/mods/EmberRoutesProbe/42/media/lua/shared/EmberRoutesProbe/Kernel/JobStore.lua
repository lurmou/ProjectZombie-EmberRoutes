-- Independent persistent Job identity. No Session, asset authority or scheduler.
local Store={LIMIT=512,PERSONAL_LIMIT=256}
local Contracts=require 'EmberRoutesProbe/Kernel/JobContracts'
local JobState=require 'EmberRoutesProbe/Kernel/JobState'
local Templates=require 'EmberRoutesProbe/Kernel/ModDataTemplates'
require('EmberRoutesProbe/Kernel/BuiltinJobContracts').install()
local emptyContract={}
local function contract(kind) return Contracts.get(kind) or emptyContract end
local function personalJob(job) return contract(job.providerType).persistentPersonal==true end
local transitions={
    PREPARING={RUNNING=true,SUSPENDED=true,SETTLING=true,RECONCILE_REQUIRED=true},
    RUNNING={STOPPING=true,SETTLING=true,RECONCILE_REQUIRED=true},
    STOPPING={SUSPENDED=true,SETTLING=true,RECONCILE_REQUIRED=true},
    SUSPENDED={PREPARING=true,SETTLING=true,RECONCILE_REQUIRED=true},
    SETTLING={DONE=true,CANCELLED=true,SUSPENDED=true,RECONCILE_REQUIRED=true},
    RECONCILE_REQUIRED={SUSPENDED=true,SETTLING=true},DONE={},CANCELLED={}}
local function id(v) return type(v)=='string' and v~='' and #v<=256 end
local function integer(v) return type(v)=='number' and v==v and v>=0 and v<math.huge and v==math.floor(v) end
local function empty(t) for _ in pairs(t) do return false end return true end
local function obligationGuard(job,ledger)
    if ledger==nil then return false,'OBLIGATION_FORMAT_UNSUPPORTED' end
    local Ledger=require 'EmberRoutesProbe/Kernel/ObligationLedger'
    local count,why=Ledger.outstanding(ledger,job.id)
    if not count then return false,why end
    if JobState.isTerminal(job.state) and count>0 then return false,'JOB_OBLIGATION_RETAINED' end
    local claims={} for _,claim in ipairs(job.payload.claims or {}) do claims[claim]=true end
    for _,obligation in pairs(ledger.byId) do
        if obligation.jobId==job.id and obligation.state~='SETTLED' then
            if obligation.npcId~=job.npcId then return false,'OBLIGATION_NPC_MISMATCH' end
            local check=contract(job.providerType).obligationRecord
            if check then
                local allowed,reason=check(job,obligation,claims)
                if not allowed then return false,reason end
            end
            local claim=Ledger.claimKey(obligation)
            if claim and not claims[claim] then return false,'OBLIGATION_CLAIM_RETAINED' end
        end
    end
    local check=contract(job.providerType).obligationGuard
    if check then return check(job,ledger) end
    return true
end
-- Copy only bounded serializable facts. Reject cycles/functions/userdata, never
-- persist native handles or behavior closures. Reject before publishing writes.
local function copy(value,seen,budget,depth)
    local kind=type(value)
    budget.n=budget.n+1
    if budget.n>8192 or depth>16 then error('JOB_DATA_LIMIT') end
    if kind=='string' then if #value>16384 then error('JOB_DATA_LIMIT') end return value end
    if kind=='boolean' or kind=='nil' then return value end
    if kind=='number' and value==value and math.abs(value)<math.huge then return value end
    if kind~='table' or seen[value] then error('JOB_DATA_UNSERIALIZABLE') end
    seen[value]=true local result={}
    for key,item in pairs(value) do
        if type(key)~='string' and not integer(key) then error('JOB_KEY_INVALID') end
        result[key]=copy(item,seen,budget,depth+1)
    end
    seen[value]=nil return result
end
local function detached(value)
    -- Capability fallback supports boot admission and the standalone Lua host.
    -- Both paths have the same data limits; no failure is swallowed or retried.
    if EmberRoutesProbeJava and EmberRoutesProbeJava.jobDataCopy then return EmberRoutesProbeJava.jobDataCopy(value) end
    return copy(value,{},{n=0},0)
end
local function validClaimId(claimId, entityId)
    if type(claimId) ~= 'string' then return false end
    local prefix, seq = string.match(claimId, '^(.+):c(%d+)$')
    return prefix ~= nil and seq ~= nil and prefix == tostring(entityId)
end
local function valid(job)
    local basic=type(job)=='table' and id(job.id) and id(job.npcId) and id(job.providerType)
        and id(job.scopeId) and integer(job.revision) and job.revision>0 and JobState.isValid(job.state)
        and (job.effects=='KNOWN' or job.effects=='UNKNOWN') and type(job.obligations)=='table'
        and type(job.payload)=='table' and (not job.orderId or id(job.orderId))
        and (not JobState.isTerminal(job.state) or (job.effects=='KNOWN' and empty(job.obligations) and #(job.payload.claims or {}) == 0))
        and (job.claimId == nil or validClaimId(job.claimId, job.id))
    if not basic then return false end
    local rule=contract(job.providerType)
    return not rule.validate or rule.validate(job)
end
local function legacy(root)
    local craft,labor=root.craftProbes,root.labor
    return root.job~=nil or craft and (type(craft)~='table' or type(craft.byNpc)~='table' or not empty(craft.byNpc))
        or labor and (type(labor)~='table' or type(labor.tasks)~='table' or not empty(labor.tasks))
end
local function prepare(root)
    if type(root)~='table' then return nil,'JOB_ROOT_INVALID' end
    if legacy(root) then return nil,'LEGACY_TASK_RESET_REQUIRED' end
    -- The saved carrier is never written by the gate: check() is read-only,
    -- and open() publishes its own carrier. The gate runs on a shallow copy,
    -- so a missing field is filled at read without touching the stored table.
    local saved=root.taskJobs
    if saved==nil then saved={format=1,byId={}} end
    if type(saved)~='table' then return nil,'JOB_FORMAT_UNSUPPORTED' end
    local probe={} for key,value in pairs(saved) do probe[key]=value end
    local ok,reason=Templates.open(probe,Templates.templates.taskJobs,'JOB_FORMAT_UNSUPPORTED')
    if not ok then return nil,reason end
    if type(probe.byId)~='table' then return nil,'JOB_FORMAT_UNSUPPORTED' end
    saved=probe
    -- The live authority is always an independent copy. `saved` stays the save
    -- carrier only: mutating it (by any other module) can no longer reach the
    -- records the store validates, indexes and publishes.
    local data={format=1,byId={}}
    local byNpc,count,personal,personalByNpc={},0,0,{}
    for key,job in pairs(saved and saved.byId or {}) do
        if not valid(job) or job.id~=key then return nil,'JOB_RECORD_INVALID' end
        local ok,detachedJob=pcall(detached,job) if not ok then return nil,'JOB_DATA_UNSERIALIZABLE' end
        data.byId[key]=detachedJob
	if personalJob(job) then
            if personalByNpc[job.npcId] then return nil,'PERSONAL_JOB_DUPLICATED' end
            personalByNpc[job.npcId]=key personal=personal+1
            if personal>Store.PERSONAL_LIMIT then return nil,'PERSONAL_JOB_LIMIT' end
        else
            count=count+1 if count>Store.LIMIT then return nil,'JOB_LIMIT' end
        end
        byNpc[job.npcId]=byNpc[job.npcId] or {} byNpc[job.npcId][key]=true
    end
    local Ledger=require 'EmberRoutesProbe/Kernel/ObligationLedger'
    local ok,why=Ledger.check(root.obligations)
    if not ok then return nil,why end
    for _,record in pairs(root.obligations.byId) do
        if record.state~='SETTLED' and record.jobId and not data.byId[record.jobId] then
            return nil,'OBLIGATION_JOB_MISSING'
        end
    end
    for _,job in pairs(data.byId) do
        local allowed,reason=obligationGuard(job,root.obligations)
        if not allowed then return nil,reason end
    end
    return {data=data,byNpc=byNpc,count=count,personal=personal,personalByNpc=personalByNpc}
end
-- Same acceptance contract as open, with no root publication or API creation.
-- Used once at world admission, before other owners initialize/normalize data.
function Store.check(root)
    local prepared,reason=prepare(root)
    if not prepared then return false,reason end
    return true
end
function Store.open(root)
    local prepared,reason=prepare(root)
    if not prepared then return nil,reason end
    local data,byNpc=prepared.data,prepared.byNpc
    local count,personal,personalByNpc=prepared.count,prepared.personal,prepared.personalByNpc
    -- Save carrier: one stable table, so TaskJobs still detects a world swap by
    -- identity, holding detached copies only. Writing through it can never reach
    -- the authority above, and every commit mirrors one record so the engine's
    -- own world-file write always sees the current set without a flush hook.
    local carrier={format=1,byId={}}
    root.taskJobs=carrier
    local function mirror(key,value)
        carrier.byId[key]=value and detached(value) or nil
    end
    for key,value in pairs(data.byId) do mirror(key,value) end
    local api={}
    local listeners={}
    -- Derived admission index, rebuilt from the sole persistent Job authority.
    -- An incomplete native result may contain unknown ItemIDs, so per-item
    -- quarantine alone cannot authorize another executor in this scope.
    local unresolvedScopes={}
    local function indexAttempt(job,remove)
	local rule=contract(job.providerType)
	if not rule.blocksScope or not rule.blocksScope(job) then return end
	local set=unresolvedScopes[job.scopeId]
	if remove then
	    if set then set[job.id]=nil if empty(set) then unresolvedScopes[job.scopeId]=nil end end
	else
	    set=set or {} set[job.id]=true unresolvedScopes[job.scopeId]=set
	end
    end
    for _,job in pairs(data.byId) do indexAttempt(job) end
    function api:scopeBlocked(scopeId,exceptId)
	for key in pairs(unresolvedScopes[scopeId] or {}) do
            if key~=exceptId then return true,contract(data.byId[key].providerType).scopeBlockedReason end
        end
	return false
    end
    -- Scalar post-commit notifications. Observers only invalidate read models;
    -- their failure cannot roll back a Job or the physical effect it records.
    local function notify(job)
        for callback in pairs(listeners) do
            local ok=pcall(callback,job.scopeId,job.id,job.revision,job.providerType)
            if not ok then listeners[callback]=nil end
        end
    end
    function api:watch(callback)
        assert(type(callback)=='function','JOB_OBSERVER_REQUIRED')
        listeners[callback]=true
        return function() listeners[callback]=nil end
    end
    function api:ordinaryCount() return count end
    -- Scalar readers. They exist so decision and recovery paths can ask a
    -- question without ever holding the record; use get() when the caller
    -- genuinely needs the whole detached document.
    function api:state(key) local job=data.byId[key] return job and job.state end
    function api:revision(key) local job=data.byId[key] return job and job.revision end
    function api:providerType(key) local job=data.byId[key] return job and job.providerType end
    -- Sorted identity list for cold recovery passes. Returns keys only: the
    -- records themselves stay behind get/adopt so no live table leaves the
    -- store while a rebuild is rewriting state.
    function api:keys()
        local result={}
        for key in pairs(data.byId) do result[#result+1]=key end
        table.sort(result)
        return result
    end
    -- Cold-recovery write. Persisted records may need a state the live machine
    -- cannot reach (a crash mid-settle leaves SETTLING behind), so the Kernel
    -- transition table is skipped while field validation, the domain contract's
    -- record rules and the detached copy are all still enforced. Listeners are
    -- notified because observers rebuild read models from this revision.
    function api:adopt(key,patch)
        local old=data.byId[key]
        if not old then return false,'JOB_MISSING' end
        if type(patch)~='table' then return false,'JOB_PATCH_INVALID' end
        for field in pairs(patch) do
            if field~='state' and field~='effects' and field~='obligations' and field~='payload'
                and field~='claimId' then return false,'JOB_PATCH_INVALID' end
        end
        local candidate={} for field,value in pairs(old) do candidate[field]=value end
        for field,value in pairs(patch) do candidate[field]=value end
        candidate.revision=old.revision+1
        if not valid(candidate) then return false,'JOB_RECORD_INVALID' end
        local ok,value=pcall(detached,candidate) if not ok then return false,'JOB_DATA_UNSERIALIZABLE' end
        local allowed,why=obligationGuard(value,root.obligations)
        if not allowed then return false,why end
        indexAttempt(old,true)
        data.byId[key]=value
        mirror(key,value)
        indexAttempt(value)
        notify(value)
        return true,value.revision
    end
    -- Read-only live view for per-frame validation paths. Callers must not
    -- mutate the returned record; detached copies remain the only published form.
    function api:peek(key) return data.byId[key] end
    -- Same internal read-only contract as peek; uses the unique personal index.
    function api:peekPersonal(npcId) return data.byId[personalByNpc[npcId]] end
    -- Internal read-only visitor: use the existing index, without a whole-ledger scan or payload copies.
    function api:visitNpc(npcId,visitor)
        for key in pairs(byNpc[npcId] or {}) do local job=data.byId[key] if job then visitor(job) end end
    end
    function api:get(key) return data.byId[key] and detached(data.byId[key]) end
    function api:forNpc(npcId,providerType)
	if contract(providerType).persistentPersonal==true then
            local key=personalByNpc[npcId]
            return key and {detached(data.byId[key])} or {}
        end
        local result={}
        for key in pairs(byNpc[npcId] or {}) do
            local job=data.byId[key]
            if not providerType or job.providerType==providerType then result[#result+1]=detached(job) end
        end
        table.sort(result,function(a,b) return a.id<b.id end)
        return result
    end
    function api:create(job,obligationOps)
        if not valid(job) or job.revision~=1 or job.state~='PREPARING' or job.effects~='KNOWN' then return false,'JOB_RECORD_INVALID' end
        if data.byId[job.id] then return false,'JOB_EXISTS' end
	local blocked,reason=self:scopeBlocked(job.scopeId)
        if blocked then return false,reason end
	if personalJob(job) then
            if personalByNpc[job.npcId] then return false,'PERSONAL_JOB_EXISTS' end
            if personal>=Store.PERSONAL_LIMIT then return false,'PERSONAL_JOB_LIMIT' end
        elseif count>=Store.LIMIT then return false,'JOB_LIMIT' end
        local ok,value=pcall(detached,job) if not ok then return false,'JOB_DATA_UNSERIALIZABLE' end
        local ledger,carrierValue
        if obligationOps~=nil then
            local Ledger=require 'EmberRoutesProbe/Kernel/ObligationLedger'
            if not require('EmberRoutesProbe/Kernel/Validate').dense(obligationOps,Ledger.LIMIT) then return false,'OBLIGATION_INTENT_INVALID' end
            for _,op in ipairs(obligationOps) do
                if type(op)~='table' or op.action~='CREATE' or type(op.record)~='table'
                    or op.record.jobId~=job.id or op.record.npcId~=job.npcId then return false,'OBLIGATION_JOB_MISMATCH' end
            end
            local why
            ledger,why=Ledger.propose(root.obligations,obligationOps)
            if not ledger then return false,why end
            local claims={} for _,key in ipairs(value.payload.claims or {}) do claims[key]=true end
            for _,obligation in pairs(ledger.byId) do
                if obligation.jobId==job.id and obligation.state~='SETTLED' then
                    local key=Ledger.claimKey(obligation)
                    if key and not claims[key] then return false,'OBLIGATION_CLAIM_RETAINED' end
                end
            end
        end
        local expectedCid = tostring(job.id) .. ':c' .. tostring(root.nextClaimSeq or 0)
        local newSequence
        if not job.claimId or job.claimId ~= expectedCid then
            newSequence = (root.nextClaimSeq or 0) + 1
            value.claimId = tostring(job.id) .. ':c' .. tostring(newSequence)
        else
            value.claimId = job.claimId
        end
        local allowed,why=obligationGuard(value,ledger or root.obligations)
        if not allowed then return false,why end
        if ledger then
            local copied,detachedValue=pcall(detached,value)
            if not copied then return false,'JOB_DATA_UNSERIALIZABLE' end
            carrierValue=detachedValue
        end
        if newSequence then root.nextClaimSeq=newSequence end
        data.byId[value.id]=value
	if ledger then carrier.byId[value.id]=carrierValue root.obligations=ledger else mirror(value.id,value) end
	indexAttempt(value)
	if personalJob(value) then
            personal=personal+1 personalByNpc[value.npcId]=value.id
        else count=count+1 end
        byNpc[value.npcId]=byNpc[value.npcId] or {} byNpc[value.npcId][value.id]=true
        notify(value)
        return true
    end
    local function update(key,revision,patch,cancelling,obligationOps)
        local old=data.byId[key]
        if not old or old.revision~=revision then return false,'JOB_CHANGED' end
        if JobState.isTerminal(old.state) then return false,'JOB_TERMINAL' end
        if type(patch)~='table' then return false,'JOB_PATCH_INVALID' end
        for field in pairs(patch) do
            if field~='state' and field~='effects' and field~='obligations' and field~='payload' then return false,'JOB_PATCH_INVALID' end
        end
	local candidate={} for field,value in pairs(old) do candidate[field]=value end
        for field,value in pairs(patch) do candidate[field]=value end
        candidate.revision=revision+1
        if not valid(candidate) then return false,'JOB_RECORD_INVALID' end
	local rule=contract(old.providerType)
	if rule.transition and not cancelling then
	    local allowed,why=rule.transition(old,candidate)
	    if not allowed then return false,why end
        end
        if not cancelling and candidate.state~=old.state and not transitions[old.state][candidate.state] then return false,'JOB_TRANSITION_INVALID' end
        local ok,value=pcall(detached,candidate) if not ok then return false,'JOB_DATA_UNSERIALIZABLE' end
	local ledger,carrierValue
	if obligationOps~=nil then
	    local Ledger=require 'EmberRoutesProbe/Kernel/ObligationLedger'
	    if not require('EmberRoutesProbe/Kernel/Validate').dense(obligationOps,Ledger.LIMIT) then return false,'OBLIGATION_INTENT_INVALID' end
	    local validLedger,ledgerWhy=Ledger.check(root.obligations)
	    if not validLedger then return false,ledgerWhy end
	    for _,op in ipairs(obligationOps) do
	        if type(op)~='table' then return false,'OBLIGATION_INTENT_INVALID' end
	        local existing=root.obligations.byId[op.id]
	        local owner=op.action=='CREATE' and op.record and op.record.jobId or existing and existing.jobId
	        if owner~=key then return false,'OBLIGATION_JOB_MISMATCH' end
	        local worker=op.action=='CREATE' and op.record and op.record.npcId or existing and existing.npcId
	        if worker~=value.npcId then return false,'OBLIGATION_NPC_MISMATCH' end
            local allowed,reason=Contracts.validateObligationOperation(old,value,op,existing)
            if not allowed then return false,reason end
	    end
	    local why
            local function retireObligation(record)
                return rule.retireObligation and rule.retireObligation(old,value,record,obligationOps) or false
            end
	    ledger,why=Ledger.propose(root.obligations,obligationOps,retireObligation)
	    if not ledger then return false,why end
	    local copied,detachedValue=pcall(detached,value)
	    if not copied then return false,'JOB_DATA_UNSERIALIZABLE' end
	    carrierValue=detachedValue
	end
	local allowed,why=obligationGuard(value,ledger or root.obligations)
	if not allowed then return false,why end
	indexAttempt(old,true)
        data.byId[key]=value
	if ledger then
	    -- All candidate copies exist before the first write; no callback runs
	    -- between these publications. The caller owns the reentrancy fence.
	    carrier.byId[key]=carrierValue
	    root.obligations=ledger
	else mirror(key,value) end
	indexAttempt(value)
        notify(value)
        return true,value.revision
    end
    function api:update(key,revision,patch,obligationOps) return update(key,revision,patch,false,obligationOps) end
    -- Kernel cancel is distinct from ordinary transitions. Validity and domain
    -- record validation still apply; no obligations/claims may be discarded.
    function api:cancel(key,revision,patch,obligationOps)
        if type(patch)~='table' or patch.state~='CANCELLED' then return false,'CANCEL_PATCH_INVALID' end
        local old=data.byId[key]
        if not old or old.revision~=revision then return false,'JOB_CHANGED' end
        local payload=patch.payload or old.payload
        local effects=patch.effects or old.effects
        local obligations=patch.obligations or old.obligations
        if effects~='KNOWN' then return false,'CANCEL_BLOCKED_EFFECTS_UNKNOWN' end
        if not empty(obligations) then return false,'CANCEL_BLOCKED_OBLIGATIONS' end
        if #(payload.claims or {})>0 then return false,'CANCEL_BLOCKED_CLAIMS' end
        return update(key,revision,patch,true,obligationOps)
    end
    -- Only LaborStore's verified physical handoff uses this narrow operation.
    -- Ordinary update cannot rewrite stable ownership or the indexed NPC.
    function api:transferOwner(key,revision,candidate,obligationOps)
        local old=data.byId[key]
	local rule=old and contract(old.providerType) or {}
        if not old or old.revision~=revision or not valid(candidate)
	    or not rule.transferValid or not rule.transferValid(old,candidate) then return false,rule.transferReason or 'COOKING_HANDOFF_CHANGED' end
        for otherId in pairs(byNpc[candidate.npcId] or {}) do
            local other=data.byId[otherId]
            if not JobState.isTerminal(other.state) then
		if not personalJob(other) or other.effects~='KNOWN' or not empty(other.obligations)
                    or #(other.payload.claims or {})>0 then return false,'OTHER_TASK_RETAINED' end
            end
        end
        local ok,value=pcall(detached,candidate) if not ok then return false,'JOB_DATA_UNSERIALIZABLE' end
        local ledger,carrierValue
        do
            local Ledger=require 'EmberRoutesProbe/Kernel/ObligationLedger'
            local count,why=Ledger.outstanding(root.obligations,key)
            if not count then return false,why end
            if count>0 then
                if not require('EmberRoutesProbe/Kernel/Validate').dense(obligationOps,Ledger.LIMIT) then return false,'OBLIGATION_TRANSFER_REQUIRED' end
                local moved={}
                for _,op in ipairs(obligationOps) do
                    local record=type(op)=='table' and root.obligations.byId[op.id]
                    if not record or record.jobId~=key or record.npcId~=old.npcId or op.action~='TRANSFER'
                        or op.npcId~=candidate.npcId then return false,'OBLIGATION_TRANSFER_INVALID' end
                    moved[op.id]=true
                end
                for id,record in pairs(root.obligations.byId) do
                    if record.jobId==key and record.state~='SETTLED' and not moved[id] then return false,'OBLIGATION_TRANSFER_REQUIRED' end
                end
                ledger,why=Ledger.propose(root.obligations,obligationOps)
                if not ledger then return false,why end
                local copied,detachedValue=pcall(detached,value)
                if not copied then return false,'JOB_DATA_UNSERIALIZABLE' end
                carrierValue=detachedValue
            elseif obligationOps~=nil and #obligationOps>0 then return false,'OBLIGATION_TRANSFER_INVALID' end
        end
        local allowed,why=obligationGuard(value,ledger or root.obligations)
        if not allowed then return false,why end
        data.byId[key]=value
        if ledger then carrier.byId[key]=carrierValue root.obligations=ledger else mirror(key,value) end
        byNpc[old.npcId][key]=nil
        if empty(byNpc[old.npcId]) then byNpc[old.npcId]=nil end
        byNpc[value.npcId]=byNpc[value.npcId] or {} byNpc[value.npcId][key]=true
        notify(value)
        return true
    end
    function api:removeSettled(key,revision)
        local old=data.byId[key]
        if not old or old.revision~=revision then return false,'JOB_CHANGED' end
	if personalJob(old) or not JobState.isTerminal(old.state)
            or old.effects~='KNOWN' or not empty(old.obligations) then return false,'JOB_NOT_SETTLED' end
	local allowed,why=obligationGuard(old,root.obligations)
	if not allowed then return false,why end
	local retiredLedger
	do
	    local operations={}
	    for id,record in pairs(root.obligations.byId) do
	        if record.jobId==key and record.state=='SETTLED' then
	            operations[#operations+1]={action='RETIRE',id=id,expectedRevision=record.revision}
	        end
	    end
	    if #operations>0 then
	        retiredLedger,why=require('EmberRoutesProbe/Kernel/ObligationLedger').propose(root.obligations,operations,function(record)
	            return record.jobId==key and record.state=='SETTLED' and old.effects=='KNOWN'
	                and JobState.isTerminal(old.state) and #(old.payload.claims or {})==0
	        end)
	        if not retiredLedger then return false,why end
	    end
	end
	indexAttempt(old,true)
        data.byId[key]=nil mirror(key,nil)
	if retiredLedger then root.obligations=retiredLedger end
        byNpc[old.npcId][key]=nil
        if empty(byNpc[old.npcId]) then byNpc[old.npcId]=nil end
        count=count-1
        notify(old)
        return true
    end
    return api
end
Store.validate = valid
return Store
