package.path = "Contents/mods/EmberRoutesProbe/42/media/lua/client/?.lua;Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;" .. package.path
local SmartZoning = require "EmberRoutesProbe/Work/SmartZoning"
local Filter = require "EmberRoutesProbe/Warehouse/StorageFilter"

local count = 0
local passed = 0
local function check(value, message)
    count = count + 1
    if value then
        passed = passed + 1
    else
        error("ASSERTION FAILED: " .. tostring(message))
    end
end

-- Mock Factory for items
local function createItem(fullType, category, displayCategory, isFood, isRanged)
    local item = {
        _fullType = fullType,
        _category = category or "Normal",
        _display = displayCategory or "Item",
        _isFood = isFood or false,
        _isRanged = isRanged or false
    }
    function item:getFullType() return self._fullType end
    function item:getCategory() return self._category end
    function item:getDisplayCategory() return self._display end
    function item:isFood() return self._isFood end
    function item:isRanged() return self._isRanged end
    function item:getAge() return 0 end
    function item:getOffAgeMax() return 100 end
    function item:isRotten() return false end
    function item:isCooked() return false end
    return item
end

-- Mock Factory for containers
local function createContainer(cType, spriteName, roomName, itemsList)
    local container = {
        _type = cType or "crate",
        _items = itemsList or {}
    }
    function container:getType() return self._type end
    function container:getItems()
        local list = {
            _raw = container._items
        }
        function list:size() return #self._raw end
        function list:get(i) return self._raw[i + 1] end
        return list
    end

    local square = {
        _roomName = roomName
    }
    function square:getRoom()
        if not self._roomName then return nil end
        return {
            getName = function() return square._roomName end
        }
    end

    local object = {
        _spriteName = spriteName or "",
        _square = square,
        _container = container
    }
    function object:getSprite()
        return {
            getName = function() return object._spriteName end
        }
    end
    function object:getSquare() return self._square end
    function object:getContainer() return self._container end

    return object, container
end

print("==================================================")
print("RUNNING SMART ZONING REALISTIC DATA SIMULATIONS...")
print("==================================================")

-- Scenario 1: Kitchen Refrigerator (Hardware Rule)
do
    local obj, cont = createContainer("fridge", "appliances_refrigeration_01_0", "kitchen", {
        createItem("Base.Steak", "Food", "Food", true),
        createItem("Base.Milk", "Food", "Food", true),
        createItem("Base.AppleRotten", "Food", "Food", true)
    })
    local cfg, reason = SmartZoning.evaluate(obj, cont)
    check(cfg ~= nil, "Refrigerator resolves successfully")
    check(reason == "PHYSICAL_REFRIGERATION", "Identified as PHYSICAL_REFRIGERATION")
    check(cfg.groups["food"] == true and cfg.groups["food.perishable"] == true, "Food perishable enabled")
    check(cfg.priority == 4, "Refrigerator has High Priority 4")
end

-- Scenario 2: Bathroom Medicine Cabinet (Hardware Rule)
do
    local obj, cont = createContainer("medicine", "furniture_storage_02_16", "bathroom", {
        createItem("Base.Bandage", "FirstAid", "Medical"),
        createItem("Base.Pills", "FirstAid", "Medical")
    })
    local cfg, reason = SmartZoning.evaluate(obj, cont)
    check(cfg ~= nil, "Medicine cabinet resolves")
    check(reason == "PHYSICAL_MEDICAL", "Identified as PHYSICAL_MEDICAL")
    check(cfg.groups["medical"] == true and cfg.groups["medical.bandages"] == true, "Medical enabled")
    check(cfg.priority == 4, "Medical cabinet has High Priority 4")
end

-- Scenario 3: Armory Gun Rack / Police Locker (Hardware Rule)
do
    local obj, cont = createContainer("gunrack", "furniture_shelving_01_20", "armory", {
        createItem("Base.Shotgun", "Weapon", "Weapon", false, true),
        createItem("Base.ShotgunShells", "Ammo", "Ammo")
    })
    local cfg, reason = SmartZoning.evaluate(obj, cont)
    check(cfg ~= nil, "Gun rack resolves")
    check(reason == "PHYSICAL_ARMORY", "Identified as PHYSICAL_ARMORY")
    check(cfg.groups["weapons"] == true and cfg.groups["weapons.guns"] == true, "Weapons & Ammo enabled")
    check(cfg.priority == 5, "Armory has Critical Priority 5")
end

-- Scenario 4: Bookshelf in Living Room (Hardware Rule)
do
    local obj, cont = createContainer("bookshelf", "furniture_shelving_01_0", "livingroom", {
        createItem("Base.BookCarpentry1", "Literature", "Literature"),
        createItem("Base.Magazine", "Literature", "Literature")
    })
    local cfg, reason = SmartZoning.evaluate(obj, cont)
    check(cfg ~= nil, "Bookshelf resolves")
    check(reason == "PHYSICAL_BOOKSHELF", "Identified as PHYSICAL_BOOKSHELF")
    check(cfg.groups["literature"] == true, "Literature enabled")
    check(cfg.priority == 3, "Bookshelf has Priority 3")
end

