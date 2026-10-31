-- Smart Spatial Zoning & Heuristic Classifier.
-- Assigns rational container roles based on Physical Sprite + Room Def + Dominant Item Heuristic.
-- Strictly prevents "single chocolate bar turning coffee table into food storage".
local Filter = require "EmberRoutesProbe/StorageFilter"

local SmartZoning = {
    DOMINANT_RATIO_THRESHOLD = 0.70,
    DOMINANT_MIN_ITEMS = 3
}

--- Evaluates the recommended Filter configuration for a physical container object.
---@param object IsoObject|table
---@param container ItemContainer|table
---@return table|nil config, string reason
function SmartZoning.evaluate(object, container)
    if not object or not container then return nil, "INVALID_TARGET" end

    local square = object.getSquare and object:getSquare()
    local cType = container.getType and string.lower(container:getType() or "") or ""
    local sprite = object.getSprite and object:getSprite()
    local spriteName = sprite and sprite.getName and string.lower(sprite:getName() or "") or ""

    -- 1. Hard Physical Appliance Rules (Hardware overrides space)
    if cType == "fridge" or cType == "freezer" or spriteName:find("fridge") or spriteName:find("freezer") then
        local config = Filter.new()
        config.groups["food"] = true
        config.groups["food.meals"] = true
        config.groups["food.perishable"] = true
        config.groups["scrap.compost"] = false
        return config, "PHYSICAL_REFRIGERATION"
    end

    if cType == "medicine" or cType == "firstaid" or spriteName:find("medicine") or spriteName:find("firstaid") then
        local config = Filter.new()
        config.groups["medical"] = true
        config.groups["medical.bandages"] = true
        config.groups["medical.pills"] = true
        return config, "PHYSICAL_MEDICAL"
    end

    if cType == "wardrobe" or cType == "dresser" or spriteName:find("wardrobe") or spriteName:find("dresser") then
        local config = Filter.new()
        config.groups["apparel"] = true
        config.groups["apparel.clothing"] = true
        config.groups["apparel.armor"] = true
        return config, "PHYSICAL_WARDROBE"
    end

    if cType == "bookshelf" or cType == "bookcase" or spriteName:find("book") or spriteName:find("bookshelf") or spriteName:find("bookcase") then
        local config = Filter.new()
        config.groups["literature"] = true
        return config, "PHYSICAL_BOOKSHELF"
    end

    if cType == "gunrack" or spriteName:find("gun") or spriteName:find("weapon") or spriteName:find("armory") then
        local config = Filter.new()
        config.groups["weapons"] = true
        config.groups["weapons.guns"] = true
        config.groups["weapons.ammo"] = true
        return config, "PHYSICAL_ARMORY"
    end

    -- 2. Room Definition Semantics (For neutral containers like counters, crates, metal shelves)
    local room = square and square.getRoom and square:getRoom()
    local roomDef = room and room.getName and room:getName()
    local roomName = string.lower(roomDef or "")

    if roomName:find("kitchen") then
        local config = Filter.new()
        config.groups["food.stable"] = true
        return config, "ROOM_KITCHEN_PANTRY"
    end

    if roomName:find("bathroom") then
        local config = Filter.new()
        config.groups["medical"] = true
        return config, "ROOM_BATHROOM_MEDICAL"
    end

    if roomName:find("garage") or roomName:find("storage") or roomName:find("shed") or roomName:find("workshop") then
        local config = Filter.new()
        config.groups["tools"] = true
        config.groups["materials"] = true
        return config, "ROOM_WORKSHOP"
    end

    if roomName:find("bedroom") then
        local config = Filter.new()
        config.private = true -- Protect bedroom personal lockers from public dump
        return config, "ROOM_BEDROOM_PRIVATE"
    end

    -- 3. Dominant Item Heuristic (For blank crates, cardboard boxes, or unassigned living areas)
    local items = container.getItems and container:getItems()
    local size = items and items:size() or 0
    if size >= SmartZoning.DOMINANT_MIN_ITEMS then
        local counts = {}
        local validCount = 0
        for i = 0, size - 1 do
            local item = items:get(i)
            if item then
                local desc = Filter.describe(item)
                local cat = Filter.classify(desc, item)
                if cat and cat ~= "other" then
                    -- Root category accumulation
                    local root = cat
                    while Filter.nodes[root] and Filter.nodes[root].parent do
                        root = Filter.nodes[root].parent
                    end
                    counts[root] = (counts[root] or 0) + 1
                    validCount = validCount + 1
                end
            end
        end

        if validCount >= SmartZoning.DOMINANT_MIN_ITEMS then
            for rootId, count in pairs(counts) do
                local ratio = count / validCount
                if ratio >= SmartZoning.DOMINANT_RATIO_THRESHOLD then
                    local config = Filter.new()
                    config.groups[rootId] = true
                    return config, "DOMINANT_HEURISTIC:" .. rootId .. " (" .. math.floor(ratio * 100) .. "%)"
                end
            end
        end
    end

    -- 4. Safe Fallback: Unassigned / Idle
    -- A single chocolate bar in a living room coffee table will safely fall through here!
    return nil, "UNASSIGNED_OR_MIXED"
end

return SmartZoning
