-- Trusted executor adapter. Persist one Job envelope; business records are its
-- payload, never a second by-NPC persistent ledger. UI reads detached projections.
local Jobs=require 'EmberRoutesProbe/TaskJobs'
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local Signals=require 'EmberRoutesProbe/LaborSignals'
local M={}
local world,store,craft,haul
local function derived(r)
    local unknown=r.uncertain==true or r.controlUncertain==true or r.phase=='COMMITTING'
    local done=r.released==true or r.kind=='EXPLICIT_TRANSFER' and r.state=='DONE'
    local free=r.format==3 and require('EmberRoutesProbe/ProductionYield').assetFree(r)
    local state=unknown and 'RECONCILE_REQUIRED' or done and (r.state=='CANCELLED' and 'CANCELLED' or 'DONE')
        or r.state=='RUNNING' and 'RUNNING' or 'SUSPENDED'
    return state,unknown and 'UNKNOWN' or 'KNOWN',(done or free) and not unknown
end
local function obligationsMatch(value,cleared)
    if type(value)~='table' then return false end
    if not cleared and value.business~=true then return false end
    for key in pairs(value) do if cleared or key~='business' then return false end end
    return true
end
local function load()
    local root=Registry.data()
    if root==world then return end
    local opened=Jobs.current()
    local c,h={},{format=2,tasks={},byNpc={},routes=root.taskRoutes or {}}
    for id,j in pairs(root.taskJobs.byId) do
        local r=j.payload
        if j.providerType=='CRAFT' or j.providerType=='HAUL' then
        if r.id~=id or r.npcId~=j.npcId then error('JOB_PAYLOAD_INVALID') end
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
    end
    root.taskRoutes=h.routes world,store,craft,haul=root,opened,c,h
end
function M.crafts() load() return craft end
-- Trusted internal read-only lookup; avoids rebuilding the whole kind map.
function M.record(id,kind)
    load() local job=world.taskJobs.byId[id]
    if job and job.providerType==kind then return job.payload end
end
function M.records(kind)
    load() local result={}
    for id,j in pairs(world.taskJobs.byId) do if j.providerType==kind then result[id]=j.payload end end
    return result
end
function M.hauls() load() return haul end
function M.refresh(id)
    load() local j=world.taskJobs.byId[id]
    if not j or j.providerType~='CRAFT' and j.providerType~='HAUL' then return false end
    local r=j.payload local state,effects,cleared=derived(r)
    if not obligationsMatch(j.obligations,cleared) then j.obligations=cleared and {} or {business=true} end
    if j.state~=state or j.effects~=effects or j.businessGeneration~=r.generation then j.revision=j.revision+1 end
    j.state,j.effects,j.businessGeneration=state,effects,r.generation return true
end
function M.flush()
    load()
    if store:ordinaryCount()==0 then return end
    for _,j in pairs(world.taskJobs.byId) do
        if j.providerType=='CRAFT' or j.providerType=='HAUL' then
        local r=j.payload
        if r.id~=j.id or r.npcId~=j.npcId then error('JOB_ID_CHANGED') end
        local state,effects,cleared=derived(r)
        local obligations=j.obligations
        if not obligationsMatch(obligations,cleared) then obligations=cleared and {} or {business=true} end
        if j.state~=state or j.effects~=effects or j.businessGeneration~=r.generation then j.revision=j.revision+1 end
        j.state,j.effects,j.obligations,j.businessGeneration=state,effects,obligations,r.generation
        end
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
    -- Clear the executor selection now; normal-tick retirement removes the
    -- settled persistent Job only after body/claim/public checks also pass.
    if haul.byNpc[r.npcId]==r.id then haul.byNpc[r.npcId]=nil end
    haul.tasks[r.id]=nil return true
end
-- Called only on a later normal tick, never from a native completion callback.
function M.canRetire(id,orderId)
    load()
    local j=world.taskJobs.byId[id]
    if not j or (j.providerType~='CRAFT' and j.providerType~='HAUL')
        or (j.state~='DONE' and j.state~='CANCELLED') or j.effects~='KNOWN' then return false end
    for _ in pairs(j.obligations) do return false end
    local r=j.payload
    if r.uncertain or r.controlUncertain or r.phase=='COMMITTING' or r.reservation then return false end
    if j.providerType=='CRAFT' then
        if not r.released or (r.state~='DONE' and r.state~='CANCELLED') then return false end
        if r.state=='DONE' and r.format==3 and (r.delivered~=r.produced
            or r.produced<r.target and r.reason~='TARGET_REACHED') then return false end
    elseif r.state~='DONE' then return false
    elseif r.format==2 and (not require('EmberRoutesProbe/HaulManifest').valid(r)
        or #require('EmberRoutesProbe/HaulManifest').claimItemIds(r)>0 or r.activeAttempt) then return false end
    local runtime=require('EmberRoutesProbe/TaskRuntime').current()
    if not runtime or not runtime:accepting() or runtime:status(j.npcId,id) then return false end
    if world.executionSave and world.executionSave.state=='BLOCKED' then return false end
    if require('EmberRoutesProbe/LaborStore').hasTaskClaims(id) then return false end
    for key,o in pairs(world.publicWork and world.publicWork.orders or {}) do
        if o.jobId==id and key~=orderId then return false end
    end
    for _,o in pairs(world.deliveryOrders and world.deliveryOrders.orders or {}) do
        if o.jobId==id then return false end
    end
    for _,other in ipairs(store:forNpc(j.npcId,'SELF_CARE')) do
        if other.providerType=='SELF_CARE' then
            local ref=other.payload.resume
            if ref and ref.jobId==id and ref.state~='RESTORED' and ref.state~='INVALIDATED'
                and (other.effects~='KNOWN' or ref.state~='RESTORE_QUEUED') then return false end
        end
    end
    return true
end
function M.retire(id,orderId)
    if not M.canRetire(id,orderId) then return false end
    local j=world.taskJobs.byId[id] local r=j.payload
    -- A restored job may finish before the personal routine observes ACTIVE.
    -- Its settled result discharges that queued restoration, not its custody.
    for _,other in ipairs(store:forNpc(j.npcId,'SELF_CARE')) do
        local ref=other.providerType=='SELF_CARE' and other.payload.resume
        if ref and ref.jobId==id and ref.state=='RESTORE_QUEUED' then
            ref.state='RESTORED'
            if not store:update(other.id,other.revision,{payload=other.payload}) then return false end
        end
    end
    if not store:removeSettled(id,j.revision) then return false end
    if craft[j.npcId]==r then craft[j.npcId]=nil end
    haul.tasks[id]=nil
    if haul.byNpc[j.npcId]==id then haul.byNpc[j.npcId]=nil end
    local receipt=world.executionSave
    if receipt and receipt.byNpc and receipt.byNpc[j.npcId] and receipt.byNpc[j.npcId].jobId==id then
        receipt.byNpc[j.npcId]=nil
    end
    return true
end
function M.retireSettled(limit)
    load()
    if store:ordinaryCount()==0 then return 0 end
    M.flush()
    local ids={}
    for id,j in pairs(world.taskJobs.byId) do
        if j.providerType~='SELF_CARE' and (j.state=='DONE' or j.state=='CANCELLED') then ids[#ids+1]=id end
    end
    table.sort(ids)
    local n=0
    for _,id in ipairs(ids) do if M.retire(id) then n=n+1 if n>=limit then break end end end
    return n
end
-- Observer only updates metadata; physical claims stay in LaborStore.
Signals.watch(function() if world==Registry.data() then M.flush() end end)
return M
