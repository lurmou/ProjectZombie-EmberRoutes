-- Actual Runtime/BT/Jobs/claims and installed handcraft Lua; native path/transfer effects mocked.
local f=dofile('tests/lua/cooking-craft-test.lua')
local checks=0 local function check(v,m) checks=checks+1 assert(v,m) end
local Record=require 'EmberRoutesProbe/CookingRecord'
local Batch=require 'EmberRoutesProbe/CookingBatch'
local Agent=require 'EmberRoutesProbe/CookingAgent'
local Jobs=require('EmberRoutesProbe/TaskJobs').current()
local Store=require 'EmberRoutesProbe/LaborStore'
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local Filter=require 'EmberRoutesProbe/StorageFilter'
local Transfer=require 'EmberRoutesProbe/WorkTransfer'
local Membership=require 'EmberRoutesProbe/MembershipService'
local Runtime=require 'EmberRoutesProbe/TaskRuntime'
local npc,actor=f.npc,f.f.fixture.actor
function npc:isDead() return not self.alive end
local entry={id='kitchen',areas={{x=1000,y=0,w=100,h=100}}}
local powered,allowed,safe=true,true,true
Membership.entry=function() return entry end
Membership.check=function() return {allowed=allowed,sharedResources=allowed} end
local storage=f.f.fixture.fixture.object(1006)
local fridge=f.f.fixture.fixture.object(1007)
function fridge.container:isFridge() return true end function fridge.container:isFreezer() return false end
function fridge.container:isPowered() return powered end function fridge.container:getTemperature() return powered and .2 or 1 end
local endpoints={source={id='source',object=storage,container=storage.container},cold={id='cold',object=fridge,container=fridge.container}}
local filter=Filter.new() filter.types['Mod.MilkCarrier']=true filter.types['Base.Butter']=true
Registry.resolve=function(id) return allowed and endpoints[id] or nil,'ACCESS_DENIED' end
Registry.revalidate=function(e) return allowed and endpoints[e.id]==e and e or nil end
Registry.logistics=function() return 'STORAGE' end
Registry.accepts=function() return allowed end Registry.filter=function() return filter end
require('EmberRoutesProbe/SettlementMembership').query=function() return {'source','cold'} end
local bridge=EmberRoutesProbeJava local key local moves=0 local stopMask=0 local delayStop=false
bridge.acquireBodyControl=function(_,job,generation) assert(not key) key=job..':'..generation return key end
bridge.bodyStopMask=function() return stopMask end
bridge.stopWithControl=function() if not delayStop then stopMask=0 end return true end
bridge.releaseBodyControl=function(_,value) assert(value==key and stopMask==0) key=nil return true end
bridge.bindingValid=function(body,id) return body==npc and id==npc.id end
bridge.moveWithControl=function(_,value,_,x,y,z)
    assert(value==key) moves=moves+1 stopMask=1 npc.x,npc.y,npc.z=x,y,z npc.motion='REACHED' return 'MOVE_REQUESTED'
end
function npc:getCurrentSquare() return {canReachTo=function() return true end} end
Transfer.prepareMove=function(c,e)
    local square=e.object:getSquare()
    return {object=e.object,square=square,x=square:getX()+.5,y=square:getY()+.5,z=square:getZ(),at=getTimestampMs()}
end
ISTimedActionQueue.queues={}
ISTimedActionQueue.add=function(action)
    ISTimedActionQueue.queues[npc]={queue={action},current=action} f.f.queue(action)
end
ISTimedActionQueue.clear=function()
    local action=f.f.queued() if action then action:stop() end
    f.f.queue(nil) ISTimedActionQueue.queues[npc]={queue={}}
end
local function advance(runtime,perform)
    runtime:step()
    local action=f.f.queued()
    if action and perform~=false then
        if action.start then action:start() end action:perform()
        if not f.f.queued() then ISTimedActionQueue.queues[npc]={queue={}} end
    end
end
local serial=0
local function create()
    serial=serial+1 powered=true allowed=true safe=true f.mode(nil)
    f.object.user=nil f.object.mod.EmberRoutesCraftOccupancy=nil f.object.mod.EmberRoutesCraftProbeBenchId=nil
    local milk=f.f.item('Mod.MilkCarrier',false,storage.container)
    milk.fluid=f.milkContainer(6) function milk:getFluidContainer() return self.fluid end
    local profile=assert(require('EmberRoutesProbe/CookingCraft').profile('Base.churn_butter'))
    local j=assert(Record.new('agent-'..serial,npc.id,'kitchen',profile.facts.id,'REQUEST','request-'..serial,.15,.15))
    j=assert(Batch.prepare(j,{profile=profile,entries={{id=milk.id,slot=0,item=milk,endpoint=endpoints.source}}}))
    assert(Jobs:create(j))
    local spec,c=assert(Agent.new(actor,{id=npc.id,handle=npc},j,f.object,
        function() return {nodes=16,scan=16,paths=1} end,function() return safe end))
    assert(spec.validate(),'candidate precheck')
    local runtime=Runtime.new() local handle=assert(runtime:submit(spec))
    return runtime,handle,c,milk
end
local function drain(runtime,handle)
    for _=1,400 do advance(runtime) local state=runtime:inspect(handle).state if state=='CLOSED' then return end end
    error('agent did not close: '..tostring(runtime:inspect(handle).state)..' '..tostring(runtime:inspect(handle).error))
end
local before=f.commits() local runtime,handle,c,milk=create()
check(milk:getContainer()==storage.container and not key,'pending request cannot move originals or acquire body')
npc.x=.5 delayStop=true
for _=1,100 do advance(runtime,false) if moves>0 then break end end
for _=1,4 do advance(runtime,false) end
check(c.job.payload.sequence==0 and not f.f.queued() and milk:getContainer()==storage.container,
    'adjacent position and accepted stop request are insufficient until native stop evidence clears')
