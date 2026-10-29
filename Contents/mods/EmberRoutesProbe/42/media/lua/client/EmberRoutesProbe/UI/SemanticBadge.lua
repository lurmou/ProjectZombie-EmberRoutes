--[[
    SemanticBadge.lua - EmberRoutes UI
    High-contrast semantic state badges and glyphs.
    Eliminates ugly debug prefixes like [STORED/仓内就绪] and transforms them into
    clean, localized, color-coded visual pills with distinct geometric glyphs.
]]

local Theme = require "EmberRoutesProbe/UI/Theme"
local Text = require "EmberRoutesProbe/UI/Text"

local SemanticBadge = {}

local function text(key)
    local value = getTextOrNull and getTextOrNull(key)
    return value or key
end

local function makeStr(codepoints, fallback)
    local ok, str = pcall(string.char, unpack(codepoints))
    if ok and str and #str == #codepoints then return str end
    return fallback
end

local GLYPH_CHECK = makeStr({10004}, "✔")
local GLYPH_DOT = makeStr({9679}, "●")
local GLYPH_CIRCLE = makeStr({9675}, "○")
local GLYPH_TRIANGLE = makeStr({9650}, "▲")
local GLYPH_DIAMOND = makeStr({9670}, "◆")
local GLYPH_PAUSE = "❚❚"
local GLYPH_ARROW = makeStr({8594}, "→")
local GLYPH_SQUARE = makeStr({9632}, "■")
local GLYPH_RETURN = makeStr({8617}, "⮌")
local GLYPH_DASH = "—"

local function isChinese()
    local resolve = _G.getTextOrNull
    if type(resolve) == "function" then
        local t = resolve("IGUI_EmberRoutesProbe_Monitor_crafting")
        if t and t ~= "Crafting job" and t ~= "IGUI_EmberRoutesProbe_Monitor_crafting" then
            return true
        end
    end
    local q = getText("IGUI_EmberRoutesProbe_Settlement_quantity")
    return q == "数量"
end

