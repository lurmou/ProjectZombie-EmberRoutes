-- Trusted executor adapter. Persist one Job envelope; business records are its
-- payload, never a second by-NPC persistent ledger. UI reads detached projections.
local Jobs=require 'EmberRoutesProbe/Runtime/TaskJobs'
local JobState=require 'EmberRoutesProbe/Kernel/JobState'
local Registry=require 'EmberRoutesProbe/Warehouse/ContainerRegistry'
local SelfCareCommit=require 'EmberRoutesProbe/SelfCare/SelfCareCommit'
local M={}
local world,store
local function load()
    local root=Registry.data()
    if root==world then return end
    local opened=Jobs.current()
    world,store=root,opened
end
function M.crafts()
    load() local result={}
    for id,j in pairs(world.taskJobs.byId) do
	if j.providerType=='CRAFT' and j.payload.format==4 and j.payload.executor=='PRODUCTION' then
	    local old=result[j.npcId]
	    if not old or old.released then result[j.npcId]=store:get(id).payload end
	end
    end
    return result
end
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
function M.hauls()
    load() local result={format=3,tasks={},byNpc={},routes={}}
    for id,j in pairs(world.taskJobs.byId) do
	if j.providerType=='HAUL' and j.payload.format==3 and j.payload.executor=='ENTITY' then
	    local r=store:get(id).payload result.tasks[id]=r
	    local old=result.tasks[result.byNpc[j.npcId]]
	    if not old or old.state=='DONE' then result.byNpc[j.npcId]=id end
	end
    end
    return result
end
-- Called only on a later normal tick, never from a native completion callback.
function M.canRetire(id,orderId)
    load()
    local j=world.taskJobs.byId[id]
    if not j then return false end
    local module=require('EmberRoutesProbe/Kernel/DomainRegistry').retirementModule(j.providerType)
    if not module or not JobState.isTerminal(j.state) or j.effects~='KNOWN' then return false end
    for _ in pairs(j.obligations) do return false end
    local r=j.payload
    if r.uncertain or r.controlUncertain or r.phase=='COMMITTING' or r.reservation then return false end
    if not require(module).valid(r) then return false end
    local runtime=require('EmberRoutesProbe/Runtime/TaskRuntime').current()
    if not runtime or not runtime:accepting() or runtime:status(j.npcId,id) then return false end
    if world.executionSave and world.executionSave.state=='BLOCKED' then return false end
    if require('EmberRoutesProbe/Work/LaborStore').hasTaskClaims(id) then return false end
    for key,o in pairs(world.publicWork and world.publicWork.orders or {}) do
        if o.jobId==id and key~=orderId then return false end
    end
    for _,o in pairs(world.deliveryOrders and world.deliveryOrders.orders or {}) do
        if o.jobId==id then return false end
    end
    for _,other in ipairs(store:forNpc(j.npcId,'SELF_CARE')) do
        if other.providerType=='SELF_CARE' then
            local ref=other.payload.resume
            if ref and ref.jobId==id and require('EmberRoutesProbe/Runtime/TaskResume').pending(ref,other.npcId)
                and (other.effects~='KNOWN' or ref.state~='RESTORE_QUEUED') then return false end
        end
    end
    return true
end
function M.retire(id,orderId)
    if not M.canRetire(id,orderId) then return false end
    local j=world.taskJobs.byId[id]
    -- A restored job may finish before the personal routine observes ACTIVE.
    -- Its settled result discharges that queued restoration, not its custody.
    for _,other in ipairs(store:forNpc(j.npcId,'SELF_CARE')) do
        local ref=other.providerType=='SELF_CARE' and other.payload.resume
        if ref and ref.jobId==id and ref.state=='RESTORE_QUEUED' then
            ref.state='RESTORED'
            if not SelfCareCommit.update(other.id,other.revision,{payload=other.payload}) then return false end
        end
    end
    if not store:removeSettled(id,j.revision) then return false end
    local receipt=world.executionSave
    if receipt and receipt.byNpc and receipt.byNpc[j.npcId] and receipt.byNpc[j.npcId].jobId==id then
        receipt.byNpc[j.npcId]=nil
    end
    return true
end
function M.retireSettled(limit)
    load()
    if store:ordinaryCount()==0 then return 0 end
    local n=0
    for id,j in pairs(world.taskJobs.byId) do
        if j.providerType~='SELF_CARE' and JobState.isTerminal(j.state) then
            if M.retire(id) then
                n=n+1
                if n>=limit then break end
            end
        end
    end
    return n
end
return M
