require "ISUI/ISButton"
local Config = require "EmberRoutesProbe/Warehouse/ContainerConfiguration"
local Theme = require "EmberRoutesProbe/UI/Theme"
local Text = require "EmberRoutesProbe/UI/Text"
local Tooltip = require "EmberRoutesProbe/UI/TooltipManager"
local SmartZoning = require "EmberRoutesProbe/Work/SmartZoning"
local Dropdown = require "EmberRoutesProbe/UI/Dropdown"

local Controls = {}
local roles = {"STORAGE", "INPUT", "EXCLUDED"}
local priorities = {1, 2, 3, 4, 5}

local function text(key)
    return getTextOrNull and (getTextOrNull("IGUI_EmberRoutesProbe_Filter_" .. key) or getTextOrNull(key)) or key
end

---@class EmberRoutesContainerConfigControls
---@field bounds table
---@field card1 table
---@field card2 table
---@field card3 table
---@field role EmberRoutesDropdown
---@field accessBtn ISButton
---@field priority EmberRoutesDropdown
---@field priorityHintLines string[]
---@field smartDetect ISButton
---@field preset EmberRoutesDropdown
---@field copy ISButton
---@field paste ISButton
---@field warning string
---@field refresh function
---@field draw function
---@field close function
---@param owner EmberRoutesStorageFilterPanel
---@param bounds {x:number, y:number, width:number, height:number}
function Controls.new(owner, bounds)
    local controls = { bounds = bounds }
    local pad = owner.pad or 10
    local fh = owner.fontHeight or 16
    local bx, by, w, h = bounds.x, bounds.y, bounds.width, bounds.height

    -- Calculate adaptive height proportions for 3 vertical cards
    local gap = math.floor(pad * 0.6)
    local c1H = fh + pad + 26 + math.floor(pad / 2) + 28 + pad
    local c2H = fh + pad + 26 + math.floor(pad / 2) + fh * 2 + pad
    local c3H = h - c1H - c2H - gap * 2
    if c3H < fh * 2 + 30 + 26 + 26 + pad * 2 then
        c3H = fh * 2 + 30 + 26 + 26 + pad * 2
    end

    controls.card1 = { x = bx, y = by, width = w, height = c1H }
    controls.card2 = { x = bx, y = by + c1H + gap, width = w, height = c2H }
    controls.card3 = { x = bx, y = by + c1H + gap + c2H + gap, width = w, height = c3H }

    -- =========================================================================
    -- CARD 1: 容器策略与权限 (Strategy & Permissions)
    -- =========================================================================
    local c1 = controls.card1
    local innerW = w - pad * 2
    local curY = c1.y + fh + pad

    -- 1.1 Role Dropdown (Encapsulated Flat 2.0)
    local function roleChanged(target, selectedRole)
        if selectedRole then
            target.store:setState({ role = selectedRole, status = "", statusError = false })
        end
    end
    local roleCombo = Dropdown:new(c1.x + pad, curY, innerW, 26, owner, roleChanged)
    roleCombo:initialise()
    local roleItems = {}
    for _, id in ipairs(roles) do
        roleItems[#roleItems + 1] = { id = id, label = Config.text(id) }
    end
    roleCombo:setOptions(roleItems, owner.store.value.role or "STORAGE")
    owner:addChild(roleCombo)
    controls.role = roleCombo
    curY = curY + 26 + math.floor(pad / 2)

    -- 1.2 Access Toggle (Public / Private)
    local function toggleAccess(target)
        target:edit(function(model)
            model.draft.private = not model.draft.private
        end)
    end
    local accessBtn = ISButton:new(c1.x + pad, curY, innerW, 28, text("publicAccess"), owner, toggleAccess)
    accessBtn:initialise()
    Theme.button(accessBtn)
    owner:addChild(accessBtn)
    controls.accessBtn = accessBtn

    -- =========================================================================
    -- CARD 2: 物流调度优先级 (Logistics Priority)
    -- =========================================================================
    local c2 = controls.card2
    curY = c2.y + fh + pad

    local function priorityChanged(target, selectedPrio)
        if selectedPrio then
            target:edit(function(model) model.draft.priority = selectedPrio end)
            target.store:setState({ status = Config.text("configPriorityUpdated"), statusError = false })
        end
    end
    local prioCombo = Dropdown:new(c2.x + pad, curY, innerW, 26, owner, priorityChanged)
    prioCombo:initialise()
    local prioItems = {}
    for _, p in ipairs(priorities) do
        prioItems[#prioItems + 1] = { id = p, label = Config.text("priority" .. p) }
    end
    prioCombo:setOptions(prioItems, owner.model.draft.priority or 3)
    owner:addChild(prioCombo)
    controls.priority = prioCombo
    controls.priorityHintLines = Text.wrapLimited(text("priorityHint"), innerW, UIFont.Small, 2)

    -- =========================================================================
    -- CARD 3: 自动化与模板 (Automation & Tools)
    -- =========================================================================
    local c3 = controls.card3
    curY = c3.y + fh + pad

    -- 3.1 Smart Auto-Detect Button
    local function smartDetectClicked(target)
        local cfg, why = SmartZoning.evaluate(target.object, target.container)
        if cfg then
            target:edit(function(model) model.draft = cfg end)
            local msg = text("SmartZone_detected")
            target.store:setState({
                status = (msg ~= "SmartZone_detected" and msg or "Smart auto-zone: ") .. tostring(why),
                statusError = false
            })
        else
            target.store:setState({
                status = text("SmartZone_noMatch"),
                statusError = true
            })
        end
    end

    local smartBtn = ISButton:new(c3.x + pad, curY, innerW, 28, text("smartDetectBtn"), owner, smartDetectClicked)
    smartBtn:initialise()
    Theme.button(smartBtn, true) -- Highlight primary accent style
    smartBtn.tooltip = text("smartDetectHint")
    owner:addChild(smartBtn)
    controls.smartDetect = smartBtn
    curY = curY + 28 + math.floor(pad / 2)

    -- 3.2 Preset Dropdown (Encapsulated Flat 2.0)
    local function presetChanged(target, selectedPreset, _, combo)
        if selectedPreset and selectedPreset ~= "" then
            target:edit(function(model) model.draft = assert(Config.preset(model.draft, selectedPreset)) end)
            target.store:setState({ status = Config.text("configPresetDraft"), statusError = false })
            combo:setSelectedId("")
        end
    end
    local presetCombo = Dropdown:new(c3.x + pad, curY, innerW, 26, owner, presetChanged)
    presetCombo:initialise()
    local presetItems = { { id = "", label = text("presetsBtn") } }
    for _, id in ipairs(Config.presets) do
        presetItems[#presetItems + 1] = { id = id, label = Config.text(id) }
    end
    presetCombo:setOptions(presetItems, "")
    owner:addChild(presetCombo)
    controls.preset = presetCombo
    curY = curY + 26 + math.floor(pad / 2)

    -- 3.3 Copy & Paste Buttons (Side by Side)
    local btnW = math.floor((innerW - pad / 2) / 2)
    local function doCopy(target)
        local result, reason = Config.copy(target.actor, target.object, target.container, target.model.draft)
        target.store:setState({ status = Config.text(reason), statusError = not result })
        controls.paste:setEnable(Config.hasClipboard(target.actor))
    end
    local function doPaste(target)
        local result, reason = Config.paste(target.actor, target.model.draft)
        if result then
            target:edit(function(model) model.draft = result end)
            reason = "configPastedDraft"
        end
        target.store:setState({ status = Config.text(reason), statusError = not result })
        controls.paste:setEnable(Config.hasClipboard(target.actor))
    end

    local copyBtn = ISButton:new(c3.x + pad, curY, btnW, 26, text("configCopy"), owner, doCopy)
    copyBtn:initialise()
    copyBtn.tooltip = text("configRulesOnly")
    Theme.button(copyBtn)
    owner:addChild(copyBtn)
    controls.copy = copyBtn

    local pasteBtn = ISButton:new(c3.x + pad + btnW + math.floor(pad / 2), curY, btnW, 26, text("configPaste"), owner, doPaste)
    pasteBtn:initialise()
    pasteBtn.tooltip = text("configRulesOnly")
    Theme.button(pasteBtn)
    owner:addChild(pasteBtn)
    controls.paste = pasteBtn

    -- Lifecycle methods
    function controls:refresh()
        self.role:setSelectedId(owner.store.value.role or "STORAGE")
        self.priority:setSelectedId(owner.model.draft.priority or 3)
        self.preset:setSelectedId("")

        local isPrivate = owner.model.draft.private == true
        self.accessBtn:setTitle(text(isPrivate and "privateAccess" or "publicAccess"))
        Theme.button(self.accessBtn, not isPrivate)

        self.paste:setEnable(Config.hasClipboard(owner.actor))
        self.warning = Config.warning(owner.model.draft, owner.store.value.role)
    end

    function controls:draw()
        local p = owner.pad or 10
        local fHeight = owner.fontHeight or 16

        -- Draw Card 1 Frame & Header
        local c1 = self.card1
        owner:drawRect(c1.x, c1.y, c1.width, c1.height, 0.45, Theme.control.r, Theme.control.g, Theme.control.b)
        owner:drawRectBorder(c1.x, c1.y, c1.width, c1.height, 0.85, Theme.border.r, Theme.border.g, Theme.border.b)
        owner:drawRect(c1.x, c1.y, c1.width, 1, 0.9, Theme.accent.r, Theme.accent.g, Theme.accent.b)
        owner:drawText(text("strategy"), c1.x + p, c1.y + p / 2, Theme.accent.r, Theme.accent.g, Theme.accent.b, 1, UIFont.Small)

        -- Draw Card 2 Frame & Header
        local c2 = self.card2
        owner:drawRect(c2.x, c2.y, c2.width, c2.height, 0.45, Theme.control.r, Theme.control.g, Theme.control.b)
        owner:drawRectBorder(c2.x, c2.y, c2.width, c2.height, 0.85, Theme.border.r, Theme.border.g, Theme.border.b)
        owner:drawRect(c2.x, c2.y, c2.width, 1, 0.9, Theme.accent.r, Theme.accent.g, Theme.accent.b)
        owner:drawText(text("priorityCard"), c2.x + p, c2.y + p / 2, Theme.accent.r, Theme.accent.g, Theme.accent.b, 1, UIFont.Small)
        for i, line in ipairs(self.priorityHintLines or {}) do
            owner:drawText(line, c2.x + p, c2.y + fHeight + p + 26 + 6 + (i - 1) * fHeight, Theme.muted.r, Theme.muted.g, Theme.muted.b, 1, UIFont.Small)
        end

        -- Draw Card 3 Frame & Header
        local c3 = self.card3
        owner:drawRect(c3.x, c3.y, c3.width, c3.height, 0.45, Theme.control.r, Theme.control.g, Theme.control.b)
        owner:drawRectBorder(c3.x, c3.y, c3.width, c3.height, 0.85, Theme.border.r, Theme.border.g, Theme.border.b)
        owner:drawRect(c3.x, c3.y, c3.width, 1, 0.9, Theme.accent.r, Theme.accent.g, Theme.accent.b)
        owner:drawText(text("automationCard"), c3.x + p, c3.y + p / 2, Theme.accent.r, Theme.accent.g, Theme.accent.b, 1, UIFont.Small)
    end

    function controls:close()
        for _, control in ipairs({self.role, self.accessBtn, self.priority, self.smartDetect, self.preset, self.copy, self.paste}) do
            Tooltip.clear(control)
        end
    end

    return controls
end

return Controls
