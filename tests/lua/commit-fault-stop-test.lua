local Fence=require 'EmberRoutesProbe/Kernel/CommitFence'
local world={} Fence.enter(world)
local actor={} local stopped,cleared,released=false,false,false
package.loaded['EmberRoutesProbe/Runtime/Driver']={
    acquireControl=function(binding) return {binding=binding} end,
    stopEvidence=function() return {available=true,nativeStopped=stopped} end,
    stopControlled=function() stopped=true return true end,
    releaseControl=function() released=true return true end,
}
ISTimedActionQueue={queues={[actor]={queue={{}},current={}}},clear=function(npc)
    assert(npc==actor) cleared=true ISTimedActionQueue.queues[npc].queue={}
end}
local controller=require('EmberRoutesProbe/Runtime/TaskController').new()
local ticket
local adapter=require('EmberRoutesProbe/Runtime/TaskBusinessStop').new({
    controller=controller,ticket=function() return ticket end,npc=actor,npcId='npc',jobId='job',
    same=function() return true end,pause=function() return false end,
    effects=function() return 'UNKNOWN' end,persist=function() return false end,
})
ticket=assert(controller:request('npc','job','WORK',adapter)) controller:step()
assert(controller:attachDriver(ticket,{id='npc',handle=actor}))
local body=controller:body(ticket)
Fence.block(world,'injected ambiguous write')
assert(not body.current() and not controller:request('other','other','WORK',adapter))
controller:step()
assert(cleared and stopped,'fault stops owned queued and native actions even when pause cannot commit')
assert(not released and controller:state(ticket)=='STOPPING','unknown effects do not release body')
assert(not controller:dispatch(ticket,function() error('must not dispatch') end))
Fence.enter({})
print('PASS fault stops existing body while retaining unknown effects; native bodies NOT RUN')
