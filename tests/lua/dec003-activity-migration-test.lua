-- Directed real participant/adapter/JobStore/Claims chain; host bridge model only.
local JobStore=require 'EmberRoutesProbe/JobStore'
local Claims=require 'EmberRoutesProbe/LaborClaims'
local checks=0
local function check(v,m) assert(v,m) checks=checks+1 end
local function copy(v) if type(v)~='table' then return v end local r={} for k,x in pairs(v) do r[k]=copy(x) end return r end
local function equal(a,b)
    if type(a)~=type(b) then return false end if type(a)~='table' then return a==b end
    for k,v in pairs(a) do if not equal(v,b[k]) then return false end end
    for k in pairs(b) do if a[k]==nil then return false end end return true
end
local function setup(old)
    local root={} local jobs=assert(JobStore.open(root))
    local st={root=root,claims=Claims.new(),tokens={},activityTokens={}}
    local S={} local snapshots={} local removes=0 local spec local status local pending=false
    local function alloc(r,id) r.nextClaimSeq=(r.nextClaimSeq or 0)+1 return id..':c'..r.nextClaimSeq end
    local function identity(r,j,id) if not j.claimId then j.claimId=alloc(r,id) end return j.claimId end
    local function clean(id) st.tokens[id]=nil st.activityTokens[id]=nil st.claims.tokensByTaskId[id]=nil end
    function S.data() return root end
    function S.getToken(id) return st.claims.tokensByTaskId[id] or st.tokens[id] or st.activityTokens[id] end
    function S.resourceOwner(k) return st.claims.owners[k] end
    local create,update,cancel,remove=jobs.create,jobs.update,jobs.cancel,jobs.removeSettled
    function jobs:create(j) local ok,r=create(self,j) if ok then snapshots[#snapshots+1]=self:get(j.id) end return ok,r end
    function jobs:update(id,rev,p) local ok,r=update(self,id,rev,p) if ok then snapshots[#snapshots+1]=self:get(id) end return ok,r end
    function jobs:cancel(id,rev,p) local ok,r=cancel(self,id,rev,p) if ok then snapshots[#snapshots+1]=self:get(id) end return ok,r end
    function jobs:removeSettled(id,rev) removes=removes+1 return remove(self,id,rev) end
    local runtime={accepting=function() return true end,owns=function() return false end,
        submit=function(_,s) spec=s return s end,status=function() return status end,
        inspect=function() return {state='CANCELLED'} end,stopJob=function() end}
    local npc={isDead=function() return false end,getX=function() return 2.5 end,getY=function() return 3.5 end,getZ=function() return 0 end}
    local binding={id='a',handle=npc}
    local event={id='scene',settlementId='home',controlEpoch=1,state='GATHERING',outcome='COMPLETED',roster={a={participantEpoch=1}}}
    local function stub(n,v) package.loaded['EmberRoutesProbe/'..n]=v end
    stub('ContainerRegistry',{data=function() return root end,id=function() return 'participant' end})
    stub('TaskJobs',{current=function() return jobs end}) stub('LaborStore',S)
    stub('TaskRuntime',{current=function() return runtime end})
    stub('ActivityStore',{copy=copy,touch=function() end,get=function() return event end})
    stub('ActivityStages',{participantExit=function() return false end}) stub('ActivityDuties',{clear=function() return true end})
    stub('ActivityReliefRecord',{})
    stub('Driver',{bindId=function() return binding end,valid=function() return true end})
    stub('ActivityResponsibilities',{associated=function() return false end,personalPending=function() return pending end})
    stub('ActivityService',{context=function() return {controlEpoch=1,participantEpoch=1} end,
        allowsPoint=function() return true end,arrived=function() return true end})
    stub('ActivityAttendance',{inspect=function() return 'READY' end})
    stub('NeedsObserver',{sample=function() return {safe=true,observedAt=100} end})
    stub('NeedsPolicy',{choose=function() return nil end})
    stub('MembershipService',{entry=function() return {} end}) stub('LeisureService',{standable=function() return true end})
    stub('SocialCoordinator',{withdraw=function() end}) stub('TaskBusinessStop',{new=function(o) return o end})
    getTimestampMs=function() return 100 end getGameTime=function() return {getWorldAgeHours=function() return 1 end} end
    if old then
        dofile('tests/lua/fixtures/dec003-pre-kernel-activity-adapter.lua').install(S,st,identity,clean,function() return true end)
    else
        require('EmberRoutesProbe/LaborDomainAdapters').install(S,st,identity,clean,function() return true end)
        st.bridge=dofile('tests/lua/fixtures/dec003-activity-kernel-host.lua')
        st.bridge.install(st,alloc,clean)
        require('EmberRoutesProbe/LaborJobCommit').install(S,st,alloc,clean)
    end
    package.loaded['EmberRoutesProbe/ActivityParticipant']=nil
    local P=old and dofile('tests/lua/fixtures/dec003-pre-kernel-activity-participant.lua') or require 'EmberRoutesProbe/ActivityParticipant'
    local function peek() return jobs:get('participant') end
    return {P=P,S=S,st=st,jobs=jobs,event=event,peek=peek,snapshots=snapshots,root=root,
        removes=function() return removes end,spec=function() return assert(spec) end,
        status=function(s) status=s end,pending=function(v) pending=v end,
        prepare=function() check(P.prepare(event),'prepare') end,
        submit=function() P.advance({},event,'a') return spec end}
end
local tile='leisureTile:2:3:0'
local function run(old,outcome)
    local f=setup(old) f.prepare()
    check(f.peek().payload.step=='INVITED' and f.peek().revision==1,'INVITED revision 1')
    local spec=assert(f.submit())
    check(f.peek().revision==2 and #f.peek().payload.claims==1 and f.S.resourceOwner(tile),'submit point/tile separately published')
    check(spec.start({}),'real participant start')
    check(f.peek().revision==3 and f.peek().state=='RUNNING' and f.peek().payload.step=='WAITING','WAITING RUNNING')
    local release=f.st.claims.release
    function f.st.claims:release(t)
        check(#f.peek().payload.claims==0,'token release follows successful clear CAS')
        return release(self,t)
    end
    local stop=spec.stopAdapter({}, {})
    check(stop.persist({bodyStopped=true,effects='KNOWN'}),'stopAdapter persist')
    check(f.peek().revision==6 and f.peek().state=='SUSPENDED' and f.peek().payload.step=='LEAVING'
        and #f.peek().payload.claims==0 and not f.S.resourceOwner(tile),'STOPPING -> clear -> SUSPENDED distinct revisions')
    check(f.snapshots[4].state=='STOPPING' and #f.snapshots[4].payload.claims==1
        and f.snapshots[5].state=='STOPPING' and #f.snapshots[5].payload.claims==0,'intermediate states preserved')
    f.event.state='SETTLING' f.event.outcome=outcome or 'COMPLETED'
    check(f.P.collectOne(f.event,'a'),'settle')
    check(not f.peek() and f.removes()==1 and f.event.roster.a.settled,'retire only after terminal success')
    check(f.snapshots[7].revision==7 and f.snapshots[7].state=='SETTLING'
        and f.snapshots[8].revision==8 and f.snapshots[8].state==(outcome=='CANCELLED' and 'CANCELLED' or 'DONE'),'two tail revisions')
    if not old and outcome=='CANCELLED' then check(f.st.bridge.calls[#f.st.bridge.calls]=='laborCancel','terminal cancel bridge') end
    return f.snapshots
end
local function parity(a,b)
    for i=1,#a do check(equal(a[i],b[i]),'old/kernel full Job parity '..i) end
    check(#a==#b,'same commit count')
end
parity(run(true),run(false))
parity(run(true,'CANCELLED'),run(false,'CANCELLED'))
-- Settle-tail revision gate: inject a competing publish after participant peek.
local function stale(old)
    local f=setup(old) f.prepare() local spec=assert(f.submit()) assert(spec.start({}))
    assert(spec.stopAdapter({},{}).persist({bodyStopped=true,effects='KNOWN'}))
    f.event.state='SETTLING'
    local original=f.jobs.update local raced=false local winner local failure
    local function race(id,rev,p)
        if not raced and p.state=='SETTLING' then
            raced=true local payload=copy(f.peek().payload) payload.reason='RACE_WINNER'
            assert(original(f.jobs,id,rev,{payload=payload})) winner=f.peek()
        end
    end
    if old then
        function f.jobs:update(id,rev,p) race(id,rev,p) return original(self,id,rev,p) end
    else
        local mutate=f.S.mutateJob
        function f.S.mutateJob(id,rev,p,m)
            race(id,rev,m)
            local ok,why,evidence=mutate(id,rev,p,m) failure=why return ok,why,evidence
        end
    end
    check(not f.P.collectOne(f.event,'a'),'stale settle tail fails')
    if not old then check(failure=='STALE_REVISION','bridge stale revision gate') end
    check(raced and equal(winner,f.peek()) and f.peek().revision==7,'stale keeps winning prior revision')
    check(not f.S.resourceOwner(tile) and #f.peek().payload.claims==0 and f.removes()==0
        and not f.event.roster.a.settled,'stale no partial claims or retirement')
    return f.peek()
end
check(equal(stale(true),stale(false)),'stale old/kernel parity')
-- A failed clear CAS must restore the tile and never reach token release.
local f=setup(false) f.prepare() local spec=assert(f.submit()) assert(spec.start({}))
local original=f.jobs.update
function f.jobs:update(id,rev,p)
    if p.payload and #p.payload.claims==0 then return false,'INJECTED_CAS_REJECT' end
    return original(self,id,rev,p)
end
check(not spec.stopAdapter({},{}).persist({bodyStopped=true,effects='KNOWN'}),'clear CAS failure')
check(f.peek().revision==4 and #f.peek().payload.claims==1 and f.S.resourceOwner(tile)
    and f.S.getToken('participant') and f.removes()==0,'rollback retains declared tile and token')
-- Stale submit rejects the proposed new tile before any partial claim publish.
f=setup(false) f.prepare()
local mutate=f.S.mutateJob local staleError
f.S.mutateJob=function(id,rev,p,m)
    local winner=copy(f.peek().payload) winner.reason='SUBMIT_RACE'
    assert(f.jobs:update(id,rev,{payload=winner}))
    local ok,why,evidence=mutate(id,rev,p,m) staleError=why return ok,why,evidence
end
check(not f.submit() and staleError=='STALE_REVISION' and f.peek().revision==2
    and #f.peek().payload.claims==0 and not f.S.resourceOwner(tile) and f.removes()==0,
    'stale submit never publishes addition')
-- Token acquisition failure remains a second claim-clearing payload revision.
f=setup(false) f.prepare() f.S.claimActivity=function() return nil,'HOST_TOKEN_FAILURE' end
check(not f.submit() and f.peek().revision==3 and #f.peek().payload.claims==0
    and not f.S.resourceOwner(tile),'claim failure clears through separate kernel mutation')
-- Wedged UNKNOWN: scene/runtime/personal/handle/obligation evidence before adapter.
local function wedged(old)
    local w=setup(old) w.prepare()
    local j=w.peek() local p=copy(j.payload) p.point={x=2.5,y=3.5,z=0} p.sequence=1 p.claims={tile}
    if old then assert(w.jobs:update(j.id,j.revision,{payload=p}))
    else assert(w.S.mutateJob(j.id,j.revision,p,{addKeys={tile}})) end
    j=w.peek() assert(w.S.claimActivity(j))
    assert(w.jobs:update(j.id,j.revision,{state='RECONCILE_REQUIRED',effects='UNKNOWN'}))
    check(not w.P.collectOne(w.event,'a') and w.S.resourceOwner(tile),'open scene cannot force settle')
    w.event.state='SETTLING' w.status({jobId='participant'})
    check(not w.P.collectOne(w.event,'a') and w.S.resourceOwner(tile),'runtime ownership blocks')
    w.status(nil) w.pending(true)
    check(not w.P.collectOne(w.event,'a') and w.S.resourceOwner(tile),'personal pending blocks')
    w.pending(false) j=w.peek() assert(w.jobs:update(j.id,j.revision,{obligations={pending=true}}))
    check(not w.P.collectOne(w.event,'a') and w.S.resourceOwner(tile),'obligation blocks')
    j=w.peek() assert(w.jobs:update(j.id,j.revision,{obligations={}}))
    local before=#w.snapshots
    local release=w.st.claims.release
    function w.st.claims:release(t)
        check(w.peek().effects=='KNOWN' and #w.peek().payload.claims==0,'wedged token release after KNOWN clear CAS')
        return release(self,t)
    end
    if not old then
        local update=w.jobs.update
        function w.jobs:update(id,rev,patch)
            if patch.state=='SETTLING' then return false,'HOST_WEDGED_CAS_REJECT' end
            return update(self,id,rev,patch)
        end
        check(not w.P.collectOne(w.event,'a') and w.peek().effects=='UNKNOWN'
            and w.S.resourceOwner(tile) and w.removes()==0,'wedged failed CAS retains UNKNOWN tile')
        w.jobs.update=update
    end
    check(w.P.collectOne(w.event,'a'),'forced settle')
    local known=w.snapshots[before+1] local terminal=w.snapshots[before+2]
    check(known.state=='SETTLING' and known.effects=='KNOWN' and #known.payload.claims==0
        and known.payload.stopped and terminal.state=='CANCELLED','UNKNOWN -> SETTLING/KNOWN -> CANCELLED')
    check(not w.S.resourceOwner(tile) and w.removes()==1,'forced release and retirement')
    if not old then check(w.st.bridge.calls[#w.st.bridge.calls]=='laborCancel','forced tail cancel bridge') end
    return w.snapshots
end
parity(wedged(true),wedged(false))
-- prepareRecovery is the published phase: unproven body -> UNKNOWN;
-- a captured stopped receipt instead follows the normal clear path.
f=setup(false) f.prepare() spec=assert(f.submit()) assert(spec.start({}))
check(f.P.prepareRecovery(nil) and f.peek().effects=='UNKNOWN'
    and #f.peek().payload.claims==1 and f.S.resourceOwner(tile),'unproven recovery retains claims UNKNOWN')
f.event.state='SETTLING'
check(not f.P.collectOne(f.event,'a') and f.removes()==0,'live participant handle blocks forced settlement')
f=setup(false) f.prepare() spec=assert(f.submit()) assert(spec.start({}))
check(f.P.prepareRecovery({state='CAPTURED',byNpc={a={jobId='participant',bodyStopped=true,effects='KNOWN'}}})
    and f.peek().payload.stopped and #f.peek().payload.claims==0 and not f.S.resourceOwner(tile),
    'captured recovery clear after Job observation')
-- persistFailure retains its own distinct observation write after clear.
f=setup(false) f.prepare() spec=assert(f.submit())
check(spec.persistFailure({bodyStopped=true,effects='KNOWN'}) and f.peek().state=='SUSPENDED'
    and f.peek().revision==4 and #f.peek().payload.claims==0,'never-started persistFailure two writes')
-- Missing bridge fails closed at actual participant create, no Lua fallback.
f=setup(false) EmberRoutesProbeJava={}
local ok,why=f.P.prepare(f.event)
check(not ok and why=='KERNEL_UNAVAILABLE' and not f.peek() and not f.event.roster.a.jobId,'missing bridge no create')
print('PASS '..checks..' ACTIVITY migration assertions (Lua host only)')
