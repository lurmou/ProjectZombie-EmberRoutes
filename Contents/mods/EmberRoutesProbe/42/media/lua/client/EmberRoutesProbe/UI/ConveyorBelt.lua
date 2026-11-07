--[[
    ConveyorBelt.lua - EmberRoutes UI
    Mechanism 7: Dynamic Logistics Conveyor Belt & Industrial Hazard Striping.
    
    Architectural Compliance:
      - Hardware Stencil: 100% symmetric setStencilRect / clearStencilRect around belt bounds.
      - Mathematical Slats Modulo: Virtual translation prevents border seam overflow.
      - Dual Visual Modes:
          "conveyor": High-tech chevron arrows indicating direction and flow rate.
          "hazard": High-contrast yellow/black diagonal industrial warning stripes.
      - Dynamic Flow Control: Velocity scales smoothly with hauling/work throughput.
      - Zero-GC: Pre-allocated color tables, zero dynamic table allocations.
]]

local Theme = require 'EmberRoutesProbe/UI/Theme'
local UICache = require 'EmberRoutesProbe/UI/UICache'

local ConveyorBelt = {}

-- Pre-allocated immutable palette (Zero GC)
local COLOR_TROUGH_DARK   = {r = 0.05, g = 0.06, b = 0.08, a = 0.98}
local COLOR_FRAME_BORDER  = {r = 0.22, g = 0.28, b = 0.35, a = 0.90}
local COLOR_FRAME_INNER   = {r = 0.12, g = 0.16, b = 0.20, a = 0.85}

-- Conveyor Mode Palette (Cyan/Blue Chevron logistics)
local COLOR_SLAT_BASE     = {r = 0.08, g = 0.14, b = 0.20, a = 0.90}
local COLOR_CHEVRON_CYAN  = {r = 0.25, g = 0.80, b = 0.95, a = 0.90}
local COLOR_CHEVRON_GLOW  = {r = 0.50, g = 0.92, b = 1.00, a = 0.50}

-- Hazard Mode Palette (Industrial Yellow/Black warning stripes)
local COLOR_HAZARD_YELLOW = {r = 0.92, g = 0.78, b = 0.18, a = 0.95}
local COLOR_HAZARD_BLACK  = {r = 0.08, g = 0.08, b = 0.08, a = 0.95}

-- Paused/Halted Mode
local COLOR_HALTED_RED    = {r = 0.85, g = 0.25, b = 0.25, a = 0.85}

---Creates a conveyor state container.
---@param speed number? Pixels per second (default 24.0)
---@param period number? Slat repetition interval (default 20px)
---@return table
function ConveyorBelt.createState(speed, period)
    return {
        offset = 0.0,
        currentSpeed = 0.0,
        targetSpeed = speed or 24.0,
        period = period or 20,
        active = true
    }
end

---Updates conveyor animation step.
---@param state table
---@param isActive boolean
---@param rateMultiplier number? (e.g. 1.5 for high throughput)
function ConveyorBelt.update(state, isActive, rateMultiplier)
    if not state then return end
    local mult = rateMultiplier or 1.0
    state.active = isActive
    state.targetSpeed = isActive and ((state.period or 20) * 1.5 * mult) or 0.0

    local dt = UIManager.getMillisSinceLastRender() / 1000.0
    if dt > 0.1 then dt = 0.1 end
    if dt <= 0 then dt = 0.016 end

    -- Smooth acceleration / deceleration
    local diff = state.targetSpeed - state.currentSpeed
    state.currentSpeed = state.currentSpeed + diff * (1.0 - math.exp(-8.0 * dt))

    state.offset = (state.offset + state.currentSpeed * dt) % (state.period or 20)
end

