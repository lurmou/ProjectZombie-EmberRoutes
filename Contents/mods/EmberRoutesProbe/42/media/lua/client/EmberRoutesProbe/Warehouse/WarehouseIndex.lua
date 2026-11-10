-- Read model only. No InventoryItem/IsoObject is published or persisted.
local Registry=require "EmberRoutesProbe/Warehouse/ContainerRegistry"
local Ledger=require "EmberRoutesProbe/Settlement/SettlementLedger"
local Membership=require "EmberRoutesProbe/Settlement/SettlementMembership"
local Filter=require "EmberRoutesProbe/Warehouse/StorageFilter"
local Log=require "EmberRoutesProbe/Kernel/Log"
local Rollup=require "EmberRoutesProbe/Warehouse/WarehouseRollup"
local Geometry=require "EmberRoutesProbe/Settlement/SettlementGeometry"
local Metrics=require "EmberRoutesProbe/Warehouse/WarehouseMetrics"
local RuntimeMetrics=require 'EmberRoutesProbe/Kernel/RuntimeMetrics'
local Read=require 'EmberRoutesProbe/Warehouse/InventoryRead'
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
        -- AE2 Invariant: DO NOT destroy contexts[ctx.id] or ctx.snapshot!
        -- ctx.snapshot is an immutable front snapshot table containing only scalar numbers and strings.
        -- Retaining it preserves the zero-wait instant display on interface reopening.
        ctx.active=nil
        ctx.merge=nil
        if not (EmberRoutesProbeJava and EmberRoutesProbeJava.warehouseApplyContainer) then
            for i=#order,1,-1 do if order[i]==ctx.id then table.remove(order,i) end end
        else
            -- Release mounted container references while no view is watching;
            -- they would otherwise pin unloaded ItemContainer objects forever.
            ctx.handles=nil
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
    if state=="READY" then
        ctx.lastReadySnapshot=ctx.snapshot
    elseif state=="UPDATING" then
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
    -- A single container change must not destroy the native aggregate: the
    -- incremental path re-reads only that container (AE2 unmount/mount is per
    -- storage). Only a whole-settlement refresh drops the cache.
    if EmberRoutesProbeJava and EmberRoutesProbeJava.warehouseResetCache and not id then
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
        -- Whole-settlement refresh remounts: one mount pass beats N per-container
        -- applies that each recompile the snapshot.
        ctx.handles=nil
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
local function acceptSnapshot(ctx,snapshot)
    if not snapshot or snapshot.state~="READY" then return false end
    -- The native index returns the same compiled snapshot while nothing changed.
    -- Republishing it would rebuild every subscribed view on each dispatch.
    -- If ctx.snapshot is not in READY state, we must publish so the view receives READY.
    if snapshot==ctx.publishedScan and not ctx.membershipDirty and ctx.snapshot and ctx.snapshot.state=="READY" then return true end
    ctx.publishedScan=snapshot
    local rowByType={}
    for _,r in ipairs(snapshot.rows or {}) do
        rowByType[r.fullType]=r
    end
    ctx.rowByType=rowByType
    ctx.luaFallback=nil
    ctx.fastContainers=snapshot.containers
    ctx.pending=false
    ctx.pendingSince=nil
    ctx.restarts=0
    ctx.viewReset=false
    publish(ctx,"READY",snapshot.rows,snapshot.counts)
    return true
end

-- Handle layer: one resolved container plus a reusable descriptor table.
-- Mirrors a mounted AE2 storage handle: built once per id, content refreshed
-- in place instead of rebuilding the whole container list on every pass.
local function resolveHandle(id)
    local position=Registry.data().containers[id] or {x=0,y=0,z=0}
    local endpoint,reason=Registry.resolve(id,"take","local-world")
    if endpoint and endpoint.container then
        local c=endpoint.container
        return {endpoint=endpoint,container=c,descriptor={
            id=id,container=c,x=position.x,y=position.y,z=position.z,
            capacity=(c.getCapacity and c:getCapacity()) or 0,
            usedWeight=(c.getCapacityWeight and c:getCapacityWeight()) or 0,
            kind=(c.getType and c:getType()) or "container",
            displayType=c.getDisplayType and c:getDisplayType() or nil,
            customName=c.getCustomName and c:getCustomName() or nil}}
    end
    return {descriptor={
        id=id,x=position.x,y=position.y,z=position.z,capacity=0,usedWeight=0,
        kind="container",status="CONTAINER_UNLOADED"},reason=reason},reason
