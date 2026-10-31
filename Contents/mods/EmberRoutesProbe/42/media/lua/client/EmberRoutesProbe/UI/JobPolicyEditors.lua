--[[
    JobPolicyEditors.lua - EmberRoutes UI
    Standard reusable editor widgets for job policy fields.
    Each editor adheres to the contract:
        create(parent, bounds, fieldDef, initialValue, onChanged, context) -> widget
--]]

require 'ISUI/ISPanel'
require 'ISUI/ISButton'
require 'ISUI/ISComboBox'
local Theme = require 'EmberRoutesProbe/UI/Theme'
local Zones = require 'EmberRoutesProbe/SettlementZones'
local LifeZoneSelector = require 'EmberRoutesProbe/UI/LifeZoneSelector'

local Editors = {}
local Text=require 'EmberRoutesProbe/UI/Text'
-- Measured rows are used both by the form and by its controls.
function Editors.flow(field,width,h,p)
    local rows=field.tags or field.options or {}
    local layout={} local x,y=0,0 local bh=math.floor(h*1.5)
    for i,row in ipairs(rows) do
        local label=row.label and getTextOrNull(row.label) or row.id or row.value
        local prefix=field.tags and '[V] ' or ''
        local w=math.min(width,math.max(bh,getTextManager():MeasureStringX(UIFont.Small,prefix..label)+p*3))
        if x>0 and x+w>width then x=0 y=y+bh+p end
        layout[i]={x=x,y=y,width=w,height=bh,label=label} x=x+w+p
    end
    return layout,y+bh
end
function Editors.height(field,width,h,p)
    if field.editor=='tag_chips' or field.editor=='enum_tabs' then
        local _,height=Editors.flow(field,width,h,p) return height
    end
    return math.floor(h*1.5)
end

---1. Toggle / Boolean Switch Editor
Editors.toggle = {
    create = function(parent, bounds, fieldDef, initialValue, onChanged, context)
        local h = parent.fontHeight or 18
        local val = initialValue == true
        local btn = ISButton:new(bounds.x, bounds.y, bounds.width, bounds.height, "", parent, nil)
        btn:initialise()
        btn.policyValue = val

        local function updateBtnText()
            local textKey = btn.policyValue and "IGUI_EmberRoutesProbe_Policy_enabled" or "IGUI_EmberRoutesProbe_Policy_disabled"
            btn.title = getText(textKey)
            if btn.policyValue then
                Theme.button(btn, true)
            else
                Theme.button(btn, false)
            end
        end
        updateBtnText()

        btn.onclick = function()
            btn.policyValue = not btn.policyValue
            updateBtnText()
            onChanged(fieldDef.key, btn.policyValue)
        end

        parent:addChild(btn)
        return btn
    end
}

