--[[
    SemanticBadge.lua - EmberRoutes UI
    High-contrast semantic state badges and glyphs.
    Eliminates ugly debug prefixes like [STORED/仓内就绪] and transforms them into
    clean, localized, color-coded visual pills with distinct geometric glyphs.
]]

local Theme = require "EmberRoutesProbe/UI/Theme"
local Text = require "EmberRoutesProbe/UI/Text"
local UICache = require "EmberRoutesProbe/UI/UICache"
local Visual = require "EmberRoutesProbe/UI/StatusVisual"

local SemanticBadge = {}

local function text(key)
    local value = getTextOrNull and getTextOrNull(key)
    return value or key
end

-- Status marks are drawn geometrically by StatusVisual (UI master guide 5.2:
-- no text or texture glyphs). Each definition maps to one distinct silhouette.
-- Each DEFINITIONS entry carries its own markState (one unique silhouette).
-- Width reserved for the geometric mark inside a badge capsule.
SemanticBadge.ICON_SLOT = 16

local DEFINITIONS = {
    RECONCILE = {
        markState = "reconcile",
        labelKey = "IGUI_EmberRoutesProbe_Badge_reconcile",
        color = {r = 1.00, g = 0.78, b = 0.25, a = 1.0},
        bg = {r = 0.25, g = 0.20, b = 0.08, a = 0.90},
        border = {r = 0.70, g = 0.55, b = 0.18, a = 0.85}
    },
    STORED = {
        markState = "done",
        labelKey = "IGUI_EmberRoutesProbe_Badge_stored",
        color = {r = 0.35, g = 0.88, b = 0.60, a = 1.0},
        bg = {r = 0.10, g = 0.22, b = 0.16, a = 0.90},
        border = {r = 0.25, g = 0.65, b = 0.45, a = 0.85}
    },
    PROCESSING = {
        markState = "active",
        labelKey = "IGUI_EmberRoutesProbe_Badge_processing",
        color = {r = 1.00, g = 0.78, b = 0.25, a = 1.0},
        bg = {r = 0.25, g = 0.20, b = 0.08, a = 0.90},
        border = {r = 0.70, g = 0.55, b = 0.18, a = 0.85}
    },
    MISSING = {
        markState = "blocked",
        labelKey = "IGUI_EmberRoutesProbe_Badge_missing",
        color = {r = 1.00, g = 0.42, b = 0.38, a = 1.0},
        bg = {r = 0.28, g = 0.10, b = 0.10, a = 0.90},
        border = {r = 0.75, g = 0.30, b = 0.28, a = 0.85}
    },
    TRANSIT = {
        markState = "transit",
        labelKey = "IGUI_EmberRoutesProbe_Badge_transit",
        color = {r = 0.25, g = 0.75, b = 1.00, a = 1.0},
        bg = {r = 0.08, g = 0.18, b = 0.26, a = 0.90},
        border = {r = 0.20, g = 0.52, b = 0.75, a = 0.85}
    },
    WAITING = {
        markState = "waiting",
        labelKey = "IGUI_EmberRoutesProbe_Badge_waiting",
        color = {r = 0.50, g = 0.64, b = 0.75, a = 1.0},
        bg = {r = 0.12, g = 0.15, b = 0.18, a = 0.90},
        border = {r = 0.35, g = 0.42, b = 0.50, a = 0.75}
    },
    IN_STORAGE = {
        markState = "waiting",
        labelKey = "IGUI_EmberRoutesProbe_Badge_inStorage",
        color = {r = 0.55, g = 0.70, b = 0.85, a = 1.0},
        bg = {r = 0.12, g = 0.16, b = 0.22, a = 0.90},
        border = {r = 0.30, g = 0.45, b = 0.60, a = 0.75}
    },
    WITHDRAWN = {
        markState = "neutral",
        labelKey = "IGUI_EmberRoutesProbe_Badge_staged",
        color = {r = 0.60, g = 0.70, b = 0.80, a = 1.0},
        bg = {r = 0.14, g = 0.16, b = 0.20, a = 0.90},
        border = {r = 0.40, g = 0.48, b = 0.55, a = 0.75}
    },
    PAUSED = {
        markState = "paused",
        labelKey = "IGUI_EmberRoutesProbe_Badge_paused",
        color = {r = 0.94, g = 0.73, b = 0.36, a = 1.0},
        bg = {r = 0.22, g = 0.18, b = 0.10, a = 0.90},
        border = {r = 0.65, g = 0.50, b = 0.25, a = 0.85}
    },
    STOPPING = {
        markState = "handoff",
        labelKey = "IGUI_EmberRoutesProbe_Badge_stopping",
        color = {r = 1.00, g = 0.60, b = 0.20, a = 1.0},
        bg = {r = 0.25, g = 0.15, b = 0.08, a = 0.90},
        border = {r = 0.70, g = 0.42, b = 0.15, a = 0.85}
    },
    RETURNING = {
        markState = "return",
        labelKey = "IGUI_EmberRoutesProbe_Badge_returning",
        color = {r = 0.65, g = 0.55, b = 0.85, a = 1.0},
        bg = {r = 0.16, g = 0.14, b = 0.22, a = 0.90},
        border = {r = 0.45, g = 0.38, b = 0.60, a = 0.85}
    },
    COMPLETED = {
        markState = "done",
        labelKey = "IGUI_EmberRoutesProbe_Badge_delivered",
        color = {r = 0.35, g = 0.88, b = 0.60, a = 1.0},
        bg = {r = 0.10, g = 0.22, b = 0.16, a = 0.90},
        border = {r = 0.25, g = 0.65, b = 0.45, a = 0.85}
    },
    DISCREPANCY = {
        markState = "reconcile",
        labelKey = "IGUI_EmberRoutesProbe_Badge_discrepancy",
        color = {r = 1.00, g = 0.42, b = 0.38, a = 1.0},
        bg = {r = 0.28, g = 0.10, b = 0.10, a = 0.90},
        border = {r = 0.75, g = 0.30, b = 0.28, a = 0.85}
    },
    SATISFIED = {
        markState = "done",
        labelKey = "IGUI_EmberRoutesProbe_Badge_satisfied",
        color = {r = 0.35, g = 0.88, b = 0.60, a = 1.0},
        bg = {r = 0.10, g = 0.22, b = 0.16, a = 0.90},
        border = {r = 0.25, g = 0.65, b = 0.45, a = 0.85}
    },
    RESTOCKING = {
        markState = "active",
        labelKey = "IGUI_EmberRoutesProbe_Badge_restocking",
        color = {r = 0.25, g = 0.75, b = 1.00, a = 1.0},
        bg = {r = 0.08, g = 0.18, b = 0.26, a = 0.90},
        border = {r = 0.20, g = 0.52, b = 0.75, a = 0.85}
    },
    DISABLED = {
        markState = "neutral",
        labelKey = "IGUI_EmberRoutesProbe_Badge_disabled",
        color = {r = 0.50, g = 0.55, b = 0.60, a = 1.0},
        bg = {r = 0.12, g = 0.13, b = 0.14, a = 0.80},
        border = {r = 0.30, g = 0.32, b = 0.35, a = 0.70}
    },
    WORK = {
        markState = "active",
        glyph = "hammer",
        labelKey = "IGUI_EmberRoutesProbe_Overview_workBadge",
        color = {r = 0.25, g = 0.75, b = 1.00, a = 1.0},
        bg = {r = 0.08, g = 0.18, b = 0.26, a = 0.90},
        border = {r = 0.20, g = 0.52, b = 0.75, a = 0.85}
    },
    LEISURE = {
        markState = "waiting",
        glyph = "moon",
        labelKey = "IGUI_EmberRoutesProbe_Overview_leisureBadge",
        color = {r = 0.35, g = 0.88, b = 0.60, a = 1.0},
        bg = {r = 0.10, g = 0.22, b = 0.16, a = 0.90},
        border = {r = 0.25, g = 0.65, b = 0.45, a = 0.85}
    }
}

