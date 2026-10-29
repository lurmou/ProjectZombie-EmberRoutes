-- Custom Themed Kits Manager.
-- Allows players to snapshot container contents or item sets as high-priority custom categories.
local Filter = require "EmberRoutesProbe/StorageFilter"

local CustomKits = {
    LIMIT = 64,
    registry = {}
}

function CustomKits.data()
    local data
    local bridge = EmberRoutesProbeJava
    if bridge and bridge.cachedModData then
        local ok, cached = pcall(bridge.cachedModData, "EmberRoutes/CustomKits/v1")
        if ok then data = cached end
    end
    if not data and ModData and ModData.getOrCreate then
        data = ModData.getOrCreate("EmberRoutes/CustomKits/v1")
    end
    if not data then data = CustomKits._fallbackData or { format = 1, kits = {} } CustomKits._fallbackData = data end
    if data.format ~= 1 then data.format = 1 data.kits = data.kits or {} end
    return data
end

local function cleanId(str)
    return str:gsub("[^%w_.]", "_")
end

function CustomKits.registerKit(kitId, name, typesMap)
    assert(type(kitId) == "string" and #kitId <= 80, "KIT_ID_INVALID")
    assert(type(name) == "string" and #name > 0 and #name <= 64, "KIT_NAME_INVALID")
    assert(type(typesMap) == "table", "KIT_TYPES_INVALID")

    -- Register into StorageFilter if not already registered
    if not Filter.nodes[kitId] then
        Filter.registerCategory(kitId, "kits", {0.35, 0.85, 0.75})
    end

    -- Register classifier hook
    local classifierId = "classifier:" .. kitId
    pcall(Filter.registerClassifier, classifierId, function(desc, item)
        if typesMap[desc.fullType] then
            return kitId
        end
    end)

    CustomKits.registry[kitId] = {
        id = kitId,
        name = name,
        types = typesMap
    }
end

function CustomKits.create(name, typesArray)
    if type(name) ~= "string" or #name == 0 or #name > 64 or name:find("[%c]") then
        return nil, "KIT_NAME_INVALID"
    end
    if type(typesArray) ~= "table" or #typesArray == 0 then
        return nil, "KIT_TYPES_EMPTY"
    end

    local d = CustomKits.data()
    local count = 0
    for _ in pairs(d.kits) do count = count + 1 end
    if count >= CustomKits.LIMIT then
        return nil, "KIT_LIMIT_EXCEEDED"
    end

    local timestamp = getTimestampMs and getTimestampMs() or os.time()
    local kitId = "kit.custom." .. cleanId(name) .. "_" .. tostring(timestamp % 1000000)

    local typesMap = {}
    for _, fullType in ipairs(typesArray) do
        if type(fullType) == "string" and #fullType > 0 then
            typesMap[fullType] = true
        end
    end

    if not next(typesMap) then
        return nil, "KIT_TYPES_EMPTY"
    end

    d.kits[kitId] = {
        id = kitId,
        name = name,
        types = typesMap
    }

    CustomKits.registerKit(kitId, name, typesMap)
    return kitId, "KIT_CREATED"
end

function CustomKits.createFromContainer(name, container)
    if not container or not container.getItems then
        return nil, "INVALID_CONTAINER"
    end
    local items = container:getItems()
    local size = items and items:size() or 0
    if size == 0 then
        return nil, "CONTAINER_EMPTY"
    end

    local seen = {}
    local typesArray = {}
    for i = 0, size - 1 do
        local item = items:get(i)
        if item and item.getFullType then
            local fullType = item:getFullType()
            if not seen[fullType] then
                seen[fullType] = true
                typesArray[#typesArray + 1] = fullType
            end
        end
    end

    return CustomKits.create(name, typesArray)
end

function CustomKits.loadAll()
    local d = CustomKits.data()
    if not d or not d.kits then return end
    for kitId, kitData in pairs(d.kits) do
        if type(kitData) == "table" and kitData.id and kitData.name and kitData.types then
            pcall(CustomKits.registerKit, kitData.id, kitData.name, kitData.types)
        end
    end
end

if Events and Events.OnGameStart then
    Events.OnGameStart.Add(CustomKits.loadAll)
end

return CustomKits
