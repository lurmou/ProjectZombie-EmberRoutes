local Probe=require "EmberRoutesProbe/Boot"
local Companion=require "EmberRoutesProbe/Companion"
local Work=require "EmberRoutesProbe/Work"
-- Background lifecycle must exist before OnGameStart, even with every UI closed.
require "EmberRoutesProbe/Persistence"
require "EmberRoutesProbe/StockService"
require "EmberRoutesProbe/PublicWork"
local ContainerMenu=require "EmberRoutesProbe/ContainerMenu"
local Commands=require "EmberRoutesProbe/NpcCommands"
require "EmberRoutesProbe/StorageTabs"
local SettlementMenu=require "EmberRoutesProbe/SettlementMenu"
require "EmberRoutesProbe/RecipeOrderEntry"
local LogisticsMenu=require "EmberRoutesProbe/LogisticsMenu"
LogisticsMenu.initialize()
require "EmberRoutesProbe/DebugMenu"
require "EmberRoutesProbe/NpcDebugMenu"

local function fillMenu(playerIndex, context, worldobjects, test)
    if test then return end
    if not SandboxVars or not SandboxVars.EmberRoutes or not SandboxVars.EmberRoutes.CarrierProbe then return end
    local actor = getSpecificPlayer(playerIndex)
    if not actor or actor:isDead() then return end
    local square
    for _, object in ipairs(worldobjects) do
        square = object:getSquare()
        if square then break end
    end
    if not square then return end
    local option = context:addOption(getText("IGUI_EmberRoutesProbe_Menu"), nil, nil)
    local menu = ISContextMenu:getNew(context)
    context:addSubMenu(option, menu)
    SettlementMenu.fill(actor,menu)
    SettlementMenu.craftSurfaces(actor,menu,worldobjects)
    if Probe.ready and Probe.hasJava() then
        local workers=menu:addOption(getText("IGUI_EmberRoutesProbe_Workers"),nil,nil)
        local workerMenu=ISContextMenu:getNew(menu) menu:addSubMenu(workers,workerMenu)
        local selected=EmberRoutesProbeJava.selectedId()
        for i=0,EmberRoutesProbeJava.workerCount()-1 do
            local id=EmberRoutesProbeJava.workerIdAt(i)
            workerMenu:addOption((id==selected and "• " or "")..string.sub(id,1,8),actor,Commands.selectWorker,id)
        end
    end
    local workOption = menu:addOption(getText("IGUI_EmberRoutesProbe_Work"), nil, nil)
    local workMenu = ISContextMenu:getNew(menu)
    menu:addSubMenu(workOption, workMenu)
    for _, command in ipairs({ "run", "pause", "resume", "report", "clear" }) do
        workMenu:addOption(getText("IGUI_EmberRoutesProbe_Work_" .. command), actor, Work.execute, command)
    end
    local settingsOption=menu:addOption(getText("IGUI_EmberRoutesProbe_ContainerSettings"),nil,nil)
    local settingsMenu=ISContextMenu:getNew(menu) menu:addSubMenu(settingsOption,settingsMenu)
    for _, object in ipairs(worldobjects) do
        if object.getContainer and object:getContainer() and object:getSquare()
                and object:getSquare():getObjects():contains(object) then
            local square = object:getSquare()
            local count=object.getContainerCount and object:getContainerCount() or 1
            for i=0,count-1 do
                local container=object.getContainerByIndex and object:getContainerByIndex(i) or object:getContainer()
                if container then
                    local label=getTextOrNull("IGUI_ContainerTitle_"..container:getType()) or container:getType()
                    local containerOption=settingsMenu:addOption(label.." ("..square:getX()..","..square:getY()..","..square:getZ()..")",nil,nil)
                    local containerMenu=ISContextMenu:getNew(settingsMenu)
                    settingsMenu:addSubMenu(containerOption,containerMenu)
                    ContainerMenu.fill(actor,containerMenu,object,container)
                    for _,role in ipairs({"source","destination"}) do
                        containerMenu:addOption(getText("IGUI_EmberRoutesProbe_Work_"..role),actor,Work.execute,role,object,container)
                    end
                end
            end
        end
    end
    menu:addOption(getText("IGUI_EmberRoutesProbe_Move"),actor,Commands.execute,"move",square)
    menu:addOption(getText("IGUI_EmberRoutesProbe_Stop"),actor,Commands.execute,"stop",square)
    local companionOption = menu:addOption(getText("IGUI_EmberRoutesProbe_Companion"), nil, nil)
    local companionMenu = ISContextMenu:getNew(menu)
    menu:addSubMenu(companionOption, companionMenu)
    for _, command in ipairs({ "follow", "hold", "sethome", "home", "status" }) do
        companionMenu:addOption(getText("IGUI_EmberRoutesProbe_Companion_" .. command), actor, Companion.execute, command)
    end
end

Events.OnFillWorldObjectContextMenu.Add(fillMenu)
