-- Real planner/service/worker adapters; native path and transfer host deliberately fake.
local world=dofile("tests/lua/multi-worker-test.lua")
local f=world.fixture local actor,a,b=world.actor,world.a,world.b
local Work=world.Work
local Registry=require "EmberRoutesProbe/Warehouse/ContainerRegistry"
local Filter=require "EmberRoutesProbe/Warehouse/StorageFilter"
local Ledger=require "EmberRoutesProbe/Settlement/SettlementLedger"
local Store=require "EmberRoutesProbe/Logistics/LogisticsStore"
local Service=require "EmberRoutesProbe/Logistics/LogisticsService"
local Claims=require "EmberRoutesProbe/Work/LaborStore"
local Probe=world.fixture.ctx.Probe
-- actions-test leaves its deliberately displaced diagnostic original for the
-- caller to resolve; return that exact object before starting this world.
local actionHost=world.fixture.ctx
local diagnostic=actionHost.Actions.fixtures
diagnostic.cargo:getContainer():Remove(diagnostic.cargo)
diagnostic.npc.root.items[#diagnostic.npc.root.items+1]=diagnostic.cargo
diagnostic.cargo.container=diagnostic.npc.root
assert(actionHost.Actions.cleanupForHaul(),'diagnostic fixture resolved before logistics')
Probe.runtimeReady=true
Probe.publicDispatch=true
Probe.isPublicDispatch=function() return Probe.publicDispatch==true end
if ERDispatchTestBridge then for key,value in pairs(ERDispatchTestBridge) do EmberRoutesProbeJava[key]=value end end
local Runtime=require 'EmberRoutesProbe/Runtime/TaskRuntime'
local keys={}
world.bridge.acquireBodyControl=function(body,job,generation) assert(not keys[body]) keys[body]=job..':'..generation return keys[body] end
world.bridge.bodyStopMask=function(body,key) return key==keys[body] and (body.actions:isEmpty() and 0 or 4) or -1 end
world.bridge.moveWithControl=function(body,key,player,x,y,z)
    assert(keys[body]==key) body.x,body.y,body.z=x,y,z body.motion='REACHED' return 'MOVE_REQUESTED'
end
world.bridge.stopWithControl=function(body,key) assert(keys[body]==key) body.motion='STOPPED' return true end
world.bridge.releaseBodyControl=function(body,key) assert(keys[body]==key and body.actions:isEmpty()) keys[body]=nil return true end
world.bridge.retireBodyControl=function() return true end
local frozen=false
world.bridge.freezeBodyControl=function() frozen=true return true end
world.bridge.thawBodyControl=function() frozen=false return true end
world.bridge.saveBodyReady=function(_,body) return frozen and not keys[body] and body.actions:isEmpty() end
world.bridge.captureCheckpointFor=function() return 'CHECKPOINT_SAVED' end
world.bridge.armSaveReceipt=function() return true end
world.bridge.verifySaveReceipt=function() return true end
local rawAdd,rawClear=ISTimedActionQueue.add,ISTimedActionQueue.clear
ISTimedActionQueue.queues={}
ISTimedActionQueue.add=function(action)
    local q={queue={action},current=action} ISTimedActionQueue.queues[action.character]=q
    local perform=action.perform
    action.perform=function(self) perform(self) if world.queued[self.character]~=self then q.queue={} q.current=nil end end
    rawAdd(action)
end
ISTimedActionQueue.clear=function(body)
    rawClear(body) local q=ISTimedActionQueue.queues[body] if q then q.queue={} q.current=nil end
end
Probe.controlledExecution=true Runtime.begin()
package.loaded['EmberRoutesProbe/Settlement/Companion']=nil
-- This scene has no craft orders or tools; keep those unrelated providers inert.
package.loaded['EmberRoutesProbe/Crafting/Production']={afterSave=function() end,busy=function() return false end,pause=function() end}
package.loaded['EmberRoutesProbe/Crafting/ProductionRecipe']={}
package.loaded['EmberRoutesProbe/Crafting/CraftSurfaces']={}
package.loaded['EmberRoutesProbe/Crafting/ProductionChain']={}
package.loaded['EmberRoutesProbe/Field/FieldDemand']={advance=function() end}
local Public=require 'EmberRoutesProbe/Work/PublicWork'
local count=0 local function check(value,message) count=count+1 assert(value,message) end
local originalPrint=print print=function() end
function actor:getIndex() return 0 end
world.select(a.id) Work.execute(actor,"clear") world.select(b.id) Work.execute(actor,"clear")
local area={x=0,y=0,w=40,h=10}
actor.x=4.5
local entry=assert(Ledger.commit(actor,nil,"Logistics test",area))
local members=dofile('tests/lua/membership-fixture.lua')(function() return Ledger.get(entry.id) end,{a.id,b.id})
local Save=require('EmberRoutesProbe/Runtime/TaskPersistence')
Save.load() -- World recovery precedes every admitted task.
local function container(x,types,role,private)
    local object=f.object(x) actor.x=x+0.5
    local filter=Filter.new() filter.private=private==true
    for _,id in ipairs(types) do filter.types[id]=true end
    check(Registry.configure(actor,object,filter,object.container)=="FILTER_CONFIGURED","configure real endpoint filter")
    if not private then check(Registry.configureLogistics(actor,object,object.container,role or "STORAGE")=="ROLE_CONFIGURED","configure role independent of filter") end
    return object
end
local input=container(4,{},"INPUT")
local food=container(12,{"food"})
local tools=container(8,{"tool"})
local wrong=container(6,{"tool"})
local correct=container(16,{"food"})
local private=container(10,{"food"},nil,true)
local untagged=f.object(14)
local originals={}
for i=1,3 do originals[i]=f.item("food",input.container) end
local tool=f.item("tool",input.container)
local misplaced=f.item("food",wrong.container)
local keep=f.item("food",correct.container)
local unknown=f.item("unknown",input.container)
local favorite=f.item("food",input.container) favorite.favorite=true
local secret=f.item("food",private.container)
local personal=f.item("food",untagged.container)
function private.container:getItems() error("private inventory must never be read by logistics") end
for _,npc in ipairs({a,b}) do
    npc.x=0.5
    function npc:getMaxWeight() return self.maxWeight or 10 end
    function npc:getInventoryWeight()
        local weight=0 for _,item in ipairs(self.root.items) do weight=weight+item:getUnequippedWeight() end return weight
    end
    function npc.root:getFreeCapacity() return 10-#self.items end
    function npc.root:hasRoomFor(_,item) return self:getFreeCapacity()>=item:getUnequippedWeight() end
end
actor.x=4.5
check(Service.addNearby(actor,entry.id)=="WORKERS_ADDED","one intent adds available settlement workers")
check(#Store.view(entry.id).workers==2,"shared two-worker pool")
check(Service.start(actor,entry.id)=="STARTED","start both modes together")
local sawBatch,sawMultiCargo=false,false
local function tick(n)
    for _=1,n do
        Public.tick() Service.tick()
        for _,npc in ipairs({a,b}) do
            local record=Work.record(npc.id)
            if record and record.producer and #record.items>1 then sawBatch=true end
            local action=world.queued[npc]
            if #npc.root.items>1 then sawMultiCargo=true end
        end
        world.tick(1,true) Runtime.current():step()
    end
end
tick(1200)
for _,item in ipairs(originals) do check(item:getContainer()==food.container,"input originals routed to matching food warehouse") end
check(tool:getContainer()==wrong.container and misplaced:getContainer()==food.container,"mixed input uses nearest matching tool warehouse while misplaced food is removed")
check(sawBatch and sawMultiCargo,"one route loads multiple originals before first delivery: "..tostring(sawBatch)..'/'..tostring(sawMultiCargo))
check(keep:getContainer()==correct.container,"correctly stored original never rebalanced")
check(unknown:getContainer()==input.container and favorite:getContainer()==input.container,"unroutable and protected input retained")
check(secret:getContainer()==private.container and personal:getContainer()==untagged.container,"private and untagged properties untouched")
check(Service.running(entry.id),"empty/no-route scans remain a low frequency running service")
local tidyOnly=f.item("food",wrong.container)
local intakeOnly=f.item("food",input.container)
Store.mode(actor,entry.id,"intake") Service.invalidate(entry.id) tick(1200)
check(tidyOnly:getContainer()==food.container and intakeOnly:getContainer()==input.container,"tidy works independently while input sorting disabled: "..tostring(tidyOnly:getContainer()==food.container)..'/'..tostring(intakeOnly:getContainer()==input.container))
Store.mode(actor,entry.id,"intake") Store.mode(actor,entry.id,"tidy") Service.invalidate(entry.id)
local remainWrong=f.item("food",wrong.container) tick(1200)
check(intakeOnly:getContainer()==food.container and remainWrong:getContainer()==wrong.container,"input sorting works independently while tidy disabled")
Store.mode(actor,entry.id,"tidy") Service.invalidate(entry.id) tick(1200)
check(remainWrong:getContainer()==food.container,"re-enabling tidy wakes shared workers")
food.container.full=true
local alternate=f.item("food",input.container) Service.invalidate() tick(1200)
check(alternate:getContainer()==correct.container,"full preferred target routes new batch to another matching warehouse")
food.container.full=false

-- Manual intervention must stick until explicit settlement restart.
world.select(a.id) members[a.id].context='WAIT' Work.pause("MOVE",a.id)
local later=f.item("food",input.container)
Service.invalidate() tick(1200)
check(not Work.automationAllowed(a.id),"manual move suspends A automatic assignment")
check(later:getContainer()==food.container,"B continues shared work after A manual takeover")

-- Stop/persist/restart preserves the full in-flight batch and original identity.
members[a.id].context='SETTLEMENT' Work.allowAutomation(a.id) Service.start(actor,entry.id)
local cargo={}
for i=1,4 do cargo[i]=f.item("food",input.container) end
Service.invalidate()
local heldNpc
for _=1,200 do
    tick(1)
    for _,npc in ipairs({a,b}) do
        local current=Work.record(npc.id)
        if #npc.root.items>=2 and current and current.reservation then heldNpc=npc break end
    end
    if heldNpc then break end
end
check(heldNpc~=nil,"batch has multiple held originals")
local record=Work.record(heldNpc.id)
check(record.reservation and record.reservation.format==2,"durable capacity manifest contains per-original batch reservation")
local taskId,phase=record.id,record.phase
local blockReason
world.bridge.blockAllCheckpoints=function(reason) blockReason=reason return 'CHECKPOINT_BLOCKED' end
assert(Save.prepare())
for _=1,40 do world.tick(1,false) Runtime.current():step() if Save.ready() then break end end
assert(Save.ready(),'save preparation drains controlled bodies')
local saveResult=require("EmberRoutesProbe/Runtime/Persistence").save()
assert(saveResult and string.find(saveResult,'^CHECKPOINT_SAVED'),tostring(saveResult)..'/'..tostring(blockReason))
check(record.state=="PAUSED" and record.phase==phase and record.id==taskId,"normal save captures paused multi-item phase without creating replacement task: "..tostring(saveResult)..'/'..tostring(record.state)..'/'..tostring(blockReason))
for _=1,1200 do Save.tick(actor) tick(1) if record.state=="RUNNING" then break end end
check(Work.record(heldNpc.id)==record and record.state=="RUNNING","running service resumes exact saved batch after normal in-game save: "..tostring(record.state)..'/'..tostring(record.reason)..'/'..tostring(frozen))
check(Service.stop(actor,entry.id)=="STOPPED","stop all automatic workers at settlement boundary")
for _=1,50 do tick(1) if record.state=='PAUSED' and not Runtime.current():owns(heldNpc.id) then break end end
check(not Service.running(entry.id) and record.state=="PAUSED" and Work.hasCargo(actor,heldNpc.id),"stopped cargo remains owned on same NPC")
tick(20)
check(record.state=="PAUSED","stopped service never restarts itself")
check(Service.start(actor,entry.id)=="STARTED","single settlement restart resumes original automatic work")
tick(1200)
for _,item in ipairs(cargo) do check(item:getContainer()==food.container,"restart delivers every original from prior batch: "..tostring(record.state)..'/'..tostring(record.reason)..'/'..tostring(record.controlUncertain)..'/'..tostring(record.manualPaused)..'/'..tostring(require('EmberRoutesProbe/Runtime/TaskJobs').current():peek(record.id).state)..'/'..tostring(Service.running(entry.id))) end

-- Rule revocation just before a native pickup must prevent the physical effect.
local revoke=f.item("food",input.container) Service.invalidate()
local tag=Registry.metadata(input,input.container)
local originalStart=world.bridge.nativeActionStart
local revoked=false
world.bridge.nativeActionStart=function(...)
    if not revoked and revoke:getContainer()==input.container then tag.logisticsRole='EXCLUDED' revoked=true end
    return originalStart(...)
end
for _=1,1200 do
    Public.tick() Service.tick() world.tick(1,false) Runtime.current():step()
    if revoked then break end
end
check(revoked,"guard-sensitive pickup started")
world.bridge.nativeActionStart=originalStart
tick(20)
check(revoke:getContainer()==input.container,"effect guard rejects source role revocation without requiring UI notification")
Service.stop(actor,entry.id)
-- Planner slices and batch sizing are bounded by physical weight, not NPC count.
tag.logisticsRole="INPUT" Registry.changed(tag.id)
local Planner=require "EmberRoutesProbe/Logistics/LogisticsPlanner"
for i=1,35 do f.item("food",input.container) end
function a.root:getFreeCapacity() return 100-#self.items end
a.maxWeight=2
local plan=assert(Planner.new(entry,Store.get(entry.id),a))
local batch,state
for _=1,10000 do
    local used
    batch,state,used=plan:step(2)
    check(used<=2,"planner globally bounded work slice")
    if state~="WAIT" then break end
end
check(state=="FOUND" and #batch.items==2,"batch respects remaining NPC weight capacity")
a.maxWeight=100
plan=assert(Planner.new(entry,Store.get(entry.id),a))
for _=1,10000 do batch,state=plan:step(64) if state~="WAIT" then break end end
check(state=="FOUND" and #batch.items==30,"route manifest is capped while avoiding per-item travel")
local reused=assert(Planner.new(entry,Store.get(entry.id),a,plan.compiled))
check(reused.phase=="SOURCES" and reused.index==plan.index,"next worker reuses compiled target policy index")
-- User runtime failures: waiting and release must work without a next global.
local savedNext=_G.next _G.next=nil
local emptyPlan=assert(Planner.new(entry,Store.get(entry.id),a))
emptyPlan.stats.accessible=1 emptyPlan.stats.storage=1
check(emptyPlan:waitingReason()=="NO_TARGET_RULES","empty target index uses PZ-supported iteration")
local wasRunning=Service.running(entry.id)
local release=Service.watch(entry.id,function() end)
release() release()
check(Service.running(entry.id)==wasRunning,"repeated unsubscribe does not change logistics state or call absent next")
_G.next=savedNext
-- Public discovery must sleep after an exhausted scan and wake on inventory.
local originalNew,originalClock=Planner.new,getTimestampMs
local publicNow,created,progress=0,0,0
getTimestampMs=function() return publicNow end
Planner.new=function()
    created=created+1
    return {step=function()
        progress=progress+1
        return nil,progress%2==1 and 'WAIT' or 'DONE'
    end}
end
Service.reset()
-- Public discovery runs behind the publicDispatch switch (F-06): the real
-- publicOffer fails closed while the switch is off, so enable it on the
-- exact Boot table LogisticsService required. Set here, at the end of the
-- test, so the earlier private-planner assertions are unaffected.
local Boot=require 'EmberRoutesProbe/Kernel/Boot'
Boot.publicDispatch=true
if not Boot.isPublicDispatch then Boot.isPublicDispatch=function() return Boot.publicDispatch==true end end
local settings=Store.get(entry.id) settings.suspended=false settings.intake=true
Service.publicOffer(actor,entry,a) Service.publicOffer(actor,entry,a)
check(created==1 and progress==2,'in-flight public scan advances without cooldown')
for _=1,10 do publicNow=publicNow+100 Service.publicOffer(actor,entry,a) end
check(created==1,'exhausted public scan is not reconstructed every decision')
for _,listener in ipairs(Registry.inventoryListeners) do listener(Registry.metadata(input,input.container).id) end
Service.publicOffer(actor,entry,a)
check(created==2,'verified inventory event immediately wakes public search')
Service.publicOffer(actor,entry,a)
publicNow=publicNow+2001 Service.publicOffer(actor,entry,a)
check(created==3,'finite retry detects changes outside mod events')
Planner.new,getTimestampMs=originalNew,originalClock
print=originalPrint
print("PASS "..count.." automatic intake/tidy/pool/batch/lifecycle assertions; native host mocked")
