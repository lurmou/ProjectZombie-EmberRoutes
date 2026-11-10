-- Pure, bounded macro survival estimation. No inventory mutation, physical side effects or world handles.
local SupplyEstimate = {
    DAILY_FOOD_PER_PERSON = 0.6,       -- Standard survivor hunger accumulated per 24 hours in PZ (~2 meals)
    DAILY_WATER_PER_PERSON = 2.0,      -- Water portions/drinks consumed per 24 hours
    MAX_PERISHABLE_WINDOW_DAYS = 3.5,  -- Room-temperature fresh crops/meat spoilage window cap
    SATURATION_DAYS = 15.0             -- Stockpile progress gauge 100% saturation target in days
}

local function isWater(fullType, node)
    local n = (node or ""):lower()
    local f = (fullType or ""):lower()
    if n:find("water", 1, true) then return true end
    if f:find("wateringcan", 1, true) or f:find("plantspray", 1, true) then return false end
    if f:find("water", 1, true) or f:find("pop", 1, true) or f:find("beer", 1, true)
        or f:find("canteen", 1, true) or f:find("juice", 1, true) or f:find("milk", 1, true) then
        return true
    end
    return false
end

local function isFood(fullType, node)
    local n = (node or ""):lower()
    local f = (fullType or ""):lower()
    if n:find("^food") or n == "food" then return true end
    if f:find("canned", 1, true) or f:find("bread", 1, true) or f:find("meat", 1, true)
        or f:find("apple", 1, true) or f:find("soup", 1, true) or f:find("stew", 1, true)
        or f:find("vegetable", 1, true) or f:find("crop", 1, true) or f:find("fish", 1, true)
        or f:find("pie", 1, true) or f:find("sandwich", 1, true) or f:find("burger", 1, true) then
        return true
    end
    return false
end

local function isPerishable(fullType, node)
    local n = (node or ""):lower()
    local f = (fullType or ""):lower()
    if n:find("^food%.perishable") then return true end
    if n:find("^food%.meals") or n:find("^food%.stable") then return false end
    if f:find("canned", 1, true) or f:find("chips", 1, true) or f:find("cookie", 1, true)
        or f:find("cracker", 1, true) or f:find("jerky", 1, true) or f:find("candy", 1, true) then
        return false
    end
    if f:find("meat", 1, true) or f:find("fish", 1, true) or f:find("crop", 1, true)
        or f:find("tomato", 1, true) or f:find("potato", 1, true) or f:find("cabbage", 1, true)
        or f:find("carrot", 1, true) or f:find("broccoli", 1, true) then
        return true
    end
    return false
end

local function isMedical(fullType, node)
    local n = (node or ""):lower()
    local f = (fullType or ""):lower()
    if n:find("^medical") then return true end
    if f:find("bandage", 1, true) or f:find("disinfectant", 1, true) or f:find("pills", 1, true)
        or f:find("antibiotic", 1, true) or f:find("painkiller", 1, true) or f:find("suture", 1, true)
        or f:find("splint", 1, true) or f:find("firstaid", 1, true) or f:find("alcohol", 1, true) then
        return true
    end
    return false
end

local function isWood(fullType, node)
    local n = (node or ""):lower()
    local f = (fullType or ""):lower()
    if n:find("^materials") then return true end
    if f:find("wood", 1, true) or f:find("log", 1, true) or f:find("plank", 1, true) then
        return true
    end
    return false
end

local function resolveHunger(fullType, node)
    local manager = getScriptManager and getScriptManager()
    local script = manager and manager.getItem and manager:getItem(fullType)
    if script and script.getHungerChange then
        local hc = script:getHungerChange()
        if type(hc) == "number" and hc ~= 0 then
            local val = math.abs(hc)
            return val > 1 and (val / 100) or val
        end
    end
    local n = (node or ""):lower()
    if n:find("^food%.meals") then return 0.35 end
    if n:find("^food%.stable") then return 0.25 end
    return 0.15
end

function SupplyEstimate.calculate(rows, population)
    local pop = (type(population) == "number" and population > 0) and population or 0
    local effectivePop = (pop > 0) and pop or 1

    local mealsCount = 0
    local cropsCount = 0
    local readyHunger = 0
    local perishableHunger = 0
    local waterCount = 0
    local medicalCount = 0
    local woodCount = 0

    if type(rows) == "table" then
        for _, row in ipairs(rows) do
            local fullType = row.fullType or row.id or ""
            local node = row.node or row.category or ""
            local count = (type(row.count) == "number" and row.count > 0) and row.count or 0

            if count > 0 then
                if isWater(fullType, node) then
                    waterCount = waterCount + count
                elseif isFood(fullType, node) then
                    local h = resolveHunger(fullType, node)
                    if isPerishable(fullType, node) then
                        cropsCount = cropsCount + count
                        perishableHunger = perishableHunger + count * h
                    else
                        mealsCount = mealsCount + count
                        readyHunger = readyHunger + count * h
                    end
                elseif isMedical(fullType, node) then
                    medicalCount = medicalCount + count
                elseif isWood(fullType, node) then
                    woodCount = woodCount + count
                end
            end
        end
    end

    local dailyFoodDemand = effectivePop * SupplyEstimate.DAILY_FOOD_PER_PERSON
    local dailyWaterDemand = effectivePop * SupplyEstimate.DAILY_WATER_PER_PERSON

    local readyDays = readyHunger / dailyFoodDemand
    local rawPerishDays = perishableHunger / dailyFoodDemand
    local perishDays = math.min(SupplyEstimate.MAX_PERISHABLE_WINDOW_DAYS, rawPerishDays)
    local totalFoodDays = readyDays + perishDays

    local waterDays = waterCount / dailyWaterDemand

    local minDays = math.min(totalFoodDays, waterDays)
    local status = "SECURE"
    if pop > 0 then
        if minDays < 2.0 then
            status = "CRITICAL"
        elseif minDays < 5.0 then
            status = "WARNING"
        else
            status = "SECURE"
        end
    else
        status = "SECURE"
    end

    return {
        population = pop,
        hasPopulation = (pop > 0),
        mealsCount = mealsCount,
        cropsCount = cropsCount,
        totalFoodCount = mealsCount + cropsCount,
        foodTotalHunger = readyHunger + perishableHunger,
        foodDays = totalFoodDays,
        foodDailyDemand = dailyFoodDemand,
        waterCount = waterCount,
        waterDays = waterDays,
        waterDailyDemand = dailyWaterDemand,
        medicalCount = medicalCount,
        woodCount = woodCount,
        minDays = minDays,
        status = status
    }
end

return SupplyEstimate
