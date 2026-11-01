-- Production execution drafts. JobStore alone owns persistent records;
-- drafts authorize nothing without their captured revision and Claims token.
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local Jobs=require 'EmberRoutesProbe/TaskJobs'
local Store=require 'EmberRoutesProbe/LaborStore'
local Record=require 'EmberRoutesProbe/CraftJobRecord'
local Yield=require 'EmberRoutesProbe/ProductionYield'
local M={}
local world,entries,byNpc=nil,{},{}
local recoveredWorld
local function currentWorld()
    local root=Registry.data()
    if root~=world then world,entries,byNpc=root,{},{} end
    return root
end
local function entry(r)
    currentWorld()
    local e=r and entries[r.id]
    return e and e.record==r and e or nil
end
local function adopt(job,r)
    local e={job=job,record=r or Jobs.current():get(job.id).payload}
    entries[job.id]=e byNpc[job.npcId]=e
    return e.record
end
function M.record(npcId)
    currentWorld() local jobs=Jobs.current() local e=byNpc[npcId]
    if e then
	local live=jobs:peek(e.job.id)
	if live and live.revision==e.job.revision and not e.failed then return e.record end
	entries[e.job.id]=nil byNpc[npcId]=nil
    end
    local selected
    for _,job in ipairs(jobs:forNpc(npcId,'CRAFT')) do
	if job.payload.executor=='PRODUCTION' then
	    if not selected or selected.payload.released and not job.payload.released then selected=job end
	end
    end
    return selected and adopt(selected) or nil
end
local function desired(r)
    if r.uncertain then return 'RECONCILE_REQUIRED','UNKNOWN',false end
    if r.released then return r.state=='CANCELLED' and 'CANCELLED' or 'DONE','KNOWN',true end
    return r.state=='RUNNING' and 'RUNNING' or 'SUSPENDED',r.phase=='COMMITTING' and 'UNKNOWN' or 'KNOWN',Yield.assetFree(r)
end
local function nextState(from,to)
    if from==to then return to end
    if to=='DONE' or to=='CANCELLED' then return from=='SETTLING' and to or 'SETTLING' end
    if to=='SUSPENDED' and from=='RUNNING' then return 'STOPPING' end
    if to=='RUNNING' and (from=='SUSPENDED' or from=='RECONCILE_REQUIRED') then return from=='SUSPENDED' and 'PREPARING' or 'SUSPENDED' end
    return to