-- Reuse visual tones; custody labels remain distinct from processing/completion.
for key,tone in pairs({STATION='PROCESSING',RETURNED='STORED',CONSUMED='DISABLED'}) do
    local base=DEFINITIONS[tone]
    DEFINITIONS[key]={labelKey='IGUI_EmberRoutesProbe_Badge_'..string.lower(key),
        markState=base.markState,color=base.color,bg=base.bg,border=base.border}
end

---Clean raw strings containing [DEBUG_KEY/文案] into pure clean badges
---Resolve a semantic status key into a fully measured presentation descriptor.
---@param key string
---@param customLabel string?
---@return table
function SemanticBadge.resolve(key, customLabel)
    local def = DEFINITIONS[key]
    local label = customLabel or (def and def.labelKey and text(def.labelKey)) or key or ""
    local color = def and def.color or Theme.textColor
    local bg = def and def.bg or Theme.control
    local border = def and def.border or Theme.border

    return {
        id = key,
        label = label,
        markState = def and def.markState or "neutral",
        glyph = def and def.glyph or nil,
        color = color,
        bg = bg,
        border = border,
        displayText = label
    }
end

---Draw a clean semantic badge at the given coordinates. Zero GC in draw loop.
---@param owner ISPanel
---@param x number
---@param y number
---@param width number
---@param height number
---@param descriptor table|string Either result from SemanticBadge.resolve or a statusKey string
function SemanticBadge.draw(owner, x, y, width, height, descriptor)
    local d = type(descriptor) == "table" and descriptor or SemanticBadge.resolve(descriptor)
    if not d then return end

    -- Background Capsule
    Theme.rect(owner, x, y, width, height, d.bg)
    Theme.rect(owner, x, y, width, height, d.border, true)

    -- Geometric status mark + label only (never a text glyph).
    local h = d.fontHeight or getTextManager():getFontHeight(UIFont.Small)
    local label = d.displayText or d.label
    local tw = d.textWidth or UICache.measure(UIFont.Small, label)
    local slot = SemanticBadge.ICON_SLOT
    local markSize = math.max(6, math.min(height - 6, slot - 4))
    local startX = x + math.max(2, math.floor((width - slot - tw) / 2))
    local ty = y + math.floor((height - h) / 2)
    -- Semantic glyph when defined (shape = meaning), else the state mark.
    -- The larger 16px slot lets a 6x6 glyph render at 12px (2px grid pitch).
    if d.glyph and Visual.glyph(owner, startX, y + math.floor((height - markSize) / 2),
        markSize, d.glyph, d.color) then
        -- glyph drawn
    else
        Visual.mark(owner, startX, y + math.floor((height - markSize) / 2),
            markSize, d.markState, d.color)
    end
    Theme.text(owner, label, startX + slot, ty, d.color)
end

return SemanticBadge
