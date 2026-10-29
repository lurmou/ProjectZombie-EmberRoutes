local f=dofile('tests/lua/repose-sites-test.lua')
-- Native bed entry is covered by self-care-repose-test; this fixture isolates
-- real routine/claim/stop integration from animation and pathfinding.
package.loaded['EmberRoutesProbe/Log']={write=function() end}
package.loaded['EmberRoutesProbe/SleepBed']={move=function() return {kind='Action',run=function() return 'Success' end} end,
    posture=function(_,object) return {object=object,enter=function() return 'Success' end,leave=function() return true end} end}
f.advance()
local checks=0 local function check(v,s) checks=checks+1 assert(v,s) end
package.loaded['EmberRoutesProbe/LaborStore']=nil
package.loaded['EmberRoutesProbe/BusinessJobs']={hauls=function() return {tasks={},byNpc={},routes={}} end,flush=function() end}
package.loaded['EmberRoutesProbe/CraftRecord']={records=function() return {} end}
local Store=require 'EmberRoutesProbe/LaborStore'
f.resourceProxy.resourceOwner=function(key) return Store.resourceOwner(key) end
for _,name in ipairs({'ISInventoryTransferAction','ISEatFoodAction','ISDrinkFluidAction'}) do package.loaded['TimedActions/'..name]=true end
package.loaded['EmberRoutesProbe/CraftSupply']={}
package.loaded['EmberRoutesProbe/SelfCareResources']={}
local main={getItems=function() return f.list({}) end}
local current=f.square(0,1) current.canReachTo=function() return true end
local asleep,resting,bed=false,false,nil local fatigue=0.9 local live,retained=true,true
local entered,exited=0,0
f.npc.getCurrentSquare=function() return current end
f.npc.getInventory=function() return main end
f.npc.isDead=function() return false end
f.npc.isAsleep=function() return asleep end f.npc.isResting=function() return resting end
f.npc.getBed=function() return bed end
f.npc.getStats=function() return {get=function() return fatigue end} end
CharacterStat={FATIGUE='fatigue',ENDURANCE='endurance'}
getGameTime=function() return {getWorldAgeHours=function() return 10 end} end
ISTimedActionQueue={queues={[f.npc]={queue={}}}}
local Jobs=require 'EmberRoutesProbe/TaskJobs' local jobs=Jobs.current()
local Record=require 'EmberRoutesProbe/SelfCareRecord'
assert(jobs:create(Record.create('care-a','a'))) Store.data()
local Sites=f.sites
local body={current=function() return live end,retained=function() return retained end,
 stop=function() return true end,clear=function() asleep=false resting=false bed=nil return true end,
 repose=function(kind,enter,object,quality)
  if not retained or enter and not live then return false end
  if enter then assert(object==f.furniture and quality=='goodBed') bed=object asleep=kind=='SLEEP' resting=kind=='REST' entered=entered+1
  else if asleep or resting then exited=exited+1 end asleep=false resting=false bed=nil end return true
 end}
local Execute=require 'EmberRoutesProbe/SelfCareExecution'
local controller={inspect=function() return {state='STOPPING',npcId='a',jobId='care-a'} end,
 stopBody=function() return true end,
 bodySnapshot=function() return {available=true,nativeStopped=not asleep and not resting and bed==nil} end}
local function start()
 live,retained=true,true fatigue=0.9
 local request=Sites.new(f.actor,f.npc,'a','SLEEP') local candidate
 for _=1,1000 do local done candidate,done=request:step(4) if done then break end end
 assert(candidate)
 local proof=assert(Sites.prepare(candidate,f.actor,f.npc,'a','SLEEP'))
 local job=jobs:get('care-a') local p=assert(Record.begin(job,'SLEEP')) p.step='STOP_CONFIRMED' p.site=proof p.claims=Sites.keys(proof,'SLEEP')
 assert(jobs:update(job.id,job.revision,{payload=p})) job=jobs:get(job.id) assert(Store.claimPersonal(job))
 local spec=Execute.new(f.actor,{id='a',handle=f.npc},job,nil,function() return {nodes=16,scan=32,paths=1} end)
 assert(spec.validate()) assert(spec.start(body)) spec.tick()
 return spec,proof
end
local function stop(spec)
 live=false local adapter=spec.stopAdapter(controller,function() return {} end)
 assert(adapter.requestStop('SAVE')) local fact=adapter.observeStop()
 assert(fact.bodyStopped) assert(adapter.persistEffects(fact)) retained=false return fact
end
local revision=Sites.view(f.actor,f.furniture).revision
assert(Sites.configure(f.actor,f.furniture,revision,'ASSIGNED','a')=='SITE_POLICY_SAVED')
local spec,proof=start()
check(asleep and bed==f.furniture and entered==1,'actual personal tree enters controlled furniture sleep with original object and quality')
check(Store.resourceOwner(Sites.keys(proof,'SLEEP')[2]).taskId=='care-a','whole furniture reserved through the actual claim authority')
local view=Sites.view(f.actor,f.furniture)
assert(Sites.configure(f.actor,f.other,view.revision,'DISABLED')=='SITE_POLICY_SAVED')
spec.tick()
check(spec.finished() and not asleep and not bed and exited==1,'policy change on another part wakes and exits the old attempt')
check(Store.resourceOwner(Sites.keys(proof,'SLEEP')[1])~=nil,'slot is retained until stopped effects are persisted')
check(stop(spec).effects=='KNOWN' and #jobs:get('care-a').payload.claims==0
 and not Store.resourceOwner(Sites.keys(proof,'SLEEP')[1]),'confirmed stop releases only original furniture claims')
