package.path='Contents/mods/EmberRoutesProbe/42/media/lua/client/?.lua;Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;'..package.path
-- Reuse the furniture identity fixture; production Sites/Policy/claims/execution
-- remain real. Engine bodies and the shared facility observation are substitutes.
local f=dofile('tests/lua/repose-sites-test.lua')
local checks=0
local function check(v,m) checks=checks+1 assert(v,m) end
package.loaded['EmberRoutesProbe/Kernel/Log']={write=function() end}
package.loaded['EmberRoutesProbe/Work/LaborStore']=nil
package.loaded['EmberRoutesProbe/Work/BusinessJobs']={hauls=function() return {tasks={},byNpc={},routes={}} end,flush=function() end}
package.loaded['EmberRoutesProbe/Crafting/CraftRecord']={records=function() return {} end}
local Store=require 'EmberRoutesProbe/Work/LaborStore'
f.resourceProxy.resourceOwner=Store.resourceOwner
local Jobs=require 'EmberRoutesProbe/Runtime/TaskJobs' local jobs=Jobs.current()
local Record=require 'EmberRoutesProbe/SelfCare/SelfCareRecord'
assert(jobs:create(Record.create('care-a','a'))) Store.data()
local row={version=1,slots={},complete=true,dirtyCount=0}
local Facilities=package.loaded['EmberRoutesProbe/Settlement/SettlementFacilities']
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
package.loaded['EmberRoutesProbe/Activity/ActivityService']={context=function() end,allowsPoint=function() return true end,policyAt=function() return 1 end}
package.loaded['EmberRoutesProbe/Activity/SocialCoordinator']={withdraw=function() end,reset=function() end}
local Service=require 'EmberRoutesProbe/Leisure/LeisureService'
local Policy=require 'EmberRoutesProbe/Leisure/LeisurePolicy'
local Registry=require 'EmberRoutesProbe/Leisure/LeisureRegistry'
-- Leave only SIT in the registered pool: normal seek receives zero scan.
local sit=Registry.get('SIT') Registry.all=function() return {sit} end
local sample={safe=true,hunger=0,thirst=0,fatigue=0,endurance=1}
local function discover(id,memory)
 Service.reset() Service.offer(id,f.entry)
 advances=0
 local c,done=Service.candidate(f.actor,{id=id,handle=f.npc},sample,{scan=0,paths=0},memory or {cooldowns={OBSERVE=11}})
 check(done,'decision never blocks on the nearby scan')
 check(advances==0,'fallback never advances facility scan')
 return c
end
local c=assert(discover('a'))
check(c.leisure.activity=='SIT' and not c.leisure.ambient and c.leisure.moving,'normal moving SIT from exhausted normal budget')
check(f.sites.validProof(c.site) and #c.claims==1,'real serializable proof and seat claim keys')
local job=jobs:get('care-a') local p=assert(Record.begin(job,'LEISURE'))
p.leisure=c.leisure p.site=c.site p.claims=c.claims p.settlementId=f.entry.id
p.membershipRevision=c.membershipRevision p.settlementRevision=c.settlementRevision
assert(jobs:update(job.id,job.revision,{payload=p})) job=jobs:get(job.id)
assert(Store.claimPersonal(job))
check(Store.resourceOwner(c.claims[1]).taskId==job.id,'real personal claim authority admits seat')
check(discover('b').leisure.ambient,'second NPC cannot select claimed seat')
-- Stop a prepared SIT through the actual execution adapter (before body start).
for _,name in ipairs({'ISInventoryTransferAction','ISEatFoodAction','ISDrinkFluidAction'}) do package.loaded['TimedActions/'..name]=true end
package.loaded['EmberRoutesProbe/Crafting/CraftSupply']={}
package.loaded['EmberRoutesProbe/SelfCare/SelfCareResources']={}
f.npc.getInventory=function() return {getItems=function() return f.list({}) end} end
local Execute=require 'EmberRoutesProbe/SelfCare/SelfCareExecution'
local spec=Execute.new(f.actor,{id='a',handle=f.npc},job,nil,function() return {scan=0,paths=0,nodes=8} end)
check(spec.persistFailure({bodyStopped=true,effects='KNOWN'},'LEISURE_NEEDS_CARE'),'known stopped interruption persists')
check(not Store.resourceOwner(c.claims[1]) and #jobs:get(job.id).payload.claims==0,'interrupt releases actual claim')
check(discover('b').leisure.activity=='SIT','released seat available to second NPC')
row.slots={}
check(discover('a').leisure.ambient,'no seat preserves ambient OBSERVE')
row.slots={seat(f.furniture,0,0)}
check(discover('a',{cooldowns={OBSERVE=11,SIT=11}}).leisure.ambient,'SIT cooldown retained')
local allowed=Policy.allowed
Policy.allowed=function(kind,...) if kind=='SIT' then return false end return allowed(kind,...) end
check(discover('a').leisure.ambient,'SIT Policy gate retained') Policy.allowed=allowed
check(discover('a',{cooldowns={OBSERVE=11},moveAfter=11}).leisure.ambient,'movement cooldown retained')
sample.safe=false check(not discover('a'),'unsafe rejects leisure') sample.safe=true
-- 67d0e15 removed the work-state dimension: no report yields a brief
-- OBSERVE from candidate() any more; the observation survives only as an
-- idle status reason, and ordinary discovery still finds the seat.
Service.note('a','WORK_OBSERVING')
check(Service.status('a').reason=='WORK_OBSERVING','observing work is recorded as an idle status reason')
local observed=discover('a')
check(observed.leisure.activity=='SIT' and not observed.leisure.ambient and observed.leisure.moving,'without the removed work-state gate, ordinary discovery still finds the seat')
row.slots={}
for i=1,9 do row.slots[i]=seat(f.furniture,100,100) end
row.slots[10]=seat(f.furniture,0,0)
check(discover('a').leisure.ambient,'bounded eight-record scan does not reach tenth slot')
row.slots={seat(f.furniture,0,0)}
f.furniture.occupied=true check(discover('a').leisure.ambient,'native occupancy retained') f.furniture.occupied=false
f.furniture.bed=true check(discover('a').leisure.ambient,'beds excluded') f.furniture.bed=false
row.slots={seat(f.furniture,0,0)} row.slots[1].z=1
check(discover('a').leisure.ambient,'other floor excluded') row.slots[1].z=0
square.isFree=function() return false end
check(discover('a').leisure.ambient,'origin must be standable') square.isFree=function() return true end
local activity=package.loaded['EmberRoutesProbe/Activity/ActivityService']
activity.policyAt=function(_,_,_,_,_,kind) return kind=='SIT' and 0 or 1 end
check(discover('a').leisure.ambient,'SIT zone prohibition retained') activity.policyAt=function() return 1 end
local rev=f.sites.view(f.actor,f.furniture).revision
assert(f.sites.configure(f.actor,f.furniture,rev,'ASSIGNED','b')=='SITE_POLICY_SAVED')
check(discover('a').leisure.ambient,'assigned seat cannot be stolen')
print('PASS idle-sit boundary checks='..checks..'; engine movement/animation mocked')
