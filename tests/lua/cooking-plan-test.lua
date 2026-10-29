local Plan=require 'EmberRoutesProbe/ProductionChainPlan'
local checks=0 local function check(v,m) checks=checks+1 assert(v,m) end
local function milk(slot,amount)
    return {slot=slot or 0,count=1,keep=true,any=true,types={},choices={},
        fluid={unit='FLUID_VOLUME',amount=amount or 5},accept=function(item) return item.milk end}
end
local function recipe(id,inputs)
    return {id=id,name=id,signature=id,product='butter',yield=1,outputs={butter=1},inputs=inputs}
end
local function bucket(id,amount) return {id=id,fullType='Mod.Carrier',fluidAmount=amount,item={milk=true}} end
local function run(r,n,stock,producers)
    local p=Plan.new(r,n,stock,producers or {}) local slices=0
    while not p.done do p:step(1) slices=slices+1 assert(slices<50000) end
    return p.result,p.reason
end
local butter=recipe('butter',{milk()})
local a,b=bucket(1,5),bucket(2,5)
local p,why=run(butter,1,{a})
check(p and #p.assets==1 and p.nodes[1].fluidInputs[1].itemId==1,'wildcard binds actual carrier, not a literal type')
check(p.nodes[1].fluidInputs[1].amount==5 and a.fluidAmount==5,'volume proof is detached; no stock mutation')
p,why=run(butter,1,{bucket(1,2.5),bucket(2,2.5)})
check(not p and why=='MATERIALS_UNAVAILABLE','one call cannot pool small bottles')
p,why=run(butter,2,{a})
check(not p and why=='MATERIALS_UNAVAILABLE','kept container does not imply reusable consumed milk')
p=run(butter,2,{a,b})
check(p and #p.assets==2 and #p.nodes[1].fluidInputs==2,'two calls may use different complete carriers')
p=run(butter,2,{bucket(3,10)})
check(p and #p.assets==1 and #p.nodes[1].fluidInputs==2,'ten units in one original supports two calls')
p,why=run(butter,1,{{id=1,fullType='Mod.Carrier',fluidAmount=10,item={milk=false}}})
check(not p and why=='MATERIALS_UNAVAILABLE','volume alone cannot substitute the native mixture predicate')
p,why=run(recipe('twoSlots',{milk(0),milk(1)}),1,{bucket(3,10)})
check(not p and why=='MATERIALS_UNAVAILABLE','one original cannot occupy two parent slots in one native call')
p=run(recipe('twoSlots',{milk(0),milk(1)}),2,{bucket(3,10),bucket(4,10)})
check(p and #p.nodes[1].fluidInputs==4,'per-call distinctness permits reuse in later calls')
local consume={slot=1,count=1,keep=false,types={['Mod.Carrier']=true},choices={'Mod.Carrier'}}
p,why=run(recipe('consumeCarrier',{milk(),consume}),1,{a})
check(not p,'consumed original cannot also supply milk')
local keep={slot=1,count=1,keep=true,types={['Mod.Carrier']=true},choices={'Mod.Carrier'}}
p,why=run(recipe('keepCarrier',{milk(),keep}),1,{a})
check(not p,'separate kept tool slot cannot share the fluid parent')
local fill=recipe('inventLiquid',{}) fill.outputs={['Mod.Carrier']=1} fill.product='Mod.Carrier'
p,why=run(butter,1,{}, {['Mod.Carrier']={fill}})
check(not p and why=='MATERIALS_UNAVAILABLE','item producer does not promise invented fluid contents')
local flexible=milk(0) local strict=milk(1)
strict.accept=function(item) return item.special end
a.item.special=true
p=run(recipe('backtrack',{flexible,strict}),1,{a,b})
check(p and #p.assets==2,'failed fluid allocation restores simulated volume before alternate original')
local meal=recipe('meal',{milk(),{slot=1,count=1,keep=false,types={butter=true},choices={'butter'}}})
meal.product='meal' meal.outputs={meal=1}
p,why=run(meal,1,{bucket(6,5)},{butter={butter}})
check(not p and why=='MATERIALS_UNAVAILABLE','dependency recipe cannot consume liquid already allocated to its parent')
p=run(meal,1,{bucket(6,10)},{butter={butter}})
check(p and #p.nodes==2 and p.claims==1 and p.nodes[1].fluidInputs[1].itemId==6
    and p.nodes[2].fluidInputs[1].itemId==6,'precursor and parent share one real carrier with separately budgeted fluid')
p,why=run(butter,257,{bucket(5,2000)})
check(not p and why=='CHAIN_PLAN_LIMIT','large fluid batch request remains bounded')
print('PASS '..checks..' fluid BOM checks; pure planning, game NOT RUN')
