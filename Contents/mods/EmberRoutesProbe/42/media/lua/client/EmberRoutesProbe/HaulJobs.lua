-- Haul execution drafts and verified manifest settlement. Persistent facts
-- remain in JobStore; all claims/capacity changes use LaborStore.mutateJob.
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local Jobs=require 'EmberRoutesProbe/TaskJobs'
local Store=require 'EmberRoutesProbe/LaborStore'
local Manifest=require 'EmberRoutesProbe/HaulManifest'
local Record=require 'EmberRoutesProbe/HaulJobRecord'
local M={}
local world,entries,byNpc,recovered=nil,{},{},nil
local function currentWorld()
    local root=Registry.data()
    if root~=world then world,entries,byNpc=root,{},{} end
    return root
end
local function entry(r) currentWorld() local e=r and entries[r.id] return e and e.record==r and e or nil end
local function adopt(job,r)
    local e={job=job,record=r or Jobs.current():get(job.id).payload} entries[job.id]=e byNpc[job.npcId]=e return e.record
end
function M.record(npcId)
    currentWorld() local jobs=Jobs.current() local e=byNpc[npcId]
    if e then
	local live=jobs:peek(e.job.id)
	if live and live.revision==e.job.revision and not e.failed then return e.record end
	entries[e.job.id]=nil byNpc[npcId]=nil
    end
    local selected
    for _,j in ipairs(jobs:forNpc(npcId,'HAUL')) do
	if j.payload.format==3 and j.payload.executor=='ENTITY' then
	    if not selected or selected.state=='DONE' and j.state~='DONE' then selected=j end
	end
    end
    return selected and adopt(selected) or nil
