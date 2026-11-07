package.path="Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;Contents/mods/EmberRoutesProbe/42/media/lua/client/?.lua;"..package.path
local count=0
local function check(value,message) count=count+1 assert(value,message) end
local Claims=require "EmberRoutesProbe/Kernel/LaborClaims"
local claims=Claims.new()
local a=claims:acquire("a",1,{"item:1","item:2"})
local b,reason=claims:acquire("b",1,{"item:3","item:2"})
check(not b and reason=="ITEM_RESERVED" and not claims.owners["item:3"],"claim acceptance atomic before mutation")
check(not claims:acquire("a",2,{"item:1"}),"renewal cannot silently abandon manifest resources")
check(claims:reserve(a,"box",1,1,1),"one free slot reserved")
b=claims:acquire("b",1,{"item:3"})
check(not claims:reserve(b,"box",3,1,1),"shared target capacity arbitrated")
check(not claims:reserve(b,"box",3,0/0,10),"NaN capacity rejected")
local renewed=claims:acquire("a",2,{"item:1","item:2"})
claims:release(a)
check(claims:valid(renewed,"item:1") and not claims:reserve(b,"box",3,1,1),"old token cannot release renewed item or capacity")
claims:release(renewed)
check(claims:reserve(b,"box",3,1,1),"new token releases its reservation")
local Schedule=require "EmberRoutesProbe/Work/LaborSchedule"
local schedule=Schedule.new() local seen={}
for i=1,100 do schedule:add(i) end
for _=1,25 do schedule:step(4,function(id) seen[id]=(seen[id] or 0)+1 end) end
for i=1,100 do check(seen[i]==1,"fair service under shared budget") end
local removed={}
schedule:step(4,function(id) removed[#removed+1]=id schedule:remove(id) end)
check(#removed==4 and removed[1]==1 and removed[4]==4,"removing current worker preserves cursor")

local View=require "EmberRoutesProbe/Warehouse/InventoryView"
local reads=0 local container={items={}}
function container:getItems() return self.items end
function container.items:size() return #self end
function container.items:get(index) reads=reads+1 return self[index+1] end
for i=1,2000 do
    container.items[i]={getID=function() return i end,getContainer=function() return container end}
end
local scan=View.scan({container}) local result,why
repeat local before=reads result,why=scan:step(32) check(reads-before<=32,"inventory reads obey slice budget") until result
check(reads==2000 and View.find(result,2000)==container.items[2000],"all original entries indexed across slices")
scan=View.scan({container}) scan:step(1) table.remove(container.items)
result,why=scan:step(32)
check(not result and why=="INVENTORY_CHANGED","size change restarts incomplete snapshot")

print("PASS "..count.." labor authority/budget checks; no engine assets mutated")
