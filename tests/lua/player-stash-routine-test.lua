package.path="Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;"..package.path
local Filter = require "EmberRoutesProbe/StorageFilter"
local ItemLock = require "EmberRoutesProbe/ItemLock"
local PlayerStashRoutine = require "EmberRoutesProbe/PlayerStashRoutine"
local BatchStoragePainting = require "EmberRoutesProbe/BatchStoragePainting"

local count = 0
local function check(val, msg)
    count = count + 1
    assert(val, msg)
end

local function fakeItem(fullType, cat, display, isEquipped, isLocked)
    local item = {
        data = { EmberRoutesLocked = isLocked == true }
    }
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
    function item:getModData() return self.data end
    return item, isEquipped
end

local function fakePlayer(x, y, z, itemList)
    local equippedMap = {}
    local rawList = {}
    for _, pair in ipairs(itemList or {}) do
        local it, eq = pair[1], pair[2]
        rawList[#rawList + 1] = it
        if eq then equippedMap[it] = true end
    end

    local p = {
        x = x or 0, y = y or 0, z = z or 0
    }
    function p:getX() return self.x end
    function p:getY() return self.y end
    function p:getZ() return self.z end
    function p:isDead() return false end
    function p:isEquipped(it) return equippedMap[it] == true end
    function p:getInventory()
        return {
            getItems = function()
                return {
                    size = function() return #rawList end,
                    get = function(_, idx) return rawList[idx + 1] end
                }
            end
        }
    end
    return p
end

local function fakeEndpoint(x, y, z, filterConfig)
    local ep = {
        square = {
            getX = function() return x end,
            getY = function() return y end,
            getZ = function() return z end
        },
        container = {
            getType = function() return "crate" end
        },
        filter = filterConfig
    }
    return ep
end

-- 1. ItemLock Unit Tests
local itemUnlocked = fakeItem("Base.Nails", "Material", "Material")
local itemLocked = fakeItem("Base.Pistol", "Weapon", "Weapon", false, true)
check(not ItemLock.isLocked(itemUnlocked), "unlocked item returns false")
check(ItemLock.isLocked(itemLocked), "locked item returns true")
ItemLock.toggle(itemUnlocked)
check(ItemLock.isLocked(itemUnlocked), "toggle locks unlocked item")
ItemLock.toggle(itemUnlocked)
check(not ItemLock.isLocked(itemUnlocked), "toggle unlocks locked item")

-- 2. PlayerStashRoutine Candidate Filtering
local edcGun, eq1 = fakeItem("Base.Pistol", "Weapon", "Weapon", true, true)       -- Equipped & Locked
local lockedKey, eq2 = fakeItem("Base.Key1", "Key", "Key", false, true)          -- In bag, but Locked
local freeAmmo, eq3 = fakeItem("Base.Bullets9mm", "Ammo", "Ammo", false, false)   -- In bag, free to stash
local freeApple, eq4 = fakeItem("Base.Apple", "Food", "Food", false, false)      -- In bag, free to stash
local freePlank, eq5 = fakeItem("Base.Plank", "Material", "Material", false, false) -- In bag, free to stash

local player = fakePlayer(10, 10, 0, {
    { edcGun, eq1 },
    { lockedKey, eq2 },
    { freeAmmo, eq3 },
    { freeApple, eq4 },
    { freePlank, eq5 }
})

local foodFilter = Filter.new()
foodFilter.groups["food"] = true

local armoryFilter = Filter.new()
armoryFilter.groups["weapons"] = true

local workshopFilter = Filter.new()
workshopFilter.groups["materials"] = true

local containers = {
    fakeEndpoint(12, 10, 0, foodFilter),    -- Distance 2
    fakeEndpoint(15, 10, 0, armoryFilter),  -- Distance 5
    fakeEndpoint(11, 10, 0, workshopFilter) -- Distance 1 (closest)
}

local plan, reason = PlayerStashRoutine.plan(player, containers)
check(plan ~= nil, "player stash routine generates valid plan")
check(plan.totalItems == 3, "exactly 3 unequipped, unlocked items planned for transfer")
check(#plan.stops == 3, "plan creates 3 physical stops")

-- Verify nearest-first ordering (TSP greedy)
check(plan.stops[1].distance == 1, "first stop is the closest workshop container (dist 1)")
check(plan.stops[2].distance == 4, "second stop is food container (dist 2 -> dSq 4)")
check(plan.stops[3].distance == 25, "third stop is armory container (dist 5 -> dSq 25)")

-- Verify correct item routing
check(plan.stops[1].items[1]:getFullType() == "Base.Plank", "plank routed to workshop")
check(plan.stops[2].items[1]:getFullType() == "Base.Apple", "apple routed to food")
check(plan.stops[3].items[1]:getFullType() == "Base.Bullets9mm", "ammo routed to armory")

-- Verify equipped and locked items were strictly excluded
for _, stop in ipairs(plan.stops) do
    for _, item in ipairs(stop.items) do
        check(item:getFullType() ~= "Base.Pistol", "EDC gun was not scheduled for transfer")
        check(item:getFullType() ~= "Base.Key1", "locked key was not scheduled for transfer")
    end
end

-- 3. BatchStoragePainting Unit Tests
local taggedBoxes = {}
local function mockTag(obj, cont, cfg)
    taggedBoxes[cont] = cfg
end

local entries = {
    { container = { id = 1, getType = function() return "crate" end }, tagFunc = mockTag },
    { container = { id = 2, getType = function() return "crate" end }, tagFunc = mockTag },
    { container = { id = 3, getType = function() return "crate" end }, tagFunc = mockTag }
}

local batchResult = BatchStoragePainting.apply(entries, "materials")
check(batchResult.updated == 3, "batch painted all 3 blank crates with materials preset")
check(taggedBoxes[entries[1].container].groups["materials"] == true, "crate 1 has materials group")
check(taggedBoxes[entries[2].container].groups["materials"] == true, "crate 2 has materials group")
check(taggedBoxes[entries[3].container].groups["materials"] == true, "crate 3 has materials group")

print("PASS " .. count .. " player stash routine, item lock, and batch painting assertions succeeded.")
