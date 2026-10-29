local now=0
getTimestampMs=function() return now end
package.loaded['TimedActions/ISRestAction']=true
local prepared,entered,interrupted=0,0,0 local queued
ISTimedActionQueue={hasAction=function(action) return queued==action end}
ISRestAction={new=function(_,npc,object,animations)
    assert(animations and object=='chair')
    return {character=npc,furnitureHasSittingData=function() return true end,
        waitToStart=function() prepared=prepared+1 return prepared==1 end,
        start=function() entered=entered+1 end,
        stop=function() queued=nil end,
        forceStop=function(self) self:stop() end,
        interruptWaitToStart=function() interrupted=interrupted+1 end}
end}
local seated,started,object=false,false,nil
local requests,clears=0,0 local contextName='idle'
local c={sameAttempt=function() return true end,valid=function() return true end,
    body={retained=function() return true end,furniture=function(obj,phase) assert(obj=='chair' and (phase=='PREPARE' or phase=='STAND_TARGET')) return true end,
        add=function(a) queued=a return true end,
        clear=function() if queued then queued:forceCancel() queued=nil end return true end,
        stop=function() return true end},npc={
    getCurrentActionContextStateName=function() return contextName end,isSitOnGround=function() return false end,
    clearVariable=function(_,key) assert(key=='forceGetUp') clears=clears+1 end,
    isSittingOnFurniture=function() return seated end,getVariableBoolean=function() return started end,
    getSitOnFurnitureObject=function() return object end,
    setVariable=function(_,key,value) assert(key=='forceGetUp' and value) requests=requests+1 end}}
local P=require 'EmberRoutesProbe/LeisurePosture'
local blocked=P.new(c,'chair') contextName='getup'
assert(blocked.enter()=='Running' and clears==0,'old get-up cannot be cleared in its transition')
contextName='idle'
local p=P.new(c,'chair')
assert(p.enter()=='Running' and queued and entered==0,'entry queues native rest')
assert(p.enter()=='Running' and prepared==0,'business polling cannot advance native frame delay')
assert(queued:waitToStart() and not queued:waitToStart())
queued:start() assert(entered==1,'engine advances native preparation and entry')
seated=true object='chair'
assert(p.enter()=='Running','seated state before start flag is not ready')
started=true assert(p.enter()=='Running','reading cannot start before native rest action completes')
assert(queued:complete()) queued=nil assert(p.enter()=='Success')
assert(not p.leave() and requests==1,'request get-up but retain body until native exit')
seated=false assert(not p.leave(),'furniture reference still blocks exit')
object=nil assert(p.leave())
local before=clears assert(p.enter()=='Failure' and clears==before,'an exited posture never clears a later get-up request')
local cancelled=P.new(c,'chair') cancelled.enter()
assert(cancelled.leave() and not queued and interrupted==1,'cancel native pre-turn before handing off')
local late=P.new(c,'chair') late.enter() now=9000
assert(late.enter()=='Failure' and c.reason=='SIT_POSE_TIMEOUT','bounded native transition')
c.sameAttempt=function() return false end
assert(not p.leave(),'old Session cannot clear a new pose')
print('P3.5 posture: native preparation, entry evidence, get-up handshake, timeout and stale Session')
