-- Golden fixtures for the idle candidate pipeline: activity ordering, return
-- protocol, budget accounting and per-offer state lifecycle. The A1 registry
-- refactor must keep every assertion byte-identical.
local root,now={},0 local hours=1
DebugLog={log=function() end}
getTimestampMs=function() return now end
getGameTime=function() return {getWorldAgeHours=function() return hours end,getTimeOfDay=function() return 12 end} end
local rolls={}
ZombRand=function(n) local r=table.remove(rolls,1) if r then return r end return n-1 end
CharacterStat={PAIN='pain'} CharacterTrait={SMOKER='smoker'}
local idle={} IdleState={instance=function() return idle end}
local entry={id='home',revision=1}
dofile('tests/lua/membership-fixture.lua')(function() return entry end,{'a','b'})
local mode={socialPending=false,readingDone=true,readingCandidate=nil,smoker=false,smoke=false,
    seat=false,seatDeferred=false}
package.loaded['EmberRoutesProbe/Warehouse/ContainerRegistry']={data=function() return root end,id=function() return 'x' end}
package.loaded['EmberRoutesProbe/Runtime/TaskJobs']={current=function() return {forNpc=function() return {} end} end}
package.loaded['EmberRoutesProbe/Leisure/StudyService']={changed=function() end,
    decorateLeisure=function(c) c.study=true return c end}
package.loaded['EmberRoutesProbe/Settlement/Companion']={exportState=function() return {mode='HOLD'} end}
local settlementRoot={format=1,revision=1,entries={[entry.id]=entry},publicLifeZones={format=1,revision=0,byId={}}}
package.loaded['EmberRoutesProbe/Settlement/SettlementLedger']={view=function() return entry end,data=function() return settlementRoot end}
package.loaded['EmberRoutesProbe/Settlement/SettlementGeometry']={inside=function() return true end}
package.loaded['EmberRoutesProbe/Settlement/SettlementFacilities']={describe=function() end,watch=function() return {slots={}} end,
    advance=function() return 0 end,reason=function() return 'PENDING' end}
package.loaded['EmberRoutesProbe/Leisure/LibraryIndex']={choose=function(actor,npc,e,_,budget,offset,leisure)
    budget.scan=budget.scan-1
    if mode.readingDone then return mode.readingCandidate,true end
    return nil,false,'INDEX_PENDING' end}
package.loaded['EmberRoutesProbe/Leisure/LeisureSmoke']={find=function(npc,budget,row)
    if mode.smoke then return {item={getID=function() return 7 end},fire={getID=function() return 8 end}},true end
    return nil,true end}
local seatIterators=0
package.loaded['EmberRoutesProbe/SelfCare/ReposeSites']={
    new=function() seatIterators=seatIterators+1 local steps=0
        return {step=function()
            if not mode.seat then return nil,true end
            if mode.seatDeferred then steps=steps+1
                if steps==1 then return nil,false,'SEAT_PENDING' end end
            return {object={},revision=1,key='seat',settlementId='home'},true end} end,
    prepare=function(f) return {id='s',partId='p',revision=1,parts={},key=f.key} end,
    keys=function() return {'repose:s:p'} end,
    resolve=function() end}
getCell=function() return {getGridSquare=function() end} end
local fitness={onGoingStiffness=function() return false end,getCurrentExeStiffnessTimer=function() return 0 end,
    getCurrentExeStiffnessInc=function() return 0 end,init=function() end}
local npc={getX=function() return 1 end,getY=function() return 1 end,getZ=function() return 0 end,
    getStats=function() return {get=function() return 0 end} end,
    getBodyDamage=function() return {getOverallBodyHealth=function() return 100 end,
        getBodyParts=function() return {size=function() return 0 end} end} end,
    getPrimaryHandItem=function() end,getSecondaryHandItem=function() end,
    hasTrait=function() return mode.smoker end,
    getFitness=function() return fitness end,getCurrentState=function() return idle end}
EmberRoutesProbeJava={reposeAtWithControl=function() return true end}

