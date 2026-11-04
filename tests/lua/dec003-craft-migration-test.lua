-- Lua HOST parity only. Frozen old code is a TEST-ONLY oracle, never a fallback.
-- Java compilation, real bridge calls, game, disk reload and performance UNVERIFIED.
local Jobs=require 'EmberRoutesProbe/JobStore'
local Claims=require 'EmberRoutesProbe/LaborClaims'
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
    local state={root=root,claims=Claims.new(),tokens={},published=false}
    local S={}
    function S.data() state.published=true return root end
    function S.getToken(id) return state.tokens[id] end
    local function alloc(r,id) r.nextClaimSeq=r.nextClaimSeq+1 return id..':c'..r.nextClaimSeq end
    local function clean(id) state.tokens[id]=nil end
    package.loaded['EmberRoutesProbe/TaskJobs']={current=function() return jobs end}
    package.loaded['EmberRoutesProbe/LaborStore']=S
    package.loaded['EmberRoutesProbe/ContainerRegistry']={data=function() return root end,id=function() return 'attempt:1' end}
    package.loaded['EmberRoutesProbe/ProductionJobs']=nil
    -- Actual same-fact adapter/generation fence, not a permissive claim mock.
    require('EmberRoutesProbe/LaborDomainAdapters').install(S,state,function() error('unexpected identity allocation') end,clean,function() return true end)
    if old then dofile('tests/lua/fixtures/dec003-pre-kernel-commit.lua').install(S,state,alloc,clean)
    else
        state.bridge=dofile('tests/lua/fixtures/dec003-craft-kernel-host.lua')
        state.bridge.install(state,alloc,clean)
        require('EmberRoutesProbe/LaborJobCommit').install(S,state,alloc,clean)
    end
    function S.quarantineResource() error('quarantine must not run in directed chain') end
    local P=old and dofile('tests/lua/fixtures/dec003-pre-kernel-production.lua') or require 'EmberRoutesProbe/ProductionJobs'
    local r={id='craft',npcId='npc',requester='player',settlementId='scope',recipeId='saw',recipeName='Saw',
        signature='saw:1',product='Base.Plank',requested=1,target=1,unitYield=1,produced=0,delivered=0,
        generation=0,state='RUNNING',phase='CRAFTING',released=false,benchId='bench',
        materials={{id=1,slot=0,source='stock'}},tools={{id=2,slot=1,source='stock'}},outputs={}}
    local items={{id=1,where='npc',condition=73},{id=2,where='npc',condition=41}}
    local function snap()
        local owners={} for k,t in pairs(state.claims.owners) do owners[k]={id=t.taskId,claimId=t.claimId} end
        local token=S.getToken(r.id)
        return copy({job=jobs:get(r.id),owners=owners,capacity=state.claims.capacity,items=items,
            resources=token and token.resources,tokenGeneration=token and token.generation})
    end
    return P,S,jobs,state,r,snap,items
