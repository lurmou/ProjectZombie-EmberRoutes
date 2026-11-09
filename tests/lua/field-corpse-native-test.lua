-- Installed native Lua actions; turning, animation engine and physics are mocked.
local n=0 local function check(v,m) n=n+1 assert(v,m) end
local vanilla='D:/Software/GameApp/steam/steamapps/common/ProjectZomboid/media/lua/shared/'
dofile(vanilla..'ISBaseObject.lua') package.loaded.ISBaseObject=true
dofile(vanilla..'TimedActions/ISBaseTimedAction.lua') package.loaded['TimedActions/ISBaseTimedAction']=true
Events={OnGameStart={Add=function() end}}
dofile(vanilla..'TimedActions/ISGrabCorpseAction.lua')
dofile(vanilla..'TimedActions/ISDropCorpseAction.lua')
for _,name in ipairs({'ISCleanBlood','ISChopTreeAction','ISGrabCorpseAction','ISDropCorpseAction','ISUnequipAction','ISEquipWeaponAction'}) do
 package.loaded['TimedActions/'..name]=true
end
for _,name in ipairs({'Farming/TimedActions/ISWaterPlantAction','Farming/TimedActions/ISHarvestPlantAction',
 'Farming/TimedActions/ISShovelAction','Farming/TimedActions/ISCurePlantAction','Farming/TimedActions/ISSeedActionNew','Farming/TimedActions/ISPlowAction','Farming/ISUI/ISFarmingMenu','Foraging/ISForageAction','Foraging/ISSearchManager','Foraging/ISForageIcon'}) do package.loaded[name]=true end
local now=0 getTimestampMs=function() return now end
getText=function(s) return s end isClient=function() return false end isMultiplayer=function() return false end
getPlayerData=function() return nil end forceDropHeavyItems=function() end ISLogSystem={logAction=function() end}
Metabolics={MediumWork='medium'}
local function square(x,y) return {getX=function() return x end,getY=function() return y end,getZ=function() return 0 end,canReachTo=function() return true end} end
local dest=square(10905,10035) local edge=square(10906,10035) local own=edge
local zone={enabled=true,settlementId='s',areas={{x=10905,y=10035,z=0,w=2,h=2}}}
local Zones={get=function() return zone end,contains=function(_,x,y,z) return x>=10905 and x<10907 and y>=10035 and y<10037 and z==0 end}
package.loaded['EmberRoutesProbe/Settlement/SettlementZones']=Zones
local item={getID=function() return 14 end,setJobType=function() end,setJobDelta=function() end,getFullType=function() return 'Base.CorpseMale' end}
local bodySquare=edge local identity='original' local itemWorld=true
local body={getSquare=function() return bodySquare end,getItem=function() return item end,
 getStaticMovingObjectIndex=function() return itemWorld and 0 or -1 end,
 getModData=function() return {} end,getPickUpSound=function() return 'pickup' end}
local Spatial={identity=function(b) return b==body and identity end,square=function() return dest end}
package.loaded['EmberRoutesProbe/Field/FieldSpatial']=Spatial
local Discovery={object=function(t) return itemWorld and t.x==bodySquare:getX() and t.y==bodySquare:getY() and t.z==0 and body or nil end,policy=function() return {corpseZoneId='dump'} end}
package.loaded['EmberRoutesProbe/Field/FieldDiscovery']=Discovery
package.loaded['EmberRoutesProbe/Field/FieldCargo']={}
package.loaded['EmberRoutesProbe/Work/LaborStore']={}
package.loaded['EmberRoutesProbe/Field/ToolRequirements']={}
local list={size=function() return itemWorld and 1 or 0 end,get=function() return body end}
getCell=function() return {getGridSquare=function(_,x,y,z) if x==bodySquare:getX() and y==bodySquare:getY() and z==0 then bodySquare.getDeadBodys=function() return list end return bodySquare end end} end
local dragging,turning,releaseRequested=false,true,false
local faced,grabType,anim,low,event=0,nil,nil,nil,nil
local x,y=10906.9,10035.5
local npc={getX=function() return x end,getY=function() return y end,getZ=function() return 0 end,
 getCurrentSquare=function() return own end,getSquare=function() return own end,isDraggingCorpse=function() return dragging end,
 isTimedActionInstant=function() return false end,faceThisObject=function(_,b) assert(b==body) faced=faced+1 end,
 shouldBeTurning=function() return turning end,reportEvent=function(_,e) event=e end,
 getDir=function() return 'W' end,
 playSound=function() return 1 end,stopOrTriggerSound=function() end,getEmitter=function() return {isPlaying=function() return false end} end,
 setMetabolicTarget=function() end,getPlayerNum=function() return -1 end,
 getInventory=function() return {setDrawDirty=function() end} end,
 pickUpCorpse=function(_,b,t) assert(b==body) grabType=t dragging=true itemWorld=false end,
 setDoGrappleLetGo=function() releaseRequested=true end}
