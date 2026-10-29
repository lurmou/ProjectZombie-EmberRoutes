-- Batch Storage Painting Policy.
-- Allows single-click or box-select configuration of multiple blank crates or whole warehouse rows.
local Filter = require "EmberRoutesProbe/StorageFilter"
local SmartZoning = require "EmberRoutesProbe/SmartZoning"

local BatchStoragePainting = {}

--- Applies a preset rule or smart-zoning evaluation to a collection of containers.
---@param containerEntries table array of { object=IsoObject, container=ItemContainer, tagFunc=function }
---@param presetId string preset ID (e.g. "materials", "tools", "weapons") or "auto"
---@return table result { updated=number, skipped=number, details=table }
function BatchStoragePainting.apply(containerEntries, presetId)
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
