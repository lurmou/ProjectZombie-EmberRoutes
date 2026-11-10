-- P0 pilot: NPC sleep in SelfCare (cross-game Factorio §1.3). An NPC with
-- no unfinished duty and no over-threshold need skips the idle section
-- (eligibility, choose, STUDY/LEISURE discovery) and only rechecks wake
-- conditions; a need crossing its unchanged enter threshold, unfinished
-- duty, a forced sleep order, or danger wakes it. The 1Hz pulse still
-- runs a full advance, so STUDY/LEISURE discovery keeps its 1.5s throttle
-- and leisure cadence is unchanged. Safety, active jobs, retry and
-- reconciliation above the sleep check never sleep.
-- Run from the repo root: lua tests/lua/p1-pilot-npc-sleep-care-test.lua
package.path="Contents/mods/EmberRoutesProbe/42/media/lua/client/?.lua;Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;"..
    "Contents/mods/EmberRoutesProbe/42/media/lua/client/?.lua;"..package.path
local checks=0
local function check(v,s) checks=checks+1 assert(v,s) end

-- NeedsPolicy enter pins live in tests/lua/p1-pilot-lowneeds-haul-test.lua
-- (canonical home); sleep wakes on choose(), it does not re-threshold it.

-- ---- Service fixture (one worker, controllable sample, counted gates) ----
local root={} local now=1000 local serial=0
local hunger,thirst,fatigue,endurance,safeSample=0.05,0.05,0.10,0.90,true
local medical=nil
local dutyRetained=false local dutyPending=false
local withdrawn=0
local checkCalls,studyCalls,leisureCalls,resourcesNewCalls,medicalBlocker=0,0,0,0,0
getTimestampMs=function() return now end
local actor={isDead=function() return false end} getSpecificPlayer=function() return actor end
local npc={isDead=function() return false end,getX=function() return 1 end,getY=function() return 1 end,
    getZ=function() return 0 end}
local members=dofile('tests/lua/membership-fixture.lua')(function() return {id='home'} end,{'a'})
local MS=package.loaded['EmberRoutesProbe/Settlement/MembershipService']
local realCheck=MS.check
MS.check=function(...) checkCalls=checkCalls+1 return realCheck(...) end
local Probe={hasPendingWork=function() return dutyPending end}
package.loaded['EmberRoutesProbe/Kernel/Boot']=Probe
package.loaded['EmberRoutesProbe/Kernel/Log']={write=function() end}
package.loaded['EmberRoutesProbe/Kernel/RuntimeMetrics']={active=function() return false end,
    measure=function(_,fn,...) return fn(...) end,measureSpan=function() end,now=function() return now end}
package.loaded['EmberRoutesProbe/Warehouse/ContainerRegistry']={data=function() return root end,
    id=function() serial=serial+1 return 'care'..serial end}
package.loaded['EmberRoutesProbe/Work/BusinessJobs']={hauls=function() return {tasks={},byNpc={},routes={}} end,
    crafts=function() return {} end,flush=function() end}
package.loaded['EmberRoutesProbe/Crafting/CraftRecord']={records=function() return {} end,resources=function() return {} end}
package.loaded['EmberRoutesProbe/Work/LaborProducers']={transfer=function() return true end}
package.loaded['EmberRoutesProbe/Work/LaborSignals']={watch=function() end,changed=function() end}
package.loaded['EmberRoutesProbe/Settlement/SettlementFacilities']={due=function() return false end,tick=function() end}
package.loaded['EmberRoutesProbe/Work/PublicWorkProviders']={retained=function() return dutyRetained end}
local runtime={accepting=function() return true end,owns=function() return false end,
    status=function() return nil end,submit=function(_,spec) return {state='PENDING'} end,
    inspect=function(_,h) return h end,stopJob=function() return true end}
package.loaded['EmberRoutesProbe/Runtime/TaskRuntime']={current=function() return runtime end}
package.loaded['EmberRoutesProbe/Runtime/Driver']={bindId=function(_,id) return {id=id,handle=npc} end}
package.loaded['EmberRoutesProbe/SelfCare/NeedsObserver']={sample=function(_,id,time)
    return {hunger=hunger,thirst=thirst,fatigue=fatigue,endurance=endurance,
        safe=safeSample,externalSafe=safeSample,observedAt=time,medical=medical}
end}
package.loaded['EmberRoutesProbe/SelfCare/SelfCareResources']={
    new=function(...)
        resourcesNewCalls=resourcesNewCalls+1
        return {step=function() return nil,true end}
    end,revalidate=function() return true end}
package.loaded['EmberRoutesProbe/SelfCare/MedicalCare']={observe=function() end,
    blocker=function() medicalBlocker=medicalBlocker+1 end,begin=function() return true end}
package.loaded['EmberRoutesProbe/Activity/ActivityService']={context=function() return nil end,
    leave=function() return false end,request=function() end}
