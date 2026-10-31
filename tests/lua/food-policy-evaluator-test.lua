-- Comprehensive Unit Test for FoodPolicyEvaluator and Cooking Directives
package.path = "Contents/mods/EmberRoutesProbe/42/media/lua/client/?.lua;Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;" .. package.path

local checks = 0
local function check(cond, msg)
    assert(cond, msg or "Assertion failed")
    checks = checks + 1
end

local Evaluator = require 'EmberRoutesProbe/FoodPolicyEvaluator'
local PolicyDef = require 'EmberRoutesProbe/CookingPolicyDef'

print("=== Running Food Policy & Evaluator Unit Tests ===")

-- Mock InventoryItem / Food
local function makeMockFood(props)
    local item = {
        foodType = props.foodType or "Vegetables",
        fullType = props.fullType or "Base.Carrots",
        rotten = props.rotten == true,
        spice = props.spice == true,
    }
    function item:getFoodType() return self.foodType end
    function item:getFullType() return self.fullType end
    function item:isRotten() return self.rotten end
    function item:isSpice() return self.spice end
    return item
end

-- 1. Test Category Mapping
check(Evaluator.getCategory(makeMockFood({ foodType = "Meat" })) == "Meat", "Meat foodType should map to Meat")
check(Evaluator.getCategory(makeMockFood({ foodType = "Fish" })) == "Meat", "Fish should map to Meat")
check(Evaluator.getCategory(makeMockFood({ foodType = "Vegetables" })) == "Vegetables", "Vegetables should map to Vegetables")
check(Evaluator.getCategory(makeMockFood({ foodType = "Fruits" })) == "Fruits", "Fruits should map to Fruits")
check(Evaluator.getCategory(makeMockFood({ fullType = "Base.TinnedSoup" })) == "Canned", "Tinned item should map to Canned")
check(Evaluator.getCategory(makeMockFood({ fullType = "Base.Butter" })) == "Dairy", "Butter should map to Dairy")
check(Evaluator.getCategory(makeMockFood({ spice = true })) == "Spices", "Spice item should map to Spices")
print("PASS: Food category O(1) heuristic mapping verified.")

-- 2. Test Policy Rejection & Whitelist
local defaultPolicy = PolicyDef.getDefaults()
-- By default: Canned is false, Meat is true, Vegetables is true, allowRotten is false

-- Carrots (Vegetables) -> ALLOW
local carrot = makeMockFood({ foodType = "Vegetables", fullType = "Base.Carrots" })
local okCarrot, reasonCarrot = Evaluator.allows(defaultPolicy, carrot)
check(okCarrot == true, "Carrots should be allowed under default policy")

-- Canned Soup -> DENY (default canned is false to save for winter/emergencies)
local cannedSoup = makeMockFood({ fullType = "Base.CannedSoup" })
local okCanned, reasonCanned = Evaluator.allows(defaultPolicy, cannedSoup)
check(okCanned == false, "Canned soup should be blocked when Canned category is false")
check(reasonCanned == "FOOD_POLICY_CATEGORY_DISALLOWED", "Expected category disallowed error")

-- Rotten Meat -> DENY (allowRotten is false)
local rottenMeat = makeMockFood({ foodType = "Meat", rotten = true })
local okRotten, reasonRotten = Evaluator.allows(defaultPolicy, rottenMeat)
check(okRotten == false, "Rotten meat must be rejected by default")
check(reasonRotten == "FOOD_POLICY_ROTTEN_DISALLOWED", "Expected rotten disallowed error")

-- 3. Test Policy Mutation / Toggle
local emergencyPolicy = {
    allowedFoodCategories = {
        Canned = true,
        Meat = false, -- e.g. strict vegetarian directive
    },
    allowRotten = true, -- famine emergency
}

-- Now Canned Soup is ALLOWED
check(Evaluator.allows(emergencyPolicy, cannedSoup) == true, "Canned soup should be allowed under emergency policy")

-- Meat is now DISALLOWED
local freshSteak = makeMockFood({ foodType = "Meat", fullType = "Base.Steak" })
local okSteak, reasonSteak = Evaluator.allows(emergencyPolicy, freshSteak)
check(okSteak == false, "Meat should be rejected when policy forbids Meat")
check(reasonSteak == "FOOD_POLICY_CATEGORY_DISALLOWED", "Expected category disallowed error")

-- Rotten is now ALLOWED in famine (if category is permitted)
local rottenCarrot = makeMockFood({ foodType = "Vegetables", rotten = true })
check(Evaluator.allows(emergencyPolicy, rottenCarrot) == true, "Rotten vegetables should be permitted when allowRotten is true")

print(string.format("=== ALL %d FOOD POLICY CHECKS PASSED ===", checks))
