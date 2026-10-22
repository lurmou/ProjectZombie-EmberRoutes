local Config=require "EmberRoutesProbe/ContainerConfiguration"
local Registry=require "EmberRoutesProbe/ContainerRegistry"
local Panel=require "EmberRoutesProbe/StorageFilterPanel"
local Text=require "EmberRoutesProbe/UI/Text"
local Menu={}
function Menu.copy(actor,object,container)
    local _,reason=Config.copy(actor,object,container)
    actor:Say(Config.text(reason))
end
function Menu.paste(actor,object,container)
    local ok,reason=Config.validate(actor,object,container)
    if not ok then actor:Say(Config.text(reason)) return end
    local rules,why=Config.paste(actor,Registry.filter(object,container))
    if not rules then actor:Say(Config.text(why)) return end
    Panel.open(actor,object,container,rules)
end
function Menu.preset(actor,object,container,id) Panel.open(actor,object,container,id) end
function Menu.fill(actor,parent,object,container)
    local config=Registry.filter(object,container)
    local registered=Registry.metadata(object,container)~=nil
    local role=Registry.logistics({object=object,container=container})
    local summary=Config.summary(config,role,registered)
    local width=math.min(420,getCore():getScreenWidth()*0.6)
    local function hint(line)
        local caption=Text.wrapLimited(line,width,UIFont.Small,1)
        local option=parent:addOption(caption[1],nil,nil) option.notAvailable=true
    end
    for line in (summary.."\n"):gmatch("(.-)\n") do
        hint(line)
    end
    if config then hint(Config.warning(config,role)) end
    parent:addOption(getText("IGUI_EmberRoutesProbe_Filter_title"),actor,Panel.open,object,container)
    local copy=parent:addOption(Config.text("configCopyRules"),actor,Menu.copy,object,container)
    copy.notAvailable=config==nil
    local paste=parent:addOption(Config.text("configPasteEdit"),actor,Menu.paste,object,container)
    paste.notAvailable=not Config.hasClipboard(actor)
    local option=parent:addOption(Config.text("configPreset"),nil,nil)
    local presets=ISContextMenu:getNew(parent) parent:addSubMenu(option,presets)
    for _,id in ipairs(Config.presets) do presets:addOption(Config.text(id),actor,Menu.preset,object,container,id) end
end
return Menu
