-- Actual Agent/Runtime/Jobs and installed actions. Native heat/power/path effects mocked.
local e=dofile('tests/lua/cooking-evolved-test.lua') local f=e.w.f
local checks=0 local function check(v,m) checks=checks+1 assert(v,m) end
local Context=require 'EmberRoutesProbe/CookingContext'
local Record=require 'EmberRoutesProbe/CookingRecord'
local Store=require 'EmberRoutesProbe/LaborStore'
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local Filter=require 'EmberRoutesProbe/StorageFilter'
local Jobs=require('EmberRoutesProbe/TaskJobs').current()
dofile('D:/Software/GameApp/steam/steamapps/common/ProjectZomboid/media/lua/shared/Entity/TimedActions/ISHandcraftAction.lua')
package.loaded['Entity/TimedActions/ISHandcraftAction']=true
local Agent=require 'EmberRoutesProbe/CookingAgent'
local Heat=require 'EmberRoutesProbe/CookingHeat'
local Recovery=require 'EmberRoutesProbe/CookingRecovery'
local Membership=require 'EmberRoutesProbe/MembershipService'
local Runtime=require 'EmberRoutesProbe/TaskRuntime'
local npc,actor=f.npc,f.fixture.actor
local entry={id='kitchen',areas={{x=0,y=0,w=20,h=20}}}
Membership.entry=function() return entry end
Membership.check=function() return {allowed=true,sharedResources=true} end
function npc:isDead() return false end
local maximum=100 function npc:getMaxWeight() return maximum end
local clock=0 function getGameTime() return {getWorldAgeHours=function() return clock end} end
local key,events,moves=nil,{},0
local bridge=EmberRoutesProbeJava
bridge.bindingValid=function(body,id) return body==npc and id==npc.id end
bridge.acquireBodyControl=function(_,job,generation) assert(not key) key=job..':'..generation return key end
bridge.bodyStopMask=function() return 0 end bridge.stopWithControl=function() return true end
bridge.releaseBodyControl=function(_,value) assert(value==key) key=nil return true end
bridge.moveWithControl=function() moves=moves+1 return 'MOVE_REQUESTED' end
ISTimedActionQueue.queues={}
ISTimedActionQueue.add=function(action) f.queue(action) ISTimedActionQueue.queues[npc]={queue={action},current=action} end
ISTimedActionQueue.clear=function()
    local action=f.queued() if action then action:stop() end f.queue(nil) ISTimedActionQueue.queues[npc]={queue={}}
end
local endpoints={} local candidateIds={} local serial=0
Registry.resolve=function(id) return endpoints[id],endpoints[id] and nil or 'CONTAINER_UNLOADED' end
Registry.revalidate=function(endpoint) return endpoints[endpoint.id]==endpoint and endpoint or nil end
Registry.logistics=function(endpoint) return endpoint.stove and 'INPUT' or 'STORAGE' end
Registry.filter=function(object) return object.filter end
Registry.accepts=function(endpoint,item) return endpoint.object.filter.types[item:getFullType()]==true end
require('EmberRoutesProbe/SettlementMembership').query=function() return candidateIds end
local function endpoint(id,x,types)
    local object=f.fixture.fixture.object(x) local container=object.container
    object.filter=Filter.new() for _,kind in ipairs(types) do object.filter.types[kind]=true end
    local ep={id=id,object=object,container=container,filter=object.filter}
    endpoints[id]=ep return ep
