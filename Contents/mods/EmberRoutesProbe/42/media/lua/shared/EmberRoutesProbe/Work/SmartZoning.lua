-- Smart Spatial Zoning & Contextual Classifier.
-- Assigns rational container roles based on Hardware Type + Room Def + Noise-Filtered Core Assets.
-- Strictly prevents "pens turning desks into armories" and "mixed junk failing classification".
local Filter = require "EmberRoutesProbe/Warehouse/StorageFilter"

local SmartZoning = {}

-- Improvised / False Weapon blacklist: Items with Category=="Weapon" in PZ scripts that are actually stationery, eating utensils or tools
local FAKE_WEAPONS = {
    ["base.pen"] = true,
    ["base.pencil"] = true,
    ["base.redpen"] = true,
    ["base.bluepen"] = true,
    ["base.greenpen"] = true,
    ["base.fork"] = true,
    ["base.spoon"] = true,
    ["base.butterknife"] = true,
    ["base.letteropener"] = true,
    ["base.scissors"] = true,
    ["base.scalpel"] = true,
    ["base.rollingpin"] = true
}

local function isFakeWeapon(fullType)
    local f = string.lower(fullType or "")
    return FAKE_WEAPONS[f] or false
end

--- Evaluates the recommended Filter configuration for a physical container object.
---@param object IsoObject|table
---@param container ItemContainer|table
---@return table config, string reason
function SmartZoning.evaluate(object, container)
    if not object or not container then return nil, "INVALID_TARGET" end

    local square = object.getSquare and object:getSquare()
    local cType = container.getType and string.lower(container:getType() or "") or ""
    local sprite = object.getSprite and object:getSprite()
    local spriteName = sprite and sprite.getName and string.lower(sprite:getName() or "") or ""

    -- 1. Hardware Absolute Fixtures (Physical container type dictates primary function)
    if cType == "fridge" or cType == "freezer" or spriteName:find("fridge") or spriteName:find("freezer") then
        local config = Filter.new()
        config.groups["food"] = true
        config.groups["food.meals"] = true
        config.groups["food.perishable"] = true
        config.groups["scrap.compost"] = false
        config.priority = 4
        return config, "PHYSICAL_REFRIGERATION"
    end

    if cType == "medicine" or cType == "firstaid" or spriteName:find("medicine") or spriteName:find("firstaid") then
        local config = Filter.new()
        config.groups["medical"] = true
        config.groups["medical.bandages"] = true
        config.groups["medical.pills"] = true
        config.priority = 4
        return config, "PHYSICAL_MEDICAL"
    end

    if cType == "wardrobe" or cType == "dresser" or spriteName:find("wardrobe") or spriteName:find("dresser") then
        local config = Filter.new()
        config.groups["apparel"] = true
        config.groups["apparel.clothing"] = true
        config.groups["apparel.armor"] = true
        config.priority = 3
        return config, "PHYSICAL_WARDROBE"
    end

    if cType == "bookshelf" or cType == "bookcase" or spriteName:find("book") or spriteName:find("bookshelf") or spriteName:find("bookcase") then
        local config = Filter.new()
        config.groups["literature"] = true
        config.priority = 3
        return config, "PHYSICAL_BOOKSHELF"
    end

    if cType == "gunrack" or spriteName:find("gun") or spriteName:find("armory") or (spriteName:find("weapon") and not spriteName:find("tool")) then
        local config = Filter.new()
        config.groups["weapons"] = true
        config.groups["weapons.guns"] = true
        config.groups["weapons.ammo"] = true
        config.priority = 5
        return config, "PHYSICAL_ARMORY"
    end

    if cType == "bin" or cType == "garbage" or spriteName:find("trash") or spriteName:find("garbage") or spriteName:find("bin") then
        local config = Filter.new()
        config.groups["scrap"] = true
        config.groups["scrap.waste"] = true
        config.groups["scrap.compost"] = true
        config.priority = 1
        return config, "PHYSICAL_GARBAGE"
    end

    -- 2. Scan and classify items with Noise Filtering & Utility Weighting
    local room = square and square.getRoom and square:getRoom()
    local roomDef = room and room.getName and room:getName()
    local roomName = string.lower(roomDef or "")

    local items = container.getItems and container:getItems()
    local size = items and items:size() or 0
    local scores = { food = 0, medical = 0, weapons = 0, tools = 0, materials = 0, literature = 0, apparel = 0 }
    local totalCoreItems = 0

    if size > 0 then
        for i = 0, size - 1 do
            local item = items:get(i)
            if item then
                local fullType = item.getFullType and item:getFullType() or ""
                local desc = Filter.describe(item)
                local cat = Filter.classify(desc, item)

                if isFakeWeapon(fullType) then
                    -- Improvised stationery/cutlery: treat as literature/stationery or kitchen tool, never weapon
                    scores.literature = scores.literature + 0.5
                elseif cat and cat ~= "other" then
                    local root = cat
                    while Filter.nodes[root] and Filter.nodes[root].parent do
                        root = Filter.nodes[root].parent
                    end
                    if scores[root] ~= nil then
                        scores[root] = scores[root] + 1
                        totalCoreItems = totalCoreItems + 1
                    end
                end
            end
        end
    end

    -- 3. Room & Morphology Contextual Biasing
    local isKitchen = roomName:find("kitchen") or spriteName:find("kitchen")
        or (cType:find("counter") and roomName:find("kitchen"))
    local isWorkshop = roomName:find("garage") or roomName:find("shed") or roomName:find("workshop") or roomName:find("storage")
        or spriteName:find("tool") or spriteName:find("metal") or spriteName:find("industrial") or spriteName:find("shelving")
    local isBathroom = roomName:find("bathroom") or roomName:find("clinic")
    local isBedroom = roomName:find("bedroom")

    -- 4. Template Snapping based on composite scores and context
    -- Case A: Strong Real Weapon Presence (Firearms, ammo, blades)
    local isArmoryDominant = (scores.weapons >= 2) or (scores.weapons >= 1 and scores.weapons >= (totalCoreItems - scores.weapons) and not isKitchen and not isWorkshop)
    if isArmoryDominant then
        local config = Filter.new()
        config.groups["weapons"] = true
        config.groups["weapons.guns"] = true
        config.groups["weapons.ammo"] = true
        config.priority = 4
        return config, "DOMINANT_ARMORY"
    end

    -- Case B: Medical (First aid, pharmaceuticals)
    local isMedicalDominant = (scores.medical >= 2) or (scores.medical >= 1 and (isBathroom or scores.medical >= (totalCoreItems - scores.medical)))
    if isMedicalDominant then
        local config = Filter.new()
        config.groups["medical"] = true
        config.groups["medical.bandages"] = true
        config.groups["medical.pills"] = true
        config.priority = 4
        return config, "DOMINANT_MEDICAL"
    end

    -- Case C: Kitchen Composite (Food + Cooking Tools, or Kitchen furniture with food/tools)
    if isKitchen or scores.food >= 2 or (scores.food >= 1 and scores.tools >= 1) then
        local config = Filter.new()
        config.groups["food"] = true
        config.groups["food.stable"] = true
        config.groups["food.meals"] = true
        config.groups["tools"] = true -- Kitchen utensils, can openers, knives
        config.priority = 3
        return config, "COMPOSITE_KITCHEN"
    end

    -- Case D: Workshop / Hardware (Tools + Building Materials)
    if isWorkshop or (scores.tools + scores.materials) >= 2 or (scores.tools >= 1 and isWorkshop) then
        local config = Filter.new()
        config.groups["tools"] = true
        config.groups["materials"] = true
        config.groups["materials.electronics"] = true
        config.priority = 3
        return config, "COMPOSITE_WORKSHOP"
    end

    -- Case E: Literature & Media (Books, magazines, manuals)
    if scores.literature >= 2 or (scores.literature >= 1 and size <= 4) then
        local config = Filter.new()
        config.groups["literature"] = true
        config.priority = 3
        return config, "DOMINANT_LITERATURE"
    end

    -- Case F: Apparel (Clothing, bags, armor)
    if scores.apparel >= 2 or (scores.apparel >= 1 and isBedroom) then
        local config = Filter.new()
        config.groups["apparel"] = true
        config.priority = 3
        return config, "DOMINANT_APPAREL"
    end

    -- 5. Safe Living Fallback: Neutral General Storage (Never fails, never throws UNASSIGNED_OR_MIXED!)
    if isBedroom then
        local config = Filter.new()
        config.groups["apparel"] = true
        config.groups["literature"] = true
        config.priority = 2
        return config, "ROOM_BEDROOM_STORAGE"
    end

    if isBathroom then
        local config = Filter.new()
        config.groups["medical"] = true
        config.priority = 3
        return config, "ROOM_BATHROOM_MEDICAL"
    end

    -- General Living / Neutral Crates / Desks: Accept general life items at Low/Backup Priority
    local config = Filter.new()
    config.groups["literature"] = true
    config.groups["trade"] = true
    config.groups["tools"] = true
    config.groups["materials"] = true
    config.priority = 1
    return config, "GENERAL_STORAGE"
end

return SmartZoning
