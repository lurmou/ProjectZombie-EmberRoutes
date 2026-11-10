-- Probe.invalidateCare wiring (E-12): Resume.install() publishes the entry,
-- calling it bumps the care epoch and marks the ref INVALIDATED, a second
-- install() is a no-op, and the pre-existing Probe.taskStopped chain still
-- runs (previous handler first, then Resume.stopped).
-- Production TaskResume + real JobStore/SelfCareCommit/LaborJobCommit; only
-- the Java bridge is a host stand-in (laborMutate applies the mutation to
-- the Lua store) and the LaborStore token/data layer is stubbed (see below).
-- Game/Java execution, disk reload and performance UNVERIFIED.
local checks=0
local function check(value,label) checks=checks+1 assert(value,label) end

local root={}
package.loaded['EmberRoutesProbe/Warehouse/ContainerRegistry']={data=function() return root end}
local status={jobId='craft',kind='PRODUCTION',state='ACTIVE',started=true}
local owns=true
local runtime={accepting=function() return true end,status=function() return status end,owns=function() return owns end}
package.loaded['EmberRoutesProbe/Runtime/TaskRuntime']={current=function() return runtime end}
local work={id='craft',generation=3,state='RUNNING'}
package.loaded['EmberRoutesProbe/Work/BusinessJobs']={crafts=function() return {a=work} end}
package.loaded['EmberRoutesProbe/Crafting/Production']={execute=function() return 'QUEUED' end}
-- Minimal bridge stand-in: the real Commit path dispatches laborMutate to
-- Java, which owns the durable write. Here the host applies the same
-- mutation to the Lua JobStore so the ref marking is observable. The
-- LaborStore token/data layer is stubbed (its world-load recovery would
-- otherwise adopt the bare test ledger); TaskResume, SelfCareCommit,
-- LaborJobCommit dispatch and the JobStore itself are all production code.
local Commit=require 'EmberRoutesProbe/Work/LaborJobCommit'
local StubStore={data=function() return root end,getToken=function() return nil end}
Commit.install(StubStore,{},function() return 'test:claim' end,function() end)
package.loaded['EmberRoutesProbe/Work/LaborStore']=StubStore
EmberRoutesProbeJava={
    laborMutate=function(jobs,owner,claims,contracts,clean,id,revision,payload,mutation)
        local live=jobs:get(id)
        if not live or live.revision~=revision then return {ok=false,result='STALE_REVISION'} end
        local ok,next=jobs:update(id,revision,{payload=payload,state=mutation.state,
            effects=mutation.effects,obligations=mutation.obligations})
        return {ok=ok,result=ok and next or 'TASK_WRITE_FAILURE'}
    end,
    laborCreate=function() return {ok=true,result='x'} end,
    laborCancel=function() return {ok=false,result='TASK_WRITE_FAILURE'} end}

local Probe=require 'EmberRoutesProbe/Kernel/Boot'
local Jobs=require 'EmberRoutesProbe/Runtime/TaskJobs'
local Record=require 'EmberRoutesProbe/SelfCare/SelfCareRecord'
local Resume=require 'EmberRoutesProbe/Runtime/TaskResume'

-- The 13 centralized reason values keep their exact literals (E-05).
local Reasons=Resume.Reasons
for _,pair in ipairs({'CLEAR','WORK_COMMAND','PRODUCTION_COMMAND','MEMBERSHIP_COMMAND',
    'COMPANION_COMMAND','USER','STOP','MOVE','REMOVE','COMPANION_ORDER','ACTION_ORDER',
    'HAUL_ORDER','PERSISTENCE_SAMPLE'}) do
    check(Reasons[pair]==pair,'reason constant '..pair..' keeps its literal')
end

check(Probe.invalidateCare==nil,'no care entry before install')
check(not Probe.careProtocolInstalled,'protocol not installed before install')

-- A previous taskStopped handler must survive install(): install() wraps it,
-- it does not replace it.
local chain={}
Probe.taskStopped=function(fact) chain[#chain+1]=fact return true end

Resume.install()
check(Probe.invalidateCare==Resume.invalidate,'install publishes invalidateCare')
check(Probe.careProtocolInstalled,'install marks the protocol installed')
check(type(Probe.prepareCareRecovery)=='function','install also publishes prepareCareRecovery')

local jobs=Jobs.current()
assert(jobs:create(Record.create('care','a')))
local function attempt()
    local j=jobs:get('care') j.payload.step='IDLE' j.payload.resume=nil j.effects='KNOWN'
    assert(jobs:update(j.id,j.revision,{payload=j.payload,effects='KNOWN'})) j=jobs:get('care')
    local p=assert(Record.begin(j,'EAT')) assert(jobs:update(j.id,j.revision,{payload=p}))
end
attempt()
assert(Resume.prepare({},'a','care'),'prepare builds a REQUESTED ref before invalidation')
local ref=jobs:get('care').payload.resume
check(ref.state=='REQUESTED' and ref.epoch==0,'prepared ref starts REQUESTED at epoch 0')

check(Probe.invalidateCare('a',Reasons.WORK_COMMAND),'installed entry accepts a care invalidation')
check(Resume.epoch('a')==1,'invalidateCare bumps the care epoch')
ref=jobs:get('care').payload.resume
check(ref.state=='INVALIDATED' and ref.reason==Reasons.WORK_COMMAND,
    'invalidateCare marks the ref INVALIDATED with the passed reason')
local done,why=Resume.resume({},'a','care')
check(done and why=='INTENT_SUPERSEDED','invalidated intent reports superseded instead of resuming')

-- Invalid ids refuse without touching the epoch.
check(not Probe.invalidateCare('',Reasons.CLEAR),'empty id refuses invalidation')
check(Resume.epoch('a')==1,'refused invalidation leaves the epoch alone')

-- install() is idempotent: the wrapped chain and the published entry are
-- the same functions after a second call.
local installedStopped,installedInvalidate=Probe.taskStopped,Probe.invalidateCare
Resume.install()
check(Probe.taskStopped==installedStopped and Probe.invalidateCare==installedInvalidate,
    'second install leaves the taskStopped chain and invalidateCare untouched')

-- The wrapped taskStopped chain still runs: previous handler first, then
-- Resume.stopped confirms the fresh predecessor.
attempt() status={jobId='craft',kind='PRODUCTION',state='ACTIVE',started=true} owns=true
work.generation=5 work.state='RUNNING' work.reason=nil
assert(Resume.prepare({},'a','care'))
ref=jobs:get('care').payload.resume
check(ref.state=='REQUESTED' and ref.epoch==1,'fresh prepare reuses the bumped epoch')
work.state='PAUSED' work.reason='SELF_CARE' work.generation=6
local stateAtChain
local seen=Probe.taskStopped
Probe.taskStopped=function(fact)
    stateAtChain=jobs:get('care').payload.resume.state
    return seen(fact)
end
local fact={npcId='a',jobId='craft',kind='PRODUCTION',state='CLOSED',reason='SELF_CARE',effects='KNOWN'}
check(Probe.taskStopped(fact),'wrapped taskStopped still reports success')
check(#chain==1 and chain[1]==fact,'previous taskStopped handler still runs')
check(stateAtChain=='REQUESTED','previous handler runs before Resume.stopped')
check(jobs:get('care').payload.resume.state=='STOP_CONFIRMED',
    'Resume.stopped still confirms the predecessor after the chain')
print('PASS '..checks..' Probe.invalidateCare install/epoch/idempotent-chain checks; Java NOT RUN')
