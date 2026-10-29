--[[
    StatMeter.lua - EmberRoutes UI
    High-density physiological, progress, and resource capacity gauge.
    Inspired by Frostpunk gauges, RimWorld colonist vitals, and State of Decay stamina caps.
    Provides both an ISPanel component and a static zero-GC draw function.
]]

require "ISUI/ISPanel"
local Theme = require "EmberRoutesProbe/UI/Theme"

---@class EmberRoutesStatMeter:ISPanel
---@field fontHeight number
---@field pad number
---@field fraction number
---@field capFraction number?
---@field mode string "progress"|"health"|"load"|"custom"
---@field customColor table?
---@field threshold number?
---@field label string?
---@field labelW number
---@field fillW number
---@field capW number
---@field activeColor table
local StatMeter = ISPanel:derive("EmberRoutesStatMeter")

local COLOR_GREEN = {r = 0.35, g = 0.88, b = 0.60, a = 1.0}
local COLOR_YELLOW = {r = 1.00, g = 0.78, b = 0.25, a = 1.0}
local COLOR_RED = {r = 1.00, g = 0.42, b = 0.38, a = 1.0}
local COLOR_BLUE = {r = 0.25, g = 0.75, b = 1.00, a = 1.0}
local COLOR_TROUGH = {r = 0.05, g = 0.07, b = 0.09, a = 0.95}
local COLOR_BORDER = {r = 0.22, g = 0.28, b = 0.34, a = 0.90}
local COLOR_CAP = {r = 0.28, g = 0.15, b = 0.15, a = 0.75}

local function resolveColor(mode, fraction, customColor)
    if customColor then return customColor end
    local f = math.max(0, math.min(1, fraction or 0))
    if mode == "health" then
        -- High is good
        if f > 0.60 then return COLOR_GREEN
        elseif f > 0.25 then return COLOR_YELLOW
        else return COLOR_RED end
    elseif mode == "load" or mode == "danger" or mode == "fatigue" then
        -- Low is good, high is danger
        if f < 0.60 then return COLOR_GREEN
        elseif f < 0.85 then return COLOR_YELLOW
        else return COLOR_RED end
    else
        -- Progress mode
        if f >= 1.0 then return COLOR_GREEN
        else return COLOR_BLUE end
    end
end

---Static zero-GC draw function for embedding inside list rows or custom prerender loops.
---@param owner ISPanel
---@param x number
---@param y number
---@param width number
---@param height number
---@param fraction number 0.0 to 1.0
---@param opts table? {mode="progress"|"health"|"load"|"custom", color=table, capFraction=number, threshold=number, label=string, labelW=number, showPercent=boolean}
function StatMeter.draw(owner, x, y, width, height, fraction, opts)
    opts = opts or {}
    local f = math.max(0, math.min(1, fraction or 0))
    local mode = opts.mode or "progress"
    local col = resolveColor(mode, f, opts.color)

    -- 1. Dark Trough
    Theme.rect(owner, x, y, width, height, COLOR_TROUGH)

    -- 2. Fill Bar
    local fillW = math.max(0, math.floor(width * f))
    if fillW > 0 then
        Theme.rect(owner, x, y, fillW, height, col)
    end

    -- 3. Stamina/Capacity Lock (Cap Region)
    if opts.capFraction and opts.capFraction < 1.0 then
        local capStart = math.floor(width * math.max(0, opts.capFraction))
        local capWidth = width - capStart
        if capWidth > 0 then
            Theme.rect(owner, x + capStart, y, capWidth, height, COLOR_CAP)
            -- Shaded hatch lines (State of Decay style)
            local step = math.max(4, math.floor(height * 0.8))
            for hx = capStart, width, step do
                Theme.rect(owner, x + hx, y, 1, height, {r=0.45, g=0.20, b=0.20, a=0.8})
            end
        end
    end

    -- 4. Threshold Marker
    if opts.threshold and opts.threshold > 0 and opts.threshold < 1.0 then
        local tx = x + math.floor(width * opts.threshold)
        Theme.rect(owner, tx, y - 1, 2, height + 2, COLOR_RED)
    end

    -- 5. Border Frame
    Theme.rect(owner, x, y, width, height, COLOR_BORDER, true)

    -- 6. Label Overlay
    local text = opts.label
    if not text and opts.showPercent then
        text = math.floor(f * 100) .. "%"
    end
    if text and text ~= "" then
        local tm = getTextManager()
        local tw = opts.labelW or tm:MeasureStringX(UIFont.Small, text)
        local h = tm:getFontHeight(UIFont.Small)
        local tx = x + math.floor((width - tw) / 2)
        local ty = y + math.floor((height - h) / 2)

        -- Micro shadow for maximum readability
        Theme.text(owner, text, tx + 1, ty + 1, {r = 0, g = 0, b = 0, a = 0.85})
        Theme.text(owner, text, tx, ty, Theme.textColor)
    end
end

---Create an interactive or self-contained ISPanel StatMeter.
---@param x number
---@param y number
---@param width number
---@param height number
---@param opts table?
---@return EmberRoutesStatMeter
function StatMeter:new(x, y, width, height, opts)
    opts = opts or {}
    local o = ISPanel.new(self, x, y, width, height)
    o.background = false
    o.fontHeight = getTextManager():getFontHeight(UIFont.Small)
    o.pad = math.ceil(o.fontHeight * 0.4)
    o.fraction = opts.fraction or 0
    o.capFraction = opts.capFraction
    o.mode = opts.mode or "progress"
    o.customColor = opts.color
    o.threshold = opts.threshold
    o.label = opts.label
    o.labelW = 0
    o.fillW = 0
    o.activeColor = resolveColor(o.mode, o.fraction, o.customColor)
    o:initialise()
    o:recompute()
    return o
end

function StatMeter:initialise()
    ISPanel.initialise(self)
end

function StatMeter:recompute()
    local f = math.max(0, math.min(1, self.fraction or 0))
    self.fillW = math.floor(self.width * f)
    self.activeColor = resolveColor(self.mode, f, self.customColor)
    if self.label and self.label ~= "" then
        self.labelW = getTextManager():MeasureStringX(UIFont.Small, self.label)
    else
        self.labelW = 0
    end
end

---Update meter value and presentation.
---@param fraction number 0.0 to 1.0
---@param label string?
---@param capFraction number?
function StatMeter:setValue(fraction, label, capFraction)
    self.fraction = fraction or 0
    if label ~= nil then self.label = label end
    if capFraction ~= nil then self.capFraction = capFraction end
    self:recompute()
end

function StatMeter:prerender()
    ISPanel.prerender(self)
    StatMeter.draw(self, 0, 0, self.width, self.height, self.fraction, {
        mode = self.mode,
        color = self.customColor,
        capFraction = self.capFraction,
        threshold = self.threshold,
        label = self.label,
        labelW = self.labelW
    })
end

return StatMeter
