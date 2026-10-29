local Carry=require 'EmberRoutesProbe/ProductionCarry'
local Producers=require 'EmberRoutesProbe/LaborProducers'
local checks=0
local function check(ok,label) checks=checks+1 assert(ok,label) end
local root={weight=0,capacity=50}
function root:getCapacityWeight() return self.weight end
function root:getEffectiveCapacity() return self.capacity end
function root:getFreeCapacity() return math.max(0,self.capacity-self.weight) end
local npc={maximum=12}
function npc:getInventory() return root end
function npc:getMaxWeight() return self.maximum end
function npc:getInventoryWeight() return root.weight end
check(Carry.fits(npc,17.9),'second heavy load level allowed')
check(not Carry.fits(npc,18),'third level boundary rejected')
check(not Carry.fits(npc,17.999),'floating margin below third level')
root.weight=5
check(Carry.fits(npc,10),'existing effective bag weight counted, no raw contents rescan')
check(Producers.freeCarry(npc)==7,'ordinary logistics retains normal capacity limit')
npc.maximum=8
check(not Carry.fits(npc,10),'native strength/status decrease rechecked')
npc.maximum=16
check(Carry.fits(npc,15),'native strength/trait increase respected without duplicate bonus')
root.capacity=10
check(not Carry.fits(npc,6),'native effective container limit retained')
root.capacity=50 root.weight=1 npc.maximum=8
check(Carry.fits(npc,9.5,9,9),'log and saw before, planks and saw after: phase peak, not sum')
check(not Carry.fits(npc,9.5,0,9),'unproven consumption cannot free capacity')
local item={getUnequippedWeight=function() return 9 end}
local io={isDestroy=function() return true end}
check(Carry.consumed(item,{keep=false,io=io})==9,'whole destroy input receives credit')
check(Carry.consumed(item,{keep=true,io=io})==0,'tool never receives consumption credit')
check(Carry.consumed(item,{keep=false,io={}})==0,'unknown/partial input stays conservative')
local script={getReplaceOnDeplete=function() return nil end}
local plain={getUnequippedWeight=function() return 6 end,getCurrentUses=function() return 1 end,
    getScriptItem=function() return script end,getReplaceOnUse=function() return nil end,
    getFluidContainer=function() return nil end,getContainer=function() return {} end}
local normal={isDestroy=function() return false end,isUsesPartialItem=function() return false end,
    hasConsumeFromItem=function() return false end,hasCreateToItem=function() return false end}
check(Carry.consumed(plain,{keep=false,io=normal})==6,'ordinary single-use branch is consumed despite mode not Destroy')
root.weight=0 npc.maximum=6
check(Carry.fits(npc,7,Carry.consumed(plain,{keep=false,io=normal}),3),
    'reported branch and saw: peak is 7, not input plus output 10')
plain.getCurrentUses=function() return 5 end
check(Carry.consumed(plain,{keep=false,io=normal})==0,'multi-use ordinary input does not free its full weight')
plain.getCurrentUses=function() return 1 end
script.getReplaceOnDeplete=function() return 'Base.Bowl' end
check(Carry.consumed(plain,{keep=false,io=normal})==0,'replacement vessel is not treated as absent')
script.getReplaceOnDeplete=function() return nil end
normal.isUsesPartialItem=function() return true end
check(Carry.consumed(plain,{keep=false,io=normal})==0,'partial-use inputs cannot receive whole-item credit')
normal.isUsesPartialItem=function() return false end
local spec={inputs={{slot=0,count=1,keep=false,io=normal}},outputWeight=3}
local plan={materials={{id=1,slot=0}},tools={},locations={[1]={item=plain}}}
check(Carry.plan(npc,spec,plan),'public preclaim uses exact one-batch weights')
plan.materials[2]={id=2,slot=0} plan.locations[2]={item=plain}
check(Carry.plan(npc,spec,plan),'future batches in a large public order are not carried all at once')
npc.maximum=3 check(not Carry.plan(npc,spec,plan),'genuine inability to carry inputs rejects before public allocation')
root.weight=0/0
check(not Carry.fits(npc,1),'NaN weight fails closed')
root.weight=0 npc.maximum=math.huge
check(not Carry.fits(npc,1),'infinite capability fails closed')
npc.maximum=0
check(not Carry.fits(npc,0),'zero capability fails closed')
local otherRoot={getCapacityWeight=function() return 2 end,getEffectiveCapacity=function() return 50 end}
local other={getInventory=function() return otherRoot end,getMaxWeight=function() return 8 end}
local allowed,facts=Carry.fits(other,9,0,0)
check(allowed and facts.weight==2 and facts.maximum==8 and facts.peak==11,'second NPC uses only its own weight and limit')
check(not Carry.fits(npc,0),'first NPC invalid capacity cannot borrow second NPC capability')
print('PASS '..checks..' production carry policy checks; native attributes mocked')
