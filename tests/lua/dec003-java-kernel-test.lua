-- Run ONLY with KahluaLaborTest --java-labor; never a Lua kernel substitute.
assert(ERLaborTestBridge,'Actual LaborCommitKernel bridge required')
local Contracts=require 'EmberRoutesProbe/Kernel/JobContracts'
assert(Contracts.register('DEC003_KERNEL',{schemaVersion=1,capacityMutable=true,validate=function() return true end,errorCodes={}}))
local Claims=require 'EmberRoutesProbe/Kernel/LaborClaims'
local Jobs=require 'EmberRoutesProbe/Kernel/JobStore'
local Ledger=require 'EmberRoutesProbe/Kernel/ObligationLedger'
local root={format=2,nextClaimSeq=0,obligations=Ledger.fresh()}
local jobs=assert(Jobs.open(root))
local state={root=root,claims=Claims.new(),tokens={},cookingTokens={}}
local Store={data=function() return root end}
Store.getToken=function(id) return state.claims.tokensByTaskId[id] end
Store.quarantineResource=function() error('kernel must never quarantine') end
package.loaded['EmberRoutesProbe/Runtime/TaskJobs']={current=function() return jobs end}
require('EmberRoutesProbe/Work/LaborJobCommit').install(Store,state,function(r,id)
    r.nextClaimSeq=r.nextClaimSeq+1 return id..':c'..r.nextClaimSeq
end,function(id) state.tokens[id]=nil end)
local originalUpdate,originalCreate
local function freshWorld()
    root={format=2,nextClaimSeq=0,obligations=Ledger.fresh()}
    jobs=assert(Jobs.open(root))
    state={root=root,claims=Claims.new(),tokens={},cookingTokens={}}
    Store={data=function() return root end}
    Store.getToken=function(id) return state.claims.tokensByTaskId[id] end
    Store.quarantineResource=function() error('kernel must never quarantine') end
    require('EmberRoutesProbe/Kernel/CommitFence').enter(root)
    require('EmberRoutesProbe/Work/LaborJobCommit').install(Store,state,function(r,id)
        r.nextClaimSeq=r.nextClaimSeq+1 return id..':c'..r.nextClaimSeq
    end,function(id) state.tokens[id]=nil end)
    originalUpdate=jobs.update originalCreate=jobs.create
end
local n=0
local function check(v,label) n=n+1 assert(v,label) end
local function draft(id,first)
    return {id=id,npcId=id,providerType='DEC003_KERNEL',scopeId=id,revision=1,state='PREPARING',
        effects='KNOWN',obligations={},payload={claims={'item:'..first}}}
end
assert(Contracts.register('DEC003_NOTIFY',{schemaVersion=1,tokenBucket='cooking',validate=function() return true end,errorCodes={}}))
local observed
local unwatch=jobs:watch(function(_,id)
    if id=='notify' then
        local token=state.claims.tokensByTaskId[id]
        observed=token~=nil and state.tokens[id]==token and state.cookingTokens[id]==token
    end
end)
local notify=draft('notify',99) notify.providerType='DEC003_NOTIFY'
check(Store.createClaimedJob(notify) and observed,'create observer sees both token caches')
unwatch()
local beforeCreate=jobs.create
jobs.create=function() return false,'INJECTED_REJECT' end
local rejected=draft('notify-reject',98) rejected.providerType='DEC003_NOTIFY'
local accepted=Store.createClaimedJob(rejected)
jobs.create=beforeCreate
check(not accepted and not state.tokens[rejected.id] and not state.cookingTokens[rejected.id]
    and not state.claims.owners['item:98'],'rejected create restores both token caches and claim')
assert(Contracts.register('DEC003_TRANSFER',{schemaVersion=1,tokenBucket='cooking',validate=function() return true end,
    transferValid=function(a,b) return (b.npcId=='new-owner' or b.npcId=='duty-owner') and b.revision==a.revision+1 end,
    transferReason='TRANSFER_REJECTED',errorCodes={TRANSFER_REJECTED='transfer rejected'}}))
