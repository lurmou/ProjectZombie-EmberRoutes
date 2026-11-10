-- Real installed equipment completion + production cleaning preparation.
local n=0 local function check(v,m) n=n+1 assert(v,m) end
-- Installed native actions need the vanilla game tree: ER_PZ_ROOT must point
-- at the installed ProjectZomboid root. Without it, skip instead of dying
-- on a hardcoded Windows install path. No behaviour change when it is set.
local Vanilla=dofile('tests/lua/fixtures/vanilla-game.lua')
local gameRoot,why=Vanilla.root()
if not gameRoot then print('SKIP field-cleaning-native-test: '..why..'; set ER_PZ_ROOT to run'); return end
local vanilla=gameRoot..'/media/lua/shared/'
dofile(vanilla..'ISBaseObject.lua') package.loaded.ISBaseObject=true
dofile(vanilla..'TimedActions/ISBaseTimedAction.lua') package.loaded['TimedActions/ISBaseTimedAction']=true
dofile(vanilla..'TimedActions/ISEquipWeaponAction.lua')
for _,name in ipairs({'ISCleanBlood','ISChopTreeAction','ISGrabCorpseAction','ISDropCorpseAction','ISUnequipAction','ISEquipWeaponAction'}) do package.loaded['TimedActions/'..name]=true end
for _,name in ipairs({'Farming/TimedActions/ISWaterPlantAction','Farming/TimedActions/ISHarvestPlantAction','Farming/TimedActions/ISShovelAction','Farming/TimedActions/ISCurePlantAction','Farming/TimedActions/ISSeedActionNew','Farming/TimedActions/ISPlowAction','Farming/ISUI/ISFarmingMenu','Foraging/ISForageAction','Foraging/ISSearchManager','Foraging/ISForageIcon'}) do package.loaded[name]=true end
getText=function(s) return s end isServer=function() return false end
getPlayerHotbar=function() end getPlayerInventory=function() return {refreshBackpacks=function() end} end
instanceof=function(item,kind) return kind=='HandWeapon' and item.weapon==true end
ItemTag={} ItemType={}
local root={} local primary,secondary
local function item(id,two)
 return {weapon=two,getID=function() return id end,getContainer=function() return root end,
 isTwoHandWeapon=function() return two end,isRequiresEquippedBothHands=function() return false end,
 isForceDropHeavyItem=function() return false end,canBeActivated=function() return false end,
 getCurrentUsesFloat=function() return 1 end,getName=function() return 'tool' end,
 getSwingAnim=function() return 'tool' end}
end
local mop,fluid=item(1,true),item(2,false)
root.getFirstEvalRecurse=function(_,predicate) for _,v in ipairs({mop,fluid}) do if predicate(v) then return v end end end
local npc={getInventory=function() return root end,getPrimaryHandItem=function() return primary end,
 getSecondaryHandItem=function() return secondary end,setPrimaryHandItem=function(_,v) primary=v end,
 setSecondaryHandItem=function(_,v) secondary=v end,getClothingItem_Back=function() end,
 isEquippedClothing=function() return false end,getCurrentSquare=function() return {} end,
 getPlayerNum=function() return -1 end,isTimedActionInstant=function() return false end}
