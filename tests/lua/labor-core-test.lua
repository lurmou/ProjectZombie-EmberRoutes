package.path="Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;Contents/mods/EmberRoutesProbe/42/media/lua/client/?.lua;"..package.path
local count=0
local function check(value,message) count=count+1 assert(value,message) end
local Claims=require "EmberRoutesProbe/LaborClaims"
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
local Schedule=require "EmberRoutesProbe/LaborSchedule"
local schedule=Schedule.new() local seen={}
for i=1,100 do schedule:add(i) end
for _=1,25 do schedule:step(4,function(id) seen[id]=(seen[id] or 0)+1 end) end
for i=1,100 do check(seen[i]==1,"fair service under shared budget") end
local removed={}
schedule:step(4,function(id) removed[#removed+1]=id schedule:remove(id) end)
check(#removed==4 and removed[1]==1 and removed[4]==4,"removing current worker preserves cursor")

local View=require "EmberRoutesProbe/InventoryView"
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

-- Isolated scalar store exercises old-world migration and corruption boundaries.
local function record(id,npc,item)
    return {id=id,npcId=npc,items={item},format=1,kind="EXPLICIT_TRANSFER",executor="ENTITY",scopeId="local-world",state="RUNNING"}
end
local root={job=record("old","a",1),source="source",destination="target"}
package.loaded["EmberRoutesProbe/ContainerRegistry"]={data=function() return root end}
local Store=require "EmberRoutesProbe/LaborStore"
check(Store.record("a").id=="old" and root.job==nil and root.labor.format==2,"legacy task migrated into one authority")
check(Store.record("a").state=="PAUSED" and Store.owner(1),"loaded running intent pauses and reacquires claims")
check(Store.route("a").source=="source" and Store.route("b").source==nil,"legacy route follows its owner without becoming every worker's default")
local old=root.labor
root={labor={format=2,tasks={x=record("x","a",7),y=record("y","b",7)},byNpc={a="x",b="y"},routes={}}}
for _=1,2 do
    local ok=pcall(Store.data) check(not ok,"conflicting reload never publishes partial cache")
    check(root.labor.tasks.x.generation==nil,"failed rebuild never mutates generations")
end
root.labor.tasks.y.items={8}
check(Store.record("b").id=="y" and Store.owner(7).taskId=="x" and Store.owner(8).taskId=="y","fixed ledger can be rebuilt without stale partial ownership")
root={labor=old}
check(Store.record("a").id=="old","world switch releases other world's cached ownership")
local batch=record("batch","batch-npc",1) batch.items={1,2}
batch.reservation={format=2,key="shared-box",items={[1]=2,[2]=3}}
root={labor={format=2,tasks={batch=batch},byNpc={["batch-npc"]="batch"},routes={}}}
check(Store.record("batch-npc")==batch and Store.availableCapacity("shared-box",5)==0,"multi-original reservation rebuilt after scalar reload")
local token=Store.claim(batch) Store.releaseCapacity(token,1)
check(Store.availableCapacity("shared-box",3)==0 and batch.reservation.items[2]==3,"delivery releases only its original after reload")
Store.releaseCapacity(token,2)
check(Store.availableCapacity("shared-box",3)==3 and not batch.reservation,"last delivered original clears durable batch capacity")
print("PASS "..count.." labor authority/migration/budget checks; no engine assets mutated")
