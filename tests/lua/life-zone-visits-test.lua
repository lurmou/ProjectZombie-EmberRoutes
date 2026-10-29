-- Real zone/visit/schema modules; native movement and occupancy are substitutes.
local checks=0
local function check(value,label) assert(value,label) checks=checks+1 end
local entry={id='home',revision=1,areas={{x=0,y=0,w=30,h=20}}}
local root={entries={home=entry}}
local actor={} local serial=0
package.loaded['EmberRoutesProbe/SettlementLedger']={data=function() return root end,
    view=function(a,id) if a==actor and id=='home' then return entry end return nil,'ACCESS_DENIED' end}
package.loaded['EmberRoutesProbe/ContainerRegistry']={id=function() serial=serial+1 return 'z'..serial end}
local reserved=false
package.loaded['EmberRoutesProbe/LaborStore']={resourceOwner=function() return reserved and {} or nil end}
local Zones=require 'EmberRoutesProbe/SettlementZones'
local Visits=require 'EmberRoutesProbe/LifeZoneVisits'
local Record=require 'EmberRoutesProbe/LeisureRecord'
local zone=assert(Zones.save(actor,'home',nil,nil,{name='Common',enabled=true,
    area={x=10,y=0,w=3,h=3,z=0},rules={OBSERVE=1}}))
local function environment(id)
    return {entry=entry,point={x=.5,y=.5,z=0},id=id or 'a',npc={},state={},memory={},offer={},
        now=100,hours=1,budget={scan=2,paths=1},
        s={safe=true,healthy=true,health=100,hunger=0,thirst=0,fatigue=0,endurance=1,pain=0}}
end
local calls=0
local function available() calls=calls+1 return {} end
local env=environment()
local candidate,done=Visits.seek(env,available)
check(candidate and done and candidate.publicVisit,'discover usable public area')
check(candidate.leisure.zoneVisit.id==zone.id and env.budget.scan==1,'bind proof and debit shared scan')
check(Record.valid({kind='LEISURE',settlementId='home',leisure=candidate.leisure}),'persistent visit validates')
local ref={id=zone.id,revision=zone.revision}
check(not Zones.destination('home',ref,{x=9.9,y=.5,z=0}),'near boundary is not arrival inside zone')
check(not Zones.destination('home',ref,{x=10.5,y=.5,z=1}),'same XY other floor is not destination')
check(not Zones.destination('home',ref,{}),'malformed target rejected')
local other=assert(Visits.seek(environment('b'),available))
check(other.point.x~=candidate.point.x or other.point.y~=candidate.point.y,'spread different NPC targets')
local inside=environment() inside.point={x=10.5,y=.5,z=0}
local noVisit,insideDone=Visits.seek(inside,available)
check(not noVisit and insideDone,'already in public area does not relocate')
local resting=environment() resting.memory.moveAfter=2
check(not Visits.seek(resting,available) and resting.budget.scan==2,'movement cooldown survives discovery')
local unsafe=environment() unsafe.s.safe=false
check(not Visits.seek(unsafe,available),'unsafe NPC cannot visit')
local exhausted=environment() exhausted.budget.scan=0
local noBudget,budgetDone=Visits.seek(exhausted,available)
check(not noBudget and budgetDone==false,'budget exhaustion is observation pending')
local unavailable=environment() local inspected=0
local missing,finished=Visits.seek(unavailable,function() inspected=inspected+1 return nil end)
check(not missing and not finished and inspected==2 and unavailable.budget.scan==0,'unloaded points obey slice budget')
for _=1,8 do
    unavailable.budget.scan=2
    missing,finished=Visits.seek(unavailable,function() inspected=inspected+1 return nil end)
    if finished then break end
