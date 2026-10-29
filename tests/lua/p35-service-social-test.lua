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
package.loaded['EmberRoutesProbe/ContainerRegistry']={data=function() return root end,id=function() return 'x' end}
package.loaded['EmberRoutesProbe/TaskJobs']={current=function() return {forNpc=function() return {} end} end}
package.loaded['EmberRoutesProbe/StudyService']={changed=function() end,
    decorateLeisure=function(c) c.study=true return c end}
package.loaded['EmberRoutesProbe/Companion']={exportState=function() return {mode='HOLD'} end}
package.loaded['EmberRoutesProbe/SettlementLedger']={view=function() return entry end}
package.loaded['EmberRoutesProbe/SettlementGeometry']={inside=function() return true end}
package.loaded['EmberRoutesProbe/SettlementFacilities']={describe=function() end,watch=function() return {slots={}} end,
    advance=function() return 0 end,reason=function() return 'PENDING' end}
package.loaded['EmberRoutesProbe/LibraryIndex']={choose=function(actor,npc,e,_,budget,offset,leisure)
    budget.scan=budget.scan-1
    if mode.readingDone then return mode.readingCandidate,true end
    return nil,false,'INDEX_PENDING' end}
package.loaded['EmberRoutesProbe/LeisureSmoke']={find=function(npc,budget,row)
    if mode.smoke then return {item={getID=function() return 7 end},fire={getID=function() return 8 end}},true end
    return nil,true end}
local seatIterators=0
package.loaded['EmberRoutesProbe/ReposeSites']={
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
package.loaded['EmberRoutesProbe/Driver']={bindId=function(_,id) return bindings[id] end}
local square={TreatAsSolidFloor=function() return true end,isSolid=function() return false end,
    isSolidTrans=function() return false end,HasStairs=function() return false end,
    isDoorSquare=function() return false end,isFree=function() return true end,
    isOutside=function() return false end,getMovingObjects=function() return {size=function() return 0 end} end,
    canReachTo=function() return true end}
getCell=function() return {getGridSquare=function() return square end} end
local Service=require 'EmberRoutesProbe/LeisureService'
local Social=require 'EmberRoutesProbe/SocialCoordinator'
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
package.loaded['EmberRoutesProbe/TaskJobs'].current=function() return {forNpc=function() return {active} end} end
assert(not Social.available('b'),'a reader cannot advertise as available for a new pair')
print('P3.5 service/coordinator integration: entry shape, actual pairing, arrival barrier, busy reader')
