package.path="Contents/mods/EmberRoutesProbe/42/media/lua/client/?.lua;Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;"..package.path
local n=0
local function check(value,why) n=n+1 assert(value,why) end
local tables,uuid,reads={},0,0
ModData={getOrCreate=function(key) tables[key]=tables[key] or {} return tables[key] end}
function getRandomUUID() uuid=uuid+1 return "uuid-"..uuid end
local client=false
function isClient() return client end function isServer() return false end
local actor={x=1,y=1,isDead=function() return false end,getIndex=function() return 0 end,getPlayerNum=function() return 0 end,
    getX=function(self) return self.x end,getY=function(self) return self.y end,getZ=function(self) return self.z or 0 end}
function getSpecificPlayer() return actor end
local events={}
Events={}
for _,name in ipairs({'OnContainerUpdate','OnTick','OnTickEvenPaused','OnGameStart'}) do
    events[name]={} Events[name]={Add=function(fn) events[name][#events[name]+1]=fn end}
end
package.loaded['EmberRoutesProbe/Kernel/Log']={write=function() end}
local squares={}
local function key(x,y,z) return x..":"..y..":"..z end
function getCell() return {getGridSquare=function(_,x,y,z) return squares[key(x,y,z)] end} end
local Geometry=require "EmberRoutesProbe/Settlement/SettlementGeometry"
local Registry=require "EmberRoutesProbe/Warehouse/ContainerRegistry"
local Ledger=require "EmberRoutesProbe/Settlement/SettlementLedger"
local Membership=require "EmberRoutesProbe/Settlement/SettlementMembership"
local Index=require "EmberRoutesProbe/Warehouse/WarehouseIndex"
local Filter=require "EmberRoutesProbe/Warehouse/StorageFilter"
local Query=require "EmberRoutesProbe/Warehouse/WarehouseQuery"
local function box(x,y,z)
    local object={data={}}
    local list={values={}}
    function list:size() return #self.values end
    function list:get(i) reads=reads+1 return self.values[i+1] end
    local container={getItems=function() return list end,getParent=function() return object end}
    function container:getType() return 'crate' end
    function container:getDisplayType() return 'crate' end
    function container:getCustomName() return nil end
    local sq={getX=function() return x end,getY=function() return y end,getZ=function() return z end}
    local objects={size=function() return 1 end,get=function() return object end,contains=function(_,other) return other==object end}
    function sq:getObjects() return objects end
    function object:getSquare() return sq end function object:getContainer() return container end
    function object:getModData() return self.data end
    squares[key(x,y,z)]=sq
    actor.x,actor.y,actor.z=x+0.5,y+0.5,z
    local config=Filter.new() config.groups.tools=true config.groups.other=true
    check(Registry.configure(actor,object,config)=='FILTER_CONFIGURED','real registry config accepted')
    local function item(id,fullType)
        local value={id=id,fullType=fullType or 'Base.Hammer',container=container}
        function value:getID() return self.id end function value:getFullType() return self.fullType end
        function value:getContainer() return self.container end
        function value:getCategory() return 'Normal' end
        function value:getDisplayCategory() return self.fullType=='Base.Hammer' and 'Tool' or 'Junk' end
        list.values[#list.values+1]=value return value
    end
    return {object=object,container=container,list=list,item=item,id=object.data.EmberRoutesContainer.id,config=config,square=sq}
end
local function configure(entry)
    actor.x,actor.y,actor.z=entry.square:getX()+0.5,entry.square:getY()+0.5,entry.square:getZ()
    return Registry.configure(actor,entry.object,entry.config)
end
-- Only registered physical containers belong to WarehouseIndex. The simulated
-- inventory effects below test invalidation/count joins, NOT native transfer.
local settlement=assert(Ledger.commit(actor,nil,'Gate B',assert(Geometry.rectangle(0,0,5,5))))
local source,destination=box(1,1,0),box(2,2,0)
local originals={}
for i,kind in ipairs({'Base.Hammer','Base.Nails','Base.Pencil','Base.Pen','Base.Eraser'}) do
    originals[i]=source.item(i,kind)
end
actor.x,actor.y,actor.z=2.5,2.5,0
check(Registry.configureLogistics(actor,source.object,source.container,'INPUT')=='ROLE_CONFIGURED','source role configured')
local latest
local release=assert(Index.watch(settlement.id,function(s) latest=s end))
local function ready()
    for _=1,200 do Index.step() if latest and latest.state=='READY' then return end end
    error('warehouse did not reach READY')
end
local npc={values={}}
local function ledger(s,npcCount,d)
    ready()
    local count=0 for _,r in ipairs(latest.rows) do count=count+r.count end
    check(#source.list.values==s and #npc.values==npcCount and #destination.list.values==d,'expected physical locations')
    check(count==s+d and s+npcCount+d==5,'warehouse excludes NPC; physical total is five')
    local seen={}
    for _,list in ipairs({source.list.values,npc.values,destination.list.values}) do
        for _,item in ipairs(list) do check(not seen[item:getID()],'each original has exactly one location') seen[item:getID()]=true end
    end
    for _,item in ipairs(originals) do check(seen[item:getID()],'no original disappears') end
end
ledger(5,0,0)
for _=1,2 do local item=table.remove(source.list.values,1) npc.values[#npc.values+1]=item item.container=npc end
Registry.inventoryChanged(source.container)
ledger(3,2,0)
local item=table.remove(npc.values,1) destination.list.values[#destination.list.values+1]=item item.container=destination.container
Registry.inventoryChanged(destination.container)
ledger(3,1,1)
-- A cancel stops work; it must not move originals or change the warehouse count.
ledger(3,1,1)
item=table.remove(npc.values,1) destination.list.values[#destination.list.values+1]=item item.container=destination.container
while #source.list.values>0 do local v=table.remove(source.list.values,1) destination.list.values[#destination.list.values+1]=v v.container=destination.container end
Registry.inventoryChanged(source.container) Registry.inventoryChanged(destination.container)
ledger(0,0,5)
-- Native fast-path deliberately lies about unresolved statuses. The real Lua
-- index must fall back before using that result for private/removed containers.
-- Endpoints are resolved before the native mount, so an unresolvable id never
-- reaches the bridge at all.
local fastCalls=0
local cached=latest
EmberRoutesProbeJava={
    warehouseMountSettlement=function()
        fastCalls=fastCalls+1 return {state='READY',rows=cached.rows,counts=cached.counts,containers={}}
    end,
    warehouseApplyContainer=function() error('unresolved endpoint must never reach native apply') end,
    warehouseUnmountContainer=function(_,id) error('unexpected unmount '..tostring(id)) end}
Index.refresh(settlement.id,false) ready()
check(fastCalls==1,'accessible snapshot uses the native branch')
local returned=table.remove(destination.list.values,1)
source.list.values[#source.list.values+1]=returned returned.container=source.container
Registry.inventoryChanged(source.container)
EmberRoutesProbeJava.warehouseMountSettlement=function() error('unresolved endpoint must never reach native mount') end
EmberRoutesProbeJava.warehouseApplyContainer=function() error('unresolved endpoint must never reach native apply') end
EmberRoutesProbeJava.warehouseUnmountContainer=function(_,id) error('unexpected unmount '..tostring(id)) end
destination.config.private=true configure(destination)
Index.refresh(settlement.id,false) ready()
check(fastCalls==1 and latest.counts.private==1 and latest.counts.items==1,'private endpoint preserves actual reason, not UNLOADED')
EmberRoutesProbeJava=nil
release()
print('PASS '..n..' Gate B registered-container/physical-ledger checks; inventory effects mocked; disk/native transfer NOT RUN')
