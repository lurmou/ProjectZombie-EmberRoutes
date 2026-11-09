--[[
    NearbyContainers.lua - EmberRoutes Warehouse
    Finds and orders interactable world containers around the player.
]]
local Registry = require "EmberRoutesProbe/Warehouse/ContainerRegistry"

local NearbyContainers = {}

---Scans for valid world containers within the specified tile radius of the actor.
---@param actor IsoPlayer
---@param currentObject IsoObject? The object currently selected/viewed
---@param currentContainer ItemContainer? The specific container currently viewed
---@param radius number? Defaults to 8 tiles
---@return table[] Array of {object, container, name, dist, x, y, z, isCurrent}
function NearbyContainers.scan(actor, currentObject, currentContainer, radius)
    if not actor or type(actor.getX) ~= "function" then return {} end
    if type(_G.getCell) ~= "function" then return {} end
    local cell = _G.getCell()
    if not cell then return {} end

    radius = radius or 8
    local ax, ay, az = actor:getX(), actor:getY(), actor:getZ()
    local px, py, pz = math.floor(ax), math.floor(ay), math.floor(az)
    local list = {}
    local seen = {}

    local minX, maxX = px - radius, px + radius
    local minY, maxY = py - radius, py + radius

    for sx = minX, maxX do
        for sy = minY, maxY do
            local square = cell:getGridSquare(sx, sy, pz)
            if square then
                local objects = square:getObjects()
                local objCount = objects and objects:size() or 0
                for i = 0, objCount - 1 do
                    local obj = objects:get(i)
                    if obj and obj.getContainer and obj:getContainer() then
                        local cCount = obj.getContainerCount and obj:getContainerCount() or 1
                        for ci = 0, cCount - 1 do
                            local cont = (ci == 0) and obj:getContainer() or (obj.getContainerByIndex and obj:getContainerByIndex(ci))
                            if cont and not seen[cont] then
                                seen[cont] = true
                                local cIndex = Registry.containerIndex(obj, cont)
                                if cIndex ~= nil then
                                    local custom = cont.getCustomName and cont:getCustomName()
                                    local name = (custom and custom ~= "") and custom
                                        or (getTextOrNull and getTextOrNull("IGUI_ContainerTitle_" .. cont:getType()) or cont:getType())
                                    local dx = (square:getX() + 0.5) - ax
                                    local dy = (square:getY() + 0.5) - ay
                                    local dist = math.sqrt(dx * dx + dy * dy)
                                    local isCurrent = (obj == currentObject) and (cont == currentContainer or cCount == 1)

                                    list[#list + 1] = {
                                        object = obj,
                                        container = cont,
                                        name = name,
                                        dist = math.floor(dist * 10) / 10,
                                        x = square:getX(),
                                        y = square:getY(),
                                        z = pz,
                                        isCurrent = isCurrent
                                    }
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    table.sort(list, function(a, b)
        if a.isCurrent ~= b.isCurrent then return a.isCurrent end
        return a.dist < b.dist
    end)

    return list
end

return NearbyContainers
