local checks=0 local function check(v,s) checks=checks+1 assert(v,s) end
local function list(t) return {size=function() return #t end,get=function(_,i) return t[i+1] end} end
local root={} local claimed={}
package.loaded['EmberRoutesProbe/ContainerRegistry']={data=function() return root end,accepts=function() return true end}
package.loaded['EmberRoutesProbe/LaborStore']={owner=function(id) return claimed[id] end}
package.loaded['EmberRoutesProbe/CraftSupply']={}
CharacterStat={HUNGER='hunger',THIRST='thirst',FATIGUE='fatigue',ENDURANCE='endurance'}
function instanceof(o,kind) return o and o.type==kind end
Fluid={Water='water'}
local stats={hunger=0.4,thirst=0.3,fatigue=0.2,endurance=0.9}
local hp=100 local seen={} local danger=0
local npc={getStats=function() return {get=function(_,k) return stats[k] end} end,
    getCurrentSquare=function() return {} end,isDead=function() return false end,
    getSpottedList=function() return list(seen) end,getSurroundingAttackingZombies=function() return danger end,
    isOnFire=function() return false end,getX=function() return 0 end,getY=function() return 0 end,getZ=function() return 0 end,
    getBodyDamage=function() return {getOverallBodyHealth=function() return hp end} end}
local Observer=require 'EmberRoutesProbe/NeedsObserver'
check(Observer.sample(npc,'a',0).safe,'bounded native sample with known safety')
danger=1 check(not Observer.sample(npc,'a',1).safe,'attacker prevents ordinary self-care') danger=0
seen={{type='IsoZombie',isDead=function() return false end,getX=function() return 4 end,
    getY=function() return 0 end,getZ=function() return 0 end}}
check(not Observer.sample(npc,'a',2).safe,'visible nearby live zombie prevents eating') seen={}
hp=99 check(not Observer.sample(npc,'a',100).safe,'new damage starts safety cooldown')
check(Observer.sample(npc,'a',3101).safe,'safety cooldown expires without inventing healing')
stats.hunger=0/0 check(not Observer.sample(npc,'a',3102),'invalid Stats is unknown') stats.hunger=0.4
local objects={} local container={getItems=function() return list(objects) end}
npc.getInventory=function() return container end
local function food(id)
    return {type='Food',getID=function() return id end,getFullType=function() return 'Base.Apple' end,getIsCraftingConsumed=function() return false end,
        getBaseHunger=function() return -0.3 end,getHungChange=function() return -0.3 end,getHungerChange=function() return -0.3 end,
        isRotten=function() return false end,isBurnt=function() return false end,isPoison=function() return false end,getPoisonPower=function() return 0 end,isTainted=function() return false end,isCooked=function() return false end,isCookable=function() return false end,isFrozen=function() return false end,isSpice=function() return false end,
        isbDangerousUncooked=function() return false end,getRequireInHandOrInventory=function() return nil end,
        getContainer=function() return container end}
end
objects={food(1),food(2)} claimed[1]={taskId='production'}
local Resources=require 'EmberRoutesProbe/SelfCareResources'
local scan=Resources.new({},npc,'EAT',true)
local found,done=scan:step(1)
check(not found and not done,'one global scan unit cannot inspect more than one item')
found,done=scan:step(1)
check(found and found.id==2 and done,'does not consume production-owned food')
objects[2].isRotten=function() return true end
check(not Resources.eligible(objects[2],'EAT'),'rotten food excluded')
objects[2].isRotten=function() return false end
objects[2].getRequireInHandOrInventory=function() return list({'lighter'}) end
check(not Resources.eligible(objects[2],'EAT'),'extra ignition/tool side effects excluded')
local restored=Resources.new({},npc,'CUSTODY',true,1,nil,'production')
found,done=restored:step(1)
check(found and found.id==1 and done,'custody recovery can locate the exact original with its own claim')
local unstable=Resources.new({},npc,'EAT',true) objects[#objects+1]=food(3)
local _,ended,reason=unstable:step(1)
check(ended and reason=='INVENTORY_CHANGED','changed source invalidates observation instead of assuming empty')
local own=objects[3] claimed[3]={taskId='personal'}
check(Resources.revalidate({item=own,id=3,container=container,npc=npc},'EAT','personal'),
    'grant revalidation accepts only the exact routine owner')
check(not Resources.revalidate({item=own,id=3,container=container,npc=npc},'EAT','other'),
    'grant revalidation refuses another claim owner')
local detached={isInCharacterInventory=function() return false end}
own.getContainer=function() return detached end
check(not Resources.revalidate({item=own,id=3,container=detached,npc=npc},'EAT','personal'),
    'bag removed from NPC before body grant is not an available personal supply')
print('PASS '..checks..' native-observation/resource-budget checks; world userdata mocked')