local DEFINITIONS = {
    STORED = {
        labelKey = "IGUI_EmberRoutesProbe_Badge_stored", glyph = GLYPH_CHECK,
        color = {r = 0.35, g = 0.88, b = 0.60, a = 1.0},
        bg = {r = 0.10, g = 0.22, b = 0.16, a = 0.90},
        border = {r = 0.25, g = 0.65, b = 0.45, a = 0.85}
    },
    PROCESSING = {
        labelKey = "IGUI_EmberRoutesProbe_Badge_processing", glyph = GLYPH_DOT,
        color = {r = 1.00, g = 0.78, b = 0.25, a = 1.0},
        bg = {r = 0.25, g = 0.20, b = 0.08, a = 0.90},
        border = {r = 0.70, g = 0.55, b = 0.18, a = 0.85}
    },
    MISSING = {
        labelKey = "IGUI_EmberRoutesProbe_Badge_missing", glyph = GLYPH_TRIANGLE,
        color = {r = 1.00, g = 0.42, b = 0.38, a = 1.0},
        bg = {r = 0.28, g = 0.10, b = 0.10, a = 0.90},
        border = {r = 0.75, g = 0.30, b = 0.28, a = 0.85}
    },
    TRANSIT = {
        labelKey = "IGUI_EmberRoutesProbe_Badge_transit", glyph = GLYPH_ARROW,
        color = {r = 0.25, g = 0.75, b = 1.00, a = 1.0},
        bg = {r = 0.08, g = 0.18, b = 0.26, a = 0.90},
        border = {r = 0.20, g = 0.52, b = 0.75, a = 0.85}
    },
    WAITING = {
        labelKey = "IGUI_EmberRoutesProbe_Badge_waiting", glyph = GLYPH_CIRCLE,
        color = {r = 0.50, g = 0.64, b = 0.75, a = 1.0},
        bg = {r = 0.12, g = 0.15, b = 0.18, a = 0.90},
        border = {r = 0.35, g = 0.42, b = 0.50, a = 0.75}
    },
    WITHDRAWN = {
        labelKey = "IGUI_EmberRoutesProbe_Badge_staged", glyph = GLYPH_DOT,
        color = {r = 0.60, g = 0.70, b = 0.80, a = 1.0},
        bg = {r = 0.14, g = 0.16, b = 0.20, a = 0.90},
        border = {r = 0.40, g = 0.48, b = 0.55, a = 0.75}
    },
    PAUSED = {
        labelKey = "IGUI_EmberRoutesProbe_Badge_paused", glyph = GLYPH_PAUSE,
        color = {r = 0.94, g = 0.73, b = 0.36, a = 1.0},
        bg = {r = 0.22, g = 0.18, b = 0.10, a = 0.90},
        border = {r = 0.65, g = 0.50, b = 0.25, a = 0.85}
    },
    STOPPING = {
        labelKey = "IGUI_EmberRoutesProbe_Badge_stopping", glyph = GLYPH_SQUARE,
        color = {r = 1.00, g = 0.60, b = 0.20, a = 1.0},
        bg = {r = 0.25, g = 0.15, b = 0.08, a = 0.90},
        border = {r = 0.70, g = 0.42, b = 0.15, a = 0.85}
    },
    RETURNING = {
        labelKey = "IGUI_EmberRoutesProbe_Badge_returning", glyph = GLYPH_RETURN,
        color = {r = 0.65, g = 0.55, b = 0.85, a = 1.0},
        bg = {r = 0.16, g = 0.14, b = 0.22, a = 0.90},
        border = {r = 0.45, g = 0.38, b = 0.60, a = 0.85}
    },
    COMPLETED = {
        labelKey = "IGUI_EmberRoutesProbe_Badge_delivered", glyph = GLYPH_CHECK,
        color = {r = 0.35, g = 0.88, b = 0.60, a = 1.0},
        bg = {r = 0.10, g = 0.22, b = 0.16, a = 0.90},
        border = {r = 0.25, g = 0.65, b = 0.45, a = 0.85}
    },
    DISCREPANCY = {
        labelKey = "IGUI_EmberRoutesProbe_Badge_discrepancy", glyph = GLYPH_DIAMOND,
        color = {r = 1.00, g = 0.42, b = 0.38, a = 1.0},
        bg = {r = 0.28, g = 0.10, b = 0.10, a = 0.90},
        border = {r = 0.75, g = 0.30, b = 0.28, a = 0.85}
    },
    SATISFIED = {
        labelKey = "IGUI_EmberRoutesProbe_Badge_satisfied", glyph = GLYPH_CHECK,
        color = {r = 0.35, g = 0.88, b = 0.60, a = 1.0},
        bg = {r = 0.10, g = 0.22, b = 0.16, a = 0.90},
        border = {r = 0.25, g = 0.65, b = 0.45, a = 0.85}
    },
    RESTOCKING = {
        labelKey = "IGUI_EmberRoutesProbe_Badge_restocking", glyph = GLYPH_DOT,
        color = {r = 0.25, g = 0.75, b = 1.00, a = 1.0},
        bg = {r = 0.08, g = 0.18, b = 0.26, a = 0.90},
        border = {r = 0.20, g = 0.52, b = 0.75, a = 0.85}
    },
    DISABLED = {
        labelKey = "IGUI_EmberRoutesProbe_Badge_disabled", glyph = GLYPH_DASH,
        color = {r = 0.50, g = 0.55, b = 0.60, a = 1.0},
        bg = {r = 0.12, g = 0.13, b = 0.14, a = 0.80},
        border = {r = 0.30, g = 0.32, b = 0.35, a = 0.70}
    }
}

---Clean raw strings containing [DEBUG_KEY/文案] into pure clean badges
---@param raw string
---@return string
function SemanticBadge.cleanRawString(raw)
    if not raw or raw == "" then return "" end
    -- Check if it matches [KEY/TEXT] pattern
    local key, rawText = raw:match("^%[([%w_]+)/(.+)%]$")
    if key and rawText then
        local def = DEFINITIONS[key]
        local glyph = def and def.glyph and (def.glyph .. " ") or ""
        return "[" .. glyph .. rawText .. "]"
    end
    return raw
end

---Resolve a semantic status key into a fully measured presentation descriptor.
---@param key string
---@param customLabel string?
---@return table
function SemanticBadge.resolve(key, customLabel)
    local def = DEFINITIONS[key]
    local zh = isChinese()
    local label = customLabel or (def and def.labelKey and text(def.labelKey)) or key or ""
    local glyph = def and def.glyph or ""
    local color = def and def.color or Theme.textColor
    local bg = def and def.bg or Theme.control
    local border = def and def.border or Theme.border

    return {
        id = key,
        label = label,
        glyph = glyph,
        color = color,
        bg = bg,
        border = border,
        displayText = (glyph ~= "" and (glyph .. " ") or "") .. label
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

    -- Glyph & Label
    local h = getTextManager():getFontHeight(UIFont.Small)
    local tm = getTextManager()
    local fullText = d.displayText or d.label
    local tw = tm:MeasureStringX(UIFont.Small, fullText)
    local tx = x + math.max(2, math.floor((width - tw) / 2))
    local ty = y + math.floor((height - h) / 2)

    Theme.text(owner, fullText, tx, ty, d.color)
end

return SemanticBadge
