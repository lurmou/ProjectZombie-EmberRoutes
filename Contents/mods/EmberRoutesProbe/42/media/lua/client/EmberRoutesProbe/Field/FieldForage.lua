-- Composition at the vanilla forage lookup seam. No SearchManager/ISPanel
-- instance, player slot, UI update loop, overlay or fabricated item is created.
require 'Foraging/ISForageAction'
require 'Foraging/ISBaseIcon'
require 'Foraging/ISSearchManager'
local F={}
function F.prepare(character,raw,zone,square)
    local fs=_G.forageSystem
    local definition=fs.itemDefs[raw.itemType]
    if not definition or not square then return nil,'FIELD_FORAGE_DEFINITION_MISSING' end
    local icon={icon=raw,iconID=raw.id,character=character,zoneData=zone,square=square,
        itemDef=definition,itemType=raw.itemType,itemList=raw.itemList,itemObj=raw.itemObj,
        itemCount=1,isTrack=false,isKnownPoison=false}
    function icon:checkForPoison() return ISBaseIcon.checkForPoison(self) end
    function icon:setIsBeingRemoved(value) self.isBeingRemoved=value end
    function icon:reset() end
    function icon:removeIsoMarker() end
    function icon:removeWorldMarker() end
    function icon:setIsNoticed() end
    function icon:setIsSeen() end
    function icon:setIsSeenThisUpdate() end
    function icon:resetBounce() end
    function icon:setAlpha() end
    -- Delegate the installed generation/count/spawn/poison semantics, including
    -- mod spawn functions. The resulting original instances live on vanilla raw.
    ISBaseIcon.initItemCount(icon)
    ISBaseIcon.getItemList(icon)
    if not icon.itemList or icon.itemList:isEmpty() then return nil,'FIELD_FORAGE_EMPTY' end
    local manager={character=character,forageIcons={[raw.id]=icon},seenIcons={},iconStack={},closeIcons={},iconQueue=0,activeIcons={}}
    function manager:removeItem(value) return ISSearchManager.removeItem(self,value) end
    function manager:removeIcon(value) self.forageIcons[value.iconID]=nil self.seenIcons[value.iconID]=nil end
    -- ISForageAction.new and forageSystem.actionComplete obtain the manager by
    -- character. Borrow only that lookup during a synchronous native call and
    -- restore it even on exceptions. Never replace a successor's changed entry.
    local function invoke(callback,...)
        local previous=ISSearchManager.players[character]
        ISSearchManager.players[character]=manager
        local ok,value=pcall(callback,...)
        local unchanged=ISSearchManager.players[character]==manager
        if unchanged then ISSearchManager.players[character]=previous end
        if not ok then error(value) end
        if not unchanged then error('FIELD_FORAGE_MANAGER_CHANGED') end
        return value
    end
    return {icon=icon,invoke=invoke,create=function()
        return invoke(function() return ISForageAction:new(character,raw.id,nil,character:getInventory(),raw.itemType) end)
    end}
end
return F
