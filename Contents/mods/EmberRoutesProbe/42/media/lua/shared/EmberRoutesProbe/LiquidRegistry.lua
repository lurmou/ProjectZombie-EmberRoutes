-- LiquidRegistry: Measures liquid containers and water quality in fixed world furniture.
-- Strictly filters world objects: only fixed furniture (RainCollectorBarrel, Sink/IsoStove, Toilet).
-- Disallows mobile/pickable items (e.g. buckets, bottles, kettles on ground).
-- Accounts for municipal water shut-off (infinite before shut-off, residual liters after).
local LiquidRegistry = {}

LiquidRegistry.ALLOWED_KINDS = {
    RainCollectorBarrel = true,
    Sink = true,
    Toilet = true,
}

local function safeString(val)
    if type(val) == "string" then return string.lower(val) end
    return ""
end

-- Checks if water supply is shut off in sandbox / world
function LiquidRegistry.isWaterShutOff()
    local shutModifier = nil
    if _G.SandboxVars then
        shutModifier = _G.SandboxVars.WaterShutModifier or _G.SandboxVars.ElecShutModifier
    end

    if shutModifier ~= nil and shutModifier >= 0 then
        if _G.getGameTime and _G.getGameTime() then
            local gt = _G.getGameTime()
            local days = gt.getNights and gt:getNights() or (gt.getWorldAgeHours and gt:getWorldAgeHours() / 24) or 0
            if days >= shutModifier then
                return true
            end
        end
    end

    if _G.getGameTime and _G.getGameTime() and _G.getGameTime().isWaterShutOff then
        local ok, shut = pcall(function() return _G.getGameTime():isWaterShutOff() end)
        if ok and shut ~= nil then return shut end
    end

    if _G.getSandboxOptions and _G.getSandboxOptions() then
        local opt = _G.getSandboxOptions():getOptionByName("WaterShutModifier")
        if opt and _G.getGameTime and _G.getGameTime() then
            local val = opt:getValue()
            if val >= 0 and _G.getGameTime():getNights() >= val then
                return true
            end
        end
    end

    return false
end

-- Strictly classifies an object as an allowed fixed world furniture, or nil.
-- Explicitly rejects mobile/pickable items on ground (IsoWorldInventoryObject, WaterBucket, etc.)
function LiquidRegistry.classify(object)
    if not object then return nil end

    -- Direct mock override for testing
    if type(object) == "table" and object.category and LiquidRegistry.ALLOWED_KINDS[object.category] then
        if object.isWorldItem or object.isItem then return nil end
        return object.category
    end

    -- 1. Disallow movable ground items and inventory objects
    local isWorldItem = false
    if _G.instanceof and _G.instanceof(object, "IsoWorldInventoryObject") then
        isWorldItem = true
    end
    if object.isWorldItem == true or (type(object.isWorldItem) == "function" and object:isWorldItem()) then
        isWorldItem = true
    end
    if type(object.getItem) == "function" and object:getItem() ~= nil then
        isWorldItem = true
    end
    if object.isItem == true or (type(object.isItem) == "function" and object:isItem()) then
        isWorldItem = true
    end
    if isWorldItem then return nil end

    -- Check object name
    local name = ""
    if object.getName and type(object.getName) == "function" then
        name = safeString(object:getName())
    end

    -- Check sprite name
    local spriteName = ""
    if object.getSprite and type(object.getSprite) == "function" then
        local sp = object:getSprite()
        if sp and sp.getName then
            spriteName = safeString(sp:getName())
        end
    end

    -- Check object properties
    local props = nil
    if object.getProperties and type(object.getProperties) == "function" then
        props = object:getProperties()
    elseif object.getSprite and type(object.getSprite) == "function" and object:getSprite() then
        local sp = object:getSprite()
        if sp.getProperties then props = sp:getProperties() end
    end

    local customName = ""
    if props and props.get then
        customName = safeString(props:get("CustomName"))
    end

    -- Explicit exclusion for loose buckets, pots, kettles even if named water-related
    if spriteName:find("bucket") or name:find("bucket") or customName:find("bucket") then
        if not (name:find("rain") or spriteName:find("rain") or customName:find("rain")) then
            return nil
        end
    end

    -- 2. RainCollectorBarrel (雨水桶 / 储水桶)
    local isBarrel = false
    if _G.instanceof and _G.instanceof(object, "RainCollectorBarrel") then
        isBarrel = true
    elseif name == "rain collector barrel" or name == "rain barrel" or customName == "rain collector barrel" then
        isBarrel = true
    elseif spriteName:find("rainbarrel") or spriteName:find("water_barrel") then
        isBarrel = true
    elseif object.getModData and type(object.getModData) == "function" then
        local md = object:getModData()
        if md and (md["need:Base.Garbagebag"] ~= nil or md.waterMax ~= nil) then
            isBarrel = true
        end
    end
    if isBarrel then return "RainCollectorBarrel" end

    -- 3. Toilet (马桶)
    local isToilet = false
    if (props and props.has and props:has("IsToilet")) or customName == "toilet" or name == "toilet" then
        isToilet = true
    elseif object.isToilet and type(object.isToilet) == "function" and object:isToilet() then
        isToilet = true
    elseif spriteName:find("toilet") or spriteName:find("fixtures_bathroom_01_0") or spriteName:find("fixtures_bathroom_01_1") then
        isToilet = true
    end
    if isToilet then return "Toilet" end

    -- 4. Sink / IsoStove (水槽 / 洗手台)
    local isSink = false
    if _G.instanceof and _G.instanceof(object, "IsoStove") then
        isSink = true
    elseif object.isSink and type(object.isSink) == "function" and object:isSink() then
        isSink = true
    elseif props and props.has and (props:has("IsSink") or props:has("WaterPiped")) then
        isSink = true
    elseif customName == "sink" or customName == "washbasin" or name == "sink" or name == "washbasin" or name == "sink / tap" then
        isSink = true
    elseif spriteName:find("fixtures_sinks") or (spriteName:find("sink") and not spriteName:find("toilet")) then
        isSink = true
    end
    if isSink then return "Sink" end

    return nil
