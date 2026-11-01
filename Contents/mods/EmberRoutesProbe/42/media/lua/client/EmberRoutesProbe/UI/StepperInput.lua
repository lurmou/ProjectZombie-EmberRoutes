--[[
    StepperInput.lua - EmberRoutes UI
    Ergonomic numeric stepper input widget.
    Encapsulates [-10] [-1] [ Value ] [+1] [+10] with mouse-wheel support,
    bounds clamping, direct typing, and zero layout boilerplate.
]]

require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISTextEntryBox"
local Layout = require "EmberRoutesProbe/UI/Layout"
local Theme = require "EmberRoutesProbe/UI/Theme"

---@class EmberRoutesStepperInput:ISPanel
---@field fontHeight number
---@field pad number
---@field value number
---@field min number
---@field max number
---@field steps number[]
---@field entry ISTextEntryBox
---@field stepButtons ISButton[]
---@field onChange fun(value:number, widget:EmberRoutesStepperInput)
local StepperInput = ISPanel:derive("EmberRoutesStepperInput")

---@param x number
---@param y number
---@param width number
---@param height number
---@param initialValue number?
---@param min number?
---@param max number?
---@param steps number[]? Array of 4 deltas, e.g. {-5, -1, 1, 5}
---@param onChange fun(value:number, widget:EmberRoutesStepperInput)?
---@return EmberRoutesStepperInput
function StepperInput:new(x, y, width, height, initialValue, min, max, steps, onChange)
    local o = ISPanel.new(self, x, y, width, height)
    o.background = false
    o.fontHeight = getTextManager():getFontHeight(UIFont.Small)
    o.pad = math.ceil(o.fontHeight * 0.4)
    o.min = min or 1
    o.max = max or 9999
    o.value = math.max(o.min, math.min(o.max, initialValue or o.min))
    o.steps = steps or {-5, -1, 1, 5}
    o.onChange = onChange or function() end
    o.stepButtons = {}
    o:initialise()
    return o
end

function StepperInput:initialise()
    ISPanel.initialise(self)
end

function StepperInput:createChildren()
    ISPanel.createChildren(self)
    local h, p = self.fontHeight, self.pad
    local btnW = math.max(24, math.floor(h * 2.2))

    -- 5-part layout: [Step 1] [Step 2] [ Center Entry ] [Step 3] [Step 4]
    local tracks = {
        {basis = btnW},
        {basis = btnW},
        {grow = 1},
        {basis = btnW},
        {basis = btnW}
    }
    local cols = assert(Layout.axis({x = 0, y = 0, width = self.width, height = self.height},
        tracks, {gap = math.max(2, math.floor(p / 3))}))

    -- Decrement Button 1
    local d1 = self.steps[1] or -5
    local b1 = ISButton:new(cols[1].x, cols[1].y, cols[1].width, cols[1].height, tostring(d1), self, function()
        self:applyDelta(d1)
    end)
    b1:initialise()
    Theme.button(b1)
    self:addChild(b1)
    self.stepButtons[1] = b1

    -- Decrement Button 2
    local d2 = self.steps[2] or -1
    local b2 = ISButton:new(cols[2].x, cols[2].y, cols[2].width, cols[2].height, (d2 > 0 and "+" or "") .. tostring(d2), self, function()
        self:applyDelta(d2)
    end)
    b2:initialise()
    Theme.button(b2)
    self:addChild(b2)
    self.stepButtons[2] = b2

    -- Center Input
    local entryBox = ISTextEntryBox:new(tostring(self.value), cols[3].x, cols[3].y, cols[3].width, cols[3].height)
    entryBox:initialise()
    entryBox:setOnlyNumbers(true)
    entryBox.target = self
    entryBox.backgroundColor = Theme.panel
    entryBox.borderColor = Theme.border
    entryBox.onTextChangeFunction = function()
        if self.syncing then return end
        local text = entryBox:getText()
        local n = tonumber(text)
        if n then
            local clamped = math.max(self.min, math.min(self.max, n))
            self.value = clamped
            if self.onChange then self.onChange(self.value, self) end
        else
            self.value = nil
            if self.onChange then self.onChange(nil, self) end
        end
    end
    self:addChild(entryBox)
    self.entry = entryBox

    -- Increment Button 1
    local d3 = self.steps[3] or 1
    local b3 = ISButton:new(cols[4].x, cols[4].y, cols[4].width, cols[4].height, (d3 > 0 and "+" or "") .. tostring(d3), self, function()
        self:applyDelta(d3)
    end)
    b3:initialise()
    Theme.button(b3)
    self:addChild(b3)
    self.stepButtons[3] = b3

    -- Increment Button 2
    local d4 = self.steps[4] or 5
    local b4 = ISButton:new(cols[5].x, cols[5].y, cols[5].width, cols[5].height, (d4 > 0 and "+" or "") .. tostring(d4), self, function()
        self:applyDelta(d4)
    end)
    b4:initialise()
    Theme.button(b4)
    self:addChild(b4)
    self.stepButtons[4] = b4
end

function StepperInput:applyDelta(delta)
    local cur = tonumber(self.entry:getText()) or self.value or self.min
    local nextVal = math.max(self.min, math.min(self.max, cur + delta))
    self:setValue(nextVal)
    if self.onChange then
        self.onChange(self.value, self)
    end
end

function StepperInput:setValue(n)
    local clamped = math.max(self.min, math.min(self.max, tonumber(n) or self.min))
    self.value = clamped
    if self.entry then
        self.syncing = true
        self.entry:setText(tostring(clamped))
        self.syncing = false
    end
end

function StepperInput:getValue()
    return self.value
end

function StepperInput:onMouseWheel(del)
    -- Scrolling up (del < 0) increments, scrolling down (del > 0) decrements
    local delta = (del < 0) and 1 or -1
    self:applyDelta(delta)
    return true
end

return StepperInput