---2. Slider / Stepper Numeric Editor
Editors.slider = {
    create = function(parent, bounds, fieldDef, initialValue, onChanged, context)
        local h = parent.fontHeight or 18
        local p = parent.pad or 4
        local minVal = fieldDef.min or 0
        local maxVal = fieldDef.max or 100
        local stepVal = fieldDef.step or 1
        local unit = fieldDef.unit and getTextOrNull("IGUI_EmberRoutesProbe_Unit_" .. fieldDef.unit) or (fieldDef.unit or "")

        local panel = ISPanel:new(bounds.x, bounds.y, bounds.width, bounds.height)
        panel:initialise()
        panel.background = false
        panel.policyValue = type(initialValue) == 'number' and initialValue or minVal

        local btnW = math.max(26, math.floor(h * 1.8))
        local valW = bounds.width - (btnW * 2 + p * 2)

        local btnMinus = ISButton:new(0, 0, btnW, bounds.height, "-", panel, nil)
        btnMinus:initialise()
        Theme.button(btnMinus, false)
        panel:addChild(btnMinus)

        local valDisplay = ISPanel:new(btnW + p, 0, valW, bounds.height)
        valDisplay:initialise()
        valDisplay.background = false
        panel:addChild(valDisplay)

        local btnPlus = ISButton:new(btnW + p + valW + p, 0, btnW, bounds.height, "+", panel, nil)
        btnPlus:initialise()
        Theme.button(btnPlus, false)
        panel:addChild(btnPlus)

        valDisplay.prerender = function(self)
            ISPanel.prerender(self)
            Theme.rect(self, 0, 0, self.width, self.height, Theme.panel)
            Theme.rect(self, 0, 0, self.width, self.height, Theme.border, true)
            local txt = tostring(panel.policyValue) .. (unit ~= "" and (" " .. unit) or "")
            local tw = getTextManager():MeasureStringX(UIFont.Small, txt)
            Theme.text(self, txt, (self.width - tw) / 2, (self.height - h) / 2, Theme.textColor)
        end

        btnMinus.onclick = function()
            local nv = math.max(minVal, panel.policyValue - stepVal)
            if nv ~= panel.policyValue then
                panel.policyValue = nv
                onChanged(fieldDef.key, panel.policyValue)
            end
        end

        btnPlus.onclick = function()
            local nv = math.min(maxVal, panel.policyValue + stepVal)
            if nv ~= panel.policyValue then
                panel.policyValue = nv
                onChanged(fieldDef.key, panel.policyValue)
            end
        end

        parent:addChild(panel)
        return panel
    end
}

---3. Settlement Zone Dropdown Editor
Editors.zone_dropdown = {
    create = function(parent, bounds, fieldDef, initialValue, onChanged, context)
        local h = parent.fontHeight or 18
        local p = parent.pad or 4
        local settlementId = context and context.settlementId
        local actor = context and context.actor

        local panel = ISPanel:new(bounds.x, bounds.y, bounds.width, bounds.height)
        panel:initialise()
        panel.background = false

        local btnNewW = math.max(68, math.floor(h * 4.5))
        local comboW = bounds.width - btnNewW - p

        local combo = ISComboBox:new(0, 0, comboW, bounds.height, panel, nil)
        combo:initialise()
        panel:addChild(combo)

        local btnNew = ISButton:new(comboW + p, 0, btnNewW, bounds.height, getText("IGUI_EmberRoutesProbe_Policy_newZone"), panel, nil)
        btnNew:initialise()
        Theme.button(btnNew, false)
        panel:addChild(btnNew)

        local currentVal = initialValue or ""

        local function populateCombo()
            combo:clear()
            -- Option 1: None / Default
            combo:addOptionWithData(getText("IGUI_EmberRoutesProbe_Policy_zoneNone"), "")
            local selIndex = 1
            if settlementId then
                local zones = Zones.list(settlementId) or {}
                for i, zone in ipairs(zones) do
                    combo:addOptionWithData(zone.name, zone.id)
                    if zone.id == currentVal then
                        selIndex = i + 1
                    end
                end
            end
            combo.selected = selIndex
        end

        populateCombo()

        combo.onChange = function()
            local opt = combo:getOptionData(combo.selected)
            currentVal = opt or ""
            onChanged(fieldDef.key, currentVal)
        end

        btnNew.onclick = function()
            if actor and settlementId then
                local labelKey = fieldDef.label or ""
                local labelText = getTextOrNull(labelKey) or labelKey
                local defaultName = labelText
                local title = getText('IGUI_EmberRoutesProbe_Policy_zoneCreate',defaultName)

                LifeZoneSelector.open(actor, settlementId, nil, {
                    title = title,
                    defaultName = defaultName,
                    isWorkZone = true,
                    onSaved = function(newZone)
                        if newZone and newZone.id then
                            currentVal = newZone.id
                            populateCombo()
                            onChanged(fieldDef.key, currentVal)
                        end
                    end,
                })
            end
        end

        local lastRev = Zones.revision()
        panel.prerender = function(self)
            ISPanel.prerender(self)
            local curRev = Zones.revision()
            if curRev ~= lastRev then
                lastRev = curRev
                populateCombo()
            end
        end

        parent:addChild(panel)
        return panel
    end
}

