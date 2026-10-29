-- Only the new timing/notification seams; synthetic clocks, no FPS claim.
local now,nanos=0,0
getTimestampMs=function() return now end
local callbacks={}
Events={OnTickEvenPaused={Add=function(fn) callbacks.paused=fn end}}
local count=0
local Even=require 'EmberRoutesProbe/EvenPaused'
Even.add(function() count=count+1 end)
for i=0,999 do now=i callbacks.paused() end
assert(count==20,'background readers run at 20Hz independently of render count')
now=5000 callbacks.paused()
assert(count==21,'missed intervals do not create a catch-up burst')
now=0 callbacks.paused()
assert(count==22,'clock reset does not strand background readers')

package.loaded['EmberRoutesProbe/Log']={write=function() end}
EmberRoutesProbeJava={diagnosticTimeNanos=function() return nanos end}
local Perf=require 'EmberRoutesProbe/RuntimeMetrics'
assert(Perf.start())
for _=1,20000 do Perf.measure('test',function() nanos=nanos+100000 end) end
local start=Perf.now() nanos=21000000000 Perf.finishTick(start)
local row=Perf.result().rows.test local bins,total=0,0
for _,n in pairs(row.hist) do bins=bins+1 total=total+n end
assert(row.calls==20000 and total==20000 and bins<=742,'histogram storage is bounded without losing call counts')
assert(row.max>0.099 and row.max<0.101,'single-call maximum remains exact')

local root={} local pending
local public,jobs=0,0
package.loaded['EmberRoutesProbe/ContainerRegistry']={data=function() return root end}
package.loaded['EmberRoutesProbe/Boot']={ready=true,runtimeReady=true}
package.loaded['EmberRoutesProbe/TaskRuntime']={current=function() return {accepting=function() return true end} end}
package.loaded['EmberRoutesProbe/LaborSignals']={watch=function(fn) pending=fn end,changed=function() end}
package.loaded['EmberRoutesProbe/PublicWork']={retireSettled=function() public=public+1 end}
package.loaded['EmberRoutesProbe/BusinessJobs']={retireSettled=function() jobs=jobs+1 return 0 end}
local Retirement=require 'EmberRoutesProbe/TaskRetirement'
now=0 Retirement.tick()
for i=1,1999 do now=i Retirement.tick() end
assert(public==1 and jobs==1,'unchanged ledgers do not trigger full retirement scans')
now=2000 Retirement.tick()
assert(public==2,'low-frequency fallback covers missing notifications')
pending() now=2100 Retirement.tick() assert(public==2,'notifications coalesce behind minimum spacing')
now=2250 Retirement.tick() assert(public==3,'changed work wakes before the next fallback')
root.executionSave={state='BLOCKED'} pending() now=2500 Retirement.tick()
assert(public==3,'save barrier still prevents retirement')
print('PASS cadence, bounded metrics, dirty retirement and save-barrier checks; native world mocked')
local Idle=require 'EmberRoutesProbe/IdleDiscovery'
local discovery=Idle.new() local checks=0
local function changed(w) checks=checks+1 return w.changed end
local watch={changed=false}
for t=0,10000,500 do
    assert(discovery:due('a',t,'home:1',1,changed))
    discovery:empty('a',t,'home:1',1,watch,true)
end
assert(not discovery:due('a',10500,'home:1',1,changed) and checks==0,'quiet idle skips work scans without checking unchanged dependencies')
assert(not discovery:due('a',11000,'home:1',2,changed) and checks==1,'unrelated notification does not wake this scope')
assert(discovery:due('b',11000,'home:1',2,changed),'another NPC keeps its independent discovery state')
watch.changed=true
assert(discovery:due('a',11500,'home:1',3,changed),'relevant inventory change wakes promptly')
watch.changed=false
discovery:empty('a',12000,'home:1',3,watch,true)
discovery:empty('a',22000,'home:1',3,watch,true,23000)
assert(not discovery:due('a',22500,'home:1',3,changed) and discovery:due('a',23000,'home:1',3,changed),
    'known retry deadline beats dormant fallback')
discovery:empty('a',23000,'home:1',3,watch,false)
assert(discovery:due('a',23100,'home:1',3,changed),'unknown observation cannot remain asleep')
discovery:empty('a',24000,'home:1',3,watch,true)
discovery:empty('a',34000,'home:1',3,watch,true)
assert(discovery:due('a',55000,'home:1',3,changed),'bounded fallback covers missed events')
discovery:empty('a',55000,'home:1',3,watch,true)
assert(discovery:due('a',55100,'home:2',3,changed),'command/catalog/policy stamp change wakes without inventory event')
print('PASS idle discovery sleep, scoped notification, retry, unknown and fallback seams')
