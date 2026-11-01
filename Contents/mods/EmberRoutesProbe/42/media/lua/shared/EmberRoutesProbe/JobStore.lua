-- Independent persistent Job identity. No Session, asset authority or scheduler.
local Store={LIMIT=512,PERSONAL_LIMIT=256}
local states={PREPARING=true,RUNNING=true,STOPPING=true,SUSPENDED=true,SETTLING=true,
    DONE=true,CANCELLED=true,RECONCILE_REQUIRED=true}
local terminal={DONE=true,CANCELLED=true}
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
local function detached(value) return copy(value,{},{n=0},0) end
local function validClaimId(claimId, entityId)
    if type(claimId) ~= 'string' then return false end
    local prefix, seq = string.match(claimId, '^(.+):c(%d+)$')
    return prefix ~= nil and seq ~= nil and prefix == tostring(entityId)
end
local function valid(job)
    local basic=type(job)=='table' and id(job.id) and id(job.npcId) and id(job.providerType)
        and id(job.scopeId) and integer(job.revision) and job.revision>0 and states[job.state]
        and (job.effects=='KNOWN' or job.effects=='UNKNOWN') and type(job.obligations)=='table'
        and type(job.payload)=='table' and (not job.orderId or id(job.orderId))
        and (not terminal[job.state] or (job.effects=='KNOWN' and empty(job.obligations) and #(job.payload.claims or {}) == 0))
        and (job.claimId == nil or validClaimId(job.claimId, job.id))
    if not basic then return false end
    if job.providerType=='COOKING' then return require('EmberRoutesProbe/CookingRecord').valid(job)
    elseif job.providerType=='FIELD_WORK' then return require('EmberRoutesProbe/FieldRecord').valid(job)
    elseif job.providerType=='ACTIVITY' then return require('EmberRoutesProbe/ActivityRecord').valid(job)
    elseif job.providerType=='CRAFT' then
        local p = job.payload
        if p and p.format == 4 then return require('EmberRoutesProbe/CraftJobRecord').valid(job) end
        return require('EmberRoutesProbe/CraftRecord').valid(job.npcId, job.payload)
    elseif job.providerType=='HAUL' then
        local p = job.payload
        if p and p.format == 3 then return require('EmberRoutesProbe/HaulJobRecord').valid(job) end
        if p and p.format == 1 then
            return type(p.items) == 'table' and type(p.source) == 'string' and type(p.destination) == 'string'
        end
        return require('EmberRoutesProbe/HaulManifest').valid(job.payload)
    end
    return true
end
local function legacy(root)
    local craft,labor=root.craftProbes,root.labor
    return root.job~=nil or craft and (type(craft)~='table' or type(craft.byNpc)~='table' or not empty(craft.byNpc))
        or labor and (type(labor)~='table' or type(labor.tasks)~='table' or not empty(labor.tasks))
end
local function prepare(root)
    if type(root)~='table' then return nil,'JOB_ROOT_INVALID' end
    if legacy(root) then return nil,'LEGACY_TASK_RESET_REQUIRED' end
    local saved=root.taskJobs
    if saved~=nil and (type(saved)~='table' or saved.format~=1 or type(saved.byId)~='table') then return nil,'JOB_FORMAT_UNSUPPORTED' end
    local data=saved or {format=1,byId={}}
    local byNpc,count,personal,personalByNpc={},0,0,{}
    for key,job in pairs(data.byId) do
        if not valid(job) or job.id~=key then return nil,'JOB_RECORD_INVALID' end
        local ok=pcall(detached,job) if not ok then return nil,'JOB_DATA_UNSERIALIZABLE' end
        if job.providerType=='SELF_CARE' then
            if personalByNpc[job.npcId] then return nil,'PERSONAL_JOB_DUPLICATED' end
            personalByNpc[job.npcId]=key personal=personal+1
            if personal>Store.PERSONAL_LIMIT then return nil,'PERSONAL_JOB_LIMIT' end
        else
            count=count+1 if count>Store.LIMIT then return nil,'JOB_LIMIT' end
        end
        byNpc[job.npcId]=byNpc[job.npcId] or {} byNpc[job.npcId][key]=true
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
    root.taskJobs=data
    local api={}
    local listeners={}
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
        if providerType=='SELF_CARE' then
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
    function api:create(job)
        if not valid(job) or job.revision~=1 or job.state~='PREPARING' or job.effects~='KNOWN' then return false,'JOB_RECORD_INVALID' end
        if data.byId[job.id] then return false,'JOB_EXISTS' end
        if job.providerType=='SELF_CARE' then
            if personalByNpc[job.npcId] then return false,'PERSONAL_JOB_EXISTS' end
            if personal>=Store.PERSONAL_LIMIT then return false,'PERSONAL_JOB_LIMIT' end
        elseif count>=Store.LIMIT then return false,'JOB_LIMIT' end
        local ok,value=pcall(detached,job) if not ok then return false,'JOB_DATA_UNSERIALIZABLE' end
        local expectedCid = tostring(job.id) .. ':c' .. tostring(root.nextClaimSeq or 0)
        if not job.claimId or job.claimId ~= expectedCid then
            root.nextClaimSeq = (root.nextClaimSeq or 0) + 1
            value.claimId = tostring(job.id) .. ':c' .. tostring(root.nextClaimSeq)
        else
            value.claimId = job.claimId
        end
        data.byId[value.id]=value
        if value.providerType=='SELF_CARE' then
            personal=personal+1 personalByNpc[value.npcId]=value.id
        else count=count+1 end
        byNpc[value.npcId]=byNpc[value.npcId] or {} byNpc[value.npcId][value.id]=true
        notify(value)
        return true
    end
    function api:update(key,revision,patch)
        local old=data.byId[key]
        if not old or old.revision~=revision then return false,'JOB_CHANGED' end
        if terminal[old.state] then return false,'JOB_TERMINAL' end
        if type(patch)~='table' then return false,'JOB_PATCH_INVALID' end
        for field in pairs(patch) do
            if field~='state' and field~='effects' and field~='obligations' and field~='payload' then return false,'JOB_PATCH_INVALID' end
        end
        local candidate=detached(old)
        for field,value in pairs(patch) do candidate[field]=value end
        candidate.revision=revision+1
        if not valid(candidate) then return false,'JOB_RECORD_INVALID' end
        if old.providerType=='COOKING' and not require('EmberRoutesProbe/CookingRecord').transition(old,candidate) then
            return false,'COOKING_TRANSITION_INVALID'
        end
        if candidate.state~=old.state and not transitions[old.state][candidate.state] then return false,'JOB_TRANSITION_INVALID' end
        local ok,value=pcall(detached,candidate) if not ok then return false,'JOB_DATA_UNSERIALIZABLE' end
        data.byId[key]=value
        notify(value)
        return true,value.revision
    end
    -- Only LaborStore's verified physical handoff uses this narrow operation.
    -- Ordinary update cannot rewrite stable ownership or the indexed NPC.
    function api:transferCooking(key,revision,candidate)
        local old=data.byId[key]
        if not old or old.revision~=revision or not valid(candidate)
            or not require('EmberRoutesProbe/CookingRecord').transferValid(old,candidate) then return false,'COOKING_HANDOFF_CHANGED' end
        for otherId in pairs(byNpc[candidate.npcId] or {}) do
            local other=data.byId[otherId]
            if not terminal[other.state] then
                if other.providerType~='SELF_CARE' or other.effects~='KNOWN' or not empty(other.obligations)
                    or #(other.payload.claims or {})>0 then return false,'OTHER_TASK_RETAINED' end
            end
        end
        local ok,value=pcall(detached,candidate) if not ok then return false,'JOB_DATA_UNSERIALIZABLE' end
        data.byId[key]=value byNpc[old.npcId][key]=nil
        if empty(byNpc[old.npcId]) then byNpc[old.npcId]=nil end
        byNpc[value.npcId]=byNpc[value.npcId] or {} byNpc[value.npcId][key]=true
        notify(value)
        return true
    end
    function api:removeSettled(key,revision)
        local old=data.byId[key]
        if not old or old.revision~=revision then return false,'JOB_CHANGED' end
        if old.providerType=='SELF_CARE' or not terminal[old.state]
            or old.effects~='KNOWN' or not empty(old.obligations) then return false,'JOB_NOT_SETTLED' end
        data.byId[key]=nil
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