end

function LiquidRegistry.isAllowedObject(object)
    return LiquidRegistry.classify(object) ~= nil
end

-- Extracts residual water amount from object
function LiquidRegistry.getResidualWater(object)
    if not object then return 0 end
    if type(object) == "table" and object.waterAmount ~= nil then
        return tonumber(object.waterAmount) or 0
    end
    local amount = nil
    if object.getFluidAmount and type(object.getFluidAmount) == "function" then
        local ok, val = pcall(function() return object:getFluidAmount() end)
        if ok and type(val) == "number" then amount = val end
    end
    if (amount == nil or amount <= 0) and object.getWaterAmount and type(object.getWaterAmount) == "function" then
        local ok, val = pcall(function() return object:getWaterAmount() end)
        if ok and type(val) == "number" then amount = val end
    end
    if (amount == nil or amount <= 0) and object.getModData and type(object.getModData) == "function" then
        local md = object:getModData()
        if md and md.waterAmount then
            amount = tonumber(md.waterAmount)
        end
    end
    return math.max(0, amount or 0)
end

-- Measures an allowed fixed world object
function LiquidRegistry.measure(object)
    local kind = LiquidRegistry.classify(object)
    if not kind then return nil end

    local isShut = LiquidRegistry.isWaterShutOff()
    local hasWater = nil
    if object.hasWater and type(object.hasWater) == "function" then
        local ok, val = pcall(function() return object:hasWater() end)
        if ok then hasWater = val end
    elseif type(object) == "table" and object.hasWater ~= nil then
        hasWater = object.hasWater
    end

    local isTainted = false
    if object.isTaintedWater and type(object.isTaintedWater) == "function" then
        local ok, val = pcall(function() return object:isTaintedWater() end)
        if ok then isTainted = (val == true) end
    elseif type(object) == "table" and object.tainted ~= nil then
        isTainted = (object.tainted == true)
    end

    local isInfinite = false
    local amount = 0

    if kind == "Sink" or kind == "Toilet" then
        if not isShut and hasWater ~= false then
            isInfinite = true
            amount = math.huge
            isTainted = false -- Piped municipal water is clean
        else
            amount = LiquidRegistry.getResidualWater(object)
        end
    elseif kind == "RainCollectorBarrel" then
        -- Rain barrel collects rainwater, not municipal piped water; always finite
        amount = LiquidRegistry.getResidualWater(object)
    end

    local displayAmount
    if isInfinite then
        displayAmount = "无限 (∞)"
    else
        displayAmount = string.format("%.1f", amount)
    end

    local displayQuality = isTainted and "污染 (Tainted)" or "纯净 (Clean)"

    local x, y, z = 0, 0, 0
    if object.getSquare and type(object.getSquare) == "function" and object:getSquare() then
        local sq = object:getSquare()
        x, y, z = sq:getX(), sq:getY(), sq:getZ()
    elseif type(object) == "table" then
        x = object.x or 0
        y = object.y or 0
        z = object.z or 0
    end

    return {
        kind = kind,
        object = object,
        isInfinite = isInfinite,
        amount = amount,
        displayAmount = displayAmount,
        isTainted = isTainted,
        displayQuality = displayQuality,
        x = x,
        y = y,
        z = z,
    }
end

-- Scans a single square for fixed furniture liquid sources
function LiquidRegistry.scanSquare(square)
    local results = {}
    if not square then return results end

    local objects = nil
    if square.getObjects and type(square.getObjects) == "function" then
        local objs = square:getObjects()
        if objs and objs.size and objs.get then
            objects = {}
            for i = 0, objs:size() - 1 do
                objects[#objects + 1] = objs:get(i)
            end
        end
    elseif type(square) == "table" and square.objects then
        objects = square.objects
    end

    if not objects then return results end

    for _, obj in ipairs(objects) do
        local entry = LiquidRegistry.measure(obj)
        if entry then
            results[#results + 1] = entry
        end
    end

    return results
end

-- Summarizes an array of measured liquid sources
function LiquidRegistry.summary(sources)
    local hasInfinite = false
    local cleanFinite = 0
    local taintedFinite = 0
    local count = #sources

    for _, s in ipairs(sources) do
        if s.isInfinite then
            hasInfinite = true
        else
            if s.isTainted then
                taintedFinite = taintedFinite + s.amount
            else
                cleanFinite = cleanFinite + s.amount
            end
        end
    end

    return {
        count = count,
        isInfinite = hasInfinite,
        cleanAmount = cleanFinite,
        taintedAmount = taintedFinite,
        totalFinite = cleanFinite + taintedFinite,
        displayClean = hasInfinite and "无限 (∞)" or string.format("%.1f", cleanFinite),
        displayTainted = string.format("%.1f", taintedFinite),
        sources = sources,
    }
end

return LiquidRegistry
