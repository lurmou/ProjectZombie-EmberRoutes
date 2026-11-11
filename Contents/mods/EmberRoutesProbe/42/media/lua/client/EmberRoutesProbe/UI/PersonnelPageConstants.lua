-- PersonnelPageConstants.lua - EmberRoutes UI
-- Shared helpers for the personnel page: i18n text helpers, the
-- priority-colour table and the bounds-rect helper. No behaviour,
-- no state; required by the page and its split-out mixin modules.
-- Moved verbatim from PersonnelPage.lua (helpers become C.* so the
-- split modules can share them); behaviour unchanged.

local C = {}

function C.text(key,...) return getText('IGUI_EmberRoutesProbe_Personnel_'..key,...) end
function C.pubText(key,...) return getText('IGUI_EmberRoutesProbe_Public_'..key,...) end
function C.tr(key,fallback) local v=getTextOrNull(key) return v or fallback or key end

C.PRIORITY_COLORS={
    [0]={bg={r=0.18,g=0.20,b=0.22,a=0.8},border={r=0.35,g=0.35,b=0.40,a=0.9},text={r=0.50,g=0.55,b=0.60,a=1.0}},
    [1]={bg={r=0.35,g=0.28,b=0.10,a=0.9},border={r=1.00,g=0.78,b=0.25,a=1.0},text={r=1.00,g=0.85,b=0.30,a=1.0}},
    [2]={bg={r=0.12,g=0.28,b=0.20,a=0.9},border={r=0.35,g=0.88,b=0.60,a=1.0},text={r=0.40,g=0.92,b=0.65,a=1.0}},
    [3]={bg={r=0.10,g=0.22,b=0.32,a=0.9},border={r=0.25,g=0.75,b=1.00,a=0.9},text={r=0.35,g=0.80,b=1.00,a=1.0}},
    [4]={bg={r=0.14,g=0.16,b=0.20,a=0.8},border={r=0.40,g=0.48,b=0.55,a=0.8},text={r=0.60,g=0.68,b=0.75,a=1.0}}
}

function C.initRect(t, defH)
    t = t or {}
    t.x = t.x or 0; t.y = t.y or 0; t.width = t.width or 0; t.height = t.height or (defH or 0); t.visible = (t.visible ~= false)
    return t
end

return C
