-- Original bug through real business/claims modules; native bodies/actions remain fake.
local f=dofile('tests/lua/multi-worker-test.lua')
local Work,actor,npc=f.Work,f.actor,f.a
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local Filter=require 'EmberRoutesProbe/StorageFilter'
local Ledger=require 'EmberRoutesProbe/SettlementLedger'
local Service=require 'EmberRoutesProbe/LogisticsService'
local Store=require 'EmberRoutesProbe/LaborStore'
local Probe=f.fixture.ctx.Probe
function actor:getIndex() return 0 end
local checks=0
local function check(v,why) checks=checks+1 assert(v,why) end
actor.x=4.5
local entry=assert(Ledger.commit(actor,nil,'Routing',{x=0,y=0,w=40,h=10}))
dofile('tests/lua/membership-fixture.lua')(function() return Ledger.get(entry.id) end,{npc.id,f.b.id})
Probe.publicDispatch=true
local function box(x,types,role)
    local o=f.fixture.object(x) actor.x=x+0.5
    local config=Filter.new() for _,id in ipairs(types) do config.types[id]=true end
    assert(Registry.configure(actor,o,config,o.container,role or 'STORAGE')=='FILTER_CONFIGURED')
    return o
end
local source=box(4,{},'INPUT')
local fridge=box(10,{'food','tool'})
local food=box(12,{'food'}) local tools=box(14,{'tool'})
local a=f.fixture.item('food',source.container)
local b=f.fixture.item('food',source.container)
local c=f.fixture.item('tool',source.container)
function npc:getMaxWeight() return 100 end
function npc:getInventoryWeight() return #self.root.items end
Service.preparePublic(actor,entry)
Work.allowAutomation(npc.id)
check(Work.assign(actor,npc.id,{producer='LOGISTICS',settlementId=entry.id,sourceMode='INTAKE',
    source=Registry.metadata(source,source.container).id,destination=Registry.metadata(fridge,fridge.container).id,
    items={a:getID(),b:getID(),c:getID()}})=='STARTED','start autonomous original batch')
local r=Work.record(npc.id) local id=r.id
local beforeClear=require('EmberRoutesProbe/TaskJobs').current():get(r.id)
check(not Store.clear(npc.id) and Store.owner(a:getID()) and require('EmberRoutesProbe/TaskJobs').current():get(r.id).revision==beforeClear.revision,
    'clear retains uncollected responsibility and persistent revision')
local first
for _=1,300 do
    f.tick(1,true)
    if r.delivered==1 then first=true break end
