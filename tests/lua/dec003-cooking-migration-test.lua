-- Directed Lua host parity only. Native selection/effects/body stop are explicit
-- seams; real Service claim, Budget, SupplyService, Record, JobStore, Claims,
-- Context, Agent.start and LaborJobCommit. No Java/game/disk/performance claim.
local Jobs=require 'EmberRoutesProbe/JobStore'
local Claims=require 'EmberRoutesProbe/LaborClaims'
local Record=require 'EmberRoutesProbe/CookingRecord'
-- TEST ONLY capability switch, mirroring dec003-kernel-workcapacity-test.lua:
-- production BuiltinJobContracts now registers COOKING capacityMutable=true
-- (registered last, after the kernel extension); this file enables it for its
-- own host-model runs and restores the original value at exit.
local Contracts=require 'EmberRoutesProbe/JobContracts'
require('EmberRoutesProbe/BuiltinJobContracts').install()
local cookingRule=Contracts.get('COOKING')
local originalCapacityMutable=cookingRule.capacityMutable
cookingRule.capacityMutable=true
local checks=0
local function check(v,m) checks=checks+1 assert(v,m) end
local function copy(v) return Record.copy(v) end
local function empty(t) for _ in pairs(t) do return false end return true end
local function equal(a,b)
    if type(a)~=type(b) then return false end
    if type(a)~='table' then return a==b end
    for k,v in pairs(a) do if not equal(v,b[k]) then return false end end
    for k in pairs(b) do if a[k]==nil then return false end end return true
