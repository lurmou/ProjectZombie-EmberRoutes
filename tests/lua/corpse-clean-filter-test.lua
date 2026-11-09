-- Unit test: Corpse cleaning filter and LifeZoneSelector territory overlay
local n = 0
local function check(v, msg)
    n = n + 1
    assert(v, msg or ("Check " .. n .. " failed"))
end

local vanilla = 'D:/Software/GameApp/steam/steamapps/common/ProjectZomboid/media/lua/shared/'
package.path = "Contents/mods/EmberRoutesProbe/42/media/lua/client/?.lua;Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;" .. package.path

getText = function(s) return s end
isServer = function() return false end
isClient = function() return false end
isMultiplayer = function() return false end
getTimestampMs = function() return 1000 end

-- 1. Mock dependencies
local mockSettlement = {
    id = 'settlement_alpha',
    revision = 1,
    areas = {
        { x = 0, y = 0, w = 100, h = 100 }
    }
}

local mockCorpseZone = {
    id = 'zone_dump_1',
    settlementId = 'settlement_alpha',
    name = 'Corpse Dump',
    revision = 1,
    enabled = true,
    isWorkZone = false,
    areas = {
        { x = 10, y = 10, w = 10, h = 10, z = 0 }
    }
}

local mockZones = {
    [mockCorpseZone.id] = mockCorpseZone
}

local zonesRevision = 1
local Zones = {
    revision = function() return zonesRevision end,
    get = function(id) return mockZones[id] end,
    contains = function(zone, x, y, z)
        if not zone or zone.enabled == false then return false end
        for _, a in ipairs(zone.areas or {}) do
            local az = a.z or 0
            if (z == nil or z == az) and x >= a.x and x < a.x + a.w and y >= a.y and y < a.y + a.h then
                return true
            end
        end
        return false
    end
}
package.loaded['EmberRoutesProbe/Settlement/SettlementZones'] = Zones

local cleanPolicy = {
    cleanRadius = 50,
    cleanBloodOnly = false,
    corpseZoneId = 'zone_dump_1'
}

local policyRevision = 1
local Policy = {
    revision = function() return policyRevision end,
    get = function(scope, category)
        if category == 'cleaning' then return cleanPolicy end
        return {}
    end
}
package.loaded['EmberRoutesProbe/Work/JobPolicyService'] = Policy

local Spatial = {
    inside = function(entry, zone, x, y, z)
        -- Inside settlement (0..100, 0..100)
        return x >= 0 and x < 100 and y >= 0 and y < 100
    end
}
package.loaded['EmberRoutesProbe/Field/FieldSpatial'] = Spatial
package.loaded['EmberRoutesProbe/Work/LaborStore'] = {}
package.loaded['EmberRoutesProbe/Warehouse/ContainerRegistry'] = {
    data = function() return {} end
}
package.loaded['EmberRoutesProbe/Field/ToolRequirements'] = {}
package.loaded['EmberRoutesProbe/Field/ToolDiscovery'] = {}
package.loaded['EmberRoutesProbe/Kernel/RuntimeMetrics'] = {
    active = function() return false end
}
package.loaded['EmberRoutesProbe/Warehouse/WarehouseIndex'] = {}
package.loaded['EmberRoutesProbe/Work/LaborSignals'] = {}

local Discovery = require 'EmberRoutesProbe/Field/FieldDiscovery'

local mockNpc = {
    getX = function() return 20 end,
    getY = function() return 20 end,
    getZ = function() return 0 end
}

print("=== Test Set 1: FieldDiscovery.allowed corpse dump zone filtering ===")

-- Case 1: Corpse inside corpse dump zone (x=15, y=15) -> MUST BE REJECTED
local corpseInDump = { kind = 'CORPSE', x = 15, y = 15, z = 0, itemId = 101 }
local allowedInDump = Discovery.allowed('cleaning', mockSettlement, corpseInDump, mockNpc)
check(allowedInDump == false, "Corpse inside corpse dump zone must NOT be allowed (would cause infinite loop)")

