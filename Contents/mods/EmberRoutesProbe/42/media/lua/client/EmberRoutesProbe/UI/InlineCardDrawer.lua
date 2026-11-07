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
local COLOR_DRAWER_BG     = {r = 0.05, g = 0.06, b = 0.08, a = 0.95}
local COLOR_DRAWER_BORDER = {r = 0.78, g = 0.62, b = 0.32, a = 0.90} -- Tactical Amber gold
local COLOR_BTN_BG        = {r = 0.12, g = 0.16, b = 0.20, a = 0.90}
local COLOR_BTN_HOVER     = {r = 0.20, g = 0.28, b = 0.36, a = 1.00}
local COLOR_BTN_BORDER    = {r = 0.35, g = 0.45, b = 0.55, a = 0.85}

---LEGACY whole-drawer skin (tactical amber border + 2px seam welding).
---Production work-order drawers use a continuous frame with low-contrast
---internal separators instead; this function is retained only for the
---mechanism regression tests. New code should reuse drawButton/hitTest.
---@deprecated
---@param list ISScrollingListBox
---@param y number Card top Y
---@param baseHeight number Height of header card
---@param drawerHeight number Height of extended drawer
---@param cardX number Card left X
---@param cardW number Card width
---@param isSelected boolean
---@param renderContentFn function(drawerX, drawerY, drawerW, drawerH)
---@return number nextY (y + totalHeight)
function InlineCardDrawer.draw(list, y, baseHeight, drawerHeight, cardX, cardW, isSelected, renderContentFn)
    local drawerY = y + baseHeight - 2 -- 2px upward overlap for seam welding
    local drawerW = cardW
    local bg = COLOR_DRAWER_BG

    -- 1. Drawer Body Background and Outer Frame
    Theme.rect(list, cardX, drawerY, drawerW, drawerHeight, bg)
    Theme.rect(list, cardX, drawerY, drawerW, drawerHeight, COLOR_DRAWER_BORDER, true)

    -- 2.【2px Seam Erasure Welding Trick】:
    -- Overwrite the seam line with background color so the header card and drawer
    -- read visually as ONE SINGLE SOLID EXTRUDED OBJECT!
    Theme.rect(list, cardX + 1, drawerY, drawerW - 2, 2, bg)

    -- 3. Render Virtual Drawer Content
    if renderContentFn then
        renderContentFn(cardX + 8, drawerY + 6, drawerW - 16, drawerHeight - 12)
    end

    return y + baseHeight + drawerHeight - 2
end

---Skin-free virtual button primitive. Text metrics and colours are supplied
---by the caller so the per-frame draw pass performs no JNI measurement and
---allocates no tables. Coordinates match the legacy drawVirtualButton exactly.
---@param list ISScrollingListBox
---@param tw number Pre-measured label width (UIFont.Small)
---@param th number Pre-measured font height
function InlineCardDrawer.drawButton(list, bx, by, bw, bh, label, tw, th, bg, border, textColor)
    Theme.rect(list, bx, by, bw, bh, bg)
    Theme.rect(list, bx, by, bw, bh, border, true)
    Theme.text(list, label, bx + math.floor((bw - tw) / 2),
        by + math.floor((bh - th) / 2), textColor)
end

---Backwards-compatible convenience wrapper (legacy palette, measures text).
---Convenience helper to draw a virtual action button inside the drawer.
---@param list ISScrollingListBox
---@param bx number Button X
---@param by number Button Y
---@param bw number Button Width
---@param bh number Button Height
---@param label string Button Text
---@param isHover boolean
---@param font UIFont?
function InlineCardDrawer.drawVirtualButton(list, bx, by, bw, bh, label, isHover, font)
    local f = font or UIFont.Small
    local tm = getTextManager()
    InlineCardDrawer.drawButton(list, bx, by, bw, bh, label,
        tm:MeasureStringX(f, label), tm:getFontHeight(f),
        isHover and COLOR_BTN_HOVER or COLOR_BTN_BG, COLOR_BTN_BORDER, Theme.textColor)
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
