local Read=require 'EmberRoutesProbe/InventoryRead'
local Producers=require 'EmberRoutesProbe/LaborProducers'
local checks=0 local function check(v,m) checks=checks+1 assert(v,m) end
local container,items={}, {values={}}
function container:getItems() return items end
function items:size() return #self.values end
function items:get(i) return self.values[i+1] end
for i=1,70 do
    local item={id=i,container=container,fullType='Base.Test',data={}}
    function item:getContainer() return self.container end
    function item:getID() return self.id end
    function item:getFullType() return self.fullType end
    function item:getModData() return self.data end
    function item:getCategory() return 'Item' end
    function item:isEquipped() return false end
    function item:isFavorite() return false end
    items.values[i]=item
end
EmberRoutesProbeJava=nil
local rows=assert(Read.slice(container,items,70,0,32))
check(#rows==96 and rows[1]==items.values[1] and rows[2]==1 and rows[3]=='Base.Test','fallback original identity and flat metadata')
check(#Read.slice(container,items,70,64,32)==18,'partial end slice')
check(not Read.slice(container,items,69,0,32),'size mismatch rejected')
check(not Read.slice(container,items,70,0,33),'slice cannot exceed budget')
items.values[2].container={}
check(not Read.slice(container,items,70,0,32),'wrong physical owner rejects whole slice')
items.values[2].container=container
local item=items.values[1]
check(Producers.eligible(item),'ordinary item eligible')
for _,value in ipairs({true,0,''}) do item.data.EmberRoutesHaulFixture=value check(not Producers.eligible(item),'Lua truthy marker protects') end
item.data.EmberRoutesHaulFixture=false check(Producers.eligible(item),'false marker is eligible')
local calls=0
EmberRoutesProbeJava={inventoryReadSlice=function(c,list,size,offset,limit)
    calls=calls+1 check(c==container and list==items and size==70 and offset==0 and limit==32,'one bounded native slice request')
    return {rows=rows}
end,workItemEligible=function(expected) check(expected==item,'original item passed to native guard') return false end,
workFreeCarry=function(npc) return npc.free end}
check(Read.slice(container,items,70,0,32)==rows and calls==1,'native table directly reused without per-item bridge getters')
check(not Producers.eligible(item) and Producers.freeCarry({free=7})==7,'central producer queries use native helpers')
EmberRoutesProbeJava.workItemEligible=function() return nil end
setmetatable(item.data,{__index={EmberRoutesPersistenceSample=true}})
check(not Producers.eligible(item),'native compatibility delegation preserves virtual Lua protection')
setmetatable(item.data,nil)
EmberRoutesProbeJava.inventoryReadSlice=function() return {reason='INVENTORY_CHANGED'} end
local value,reason=Read.slice(container,items,70,0,32)
check(value==nil and reason=='INVENTORY_CHANGED','native invalidation propagated')
local Driver=require 'EmberRoutesProbe/Driver'
local presentCalls=0
EmberRoutesProbeJava.carrierPresent=function(handle) presentCalls=presentCalls+1 return handle==item end
EmberRoutesProbeJava.carrierId=function(handle) presentCalls=presentCalls+1 return handle==item and 'npc' or '' end
check(Driver.valid({handle=item,id='npc'}) and presentCalls==2,'legacy validation preserves both native facts')
EmberRoutesProbeJava.bindingValid=function(handle,id) return handle==item and id=='npc' end
presentCalls=0
check(Driver.valid({handle=item,id='npc'}) and presentCalls==0,'combined native validation avoids duplicate presence/identity calls')
check(not Driver.valid({handle=item,id='stale'}) and not Driver.valid(nil),'combined validation rejects stale or absent binding')
print('PASS '..checks..' native inventory adapter checks; game bridge mocked')
