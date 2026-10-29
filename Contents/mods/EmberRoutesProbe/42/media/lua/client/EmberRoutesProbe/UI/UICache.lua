-- EmberRoutes UI Performance Cache & Zero-GC Constants
-- Eliminates runtime table allocations in render/prerender loops.
local UICache = {}

-- Static singleton color tables (immune to frame GC thrashing in Kahlua/JVM)
UICache.Colors = {
    SLOT_DEFAULT_BG = { r = 0.08, g = 0.09, b = 0.11, a = 0.90 },
    BADGE_BG        = { r = 0,    g = 0,    b = 0,    a = 0.75 },
    TOOLTIP_BG      = { r = 0.08, g = 0.10, b = 0.13, a = 0.95 },
    SEPARATOR       = { r = 0.20, g = 0.25, b = 0.30, a = 0.40 },
    TOOL_BORDER     = { r = 0.94, g = 0.73, b = 0.36, a = 1.00 },
    SUCCESS_TEXT    = { r = 0.35, g = 0.88, b = 0.60, a = 1.00 },
    ERROR_TEXT      = { r = 0.95, g = 0.35, b = 0.30, a = 1.00 },
    MUTED_BORDER    = { r = 0.30, g = 0.35, b = 0.40, a = 0.45 },
    PANEL_BG        = { r = 0.06, g = 0.09, b = 0.13, a = 0.95 }
}

-- Text measurement memoization cache to avoid cross-language JNI FontManager calls.
-- Two-level key: font object identity first, text second; tostring(font) per
-- call was itself a per-frame string allocation.
local measureCache = {}
local countWidthCache = {}

---@param font any
---@param text string
---@return number
function UICache.measureText(font, text)
    if not text or text == "" then return 0 end
    local perFont = measureCache[font]
    if not perFont then perFont = {} measureCache[font] = perFont end
    local val = perFont[text]
    if not val then
        val = getTextManager():MeasureStringX(font, text)
        perFont[text] = val
    end
    return val
end

---@param countText string
---@return number
function UICache.measureCount(countText)
    if not countText or countText == "" then return 0 end
    local val = countWidthCache[countText]
    if not val then
        val = getTextManager():MeasureStringX(UIFont.Small, countText)
        countWidthCache[countText] = val
    end
    return val
end

function UICache.clear()
    measureCache = {}
    countWidthCache = {}
end

return UICache
