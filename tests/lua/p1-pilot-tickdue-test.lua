-- p1-pilot-tickdue-test.lua: Lua must no longer ask Java "is a verify due?"
-- every idle window. The idle re-verify runs on the local step clock with
-- the same lengthening backoff, real changes arrive as dirty applies
-- (Ledger.listeners / inventory listeners / OnContainerUpdate), and
-- WarehouseFastIndex.tickDue now answers from the master 15Hz tier.
-- Fails on unmodified main: the old advanceNative calls warehouseTickDue
-- once per verify window, so tickDueCalls > 0 after the idle soak.
package.path="Contents/mods/EmberRoutesProbe/42/media/lua/client/?.lua;Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;"..package.path
local n=0
local function check(value,why) n=n+1 assert(value,why) end
local tables,uuid,reads={},0,0
ModData={getOrCreate=function(key) tables[key]=tables[key] or {} return tables[key] end}
function getRandomUUID() uuid=uuid+1 return "uuid-"..uuid end
_G.getRandomUUID = getRandomUUID
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

-- Counting fake bridge with fingerprint change detection, mirroring the
-- Java fast path: an unchanged container returns the identical front
-- snapshot; a changed one rebuilds it with a new revision.
local bridge={tickDueCalls=0,applyCalls=0,mountCalls=0,unmountCalls=0,resetCalls=0}
local fronts,fps,descs,revs={},{},{},{}
local function fingerprint(desc)
    local c=desc.container
    if not c then return "UNLOADED" end
    local items=c:getItems()
    local parts={tostring(items:size())}
    for i=0,items:size()-1 do
        local it=items:get(i)
        parts[#parts+1]=tostring(it:getID())..":"..it:getFullType()
    end
    return table.concat(parts,",")
end
local function buildSnapshot(id)
    local rowsByType,items,loaded,unloaded={} ,0,0,0
    for cid,desc in pairs(descs[id] or {}) do
        if desc.container then
            loaded=loaded+1
            local list=desc.container:getItems()
            local perType={}
            for i=0,list:size()-1 do
                local it=list:get(i)
                local ft=it:getFullType()
                perType[ft]=(perType[ft] or 0)+1
                items=items+1
            end
            for ft,count in pairs(perType) do
                local row=rowsByType[ft]
                if not row then row={fullType=ft,count=0,node="other",sources={}} rowsByType[ft]=row end
                row.count=row.count+count
                row.sources[#row.sources+1]={id=cid,count=count,x=desc.x,y=desc.y,z=desc.z,kind=desc.kind}
            end
        else
            unloaded=unloaded+1
        end
    end
    local fullTypes={}
    for ft in pairs(rowsByType) do fullTypes[#fullTypes+1]=ft end
    table.sort(fullTypes)
    local rows={}
    for _,ft in ipairs(fullTypes) do rows[#rows+1]=rowsByType[ft] end
    revs[id]=(revs[id] or 0)+1
    return {state="READY",rows=rows,counts={loaded=loaded,unloaded=unloaded,private=0,missing=0,limited=0,
        items=items,containers=loaded+unloaded,totalCapacity=0,usedWeight=0,fullCount=0,fullContainers={}},
        containers={},tags={},revision=revs[id]}
end
bridge.warehouseMountSettlement=function(id,list)
    bridge.mountCalls=bridge.mountCalls+1
    descs[id]=descs[id] or {} fps[id]=fps[id] or {}
    local present={}
    for _,desc in ipairs(list) do
        present[desc.id]=true
        descs[id][desc.id]=desc
        fps[id][desc.id]=fingerprint(desc)
    end
    for cid in pairs(descs[id]) do if not present[cid] then descs[id][cid]=nil fps[id][cid]=nil end end
    fronts[id]=buildSnapshot(id)
    return fronts[id]
end
bridge.warehouseApplyContainer=function(id,desc)
    bridge.applyCalls=bridge.applyCalls+1
    descs[id]=descs[id] or {} fps[id]=fps[id] or {}
    local fp=fingerprint(desc)
    if descs[id][desc.id] and fps[id][desc.id]==fp then return fronts[id] end
    descs[id][desc.id]=desc
    fps[id][desc.id]=fp
    fronts[id]=buildSnapshot(id)
    return fronts[id]
end
bridge.warehouseUnmountContainer=function(id,cid)
    bridge.unmountCalls=bridge.unmountCalls+1
    if descs[id] then descs[id][cid]=nil end
    if fps[id] then fps[id][cid]=nil end
    if fronts[id] then fronts[id]=buildSnapshot(id) end
    return fronts[id]
end
bridge.warehouseResetCache=function(id) bridge.resetCalls=bridge.resetCalls+1 end
bridge.warehouseTickDue=function(id,urgent) bridge.tickDueCalls=bridge.tickDueCalls+1 return true end
bridge.warehouseTypeCount=function(id,ft) return 0 end
EmberRoutesProbeJava=bridge

local Geometry=require "EmberRoutesProbe/Settlement/SettlementGeometry"
local Registry=require "EmberRoutesProbe/Warehouse/ContainerRegistry"
local Ledger=require "EmberRoutesProbe/Settlement/SettlementLedger"
local Membership=require "EmberRoutesProbe/Settlement/SettlementMembership"
local Index=require "EmberRoutesProbe/Warehouse/WarehouseIndex"
local Filter=require "EmberRoutesProbe/Warehouse/StorageFilter"
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
local area=assert(Geometry.rectangle(5,5,0,0))
local settlement=assert(Ledger.commit(actor,nil,'Base A',area))
local stableId=settlement.id
local a,b=box(1,1,0),box(2,2,0)
local original=a.item(1)
a.item(2,'Base.Nails') b.item(3)
local members=Membership.query(settlement)
check(#members==2,'shared fixture has exactly two member containers')

local latest,notifications=0,0
local release=assert(Index.watch(stableId,function(snapshot) latest=snapshot notifications=notifications+1 end))
check(latest.state=='READY' and latest.counts.loaded==2 and latest.counts.items==3,'native mount publishes READY with both containers')
check(bridge.mountCalls==1 and bridge.tickDueCalls==0,'mount asks Java nothing about cadence')
local readySnapshot=latest
local readyNotifications=notifications

-- 1. Idle soak: the safety-net verify still runs on its lengthening
-- backoff, but Lua never asks Java whether it is due.
for _=1,500 do Index.step() end
check(bridge.tickDueCalls==0,'idle soak makes zero warehouseTickDue bridge calls')
check(bridge.applyCalls>=4 and bridge.applyCalls<=20,'idle verify runs on backoff cadence, not every step (applies='..bridge.applyCalls..')')
check(latest==readySnapshot and notifications==readyNotifications,'unchanged index republishes nothing while idle')
check(latest.counts.items==3,'idle index keeps the same counts')

-- 2. Silent change (scripted addItem, no event): the fingerprint safety
-- net must pick it up within the bounded backoff window (max 160 steps).
a.item(4,'Base.Nails')
local silentSteps=nil
for i=1,300 do
    Index.step()
    if latest.counts.items==4 then silentSteps=i break end
end
check(silentSteps~=nil,'silent container change reaches the index without any event')
check(silentSteps<=200,'silent change freshness bounded by the verify backoff (steps='..tostring(silentSteps)..')')
check(latest.state=='READY' and latest~=readySnapshot,'silent change republishes a fresh READY snapshot')
check(bridge.tickDueCalls==0,'silent-change refresh asks Java nothing about cadence')
readySnapshot=latest
readyNotifications=notifications

-- 3. No-change stability after the silent refresh.
for _=1,200 do Index.step() end
check(latest==readySnapshot and notifications==readyNotifications,'no republish while nothing changes after refresh')
check(bridge.tickDueCalls==0,'stability soak makes zero warehouseTickDue bridge calls')

-- 4. Change-triggered (container event path): dirty apply runs on the
-- next step, without waiting for the next verify window.
b.item(5)
Index.changed(b.id,false)
local eventSteps=nil
for i=1,5 do
    Index.step()
    if latest.state=='READY' and latest.counts.items==5 then eventSteps=i break end
end
check(eventSteps~=nil,'event-driven change refreshes promptly (steps='..tostring(eventSteps)..')')
check(bridge.tickDueCalls==0,'event-driven refresh asks Java nothing about cadence')

-- 5. Ledger.listeners path: renaming the settlement refreshes the index
-- through the listener, with no cadence question.
local renamed=assert(Ledger.commit(actor,stableId,'Base renamed',area))
check(renamed.id==stableId,'rename preserves the stable settlement id')
local ledgerSteps=nil
for i=1,10 do
    Index.step()
    if latest.state=='READY' and latest.counts.items==5 then ledgerSteps=i break end
end
check(ledgerSteps~=nil,'ledger change refreshes the index (steps='..tostring(ledgerSteps)..')')
check(bridge.resetCalls>=1,'ledger refresh reaches the Java cache reset')
check(bridge.tickDueCalls==0,'ledger refresh asks Java nothing about cadence')

release()
print('PASS '..n..' tickDue anti-pattern checks; bridge calls tickDue=0 mount='..bridge.mountCalls
    ..' apply='..bridge.applyCalls..' unmount='..bridge.unmountCalls..' reset='..bridge.resetCalls)