---4. Segmented Radio Tabs (Enum Single Selection)
Editors.enum_tabs = {
    create = function(parent, bounds, fieldDef, initialValue, onChanged, context)
        local h = parent.fontHeight or 18
        local p = parent.pad or 4
        local options = fieldDef.options or {}
        local count = #options
        if count == 0 then return nil end

        local panel = ISPanel:new(bounds.x, bounds.y, bounds.width, bounds.height)
        panel:initialise()
        panel.background = false
        panel.selectedValue = initialValue or (options[1] and options[1].value)

        local flow=Editors.flow(fieldDef,bounds.width,h,p)
        local buttons = {}

        local function refreshButtons()
            for _, item in ipairs(buttons) do
                local isSel = item.val == panel.selectedValue
                Theme.button(item.btn, isSel)
            end
        end

        for i, opt in ipairs(options) do
            local r=flow[i]
            local bx,bw=r.x,r.width
            local label = opt.label and getTextOrNull(opt.label) or opt.value
            local btn = ISButton:new(bx,r.y,bw,r.height,Text.wrapLimited(label,bw-p*2,UIFont.Small,1)[1],panel,nil)
            btn.tooltip=label
            btn:initialise()
            local val = opt.value
            btn.onclick = function()
                if panel.selectedValue ~= val then
                    panel.selectedValue = val
                    refreshButtons()
                    onChanged(fieldDef.key, val)
                end
            end
            panel:addChild(btn)
            buttons[#buttons + 1] = { btn = btn, val = val }
        end

        refreshButtons()
        parent:addChild(panel)
        return panel
    end
}

---5. Multi-Select Category Chips (Tag Matrix)
Editors.tag_chips = {
    create = function(parent, bounds, fieldDef, initialValue, onChanged, context)
        local h = parent.fontHeight or 18
        local p = parent.pad or 4
        local tags = fieldDef.tags or {}
        local count = #tags
        if count == 0 then return nil end

        local panel = ISPanel:new(bounds.x, bounds.y, bounds.width, bounds.height)
        panel:initialise()
        panel.background = false

        -- Clone initialValue mapping: [tagId] = boolean
        local state = {}
        if type(initialValue) == 'table' then
            for k, v in pairs(initialValue) do state[k] = v end
        end
        for _, t in ipairs(tags) do
            if state[t.id] == nil then
                state[t.id] = (t.default ~= false) -- Default true unless specified
            end
        end

        local flow=Editors.flow(fieldDef,bounds.width,h,p)
        local buttons = {}

        local function getChipText(tagDef)
            local isEnabled = state[tagDef.id] == true
            local label = tagDef.label and getTextOrNull(tagDef.label) or tagDef.id
            return (isEnabled and "[V] " or "[X] ") .. label
        end

        local function refreshChips()
            for _, item in ipairs(buttons) do
                local isEnabled = state[item.tag.id] == true
                local label=getChipText(item.tag)
                item.btn.title = Text.wrapLimited(label,item.btn.width-p*2,UIFont.Small,1)[1]
                item.btn.tooltip=label
                Theme.button(item.btn, isEnabled)
            end
        end

        for i, tag in ipairs(tags) do
            local r=flow[i]
            local btn = ISButton:new(r.x,r.y,r.width,r.height,"",panel,nil)
            btn:initialise()
            local currentTag = tag
            btn.onclick = function()
                state[currentTag.id] = not state[currentTag.id]
                refreshChips()
                -- Pass shallow copy of state table
                local out = {}
                for k, v in pairs(state) do out[k] = v end
                onChanged(fieldDef.key, out)
            end
            panel:addChild(btn)
            buttons[#buttons + 1] = { btn = btn, tag = tag }
        end

        refreshChips()
        parent:addChild(panel)
        return panel
    end
}

---Get an editor definition by type name
function Editors.get(editorType)
    return Editors[editorType] or Editors.toggle
end

return Editors
