--[[
    MechanicalRoller.lua - EmberRoutes UI
    Mechanism 5: Industrial Odometer & Split-Flap Rolling Digit Counter.
    
    Architectural Compliance:
      - Ergonomic Sizing: Default digit size 22x34px, comfortable reading spacing.
      - 3D Cylindrical Shading: Multi-step top and bottom shadow bands for authentic mechanical drum depth.
      - Cascading Odometer Math: Higher digits only engage when lower digit crosses 9.0.
      - Damped Annealing: Frame-delta based exponential smoothing (UIManager.getMillisSinceLastRender).
      - Hardware Stencil: 100% symmetric setStencilRect / clearStencilRect per digit slot.
      - Zero-GC: Zero table allocations, pre-cached digit strings, pre-allocated color scalars.
]]

local Theme = require 'EmberRoutesProbe/UI/Theme'
local UICache = require 'EmberRoutesProbe/UI/UICache'

local MechanicalRoller = {}

local DIGIT_STRINGS = {
    [0] = "0", [1] = "1", [2] = "2", [3] = "3", [4] = "4",
    [5] = "5", [6] = "6", [7] = "7", [8] = "8", [9] = "9"
}

-- Pre-allocated immutable palette (Zero GC)
local COLOR_SOCKET_BG     = {r = 0.03, g = 0.04, b = 0.06, a = 0.98}
local COLOR_SLOT_TROUGH   = {r = 0.07, g = 0.09, b = 0.12, a = 1.00}
local COLOR_BORDER_OUTER  = {r = 0.18, g = 0.24, b = 0.30, a = 0.90}
local COLOR_BORDER_INNER  = {r = 0.30, g = 0.40, b = 0.50, a = 0.85}
local COLOR_FLAP_LINE     = {r = 0.01, g = 0.02, b = 0.03, a = 0.85}
local COLOR_FLAP_HILIGHT  = {r = 0.45, g = 0.55, b = 0.65, a = 0.25}

-- Cylindrical shadow bands (top and bottom gradient falloff)
local SHADOW_BAND_1 = {r = 0.00, g = 0.00, b = 0.00, a = 0.55}
local SHADOW_BAND_2 = {r = 0.00, g = 0.00, b = 0.00, a = 0.35}
local SHADOW_BAND_3 = {r = 0.00, g = 0.00, b = 0.00, a = 0.15}

---Creates a scalar state container for smooth interpolation.
---@param numDigits number?
---@param lambda number? Exponential decay coefficient
---@return table
function MechanicalRoller.createState(numDigits, lambda)
    return {
        current = 0.0,
        target = 0.0,
        numDigits = numDigits or 3,
        lambda = lambda or 9.0 -- default fast responsive mechanical snap
    }
end

---Updates damped annealing step towards target value using frame delta.
---@param state table
---@param targetValue number
function MechanicalRoller.update(state, targetValue)
    if not state then return end
    state.target = math.max(0, targetValue or 0)
    
    local dt = UIManager.getMillisSinceLastRender() / 1000.0
    if dt > 0.1 then dt = 0.1 end
    if dt <= 0 then dt = 0.016 end

    local diff = state.target - state.current
    if math.abs(diff) < 0.002 then
        state.current = state.target
    else
        local factor = 1.0 - math.exp(-(state.lambda or 9.0) * dt)
        state.current = state.current + diff * factor
    end
end

---Calculates total pixel width of the roller component.
---@param numDigits number
---@param digitWidth number?
---@param gap number?
---@return number
function MechanicalRoller.measureWidth(numDigits, digitWidth, gap)
    digitWidth = digitWidth or 22
    gap = gap or 3
    return numDigits * digitWidth + math.max(0, numDigits - 1) * gap + 4 -- 4px outer bezel padding
end

---Calculates total recommended pixel height.
---@param digitHeight number?
---@return number
function MechanicalRoller.measureHeight(digitHeight)
    return (digitHeight or 34) + 4 -- 4px outer bezel padding
end

