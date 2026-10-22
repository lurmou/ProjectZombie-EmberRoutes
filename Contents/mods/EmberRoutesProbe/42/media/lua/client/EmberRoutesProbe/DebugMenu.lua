require "DebugUIs/DebugContextMenu"
local Commands=require "EmberRoutesProbe/NpcCommands"
local Actions=require "EmberRoutesProbe/Actions"
local Haul=require "EmberRoutesProbe/Haul"
local Persistence=require "EmberRoutesProbe/Persistence"
local SettlementMenu=require "EmberRoutesProbe/SettlementMenu"
local Craft=require "EmberRoutesProbe/CraftProbe"
local function fill(actor,menu,worldobjects,square)
    menu:addOption(getText("IGUI_EmberRoutesProbe_Spawn"), actor, Commands.execute, "spawn", square)
    menu:addOption(getText("IGUI_EmberRoutesProbe_Inspect"), actor, Commands.execute, "inspect", square)
    menu:addOption(getText("IGUI_EmberRoutesProbe_Remove"), actor, Commands.execute, "remove", square)
    for _, command in ipairs({ "report", "restore", "sample", "checksample", "saveworld", "clearsample", "recover" }) do
        menu:addOption(getText("IGUI_EmberRoutesProbe_Persistence_" .. command), actor, Persistence.execute, command)
    end
    local actionOption = menu:addOption(getText("IGUI_EmberRoutesProbe_Actions"), nil, nil)
    local actionMenu = ISContextMenu:getNew(menu)
    menu:addSubMenu(actionOption, actionMenu)
    for _, command in ipairs({ "suite", "prepare", "eat", "drink", "pack", "unpack", "cancel", "report", "cleanup" }) do
        actionMenu:addOption(getText("IGUI_EmberRoutesProbe_Action_" .. command), actor, Actions.execute, command)
    end
    local haulOption = menu:addOption(getText("IGUI_EmberRoutesProbe_Haul"), nil, nil)
    local haulMenu = ISContextMenu:getNew(menu)
    menu:addSubMenu(haulOption, haulMenu)
    -- Only explicitly clicked physical containers are candidates; never scan inventories.
    for _, object in ipairs(worldobjects) do
        if object.getContainer and object:getContainer() and object:getSquare()
                and object:getSquare():getObjects():contains(object) then
            local containerOption = haulMenu:addOption(getText("IGUI_EmberRoutesProbe_HaulContainer")
                .. " " .. object:getContainer():getType() .. " (" .. object:getSquare():getX()
                .. "," .. object:getSquare():getY() .. "," .. object:getSquare():getZ() .. ")", nil, nil)
            local containerMenu = ISContextMenu:getNew(haulMenu)
            haulMenu:addSubMenu(containerOption, containerMenu)
            for _, command in ipairs({ "source", "destination", "untag" }) do
                containerMenu:addOption(getText("IGUI_EmberRoutesProbe_Haul_" .. command), actor, Haul.execute, command, object)
            end
        end
    end
    for _, command in ipairs({ "run", "cancel", "report", "cleanup" }) do
        haulMenu:addOption(getText("IGUI_EmberRoutesProbe_Haul_" .. command), actor, Haul.execute, command)
    end
    menu:addOption(getText("IGUI_EmberRoutesProbe_SpawnAdditional"),actor,Commands.execute,"spawnAdditional",square)
    menu:addOption(getText("IGUI_EmberRoutesProbe_Settlement_perfStart"),actor,SettlementMenu.performance)
    local craftOption=menu:addOption(getText("IGUI_EmberRoutesProbe_Craft"),nil,nil)
    local craftMenu=ISContextMenu:getNew(menu) menu:addSubMenu(craftOption,craftMenu)
    local bench
    for _,object in ipairs(worldobjects) do
        if object.isGenericCraftingSurface and object:isGenericCraftingSurface() then bench=object break end
    end
    for _,command in ipairs({"teach","run","resume","return","stop","report"}) do
        local option=craftMenu:addOption(getText("IGUI_EmberRoutesProbe_Craft_"..command),actor,Craft.execute,command,bench)
        if (command=="teach" or command=="run") and not bench then option.notAvailable=true end
    end

end
-- Append only inside the native debug submenu, after vanilla builds it.
local original=DebugContextMenu.doDebugMenu
DebugContextMenu.doDebugMenu=function(playerIndex,context,worldobjects,test)
    local result=original(playerIndex,context,worldobjects,test)
    if test or not isDebugEnabled() or not SandboxVars or not SandboxVars.EmberRoutes
        or not SandboxVars.EmberRoutes.CarrierProbe then return result end
    local actor=getSpecificPlayer(playerIndex)
    local option=context:getOptionFromName(getText("ContextMenu_Debug"))
    local parent=option and option.subOption and context:getSubMenu(option.subOption)
    if not parent or not actor or actor:isDead() then return result end
    local square
    for _,object in ipairs(worldobjects) do square=object:getSquare() if square then break end end
    if not square then return result end
    local child=parent:addOption(getText("IGUI_EmberRoutesProbe_DebugMenu"),nil,nil)
    local menu=ISContextMenu:getNew(parent) parent:addSubMenu(child,menu)
    fill(actor,menu,worldobjects,square)
    return result
end
return true