-- Scenario 5: Kitchen Counter with Food + Kitchen Tools + A PEN (PZ Fake Weapon Noise Test)
do
    local obj, cont = createContainer("counter", "kitchen_counters_01_0", "kitchen", {
        createItem("Base.CannedBolognese", "Food", "Food", true),
        createItem("Base.TinOpener", "Item", "Tool"),
        createItem("Base.KitchenKnife", "Weapon", "Tool"),
        createItem("Base.Pen", "Weapon", "Weapon") -- PEN in PZ is Category=="Weapon"!
    })
    local cfg, reason = SmartZoning.evaluate(obj, cont)
    check(cfg ~= nil, "Kitchen counter with mixed tools & pen resolves")
    check(reason == "COMPOSITE_KITCHEN", "Identified as COMPOSITE_KITCHEN")
    check(cfg.groups["food"] == true, "Food enabled")
    check(cfg.groups["tools"] == true, "Cooking tools enabled")
    check(cfg.groups["weapons"] == nil, "Pen did NOT falsely trigger weapons category!")
    check(cfg.priority == 3, "Kitchen counter has Priority 3")
end

-- Scenario 6: Workshop Metal Shelves with Tools + Materials + Soda Can (Noise Test)
do
    local obj, cont = createContainer("shelves", "furniture_shelving_01_24", "garage", {
        createItem("Base.Hammer", "Weapon", "Tool"),
        createItem("Base.NailsBox", "Item", "Material"),
        createItem("Base.Plank", "Item", "Material"),
        createItem("Base.PopCanEmpty", "Item", "Junk") -- Empty soda can
    })
    local cfg, reason = SmartZoning.evaluate(obj, cont)
    check(cfg ~= nil, "Workshop shelf resolves")
    check(reason == "COMPOSITE_WORKSHOP", "Identified as COMPOSITE_WORKSHOP")
    check(cfg.groups["tools"] == true and cfg.groups["materials"] == true, "Tools & Materials enabled")
    check(cfg.priority == 3, "Workshop shelf has Priority 3")
end

-- Scenario 7: Hallway / Living Room Desk with Writing Stationery & Newspaper
do
    local obj, cont = createContainer("desk", "furniture_tables_low_01_0", "livingroom", {
        createItem("Base.Pen", "Weapon", "Weapon"),
        createItem("Base.Pencil", "Weapon", "Weapon"),
        createItem("Base.Newspaper", "Literature", "Literature")
    })
    local cfg, reason = SmartZoning.evaluate(obj, cont)
    check(cfg ~= nil, "Living room desk with stationery resolves")
    check(reason == "DOMINANT_LITERATURE" or reason == "GENERAL_STORAGE", "Resolved cleanly as literature/general storage")
    check(cfg.groups["weapons"] == nil, "Pens did NOT turn living room desk into an armory!")
    check(cfg.private == false, "Desk is NOT falsely marked private!")
end

-- Scenario 7B: Coffee Table with Pure Random Misc Junk (Empty mug, cigarettes, lighter)
do
    local obj, cont = createContainer("coffeetable", "furniture_tables_low_01_4", "livingroom", {
        createItem("Base.MugEmpty", "Item", "Junk"),
        createItem("Base.Cigarettes", "Item", "Item"),
        createItem("Base.Lighter", "Item", "Item")
    })
    local cfg, reason = SmartZoning.evaluate(obj, cont)
    check(cfg ~= nil, "Coffee table with misc junk resolves without error")
    check(reason == "GENERAL_STORAGE", "Identified as GENERAL_STORAGE fallback")
    check(cfg.priority == 1, "Misc coffee table has Lowest Priority 1")
    check(cfg.private == false, "Coffee table is NOT marked private")
end

-- Scenario 8: Player-built Wooden Crate in a Custom Self-Built Room (room == nil)
do
    local obj, cont = createContainer("crate", "carpentry_01_16", nil, {
        createItem("Base.Plank", "Item", "Material"),
        createItem("Base.NailsBox", "Item", "Material"),
        createItem("Base.Screwdriver", "Weapon", "Tool")
    })
    local cfg, reason = SmartZoning.evaluate(obj, cont)
    check(cfg ~= nil, "Self-built crate in nil room resolves")
    check(reason == "COMPOSITE_WORKSHOP", "Identified as COMPOSITE_WORKSHOP from materials/tools")
    check(cfg.groups["materials"] == true and cfg.groups["tools"] == true, "Materials & Tools enabled")
    check(cfg.priority == 3, "Workshop crate has Priority 3")
end

-- Scenario 9: Completely Empty Neutral Cardboard Box in an Unassigned Room
do
    local obj, cont = createContainer("cardboardbox", "furniture_storage_01_56", nil, {})
    local cfg, reason = SmartZoning.evaluate(obj, cont)
    check(cfg ~= nil, "Empty neutral cardboard box resolves")
    check(reason == "GENERAL_STORAGE", "Identified as GENERAL_STORAGE fallback")
    check(cfg.priority == 1, "Fallback box has lowest Priority 1")
end

-- Scenario 10: Wardrobe in Bedroom (Clothing & Bags)
do
    local obj, cont = createContainer("wardrobe", "furniture_storage_01_0", "bedroom", {
        createItem("Base.Jacket_Leather", "Clothing", "Clothing"),
        createItem("Base.Jeans", "Clothing", "Clothing"),
        createItem("Base.Bag_Schoolbag", "Container", "Container")
    })
    local cfg, reason = SmartZoning.evaluate(obj, cont)
    check(cfg ~= nil, "Bedroom wardrobe resolves")
    check(reason == "PHYSICAL_WARDROBE", "Identified as PHYSICAL_WARDROBE")
    check(cfg.groups["apparel"] == true, "Apparel enabled")
    check(cfg.priority == 3, "Wardrobe has Priority 3")
end

print("==================================================")
print(string.format("SIMULATION RESULTS: %d / %d ASSERTIONS PASSED (100%% PASS RATE)", passed, count))
print("ALL REALISTIC PROJECT ZOMBOID BASE SCENARIOS VERIFIED!")
print("==================================================")