local saved=jobs:get('care-a')
check(saved.payload.step=='IDLE' and saved.payload.reason=='SITE_CHANGED','known policy interruption leaves routine ready for another attempt')
view=Sites.view(f.actor,f.furniture) assert(Sites.configure(f.actor,f.furniture,view.revision,'PUBLIC')=='SITE_POLICY_SAVED')
local successor,nextProof=start() local before=exited
-- The predecessor remains a Lua object but its attempt is no longer current.
local oldAdapter=spec.stopAdapter(controller,function() return {} end)
check(not oldAdapter.requestStop('STALE') and asleep and exited==before,'old attempt cannot wake or release successor')
fatigue=0.2 successor.tick()
check(successor.finished() and not asleep and not bed,'observed native fatigue target exits furniture before completion')
check(stop(successor).effects=='KNOWN' and not Store.resourceOwner(Sites.keys(nextProof,'SLEEP')[1]),'normal completion clears bed and releases reservation')
-- The actual observer loop must prepare/claim before requesting a body. Policy
-- changes while pending must reject without stranding the preparation claim.
local sampled=0 local pending
f.actor.isDead=function() return false end
f.npc.isOnFire=function() return false end f.npc.getSurroundingAttackingZombies=function() return 0 end
package.loaded['EmberRoutesProbe/Boot']={}
package.loaded['EmberRoutesProbe/NeedsObserver']={sample=function(_,id,time)
 sampled=sampled+1 return {hunger=0,thirst=0,fatigue=0.9,endurance=1,safe=true,observedAt=time} end}
package.loaded['EmberRoutesProbe/Companion']={exportState=function() return {mode='HOLD'} end}
package.loaded['EmberRoutesProbe/TaskRuntime']={current=function() return {accepting=function() return true end,status=function() end,
 submit=function(_,candidate) pending=candidate return {state='PENDING'} end} end}
EmberRoutesProbeJava.workerCount=function() return 1 end
EmberRoutesProbeJava.reposeWithControl=function() return true end
EmberRoutesProbeJava.reposeAtWithControl=function() return true end
local service=require 'EmberRoutesProbe/SelfCare' service.install()
for _=1,1000 do f.advance() service.tick() if pending then break end end
saved=jobs:get('care-a')
check(pending and sampled>0 and saved.payload.site and #saved.payload.claims==2,
 'automatic observation reserves furniture before submitting personal body candidate')
view=Sites.view(f.actor,f.furniture) assert(Sites.configure(f.actor,f.furniture,view.revision,'ASSIGNED','b')=='SITE_POLICY_SAVED')
check(not pending.validate(),'pending admission rechecks assignment before using furniture')
check(pending.persistFailure({bodyStopped=true,effects='KNOWN'},'CANDIDATE_CHANGED')
 and #jobs:get('care-a').payload.claims==0 and not Store.resourceOwner(Sites.keys(saved.payload.site,'SLEEP')[1]),
 'rejection before start releases prepared reservation without a body or physical effects')
view=Sites.view(f.actor,f.furniture) assert(Sites.configure(f.actor,f.furniture,view.revision,'PUBLIC')=='SITE_POLICY_SAVED')
local moveRequest=Sites.new(f.actor,f.npc,'a','SLEEP') local moveCandidate
for _=1,1000 do local done moveCandidate,done=moveRequest:step(4) if done then break end end
assert(moveCandidate)
local moveProof=assert(Sites.prepare(moveCandidate,f.actor,f.npc,'a','SLEEP'))
local job=jobs:get('care-a')
local p=assert(Record.begin(job,'SLEEP'))
p.site=moveProof
p.claims=Sites.keys(moveProof,'SLEEP')
assert(jobs:update(job.id,job.revision,{payload=p}))
job=jobs:get(job.id)
assert(Store.claimPersonal(job))
local Furniture=require 'EmberRoutesProbe/SelfCareFurniture'
local moveCalled,stopCalled=0,0
local farSquare=f.square(10,10) farSquare.canReachTo=function() return true end
local currentSquare=farSquare
f.npc.getCurrentSquare=function() return currentSquare end
local adjSquare=f.square(0,1) adjSquare.canReachTo=function() return true end
adjSquare.TreatAsSolidFloor=function() return true end
adjSquare.isSolid=function() return false end
adjSquare.isSolidTrans=function() return false end
AdjacentFreeTileFinder={Find=function() return adjSquare end}
EmberRoutesProbeJava.motionResult=function() return 'MOVING' end
local moveCtx={
 valid=function() return true end,
 payload={site=moveProof,kind='REST'},
 actor=f.actor,npc=f.npc,
 job={npcId='a',id='care-a'},
 budget={paths=2},
 body={
  move=function(a,pt) moveCalled=moveCalled+1 return true,'MOVE_REQUESTED:test' end,
  stop=function() stopCalled=stopCalled+1 return true end,
 }
}
local moveNode=Furniture.move(moveCtx)
local okRun,moveStatus=pcall(moveNode.run)
check(okRun and moveStatus=='Running' and moveCalled==1,'non-sleep furniture move handles multiple return values from body.move')
check(moveNode.run()=='Running','moving node continues running when motionResult is MOVING')
currentSquare=adjSquare
check(moveNode.run()=='Success' and stopCalled==1,'moving node succeeds once near furniture and stops body')
print('PASS '..checks..' furniture/personal-tree/claims/stop integration checks; native Stats and bodies mocked')
