local Registry=require "EmberRoutesProbe/ContainerRegistry"
local Filter=require "EmberRoutesProbe/StorageFilter"
local Rules=require "EmberRoutesProbe/HaulRules"
local Gate=require "EmberRoutesProbe/RuntimeGate"
local Config={presets={
    "food","food.meals","food.perishable","food.stable",
    "medical","medical.bandages","medical.pills",
    "weapons","weapons.guns","weapons.ammo",
    "apparel","literature","tools","materials","trade","scrap",
    "kit.fishing","kit.farming","kit.tailoring","kit.mechanic"
}}
local clipboard=setmetatable({},{__mode="k"})
function Config.text(key)
    for _,prefix in ipairs({"IGUI_EmberRoutesProbe_Filter_","IGUI_EmberRoutesProbe_WorkCode_","IGUI_EmberRoutesProbe_Logistics_"}) do
        local value=getTextOrNull(prefix..key) if value then return value end
    end
    return key
end
function Config.validate(actor,object,container)
    if not Gate.canExecute(actor) or not actor then return nil,"DRIVER_UNAVAILABLE" end
    local square=object and object:getSquare()
    if not square or Registry.containerIndex(object,container)==nil or not square:getObjects():contains(object) then return nil,"WORLD_CONTAINER_REQUIRED" end
    if not getCell() or getCell():getGridSquare(square:getX(),square:getY(),square:getZ())~=square then return nil,"CONTAINER_UNLOADED" end
    if not Rules.near(actor:getX(),actor:getY(),actor:getZ(),square:getX()+0.5,square:getY()+0.5,square:getZ()) then return nil,"TOO_FAR_TO_TAG" end
    return true
end
-- Only allocation rules are replaced: permissions and logistics role belong to the target.
function Config.replace(config,rules)
    local target,why
    if config then target,why=Filter.copy(config) else target=Filter.new() end
    if not target then return nil,why end
    local source,reason=Filter.copy(rules)
    if not source then return nil,reason end
    target.groups,target.types=source.groups,source.types
    return target
end
function Config.preset(config,id)
    local found=false for _,key in ipairs(Config.presets) do if key==id then found=true break end end
    if not found then return nil,"INVALID_PRESET" end
    local rules=Filter.new() rules.groups[id]=true
    return Config.replace(config,rules)
end
function Config.copy(actor,object,container,draft)
    local ok,reason=Config.validate(actor,object,container)
    if not ok then return nil,reason end
    local copy=Filter.copy(draft or Registry.filter(object,container))
    if not copy then return nil,"configNothingToCopy" end
    clipboard[actor]={world=Registry.data(),rules=copy}
    return true,"configCopied"
end
function Config.hasClipboard(actor)
    local entry=clipboard[actor]
    if entry and entry.world~=Registry.data() then clipboard[actor]=nil entry=nil end
    return entry~=nil
end
function Config.paste(actor,target)
    if not Config.hasClipboard(actor) then return nil,"configClipboardEmpty" end
    return Config.replace(target,clipboard[actor].rules)
end
function Config.summary(config,role,registered)
    if not config then return Config.text("configUnregistered") end
    local state=Config.text(config.private and "privateShort" or "configShared").." · "..Config.text(config.enabled and "configEnabled" or "disabled")
    local allowed,denied,yes,no={},{},0,0
    for _,id in ipairs(Filter.order) do
        if config.groups[id]==true then allowed[#allowed+1]=Config.text(id)
        elseif config.groups[id]==false then denied[#denied+1]=Config.text(id) end
    end
    for _,value in pairs(config.types) do if value then yes=yes+1 else no=no+1 end end
    local function groups(values)
        local visible={} for i=1,math.min(3,#values) do visible[#visible+1]=values[i] end
        if #values>3 then visible[#visible+1]="…" end
        return #visible>0 and table.concat(visible,", ") or Config.text("configNone")
    end
    local exactText = (yes==0 and no==0) and Config.text("exactNone") or (Config.text("exactSummary")..yes.." / "..no)
    return (registered and "" or (Config.text("configDraft").." · "))..Config.text(role).." · "..state
        .."\n"..Config.text("configAllow")..groups(allowed).." | "..Config.text("configDeny")..groups(denied)
        .."\n"..exactText
end
function Config.warning(config,role)
    if not config.enabled then return Config.text("configDisabledHint") end
    if config.private then return Config.text("configPrivateHint") end
    if role=="EXCLUDED" then return Config.text("configExcludedHint") end
    if role=="INPUT" then return Config.text("configInputHint") end
    for _,field in ipairs({"groups","types"}) do for _,value in pairs(config[field]) do if value then return Config.text("configReadyHint") end end end
    return Config.text("configNoRulesHint")
end
return Config
