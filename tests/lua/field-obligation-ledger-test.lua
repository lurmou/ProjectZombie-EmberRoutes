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
package.loaded['TimedActions/ISInventoryTransferAction']=true
package.loaded['TimedActions/ISGrabItemAction']=true
local Cargo=require 'EmberRoutesProbe/Field/FieldCargo'
local job={id='field',npcId='worker',providerType='FIELD_WORK',scopeId='world',revision=1,
    state='PREPARING',effects='KNOWN',obligations={work=true},payload={format=1,category='lumberjack',
    offerKey='tree',target={kind='TREE',identity='tree',x=0,y=0,z=0},
    phase='WORK',sequence=0,claims={},assets={}}}
assert(Store.createClaimedJob(job))
job=jobs:get(job.id) local token=assert(Store.claimField(job))
local c={job=job}
function c.change(edit,capacity,ops)
    local proposed=jobs:get(c.job.id) edit(proposed)
    local ok,value,evidence=Store.replaceField(c.job,token,proposed,capacity,ops)
    if ok then c.job=value else print("field commit failed "..tostring(value).." / "..tostring(evidence)) end return ok,value
end
local item={getFullType=function() return 'Base.Log' end}
assert(Cargo.outputs(c,{}, {[101]=item},false))
local asset=c.job.payload.assets[1]
local debt=root.obligations.byId[asset.obligationId]
assert(debt and debt.state=='ACTIVE' and debt.data.itemId==101 and state.claims.owners['item:101'])
assert(Jobs.check(root),'cold admission preserves field output responsibility')
local seen local unwatch=jobs:watch(function(_,key)
    if key==job.id then local t=state.claims.tokensByTaskId[key] seen=t and t.generation==jobs:peek(key).payload.sequence end
end)
assert(c.change(function(j) j.payload.sequence=1 end) and seen) unwatch()
local beforeRevision=c.job.revision local original=jobs.update
jobs.update=function() return false,'INJECTED_REJECT' end
local rejected=jobs:get(job.id).payload rejected.sequence=2
assert(not Store.mutateJob(job.id,beforeRevision,rejected,{}) and token.generation==1
    and jobs:get(job.id).payload.sequence==1,'CAS rejection restores prior generation')
jobs.update=original
local bad=jobs:get(job.id) bad.payload.assets[1].custody='DELIVERED' bad.payload.claims={}
assert(not Store.replaceField(c.job,token,bad),'claim cannot be removed before settlement')
local missing={{action='SETTLE',id=debt.id,expectedRevision=debt.revision,
    evidence={effects='KNOWN',itemId=101,destinationId='stock',attemptId='field:1'}}}
assert(not Store.replaceField(c.job,token,bad,nil,missing),'physical return evidence required')
local proof={{action='SETTLE',id=debt.id,expectedRevision=debt.revision,
    evidence={effects='KNOWN',itemId=101,destinationId='stock',attemptId='field:1',originalPresent=true}}}
assert(Store.replaceField(c.job,token,bad,nil,proof))
assert(root.obligations.byId[debt.id].state=='SETTLED' and not state.claims.owners['item:101'])
print('PASS field output obligation, claim, cold admission and settlement via actual Java; native host mocked')