end

-- An endpoint the registry cannot resolve (private/moved/removed) must never be
-- reported as merely unloaded: the Lua read model keeps the real reason. Drop
-- the native aggregate and let the Lua index answer for a bounded window.
local LUA_RETRY_STEPS=100
local function fallbackToLua(ctx)
    ctx.luaFallback=true
    ctx.handles=nil
    ctx.publishedScan=nil
    ctx.nativeRetryAt=Index.clock+LUA_RETRY_STEPS
    Index.refresh(ctx.id,false)
    return false
end

local function mountHandles(ctx)
    local entry=Ledger.data().entries[ctx.id]
    if not entry then return false end
    if ctx.membershipDirty or not ctx.ids or #ctx.ids==0 then
        local ids=Membership.query(entry)
        if ids then ctx.ids=ids ctx.membershipDirty=false end
    end
    local handles,list,members={},{},{}
    for _,id in ipairs(ctx.ids or {}) do
        local handle=resolveHandle(id)
        if not handle.container and handle.reason~="CONTAINER_UNLOADED" then return fallbackToLua(ctx) end
        handles[id]=handle members[id]=true
        list[#list+1]=handle.descriptor
    end
    ctx.handles=handles ctx.members=members
    if acceptSnapshot(ctx,EmberRoutesProbeJava.warehouseMountSettlement(ctx.id,list)) then
        ctx.dirty={}
        return true
    end
    return false
end

local function applyHandle(ctx,id)
    if ctx.members and not ctx.members[id] then return end
    local handle=ctx.handles and ctx.handles[id]
    if not handle then
        -- Newly added member or a container mounted after the last refresh.
        handle=resolveHandle(id)
        ctx.handles=ctx.handles or {}
        ctx.handles[id]=handle
    end
    if not handle.container and handle.reason~="CONTAINER_UNLOADED" then return fallbackToLua(ctx) end
    local d=handle.descriptor
    if handle.container then
        d.usedWeight=(handle.container.getCapacityWeight and handle.container:getCapacityWeight()) or d.usedWeight
    end
    acceptSnapshot(ctx,EmberRoutesProbeJava.warehouseApplyContainer(ctx.id,d))
end

-- Membership diff (AE2 mount/unmount). Ids that left the roster are removed from
-- the native aggregate entirely, unlike an unloaded container which keeps a
-- record. Ids that joined are resolved and queued for one content read.
local function applyMembership(ctx,ids)
    ctx.handles=ctx.handles or {}
    local present={}
    for _,id in ipairs(ids) do present[id]=true end
    for id in pairs(ctx.handles) do
        if not present[id] then
            ctx.handles[id]=nil
            ctx.dirty[id]=nil
            EmberRoutesProbeJava.warehouseUnmountContainer(ctx.id,id)
        end
    end
    for _,id in ipairs(ids) do
        if not ctx.handles[id] then
            local handle=resolveHandle(id)
            if not handle.container and handle.reason~="CONTAINER_UNLOADED" then return fallbackToLua(ctx) end
            ctx.handles[id]=handle
            ctx.dirty[id]=true
        end
    end
    ctx.members=present
    ctx.membershipDirty=false
    return true
end

-- Full re-check of every mounted handle: identity first, then content. Content
-- must be re-fingerprinted here because not every engine-side mutation raises
-- OnContainerUpdate (scripted addItem/removeItem). An unchanged container
-- returns the same compiled snapshot and publishes nothing.
-- Runs on a self-lengthening idle period: AE2 asks the network to tick slower
-- when nothing changed, which keeps an idle settlement from paying this pass
-- on every dispatch.
local function verifyHandles(ctx)
    local quiet=true
    for id,handle in pairs(ctx.handles or {}) do
        if handle.container then
            local current=Registry.revalidate(handle.endpoint,"take","local-world")
            if not current or current.container~=handle.container then
                ctx.handles[id]=resolveHandle(id)
                ctx.dirty[id]=true
                quiet=false
            else
                local d=handle.descriptor
                d.usedWeight=(handle.container.getCapacityWeight and handle.container:getCapacityWeight()) or d.usedWeight
                local before=ctx.publishedScan
                acceptSnapshot(ctx,EmberRoutesProbeJava.warehouseApplyContainer(ctx.id,d))
                if ctx.publishedScan~=before then quiet=false end
            end
        else
            local replacement=resolveHandle(id)
            if replacement.container then
                ctx.handles[id]=replacement ctx.dirty[id]=true quiet=false
            end
        end
    end
    return quiet
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
        if EmberRoutesProbeJava and EmberRoutesProbeJava.warehouseApplyContainer then
            mountHandles(ctx)
        else
            Index.refresh(id)
        end
    else
        local inOrder=false
        for _,oId in ipairs(order) do if oId==id then inOrder=true break end end
        if not inOrder then
            order[#order+1]=id
            if not (EmberRoutesProbeJava and EmberRoutesProbeJava.warehouseApplyContainer) then
                Index.refresh(id)
            end
        end
        if EmberRoutesProbeJava and EmberRoutesProbeJava.warehouseApplyContainer
                and (not ctx.snapshot or ctx.snapshot.state~="READY") then
            mountHandles(ctx)
        end
    end
    local token={}
    ctx.listeners[token]=listener ctx.consumers=ctx.consumers+1
    local initialSnapshot = (ctx.snapshot and ctx.snapshot.state == "READY") and ctx.snapshot or (ctx.lastReadySnapshot or ctx.snapshot)
    local ok,reason=pcall(listener,initialSnapshot)
    if not ok then
        unwatch(ctx,token) Log.write("WAREHOUSE","OBSERVER_REMOVED "..tostring(reason))
        return nil,"UI_SUBSCRIBER_ERROR"
    end
    return function() unwatch(ctx,token) end
end
fail=function(ctx,reason)
    ctx.active=nil ctx.merge=nil ctx.rowByType=nil ctx.pending=false ctx.halted=true ctx.handles=nil
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
-- Incremental path: at most this many containers per dispatcher pass, the
-- equivalent of AE2's per-tick work allowance.
-- Dispatcher passes, not wall time: one pass is the pacing unit this index
-- already uses, so behaviour does not depend on a host clock global.
local APPLY_PER_STEP=4
local VERIFY_MIN_STEPS=20
local VERIFY_MAX_STEPS=160

local function advanceNative(ctx,budget)
    if not ctx.handles then
        mountHandles(ctx)
        return budget
    end
    if ctx.membershipDirty then
        local entry=Ledger.data().entries[ctx.id]
        if not entry then return 0 end
        local ids=Membership.query(entry)
        if ids and not applyMembership(ctx,ids) then return 0 end
    end
    local applied=0
    for id in pairs(ctx.dirty) do
        if applied>=APPLY_PER_STEP then break end
        ctx.dirty[id]=nil
        applied=applied+1
        applyHandle(ctx,id)
    end
    if applied>0 then return applied end
    -- Idle: re-verify mounted handles on a lengthening period instead of
    -- rescanning every container on a fixed one. No bridge call asks
    -- whether a verify is due: the gate is the local step clock plus the
    -- backoff below, and every real change already arrives as a dirty
    -- apply (Ledger.listeners / inventory listeners / OnContainerUpdate).
    -- The verify only exists for silent scripted mutations that raise no
    -- event; its fingerprint fast path republishes nothing when unchanged.
    if not ctx.verifyAt or Index.clock>=ctx.verifyAt then
        local quiet=verifyHandles(ctx)
        ctx.verifySteps=quiet and math.min((ctx.verifySteps or VERIFY_MIN_STEPS)*2,VERIFY_MAX_STEPS) or VERIFY_MIN_STEPS
        ctx.verifyAt=Index.clock+(ctx.verifySteps or VERIFY_MIN_STEPS)
    end
    return 0
end

local function advance(ctx,budget)
    if ctx.halted then return 0 end
    if EmberRoutesProbeJava then
        -- The native mount/apply bridge is part of this build's contract; a
        -- missing entry means the jar and these scripts are not a pair.
        if not (EmberRoutesProbeJava.warehouseApplyContainer
                and EmberRoutesProbeJava.warehouseUnmountContainer) then
            fail(ctx,"FAST_INDEX_INCOMPLETE")
            return 0
        end
        -- While the Lua read model answers (unresolvable endpoints), retry the
        -- native path only after a bounded delay.
        local retry=ctx.nativeRetryAt
        if not ctx.luaFallback or (retry and Index.clock>=retry) then
            ctx.luaFallback=nil ctx.nativeRetryAt=nil
            return advanceNative(ctx,budget)
        end
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
-- O(1) aggregate read. The Java side keeps an incremental KeyCounter, so this
-- never touches item rows and never triggers a recompile; older JARs fall back
-- to the published row index.
function Index.typeCount(id,fullType)
    local bridge=EmberRoutesProbeJava
    if bridge and bridge.warehouseTypeCount then
        return bridge.warehouseTypeCount(id,fullType) or 0
    end
    local ctx=contexts[id]
    local row=ctx and ctx.rowByType and ctx.rowByType[fullType]
    return row and row.count or 0
end
function Index.hasType(id,fullType) return Index.typeCount(id,fullType)>0 end
-- Candidate discovery only: no reservations or effect permission are granted.
function Index.candidates(actor,id,request)
    local entry,reason=Ledger.view(actor,id)
    if not entry then return nil,reason end
    if not Geometry.inside(entry,actor:getX(),actor:getY()) then return nil,"OUTSIDE_SETTLEMENT" end
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
        local position=Registry.describe(cid)
        list[#list+1]={
            id=cid,
            x=res.x or position and position.x,
            y=res.y or position and position.y,
            z=res.z or position and position.z,
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
                or (entry and position and Geometry.inside(entry,position.x,position.y)) then invalidate(ctx,id,false,resetView) end
    end
end
-- Sampled like SettlementFacilities' event handlers: container events run
-- outside every service bucket and spike with world/container churn. Metrics
-- module resolved once; a per-event require would itself become the hot path.
local RuntimeMetrics=require 'EmberRoutesProbe/Kernel/RuntimeMetrics'
local function containerChanged(object)
    local started=RuntimeMetrics.active() and RuntimeMetrics.now() or nil
    local ids=Registry.affected(object)
    if not ids then
        -- An event we cannot attribute used to invalidate every settlement's
        -- whole index. Membership did not actually change, so just ask each
        -- context to re-diff its roster on the next pass.
        for _,ctx in pairs(contexts) do ctx.membershipDirty=true end
    else
        for _,id in ipairs(ids) do Index.changed(id,false) end
    end
    if started then RuntimeMetrics.measureSpan('ModEvents',started) end
end
-- Registry changes (container registered, moved or untagged) can change
-- settlement membership without any inventory event. Mark it so the next pass
-- diffs the roster and unmounts containers that left (AE2 unmount).
function Index.registryChanged(id)
    Index.changed(id,true)
    for _,ctx in pairs(contexts) do ctx.membershipDirty=true end
end
function Index.snapshot(id)
    local ctx=contexts[id]
    if not ctx then return nil end
    if ctx.snapshot and ctx.snapshot.state=="READY" then return ctx.snapshot end
    return ctx.lastReadySnapshot or ctx.snapshot
end

Registry.listeners[#Registry.listeners+1]=Index.registryChanged
Registry.inventoryListeners[#Registry.inventoryListeners+1]=function(id)
    for _,ctx in pairs(contexts) do if ctx.members and ctx.members[id] then invalidate(ctx,id,false) end end
end
Ledger.listeners[#Ledger.listeners+1]=function(id) if contexts[id] then Index.refresh(id,true) end end
Events.OnContainerUpdate.Add(containerChanged)
-- Actual IngameState dispatches this while paused too; read-only UI jobs stay responsive.
-- Registered through the mod's single even-paused dispatcher.
require('EmberRoutesProbe/Kernel/EvenPaused').add(Index.step)
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
