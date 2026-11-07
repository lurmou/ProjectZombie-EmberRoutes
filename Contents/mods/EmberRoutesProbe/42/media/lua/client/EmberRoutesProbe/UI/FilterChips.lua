--[[
    FilterChips.lua - EmberRoutes UI
    High-ergonomic horizontal toggle chips (capsules).
    Replaces bulky ISComboBox dropdowns with 1-click tactile filter chips.
    Zero-GC rendering, dynamic typography, responsive hover & alert badges.
    Powered by SpringDriver for Motion-inspired shared layout kinetic sliding indicators.
]]

require "ISUI/ISPanel"
local Theme = require "EmberRoutesProbe/UI/Theme"
local SpringDriver = require "EmberRoutesProbe/UI/SpringDriver"
local Visual = require "EmberRoutesProbe/UI/StatusVisual"
local quietBorder={r=0.20,g=0.25,b=0.30,a=0.6}
local quietBadge={r=0.08,g=0.10,b=0.12,a=0.8}

---@class EmberRoutesFilterChips:ISPanel
---@field fontHeight number
---@field pad number
---@field options table[]
---@field chips table[]
---@field selectedId string?
---@field hoveredIndex number?
---@field indicator table
---@field indicatorInitialized boolean
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
    o.indicator = SpringDriver.create2D(0, 0, { stiffness = 320, damping = 28, precision = 0.5 })
    o.indicatorInitialized = false
    o:initialise()
    return o
end

function FilterChips:initialise()
    ISPanel.initialise(self)
end

