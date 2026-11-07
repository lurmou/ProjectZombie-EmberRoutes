package.path = "Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;" .. package.path
local SupplyEstimate = require 'EmberRoutesProbe/Warehouse/SupplyEstimate'

local n = 0
local function check(v, why)
    n = n + 1
    assert(v, why)
end

-- 1. Empty rows with 0 population
local res0 = SupplyEstimate.calculate({}, 0)
check(res0.population == 0, "population is 0")
check(not res0.hasPopulation, "hasPopulation is false")
check(res0.mealsCount == 0 and res0.cropsCount == 0, "counts are 0")
check(res0.foodDays == 0 and res0.waterDays == 0, "days are 0")
check(res0.status == "SECURE", "empty with 0 pop is SECURE")

-- 2. Ready meals with population 2
-- 20 meals under food.meals (default 0.35 hunger each) = 7.0 hunger
-- daily demand = 2 * 0.6 = 1.2 hunger/day
-- expected readyDays = 7.0 / 1.2 = 5.833 days
local rowsMeals = {
    {fullType = "Base.PotOfStew", node = "food.meals", count = 20}
}
local resMeals = SupplyEstimate.calculate(rowsMeals, 2)
check(resMeals.mealsCount == 20, "mealsCount matches")
check(resMeals.cropsCount == 0, "cropsCount is 0")
check(math.abs(resMeals.foodDays - (7.0 / 1.2)) < 0.001, "foodDays matches hunger demand")
check(resMeals.waterDays == 0, "waterDays is 0")
check(resMeals.status == "CRITICAL", "water is 0 so minDays is 0, status is CRITICAL")

-- 3. Food + Water adequate
-- 20 meals (5.83 days) + 30 water (30 / (2 * 2) = 7.5 days)
-- minDays = 5.833 >= 5.0 -> SECURE
local rowsBoth = {
    {fullType = "Base.PotOfStew", node = "food.meals", count = 20},
    {fullType = "Base.WaterBottleFull", node = "water", count = 30},
    {fullType = "Base.Bandage", node = "medical.bandages", count = 5},
    {fullType = "Base.Log", node = "materials", count = 12}
}
local resBoth = SupplyEstimate.calculate(rowsBoth, 2)
check(resBoth.waterCount == 30, "waterCount is 30")
check(resBoth.medicalCount == 5, "medicalCount is 5")
check(resBoth.woodCount == 12, "woodCount is 12")
check(resBoth.waterDays == 7.5, "waterDays is 7.5")
check(resBoth.status == "SECURE", "status is SECURE when minDays >= 5")

-- 4. Status WARNING (2.0 <= minDays < 5.0)
-- 10 water with 2 people = 10 / 4 = 2.5 days -> WARNING
local rowsWarning = {
    {fullType = "Base.PotOfStew", node = "food.meals", count = 20},
    {fullType = "Base.WaterBottleFull", node = "water", count = 10}
}
local resWarn = SupplyEstimate.calculate(rowsWarning, 2)
check(resWarn.waterDays == 2.5, "waterDays is 2.5")
check(resWarn.status == "WARNING", "status is WARNING when minDays is 2.5")

-- 5. Perishable crop capping at MAX_PERISHABLE_WINDOW_DAYS (3.5)
-- 1000 cabbages = huge hunger, but perishable capped at 3.5 days!
local rowsCrops = {
    {fullType = "Base.Cabbage", node = "food.perishable", count = 1000},
    {fullType = "Base.WaterBottleFull", node = "water", count = 50}
}
local resCrops = SupplyEstimate.calculate(rowsCrops, 1)
check(resCrops.cropsCount == 1000, "cropsCount is 1000")
check(resCrops.foodDays == 3.5, "perishable days capped at 3.5 days")

-- 6. Mock getScriptManager returning specific hunger values
_G.getScriptManager = function()
    return {
        getItem = function(_, itemType)
            if itemType == "Custom.SuperSteak" then
                return {
                    getHungerChange = function() return -0.8 end
                }
            end
            return nil
        end
    }
end

local rowsCustom = {
    {fullType = "Custom.SuperSteak", node = "food.meals", count = 5}
}
-- 5 * 0.8 = 4.0 hunger; for 1 person (0.6/day) -> 4.0 / 0.6 = 6.666 days
local resCustom = SupplyEstimate.calculate(rowsCustom, 1)
check(math.abs(resCustom.foodDays - (4.0 / 0.6)) < 0.001, "reads native script hunger correctly")

_G.getScriptManager = nil

print("PASS " .. n .. " SupplyEstimate checks cleanly executed.")
