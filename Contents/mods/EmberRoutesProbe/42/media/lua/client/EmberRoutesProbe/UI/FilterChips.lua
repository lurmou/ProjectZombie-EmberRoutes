--[[
    FilterChips.lua - EmberRoutes UI
    High-ergonomic horizontal toggle chips (capsules).
    Replaces bulky ISComboBox dropdowns with 1-click tactile filter chips.
    Zero-GC rendering, dynamic typography, responsive hover & alert badges.
]]

require "ISUI/ISPanel"
local Theme = require "EmberRoutesProbe/UI/Theme"
local Tooltip = require "EmberRoutesProbe/UI/TooltipAnchor"

---@class EmberRoutesFilterChips:ISPanel
---@field fontHeight number
---@field pad number
---@field options table[]
---@field chips table[]
---@field selectedId string?
---@field hoveredIndex number?
---@field onSelect fun(id:string, chip:table, widget:EmberRoutesFilterChips)
local FilterChips = ISPanel:derive("EmberRoutesFilterChips")

---@param x number
---@param y number
---@param width number
---@param height number
---@param onSelect fun(id:string, chip:table, widget:EmberRoutesFilterChips)?
---@return EmberRoutesFilterChips
function FilterChips:new(x, y, width, height, onSelect)
    local o = ISPanel.new(self, x, y, width, height)
    o.background = false
    o.fontHeight = getTextManager():getFontHeight(UIFont.Small)
    o.pad = math.ceil(o.fontHeight * 0.4)
    o.options = {}
    o.chips = {}
    o.selectedId = nil
    o.hoveredIndex = nil
    o.onSelect = onSelect or function() end
    o.gap = 4
    o:initialise()
    return o
end

function FilterChips:initialise()
    ISPanel.initialise(self)
end

---Set or update chip options with zero-GC cached coordinates.
---@param options table[] Array of {id=string, label=string, count=number?, alert=boolean?, glyph=string?, tooltip=string?}
---@param selectedId string?
function FilterChips:setOptions(options, selectedId)
    self.options = options or {}
    self.selectedId = selectedId or self.selectedId or (self.options[1] and self.options[1].id)
    self.chips = {}

    local h, p = self.fontHeight, self.pad
    local gap = self.gap or 4
    local tm = getTextManager()

    -- 1. Measure raw dimensions
    local totalMeasuredW = 0
    local rawChips = {}
    for i, opt in ipairs(self.options) do
        local label = opt.label or opt.id
        local labelW = tm:MeasureStringX(UIFont.Small, label)
        local countStr = opt.count ~= nil and tostring(opt.count) or nil
        local countW = countStr and tm:MeasureStringX(UIFont.Small, countStr) or 0
        local glyph = opt.glyph or ""
        local glyphW = glyph ~= "" and (tm:MeasureStringX(UIFont.Small, glyph) + 2) or 0

        local pillPadding = p * 1.4
        local extraBadgeW = countStr and (countW + p + 6) or 0
        local chipW = math.ceil(labelW + glyphW + extraBadgeW + pillPadding)
        local minW = math.ceil(labelW + glyphW + 12)

        rawChips[i] = {
            id = opt.id,
            label = label,
            labelW = labelW,
            countStr = countStr,
            countW = countW,
            glyph = glyph,
            glyphW = glyphW,
            alert = opt.alert or false,
            tooltip = opt.tooltip,
            targetW = chipW,
            minW = minW,
            data = opt
        }
        totalMeasuredW = totalMeasuredW + chipW
    end

    local numChips = #rawChips
    if numChips == 0 then return end

    -- 2. Responsive fit
    local availableW = self.width
    local totalGaps = (numChips - 1) * gap
    local scale = 1.0
    if totalMeasuredW + totalGaps > availableW and availableW > 50 then
        local availForChips = math.max(20, availableW - totalGaps)
        scale = math.min(1.0, availForChips / totalMeasuredW)
    end

    local curX = 0
    local chipH = self.height
    for i, c in ipairs(rawChips) do
        local finalW = math.max(math.floor(c.targetW * scale), c.minW)
        c.x = curX
        c.y = 0
        c.width = finalW
        c.height = chipH
        c.textY = math.floor((chipH - h) / 2)
        curX = curX + finalW + gap
        self.chips[i] = c
    end
