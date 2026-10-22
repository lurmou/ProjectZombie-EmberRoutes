local Geometry=require "EmberRoutesProbe/SettlementGeometry"
local Registry=require "EmberRoutesProbe/ContainerRegistry"
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
    local data=ModData.getOrCreate("EmberRoutes/Settlements/v1")
    if data.format and data.format~=1 then error("SETTLEMENT_FORMAT_UNSUPPORTED") end
    data.format,data.entries,data.revision=1,data.entries or {},data.revision or 0
    data.factionId=data.factionId or Registry.id()
    return data
end
function Ledger.authorized(actor)
    return not isClient() and not isServer() and actor and not actor:isDead()
        and getSpecificPlayer(actor:getIndex())==actor
end
-- Detached read DTO: UI edits cannot bypass commit() by mutating persisted tables.
---@return EmberRoutesSettlement?
function Ledger.get(id)
    local entry=Ledger.data().entries[id]
    if not entry then return nil end
    local copy={format=entry.format,id=entry.id,name=entry.name,factionId=entry.factionId,revision=entry.revision,areas={}}
    for _,r in ipairs(entry.areas) do copy.areas[#copy.areas+1]={x=r.x,y=r.y,w=r.w,h=r.h} end
    return copy
end
function Ledger.view(actor,id)
    if not Ledger.authorized(actor) then return nil,"DRIVER_UNAVAILABLE" end
    local entry=Ledger.get(id)
    if not entry then return nil,"SETTLEMENT_MISSING" end
    if entry.factionId~=Ledger.data().factionId then return nil,"ACCESS_DENIED" end
    if not Geometry.inside(entry,actor:getX(),actor:getY()) then return nil,"OUTSIDE_SETTLEMENT" end
    return entry
end
function Ledger.list()
    local result={}
    for id in pairs(Ledger.data().entries) do result[#result+1]=Ledger.get(id) end
    table.sort(result,function(a,b) return a.id<b.id end)
    return result
end
function Ledger.at(x,y)
    local result={}
    for _,entry in ipairs(Ledger.list()) do
        if entry.factionId==Ledger.data().factionId and Geometry.inside(entry,x,y) then result[#result+1]=entry end
    end
    return result
end
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
-- Validators are pure rejection hooks for future registered system-town boundaries.
-- No native town/protection object is created here.
function Ledger.commit(actor,id,name,area)
    if not Ledger.authorized(actor) then return nil,"DRIVER_UNAVAILABLE" end
    name=nameValue(name)
    if not name then return nil,"INVALID_NAME" end
    if area and not Geometry.valid(area) then return nil,"INVALID_BOUNDS" end
    local data=Ledger.data()
    local entry=id and data.entries[id]
    if id and not entry then return nil,"SETTLEMENT_MISSING" end
    if entry and entry.factionId~=data.factionId then return nil,"ACCESS_DENIED" end
    if not entry and not area then return nil,"INVALID_BOUNDS" end
    if not entry and #Ledger.list()>=32 then return nil,"SETTLEMENT_LIMIT" end
    if entry and area and #entry.areas>=16 then return nil,"AREA_LIMIT" end
    if area then
        for _,validate in ipairs(Ledger.validators) do
            local reason=validate(data.factionId,area,id)
            if reason then return nil,reason end
        end
    end
    if not entry then
        entry={format=1,id=Registry.id(),name=name,factionId=data.factionId,areas={},revision=0}
        data.entries[entry.id]=entry
    end
    entry.name=name
    if area then entry.areas[#entry.areas+1]={x=area.x,y=area.y,w=area.w,h=area.h} end
    notify(data,entry)
    return Ledger.get(entry.id),"SETTLEMENT_SAVED"
end
return Ledger
