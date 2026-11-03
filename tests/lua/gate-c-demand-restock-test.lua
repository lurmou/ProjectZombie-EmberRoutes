-- Existing PublicWork/stock entry with independent cooking/craft observations;
-- real farming discovery and public directory; native production effects mocked.
dofile('tests/lua/public-work-test.lua')
local n=0 local function check(v,m) n=n+1 assert(v,m) end
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local Public=require 'EmberRoutesProbe/PublicWork'
local actor=getSpecificPlayer(0) local root={}
Registry.data=function() return root end
Registry.resolve=function(id) return {id=id} end
local now=1000000 getTimestampMs=function() return now end
EmberRoutesProbeJava.workerCount=function() return 0 end
local recipes={craft={id='craft',name='Planks',product='Base.Plank',yield=3,surface=false,recipe={}},
    meal={id='meal',name='Meal',product='Base.Meal',yield=1,surface=false,recipe={},cooking=true}}
package.loaded['EmberRoutesProbe/ProductionRecipe'].read=function(id) return recipes[id] end
package.loaded['EmberRoutesProbe/CookingOrders'].describe=function(id) if id=='meal' then return recipes.meal end end
local cookingCount,craftCount=0,0
package.loaded['EmberRoutesProbe/CookingService']={stock=function() return {state='READY',complete=true,knownCount=cookingCount} end}
package.loaded['EmberRoutesProbe/WarehouseIndex']={watch=function() return function() end end,
    candidates=function() return {state='READY',complete=true,knownCount=craftCount} end,refresh=function() end}
package.loaded['EmberRoutesProbe/ProductionChain'].new=function() return {step=function() return {nodes={}} end} end
Public.prepareRecovery()
check(Public.saveRule(actor,'s','craft',5,4)=='RULE_SAVED','crafting independent threshold registered')
check(Public.saveRule(actor,'s','meal',2,2)=='RULE_SAVED','cooking independent threshold registered')
local function tick() now=now+3000 Public.tick() end
for _=1,4 do tick() end
local craft=Public.rule('s','Base.Plank') local meal=Public.rule('s','Base.Meal')
check(craft.activeOrder and meal.activeOrder and craft.activeOrder~=meal.activeOrder,'each domain triggers its own cycle without a worker')
local craftId,mealId=craft.activeOrder,meal.activeOrder
check(root.publicWork.orders[craftId].target==6 and root.publicWork.orders[craftId].quantity==4,'restock preserves requested vs rounded actual')
Public.saveRule(actor,'s','craft',9,7) Public.saveRule(actor,'s','meal',9,7)
for _=1,4 do tick() end
check(Public.rule('s','Base.Plank').activeOrder==craftId and Public.rule('s','Base.Meal').activeOrder==mealId,'demand changes do not create new intents for active cycles')
local token=Public.requestId() local _,manualId=Public.create(actor,'s','craft',4,nil,token)
check(Public.overlapReason(manualId)=='CYCLE_ACTIVE','first restock cycle suppresses later manual production')
-- Cross-target evidence must suppress delivery for either actual destination.
local business=package.loaded['EmberRoutesProbe/BusinessJobs']
local oldRecord=business.record
local splitDone=false
business.record=function(id) if id=='split-job' then return {state=splitDone and 'DONE' or 'RUNNING',released=splitDone,outputs={{fullType='Base.Plank',destination='D1'},
    {fullType='Base.Plank',destination='D2'}}} end if oldRecord then return oldRecord(id) end end
root.publicWork.orders[craftId].jobId='split-job' root.publicWork.orders[craftId].npcId='alice'
local delivery={state='WAITING',settlementId='s',destinationId='D2',overlapSequence=999}
check(Public.deliveryOverlapReason(delivery,{fullType='Base.Plank'})=='CYCLE_ACTIVE','second output destination retains first-created-wins evidence')
splitDone=true
root.publicWork.orders[craftId].state='DONE' root.publicWork.orders[mealId].state='DONE'
root.publicWork.orders[manualId].state='CANCELLED'
craftCount=20 cookingCount=20
for _=1,4 do tick() end
check(not Public.rule('s','Base.Plank').activeOrder and not Public.rule('s','Base.Meal').activeOrder,'independent known settlements close both cycles')
-- First manual order stops a new refill until its own settlement.
local _,earlier=Public.create(actor,'s','meal',2,nil,Public.requestId()) cookingCount=0
for _=1,4 do tick() end
check(not Public.rule('s','Base.Meal').activeOrder and Public.rule('s','Base.Meal').reason=='MANUAL_ORDER_ACTIVE','manual-first intent suppresses later cooking restock')
root.publicWork.orders[earlier].state='DONE'
for _=1,4 do tick() end
check(Public.rule('s','Base.Meal').activeOrder~=mealId,'new stock deficit after settlement starts one new cycle')
local nextMeal=Public.rule('s','Base.Meal').activeOrder root.publicWork.orders[nextMeal]=nil
for _=1,4 do tick() end
check(Public.rule('s','Base.Meal').activeOrder==nextMeal and Public.rule('s','Base.Meal').reason=='TASK_RECORD_MISSING','missing order is diagnostic, not settlement or a duplicate cycle')
-- Farming demand is a physical plant condition, not an invented product order.
package.loaded['EmberRoutesProbe/FieldDiscovery']=nil
package.loaded['EmberRoutesProbe/FieldSpatial']={inside=function() return true end,
    identity=function() return 'plant-1' end,square=function() return {} end}
package.loaded['EmberRoutesProbe/JobPolicyService']={get=function() return {} end}
package.loaded['EmberRoutesProbe/SettlementZones']={revision=function() return 1 end}
local plant={x=2,y=3,z=0,state='seeded',typeOfSeed='Carrots',waterLvl=10,
    isAlive=function() return true end,canHarvest=function() return false end,getObject=function() return {} end}
CFarmingSystem={instance={getLuaObjectCount=function() return 1 end,getLuaObjectByIndex=function() return plant end,getLuaObjectAt=function() return plant end}}
local D=require 'EmberRoutesProbe/FieldDiscovery'
local env={entry={id='s',revision=1},npc={getX=function() return 2 end,getY=function() return 3 end},now=now}
local rows=D.targets(env,'farming') check(#rows==1 and rows[1].kind=='WATER','farming independently observes real water demand')
local selected=rows[1]
local Directory=require 'EmberRoutesProbe/TaskDirectory' local directory=Directory.new()
local Field=require 'EmberRoutesProbe/FieldWork'
env.directory=directory env.candidates={}
check(Field.offer(env,'farming',selected),'farming demand enters existing public directory')
local offer=env.candidates[1]
check(directory:claim(offer.key,offer.revision,'alice','farm-job'),'one owner claims plant intent')
plant.waterLvl=20 env.now=env.now+1000 env.candidates={}
rows=D.targets(env,'farming')
check(not Field.offer(env,'farming',rows[1]),'water demand change alone cannot duplicate a claimed intent')
plant.waterLvl=100 env.now=env.now+1000 rows=D.targets(env,'farming')
check(#rows==0 and not D.claim(selected,env.npc,env.entry,'farming'),'satisfied demand disappears and stale claim is rejected')
check(directory:release(offer.key,'farm-job',{effects='KNOWN',obligationsCleared=true}),'known completed farming intent settles through existing directory')
plant.canHarvest=function() return true end env.now=env.now+1000 rows=D.targets(env,'farming')
check(#rows==1 and rows[1].kind=='HARVEST','later harvest condition independently triggers farming work')
print('PASS '..n..' Gate C demand/restock checks; domain effects/native game UNVERIFIED')