package.loaded['EmberRoutesProbe/Work/LaborStore']={validField=function() return true end,validToolUse=function() return true end}
package.loaded['EmberRoutesProbe/Field/ToolRequirements']={matchPhysical=function() return true end}
local square={}
package.loaded['EmberRoutesProbe/Field/FieldSpatial']={square=function() return square end,reachable=function() return true end,walkway=function() return true end,adjacent=function() return square end}
package.loaded['EmberRoutesProbe/Field/FieldDiscovery']={object=function() end}
package.loaded['EmberRoutesProbe/Field/FieldCargo']={}
local spec
package.loaded['EmberRoutesProbe/Field/FieldActions']={new=function(_,h) spec=h return {} end}
local cleanCount=0
ISCleanBlood={new=function(_,who,sq,cleaner) check(who==npc and sq==square and cleaner==fluid,'native clean receives same NPC square and cleaner original') cleanCount=cleanCount+1 return {} end}
local O=require 'EmberRoutesProbe/Field/FieldOperations'
local c={npc=npc,job={id='j',npcId='n',payload={target={kind='STAIN',tools={1,2}}}},token={}}
c.body={snapshot=function() return {nativeStopped=true} end}
c.move=function() return 'Success' end
-- Verify the actual native behavior that made the old blanket equip loop unsafe.
primary=mop secondary=mop
ISEquipWeaponAction.complete(ISEquipWeaponAction:new(npc,fluid,50,false,false))
check(primary==nil and secondary==fluid,'installed native secondary equip removes primary two-handed item')
primary=nil secondary=nil
O.step(c) check(spec.kind=='EQUIP','mop is prepared first')
local action=spec.create() ISEquipWeaponAction.complete(action)
check(primary==mop and secondary==mop,'native preparation equips mop in both hands')
c.node=nil O.step(c)
check(spec.kind=='STAIN','two-hand cleaner remains in inventory instead of displacing mop')
spec.create() check(cleanCount==1 and primary==mop and secondary==mop,'cleaning starts with both hands still holding mop')
-- Single-hand cloth follows the separate vanilla branch.
mop.weapon=false mop.isTwoHandWeapon=function() return false end
primary=mop secondary=nil c.node=nil O.step(c)
check(spec.kind=='EQUIP','single-hand cloth equips cleaner in secondary hand')
action=spec.create() ISEquipWeaponAction.complete(action)
c.node=nil O.step(c) check(spec.kind=='STAIN' and primary==mop and secondary==fluid,'cloth and cleaner reach native cleaning without equip loop')
-- Other field preparation uses the same real native equip action.
local plant={}
local discovery=require 'EmberRoutesProbe/Field/FieldDiscovery'
discovery.object=function() return plant end discovery.plant=function() return plant end
require('EmberRoutesProbe/Field/FieldSpatial').identity=function() return 'plant' end

c.node=nil c.job.payload.target={kind='WATER',identity='plant',tools={1}} primary=nil secondary=nil
O.step(c) check(spec.kind=='EQUIP','watering equips the carried container before approaching the plant')
action=spec.create() ISEquipWeaponAction.complete(action)
check(primary==mop,'watering original is held in primary hand')
c.node=nil c.job.payload.target={kind='CLEAR',identity='plant',tools={1}} primary=mop secondary=nil
dofile(vanilla..'Farming/TimedActions/ISShovelAction.lua')
O.step(c) check(spec.kind=='CLEAR','shoveling preserves native work kind')
action=spec.create() check(action.maxTime==40 and action.item==mop and action.plant==plant,'shoveling uses installed menu duration and originals')
c.node=nil c.job.payload.target={kind='TREE',identity='plant',tools={1}}
mop.weapon=true mop.isTwoHandWeapon=function() return true end primary=nil secondary=fluid
O.step(c) check(spec.kind=='EQUIP','tree tool is equipped through native action')
action=spec.create() check(not action.twoHands,'tree preparation preserves occupied secondary hand like vanilla doChopTree')
ISEquipWeaponAction.complete(action)
check(primary==mop and secondary==fluid,'native axe equip keeps existing secondary original')

-- Corpse cleaning hand item and custody unequip lifecycle checks
local corpseObj={getStaticMovingObjectIndex=function() return 0 end,getSquare=function() return square end}
discovery.object=function() return corpseObj end
require('EmberRoutesProbe/Field/FieldSpatial').identity=function() return 'corpse_1' end
EmberRoutesProbeJava={motionResult=function() return 'REACHED' end,carrierId=function() return 'n' end}
c.npc.isDraggingCorpse=function() return false end
c.npc.getSquare=function() return square end
square.canReachTo=function() return true end
c.body.move=function() return true,'MOVE_REQUESTED_CORPSE' end

local custodyMop=mop
package.loaded['EmberRoutesProbe/Work/LaborStore'].owner=function(id)
    if id==1 then return {taskId='custody:n:1'} end
    if id==999 then return {taskId='other_job'} end
    return nil
end
package.loaded['EmberRoutesProbe/Work/LaborStore'].canClaimTool=function(npcId,id)
    return npcId=='n' and id==1
end

c.node=nil c.job.payload.target={kind='CORPSE',identity='corpse_1'} c.job.payload.workDone=nil
c.corpseApproach={body=corpseObj,reached=true}
primary=custodyMop secondary=nil
local state=O.step(c)
check(state=='Running' and spec.kind=='UNEQUIP','held custody tool triggers UNEQUIP instead of Failure')

local illegalItem=item(999,false)
primary=illegalItem secondary=nil c.node=nil c.corpseApproach={body=corpseObj,reached=true}
state=O.step(c)
check(state=='Failure' and c.reason=='FIELD_HANDS_OCCUPIED','unauthorized held item is rejected with FIELD_HANDS_OCCUPIED')

print('PASS '..n..' installed native cleaning equipment checks; animation/physics NOT RUN')
