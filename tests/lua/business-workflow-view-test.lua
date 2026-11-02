local n=0 local function check(v,m) n=n+1 assert(v,m) end
local Craft=require 'EmberRoutesProbe/CraftWorkflowView'
local Haul=require 'EmberRoutesProbe/HaulWorkflowView'
local function step(row,key) for _,s in ipairs(row.workflow.steps) do if s.key==key then return s end end end
local row={closed=false}
local p={phase='CRAFTING',target=3,produced=0,materials={{id=1}},tools={{id=2}},outputs={},generation=1}
Craft.attach(row,p,{state='ACTIVE'},7)
check(step(row,'craftEffect').status=='ACTIVE' and row.workflow.viewRevision==7,'craft displays current action with Job version')
check(not step(row,'craftDelivery'),'no invented output delivery without originals')
p.unitMade=true p.outputs={{id=3,delivered=false}} p.nativeAttempt={state='APPLIED',observation={complete=true}}
Craft.attach(row,p,nil,8)
check(step(row,'craftEffect').status=='COMPLETED' and step(row,'craftDelivery').status=='PLANNED','verified one recipe effect does not mean delivered order')
p.nativeAttempt.state='UNKNOWN'
Craft.attach(row,p,nil,9)
check(step(row,'craftEffect').status=='UNCERTAIN','unresolved native craft is not completion')
p.unitMade=false p.phase='COMMITTING' p.nativeAttempt.state='COMMITTING'
Craft.attach(row,p,{state='ACTIVE'},10)
check(step(row,'craftEffect').status=='ACTIVE','live native recipe commitment is in progress rather than failed unknown')
Craft.attach(row,p,nil,11)
check(step(row,'craftEffect').status=='UNCERTAIN','stopped unobserved recipe commitment retains uncertainty')
local h={generation=1,routeRevision=2,manifest={{itemId=1,custodyState='WITHDRAWN'},
    {itemId=2,custodyState='CARRIED'},{itemId=3,custodyState='DELIVERED',deliveryReceipt={destinationId='old'}}},
    activeAttempt={kind='PUT',itemId=2}}
row={closed=false} Haul.attach(row,h,{state='ACTIVE'},10)
check(step(row,'haulTake').progress=='2/2','withdrawn line is excluded from picked quantity')
check(step(row,'haulPut').status=='ACTIVE' and step(row,'haulPut').progress=='1/2','partial receipt is preserved during current PUT')
h.routeRevision=3 h.routingWait={reason='FULL'} h.activeAttempt=nil
Haul.attach(row,h,nil,11)
check(step(row,'haulRoute').status=='BLOCKED' and step(row,'haulPut').progress=='1/2','route changes do not roll back existing delivery facts')
check(h.manifest[3].deliveryReceipt.destinationId=='old','read projection never rewrites routing or receipts')
h.manifest={{itemId=1,custodyState='WITHDRAWN'}} h.routingWait=nil
Haul.attach(row,h,nil,12)
check(not step(row,'haulTake') and not step(row,'haulPut') and step(row,'haulWithdraw').status=='COMPLETED','all withdrawn is not rendered as all taken/delivered')
getText=function(key) return key end
package.loaded['EmberRoutesProbe/DisplayNames']={name=function() return 'Cook' end}
package.loaded['EmberRoutesProbe/MembershipService']={view=function() end}
local Cooking=require 'EmberRoutesProbe/CookingMonitor'
local j={id='cooking',npcId='n',revision=2,state='SUSPENDED',effects='KNOWN',payload={source='AUTO',phase='HEATING',
    assets={{id=5,role='OUTPUT',fullType='Base.Food',custody='STATION'}},duty={state='HEATING'},heat={closed=false,aborted=false}}}
row=Cooking.project({bind=function() end},j)
check(step(row,'cookDuty') and step(row,'cookDuty').status~='COMPLETED','furnace duty remains visible without a body session')
check(step(row,'cookHeat').status~='COMPLETED' and row.responsibilitySummary,'heat is not complete because worker stopped')
j.effects='UNKNOWN' j.payload.phase='FILLING' j.payload.attempt={kind='WATER',state='COMMITTING'}
row=Cooking.project({bind=function() end,runtime={status=function() return {state='ACTIVE'} end}},j)
check(step(row,'cookWater').status=='ACTIVE' and not row.uncertain,'healthy progressive water is distinct from failed unknown effect')
row=Cooking.project({bind=function() end},j)
check(step(row,'cookFill').status=='UNCERTAIN','stopped unresolved fluid effect is not marked successful')
check(j.payload.assets[1].custody=='STATION' and j.payload.duty~=nil,'cooking projection never releases original or furnace responsibility')
print('PASS '..n..' domain-specific workflow projection checks; native world not run')
