-- TEST ONLY: host Lua model of NEW Java work-capacity logic, NOT Java proof.
-- COOKING capability is a test-only switch, restored and asserted at exit; production stays OFF.
local Record=require 'EmberRoutesProbe/Cooking/CookingRecord'
local JobStore=require 'EmberRoutesProbe/Kernel/JobStore'
local Budget=require 'EmberRoutesProbe/Cooking/CookingBudget'
local Claims=require 'EmberRoutesProbe/Kernel/LaborClaims'
local Contracts=require 'EmberRoutesProbe/Kernel/JobContracts'
require('EmberRoutesProbe/Kernel/BuiltinJobContracts').install()
local model=dofile('tests/lua/fixtures/dec003-workcapacity-kernel-host.lua')
local checks=0
local function check(v,m) checks=checks+1 assert(v,m) end
local function near(a,b) return math.abs(a-b)<0.000001 end
-- Test the proposed contract locally before production registration, retaining
-- its gate and all real Record/JobStore guards. Restore it before process exit.
local rule=Contracts.get('COOKING') local originalMutable=rule.capacityMutable
local function setup(root)
    root=root or {} local jobs=assert(JobStore.open(root))
    local st={root=root,claims=Claims.new(),tokens={},cookingTokens={}}
    local S={}
    local function alloc(r,id) r.nextClaimSeq=(r.nextClaimSeq or 0)+1 return id..':c'..r.nextClaimSeq end
    local function identity(r,j) if not j.claimId then j.claimId=alloc(r,j.id) end return j.claimId end
    local function clean(id) st.tokens[id]=nil st.cookingTokens[id]=nil end
    function S.data() return root end
    function S.getToken(id) return st.tokens[id] or st.cookingTokens[id] end
    function S.owner(id) return st.claims.owners['item:'..id] end
    function S.availableCapacity(key,free) return st.claims:available(key,free) end
    package.loaded['EmberRoutesProbe/Work/LaborStore']=S
    package.loaded['EmberRoutesProbe/Runtime/TaskJobs']={current=function() return jobs end}
    require('EmberRoutesProbe/Work/LaborDomainAdapters').install(S,st,identity,clean,function() return true end)
    require('EmberRoutesProbe/Work/LaborJobCommit').install(S,st,alloc,clean)
    model.install(st,alloc,clean)
    require('EmberRoutesProbe/Cooking/CookingJobRecovery').restore({current=root,rebuilt=st.claims,
        hasConflict=function() return false end,ensureEntityClaimId=identity,rebuiltCooking=st.cookingTokens})
    return S,st,jobs
end
local function job(id,npc,target,amount)
    return assert(Record.new(id,npc,'base','Soup','AUTO','policy:base',target or .3,amount or .3))
end
local S,st,jobs=setup()
local draft=job('core','chef') assert(S.createClaimedJob(draft))
local token=S.getToken('core') local key='cooking:capacity:core'
local payload=Record.copy(jobs:get('core').payload) payload.claims={key}
payload.capacity={endpointId='cold',amount=4}
local function cmd(amount) return {key='cold',amount=amount} end
local function mutate(p,work,extra)
    local j=jobs:get('core') local m=extra or {} m.workCapacity=work
    return S.mutateJob(j.id,j.revision,p,m)
end
rule.capacityMutable=nil
local ok,why,evidence=mutate(payload,cmd(4),{addKeys={key},obligations={storage=true}})
check(not ok and evidence=='CAPACITY_MUTATION_UNSUPPORTED' and not st.claims.capacity.cold,'closed contract refuses work')
check(Contracts.get('HAUL').capacityMutable and Contracts.get('FIELD_WORK').capacityMutable,'other contracts enabled before registration')
rule.capacityMutable=true
check(Contracts.get('HAUL').capacityMutable and Contracts.get('FIELD_WORK').capacityMutable,'other contracts unchanged by candidate registration')
check(mutate(payload,cmd(4),{addKeys={key},obligations={storage=true}}),'first work reserve')
local function exact(amount,count)
    local b=st.claims.capacity.cold local c=b and b.entries.core
    return b and b.total==amount and b.count==count and c and c.amount==amount and c.workAmount==amount
        and c.count==0 and token.capacityKey=='cold' and st.claims.owners[key]==token
