-- Real SelfCare admission/Execution/Resume/adapter/JobStore/Claims; model bridge only.
local JobStore=require 'EmberRoutesProbe/Kernel/JobStore'
local Claims=require 'EmberRoutesProbe/Kernel/LaborClaims'
local Record=require 'EmberRoutesProbe/SelfCare/SelfCareRecord'
local checks=0
local function check(v,m) assert(v,m) checks=checks+1 end
local function copy(v) if type(v)~='table' then return v end local r={} for k,x in pairs(v) do r[k]=copy(x) end return r end
local function equal(a,b)
    if type(a)~=type(b) then return false end if type(a)~='table' then return a==b end
    for k,v in pairs(a) do if not equal(v,b[k]) then return false end end
    for k in pairs(b) do if a[k]==nil then return false end end return true
end
local function setup(old,borrowed)
    local root={} local jobs=assert(JobStore.open(root))
    local st={root=root,claims=Claims.new(),tokens={},personalTokens={}}
    local S={} local snapshots={} local spec local now=10000 local reject=false
    local function alloc(r,id) r.nextClaimSeq=(r.nextClaimSeq or 0)+1 return id..':c'..r.nextClaimSeq end
    local function identity(r,j,id) if not j.claimId then j.claimId=alloc(r,id) end return j.claimId end
    local function clean(id) st.tokens[id]=nil st.personalTokens[id]=nil st.claims.tokensByTaskId[id]=nil end
    function S.data() return root end
    function S.getToken(id) return st.claims.tokensByTaskId[id] or st.tokens[id] or st.personalTokens[id] end
    local create,update=jobs.create,jobs.update
    function jobs:create(j) local ok,r=create(self,j) if ok then snapshots[#snapshots+1]=self:get(j.id) end return ok,r end
    function jobs:update(id,rev,p) local ok,r=update(self,id,rev,p) if ok then snapshots[#snapshots+1]=self:get(id) end return ok,r end
    local inv={hasRoomFor=function() return true end,getItems=function() return {size=function() return 0 end} end}
    local item={getID=function() return 11 end,getHungChange=function() return -.5 end,getContainer=function() return inv end}
    local npc={isDead=function() return false end,isOnFire=function() return false end,
        getSurroundingAttackingZombies=function() return 0 end,getInventory=function() return inv end,
        getX=function() return 1 end,getY=function() return 2 end,getZ=function() return 0 end}
    for _,name in ipairs({'isAsleep','isResting','isSittingOnFurniture'}) do npc[name]=function() return false end end
    npc.getSitOnFurnitureObject=function() return nil end
    local binding={id='a',handle=npc}
    local rt={accepting=function() return true end,status=function() return nil end,owns=function() return false end,
        submit=function(_,s) if reject then return nil,'HOST_REJECT' end spec=s return s end,
        inspect=function() return {state='CLOSED'} end,stopJob=function() end}
    local function stub(n,v) package.loaded['EmberRoutesProbe/'..n]=v end
    stub('Boot',{}) stub('ContainerRegistry',{data=function() return root end,id=function() return 'personal' end})
    stub('TaskJobs',{current=function() return jobs end}) stub('LaborStore',S)
    stub('TaskRuntime',{current=function() return rt end}) stub('Driver',{bindId=function() return binding end,valid=function() return true end})
    stub('SelfCareResources',{eligible=function() return true end,revalidate=function() return true end,
        new=function() return {step=function() return {id=11,item=item,container=inv,endpoint=borrowed and {id='source'},entry=borrowed and {id='home'}},true end} end})
    stub('NeedsObserver',{sample=function() return {safe=true,observedAt=now,hunger=.6,thirst=0} end})
    stub('NeedsPolicy',{choose=function() return 'EAT' end})
    stub('SettlementFacilities',{tick=function() end}) stub('RuntimeMetrics',{active=function() return false end})
    stub('Log',{write=function(_,s) error(s) end})
    stub('MembershipService',{view=function() return {context='HOME'} end,check=function() return {allowed=true,sharedResources=true} end})
    stub('SocialCoordinator',{withdraw=function() end}) stub('ActivityService',{context=function() return nil end})
    stub('CookingFood',{read=function() return nil end})
    stub('SelfCareCustody',{located=function() return true end,observe=function() return true end,
        findOriginal=function() return item,true end,take=function() return {kind='Action',run=function() return 'Success' end} end,
        returns=function() return {kind='Action',run=function() return 'Success' end} end})
    stub('SelfCareActions',{consumption=function() return {kind='Action',run=function() return 'Success' end} end})
    stub('TaskBusinessStop',{new=function(o) return o end})
    for _,name in ipairs({'SelfCareCommit','SelfCare','SelfCareExecution','TaskResume'}) do package.loaded['EmberRoutesProbe/'..name]=nil end
    local A=old and dofile('tests/lua/fixtures/dec003-pre-kernel-personal-adapter.lua') or require 'EmberRoutesProbe/Work/LaborDomainAdapters'
    A.install(S,st,identity,clean,function() return true end)
    if not old then
        local host=dofile('tests/lua/fixtures/dec003-activity-kernel-host.lua')
        host.install(st,alloc,clean)
        require('EmberRoutesProbe/Work/LaborJobCommit').install(S,st,alloc,clean)
    else EmberRoutesProbeJava={} end
    EmberRoutesProbeJava.workerCount=function() return 1 end
    EmberRoutesProbeJava.workerIdAt=function() return 'a' end
    getTimestampMs=function() return now end getSpecificPlayer=function() return {isDead=function() return false end} end
    if old then package.loaded['EmberRoutesProbe/Runtime/TaskResume']=dofile('tests/lua/fixtures/dec003-pre-kernel-task-resume.lua') end
    local E=old and dofile('tests/lua/fixtures/dec003-pre-kernel-selfcare-execution.lua') or require 'EmberRoutesProbe/SelfCare/SelfCareExecution'
    package.loaded['EmberRoutesProbe/SelfCare/SelfCareExecution']=E
    local care=old and dofile('tests/lua/fixtures/dec003-pre-kernel-selfcare.lua') or require 'EmberRoutesProbe/SelfCare/SelfCare'
    return {jobs=jobs,S=S,st=st,root=root,care=care,snapshots=snapshots,spec=function() return assert(spec) end,
        binding=binding,rt=rt,peek=function() return jobs:get('personal') end,reject=function() reject=true end,
        tick=function() now=now+10000 care.tick() end}
end
local function run(old)
    local f=setup(old) f.tick()
    check(f.snapshots[1].payload.step=='IDLE' and f.snapshots[1].revision==1,'personal create')
    check(f.snapshots[2].payload.step=='REQUESTED' and f.snapshots[2].payload.sequence==1,'begin sequence')
    local spec=f.spec() check(spec.start({}),'execution start')
    check(f.peek().payload.step=='ACTING' and f.peek().state=='RUNNING','ACTING RUNNING')
    local release=f.st.claims.release
    function f.st.claims:release(t)
        check(#f.peek().payload.claims==0,'release strictly after clear CAS') return release(self,t)
    end
    check(spec.stopAdapter({},{}).persist({effects='KNOWN',bodyStopped=true}),'execution finish')
    check(f.peek().revision==9 and f.peek().payload.step=='IDLE' and f.peek().state=='SUSPENDED'
        and #f.peek().payload.claims==0 and not f.S.getToken('personal'),'finish claims cleared')
    check(f.snapshots[6].payload.step=='IDLE' and #f.snapshots[6].payload.claims==1
        and #f.snapshots[7].payload.claims==0 and f.snapshots[8].state=='STOPPING','separate finish revisions')
    f.tick() f.tick()
    check(f.peek().id=='personal' and f.peek().payload.sequence==2 and f.peek().payload.attemptId=='personal:2','same recurring id next attempt')
    check(#f.jobs:forNpc('a','SELF_CARE')==1,'one personal identity')
    return f
end
local old,new=run(true),run(false)
check(#old.snapshots==#new.snapshots,'same commit count')
for i,j in ipairs(old.snapshots) do
    local a,b=copy(j),copy(new.snapshots[i])
    -- Kernel allocates the stable claim identity at create, old path at first claim.
    a.claimId=nil b.claimId=nil check(equal(a,b),'full business Job parity '..i)
end
-- Actual service rollback after rejected submission, before payload/obligations restored.
for _,legacy in ipairs({true,false}) do
    local f=setup(legacy,true) f.reject() f.tick()
    check(f.peek().payload.step=='IDLE' and f.peek().payload.sequence==0 and #f.peek().payload.claims==0
        and equal(f.peek().obligations,{}) and not f.st.claims.owners['item:11'],'service rollback before payload')
end
-- Race between intent preparation and commit check, before additions publish.
local function stale(legacy)
    local f=setup(legacy) local winner local why
    if legacy then
        local update=f.jobs.update
        function f.jobs:update(id,rev,patch)
            if patch.payload and patch.payload.step=='REQUESTED' then
                local current=self:get(id)
                assert(update(self,id,rev,{payload=current.payload})) winner=self:get(id)
            end
            local ok,r=update(self,id,rev,patch) why=r return ok,r
        end
    else
        local mutate=f.S.mutateJob
        f.S.mutateJob=function(id,rev,p,m)
            if p.step=='REQUESTED' then
                local current=f.jobs:get(id)
                assert(f.jobs:update(id,rev,{payload=current.payload})) winner=f.jobs:get(id)
            end
            local ok,r,e=mutate(id,rev,p,m) why=r return ok,r,e
        end
    end
    f.tick()
    check(equal(f.peek(),winner),'stale keeps prior winning revision and before payload')
    if not legacy then check(why=='STALE_REVISION','kernel stale error') end
    check(f.peek().payload.step=='IDLE' and f.peek().payload.sequence==0 and equal(f.peek().obligations,{})
        and not f.st.claims.owners['item:11'],'stale no partial claims/obligations')
    local result=f.peek() result.claimId=nil return result
end
check(equal(stale(true),stale(false)),'old/kernel stale business parity')
local f
-- Missing bridge at create has no Lua write and no identity allocation.
f=setup(false) EmberRoutesProbeJava.laborCreate=nil f.tick()
check(not f.peek() and not f.root.nextClaimSeq,'missing bridge fail closed')
-- Transactional output claims and seat removal use the same persist CAS.
f=setup(false) f.tick() local spec,c=require('EmberRoutesProbe/SelfCare/SelfCareExecution').new({},f.binding,f.peek(),
    {id=11,item={}},function() return {} end,false,{},function() return true end)
check(spec.start({}),'second execution context starts')
check(c.claimOutputs({12}) and f.st.claims.owners['item:12'] and #f.peek().payload.claims==2,'output addition in persist transaction')
c.payload.claims[#c.payload.claims+1]='repose:seat'
check(c.persist() and f.S.extendPersonal(c.job,c.token) and f.st.claims.owners['repose:seat'],'seat extension folded into persist')
c.payload.claims={'item:11','item:12'}
check(c.persist() and f.S.releasePersonalSeats(c.job,c.token) and not f.st.claims.owners['repose:seat'],'seat shrink folded into persist')
local prior=f.peek() local update=f.jobs.update
function f.jobs:update(id,rev,p) return false,'HOST_CAS_REJECT' end
check(not c.claimOutputs({13}) and equal(f.peek(),prior) and not f.st.claims.owners['item:13']
    and f.st.claims.owners['item:12'],'output CAS rejection restores claims and prior payload')
f.jobs.update=update
-- Interrupted borrowed original: real recovery classification and reconciliation.
f=setup(false,true) f.tick() check(f.spec().start({}),'borrowed attempt start')
check(f.care.prepareRecovery(nil) and f.peek().effects=='UNKNOWN'
    and f.peek().payload.step=='RECONCILE_REQUIRED' and f.peek().obligations.RETURN_ORIGINALS,'interrupted obligation retained')
ISTimedActionQueue={queues={}}
package.loaded['EmberRoutesProbe/SelfCare/SelfCareReconciliation']=nil
check(require('EmberRoutesProbe/SelfCare/SelfCareReconciliation').run(f.binding,f.peek(),{},{scan=32},f.rt),'evidence scan reconciles')
check(f.peek().state=='SUSPENDED' and f.peek().effects=='KNOWN' and f.peek().payload.step=='SETTLING'
    and f.peek().obligations.RETURN_ORIGINALS.itemId==11 and f.st.claims.owners['item:11'],'KNOWN retains RETURN_ORIGINALS and original claim')
-- Cold classification queues without changing the published Job object.
local pending={} local before=f.peek()
require('EmberRoutesProbe/SelfCare/SelfCareJobRecovery').restore({current=f.root,rebuilt=f.st.claims,
    hasConflict=function() return true end,rebuiltPersonal={},pendingPersonal=pending})
check(#pending==1 and equal(before,f.peek()),'cold conflict is a detached queued proposal')
check(require('EmberRoutesProbe/SelfCare/SelfCareCommit').update(pending[1].id,pending[1].revision,pending[1].patch)
    and f.peek().effects=='UNKNOWN','cold queued proposal uses kernel after publication')
-- Hard stop: legacy cold death bypassed RUNNING's suspension fence.
f=setup(false) assert(f.S.createClaimedJob(Record.create('personal','a')))
local j=f.peek() local p=assert(Record.begin(j,'REST')) p.step='ACTING'
assert(require('EmberRoutesProbe/SelfCare/SelfCareCommit').update(j.id,j.revision,{payload=p,state='RUNNING'}))
package.loaded['EmberRoutesProbe/Settlement/MembershipService']={view=function() return {retired=true} end}
pending={} before=f.peek()
require('EmberRoutesProbe/SelfCare/SelfCareJobRecovery').restore({current=f.root,rebuilt=f.st.claims,
    hasConflict=function() return false end,rebuiltPersonal={},pendingPersonal=pending})
check(equal(before,f.peek()) and pending[1].patch.state=='SUSPENDED','cold death proposal cannot bypass transition')
local ok,reason=require('EmberRoutesProbe/SelfCare/SelfCareCommit').update(pending[1].id,pending[1].revision,pending[1].patch)
check(not ok and reason=='TASK_WRITE_FAILURE' and equal(before,f.peek()),'cold nonretained RUNNING death remains a recorded contract gap')
print('PASS '..checks..' SELF_CARE migration assertions (Lua host model only)')
