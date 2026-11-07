-- Explicit platform selection; resolve one saved square, never scan a territory.
local Registry=require "EmberRoutesProbe/Warehouse/ContainerRegistry"
local Ledger=require "EmberRoutesProbe/Settlement/SettlementLedger"
local Geometry=require "EmberRoutesProbe/Settlement/SettlementGeometry"
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
function Surfaces.findNearest(entry,npc)
    if not entry then return nil,"SETTLEMENT_REQUIRED" end
    local list=Surfaces.list(entry)
    if #list==0 then return nil,"CRAFT_SURFACE_REQUIRED" end
    local anyUnloaded=false
    if not npc then
        for _,surface in ipairs(list) do
            local candidate,why=Surfaces.resolve(surface,surface.id)
            if candidate and candidate:getModData().EmberRoutesExcluded~=true then
                return candidate,nil,surface.id
            elseif why=="SURFACE_UNLOADED" then
                anyUnloaded=true
            end
        end
        return nil,anyUnloaded and "SURFACE_UNLOADED" or "CRAFT_SURFACE_REQUIRED"
    end
    local bestObj,bestDist,bestId=nil,nil,nil
    local nx,ny,nz=npc:getX(),npc:getY(),npc:getZ()
    for _,surface in ipairs(list) do
        local candidate,why=Surfaces.resolve(surface,surface.id)
        if candidate and candidate:getModData().EmberRoutesExcluded~=true then
            if not candidate:getUsingPlayer() or candidate:getUsingPlayer()==npc then
                local dx=surface.x+0.5-nx
                local dy=surface.y+0.5-ny
                local dz=(surface.z-nz)*4
                local d=dx*dx+dy*dy+dz*dz
                if not bestDist or d<bestDist then
                    bestDist=d bestObj=candidate bestId=surface.id
                end
            end
        elseif why=="SURFACE_UNLOADED" then
            anyUnloaded=true
        end
    end
    if bestObj then return bestObj,nil,bestId end
    return nil,anyUnloaded and "SURFACE_UNLOADED" or "CRAFT_SURFACE_REQUIRED"
end
return Surfaces
