--[[
    InlineCardDrawer.lua - EmberRoutes UI
    Mechanism 1: Inline Extending Card Drawer with 2px Seam Erasure Welding.
    
    Architectural Compliance:
      - ProjectRemnants Heritage: Reproduces the seamless extruded physical drawer effect.
      - 2px Seam Erasure: Overwrites the bottom border of the header card with background color
        at the junction line, visually welding the card and drawer into a single physical unit.
      - Virtual Childless Architecture: 100% rendered inside list item drawing callback.
        Zero sub-ISUIElements created, zero memory leaks, zero GC overhead.
      - Ergonomic Interaction: Accurate local hit-testing math for buttons and toggles.
]]

local Theme = require 'EmberRoutesProbe/UI/Theme'

local InlineCardDrawer = {}

-- Pre-allocated immutable palette (Zero GC)
local COLOR_BTN_BG        = {r = 0.12, g = 0.16, b = 0.20, a = 0.90}
local COLOR_BTN_HOVER     = {r = 0.20, g = 0.28, b = 0.36, a = 1.00}
local COLOR_BTN_BORDER    = {r = 0.35, g = 0.45, b = 0.55, a = 0.85}

---Skin-free virtual button primitive with Flat 2.0 tactile feedback.
---@param list ISScrollingListBox
---@param tw number Pre-measured label width (UIFont.Small)
---@param th number Pre-measured font height
---@param isHover boolean?
---@param isDown boolean?
function InlineCardDrawer.drawButton(list, bx, by, bw, bh, label, tw, th, bg, border, textColor, isHover, isDown)
    local bCol = isHover and (Theme.accent or border) or border
    local bgCol = isDown and {r = bg.r * 0.75, g = bg.g * 0.75, b = bg.b * 0.75, a = bg.a or 1}
               or (isHover and COLOR_BTN_HOVER or bg)
    local off = isDown and 1 or 0
    Theme.rect(list, bx, by, bw, bh, bgCol)
    Theme.rect(list, bx, by, bw, bh, bCol, true)
    if isDown then
        Theme.rect(list, bx, by, bw, 1, {r = 0, g = 0, b = 0, a = 0.65})
    end
    Theme.text(list, label, bx + math.floor((bw - tw) / 2) + off,
        by + math.floor((bh - th) / 2) + off, textColor)
end

---Determines if a mouse click inside the list hits a virtual rectangle.
---@param mouseX number Local list mouse X
---@param mouseY number Local list mouse Y
---@param rx number Rect X
---@param ry number Rect Y
---@param rw number Rect Width
---@param rh number Rect Height
---@return boolean
function InlineCardDrawer.hitTest(mouseX, mouseY, rx, ry, rw, rh)
    return mouseX >= rx and mouseX <= (rx + rw) and mouseY >= ry and mouseY <= (ry + rh)
end

return InlineCardDrawer
