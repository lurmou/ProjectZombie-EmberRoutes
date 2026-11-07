-- Installed VM cost only; reflective JavaFunction is not the game Exposer.
local Registry=require 'EmberRoutesProbe/Warehouse/ContainerRegistry'
local root={format=1,taskJobs={format=1,byId={}},containers={},quarantineResources={}}
Registry.data=function() return root end
local Store=require 'EmberRoutesProbe/Work/LaborStore'
Store.data()
local function measure(label,run)
    for i=1,2000 do run() end
    local start=_ERTestNanos()
    for i=1,10000 do run() end
    print('HOST '..label..' 10000 commits: '..tostring((_ERTestNanos()-start)/1000000)..' ms; game NOT RUN')
end
local craft={id='cost-craft',npcId='cost-worker-c',providerType='CRAFT',scopeId='cost-c',revision=1,state='PREPARING',effects='KNOWN',obligations={},
    payload={format=4,id='cost-craft',npcId='cost-worker-c',sequence=1,recipeId='Base.MakeAxe',target=1,produced=0,materials={{id=1,consumed=false}},tools={{id=2}},outputs={},claims={'item:1','item:2'}}}
assert(Store.createClaimedJob(craft))
local rev=1
measure('craft-update',function()
    local ok,value=Store.mutateJob(craft.id,rev,craft.payload,{}) assert(ok,tostring(value)) rev=value
end)
local claims,manifest,items={},{},{}
for i=11,10+(ERCostWidth or 30) do claims[#claims+1]='item:'..i manifest[#manifest+1]={itemId=i,custodyState='UNCOLLECTED'} items[i]=1 end
local haul={id='cost-haul',npcId='cost-worker-h',providerType='HAUL',scopeId='cost-h',revision=1,state='PREPARING',effects='KNOWN',obligations={},
    payload={format=3,sequence=1,source='source',destination='dest',claims=claims,manifest=manifest,reservation={format=2,key='dest',items=items,free=100}}}
assert(Store.createClaimedJob(haul)) rev=1
measure('haul-reserve'..tostring(ERCostWidth or 30),function()
    local ok,value=Store.mutateJob(haul.id,rev,haul.payload,{capacity={key='dest',items=items,free=100}}) assert(ok,tostring(value)) rev=value
end)