-- Case 2: Corpse outside corpse dump zone, within settlement (x=30, y=30) -> MUST BE ALLOWED
local corpseOutsideDump = { kind = 'CORPSE', x = 30, y = 30, z = 0, itemId = 102 }
local allowedOutside = Discovery.allowed('cleaning', mockSettlement, corpseOutsideDump, mockNpc)
check(allowedOutside == true, "Corpse outside dump zone and within radius must be allowed")

-- Case 3: Stain inside corpse dump zone (x=15, y=15) -> MUST BE ALLOWED
local stainInDump = { kind = 'STAIN', x = 15, y = 15, z = 0 }
local allowedStain = Discovery.allowed('cleaning', mockSettlement, stainInDump, mockNpc)
check(allowedStain == true, "Stain inside corpse dump zone must still be allowed to be cleaned")

-- Case 4: Corpse dump zone is disabled -> corpse at (15, 15) is not in an active zone -> MUST BE ALLOWED
mockCorpseZone.enabled = false
zonesRevision = zonesRevision + 1
Discovery.invalidate()
local allowedWithDisabledZone = Discovery.allowed('cleaning', mockSettlement, corpseInDump, mockNpc)
check(allowedWithDisabledZone == true, "Corpse at location of disabled dump zone must be allowed (zone not active)")
mockCorpseZone.enabled = true
zonesRevision = zonesRevision + 1
Discovery.invalidate()

-- Case 5: Corpse dump zone belongs to another settlement -> MUST BE ALLOWED
mockCorpseZone.settlementId = 'settlement_beta'
zonesRevision = zonesRevision + 1
Discovery.invalidate()
local allowedOtherSettlement = Discovery.allowed('cleaning', mockSettlement, corpseInDump, mockNpc)
check(allowedOtherSettlement == true, "Dump zone of another settlement must not filter corpses of this settlement")
mockCorpseZone.settlementId = 'settlement_alpha'
zonesRevision = zonesRevision + 1
Discovery.invalidate()

-- Case 6: No corpseZoneId configured -> MUST BE ALLOWED (if inside settlement)
cleanPolicy.corpseZoneId = ''
policyRevision = policyRevision + 1
Discovery.invalidate()
local allowedNoZoneConfigured = Discovery.allowed('cleaning', mockSettlement, corpseInDump, mockNpc)
check(allowedNoZoneConfigured == true, "When corpseZoneId is empty string, corpse must pass dump filter")
cleanPolicy.corpseZoneId = 'zone_dump_1'
policyRevision = policyRevision + 1
Discovery.invalidate()

-- Case 7: Corpse too far away (> cleanRadius 50) -> MUST BE REJECTED
local farCorpse = { kind = 'CORPSE', x = 90, y = 90, z = 0, itemId = 103 }
local allowedFar = Discovery.allowed('cleaning', mockSettlement, farCorpse, mockNpc)
check(allowedFar == false, "Corpse beyond cleanRadius must be rejected")

print("PASS: All 7 FieldDiscovery.allowed corpse filter checks passed.")

print("=== Test Set 2: LifeZoneSelector settlement boundary rendering ===")

-- Mock UI environment for LifeZoneSelector
local highlightsDrawn = {}
_G.addAreaHighlightForPlayer = function(playerNum, x1, y1, x2, y2, z, r, g, b, a)
    highlightsDrawn[#highlightsDrawn + 1] = {
        playerNum = playerNum,
        x1 = x1, y1 = y1, x2 = x2, y2 = y2, z = z,
        r = r, g = g, b = b, a = a
    }
end

local mockActor = {
    getIndex = function() return 0 end,
    getPlayerNum = function() return 0 end,
    getX = function() return 0 end,
    getY = function() return 0 end,
    getZ = function() return 0 end,
    isDead = function() return false end,
    getJoypadBind = function() return -1 end
}

local Ledger = {
    view = function(actor, scope)
        if scope == mockSettlement.id then return mockSettlement end
        return nil
    end,
    get = function(scope)
        if scope == mockSettlement.id then return mockSettlement end
        return nil
    end,
    data = function() return {} end
}
package.loaded['EmberRoutesProbe/Settlement/SettlementLedger'] = Ledger

