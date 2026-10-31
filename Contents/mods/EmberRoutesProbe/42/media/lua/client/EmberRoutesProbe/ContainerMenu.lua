local Config=require "EmberRoutesProbe/ContainerConfiguration"
local Registry=require "EmberRoutesProbe/ContainerRegistry"
local Panel=require "EmberRoutesProbe/StorageFilterPanel"
local Text=require "EmberRoutesProbe/UI/Text"
local Logistics=require "EmberRoutesProbe/LogisticsMenu"
local SmartZoning=require "EmberRoutesProbe/SmartZoning"
local CustomKits=require "EmberRoutesProbe/CustomKits"
local PlayerStashRoutine=require "EmberRoutesProbe/PlayerStashRoutine"
local Ledger=require "EmberRoutesProbe/SettlementLedger"
local Geometry=require "EmberRoutesProbe/SettlementGeometry"

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

function Menu.smartZone(actor,object,container)
    local ok,reason=Config.validate(actor,object,container)
    if not ok then actor:Say(Config.text(reason)) return end
    local config,why=SmartZoning.evaluate(object,container)
    if config then
        Panel.open(actor,object,container,config)
    else
        actor:Say(getText("IGUI_EmberRoutesProbe_SmartZone_noMatch"))
    end
end

function Menu.saveAsKit(actor,object,container)
    local ok,reason=Config.validate(actor,object,container)
    if not ok then actor:Say(Config.text(reason)) return end
    local items=container and container:getItems()
    if not items or items:size()==0 then
        actor:Say(getText("IGUI_EmberRoutesProbe_CustomKit_empty"))
        return
    end
    if ISTextBox then
        local playerNum=actor:getPlayerNum()
        local modal=ISTextBox:new(0,0,280,180,getText("IGUI_EmberRoutesProbe_CustomKit_prompt"),"",nil,function(_,button)
            if button.internal=="OK" then
                local text=button.parent.entry:getText()
                local kitId,err=CustomKits.createFromContainer(text,container)
                if kitId then
                    actor:Say(getText("IGUI_EmberRoutesProbe_CustomKit_success")..": "..text)
                else
                    actor:Say(getText("IGUI_EmberRoutesProbe_CustomKit_error")..": "..tostring(err))
                end
            end
        end,playerNum)
        modal:initialise()
        modal:addToUIManager()
    end
end

function Menu.getNearbyStorage(actor, maxDist)
    local list = {}
    local data = Registry.data()
    local px = actor.getX and actor:getX() or 0
    local py = actor.getY and actor:getY() or 0
    local pz = actor.getZ and actor:getZ() or 0

    local currentSettlement = nil
    local settlements = Ledger.at(px, py)
    if settlements and #settlements > 0 then
        currentSettlement = settlements[1]
    end

    local dMaxSq = (maxDist or 15) * (maxDist or 15)

    for id, rec in pairs(data.containers or {}) do
        if rec.z == pz then
            local isCandidate = false
            if currentSettlement then
                if Geometry.inside(currentSettlement, rec.x, rec.y) then
                    isCandidate = true
                end
            else
                local dx, dy = rec.x - px, rec.y - py
                if (dx * dx + dy * dy) <= dMaxSq then
                    isCandidate = true
                end
            end

            if isCandidate then
                local ep = Registry.resolve(id)
                if ep and ep.object and ep.container then
                    list[#list + 1] = {
                        object = ep.object,
                        container = ep.container,
                        square = ep.object:getSquare(),
                        filter = Registry.filter(ep.object, ep.container)
                    }
                end
            end
        end
    end
    return list
end

function Menu.stashRoutine(actor)
    local px = actor.getX and actor:getX() or 0
    local py = actor.getY and actor:getY() or 0
    local settlements = Ledger.at(px, py)
    local inSettlement = settlements and #settlements > 0

    local containers = Menu.getNearbyStorage(actor, inSettlement and 9999 or 15)
    local plan, reason = PlayerStashRoutine.plan(actor, containers, {
        unlimitedDistance = inSettlement,
        maxDistance = inSettlement and 9999 or 15
    })
    if not plan then
        local errKey = "IGUI_EmberRoutesProbe_Stash_" .. tostring(reason)
        local errText = getTextOrNull(errKey) or reason
        actor:Say(errText)
        return
    end
    local ok = PlayerStashRoutine.execute(actor, plan)
    if ok then
        actor:Say(getText("IGUI_EmberRoutesProbe_Stash_started") .. " (" .. plan.totalItems .. ")")
    end
end

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
    parent:addOption(getText("IGUI_EmberRoutesProbe_SmartZone_apply"),actor,Menu.smartZone,object,container)
    parent:addOption(getText("IGUI_EmberRoutesProbe_CustomKit_create"),actor,Menu.saveAsKit,object,container)
    parent:addOption(getText("IGUI_EmberRoutesProbe_Stash_action"),actor,Menu.stashRoutine)
    Logistics.container(actor,parent,object,container)
    local copy=parent:addOption(Config.text("configCopyRules"),actor,Menu.copy,object,container)
    copy.notAvailable=config==nil
    local paste=parent:addOption(Config.text("configPasteEdit"),actor,Menu.paste,object,container)
    paste.notAvailable=not Config.hasClipboard(actor)
    local option=parent:addOption(Config.text("configPreset"),nil,nil)
    local presets=ISContextMenu:getNew(parent) parent:addSubMenu(option,presets)
    for _,id in ipairs(Config.presets) do presets:addOption(Config.text(id),actor,Menu.preset,object,container,id) end
end

return Menu
