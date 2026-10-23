-- Trusted executor adapter. Persist one Job envelope; business records are its
-- payload, never a second by-NPC persistent ledger. UI reads detached projections.
local Jobs=require 'EmberRoutesProbe/JobStore'
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local Signals=require 'EmberRoutesProbe/LaborSignals'
local M={}
local world,store,craft,haul
local function derived(r)
    local unknown=r.uncertain==true or r.controlUncertain==true or r.phase=='COMMITTING'
    local done=r.released==true or r.kind=='EXPLICIT_TRANSFER' and r.state=='DONE'
    local state=unknown and 'RECONCILE_REQUIRED' or done and (r.state=='CANCELLED' and 'CANCELLED' or 'DONE')
        or r.state=='RUNNING' and 'RUNNING' or 'SUSPENDED'
    return state,unknown and 'UNKNOWN' or 'KNOWN',done and not unknown and {} or {business=true}
end
local function load()
    local root=Registry.data()
    if root==world then return end
    local opened,reason=Jobs.open(root) if not opened then error(reason) end
    local c,h={},{format=2,tasks={},byNpc={},routes=root.taskRoutes or {}}
    for id,j in pairs(root.taskJobs.byId) do
        local r=j.payload
        if r.id~=id or r.npcId~=j.npcId or (j.providerType~='CRAFT' and j.providerType~='HAUL') then error('JOB_PAYLOAD_INVALID') end
        if j.providerType=='CRAFT' then
            local previous=c[r.npcId]
            if previous and not previous.released and not r.released then error('NPC_TASK_CONFLICT') end
            if not previous or previous.released then c[r.npcId]=r end
        else
            local previous=h.tasks[h.byNpc[r.npcId]]
            if previous and previous.state~='DONE' and r.state~='DONE' then error('NPC_TASK_CONFLICT') end
            h.tasks[id]=r
            if not previous or previous.state=='DONE' then h.byNpc[r.npcId]=id end
        end
    end
    root.taskRoutes=h.routes world,store,craft,haul=root,opened,c,h
end
function M.crafts() load() return craft end
function M.records(kind)
    load() local result={}
    for id,j in pairs(world.taskJobs.byId) do if j.providerType==kind then result[id]=j.payload end end
    return result
end
function M.hauls() load() return haul end
function M.flush()
    load()
    for _,j in pairs(world.taskJobs.byId) do
        local r=j.payload
        if r.id~=j.id or r.npcId~=j.npcId then error('JOB_ID_CHANGED') end
        local state,effects,obligations=derived(r)
        if j.state~=state or j.effects~=effects or j.businessGeneration~=r.generation then j.revision=j.revision+1 end
        j.state,j.effects,j.obligations,j.businessGeneration=state,effects,obligations,r.generation
    end
end
local function publish(r,kind)
    load()
    if world.taskJobs.byId[r.id] then
        return world.taskJobs.byId[r.id].payload==r,'JOB_EXISTS'
    end
    local ok,reason=store:create({id=r.id,npcId=r.npcId,providerType=kind,scopeId=r.settlementId or 'local-world',
        orderId=r.orderId,revision=1,state='PREPARING',effects='KNOWN',obligations={},payload=r})
    if not ok then return false,reason end
    -- Only backend owners obtain this mutable reference. Store.create already
    -- checked serializability; retain executor identity for late-callback fences.
    world.taskJobs.byId[r.id].payload=r
    if kind=='CRAFT' then craft[r.npcId]=r else haul.tasks[r.id]=r haul.byNpc[r.npcId]=r.id end
    M.flush() return true
end
function M.publishCraft(r) return publish(r,'CRAFT') end
function M.publishHaul(r) return publish(r,'HAUL') end
function M.removeHaul(r)
    load()
    if r.state~='DONE' then return false,'JOB_NOT_SETTLED' end
    -- Keep settled Job facts until an explicit bounded history policy removes
    -- them. Clear only this executor's derived current selection.
    if haul.byNpc[r.npcId]==r.id then haul.byNpc[r.npcId]=nil end
    haul.tasks[r.id]=nil return true
end
-- Observer only updates metadata; physical claims stay in LaborStore.
Signals.watch(function() if world==Registry.data() then M.flush() end end)
return M
