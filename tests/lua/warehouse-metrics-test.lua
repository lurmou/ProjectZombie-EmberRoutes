package.path="Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;"..package.path
local oldLog=package.loaded['EmberRoutesProbe/Log']
local logs=0 local logger=oldLog or {} local oldWrite=logger.write
logger.write=function() logs=logs+1 end package.loaded['EmberRoutesProbe/Log']=logger
local Metrics=require 'EmberRoutesProbe/WarehouseMetrics'
local previous=_G.EmberRoutesProbeJava
local reads,clock=0,0
EmberRoutesProbeJava={diagnosticTimeNanos=function() reads=reads+1 clock=clock+1000 return clock end}
local n=0 local function check(v,why) n=n+1 assert(v,why) end
check(Metrics.begin('ui.query')==nil and reads==0,'disabled sampling never calls the Java clock')
check(Metrics.start() and not Metrics.begin('unregistered.stage'),'sampling allows only bounded predefined stages')
for i=1,Metrics.LIMIT+10 do local started=Metrics.begin('ui.query') Metrics.finish('ui.query',started) end
local report=Metrics.stop()
check(report['ui.query'].count==Metrics.LIMIT and report['ui.query'].capped,'sample capacity is bounded')
check(report['ui.query'].averageMs==0.001 or math.abs(report['ui.query'].averageMs-0.001)<0.000001,'nanoseconds convert to milliseconds')
check(report['ui.query'].recentP95Ms==0.001,'recent percentile reflects the bounded sample window')
local calls=reads Metrics.begin('ui.query')
check(reads==calls and logs==1,'stop disables timers and emits one aggregate per sampled stage')
Metrics.start() check(not Metrics.report()['ui.query'],'new sampling session drops old measurements') Metrics.stop()
EmberRoutesProbeJava=previous logger.write=oldWrite package.loaded['EmberRoutesProbe/Log']=oldLog
print('PASS '..n..' bounded CPU metrics checks; GPU timing NOT RUN')
