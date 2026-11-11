-- Lua HOST parity only. Java compilation/bridge/game/performance UNVERIFIED.
local Jobs=require 'EmberRoutesProbe/Kernel/JobStore'
local Claims=require 'EmberRoutesProbe/Kernel/LaborClaims'
local Manifest=require 'EmberRoutesProbe/Hauling/HaulManifest'
local checks=0
local function check(v,m) checks=checks+1 assert(v,m) end
local function copy(t) if type(t)~='table' then return t end local r={} for k,v in pairs(t) do r[k]=copy(v) end return r end
local function equal(a,b)
    if type(a)~=type(b) then return false end
    if type(a)~='table' then return a==b end
    for k,v in pairs(a) do if not equal(v,b[k]) then return false end end
    for k in pairs(b) do if a[k]==nil then return false end end return true
end
local function setup(old)
    EmberRoutesProbeJava=nil
    local root={nextClaimSeq=0} local jobs=assert(Jobs.open(root))
    local state={root=root,claims=Claims.new(),tokens={}}
    local Store={data=function() return root end,ensureLoaded=function() return root end,claimsInstanceIdForTests=function() return tostring(state.claims) end}
    -- Test double for the production Store.capacityEntries contract (HaulJobs
    -- releaseItemId path reads through it); mirrors LaborStore over state.claims.
    function Store.capacityEntries(key, jobId)
        local bucket=key and state.claims.capacity[key]
        local entry=bucket and bucket.entries and bucket.entries[jobId]
        local items=entry and entry.items
        if not items then return nil end
        local copy={} for id,amount in pairs(items) do copy[id]=amount end return copy
    end
    function Store.getToken(id) return state.claims.tokensByTaskId[id] end
    local function alloc(r,id) r.nextClaimSeq=r.nextClaimSeq+1 return id..':c'..r.nextClaimSeq end
    local function clean(id) state.tokens[id]=nil end
    package.loaded['EmberRoutesProbe/Runtime/TaskJobs']={current=function() return jobs end}
    package.loaded['EmberRoutesProbe/Work/LaborStore']=Store
    package.loaded['EmberRoutesProbe/Warehouse/ContainerRegistry']={data=function() return root end}
    package.loaded['EmberRoutesProbe/Hauling/HaulJobs']=nil
    function Store.claimHaulJob(j)
        local t=assert(state.claims:acquire(j.id,j.payload.sequence,j.payload.claims,{claimId=j.claimId}))
        state.tokens[j.id]=t return t
    end
    function Store.validHaulJob(j,t) return jobs:peek(j.id).revision==j.revision and Store.getToken(j.id)==t end
    if old then dofile('tests/lua/fixtures/dec003-pre-kernel-commit.lua').install(Store,state,alloc,clean)
    else
        state.bridge=dofile('tests/lua/fixtures/dec003-kernel-host.lua')
        state.bridge.install(state,alloc,clean)
        require('EmberRoutesProbe/Work/LaborJobCommit').install(Store,state,alloc,clean)
    end
    local Haul
    if old then Haul=dofile('tests/lua/fixtures/dec003-pre-kernel-haul.lua')
    else Haul=require 'EmberRoutesProbe/Hauling/HaulJobs' end
    local r={id='haul',npcId='npc',format=3,executor='ENTITY',producer='LOGISTICS',settlementId='scope',
        source='source',destination='dest',generation=0,sequence=0,state='RUNNING',items={1,2},plannedCount=2,
        routeRevision=0,attemptSequence=0,delivered=0,withdrawn=0}
    r.manifest=Manifest.create(r)
    -- Items are identity-bearing host objects; commit must never move/recreate them.
    local items={{id=1,where='source',condition=73},{id=2,where='npc',condition=41}}
    local function snapshot()
        local owners={} for k,t in pairs(state.claims.owners) do owners[k]={id=t.taskId,claimId=t.claimId} end
        return copy({job=jobs:get('haul'),owners=owners,capacity=state.claims.capacity,items=items})
    end
    return Haul,Store,jobs,state,r,snapshot,items