end
function M.commit(r,capacity)
    local e=entry(r)
    if not e or e.failed then return false,'HAUL_DRAFT_STALE' end
    if e.job.state=='DONE' or e.job.state=='CANCELLED' then return r.state==e.job.payload.state and r.generation==e.job.payload.generation,'JOB_TERMINAL' end
    local live=Jobs.current():peek(r.id)
    if not live or live.revision~=e.job.revision then e.failed=true return false,'HAUL_JOB_CHANGED' end
    r.sequence=r.generation r.claims=Record.activeClaims(r)
    if r.reservation and r.reservation.format==2 then
	local any=false for _ in pairs(r.reservation.items) do any=true break end
	if not any then r.reservation=nil end
    end
    local unknown=r.controlUncertain==true
    local target=unknown and 'RECONCILE_REQUIRED' or r.state=='DONE' and 'DONE' or r.state=='RUNNING' and 'RUNNING' or 'SUSPENDED'
    local effects=(unknown or r.activeAttempt~=nil) and 'UNKNOWN' or 'KNOWN'
    local cleared=target=='DONE'
    for _=1,3 do
	local state=target
	if target=='DONE' and e.job.state~='SETTLING' then state='SETTLING'
	elseif target=='SUSPENDED' and e.job.state=='RUNNING' then state='STOPPING'
	elseif target=='RUNNING' and e.job.state=='SUSPENDED' then state='PREPARING' end
	local token=Store.getToken(r.id)
	if not token then e.failed=true return false,'HAUL_TOKEN_MISSING' end
	local have,want,add,remove={},{},{},{}
	for _,key in ipairs(token.resources) do have[key]=true end
	for _,key in ipairs(r.claims) do want[key]=true if not have[key] then add[#add+1]=key end end
	for _,key in ipairs(token.resources) do if not want[key] then remove[#remove+1]=key end end
	local ok,why=Store.mutateJob(r.id,e.job.revision,r,{addKeys=add,removeKeys=remove,capacity=capacity,
	    state=state,effects=effects,obligations=cleared and {} or {business=true}})
	if not ok then
	    local current=Jobs.current():peek(r.id)
	    e.failed=not current or current.revision~=e.job.revision
	    return false,why
	end
	capacity=nil e.job=Jobs.current():get(r.id)
	if not e.job or e.job.revision~=why then e.failed=true return false,'HAUL_POST_COMMIT_CHANGED' end
	if e.job.state==target then return true end
    end
    e.failed=true return false,'HAUL_TRANSITION_UNRESOLVED'
end
function M.claim(r)
    currentWorld() local e=entry(r)
    if not e then
	for _,job in ipairs(Jobs.current():forNpc(r.npcId)) do
	    if job.providerType=='CRAFT' and job.state~='DONE' and job.state~='CANCELLED'
		and not require('EmberRoutesProbe/ProductionYield').assetFree(job.payload) then return nil,'OTHER_TASK_RETAINED' end
	end
	r.generation=(r.generation or 0)+1 r.sequence=r.generation r.claims=Record.activeClaims(r)
	local ok,why=Store.createClaimedJob({id=r.id,npcId=r.npcId,providerType='HAUL',scopeId=r.settlementId or r.scopeId,
	    orderId=r.orderId,revision=1,state='PREPARING',effects='KNOWN',obligations={business=true},payload=r})
	if not ok then return nil,why end
	local business=require('EmberRoutesProbe/BusinessJobs')
	local old=business.legacyHauls()
	old=old.tasks[old.byNpc[r.npcId]]
	if old and old.state=='DONE' then business.removeHaul(old) end
	adopt(Jobs.current():get(r.id),r)
    else
	if e.failed or e.job.effects=='UNKNOWN' then return nil,'HAUL_RECONCILE_REQUIRED' end
	local token,why=Store.claimHaulJob(e.job)
	if not token then return nil,why end
	r.generation=r.generation+1
    end
    local ok,why=M.commit(r)
    if not ok then return nil,why end
    return Store.claimHaulJob(entry(r).job)
end
function M.valid(r,generation,token)
    local e=entry(r)
    return e and not e.failed and r.state=='RUNNING' and r.generation==generation
	and Store.validHaulJob(e.job,token) or false
end
function M.capacity(r,key,weights,free)
    local before=r.reservation local amounts={}
    if before and before.key==key then for id,amt in pairs(before.items or {}) do amounts[id]=amt end end
    for id,amt in pairs(weights) do amounts[id]=amt end
    r.reservation={format=2,key=key,items=amounts}
    local ok,why=M.commit(r,{key=key,items=amounts,free=free})
    if not ok then r.reservation=before end return ok,why
end
function M.releaseCapacity(r,itemId)
    local before=r.reservation
    if not before then return true end
    if itemId then
	local amounts={} for id,amt in pairs(before.items) do if id~=itemId then amounts[id]=amt end end
	r.reservation={format=2,key=before.key,items=amounts}
    else r.reservation=nil end
    local cap=false if itemId then cap={releaseItemId=itemId} end
    local ok,why=M.commit(r,cap)
    if not ok then r.reservation=before end return ok,why
end
function M.settle(r,token,generation,changes)
    if not M.valid(r,generation,token) then return false,'HAUL_JOB_CHANGED' end
    for _,change in ipairs(changes) do
	local line=Manifest.line(r,change.itemId)
	if not line or (change.state~='DELIVERED' and change.state~='WITHDRAWN') then return false,'SETTLEMENT_INVALID' end
	if Manifest.pending(line) then
	    if change.state=='WITHDRAWN' and (line.custodyState~='UNCOLLECTED' or r.activeAttempt and r.activeAttempt.itemId==change.itemId)
		or change.state=='DELIVERED' and (not change.receipt or not change.receipt.attemptId or not change.receipt.destinationId) then return false,'SETTLEMENT_INVALID' end
	elseif line.custodyState~=change.state then return false,'SETTLEMENT_CHANGED' end
    end
    for _,change in ipairs(changes) do
	local line=Manifest.line(r,change.itemId) line.custodyState=change.state line.deliveryReceipt=change.receipt
	if r.reservation then r.reservation.items[change.itemId]=nil end
    end
    r.delivered,r.withdrawn=Manifest.count(r)
    return M.commit(r)
end
function M.finish(r)
    if r.controlUncertain or r.activeAttempt or #Manifest.claimItemIds(r)>0 then return false,'HAUL_OBLIGATION_RETAINED' end
    r.reservation=nil r.state='DONE' r.generation=r.generation+1
    return M.commit(r,false)
end
function M.prepareRecovery()
    local root=currentWorld() if recovered==root then return end
    local jobs=Jobs.current()
    for id,j in pairs(root.taskJobs.byId) do
	if j.providerType=='HAUL' and j.payload.format==3 and j.payload.executor=='ENTITY'
	    and j.state~='DONE' and j.state~='CANCELLED' then
	    local saved=jobs:get(id) local p=saved.payload local unknown=saved.effects=='UNKNOWN' or p.controlUncertain or p.activeAttempt~=nil
	    p.state='PAUSED' p.reason='LOAD_RECOVERY' p.generation=p.generation+1 p.sequence=p.generation
	    if unknown then p.controlUncertain=true end
	    local state=unknown and 'RECONCILE_REQUIRED' or 'SUSPENDED'
	    if saved.state=='RUNNING' and state=='SUSPENDED' then
		assert(jobs:update(id,saved.revision,{payload=p,state='STOPPING'}),'HAUL_RECOVERY_STOP_FAILED') saved=jobs:get(id)
	    end
	    assert(jobs:update(id,saved.revision,{payload=p,state=state,effects=unknown and 'UNKNOWN' or 'KNOWN'}),'HAUL_RECOVERY_FAILED')
	end
    end
    entries,byNpc={},{} recovered=root
end
function M.reset() entries,byNpc={},{} end
return M