local transfer=draft('transfer',97) transfer.providerType='DEC003_TRANSFER'
assert(Store.createClaimedJob(transfer))
local originalToken=state.cookingTokens.transfer
local proposed=jobs:get('transfer') proposed.npcId='new-owner' proposed.revision=2
local transferObserved
local releaseTransfer=jobs:watch(function(_,id)
    if id=='transfer' then
        local token=state.cookingTokens.transfer
        transferObserved=token~=originalToken and state.claims.tokensByTaskId.transfer==token
            and state.claims.owners['item:97']==token
    end
end)
check(Store.transferJobOwner('transfer',1,proposed,originalToken) and transferObserved,
    'transfer observer sees new owner and rotated claim together')
releaseTransfer()
local newToken=state.cookingTokens.transfer
local rejectedTransfer=jobs:get('transfer') rejectedTransfer.npcId='wrong-owner' rejectedTransfer.revision=3
local transferred=Store.transferJobOwner('transfer',2,rejectedTransfer,newToken)
check(not transferred and state.cookingTokens.transfer==newToken and state.claims.owners['item:97']==newToken
    and jobs:get('transfer').revision==2,'rejected transfer restores original claim and owner')
check(not Store.transferJobOwner('transfer',2,rejectedTransfer,originalToken),'stale transfer token rejected')
root.obligations=require('EmberRoutesProbe/Kernel/ObligationLedger').fresh()
local Cooking=require 'EmberRoutesProbe/Cooking/CookingRecord'
local cook=assert(Cooking.new('real-cook','chef','world','profile','AUTO','source',1,1))
assert(Store.createClaimedJob(cook))
local cookingPayload=Cooking.copy(cook.payload)
cookingPayload.claims={'cooking:oven'}
cookingPayload.dutySequence=1
cookingPayload.duty={id='real-cook:furnace:1',siteKey='cooking:oven',ownerId='chef',revision=1,
    originalActive=false,openedByJob=false,lastActive=false,state='RESERVED'}
local stoveObligation={id='real-cook:furnace:1',type='FURNACE_DUTY',npcId='chef',jobId='real-cook',
    revision=1,state='ACTIVE',data={siteKey='cooking:oven'}}
check(not Store.mutateJob(cook.id,1,cookingPayload,{addKeys={'cooking:oven'}})
    and not state.claims.owners['cooking:oven'],'furnace claim cannot publish without independent obligation')
check(Store.mutateJob(cook.id,1,cookingPayload,{addKeys={'cooking:oven'},
    obligationOps={{action='CREATE',id=stoveObligation.id,record=stoveObligation}}}),
    'cooking reserve creates independent furnace obligation with claim')
local afterReserve=jobs:get(cook.id).payload
afterReserve.duty=nil afterReserve.claims={}
check(not Store.mutateJob(cook.id,2,afterReserve,{removeKeys={'cooking:oven'}})
    and state.claims.owners['cooking:oven'],'furnace cannot release while obligation remains')
check(Store.mutateJob(cook.id,2,afterReserve,{removeKeys={'cooking:oven'},obligationOps={{action='SETTLE',
    id=stoveObligation.id,expectedRevision=1,evidence={effects='KNOWN',siteKey='cooking:oven',inactive=true,
        foodClear=true,shutdownRequired=false}}}}),'observed inactive furnace settles with claim release')
local duty=draft('duty-transfer',93) duty.providerType='DEC003_TRANSFER' duty.payload.claims={'stove:test'}
local dutyOwed={id='duty:93',type='FURNACE_DUTY',npcId=duty.npcId,jobId=duty.id,revision=1,
    state='ACTIVE',data={siteKey='stove:test',openedByJob=true}}
assert(Store.createClaimedJob(duty,{{action='CREATE',id=dutyOwed.id,record=dutyOwed}}))
local dutyToken=state.cookingTokens[duty.id]
local dutyNext=jobs:get(duty.id) dutyNext.npcId='duty-owner' dutyNext.revision=2
check(not Store.transferJobOwner(duty.id,1,dutyNext,dutyToken)
    and state.cookingTokens[duty.id]==dutyToken,'owner cannot move without active furnace obligation')
local dutyObserved
local releaseDuty=jobs:watch(function(_,id)
    if id==duty.id then dutyObserved=root.obligations.byId[dutyOwed.id].npcId=='duty-owner'
        and state.claims.owners['stove:test']==state.cookingTokens[id] end
end)
local dutyOps={{action='TRANSFER',id=dutyOwed.id,expectedRevision=1,npcId='duty-owner',
    evidence={siteKey='stove:test',siteVerified=true,originalsVerified=true,bodyReleased=true}}}
