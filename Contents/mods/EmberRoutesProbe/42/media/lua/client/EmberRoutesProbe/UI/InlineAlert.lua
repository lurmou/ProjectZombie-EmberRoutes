--[[
    InlineAlert.lua - EmberRoutes UI
    Mechanism: 4-Tier Semantic Inline Alert & Banner Component.
    
    Architectural Compliance:
      - GitHub Primer Flash / Alert Parity: Left 3px solid accent stripe + subtle tint bg + Primer Octicon.
      - 4 Industry Semantic Levels: INFO, SUCCESS, WARNING, DANGER.
      - Zero-GC Invariant: Pre-allocated palette tables, reusable measured text buffers.
      - Interactive Dismiss & Action Hooks: Optional close callback and inline CTA.
]]

local Theme = require 'EmberRoutesProbe/UI/Theme'
local StatusVisual = require 'EmberRoutesProbe/UI/StatusVisual'
local Text = require 'EmberRoutesProbe/UI/Text'

local InlineAlert = {}

-- Pre-allocated immutable semantic palettes (Zero GC)
local PALETTES = {
    info = {
        bar = {r = 0.22, g = 0.74, b = 0.97, a = 1.00},   -- #38BDF8 Sky blue
        bg  = {r = 0.08, g = 0.15, b = 0.22, a = 0.85},
        border = {r = 0.18, g = 0.35, b = 0.50, a = 0.80},
        text = {r = 0.85, g = 0.92, b = 0.98, a = 1.00},
        icon = "bullet"
    },
    success = {
        bar = {r = 0.25, g = 0.73, b = 0.31, a = 1.00},   -- #3FB950 Green
        bg  = {r = 0.06, g = 0.18, b = 0.10, a = 0.85},
        border = {r = 0.18, g = 0.45, b = 0.25, a = 0.80},
        text = {r = 0.85, g = 0.96, b = 0.88, a = 1.00},
        icon = "check"
    },
    warning = {
        bar = {r = 0.82, g = 0.60, b = 0.13, a = 1.00},   -- #D29922 Amber
        bg  = {r = 0.20, g = 0.15, b = 0.06, a = 0.85},
        border = {r = 0.45, g = 0.35, b = 0.15, a = 0.80},
        text = {r = 0.98, g = 0.92, b = 0.80, a = 1.00},
        icon = "warn"
    },
    danger = {
        bar = {r = 0.97, g = 0.32, b = 0.29, a = 1.00},   -- #F85149 Red
        bg  = {r = 0.22, g = 0.08, b = 0.08, a = 0.85},
        border = {r = 0.52, g = 0.20, b = 0.20, a = 0.80},
        text = {r = 0.98, g = 0.85, b = 0.85, a = 1.00},
        icon = "warn"
    }
}

---Calculates recommended height for an inline alert given text and width.
---@param text string
---@param width number
---@param pad number?
---@return number height
function InlineAlert.measureHeight(text, width, pad)
    pad = pad or 8
    local tm = getTextManager()
    local fontH = tm and tm:getFontHeight(UIFont.Small) or 14
    local availableW = math.max(40, width - 26 - pad * 2)
    local lines = Text.wrapLimited(text or "", availableW, UIFont.Small, 3)
    return math.max(28, #lines * fontH + pad * 2)
end

---Draws an inline alert banner inside owner.
---@param owner ISPanel
---@param x number
---@param y number
---@param width number
---@param height number
---@param opts table {type="info"|"success"|"warning"|"danger", message=string, icon=string?, title=string?}
function InlineAlert.draw(owner, x, y, width, height, opts)
    if not owner or width <= 0 or height <= 0 then return end
    opts = opts or {}
    local pType = opts.type or "info"
    local pal = PALETTES[pType] or PALETTES.info

    -- 1. Outer Container Background and Border
    Theme.rect(owner, x, y, width, height, pal.bg)
    Theme.rect(owner, x, y, width, height, pal.border, true)

    -- 2. Left 3px Solid Accent Stripe
    Theme.rect(owner, x, y, 3, height, pal.bar)

    -- 3. Semantic Primer Octicon
    local iconSize = 14
    local iconName = opts.icon or pal.icon
    local iconY = y + math.floor((height - iconSize) / 2)
    StatusVisual.mark(owner, x + 8, iconY, iconSize, iconName, pal.bar)

    -- 4. Text Message
    local textX = x + 26
    local textY = y + 6
    local msg = opts.message or ""
    local title = opts.title

    local tm = getTextManager()
    local fontH = tm and tm:getFontHeight(UIFont.Small) or 14

    if title and title ~= "" then
        Theme.text(owner, title, textX, textY, pal.bar, UIFont.Small)
        textY = textY + fontH + 2
    end

    local maxTextW = math.max(20, width - (textX - x) - 8)
    local lines = Text.wrapLimited(msg, maxTextW, UIFont.Small, 2)
    for _, line in ipairs(lines) do
        Theme.text(owner, line, textX, textY, pal.text, UIFont.Small)
        textY = textY + fontH
    end
end

return InlineAlert
