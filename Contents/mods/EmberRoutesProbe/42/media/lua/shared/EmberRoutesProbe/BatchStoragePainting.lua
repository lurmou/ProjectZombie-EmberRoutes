-- Batch Storage Painting Policy.
-- Allows single-click or box-select configuration of multiple blank crates or whole warehouse rows.
local Filter = require "EmberRoutesProbe/StorageFilter"
local SmartZoning = require "EmberRoutesProbe/SmartZoning"

local BatchStoragePainting = {}

--- Scans a world rectangle for loaded containers.
---@param area {x:number, y:number, w:number, h:number}
---@param zLevel number|table|nil
---@return table array of { object=IsoObject, container=ItemContainer, square=IsoGridSquare }
function BatchStoragePainting.scanArea(area, zLevel)
    if not area or not area.x or not area.y or not area.w or not area.h then return {} end
    local cell = getCell and getCell()
    if not cell then return {} end

    local results = {}
    local seen = {}
    local minZ = 0
    local maxZ = 7
    if type(zLevel) == "number" then
        minZ = zLevel
        maxZ = zLevel
    end

    for z = minZ, maxZ do
        for x = area.x, area.x + area.w - 1 do
            for y = area.y, area.y + area.h - 1 do
                local sq = cell:getGridSquare(x, y, z)
                if sq then
                    local objs = sq:getObjects()
                    local objCount = objs and objs:size() or 0
                    for i = 0, objCount - 1 do
                        local obj = objs:get(i)
                        if obj and obj.getContainer and obj:getContainer() then
                            local numContainers = (obj.getContainerCount and obj:getContainerCount()) or 1
                            for cIdx = 0, numContainers - 1 do
                                local container = (obj.getContainerByIndex and obj:getContainerByIndex(cIdx)) or obj:getContainer()
                                if container and not seen[container] then
                                    seen[container] = true
                                    results[#results + 1] = {
                                        object = obj,
                                        container = container,
                                        square = sq
                                    }
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return results
end

--- Scans all areas within a settlement for loaded containers.
---@param settlement table EmberRoutesSettlement
---@return table array of { object=IsoObject, container=ItemContainer, square=IsoGridSquare }
function BatchStoragePainting.scanSettlement(settlement)
    if not settlement or not settlement.areas then return {} end
    local results = {}
    local seen = {}
    for _, area in ipairs(settlement.areas) do
        local list = BatchStoragePainting.scanArea(area)
        for _, entry in ipairs(list) do
            if not seen[entry.container] then
                seen[entry.container] = true
                results[#results + 1] = entry
            end
        end
    end
    return results
end

--- Applies a preset rule or smart-zoning evaluation to a collection of containers.
---@param containerEntries table array of { object=IsoObject, container=ItemContainer, tagFunc=function }
---@param presetId string preset ID (e.g. "materials", "tools", "weapons") or "auto"
---@param actor IsoPlayer|nil optional actor performing the action
---@return table result { updated=number, skipped=number, details=table }
function BatchStoragePainting.apply(containerEntries, presetId, actor)
    if type(containerEntries) ~= "table" then
        return { updated = 0, skipped = 0, error = "INVALID_CONTAINER_LIST" }
    end

    local updated = 0
    local skipped = 0
    local details = {}

    for _, entry in ipairs(containerEntries) do
        local object = entry.object
        local container = entry.container or (object and object.getContainer and object:getContainer())
        local targetConfig = nil
        local reason = nil

        if presetId == "auto" then
            targetConfig, reason = SmartZoning.evaluate(object, container)
        else
            -- Check if valid category or kit
            if Filter.nodes[presetId] then
                targetConfig = Filter.new()
                targetConfig.groups[presetId] = true
                reason = "PRESET:" .. presetId
            else
                reason = "INVALID_PRESET:" .. tostring(presetId)
            end
        end

        if targetConfig then
            if entry.tagFunc then
                entry.tagFunc(object, container, targetConfig)
            else
                local ok, Registry = pcall(require, "EmberRoutesProbe/ContainerRegistry")
                if ok and Registry and Registry.configure then
                    Registry.configure(actor, object, targetConfig, container, "STORAGE", true)
                end
            end
            updated = updated + 1
            details[#details + 1] = { object = object, container = container, status = "UPDATED", reason = reason }
        else
            skipped = skipped + 1
            details[#details + 1] = { object = object, container = container, status = "SKIPPED", reason = reason }
        end
    end

    return {
        updated = updated,
        skipped = skipped,
        details = details
    }
end

return BatchStoragePainting
