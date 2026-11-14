-- Controller/ticket and queue boundaries; no native pose engine.
local now=100 local retries=0 local stopped=false local mask=2048 local actor={}
package.loaded['EmberRoutesProbe/Kernel/Clock']={nowMs=function() return now end}
package.loaded['EmberRoutesProbe/Runtime/Driver']={
    acquireControl=function(binding) return {binding=binding,key='owned'} end,
    stopEvidence=function() return {available=true,nativeMask=mask,nativeStopped=stopped} end,
    retryStandExit=function(control) assert(control.key=='owned') retries=retries+1 return true end,
    releaseControl=function() return true end,
}
ISTimedActionQueue={queues={[actor]={queue={{}},current={}}}}
local ctrl=require('EmberRoutesProbe/Runtime/TaskController').new()
local adapter={requestStop=function() return true end,
    observeStop=function() return {bodyStopped=stopped,effects='KNOWN'} end,persistEffects=function() return true end}
local ticket=assert(ctrl:request('npc','job','WORK',adapter)) ctrl:step()
assert(ctrl:attachDriver(ticket,{id='npc',handle=actor})) assert(ctrl:requestStop(ticket,'USER'))
ctrl:step() now=2100 ctrl:step() assert(retries==0,'nonempty Lua queue blocks retry')
ISTimedActionQueue.queues[actor]={queue={}} ctrl:step() now=3101 ctrl:step()
assert(retries==1 and ctrl:state(ticket)=='STOPPING','stable posture requests get-up but does not release')
mask=4096 now=5102 ctrl:step() now=7103 ctrl:step() assert(retries==1,'other native stop causes exclude retry')
stopped=true mask=0 ctrl:step() assert(ctrl:state(ticket)=='CLOSED')
now=9104 ctrl:step() assert(not ctrl:requestStop(ticket,'LATE') and retries==1,'stale ticket cannot trigger retry')
print('PASS stop ticket, no-progress and queue retry gates; native pose NOT RUN')
