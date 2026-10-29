--[[
    CompactSummaryStrip.lua - EmberRoutes UI
    High-density single-line warehouse health banner.
    Displays items count, integrated container health and volume capacity load
    with dual nested sub-pills for tight meter cohesion and zero wasted space.
]]

local Layout = require "EmberRoutesProbe/UI/Layout"
local Text = require "EmberRoutesProbe/UI/Text"
local Theme = require "EmberRoutesProbe/UI/Theme"
local StatMeter = require "EmberRoutesProbe/UI/StatMeter"

local CompactSummaryStrip = {}
local methods = {}
methods.__index = methods

---Resolve a translation key; never falls back to a hardcoded language string.
---@param key string
---@return string
local function text(key)
    return getTextOrNull(key) or key
end

---Create a new compact summary strip.
---@param bounds {x:number, y:number, width:number, height:number}
---@param h number Font height
---@param p number Padding
---@return table
function CompactSummaryStrip.new(bounds, h, p)
    local tracks = {
        {grow = 1.0}, -- Section 1: Total Items & Categories
        {grow = 2.5}  -- Section 2: Unified Container & Volume Capsule (Nested Sub-Pills)
    }
    local pills = assert(Layout.axis(bounds, tracks, {gap = math.max(2, math.floor(p / 2))}))

    local self = setmetatable({
        bounds = bounds,
        pills = pills,
        fontHeight = h,
        pad = p,
        coverage = 0,
        pct = 0,
        loadedStr = "--",
        alerts = 0,
        itemsLabel = text("IGUI_EmberRoutesProbe_Settlement_summaryTotalFormat"),
        containerText = "",
        loadText = "",
        probeColor = Theme.status.READY,
        probeBg = {r = 0.08, g = 0.16, b = 0.12, a = 0.85},
        probeBorder = {r = 0.20, g = 0.50, b = 0.35, a = 0.85},
        state = "UPDATING",
        note = "",
        detailTooltip = text("IGUI_EmberRoutesProbe_Settlement_summaryMergedClickHint")
    }, methods)

    self:updateSubPills()
    return self
end

function methods:updateSubPills()
    local pct = self.pct or 0
    self.loadText = string.format(text("IGUI_EmberRoutesProbe_Settlement_subPillLoadFormat"), pct)

    if self.state == "UPDATING" then
        self.containerText = text("IGUI_EmberRoutesProbe_Settlement_subPillScanning")
        self.probeColor = Theme.gold
        self.probeBg = {r = 0.18, g = 0.14, b = 0.08, a = 0.85}
        self.probeBorder = {r = 0.55, g = 0.42, b = 0.18, a = 0.85}
    elseif self.state == "ERROR" then
        self.containerText = text("IGUI_EmberRoutesProbe_Settlement_subPillError")
        self.probeColor = Theme.status.ERROR
        self.probeBg = {r = 0.26, g = 0.10, b = 0.10, a = 0.85}
        self.probeBorder = {r = 0.70, g = 0.28, b = 0.26, a = 0.85}
    elseif self.alerts > 0 then
        self.containerText = string.format(text("IGUI_EmberRoutesProbe_Settlement_subPillContainersAlert"), self.alerts)
        self.probeColor = Theme.gold
        self.probeBg = {r = 0.20, g = 0.16, b = 0.08, a = 0.85}
        self.probeBorder = {r = 0.60, g = 0.45, b = 0.18, a = 0.85}
    else
        self.containerText = string.format(text("IGUI_EmberRoutesProbe_Settlement_subPillContainersReady"), tostring(self.loadedStr))
        self.probeColor = Theme.status.READY
        self.probeBg = {r = 0.08, g = 0.16, b = 0.12, a = 0.85}
        self.probeBorder = {r = 0.20, g = 0.50, b = 0.35, a = 0.85}
    end
end

---Update counts and categories
---@param values table? {items:number, loaded:string|number, unloaded:number, missing:number, limited:number, private:number, containers:number}
---@param totalTypes number? Unique item categories count
function methods:setValues(values, totalTypes)
    local items = values and values.items or values and values.instanceCount or "--"
    local types = totalTypes or "--"

    -- 1. Format Items Label
    self.itemsLabel = string.format(text("IGUI_EmberRoutesProbe_Settlement_summaryTotalFormat"), tostring(items), tostring(types))

    -- 2. Probe & Container Alerts
    self.loadedStr = values and (values.loaded or values.containers) or "--"
    local unloaded = values and tonumber(values.unloaded) or 0
    local missing = values and tonumber(values.missing) or 0
    local limited = values and tonumber(values.limited) or 0
    self.alerts = unloaded + missing + limited

    self:updateSubPills()