end
local function makeStove(id)
    local ep=endpoint(id,2,{'Base.PotOfSoupRecipe'}) ep.stove=true local object=ep.object
    object.stove=true object.active=false object.powered=true
    function object:isMicrowave() return false end function object:isBroken() return false end
    function object:Activated() return self.active end
    function object:Toggle()
        self.active=not self.active
        events[#events+1]={kind=self.active and 'ON' or 'OFF',contents=self.container:getItems():size()}
    end
    function object:PlayToggleSound() end function object:getObjectIndex() return 0 end
    function ep.container:isPowered() return object.powered end
    return ep
end
local function fridge(id,x)
    local ep=endpoint(id,x,{'Base.PotOfSoupRecipe'}) ep.object.powered=true
    function ep.container:isFridge() return true end function ep.container:isFreezer() return false end
    function ep.container:isPowered() return ep.object.powered end
    function ep.container:getTemperature() return ep.object.powered and .2 or 1 end
    return ep
end
local function preparation(two)
    serial=serial+1 maximum=100 events={}
    npc.x,npc.y,npc.z=2.5,.5,0
    local c,pot,ingredients=e.setup({'Base.Carrot','Base.Potato'})
    e.finish(c,assert(e.Evolved.new(c,e.recipe,pot,ingredients,.12)))
    local id=assert(Record.resolveOutput(c.job,Record.outputReference(c.job,c.job.payload.evolved.baseSequence,1))).id
    local ids={id}
    if two then
        local item=f.item('Base.PotOfSoupRecipe',true)
        local j=Record.copy(c.job) j.payload.assets[#j.payload.assets+1]={id=item.id,fullType=item.kind,custody='HELD',role='INPUT'}
        j.payload.claims[#j.payload.claims+1]='item:'..item.id assert(Context.publish(c,j))
        c.items[item.id]=item ids[#ids+1]=item.id
    end
    for _,item in ipairs(f.root.items) do for _,id in ipairs(ids) do if item.id==id then c.items[id]=item end end end
    assert(Heat.new(c,ids)) -- Durable heat plan, no native action or furnace claim yet.
    local stove=makeStove('oven-'..serial) local a=fridge('cold-a-'..serial,4) local b=fridge('cold-b-'..serial,6)
    local warehouse=endpoint('stock-'..serial,5,{'Base.Carrot','Base.Potato'})
    candidateIds={stove.id,a.id,b.id,warehouse.id}
    local spec,context=assert(Agent.new(actor,{id=npc.id,handle=npc},c.job,nil,
        function() return {nodes=24,scan=16,paths=1} end,function() return true end))
    local runtime=Runtime.new() local handle=assert(runtime:submit(spec))
    return {r=runtime,h=handle,c=context,stove=stove,a=a,b=b,ids=ids}
end
local function advance(t,perform)
    clock=clock+2/3600 t.r:step()
    local action=f.queued()
    if action and perform~=false then
        action:start() if action.complete then action:complete() end action:perform()
        if not f.queued() then ISTimedActionQueue.queues[npc]={queue={}} end
    end
end
local function untilState(t,predicate,perform)
    for _=1,300 do advance(t,perform) if predicate() then return end end
    error('state not reached: '..tostring(t.c.job.state)..' '..tostring(t.c.reason)..' '..tostring(t.r:inspect(t.h).error)
        ..' phase='..t.c.job.payload.phase..' duty='..tostring(t.c.job.payload.duty and t.c.job.payload.duty.state)
        ..' heatClosed='..tostring(t.c.job.payload.heat.closed)..' heatAbort='..tostring(t.c.job.payload.heat.aborted))
end
local function finish(t)
    untilState(t,function() return t.r:inspect(t.h).state=='CLOSED' end)
end
local function cook(t,index)
    local id=t.ids[index or 1] local item=t.c.items[id] assert(item) item.cooked=true
end
local function resume(t)
    local spec,c=assert(Agent.new(actor,{id=npc.id,handle=npc},t.c.job,nil,
        function() return {nodes=24,scan=16,paths=1} end,function() return true end))
    local r=Runtime.new() local h=assert(r:submit(spec))
    return {r=r,h=h,c=c,stove=t.stove,a=t.a,b=t.b,ids=t.ids}
end
local function candidate(jobId)
    local query=Recovery.new(actor,{id=npc.id,handle=npc})
    for _=1,100 do local row,done=query:step(1) if row and row.jobId==jobId then return row end if done then return end end
end
local t=preparation(true)
untilState(t,function() return t.stove.object.active end)
check(t.stove.container:getItems():size()==2 and #events==1 and events[1].kind=='ON','both original foods load before one actual native activation')
for _=1,5 do advance(t) end
check(t.c.job.state=='RUNNING' and not t.c.items[t.ids[1]].cooked,'waiting never fabricates cooked flags or elapsed-time food effects')
cook(t,1)
untilState(t,function() return t.c.items[t.ids[1]]:getContainer()==f.root end)
check(t.stove.object.active and t.c.items[t.ids[2]]:getContainer()==t.stove.container,'first ready original leaves the active stove while second food continues heating')
cook(t,2)
finish(t)
check(t.c.job.state=='DONE' and t.c.closed and not t.stove.object.active and not t.c.job.payload.duty,
    'heat, shutdown, delivery and leftover return settle through the same Runtime Job: '..tostring(t.c.reason)..' '..tostring(t.c.job.state)..' '..tostring(t.r:inspect(t.h).error))
check(#events==2 and events[2].kind=='OFF' and events[2].contents==0,'normal native OFF occurs only after all owned foods leave residual heat')
check(t.c.items[t.ids[1]]:getContainer()==t.a.container and t.c.items[t.ids[2]]:getContainer()==t.a.container,
    'multiple output originals are actually delivered instead of reusing the prior transfer leaf')
check(math.abs(t.c.job.payload.expected-.36)<.000001 and not Store.owner(t.ids[1]) and not Store.owner(t.ids[2]),
    'whole-batch actual fullness includes earlier extracted foods and every delivered original is settled')
-- Cold storage changes before its effect: known cancellation relocates the same original.
t=preparation(false) untilState(t,function() return t.stove.object.active end) cook(t)
untilState(t,function()
    local a=t.c.job.payload.attempt
    if a and a.kind=='TRANSFER' and a.state=='PREPARED' and a.spec.toId==t.a.id and f.queued()~=nil then return true end
    local pending=f.queued()
    if pending then pending:start() if pending.complete then pending:complete() end pending:perform() ISTimedActionQueue.queues[npc]={queue={}} end
    return false
end,false)
t.a.object.powered=false
local action=f.queued() action:perform() ISTimedActionQueue.queues[npc]={queue={}}
finish(t)
check(t.c.closed and t.c.items[t.ids[1]]:getContainer()==t.b.container and t.a.container:getItems():size()==0,
    'cold outage before commit reroutes a known unchanged transfer without another Job or duplicate')
-- Session loss keeps Duty; a later candidate drains it without opening another fire.
t=preparation(false) untilState(t,function() return t.stove.object.active end)
assert(t.r:stop(npc.id,'SELF_CARE')) finish(t)
check(t.c.job.state=='SUSPENDED' and t.c.job.obligations.furnace and t.stove.object.active,'interruption preserves physical-device duty and exact loaded originals')
local row=assert(candidate(t.c.job.id)) check(row.ready and row.reason=='FURNACE_DRAIN_REQUIRED','same-NPC recovery is discovered from existing indexed Jobs')
check(Jobs:peek(t.c.job.id).revision==t.c.job.revision and not key and #events==1,
    'candidate discovery does not publish a Job, claim a body or remotely manipulate heat')
t=resume(t) finish(t)
check(t.c.job.state=='CANCELLED' and t.c.job.payload.heat.aborted and t.c.job.payload.expected==0
    and t.c.items[t.ids[1]]:getContainer()==t.a.container and not t.c.job.payload.duty,
    'unfinished food is returned to cold storage after physical extraction/shutdown, not counted as delivered meals')
check(#events==2 and events[1].kind=='ON' and events[2].kind=='OFF','recovery never restarts the stove')
-- Emergency OFF when extraction capacity is unavailable leaves a real unload obligation.
t=preparation(false) untilState(t,function() return t.stove.object.active end) cook(t) maximum=1 finish(t)
check(t.c.job.state=='SUSPENDED' and not t.stove.object.active and t.c.job.payload.duty
    and t.c.items[t.ids[1]]:getContainer()==t.stove.container,'blocked extraction closes an owned stove but retains its unload duty')
check(events[2].kind=='OFF' and events[2].contents==1,'emergency ordering differs only when physical extraction is blocked')
maximum=100 t=resume(t) finish(t)
check(t.c.closed and not t.c.job.payload.duty and t.c.items[t.ids[1]]:getContainer()==t.a.container,'capacity recovery finishes the retained original, never recreating food')
-- An external OFF is observed, never undone.
t=preparation(false) untilState(t,function() return t.stove.object.active end) t.stove.object.active=false finish(t)
check(t.c.closed and t.c.job.state=='CANCELLED' and #events==1,'externally switched-off heat is safely drained without relighting or blindly toggling')
-- A power outage stops heating; absent cold storage retains food until storage recovers.
t=preparation(false) untilState(t,function() return t.stove.object.active end)
t.stove.object.powered=false t.a.object.powered=false t.b.object.powered=false finish(t)
check(t.c.job.state=='SUSPENDED' and not t.stove.object.active and not t.c.job.payload.duty
    and t.c.items[t.ids[1]]:getContainer()==f.root and Store.owner(t.ids[1]),
    'power/cold outage physically clears the hot device but keeps undeliverable unfinished food owned')
t.b.object.powered=true t=resume(t) finish(t)
check(t.c.closed and t.c.job.state=='CANCELLED' and t.c.items[t.ids[1]]:getContainer()==t.b.container
    and t.c.job.payload.expected==0,'cold restoration stores the same raw original without restarting heat or crediting a meal')
-- Foreign food does not become owned output and is never toggled off on its owner's behalf.
t=preparation(false) untilState(t,function() return t.stove.object.active end)
local foreign=f.item('Base.Carrot',true,t.stove.container) finish(t)
check(t.stove.object.active and foreign:getContainer()==t.stove.container and not Store.owner(foreign.id)
    and t.c.job.obligations.furnace,'foreign intervention retains reconciliation duty without stealing food or switching player contents off')
row=assert(candidate(t.c.job.id)) check(not row.ready and row.reason=='FURNACE_RECONCILE_REQUIRED','ambiguous device responsibility is not advertised as automatic recovery')
local forged=Record.copy(t.c.job) forged.payload.duty.position.x=forged.payload.duty.position.x+1
check(not Jobs:update(forged.id,forged.revision,{payload=forged.payload}),
    'a retained physical-device position cannot be rebound to another stove during recovery')
print('PASS '..checks..' heat/delivery/recovery checks; actual Runtime/actions, mocked native heat/world; game NOT RUN')
return {e=e,f=f,entry=entry,endpoint=endpoint,stove=makeStove,fridge=fridge,
    setCandidates=function(ids) candidateIds=ids end,advance=advance,finish=finish,untilState=untilState,
    preparation=preparation}
