local checks=0
local function check(value,label) checks=checks+1 assert(value,label) end
local root={}
package.loaded['EmberRoutesProbe/ContainerRegistry']={data=function() return root end}
local status={jobId='craft',kind='PRODUCTION',state='ACTIVE',started=true}
local owns=true local submits=0
local runtime={accepting=function() return true end,status=function() return status end,owns=function() return owns end}
package.loaded['EmberRoutesProbe/TaskRuntime']={current=function() return runtime end}
local work={id='craft',generation=3,state='RUNNING'}
package.loaded['EmberRoutesProbe/BusinessJobs']={crafts=function() return {a=work} end}
package.loaded['EmberRoutesProbe/Production']={execute=function(_,command,_,id,options)
    assert(command=='resume' and id=='a' and options.nonPreemptive)
    submits=submits+1 owns=true status={jobId='craft',kind='PRODUCTION',state='PENDING',started=false}
    return 'QUEUED'
end}
local Jobs=require 'EmberRoutesProbe/TaskJobs'
local Record=require 'EmberRoutesProbe/SelfCareRecord'
local Resume=require 'EmberRoutesProbe/TaskResume'
local jobs=Jobs.current()
assert(jobs:create(Record.create('care','a')))
local function attempt()
    local j=jobs:get('care') j.payload.step='IDLE' j.payload.resume=nil j.effects='KNOWN'
    assert(jobs:update(j.id,j.revision,{payload=j.payload,effects='KNOWN'})) j=jobs:get('care')
    local p=assert(Record.begin(j,'EAT')) assert(jobs:update(j.id,j.revision,{payload=p}))
end
attempt()
check(Resume.prepare({},'a','care'),'recovery relation persists before requesting interruption')
local ref=jobs:get('care').payload.resume
check(ref.jobId=='craft' and ref.beforeGeneration==3 and ref.state=='REQUESTED','captures original identity and command epoch')
check(not Resume.resume({},'a','care'),'unconfirmed predecessor cannot resume')
work.generation=4 work.state='PAUSED' work.reason='SELF_CARE'
check(Resume.stopped({npcId='a',jobId='other',kind='PRODUCTION',state='CLOSED',reason='SELF_CARE',effects='KNOWN'}),
    'unrelated stop notification is harmless')
check(jobs:get('care').payload.resume.state=='REQUESTED','wrong Job cannot confirm handoff')
check(Resume.stopped({npcId='a',jobId='craft',kind='PRODUCTION',state='CLOSED',reason='SELF_CARE',effects='KNOWN'}),'stop confirmation persisted')
ref=jobs:get('care').payload.resume
check(ref.state=='STOP_CONFIRMED' and ref.generation==4,'binds stopped business generation instead of stale start generation')
owns=false status=nil
local done,why=Resume.resume({},'a','care')
check(not done and why=='QUEUED' and submits==1,'resume submits original Job non-preemptively')
check(not Resume.resume({},'a','care') and submits==1,'repeated resume while pending cannot double-submit')
-- Simulate saving before the resumed task starts: cancelled admission is retried,
-- never mistaken for a completed recovery merely because submit returned QUEUED.
owns=false status=nil
done,why=Resume.resume({},'a','care')
check(not done and why=='QUEUED' and submits==2,'cancelled pending admission keeps durable recovery obligation')
status={jobId='craft',kind='PRODUCTION',state='ACTIVE',started=true}
check(Resume.resume({},'a','care'),'actual started successor confirms restoration')
check(jobs:get('care').payload.resume.state=='RESTORED','restoration acknowledgement persists')
attempt() status={jobId='craft',kind='PRODUCTION',state='ACTIVE',started=true} owns=true
work.generation=5 work.state='RUNNING' work.reason=nil
assert(Resume.prepare({},'a','care'))
check(Resume.invalidate('a','USER_PAUSE'),'accepted user command supersedes old intent')
owns=false status=nil
check(Resume.resume({},'a','care') and submits==2,'superseded intent cannot revive paused work')
attempt() status={jobId='craft',kind='PRODUCTION',state='ACTIVE',started=true} owns=true
assert(Resume.prepare({},'a','care'))
work.state='PAUSED' work.reason='SELF_CARE' work.generation=6
assert(Resume.stopped({npcId='a',jobId='craft',kind='PRODUCTION',state='CLOSED',reason='SELF_CARE',effects='UNKNOWN'}))
owns=false status=nil
check(not Resume.resume({},'a','care') and submits==2,'unknown original effects block only automatic recovery')
check(jobs:get('care').effects=='KNOWN','unknown original effect does not invent consumption by personal routine')
attempt()
check(Resume.prepare({},'a','care') and jobs:get('care').payload.step=='STOP_CONFIRMED','idle NPC needs no fictitious public job')
check(Resume.resume({},'a','care'),'no predecessor needs no public reclaim')
attempt() status={jobId='craft',kind='PRODUCTION',state='ACTIVE',started=true} owns=true
work.state='RUNNING' work.generation=8 work.reason=nil
assert(Resume.prepare({},'a','care')) work.state='PAUSED' work.generation=9 work.reason='SELF_CARE'
check(Resume.prepareRecovery({state='CAPTURED',byNpc={a={jobId='craft',kind='PRODUCTION',reason='SELF_CARE',
    effects='KNOWN',bodyStopped=true,persisted=true,started=true}}}),'saved receipt repairs handoff without a later normal tick')