---Set or update chip options with zero-GC cached coordinates.
---@param options table[] Array of {id=string, label=string, count=number?, alert=boolean?, mark=string?, tooltip=string?}
---@param selectedId string?
function FilterChips:setOptions(options, selectedId)
    self.options = options or {}
    self.selectedId = selectedId or self.selectedId or (self.options[1] and self.options[1].id)
    self.chips = {}
    self.indicatorInitialized = false

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
        -- Fixed slot for a geometric status mark; no text glyph is measured.
        local mark = opt.mark or ""
        local markW = mark ~= "" and 12 or 0

        local pillPadding = p * 1.4
        local extraBadgeW = countStr and (countW + p + 6) or 0
        local chipW = math.ceil(labelW + markW + extraBadgeW + pillPadding)
        local minW = math.ceil(labelW + markW + 12)

        rawChips[i] = {
            id = opt.id,
            label = label,
            labelW = labelW,
            countStr = countStr,
            countW = countW,
            mark = mark,
            markW = markW,
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

    if self.variant=='dossier' then
        local Text=require 'EmberRoutesProbe/UI/Text'
        local cols=self.width>=h*12 and 2 or 1
        local rows=math.ceil(numChips/cols)
        local cellW=math.max(1,(self.width-gap*(cols-1))/cols)
        local cellH=self.height/rows
        for i,c in ipairs(rawChips) do
            c.mark='' c.markW=0
            c.label=Text.wrapLimited(c.label,math.max(1,cellW-c.countW-p*3),UIFont.Small,1)[1] or ''
            c.labelW=tm:MeasureStringX(UIFont.Small,c.label)
            c.x=((i-1)%cols)*(cellW+gap) c.y=math.floor((i-1)/cols)*cellH
            c.width=cellW c.height=cellH c.textY=c.y+math.max(0,(cellH-h)/2)
            self.chips[i]=c
        end
        return
    end
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
---@param immediate boolean? If true, instantly snaps the indicator without animation
function FilterChips:setSelected(id, immediate)
    self.selectedId = id
    if immediate and self.indicator then
        for _, chip in ipairs(self.chips) do
            if chip.id == id then
                SpringDriver.snap2D(self.indicator, chip.x, chip.width)
                self.indicatorInitialized = true
                break
            end
        end
    end
end

function FilterChips:chipAt(x, y)
    if y < 0 or y > self.height then return nil end
    for i, chip in ipairs(self.chips) do
        if x >= chip.x and x <= chip.x + chip.width and (self.variant~='dossier' or y>=chip.y and y<chip.y+chip.height) then
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
    local dossier = (self.variant == 'dossier')
    local underline = (self.variant == 'underline')

    if not dossier then
        -- 1. Shared Layout Kinetic Indicator (SpringDriver)
        local targetChip = nil
        for i, chip in ipairs(self.chips) do
            if chip.id == self.selectedId then
                targetChip = chip
                break
            end
        end

        if targetChip then
            if not self.indicatorInitialized then
                SpringDriver.snap2D(self.indicator, targetChip.x, targetChip.width)
                self.indicatorInitialized = true
            else
                local dt = 0.016
                if UIManager and UIManager.getMillisSinceLastRender then
                    local ms = UIManager.getMillisSinceLastRender()
                    if ms and ms > 0 then dt = ms / 1000.0 end
                end
                SpringDriver.update2D(self.indicator, targetChip.x, targetChip.width, dt)
            end
        end

        -- 2. Passive Chip Backgrounds
        for i, chip in ipairs(self.chips) do
            local isHovered = (i == self.hoveredIndex)
            if underline then
                if isHovered then
                    Theme.rect(self, chip.x, chip.y, chip.width, chip.height, Theme.hover)
                end
            else
                local bg = isHovered and Theme.hover or Theme.control
                local border = isHovered and Theme.border or quietBorder
                Theme.rect(self, chip.x, chip.y, chip.width, chip.height, bg)
                Theme.rect(self, chip.x, chip.y, chip.width, chip.height, border, true)
            end
        end

        -- 3. Render Kinetic Active Indicator (Gliding Capsule / Underline)
        if targetChip and self.indicatorInitialized then
            local indX = math.floor(self.indicator.a)
            local indW = math.floor(self.indicator.b)
            if underline then
                Theme.rect(self, indX, self.height - 2, indW, 2, Theme.accent)
            else
                Theme.rect(self, indX, 0, indW, self.height, Theme.selected)
                Theme.rect(self, indX, 0, indW, self.height, Theme.accent, true)
                Theme.rect(self, indX, 0, math.max(2, math.floor(p / 3)), self.height, Theme.accent)
            end
        end
    else
        -- Dossier variant: static grid cards
        for i, chip in ipairs(self.chips) do
            local isSelected = (chip.id == self.selectedId)
            local isHovered = (i == self.hoveredIndex)
            if isHovered then
                Theme.rect(self, chip.x, chip.y, chip.width, chip.height, Theme.dossier.panel)
            end
            if isSelected then
                Theme.rect(self, chip.x, chip.y + chip.height - 2, chip.width, 2, Theme.dossier.gold)
            end
        end
    end

    -- 4. Foreground Content (Geometric Marks, Labels, Count Badges)
    for i, chip in ipairs(self.chips) do
        local isSelected = (chip.id == self.selectedId)
        local isHovered = (i == self.hoveredIndex)

        local textCol = dossier and (isSelected and Theme.dossier.text or Theme.dossier.muted) or isSelected and Theme.textColor or (isHovered and Theme.textColor or Theme.muted)
        local showCount = chip.countStr ~= nil and (chip.width >= chip.labelW + chip.markW + chip.countW + 18)
        local contentW = chip.labelW + chip.markW + (showCount and (chip.countW + 10) or 0)
        local drawX = chip.x + math.max(4, math.floor((chip.width - contentW) / 2))

        -- Optional geometric status mark
        if chip.mark ~= "" then
            local markCol = isSelected and Theme.accent or Theme.muted
            local ms = math.max(6, math.min(h - 4, 10))
            Visual.mark(self, drawX, chip.textY + math.floor((h - ms) / 2), ms, chip.mark, markCol)
            drawX = drawX + chip.markW
        end

        -- Main Label
        Theme.text(self, chip.label, drawX, chip.textY, textCol)
        drawX = drawX + chip.labelW + 4

        -- Count Pill Badge
        if showCount then
            local badgeH = h - 2
            local badgeW = chip.countW + 6
            local badgeY = chip.textY + 1
            local badgeBg = chip.alert and Theme.status.ERROR or (isSelected and Theme.panel or quietBadge)
            local badgeTextCol = dossier and (chip.alert and Theme.dossier.alert or Theme.dossier.muted) or chip.alert and Theme.textColor or (isSelected and Theme.accent or Theme.muted)

            if not underline and not dossier then
                local border = isSelected and Theme.accent or (isHovered and Theme.border or quietBorder)
                Theme.rect(self, drawX, badgeY, badgeW, badgeH, badgeBg)
                Theme.rect(self, drawX, badgeY, badgeW, badgeH, border, true)
            end
            Theme.text(self, chip.countStr, drawX + 3, badgeY - 1, badgeTextCol)
        end
    end
end

return FilterChips
