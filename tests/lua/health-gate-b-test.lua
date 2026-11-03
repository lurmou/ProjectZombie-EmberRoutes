-- Reuse the repository's public-work host and its complete domain substitutes.
-- Native movement, transfer, renderer and disk are NOT exercised here.
dofile('tests/lua/public-work-test.lua')
local Public=require 'EmberRoutesProbe/PublicWork'
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local root={}
Registry.data=function() return root end
Public.prepareRecovery() -- A new test world clears the prior fixture's deliberate dispatch fault.
local actor=getSpecificPlayer(0)
local metadata={}
function actor:getModData() return metadata end
local checks=0
local function check(v,m) checks=checks+1 assert(v,m) end
local Draft=require 'EmberRoutesProbe/PublicOrderDraft'
local d=Draft.update(actor,'s','saw',5,nil,{})
local token=d.requestId
local result,id=Public.create(actor,'s','saw',5,nil,'gate-b-first')
check(result=='ORDER_CREATED','existing authority creates an order')
-- The existing fixture wraps request labels; exercise the real receipt with its saved label.
local again,same=Public.create(actor,'s','saw',5,nil,'gate-b-first')
check(again=='ORDER_CREATED' and same==id,'same receipt never creates a second order')
Draft.result(actor,'s',token,'ORDER_CREATED')
check(Draft.update(actor,'s','saw',5,nil,{}).requestId==token,'refresh preserves the intent token')
package.loaded['EmberRoutesProbe/PublicOrderDraft']=nil
Draft=require 'EmberRoutesProbe/PublicOrderDraft'
check(Draft.read(actor,'s').result=='ORDER_CREATED' and Draft.update(actor,'s','saw',5,nil,{}).requestId==token,
    'reopening/reloading UI module restores submitted result and unchanged intent')
local changed=Draft.update(actor,'s','saw',6,nil,{})
check(changed.requestId~=token and not changed.result,'actual quantity change creates a new intent')
local back=Draft.update(actor,'s','saw',5,nil,{})
check(back.requestId~=token and back.requestId~=changed.requestId,'A-B-A is a new intent, not a content deduplication index')
local pref=Draft.update(actor,'s','saw',5,nil,{['Base.Log']='alternate'})
check(pref.requestId~=back.requestId,'precursor preference change is content')
Draft.update(actor,'other','saw',1,nil,{})
check(Draft.read(actor,'s').requestId==pref.requestId,'switching settlements preserves each current draft')
-- First-created LIVE Order wins across manual/policy only. Rule configuration
-- without a deficit/cycle is not an active demand and does not reserve stock.
local _,later=Public.create(actor,'s','saw',5,nil,'gate-b-later')
check(later~=id and not Public.overlapReason(later),'independent manual intents remain separate orders')
root.publicWork.orders[id].policyId='s:Base.Plank'
check(Public.overlapReason(later)=='CYCLE_ACTIVE' and not Public.overlapReason(id),'earlier live policy suppresses later manual order')
root.publicWork.orders[id].state='CANCELLED'
check(not Public.overlapReason(later),'cancelled policy no longer suppresses live demand')
local _,policy=Public.create(actor,'s','saw',5,nil,'gate-b-policy')
root.publicWork.orders[policy].policyId='s:Base.Plank'
check(Public.overlapReason(policy)=='MANUAL_ORDER_ACTIVE','earlier live manual suppresses later policy')
root.publicWork.orders[later].state='DONE'
check(not Public.overlapReason(policy),'completed demand stops suppressing the retained later demand')
-- Unsupported public format: real loader rejects; no graceful fallback assumed.
local invalid={publicWork={format=99,orders={},priorities={}}}
Registry.data=function() return invalid end
local before=invalid.publicWork
local ok,why=pcall(Public.prepareRecovery)
check(not ok and tostring(why):find('PUBLIC_WORK_FORMAT_INVALID',1,true) and invalid.publicWork==before,
    'unsupported public format refuses without replacing original root')
-- The real cancel entry uses the existing Work stop API and keeps Job identity.
root={deliveryOrders={format=1,orders={cargo={id='cargo',format=1,revision=1,
    settlementId='s',requesterId='owner',state='ASSIGNED',jobId='held-job',npcId='alice',
    items={{fullType='Base.Plank',quantity=2,delivered=0}}}}}}
Registry.data=function() return root end
local members=require 'EmberRoutesProbe/MembershipService'
members.character=function() return 'owner' end
local work=require 'EmberRoutesProbe/Work'
local pauses,resumes=0,0
work.pause=function(reason,npcId) check(reason=='USER' and npcId=='alice','cancel routes to the existing owner stop') pauses=pauses+1 end
work.resumeFor=function() resumes=resumes+1 end
local business=require 'EmberRoutesProbe/BusinessJobs'
local manifest={{itemId=1,custodyState='CARRIED'},{itemId=2,custodyState='UNCOLLECTED'}}
local retained={id='held-job',producer='DELIVERY',state='PAUSED',reason='LOAD_RECOVERY',manifest=manifest}
business.record=function() return retained end
local Delivery=require 'EmberRoutesProbe/DeliveryService'
check(Delivery.cancel(actor,'cargo',0)=='ORDER_CHANGED' and pauses==0,'stale cancellation cannot stop a worker')
check(Delivery.cancel(actor,'cargo',1)=='CANCEL_REQUESTED' and pauses==1,'accepted cancel requests owner stop exactly once')
local o=Delivery.order('cargo')
check(o.cancelled and o.state=='CANCELLED' and o.jobId=='held-job','cancel preserves persistent responsibility')
Delivery.advance({actor=actor,now=100000})
check(resumes==0 and retained.manifest==manifest and manifest[1].custodyState=='CARRIED'
    and manifest[2].custodyState=='UNCOLLECTED','cancel never settles cargo or automatically resumes retained job')
local function copy(t) if type(t)~='table' then return t end local r={} for k,v in pairs(t) do r[k]=copy(v) end return r end
root=copy(root) -- A host serialization stand-in, not disk save evidence.
package.loaded['EmberRoutesProbe/DeliveryService']=nil
Delivery=require 'EmberRoutesProbe/DeliveryService'
check(Delivery.order('cargo').cancelled and Delivery.order('cargo').jobId=='held-job','cancel and owner link survive supported record reload')
Delivery.advance({actor=actor,now=200000})
local candidates={}
Delivery.discover({actor=actor,entry={id='s'},candidates=candidates})
check(resumes==0 and #candidates==0,'cancelled demand is neither auto-resumed nor rediscovered after reload')
root={deliveryOrders={format=99,orders={}}}
local original=root.deliveryOrders
local loaded,reason=pcall(Delivery.data)
check(not loaded and tostring(reason):find('DELIVERY_FORMAT_UNSUPPORTED',1,true) and root.deliveryOrders==original,
    'unsupported delivery format rejects and preserves the original table')
print('PASS '..checks..' Gate B intent/overlap/cancel/format host checks; native UI, originals and disk NOT RUN')
