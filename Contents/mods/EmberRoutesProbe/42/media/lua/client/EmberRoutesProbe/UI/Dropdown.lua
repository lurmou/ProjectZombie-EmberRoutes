--[[
    Dropdown.lua - EmberRoutes UI Infrastructure
    Encapsulated Flat 2.0 dropdown select component.
    Adheres to Theme palette, Flat 2.0 vector chevron, zero-GC rendering,
    and simplifies option population and selection retrieval.
]]

require "ISUI/ISComboBox"
local Theme = require "EmberRoutesProbe/UI/Theme"
local Visual = require "EmberRoutesProbe/UI/StatusVisual"

---@class EmberRoutesDropdown: ISComboBox
---@field placeholder string
local Dropdown = ISComboBox:derive("EmberRoutesDropdown")

---@param x number
---@param y number
---@param width number
---@param height number
---@param target any?
---@param onChange function? Callback signature: function(target, selectedData, selectedText, combo)
---@return EmberRoutesDropdown
function Dropdown:new(x, y, width, height, target, onChange)
    local o = ISComboBox.new(self, x, y, width, height, target, nil)
    setmetatable(o, self)
    self.__index = self

    o.userOnChange = onChange
    o.onChange = function(cbTarget, combo)
        local data = combo:getSelectedData()
        local txt = combo:getOptionText(combo.selected)
        if o.userOnChange then
            o.userOnChange(cbTarget, data, txt, combo)
        end
    end

    Theme.combo(o)
    return o
end

function Dropdown:initialise()
    ISComboBox.initialise(self)
    Theme.combo(self)
end

function Dropdown:showPopup()
    ISComboBox.showPopup(self)
    if self.popup then
        Theme.list(self.popup)
    end
end

---Closes and cleans up the popup dropdown menu safely.
function Dropdown:closePopup()
    if self.expanded then
        if self.hidePopup then
            self:hidePopup()
        end
        self.expanded = false
    end
end

---Adds an option with associated data payload, guaranteeing safe fallback.
---@param label string
---@param data any
function Dropdown:addOptionWithData(label, data)
    if ISComboBox.addOptionWithData then
        ISComboBox.addOptionWithData(self, label, data)
    else
        self.options = self.options or {}
        table.insert(self.options, { text = label, data = data })
    end
end

---Sets options array of {id=any, label=string} or string list.
---@param items table[] Array of {id:any, label:string} or strings
---@param selectedId any? ID of the option to select initially
function Dropdown:setOptions(items, selectedId)
    self:clear()
    local targetIdx = (items and #items > 0) and 1 or 0
    for i, it in ipairs(items or {}) do
        local label, id
        if type(it) == "table" then
            label = it.label or tostring(it.id)
            if it.id ~= nil then
                id = it.id
            else
                id = it
            end
        else
            label = tostring(it)
            id = it
        end
        self:addOptionWithData(label, id)
        if selectedId ~= nil and id == selectedId then
            targetIdx = i
        end
    end
    self.selected = targetIdx
end

---Returns the text label of the option at the given index.
---@param index number
---@return string
function Dropdown:getOptionText(index)
    if not self.options or not index or index <= 0 or index > #self.options then return "" end
    local opt = self.options[index]
    if type(opt) == "table" then
        return opt.text or ""
    elseif type(opt) == "string" then
        return opt
    end
    if ISComboBox.getOptionText then
        return ISComboBox.getOptionText(self, index) or ""
    end
    return ""
end

---Returns the data associated with option at the given index.
---@param index number
---@return any
function Dropdown:getOptionData(index)
    if not self.options or not index or index <= 0 or index > #self.options then return nil end
    local opt = self.options[index]
    if type(opt) == "table" and opt.data ~= nil then
        return opt.data
    end
    if ISComboBox.getOptionData then
        return ISComboBox.getOptionData(self, index)
    end
    return nil
end

---Returns the data associated with the currently selected option.
---@return any
function Dropdown:getSelectedData()
    if not self.selected or self.selected <= 0 then return nil end
    return self:getOptionData(self.selected)
end

---Selects the option matching the given data ID.
---@param id any
---@return boolean
function Dropdown:setSelectedId(id)
    if not self.options then return false end
    for i = 1, #self.options do
        if self:getOptionData(i) == id then
            self.selected = i
            return true
        end
    end
    return false
end

---Cycles to the next option (useful for gamepad navigation).
function Dropdown:selectNext()
    if not self.options or #self.options == 0 then return end
    self.selected = (self.selected % #self.options) + 1
    if self.onChange then
        self.onChange(self.target, self)
    end
end

---Cycles to the previous option (useful for gamepad navigation).
function Dropdown:selectPrev()
    if not self.options or #self.options == 0 then return end
    self.selected = (self.selected - 2 + #self.options) % #self.options + 1
    if self.onChange then
        self.onChange(self.target, self)
    end
end

function Dropdown:prerender()
    local isHover = self:isMouseOver()
    local isExpanded = self.expanded == true

    -- 1. Control background
    local bg = isExpanded and Theme.selected or (isHover and Theme.hover or Theme.control)
    self:drawRect(0, 0, self.width, self.height, bg.a or 1.0, bg.r, bg.g, bg.b)

    -- 2. Outline (accent border on hover / open)
    local bc = (isExpanded or isHover) and Theme.accent or Theme.border
    self:drawRectBorder(0, 0, self.width, self.height, bc.a or 0.90, bc.r, bc.g, bc.b)

    -- 3. Selected Option Label
    local fontHgt = getTextManager():getFontHeight(self.font or UIFont.Small)
    local textY = math.floor((self.height - fontHgt) / 2)
    local label = self:getOptionText(self.selected)
    if label and label ~= "" then
        local textColor = (isExpanded or isHover) and { r = 1, g = 1, b = 1, a = 1 } or Theme.textColor
        self:drawText(label, 8, textY, textColor.r, textColor.g, textColor.b, textColor.a or 1, self.font or UIFont.Small)
    end

    -- 4. Flat 2.0 Vector Chevron Icon (Never Emoji)
    local isize = 12
    local iconX = self.width - isize - 8
    local iconY = math.floor((self.height - isize) / 2)
    local chevronColor = (isExpanded or isHover) and Theme.accent or Theme.muted
    Visual.icon(self, iconX, iconY, isize, isExpanded and "chevronUp" or "chevronDown", chevronColor)
end

return Dropdown
