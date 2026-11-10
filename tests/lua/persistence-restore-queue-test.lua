-- Real startup queue; native snapshots/world loading are explicit host substitutes.
local checks,now,actors=0,0,0
local function check(value,message) checks=checks+1 assert(value,message) end
local root={}
local ids={'a','b','c'}
local calls,attempts,answers={}, {}, {}
local duringRestore
local actor={isDead=function() return false end,getCurrentSquare=function() return {} end}
function getSpecificPlayer() actors=actors+1 return actor end
function getTimestampMs() return now end
local Probe={ready=true,enabled=true,controlledExecution=true,hasJava=function() return true end}
local resets={}
function Probe.registerReset(name, fn) resets[name]=fn end
package.loaded['EmberRoutesProbe/Kernel/Boot']=Probe
package.loaded['EmberRoutesProbe/Kernel/Log']={write=function() end}
package.loaded['EmberRoutesProbe/Warehouse/ContainerRegistry']={data=function() return root end}
for _,name in ipairs({'Companion','Actions','PersistenceSamples','TaskDiagnostic'}) do
    package.loaded['EmberRoutesProbe/'..name]={}
end
package.loaded['EmberRoutesProbe/Runtime/ExitSave']={install=function() end}
package.loaded['EmberRoutesProbe/Runtime/TaskPersistence']={pending=function() return false end,
    tick=function() end,reset=function() end,
    restore=function(a,id)
        check(a==actor,'restore receives actual local actor')
        attempts[id]=(attempts[id] or 0)+1
        calls[#calls+1]={id=id,at=now}
        if duringRestore then duringRestore() end
        local sequence=answers[id]
        return sequence[math.min(attempts[id],#sequence)]
    end}
EmberRoutesProbeJava={workerCount=function() return #ids end,workerIdAt=function(i) return ids[i+1] end}
local Persistence=require 'EmberRoutesProbe/Runtime/Persistence'
local function tick(time) now=time Persistence.tick() end
local function begin(list,results)
    resets.Persistence() Probe.restorePending=true
    ids=list answers=results calls={} attempts={} now=0 duringRestore=nil
end
begin({'a','b','c'},{a={'RESTORE_TILE_UNAVAILABLE','RESTORE_TILE_UNAVAILABLE','CHECKPOINT_RESTORED'},
    b={'CHECKPOINT_RESTORED'},c={'RESTORE_BLOCKED corrupt'}})
tick(0) check(#calls==1 and calls[1].id=='a','one restore per tick')
tick(0) check(#calls==2 and calls[2].id=='b','second body on a separate tick')
tick(0) check(#calls==3 and calls[3].id=='c','hard failure gets one attempt')
tick(0) -- Finish the round and schedule its deferred member.
tick(1999) check(#calls==3,'deferred round waits two seconds')
tick(2000) check(attempts.a==2,'unavailable square gets a second attempt')
tick(2000)
tick(3999) check(attempts.a==2,'each deferred round retains its interval')
tick(4000) check(attempts.a==3,'third attempt can restore the original body')
tick(4000)
check(attempts.b==1 and attempts.c==1,'success and corruption never enter retry rounds')
local before,observed=#calls,actors
for _=1,100 do tick(100000) end
check(#calls==before and actors==observed,'finished queue has no native or actor polling')

begin({'a'},{a={'RESTORE_TILE_UNAVAILABLE'}})
tick(0) tick(0) tick(2000) tick(2000) tick(4000) tick(4000) tick(6000)
check(attempts.a==3,'unavailable saved square has a three-attempt ceiling')

begin({'a'},{a={'RESTORE_ALREADY_CONSUMED'}})
tick(0) tick(0) tick(2000)
check(attempts.a==1,'already consumed snapshot never gets another automatic attempt')

begin({'a'},{a={'RESTORE_TILE_UNAVAILABLE'}})
tick(0) tick(0) root={}
tick(2000) tick(4000)
check(attempts.a==1,'world replacement revokes old deferred restores')

begin({'a'},{a={'RESTORE_TILE_UNAVAILABLE'}})
tick(0) tick(0) resets.Persistence()
tick(2000)
check(attempts.a==1,'reset revokes delayed restore')

begin({'a'},{a={'RESTORE_TILE_UNAVAILABLE'}})
duringRestore=function() resets.Persistence() end
tick(0) tick(2000)
check(attempts.a==1,'reset inside a restore callback cannot requeue its old attempt')

begin({'a'},{a={'RESTORE_TILE_UNAVAILABLE'}})
duringRestore=function() root={} end
tick(0) tick(2000)
check(attempts.a==1,'world replacement inside restore cannot schedule another old-world attempt')

begin({}, {})
tick(0)
before=#calls
for _=1,10 do tick(2000) end
check(#calls==before,'empty roster performs no restore')
print('PASS '..checks..' real persistence restore-queue checks; native restore/disk NOT RUN')