local bindings={a={id='a',handle=npc},b={id='b',handle=npc}}
package.loaded['EmberRoutesProbe/Runtime/Driver']={bindId=function(_,id) return bindings[id] end}
local square={TreatAsSolidFloor=function() return true end,isSolid=function() return false end,
    isSolidTrans=function() return false end,HasStairs=function() return false end,
    isDoorSquare=function() return false end,isFree=function() return true end,
    isOutside=function() return false end,getMovingObjects=function() return {size=function() return 0 end} end,
    canReachTo=function() return true end}
getCell=function() return {getGridSquare=function() return square end} end
local Service=require 'EmberRoutesProbe/Leisure/LeisureService'
local Social=require 'EmberRoutesProbe/Activity/SocialCoordinator'
local sample={safe=true,hunger=0,thirst=0,fatigue=0,endurance=1}
Service.offer('a',entry) Service.offer('b',entry)
Social.advertise('b',entry,{x=1,y=1,z=0},0)
rolls={0}
local c=Service.candidate({},bindings.a,sample,{scan=32,paths=1})
assert(c and c.leisure.activity=='SOCIAL','real service and real coordinator must agree on entry contract')
assert(Social.accept(c.leisure.socialId,'a','attempt-a',1))
assert(Social.accept(c.leisure.socialId,'b','attempt-b',1))
assert(Social.arrive(c.leisure.socialId,'a','attempt-a',1))
assert(Social.arrive(c.leisure.socialId,'b','attempt-b',1))
assert(Social.view(c.leisure.socialId,'a','attempt-a',1).phase=='CONVERSE')
local active={effects='KNOWN',payload={step='ACTING',kind='STUDY'}}
package.loaded['EmberRoutesProbe/Runtime/TaskJobs'].current=function() return {forNpc=function() return {active} end} end
assert(not Social.available('b'),'a reader cannot advertise as available for a new pair')
print('P3.5 service/coordinator integration: entry shape, actual pairing, arrival barrier, busy reader')

-- Exercise the real formation path, counting only the chance RNG (10000).
active.payload.step='IDLE'
local chanceRolls=0
local inviting=false
local invite=Social.invite
Social.invite=function(...)
    inviting=true local result=invite(...) inviting=false return result
end
ZombRand=function(n) if inviting and n==10000 then chanceRolls=chanceRolls+1 end return n-1 end
Service.reset() Service.offer('a',entry) Service.offer('b',entry)
Social.advertise('b',entry,{x=1,y=1,z=0},now)
local function discover() return Service.candidate({},bindings.a,sample,{scan=32,paths=1}) end
discover() discover()
assert(chanceRolls==1,'one failed roll per eligible partner per discovery round')
now=1500 Service.offer('a',entry) discover()
assert(chanceRolls==2,'later discovery round retries')
now=3000 Service.offer('a',entry) bindings.b=nil discover()
assert(chanceRolls==2,'missing actual partner does not consume chance')
bindings.b={id='b',handle=npc}
discover() assert(chanceRolls==3,'eligible partner can roll once after binding appears')
Service.workState('a',entry,'READY') discover()
assert(not Social.invite('b',entry,now,function(a,b) return a,b end),'ready work withdraws advert')
Service.workState('a',entry,'OBSERVING') discover()
assert(not Social.invite('b',entry,now,function(a,b) return a,b end),'observing work withdraws advert')
print('PASS cut 3 eligible-only single chance per round, later retry and WORK_READY/WORK_OBSERVING withdrawal')

active.payload.step='ACTING' active.payload.kind='LEISURE'
for _,activity in ipairs({'OBSERVE','SIT','READING','STROLL','FITNESS','SMOKE'}) do
    active.payload.leisure={activity=activity}
    assert(Social.available('b')==(activity=='OBSERVE'),'idle-only invitation scope: '..activity)
end
active.payload.leisure={activity='OBSERVE',zoneVisit='zone'}
assert(not Social.available('b'))
active.payload.leisure={activity='OBSERVE',roleDuty=true}
assert(not Social.available('b'))
active.effects='UNKNOWN' active.payload.leisure={activity='OBSERVE'}
assert(not Social.available('b'))
print('PASS cut 3 unchanged idle/disposable OBSERVE invitation scope')
