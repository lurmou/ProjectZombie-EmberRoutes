-- QA overlay only; all commands live inside the native Debug submenu.
require 'DebugUIs/DebugContextMenu'
local Q=require 'EmberRoutesProbe/B5Acceptance'
local original=DebugContextMenu.doDebugMenu
DebugContextMenu.doDebugMenu=function(playerIndex,context,objects,test)
    local result=original(playerIndex,context,objects,test)
    if test or not isDebugEnabled() then return result end
    local actor=getSpecificPlayer(playerIndex)
    local option=context:getOptionFromName(getText('ContextMenu_Debug'))
    local parent=option and option.subOption and context:getSubMenu(option.subOption)
    if not actor or not parent then return result end
    local entry=parent:addOption(getText('IGUI_EmberRoutesProbe_B5QA'),nil,nil)
    local menu=ISContextMenu:getNew(parent) parent:addSubMenu(entry,menu)
    for _,command in ipairs({'prepare','verify'}) do
	menu:addOption(getText('IGUI_EmberRoutesProbe_B5QA_'..command),actor,Q.execute,command)
    end
    return result
end
return true