---Static zero-GC draw function for embedding in HUD panels or card rows.
---@param owner ISPanel
---@param x number
---@param y number
---@param state table {current=number, target=number, numDigits=number}
---@param opts table? {digitWidth=number, digitHeight=number, gap=number, textColor=table, font=UIFont}
---@return number totalWidthRendered
function MechanicalRoller.draw(owner, x, y, state, opts)
    opts = opts or {}
    local numDigits = opts.numDigits or (state and state.numDigits) or 3
    local digitW = opts.digitWidth or 22
    local digitH = opts.digitHeight or 34
    local gap = opts.gap or 3
    local font = opts.font or UIFont.Medium
    local tm = getTextManager()
    local fontH = tm:getFontHeight(font)
    local textOffsetY = math.floor((digitH - fontH) / 2)

    local totalSlotsW = numDigits * digitW + math.max(0, numDigits - 1) * gap
    local totalOuterW = totalSlotsW + 4
    local totalOuterH = digitH + 4

    -- 1. Outer Recessed Bezel Frame (Sunken Industrial Housing)
    Theme.rect(owner, x, y, totalOuterW, totalOuterH, opts.socketBg or COLOR_SOCKET_BG)
    Theme.rect(owner, x, y, totalOuterW, totalOuterH, COLOR_BORDER_OUTER, true)
    Theme.rect(owner, x + 1, y + 1, totalOuterW - 2, totalOuterH - 2, COLOR_BORDER_INNER, true)

    local startX = x + 2
    local slotY = y + 2
    local val = math.max(0, state and state.current or 0)

    -- Cascading mechanical odometer digit calculation (Zero-GC scalar loop)
    local prevSlot = val % 10
    for i = 0, numDigits - 1 do
        local slotVal = 0
        if i == 0 then
            slotVal = prevSlot
        else
            local divisor = (i == 1 and 10) or (i == 2 and 100) or (i == 3 and 1000) or (10 ^ i)
            local base = math.floor(val / divisor) % 10
            if prevSlot > 9.0 then
                slotVal = base + (prevSlot - 9.0)
            else
                slotVal = base
            end
            prevSlot = slotVal
        end

        local slotX = startX + (numDigits - 1 - i) * (digitW + gap)

        -- 2. Hardware Stencil clipping viewport for this individual digit drum
        owner:setStencilRect(slotX, slotY, digitW, digitH)

        -- 3. Slot recessed drum trough background
        Theme.rect(owner, slotX, slotY, digitW, digitH, COLOR_SLOT_TROUGH)

        -- 4. Digits vertical translation & rendering
        local intDigit = math.floor(slotVal) % 10
        local rollFrac = slotVal - math.floor(slotVal)
        local nextDigit = (intDigit + 1) % 10

        local d1_Y = slotY + textOffsetY - math.floor(rollFrac * digitH)
        local d2_Y = d1_Y + digitH
        
        -- Center digit string inside slot
        local digitStr1 = DIGIT_STRINGS[intDigit]
        local digitStr2 = DIGIT_STRINGS[nextDigit]
        local strW = UICache.measure(font, digitStr1)
        local textX = slotX + math.floor((digitW - strW) / 2)

        local tColor = opts.textColor or Theme.textColor
        Theme.text(owner, digitStr1, textX, d1_Y, tColor, font)
        if rollFrac > 0.001 then
            Theme.text(owner, digitStr2, textX, d2_Y, tColor, font)
        end

        -- 5. 3D Cylindrical Shading Overlays (Creating true drum depth)
        -- Top shadow bands (curvature away from viewer)
        Theme.rect(owner, slotX, slotY,     digitW, 2, SHADOW_BAND_1)
        Theme.rect(owner, slotX, slotY + 2, digitW, 2, SHADOW_BAND_2)
        Theme.rect(owner, slotX, slotY + 4, digitW, 2, SHADOW_BAND_3)

        -- Bottom shadow bands (curvature away from viewer)
        Theme.rect(owner, slotX, slotY + digitH - 6, digitW, 2, SHADOW_BAND_3)
        Theme.rect(owner, slotX, slotY + digitH - 4, digitW, 2, SHADOW_BAND_2)
        Theme.rect(owner, slotX, slotY + digitH - 2, digitW, 2, SHADOW_BAND_1)

        -- 6. Split-Flap Middle Slit Line & Specular Micro-Highlight
        local midY = slotY + math.floor(digitH / 2)
        Theme.rect(owner, slotX, midY - 1, digitW, 1, COLOR_FLAP_HILIGHT)
        Theme.rect(owner, slotX, midY,     digitW, 1, COLOR_FLAP_LINE)

        -- 7. Slot Inner Edge Contour
        Theme.rect(owner, slotX, slotY, digitW, digitH, COLOR_BORDER_INNER, true)

        -- 8. 100% Symmetric Stencil Cleanup
        owner:clearStencilRect()
    end

    return totalOuterW
end

return MechanicalRoller