delayStop=false
drain(runtime,handle)
check(c.job.state=='DONE' and c.job.payload.phase=='SETTLED' and c.closed,'completed job becomes terminal only through stopped-body persistence: '
    ..tostring(c.job.state)..' '..tostring(c.reason)..' '..tostring(runtime:inspect(handle).error))
check(f.commits()==before+1 and milk.fluid:getAmount()==1 and milk:getContainer()==storage.container,
    'one actual handcraft consumes five units and returns the same remaining-milk carrier')
local output=c.job.payload.bindings[1].outputIds[1]
check(not Store.owner(milk.id) and not Store.owner(output) and not key and not f.object.user,
    'no outstanding originals, body control or native UsingPlayer after complete settlement')
local stored=false for _,item in ipairs(fridge.container.items) do if item.id==output then stored=true end end
check(stored and moves>0,'actual produced Butter is delivered to powered cold storage through owned movement')
-- Revoke while collecting: the same Job retains the carried original for settle-only recovery.
runtime,handle,c,milk=create()
for _=1,100 do advance(runtime) if milk:getContainer()==npc:getInventory() then break end end
assert(runtime:stop(npc.id,'USER'))
for _=1,30 do advance(runtime,false) if runtime:inspect(handle).state=='CLOSED' then break end end
check(c.job.state=='SUSPENDED' and Store.owner(milk.id) and milk.fluid:getAmount()==6,
    'revoke persists custody and stops before consuming milk')
local resume,rc=assert(Agent.new(actor,{id=npc.id,handle=npc},c.job,nil,
    function() return {nodes=16,scan=16,paths=1} end,function() return true end,{settleOnly=true}))
local recovery=Runtime.new() local rh=assert(recovery:submit(resume)) drain(recovery,rh)
check(rc.job.state=='CANCELLED' and milk:getContainer()==storage.container and not Store.owner(milk.id),
    'settle-only recovery returns borrowed original without starting another recipe')
local function resumeJob(job,object,settleOnly)
    local spec,c=assert(Agent.new(actor,{id=npc.id,handle=npc},job,object,
        function() return {nodes=16,scan=16,paths=1} end,function() return true end,{settleOnly=settleOnly}))
    local r=Runtime.new() local h=assert(r:submit(spec)) drain(r,h) return c
end
before=f.commits() runtime,handle,c,milk=create()
for _=1,100 do advance(runtime) if c.job.payload.bindings then break end end
assert(runtime:stop(npc.id,'REVOKED')) drain(runtime,handle)
check(c.job.state=='SUSPENDED' and not f.object.user and not c.job.payload.station and Store.owner(milk.id),
    'session stop after native completion clears UsingPlayer but retains delivery/return responsibilities')
rc=resumeJob(c.job,nil,false)
check(rc.closed and f.commits()==before+1 and milk:getContainer()==storage.container,
    'resume from stored craft receipt delivers actual output without a second native recipe call')
before=f.commits() runtime,handle,c,milk=create() powered=false drain(runtime,handle)
check(c.job.state=='SUSPENDED' and milk:getContainer()==storage.container and f.commits()==before,
    'no powered cold storage blocks collection and native production')
powered=true rc=resumeJob(c.job,nil,true)
check(rc.closed and rc.job.state=='CANCELLED' and not Store.owner(milk.id),
    'untouched source reservation settles only after original-location verification')
runtime,handle,c,milk=create()
for _=1,100 do advance(runtime,false) if f.f.queued() then break end end
assert(runtime:stop(npc.id,'REVOKED')) drain(runtime,handle)
check(c.job.state=='SUSPENDED' and c.job.payload.attempt.state=='ABORTED' and milk:getContainer()==storage.container,
    'revoked queued take records known no-effect and retains its original source binding')
local tampered=Record.copy(c.job) tampered.payload.fixed.inputs[1].sourceId='cold'
check(not Jobs:update(tampered.id,tampered.revision,{payload=tampered.payload}),
    'fixed-batch origin cannot be rewritten during recovery')
resumeJob(c.job,nil,true)
before=f.commits() runtime,handle,c,milk=create()
for _=1,100 do
    advance(runtime,false)
    local a=c.job.payload.attempt
    if a and a.kind=='CRAFT' and f.f.queued() then break end
    local action=f.f.queued()
    if action then action:start() action:perform() ISTimedActionQueue.queues[npc]={queue={}} end
end
assert(runtime:stop(npc.id,'REVOKED')) drain(runtime,handle)
check(c.job.state=='SUSPENDED' and c.job.payload.attempt.kind=='CRAFT' and c.job.payload.attempt.state=='ABORTED'
    and milk.fluid:getAmount()==6 and not f.object.user,'pre-effect craft revoke releases workstation without consuming liquid')
rc=resumeJob(c.job,f.object,false)
check(rc.closed and f.commits()==before+1,'known aborted craft may start a new sequence and still produces exactly one batch')
runtime,handle,c,milk=create() f.mode('throw-after-output')
for _=1,150 do advance(runtime) if c.job.state=='RECONCILE_REQUIRED' then break end end
check(c.job.effects=='UNKNOWN' and c.job.state=='RECONCILE_REQUIRED' and #c.job.payload.assets==2
    and Store.owner(milk.id),'partial native exception retains both original carrier and observed output')
check(not Agent.new(actor,{id=npc.id,handle=npc},c.job,f.object,
    function() return {nodes=16,scan=16,paths=1} end,function() return true end),'unknown craft cannot be automatically resumed or replayed')
print('PASS '..checks..' fixed cooking Agent checks; actual Runtime/BT/native Lua, mocked engine; game NOT RUN')