end
local function run(old)
    local P,S,J,st,r,snap,items=setup(old) local out={}
    check(P.create(r),'create') check(J:get(r.id).revision==2,'create rev1 -> running rev2') out.created=snap()
    check(P.claim(r),'same-fact claim') check(J:get(r.id).revision==3,'claim commits revision') out.claimed=snap()
    local attempt=assert(P.beginEffect(r,S.getToken(r.id)))
    check(J:get(r.id).effects=='UNKNOWN' and J:get(r.id).payload.nativeAttempt.state=='COMMITTING','in-flight effect durable') out.committing=snap()
    -- Explicit host simulation of irreversible native effects; commits do not move items.
    r.materials[1].consumed=true items[1].where='consumed'
    items[3]={id=3,where='npc',condition=100}
    r.outputs={{id=3,fullType='Base.Plank',delivered=false}} r.produced=1 r.phase='CONFIRMED'
    check(P.observe(r,attempt,true),'observe APPLIED')
    check(J:get(r.id).payload.nativeAttempt.state=='APPLIED' and st.claims.owners['item:3']==S.getToken(r.id)
        and not st.claims.owners['item:1'],'new output claimed; consumed original shrunk') out.applied=snap()
    local before=snap() check(P.observe(r,attempt,true) and equal(before,snap()),'receipt idempotency')
    -- Host simulates verified output delivery and tool return before business release.
    items[2].where='stock' items[3].where='destination'
    r.outputs[1].delivered=true r.delivered=1 r.released=true r.state='DONE' r.phase='DONE'
    local steps={} local update=J.update
    J.update=function(self,id,rev,patch) steps[#steps+1]={state=patch.state,revision=rev+1} return update(self,id,rev,patch) end
    check(P.commit(r),'normal DONE')
    check(#steps==2 and steps[1].state=='SETTLING' and steps[2].state=='DONE' and J:get(r.id).revision==7,'step-wise revisions retained')
    check(not S.getToken(r.id) and not next(st.claims.owners) and not next(st.claims.capacity),'terminal releases claims, capacity N/A')
    out.done=snap() out.steps=steps
    if not old then check(st.bridge.calls[1]=='laborCreate' and st.bridge.calls[2]=='laborMutate','real facade dispatch to host model') end
    return out
end
local old,new=run(true),run(false)
for k,v in pairs(old) do check(equal(v,new[k]),'old/kernel host parity '..k) end
local function stale(old)
    local P,S,J,st,r,snap=setup(old) assert(P.create(r))
    local live=J:get(r.id) assert(J:update(r.id,live.revision,{payload=live.payload}))
    r.outputs={{id=3,fullType='Base.Plank',delivered=false}}
    local before=snap() local ok,why=P.commit(r)
    check(not ok and why=='PRODUCTION_JOB_CHANGED' and equal(before,snap()) and not st.claims.owners['item:3'],'stale draft no partial claims/revision')
    return {state=snap(),error=why}
end
check(equal(stale(true),stale(false)),'stale parity including prior revision, items, nativeAttempt, rollback/no-write')
local function recovery(old,unknown)
    local P,S,J,st,r,snap=setup(old) assert(P.create(r))
    if unknown then
        assert(P.beginEffect(r,S.getToken(r.id)))
        st.claims:release(S.getToken(r.id)) st.tokens[r.id]=nil
    end
    st.published=false
    if not old then
        local mutate=EmberRoutesProbeJava.laborMutate
        EmberRoutesProbeJava.laborMutate=function(...) check(st.published,'Store published before recovery kernel') return mutate(...) end
    end
    P.prepareRecovery()
    check(J:get(r.id).state==(unknown and 'RECONCILE_REQUIRED' or 'SUSPENDED'),'recovery target')
    local before=snap() P.prepareRecovery() check(equal(before,snap()),'recovery once per world')
    return snap()
end
check(equal(recovery(true,false),recovery(false,false)),'normal recovery parity')
check(equal(recovery(true,true),recovery(false,true)),'no-token in-flight recovery parity')
-- Same existing cancel-to-CANCELLED mutate path, no third cancellation API.
local P,S,J,st,r,snap=setup(false) assert(P.create(r))
r.released=true r.state='CANCELLED' r.phase='CANCELLED'
check(P.commit(r) and J:get(r.id).state=='CANCELLED' and J:get(r.id).revision==4 and not S.getToken(r.id),'cancel via two kernel mutate steps')
-- Resumed execution publishes the sequence before same-fact reacquisition.
P,S,J,st,r,snap=setup(false) assert(P.create(r)) r.generation=1
check(P.claim(r) and S.getToken(r.id).generation==1,'resumed sequence fence')
-- Failed replace restores draft; pre-CAS single rollback restores owner/job snapshots.
local before=snap() local draft=copy(r) local proposed=copy(r)
proposed.outputs={{id=3,fullType='Base.Plank',delivered=false}}
local update=J.update J.update=function() return false,'INJECTED_REJECT' end
local ok,why=P.replace(r,S.getToken(r.id),proposed) J.update=update
check(not ok and why=='TASK_WRITE_FAILURE' and equal(before,snap()) and equal(draft,r),'replace rejection restores draft and assets')
-- Observe failure deliberately differs from frozen safety chain: no quarantine,
-- no UNKNOWN second publication, no retry; caller must reload the last save.
local attempt=assert(P.beginEffect(r,S.getToken(r.id)))
r.materials[1].consumed=true r.outputs={{id=3,fullType='Base.Plank',delivered=false}} r.phase='CONFIRMED' r.produced=1
before=snap() update=J.update J.update=function() return false,'INJECTED_REJECT' end
ok,why=P.observe(r,attempt,true) J.update=update
check(not ok and why=='TASK_WRITE_FAILURE' and equal(before,snap()) and not st.claims.owners['item:3'],'observe rejection single rollback, no second publish/quarantine')
check(not P.valid(r,S.getToken(r.id)),'failed observation invalidates execution draft')
-- Recovery missing bridge fails at commit and does not mark world recovered.
P,S,J,st,r,snap=setup(false) assert(P.create(r)) before=snap()
local bridge=EmberRoutesProbeJava EmberRoutesProbeJava=nil
ok,why=pcall(P.prepareRecovery)
check(not ok and tostring(why):find('KERNEL_UNAVAILABLE',1,true) and equal(before,snap()),'recovery fail closed')
EmberRoutesProbeJava=bridge check(P.prepareRecovery(),'recovery can run after failed load is resolved')
P,S,J,st,r,snap=setup(false) EmberRoutesProbeJava=nil
ok,why=P.create(r) check(not ok and why=='KERNEL_UNAVAILABLE' and not J:get(r.id),'create fail closed')
-- Classify pre-publication rebuild failure writes: no JobStore/kernel call.
local Recovery=require 'EmberRoutesProbe/CraftJobRecovery'
P,S,J,st,r,snap=setup(false) assert(P.create(r))
local rev=J:get(r.id).revision local calls=#st.bridge.calls
Recovery.restore({current=st.root,rebuilt=st.claims,hasConflict=function() return true end,
    ensureEntityClaimId=function() error('conflict must not allocate') end,rebuiltCraft={},newTokens={}})
check(J:get(r.id).state=='RECONCILE_REQUIRED' and J:get(r.id).effects=='UNKNOWN'
    and J:get(r.id).revision==rev and #st.bridge.calls==calls,'pre-publish conflict rebuild is not kernel commit')
print('PASS '..checks..' CRAFT migration host checks; old Lua vs Phase 1 Lua model parity; Java/game NOT RUN')
