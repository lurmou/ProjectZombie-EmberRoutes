local Controller=require 'EmberRoutesProbe/TaskController'
local Evidence=require 'EmberRoutesProbe/TaskStopEvidence'
local n=0
local function check(v,m) n=n+1 assert(v,m) end
local c=Controller.new()
local stopped,persisted=false,false
local a={requestStop=function() stopped=true end,
    observeStop=function() return {bodyStopped=true,effects='UNKNOWN'} end,
    persistEffects=function() return persisted end}
local t=assert(c:request('a','work','WORK',a))
check(not c:dispatch(t,function() error('queued ran') end),'queued has no body')
check(not c:request('a','other','WORK',a),'one request per NPC')
c:step()
check(c:inspect(t).state=='ACTIVE','grant on step')
local b=assert(c:request('b','follow','FOLLOW',a)) c:step()
check(c:inspect(b).state=='ACTIVE','independent NPC')
local calls=0
check(c:dispatch(t,function()
    calls=calls+1
    c:requestStop(t,'USER')
    c:step()
    check(not c:dispatch(t,function() calls=calls+10 end),'reentrant dispatch denied')
end),'in-flight stop returns')
check(calls==1,'one effect')
c:step()
check(stopped and c:inspect(t).state=='STOPPING','unknown must be persisted')
check(not c:request('a','new','WORK',a),'cannot reassign unresolved')
persisted=true c:step()
check(c:inspect(t).state=='CLOSED','persisted unknown releases body')
local nextT=assert(c:request('a','escape','ESCAPE',a)) c:step()
check(not c:requestStop(t,'LATE'),'late ticket cannot stop successor')
check(c:inspect(nextT).state=='ACTIVE','successor remains active')
c:beginSave()
check(not c:request('c','work','WORK',a),'save admission closed')
check(not c:dispatch(nextT,function() calls=calls+10 end),'save fences effects')
check(not c:finishSave(true),'cannot reopen while bodies unresolved')
c:step()
check(not c:finishSave(false),'failed save stays closed')
check(not c:request('c','work','WORK',a),'failed save blocks admission')
check(c:finishSave(true),'explicit verified live-world recovery')
local q=assert(c:request('q','queued','WORK',a))
check(c:requestStop(q,'USER') and c:inspect(q).state=='CANCELLED','queued cancellation no body')
local bad={requestStop=function() error('stop failed') end,observeStop=a.observeStop,persistEffects=a.persistEffects}
local f=assert(c:request('f','bad','WORK',bad)) c:step() c:requestStop(f,'USER') c:step()
check(c:inspect(f).state=='STOPPING','stop failure not success')
check(not Evidence.validate({bodyStopped=true,effects='KNOWN',queueEmpty=true}), 'unpersisted evidence rejected')
local e=assert(c:request('e','effect-error','WORK',a)) c:step()
check(not c:dispatch(e,function() error('possibly committed') end),'effect exception fenced')
check(c:inspect(e).state=='STOPPING','exception cannot authorize replacement')
local e2=Evidence.validate({bodyStopped=false,effects='KNOWN',persisted=true})
check(not e2,'persisted effects do not prove body stopped')
c:retire()
check(not c:dispatch(f,function() end) and not c:request('x','x','WORK',a),'retired world fenced')
local stalled=Controller.new()
local blocked={requestStop=function() return false end,observeStop=function() error('must not observe rejected stop') end,
    persistEffects=function() error('must not persist rejected stop') end}
local pending=assert(stalled:request('p','p','WORK',blocked)) stalled:step()
stalled:requestStop(pending,'STOP') stalled:step()
check(stalled:inspect(pending).state=='STOPPING','false stop result stays blocked')
local bounded=Controller.new()
for i=1,256 do
    local queued=assert(bounded:request('n'..i,'j'..i,'WORK',a)) bounded:requestStop(queued,'CANCEL')
end
check(not bounded:request('overflow','overflow','WORK',a),'queue storage bounded before step')
bounded:step()
check(bounded:request('room','room','WORK',a)~=nil,'terminal queue entries reclaimed')
check(c:state(t)==c:inspect(t).state and stalled:state(pending)=='STOPPING','scalar state agrees with stopped/active ticket snapshots')
check(c:state({})==nil and c:state(nil)==nil,'scalar state never invents missing ticket status')
local scalar=Controller.new() local st=assert(scalar:request('scalar','scalar','WORK',a))
check(scalar:state(st)=='QUEUED','queued state available without full snapshot')
scalar:step() check(scalar:state(st)=='ACTIVE','grant updates scalar state immediately')
local dt=scalar:inspect(st) dt.state='tampered'
check(scalar:state(st)=='ACTIVE','scalar query does not expose mutable controller storage')
print('PASS '..n..' controller checks; native bodies/save NOT RUN')