end
check(finished and inspected==9 and unavailable.state.retryAt>unavailable.now,'bounded sampling sleeps, not infinite scan')
unavailable.budget.scan=2
check(not Visits.seek(unavailable,available) and unavailable.budget.scan==2,'retry backoff avoids repeated native calls')
reserved=true local occupied=environment() local inspectedBefore=calls
Visits.seek(occupied,available)
check(calls==inspectedBefore,'shared reservations are checked before native occupancy')
reserved=false
local now=0
getTimestampMs=function() return now end
local motion='MOVING'
EmberRoutesProbeJava={motionResult=function() return motion end}
package.loaded['EmberRoutesProbe/MembershipService']={entry=function() return entry end}
package.loaded['EmberRoutesProbe/LeisureService']={standable=function() return {} end}
local Actions=require 'EmberRoutesProbe/LeisureActions'
local function context(point)
    local location={x=.5,y=.5,z=0}
    local saves,moves,stops=0,0,0
    local c={actor=actor,job={npcId='a'},payload={settlementId='home',
        leisure={format=1,activity='OBSERVE',hours=1,moving=true,point=point,zoneVisit={id=zone.id,revision=zone.revision}}},
        budget={paths=1},valid=function() return true end}
    c.npc={getX=function() return location.x end,getY=function() return location.y end,getZ=function() return location.z end}
    c.body={move=function() moves=moves+1 return true,'MOVE_REQUESTED' end,stop=function() stops=stops+1 return true end}
    c.persist=function() saves=saves+1 return true end
    return c,location,function() return saves,moves,stops end
end
local c,location,counts=context(candidate.point)
local leaf=Actions.new(c)
check(leaf.run()=='Running' and c.budget.paths==0,'visit uses authorized move and existing path budget')
location.x,location.y=candidate.point.x,candidate.point.y
check(leaf.run()=='Success' and c.payload.leisure.finished,'real arrival closes transport')
local saves,moves,stops=counts()
check(saves==1 and moves==1 and stops==1,'arrival persists only one position fact after movement stop')
check(not c.payload.leisure.applying and not c.payload.leisure.applied,'travel does not grant entertainment effects')
local near,nearPosition,nearCounts=context({x=10.5,y=.5,z=0})
nearPosition.x=9.9
check(Actions.new(near).run()=='Running' and not near.payload.leisure.finished,
    'near boundary still requests movement instead of faking or cancelling arrival')
local nearSaves,nearMoves=nearCounts()
check(nearSaves==0 and nearMoves==1,'boundary approach uses body authority without an arrival receipt')
local changed,changedPosition,changedCounts=context(candidate.point)
local changedLeaf=Actions.new(changed)
check(changedLeaf.run()=='Running','start before policy change')
zone.enabled=false
zone=assert(Zones.save(actor,'home',zone.id,zone.revision,zone))
check(not Zones.destination('home',ref,candidate.point),'revision change invalidates destination proof')
check(changedLeaf.run()=='Failure' and not changed.payload.leisure.finished,'disabled destination stops further travel dispatch')
changedLeaf.halt()
local _,_,haltStops=changedCounts()
check(haltStops==1,'halt uses the same body stop')
local disabled=environment()
check(not Visits.seek(disabled,available),'disabled zone is not a destination')
check(Zones.remove(actor,'home',zone.id,zone.revision),'remove test zone')
check(not Zones.destination('home',{id=zone.id,revision=zone.revision},candidate.point),'removed zone never rebinds by coordinates')
local personal={effects='KNOWN',payload={kind='LEISURE',step='ACTING',leisure={activity='OBSERVE',zoneVisit=ref}}}
package.loaded['EmberRoutesProbe/TaskJobs']={current=function() return {forNpc=function() return {personal} end} end}
local Social=require 'EmberRoutesProbe/SocialCoordinator'
check(not Social.available('a'),'in-transit visit does not advertise as an idle social partner')
personal.payload.leisure.zoneVisit=nil
check(Social.available('a'),'ordinary idle observation remains eligible for social invitations')
print('life-zone-visits: '..checks..' PASS (native movement/occupancy substitutes)')