end
check(exact(4,1),'first reserve exact work entry')
check(mutate(payload,cmd(4)) and exact(4,1),'idempotent unchanged publish')
payload=Record.copy(payload) payload.capacity.amount=3
check(mutate(payload,cmd(3)) and exact(3,1),'shrink by difference')
local update=jobs.update
local function refuse() return false,'INJECTED_CAS_REFUSAL' end
for _,amount in ipairs({2,3}) do
    local p=Record.copy(payload) p.capacity.amount=amount
    local rev=jobs:get('core').revision jobs.update=refuse
    ok,why=mutate(p,cmd(amount)) jobs.update=update
    check(not ok and why=='TASK_WRITE_FAILURE' and jobs:get('core').revision==rev and exact(3,1),
        'CAS restore exact amount/count/key/resources; amount '..amount)
end
local released=Record.copy(payload) released.capacity=nil released.claims={}
jobs.update=refuse
ok,why=mutate(released,false,{removeKeys={key},obligations={}}) jobs.update=update
check(not ok and exact(3,1),'zero release + shrink refusal restores owners and work')
check(mutate(released,false,{removeKeys={key},obligations={}}),'zero release and owners removal')
check(st.claims.capacity.cold==nil and token.capacityKey==nil and st.claims.owners[key]==nil
    and jobs:get('core').obligations.storage==nil,'empty bucket cleanup and storage clear')
check(mutate(released,false) and not st.claims.capacity.cold and not token.capacityKey,'false without prior capacity key is a no-op release')
-- Newly created work entry must not survive CAS refusal (workExists=false).
jobs.update=refuse
ok=mutate(payload,cmd(3),{addKeys={key},obligations={storage=true}}) jobs.update=update
check(not ok and st.claims.capacity.cold==nil and not token.capacityKey and not st.claims.owners[key],
    'absent-before work is not rebuilt')
check(mutate(payload,cmd(3),{addKeys={key},obligations={storage=true}}),'reserve again')
for _,work in ipairs({{key='other',amount=3},{key='cold',amount=0},{key='cold',amount=-1},{key='cold',amount=0/0},
    {key='cold',amount=math.huge},{key='cold',amount=3,extra=true},{key='',amount=3}}) do
    ok,why,evidence=mutate(payload,work)
    check(not ok and evidence==(work.key=='other' and 'CAPACITY_TARGET_CHANGED' or 'CAPACITY_SHAPE_INVALID')
        and exact(3,1),'shape / target refusal preserves promise')
end
local b=st.claims.capacity.cold local c=b.entries.core
c.count=1
check(model.setWork(st.claims,token,'cold',2)=='CAPACITY_UNAVAILABLE' and c.amount==3,'item-entry count refuses work')
c.count=0 local foreign={taskId='foreign'} c.token=foreign
check(model.setWork(st.claims,token,'cold',2)=='CAPACITY_UNAVAILABLE' and c.token==foreign and c.amount==3,'foreign entry never overwritten')
c.token=token
-- Follow-up: all command execution below is the host model, never JVM execution.
local oldBucket=st.claims.capacity.cold
check(model.setWork(st.claims,token,'cold',3)==nil and model.setWork(st.claims,token,'cold',3)==nil
    and exact(3,1) and st.claims.capacity.cold==oldBucket,'direct set same key/amount is idempotent')
for _,amount in ipairs({0,-1,math.huge,0/0}) do
    check(model.setWork(st.claims,token,'new-shape',amount)=='CAPACITY_UNAVAILABLE'
        and not st.claims.capacity['new-shape'] and token.capacityKey=='cold','invalid direct new-key shape has no writes')
end
check(model.setWork(st.claims,token,'new-target',2)=='CAPACITY_TARGET_CHANGED'
    and not st.claims.capacity['new-target'] and token.capacityKey=='cold','new target failure has no writes')
local own=st.claims.owners[key] st.claims.owners[key]=nil
check(model.setWork(st.claims,token,'new-owner',2)=='STALE_CLAIM'
    and not st.claims.capacity['new-owner'] and token.capacityKey=='cold','new owner failure has no writes')
