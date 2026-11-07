-- Directed main-chain host: real PublicWork/DeliveryService/DeliveryTarget/DeliveryFlow.
-- Native motion, physical transfers and disk are substitutes, never in-game evidence.
dofile('tests/lua/public-work-test.lua')
local Public=require 'EmberRoutesProbe/Work/PublicWork'
local Registry=require 'EmberRoutesProbe/Warehouse/ContainerRegistry'
local Ledger=require 'EmberRoutesProbe/Settlement/SettlementLedger'
local Members=require 'EmberRoutesProbe/Settlement/MembershipService'
local Work=require 'EmberRoutesProbe/Work/Work'
local Business=require 'EmberRoutesProbe/Work/BusinessJobs'
local actor=getSpecificPlayer(0)
local now=100000
function getTimestampMs() return now end
local n=0
local function check(v,m) n=n+1 assert(v,m) end
local root={}
Registry.data=function() return root end
Public.prepareRecovery()
local entry={id='s',factionId='f'}
Ledger.view=function() return entry end
Ledger.get=function() return entry end
Ledger.data=function() return {factionId='f'} end
Members.character=function() return 'owner' end
Members.view=function() return {settlementId='s',factionId='f'} end
local function container()
    local c={items={},capacity=100}
    function c:getItems()
        return {size=function() return #c.items end,get=function(_,i) return c.items[i+1] end,
            contains=function(_,item) for _,v in ipairs(c.items) do if v==item then return true end end return false end}
    end
    function c:hasRoomFor(_,item) return not self.full and #self.items+item:getUnequippedWeight()<=self.capacity end
    function c:getFreeCapacity() return self.full and 0 or self.capacity-#self.items end
    return c
