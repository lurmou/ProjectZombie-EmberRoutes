local checks,time,sequence=0,0,0
local function check(value,message) checks=checks+1 assert(value,message) end
local function body(id,x)
    local b={id=id,x=x or 0,motion='STOPPED'}
    function b:getX() return self.x end
    function b:getY() return 0 end
    function b:getZ() return 0 end
    return b
end
local bodies={a=body('a'),b=body('b')}
local selected='a'
local actor=body('actor',8)
function actor:isDead() return false end
function actor:Say() end
function getSpecificPlayer() return actor end
function getText(key) return key end
function getTimestampMs() return time end
DebugLog={log=function() end}
local Probe={ready=true,controlledExecution=true,build={prefix='TEST'},hasJava=function() return true end}
function Probe.cancelAll() error('controlled companion must not cancel other businesses directly') end
package.loaded['EmberRoutesProbe/Boot']=Probe
local root={}
package.loaded['EmberRoutesProbe/ContainerRegistry']={data=function() return root end,
    id=function() sequence=sequence+1 return 'job-'..sequence end}
local keys={}
local legacy,moves,retires=0,{},0
EmberRoutesProbeJava={
    selectedId=function() return selected end,
    controlledCarrier=function() return bodies[selected] end,
    carrierFor=function(id) return bodies[id] end,
    carrierId=function(b) return b.id end,
    carrierPresent=function(b) return bodies[b.id]==b end,
    motionResult=function(b) return b.motion end,
    acquireBodyControl=function(b,job,generation)
        assert(not keys[b.id]) keys[b.id]=job..':'..generation return keys[b.id]
    end,
    moveWithControl=function(b,key)
        assert(key==keys[b.id]) b.motion='MOVING' moves[b.id]=(moves[b.id] or 0)+1 return 'MOVE_REQUESTED'
    end,
    stopWithControl=function(b,key) assert(key==keys[b.id]) b.motion='STOPPED' return true end,
    bodyStopMask=function(b,key) assert(key==keys[b.id]) return b.motion=='MOVING' and 1 or 0 end,
    releaseBodyControl=function(b,key) assert(key==keys[b.id] and b.motion=='STOPPED') keys[b.id]=nil return true end,
    retireBodyControl=function() retires=retires+1 return true end,
    stopCarrier=function() legacy=legacy+1 error('legacy stop bypass') end,
    command=function() legacy=legacy+1 error('legacy move bypass') end,
}
ISTimedActionQueue={queues={},clear=function(b) ISTimedActionQueue.queues[b]=nil end}
local Runtime=require 'EmberRoutesProbe/TaskRuntime'
local Companion=require 'EmberRoutesProbe/Companion'
local function tick(n)
    for _=1,n do time=time+1000 Probe.tickTasks() Companion.tick() end
end
check(Companion.debugExecute(actor,'follow'),'command submits a candidate')
check(Companion.exportState('a').mode=='HOLD' and keys.a==nil,'UI command does not start same stack')
selected='b'
tick(3)
check(Companion.exportState('a').mode=='FOLLOW' and moves.a==1 and not keys.b,'selection change cannot retarget deferred command')
check(Companion.debugExecute(actor,'follow'),'second NPC starts independently') tick(3)
check(Companion.exportState('b').mode=='FOLLOW' and moves.b==1,'second controlled follow progresses')
selected='a'
check(Companion.debugExecute(actor,'hold'),'hold submits through same service')
check(Companion.exportState('a').mode=='FOLLOW','hold waits for stop protocol')
tick(6)
check(Companion.exportState('a').mode=='HOLD' and keys.a==nil,'hold drains and releases controlled session')
check(Companion.exportState('b').mode=='FOLLOW' and keys.b~=nil,'one NPC hold preserves other follower')
check(root.companionIntents.byNpc.a.mode=='HOLD' and root.companionIntents.byNpc.a.effects=='KNOWN','scalar stopped intent is recorded')
local saved={id='a',jobId='saved-follow-job',mode='FOLLOW',hasHome=false}
check(Companion.debugRestoreState(actor,saved),'restore queues a candidate')
saved.id='b' saved.mode='HOLD' selected='b'
tick(3)
check(Companion.exportState('a').mode=='FOLLOW' and Companion.exportState('a').jobId=='saved-follow-job',
    'restore captures original scalars NPC ID and stable job')
local oldRuntime=Runtime.current()
Probe.resetTasks()
check(Runtime.current()==nil,'reset cannot recreate an execution service during legacy cleanup')
local before=moves.a
Companion.tick()
check(moves.a==before and legacy==0,'retired companion cannot dispatch or fall back to legacy Java')
-- Let the old owners finish stopping before simulating a native world teardown.
oldRuntime:step() oldRuntime:step()
check(keys.a==nil and keys.b==nil,'retired world retains stop authority until release')
check(root.companionIntents.byNpc.a.mode=='FOLLOW','retirement retains follow recovery intent')
root={}
Probe.beginTasks()
check(Runtime.current()~=oldRuntime,'new world obtains a new running service')
local active=Runtime.current()
Probe.beginTasks()
check(Runtime.current()==active,'repeat begin in the same world preserves session generation source')
-- Native world replacement happens independently of the Lua ModData pointer.
selected='a' Companion.debugExecute(actor,'follow') tick(3)
local beforeRetires=retires
root={} keys={}
check(Runtime.current()~=active and retires==beforeRetires,'old Lua service cannot retire new native world authority')
check(legacy==0,'all controlled companion movement and stop use native capability')
print('PASS '..checks..' controlled companion integration checks; native host mocked')
