-- Actual shared warehouse matcher + typed input adapter + BOM; physical world mocked.
local checks=0 local function check(v,m) checks=checks+1 assert(v,m) end
local function list(t)
    t=t or {} function t:size() return #self end function t:get(i) return self[i+1] end
    return t
end
local root={} local owner={} local unloaded=false local permitted=true
local warehouse={items=list()} function warehouse:getItems() return self.items end
local inventory={items=list()} function inventory:getItems() return self.items end
local endpoint={id='storage',container=warehouse,object={}}
local npc={getInventory=function() return inventory end}
local entry={id='settlement'}
local Registry={data=function() return root end,logistics=function() return 'STORAGE' end,
    accepts=function() return permitted end,filter=function() return {} end,revalidate=function() return permitted end}
package.loaded['EmberRoutesProbe/ContainerRegistry']=Registry
package.loaded['EmberRoutesProbe/SettlementMembership']={query=function() return {'storage'} end}
package.loaded['EmberRoutesProbe/SortPolicy']={index=function() return {add=function() end} end}
package.loaded['EmberRoutesProbe/StorageFilter']={copy=function(x) return x end}
package.loaded['EmberRoutesProbe/CraftSupply']={endpoint=function()
    if unloaded then return nil,'CONTAINER_UNLOADED' end return endpoint
end}
package.loaded['EmberRoutesProbe/LaborStore']={owner=function(id) return owner[id] end}
package.loaded['EmberRoutesProbe/LaborProducers']={eligible=function(item) return not item.denied end}
package.loaded['EmberRoutesProbe/CookingFood']={read=function() return {safe=true,frozen=false} end}
function instanceof() return false end
local native={canUseItem=function(_,item) return item.milk end,
    isFluidMatch=function(_,container) return container.milk end}
local fluid={resource='Fluid',amount=5,line='-fluid 5',io=native}
local row={slot=0,count=1,keep=true,any=true,resource='Item',child=fluid,io=native}
local profile={facts={id='Mod.Butter',name='Butter',signature='v1',surface=false},roots={row},outputs={['Mod.Butter']=1}}
package.loaded['EmberRoutesProbe/CookingCraft']={profile=function() return profile end}
local Supply=require 'EmberRoutesProbe/CookingSupply'
local sampleCalls=0
local function item(id,amount,milk)
    local c={amount=amount,milk=milk~=false}
    function c:getAmount() return self.amount end function c:getCapacity() return 20 end
    function c:createFluidSample()
        sampleCalls=sampleCalls+1
        return {size=function() return 1 end,getPercentage=function() return 1 end,
            getFluid=function() return {getFluidTypeString=function() return self.milk and 'CowMilk' or 'Water' end} end,
            release=function() end}
    end
    local v={id=id,milk=milk~=false,container=warehouse,fluid=c}
    function v:getID() return self.id end function v:getFullType() return 'Mod.Bucket' end
    function v:getContainer() return self.container end function v:getFluidContainer() return self.fluid end
    function v:getIsCraftingConsumed() return false end
    return v
end
local function fresh(items)
    root={} owner={} unloaded=false permitted=true inventory.items=list() warehouse.items=list(items)
    profile.roots={row}
    return assert(Supply.new(entry,npc,'Mod.Butter','job'))
end
local function run(request)
    for _=1,1000 do local result,why=request:step(1) if result or why then return result,why end end
    error('unbounded request')
end
local a=item(1,2.5) local b=item(2,5) local water=item(3,10,false)
local request=fresh({a,water,b}) local result,why=run(request)
check(result and #result.entries==1 and result.entries[1].id==2,'shared matcher rejects small/wrong-fluid carriers and selects exact full original')
check(result.entries[1].endpoint==endpoint and result.entries[1].slot==0,'selection retains real take endpoint and native parent slot')
check(result.plan.nodes[1].fluidInputs[1].itemId==2 and b.fluid.amount==5 and not owner[2],
    'BOM binds selected original without fluid mutation, claims or movement')
result,why=run(fresh({item(4,2.5),item(5,2.5)}))
check(not result and why=='MATERIALS_UNAVAILABLE','kept milk carrier shortage is materials, not missing tools')
request=fresh({b}) owner[2]={taskId='other'} result,why=run(request)
check(not result and why=='MATERIALS_UNAVAILABLE','another Job claim excludes a carrier')
request=fresh({b}) owner[2]={taskId='job'} result=run(request)
check(result~=nil,'same Job may observe its already claimed original')
request=fresh({b}) permitted=false result=run(request)
check(not result,'warehouse policy excludes unauthorized originals')
request=fresh({b}) unloaded=true result,why=run(request)
check(not result and why=='CHAIN_INVENTORY_UNKNOWN','unloaded storage is not certified empty')
request=fresh({b})
for _=1,100 do request:step(1) if request.scanned then break end end
b.fluid.amount=1 result,why=run(request)
check(not result and why=='INPUT_CHANGED','milk consumed between scan and planning invalidates selection')
b.fluid.amount=5
request=fresh({b})
for _=1,100 do request:step(1) if request.scanned then break end end
owner[2]={taskId='new-owner'} result,why=run(request)
check(not result and why=='INPUT_CHANGED','claim acquired after scan fences the old selection')
request=fresh({b})
for _=1,100 do request:step(1) if request.scanned then break end end
b.container=inventory result,why=run(request)
check(not result and why=='ITEM_LOCATION_CHANGED','moved original invalidates old take endpoint')
b.container=warehouse
request=fresh({b}) root={} result,why=run(request)
check(not result and why=='WORLD_RESET','world generation fences a pending scan')
request=fresh({b}) request:cancel() result,why=run(request)
check(not result and why=='WORLD_RESET' and #request.entries==0,'cancel drops runtime candidates without touching originals')
check(sampleCalls>0,'selected fluid amount is read through actual shared sample adapter')
print('PASS '..checks..' cooking original-selection checks; actual matcher/BOM, mocked world; game NOT RUN')
