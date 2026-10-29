-- Real delivery/haul/claims/Session modules; native inventory/actions/pathing are substitutes.
local f=dofile('tests/lua/multi-worker-test.lua')
local Work,actor,npc=f.Work,f.actor,f.a
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local Ledger=require 'EmberRoutesProbe/SettlementLedger'
local Filter=require 'EmberRoutesProbe/StorageFilter'
local Store=require 'EmberRoutesProbe/LaborStore'
local Runtime=require 'EmberRoutesProbe/TaskRuntime'
local Probe=f.fixture.ctx.Probe
local checks=0
local function check(v,why) checks=checks+1 assert(v,why) end
function actor:getIndex() return 0 end
actor.x=4.5
local entry=assert(Ledger.commit(actor,nil,'Delivery',{x=0,y=0,w=40,h=10}))
local rows=dofile('tests/lua/membership-fixture.lua')(function() return Ledger.get(entry.id) end,{npc.id,f.b.id})
rows[npc.id].factionId=Ledger.data().factionId rows[f.b.id].factionId=Ledger.data().factionId
local source=f.fixture.object(4)
local storageFilter=Filter.new() storageFilter.types.food=true storageFilter.types.tool=true storageFilter.types.heavy=true
assert(Registry.configure(actor,source,storageFilter,source.container,'STORAGE')=='FILTER_CONFIGURED')
local item1=f.fixture.item('food',source.container)
local item2=f.fixture.item('food',source.container)
local playerInventory=f.fixture.ctx.newContainer()
actor.z=0 actor.moving=false
function actor:getInventory() return playerInventory end
function actor:getInventoryWeight() return #playerInventory.items end
function actor:getMaxWeight() return self.capacity or 100 end
function actor:getZ() return self.z end
local playerSquare={}
function playerSquare:getX() return math.floor(actor.x) end
function playerSquare:getY() return 0 end
function playerSquare:getZ() return actor.z end
function actor:getCurrentSquare() return playerSquare end
function actor:isPlayerMoving() return self.moving end
function npc:getMaxWeight() return 100 end
function npc:getInventoryWeight() return #self.root.items end
function npc:setSneaking(v) self.sneaking=v end
function npc:CanSee(z) return z.visible end
local spotted=f.fixture.ctx.list({})
function npc:getSpottedList() return spotted end
local oldInstanceof=instanceof
function instanceof(v,k) if k=='IsoZombie' then return v.zombie==true end return oldInstanceof and oldInstanceof(v,k) or false end
local keys={}
f.bridge.acquireBodyControl=function(body,job,generation) assert(not keys[body]) keys[body]=job..':'..generation return keys[body] end
f.bridge.bodyStopMask=function(body,key) return key==keys[body] and (body.actions:isEmpty() and 0 or 4) or -1 end
f.bridge.moveWithControl=function(body,key,player,x,y,z)
    assert(keys[body]==key) body.x,body.y,body.z=x,y,z body.motion='REACHED' return 'MOVE_REQUESTED'
end
f.bridge.stopWithControl=function(body,key) assert(keys[body]==key) body.motion='STOPPED' return true end
f.bridge.releaseBodyControl=function(body,key) assert(keys[body]==key and body.actions:isEmpty()) keys[body]=nil return true end
f.bridge.retireBodyControl=function() return true end
local rawAdd,rawClear=ISTimedActionQueue.add,ISTimedActionQueue.clear
ISTimedActionQueue.queues={}
ISTimedActionQueue.add=function(action)
    local q={queue={action},current=action} ISTimedActionQueue.queues[action.character]=q
    local perform=action.perform
    action.perform=function(self)
        perform(self)
        if f.queued[self.character]~=self then q.queue={} q.current=nil end
    end
    rawAdd(action)
end
ISTimedActionQueue.clear=function(body)
    rawClear(body) local q=ISTimedActionQueue.queues[body] if q then q.queue={} q.current=nil end