end
local function setup(old)
    local root={} local jobs=assert(Jobs.open(root))
    local st={root=root,claims=Claims.new(),tokens={},cookingTokens={}}
    local S={} local now=1000 local submitted
    local entry={id='base',factionId='f',revision=1}
    root.npcMembership={format=1,byNpc={chef={npcId='chef',settlementId='base',factionId='f'}}}
    local function alloc(r,id) r.nextClaimSeq=(r.nextClaimSeq or 0)+1 return id..':c'..r.nextClaimSeq end
    local function identity(r,j) if not j.claimId then j.claimId=alloc(r,j.id) end return j.claimId end
    local function clean(id) st.tokens[id]=nil st.cookingTokens[id]=nil end
    function S.data() return root end
    function S.getToken(id) return st.tokens[id] or st.cookingTokens[id] end
    function S.hasTaskClaims(id) return st.claims.tokensByTaskId[id]~=nil end
    function S.claimsVersion() return st.claims,st.claims.revision end
    function S.owner(id) return st.claims.owners['item:'..id] end
    local npc={isDead=function() return false end,getX=function() return 0 end,getY=function() return 0 end,
        getZ=function() return 0 end,isOnFire=function() return false end,getSurroundingAttackingZombies=function() return 0 end}
    local actor={isDead=function() return false end}
    local binding={id='chef',handle=npc}
    local runtime={owns=function() return false end,accepting=function() return true end,status=function() return nil end,
        submit=function(_,spec) submitted=spec return spec end,stopJob=function() return true end}
    local function stub(name,v) package.loaded['EmberRoutesProbe/'..name]=v end
    stub('LaborStore',S) stub('TaskJobs',{current=function() return jobs end})
    stub('ContainerRegistry',{data=function() return root end,revalidate=function() return true end})
    stub('TaskRuntime',{current=function() return runtime end})
    stub('Driver',{bindId=function() return binding end,valid=function() return true end})
    stub('MembershipService',{entry=function() return entry end,check=function() return {allowed=true,sharedResources=true} end,
        members=function() return {'chef'} end,view=function() return {context='SETTLEMENT'} end})
    stub('NeedsObserver',{sample=function() return {safe=true} end})
    stub('Work',{busy=function() return false end,hasCargo=function() return false end,registerExecutor=function() end})
    stub('LaborSignals',{changed=function() end}) stub('SelfCare',{blocksWork=function() return false end})
    stub('PlanningWake',{capture=function() return {} end,changed=function() return false end})
    stub('PublicWork',{priorities=function() return {cooking=1} end})
    stub('JobPolicyService',{get=function() return {} end})
    stub('SettlementLedger',{view=function() return entry end})
    stub('CookingProfiles',{accept=function() return true end})
    stub('CraftStations',{}) stub('ProductionActions',{}) stub('CookingInventory',{})
    stub('CookingActions',{}) stub('CookingCraft',{}) stub('CookingFacilities',{})
    stub('TaskBusinessStop',{new=function(o) return o end})
    stub('MealSupplyIndex',{new=function() return {step=function() return true end,
        result=function() return {complete=true,scopeId='base',ready=old and 0 or 0} end} end})
    local selection={kind='HEAT',estimated=.3,minimum=.1,target=.3,
        base={id=11,endpoint={id='source'},item={getFullType=function() return 'Base.Carrot' end}}}
    local menu={step=function() return true end,result=function() return selection end}
    stub('CookingMenu',{new=function() return menu end,fit=function(v) return v end})
    stub('CookingEvolved',{prepare=function(j)
        local p=copy(j) p.payload.raw={id=11,sourceId='source',fullType='Base.Carrot'}
        p.payload.assets={{id=11,fullType='Base.Carrot',custody='SOURCE',role='OUTPUT'}}
        p.payload.claims={'item:11'} return p
    end})
    stub('CookingCargo',{coldGate=function() return {run=function() return 'Success' end} end,
        locate=function() return {kind='Action',run=function() return 'Success' end} end,
        store=function() return {kind='Action',run=function() return 'Success' end} end})
    function getTimestampMs() return now end
    function getGameTime() return {getWorldAgeHours=function() return 1 end} end
    for _,n in ipairs({'CookingService','CookingBudget','CookingSupplyService','CookingContext','CookingAgent','CookingOrders'}) do
        package.loaded['EmberRoutesProbe/'..n]=nil
    end
    if old then
        dofile('tests/lua/fixtures/dec003-pre-kernel-cooking-adapter.lua').install(S,st,identity,clean,function() return true end)
        stub('CookingBudget',dofile('tests/lua/fixtures/dec003-pre-kernel-cooking-budget.lua'))
        EmberRoutesProbeJava={}
    else
        require('EmberRoutesProbe/LaborDomainAdapters').install(S,st,identity,clean,function() return true end)
        -- Work-capacity host transaction model; only token bucket differs.
        -- It is the same model dec003-kernel-workcapacity-test.lua uses, not a
        -- second model invented for this file.
        st.fieldTokens=st.cookingTokens
        st.bridge=dofile('tests/lua/fixtures/dec003-workcapacity-kernel-host.lua')
        st.bridge.install(st,alloc,clean)
        require('EmberRoutesProbe/LaborJobCommit').install(S,st,alloc,clean)
    end
    EmberRoutesProbeJava.carrierId=function() return 'chef' end
    EmberRoutesProbeJava.carrierPresent=function() return true end
    -- Agent.new/start runs real code; effects/heat/delivery below are observations,
    -- not a claim of executing native cooking (work-capacity chain is OPEN).
    local Agent=require 'EmberRoutesProbe/CookingAgent'
    local Orders=require 'EmberRoutesProbe/CookingOrders'
    Orders.describe=function() return {kind='EVOLVED',recipeId='heat:Base.Carrot',recipe={}} end
    local service=old and dofile('tests/lua/fixtures/dec003-pre-kernel-cooking-service.lua') or require 'EmberRoutesProbe/CookingService'
    local function admit(id,request)
        if request then root.publicWork={orders={order={id='order',category='cooking',state='WAITING',
            settlementId='base',recipeId='heat:Base.Carrot',sequence=1,revision=1}}} end
        -- REQUEST planning must not be preempted by meal deficit; use completed
        -- ready-stock observation while retaining the real SupplyService funnel.
        local index=package.loaded['EmberRoutesProbe/MealSupplyIndex']
        index.new=function() return {step=function() return true end,
            result=function() return {complete=true,scopeId='base',ready=request and 1 or 0} end} end
        local env={actor=actor,npc=npc,npcId='chef',entry=entry,now=now,candidates={},
            upsertOffer=function() return {} end}
        service.discover(env)
        for _=1,8 do now=now+50 env.now=now service.advance(env) service.discover(env) if env.candidates[1] then break end end
        local selected=assert(env.candidates[1],service.status('chef'))
        local draft
        local create=jobs.create
        function jobs:create(j) draft=copy(j) return create(self,j) end
        check(service.claim(selected,'chef',id,{actor=actor,entry=entry,now=now})=='QUEUED','actual Service.claim admission')
        jobs.create=create
        return assert(jobs:get(id)),assert(draft),submitted
    end
    return {root=root,jobs=jobs,S=S,st=st,admit=admit,service=service,npc=npc,actor=actor,Agent=Agent,clean=clean,runtime=runtime}
