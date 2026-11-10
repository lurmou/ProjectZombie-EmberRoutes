-- SettlementOverviewConstants.lua - EmberRoutes UI
-- Shared constants and pure helpers for the settlement overview page:
-- card/drawer geometry, order stage labels and glyphs, stockpile colours,
-- static prerender draw arguments, compass labels, and the compass / zone
-- lookup helpers. No behaviour, no state; required by the page and its
-- split-out mixin modules. Moved verbatim from SettlementOverviewPage.lua.

local C = {}

C.BASE_CARD_H = 54
C.DRAWER_H    = 140

C.STAGE_LABELS = {
    getText('IGUI_EmberRoutesProbe_Stage_Prepare'),
    getText('IGUI_EmberRoutesProbe_Stage_Work'),
    getText('IGUI_EmberRoutesProbe_Stage_Collect'),
    getText('IGUI_EmberRoutesProbe_Stage_Deliver')
}
C.STAGE_INDEX = {PREPARE = 1, WORK = 2, COLLECT = 3, DELIVER = 4}
-- Shape encodes the stage meaning, colour encodes the state. The glyph names
-- are consumed by StatusVisual.glyph; unknown label keys degrade to state marks.
C.DEFAULT_STAGE_GLYPHS = {"box", "hammer", "arrowDown", "arrowRight"}
C.CUSTOM_STAGE_GLYPHS = {
    IGUI_EmberRoutesProbe_Order_stage_source = "box",
    IGUI_EmberRoutesProbe_Order_stage_staging = "arrowDown",
    IGUI_EmberRoutesProbe_Order_stage_craft = "hammer",
    IGUI_EmberRoutesProbe_Order_stage_store = "box",
}

C.STOCK_COLORS = {
    water   = {r = 0.25, g = 0.70, b = 0.95, a = 0.90},
    meals   = {r = 0.95, g = 0.75, b = 0.30, a = 0.90},
    crops   = {r = 0.45, g = 0.85, b = 0.45, a = 0.90},
    medical = {r = 0.95, g = 0.45, b = 0.55, a = 0.90},
    wood    = {r = 0.80, g = 0.65, b = 0.45, a = 0.90}
}

-- Static draw arguments: prerender runs every frame and must not allocate.
C.DRIVE_STRIP_BG  = {r = 0.08, g = 0.10, b = 0.13, a = 0.75}
C.INJURY_JUMP_BG  = {r = 0.35, g = 0.15, b = 0.15, a = 0.85}
C.DRIVE_GEAR_OPTS = {drivenAngle = -math.pi / 4}
C.ROLLER_OPTS     = {digitWidth = 14, digitHeight = 18, gap = 2, font = UIFont.Small}
C.DIAL_OPTS       = {mode = "health"}

C.DIRECTION_LABELS = {
    N  = getText('IGUI_EmberRoutesProbe_Overview_dirN'),
    NE = getText('IGUI_EmberRoutesProbe_Overview_dirNE'),
    E  = getText('IGUI_EmberRoutesProbe_Overview_dirE'),
    SE = getText('IGUI_EmberRoutesProbe_Overview_dirSE'),
    S  = getText('IGUI_EmberRoutesProbe_Overview_dirS'),
    SW = getText('IGUI_EmberRoutesProbe_Overview_dirSW'),
    W  = getText('IGUI_EmberRoutesProbe_Overview_dirW'),
    NW = getText('IGUI_EmberRoutesProbe_Overview_dirNW')
}

-- World +Y runs south, so a negative dy points north. Eight-way scalar
-- classification avoids trig and keeps the label language-neutral.
function C.compassOf(dx, dy)
    local ax, ay = math.abs(dx), math.abs(dy)
    if ax < ay * 0.38 then return dy < 0 and 'N' or 'S' end
    if ay < ax * 0.38 then return dx > 0 and 'E' or 'W' end
    if dx > 0 then return dy < 0 and 'NE' or 'SE' end
    return dy < 0 and 'NW' or 'SW'
end

-- Resolve a real, user-named life/work zone for a world tile. The zone registry
-- lives client-side and is optional (single-player preview hosts may not have
-- any designated zones), so every step is guarded.
function C.areaNameAt(scope, x, y, z)
    if not scope or type(x) ~= 'number' or type(y) ~= 'number' then return nil end
    local ok, Zones = pcall(require, 'EmberRoutesProbe/Settlement/SettlementZones')
    if not ok or type(Zones) ~= 'table' or not Zones.list or not Zones.contains then return nil end
    local listedOk, zones = pcall(Zones.list, scope)
    if not listedOk or type(zones) ~= 'table' then return nil end
    local fx, fy = math.floor(x), math.floor(y)
    local fz = (type(z) == 'number') and math.floor(z) or nil
    for _, zone in ipairs(zones) do
        if zone.name and zone.enabled ~= false and Zones.contains(zone, fx, fy, fz) then
            return zone.name
        end
    end
    return nil
end

return C
