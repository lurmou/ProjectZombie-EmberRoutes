package.path='Contents/mods/EmberRoutesProbe/42/media/lua/client/?.lua;Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;'..package.path
-- Reuse the furniture identity fixture; production Sites/Policy/claims/execution
-- remain real. Engine bodies and the shared facility observation are substitutes.
local f=dofile('tests/lua/repose-sites-test.lua')
local checks=0
local function check(v,m) checks=checks+1 assert(v,m) end
package.loaded['EmberRoutesProbe/Log']={write=function() end}
package.loaded['EmberRoutesProbe/LaborStore']=nil
package.loaded['EmberRoutesProbe/BusinessJobs']={hauls=function() return {tasks={},byNpc={},routes={}} end,flush=function() end}
package.loaded['EmberRoutesProbe/CraftRecord']={records=function() return {} end}
local Store=require 'EmberRoutesProbe/LaborStore'
f.resourceProxy.resourceOwner=Store.resourceOwner
local Jobs=require 'EmberRoutesProbe/TaskJobs' local jobs=Jobs.current()
local Record=require 'EmberRoutesProbe/SelfCareRecord'
assert(jobs:create(Record.create('care-a','a'))) Store.data()
local row={version=1,slots={},complete=true,dirtyCount=0}
local Facilities=package.loaded['EmberRoutesProbe/SettlementFacilities']
local advances=0
Facilities.watch=function() return row end
Facilities.advance=function(_,n) advances=advances+n return 0 end
Facilities.pending=function() return false end
local function seat(object,x,y) return {object=object,x=x,y=y,z=0,quality='goodBed',seats=1} end
row.slots={seat(f.furniture,0,0)}
local square=f.squares['0:1:0'] or f.square(0,1)
for _,name in ipairs({'isSolid','isSolidTrans','HasStairs','isDoorSquare','isOutside'}) do square[name]=function() return false end end
square.TreatAsSolidFloor=function() return true end square.isFree=function() return true end
square.getMovingObjects=function() return f.list({f.npc}) end
local oldGrid=f.cell.getGridSquare
f.cell.getGridSquare=function(self,x,y,z) if x==0 and y==1 and z==0 then return square end return oldGrid(self,x,y,z) end
CharacterStat={PAIN='pain'}
IdleState={instance=function() return 'IDLE' end}
f.npc.getStats=function() return {get=function() return 0 end} end
f.npc.getBodyDamage=function() return {getOverallBodyHealth=function() return 100 end} end
f.npc.getPrimaryHandItem=function() end f.npc.getSecondaryHandItem=function() end
f.npc.getCurrentState=function() return 'OTHER' end
getGameTime=function() return {getWorldAgeHours=function() return 10 end} end
ZombRand=function(n) return n-1 end
EmberRoutesProbeJava.reposeAtWithControl=function() return true end
package.loaded['EmberRoutesProbe/ActivityService']={context=function() end,allowsPoint=function() return true end,policyAt=function() return 1 end}
package.loaded['EmberRoutesProbe/SocialCoordinator']={withdraw=function() end,reset=function() end}
local Service=require 'EmberRoutesProbe/LeisureService'
local Policy=require 'EmberRoutesProbe/LeisurePolicy'
local Registry=require 'EmberRoutesProbe/LeisureRegistry'
-- Isolate fallback from ordinary registered seeks; STROLL construction and
-- Policy selection remain real, with optional normal-selection scan budget.
Registry.all=function() return {} end
local sample={safe=true,hunger=0,thirst=0,fatigue=0,endurance=1}
-- Decisions retain the same offer, unlike the independent legacy cases.
local memory={cooldowns={OBSERVE=11}}
local function reset()
 Service.reset() Service.workState('a',f.entry,'IDLE')
 memory={cooldowns={OBSERVE=11}} advances=0
end
local function decide(scan)
 Service.workState('a',f.entry,'IDLE')
 local c,done=Service.candidate(f.actor,{id='a',handle=f.npc},sample,{scan=scan or 0,paths=0},memory)
 check(done,'bounded decision completes')
 return c
end
local Activity=package.loaded['EmberRoutesProbe/ActivityService']
local points,visits={},{}
local grid=f.cell.getGridSquare
f.cell.getGridSquare=function(self,x,y,z)
 local key=x..':'..y..':'..z
 if points[key]~=nil then
  visits[key]=(visits[key] or 0)+1
  return points[key] or nil
 end
 return grid(self,x,y,z)
end
local function floor()
 return {TreatAsSolidFloor=function() return true end,isFree=function() return true end,
 isSolid=function() return false end,isSolidTrans=function() return false end,
 HasStairs=function() return false end,isDoorSquare=function() return false end,
 isOutside=function() return false end,getMovingObjects=function() return f.list({}) end}
end
-- NPC origin is (0.5,1.5); normal random direction is north (index 4).
local keys={'2:1:0','0:3:0','-2:1:0','0:-1:0'}
local function directions(value)
 visits={}
 for _,key in ipairs(keys) do points[key]=value and floor() or false end
