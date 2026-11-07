local Geometry=require "EmberRoutesProbe/Settlement/SettlementGeometry"
local Registry=require "EmberRoutesProbe/Warehouse/ContainerRegistry"
local Gate=require "EmberRoutesProbe/Kernel/RuntimeGate"
local Ledger={listeners={},validators={}}
---@class EmberRoutesSettlement
---@field format integer
---@field id string
---@field factionId string
---@field name string
---@field revision integer
---@field areas table[]
---@return {format:number,entries:table<string,EmberRoutesSettlement>,revision:number,factionId:string}
function Ledger.data()
    -- Native root-handle cache (cleared on world lifecycle by the extension);
    -- missing/noop bridge keeps the direct getOrCreate path for fixtures.
    local bridge=EmberRoutesProbeJava
    local data
    if bridge and bridge.cachedModData then
        local ok,cached=pcall(bridge.cachedModData,"EmberRoutes/Settlements/v1")
        if ok then data=cached end
    end
    if not data then data=ModData.getOrCreate("EmberRoutes/Settlements/v1") end
    if data.format and data.format~=1 then error("SETTLEMENT_FORMAT_UNSUPPORTED") end
    data.format,data.entries,data.revision=1,data.entries or {},data.revision or 0
    data.factionId=data.factionId or Registry.id()
    return data
end
function Ledger.authorized(actor)
    return Gate.canExecute(actor)
        and type(actor.getIndex)=="function"
        and getSpecificPlayer(actor:getIndex())==actor
