-- TransferDuration: vanilla ISInventoryTransferAction maxTime formula
-- (B42.22) ported for the native "Loot" presentation path.
-- Run: LUA_PATH="Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;Contents/mods/EmberRoutesProbe/42/media/lua/client/?.lua;;" lua tests/lua/transfer-duration-test.lua
local TransferDuration = require 'EmberRoutesProbe/Work/TransferDuration'
local n = 0 local function check(ok, label) n = n + 1 assert(ok, label) end

local function container(ctype, inInventory, capacityWeight, maxWeight)
    return {
        _type = ctype or "crate",
        _inInv = inInventory or false,
        _cap = capacityWeight or 0,
        _max = maxWeight or 10,
        getType = function(self) return self._type end,
        isInCharacterInventory = function(self, _) return self._inInv end,
        getCapacityWeight = function(self) return self._cap end,
        getMaxWeight = function(self) return self._max end,
    }
end

local function character(opts)
    opts = opts or {}
    local own = container("inventory", true)
    return {
        _own = own,
        _traits = opts.traits or {},
        _awkward = opts.awkward or false,
        _instant = opts.instant or false,
        getInventory = function(self) return self._own end,
        hasTrait = function(self, t) return self._traits[t] == true end,
        isWearingAwkwardGloves = function(self) return self._awkward end,
        isTimedActionInstant = function(self) return self._instant end,
    }
end

local function item(weight)
    return { _w = weight, getActualWeight = function(self) return self._w end }
end

local plain = character()
local world = container("crate", false)
local own = plain:getInventory()

-- Base directions (weight 1, no traits): world<->world 120, either side
-- touching the own inventory 50.
check(TransferDuration.forTransfer(plain, item(1), world, world) == 120, "world->world base 120")
check(TransferDuration.forTransfer(plain, item(1), world, own) == 50, "world->own base 50")
check(TransferDuration.forTransfer(plain, item(1), own, world) == 50, "own->world base 50")

-- Weight has ONLY an upper clamp (w > 3 -> 3): light items are
-- proportionally faster, there is deliberately no lower clamp at 1.
check(TransferDuration.forTransfer(plain, item(0.5), world, own) == 25, "w=0.5 is faster than w=1 (25 < 50)")
check(TransferDuration.forTransfer(plain, item(1), world, own) == 50, "w=1 baseline 50")
check(TransferDuration.forTransfer(plain, item(5), world, own) == 150, "w=5 clamps to 3 (50*3=150)")
check(TransferDuration.forTransfer(plain, item(3), world, own) == 150, "w=3 is the clamp, not above it")

-- Packing direction only (own inventory -> carried container): fill
-- ratio multiplies, floored at 0.4. Other directions ignore fill.
local emptyBag = container("Bag_Schoolbag", true, 0, 10)
local fullBag = container("Bag_Schoolbag", true, 9, 10)
check(TransferDuration.forTransfer(plain, item(1), own, emptyBag) == 48, "packing near-empty bag: 120*1*0.4=48 (floor)")
check(TransferDuration.forTransfer(plain, item(1), own, fullBag) == 108, "packing near-full bag: 120*0.9=108")
check(TransferDuration.forTransfer(plain, item(1), world, own) == 50, "world->own ignores destination fill")
check(TransferDuration.forTransfer(plain, item(1), own, world) == 50, "own->world ignores fill")

-- Floor destination: own->floor x0.1, world->floor x0.2,
-- carried-container->floor unchanged.
local floor = container("floor", false)
check(TransferDuration.forTransfer(plain, item(1), own, floor) == 5, "own->floor x0.1 (50*0.1=5)")
check(TransferDuration.forTransfer(plain, item(1), world, floor) == 24, "world->floor x0.2 (120*0.2=24)")
check(TransferDuration.forTransfer(plain, item(1), emptyBag, floor) == 120, "bag->floor unchanged")

-- Traits.
local dextrous = character({ traits = { DEXTROUS = true } })
check(TransferDuration.forTransfer(dextrous, item(1), world, own) == 25, "DEXTROUS x0.5")
local thumbs = character({ traits = { ALL_THUMBS = true } })
check(TransferDuration.forTransfer(thumbs, item(1), world, own) == 100, "ALL_THUMBS x2.0")
local gloves = character({ awkward = true })
check(TransferDuration.forTransfer(gloves, item(1), world, own) == 100, "awkward gloves x2.0")

-- Instant actions collapse to 1 tick whatever the weight/direction.
local instant = character({ instant = true })
check(TransferDuration.forTransfer(instant, item(5), world, world) == 1, "instant -> 1")

-- No item: base time only (weight/fill factors need an item).
check(TransferDuration.forTransfer(plain, nil, world, own) == 50, "nil item keeps base 50")
-- Zero-weight item never yields a 0 native duration (<=0 means
-- "infinite" on the Java side), so the helper floors at 1 tick.
check(TransferDuration.forTransfer(plain, item(0), world, own) == 1, "w=0 floors at 1 tick")

print('PASS ' .. n .. ' transfer duration checks; game/save codec NOT RUN')
