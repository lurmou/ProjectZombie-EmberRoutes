local f=dofile('tests/lua/multi-worker-test.lua')
local Runtime=require 'EmberRoutesProbe/TaskRuntime'
local Store=require 'EmberRoutesProbe/LaborStore'
local Work=f.Work
local checks=0
local function check(value,message) checks=checks+1 assert(value,message) end
local keys={}
local bridge=f.bridge
bridge.acquireBodyControl=function(npc,job,generation)
    assert(not keys[npc]) keys[npc]=job..':'..generation return keys[npc]
end
bridge.bodyStopMask=function(npc,key) return key==keys[npc] and (npc.actions:isEmpty() and 0 or 4) or -1 end
bridge.moveWithControl=function(npc,key,actor,x,y,z)
    assert(key==keys[npc] and npc.actions:isEmpty())
    npc.x,npc.y,npc.z=x,y,z npc.motion='REACHED' return 'MOVE_REQUESTED'
end
bridge.stopWithControl=function(npc,key) assert(key==keys[npc]) npc.motion='STOPPED' return true end
bridge.releaseBodyControl=function(npc,key) assert(key==keys[npc] and npc.actions:isEmpty()) keys[npc]=nil return true end
bridge.retireBodyControl=function() return true end
bridge.stopCarrier=function() error('controlled transfer used legacy stop') end
bridge.commandFor=function() error('controlled transfer used legacy move') end
f.fixture.ctx.Probe.cancelAll=function() error('controlled transfer directly cancelled other businesses') end
ISTimedActionQueue.queues={}
local rawAdd,rawClear=ISTimedActionQueue.add,ISTimedActionQueue.clear
ISTimedActionQueue.add=function(action)
    local q={queue={action},current=action}
    ISTimedActionQueue.queues[action.character]=q
    local perform,stop=action.perform,action.stop
    action.perform=function(self)
        perform(self)
        if q.current==self and f.queued[self.character]~=self then q.queue={} q.current=nil end
    end
    action.stop=function(self)
        stop(self)
        if q.current==self and f.queued[self.character]~=self then q.queue={} end
    end
    rawAdd(action)
end
ISTimedActionQueue.clear=function(npc)
    rawClear(npc)
    local q=ISTimedActionQueue.queues[npc]
    if q then q.queue={} end
end
f.fixture.ctx.Probe.controlledExecution=true
Runtime.begin()
local function route(npc,x)
    local source,dest=f.fixture.object(x),f.fixture.object(x+8)
    f.select(npc.id) f.actor.x=x+0.5
    Work.execute(f.actor,'inbox',source) Work.execute(f.actor,'source',source)
    f.actor.x=x+8.5 Work.execute(f.actor,'outbox',dest) Work.execute(f.actor,'destination',dest)
    return source,dest
end
local function tick(effects)
    f.tick(1,false)
    Runtime.current():step()
    if effects then
        for _,npc in ipairs({f.a,f.b}) do local action=f.queued[npc] if action then action:perform() end end
    end
end
local function pump()
    for _=1,150 do
        tick(true)
        if not Runtime.current():owns(f.a.id) and not Runtime.current():owns(f.b.id) then return end
    end
    error('controlled transfers did not drain')
end
local source,dest=route(f.a,4)
local original=f.fixture.item('controlled-original',source.container)
check(Work.execute(f.actor,'run')=='QUEUED','manual transfer is admitted asynchronously')
check(not Store.owner(original:getID()) and original:getContainer()==source.container,'no premature original claim or transfer')
pump()
local record=Work.record(f.a.id)
check(record.state=='DONE' and record.delivered==1 and original:getContainer()==dest.container,'original delivered and completion recorded')
check(keys[f.a]==nil and not Store.owner(original:getID()),'completed transfer releases its body and asset claims')
local otherSource,otherDest=route(f.b,20)
local second=f.fixture.item('other-original',otherSource.container)
check(Work.execute(f.actor,'run')=='QUEUED','second NPC queued')
f.select(f.a.id)
local third=f.fixture.item('paused-original',source.container)
check(Work.execute(f.actor,'run')=='QUEUED','first NPC queues separate manifest')
for _=1,40 do tick(false) if f.queued[f.a] and f.queued[f.b] then break end end
local old=f.queued[f.a] local other=f.queued[f.b]
check(old~=nil and other~=nil,'two NPC action queues coexist')
local jobId=Work.record(f.a.id).id
Work.pause('USER',f.a.id)
for _=1,12 do tick(false) if not Runtime.current():owns(f.a.id) then break end end
check(Work.record(f.a.id).state=='PAUSED' and Store.owner(third:getID()) and third:getContainer()==source.container,
    'pause retains original identity and claim before any transfer effect')
check(f.queued[f.b]==other and keys[f.b]~=nil,'pausing A does not stop B')
local resumeGeneration=Work.record(f.a.id).generation
check(Work.taskCommand(f.actor,f.a.id,jobId,resumeGeneration-1,'resume')=='TASK_CHANGED','monitor cannot resume an obsolete transfer revision')
check(Work.taskCommand(f.actor,f.a.id,jobId,resumeGeneration,'resume')=='QUEUED','explicit stable-job resume goes through fresh admission')
for _=1,40 do tick(false) if f.queued[f.a] then break end end
local successor=f.queued[f.a]
check(successor and successor~=old,'resumed job has a fresh native action')
old:stop() old:perform()
check(f.queued[f.a]==successor and third:getContainer()==source.container,'late stop/perform cannot remove successor or transfer an original')
pump()
check(Work.record(f.a.id).id==jobId and third:getContainer()==dest.container,'same job resumes and delivers exactly its original')
check(second:getContainer()==otherDest.container and Work.record(f.b.id).state=='DONE','other NPC also finishes independently')
local fourth=f.fixture.item('unknown-original',source.container)
check(Work.execute(f.actor,'run')=='QUEUED','unknown-effect fixture queued')
for _=1,40 do tick(false) if f.queued[f.a] then break end end
local take=f.queued[f.a] check(take~=nil,'unknown-effect fixture reaches transfer')
take:perform() check(fourth:getContainer()==f.a.root,'original actually moved into NPC')
f.a.root:Remove(fourth)
Work.pause('USER',f.a.id)
for _=1,15 do tick(false) if not Runtime.current():owns(f.a.id) then break end end
record=Work.record(f.a.id)
check(record.controlUncertain and Store.owner(fourth:getID()) and keys[f.a]==nil,'missing original records UNKNOWN without keeping safe body hostage')
check(Work.execute(f.actor,'resume')=='RECONCILE_REQUIRED','unknown transfer cannot replay')
check(not f.queued[f.a] and fourth:getContainer()==nil,'no reconstructed substitute or duplicate effect')
print('PASS '..checks..' controlled transfer checks; native bodies mocked')
