local Service
local function service()
    if not Service then Service=require "EmberRoutesProbe/Logistics/LogisticsService" end
    return Service
end
local Registry=require "EmberRoutesProbe/Warehouse/ContainerRegistry"
local Menu={}
function Menu.initialize() service() end
local text=require("EmberRoutesProbe/Logistics/LogisticsText").get
function Menu.role(actor,role,object,container)
    local result=Registry.configureLogistics(actor,object,container,role)
    actor:Say(text("result").." "..text(result or "UNSET"))
end
function Menu.container(actor,parent,object,container)
    local option=parent:addOption(text("role"),nil,nil)
    local menu=ISContextMenu:getNew(parent) parent:addSubMenu(option,menu)
    local configured=Registry.metadata(object,container)
    local selected=configured and Registry.logistics({object=object,container=container})
    local hint=menu:addOption(text(configured and "ROLE_HINT" or "UNTAGGED_HINT"),nil,nil)
    hint.notAvailable=true
    for _,role in ipairs({"INPUT","STORAGE","EXCLUDED"}) do
        local choice=menu:addOption(text(role),actor,Menu.role,role,object,container)
        if menu.setOptionChecked then menu:setOptionChecked(choice,role==selected) else choice.checkMark=(role==selected) end
    end
    if selected then
        menu:addOption(text("UNSET"),actor,Menu.role,nil,object,container)
    end
end
return Menu