check(jobs:get('care').payload.resume.generation==9 and jobs:get('care').payload.step=='STOP_CONFIRMED',
    'repaired relation uses persisted stopped business facts')
local haul={id='haul',state='RUNNING',generation=10}
package.loaded['EmberRoutesProbe/Work']={record=function() return haul end}
package.loaded['EmberRoutesProbe/LaborStore']={recoveryGeneration=function() return {before=11,after=12} end}
attempt() status={jobId='haul',kind='TRANSFER',state='ACTIVE',started=true}
assert(Resume.prepare({},'a','care')) haul.state='PAUSED' haul.generation=11 haul.reason='SELF_CARE'
assert(Resume.stopped({npcId='a',jobId='haul',kind='TRANSFER',state='CLOSED',reason='SELF_CARE',effects='KNOWN'}))
haul.generation=12
check(Resume.prepareRecovery(nil) and jobs:get('care').payload.resume.generation==12,
    'only authoritative load increment remaps transfer generation')
haul.generation=13 assert(Resume.prepareRecovery(nil))
check(jobs:get('care').payload.resume.generation==12,'arbitrary newer business generation cannot be blessed')
root.executionSave={state='BLOCKED'}
local allowed,blocked=Resume.resume({},'a','care')
check(not allowed and blocked=='SAVE_RECONCILE_REQUIRED','failed save forbids automatic personal restoration')
root.executionSave=nil
-- Borrowed books retain custody while a newer explicit follow intent receives
-- a brief personal-supply interruption, then restore that same intent.
local loan=jobs:get('care')
loan.payload.step='IDLE' loan.payload.resume=nil
assert(jobs:update(loan.id,loan.revision,{payload=loan.payload})) loan=jobs:get('care')
local p=assert(Record.begin(loan,'STUDY'))
p.step='SETTLING' p.itemId=77 p.sourceId='shelf' p.settlementId='home' p.study={version=0} p.claims={'item:77'}
assert(jobs:update(loan.id,loan.revision,{payload=p,obligations={RETURN_ORIGINALS={itemId=77,sourceId='shelf'}}}))
status={jobId='craft',kind='PRODUCTION',state='ACTIVE',started=true} owns=true
check(not Resume.prepare({},'a','care'),'retained loan cannot use settlement recovery to preempt ordinary work')
local restored=0
package.loaded['EmberRoutesProbe/Companion']={exportState=function() return {id='a',jobId='follow',mode='FOLLOW'} end,
    restoreState=function(_,intent) assert(intent.mode=='FOLLOW' and intent.jobId=='follow') restored=restored+1 return true end}
status={jobId='follow',kind='COMPANION',state='ACTIVE',started=true}
check(Resume.prepare({},'a','care'),'retained loan can capture the newer active companion intent for survival relief')
assert(Resume.stopped({npcId='a',jobId='follow',kind='COMPANION',state='CLOSED',reason='SELF_CARE',effects='KNOWN'}))
check(jobs:get('care').obligations.RETURN_ORIGINALS.itemId==77,'companion stop acknowledgement cannot discard the borrowed original')
owns=false status=nil
Resume.resume({},'a','care')
check(restored==1 and jobs:get('care').payload.resume.state=='RESTORE_QUEUED','survival relief restores the current follow intent without claiming another order')
print('PASS '..checks..' personal recovery/command/save-window checks; native bodies mocked')
