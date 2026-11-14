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
Store.getToken=function(id) return state.tokens[id] end
package.loaded['EmberRoutesProbe/Work/LaborStore']=Store
EmberRoutesProbeJava=ERLaborTestBridge
require('EmberRoutesProbe/Work/LaborJobCommit').install(Store,state,function(r,id)
    r.nextClaimSeq=r.nextClaimSeq+1 return id..':c'..r.nextClaimSeq
end,function(id) state.tokens[id]=nil end)
require('EmberRoutesProbe/Work/LaborDomainAdapters').install(Store,state,
    function(_,job) return job.claimId end,function(id) state.tokens[id]=nil end,function() return true end)
local Haul=require 'EmberRoutesProbe/Hauling/HaulJobs'
local function draft(id,item,producer)
    return {format=3,executor='ENTITY',id=id,npcId=id,source='source',destination='dest',settlementId='world',
        producer=producer or 'LOGISTICS',items={item},plannedCount=1,routeRevision=0,attemptSequence=0,
        state='RUNNING',generation=0,delivered=0,withdrawn=0,
        orderId=producer=='DELIVERY' and 'order' or nil,orderRevision=producer=='DELIVERY' and 1 or nil,
        requesterId=producer=='DELIVERY' and 'player' or nil,itemTypes=producer=='DELIVERY' and {[tostring(item)]='Base.Item'} or nil,
        manifest={{itemId=item,sourceId='source',destinationId='dest',custodyState='UNCOLLECTED',
            deliveryPolicy=producer=='DELIVERY' and 'PLAYER' or 'AUTO_STORAGE'}}}
end
local r=draft('haul',10)
local token=assert(Haul.claim(r))
local seen local unwatch=jobs:watch(function(_,key)
    if key==r.id then local t=state.claims.tokensByTaskId[key] seen=t and t.generation==jobs:peek(key).payload.sequence end
end)
r.generation=r.generation+1 assert(Haul.commit(r) and seen) unwatch()
for _ in pairs(root.obligations.byId) do error('an untouched claim is not a carried obligation') end
r.attemptSequence=1 r.activeAttempt={attemptId='haul:1',itemId=10,kind='TAKE',fromId='source',toId='haul'}
local ops=assert(Haul.preparePickup(r,r.manifest[1]))
assert(Haul.commit(r,nil,ops))
local owed=root.obligations.byId[r.manifest[1].obligationId]
assert(owed and owed.state=='RECONCILE_REQUIRED' and jobs:get(r.id).effects=='UNKNOWN')
r.manifest[1].custodyState='CARRIED' r.activeAttempt=nil
assert(Haul.commit(r,nil,{{action='CONFIRM',id=owed.id,expectedRevision=owed.revision,
    evidence={effects='KNOWN',itemId=10,originalPresent=true}}}))
assert(root.obligations.byId[owed.id].state=='ACTIVE')
assert(not Haul.settle(r,token,r.generation,{{itemId=10,state='DELIVERED'}}),'missing receipt rejected')
assert(Haul.settle(r,token,r.generation,{{itemId=10,state='DELIVERED',receipt={destinationId='dest',attemptId='haul:2'}}}))
assert(root.obligations.byId[owed.id].state=='SETTLED' and not state.claims.owners['item:10'])
assert(Haul.finish(r),'settled haul reaches terminal state')
local delivery=draft('delivery',11,'DELIVERY')
local deliveryToken=assert(Haul.claim(delivery))
delivery.attemptSequence=1 delivery.activeAttempt={attemptId='delivery:1',itemId=11,kind='TAKE',fromId='source',toId='delivery'}
assert(Haul.commit(delivery,nil,assert(Haul.preparePickup(delivery,delivery.manifest[1]))))
local uncertain=root.obligations.byId[delivery.manifest[1].obligationId]
assert(uncertain and uncertain.type=='DELIVERY_RETURN' and uncertain.state=='RECONCILE_REQUIRED')
assert(not Haul.finish(delivery) and state.claims.owners['item:11'],'unknown pickup retains claim and responsibility')
assert(Jobs.check(root),'cold admission accepts the linked unknown attempt without replay')
delivery.activeAttempt=nil
assert(Haul.commit(delivery))
assert(not Haul.settle(delivery,deliveryToken,delivery.generation,{{itemId=11,state='WITHDRAWN'}})
    and state.claims.owners['item:11'],'unsettled pickup cannot withdraw its claim')
local previousId=delivery.manifest[1].obligationId
assert(Haul.observeHeld(delivery,delivery.manifest[1]))
assert(delivery.manifest[1].obligationId==previousId and root.obligations.byId[previousId].state=='ACTIVE',
    'observed held original confirms existing responsibility')
local retry=draft('retry',12)
local retryToken=assert(Haul.claim(retry))
retry.attemptSequence=1 retry.activeAttempt={attemptId='retry:1',itemId=12,kind='TAKE',fromId='source',toId='retry'}
assert(Haul.commit(retry,nil,assert(Haul.preparePickup(retry,retry.manifest[1]))))
local unchanged=root.obligations.byId[retry.manifest[1].obligationId]
retry.activeAttempt=nil
assert(Haul.commit(retry,nil,{{action='SETTLE',id=unchanged.id,expectedRevision=unchanged.revision,
    evidence={kind='UNCHANGED',effects='KNOWN',itemId=12,destinationId='source',attemptId='retry:1',originalPresent=true}}}))
assert(Haul.settle(retry,retryToken,retry.generation,{{itemId=12,state='WITHDRAWN'}})
    and not state.claims.owners['item:12'],'observed unchanged original permits withdrawal')
print('PASS haul and delivery claim/unknown/receipt boundaries through actual Java; native movement/disk NOT RUN')
