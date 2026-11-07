-- Item Lock & Protection Policy.
-- Protects player gear, EDC weapons, and marked items from auto-stashing or dumping.
local ItemLock = {}

function ItemLock.isLocked(item)
    if not item then return false end
    if not item.getModData then return false end
    local md = item:getModData()
    return md and md.EmberRoutesLocked == true
end

function ItemLock.setLocked(item, locked)
    if not item or not item.getModData then return false end
    local md = item:getModData()
    if not md then return false end
    md.EmberRoutesLocked = (locked == true)
    return true
end

function ItemLock.toggle(item)
    if not item then return false end
    local current = ItemLock.isLocked(item)
    ItemLock.setLocked(item, not current)
    return not current
end

--- Filters an array/list of items, removing equipped and locked items.
---@param player IsoPlayer|table
---@param items table array of inventory items
---@return table eligibleItems, table skippedItems
function ItemLock.filterTransferCandidates(player, items)
    local eligible, skipped = {}, {}
    for _, item in ipairs(items or {}) do
        local locked = ItemLock.isLocked(item)
        local equipped = player and player.isEquipped and player:isEquipped(item) or false
        if locked or equipped then
            skipped[#skipped + 1] = { item = item, reason = locked and "LOCKED" or "EQUIPPED" }
        else
            eligible[#eligible + 1] = item
        end
    end
    return eligible, skipped
end

return ItemLock
