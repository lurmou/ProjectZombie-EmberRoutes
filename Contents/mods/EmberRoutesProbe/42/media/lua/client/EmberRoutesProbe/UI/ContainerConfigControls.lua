require "ISUI/ISComboBox"
require "ISUI/ISButton"
local Config=require "EmberRoutesProbe/ContainerConfiguration"
local Layout=require "EmberRoutesProbe/UI/Layout"
local Theme=require "EmberRoutesProbe/UI/Theme"
local Text=require "EmberRoutesProbe/UI/Text"
local Tooltip=require "EmberRoutesProbe/UI/TooltipAnchor"
local Controls={}
local roles={"STORAGE","INPUT","EXCLUDED"}
---@class EmberRoutesContainerConfigControls
---@field summary table
---@field role ISComboBox
---@field preset ISComboBox
---@field copy ISButton
---@field paste ISButton
---@field lines string[]
---@field warning string
---@field refresh function
---@field draw function
---@field close function
---@param owner EmberRoutesStorageFilterPanel
---@return EmberRoutesContainerConfigControls
function Controls.new(owner,bounds,summary)
    ---@type EmberRoutesContainerConfigControls
    local controls={summary=summary}
    local slots=assert(Layout.axis(bounds,{{grow=1.3},{grow=1.5},{grow=0.7},{grow=0.7}},{gap=owner.pad/2}))
    local function roleChanged(target,combo) target.store:setState({role=roles[combo.selected],status="",statusError=false}) end
    local function presetChanged(target,combo)
        local id=Config.presets[combo.selected-1]
        if id then
            target:edit(function(model) model.draft=assert(Config.preset(model.draft,id)) end)
            target.store:setState({status=Config.text("configPresetDraft"),statusError=false}) combo.selected=1
        end
    end
    for i,callback in ipairs({roleChanged,presetChanged}) do
        local r=slots[i] local combo=ISComboBox:new(r.x,r.y,r.width,r.height,owner,callback)
        combo:initialise() owner:addChild(combo)
        if i==1 then
            controls.role=combo for _,id in ipairs(roles) do combo:addOption(Config.text(id)) end
        else
            controls.preset=combo combo:addOption(Config.text("configPreset"))
            for _,id in ipairs(Config.presets) do combo:addOption(Config.text(id)) end
        end
    end
    for i,action in ipairs({"copy","paste"}) do
        local r=slots[i+2]
        local function clicked(target)
            local result,reason
            if action=="copy" then
                result,reason=Config.copy(target.actor,target.object,target.container,target.model.draft)
            else
                result,reason=Config.paste(target.actor,target.model.draft)
                if result then target:edit(function(model) model.draft=result end) reason="configPastedDraft" end
            end
            target.store:setState({status=Config.text(reason),statusError=not result})
            controls.paste:setEnable(Config.hasClipboard(target.actor))
        end
        local button=ISButton:new(r.x,r.y,r.width,r.height,Config.text("config"..(action=="copy" and "Copy" or "Paste")),owner,clicked)
        button:initialise() button.tooltip=Config.text("configRulesOnly") Theme.button(button) owner:addChild(button)
        controls[action]=button
    end
    function controls:refresh()
        for i,role in ipairs(roles) do if role==owner.store.value.role then self.role.selected=i break end end
        self.paste:setEnable(Config.hasClipboard(owner.actor))
        local value=Config.summary(owner.model.draft,owner.store.value.role,owner.registered)
        self.lines=Text.wrapLimited(value,self.summary.width,UIFont.Small,3)
        self.warning=Config.warning(owner.model.draft,owner.store.value.role)
    end
    function controls:draw()
        for i,line in ipairs(self.lines or {}) do Theme.text(owner,line,self.summary.x,self.summary.y+(i-1)*owner.fontHeight,Theme.accent) end
    end
    function controls:close()
        for _,control in ipairs({self.role,self.preset,self.copy,self.paste}) do Tooltip.clear(control) end
    end
    return controls
end
return Controls
