-- Transfer duration for the native "Loot" presentation action.
--
-- Faithful port of the vanilla maxTime formula in
-- ISInventoryTransferAction:new (B42.22,
-- client/TimedActions/ISInventoryTransferAction.lua:764+), for the
-- container <-> inventory directions only. The Lua transfer call sites
-- pass no `time` argument at all, so the vanilla action computes this
-- itself; this helper exists for the native presentation path, where
-- the physical transfer is done by Lua and only the "Loot" animation
-- needs a duration. Both paths therefore share one duration source.
--
-- Formula (single-player; see notes below for the omitted parts):
--   base 120 ticks; 50 when exactly one side is the character's own
--   inventory and the other side is a world container.
--   Packing only (own inventory -> a container inside the inventory):
--   multiply by the destination's fill ratio
--   (current weight / max weight), clamped to a minimum of 0.4.
--   Multiply by the item's actual weight, clamped ONLY above
--   (w > 3 -> w = 3). Light items are proportionally faster: there is
--   deliberately no lower clamp at 1.
--   Destination is the floor: x0.1 from the own inventory, x0.2 from a
--   world container; packing -> floor is unchanged.
--   Traits: DEXTROUS x0.5; ALL_THUMBS or awkward gloves x2.0.
--   isTimedActionInstant() -> 1 tick.
--
-- Deliberately omitted, with reasons:
--   * Multiplayer client maxTime = -1: the client completes the
--     transfer on the server's ItemTransactionPacket, so the duration
--     is server-driven and meaningless here. Single-player only.
--   * Vanilla start() multiplies by 1.5 when the action begins while
--     moving. Our actions always start from a standstill (the carrier
--     is parked / carrierActive before the action starts), so the
--     factor does not apply.
--   * The result is floored to an integer and clamped to at least 1
--     tick: a native durationTicks <= 0 means "infinite" on the Java
--     side, so a zero-weight item must never produce 0 here. (The
--     vanilla transfer path is unaffected: it never calls this.)
local TransferDuration = {}

local BASE_TICKS = 120
local INVENTORY_TICKS = 50
local MAX_WEIGHT = 3
local MIN_FILL = 0.4

local function trait(name)
    if CharacterTrait and CharacterTrait[name] then return CharacterTrait[name] end
    return name
end

-- The engine methods below exist on every real ItemContainer /
-- IsoGameCharacter, but callers in tests (and future call sites) may
-- pass lighter stand-ins. A missing method reads as its neutral
-- value (not in the character's inventory, no type, weight 1) instead
-- of erroring; real objects are unaffected.
local function inCharacterInventory(container, character)
    if container.isInCharacterInventory then
        return container:isInCharacterInventory(character)
    end
    return false
end

local function containerType(container)
    if container.getType then return container:getType() end
    return nil
end

--- Duration in ticks for moving `item` from `srcContainer` to
--- `destContainer` as `character` would experience it in vanilla.
--- `item` may be nil (vanilla leaves the base time, floor and trait
--- factors still apply); all other arguments are required.
function TransferDuration.forTransfer(character, item, srcContainer, destContainer)
    local own = character:getInventory()
    local time = BASE_TICKS
    local fill = 1.0
    if srcContainer == own then
        if inCharacterInventory(destContainer, character) then
            -- Packing: own inventory -> a container carried on the body.
            local maxWeight = destContainer.getMaxWeight and destContainer:getMaxWeight() or nil
            local curWeight = destContainer.getCapacityWeight and destContainer:getCapacityWeight() or nil
            if maxWeight and maxWeight > 0 and curWeight then
                fill = curWeight / maxWeight
            end
        else
            time = INVENTORY_TICKS
        end
    elseif not inCharacterInventory(srcContainer, character) then
        if inCharacterInventory(destContainer, character) then
            time = INVENTORY_TICKS
        end
    end
    if fill < MIN_FILL then fill = MIN_FILL end

    if item then
        local w = item.getActualWeight and item:getActualWeight() or 1
        if w > MAX_WEIGHT then w = MAX_WEIGHT end
        time = time * w * fill
    end

    if containerType(destContainer) == "floor" then
        if srcContainer == own then
            time = time * 0.1
        elseif inCharacterInventory(srcContainer, character) then
            -- Packing -> floor: vanilla leaves the time unchanged.
        else
            time = time * 0.2
        end
    end

    if character.hasTrait and character:hasTrait(trait("DEXTROUS")) then
        time = time * 0.5
    end
    if (character.hasTrait and character:hasTrait(trait("ALL_THUMBS")))
        or (character.isWearingAwkwardGloves and character:isWearingAwkwardGloves()) then
        time = time * 2.0
    end
    if character.isTimedActionInstant and character:isTimedActionInstant() then
        time = 1
    end

    return math.max(1, math.floor(time))
end

return TransferDuration