package.loaded['EmberRoutesProbe/Activity/SocialCoordinator']={withdraw=function() withdrawn=withdrawn+1 end,
    pending=function() return nil end}
package.loaded['EmberRoutesProbe/Leisure/StudyService']={candidate=function(...)
        studyCalls=studyCalls+1 return nil,true
    end,valid=function() return true end,offer=function() end,changed=function() end}
package.loaded['EmberRoutesProbe/Leisure/LeisureService']={candidate=function(...)
        leisureCalls=leisureCalls+1 return nil,true
    end,consumeResume=function() return true end,valid=function() return true end,
    failed=function() end,note=function() end,reset=function() end,offer=function() end,
    probeable=function() return false end,workReady=function() end,invalidate=function() end}
package.loaded['EmberRoutesProbe/SelfCare/ReposeSites']={new=function()
        return {step=function() return nil,true,'SITE_UNAVAILABLE' end}
    end,prepare=function() return nil end,keys=function() return {} end}
EmberRoutesProbeJava={workerCount=function() return 1 end,workerIdAt=function() return 'a' end}
local Service=require 'EmberRoutesProbe/SelfCare/SelfCare'
Service.install()
local function tick() now=now+200 Service.tick() end
local function fallAsleep()
    for _=1,3 do tick() end
    check(Service.sleeping('a')~=nil,'NPC falls asleep with no duty and satisfied needs')
end
local function fresh()
    root={} hunger,thirst,fatigue,endurance,safeSample=0.05,0.05,0.10,0.90,true
    medical=nil dutyRetained=false dutyPending=false
end

-- Sleep entry + skip: between 1Hz pulses no eligibility check and no
-- STUDY/LEISURE discovery runs. Entry happens on the first tick
-- (now=1200, sleepUntil=2200); the snapshot below is at now=1600, so
-- exactly the next two 200ms ticks are quiet and the third is the pulse.
fresh()
fallAsleep()
local c0,s0,l0=checkCalls,studyCalls,leisureCalls
for _=1,2 do tick() end
check(checkCalls==c0,'sleeping NPC runs no eligibility check between pulses')
check(studyCalls==s0 and leisureCalls==l0,'sleeping NPC runs no STUDY/LEISURE discovery between pulses')
check(Service.sleeping('a')~=nil,'NPC is still asleep after quiet ticks')

-- 1Hz pulse: the next full advance runs eligibility again and re-sleeps;
-- STUDY/LEISURE discovery still waits for its own 1.5s throttle.
tick()
check(checkCalls>c0,'the 1Hz pulse runs a full advance (eligibility again)')
check(studyCalls==s0 and leisureCalls==l0,'the pulse still respects the 1.5s discovery throttle')
check(Service.sleeping('a')~=nil,'NPC re-sleeps after the pulse finds nothing')
for _=1,5 do tick() end
check(studyCalls>s0 and leisureCalls>l0,'STUDY/LEISURE discovery still runs on a later pulse (leisure not starved)')

-- Wake on need: hunger crossing enter wakes within 6 ticks (one 1Hz
-- sample period) and the EAT path starts.
fresh()
fallAsleep()
hunger=0.30
local r0=resourcesNewCalls
local woken=false
for _=1,6 do tick() if Service.sleeping('a')==nil then woken=true break end end
check(woken,'need crossing its threshold wakes the sleeper within 6 ticks')
check(resourcesNewCalls>r0,'need-woken NPC starts self-care resource discovery')

-- Wake on medical need.
fresh()
fallAsleep()
medical={needsCare=true}
woken=false
for _=1,6 do tick() if Service.sleeping('a')==nil then woken=true break end end
check(woken,'medical need wakes the sleeper within 6 ticks')

-- Wake on unfinished duty.
fresh()
fallAsleep()
dutyRetained=true
tick()
check(Service.sleeping('a')==nil,'unfinished duty wakes the sleeper on the next visit')

-- Wake on a player sleep order (forced sleep is a wake condition, and the
-- order itself is honoured by the normal path, not swallowed by sleep).
fresh()
fallAsleep()
EmberRoutesProbeJava.reposeWithControl=function() return true end
EmberRoutesProbeJava.reposeAtWithControl=function() return true end
check(Service.force('a','SLEEP')==true,'player sleep order accepted')
tick()
check(Service.sleeping('a')==nil,'forced sleep order wakes the sleeper')
EmberRoutesProbeJava.reposeWithControl=nil EmberRoutesProbeJava.reposeAtWithControl=nil

-- Safety is never slept: danger still withdraws the NPC every visit.
fresh()
fallAsleep()
local w0=withdrawn
safeSample=false
for _=1,3 do tick() end
check(withdrawn>w0,'danger still withdraws a sleeping NPC (safety gate runs first)')
print('PASS '..checks..' NPC sleep self-care checks; SelfCare thresholds unchanged')
