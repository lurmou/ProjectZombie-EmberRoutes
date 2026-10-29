require "ISUI/ISComboBox"
require "ISUI/ISButton"
local Config=require "EmberRoutesProbe/ContainerConfiguration"
local Layout=require "EmberRoutesProbe/UI/Layout"
local Theme=require "EmberRoutesProbe/UI/Theme"
local Text=require "EmberRoutesProbe/UI/Text"
local Tooltip=require "EmberRoutesProbe/UI/TooltipAnchor"
local SmartZoning=require "EmberRoutesProbe/SmartZoning"
local Controls={}
local roles={"STORAGE","INPUT","EXCLUDED"}
---@class EmberRoutesContainerConfigControls
---@field summary table
---@field role ISComboBox
---@field preset ISComboBox
---@field smartDetect ISButton
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
    local slots=assert(Layout.axis(bounds,{{grow=1.1},{grow=1.2},{grow=1.4},{grow=0.65},{grow=0.65}},{gap=owner.pad/2}))
    local function roleChanged(target,combo) target.store:setState({role=roles[combo.selected],status="",statusError=false}) end
    local function presetChanged(target,combo)
        local id=Config.presets[combo.selected-1]
        if id then
            target:edit(function(model) model.draft=assert(Config.preset(model.draft,id)) end)
            target.store:setState({status=Config.text("configPresetDraft"),statusError=false}) combo.selected=1
        end
    end

    -- 1. Role Combo
    local rRole = slots[1]
    local roleCombo = ISComboBox:new(rRole.x, rRole.y, rRole.width, rRole.height, owner, roleChanged)
    roleCombo:initialise() owner:addChild(roleCombo)
    controls.role = roleCombo
    for _, id in ipairs(roles) do roleCombo:addOption(Config.text(id)) end

    -- 2. Smart Auto-Detect Button
    local rSmart = slots[2]
    local function smartDetectClicked(target)
        local cfg, why = SmartZoning.evaluate(target.object, target.container)
        if cfg then
            target:edit(function(model) model.draft = cfg end)
            local msg = getText("IGUI_EmberRoutesProbe_SmartZone_detected")
            target.store:setState({
                status = (msg ~= "IGUI_EmberRoutesProbe_SmartZone_detected" and msg or "Smart auto-zone: ") .. tostring(why),
                statusError = false
            })
        else
            target.store:setState({
                status = getText("IGUI_EmberRoutesProbe_SmartZone_noMatch"),
                statusError = true
            })
        end
    end
    local smartBtn = ISButton:new(rSmart.x, rSmart.y, rSmart.width, rSmart.height, getText("IGUI_EmberRoutesProbe_Filter_smartDetect"), owner, smartDetectClicked)
    smartBtn:initialise()
    smartBtn.tooltip = getText("IGUI_EmberRoutesProbe_Filter_smartDetectHint")
    Theme.button(smartBtn)
    owner:addChild(smartBtn)
    controls.smartDetect = smartBtn

    -- 3. Preset Combo
    local rPreset = slots[3]
    local presetCombo = ISComboBox:new(rPreset.x, rPreset.y, rPreset.width, rPreset.height, owner, presetChanged)
    presetCombo:initialise() owner:addChild(presetCombo)
    controls.preset = presetCombo
    presetCombo:addOption(getText("IGUI_EmberRoutesProbe_Filter_presetsBtn"))
    for _, id in ipairs(Config.presets) do presetCombo:addOption(Config.text(id)) end

    -- 4. Copy & Paste Buttons
    for i,action in ipairs({"copy","paste"}) do
        local r=slots[i+3]
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
        for _,control in ipairs({self.role,self.smartDetect,self.preset,self.copy,self.paste}) do Tooltip.clear(control) end
    end
    return controls
end
return Controls