end
function M.commit(r)
    local e=entry(r)
    if not e or e.failed then return false,'PRODUCTION_DRAFT_STALE' end
    if e.job.state=='DONE' or e.job.state=='CANCELLED' then return r.state==e.job.payload.state and r.generation==e.job.payload.generation,'JOB_TERMINAL' end
    local live=Jobs.current():peek(r.id)
    if not live or live.revision~=e.job.revision then e.failed=true return false,'PRODUCTION_JOB_CHANGED' end
    r.sequence=r.generation r.claims=Record.activeClaims(r)
    local target,effects,cleared=desired(r)
    local obligations=cleared and {} or {business=true}
    for _=1,3 do
	local state=nextState(e.job.state,target)
	local token=Store.getToken(r.id)
	if not token then e.failed=true return false,'PRODUCTION_TOKEN_MISSING' end
	local have,want,add,remove={},{},{},{}
	for _,key in ipairs(token.resources) do have[key]=true end
	for _,key in ipairs(r.claims) do want[key]=true if not have[key] then add[#add+1]=key end end
	for _,key in ipairs(token.resources) do if not want[key] then remove[#remove+1]=key end end
	local ok,why=Store.mutateJob(r.id,e.job.revision,r,
	    {addKeys=add,removeKeys=remove,state=state,effects=effects,obligations=obligations})
	if not ok then e.failed=true return false,why end
	e.job=Jobs.current():get(r.id)
	if not e.job or e.job.revision~=why then e.failed=true return false,'PRODUCTION_POST_COMMIT_CHANGED' end
	if e.job.state==target then return true end
    end
    e.failed=true return false,'PRODUCTION_TRANSITION_UNRESOLVED'
end
function M.create(r)
    currentWorld()
    for _,old in ipairs(Jobs.current():forNpc(r.npcId,'CRAFT')) do
	if old.state~='DONE' and old.state~='CANCELLED' then return nil,'OTHER_TASK_RETAINED' end
    end
    r.format,r.executor,r.sequence=4,'PRODUCTION',r.generation
    r.claims=Record.activeClaims(r)
    local job={id=r.id,npcId=r.npcId,providerType='CRAFT',scopeId=r.settlementId,
	orderId=r.orderId,revision=1,state='PREPARING',effects='KNOWN',obligations={business=true},payload=r}
    local ok,why=Store.createClaimedJob(job)
    if not ok then return nil,why end
    adopt(Jobs.current():get(r.id),r)
    local token=Store.getToken(r.id)
    local saved,reason=M.commit(r)
    if not saved then return nil,reason end
    return token
end
function M.claim(r,returnOnly)
    local e=entry(r)
    if not e or e.failed or e.job.effects=='UNKNOWN' and not returnOnly then return nil,'PRODUCTION_RECONCILE_REQUIRED' end
    local token,why=Store.claimCraft(e.job,returnOnly)
    if not token then return nil,why end
    local ok,reason=M.commit(r)
    if not ok then return nil,reason end
    -- A resumed attempt publishes its new execution sequence before reacquiring.
    return Store.claimCraft(e.job,returnOnly)
end
function M.valid(r,token,key)
    local e=entry(r)
    return e and not e.failed and Store.validCraft(e.job,token,key) or false
end
function M.replace(r,token,proposed)
    if not M.valid(r,token) then return false,'PRODUCTION_JOB_CHANGED' end
    local before={} for k,v in pairs(r) do before[k]=v end
    for k in pairs(r) do r[k]=nil end for k,v in pairs(proposed) do r[k]=v end
    local ok,why=M.commit(r)
    if not ok then for k in pairs(r) do r[k]=nil end for k,v in pairs(before) do r[k]=v end end
    return ok,why
end
function M.beginEffect(r,token)
    if not M.valid(r,token) or r.nativeAttempt and r.nativeAttempt.state~='APPLIED' then return nil,'PRODUCTION_ATTEMPT_RETAINED' end
    r.nativeAttempt={format=1,id=Registry.id(),sequence=r.generation,state='COMMITTING',recipeId=r.recipeId,signature=r.signature}
    r.phase='COMMITTING'
    local ok,why=M.commit(r)
    return ok and r.nativeAttempt.id or nil,why
end
local function sameReceipt(a,b)
    if not a or a.complete~=b.complete or a.reason~=b.reason or #a.outputs~=#b.outputs or #a.consumed~=#b.consumed then return false end
    for i,o in ipairs(a.outputs) do if o.id~=b.outputs[i].id or o.fullType~=b.outputs[i].fullType then return false end end
    for i,id in ipairs(a.consumed) do if id~=b.consumed[i] then return false end end
    return true
end
function M.observe(r,attemptId,complete,reason)
    local e=entry(r)
    if not e or not r.nativeAttempt or r.nativeAttempt.id~=attemptId then return false,'PRODUCTION_ATTEMPT_CHANGED' end
    local receipt={format=1,attemptId=attemptId,complete=complete==true,outputs={},consumed={}}
    if reason then receipt.reason=string.sub(tostring(reason),1,256) end
    for _,o in ipairs(r.outputs) do receipt.outputs[#receipt.outputs+1]={id=o.id,fullType=o.fullType} end
    for _,m in ipairs(r.materials) do if m.consumed then receipt.consumed[#receipt.consumed+1]=m.id end end
    local prior=e.observed and e.observed[attemptId]
    if prior then
	if sameReceipt(prior.receipt,receipt) then return prior.ok,prior.reason end
	return false,'PRODUCTION_OBSERVATION_CHANGED'
    end
    local saved=e.job.payload.nativeAttempt
    if saved and saved.id==attemptId and saved.observation then
	if sameReceipt(saved.observation,receipt) then return saved.state=='APPLIED','PRODUCTION_OBSERVATION_RECORDED' end
	return false,'PRODUCTION_OBSERVATION_CHANGED'
    end
    e.observed={}
    e.observed[attemptId]={receipt=receipt,ok=false,reason='PRODUCTION_OBSERVATION_PENDING'}
    r.nativeAttempt.observation=receipt r.nativeAttempt.state=complete and 'APPLIED' or 'UNKNOWN'
    if not complete then r.uncertain=true r.phase='RECONCILE_REQUIRED' end
    local ok,why=M.commit(r)
    e.observed[attemptId].ok=ok e.observed[attemptId].reason=why
    if ok then return true end
    local fresh=Jobs.current():get(r.id)
    if fresh and fresh.payload.nativeAttempt and fresh.payload.nativeAttempt.id==attemptId
	and fresh.payload.nativeAttempt.state=='APPLIED' and sameReceipt(fresh.payload.nativeAttempt.observation,receipt) then
	return false,'PRODUCTION_POST_COMMIT_CHANGED'
    end
    -- Native effects cannot be rolled back by refusing a draft. Keep each known
    -- output on the existing persistent system-owned quarantine, with provenance.
    for _,o in ipairs(receipt.outputs) do
	Store.quarantineResource('item:'..o.id,'CRAFT_RESULT_UNCOMMITTED',
	    {jobId=r.id,claimId=e.job.claimId,attemptId=attemptId,observation=receipt})
    end
    if fresh and fresh.payload.nativeAttempt and fresh.payload.nativeAttempt.id==attemptId
	and fresh.payload.nativeAttempt.sequence==r.nativeAttempt.sequence
	and fresh.payload.nativeAttempt.state~='APPLIED' then
	fresh.payload.nativeAttempt.observation=receipt fresh.payload.nativeAttempt.state='UNKNOWN'
	fresh.payload.uncertain=true fresh.payload.phase='RECONCILE_REQUIRED' fresh.payload.state='PAUSED'
	Jobs.current():update(fresh.id,fresh.revision,{payload=fresh.payload,effects='UNKNOWN',state='RECONCILE_REQUIRED'})
    end
    return false,why
end
function M.reset() entries,byNpc={},{} end
function M.prepareRecovery()
    local root=currentWorld()
    if recoveredWorld==root then return end
    local jobs=Jobs.current()
    for id,live in pairs(root.taskJobs.byId) do
	if live.providerType=='CRAFT' and live.payload.executor=='PRODUCTION'
	    and live.state~='DONE' and live.state~='CANCELLED' then
	    local job=jobs:get(id) local p=job.payload
	    local unknown=job.effects=='UNKNOWN' or p.phase=='COMMITTING' or p.uncertain
	    p.state='PAUSED' p.reason='LOAD_RECOVERY' p.generation=p.generation+1 p.sequence=p.generation
	    if unknown then
		p.uncertain=true p.phase='RECONCILE_REQUIRED'
		if p.nativeAttempt then p.nativeAttempt.state='UNKNOWN' end
	    end
	    local target=unknown and 'RECONCILE_REQUIRED' or 'SUSPENDED'
	    if job.state=='RUNNING' and target=='SUSPENDED' then
		assert(jobs:update(id,job.revision,{payload=p,state='STOPPING'}),'PRODUCTION_RECOVERY_STOP_FAILED')
		job=jobs:get(id)
	    end
	    assert(jobs:update(id,job.revision,{payload=p,state=target,effects=unknown and 'UNKNOWN' or 'KNOWN'}),'PRODUCTION_RECOVERY_FAILED')
	end
    end
    entries,byNpc={},{} recoveredWorld=root
end
return M
