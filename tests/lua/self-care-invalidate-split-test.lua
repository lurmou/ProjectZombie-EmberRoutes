-- E-09: epoch/ref-state split repro. Resume.invalidate bumps the care epoch
-- first and only then persists ref.state='INVALIDATED' via Commit.update. When
-- that commit fails (here: KERNEL_UNAVAILABLE), the epoch has moved but the
-- stored ref is still REQUESTED: blocksWork (epoch gate) has released while
-- SelfCare.settle (state gate) still waits for the predecessor to stop.
-- The test fails while settle only looks at state, and passes once settle
-- uses the same epoch-aware fact as blocksWork (Resume.pending).
-- Production TaskResume + production SelfCare; only the kernel bridge,
-- observer, medical hook, activity context, driver and claim store are
-- doubles. The frozen dec003-pre-kernel-task-resume fixture is untouched:
-- its invalidate uses Jobs.current():update, a different failure surface.
local checks=0
local function check(value,label) checks=checks+1 assert(value,label) end
local root={}
local kernelAvailable=true
package.loaded['EmberRoutesProbe/Kernel/LaborKernelAvailability']={validate=function() return kernelAvailable end}
package.loaded['EmberRoutesProbe/Warehouse/ContainerRegistry']={data=function() return root end,
    id=function() return 'care' end}
local runtime={accepting=function() return true end,status=function() return nil end,owns=function() return false end}
package.loaded['EmberRoutesProbe/Runtime/TaskRuntime']={current=function() return runtime end}
package.loaded['EmberRoutesProbe/Runtime/Driver']={bindId=function(_,id) return {id=id,handle={}} end}
package.loaded['EmberRoutesProbe/SelfCare/NeedsObserver']={sample=function(_,_,now)
    return {safe=true,externalSafe=true,hunger=0.1,thirst=0.1,fatigue=0.1,endurance=0.9,observedAt=now} end}
package.loaded['EmberRoutesProbe/SelfCare/MedicalCare']={observe=function() end}
package.loaded['EmberRoutesProbe/Activity/ActivityService']={context=function() return nil end}
local Jobs=require 'EmberRoutesProbe/Runtime/TaskJobs'
-- Claim store double: no Java kernel. mutateJob applies the patch through the
-- real JobStore, so revision checks and detached copies behave as production.
package.loaded['EmberRoutesProbe/Work/LaborStore']={
    claimPersonal=function() return {resources={}} end,
    finishPersonal=function() return true end,
    getToken=function() return nil end,
    mutateJob=function(id,revision,payload,mutation)
        return Jobs.current():update(id,revision,{payload=payload,state=mutation.state,
            effects=mutation.effects,obligations=mutation.obligations})
    end,
    data=function() end,
}
getTimestampMs=function() return 1000 end
getSpecificPlayer=function() return {isDead=function() return false end} end
EmberRoutesProbeJava={workerCount=function() return 1 end,workerIdAt=function() return 'a' end}
local Record=require 'EmberRoutesProbe/SelfCare/SelfCareRecord'
local Resume=require 'EmberRoutesProbe/Runtime/TaskResume'
local Service=require 'EmberRoutesProbe/SelfCare/SelfCare'
local jobs=Jobs.current()
assert(jobs:create(Record.create('care','a')))
local job=jobs:get('care')
job.payload.step='IDLE'
assert(jobs:update(job.id,job.revision,{payload=job.payload}))
job=jobs:get('care')
local p=assert(Record.begin(job,'EAT'))
p.resume={jobId='craft',kind='PRODUCTION',epoch=Resume.epoch('a'),state='REQUESTED'}
assert(jobs:update(job.id,job.revision,{payload=p}))
check(jobs:get('care').payload.resume.state=='REQUESTED','predecessor stop pending before invalidation')
-- The kernel goes away: Commit.update now fails KERNEL_UNAVAILABLE.
kernelAvailable=false
local ok,why=Resume.invalidate('a','WORK_COMMAND')
check(not ok,'failed Commit.update is reported, not swallowed: '..tostring(why))
check(Resume.epoch('a')==1,'epoch advanced before the failed ref write')
local stored=jobs:get('care').payload.resume
check(stored.state=='REQUESTED','failed ref write leaves the stored ref REQUESTED')
check(not Resume.pending(stored,'a'),'epoch gate already treats the superseded ref as dead')
-- blocksWork still returns true here, but only via its step~='IDLE' gate, not
-- via pending(): the epoch gate (pending) and settle's state gate disagree
-- about the same ref, which is the split this test pins down.
-- Kernel back: the tick must settle the attempt instead of waiting forever
-- for a predecessor stop that the superseded intent no longer needs.
kernelAvailable=true
Service.tick()
check(jobs:get('care').payload.step=='IDLE','tick settles instead of stalling on PREDECESSOR_STOP_PENDING')
print('PASS '..checks..' invalidate/commit-failure split checks; production TaskResume/SelfCare')
