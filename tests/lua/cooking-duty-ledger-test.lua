-- Production Duty -> Context -> Labor adapters -> actual Java kernel/JobStore.
assert(ERLaborTestBridge,'actual Java labor kernel required')
local Ledger=require 'EmberRoutesProbe/Kernel/ObligationLedger'
local Jobs=require 'EmberRoutesProbe/Kernel/JobStore'
local Claims=require 'EmberRoutesProbe/Kernel/LaborClaims'
local Record=require 'EmberRoutesProbe/Cooking/CookingRecord'
local root={}
ModData={getOrCreate=function() return root end}
EmberRoutesProbeJava=ERLaborTestBridge
local Registry=require 'EmberRoutesProbe/Warehouse/ContainerRegistry'
assert(Registry.data()==root and root.format==2)
root.nextClaimSeq=0 -- LaborStore's work template normally initializes this.
local jobs=assert(Jobs.open(root))
local state={root=root,claims=Claims.new(),tokens={},cookingTokens={},personalTokens={},activityTokens={},fieldTokens={}}
local Store={data=function() return root end}
Store.getToken=function(id) return state.cookingTokens[id] or state.tokens[id] end
package.loaded['EmberRoutesProbe/Runtime/TaskJobs']={current=function() return jobs end}
package.loaded['EmberRoutesProbe/Work/LaborStore']=Store
package.loaded['EmberRoutesProbe/Cooking/CookingDirectives']={kitchen=function() return true end}
package.loaded['EmberRoutesProbe/Cooking/CookingFacilities']={stove=function() return {siteKey='cooking:oven',active=false,powered=true,broken=false} end}
package.loaded['EmberRoutesProbe/Cooking/CookingInventory']={snapshot=function() return {} end}
local npc={}
EmberRoutesProbeJava.carrierId=function() return 'chef' end
EmberRoutesProbeJava.carrierPresent=function() return true end
require('EmberRoutesProbe/Work/LaborJobCommit').install(Store,state,function(r,id)
    r.nextClaimSeq=r.nextClaimSeq+1 return id..':c'..r.nextClaimSeq
end,function(id) state.tokens[id]=nil state.cookingTokens[id]=nil end)
require('EmberRoutesProbe/Work/LaborDomainAdapters').install(Store,state,
    function(_,job) return job.claimId end,function() end,function() return true end)
local job=assert(Record.new('cook','chef','world','profile','AUTO','source',1,1))
assert(Store.createClaimedJob(job))
local c={job=jobs:get(job.id),token=state.cookingTokens[job.id],npc=npc,
    body={current=function() return true end},valid=function() return true end}
local square={getX=function() return 1 end,getY=function() return 2 end,getZ=function() return 0 end}
local endpoint={id='oven',object={getSquare=function() return square end}}
local Duty=require 'EmberRoutesProbe/Cooking/CookingDuty'
assert(Duty.reserve(c,endpoint),'reserve publishes duty')
local id=c.job.payload.duty.id
assert(root.obligations.byId[id] and root.obligations.byId[id].state=='ACTIVE'
    and not c.job.obligations.furnace and state.claims.owners['cooking:oven'],'independent duty and claim exist')
local observedGeneration
local unwatch=jobs:watch(function(_,jobId)
    if jobId==job.id then
        local current=jobs:peek(jobId)
        observedGeneration=state.cookingTokens[jobId].generation==current.payload.sequence
    end
end)
local started=assert(Record.begin(c.job,'TOGGLE',{}))
assert(require('EmberRoutesProbe/Cooking/CookingContext').publish(c,started) and observedGeneration,
    'observer sees current claim generation when attempt begins')
unwatch()
local aborted=assert(Record.abort(c.job,c.job.payload.attempt.id))
assert(require('EmberRoutesProbe/Cooking/CookingContext').publish(c,aborted))
assert(Duty.release(c,endpoint),'inactive empty stove releases')
assert(root.obligations.byId[id].state=='SETTLED' and not state.claims.owners['cooking:oven']
    and not c.job.payload.duty,'settlement evidence and release published together')
assert(Duty.reserve(c,endpoint),'same Job may reserve again after settled duty')
local second=c.job.payload.duty.id
assert(second~=id and root.obligations.byId[id].state=='SETTLED'
    and root.obligations.byId[second].state=='ACTIVE','new duty has distinct identity without overwriting prior evidence')
assert(Duty.release(c,endpoint) and root.obligations.byId[second].state=='SETTLED')
print('PASS cooking duty production ledger path; native stove and disk NOT RUN')