end
local function run(old)
    local H,S,J,state,r,snapshot,items=setup(old) local out={}
    check(H.claim(r),'create/claim')
    check(J:get(r.id).revision==2 and J:get(r.id).state=='RUNNING','create 1 -> running 2')
    if not old then check(state.bridge.calls[1]=='laborCreate' and state.bridge.calls[2]=='laborMutate','real Lua facade dispatches create/mutate entries to host stand-in') end
    out.created=snapshot()
    check(H.capacity(r,'dest',{[1]=2,[2]=3},20),'reserve capacity')
    out.reserved=snapshot()
    -- An in-flight original and its attempt survive a commit unchanged.
    r.manifest[2].custodyState='CARRIED'
    r.activeAttempt={itemId=2,kind='PUT',attemptId='haul:put:1',fromId='npc',toId='dest'}
    check(H.commit(r),'in-flight commit')
    check(J:get(r.id).payload.activeAttempt.attemptId=='haul:put:1' and state.claims.owners['item:2'],'in-flight retained')
    out.inflight=snapshot()
    local rev=J:get(r.id).revision local before=snapshot()
    local ok,why=S.mutateJob(r.id,rev-1,copy(r),{})
    check(not ok and why=='STALE_REVISION' and equal(before,snapshot()),'stale no writes')
    out.stale={state=snapshot(),error=why}
    -- Same mismatch reaches old commit validation vs new HAUL entry policy.
    if old then ok,why=S.mutateJob(r.id,rev,copy(r),{capacity={key='dest',items={[1]=99},free=100}})
    else ok,why=H.commit(r,{key='dest',items={[1]=99},free=100}) end
    check(not ok and why==(old and 'CAPACITY_PAYLOAD_MISMATCH' or 'INVALID_REQUEST') and equal(before,snapshot()),'capacity-payload mismatch no writes')
    out.mismatch={state=snapshot(),error='INVALID_REQUEST',legacyError=old and why or 'CAPACITY_PAYLOAD_MISMATCH'}
    -- Real capacity contention exercises resource rollback, not a canned error.
    ok,why=H.capacity(r,'dest',{[1]=50},5)
    check(not ok and why==(old and 'CAPACITY_RESERVED' or 'CAPACITY_FAILURE')
        and equal(before,snapshot()) and r.reservation.items[1]==2,'capacity rejection restores authority and draft reservation')
    out.capacityFailure={state=snapshot(),error='CAPACITY_FAILURE'}
    -- Clear the attempt only after the host's simulated physical delivery.
    r.activeAttempt=nil
    items[1].where='dest' items[2].where='dest'
    check(H.settle(r,S.getToken(r.id),r.generation,{
        {itemId=1,state='DELIVERED',receipt={attemptId='put:1',destinationId='dest'}},
        {itemId=2,state='DELIVERED',receipt={attemptId='put:2',destinationId='dest'}}}),'settle originals')
    check(H.finish(r),'normal finish')
    check(J:get(r.id).state=='DONE' and not S.getToken(r.id) and not state.claims.capacity.dest,'terminal releases')
    out.done=snapshot()
    rev=J:get(r.id).revision
    ok,why=S.mutateJob(r.id,rev-1,J:get(r.id).payload,
        {state='DONE',effects='KNOWN',obligations={},addKeys={},removeKeys={}})
    check(not ok and why=='STALE_REVISION','successful commit retry is stale; no receipt')
    out.retry={state=snapshot(),error=why}
    return out
