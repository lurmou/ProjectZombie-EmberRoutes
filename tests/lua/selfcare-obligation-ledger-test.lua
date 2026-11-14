assert(ERLaborTestBridge,'actual Java labor kernel required')
local Ledger=require 'EmberRoutesProbe/Kernel/ObligationLedger'
local Jobs=require 'EmberRoutesProbe/Kernel/JobStore'
local Claims=require 'EmberRoutesProbe/Kernel/LaborClaims'
local root={format=2,nextClaimSeq=0,obligations=Ledger.fresh()}
local jobs=assert(Jobs.open(root))
local state={root=root,claims=Claims.new(),tokens={},cookingTokens={},personalTokens={},activityTokens={},fieldTokens={}}
local serial=0
local Registry={data=function() return root end,id=function() serial=serial+1 return 'u'..serial end}
package.loaded['EmberRoutesProbe/Warehouse/ContainerRegistry']=Registry
package.loaded['EmberRoutesProbe/Runtime/TaskJobs']={current=function() return jobs end}
local Store={data=function() return root end}
Store.getToken=function(id) return state.claims.tokensByTaskId[id] end
package.loaded['EmberRoutesProbe/Work/LaborStore']=Store
EmberRoutesProbeJava=ERLaborTestBridge
require('EmberRoutesProbe/Work/LaborJobCommit').install(Store,state,function(r,id)
    r.nextClaimSeq=r.nextClaimSeq+1 return id..':c'..r.nextClaimSeq
end,function(id) state.tokens[id]=nil end)
require('EmberRoutesProbe/Work/LaborDomainAdapters').install(Store,state,
    function(_,job) return job.claimId end,function(id) state.tokens[id]=nil end,function() return true end)
local Personal=require 'EmberRoutesProbe/SelfCare/SelfCareRecord'
local Ob=require 'EmberRoutesProbe/SelfCare/SelfCareObligations'
local Commit=require 'EmberRoutesProbe/SelfCare/SelfCareCommit'
local source={items={}}
function source:getItems() return {contains=function(_,x) return source.items[x]==true end} end
Registry.resolve=function(id) if id=='source' then return {id=id,container=source} end end
local item={getID=function() return 101 end,getContainer=function(self) return self.container end,container=source}
source.items[item]=true
local job=Personal.create('personal','worker') assert(Store.createClaimedJob(job)) job=jobs:get(job.id)
local p=assert(Personal.begin(job,'EAT')) p.itemId=101 p.sourceId='source' p.claims={'item:101'} p.fraction=.5
local id,op=Ob.create(job,p) p.obligationId=id
local seen local unwatch=jobs:watch(function(_,key)
    if key==job.id then local t=state.claims.tokensByTaskId[key] seen=t and t.generation==jobs:peek(key).payload.sequence end
end)
assert(Commit.update(job.id,job.revision,{payload=p,obligationOps={op}}) and seen) unwatch()
job=jobs:get(job.id) local token=assert(Store.claimPersonal(job))
assert(root.obligations.byId[id].state=='ACTIVE' and state.claims.owners['item:101'])
assert(Jobs.check(root),'cold admission accepts personal debt')
local attempted=jobs:get(job.id) attempted.payload.claims={}
assert(not Commit.update(job.id,attempted.revision,{payload=attempted.payload}),'unsettled responsibility retains claim')
local ops=assert(Ob.settlement(job,job.payload,{[101]=item},'KNOWN',true))
assert(Commit.update(job.id,job.revision,{obligationOps=ops}))
job=jobs:get(job.id) assert(root.obligations.byId[id].state=='SETTLED')
local idle=job.payload idle.step='IDLE' assert(Commit.update(job.id,job.revision,{payload=idle})) job=jobs:get(job.id)
assert(Store.finishPersonal(job,token)) job=jobs:get(job.id)
local nextPayload=assert(Personal.begin(job,'EAT')) nextPayload.itemId=101 nextPayload.sourceId='source'
nextPayload.claims={'item:101'} nextPayload.fraction=.5
local nextId,nextOp=Ob.create(job,nextPayload) nextPayload.obligationId=nextId
assert(Commit.update(job.id,job.revision,{payload=nextPayload,obligationOps={nextOp}}))
job=jobs:get(job.id) assert(not root.obligations.byId[id] and root.obligations.byId[nextId])
local payload=job.payload payload.consumption={attemptId=payload.attemptId,itemId=101,kind='EAT',fullType='Base.Food',
    before=1,fraction=.5,started=true,completed=true,stopped=false,effects='KNOWN',after=0,consumed=1,outputs={102}}
payload.claims[#payload.claims+1]='item:102'
assert(Commit.update(job.id,job.revision,{payload=payload})) job=jobs:get(job.id)
item.container=nil source.items[item]=nil
assert(not Ob.settlement(job,job.payload,{[101]=item},'KNOWN',false),'missing output cannot settle consumption')
local forged={{action='SETTLE',id=nextId,expectedRevision=1,evidence={effects='KNOWN',itemId=101,
    attemptId=job.payload.attemptId,destinationId='source',kind='CONSUMED',consumptionKind='EAT',outputs={}}}}
assert(not Commit.update(job.id,job.revision,{obligationOps=forged}),'missing output receipt rejected')
local output={getID=function() return 102 end,getContainer=function(self) return self.container end,container=source}
source.items[output]=true
local consumed=assert(Ob.settlement(job,job.payload,{[101]=item,[102]=output},'KNOWN',false))
assert(Commit.update(job.id,job.revision,{obligationOps=consumed}))
assert(root.obligations.byId[nextId].settlement.kind=='CONSUMED')
print('PASS self-care unchanged, repeated attempt and consumed receipt through actual Java; native host mocked')

