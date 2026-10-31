--[[
    FoodPolicyEvaluator.lua - EmberRoutes
    Zero-GC, O(1) Food Evaluation Engine against Settlement Cooking Directives.
    Used by CookingSupply and CookingDuty in hot item scanning loops.
--]]

local Evaluator = {}

---Map Vanilla FoodType string to EmberRoutes Policy Food Categories.
local FOOD_TYPE_MAP = {
    -- Meat / Fish / Poultry
    ["Meat"] = "Meat",
    ["Fish"] = "Meat",
    ["Egg"] = "Meat",
    ["Poultry"] = "Meat",
    ["SmallAnimal"] = "Meat",
    -- Vegetables
    ["Vegetables"] = "Vegetables",
    ["Vegetable"] = "Vegetables",
    -- Fruits / Berries / Mushrooms
    ["Fruits"] = "Fruits",
    ["Fruit"] = "Fruits",
    ["Berries"] = "Fruits",
    ["Mushrooms"] = "Vegetables",
    -- Dairy / Butter / Milk
    ["Dairy"] = "Dairy",
    ["Milk"] = "Dairy",
    -- Spices / Condiments
    ["Spice"] = "Spices",
    ["Condiment"] = "Spices",
    -- Canned
    ["CannedFood"] = "Canned",
}

---Fast determination of food category.
---@param item InventoryItem
---@return string
function Evaluator.getCategory(item)
    if not item then return "Other" end

    -- 1. Check if spice
    if item.isSpice and item:isSpice() then
        return "Spices"
    end

    -- 2. Check fullType heuristics for high-value/canned goods (takes precedence over generic vegetables/meat)
    local fullType = item.getFullType and item:getFullType() or ""
    if fullType:find("Canned") or fullType:find("Tinned") or fullType:find("Tin") then
        return "Canned"
    end
    if fullType:find("Butter") or fullType:find("Cheese") or fullType:find("Milk") then
        return "Dairy"
    end

    -- 3. Check generic foodType field on Food items
    if item.getFoodType then
        local ft = item:getFoodType()
        if ft and FOOD_TYPE_MAP[ft] then
            return FOOD_TYPE_MAP[ft]
        end
    end

    return "Other"
end

---Evaluate whether an inventory food item satisfies the settlement's cooking directives.
---@param policy table Settlement cooking policy from JobPolicyService
---@param item InventoryItem
---@return boolean, string?
function Evaluator.allows(policy, item)
    if not policy or not item then return true end

    -- 1. Rotting check
    if item.isRotten and item:isRotten() then
        if policy.allowRotten ~= true then
            return false, "FOOD_POLICY_ROTTEN_DISALLOWED"
        end
    end

    -- 2. Category Whitelist / Blacklist check
    local allowedCats = policy.allowedFoodCategories
    if allowedCats then
        local cat = Evaluator.getCategory(item)
        if allowedCats[cat] == false then
            return false, "FOOD_POLICY_CATEGORY_DISALLOWED"
        end
    end

    return true
end

return Evaluator