end
reset() directions(true) row.slots={seat(f.furniture,0,0)}
check(decide().leisure.activity=='SIT','SIT wins over available fallback STROLL')
reset() row.slots={} directions(true)
check(decide().leisure.activity=='STROLL','no seat then fresh STROLL')
reset() directions(false)
check(decide().leisure.ambient,'no seat and all directions fail then OBSERVE')
reset() directions(true) points['0:-1:0']=false
local c=decide(1)
check(c.leisure.activity=='STROLL' and c.leisure.point.x==2.5,'fresh direction rescues original unstandable point')
check(visits['0:-1:0']==1,'normal point checked only once')
reset() directions(true)
Service.failed('a','STROLL:0:-1:0','TEST')
c=decide(1)
check(c.leisure.activity=='STROLL' and c.leisure.point.x==2.5,'blocked original target uses fresh legal direction')
check(visits['0:-1:0']==1,'blocked original never rechecked')
reset() directions(true)
Activity.policyAt=function(_,_,x,y,_,kind) return kind=='STROLL' and y<0 and 0 or 1 end
check(decide(1).leisure.point.x==2.5,'zone-zero original uses fresh legal direction')
Activity.policyAt=function() return 1 end
reset() directions(false)
check(decide(1).leisure.ambient,'normal and fallback all-directions failure observes')
for _,key in ipairs(keys) do check(visits[key]==1,'each cardinal point checked at most once') end
reset() directions(true)
for _,key in ipairs(keys) do Service.failed('a','STROLL:'..key,'TEST') end
check(decide().leisure.ambient,'all blocked targets rejected')
reset() directions(true) memory.cooldowns.STROLL=11
check(decide().leisure.ambient,'STROLL cooldown cannot be rescued')
reset() memory.moveAfter=11
check(decide().leisure.ambient,'moveAfter retained')
reset() memory.decisionAfter=11
check(decide().leisure.ambient,'decision pause retains ambient')
reset()
local allowed=Policy.allowed
Policy.allowed=function(kind,...) return kind~='STROLL' and allowed(kind,...) end
check(decide().leisure.ambient,'STROLL Policy retained') Policy.allowed=allowed
reset()
Activity.policyAt=function(_,_,_,_,_,kind) return kind=='STROLL' and 0 or 1 end
check(decide().leisure.ambient,'all destination zones rejected') Activity.policyAt=function() return 1 end
reset() sample.safe=false
check(not decide(),'safety authoritative') sample.safe=true
reset() sample.hunger=1
check(not decide(),'needs authoritative') sample.hunger=0
reset() Service.workState('a',f.entry,'READY')
local ready=Service.candidate(f.actor,{id='a',handle=f.npc},sample,{scan=0,paths=0},memory)
check(not ready,'work READY wins')
-- Failed SIT keeps its 60s deadline despite STROLL/OBSERVE outcomes.
reset() directions(true)
row.slots={}
for i=1,9 do row.slots[i]=seat(f.furniture,100,100) end
row.slots[10]=seat(f.furniture,0,0)
check(decide().leisure.activity=='STROLL','first eight records miss later seat')
check(decide().leisure.activity=='STROLL','STROLL does not bypass retry')
f.advance(59999)
check(decide().leisure.activity=='STROLL','SIT retry still blocked before 60 seconds')
f.advance(1)
c=decide()
check(c.leisure.activity=='SIT' and not c.leisure.ambient,'next window finds tenth seat after retry')
check(advances==0,'indexed fallback never advances Facilities')
-- Use real iterator to observe exact windows, wrap and list shrink.
local Sites=f.sites
row.slots={} for i=1,10 do row.slots[i]=seat(f.furniture,100,100) end
local function window(offset)
 return Sites.new(f.actor,f.npc,'a','REST',{},
 {indexedOnly=true,seatingOnly=true,excludeBeds=true,sameFloor=true,maxDistance=4,offset=offset}):step(8)
end
local found,done,why,offset=window(1)
check(not found and done and offset==9,'first window consumes eight records')
found,done,why,offset=window(offset)
check(not found and done and offset==1,'tail window wraps to start')
row.slots={seat(f.furniture,0,0)}
found,done,why,offset=window(9)
check(found and offset==1,'shrunk list clamps/wraps cursor')
-- Observe reset and retry-clock invalidation through public decision calls.
local function missFirst()
 reset() directions(false)
 row.slots={} for i=1,10 do row.slots[i]=seat(f.furniture,100,100) end
 check(decide().leisure.ambient,'empty first window yields OBSERVE')
 row.slots[1]=seat(f.furniture,0,0)
end
missFirst() row.version=row.version+1
check(decide().leisure.activity=='SIT','facility version resets cursor and retry')
missFirst() Service.seatReleased(f.entry.id)
check(decide().leisure.activity=='SIT','seatEpoch resets cursor and retry')
missFirst()
local x=f.npc.getX f.npc.getX=function() return 1.5 end
-- Keep the new origin standable; seat remains within four tiles.
points['1:1:0']=floor()
check(decide().leisure.activity=='SIT','location stamp resets cursor and retry')
f.npc.getX=x
reset() directions(false)
row.slots={} for i=1,10 do row.slots[i]=seat(f.furniture,100,100) end
check(decide().leisure.ambient,'seatless first window observes')
f.advance(60000) check(decide().leisure.ambient,'seatless tail window observes')
row.slots[1]=seat(f.furniture,0,0)
check(decide().leisure.ambient,'OBSERVE preserves SIT retry and cursor')
f.advance(60000) check(decide().leisure.activity=='SIT','wrapped next pass reaches first record')
print('PASS R1/R2 directed checks='..checks..'; second-NPC claims and interrupt release covered by idle-sit regression')
