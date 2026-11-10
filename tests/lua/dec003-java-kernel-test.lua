-- Run ONLY with KahluaLaborTest --java-labor; never a Lua kernel substitute.
assert(ERLaborTestBridge,'Actual LaborCommitKernel bridge required')
local Contracts=require 'EmberRoutesProbe/Kernel/JobContracts'
assert(Contracts.register('DEC003_KERNEL',{schemaVersion=1,capacityMutable=true,validate=function() return true end,errorCodes={}}))
local Claims=require 'EmberRoutesProbe/Kernel/LaborClaims'
local Jobs=require 'EmberRoutesProbe/Kernel/JobStore'
local root={nextClaimSeq=0}
local jobs=assert(Jobs.open(root))
local state={root=root,claims=Claims.new(),tokens={}}
local Store={data=function() return root end}
Store.getToken=function(id) return state.claims.tokensByTaskId[id] end
Store.quarantineResource=function() error('kernel must never quarantine') end
package.loaded['EmberRoutesProbe/Runtime/TaskJobs']={current=function() return jobs end}
require('EmberRoutesProbe/Work/LaborJobCommit').install(Store,state,function(r,id)
    r.nextClaimSeq=r.nextClaimSeq+1 return id..':c'..r.nextClaimSeq
end,function(id) state.tokens[id]=nil end)
local n=0
local function check(v,label) n=n+1 assert(v,label) end
local function draft(id,first)
    return {id=id,npcId=id,providerType='DEC003_KERNEL',scopeId=id,revision=1,state='PREPARING',
        effects='KNOWN',obligations={},payload={claims={'item:'..first}}}
end
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
local originalUpdate=jobs.update
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
local b=draft('create-fail',10) b.payload.reservation={key='full',items={[10]=2},free=0}
ok,why=Store.createClaimedJob(b)
check(not ok and why=='CAPACITY_FAILURE' and not jobs:get(b.id) and not state.claims.owners['item:10'],'create capacity rollback')
local originalCreate=jobs.create
jobs.create=function() error('CREATE_THROW') end
ok,why=Store.createClaimedJob(draft('create-throw',11))
jobs.create=originalCreate
check(not ok and why=='TASK_WRITE_FAILURE','create callback throw wrapped')
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
-- A store refusal before its write is the only TASK_WRITE_FAILURE proven clean.
assert(Contracts.register('DEC003_FENCE',{schemaVersion=1,validate=function() return true end,
    blocksScope=function(j) return j.payload.fence==true end,errorCodes={}}))
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
