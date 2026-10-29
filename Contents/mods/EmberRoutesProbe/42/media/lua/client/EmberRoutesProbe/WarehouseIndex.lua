-- Read model only. No InventoryItem/IsoObject is published or persisted.
local Registry=require "EmberRoutesProbe/ContainerRegistry"
local Ledger=require "EmberRoutesProbe/SettlementLedger"
local Membership=require "EmberRoutesProbe/SettlementMembership"
local Filter=require "EmberRoutesProbe/StorageFilter"
local Log=require "EmberRoutesProbe/Log"
local Rollup=require "EmberRoutesProbe/WarehouseRollup"
local Geometry=require "EmberRoutesProbe/SettlementGeometry"
local Metrics=require "EmberRoutesProbe/WarehouseMetrics"
local RuntimeMetrics=require 'EmberRoutesProbe/RuntimeMetrics'
local Read=require 'EmberRoutesProbe/InventoryRead'
local Index={BUDGET=128,MAX_ITEMS=20000,MAX_TYPES=2048,clock=0}
local contexts,order,cursor={}, {},0
local fail
local function store(ctx,id,result)
    ctx.knownCount=(ctx.knownCount or 0)-(ctx.results[id] and ctx.results[id].count or 0)+(result and result.count or 0)
    ctx.results[id]=result
end
local function unwatch(ctx,token)
    if not ctx.listeners[token] then return end
    ctx.listeners[token]=nil ctx.consumers=ctx.consumers-1
    if ctx.consumers==0 and contexts[ctx.id]==ctx then
        if not (EmberRoutesProbeJava and EmberRoutesProbeJava.warehouseFastScan) then
            contexts[ctx.id]=nil ctx.active=nil ctx.merge=nil ctx.rowByType=nil ctx.results={} ctx.dirty={}
            for i=#order,1,-1 do if order[i]==ctx.id then table.remove(order,i) end end
        else
            ctx.active=nil ctx.merge=nil
            for i=#order,1,-1 do if order[i]==ctx.id then table.remove(order,i) end end
        end
    end