end

---Select a chip programmatically without necessarily re-triggering callback
---@param id string
function FilterChips:setSelected(id)
    self.selectedId = id
end

function FilterChips:getSelected()
    return self.selectedId
end

function FilterChips:chipAt(x, y)
    if y < 0 or y > self.height then return nil end
    for i, chip in ipairs(self.chips) do
        if x >= chip.x and x <= chip.x + chip.width then
            return i, chip
        end
    end
    return nil
end

function FilterChips:onMouseDown(x, y)
    local idx, chip = self:chipAt(x, y)
    if chip then
        if self.selectedId ~= chip.id then
            self.selectedId = chip.id
            if self.onSelect then
                self.onSelect(chip.id, chip, self)
            end
        end
        return true
    end
    return false
end

function FilterChips:onMouseMove(dx, dy)
    local mx = self:getMouseX()
    local my = self:getMouseY()
    local idx = self:chipAt(mx, my)
    self.hoveredIndex = idx
end

function FilterChips:onMouseMoveOutside(dx, dy)
    self.hoveredIndex = nil
end

---Zero-GC rendering loop
function FilterChips:prerender()
    ISPanel.prerender(self)
    local h, p = self.fontHeight, self.pad

    for i, chip in ipairs(self.chips) do
        local isSelected = (chip.id == self.selectedId)
        local isHovered = (i == self.hoveredIndex)

        -- Background capsule
        local bg = isSelected and Theme.selected or (isHovered and Theme.hover or Theme.control)
        local border = isSelected and Theme.accent or (isHovered and Theme.border or {r=0.20, g=0.25, b=0.30, a=0.6})
        Theme.rect(self, chip.x, chip.y, chip.width, chip.height, bg)
        Theme.rect(self, chip.x, chip.y, chip.width, chip.height, border, true)

        -- Accent left indicator for selected chip
        if isSelected then
            Theme.rect(self, chip.x, chip.y, math.max(2, math.floor(p/3)), chip.height, Theme.accent)
        end

        local textCol = isSelected and Theme.textColor or (isHovered and Theme.textColor or Theme.muted)
        local showCount = chip.countStr ~= nil and (chip.width >= chip.labelW + chip.glyphW + chip.countW + 18)
        local contentW = chip.labelW + chip.glyphW + (showCount and (chip.countW + 10) or 0)
        local drawX = chip.x + math.max(4, math.floor((chip.width - contentW) / 2))

        -- Optional Glyph
        if chip.glyph ~= "" then
            local glyphCol = isSelected and Theme.accent or Theme.muted
            Theme.text(self, chip.glyph, drawX, chip.textY, glyphCol)
            drawX = drawX + chip.glyphW
        end

        -- Main Label
        Theme.text(self, chip.label, drawX, chip.textY, textCol)
        drawX = drawX + chip.labelW + 4

        -- Count Pill Badge
        if showCount then
            local badgeH = h - 2
            local badgeW = chip.countW + 6
            local badgeY = chip.textY + 1
            local badgeBg = chip.alert and Theme.status.ERROR or (isSelected and Theme.panel or {r=0.08, g=0.10, b=0.12, a=0.8})
            local badgeTextCol = chip.alert and Theme.textColor or (isSelected and Theme.accent or Theme.muted)

            Theme.rect(self, drawX, badgeY, badgeW, badgeH, badgeBg)
            Theme.rect(self, drawX, badgeY, badgeW, badgeH, border, true)
            Theme.text(self, chip.countStr, drawX + 3, badgeY - 1, badgeTextCol)
        end
    end
end

return FilterChips