end
check(first and r.format==3 and #r.items==3,'first delivery keeps full original plan')
actor.x=10.5 Registry.configure(actor,fridge,Filter.new(),fridge.container,'STORAGE')
for _=1,500 do Service.tick() f.tick(1,true) if r.state=='DONE' then break end end
check(r.state=='DONE' and r.id==id and r.delivered==3,'rejecting fridge reroutes remaining held originals on same Job')
check(a:getContainer()==fridge.container and b:getContainer()==food.container and c:getContainer()==tools.container,
    'already delivered stays; remaining mixed cargo splits by current policy')
check(#r.items==3 and not Store.owner(a:getID()) and not Store.owner(b:getID()) and not Store.owner(c:getID()),
    'denominator stable and each delivered original claim released')
-- A capacity-bearing token can shrink, reacquire its exact reduced set, then become empty.
local claims=require('EmberRoutesProbe/LaborClaims').new()
local t=assert(claims:acquire('shrink',1,{'item:101','item:102'}))
assert(claims:reserve(t,'box',101,1,10)) assert(claims:reserve(t,'box',102,1,10))
check(claims:shrink(t,{'item:101'}) and #t.resources==1 and claims:available('box',10)==9,'shrink preserves remaining capacity')
t=assert(claims:acquire('shrink',2,{'item:102'}))
check(claims:shrink(t,{'item:102'}) and #t.resources==0 and not t.capacityKey,'empty token has no capacity or original owner')
-- No target pauses the body; creating a suitable target wakes the same responsibility.
local d=f.fixture.item('unknown-type',source.container)
local any=Filter.new() any.types['unknown-type']=true
Registry.configure(actor,fridge,any,fridge.container,'STORAGE')
check(Work.assign(actor,npc.id,{producer='LOGISTICS',settlementId=entry.id,sourceMode='INTAKE',
    source=Registry.metadata(source,source.container).id,destination=Registry.metadata(fridge,fridge.container).id,
    items={d:getID()}})=='STARTED','second independent batch')
r=Work.record(npc.id)
check(Store.owner(d:getID())~=nil,'new Job claims its original before pickup old='..id..' new='..r.id..' item='..tostring(r.items[1])..' d='..tostring(d:getID())..' line='..r.manifest[1].custodyState)
for _=1,100 do f.tick(1,true) if d:getContainer()==npc.root then break end end
check(Store.owner(d:getID())~=nil,'pickup retains original claim')
actor.x=10.5 Registry.configure(actor,fridge,Filter.new(),fridge.container,'STORAGE')
for _=1,200 do Service.tick() f.tick(1,true) if r.reason=='ROUTING_WAIT' then break end end
check(r.state=='PAUSED' and not Work.busy(npc.id) and Store.owner(d:getID()),'no target retains cargo but releases active execution: '..r.state..'/'..r.reason..' busy='..tostring(Work.busy(npc.id))..' held='..tostring(d:getContainer()==npc.root)..' line='..r.manifest[1].custodyState..' claims='..tostring(Store.hasTaskClaims(r.id))..' id='..tostring(d:getID()))
local later=box(18,{'unknown-type'})
for _=1,300 do Service.tick() f.tick(1,true) if r.state=='DONE' then break end end
check(r.state=='DONE' and d:getContainer()==later.container,'new registered target wakes route wait without manual resume')
-- Exercise the same adapter with real Session arbitration and independent queue evidence.
local Runtime=require 'EmberRoutesProbe/TaskRuntime'
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
local function controlled(n,effects)
    for _=1,n do f.tick(1,effects) Runtime.current():step() Service.tick() end
end
local e=f.fixture.item('food',source.container) local g=f.fixture.item('food',source.container)
check(Work.assign(actor,npc.id,{producer='LOGISTICS',settlementId=entry.id,sourceMode='INTAKE',
    source=Registry.metadata(source,source.container).id,destination=Registry.metadata(food,food.container).id,
    items={e:getID(),g:getID()}})=='QUEUED','autonomous haul requests a controlled Session')
r=Work.record(npc.id)
for _=1,100 do controlled(1,true) r=Work.record(npc.id) if r.items[1]==e:getID() and r.delivered==1 then break end end
Work.pause('USER',npc.id)
for _=1,25 do controlled(1,false) if not Runtime.current():owns(npc.id) then break end end
check(r.state=='PAUSED' and r.manualPaused and not keys[npc] and Store.owner(g:getID()) and not Store.owner(e:getID()),
    'partial delivery then controlled pause retains exactly remaining claim and releases body')
controlled(70,false)
check(r.state=='PAUSED' and not Runtime.current():owns(npc.id),'USER pause is never auto-resumed by routing wake')
check(Work.taskCommand(actor,npc.id,r.id,r.generation,'resume')=='QUEUED','explicit resume grants fresh Session after claim shrink')
for _=1,200 do controlled(1,true) if r.state=='DONE' and not Runtime.current():owns(npc.id) then break end end
check(r.state=='DONE' and r.delivered==2 and not keys[npc] and not Store.owner(g:getID()),'controlled completion clears final claim/body without empty reacquire')
-- A current valid format=1 Job upgrades in place from observed IDs, never by quantity.
local legacyHeld=f.fixture.item('tool',npc.root)
local legacyDone=f.fixture.item('food',food.container)
local legacyUntaken=f.fixture.item('tool',source.container)
local legacy={id=Registry.id(),npcId=npc.id,format=1,kind='EXPLICIT_TRANSFER',scopeId='local-world',executor='ENTITY',
    producer='LOGISTICS',settlementId=entry.id,sourceMode='INTAKE',source=Registry.metadata(source,source.container).id,
    destination=Registry.metadata(food,food.container).id,items={legacyDone:getID(),legacyHeld:getID(),legacyUntaken:getID()},
    state='PAUSED',reason='FILTER_REJECTED item='..legacyHeld:getID(),phase='DELIVER',delivered=1}
assert(Store.claim(legacy)) assert(Store.publish(legacy))
check(Work.resumeFor(actor,npc.id)=='QUEUED' and legacy.format==2,'current paused format1 upgrades same Job with complete original evidence')
for _=1,200 do controlled(1,true) if legacy.state=='DONE' and not Runtime.current():owns(npc.id) then break end end
check(legacy.delivered==2 and legacy.withdrawn==1 and legacyHeld:getContainer()==tools.container
    and legacyDone:getContainer()==food.container and legacyUntaken:getContainer()==source.container,
    'upgrade preserves previous delivery, reroutes held original and withdraws untaken original')
-- Revoke access with a PUT already queued. The old snapshot cannot write/clear its successor.
local spare=box(22,{'food'})
local moving=f.fixture.item('food',source.container)
Work.allowAutomation(npc.id)
check(Work.assign(actor,npc.id,{producer='LOGISTICS',settlementId=entry.id,sourceMode='INTAKE',
    source=Registry.metadata(source,source.container).id,destination=Registry.metadata(food,food.container).id,
    items={moving:getID()}})=='QUEUED','controlled revocation batch queued')
local oldPut
for _=1,100 do
    controlled(1,false)
    local action=f.queued[npc]
    if action then
        if action.from==npc.root then oldPut=action break else action:perform() end
    end
end
check(oldPut~=nil,'PUT reaches native queue before policy changes')
local denied=Filter.new() denied.private=true actor.x=12.5
Registry.configure(actor,food,denied,food.container,'STORAGE')
local readFood=food.container.getItems
food.container.getItems=function() error('private target must not be inspected even by stop recovery') end
oldPut:perform()
controlled(20,false)
r=Work.record(npc.id)
check(not r.controlUncertain and moving:getContainer()==npc.root,'revoked queued PUT remains known from held original without private inventory read')
for _=1,200 do
    controlled(1,true)
    if r.state=='DONE' and not Runtime.current():owns(npc.id) then break end
end
check(r.state=='DONE' and moving:getContainer()==spare.container,'private old target reroutes through a fresh controlled Session')
oldPut:stop() oldPut:perform()
check(moving:getContainer()==spare.container and not Store.owner(moving:getID()),'late revoked callback neither replays original nor changes completed claim')
food.container.getItems=readFood
-- Rebuild the world-local ledger from a paused, partially settled manifest.
local reloadHeld=f.fixture.item('tool',npc.root)
local reloadDone=f.fixture.item('tool',tools.container)
local saved={id=Registry.id(),npcId=npc.id,format=2,kind='EXPLICIT_TRANSFER',scopeId='local-world',executor='ENTITY',
    producer='LOGISTICS',settlementId=entry.id,sourceMode='INTAKE',source=Registry.metadata(source,source.container).id,
    destination=Registry.metadata(tools,tools.container).id,items={reloadHeld:getID(),reloadDone:getID()},
    state='PAUSED',reason='USER',phase='DELIVER',generation=0,routeRevision=1,attemptSequence=1,plannedCount=2,manualPaused=true}
saved.manifest=require('EmberRoutesProbe/HaulManifest').create(saved,{[reloadHeld:getID()]=2,[reloadDone:getID()]=3})
saved.delivered=1 assert(Store.claim(saved)) assert(Store.publish(saved))
local root=Registry.data() local restored={}
for k,v in pairs(root) do restored[k]=v end
local oldGet=ModData.getOrCreate
ModData.getOrCreate=function(name) if name=='EmberRoutes/Work/v1' then return restored end return oldGet(name) end
local loaded=Store.record(npc.id)
check(loaded.id==saved.id and Store.owner(reloadHeld:getID()) and not Store.owner(reloadDone:getID()),
    'world-local rebuild claims only unresolved original; delivered receipt never reclaims warehouse stock')
check(loaded.delivered==1 and #loaded.items==2,'world-local rebuild preserves original denominator and delivery count')
print('PASS '..checks..' haul R1 reroute/split/receipts/claims/wake/Session/upgrade/revocation/rebuild assertions; native host mocked')
