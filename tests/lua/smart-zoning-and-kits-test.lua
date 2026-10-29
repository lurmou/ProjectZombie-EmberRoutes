package.path="Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;"..package.path
local Filter = require "EmberRoutesProbe/StorageFilter"
local SmartZoning = require "EmberRoutesProbe/SmartZoning"
local CustomKits = require "EmberRoutesProbe/CustomKits"

local count = 0
local function check(val, msg)
    count = count + 1
    assert(val, msg)
end

local function fakeItem(fullType, cat, display)
    local item = {}
    function item:getFullType() return fullType end
    function item:getCategory() return cat or "Item" end
    function item:getDisplayCategory() return display or "" end
    function item:isFood() return display == "Food" end
    function item:isRotten() return false end
    function item:isCooked() return false end
    function item:isRanged() return false end
    function item:IsClothing() return false end
    function item:isClothing() return false end
    function item:IsContainer() return false end
    function item:isContainer() return false end
    return item
end

local function fakeContainer(cType, itemList)
    local list = itemList or {}
    local c = {}
    function c:getType() return cType or "crate" end
    function c:getItems()
        return {
            size = function() return #list end,
            get = function(_, idx) return list[idx + 1] end
        }
    end
    return c
end

local function fakeObject(square, cType, spriteName, itemList)
    local container = fakeContainer(cType, itemList)
    local obj = {}
    function obj:getSquare() return square end
    function obj:getContainer() return container end
    function obj:getSprite()
        return {
            getName = function() return spriteName or "" end
        }
    end
    return obj, container
end

local function fakeSquare(roomName)
    local sq = {}
    function sq:getRoom()
        if not roomName then return nil end
        return {
            getName = function() return roomName end
        }
    end
    return sq
end

-- 1. Physical Furniture Hard Rules
local objFridge, cFridge = fakeObject(fakeSquare("livingroom"), "fridge", "appliances_refrigeration_01", { fakeItem("Base.Pistol", "Weapon") })
local cfgFridge, whyFridge = SmartZoning.evaluate(objFridge, cFridge)
check(cfgFridge and cfgFridge.groups["food.perishable"] and cfgFridge.groups["scrap.compost"] == false, "fridge gets refrigeration rules even in livingroom")
check(whyFridge == "PHYSICAL_REFRIGERATION", "fridge reasons as physical refrigeration")

local objMed, cMed = fakeObject(fakeSquare("bedroom"), "medicine", "fixtures_bathroom_01", { fakeItem("Base.Chocolate", "Food", "Food") })
local cfgMed, whyMed = SmartZoning.evaluate(objMed, cMed)
check(cfgMed and cfgMed.groups["medical"], "medicine cabinet gets medical rules even with chocolate")

-- 2. Room Definition Semantics (Neutral Counters)
local objKitchenCounter, cKitchenCounter = fakeObject(fakeSquare("kitchen"), "counter", "furniture_shelving_01", {})
local cfgKitchen, whyKitchen = SmartZoning.evaluate(objKitchenCounter, cKitchenCounter)
check(cfgKitchen and cfgKitchen.groups["food.stable"], "kitchen counter gets food.stable pantry rules")

local objGarageCounter, cGarageCounter = fakeObject(fakeSquare("garage"), "counter", "furniture_shelving_01", {})
local cfgGarage, whyGarage = SmartZoning.evaluate(objGarageCounter, cGarageCounter)
check(cfgGarage and cfgGarage.groups["tools"] and cfgGarage.groups["materials"], "garage counter gets workshop rules")

local objBedroomStand, cBedroomStand = fakeObject(fakeSquare("bedroom"), "counter", "furniture_tables_high_01", {})
local cfgBed, whyBed = SmartZoning.evaluate(objBedroomStand, cBedroomStand)
check(cfgBed and cfgBed.private == true, "bedroom nightstand marked as private personal storage")

-- 3. THE CHOCOLATE BAR TEST (Crucial Anti-False-Positive Test)
-- A coffee table in livingroom with 1 chocolate bar must NEVER be turned into food storage!
local objCoffeeTable, cCoffeeTable = fakeObject(fakeSquare("livingroom"), "table", "furniture_tables_low_01", {
    fakeItem("Base.Chocolate", "Food", "Food")
})
local cfgCoffee, whyCoffee = SmartZoning.evaluate(objCoffeeTable, cCoffeeTable)
check(cfgCoffee == nil, "single chocolate bar in livingroom coffee table is rejected (unassigned)")
check(whyCoffee == "UNASSIGNED_OR_MIXED", "unassigned or mixed reason reported")

-- 4. Dominant Item Heuristic (For blank wooden crates in warehouse)
local plankList = {
    fakeItem("Base.Plank", "Material", "Material"),
    fakeItem("Base.Plank", "Material", "Material"),
    fakeItem("Base.Plank", "Material", "Material"),
    fakeItem("Base.Plank", "Material", "Material"),
    fakeItem("Base.Plank", "Material", "Material"),
    fakeItem("Base.Chocolate", "Food", "Food") -- 1 stray chocolate
}
local objCrate, cCrate = fakeObject(fakeSquare("warehouse"), "crate", "carpentry_01_16", plankList)
local cfgCrate, whyCrate = SmartZoning.evaluate(objCrate, cCrate)
check(cfgCrate and cfgCrate.groups["materials"] == true, "dominant 83% planks turns crate into materials storage")
check(whyCrate:find("DOMINANT_HEURISTIC:materials"), "dominant heuristic reported")

-- Mixed crate with no dominant category (>70%)
local mixedList = {
    fakeItem("Base.Plank", "Material", "Material"),
    fakeItem("Base.Apple", "Food", "Food"),
    fakeItem("Base.Pistol", "Weapon", "Weapon")
}
local objMixed, cMixed = fakeObject(fakeSquare("warehouse"), "crate", "carpentry_01_16", mixedList)
local cfgMixed, whyMixed = SmartZoning.evaluate(objMixed, cMixed)
check(cfgMixed == nil, "mixed crate with 33%/33%/33% is not assigned (stays idle)")

-- 5. Custom Kits Management
local kitContainer = fakeContainer("crate", {
    fakeItem("MyMod.SuperRadar", "Item", "Tool"),
    fakeItem("MyMod.RadarBattery", "Item", "Electronic"),
    fakeItem("MyMod.AntennaWire", "Item", "Material")
})
local kitId, msg = CustomKits.createFromContainer("雷达勘探组", kitContainer)
check(kitId and kitId:find("kit.custom"), "custom kit created with kit.custom ID")
check(CustomKits.registry[kitId] ~= nil, "custom kit registered into CustomKits registry")
check(Filter.nodes[kitId] ~= nil, "custom kit registered into StorageFilter tree")

-- Verify classification & matching
local radarItem = fakeItem("MyMod.SuperRadar", "Item", "Tool")
check(Filter.classify(Filter.describe(radarItem), radarItem) == kitId, "custom radar item classified to newly created kit")

local customBox = Filter.new()
customBox.groups[kitId] = true
check(Filter.matches(customBox, radarItem), "box with custom kit accepts its exact components")

print("PASS " .. count .. " smart zoning, dominant heuristic, and custom kits assertions succeeded.")