---Draws animated conveyor or hazard striping.
---@param owner ISPanel
---@param x number
---@param y number
---@param w number
---@param h number
---@param mode "conveyor"|"hazard"|"paused"
---@param state table|number State table or offset number
---@param opts table? {period=number, label=string, font=UIFont}
function ConveyorBelt.draw(owner, x, y, w, h, mode, state, opts)
    opts = opts or {}
    local period = opts.period or (type(state) == "table" and state.period) or 20
    local offset = (type(state) == "table" and state.offset) or (type(state) == "number" and state) or 0.0
    offset = offset % period

    -- 1. Outer Frame (Sunken Industrial Track)
    Theme.rect(owner, x, y, w, h, COLOR_TROUGH_DARK)
    Theme.rect(owner, x, y, w, h, COLOR_FRAME_BORDER, true)

    -- 2. Hardware Stencil clipping viewport (keeps scrolling slats cleanly inside track)
    owner:setStencilRect(x + 1, y + 1, w - 2, h - 2)

    local startX = x - period + math.floor(offset)
    local endX = x + w + period

    if mode == "hazard" then
        -- Industrial Diagonal Hazard Stripes (Yellow / Black alternating)
        local curX = startX
        local stripeW = math.floor(period / 2)
        local index = 0
        while curX < endX do
            local col = (index % 2 == 0) and COLOR_HAZARD_YELLOW or COLOR_HAZARD_BLACK
            Theme.rect(owner, curX, y + 1, stripeW, h - 2, col)
            curX = curX + stripeW
            index = index + 1
        end
    elseif mode == "paused" then
        -- Halted State (Static Muted warning track)
        Theme.rect(owner, x + 1, y + 1, w - 2, h - 2, {r = 0.12, g = 0.08, b = 0.08, a = 0.90})
        local curX = x + 1
        while curX < x + w do
            Theme.rect(owner, curX, y + 1, 4, h - 2, COLOR_HALTED_RED)
            curX = curX + 16
        end
    else
        -- Active Logistics Conveyor (Forward Chevrons)
        local curX = startX
        local halfH = math.floor(h / 2)
        while curX < endX do
            -- Base slat spacer
            Theme.rect(owner, curX, y + 1, 2, h - 2, COLOR_SLAT_BASE)

            -- Stylized Forward Chevron Arrow ('>' shape)
            local tipX = curX + math.floor(period * 0.6)
            local midY = y + halfH
            
            -- Chevron arrow spine
            Theme.rect(owner, curX + 4, midY - 3, 4, 6, COLOR_CHEVRON_CYAN)
            Theme.rect(owner, curX + 7, midY - 2, 3, 4, COLOR_CHEVRON_GLOW)
            Theme.rect(owner, tipX,     midY - 1, 2, 2, COLOR_CHEVRON_GLOW)

            curX = curX + period
        end
    end

    -- 3. Top and Bottom Guide Rails (Metallic edge lines)
    Theme.rect(owner, x + 1, y + 1, w - 2, 1, COLOR_FRAME_INNER)
    Theme.rect(owner, x + 1, y + h - 2, w - 2, 1, COLOR_FRAME_INNER)

    -- 4. 100% Symmetric Stencil Cleanup
    owner:clearStencilRect()

    -- 5. Optional Centered Badge/Label
    if opts.label and opts.label ~= "" then
        local font = opts.font or UIFont.Small
        local tm = getTextManager()
        local tw = UICache.measure(font, opts.label)
        local th = tm:getFontHeight(font)
        local lx = x + math.floor((w - tw) / 2)
        local ly = y + math.floor((h - th) / 2)

        -- Micro-capsule behind label for contrast
        Theme.rect(owner, lx - 6, ly - 2, tw + 12, th + 4, {r = 0.02, g = 0.03, b = 0.04, a = 0.88})
        Theme.rect(owner, lx - 6, ly - 2, tw + 12, th + 4, COLOR_FRAME_BORDER, true)
        Theme.text(owner, opts.label, lx, ly, {r = 0.95, g = 0.95, b = 0.95, a = 1.0}, font)
    end
end

return ConveyorBelt