check(Store.transferJobOwner(duty.id,1,dutyNext,dutyToken,dutyOps) and dutyObserved,
    'furnace owner, obligation and token visible together')
releaseDuty()
local created=draft('create-obligation',95)
local createdOwed={id='held:95',type='CARRIED_ITEM',npcId=created.npcId,jobId=created.id,
    revision=1,state='ACTIVE',data={itemId=95,sourceId='source'}}
local createdObserved
local releaseCreate=jobs:watch(function(_,id)
    if id==created.id then createdObserved=root.obligations.byId[createdOwed.id]~=nil
        and state.tokens[id]==state.claims.owners['item:95'] end
end)
check(Store.createClaimedJob(created,{{action='CREATE',id=createdOwed.id,record=createdOwed}})
    and createdObserved,'create observer sees Job, obligation and claim')
releaseCreate()
local badCreate=draft('create-mismatch',94)
local badOwed={id='held:94',type='CARRIED_ITEM',npcId='other',jobId=badCreate.id,
    revision=1,state='ACTIVE',data={itemId=94,sourceId='source'}}
check(not Store.createClaimedJob(badCreate,{{action='CREATE',id=badOwed.id,record=badOwed}})
    and not jobs:peek(badCreate.id) and not state.claims.owners['item:94']
    and not root.obligations.byId[badOwed.id],'invalid obligation create rolls back claim and Job')
local atomic=draft('atomic-obligation',96) assert(Store.createClaimedJob(atomic))
local obligation={id='held:96',type='CARRIED_ITEM',npcId=atomic.npcId,jobId=atomic.id,
    revision=1,state='ACTIVE',data={itemId=96,sourceId='source'}}
local paired
local releaseAtomic=jobs:watch(function(_,id)
    if id==atomic.id then
        local r=root.obligations.byId[obligation.id]
        paired=jobs:peek(id).revision==2 and r and r.state=='ACTIVE'
    end
end)
check(Store.mutateJob(atomic.id,1,atomic.payload,{obligationOps={{action='CREATE',id=obligation.id,record=obligation}}})
    and paired,'observer sees job and obligation together')
releaseAtomic()
local invalidRelease=Store.mutateJob(atomic.id,2,{claims={}},{removeKeys={'item:96'}})
check(not invalidRelease and state.claims.owners['item:96'],'active liability forbids releasing its original claim')
local terminal=Store.mutateJob(atomic.id,2,atomic.payload,{state='SETTLING'})
assert(terminal)
local done=Store.mutateJob(atomic.id,3,{claims={}},{state='DONE',removeKeys={'item:96'}})
check(not done and jobs:get(atomic.id).revision==3,'terminal Job retains active independent obligation')
done=Store.mutateJob(atomic.id,3,{claims={}},{state='DONE',removeKeys={'item:96'},obligationOps={{action='SETTLE',id=obligation.id,
    expectedRevision=1,evidence={effects='KNOWN',itemId=96,destinationId='box',originalPresent=true,attemptId='attempt'}}}})
check(done and root.obligations.byId[obligation.id].state=='SETTLED','settlement and terminal Job publish together')
check(jobs:removeSettled(atomic.id,4) and not root.obligations.byId[obligation.id]
    and root.obligations.byId[createdOwed.id].state=='ACTIVE','retiring settled Job prunes only its proven settled obligation')