st.claims.owners[key]=own
local entry=oldBucket.entries.core
for _,kind in ipairs({'mixed','foreign','wrong-bucket','items-only','foreign-owner'}) do
    local oldKey=token.capacityKey
    if kind=='foreign-owner' then st.claims.owners[key]={} end
    if kind=='mixed' then entry.items[777]=1 entry.count=1 end
    if kind=='foreign' then entry.token={} end
    if kind=='wrong-bucket' then token.capacityKey=nil end
    if kind=='items-only' then entry.items[777]=1 end
    local savedOwner=st.claims.owners[key]
    local accepted,code,ev=mutate(payload,cmd(2))
    check(not accepted and code=='CAPACITY_FAILURE' and ev=='CAPACITY_ENTRY_INVALID'
        and oldBucket.total==3 and oldBucket.count==1 and entry.amount==3
        and st.claims.owners[key]==savedOwner and ((kind=='wrong-bucket' and token.capacityKey==nil) or (kind~='wrong-bucket' and token.capacityKey==oldKey)),
        'invalid work entry refused before snapshot: '..kind)
    entry.items={} entry.count=0 entry.token=token token.capacityKey=oldKey st.claims.owners[key]=own
end
ok,why,evidence=mutate(payload,cmd(2),{removeKeys={'not-owned'}})
check(not ok and evidence=='RESOURCE_NOT_OWNED' and exact(3,1),'unowned remove rejected before work, as in Java')
entry.workAmount=nil entry.count=1 entry.items[777]=3
ok,why,evidence=mutate(payload,cmd(2))
check(not ok and evidence=='CAPACITY_UNAVAILABLE' and oldBucket.total==3 and oldBucket.count==1
    and entry.amount==3 and entry.items[777]==3,'existing item entry stays unchanged under work set')
entry.workAmount=3 entry.count=0 entry.items={}
local shrink=st.claims.shrink local sawWork=false
st.claims.shrink=function(self,t,keys)
    sawWork=self.capacity.cold.entries.core.amount==2
    return false,'INJECTED_SHRINK_REFUSAL'
end
ok,why=mutate(payload,cmd(2),{removeKeys={key}})
st.claims.shrink=shrink
check(not ok and why=='CLAIM_FAILURE' and sawWork and exact(3,1),'work-before-shrink refusal restores amount and owners')

local haul=assert(st.claims:acquireNew('haul',0,{'item:999'},{claimId='haul:c1'}))
check(st.claims:available('cold',6)==3 and st.claims:reserve(haul,'cold',999,2,6),'HAUL sees work and shares bucket')
check(st.claims.capacity.cold.total==5 and st.claims.capacity.cold.count==2,'shared total and entries')
check(not st.claims:reserve(haul,'cold',999,4,6) and st.claims.capacity.cold.total==5,'HAUL cannot overbook shared work')
st.claims:release(haul)
-- Terminal cleanup alone releases work, no explicit workCapacity command.
local settled=Record.copy(released) settled.phase='SETTLED'
local j=jobs:get('core')
check(S.cancelJob(j.id,j.revision,settled,{state='CANCELLED',obligations={}}),'cancel without work command')
check(not st.claims.capacity.cold and not token.capacityKey and not st.claims.owners[key],'cancel releases work and owners')
if arg[1]=='core' then rule.capacityMutable=originalMutable check(rule.capacityMutable==originalMutable,'core switch restored') print('PASS '..checks..' work-capacity core model assertions; NOT Java execution') return end
local root={} S,st,jobs=setup(root)
local quota=assert(Budget.open(root,jobs))
local function job(id,npc,target,amount)
    return assert(Record.new(id,npc,'base','Soup','AUTO','policy:base',target or 0.3,amount or 0.3))
end
local function snapshot(n,ready,min)
    local v=assert(quota:view('base'))
    return {scopeId='base',stamp=v.stamp,complete=true,population=n or 2,ready=ready or 0,
        minimum=min or 0.1,active=false}
end
local before=snapshot()
check(quota:reserve(job('cook-a','a'),before),'first cook receives finite quota')
check(not quota:reserve(job('cook-b','b'),before),'same-frame contender cannot use old supply stamp')
check(not quota:reserve(job('cook-a','a'),snapshot()),'duplicate request does not create/replay job')
local v=assert(quota:view('base'))
check(near(v.blocked,0.3) and v.pending==0,'unconfirmed output retains quota but is not edible or predicted food')
local fresh=snapshot() fresh.complete=false
check(not quota:reserve(job('cook-b','b'),fresh),'unloaded/incomplete observation is not zero stock')
check(quota:reserve(job('cook-b','b'),snapshot()),'second cook can cover different remaining deficit')
check(not quota:reserve(job('cook-c','c'),snapshot()),'two reserved batches prevent third full-deficit claim')
local saved=assert(jobs:get('cook-a'))
local p=Record.copy(saved.payload) p.expected=0.3
check(S.mutateJob(saved.id,saved.revision,p),'verified prediction stays in existing job')
v=assert(quota:view('base'))
check(near(v.pending,0.3) and near(v.blocked,0.3),'prediction and unknown quota have distinct accounting')
local reopened=assert(JobStore.open(root))
local after=assert(Budget.open(root,reopened)):view('base')
check(after.stamp==v.stamp and near(after.pending,v.pending) and near(after.blocked,v.blocked),
    'save/reopen derives exactly same allocations from Jobs without second ledger')