end
local boxes={}
for _,id in ipairs({'S','D','D2'}) do boxes[id]={id=id,container=container(),role=id=='S' and 'INPUT' or 'STORAGE',object={}} end
Registry.resolve=function(id) return boxes[id] end
Registry.revalidate=function(e) return e and boxes[e.id]==e and e end
Registry.describe=function(id) if boxes[id] then return {x=1,y=1,z=0} end end
Registry.logistics=function(e) return e.role end
Registry.accepts=function(e) return not e.reject end
package.loaded['EmberRoutesProbe/Settlement/SettlementMembership']={query=function() return {'S','D','D2'} end}
local own=container()
local npc={getInventory=function() return own end,getMaxWeight=function() return 100 end}
local serial=0
local function item(kind,c)
    serial=serial+1 local value={id=serial,fullType=kind,container=c}
    function value:getID() return self.id end
    function value:getFullType() return self.fullType end
    function value:getUnequippedWeight() return 1 end
    function value:getContainer() return self.container end
    c.items[#c.items+1]=value return value
end
local goods={item('Base.Plank',boxes.S.container),item('Base.Plank',boxes.S.container)}
local producers={freeCarry=function() return 100 end,eligible=function() return true end,register=function() end}
package.loaded['EmberRoutesProbe/Work/LaborProducers']=producers
local store=require 'EmberRoutesProbe/Work/LaborStore'
store.owner=function() end
store.availableFor=function(_,_,_,free) return free end
local Delivery=require 'EmberRoutesProbe/Logistics/DeliveryService'
local function create(token,destination,quantity)
    return Delivery.createOrder(actor,'s',{{fullType='Base.Plank',quantity=quantity or 2,sourceId='S'}},token,destination)
end
local result,id=create('intent','D')
check(result=='ORDER_CREATED','explicit INPUT to STORAGE order accepted')
local _,same=create('intent','D') check(same==id,'same content and destination is the same intent')
local _,changed=create('intent','D2') check(changed~=id,'changing destination creates a new intent')
Delivery.order(changed).cancelled=true Delivery.order(changed).state='CANCELLED'
check(create('invalid','missing')=='DESTINATION_UNREGISTERED','invalid explicit destination never falls back to player')
boxes.D.reject=true
check(create('filter-submit','D')=='DESTINATION_FILTER_REJECTED','submit rejects actual source item against target filter')
boxes.D.reject=false boxes.D.container.full=true
check(create('full-submit','D')=='DESTINATION_FULL','submit validates real target capacity')
boxes.D.container.full=false
local o=Delivery.order(id)
local function offer()
    local candidates={}
    Delivery.discover({actor=actor,npc=npc,npcId='alice',entry=entry,candidates=candidates,
        upsertOffer=function() return {} end})
    return candidates[1]
end
boxes.D.reject=true check(not offer() and o.reason=='DESTINATION_FILTER_REJECTED','batch rechecks filter without claims')
boxes.D.reject=false
local candidate=assert(offer())
check(candidate.intent.destination=='D' and #candidate.intent.items==2 and candidate.intent.source=='S','batch contains exact INPUT originals and chosen destination')
local _,storage=Delivery.createOrder(actor,'s',{{fullType='Base.Plank',quantity=1,sourceId='S'}},'storage-source','D')
-- Check explicit STORAGE on the same registered source, independently of INPUT selection.
boxes.S.role='STORAGE'
local resultStorage,storageId=Delivery.createOrder(actor,'s',{{fullType='Base.Plank',quantity=1,sourceId='S'}},'storage-source-two','D')
check(resultStorage=='ORDER_CREATED','explicit STORAGE source remains supported')
Delivery.order(storage).state='CANCELLED' Delivery.order(storage).cancelled=true
Delivery.order(storageId).state='CANCELLED' Delivery.order(storageId).cancelled=true
boxes.S.role='INPUT'
check(Delivery.createOrder(actor,'s',{{fullType='Base.Plank',quantity=1,sourceId='missing'}},'missing-source','D')=='SOURCE_UNAVAILABLE',
    'unregistered source is rejected without expanding to another box')
local job={id='job',orderId=id,npcId='alice',requesterId='owner',settlementId='s',scopeId='local-world',
    producer='DELIVERY',manifest={{itemId=goods[1].id,sourceId='S',custodyState='UNCOLLECTED'},
        {itemId=goods[2].id,sourceId='S',custodyState='UNCOLLECTED'}},
    itemTypes={[tostring(goods[1].id)]='Base.Plank',[tostring(goods[2].id)]='Base.Plank'}}
local assigned
Work.allowAutomation=function() end
Work.assign=function(_,_,intent) assigned=intent return 'QUEUED' end
check(Delivery.claim(candidate,'alice','job',{actor=actor})=='QUEUED' and assigned.destination=='D','existing claim path carries destination through to Work')
local _,general=Delivery.createOrder(actor,'s',{{fullType='Base.Plank',quantity=1}},'general-input','D')
check(not offer() and Delivery.order(general).reason=='STOCK_OR_CAPACITY_WAIT','ordinary scan never expands into INPUT')
Delivery.order(general).cancelled=true Delivery.order(general).state='CANCELLED'
local moves=0
package.loaded['EmberRoutesProbe/Work/WorkTransfer']={reachable=function() return true end,move=function()
    moves=moves+1 return {start=function() return 'FAILED','PATH_BLOCKED' end,poll=function() return 'FAILED','PATH_BLOCKED' end}
end}
package.loaded['EmberRoutesProbe/Warehouse/InventoryView']={scan=function(containers)
    return {step=function() return containers end}
end,find=function(containers,id)
    for index,c in ipairs(containers) do for _,v in ipairs(c.items) do if v.id==id then return v,index end end end
    return nil,nil,'ITEM_MISSING'
end}
package.loaded['EmberRoutesProbe/Hauling/HaulRouting']={}
local Target=require 'EmberRoutesProbe/Logistics/DeliveryTarget'
local Flow=require 'EmberRoutesProbe/Logistics/DeliveryFlow'
local c={job=job,npc=npc,actor=actor,token={},generation=1,body={stop=function() return true end,
    snapshot=function() return {available=true,nativeStopped=true} end}}
local puts=0
local function transfer(_,line,value,endpoint,kind)
    local from=value.container local to=kind=='TAKE' and own or endpoint.container
    for i,v in ipairs(from.items) do if v==value then table.remove(from.items,i) break end end
    to.items[#to.items+1]=value value.container=to
    if kind=='TAKE' then line.custodyState='CARRIED'
    else line.custodyState='DELIVERED' line.deliveryReceipt={destinationId=endpoint.id,attemptId='put-'..line.itemId} puts=puts+1 end
    return {kind=kind}
end
local function nextLine() return Flow.next(c,transfer,function() job.deliveryOnly=true end) end
local first=nextLine()
check(first.kind=='TAKE' and goods[1].container==own and goods[2].container==boxes.S.container,'explicit INPUT TAKE moves only selected original')
check(Delivery.projectDelivery(o,job)[1]==0,'carried goods are not delivery receipts')
boxes.D.reject=true
local step,why=nextLine()
check(not step and why=='DESTINATION_FILTER_REJECTED' and goods[1].container==own and goods[2].container==boxes.S.container,'PUT filter HOLD retains carried and untouched originals')
boxes.D.reject=false boxes.D.container.full=true
step,why=nextLine() check(not step and why=='DESTINATION_FULL' and puts==0,'full box HOLD produces no receipt')
boxes.D.container.full=false
local destination=boxes.D boxes.D=nil
step,why=nextLine() check(not step and why=='DESTINATION_UNREGISTERED' and puts==0,'removed destination HOLD never reroutes')
boxes.D=destination
nextLine() -- remaining TAKE, same order
check(goods[2].container==own,'restored destination resumes same order and pending original')
local Transfer=require 'EmberRoutesProbe/Work/WorkTransfer'
Transfer.reachable=function() return false end
local move=nextLine()
check(move and move.start()=='FAILED' and Target.failureReason(c,goods[1])=='DESTINATION_UNREACHABLE'
    and goods[1].container==own and puts==0,'unreachable named destination maps to frozen HOLD reason without transfer')
Transfer.reachable=function() return true end
nextLine() nextLine() -- real Flow PUT leaves, substituted physical transfer
check(puts==2 and goods[1].container==boxes.D.container and Delivery.projectDelivery(o,job)[1]==2,'only destination receipts credit box order')
job.manifest[1].custodyState='CARRIED'
check(Delivery.projectDelivery(o,job)[1]==1,'carried line cannot count even if it contains a stale receipt')
job.manifest[1].custodyState='DELIVERED'
job.manifest[1].deliveryReceipt.destinationId='player:owner'
check(Delivery.projectDelivery(o,job)[1]==1,'box order ignores player receipt')
job.manifest[1].deliveryReceipt.destinationId='D'
-- Verify legacy target and receipt contract separately from box PUT.
local _,legacy=create('legacy',nil,1)
local legacyOrder=Delivery.order(legacy)
local ownPlayer=container() function actor:getInventory() return ownPlayer end
job.orderId=legacy job.id='legacy-job' legacyOrder.jobId=job.id legacyOrder.npcId='alice'
check(Target.endpoint(c).id=='player:owner','absent destination retains player endpoint')
check(Delivery.projectDelivery(legacyOrder,job)[1]==0,'legacy delivery ignores box receipt')
job.manifest[1].deliveryReceipt.destinationId='player:owner'
check(Delivery.projectDelivery(legacyOrder,job)[1]==1,'legacy player receipt still credits exactly once')
legacyOrder.cancelled=true legacyOrder.state='CANCELLED'
-- Cancel mid-carry through real cancel + Flow + recovery; no auto return.
job.orderId=id job.id='job'
o.jobId='job' o.npcId='alice'
job.manifest[1].custodyState='CARRIED' job.manifest[1].deliveryReceipt=nil
job.manifest[2].custodyState='UNCOLLECTED' job.manifest[2].deliveryReceipt=nil
goods[1].container=own own.items={goods[1]} goods[2].container=boxes.S.container boxes.S.container.items={goods[2]} boxes.D.container.items={}
local pauses,resumes=0,0
Work.pause=function(reason,id) check(reason=='USER' and id=='alice','cancel stops existing body owner') pauses=pauses+1 end
Work.resumeFor=function() resumes=resumes+1 end
Business.record=function() return job end
job.state='PAUSED' job.reason='DESTINATION_FULL'
check(Delivery.cancel(actor,id,o.revision)=='CANCEL_REQUESTED' and pauses==1,'cancel makes demand terminal immediately')
step,why=nextLine()
check(not step and why=='CANCEL_REQUESTED' and goods[1].container==own and goods[2].container==boxes.S.container and not job.returning,
    'cancelled carried goods stay NPC, unpicked stay source, no return branch')
now=now+2000 Delivery.advance({actor=actor,now=now})
check(resumes==0 and not offer(),'cancelled demand is never redispatched or automatically resumed')
-- Existing first-created suppression, both creation orders; no unverifiable merge.
root={}; Registry.data=function() return root end Public.prepareRecovery()
local _,publicId=Public.create(actor,'s','saw',2,nil,'overlap-public-first')
local public=root.publicWork.orders[publicId] public.policyId='stock' public.jobId='craft' public.npcId='bob'
local craft={outputs={{id=91,fullType='Base.Plank',destination='D'}}}
Business.record=function() return craft end
local _,later=create('delivery-later','D',1)
local laterOrder=Delivery.order(later)
check(Public.deliveryOverlapReason(laterOrder,laterOrder.items[1])=='CYCLE_ACTIVE','verifiable earlier stock demand suppresses box delivery')
check(not offer() and laterOrder.reason=='CYCLE_ACTIVE' and laterOrder.items[1].reason=='CYCLE_ACTIVE','suppressed delivery is visible and never picked')
craft.outputs[1].destination=nil
check(not Public.deliveryOverlapReason(laterOrder,laterOrder.items[1]),'unknown public destination is not merged with every delivery')
craft.outputs[1].destination='D2'
check(not Public.deliveryOverlapReason(laterOrder,laterOrder.items[1]),'different box is a different overlap key')
public.state='CANCELLED' laterOrder.state='CANCELLED' laterOrder.cancelled=true
local _,earlier=create('delivery-first','D',1)
local _,laterPublic=Public.create(actor,'s','saw',2,nil,'overlap-public-later')
local laterDemand=root.publicWork.orders[laterPublic] laterDemand.policyId='stock' laterDemand.jobId='craft2' laterDemand.npcId='bob'
craft.outputs[1].destination='D'
check(Public.overlapReason(laterPublic)=='MANUAL_ORDER_ACTIVE','earlier delivery suppresses later stock demand at same verified box')
check(Public.outputOverlapReason(laterPublic,'Base.Plank','D')=='MANUAL_ORDER_ACTIVE'
    and not Public.outputOverlapReason(laterPublic,'Base.Plank','D2'),
    'existing production output boundary blocks only the verified matching destination')
check(Public.order(laterPublic).reason=='MANUAL_ORDER_ACTIVE','suppression surfaces in detached Order state')
Delivery.order(earlier).state='CANCELLED' Delivery.order(earlier).cancelled=true
check(not Public.overlapReason(laterPublic),'cancelled first demand releases suppression without touching originals')
print('PASS '..n..' box-to-box directed host checks; native motion/transfer/UI/disk NOT RUN')
