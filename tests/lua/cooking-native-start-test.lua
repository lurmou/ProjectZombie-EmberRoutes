-- Installed native start and production adapter; domain admission is a stub.
-- Installed native actions need the vanilla game tree: ER_PZ_ROOT must point
-- at the installed ProjectZomboid root. Without it, skip instead of dying
-- on a hardcoded Windows install path. No behaviour change when it is set.
local Vanilla=dofile('tests/lua/fixtures/vanilla-game.lua')
local game,why=Vanilla.sharedRoot()
if not game then print('SKIP cooking-native-start-test: '..why..'; set ER_PZ_ROOT to run'); return end
dofile(game..'ISBaseObject.lua') package.loaded.ISBaseObject=true
dofile(game..'TimedActions/ISBaseTimedAction.lua') package.loaded['TimedActions/ISBaseTimedAction']=true
dofile(game..'TimedActions/ISAddItemInRecipe.lua') package.loaded['TimedActions/ISAddItemInRecipe']=true
package.loaded['TimedActions/ISToggleStoveAction']=true package.loaded['TimedActions/ISInventoryTransferAction']=true
isClient=function() return false end isServer=function() return false end getText=function(k) return k end
Perks={Cooking='Cooking'}
local root={contains=function() return true end} local sound,jobType,animationCalls=0,nil,0
local function item(id)
 return {getID=function() return id end,getFullType=function() return 'Base.Test'..id end,
 getExtraItems=function() end,isSpice=function() return false end,getDisplayName=function() return 'item' end,
 setJobType=function(_,v) jobType=v end,getContainer=function() return root end}
end
local base,ingredient=item(1),item(2)
local npc={getInventory=function() return root end,isTimedActionInstant=function() return false end,
 getPerkLevel=function() return 0 end,getEmitter=function() return {playSoundImpl=function() sound=sound+1 return 1 end} end}
local recipe={getOriginalname=function() return 'recipe' end,isItemUsableInRecipe=function() return true end,
 isResultItem=function() return true end,isSpiceAdded=function() return false end,getAddIngredientSound=function() end,
 getItemsCanBeUse=function() return {contains=function() return true end} end}
local function instrument(a) a.action={setActionAnim=function() animationCalls=animationCalls+1 end} return a end
local baseline=instrument(ISAddItemInRecipe:new(npc,recipe,base,ingredient)) baseline:start()
local baselineType=jobType
assert(sound==1 and animationCalls==0)
local c={job={payload={sequence=0,profileId='recipe',assets={}}},npc=npc,token={}}
package.loaded['EmberRoutesProbe/Cooking/CookingContext']={active=function() return true end,current=function() return true end,
 publish=function(_,j) c.job=j return true end}
package.loaded['EmberRoutesProbe/Cooking/CookingRecord']={limit=96,copy=function(j) return j end,
 begin=function(j,kind,ids,spec) j.payload.sequence=1 j.payload.attempt={id='attempt',state='PREPARED',kind=kind,itemIds=ids,spec=spec} return j end}
package.loaded['EmberRoutesProbe/Cooking/CookingInventory']={asset=function(_,id) return {fullType='Base.Test'..id,custody='HELD'} end,
 contains=function() return true end,foodStamp=function(i) return i:getID() end,snapshot=function() return {} end,amount=function() return 1 end}
package.loaded['EmberRoutesProbe/Cooking/CookingFood']={read=function() return {food=true,safe=true,raw=1} end}
package.loaded['EmberRoutesProbe/Work/LaborStore']={validCooking=function() return true end}
package.loaded['EmberRoutesProbe/Cooking/CookingPolicy']={finite=function(v) return type(v)=='number' end,maxSpices=2}
for _,name in ipairs({'ContainerRegistry','WorkTransfer','CookingDuty','ProductionCarry'}) do package.loaded['EmberRoutesProbe/'..name]={} end
local queued
ISTimedActionQueue={hasAction=function(a) return a==queued end}
c.body={retained=function() return true end,add=function(a) queued=instrument(a) return true end}
local Actions=require 'EmberRoutesProbe/Cooking/CookingActions'
assert(Actions.add(c,1,recipe,base,ingredient).run()=='Running')
queued:start()
assert(jobType==baselineType and sound==2 and animationCalls==0,'adapter preserves installed start sound/job type without adding Craft animation')
assert(queued.waitToStart==baseline.waitToStart,'native waiting lifecycle remains inherited')
print('PASS installed cooking start parity; claims/effects/animation engine NOT RUN')