-- A delivered output enters shared ready stock and leaves its old in-progress amount.
saved=assert(jobs:get('cook-a')) p=Record.copy(saved.payload)
p.assets={{id=701,fullType='Base.PotOfSoupRecipe',custody='DELIVERED',role='OUTPUT',effective=0.3}}
check(S.mutateJob(saved.id,saved.revision,p),'delivery publishes original identity and actual amount')
v=assert(quota:view('base'))
check(v.pending==0 and near(v.blocked,0.3),'delivered meal is not counted in both shared S and old P')
local sharedRoot={} local Store,sharedState,sharedJobs=setup(sharedRoot)
local f={a={id='foundation-chef-a'},b={id='foundation-chef-b'}}
local a=job('foundation-a',f.a.id)
local b=job('foundation-b',f.b.id)
check(Store.createClaimedJob(a) and Store.createClaimedJob(b),'cooking stores ordinary durable Jobs')
local ta=assert(Store.claimCooking(a))
local tb=assert(Store.claimCooking(b))
local original=Record.copy(a)
original.payload.assets={{id=987001,fullType='Base.Pot',custody='HELD'}}
original.payload.claims={'item:987001'}
local ok,nextJob,nextToken=Store.replaceCooking(a,ta,original)
check(ok,'original acquired through existing shared claims')
a,ta=nextJob,nextToken
check(Store.owner(987001).taskId==a.id,'other production sees same item owner')
local rejected=Record.copy(a) rejected.payload.quota=0.4
rejected.payload.assets={{id=987002,fullType='Base.Pot',custody='HELD'}} rejected.payload.claims={'item:987002'}
check(not Store.replaceCooking(a,ta,rejected),'durable transition refusal rejects replacement claims')
check(Store.owner(987001).taskId==a.id and not Store.owner(987002) and Store.validCooking(a,ta),
    'failed publish restores old original and token without leaking new claim')
local conflict=Record.copy(b)
conflict.payload.assets={{id=987001,fullType='Base.Pot',custody='HELD'}}
conflict.payload.claims={'item:987001'}
check(not Store.replaceCooking(b,tb,conflict),'other cook cannot steal retained pot')
check(#sharedJobs:get(b.id).payload.claims==0 and Store.owner(987001).taskId==a.id,
    'claim conflict changes neither durable declaration nor old owner')
local prepared=assert(Record.begin(a,'TRANSFER',{987001}))
local good,ja,t1=Store.replaceCooking(a,ta,prepared)
check(good and not Store.validCooking(a,ta),'new attempt fences old token and revision')
a,ta=ja,t1
local unsafeCommit=assert(Record.committing(a,a.payload.attempt.id))
good,ja,t1=Store.replaceCooking(a,ta,unsafeCommit)
check(good,'unknown commit persists in same Job and retains original')
a,ta=ja,t1
check(not Store.finishCooking(a,ta),'unknown original cannot be released')
check(Store.owner(987001).taskId==a.id,'failed finish keeps shared original protected')
-- Rebuild only LaborStore cache, not durable Jobs or other provider data.
local loadedStore
loadedStore,sharedState,sharedJobs=setup(sharedRoot)
check(loadedStore.owner(987001).taskId==a.id,'load restores unknown cooking claims before any new allocation')
check(not loadedStore.validCooking(a,ta),'old in-memory token cannot operate after world claim rebuild')
local reserved=Record.copy(sharedJobs:get(b.id))
reserved.payload.claims={'cooking:capacity:'..b.id}
reserved.payload.capacity={endpointId='foundation-cold',amount=4} reserved.obligations.storage=true
local refreshed=assert(loadedStore.claimCooking(sharedJobs:get(b.id)))
local capacityOK,capacityJob,capacityToken=loadedStore.replaceCooking(sharedJobs:get(b.id),refreshed,reserved)
check(capacityOK and loadedStore.availableCapacity('foundation-cold',6)==2,
    'a durable batch promise shares the existing hauling space budget')