end
-- Detached read DTO: UI edits cannot bypass commit() by mutating persisted tables.
---@return EmberRoutesSettlement?
function Ledger.get(id)
    local entry=Ledger.data().entries[id]
    if not entry then return nil end
    local copy={format=entry.format,id=entry.id,name=entry.name,factionId=entry.factionId,revision=entry.revision,areas={}}
    if entry.returnPoint then local p=entry.returnPoint copy.returnPoint={x=p.x,y=p.y,z=p.z,revision=p.revision} end
    for _,r in ipairs(entry.areas) do copy.areas[#copy.areas+1]={x=r.x,y=r.y,w=r.w,h=r.h} end
    return copy
end
function Ledger.view(actor,id)
    if not Ledger.authorized(actor) then return nil,"DRIVER_UNAVAILABLE" end
    local entry=Ledger.get(id)
    if not entry then return nil,"SETTLEMENT_MISSING" end
    if entry.factionId~=Ledger.data().factionId then return nil,"ACCESS_DENIED" end
    return entry
end
function Ledger.list()
    local result={}
    for id in pairs(Ledger.data().entries) do result[#result+1]=Ledger.get(id) end
    table.sort(result,function(a,b) return a.id<b.id end)
    return result
end
function Ledger.at(x,y)
    local data=Ledger.data() local factionId=data.factionId
    local result={}
    for _,entry in ipairs(Ledger.list()) do
        if entry.factionId==factionId and Geometry.inside(entry,x,y) then result[#result+1]=entry end
    end
    return result
end
-- Internal live lookup for per-tick runtime paths: returns the persisted entries
-- themselves (no copy, no sort, no actor authorization). Callers must treat the
-- result as read-only; detached DTOs remain the only published form.
local function nameValue(name)
    if type(name)~="string" then return nil end
    name=name:match("^%s*(.-)%s*$")
    if name=="" or #name>64 or name:find("[%c]") then return nil end
    return name
end
local function notify(data,entry)
    data.revision=data.revision+1 entry.revision=(entry.revision or 0)+1
    for _,fn in ipairs(Ledger.listeners) do fn(entry.id) end
end
function Ledger.setReturnPoint(actor,id,point,expected)
    local entry,why=Ledger.view(actor,id) if not entry then return false,why end
    if entry.revision~=expected then return false,'SETTLEMENT_CHANGED' end
    if type(point)~='table' then return false,'RETURN_POINT_INVALID' end
    for _,key in ipairs({'x','y','z'}) do
        local n=point[key] if type(n)~='number' or n~=n or math.abs(n)>10000000 then return false,'RETURN_POINT_INVALID' end
    end
    if point.z~=math.floor(point.z) or not Geometry.inside(entry,point.x,point.y) then return false,'RETURN_POINT_INVALID' end
    local square=getCell() and getCell():getGridSquare(math.floor(point.x),math.floor(point.y),point.z)
    if not square then return false,'TARGET_UNLOADED' end
    if not square:isFree(false) then return false,'RETURN_POINT_BLOCKED' end
    local data=Ledger.data() local live=data.entries[id]
    live.returnPoint={x=point.x,y=point.y,z=point.z,revision=(live.returnPoint and live.returnPoint.revision or 0)+1}
    notify(data,live) return true
end
local returnWorld,returnSearches
-- One shared settlement target. Search state is disposable and bounded; no NPC
-- receives a private home and no unobserved/blocked coordinate is persisted.
function Ledger.ensureReturnPoint(actor,id)
    local entry,why=Ledger.view(actor,id)
    if not entry then return false,why end
    if entry.returnPoint then return true,'RETURN_POINT_SET' end
    local data=Ledger.data()
    if returnWorld~=data then returnWorld,returnSearches=data,{} end
    local scan=returnSearches[id]
    if not scan or scan.revision~=entry.revision then
        scan={revision=entry.revision,area=0,offsets={},nextAt=0} returnSearches[id]=scan
    end
    local now=type(getTimestampMs)=='function' and getTimestampMs() or 0
    if now<scan.nextAt then return false,'RETURN_POINT_INITIALIZING' end
    scan.nextAt=now+1000
    local cell=type(getCell)=='function' and getCell()
    if not cell then return false,'TARGET_UNLOADED' end
    local function candidate(x,y,z)
        if not Geometry.inside(entry,x,y) then return false end
        local square=cell:getGridSquare(x,y,z)
        if not square or not square.TreatAsSolidFloor or not square:TreatAsSolidFloor()
            or not square.isFree or not square:isFree(false) then return false end
        local ok,reason=Ledger.setReturnPoint(actor,id,{x=x+0.5,y=y+0.5,z=z},entry.revision)
        if ok then returnSearches[id]=nil end
        return ok,reason
    end
    -- Prefer the creator's observed floor when it lies in the settlement.
    if actor.getX and actor.getY and actor.getZ
        and candidate(math.floor(actor:getX()),math.floor(actor:getY()),math.floor(actor:getZ())) then
        return true,'RETURN_POINT_SET'
    end
    -- Try each area's centre first, then advance through its actual ground
    -- squares. Round-robin areas avoids an unloaded rectangle starving others.
    for _,a in ipairs(entry.areas) do
        if candidate(a.x+math.floor(a.w/2),a.y+math.floor(a.h/2),0) then return true,'RETURN_POINT_SET' end
    end
    for _=1,64-#entry.areas do
        scan.area=scan.area%#entry.areas+1
        local a=entry.areas[scan.area] local offset=scan.offsets[scan.area] or 0
        local x,y=a.x+offset%a.w,a.y+math.floor(offset/a.w)
        scan.offsets[scan.area]=(offset+1)%(a.w*a.h)
        if candidate(x,y,0) then return true,'RETURN_POINT_SET' end
    end
    return false,'RETURN_POINT_INITIALIZING'
end
-- Validators are pure rejection hooks for future registered system-town boundaries.
-- No native town/protection object is created here.
function Ledger.commit(actor,id,name,area)
    if not Ledger.authorized(actor) then return nil,"DRIVER_UNAVAILABLE" end
    name=nameValue(name)
    if not name then return nil,"INVALID_NAME" end
    local isList=type(area)=="table" and area[1]~=nil
    local isSingle=type(area)=="table" and area.x~=nil and not isList
    if isSingle and not Geometry.valid(area) then return nil,"INVALID_BOUNDS" end
    if isList then
        if #area==0 then return nil,"INVALID_BOUNDS" end
        if #area>(Geometry.MAX_AREAS or 32) then return nil,"AREA_LIMIT" end
        for _,r in ipairs(area) do if not Geometry.valid(r) then return nil,"INVALID_BOUNDS" end end
    end
    local data=Ledger.data()
    local entry=id and data.entries[id]
    if id and not entry then return nil,"SETTLEMENT_MISSING" end
    if entry and entry.factionId~=data.factionId then return nil,"ACCESS_DENIED" end
    if not entry and not area then return nil,"INVALID_BOUNDS" end
    if not entry and #Ledger.list()>=32 then return nil,"SETTLEMENT_LIMIT" end
    if entry and isSingle and #entry.areas>=16 then return nil,"AREA_LIMIT" end
    if isSingle then
        for _,validate in ipairs(Ledger.validators) do
            local reason=validate(data.factionId,area,id)
            if reason then return nil,reason end
        end
    elseif isList then
        for _,r in ipairs(area) do
            for _,validate in ipairs(Ledger.validators) do
                local reason=validate(data.factionId,r,id)
                if reason then return nil,reason end
            end
        end
    end
    if not entry then
        entry={format=1,id=Registry.id(),name=name,factionId=data.factionId,areas={},revision=0}
        data.entries[entry.id]=entry
    end
    entry.name=name
    if isList then
        local sanitized={}
        for _,r in ipairs(area) do sanitized[#sanitized+1]={x=r.x,y=r.y,w=r.w,h=r.h} end
        entry.areas=sanitized
    elseif isSingle then
        entry.areas[#entry.areas+1]={x=area.x,y=area.y,w=area.w,h=area.h}
    end
    notify(data,entry)
    if not entry.returnPoint then Ledger.ensureReturnPoint(actor,entry.id) end
    return Ledger.get(entry.id),"SETTLEMENT_SAVED"
end
return Ledger
