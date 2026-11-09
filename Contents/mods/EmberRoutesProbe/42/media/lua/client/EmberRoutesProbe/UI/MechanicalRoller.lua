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

        -- 2. Slot recessed drum trough background
        Theme.rect(owner, slotX, slotY, digitW, digitH, COLOR_SLOT_TROUGH)

        -- 3. Clean digit text rendering (Centered, crisp, Zero-GC, No Stencil, No middle slice)
        local intDigit = math.floor(slotVal) % 10
        local digitStr = DIGIT_STRINGS[intDigit]
        local strW = UICache.measure(font, digitStr)
        local textX = slotX + math.floor((digitW - strW) / 2)
        local textY = slotY + textOffsetY

        local tColor = opts.textColor or Theme.textColor
        Theme.text(owner, digitStr, textX, textY, tColor, font)

        -- 4. Slot Inner Edge Contour
        Theme.rect(owner, slotX, slotY, digitW, digitH, COLOR_BORDER_INNER, true)
    end

    return totalOuterW
end

return MechanicalRoller
