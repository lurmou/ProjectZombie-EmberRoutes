--[[
    EmptyState.lua - EmberRoutes UI
    Mechanism: Industrial Blankslate & Zero-Data Instructional Placeholder.
    
    Architectural Compliance:
      - GitHub Primer Blankslate Parity: Large Octicon + High-Contrast Title + Muted Guidance.
      - Zero-GC Invariant: Static scalar colors, pre-calculated text measurements.
      - Dynamic Centering: Adapts smoothly to arbitrary container dimensions.
      - Embedded Action Support: Optional CTA (Call-to-Action) button coordination & hit-testing.
]]

local Theme = require 'EmberRoutesProbe/UI/Theme'
local StatusVisual = require 'EmberRoutesProbe/UI/StatusVisual'
local Text = require 'EmberRoutesProbe/UI/Text'

local EmptyState = {}

-- Pre-allocated immutable scalar color tables (Zero GC)
local ICON_COLOR   = {r = 0.50, g = 0.60, b = 0.70, a = 0.40}
local HINT_COLOR   = {r = Theme.muted.r, g = Theme.muted.g, b = Theme.muted.b, a = 0.75}
local BTN_BG       = {r = Theme.control.r, g = Theme.control.g, b = Theme.control.b, a = 0.85}
local BTN_BORDER   = {r = Theme.border.r, g = Theme.border.g, b = Theme.border.b, a = 0.90}
local BTN_HOVER_BG = {r = Theme.control.r + 0.08, g = Theme.control.g + 0.08, b = Theme.control.b + 0.08, a = 0.95}

---Draws an industrial empty state placeholder vertically and horizontally centered.
---@param owner ISPanel
---@param bounds table {x=number, y=number, width=number, height=number}
---@param opts table {icon=string?, iconSize=number?, title=string, hint=string?, action=string?}
function EmptyState.draw(owner, bounds, opts)
    if not owner or not bounds or bounds.width <= 0 or bounds.height <= 0 then return end
    opts = opts or {}

    local iconName = opts.icon or "box"
    local title = opts.title or ""
    local hint = opts.hint or ""
    local action = opts.action
    local iconSize = opts.iconSize or 32

    local tm = getTextManager()
    local fontH = tm and tm:getFontHeight(UIFont.Small) or 14
    local titleW = tm and tm:MeasureStringX(UIFont.Small, title) or (#title * 8)

    -- Calculate total stack height
    local totalContentH = iconSize + 10 + fontH
    local hintLines = nil
    if hint and hint ~= "" then
        local maxTextW = math.max(60, bounds.width - 40)
        hintLines = Text.wrapLimited(hint, maxTextW, UIFont.Small, 2)
        totalContentH = totalContentH + 6 + #hintLines * fontH
    end

    local btnH = 24
    local btnW = 0
    if action and action ~= "" then
        btnW = (tm and tm:MeasureStringX(UIFont.Small, action) or (#action * 8)) + 24
        totalContentH = totalContentH + 14 + btnH
    end

    local startY = bounds.y + math.floor((bounds.height - totalContentH) / 2)
    local centerX = bounds.x + math.floor(bounds.width / 2)

    -- 1. Large Primer Octicon Centerpiece
    local iconX = centerX - math.floor(iconSize / 2)
    StatusVisual.icon(owner, iconX, startY, iconSize, iconName, ICON_COLOR)

    -- 2. Title Text
    local titleY = startY + iconSize + 10
    local titleX = centerX - math.floor(titleW / 2)
    Theme.text(owner, title, titleX, titleY, Theme.textColor, UIFont.Small)

    -- 3. Muted Guidance Subtext
    local curY = titleY + fontH
    if hintLines and #hintLines > 0 then
        curY = curY + 6
        for _, line in ipairs(hintLines) do
            local lineW = tm and tm:MeasureStringX(UIFont.Small, line) or (#line * 7)
            Theme.text(owner, line, centerX - math.floor(lineW / 2), curY, HINT_COLOR, UIFont.Small)
            curY = curY + fontH
        end
    end

    -- 4. Interactive Call-To-Action (CTA) Pill Button
    if action and action ~= "" then
        local btnX = centerX - math.floor(btnW / 2)
        local btnY = curY + 12

        local isHover = false
        if owner.getMouseX and owner.getMouseY then
            local mx, my = owner:getMouseX(), owner:getMouseY()
            if mx >= btnX and mx <= btnX + btnW and my >= btnY and my <= btnY + btnH then
                isHover = true
            end
        end

        Theme.rect(owner, btnX, btnY, btnW, btnH, isHover and BTN_HOVER_BG or BTN_BG)
        Theme.rect(owner, btnX, btnY, btnW, btnH, isHover and Theme.primary or BTN_BORDER, true)
        local tw = tm and tm:MeasureStringX(UIFont.Small, action) or (#action * 8)
        local tx = btnX + math.floor((btnW - tw) / 2)
        local ty = btnY + math.floor((btnH - fontH) / 2)
        Theme.text(owner, action, tx, ty, isHover and Theme.primary or Theme.textColor, UIFont.Small)

        -- Cache button bounds for zero-allocation hit testing
        local b = bounds._emptyActionBtn
        if not b then
            b = {x = btnX, y = btnY, width = btnW, height = btnH, visible = true}
            bounds._emptyActionBtn = b
        else
            b.x = btnX
            b.y = btnY
            b.width = btnW
            b.height = btnH
            b.visible = true
        end
    elseif bounds._emptyActionBtn then
        bounds._emptyActionBtn.visible = false
    end
end

---Autonomous Hit-Testing for EmptyState Action Button
---@param bounds table
---@param lx number Local container X
---@param ly number Local container Y
---@return boolean
function EmptyState.hitTest(bounds, lx, ly)
    local btn = bounds and bounds._emptyActionBtn
    if not btn or not btn.visible then return false end
    return lx >= btn.x and lx <= btn.x + btn.width and ly >= btn.y and ly <= btn.y + btn.height
end

return EmptyState