check(loadedStore.availableCooking(capacityJob,capacityToken,'foundation-cold',3)==3,
    'overfull cold storage never invents free space by refunding a clamped promise')
local restored=setup(sharedRoot)
check(restored.availableCapacity('foundation-cold',6)==2,
    'saved cooking promises rebuild before another worker can reserve the destination')

-- Real Capacity -> Context -> replaceCooking -> LaborJobCommit -> host model.
local Store,state,storeJobs=setup()
package.loaded['EmberRoutesProbe/Cooking/CookingContext']=nil
package.loaded['EmberRoutesProbe/Cooking/CookingCapacity']=nil
package.loaded['EmberRoutesProbe/Warehouse/ContainerRegistry']={revalidate=function() return true end}
local Context=require 'EmberRoutesProbe/Cooking/CookingContext'
local Capacity=require 'EmberRoutesProbe/Cooking/CookingCapacity'
local j=job('capacity-chain','chain-chef') assert(Store.createClaimedJob(j))
local c={job=storeJobs:get(j.id),token=assert(Store.claimCooking(storeJobs:get(j.id))),npc={},
    body={current=function() return true end},valid=function() return true end}
EmberRoutesProbeJava.carrierId=function() return 'chain-chef' end
EmberRoutesProbeJava.carrierPresent=function() return true end
local endpoint={id='chain-cold',container={getFreeCapacity=function() return 6 end}}
check(Capacity.reserve(c,endpoint,4),'production reserve reaches commit')
check(state.claims.capacity['chain-cold'].total==4 and c.token.capacityKey==endpoint.id,'adapter reserve publishes work')
local function chainExact()
    local b=state.claims.capacity[endpoint.id] local entry=b and b.entries[j.id]
    return b and b.total==4 and b.count==1 and entry.amount==4 and entry.workAmount==4
        and entry.count==0 and entry.token==c.token and c.token.capacityKey==endpoint.id
        and state.claims.owners['cooking:capacity:'..j.id]==c.token
end
local update=storeJobs.update
for _,amount in ipairs({2,4}) do
    local proposal=Record.copy(c.job) proposal.payload.capacity.amount=amount
    local rev=c.job.revision storeJobs.update=function() return false,'INJECTED_CAS_REFUSAL' end
    check(not Context.publish(c,proposal) and storeJobs:get(j.id).revision==rev and chainExact(),
        'adapter changed/unchanged publish CAS restores exact promise '..amount)
    storeJobs.update=update
