-- QA overlay only. Never copied into the normal mod by the production build.
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local Store=require 'EmberRoutesProbe/LaborStore'
local Jobs=require 'EmberRoutesProbe/TaskJobs'
local Gate=require 'EmberRoutesProbe/RuntimeGate'
local Log=require 'EmberRoutesProbe/Log'
local Q={}
local KEY='b5AcceptanceFixture'
local function need(v,reason) if not v then error(reason) end return v end
local function session()
    _G.EmberRoutesB5QaSessionId=_G.EmberRoutesB5QaSessionId or Registry.id()
    return _G.EmberRoutesB5QaSessionId
end
local function allowed(actor)
    need(isDebugEnabled and isDebugEnabled() and Gate.isSinglePlayer(),'B5_DEBUG_SINGLEPLAYER_REQUIRED')
    need(actor and actor==getSpecificPlayer(0) and not actor:isDead(),'B5_LOCAL_LIVING_PLAYER_REQUIRED')
end
local function key(id) return 'item:'..tostring(id) end
local function create(id,itemIds,reservation)
    local materials,keys={},{}
    for _,itemId in ipairs(itemIds) do materials[#materials+1]={id=itemId} keys[#keys+1]=key(itemId) end
    need(Store.createClaimedJob({id=id,npcId=id,providerType='CRAFT',scopeId='B5_QA',revision=1,
	state='PREPARING',effects='KNOWN',obligations={asset=true},payload={format=4,sequence=0,
	recipeId='Base.MakeAxe',target=1,produced=0,materials=materials,tools={},outputs={},claims=keys,reservation=reservation}}),
	'B5_JOB_CREATE_FAILED')
    return need(Jobs.current():get(id),'B5_JOB_MISSING')
end
function Q.prepare(actor)
    allowed(actor)
    local root=Registry.data() local jobs=Jobs.current()
    need(root[KEY]==nil,'B5_FIXTURE_ALREADY_EXISTS')
    for _ in pairs(root.taskJobs.byId) do error('B5_EMPTY_JOB_LEDGER_REQUIRED') end
    for _ in pairs(root.quarantineResources or {}) do error('B5_EMPTY_QUARANTINE_REQUIRED') end
    local f={format=1,id=Registry.id(),items={},coldBoots=0,lastSession=session(),ready=false}
    root[KEY]=f -- Partial preparation stays diagnosable; never erase unknown responsibility.
    for _,role in ipairs({'collision','capacity','ordinary','invalid'}) do
	local item=need(actor:getInventory():AddItem('Base.Pencil'),'B5_SAMPLE_ITEM_UNAVAILABLE')
	f.items[role]=item:getID()
	local data=item:getModData() data.EmberRoutesProbeFixture=true data.EmberRoutesB5Sample=f.id
    end
    f.jobId='b5-collision:'..f.id f.capacityJobId='b5-capacity:'..f.id f.bucket='b5-bin:'..f.id
    local job=create(f.jobId,{f.items.collision}) f.originalClaimId=job.claimId
    for i=1,20 do
	need(Store.quarantineResource(key(f.items.collision),'B5_LEGAL_REPEAT',{fixtureId=f.id,ordinal=i}),'B5_QUARANTINE_FAILED')
    end
    -- Deliberate malformed-world fixture, not an application mutation API:
    -- a different participant cites the same persistent claim identity.
    local q=root.quarantineResources[key(f.items.collision)]
    q.originalTaskId='b5-other:'..f.id
    local capacity=create(f.capacityJobId,{f.items.capacity,f.items.ordinary},
	{key=f.bucket,items={[f.items.capacity]=3,[f.items.ordinary]=4},free=100})
    need(Store.quarantineResource(key(f.items.capacity),'B5_PARTIAL_CAPACITY',{fixtureId=f.id}),'B5_CAPACITY_QUARANTINE_FAILED')
    local p=capacity.payload p.materials={{id=f.items.capacity}} p.claims={key(f.items.capacity)}
    p.reservation.items={[f.items.capacity]=3}
    need(jobs:update(capacity.id,capacity.revision,{payload=p,state='RECONCILE_REQUIRED',effects='UNKNOWN'}),'B5_CAPACITY_JOB_UPDATE_FAILED')
    Store.claimsInstance():release(Store.getToken(capacity.id))
    need(Store.availableCapacity(f.bucket,100)==97,'B5_QUARANTINE_CAPACITY_LOST')
    need(Store.quarantineResource(key(f.items.invalid),'B5_INVALID_EVIDENCE',
	{fixtureId=f.id,bad=function() end}),'B5_INVALID_CREATION_MUST_PROTECT')
    need(not root.quarantineResources[key(f.items.invalid)].evidenceReport.complete,'B5_INVALID_EVIDENCE_UNMARKED')
    f.ready=true
    return 'PREPARED_SAVE_QUIT_AND_RELOAD fixture='..f.id..' job='..f.jobId..' originalClaimId='..f.originalClaimId
end
function Q.verify(actor)
    allowed(actor)
    local root=Registry.data() local f=need(root[KEY],'B5_FIXTURE_ABSENT')
    need(f.format==1 and f.ready,'B5_FIXTURE_INCOMPLETE')
    need(f.lastSession~=session(),'B5_SAME_LUA_SESSION_NOT_A_COLD_BOOT')
    Store.data() -- Read/rebuild the real current Claims instance; never clear runtime caches here.
    need(require('EmberRoutesProbe/JobStore').open(root),'B5_JOBSTORE_REOPEN_FAILED')
    local inventory=actor:getInventory():getItems() local found={}
    for i=0,inventory:size()-1 do
	local item=inventory:get(i)
	if item:getModData().EmberRoutesB5Sample==f.id then found[item:getID()]=item:getFullType() end
    end
    for _,id in pairs(f.items) do need(found[id]=='Base.Pencil','B5_PHYSICAL_SAMPLE_ID_CHANGED') end
    local job=need(Jobs.current():get(f.jobId),'B5_COLLISION_JOB_LOST')
    local prefix=type(job.claimId)=='string' and string.match(job.claimId,'^(.+):c%d+$')
    need(prefix==f.jobId and job.claimId~=f.originalClaimId,'B5_COLLISION_IDENTITY_NOT_LEGAL_OR_REKEYED')
    need(job.state=='RECONCILE_REQUIRED' and job.effects=='UNKNOWN','B5_COLLISION_NOT_ISOLATED')
    need(not f.acceptedClaimId or job.claimId==f.acceptedClaimId,'B5_RESTART_CHANGED_REASSIGNED_ID')
    need(Store.getToken(f.jobId)==nil,'B5_ISOLATED_JOB_REGAINED_TOKEN')
    for _,role in ipairs({'collision','capacity','invalid'}) do
	local owner=Store.resourceOwner(key(f.items[role]))
	need(owner and owner.kind=='SYSTEM_QUARANTINE','B5_ORIGINAL_NOT_PROTECTED:'..role)
    end
    local q=root.quarantineResources[key(f.items.collision)]
    need(q.originalClaimId==f.originalClaimId and q.evidence.identityCollisions
	and q.evidence.identityCollisions[f.jobId],'B5_COLLISION_EVIDENCE_LOST')
    need(q.evidenceReport.complete and #q.evidenceEvents.events==20,'B5_REPEAT_EVIDENCE_CHANGED')
    local c=Store.claimsInstance() local revision=c.revision local capKey=key(f.items.capacity)
    need(c:restoreQuarantine(capKey,root.quarantineResources[capKey]),'B5_REPEAT_RESTORE_REJECTED')
    need(c:restoreQuarantine(capKey,root.quarantineResources[capKey]),'B5_SECOND_RESTORE_REJECTED')
    need(c.revision==revision and Store.availableCapacity(f.bucket,100)==97,'B5_RESTORE_DOUBLE_COUNTED')
    local changed={} for k,v in pairs(root.quarantineResources[capKey]) do changed[k]=v end
    changed.capacityAmount=changed.capacityAmount+1
    need(not c:restoreQuarantine(capKey,changed),'B5_CONFLICTING_RESTORE_ACCEPTED')
    need(c.revision==revision and Store.availableCapacity(f.bucket,100)==97,'B5_CONFLICTING_RESTORE_CHANGED_STATE')
    local savedJob=Jobs.current():get(f.capacityJobId)
    local ok=Store.unquarantineResource(capKey,{reason='B5_INVALID_RELEASE'},{bad=function() end})
    need(not ok and c.revision==revision and Store.availableCapacity(f.bucket,100)==97,'B5_INVALID_RELEASE_CHANGED_OWNERSHIP')
    need(Jobs.current():get(f.capacityJobId).revision==savedJob.revision,'B5_INVALID_RELEASE_CHANGED_JOB')
    need(not root.quarantineResources[key(f.items.invalid)].evidenceReport.complete,'B5_INCOMPLETE_MARKER_LOST')
    f.acceptedClaimId=job.claimId f.lastSession=session() f.coldBoots=f.coldBoots+1
    return 'COLD_BOOT_PASS '..f.coldBoots..' capacity=3 originals=protected fixture='..f.id..' job='..f.jobId
	..' claimId='..job.claimId..' originalClaimId='..f.originalClaimId..' events=20'
	..' items='..f.items.collision..','..f.items.capacity..','..f.items.ordinary..','..f.items.invalid
end
function Q.execute(actor,command)
    local fn=command=='prepare' and Q.prepare or command=='verify' and Q.verify
    if not fn then return false,'B5_COMMAND_INVALID' end
    local ok,result=pcall(fn,actor)
    Log.write('B5_ACCEPTANCE',(ok and 'OK ' or 'FAIL ')..tostring(result))
    return ok,result
end
return Q
