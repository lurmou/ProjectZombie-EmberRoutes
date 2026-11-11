-- Tests for LaborProducers carry container recognition, bag prioritization,
-- freeCarry calculation with equipped bags, and weight reduction.
local Producers = require 'EmberRoutesProbe/Work/LaborProducers'

local count = 0
local function check(ok, label)
    count = count + 1
    assert(ok, label)
end

local function makeContainer(capacity, freeCapacity)
    local itemsList = {}
    local cont = {
        _items = itemsList,
        _cap = capacity or 50,
        _free = freeCapacity or 50,
        _parent = nil,
        getItems = function(self)
            return {
                size = function() return #itemsList end,
                get = function(_, idx) return itemsList[idx + 1] end,
                contains = function(_, it)
                    for _, v in ipairs(itemsList) do if v == it then return true end end
                    return false
                end
            }
        end,
        getFreeCapacity = function(self, _) return self._free end,
        getCapacity = function(self) return self._cap end,
        hasRoomFor = function(self, _, it)
            local w = it and it.getActualWeight and it:getActualWeight() or 1
            return self._free >= w
        end,
        isInCharacterInventory = function(self, chr)
            return true
        end
    }
    return cont
end

local function makeBag(name, weightReduction, capacity, freeCapacity, equipped)
    local bagCont = makeContainer(capacity, freeCapacity)
    local bagItem = {
        _name = name,
        _red = weightReduction,
        _equipped = equipped ~= false,
        _cont = bagCont,
        getCategory = function(self) return "Container" end,
        isEquipped = function(self) return self._equipped end,
        getItemContainer = function(self) return self._cont end,
        getInventory = function(self) return self._cont end,
        getWeightReduction = function(self) return self._red end,
        getActualWeight = function(self) return 1.5 end,
        getUnequippedWeight = function(self) return 1.5 end,
        getModData = function(self) return {} end,
        isFavorite = function(self) return false end
    }
    return bagItem, bagCont
end

local function makeCharacter(maxWeight, currentWeight)
    local own = makeContainer(8, 8)
    local equippedItems = {}
    local chr = {
        _own = own,
        _maxWeight = maxWeight or 20,
        _weight = currentWeight or 5,
        getInventory = function(self) return self._own end,
        getMaxWeight = function(self) return self._maxWeight end,
        getInventoryWeight = function(self) return self._weight end,
        isEquipped = function(self, item) return item:isEquipped() end
    }
    return chr, own
end

local function makeItem(weight)
    return {
        getActualWeight = function() return weight end,
        getUnequippedWeight = function() return weight end,
        getCategory = function() return "Item" end,
        isEquipped = function() return false end,
        isFavorite = function() return false end,
        getModData = function() return {} end
    }
end

-- Case 1: Plain character without bags
local chr1, own1 = makeCharacter(20, 5) -- comfortable remaining = 15, own free = 8
check(Producers.freeCarry(chr1) == 8, "plain character freeCarry clamped by own freeCapacity (8 < 15)")
check(Producers.isCharacterInventory(chr1, own1) == true, "own is character inventory")
local containers1 = Producers.getCarryContainers(chr1)
check(#containers1 == 1 and containers1[1].container == own1, "only 1 container when no bags equipped")
local best1 = Producers.bestCarryContainer(chr1, makeItem(3))
check(best1 == own1, "best container is own when no bags")

-- Case 2: Character with Big Hiking Bag (80% reduction, 30 capacity, 30 free)
local chr2, own2 = makeCharacter(20, 5)
local bagItem2, bagCont2 = makeBag("BigHikingBag", 80, 30, 30, true)
own2._items[#own2._items + 1] = bagItem2

local containers2 = Producers.getCarryContainers(chr2)
check(#containers2 == 2, "2 containers found (own + hiking bag)")
check(containers2[2].container == bagCont2 and containers2[2].weightReduction == 80, "bag has 80% reduction")
check(Producers.isCharacterInventory(chr2, bagCont2) == true, "equipped bag is character inventory")

-- freeCarry: own free 8 + bag free 30 = 38. maxWeight 20 - weight 5 = 15. min(38, 15) = 15.
check(Producers.freeCarry(chr2) == 15, "freeCarry accounts for bag and clamps to comfortable remaining")

-- bestCarryContainer should pick the bag over own pocket
local itemToPack = makeItem(5)
local best2 = Producers.bestCarryContainer(chr2, itemToPack)
check(best2 == bagCont2, "best container picks equipped bag with weight reduction")

-- Case 3: Character with multiple bags (Schoolbag 60% vs Hiking Bag 80%)
local chr3, own3 = makeCharacter(20, 5)
local schoolItem, schoolCont = makeBag("Schoolbag", 60, 15, 15, true)
local hikingItem, hikingCont = makeBag("HikingBag", 80, 25, 25, true)
-- Add in arbitrary order
own3._items[#own3._items + 1] = schoolItem
own3._items[#own3._items + 1] = hikingItem

local containers3 = Producers.getCarryContainers(chr3)
check(#containers3 == 3, "3 containers found")
check(containers3[2].weightReduction == 80 and containers3[2].container == hikingCont, "sorted descending: 80% first")
check(containers3[3].weightReduction == 60 and containers3[3].container == schoolCont, "sorted descending: 60% second")

-- When hiking bag is full, it spills over to schoolbag, then to own pocket
hikingCont._free = 1 -- only 1 free
local itemToPack3 = makeItem(5)
local best3 = Producers.bestCarryContainer(chr3, itemToPack3)
check(best3 == schoolCont, "hiking bag full -> falls back to schoolbag")

schoolCont._free = 0 -- schoolbag also full
local best4 = Producers.bestCarryContainer(chr3, itemToPack3)
check(best4 == own3, "both bags full -> falls back to own pocket")

own3._free = 2 -- own pocket also insufficient for 5
local best5, reason5 = Producers.bestCarryContainer(chr3, itemToPack3)
check(best5 == nil and reason5 == "INSUFFICIENT_CARRY_CAPACITY", "all containers full -> INSUFFICIENT_CARRY_CAPACITY")
check(Producers.hasCarryRoomFor(chr3, itemToPack3) == false, "hasCarryRoomFor false when all full")

print('PASS ' .. count .. ' labor producers carry & bag tests')
