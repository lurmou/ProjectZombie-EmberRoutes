local checks=0
local function check(v,s) checks=checks+1 assert(v,s) end
local predicates=0
local function list(values) return {size=function() return #values end,get=function(_,i) return values[i+1] end} end
local source={}
local npcInventory={getItems=function() return list({}) end}
local npc={getInventory=function() return npcInventory end}
local a={getID=function() return 1 end,getContainer=function() return source end,getIsCraftingConsumed=function() return false end}
local b={getID=function() return 2 end,getContainer=function() return source end,getIsCraftingConsumed=function() return false end}
source.getItems=function() return list({a,b}) end
local endpoint={id='crate',container=source,object={}}
package.loaded['EmberRoutesProbe/CraftSupply']={endpoint=function() return endpoint end}
package.loaded['EmberRoutesProbe/SettlementMembership']={query=function() return {'crate'} end}
package.loaded['EmberRoutesProbe/SortPolicy']={index=function() return {add=function() end} end}
package.loaded['EmberRoutesProbe/StorageFilter']={copy=function() return {} end}
package.loaded['EmberRoutesProbe/ContainerRegistry']={logistics=function() return 'STORAGE' end,
 accepts=function() return true end,filter=function() return {} end,revalidate=function() return true end}
package.loaded['EmberRoutesProbe/LaborStore']={owner=function() end}
package.loaded['EmberRoutesProbe/LaborProducers']={eligible=function() return true end}
local flexible={canUseItem=function() predicates=predicates+1 return true end}
local restricted={canUseItem=function(_,item) predicates=predicates+1 return item==a end}
local Supply=require 'EmberRoutesProbe/ProductionSupply'
local function plan()
 return assert(Supply.new({},npc,{inputs={{slot=1,count=1,io=flexible},{slot=2,count=1,io=restricted}}},
 {id='job',materials={},tools={},outputs={}},true,1))
end
local p=plan() local done
for _=1,200 do
 local before=predicates local reason done,reason=p:step(1)
 check(predicates-before<=1,'one budget unit performs at most one native matching predicate')
 check(not reason,'augmenting matching remains feasible')
 if done then break end
end
check(done and #p.materials==2,'budget-one matching eventually completes')
local assigned={} for _,asset in ipairs(p.materials) do assigned[asset.slot]=asset.id end
check(assigned[1]==2 and assigned[2]==1,'flexible slot yields restricted original through augmenting path')
check(p:step(1)==true and #p.materials==2,'completed plan remains idempotent')
local Queue=require 'EmberRoutesProbe/PrecheckQueue'
local q=Queue.new(4) local spent={} local cancelled=0 local ready=0
for i=1,4 do
 local key='w'..i spent[key]=0
 check(q:put(key,{request={cancel=function() cancelled=cancelled+1 end,
  step=function(_,budget) spent[key]=spent[key]+budget end}}),'bounded queue accepts four')
end
check(not q:put('overflow',{}),'hard concurrency cap')
local ops=q:step(128,function() return true end,function() ready=ready+1 end,function() return 0 end)
check(ops==128 and ready==0,'global operation budget covers all requests')
for _,n in pairs(spent) do check(n==32,'active requests receive fair shares independent of roster') end
local clock=0
local ops2=q:step(128,function() return true end,function() end,function() clock=clock+1 return clock end)
check(ops2<=16,'soft time budget checked between small chunks')
q:clear() check(cancelled==4 and q:size()==0,'clear cancels all transient work')
local Chain=require 'EmberRoutesProbe/ProductionChainPlan'
local producers={}
for i=1,100 do producers[i]={id='p'..i,yield=1,outputs={material=1},inputs={}} end
local chain=Chain.new({id='root',yield=1,outputs={result=1},inputs={{slot=1,count=1,keep=false,types={material=true},choices={'material'}}}},1,{}, {material=producers})
for _=1,10 do chain:step(1) end
check(not chain.done,'producer enumeration cannot expand an entire catalogue in one planning operation')
local result,reason
for _=1,200 do result,reason=chain:step(1) if result or reason then break end end
check(reason=='CHAIN_PLAN_LIMIT','overlarge alternatives still fail with the existing explicit limit')
print('PASS '..checks..' planning operation/augmenting/fairness/time-bound checks; native world mocked')