-- Mock ISCollapsableWindow and base classes
local function makeMockClass(name)
    local cls = { Type = name }
    cls.__index = cls
    function cls:derive(n)
        local derived = { Type = n }
        derived.__index = derived
        setmetatable(derived, self)
        return derived
    end
    function cls:new(x, y, w, h, ...)
        local o = setmetatable({ x = x or 0, y = y or 0, width = w or 400, height = h or 300 }, self)
        if o.initialise then o:initialise(...) end
        return o
    end
    function cls:initialise() end
    function cls:createChildren() end
    function cls:addChild() end
    function cls:addToUIManager() end
    function cls:removeFromUIManager() end
    function cls:close() end
    function cls:setWantKeyEvents() end
    function cls:titleBarHeight() return 20 end
    function cls:isVisible() return true end
    return cls
end

_G.ISPanel = makeMockClass('ISPanel')
_G.ISCollapsableWindow = makeMockClass('ISCollapsableWindow')
_G.ISTextEntryBox = makeMockClass('ISTextEntryBox')
_G.ISButton = makeMockClass('ISButton')

package.loaded['ISUI/ISPanel'] = _G.ISPanel
package.loaded['ISUI/ISButton'] = _G.ISButton
package.loaded['ISUI/ISCollapsableWindow'] = _G.ISCollapsableWindow
package.loaded['ISUI/ISTextEntryBox'] = _G.ISTextEntryBox
_G.UIFont = { Small = 1 }
_G.getTextManager = function() return { getFontHeight = function() return 16 end, MeasureStringX = function() return 10 end } end
_G.getCore = function() return { getScreenWidth = function() return 1920 end, getScreenHeight = function() return 1080 end } end

local LifeZoneSelector = require 'EmberRoutesProbe/UI/LifeZoneSelector'
local selector = LifeZoneSelector:new(mockActor, 'settlement_alpha', nil, {
    title = '划定尸体堆放区',
    defaultName = 'Corpse Zone',
    isWorkZone = false
})

selector.areas = {
    { x = 10, y = 10, w = 20, h = 20, z = 0 }
}
selector.previewZ = 0
selector.lockedZ = 0
selector.overPanel = function() return false end
selector.point = function() return 0, 0 end

highlightsDrawn = {}
selector:renderWorldHighlights()

check(#highlightsDrawn >= 2, "Expected at least 2 highlight draws (settlement boundary + zone areas), got " .. #highlightsDrawn)

-- Check territory overlay highlight (cyan/blue: r=0.20, g=0.60, b=0.95, a=0.18)
local foundSettlementHighlight = false
local foundZoneHighlight = false

for _, h in ipairs(highlightsDrawn) do
    if math.abs(h.r - 0.20) < 0.01 and math.abs(h.g - 0.60) < 0.01 and math.abs(h.b - 0.95) < 0.01 then
        foundSettlementHighlight = true
        check(h.x1 == 0 and h.y1 == 0 and h.x2 == 100 and h.y2 == 100, "Settlement territory area coordinates match mock")
        check(math.abs(h.a - 0.18) < 0.01, "Settlement territory overlay alpha matches 0.18")
    elseif math.abs(h.r - 0.95) < 0.01 and math.abs(h.g - 0.78) < 0.01 and math.abs(h.b - 0.20) < 0.01 then
        foundZoneHighlight = true
        check(h.x1 == 10 and h.y1 == 10 and h.x2 == 30 and h.y2 == 30, "Zone confirmed area coordinates match")
    end
end

check(foundSettlementHighlight, "Parent settlement territory must be rendered as translucent highlight overlay")
check(foundZoneHighlight, "Zone's own confirmed area must be rendered on top")

print("PASS: LifeZoneSelector territory overlay and zone highlights verified.")
print("PASS " .. n .. " corpse cleaning filter and zone boundary tests completed successfully.")