local suite=dofile('tests/lua/task-diagnostics-runtime-test.lua')
local f,Runtime=suite.f,suite.Runtime
local npc,actor,Probe=f.npc,f.actor,f.ctx.Probe
local checks,pauses,removes=0,0,0
local function check(value,message) checks=checks+1 assert(value,message) end
package.loaded['EmberRoutesProbe/Work']={
    pause=function(reason,id) assert(id=='npc-a') pauses=pauses+1 end,
    prepareRemoval=function() return not Runtime.current():owns('npc-a') end}
EmberRoutesProbeJava.removeIdleCarrier=function(id,body,a)
    assert(id=='npc-a' and body==npc and a==actor and not Runtime.current():owns(id)) removes=removes+1 return 'REMOVED'
end
local Commands=require 'EmberRoutesProbe/NpcCommands'
local square={getX=function() return 7 end,getY=function() return 0 end,getZ=function() return 0 end}
check(Commands.execute(actor,'move',square)=='QUEUED','debug move requests controlled body')
check(Commands.execute(actor,'remove')=='CARGO_OR_CONTROL_RETAINED' and removes==0,'active body cannot be removed')
suite.drain()
check(npc:getX()==7.5 and pauses==1,'controlled debug move reaches captured target and suspends work')
check(Commands.execute(actor,'stop')=='ALREADY_STOPPED' and pauses==2,'idle stop does not call legacy native command')
check(Commands.execute(actor,'remove')=='REMOVED' and removes==1,'idle confirmed body uses dedicated lifecycle operation')
suite.root.diagnosticRecovery={format=1,byNpc={['npc-a']={kind='ACTIONS',jobId='old',ids={999}}}}
check(Commands.execute(actor,'move',square)=='QUEUED','unknown asset obligation does not freeze safe movement') suite.drain()
check(suite.root.diagnosticRecovery.byNpc['npc-a'].jobId=='old','movement cannot overwrite unknown originals')
check(Commands.execute(actor,'remove')=='DIAGNOSTIC_RECONCILE_REQUIRED' and removes==1,'unknown originals block destructive body removal')
print('PASS '..checks..' controlled diagnostic command checks; removal bridge mocked')
