-- Real floor selection, personal claims and repose leaf; native animation mocked.
local root,now={taskJobs={format=1,byId={}}},0 local entry={id='home',revision=1}
getTimestampMs=function() return now end
getGameTime=function() return {getWorldAgeHours=function() return 10 end} end
CharacterStat={FATIGUE='fatigue',ENDURANCE='endurance'}
package.loaded['EmberRoutesProbe/ContainerRegistry']={data=function() return root end}
package.loaded['EmberRoutesProbe/BusinessJobs']={hauls=function() return {tasks={},byNpc={},routes={}} end,flush=function() end}
package.loaded['EmberRoutesProbe/CraftRecord']={records=function() return {} end}
package.loaded['EmberRoutesProbe/Boot']={}
package.loaded['EmberRoutesProbe/Log']={write=function() end}
package.loaded['EmberRoutesProbe/MembershipService']={entry=function() return entry end}
package.loaded['EmberRoutesProbe/SettlementGeometry']={inside=function(_,x,y) return x>=1 and x<=2 and y==1 end}
local x,ground,asleep,fatigue,owner=0,false,false,0.9,true
local begun,ready,starts,stops=false,false,0,0
local npc={getX=function() return x end,getY=function() return 1 end,getZ=function() return 0 end,
    isSitOnGround=function() return ground end,getCurrentActionContextStateName=function() return ground and 'sitonground' or 'idle' end,
    isAsleep=function() return asleep end,isResting=function() return false end,
    getStats=function() return {get=function() return fatigue end} end}
local calls=0
EmberRoutesProbeJava={floorSleepSafe=function(_,sx,sy,sz)
    calls=calls+1 return (sx==1 or sx==2) and sy==1 and sz==0
end,motionResult=function() return 'MOVING' end,bedPoseReady=function() return ready end}
local F=require 'EmberRoutesProbe/FloorSleep'
local scan=F.scan(npc,'a') local point
for i=1,81 do local p,done=scan:step(1) point=p if done then break end end
assert(point and point.x==1 and calls<=9,'bounded scan finds a safe point inside the settlement')
local Record=require 'EmberRoutesProbe/SelfCareRecord'
local Jobs=require 'EmberRoutesProbe/TaskJobs'
local Store=require 'EmberRoutesProbe/LaborStore'
local job=Record.create('sleep','a') job.payload=Record.begin(job,'SLEEP')
job.payload.floorSite=point job.payload.claims={F.key(point)} job.payload.step='ACTING'
assert(Record.valid(job) and Jobs.current():create(job))
local token=assert(Store.claimPersonal(job))
local c={job=job,npc=npc,payload=job.payload,token=token,effects='KNOWN',actor={},budget={paths=1},
    valid=function() return owner end,sameAttempt=function() return owner end,persist=function() return true end}
c.body={retained=function() return owner end,move=function() return true end,
    furniture=function(object,phase) assert(object==nil and phase=='FLOOR') ground=begun return begun end,
    stop=function() stops=stops+1 asleep=false return true end,
    repose=function(kind,enter) assert(kind=='SLEEP') asleep=enter if enter then starts=starts+1 end return true end}
assert(F.valid(c),'reserved floor is valid even before the execution context receives its token')
local competing=F.scan(npc,'b') local other
for i=1,81 do local p,done=competing:step(1) other=p if done then break end end
assert(other and other.x==2,'another sleeper skips the claimed tile')
local move=F.move(c) assert(move.run()=='Running') x=1 assert(move.run()=='Success')
local Repose=require 'EmberRoutesProbe/SelfCareRepose'
local leaf=Repose.new(c)
assert(leaf.run()=='Running' and starts==0,'no sleep effects while native sitting is pending')
begun=true assert(leaf.run()=='Running' and starts==0,'native ground seat alone is not sleep evidence')
ready=true assert(leaf.run()=='Running' and starts==1 and asleep,'stable sleep clip enables original sleep effects once')
fatigue=0.2 assert(leaf.run()=='Running' and not asleep and ground,'wake requests exit but waits for native get-up')
assert(Store.resourceOwner(F.key(point)),'floor stays claimed throughout pose exit')
ground=false assert(leaf.run()=='Success' and c.payload.repose.completed,'actual standing completes the sleep episode')
local old=F.scan(npc,'a') entry.revision=2 assert(select(2,old:step(8)),'membership revision invalidates pending selection')
owner=false local before=stops assert(not leaf.halt() and stops==before,'stale owner cannot stop a successor')
job.payload.floorSite.x=1.5 assert(not Record.valid(job),'malformed floor coordinates are rejected on save/load')
print('PASS floor sleep selection/claims/native-pose gating/async get-up/stale owner; world and clips mocked')
