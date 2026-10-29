-- Installed Kahlua; count eliminated work rather than invent game timings.
local checks=0
local function check(v,m) checks=checks+1 assert(v,m) end
local Queue=require 'EmberRoutesProbe/PrecheckQueue'
local empty=Queue.new(4)
local clocks=0
local function clock() clocks=clocks+1 return 0 end
for _=1,1000 do
    local ops,slices,ms=empty:step(128,function() error('empty validation') end,function() error('empty completion') end,clock)
    check(ops==0 and slices==0 and ms==0,'empty queue has no work')
end
check(clocks==0,'empty queue never queries clock')

local logs={}
package.loaded['EmberRoutesProbe/Log']={write=function(k,s) logs[#logs+1]=k..' '..s end}
package.loaded['EmberRoutesProbe/Build']={version='test'}
local reads,nanos=0,0
local function noop() end
local missing
local bridge=setmetatable({}, {__index=function(_,key)
    reads=reads+1
    if key==missing then return nil end
    if key=='version' then return function() return 'test' end end
    if key=='begin' then return function() return 'READY' end end
    if key=='diagnosticTimeNanos' then return function() return nanos end end
    return noop
end})
EmberRoutesProbeJava=bridge
SandboxVars={EmberRoutes={CarrierProbe=true}}
function getText(k) return k end
local Probe=require 'EmberRoutesProbe/Boot'
for _,name in ipairs({'prepareTaskRecovery','beginTasks','tickTasks','resetTasks','savePersistentCarrier',
    'beforeStockSave','afterStockSave','resetStock'}) do Probe[name]=noop end
Probe.begin()
check(Probe.ready and Probe.runtimeReady,'complete native bridge accepted')
local before=reads
for _=1,1000 do check(Probe.hasJava(),'cached availability') end
check(reads==before,'successful startup removes repeated native capability lookups')
missing='removeIdleCarrier'
Probe.begin()
check(not Probe.ready and Probe.failureCode=='MISSING_JAVA','restart always revalidates same bridge identity')
missing=nil Probe.begin()
EmberRoutesProbeJava={}
check(not Probe.hasJava(),'bridge replacement invalidates cache')
EmberRoutesProbeJava=bridge

local Metrics=require 'EmberRoutesProbe/RuntimeMetrics'
check(not Metrics.active(),'profiling disabled by default')
check(Metrics.start(),'explicit profiling start')
local ran={}
for _,name in ipairs({'Persistence','SelfCare','Tasks','Crafting','Actions','Haul','Work','Companion','Logistics','PublicWork','Retirement','CraftView'}) do
    Probe['tick'..name]=function() ran[#ran+1]=name nanos=nanos+100000 end
end
Probe.tick()
check(#ran==12 and ran[1]=='Persistence' and ran[12]=='CraftView','profile preserves service order')
nanos=21000000000 Probe.tick()
check(not Metrics.active() and Metrics.result().ticks==2,'sampling stops after bounded interval')
check(Metrics.result().rows.SelfCare.calls==2,'child call counts recorded')
check(Metrics.result().rows.SelfCare.max>0,'high resolution child time recorded')
local logCount=#logs Probe.tick()
check(#logs==logCount and #ran==36,'normal ticks run all services without profiler logging')
check(Metrics.start(),'sampling may restart')
Metrics.reset() check(not Metrics.active() and Metrics.result()==nil,'world reset drops sample')

-- No pending restore/save must not touch the player or native bridge.
for _,name in ipairs({'Companion','Actions','PersistenceSamples','TaskDiagnostic'}) do
    package.loaded['EmberRoutesProbe/'..name]={}
end
local pending=false local recovery=0
package.loaded['EmberRoutesProbe/TaskPersistence']={pending=function() return pending end,tick=function() recovery=recovery+1 pending=false end}
local actors=0
function getSpecificPlayer() actors=actors+1 return {isDead=function() return false end,getCurrentSquare=function() return {} end} end
Probe.restorePending=false
local Persistence=require 'EmberRoutesProbe/Persistence'
for _=1,1000 do Persistence.tick() end
check(actors==0 and recovery==0,'idle persistence never queries player or recovery')
pending=true Persistence.tick()
check(actors==1 and recovery==1,'pending save recovery retains next-tick execution')
print('PASS runtime idle checks='..checks)
