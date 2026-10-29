local f=dofile('tests/lua/craft-probe-test.lua')
local Runtime=require 'EmberRoutesProbe/TaskRuntime'
local Production=require 'EmberRoutesProbe/Production'
local checks=0
local function check(value,message) checks=checks+1 assert(value,message) end
local key,grants
grants=0
local bridge=EmberRoutesProbeJava
bridge.acquireBodyControl=function(npc,job,generation)
    assert(not key) grants=grants+1 key=job..':'..generation return key
end
bridge.bodyStopMask=function(npc,k) return k==key and (npc.actions:isEmpty() and 0 or 4) or -1 end
bridge.stopWithControl=function(npc,k) assert(k==key) return true end
bridge.releaseBodyControl=function(npc,k) assert(k==key and npc.actions:isEmpty()) key=nil return true end
bridge.retireBodyControl=function() return true end
bridge.freezeBodyControl=function() return true end
bridge.thawBodyControl=function() return key==nil end
bridge.controlledCarrier=function() return f.npc end
bridge.motionResult=function() return f.npc.motion or 'STOPPED' end
bridge.moveWithControl=function(npc,k,actor,x,y,z)
    assert(k==key and npc.actions:isEmpty()) npc.x=x npc.motion='REACHED' return 'MOVE_REQUESTED'
end
bridge.stopCarrier=function() error('managed production used legacy stop') end
f.Probe.cancelAll=function() error('managed production directly preempted another business') end
local rawAdd,rawClear=ISTimedActionQueue.add,ISTimedActionQueue.clear
ISTimedActionQueue.queues={}
ISTimedActionQueue.add=function(action)
    local q={queue={action},current=action}
    ISTimedActionQueue.queues[action.character]=q
    local perform,stop=action.perform,action.stop
    action.perform=function(self)
        perform(self)
        if q.current==self and not f.queued() then q.queue={} q.current=nil end
    end
    action.stop=function(self)
        stop(self)
        if q.current==self and not f.queued() then q.queue={} end -- Simulate vanilla stale `current`.
    end
    rawAdd(action)
end
ISTimedActionQueue.clear=function(npc)
    rawClear(npc)
    local q=ISTimedActionQueue.queues[npc]
    if q then q.queue={} end
end
local function fresh()
    local macro=package.loaded['EmberRoutesProbe/MembershipService'].view(f.npc.id)
    macro.context='SETTLEMENT' macro.leaderId=nil
    f.Probe.controlledExecution=false
    Runtime.reset()
    local log,saw=f.fresh(1)
    key=nil ISTimedActionQueue.queues={}
    Runtime.begin() f.Probe.controlledExecution=true
    return log,saw
end
local function run()
    return f.Craft.execute(f.actor,'run',nil,f.npc.id,true,{recipeId=f.recipe.key,quantity=3})
end
local lastCraft
local function tick(effects)
    f.tick(false)
    Runtime.current():step()
    if effects and f.queued() then
        if f.queued().craftRecipe then lastCraft=f.queued() end
        f.queued():perform()
    end
end
local function pump()
    for _=1,2000 do tick(true) if not Runtime.current():owns(f.npc.id) then return end end
    error('controlled production did not drain')
