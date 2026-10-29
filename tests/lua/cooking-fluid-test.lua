-- Installed progressive pour action, real Jobs/Claims/receipts. Physical fluid
-- mutation is a host double; this is not an in-game pouring/animation result.
local w=dofile('tests/lua/cooking-water-test.lua') local f=w.f
local Record=require 'EmberRoutesProbe/CookingRecord'
local Context=require 'EmberRoutesProbe/CookingContext'
local Store=require 'EmberRoutesProbe/LaborStore'
local Fluids=require 'EmberRoutesProbe/CraftFluids'
local Pour=require 'EmberRoutesProbe/CookingFluidTransfer'
local checks=0 local function check(v,m) checks=checks+1 assert(v,m) end
local previousInstance=instanceof
function instanceof(value,kind)
    if kind=='IsoObject' then return value and value.getSquare~=nil or false end
    if kind=='InventoryItem' then return value and value.getID~=nil or false end
    return previousInstance(value,kind)
end
local function fluid(owner,amount)
    local c={owner=owner,amount=amount,capacity=10}
    function c:getAmount() return self.amount end function c:getCapacity() return self.capacity end
    function c:isPureFluid(kind) return kind=='Water' end
    function c:createFluidSample()
        local count=self.amount>0 and 1 or 0
        return {size=function() return count end,getFluid=function() return {getFluidTypeString=function() return 'Water' end} end,
            getPercentage=function() return 1 end,release=function() end}
    end
    return c
end
ISFluidContainer={new=function(_,value) return {isValid=function() return true end,
    getOwner=function() return value.owner end,getFluidContainer=function() return value end,
    getFluidObject=function() return value end,sync=function() end} end}
ISFluidUtil={getMinTransferActionTime=function() return 10 end,getTransferActionTimePerLiter=function() return 100 end}
package.loaded['Fluids/ISFluidContainer']=true package.loaded['Fluids/ISFluidUtil']=true
dofile('D:/Software/GameApp/steam/steamapps/common/ProjectZomboid/media/lua/shared/Fluids/ISFluidTransferAction.lua')
package.loaded['Fluids/ISFluidTransferAction']=true
function getPlayer() error('NPC pouring must not borrow the real player inventory gate') end
Metabolics={LightDomestic=1,HeavyDomestic=2,MediumWork=3}
function f.npc:setMetabolicTarget() end
local calls=0
FluidContainer={CanTransfer=function(a,b) return a~=b and a.amount>0 and b.amount<b.capacity end,
    Transfer=function(a,b,amount)
        local token=assert(Store.owner(b.owner.id))
        local job=require('EmberRoutesProbe/TaskJobs').current():peek(token.taskId)
        assert(job.effects=='UNKNOWN' and job.payload.attempt.state=='COMMITTING','effect barrier precedes every native pour')
        calls=calls+1 local n=math.max(0,math.min(amount,a.amount,b.capacity-b.amount))
        a.amount=a.amount-n b.amount=b.amount+n
    end}
local c,target=w.setup() local source=f.item('Base.WaterBottle',false)
source.fluid=fluid(source,4) target.fluid=fluid(target,0)
function source:getFluidContainer() return self.fluid end
function source:getItemHeat() return 1 end function target:getItemHeat() return 1 end
local j=Record.copy(c.job)
j.payload.assets[#j.payload.assets+1]={id=source.id,fullType=source.kind,custody='HELD',role='TOOL'}
j.payload.claims[#j.payload.claims+1]='item:'..source.id assert(Context.publish(c,j)) c.items[source.id]=source
local leaf=assert(Pour.new(c,1,source,target,4)) assert(leaf.run()=='Running')
local action=f.queued() action:start() action.delta=.4 action:update()
check(math.abs(target.fluid.amount-1.6)<.000001 and c.job.effects=='UNKNOWN' and c.progressive,
    'native update creates partial fluid progress inside the same protected attempt')
action.delta=.6 action:update() assert(leaf.halt())
check(leaf.run()=='Success' and c.job.effects=='KNOWN' and c.job.payload.attempt.receipt.partial,
    'controlled stop accounts for partial native progress without restoring either container')
check(math.abs(source.fluid.amount-1.6)<.000001 and math.abs(target.fluid.amount-2.4)<.000001,
    'partial transfer conserves real source and target volumes')
local before=calls
check(Pour.new(c,1,source,target,4).run()=='Success' and calls==before,'completed receipt replay cannot pour twice')
leaf=assert(Pour.new(c,2,source,target,4)) assert(leaf.run()=='Running')
action=f.queued() action:start() action:complete() action:complete() action:perform()
check(leaf.run()=='Success' and math.abs(target.fluid.amount-4)<.000001 and source.fluid.amount==0,
    'continuation recalculates from the remaining original liquid and fences duplicate completion')
local beforeA={amount=2,capacity=10,components={{kind='Water',amount=2}}}
local afterA={amount=1,capacity=10,components={{kind='Water',amount=1}}}
local beforeB={amount=1,capacity=10,components={{kind='Bleach',amount=1}}}
local wrongB={amount=2,capacity=10,components={{kind='Water',amount=2}}}
check(not Fluids.transferred(beforeA,afterA,beforeB,wrongB,1),'equal total volume cannot conceal a changed mixture')
-- The bridge supplies the engine-selected backing object, not a nearby guess.
local Sources=require 'EmberRoutesProbe/CookingWaterSources'
local tap,tank=w.source(1,0),w.source(2,5) tap.external=true
tank.fluid=fluid(tank,5)
function tank:getFluidAmount() return self.fluid.amount end function tank:hasFluid() return self.fluid.amount>0 end
function tap:getFluidAmount() return tank.fluid.amount end function tap:hasFluid() return tank.fluid.amount>0 end
function tap:transferFluidTo(targetFluid,amount) FluidContainer.Transfer(tank.fluid,targetFluid,amount) end
EmberRoutesProbeJava.waterSourceBacking=function(object)
    return object==tap and {mode='PLUMBED',object=tank} or {reason='WATER_BACKING_UNAVAILABLE'}
end
local plumbing,pot=w.setup() pot.fluid=fluid(pot,0)
local fill=assert(w.Water.take(plumbing,1,pot,tap))
local promise=plumbing.job.payload.waterSource
check(promise.backing and Store.resourceOwner(promise.key) and Store.resourceOwner(promise.backing.key),
    'a plumbed tap declares its actual tank in the same original claim graph')
local contender,otherPot=w.setup() otherPot.fluid=fluid(otherPot,0)
check(not w.Water.take(contender,1,otherPot,tap),'another cook cannot draw through an alias of the claimed supply')
assert(fill.run()=='Running') action=f.queued() action:start() action.delta=.4 action:update()
action:complete() action:perform()
check(fill.run()=='Success' and pot.fluid.amount==5 and tank.fluid.amount==0
    and not plumbing.job.payload.waterSource and not Store.resourceOwner(promise.backing.key),
    'actual backing depletion is proven before both source claims release')
tank.fluid.amount=5
function tank.fluid:createFluidSample()
    return {size=function() return 2 end,getFluid=function(_,i)
        return {getFluidTypeString=function() return i==0 and 'Water' or 'Bleach' end} end,
        getPercentage=function() return .5 end,release=function() end}
end
check(not Sources.read(plumbing.actor,'kitchen',tap),
    'water as primary fluid does not authorize a plumbed supply containing another liquid')
print('PASS '..checks..' native progressive-pour checks; native fluid effects mocked, game NOT RUN')