end
local function run(old)
    local f=setup(old) local S,jobs=f.S,f.jobs
    local job,draft,spec=f.admit('request',true)
    check(draft.state=='PREPARING' and draft.revision==1 and #draft.payload.claims==0,'single empty admission create')
    check(job.revision==2 and S.owner(11) and spec,'prepared original owned and submitted')
    local snapshots={copy(draft),copy(job)}
    -- Service.submit has constructed the real Agent; capture a fresh explicit
    -- context to inspect start without pretending to execute native effects.
    local agent,c=assert(f.Agent.new(f.actor,{id='chef',handle=f.npc},job,nil,function() return {nodes=16} end,function() return true end))
    check(agent.start({current=function() return true end,clear=function() return true end}),'agent start')
    check(c.job.state=='RUNNING' and c.job.revision==3,'start separate revision') snapshots[#snapshots+1]=copy(c.job)
    local C=require 'EmberRoutesProbe/CookingContext'
    local stale=copy(c.job) stale.payload.assets[#stale.payload.assets+1]={id=12,fullType='Base.Pot',custody='HELD'}
    stale.payload.claims[#stale.payload.claims+1]='item:12'
    local winner=copy(c.job.payload) winner.reason='CONCURRENT'
    assert(jobs:update(c.job.id,c.job.revision,{payload=winner}))
    local before=jobs:get(c.job.id)
    check(not C.publish(c,stale),'stale Context.publish rejects')
    check(equal(before,jobs:get(c.job.id)) and not S.owner(12),'no partial claims or Job on stale')
    c.job=before c.token=assert(S.claimCooking(before))
    local j=copy(c.job) j.payload.assets[1].custody='DELIVERED' j.payload.assets[1].effective=.3 j.payload.claims={} j.state='SETTLING'
    -- Capacity N/A here: native coldGate/reserveWork is a classified hard stop,
    -- not a zero-capacity assertion about the complete native cooking chain.
    assert(C.publish(c,j),tostring(c.reason).." valid="..tostring(Record.valid(j)).." trans="..tostring(Record.transition(c.job,j))) snapshots[#snapshots+1]=copy(c.job)
    c.completed=true
    local stop=C.stopAdapter(c,{}, {})
    check(stop.persist({bodyStopped=true}),'stopped-body terminal persist + finish')
    check(c.closed and c.job.state=='DONE' and c.job.payload.phase=='SETTLED' and #c.job.payload.claims==0
        and empty(c.job.obligations) and not S.owner(11),'DONE clears responsibilities')
    snapshots[#snapshots+1]=copy(c.job)
    -- No-token rejectEmpty-equivalent SETTLING -> cancel: real service failed
    -- claim token after an otherwise successful REQUEST admission.
    local reject=setup(old) local claim=reject.S.claimCooking
    reject.S.claimCooking=function(j)
        -- Genuine no-token/no-resource case. A failed re-claim while kernel's
        -- empty create token remains cached is separately retained by hasTaskClaims.
        local t=reject.S.getToken(j.id) if t then reject.st.claims:release(t) end
        reject.clean(j.id) return nil,'INJECTED_TOKEN_LOSS'
    end
    local cancelled=reject.admit('empty',true)
    check(cancelled.state=='CANCELLED' and cancelled.revision==3 and cancelled.payload.phase=='SETTLED','rejectEmpty no-token two commits')
    reject.S.claimCooking=claim
    -- AUTO uses actual SupplyService.reserve -> SAME Budget.reserve/create.
    local auto=setup(old) local a,ad=auto.admit('auto',false)
    check(ad.payload.source=='AUTO' and ad.revision==1 and a.revision==2,'AUTO same create and prepared publish')
    if not old then
        local n=0 for _,name in ipairs(auto.st.bridge.calls) do if name=='laborCreate' then n=n+1 end end
        check(n==1,'AUTO exactly one kernel create')
    end
    return snapshots
end
-- Command flags carry unchanged claims/capacity and no resource commands even
-- when an agent holds a token. Return requests settle-only recovery, not cancel.
local f=setup(false)
local job=f.admit('command',true)
f.runtime.status=function() return {state='ACTIVE'} end
check(f.service.command(f.actor,'base',job.id,'return')=='CANCEL_REQUESTED','return live requests cancellation')
job=f.jobs:get(job.id)
check(job.payload.cancelRequested and job.payload.reason=='USER_CANCEL' and #job.payload.claims==1
    and f.S.owner(11),'flag preserves original owner and claims')
local agent,c=assert(f.Agent.new(f.actor,{id='chef',handle=f.npc},job,nil,
    function() return {nodes=16} end,function() return true end,{settleOnly=true}))
assert(agent.start({current=function() return true end,clear=function() return true end}))
local C=require 'EmberRoutesProbe/CookingContext'
local j=copy(c.job) j.state='SETTLING' j.payload.assets[1].custody='RETURNED' j.payload.claims={}
assert(C.publish(c,j)) c.completed=true
check(C.stopAdapter(c,{},{}).persist({bodyStopped=true}) and c.job.state=='CANCELLED',
    'command return -> session SETTLING -> kernel cancel and finish')
check(f.st.bridge.calls[#f.st.bridge.calls]=='laborCancel','only kernel cancel terminal entry')
-- SUSPENDED start must expose both revisions, never collapse to RUNNING.
f=setup(false) job=f.admit('suspended',true) C=require 'EmberRoutesProbe/CookingContext'
assert(f.S.mutateJob(job.id,job.revision,job.payload,{state='SUSPENDED'})) job=f.jobs:get(job.id)
agent,c=assert(f.Agent.new(f.actor,{id='chef',handle=f.npc},job,nil,function() return {} end,function() return true end))
assert(agent.start({current=function() return true end}))
check(c.job.state=='RUNNING' and c.job.revision==job.revision+2,'SUSPENDED start two publishes')
-- Work-capacity publish is a kernel contract change, not a legacy branch:
-- first publish sets the promise via kernel workCapacity, and an unchanged
-- publish must also carry the workCapacity command, otherwise the kernel
-- snapshot holds no promise and a later CAS failure would clear it.
local cap=copy(c.job) cap.payload.capacity={endpointId='cold',amount=4}
cap.payload.claims[#cap.payload.claims+1]='cooking:capacity:'..cap.id cap.obligations.storage=true
local count=#f.st.bridge.calls
assert(C.publish(c,cap))
check(#f.st.bridge.calls==count+1 and f.st.bridge.calls[#f.st.bridge.calls]=='laborMutate'
    and f.st.claims.capacity.cold.total==4,'capacity publish via kernel workCapacity, total 4')
local keep=copy(c.job) keep.payload.reason='RETAIN_SPACE'
local keepCount=#f.st.bridge.calls
assert(C.publish(c,keep))
check(#f.st.bridge.calls==keepCount+1 and f.st.bridge.calls[#f.st.bridge.calls]=='laborMutate'
    and f.st.claims.capacity.cold.total==4,'unchanged capacity publish also via kernel workCapacity, amount unchanged')
-- A race after adapter admission reaches the kernel revision gate itself.
f=setup(false) job=f.admit('race',true) C=require 'EmberRoutesProbe/CookingContext'
c={job=job,token=assert(f.S.claimCooking(job))}
local proposal=copy(job) proposal.payload.assets[#proposal.payload.assets+1]={id=12,fullType='Base.Pot',custody='HELD'}
proposal.payload.claims[#proposal.payload.claims+1]='item:12'
local mutate=f.S.mutateJob
f.S.mutateJob=function(id,rev,p,m)
    local winner=copy(job.payload) winner.reason='RACE_WINNER'
    assert(f.jobs:update(id,rev,{payload=winner}))
    return mutate(id,rev,p,m)
end
check(not C.publish(c,proposal) and c.reason=='STALE_REVISION','kernel stale gate reached after adapter admission')
check(f.jobs:get(job.id).revision==3 and f.jobs:get(job.id).payload.reason=='RACE_WINNER'
    and not f.S.owner(12) and f.S.owner(11),'kernel stale keeps winner and old claims only')
-- persistFailure without a token preserves every claim/capacity declaration;
-- this is an observation write, never authorization to shrink resources.
f=setup(false) job=f.admit('start-failure',true)
agent,c=assert(f.Agent.new(f.actor,{id='chef',handle=f.npc},job,nil,function() return {} end,function() return true end))
local token=f.S.getToken(job.id) f.st.claims:release(token) f.clean(job.id)
check(agent.persistFailure({bodyStopped=true},'HOST_START_REJECTED'),'no-token persistFailure kernel mutation')
check(f.jobs:get(job.id).state=='SUSPENDED' and #f.jobs:get(job.id).payload.claims==1,
    'persistFailure does not pretend originals settled')
local before=run(true) local after=run(false)
-- Kernel allocates identity during create; old JobStore allocated inside create.
check(before[1].claimId==nil and after[1].claimId=='request:c1','approved earlier kernel identity allocation')
before[1].claimId=after[1].claimId
for i=1,#before do check(equal(before[i],after[i]),'old/kernel full Job parity point '..i) end
cookingRule.capacityMutable=originalCapacityMutable
check(cookingRule.capacityMutable==originalCapacityMutable,'test-only capacity switch restored to original value')
print('PASS '..checks..' COOKING migration assertions; Lua host only; capacity-bearing chain via kernel workCapacity')