local queued
ISTimedActionQueue={hasAction=function(a) return queued==a end,getTimedActionQueue=function() return {onCompleted=function() queued=nil end} end}
local function context()
 local c={npc=npc,job={id='job',scopeId='s',effects='KNOWN',payload={sequence=0,assets={},target={kind='CORPSE',identity='original',x=10910,y=10037,z=0}}}}
 c.same=function() return true end c.valid=function() return true end
 c.change=function(f) f(c.job) return true end
 c.unknown=function(reason) c.reason=reason c.job.effects='UNKNOWN' c.job.payload.attempt.state='UNKNOWN' return true end
 c.body={current=function() return true end,retained=function() return true end,snapshot=function() return {nativeStopped=false,nativeMask=4096} end,
 add=function(a) queued=a a.action={getJobDelta=function() return 0 end,setActionAnim=function(_,s) anim=s end,setAnimVariable=function(_,k,v) if k=='LootPosition' then low=v end end,setAllowedWhileDraggingCorpses=function() end} return true end}
 c.move=function(_,arrived) return arrived and 'Success' or 'Running' end
 return c
end
local Actions=require 'EmberRoutesProbe/Field/FieldActions'
local c=context()
local grab=Actions.new(c,{kind='GRAB_CORPSE',create=function() return ISGrabCorpseAction:new(npc,body) end,
 observe=function() return true,dragging,not dragging end})
grab.run() local native=queued
check(native.waitToStart==ISGrabCorpseAction.waitToStart,'adapter retains installed native waitToStart')
check(native:waitToStart() and faced==1,'native action faces actual corpse and waits for turning')
turning=false check(not native:waitToStart(),'native turning completion admits start')
native:start()
check(anim=='Loot' and low=='Low' and event=='EventLootItem','installed start preserves low loot animation and event')
native:update() check(faced==3,'installed update continues facing actual corpse')
native:complete() native:perform()
check(grab.run()=='Success' and grabType=='BwdDrag','installed complete grabs same original with native backward drag type')
local Operations=require 'EmberRoutesProbe/Field/FieldOperations'
c=context() c.job.payload.holding=true
check(Operations.step(c)=='Running' and not c.node,'entering dump-zone edge is not arrival at drop point')
x=10905.5 own=dest
check(Operations.step(c)=='Running' and c.node,'exact drop-point arrival creates native drop action')
check(c.node.run()=='Running','drop action queued') native=queued native:start()
check(releaseRequested and dragging,'native start requests asynchronous release without synthetic corpse mutation')
native:complete() native:perform()
check(c.node.run()=='Running','native queue completion alone cannot settle an unreleased corpse')
now=100 dragging=false itemWorld=true bodySquare=edge
check(c.node.run()=='Success' and c.job.payload.workDone and not c.job.payload.holding,'physical original in zone confirms async delivery')
c=context() c.job.payload.target.x=10906 c.job.payload.target.y=10035
c.job.payload.attempt={kind='DROP_CORPSE',state='ABORTED',dispatched=true}
check(Operations.reconcileCorpse(c) and c.job.payload.workDone and c.job.payload.attempt.state=='APPLIED','old known aborted record recovers from actual original in current zone')
c=context() c.job.payload.target.x=10906 c.job.payload.target.y=10035
c.job.payload.attempt={kind='DROP_CORPSE',state='ABORTED'} identity='replacement'
check(Operations.reconcileCorpse(c) and not c.job.payload.workDone,'replacement at same coordinate cannot settle original') identity='original'
c.job.effects='UNKNOWN'
check(Operations.reconcileCorpse(c) and not c.job.payload.workDone,'unknown effect is not automatically released')
dragging=true releaseRequested=false c=context() c.job.payload.holding=true
Operations.step(c) c.node.run() native=queued native:start() native:complete() native:perform()
check(c.node.run()=='Running','new release begins its own observation window')
now=5200
check(c.node.run()=='Failure' and c.job.effects=='UNKNOWN' and c.job.payload.holding,
 'release timeout preserves corpse responsibility and marks uncertainty')
-- Actual workflow must request native corpse positioning before unequipping.
dragging=false itemWorld=true bodySquare=edge identity='original'
local secondary={getID=function() return 55 end}
npc.getPrimaryHandItem=function() return nil end
npc.getSecondaryHandItem=function() return secondary end
package.loaded['EmberRoutesProbe/Work/LaborStore'].owner=function() end
ISUnequipAction={new=function(_,who,what) assert(who==npc and what==secondary) return {isValid=function() return true end,start=function() end,update=function() end,perform=function() end,stop=function() end} end}
local motion='MOVING' local requests=0
EmberRoutesProbeJava={motionResult=function() return motion end}
c=context() c.job.payload.target.x=bodySquare:getX() c.job.payload.target.y=bodySquare:getY()
c.body.move=function(_,point) check(point.corpse==body,'same original is passed to native planner') requests=requests+1 return true,'MOVE_REQUESTED_CORPSE' end
check(Operations.step(c)=='Running' and requests==1 and not c.node,'corpse workflow first requests dedicated native positioning')
check(Operations.step(c)=='Running' and requests==1 and not c.node,'native positioning is not updated by a second Lua path action')
motion='REACHED'
check(Operations.step(c)=='Running' and c.node and c.job.payload.attempt.kind=='UNEQUIP','secondary-only hand is unequipped after native arrival')
check(c.node.run()=='Running','secondary unequip uses owned native action queue')
c=context() c.job.payload.target.x=bodySquare:getX() c.job.payload.target.y=bodySquare:getY()
c.body.move=function() return true,'CORPSE_NO_APPROACH' end
check(Operations.step(c)=='Failure' and not c.node,'unavailable native approach never falls back to arbitrary adjacent pickup')
print('PASS '..n..' installed native corpse Lua/recovery checks; animation engine and physics mocked')
