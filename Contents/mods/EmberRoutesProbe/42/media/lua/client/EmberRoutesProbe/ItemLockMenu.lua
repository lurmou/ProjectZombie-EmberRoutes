-- Inventory Object Context Menu for Item Lock & Keep protection.
local ItemLock = require "EmberRoutesProbe/ItemLock"

local ItemLockMenu = {}

function ItemLockMenu.onToggleLock(items, player)
    for _, it in ipairs(items or {}) do
        if it.items and type(it.items) == "table" then
            for j = 1, #it.items do
                local subItem = it.items[j]
                if subItem and subItem.getModData then
                    ItemLock.toggle(subItem)
                end
            end
        elseif it and it.getModData then
            ItemLock.toggle(it)
        end
    end
end

function ItemLockMenu.fill(playerNum, context, items)
    if not items or #items == 0 then return end

    local firstItem = items[1]
    if firstItem.items and type(firstItem.items) == "table" and firstItem.items[1] then
        firstItem = firstItem.items[1]
    end

    if not firstItem or not firstItem.getModData then return end

    local locked = ItemLock.isLocked(firstItem)
    local icon = locked and "\240\159\148\146 " or "\240\159\148\147 "
    local text = icon .. (locked and getText("IGUI_EmberRoutesProbe_ItemLock_unlock") or getText("IGUI_EmberRoutesProbe_ItemLock_lock"))
    context:addOption(text, items, ItemLockMenu.onToggleLock, playerNum)
end

if Events and Events.OnFillInventoryObjectContextMenu then
    Events.OnFillInventoryObjectContextMenu.Add(ItemLockMenu.fill)
end

return ItemLockMenu