end
-- Current pinned ItemContainer JAR + vanilla ISInventoryPage use getDisplayType;
-- the installed Umbrella index omits it.
---@class EmberRoutesPhysicalContainer:ItemContainer
---@field getDisplayType fun(self:EmberRoutesPhysicalContainer):string
local function publish(ctx,state,rows,counts,reason)
    ctx.snapshot={format=1,settlementId=ctx.id,revision=ctx.generation,settlementRevision=ctx.scopeRevision,coverage="ROOT_ONLY",state=state,
        rows=rows or {},counts=counts or {},reason=reason,readAt=Index.clock}
    if state=="UPDATING" then
        local dirty={}
        for id in pairs(ctx.viewDirty or {}) do dirty[id]=true end
        ctx.snapshot.retain=not ctx.viewReset ctx.snapshot.dirtyAll=ctx.viewAll or false ctx.snapshot.dirtySources=dirty
    end
    local failed={}
    for token,listener in pairs(ctx.listeners) do
        local ok,reason=pcall(listener,ctx.snapshot)
        if not ok then failed[#failed+1]=token Log.write("WAREHOUSE","OBSERVER_REMOVED "..tostring(reason)) end
    end
    for _,token in ipairs(failed) do unwatch(ctx,token) end
end
local function invalidate(ctx,id,membership,resetView)
    if ctx.halted then return end -- Error remains explicit until manual refresh.
    if EmberRoutesProbeJava and EmberRoutesProbeJava.warehouseResetCache and (resetView or not id) then
        EmberRoutesProbeJava.warehouseResetCache(ctx.id)
    end
    if not ctx.pending then ctx.viewDirty={} ctx.viewAll=false ctx.viewReset=false end
    local notify=not ctx.pending or (resetView and not ctx.viewReset) or (not id and not ctx.viewAll)
        or (id and not ctx.viewDirty[id])
    if id then ctx.viewDirty[id]=true else ctx.viewAll=true end
    ctx.viewReset=ctx.viewReset or resetView or false
    if ctx.merge or (ctx.active and (not id or ctx.active.id==id)) then
        if ctx.active then ctx.dirty[ctx.active.id]=true ctx.active=nil end
        ctx.restarts=(ctx.restarts or 0)+1
        if ctx.restarts>=8 then fail(ctx,"INVENTORY_UNSTABLE") return end
    end
    ctx.merge=nil ctx.rowByType=nil ctx.scanCursor=1
    if id then store(ctx,id,nil) ctx.dirty[id]=true
    else
        ctx.results={} ctx.knownCount=0
        for _,candidate in ipairs(ctx.ids) do ctx.dirty[candidate]=true end
    end
    ctx.membershipDirty=ctx.membershipDirty or membership
    ctx.pendingSince=ctx.pendingSince or Index.clock
    ctx.generation=ctx.generation+1 ctx.notBefore=math.min(Index.clock+15,ctx.pendingSince+60)
    ctx.pending=true
    if notify then publish(ctx,"UPDATING") end
end
function Index.refresh(id,resetView)
    local ctx=contexts[id]
    if ctx then
        ctx.halted=false ctx.restarts=0 ctx.active=nil ctx.merge=nil ctx.pendingSince=Index.clock
        invalidate(ctx,nil,true,resetView) ctx.notBefore=Index.clock
    end
end
local function fastScanJava(ctx)
    if not (EmberRoutesProbeJava and EmberRoutesProbeJava.warehouseFastScan) then return false end
    local ledger=Ledger.data()
    local entry=ledger.entries[ctx.id]
    if not entry then return false end
    if ctx.membershipDirty or not ctx.ids or #ctx.ids==0 then
        local ids=Membership.query(entry)
        if ids then ctx.ids=ids ctx.membershipDirty=false end
    end
    local containerList={}
    for _,id in ipairs(ctx.ids or {}) do
        local endpoint=Registry.resolve(id,"take","local-world")
        local pos=Registry.data().containers[id]
        if endpoint and endpoint.container then
            local c=endpoint.container
            local cap=(c.getCapacity and c:getCapacity()) or 0
            local used=(c.getCapacityWeight and c:getCapacityWeight()) or (c.getContentsWeight and c:getContentsWeight()) or 0
            containerList[#containerList+1]={
                id=id,
                container=c,
                x=pos and pos.x or 0,
                y=pos and pos.y or 0,
                z=pos and pos.z or 0,
                kind=c:getType() or "container",
                displayType=c.getDisplayType and c:getDisplayType() or nil,
                customName=c.getCustomName and c:getCustomName() or nil,
                capacity=cap,
                usedWeight=used
            }
        else
            containerList[#containerList+1]={
                id=id,
                x=pos and pos.x or 0,
                y=pos and pos.y or 0,
                z=pos and pos.z or 0,
                status="CONTAINER_UNLOADED"
            }
        end
    end

    local snapshot=EmberRoutesProbeJava.warehouseFastScan(ctx.id,containerList,ctx.viewReset or false)
    if not snapshot or snapshot.state~="READY" then return false end

    local rowByType={}
    for _,r in ipairs(snapshot.rows or {}) do
        rowByType[r.fullType]=r
    end
    ctx.rowByType=rowByType
    ctx.fastContainers=snapshot.containers
    ctx.pending=false
    ctx.pendingSince=nil
    ctx.restarts=0
    ctx.viewReset=false
    ctx.dirty={}
    publish(ctx,"READY",snapshot.rows,snapshot.counts)
    return true
end

function Index.watch(id,listener)
    if isClient() or isServer() then return nil,"DRIVER_UNAVAILABLE" end
    local entry=Ledger.data().entries[id]
    if not entry then return nil,"SETTLEMENT_MISSING" end
    if entry.factionId~=Ledger.data().factionId then return nil,"ACCESS_DENIED" end
    local ctx=contexts[id]
    if not ctx then
        ctx={id=id,root=Ledger.data(),scopeRevision=entry.revision,listeners={},consumers=0,ids={},dirty={},results={},generation=0,pending=false}
        contexts[id]=ctx order[#order+1]=id
        if EmberRoutesProbeJava and EmberRoutesProbeJava.warehouseFastScan then
            fastScanJava(ctx)
        else
            Index.refresh(id)
        end
    else
        local inOrder=false
        for _,oId in ipairs(order) do if oId==id then inOrder=true break end end
        if not inOrder then order[#order+1]=id end
        if EmberRoutesProbeJava and EmberRoutesProbeJava.warehouseFastScan and (not ctx.snapshot or ctx.snapshot.state~="READY") then
            fastScanJava(ctx)
        end
    end
    local token={}
    ctx.listeners[token]=listener ctx.consumers=ctx.consumers+1
    local ok,reason=pcall(listener,ctx.snapshot)
    if not ok then
        unwatch(ctx,token) Log.write("WAREHOUSE","OBSERVER_REMOVED "..tostring(reason))
        return nil,"UI_SUBSCRIBER_ERROR"
    end
    return function() unwatch(ctx,token) end
end
fail=function(ctx,reason)
    ctx.active=nil ctx.merge=nil ctx.rowByType=nil ctx.pending=false ctx.halted=true
    Log.write("WAREHOUSE","STOPPED settlement="..ctx.id.." reason="..tostring(reason))
    publish(ctx,"ERROR",nil,nil,reason)
end
local function start(ctx,id)
    local endpoint,reason=Registry.resolve(id,"take","local-world")
    if not endpoint then store(ctx,id,{status=reason}) ctx.dirty[id]=nil return end
    ---@type EmberRoutesPhysicalContainer
    local container=endpoint.container
    local items=container:getItems()
    if items:size()>2000 then store(ctx,id,{status="INVENTORY_SCAN_LIMIT"}) ctx.dirty[id]=nil return end
    local total=items:size()+(ctx.knownCount or 0)
    if total>Index.MAX_ITEMS then fail(ctx,"INVENTORY_SCAN_LIMIT") return end
    local position=Registry.data().containers[id]
    ctx.active={id=id,object=endpoint.object,container=container,items=items,size=items:size(),cursor=0,
        result={status="LOADED",count=items:size(),types={},ids={},x=position.x,y=position.y,z=position.z,
            kind=container:getType(),displayType=container:getDisplayType(),customName=container:getCustomName(),
            capacity=(container.getCapacity and container:getCapacity()) or 0,
            usedWeight=(container.getCapacityWeight and container:getCapacityWeight()) or (container.getContentsWeight and container:getContentsWeight()) or 0}}
end
local function advance(ctx,budget)
    if EmberRoutesProbeJava and EmberRoutesProbeJava.warehouseFastScan then
        if fastScanJava(ctx) then return budget end
    end
    if not ctx.pending or ctx.halted or Index.clock<ctx.notBefore then return 0 end
    local ledger=Ledger.data()
    if ctx.root~=ledger then fail(ctx,"WORLD_CHANGED") return 0 end
    local entry=ledger.entries[ctx.id]
    if not entry then fail(ctx,"SETTLEMENT_MISSING") return 0 end
    ctx.scopeRevision=entry.revision
    if ctx.membershipDirty then
        local ids,reason=Membership.query(entry)
        if not ids then fail(ctx,reason) return 0 end
        ctx.ids=ids ctx.membershipDirty=false
        local present={}
        for _,id in ipairs(ctx.ids) do present[id]=true if not ctx.results[id] then ctx.dirty[id]=true end end
        ctx.members=present
        for id in pairs(ctx.results) do if not present[id] then store(ctx,id,nil) end end
        for id in pairs(ctx.dirty) do if not present[id] then ctx.dirty[id]=nil end end
    end
    local spent=0
    while spent<budget do
        if not ctx.active then
            if ctx.merge then
                local used,state,reason=ctx.merge:step(budget-spent)
                spent=spent+used
                if state=="ERROR" then fail(ctx,reason)
                elseif state=="READY" then
                    local merge=ctx.merge ctx.merge=nil ctx.rowByType=merge.byType
                    Log.write("WAREHOUSE","READY settlement="..ctx.id.." revision="..ctx.generation
                        .." loaded="..merge.counts.loaded.." items="..merge.counts.items.." types="..#merge.rows
                        .." unloaded="..merge.counts.unloaded.." private="..merge.counts.private
                        .." missing="..merge.counts.missing.." limited="..merge.counts.limited)
                    ctx.pending=false ctx.pendingSince=nil ctx.restarts=0
                    publish(ctx,"READY",merge.rows,merge.counts)
                end
                break
            end
            local candidate=ctx.ids[ctx.scanCursor or 1]
            if not candidate then ctx.merge=Rollup.new(ctx.ids,ctx.results,Index.MAX_ITEMS,Index.MAX_TYPES)
            else
                ctx.scanCursor=(ctx.scanCursor or 1)+1 spent=spent+1
                if ctx.dirty[candidate] then start(ctx,candidate) end
                if ctx.halted then break end
            end
        else
            local a=ctx.active
            if a.container:getItems()~=a.items or a.items:size()~=a.size then invalidate(ctx,a.id) break end
            if a.cursor>=a.size then
                local endpoint,reason=Registry.revalidate(a,"take","local-world")
                store(ctx,a.id,endpoint and a.result or {status=reason or "CONTAINER_CHANGED"})
                ctx.dirty[a.id]=nil ctx.active=nil spent=spent+1
            else
                -- Charge before reading: a rejected/duplicate batch may have
                -- already inspected every original, even if Lua stops early.
                local limit=math.min(Read.LIMIT,budget-spent,a.size-a.cursor)
                spent=spent+limit
                local rows=Read.slice(a.container,a.items,a.size,a.cursor,limit)
                if not rows then invalidate(ctx,a.id) break end
                for i=1,#rows,3 do
                    local item,id,fullType=rows[i],rows[i+1],rows[i+2]
                    if a.result.ids[id] then fail(ctx,"ITEM_ID_DUPLICATED") break end
                    a.result.ids[id]=true
                    local value=a.result.types[fullType]
                    if not value then value={count=0,node=Filter.classify(Filter.describe(item),item)} a.result.types[fullType]=value end
                    value.count=value.count+1 a.cursor=a.cursor+1
                end
                if ctx.halted then break end
            end
        end
    end
    return spent
end
local function stepImpl()
    if #order==0 then return 0 end
    local measured=Metrics.begin("index.slice")
    Index.clock=Index.clock+1
    local spent=0
    for _=1,#order do
        if #order==0 then break end
        cursor=cursor%#order+1
        local ctx=contexts[order[cursor]]
        if ctx then
            local ok,result=pcall(advance,ctx,Index.BUDGET-spent)
            if not ok then
                Log.write("WAREHOUSE","READ_ERROR "..tostring(result)) fail(ctx,"INVENTORY_READ_ERROR")
                spent=Index.BUDGET -- Reserve the whole remaining slice after an interrupted call.
            else spent=spent+result end
        end
        if spent>=Index.BUDGET then break end
    end
    Metrics.finish("index.slice",measured)
    return spent
end
-- Sample this standalone tick via the mod's single even-paused dispatcher;
-- without a row its cost stayed invisible. Metrics module resolved at load.
function Index.step()
    if #order==0 then return 0 end
    if not RuntimeMetrics.active() then return stepImpl() end
    local started=RuntimeMetrics.now()
    local spent=stepImpl()
    RuntimeMetrics.measureSpan('WarehouseIndex',started)
    return spent
end
-- Candidate discovery only: no reservations or effect permission are granted.
function Index.candidates(actor,id,request)
    local entry,reason=Ledger.view(actor,id)
    if not entry then return nil,reason end
    local function finite(value) return type(value)=="number" and value==value and math.abs(value)<=10000000 end
    if type(request)~="table" or type(request.fullType)~="string" or #request.fullType==0 or #request.fullType>256 then
        return nil,"INVALID_QUERY"
    end
    local limit=request.limit
    if limit==nil then limit=32 end
    if not finite(limit) or limit<1 or limit>256 or limit~=math.floor(limit) then return nil,"INVALID_QUERY" end
    local origin=request.origin
    if origin~=nil and (type(origin)~="table" or not finite(origin.x) or not finite(origin.y) or not finite(origin.z)) then
        return nil,"INVALID_QUERY"
    end
    local ctx=contexts[id]
    if not ctx then return {state="NOT_REQUESTED",coverage="ROOT_ONLY",sources={},complete=false} end
    if ctx.root~=Ledger.data() then fail(ctx,"WORLD_CHANGED") end
    if ctx.scopeRevision~=entry.revision then Index.refresh(id,true) end
    local s=ctx.snapshot
    local result={state=s.state,reason=s.reason,revision=s.revision,settlementRevision=s.settlementRevision,
        coverage=s.coverage,sources={},complete=false}
    if s.state~="READY" or not ctx.rowByType then return result end
    local c=s.counts
    result.complete=c.unloaded==0 and c.private==0 and c.missing==0 and c.limited==0
    local row=ctx.rowByType[request.fullType]
    result.knownCount=row and row.count or 0
    if not row then return result end
    for _,source in ipairs(row.sources) do
        local copy={id=source.id,x=source.x,y=source.y,z=source.z,count=source.count,
            kind=source.kind,displayType=source.displayType,customName=source.customName}
        if origin then copy.distanceSquared=(source.x-origin.x)^2+(source.y-origin.y)^2+(source.z-origin.z)^2 end
        result.sources[#result.sources+1]=copy
    end
    table.sort(result.sources,function(a,b)
        if origin and a.distanceSquared~=b.distanceSquared then return a.distanceSquared<b.distanceSquared end
        return a.id<b.id
    end)
    result.truncated=#result.sources>limit
    for i=#result.sources,limit+1,-1 do result.sources[i]=nil end
    return result
end
function Index.containers(id)
    local ctx=contexts[id]
    if not ctx then return {} end
    if ctx.fastContainers and #ctx.fastContainers>0 then
        local list={}
        for _,c in ipairs(ctx.fastContainers) do list[#list+1]=c end
        table.sort(list,function(a,b)
            if (a.z or 0)~=(b.z or 0) then return (a.z or 0)<(b.z or 0) end
            if (a.y or 0)~=(b.y or 0) then return (a.y or 0)<(b.y or 0) end
            return (a.x or 0)<(b.x or 0)
        end)
        return list
    end
    local list={}
    for cid,res in pairs(ctx.results or {}) do
        list[#list+1]={
            id=cid,
            x=res.x,
            y=res.y,
            z=res.z,
            kind=res.kind,
            displayType=res.displayType,
            customName=res.customName,
            capacity=res.capacity or 0,
            usedWeight=res.usedWeight or 0,
            status=res.status,
            count=res.count or 0
        }
    end
    table.sort(list,function(a,b)
        if (a.z or 0)~=(b.z or 0) then return (a.z or 0)<(b.z or 0) end
        if (a.y or 0)~=(b.y or 0) then return (a.y or 0)<(b.y or 0) end
        return (a.x or 0)<(b.x or 0)
    end)
    return list
end
function Index.changed(id,resetView)
    if resetView==nil then resetView=true end
    local position=id and Registry.describe(id)
    for _,ctx in pairs(contexts) do
        local entry=Ledger.data().entries[ctx.id]
        if not id or not position or (ctx.members and ctx.members[id])
                or (entry and position and Geometry.inside(entry,position.x,position.y)) then invalidate(ctx,id,true,resetView) end
    end
end
-- Sampled like SettlementFacilities' event handlers: container events run
-- outside every service bucket and spike with world/container churn. Metrics
-- module resolved once; a per-event require would itself become the hot path.
local RuntimeMetrics=require 'EmberRoutesProbe/RuntimeMetrics'
local function containerChanged(object)
    local started=RuntimeMetrics.active() and RuntimeMetrics.now() or nil
    local ids=Registry.affected(object)
    if not ids then Index.changed(nil,false) else for _,id in ipairs(ids) do Index.changed(id,false) end end
    if started then RuntimeMetrics.measureSpan('ModEvents',started) end
end
Registry.listeners[#Registry.listeners+1]=Index.changed
Registry.inventoryListeners[#Registry.inventoryListeners+1]=function(id)
    for _,ctx in pairs(contexts) do if ctx.members and ctx.members[id] then invalidate(ctx,id,false) end end
end
Ledger.listeners[#Ledger.listeners+1]=function(id) if contexts[id] then Index.refresh(id,true) end end
Events.OnContainerUpdate.Add(containerChanged)
-- Actual IngameState dispatches this while paused too; read-only UI jobs stay responsive.
-- Registered through the mod's single even-paused dispatcher.
require('EmberRoutesProbe/EvenPaused').add(Index.step)
Events.OnGameStart.Add(function()
    if Metrics.enabled then Metrics.stop() end
    local old=contexts
    contexts,order,cursor={},{},0
    for _,ctx in pairs(old) do
        ctx.active=nil ctx.merge=nil ctx.rowByType=nil ctx.results={} ctx.dirty={} ctx.pending=false ctx.halted=true
        publish(ctx,"ERROR",nil,nil,"WORLD_CHANGED")
    end
end)
return Index
