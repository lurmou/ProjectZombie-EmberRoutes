local Probe=require "EmberRoutesProbe/Boot"
local Companion=require "EmberRoutesProbe/Companion"
local Work=require "EmberRoutesProbe/Work"
-- Background lifecycle must exist before OnGameStart, even with every UI closed.
require "EmberRoutesProbe/Persistence"
require "EmberRoutesProbe/StockService"
require "EmberRoutesProbe/PublicWork"
-- Load eagerly: Boot registers Probe.tickDelivery once, so a lazy require from the
-- first "call delivery" click would leave early orders without a ticker.
require "EmberRoutesProbe/DeliveryService"
require "EmberRoutesProbe/ActivityService"
require('EmberRoutesProbe/TaskResume').install()
require('EmberRoutesProbe/SelfCare').install()
require('EmberRoutesProbe/TaskRetirement').install()
require('EmberRoutesProbe/MembershipLifecycle').install()
local ContainerMenu=require "EmberRoutesProbe/ContainerMenu"
local Commands=require "EmberRoutesProbe/NpcCommands"
require "EmberRoutesProbe/StorageTabs"
local SettlementMenu=require "EmberRoutesProbe/SettlementMenu"
require "EmberRoutesProbe/RecipeOrderEntry"
require "EmberRoutesProbe/VanillaCraftingHook"
local LogisticsMenu=require "EmberRoutesProbe/LogisticsMenu"
LogisticsMenu.initialize()
require "EmberRoutesProbe/DebugMenu"
require "EmberRoutesProbe/NpcDebugMenu"
local ReposeMenu=require "EmberRoutesProbe/ReposeMenu"
local MembershipMenu=require "EmberRoutesProbe/MembershipMenu"
local DisplayNames=require "EmberRoutesProbe/DisplayNames"
local Driver=require "EmberRoutesProbe/Driver"
require "EmberRoutesProbe/CleaningPolicyDef"
require "EmberRoutesProbe/CookingPolicyDef"
require 'EmberRoutesProbe/LumberjackPolicyDef'
require 'EmberRoutesProbe/ForagerPolicyDef'

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

    -- 1. 据点与工单管理
    SettlementMenu.fill(actor, menu)
    SettlementMenu.craftSurfaces(actor, menu, worldobjects)

    -- 2. 设施与交互对象 (床位、座椅、容器)
    ReposeMenu.fill(actor, menu, worldobjects)

    local containers = {}
    for _, object in ipairs(worldobjects) do
        if object.getContainer and object:getContainer() and object:getSquare()
                and object:getSquare():getObjects():contains(object) then
            local sq = object:getSquare()
            local count = object.getContainerCount and object:getContainerCount() or 1
            for i = 0, count - 1 do
                local container = object.getContainerByIndex and object:getContainerByIndex(i) or object:getContainer()
                if container then
                    containers[#containers + 1] = {
                        object = object,
                        container = container,
                        square = sq,
                        label = getTextOrNull("IGUI_ContainerTitle_" .. container:getType()) or container:getType()
                    }
                end
            end
        end
    end

    if #containers == 1 then
        local c = containers[1]
        local title = getText("IGUI_EmberRoutesProbe_ContainerSettings") .. " (" .. c.label .. ")"
        local containerOption = menu:addOption(title, nil, nil)
        local containerMenu = ISContextMenu:getNew(menu)
        menu:addSubMenu(containerOption, containerMenu)
        ContainerMenu.fill(actor, containerMenu, c.object, c.container)
        if isDebugEnabled() then
            for _, role in ipairs({ "source", "destination" }) do
                containerMenu:addOption(getText("IGUI_EmberRoutesProbe_Work_" .. role), actor, Work.execute, role, c.object, c.container)
            end
        end
    elseif #containers > 1 then
        local settingsOption = menu:addOption(getText("IGUI_EmberRoutesProbe_ContainerSettings"), nil, nil)
        local settingsMenu = ISContextMenu:getNew(menu)
        menu:addSubMenu(settingsOption, settingsMenu)
        for _, c in ipairs(containers) do
            local floorNum = c.square:getZ()
            local floorLabel = floorNum == 0 and getText("IGUI_EmberRoutesProbe_Floor_ground") or string.format(getText("IGUI_EmberRoutesProbe_Floor_level"), floorNum)
            local label = c.label .. " · " .. floorLabel
            local containerOption = settingsMenu:addOption(label, nil, nil)
            local containerMenu = ISContextMenu:getNew(settingsMenu)
            settingsMenu:addSubMenu(containerOption, containerMenu)
            ContainerMenu.fill(actor, containerMenu, c.object, c.container)
            if isDebugEnabled() then
                for _, role in ipairs({ "source", "destination" }) do
                    containerMenu:addOption(getText("IGUI_EmberRoutesProbe_Work_" .. role), actor, Work.execute, role, c.object, c.container)
                end
            end
        end
    end

    -- 3. 当前随从指令与工作者选择
    if Probe.ready and Probe.hasJava() then
        local workerCount = EmberRoutesProbeJava.workerCount()
        local selected = EmberRoutesProbeJava.selectedId()
        if workerCount > 0 then
            local binding = selected and Driver.bindId(actor, selected)
            local selectedName = selected and DisplayNames.name(selected, binding and binding.handle) or nil
            if selected and selectedName then
                local companionOption = menu:addOption(getText("IGUI_EmberRoutesProbe_SelectedWorker_title") .. ": " .. selectedName, nil, nil)
                local companionMenu = ISContextMenu:getNew(menu)
                menu:addSubMenu(companionOption, companionMenu)
                companionMenu:addOption(getText("IGUI_EmberRoutesProbe_Move"), actor, Commands.execute, "move", square)
                companionMenu:addOption(getText("IGUI_EmberRoutesProbe_Stop"), actor, Commands.execute, "stop", square)
                MembershipMenu.fill(actor, companionMenu, nil, selected)
                companionMenu:addOption(getText("IGUI_EmberRoutesProbe_Companion_status"), actor, Companion.execute, "status")
            end
            local workers = menu:addOption(getText("IGUI_EmberRoutesProbe_Workers"), nil, nil)
            local workerMenu = ISContextMenu:getNew(menu)
            menu:addSubMenu(workers, workerMenu)
            for i = 0, workerCount - 1 do
                local id = EmberRoutesProbeJava.workerIdAt(i)
                local b = Driver.bindId(actor, id)
                local name = DisplayNames.name(id, b and b.handle)
                local prefix = (id == selected and "• " or "  ")
                workerMenu:addOption(prefix .. name, actor, Commands.selectWorker, id)
            end
        else
            local opt = menu:addOption(getText("IGUI_EmberRoutesProbe_NoWorkers"), nil, nil)
            opt.notAvailable = true
        end
    end

    -- 4. 地面集结点设置 (若点击地面处于据点领地内)
    SettlementMenu.returnPoint(actor, menu, square)

    -- 5. 高级/调试指令 (仅 Debug 模式呈现)
    if isDebugEnabled() then
        local debugOpt = menu:addOption(getText("IGUI_EmberRoutesProbe_Debug_probeCommands"), nil, nil)
        local debugMenu = ISContextMenu:getNew(menu)
        menu:addSubMenu(debugOpt, debugMenu)
        local workOption = debugMenu:addOption(getText("IGUI_EmberRoutesProbe_Work"), nil, nil)
        local workMenu = ISContextMenu:getNew(debugMenu)
        debugMenu:addSubMenu(workOption, workMenu)
        for _, command in ipairs({ "run", "pause", "resume", "report", "clear" }) do
            workMenu:addOption(getText("IGUI_EmberRoutesProbe_Work_" .. command), actor, Work.execute, command)
        end
    end
end

Events.OnFillWorldObjectContextMenu.Add(fillMenu)

-- Right-clicking a carrier body usually finds nothing else interactable, and
-- B42 can skip OnFillWorldObjectContextMenu entirely in that case, so per-NPC
-- entries are filled in the unconditional pre-fill event instead.
local function preFillMenu(playerIndex, context, worldobjects, test)
    if test then return end
    if not SandboxVars or not SandboxVars.EmberRoutes or not SandboxVars.EmberRoutes.CarrierProbe then return end
    local actor = getSpecificPlayer(playerIndex)
    if not actor or actor:isDead() then return end
    MembershipMenu.npcEntries(actor, context, worldobjects)
end
Events.OnPreFillWorldObjectContextMenu.Add(preFillMenu)
