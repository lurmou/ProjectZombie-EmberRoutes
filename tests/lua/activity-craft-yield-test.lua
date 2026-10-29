-- Reuse the established native-craft substitute, not a second item/recipe model.
local f=dofile('tests/lua/craft-probe-test.lua')
local Yield=require 'EmberRoutesProbe/ProductionYield'
local Production=require 'EmberRoutesProbe/Production'
local checks=0
local function check(v,label) assert(v,label) checks=checks+1 end
f.Probe.controlledExecution=false
f.Probe.activityContext=nil
local _,saw=f.fresh(3)
local logs={}
for i=0,f.materials.container:getItems():size()-1 do
    local item=f.materials.container:getItems():get(i)
    if item:getFullType()=='Base.Log' then logs[#logs+1]=item end
end
local function invite(id) return {eventId='gathering',settlementId=f.entry.id} end
check(f.Craft.execute(f.actor,'run',nil,f.npc.id,true,{recipeId=f.recipe.key,quantity=9,
    orderId='demand',chain=true,nonPreemptive=true})=='STARTED','public batch starts')
for _=1,1500 do f.tick(true) if f.nativeCalls()>=1 then break end end
check(f.nativeCalls()==1,'one actual native craft before yield intent')
f.Probe.activityContext=invite
for _=1,1500 do f.tick(true) if not f.Work.busy(f.npc.id) then break end end
local r=f.Craft.record(f.npc.id)
check(r.released and r.state=='CANCELLED' and r.reason=='ACTIVITY_YIELD','execution settles through original return-only protocol')
check(r.delivered==3 and f.nativeCalls()==1,'finished unit delivered without starting another')
check(saw.container==f.tools.container and not f.Store.owner(saw.id),'original saw returned and claim released')
local untouched=0 for _,log in ipairs(logs) do if log.container==f.materials.container then untouched=untouched+1 end end
check(untouched==2,'unused original logs remain in storage')
local demand={id='demand',jobId=r.id,state='RUNNING',settlementId=f.entry.id,recipeId=f.recipe.key,
    product=r.product,quantity=9,target=9}
local patch=assert(Yield.settle(demand,r))
check(patch.state=='WAITING' and patch.progress.delivered==3,'partial execution retains original demand')
demand.craftProgress=patch.progress demand.jobId=nil demand.state=patch.state
check(demand.quantity==9 and Yield.remaining(demand)==6,'request identity and original quantity remain immutable')
check(not Yield.settle(demand,r),'detached old job cannot settle twice')
f.Probe.activityContext=nil
check(f.Craft.execute(f.actor,'run',nil,f.npc.id,true,{recipeId=f.recipe.key,quantity=Yield.remaining(demand),
    orderId='demand',chain=true,nonPreemptive=true})=='STARTED','same demand starts only remaining quantity')
local nextRecord=f.Craft.record(f.npc.id) demand.jobId=nextRecord.id
for _=1,2500 do f.tick(true) if not f.Work.busy(f.npc.id) then break end end
patch=assert(Yield.settle(demand,nextRecord))
check(patch.state=='DONE' and patch.progress.delivered==9 and f.nativeCalls()==3,'three originals make nine planks with no repeated first unit')
local fake={id='intermediate',orderId='demand',settlementId=f.entry.id,released=true,state='CANCELLED',
    recipeId='MakePart',product='Part',delivered=30,target=30,
    chain={index=1,nodes={{},{}},goal={recipeId=f.recipe.key,product=r.product}},
    activityYield={format=1,eventId='gathering',recipeId=f.recipe.key,product=r.product}}
local intermediate={id='demand',jobId='intermediate',state='RUNNING',settlementId=f.entry.id,
    recipeId=f.recipe.key,product=r.product,quantity=9,target=9}
patch=assert(Yield.settle(intermediate,fake))
check(patch.progress.delivered==0 and patch.state=='WAITING','BOM intermediates never fulfill the final demand')
fake.uncertain=true check(not Yield.settle(intermediate,fake),'unknown returned assets cannot release demand') fake.uncertain=nil
fake.released=false check(not Yield.settle(intermediate,fake),'paused assets cannot release demand') fake.released=true
fake.activityYield.cancelled=true
check(Yield.settle(intermediate,fake).state=='CANCELLED','explicit cancellation cannot resurrect the demand')
fake.activityYield.cancelled=nil intermediate.state='CANCELLED'
check(Yield.settle(intermediate,fake).state=='CANCELLED','cancelled public demand stays cancelled')
-- A saved mid-return intent must not resume native production, even after the party ends.
f.Probe.activityContext=nil
f.fresh(3)
assert(f.Craft.execute(f.actor,'run',nil,f.npc.id,true,{recipeId=f.recipe.key,quantity=9,orderId='saved',chain=true,nonPreemptive=true})=='STARTED')
for _=1,1500 do f.tick(true) if f.nativeCalls()>=1 then break end end
f.Probe.activityContext=invite f.tick(false)
r=f.Craft.record(f.npc.id)
check(r.activityYield~=nil and not r.released,'yield intent persists before all returns finish')
Production.pause('SAVE',f.npc.id)
f.Probe.activityContext=nil
local resumed=Production.execute(f.actor,'resume',nil,f.npc.id,{nonPreemptive=true})
check(resumed=='RETURN_STARTED','resume of a committed yield is return-only')
for _=1,1800 do f.tick(true) if not f.Work.busy(f.npc.id) then break end end
check(r.released and f.nativeCalls()==1,'saved cleanup cannot craft extra units after context disappears')
local root=f.registry.data()
root.publicWork={format=1,sequence=1,orders={saved={id='saved',requestId='request-saved',settlementId=f.entry.id,
    recipeId=f.recipe.key,product=r.chain.goal.product,name='Saved demand',quantity=9,target=9,
    sequence=1,revision=1,state='RUNNING',jobId=r.id,npcId=f.npc.id}},priorities={},rules={},requests={}}
local Public=require 'EmberRoutesProbe/PublicWork'
Public.prepareRecovery()
Public.provider('crafting').reconcile()
local persisted=assert(Public.order('saved'))
check(persisted.state=='WAITING' and not persisted.jobId and persisted.craftProgress.delivered==3,
    'real public provider retains the same demand and detaches only the settled execution')
Public.provider('crafting').reconcile()
check(Public.order('saved').craftProgress.delivered==3,'repeated provider reconciliation cannot credit twice')
persisted.craftProgress.delivered=999
check(Public.order('saved').craftProgress.delivered==3,'UI projection cannot mutate continuation progress')
check(Public.order('saved').quantity==9 and Yield.remaining(Public.order('saved'))==6,'real provider preserves original request quantity')
-- Manual work keeps its original Job and resumes only the remaining goal.
f.Probe.activityContext=nil f.fresh(3)
assert(f.Craft.execute(f.actor,'run',nil,f.npc.id,true,{recipeId=f.recipe.key,quantity=9,chain=true,nonPreemptive=true})=='STARTED')
for _=1,1500 do f.tick(true) if f.nativeCalls()==1 then break end end
local manualId=f.Craft.record(f.npc.id).id
local Resume=require 'EmberRoutesProbe/TaskResume'
local m=require('EmberRoutesProbe/MembershipService').view(f.npc.id)
f.Probe.activityContext=function() return {eventId='manual-party',settlementId=f.entry.id,
    commandEpoch=Resume.epoch(f.npc.id),membershipRevision=m.revision} end
for _=1,1500 do f.tick(true) if not f.Work.busy(f.npc.id) then break end end
local manual=f.Craft.record(f.npc.id)
check(manual.id==manualId and not manual.released and Yield.assetFree(manual),'manual goal stays in the same asset-free suspended Job')
check(manual.activityContinuation.delivered==3 and manual.requested==6 and f.nativeCalls()==1,'manual continuation credits only the completed first unit')
check(Production.status(manual).delivered==3 and Production.status(manual).requested==9,'manual UI retains original goal and delivered progress')
local envelope=require('EmberRoutesProbe/TaskJobs').current():peek(manualId)
check(envelope.state=='SUSPENDED' and not envelope.obligations.business,'asset-free intent is not an outstanding original-item obligation')
Production.tickPending()
check(Yield.assetFree(manual) and f.nativeCalls()==1,'active gathering prevents automatic work resume')
f.Probe.activityContext=nil
for _=1,2500 do Production.tickPending() f.tick(true) if manual.released then break end end
check(manual.id==manualId and manual.released and manual.state=='DONE' and f.nativeCalls()==3,
    'original manual Job resumes exactly the remaining two units: '..tostring(manual.state)..'/'..tostring(manual.reason)..' calls='..tostring(f.nativeCalls()))
check(Production.status(manual).delivered==9,'manual original-goal progress is not lost or counted twice')
print('activity-craft-yield: '..checks..' PASS (native craft/inventory substitutes; no game run)')