end
local beforeCalls=#model.calls
check(Context.publish(c,Record.copy(c.job)) and #model.calls==beforeCalls+1 and chainExact(),'unchanged adapter publish sends command')
local proposal=Record.copy(c.job) Capacity.delivered(proposal,endpoint.id,1)
check(Context.publish(c,proposal) and state.claims.capacity[endpoint.id].total==3,'production delivered shrink')
proposal=Record.copy(c.job) Capacity.delivered(proposal,endpoint.id,3)
check(Context.publish(c,proposal) and not state.claims.capacity[endpoint.id] and not c.token.capacityKey
    and not c.job.obligations.storage and not state.claims.owners['cooking:capacity:'..j.id],'production delivered zero + owners cleanup')
check(Capacity.reserve(c,endpoint,4) and Capacity.release(c) and not state.claims.capacity[endpoint.id],
    'production explicit release cleans empty bucket')
-- HAUL publishes use host-model change() with a minimal CAS store, not the HAUL adapter.
local h=assert(state.claims:acquireNew('cross-haul',0,{'item:999'},{claimId='cross:c1'}))
local hj={id='cross-haul',providerType='HAUL',revision=1,claimId=h.claimId}
local hJobs={get=function() return hj end,update=function() return true,2 end}
local hOwner={getToken=function() return h end}
local function haulChange(amount,free)
    local capacity=false if amount~=false then capacity={key=endpoint.id,items={[999]=amount},free=free or 6} end
    return EmberRoutesProbeJava.laborMutate(hJobs,hOwner,state.claims,Contracts,function() end,hj.id,1,{},
        {capacity=capacity})
end
local function crossExact(cook,haul)
    local b=state.claims.capacity[endpoint.id]
    return b and b.total==cook+haul and b.count==2 and b.entries[j.id].amount==cook
        and b.entries[h.taskId].amount==haul and b.entries[h.taskId].items[999]==haul
        and state.claims.owners['item:999']==h and state.claims.owners['cooking:capacity:'..j.id]==c.token
end
check(Capacity.reserve(c,endpoint,4),'cross cooking-first reserves four')
check(not haulChange(4).ok and haulChange(2).ok and crossExact(4,2),'cooking-first HAUL free check caps at two')
local hEntry=state.claims.capacity[endpoint.id].entries[h.taskId]
local cp=Record.copy(c.job) cp.payload.capacity.amount=3
storeJobs.update=function() return false,'INJECTED_CAS_REFUSAL' end
check(not Context.publish(c,cp) and crossExact(4,2)
    and state.claims.capacity[endpoint.id].entries[h.taskId]==hEntry,'cooking CAS rollback preserves HAUL entry/total/owners')
storeJobs.update=update
local cEntry=state.claims.capacity[endpoint.id].entries[j.id]
hJobs.update=function() return false,'INJECTED_CAS_REFUSAL' end
local hr=haulChange(1)
check(not hr.ok and hr.result=='TASK_WRITE_FAILURE' and crossExact(4,2)
    and state.claims.capacity[endpoint.id].entries[j.id]==cEntry,'HAUL model CAS rollback preserves cooking entry/total/owners')
hJobs.update=function() return true,2 end
hEntry=state.claims.capacity[endpoint.id].entries[h.taskId]
check(Capacity.release(c) and state.claims.capacity[endpoint.id].total==2
    and state.claims.capacity[endpoint.id].entries[h.taskId]==hEntry and state.claims.owners['item:999']==h,
    'release cooking preserves HAUL')
-- Reverse admission is enforced by PRODUCTION Capacity.reserve pre-check, never raw setWork.
check(haulChange(4).ok,'haul-first reserves four')
check(not Capacity.reserve(c,endpoint,4) and state.claims.capacity[endpoint.id].total==4,
    'production reserve pre-check refuses four with only two free')
check(Capacity.reserve(c,endpoint,2) and crossExact(2,4),'production reserve pre-check admits two')
cEntry=state.claims.capacity[endpoint.id].entries[j.id]
check(haulChange(false).ok and state.claims.capacity[endpoint.id].total==2
    and state.claims.capacity[endpoint.id].entries[j.id]==cEntry
    and state.claims.owners['cooking:capacity:'..j.id]==c.token,'release HAUL preserves cooking')
check(haulChange(2).ok,'restore HAUL for cancel isolation')
hEntry=state.claims.capacity[endpoint.id].entries[h.taskId]
local terminal=Record.copy(c.job.payload) terminal.capacity=nil terminal.claims={} terminal.phase='SETTLED'
check(Store.cancelJob(c.job.id,c.job.revision,terminal,{state='CANCELLED',obligations={}})
    and state.claims.capacity[endpoint.id].total==2 and state.claims.capacity[endpoint.id].entries[h.taskId]==hEntry
    and not state.claims.capacity[endpoint.id].entries[j.id] and state.claims.owners['item:999']==h,
    'cancel without work command clears only cooking with HAUL present')
-- Capability toggle isolation: same capacity acceptance/refusal before and after.
for _,provider in ipairs({'HAUL','FIELD_WORK'}) do
    hj.providerType=provider local flag=Contracts.get(provider).capacityMutable
    rule.capacityMutable=nil
    local offGood=haulChange(2).ok local offBad=haulChange(7).result
    rule.capacityMutable=true
    check(Contracts.get(provider).capacityMutable==flag and offGood and haulChange(2).ok
        and offBad==haulChange(7).result and offBad=='CAPACITY_FAILURE',provider..' validation unchanged by test switch')
end

-- Command conflicts are refused before snapshot so foreign entries stay untouched.
local owner=assert(state.claims:acquireNew('conflicts',0,{'cooking:capacity:conflicts'},{claimId='conflicts:c1'}))
local other={taskId='other'}
state.claims.capacity.conflict={entries={conflicts={token=other,items={},count=0,amount=5,workAmount=5}},total=5,count=1}
check(model.setWork(state.claims,owner,'conflict',2)=='CAPACITY_UNAVAILABLE'
    and state.claims.capacity.conflict.entries.conflicts.token==other,'foreign token conflict preserves bucket')
rule.capacityMutable=originalMutable
check(rule.capacityMutable==originalMutable,'test-only capability restored')
print('PASS '..checks..' work-capacity assertions; host model NOT Java execution')