end
local old=run(true) local kernel=run(false)
for k,v in pairs(old) do check(equal(v,kernel[k]),'old/kernel host parity '..k) end
-- Kernel-specific cancellation contract: any nonterminal, asset-free only.
local H,S,J,state,r,snapshot=setup(false)
assert(H.claim(r))
local before=snapshot()
check(not H.cancel(r) and equal(before,snapshot()),'cancel retains outstanding originals')
for _,l in ipairs(r.manifest) do l.custodyState='WITHDRAWN' end
check(H.cancel(r),'cancel from RUNNING through laborCancel')
check(J:get(r.id).state=='CANCELLED' and not S.getToken(r.id)
    and state.bridge.calls[#state.bridge.calls]=='laborCancel','cancel releases token via cancel entry')
-- Entry policy/bridge fail-closed, never the frozen test implementation.
H,S,J,state,r,snapshot=setup(false)
r.source=nil local ok,why=H.claim(r)
check(not ok and why=='INVALID_REQUEST' and not J:get(r.id),'invalid draft refused before kernel create')
H,S,J,state,r,snapshot=setup(false)
EmberRoutesProbeJava=nil ok,why=H.claim(r)
check(not ok and why=='KERNEL_UNAVAILABLE' and not J:get(r.id),'missing bridge fail closed')
-- Published Store and recovery mutation chain, no direct jobs:update route.
H,S,J,state,r,snapshot=setup(false)
assert(H.claim(r)) local rev=J:get(r.id).revision
check(H.prepareRecovery(),'published recovery through bridge')
check(J:get(r.id).revision==rev+2 and J:get(r.id).state=='SUSPENDED'
    and J:get(r.id).payload.reason=='LOAD_RECOVERY' and state.claims.owners['item:1'],'recovery STOPPING/SUSPENDED preserves claims')
local saved=snapshot() check(H.prepareRecovery() and equal(saved,snapshot()),'recovery once per world')
-- Explicit CAS rejection: Phase 1 restores resource writes once, no quarantine.
local p=J:get(r.id).payload p.reservation={format=2,key='new',items={[1]=2}}
local original=J.update J.update=function() return false,'INJECTED_REJECT' end
ok,why=S.mutateJob(r.id,J:get(r.id).revision,p,{capacity={key='new',items={[1]=2},free=10}})
J.update=original
check(not ok and why=='TASK_WRITE_FAILURE' and equal(saved,snapshot()),'pre-CAS rollback preserves job/claim/capacity/items')
-- Recovery parity against the actual frozen HAUL direct-write implementation.
local function recovery(old,uncertain)
    local h,store,j,st,draft,snap=setup(old)
    assert(h.claim(draft))
    if uncertain then
        draft.activeAttempt={itemId=1,kind='TAKE',attemptId='take:1',fromId='source',toId='npc'}
        assert(h.commit(draft))
        -- Simulate reconstruction conflict: no runtime token, durable claims stay.
        st.claims:release(store.getToken(draft.id)) st.tokens[draft.id]=nil
    end
    h.prepareRecovery()
    local jnew=j:get(draft.id)
    check(jnew.payload.reason=='LOAD_RECOVERY' and #jnew.payload.claims==2,'recovery keeps durable responsibility')
    if uncertain then check(jnew.effects=='UNKNOWN' and jnew.payload.activeAttempt.attemptId=='take:1','unknown recovery without token retains in-flight work') end
    return snap()
end
check(equal(recovery(true,false),recovery(false,false)),'normal recovery old/kernel host parity')
check(equal(recovery(true,true),recovery(false,true)),'no-token uncertain recovery old/kernel host parity')
-- Directed release and failure paths beyond the parity chain.
H,S,J,state,r,snapshot=setup(false) assert(H.claim(r))
assert(H.capacity(r,'dest',{[1]=2,[2]=3},20))
check(H.releaseCapacity(r,1) and r.reservation.items[1]==nil
    and state.claims.capacity.dest.total==3,'release one capacity item through bridge')
check(H.releaseCapacity(r) and not state.claims.capacity.dest,'release entire capacity through bridge')
local malformed=copy(r) malformed.manifest[1].custodyState='INVALID'
ok,why=S.mutateJob(r.id,J:get(r.id).revision,malformed,{})
check(not ok and why=='TASK_WRITE_FAILURE','domain record validator remains Lua CAS policy')
-- Revised scope allows new addKeys inside the transaction; no threshold path.
r.items[3]=3 r.manifest[3]={itemId=3,sourceId='source',custodyState='UNCOLLECTED',deliveryPolicy='AUTO_STORAGE'} r.plannedCount=3
check(H.commit(r) and state.claims.owners['item:3']==S.getToken(r.id),'claim extension inside host kernel transaction')
-- Cancel bridge failure returns unchanged authority and restores draft reservation.
H,S,J,state,r,snapshot=setup(false) assert(H.claim(r))
assert(H.capacity(r,'dest',{[1]=2},20))
for _,l in ipairs(r.manifest) do l.custodyState='WITHDRAWN' end
before=snapshot() original=J.cancel J.cancel=function() return false,'INJECTED_CANCEL_REJECT' end
ok,why=H.cancel(r) J.cancel=original
check(not ok and why=='TASK_WRITE_FAILURE' and equal(before,snapshot()) and r.reservation.items[1]==2,'cancel rejection rolls back resources/draft reservation')
print('PASS '..checks..' HAUL migration host checks; old Lua vs Phase 1 Lua model parity; Java/game NOT RUN')