end

---Update capacity ratio
---@param used number?
---@param total number?
function methods:setCoverage(used, total)
    if used and total and total > 0 then
        self.coverage = math.max(0, math.min(1, used / total))
        self.pct = math.floor(self.coverage * 100)
    else
        self.coverage = 0
        self.pct = 0
    end
    self:updateSubPills()
end

---Update status code and note
---@param state string
---@param note string?
function methods:setStatus(state, note)
    self.state = state
    self.note = note or ""
    self:updateSubPills()
end

---Zero-GC drawing of the pills and nested sub-pills
---@param owner ISPanel
function methods:draw(owner)
    local h, p = self.fontHeight, self.pad
    local p1, p2 = self.pills[1], self.pills[2]
    local textY = math.floor((p1.height - h) / 2)

    -- Pill 1: Total Items & Categories
    Theme.rect(owner, p1.x, p1.y, p1.width, p1.height, Theme.panel)
    Theme.rect(owner, p1.x, p1.y, p1.width, p1.height, Theme.border, true)
    Theme.rect(owner, p1.x, p1.y, math.max(2, math.floor(p / 4)), p1.height, Theme.accent)
    Theme.text(owner, self.itemsLabel, p1.x + p, p1.y + textY, Theme.gold)

    -- Pill 2: Master Container & Volume Capsule (Clickable, Outer Frame)
    Theme.rect(owner, p2.x, p2.y, p2.width, p2.height, self.probeBg)
    Theme.rect(owner, p2.x, p2.y, p2.width, p2.height, self.probeBorder, true)

    local subPad = math.max(2, math.floor(p / 3))
    local subY = p2.y + subPad
    local subH = p2.height - subPad * 2
    local gap = math.max(4, math.floor(p / 2))
    local innerW = p2.width - subPad * 2

    -- Sub-pill inner recessed styling
    local subBg = {r = 0.04, g = 0.08, b = 0.06, a = 0.75}
    local subBorder = {r = self.probeBorder.r * 0.75, g = self.probeBorder.g * 0.75, b = self.probeBorder.b * 0.75, a = 0.70}

    local tm = getTextManager()
    local cTextW = tm and tm.MeasureStringX and tm:MeasureStringX(UIFont.Small, self.containerText) or (#self.containerText * 7)
    local sub1W = math.max(cTextW + p * 2, math.floor(innerW * 0.40))
    local sub1X = p2.x + subPad

    -- Nested Sub-Pill A: Container Readiness
    Theme.rect(owner, sub1X, subY, sub1W, subH, subBg)
    Theme.rect(owner, sub1X, subY, sub1W, subH, subBorder, true)
    local cTextX = sub1X + math.floor((sub1W - cTextW) / 2)
    Theme.text(owner, self.containerText, cTextX, subY + math.floor((subH - h) / 2), self.probeColor)

    -- Nested Sub-Pill B: Volume Load & Tight Progress Meter
    local sub2X = sub1X + sub1W + gap
    local sub2W = p2.x + p2.width - subPad - sub2X
    if sub2W > 40 then
        Theme.rect(owner, sub2X, subY, sub2W, subH, subBg)
        Theme.rect(owner, sub2X, subY, sub2W, subH, subBorder, true)

        local lTextW = tm and tm.MeasureStringX and tm:MeasureStringX(UIFont.Small, self.loadText) or (#self.loadText * 7)
        local lTextX = sub2X + p
        local lTextY = subY + math.floor((subH - h) / 2)
        local lColor = (self.pct >= 80) and Theme.gold or Theme.textColor
        Theme.text(owner, self.loadText, lTextX, lTextY, lColor)

        -- Progress bar directly anchored right next to load text, filling the remainder of sub-pill B
        local meterX = lTextX + lTextW + math.floor(p / 2)
        local meterW = math.max(16, sub2X + sub2W - meterX - p)
        local meterH = math.max(6, math.floor(h * 0.55))
        local meterY = subY + math.floor((subH - meterH) / 2)

        if meterW >= 16 then
            StatMeter.draw(owner, meterX, meterY, meterW, meterH, self.coverage, {
                mode = "load",
                threshold = 0.8,
                showPercent = false
            })
        end
    end
end

return CompactSummaryStrip
