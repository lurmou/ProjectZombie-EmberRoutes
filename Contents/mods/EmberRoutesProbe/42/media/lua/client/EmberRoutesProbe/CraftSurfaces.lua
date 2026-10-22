-- Explicit platform selection; resolve one saved square, never scan a territory.
local Registry=require "EmberRoutesProbe/ContainerRegistry"
local Ledger=require "EmberRoutesProbe/SettlementLedger"
local Geometry=require "EmberRoutesProbe/SettlementGeometry"
local Surfaces={}
function Surfaces.location(object)
    local square=object and object:getSquare()
    if not square then return nil end
    return {x=square:getX(),y=square:getY(),z=square:getZ()}
end
function Surfaces.resolve(position,id)
    if not position then return nil,"CRAFT_SURFACE_REQUIRED" end
    local cell=getCell()
    local square=cell and cell:getGridSquare(position.x,position.y,position.z)
    if not square then return nil,"SURFACE_UNLOADED" end
    local found
    local objects=square:getObjects()
    for i=0,objects:size()-1 do
        local object=objects:get(i)
        if object:getModData().EmberRoutesCraftProbeBenchId==id then
            if found then return nil,"SURFACE_ID_CONFLICT" end found=object
        end
    end
    if not found or not found.isGenericCraftingSurface or not found:isGenericCraftingSurface() then
        return nil,"CRAFT_SURFACE_REQUIRED"
    end
    return found
end
function Surfaces.remember(actor,object)
    local entries=Ledger.at(actor:getX(),actor:getY())
    if #entries~=1 then return nil,"SETTLEMENT_REQUIRED" end
    local entry,reason=Ledger.view(actor,entries[1].id)
    if not entry then return nil,reason end
    local position=Surfaces.location(object)
    if not position or not object.isGenericCraftingSurface or not object:isGenericCraftingSurface()
        or not Geometry.inside(entry,position.x,position.y) then return nil,"CRAFT_SURFACE_REQUIRED" end
    local square=object:getSquare() local cell=getCell()
    if not cell or cell:getGridSquare(position.x,position.y,position.z)~=square
        or not square:getObjects():contains(object) then return nil,"SURFACE_UNLOADED" end
    local root=Registry.data() local saved=root.craftSurfaces or {}
    local id=object:getModData().EmberRoutesCraftProbeBenchId
    if not id or not saved[id] then
        local count=0 for _ in pairs(saved) do count=count+1 end
        if count>=64 then return nil,"SURFACE_LIMIT" end
    end
    id=id or Registry.id() object:getModData().EmberRoutesCraftProbeBenchId=id
    saved[id]=position root.craftSurfaces=saved
    return {id=id,settlementId=entry.id,x=position.x,y=position.y,z=position.z}
end
function Surfaces.list(entry)
    local result={}
    for id,position in pairs(Registry.data().craftSurfaces or {}) do
        if Geometry.inside(entry,position.x,position.y) then
            result[#result+1]={id=id,x=position.x,y=position.y,z=position.z}
        end
    end
    table.sort(result,function(a,b) return a.id<b.id end)
    return result
end
return Surfaces
