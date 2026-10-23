local Stop=require 'EmberRoutesProbe/TaskBusinessStop'
local checks=0
local function check(v,m) checks=checks+1 assert(v,m) end
local npc={}
local state,same,native,paused,persisted='ACTIVE',true,true,0,false
local ticket={}
local currentJob='job'
local controller={inspect=function() return {state=state,npcId='npc',jobId=currentJob} end,
    bodySnapshot=function() return {available=true,nativeStopped=native} end,
    stopBody=function() check(paused>0,'fence before native stop') return true end}
ISTimedActionQueue={queues={}}
local spec={controller=controller,ticket=function() return ticket end,npc=npc,npcId='npc',jobId='job',
    same=function() return same end,pause=function() paused=paused+1 end,
    effects=function() return 'UNKNOWN' end,persist=function(fact) persisted=fact.effects=='UNKNOWN' return persisted end}
local adapter=Stop.new(spec)
check(not adapter.requestStop('USER') and paused==0,'active owner cannot invoke stop adapter')
state='STOPPING'
currentJob='other'
check(not adapter.requestStop('WRONG_JOB') and paused==0,'same NPC wrong job cannot stop business')
currentJob='job'
check(adapter.requestStop('USER'),'stopping owner pauses business')
ISTimedActionQueue.queues[npc]={queue={1},current=1}
check(not adapter.observeStop().bodyStopped,'native stopped not enough when Lua queue remains')
ISTimedActionQueue.queues[npc]={queue={},current=1}
check(not adapter.observeStop().bodyStopped,'Lua current action must clear')
ISTimedActionQueue.queues[npc]=nil native=false
check(not adapter.observeStop().bodyStopped,'empty Lua queue not enough when native moving')
native=true
check(adapter.observeStop().bodyStopped and adapter.observeStop().effects=='UNKNOWN','combined snapshot preserves unknown effects')
check(adapter.persistEffects({effects='UNKNOWN'}) and persisted,'business retains unknown obligation')
same=false
check(not adapter.requestStop('LATE') and paused==1,'stale record not paused')
check(not adapter.observeStop().bodyStopped and not adapter.persistEffects({effects='KNOWN'}),'stale cannot release or rewrite facts')
same=true ISTimedActionQueue=nil
check(not adapter.observeStop().bodyStopped,'missing Lua observation is unknown')
spec.pause=function() error('partial stop') end
local failure=Stop.new(spec)
check(not pcall(failure.requestStop,'USER'),'partial pause exception is not success')
check(not failure.observeStop().bodyStopped,'failed pause cannot provide stopping evidence')
print('PASS '..checks..' business-stop boundary checks; native bodies NOT RUN')
