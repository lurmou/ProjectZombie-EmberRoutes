-- Real recurring Job, claims, BT and stop adapter; native queue mocked.
local root={} local hours=1 local now=0
DebugLog={log=function() end}
ZombRand=function() return 5000 end
dofile('tests/lua/membership-fixture.lua')(function() return {id='home',revision=1} end,{'a'})
getTimestampMs=function() return now end getGameTime=function() return {getWorldAgeHours=function() return hours end} end
package.loaded['EmberRoutesProbe/ContainerRegistry']={data=function() return root end}
package.loaded['EmberRoutesProbe/BusinessJobs']={hauls=function() return {tasks={},byNpc={},routes={}} end,flush=function() end}
package.loaded['EmberRoutesProbe/CraftRecord']={records=function() return {} end}
package.loaded['EmberRoutesProbe/Boot']={}
package.loaded['EmberRoutesProbe/CraftSupply']={}
package.loaded['EmberRoutesProbe/WorkTransfer']={}
package.loaded['EmberRoutesProbe/Companion']={exportState=function() return {mode='HOLD'} end}
package.loaded['EmberRoutesProbe/SettlementLedger']={view=function() return {id='home'} end}
package.loaded['EmberRoutesProbe/SettlementGeometry']={inside=function() return true end}
package.loaded['TimedActions/ISEatFoodAction']=true package.loaded['TimedActions/ISDrinkFluidAction']=true
package.loaded['TimedActions/ISBaseTimedAction']=true
local queued
local npc={isDead=function() return false end,getX=function() return 1 end,getY=function() return 1 end,
    getZ=function() return 0 end,getInventory=function() return {} end}
ISTimedActionQueue={queues={},hasAction=function(a) return a==queued end}
local function empty() queued=nil ISTimedActionQueue.queues[npc]={queue={}} end
ISBaseTimedAction={new=function(_,character) return {character=character,
    forceComplete=function(self) self:complete() self:perform() end,forceStop=function(self) self:stop() end} end,
    stop=empty,perform=empty}
local body={current=function() return true end,retained=function() return true end,
    add=function(a) queued=a ISTimedActionQueue.queues[npc]={queue={a},current=a} a:start() return true end,
    clear=function() if queued then queued:stop() end empty() return true end,stop=function() return true end}
local Jobs=require 'EmberRoutesProbe/TaskJobs'
local Record=require 'EmberRoutesProbe/SelfCareRecord'
local Store=require 'EmberRoutesProbe/LaborStore'
local job=Record.create('j','a') job.payload=Record.begin(job,'LEISURE')
job.payload.membershipRevision=1 job.payload.settlementRevision=1
job.payload.step='STOP_CONFIRMED' job.payload.settlementId='home'
job.payload.leisure={format=1,activity='OBSERVE',hours=hours}
assert(Jobs.current():create(job)) job=Jobs.current():get('j')
assert(Store.claimPersonal(job))
local budget={nodes=16,paths=1,scan=32}
local spec=require('EmberRoutesProbe/SelfCareExecution').new({}, {id='a',handle=npc},job,nil,function() return budget end,false,nil,function() return true end)
assert(spec.nonPreemptive and spec.validate()) assert(spec.start(body))
spec.tick() assert(queued and not spec.finished())
require('EmberRoutesProbe/LeisureService').review=function() return true end
hours=hours+1
for _=1,200 do now=now+100 if queued then queued:update() end end
budget.nodes=16 spec.tick() assert(spec.finished())
local controller={inspect=function() return {state='STOPPING',npcId='a',jobId='j'} end,
    bodySnapshot=function() return {available=true,nativeStopped=true} end,stopBody=function() return true end}
local stop=spec.stopAdapter(controller,function() return {} end)
assert(stop.requestStop('COMPLETED')) local fact=stop.observeStop()
assert(fact.bodyStopped and fact.effects=='KNOWN' and stop.persistEffects(fact))
local saved=Jobs.current():get('j')
assert(saved.payload.step=='IDLE' and #saved.payload.claims==0 and saved.effects=='KNOWN')
assert(saved.payload.leisureMemory.cooldowns.OBSERVE==hours)
assert(Record.valid(saved),'real persisted routine remains loadable after idle episode')
print('P3.5 execution: real Job/claims/BT admission, native action, stop evidence, durable cooldown')

local care=require 'EmberRoutesProbe/SelfCare'
assert(care.prepareRecovery(nil))
assert(Jobs.current():get('j').payload.step=='IDLE','settled leisure stays settled on load')
saved=Jobs.current():get('j') local p=saved.payload p.step='ACTING' p.leisure.finished=nil p.leisure.applied=nil
assert(Jobs.current():update(saved.id,saved.revision,{payload=p}))
assert(care.prepareRecovery(nil))
assert(Jobs.current():get('j').payload.step=='STOP_CONFIRMED','known non-asset leisure cancels on load, never resumes conversation')
saved=Jobs.current():get('j') p=saved.payload p.step='ACTING' p.leisure.applying=true
assert(Jobs.current():update(saved.id,saved.revision,{payload=p}))
assert(care.prepareRecovery(nil))
assert(Jobs.current():get('j').effects=='UNKNOWN','interrupted effect intent quarantined without replay')
print('P3.5 actual recovery: settled unchanged, in-progress cancelled, effect intent UNKNOWN')
