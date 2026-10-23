-- Independent persistent Job identity. No Session, asset authority or scheduler.
local Store={LIMIT=512}
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
local function valid(job)
    return type(job)=='table' and id(job.id) and id(job.npcId) and id(job.providerType)
        and id(job.scopeId) and integer(job.revision) and job.revision>0 and states[job.state]
        and (job.effects=='KNOWN' or job.effects=='UNKNOWN') and type(job.obligations)=='table'
        and type(job.payload)=='table' and (not job.orderId or id(job.orderId))
        and (not terminal[job.state] or job.effects=='KNOWN' and empty(job.obligations))
end
local function legacy(root)
    local craft,labor=root.craftProbes,root.labor
    return root.job~=nil or craft and (type(craft)~='table' or type(craft.byNpc)~='table' or not empty(craft.byNpc))
        or labor and (type(labor)~='table' or type(labor.tasks)~='table' or not empty(labor.tasks))
end
function Store.open(root)
    if type(root)~='table' then return nil,'JOB_ROOT_INVALID' end
    if legacy(root) then return nil,'LEGACY_TASK_RESET_REQUIRED' end
    local saved=root.taskJobs
    if saved~=nil and (type(saved)~='table' or saved.format~=1 or type(saved.byId)~='table') then return nil,'JOB_FORMAT_UNSUPPORTED' end
    local data=saved or {format=1,byId={}}
    local byNpc,count={},0
    for key,job in pairs(data.byId) do
        if not valid(job) or job.id~=key then return nil,'JOB_RECORD_INVALID' end
        local ok=pcall(detached,job) if not ok then return nil,'JOB_DATA_UNSERIALIZABLE' end
        count=count+1 if count>Store.LIMIT then return nil,'JOB_LIMIT' end
        byNpc[job.npcId]=byNpc[job.npcId] or {} byNpc[job.npcId][key]=true
    end
    root.taskJobs=data
    local api={}
    function api:get(key) return data.byId[key] and detached(data.byId[key]) end
    function api:forNpc(npcId)
        local result={}
        for key in pairs(byNpc[npcId] or {}) do result[#result+1]=detached(data.byId[key]) end
        table.sort(result,function(a,b) return a.id<b.id end)
        return result
    end
    function api:create(job)
        if not valid(job) or job.revision~=1 or job.state~='PREPARING' or job.effects~='KNOWN' then return false,'JOB_RECORD_INVALID' end
        if data.byId[job.id] then return false,'JOB_EXISTS' end
        if count>=Store.LIMIT then return false,'JOB_LIMIT' end
        local ok,value=pcall(detached,job) if not ok then return false,'JOB_DATA_UNSERIALIZABLE' end
        data.byId[value.id]=value count=count+1
        byNpc[value.npcId]=byNpc[value.npcId] or {} byNpc[value.npcId][value.id]=true
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
        if candidate.state~=old.state and not transitions[old.state][candidate.state] then return false,'JOB_TRANSITION_INVALID' end
        local ok,value=pcall(detached,candidate) if not ok then return false,'JOB_DATA_UNSERIALIZABLE' end
        data.byId[key]=value
        return true,value.revision
    end
    return api
end
return Store
