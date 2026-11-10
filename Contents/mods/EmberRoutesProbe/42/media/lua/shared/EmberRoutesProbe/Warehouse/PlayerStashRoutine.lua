-- Player Stash Routine (Physical Unload & Storage Service).
-- Real physical walk & inventory transfer via vanilla TimedActions; NEVER magic AE2 teleportation.
-- Fully cancelable on player movement, panic, or zombie threat.
local Filter = require "EmberRoutesProbe/Warehouse/StorageFilter"
local SortPolicy = require "EmberRoutesProbe/Warehouse/SortPolicy"
local ItemLock = require "EmberRoutesProbe/Warehouse/ItemLock"

local PlayerStashRoutine = {
    DEFAULT_MAX_DISTANCE = 15,
    -- "Unlimited" distance inside a settlement: not a real range, just the
    -- number passed where a maxDistance is required (getNearbyStorage /
    -- plan maxDistance). The real gate is options.unlimitedDistance;
    -- this only names the 9999 so the two call sites cannot drift apart.
    -- Deliberately NOT shared with the 9999 quantity caps (Production,
    -- DeliveryService, OrderStore, StockRule, CraftRecord, ...): same
    -- digits, different meaning (a count limit, not a distance).
    UNLIMITED_DISTANCE = 9999
}

--- Calculates distance squared between two points.
local function distSq(x1, y1, x2, y2)
    local dx, dy = x1 - x2, y1 - y2
    return dx * dx + dy * dy
end

--- Plans the physical stash routine for a player.
---@param player IsoPlayer|table
---@param accessibleContainers table array of { object=IsoObject, container=ItemContainer, square=IsoGridSquare, filter=table }
---@param options table|nil { maxDistance = number }
---@return table plan, string reason
function PlayerStashRoutine.plan(player, accessibleContainers, options)
    if not player or (player.isDead and player:isDead()) then
        return nil, "PLAYER_UNAVAILABLE"
    end

    local inv = player.getInventory and player:getInventory()
    if not inv or not inv.getItems then
        return nil, "NO_INVENTORY"
    end

    local items = inv:getItems()
    local size = items and items:size() or 0
    if size == 0 then
        return nil, "INVENTORY_EMPTY"
    end

    -- 1. Gather unequipped and unlocked candidate items
    local rawItems = {}
    for i = 0, size - 1 do
        local item = items:get(i)
        if item then rawItems[#rawItems + 1] = item end
    end

    local candidates, skipped = ItemLock.filterTransferCandidates(player, rawItems)
    if #candidates == 0 then
        return nil, "NO_TRANSFERRABLE_ITEMS"
    end

    -- 2. Filter valid, non-private, within-reach destination containers
    local px = player.getX and player:getX() or 0
    local py = player.getY and player:getY() or 0
    local pz = player.getZ and player:getZ() or 0
    local maxDist = options and options.maxDistance or PlayerStashRoutine.DEFAULT_MAX_DISTANCE
    local maxDistSq = maxDist * maxDist

    local validEndpoints = {}
    for _, ep in ipairs(accessibleContainers or {}) do
        local sq = ep.square or (ep.object and ep.object.getSquare and ep.object:getSquare())
        if sq then
            local sx, sy, sz = sq:getX(), sq:getY(), sq:getZ()
            local withinDist = (options and options.unlimitedDistance) or (distSq(px, py, sx, sy) <= maxDistSq)
            if sz == pz and withinDist then
                local config = ep.filter
                if config and Filter.access(config) and not config.private then
                    validEndpoints[#validEndpoints + 1] = {
                        object = ep.object,
                        container = ep.container,
                        square = sq,
                        filter = config,
                        dist = distSq(px, py, sx, sy),
                        items = {}
                    }
                end
            end
        end
    end

    if #validEndpoints == 0 then
        return nil, "NO_VALID_CONTAINERS_NEARBY"
    end

    -- 3. Match candidate items to best containers using SortPolicy specificity
    local totalMatched = 0
    for _, item in ipairs(candidates) do
        local desc = Filter.describe(item)
        local bestEp = nil
        local bestCand = nil

        for _, ep in ipairs(validEndpoints) do
            if Filter.matches(ep.filter, item) then
                local spec = SortPolicy.specificity(ep.filter, desc, item) or 0
                local prio = ep.filter and ep.filter.priority or 3
                local cand = { id = ep.id or tostring(ep), priority = prio, specificity = spec, distance = ep.dist }
                if not bestCand or SortPolicy.better(cand, bestCand) then
                    bestCand = cand
                    bestEp = ep
                end
            end
        end

        if bestEp then
            bestEp.items[#bestEp.items + 1] = item
            totalMatched = totalMatched + 1
        end
    end

    if totalMatched == 0 then
        return nil, "NO_ITEMS_MATCHED_CONTAINERS"
    end

    -- 4. Construct sorted itinerary (TSP-like greedy nearest neighbor)
    local itinerary = {}
    for _, ep in ipairs(validEndpoints) do
        if #ep.items > 0 then
            itinerary[#itinerary + 1] = {
                object = ep.object,
                container = ep.container,
                square = ep.square,
                items = ep.items,
                distance = ep.dist
            }
        end
    end

    table.sort(itinerary, function(a, b) return a.distance < b.distance end)

    return {
        totalItems = totalMatched,
        stops = itinerary
    }, "SUCCESS"
end

--- Enqueues TimedActions for physical movement and item transfers.
---@param player IsoPlayer
---@param plan table generated by PlayerStashRoutine.plan
---@return boolean success
function PlayerStashRoutine.execute(player, plan)
    if not plan or not plan.stops or #plan.stops == 0 then return false end
    if not ISTimedActionQueue or not ISWalkToTimedAction or not ISInventoryTransferAction then
        return false, "TIMED_ACTION_SYSTEM_UNAVAILABLE"
    end

    local playerInv = player:getInventory()

    for _, stop in ipairs(plan.stops) do
        -- 1. Walk to adjacent free tile of the target container
        local sq = stop.square
        if sq then
            local freeSquare = sq
            if AdjacentFreeTileFinder and AdjacentFreeTileFinder.Find then
                freeSquare = AdjacentFreeTileFinder.Find(sq, player) or sq
            end
            ISTimedActionQueue.add(ISWalkToTimedAction:new(player, freeSquare))
        end

        -- 2. Enqueue transfer for each item
        local targetContainer = stop.container or (stop.object and stop.object:getContainer())
        if targetContainer then
            for _, item in ipairs(stop.items) do
                local sourceContainer = item:getContainer() or playerInv
                ISTimedActionQueue.add(ISInventoryTransferAction:new(player, item, sourceContainer, targetContainer))
            end
        end
    end

    return true
end

return PlayerStashRoutine