end
Probe.controlledExecution=true Runtime.begin()
local Delivery=require 'EmberRoutesProbe/DeliveryService'
local directory=require('EmberRoutesProbe/TaskDirectory').new()
local recovery=true
local function step(n,effects)
    for _=1,n do
        f.tick(1,effects) Runtime.current():step()
        if recovery then Delivery.advance({actor=actor,now=getTimestampMs(),directory=directory}) end
    end
end
local function offer(o,body)
    local candidates={}
    Delivery.discover({actor=actor,npc=body or npc,npcId=(body or npc).id,entry=entry,candidates=candidates,
        upsertOffer=function(...) return directory:upsert(...) end})
    return candidates[1]
end
local function assign(o)
    local candidate=assert(offer(o),'delivery candidate') local id=Registry.id()
    assert(directory:claim(candidate.key,candidate.revision,npc.id,id))
    check(Delivery.claim(candidate,npc.id,id,{actor=actor})=='QUEUED','delivery requests same controlled runtime')
    return assert(Work.record(npc.id))
end
Work.allowAutomation(npc.id)
local result,id=Delivery.createOrder(actor,entry.id,{{fullType='food',quantity=2}},'request-1')
check(result=='ORDER_CREATED','create stable demand')
local _,same=Delivery.createOrder(actor,entry.id,{{fullType='food',quantity=2}},'request-1')
check(same==id,'request replay returns same order')
check(Delivery.createOrder(actor,entry.id,{{fullType='food',quantity=1}},'request-1')=='REQUEST_CHANGED','request id cannot change quantity')
local o=Delivery.order(id) local r=assign(o)
Runtime.current():stopJob(npc.id,r.id,'REPLACED')
check(Work.resumeFor(actor,npc.id)=='QUEUED','rejected queued grant can recover the already published Job without a stale pending flag')
check(Store.owner(item1:getID()) and Store.owner(item2:getID()),'queued Job already durably claims originals before body grant')
check(not offer(o,f.b),'second NPC cannot claim allocated order')
local conflict={id=Registry.id(),npcId=f.b.id,generation=0,items={item1:getID()},format=1}
check(not Store.claim(conflict),'other work cannot claim same original')
actor.moving=true actor.x=45.5
for _=1,150 do step(1,true) if item1:getContainer()==npc.root and item2:getContainer()==npc.root then break end end
step(20,true)
check(#playerInventory.items==0 and Store.owner(item1:getID()),'moving player never receives cargo or releases its claim')
-- Same XY on another floor must approach that floor, not deliver remotely.
actor.moving=false actor.z=1 npc.z=0
local oldMove=f.bridge.moveWithControl
f.bridge.moveWithControl=function() return 'MOVE_REQUESTED' end
step(20,true)
check(#playerInventory.items==0,'different floor cannot hand off even at matching XY')
f.bridge.moveWithControl=oldMove
-- Interrupt blocked path, retain responsibility and resume a fresh Session.
recovery=false Work.pause('SAVE',npc.id) step(8,false)
check(r.state=='PAUSED' and not Runtime.current():owns(npc.id) and Store.owner(item1:getID()),'save stop retains cargo and original claims')
recovery=true actor.z=0 npc.z=0 actor.capacity=0
step(60,true)
check(#playerInventory.items==0 and item1:getContainer()==npc.root and r.reason=='PLAYER_CAPACITY_WAIT','full player inventory waits with original on courier')
-- Only actual observed zombies affect posture outside the settlement.
local zombie={zombie=true,visible=false,isDead=function() return false end}
spotted[1]=zombie step(8,false)
check(not npc.sneaking,'unseen nearby zombie does not trigger crouch')
zombie.visible=true step(8,false)
check(npc.sneaking,'visible observed zombie outside settlement enables crouch')
zombie.visible=false step(8,false)
check(not npc.sneaking,'loss of sight clears crouch')
actor.capacity=100
for _=1,160 do step(1,true) if o.state=='DONE' then break end end
check(o.state=='DONE' and #playerInventory.items==2 and o.items[1].delivered==2,'same originals delivered and counted exactly once')
step(30,true)
check(o.items[1].delivered==2 and not Store.owner(item1:getID()) and not keys[npc],'completion releases claims/body without replay')
-- Cancellation after pickup must travel back, not teleport cargo into the source.
actor.x=4.5
local cargo=f.fixture.item('tool',source.container)
local _,cancelId=Delivery.createOrder(actor,entry.id,{{fullType='tool',quantity=1}},'cancel')
local cancelOrder=Delivery.order(cancelId) local returned=assign(cancelOrder)
actor.x=45.5 actor.moving=true
for _=1,150 do step(1,true) if cargo:getContainer()==npc.root then break end end
check(Delivery.cancel(actor,cancelId,cancelOrder.revision)=='CANCEL_REQUESTED','existing order cancellation requests safe return')
local beforeX=npc.x step(1,false)
check(cargo:getContainer()==npc.root and Store.owner(cargo:getID()),'cancel does not remotely deposit or discard original')
for _=1,200 do step(1,true) if cancelOrder.state=='CANCELLED' then break end end
check(cancelOrder.state=='CANCELLED' and cargo:getContainer()==source.container and cancelOrder.items[1].delivered==0,'actual return to source settles custody without counting player delivery: '..cancelOrder.state..'/'..returned.state..'/'..tostring(returned.reason)..' source='..tostring(cargo:getContainer()==source.container))
-- Rebuild serializable facts against the same observed physical originals.
actor.x=4.5 actor.moving=false
local savedItem=f.fixture.item('saved',source.container)
storageFilter.types.saved=true
assert(Registry.configure(actor,source,storageFilter,source.container,'STORAGE')=='FILTER_CONFIGURED')
local _,savedId=Delivery.createOrder(actor,entry.id,{{fullType='saved',quantity=1}},'saved')
local savedOrder=Delivery.order(savedId) local savedJob=assign(savedOrder)
actor.x=45.5 actor.moving=true
for _=1,120 do step(1,true) if savedItem:getContainer()==npc.root then break end end
actor.moving=false
for _=1,80 do step(1,false) if f.queued[npc] then break end end
local late=assert(f.queued[npc],'owned PUT queued')
recovery=false Work.pause('SAVE',npc.id) step(8,false)
check(savedJob.state=='PAUSED' and not savedJob.activeAttempt and Store.owner(savedItem:getID()),'stopped unperformed transfer has known pre-effect location and retains original')
local function clone(v)
    if type(v)~='table' then assert(type(v)~='function' and type(v)~='userdata','durable facts only') return v end
    local t={} for k,x in pairs(v) do t[k]=clone(x) end return t
end
local loaded=clone(Registry.data())
Registry.data=function() return loaded end
savedJob=Store.record(npc.id) savedOrder=Delivery.order(savedId)
check(Store.owner(savedItem:getID()) and savedJob.reason=='SAVE','fresh root rebuild restores the same original claim')
late:perform()
check(savedItem:getContainer()==npc.root and #playerInventory.items==2,'old callback cannot operate after world/Session rebuild')
recovery=true
for _=1,160 do step(1,true) if savedOrder.state=='DONE' then break end end
check(savedOrder.state=='DONE' and savedOrder.items[1].delivered==1 and savedItem:getContainer()==playerInventory,'restored responsibility delivers once without reacquiring a replacement')
-- Single item exceeding the worker limit is not silently skipped or reported delivered.
actor.x=4.5 actor.moving=false
local heavy=f.fixture.item('heavy',source.container)
function heavy:getUnequippedWeight() return 101 end
local _,heavyId=Delivery.createOrder(actor,entry.id,{{fullType='heavy',quantity=1}},'heavy')
local heavyOrder=Delivery.order(heavyId)
check(not offer(heavyOrder) and heavyOrder.reason=='NPC_ITEM_OVERWEIGHT' and not Store.owner(heavy:getID()),'unliftable original blocks demand without claiming or fabricating delivery')
check(Delivery.distanceToSettlement(entry,90,5)>50 and Delivery.distanceToSettlement(entry,89,5)==50,'boundary distance uses area edge, inclusive 50 tiles')
assert(Delivery.cancel(actor,heavyId,heavyOrder.revision)=='CANCEL_REQUESTED')
-- A single courier can finish multiple capacity-bounded public segments.
actor.x=4.5 actor.moving=false
local batches={f.fixture.item('batch',source.container),f.fixture.item('batch',source.container),f.fixture.item('batch',source.container)}
storageFilter.types.batch=true
assert(Registry.configure(actor,source,storageFilter,source.container,'STORAGE')=='FILTER_CONFIGURED')
local maxCarry=#npc.root.items+1
function npc:getMaxWeight() return maxCarry end
local _,batchId=Delivery.createOrder(actor,entry.id,{{fullType='batch',quantity=3}},'batch')
local batchOrder=Delivery.order(batchId)
for segment=1,3 do
    local batchJob=assign(batchOrder)
    check(#batchJob.items==1,'public segment respects remaining physical carrying weight')
    actor.x=45.5
    for _=1,200 do step(1,true) if not batchOrder.jobId then break end end
    check(batchOrder.items[1].delivered==segment,'each capacity segment increments actual deliveries once')
    if segment<3 then
        check(batchOrder.state=='WAITING' and npc.x<40 and not batchJob.returnForNextBatch,'empty courier returns to work context before next public claim')
    end
end
check(batchOrder.state=='DONE' and batches[1]:getContainer()==playerInventory and batches[3]:getContainer()==playerInventory,
    'all public batches deliver the original instances')
function npc:getMaxWeight() return 100 end
actor.x=4.5
-- Exceeding the 50-tile boundary discharges only after a reachable storage accepts.
local farItem=f.fixture.item('far',source.container)
storageFilter.types.far=true
assert(Registry.configure(actor,source,storageFilter,source.container,'STORAGE')=='FILTER_CONFIGURED')
local _,farId=Delivery.createOrder(actor,entry.id,{{fullType='far',quantity=1}},'far')
local farOrder=Delivery.order(farId) local farJob=assign(farOrder)
actor.x=45.5 actor.moving=true
for _=1,100 do step(1,true) if farItem:getContainer()==npc.root then break end end
source.container.full=true actor.x=90
step(30,true)
check(farJob.returning and farItem:getContainer()==npc.root and Store.owner(farItem:getID()),'boundary abort with no storage capacity retains original and claim')
source.container.full=false
for _=1,180 do step(1,true) if farOrder.state=='CANCELLED' then break end end
check(farOrder.state=='CANCELLED' and farItem:getContainer()==source.container and farOrder.items[1].delivered==0,
    'return capacity wake finishes same obligation without false player delivery')
-- Neither endpoint contains the original: UNKNOWN cannot be replayed or released.
actor.x=4.5 actor.moving=false
local unknown=f.fixture.item('unknown',source.container)
storageFilter.types.unknown=true
assert(Registry.configure(actor,source,storageFilter,source.container,'STORAGE')=='FILTER_CONFIGURED')
local _,unknownId=Delivery.createOrder(actor,entry.id,{{fullType='unknown',quantity=1}},'unknown')
local unknownOrder=Delivery.order(unknownId) local unknownJob=assign(unknownOrder)
actor.x=45.5 actor.moving=true
for _=1,120 do step(1,true) if unknown:getContainer()==npc.root then break end end
actor.moving=false
for _=1,80 do step(1,false) if f.queued[npc] then break end end
local uncertainAction=assert(f.queued[npc])
local external=f.fixture.ctx.newContainer()
npc.root:Remove(unknown) external.items[#external.items+1]=unknown unknown.container=external
Work.pause('USER',npc.id) step(10,false)
check(unknownJob.controlUncertain and unknownJob.activeAttempt and Store.owner(unknown:getID()),'unknown effect persists attempt and claim after physical stop')
uncertainAction:perform() step(20,true)
check(unknown:getContainer()==external and unknownOrder.items[1].delivered==0 and not Runtime.current():owns(npc.id),
    'unknown transfer and late callback are never retried or counted')
print('PASS '..checks..' delivery public/claims/Session/capacity/movement/return assertions; native host mocked')