-- Creation retains existing per-item reservation semantics (no new 30 limit).
local wide=draft('wide',100) wide.payload.claims={} wide.payload.reservation={key='wide',items={},free=100}
for i=100,130 do wide.payload.claims[#wide.payload.claims+1]='item:'..i wide.payload.reservation.items[i]=1 end
check(Store.createClaimedJob(wide),'creation retains >30 item acceptance')
local a=draft('main',1)
check(Store.createClaimedJob(a),'Java create')
check(state.claims.owners['item:1']==Store.getToken(a.id),'create owner')
local p=jobs:get(a.id).payload
p.claims={'item:1','item:2'} p.reservation={key='dest',items={[1]=1,[2]=2},free=20}
local ok,why=Store.mutateJob(a.id,1,p,{addKeys={'item:2'},capacity=p.reservation})
check(ok and why==2,'extend then capacity then CAS')
check(Store.getToken(a.id)==state.claims.owners['item:2'] and state.claims.capacity.dest.total==3,'claimed published payload')
ok,why=Store.mutateJob(a.id,1,p,{})
check(not ok and why=='STALE_REVISION','stale revision')
p=jobs:get(a.id).payload
-- Malformed command replaces the removed reservation equality assertion.
ok,why=Store.mutateJob(a.id,2,p,{capacity={key='dest',items='invalid',free=20}})
check(not ok and why=='INVALID_REQUEST' and jobs:get(a.id).revision==2,'invalid capacity shape')
-- addKeys on a recovered token whose resource list aliases persistent facts
-- must never mutate the stored payload before CAS.
local token=Store.getToken(a.id)
token.resources=jobs:peek(a.id).payload.claims
p=jobs:get(a.id).payload p.claims[#p.claims+1]='item:3'
originalUpdate=jobs.update
jobs.update=function(self,id,rev,patch)
    check(#self:peek(id).payload.claims==2,'extend detached from authority before CAS')
    return false,'INJECTED_REJECT'
end
ok,why=Store.mutateJob(a.id,2,p,{addKeys={'item:3'}})
jobs.update=originalUpdate
check(not ok and why=='TASK_WRITE_FAILURE' and not state.claims.owners['item:3'],'CAS rejection rolls addition back')
-- Callback throw is returned without a second publication or quarantine.
jobs.update=function() error('CAS_THROW') end
ok,why=Store.mutateJob(a.id,2,jobs:get(a.id).payload,{})
jobs.update=originalUpdate
check(not ok and why=='TASK_WRITE_FAILURE','mutate callback throw wrapped')
check(not Store.createClaimedJob(draft('blocked-after-throw',91)),'ambiguous mutate fences later commits')
freshWorld()
local b=draft('create-fail',10) b.payload.reservation={key='full',items={[10]=2},free=0}
ok,why=Store.createClaimedJob(b)
check(not ok and why=='CAPACITY_FAILURE' and not jobs:get(b.id) and not state.claims.owners['item:10'],'create capacity rollback')
originalCreate=jobs.create
jobs.create=function() error('CREATE_THROW') end
ok,why=Store.createClaimedJob(draft('create-throw',11))
jobs.create=originalCreate
check(not ok and why=='TASK_WRITE_FAILURE','create callback throw wrapped')
check(not Store.createClaimedJob(draft('blocked-after-create',92)),'ambiguous create fences later commits')
freshWorld()
local c=draft('cancel',20) check(Store.createClaimedJob(c),'cancel fixture')
ok,why=Store.cancelJob(c.id,1,c.payload,{})
check(not ok and why=='TASK_WRITE_FAILURE' and jobs:get(c.id).revision==1,'cancel blocked claims')
local cleared={claims={}}
ok,why=Store.cancelJob(c.id,1,cleared,{removeKeys={'item:20'}})
check(ok and why==2 and jobs:get(c.id).state=='CANCELLED' and not Store.getToken(c.id),'cancel from PREPARING')
local d=draft('done',30) assert(Store.createClaimedJob(d))
assert(Store.mutateJob(d.id,1,d.payload,{state='SETTLING'}))
ok,why=Store.mutateJob(d.id,2,{claims={}},{state='DONE',removeKeys={'item:30'}})
check(ok and why==3 and not Store.getToken(d.id),'normal end DONE through kernel')
-- Shrink is visible to CAS; explicit rejection restores both owners and capacity.
local e=draft('pre-cas',40)
e.payload.reservation={key='before',items={[40]=1},free=20}
assert(Store.createClaimedJob(e))
jobs.update=function(self,id,rev,patch)
    check(not state.claims.owners['item:40'],'shrink precedes CAS')
    return false,'INJECTED_REJECT'
end
ok,why=Store.mutateJob(e.id,1,{claims={}},{removeKeys={'item:40'}})
jobs.update=originalUpdate
check(not ok and why=='TASK_WRITE_FAILURE' and jobs:get(e.id).revision==1
    and state.claims.owners['item:40']==Store.getToken(e.id)
    and state.claims.capacity.before.total==1,'pre-CAS restore leaves nothing applied')
-- Terminal cleanup throw leaves the successful CAS intact, without compensation.
local g=draft('cleanup-throw',60) assert(Store.createClaimedJob(g))
require('EmberRoutesProbe/Work/LaborJobCommit').install(Store,state,function() error('unused') end,
    function() error('CLEANUP_THROW') end)
local updates=0
local originalCancel=jobs.cancel
jobs.cancel=function(self,id,rev,patch)
    updates=updates+1
    return originalCancel(self,id,rev,patch)
end
local evidence
ok,why,evidence=Store.cancelJob(g.id,1,{claims={}},{removeKeys={'item:60'}})
check(not ok and why=='TASK_WRITE_FAILURE' and updates==1 and jobs:get(g.id).revision==2
    and jobs:get(g.id).state=='CANCELLED' and type(evidence)=='string'
    and evidence:find('CAS_REACHED_RELOAD_FROM_SAVE',1,true),'post-CAS cleanup marker only')
freshWorld()
-- Restore failure returns a marker; prior revision/state remains untouched.
local f=draft('restore-fail',50) f.payload.reservation={key='old',items={[50]=1},free=20}
-- Restore the normal cleanup for subsequent fixtures.
require('EmberRoutesProbe/Work/LaborJobCommit').install(Store,state,function(r,id)
    r.nextClaimSeq=r.nextClaimSeq+1 return id..':c'..r.nextClaimSeq
end,function(id) state.tokens[id]=nil end)
assert(Store.createClaimedJob(f))
updates=0
jobs.update=function(self,id,rev,patch)
    updates=updates+1
    state.claims.owners['item:50']={taskId='unexpected',resources={'item:50'}}
    return false,'CAS_REJECTED_AFTER_OWNER_CHANGE'
end
local changed=jobs:get(f.id).payload changed.reservation.key='new'
ok,why,evidence=Store.mutateJob(f.id,1,changed,{capacity={key='new',items={[50]=1},free=20}})
jobs.update=originalUpdate
check(not ok and why=='ROLLBACK_FAILURE' and type(evidence)=='string'
    and evidence:find('RECONCILE_REQUIRED',1,true) and updates==1
    and jobs:get(f.id).revision==1 and jobs:get(f.id).state=='PREPARING','single restore failure marker only')
check(not Store.createRefusedBeforeWrite(why,evidence),'restore failure is never a clean refusal')
freshWorld()
-- A store refusal before its write is the only TASK_WRITE_FAILURE proven clean.
assert(Contracts.register('DEC003_FENCE',{schemaVersion=1,validate=function() return true end,
    blocksScope=function(j) return j.payload.fence==true end,scopeBlockedReason='CRAFT_SCOPE_RECONCILE_REQUIRED',
    errorCodes={CRAFT_SCOPE_RECONCILE_REQUIRED='fixture scope fence refusal'}}))
local fence=draft('fence',70) fence.providerType='DEC003_FENCE' fence.scopeId='fenced' fence.payload.fence=true
assert(Store.createClaimedJob(fence))
check(jobs:scopeBlocked('fenced'),'fence fixture blocks its scope')
local refused=draft('fenced-refusal',71) refused.scopeId='fenced'
ok,why,evidence=Store.createClaimedJob(refused)
check(not ok and why=='TASK_WRITE_FAILURE' and evidence=='CRAFT_SCOPE_RECONCILE_REQUIRED','scope fence refusal: code and exact evidence')
check(not jobs:peek(refused.id) and not state.claims.owners['item:71'] and not state.claims.tokensByTaskId[refused.id],
    'refusal wrote no Job and released the new token')
check(Store.createRefusedBeforeWrite(why,evidence),'refusal before the write is recognised')
-- A throw after the store wrote the Job is prefixed and never recognised.
-- The thrown text names a refusal code: only an exact, unprefixed match counts.
jobs.create=function(self,job) originalCreate(self,job) error('CRAFT_SCOPE_RECONCILE_REQUIRED') end
ok,why,evidence=Store.createClaimedJob(draft('after-write',72))
jobs.create=originalCreate
check(not ok and why=='TASK_WRITE_FAILURE' and jobs:peek('after-write') and type(evidence)=='string'
    and evidence:find('CAS_REACHED_RELOAD_FROM_SAVE:',1,true)==1,'post-write throw is prefixed')
check(not Store.createRefusedBeforeWrite(why,evidence),'post-write throw is not recognised')
print('PASS '..n..' actual Java kernel contract checks; game NOT RUN')