end
local log,saw=fresh()
check(run()=='QUEUED' and f.nativeCalls()==0 and not f.Store.owner(log.id),'request does not claim or move originals')
check(f.Work.busy(f.npc.id),'pending body is visible to worker admission')
tick(false) tick(false)
local r=f.Craft.record(f.npc.id)
check(r and r.state=='RUNNING' and grants>0,'grant creates original production record')
local jobId=r.id
pump()
r=f.Craft.record(f.npc.id)
check(r.id==jobId and r.state=='DONE' and r.released and f.nativeCalls()==1,'normal completion drains without replay')
check(saw.container==f.tools.container and not f.Store.owner(saw.id) and key==nil,'real tool returned before terminal body release')
local count=0 for _,asset in ipairs(r.outputs) do if asset.delivered then count=count+1 end end
check(count==#r.outputs and r.delivered==r.target,'only verified original outputs count as delivered')
log,saw=fresh()
check(run()=='QUEUED','second controlled production accepted')
for _=1,300 do tick(false) if f.queued() then break end end
local old=f.queued() check(old~=nil,'transfer reached native queue')
old:perform()
check(log.container==f.npc.root or saw.container==f.npc.root,'fixture has physically collected cargo')
f.Work.pause('USER',f.npc.id)
check(key~=nil,'pause request does not release body immediately')
for _=1,20 do tick(false) if not Runtime.current():owns(f.npc.id) then break end end
r=f.Craft.record(f.npc.id) jobId=r.id
check(r.state=='PAUSED' and not r.released and key==nil and f.nativeCalls()==0,'stop confirms body while retaining unfinished originals')
check(f.Store.owner(log.id) and f.Store.owner(saw.id),'session close does not release asset claims')
check(f.Craft.execute(f.actor,'resume',nil,f.npc.id,true)=='QUEUED','resume is another admission request')
pump()
check(f.Craft.record(f.npc.id).id==jobId and f.nativeCalls()==1,'resume preserves job ID and produces once')
old:perform() old:stop()
check(f.nativeCalls()==1 and f.Craft.record(f.npc.id).state=='DONE','late transfer callback cannot alter closed job')
log,saw=fresh()
check(run()=='QUEUED','pending-cancel fixture accepted')
f.Work.pause('USER',f.npc.id)
for _=1,4 do tick(false) end
check(not Runtime.current():owns(f.npc.id) and not f.Craft.record(f.npc.id) and not f.Store.owner(log.id),
    'cancel before grant leaves no task or phantom resource claims')
log,saw=fresh()
check(run()=='QUEUED','commit-error fixture accepted')
for _=1,300 do tick(false) if f.queued() and f.queued().craftRecipe then break end if f.queued() then f.queued():perform() end end
local craft=f.queued() check(craft and craft.craftRecipe,'craft reached native commit boundary')
-- This fixture injects an exception after consuming an original.
f.setMode('consume_error') craft:perform()
for _=1,30 do tick(false) if not Runtime.current():owns(f.npc.id) then break end end
r=f.Craft.record(f.npc.id)
check(r.uncertain and not r.released and f.nativeCalls()==1 and key==nil,'unknown commit is retained while safe body closes')
local result=f.Craft.execute(f.actor,'resume',nil,f.npc.id,true)
check(result~='QUEUED' and f.nativeCalls()==1,'unknown commit is never automatically repeated')
local Companion=require 'EmberRoutesProbe/Companion'
log,saw=fresh()
check(run()=='QUEUED','handoff fixture accepted')
for _=1,300 do
    tick(false)
    if f.queued() and f.queued().craftRecipe then break end
    if f.queued() then f.queued():perform() end
end
check(f.queued() and f.queued().craftRecipe,'handoff interrupts actual queued saw action before commit')
jobId=f.Craft.record(f.npc.id).id
local member=package.loaded['EmberRoutesProbe/MembershipService'].view(f.npc.id)
member.context='FOLLOW' member.leaderId='fixture-leader'
check(Companion.startFor(f.actor,f.npc.id,member.revision),'authorized follow adapter submits against current production owner')
for _=1,25 do tick(false) end
check(f.Craft.record(f.npc.id).state=='PAUSED' and Companion.exportState(f.npc.id).mode=='FOLLOW',
    'confirmed production stop grants body to actual companion adapter')
check(f.Store.owner(log.id) and f.Store.owner(saw.id) and f.nativeCalls()==0,'follow preserves paused production originals and never crafts')
local Service=require 'EmberRoutesProbe/CraftingService'
local snapshot=Service.status(f.actor,f.entry.id)
local worker
for _,row in ipairs(snapshot.workers) do if row.id==f.npc.id then worker=row break end end
check(worker and worker.busy and not worker.orderBusy and worker.order.resumable,'following worker exposes paused production independently of body ownership')
local Monitor=require 'EmberRoutesProbe/OrderMonitorService'
local monitored=Monitor.status(f.actor,f.entry.id).rows[1]
check(monitored and monitored.jobId==jobId and monitored.bodyMode=='FOLLOW' and monitored.canResume,
    'actual monitor projects retained saw Job and current follow independently')
check(Monitor.command(f.actor,f.entry.id,monitored.id,monitored.generation,'resume')=='QUEUED',
    'monitor bridge resumes hand recipe through panel service without a nonexistent surface while following')
pump()
check(f.Craft.record(f.npc.id).id==jobId and f.Craft.record(f.npc.id).state=='DONE' and f.nativeCalls()==1,
    'follow-to-production handoff completes the same job once')
check(Companion.exportState(f.npc.id).mode=='HOLD' and key==nil,'old companion cannot keep moving after production resumes')
log,saw=fresh()
f.npc.maxWeight=6 log.weight=9 saw.weight=0.7
check(run()=='QUEUED','overweight order enters controlled planning')
pump()
r=f.Craft.record(f.npc.id)
check(r.state=='CANCELLED' and r.released and r.reason=='CAPACITY_UNAVAILABLE','uncollected overweight order releases after confirmed stop')
check(log.container==f.materials.container and saw.container==f.tools.container and not f.Store.owner(log.id) and key==nil,
    'uncollected originals remain in warehouse without phantom claims')
f.npc.maxWeight=8
check(run()=='QUEUED','same NPC can accept another order after safe rejection')
pump()
check(f.Craft.record(f.npc.id).state=='DONE','new order completes after capacity corrected')
log,saw=fresh() f.npc.maxWeight=6 log.weight=9 saw.weight=0.7
local preflight=require('EmberRoutesProbe/ProductionChain').new(f.actor,f.npc,f.entry,f.recipe.key,3,nil,'offer:test',false)
local result,blocked
for _=1,2000 do result,blocked=preflight:step() if result or blocked then break end end
check(not result and blocked=='CAPACITY_UNAVAILABLE' and not f.Craft.record(f.npc.id)
    and not f.Store.owner(log.id),'public overweight discovery retains demand without allocating Job or originals')
check(f.Craft.execute(f.actor,'run',nil,f.npc.id,true,{recipeId=f.recipe.key,quantity=3,orderId='public-demand'})=='QUEUED',
    'late public capacity failure fixture admitted')
pump() r=f.Craft.record(f.npc.id) local publicJob=r.id
check(r.state=='PAUSED' and not r.released and r.orderId=='public-demand' and r.reason=='CAPACITY_UNAVAILABLE' and key==nil,
    'late capacity failure pauses exact public Job instead of cancelling its demand')
f.npc.maxWeight=8
check(f.Craft.execute(f.actor,'resume',nil,f.npc.id,true)=='QUEUED','capacity-corrected public Job remains resumable')
pump() r=f.Craft.record(f.npc.id)
check(r.id==publicJob and r.state=='DONE' and r.orderId=='public-demand','corrected capacity completes same public Job once')
log,saw=fresh()
f.npc.maxWeight=8 log.weight=9 saw.weight=0.7
check(run()=='QUEUED','carried capacity-drop fixture accepted')
for _=1,1000 do tick(true) if log.container==f.npc.root then break end end
check(log.container==f.npc.root,'original log physically collected before capacity drop')
f.npc.maxWeight=6
pump()
r=f.Craft.record(f.npc.id)
check(r.state=='PAUSED' and not r.released and f.Store.owner(log.id) and f.nativeCalls()==0,
    'capacity drop retains actual carried original and never releases or crafts it')
f.npc.maxWeight=nil
log,saw=fresh()
check(run()=='QUEUED','partial delivery cancellation fixture accepted')
local delivered
for _=1,1500 do
    tick(true)
    r=f.Craft.record(f.npc.id)
    for _,asset in ipairs(r and r.outputs or {}) do if asset.delivered then delivered=asset break end end
    if delivered then break end
end
check(delivered~=nil,'first output is confirmed delivered before pause')
local original
for _,endpoint in ipairs({f.products,f.materials,f.tools}) do
    for _,value in ipairs(endpoint.container.items) do if value.id==delivered.id then original=value break end end
end
check(original~=nil,'delivered original exists in warehouse')
original:getContainer():Remove(original) -- A later consumer takes the already credited product.
f.Work.pause('USER',f.npc.id)
for _=1,30 do tick(false) if not Runtime.current():owns(f.npc.id) then break end end
check(f.Craft.execute(f.actor,'return',nil,f.npc.id,true)=='QUEUED','cancel accepts partially delivered order')
pump()
r=f.Craft.record(f.npc.id)
check(r.state=='CANCELLED' and r.released and saw.container==f.tools.container,
    'cancel skips credited output while returning all remaining originals')
check(require('EmberRoutesProbe/BusinessJobs').retire(r.id) and not f.Craft.record(f.npc.id),
    'actual cancellation retires after original tool and remaining outputs are returned')
log,saw=fresh()
check(run()=='QUEUED','missing original fixture accepted')
for _=1,1000 do tick(true) if log.container==f.npc.root then break end end
f.Work.pause('USER',f.npc.id)
for _=1,30 do tick(false) if not Runtime.current():owns(f.npc.id) then break end end
log:getContainer():Remove(log)
local substitute=f.item(log.kind) f.materials.container:AddItem(substitute)
check(f.Craft.execute(f.actor,'return',nil,f.npc.id,true)=='QUEUED','missing-original cancellation enters reconciliation')
pump()
r=f.Craft.record(f.npc.id)
check(r.reason=='ITEM_MISSING' and not r.released and f.Store.owner(log.id) and substitute.container==f.materials.container,
    'genuine missing original retains claim and never substitutes same-type item')
check(not require('EmberRoutesProbe/BusinessJobs').retire(r.id) and f.registry.data().taskJobs.byId[r.id],
    'failed cancellation remains visible for original reconciliation')
log,saw=fresh()
f.Probe.runtimeReady=true
member.context='SETTLEMENT' member.leaderId=nil
local Public=require 'EmberRoutesProbe/PublicWork'
check(Public.setPriority(f.actor,f.entry.id,f.npc.id,'crafting',1)=='PRIORITY_SAVED','minimal per-NPC craft priority saved')
check(Public.setPriority(f.actor,f.entry.id,f.npc.id,'hauling',0)=='PRIORITY_SAVED','hauling may be independently disabled')
local publicRequest=Public.requestId()
local accepted,orderId=Public.create(f.actor,f.entry.id,f.recipe.key,3,nil,publicRequest)
check(accepted=='ORDER_CREATED' and orderId and not f.Craft.record(f.npc.id),'public request has no executor and causes no immediate production')
local duplicate,duplicateId=Public.create(f.actor,f.entry.id,f.recipe.key,3,nil,publicRequest)
check(duplicate=='ORDER_CREATED' and duplicateId==orderId and #Public.orders(f.entry.id)==1,'repeated request is idempotent')
for _=1,2000 do
    tick(true) Public.tick()
    if Public.orders(f.entry.id)[1].state=='DONE' then break end
end
r=f.Craft.record(f.npc.id)
check(r and r.orderId==orderId and r.state=='DONE' and f.nativeCalls()==1,'public claim completes one actual controlled saw Job')
check(f.registry.data().taskJobs.byId[r.id].payload==r and not f.registry.data().craftProbes and not f.registry.data().labor,
    'new Job payload is the single persistent business record; old roots are absent')
local firstJob=r.id
local retiredCallback=lastCraft
for _=1,30 do tick(true) if not Runtime.current():owns(f.npc.id) then break end end
check(Public.retireSettled(8)==1 and not f.registry.data().taskJobs.byId[firstJob]
    and not f.Craft.record(f.npc.id) and #Public.orders(f.entry.id)==0,'closed public Order and Job disappear together after body release')
retiredCallback:perform() retiredCallback:stop()
check(not f.registry.data().taskJobs.byId[firstJob] and f.nativeCalls()==1,
    'late native craft completion and stop do not recreate retired Job or repeat effect')
duplicate,duplicateId=Public.create(f.actor,f.entry.id,f.recipe.key,3,nil,publicRequest)
check(duplicate=='ORDER_CREATED' and duplicateId==orderId and #Public.orders(f.entry.id)==0,
    'completed request receipt acknowledges retry without recreating work')
f.materials.container:AddItem(f.item(log.kind))
local _,nextOrder=Public.create(f.actor,f.entry.id,f.recipe.key,3,nil,Public.requestId())
for _=1,2000 do
    tick(true) Public.tick()
    local rows=Public.orders(f.entry.id)
    if rows[1] and rows[1].state=='DONE' then break end
end
check(#Public.orders(f.entry.id)==1 and Public.orders(f.entry.id)[1].id==nextOrder,
    'only successor remains in the work list')
local history=require('EmberRoutesProbe/BusinessJobs').records('CRAFT')
local current=f.Craft.record(f.npc.id)
check(current and current.orderId==nextOrder and current.state=='DONE' and not history[firstJob] and f.nativeCalls()==2,
    'successor completes once without retaining predecessor history')
for _=1,30 do tick(true) if not Runtime.current():owns(f.npc.id) then break end end
require('EmberRoutesProbe/TaskRetirement').install()
f.Probe.tickRetirement()
check(#Public.orders(f.entry.id)==0 and not f.registry.data().taskJobs.byId[current.id],
    'normal background retirement hook clears successor after settlement')
print('PASS '..checks..' controlled production checks; native effects mocked')
