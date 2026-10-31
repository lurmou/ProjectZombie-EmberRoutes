-- Work Zone Selector and SettlementZones Linkage Unit Tests
local function assertEqual(a, b, msg)
    if a ~= b then
        error(string.format("ASSERTION FAILED: %s (expected %s, got %s)", tostring(msg), tostring(b), tostring(a)))
    end
end

package.path = "Contents/mods/EmberRoutesProbe/42/media/lua/client/?.lua;Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;" .. package.path

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
    return cls
end

local function makeMockButton()
    local cls = makeMockClass('ISButton')
    function cls:new(x, y, w, h, title, target, onclick)
        local o = setmetatable({ x = x or 0, y = y or 0, width = w or 400, height = h or 300, title = title, target = target, onclick = onclick }, self)
        if o.initialise then o:initialise() end
        return o
    end
    return cls
end

_G.ISPanel = makeMockClass('ISPanel')
_G.ISButton = makeMockButton()
_G.ISScrollingListBox = makeMockClass('ISScrollingListBox')
_G.ISComboBox = makeMockClass('ISComboBox')
_G.ISCollapsableWindow = makeMockClass('ISCollapsableWindow')
_G.ISTextEntryBox = makeMockClass('ISTextEntryBox')

package.loaded['ISUI/ISPanel'] = _G.ISPanel
package.loaded['ISUI/ISButton'] = _G.ISButton
package.loaded['ISUI/ISScrollingListBox'] = _G.ISScrollingListBox
package.loaded['ISUI/ISComboBox'] = _G.ISComboBox
package.loaded['ISUI/ISCollapsableWindow'] = _G.ISCollapsableWindow
package.loaded['ISUI/ISTextEntryBox'] = _G.ISTextEntryBox

_G.UIFont = { Small = 1, Medium = 2, Large = 3 }
_G.Joypad = { AButton = 0, BButton = 1, XButton = 2, YButton = 3 }
_G.Events = { OnRenderTick = { Add = function() end, Remove = function() end } }
_G.getTextManager = function() return { getFontHeight = function() return 18 end, MeasureStringX = function() return 100 end } end
_G.getCore = function() return { getScreenWidth = function() return 1920 end, getScreenHeight = function() return 1080 end } end

-- Mock PZ environment
getText = function(key, ...)
    local map = {
        ["IGUI_EmberRoutesProbe_Settlement_summary"] = "已划定区域：%1 个区块 · 共 %2 格",
        ["IGUI_EmberRoutesProbe_Settlement_modeAdd"] = "➕ 框选添加",
        ["IGUI_EmberRoutesProbe_Settlement_modeRemove"] = "➖ 剔除挖空",
        ["IGUI_EmberRoutesProbe_Settlement_modeUndo"] = "↩ 撤销",
        ["IGUI_EmberRoutesProbe_Settlement_modeClear"] = "🗑 清空",
        ["IGUI_EmberRoutesProbe_Settlement_hintAdd"] = "点击并拖拽以添加区域",
        ["IGUI_EmberRoutesProbe_Settlement_hintRemove"] = "模式：剔除区域",
        ["IGUI_EmberRoutesProbe_LifeZone_create"] = "划定工作区域",
        ["IGUI_EmberRoutesProbe_LifeZone_defaultName"] = "工作区",
        ["IGUI_EmberRoutesProbe_LifeZone_selectionHint"] = "在窗口外拖拽选择区域",
        ["IGUI_EmberRoutesProbe_LifeZone_range"] = "%1x%2 (Z:%3)",
        ["IGUI_EmberRoutesProbe_Policy_clean_corpseZone"] = "尸体堆放划区",
        ["IGUI_EmberRoutesProbe_Policy_lumber_zone"] = "指定伐木区",
    }
    local str = map[key] or key
    local args = {...}
    if #args > 0 then
        for i, v in ipairs(args) do
            str = str:gsub("%%" .. i .. "%$?%a?", tostring(v))
        end
    end
    return str
end

getTextOrNull = function(key) return getText(key) end
local uuid=0
getRandomUUID = function() uuid=uuid+1 return "test-uuid-" .. tostring(uuid) end

local zoneName=ERTestTranslations and ERTestTranslations.TEST_WorkZoneName or 'Lumber zone'
-- Test 1: String replacement with %1, %1$s, %2, %2$s to verify no '$s' residue
print("=== Test 1: Testing String Formatter for Placeholders ===")
local rawEN = "Territory: %1$s area(s) · %2$s tiles"
local strTest = rawEN
local args = {1, 35}
for i, v in ipairs(args) do
    strTest = strTest:gsub("%%" .. i .. "%$?%a?", tostring(v))
end
assertEqual(strTest, "Territory: 1 area(s) · 35 tiles", "Residue test for %1$s")
print("PASS: Placeholders %1$s and %2$s formatted cleanly without $s residue.")

-- Test 2: SettlementZones with isWorkZone = true outside territory
print("=== Test 2: Testing SettlementZones WorkZone Saving ===")
local Zones = require("EmberRoutesProbe/SettlementZones")
local Ledger = require("EmberRoutesProbe/SettlementLedger")

-- Mock actor and ledger
local mockActor = {
    getZ = function() return 0 end,
    getX = function() return 100 end,
    getY = function() return 100 end,
    getIndex = function() return 0 end,
    getJoypadBind = function() return -1 end,
    Say = function(self, msg) end
}

local mockData = {
    byId = {
        ["settlement_test"] = {
            id = "settlement_test",
            name = "Test Settlement",
            owner = "player1",
            areas = {{ x = 10, y = 10, w = 20, h = 20, z = 0 }}
        }
    }
}
mockData.entries = mockData.byId

Ledger.data = function() return mockData end
Ledger.view = function(actor, scope) return mockData.byId[scope], nil end
Ledger.list = function() return { mockData.byId["settlement_test"] } end

-- Save a work zone far outside settlement areas (e.g. x=500, y=500)
local outsideArea = { x = 500, y = 500, w = 15, h = 15, z = 0 }
local saved, why = Zones.save(mockActor, "settlement_test", nil, nil, {
    name = zoneName,
    area = outsideArea,
    enabled = true,
    rules = {},
    isWorkZone = true -- Flag to allow outside zones
})

assert(saved ~= nil, "Zones.save should succeed for work zones outside settlement: " .. tostring(why))
assertEqual(saved.name, zoneName, "Saved zone name matches")
assertEqual(saved.area.x, 500, "Saved zone area X matches")
assertEqual(saved.isWorkZone, true, "Saved zone isWorkZone flag matches")
print("PASS: Work zone saved outside core settlement boundaries successfully.")

-- Test 3: LifeZoneSelector dragging, bounds persistence, and apply linkage
print("=== Test 3: Testing LifeZoneSelector dragging & no-rebound verification ===")
local LifeZoneSelector = require("EmberRoutesProbe/UI/LifeZoneSelector")

local callbackZone = nil
local selectorInstance = LifeZoneSelector:new(mockActor, "settlement_test", nil, {
    title = "划定伐木区",
    defaultName = zoneName,
    isWorkZone = true,
    onSaved = function(newZone)
        callbackZone = newZone
    end
})

assertEqual(selectorInstance.title, "划定伐木区", "Selector title set from options")
assertEqual(selectorInstance.defaultName, zoneName, "Default name set from options")
assertEqual(selectorInstance.isWorkZone, true, "isWorkZone set from options")

-- Mock point() to simulate mouse cursor in world
local mockMousePt = { x = 600, y = 600 }
selectorInstance.point = function(self) return mockMousePt.x, mockMousePt.y end
selectorInstance.overPanel = function(self) return false end

-- 1. Mouse down at (600, 600)
selectorInstance:onMouseDownOutside()
assert(selectorInstance.dragging == true, "Selector should be dragging after mouse down")
assertEqual(selectorInstance.anchor.x, 600, "Anchor X matches mouse down point")

-- 2. Mouse move to (614, 619) -> 15x20 area
mockMousePt.x, mockMousePt.y = 614, 619
selectorInstance:onMouseMoveOutside()
assert(selectorInstance.dragArea ~= nil, "dragArea should be populated during mouse move")
assertEqual(selectorInstance.dragArea.w, 15, "dragArea width is 15")
assertEqual(selectorInstance.dragArea.h, 20, "dragArea height is 20")

-- 3. Mouse up outside -> finishes drag into self.areas
selectorInstance:onMouseUpOutside()
assert(selectorInstance.dragging == false, "Dragging flag reset on mouse up")
assert(#selectorInstance.areas == 1, "self.areas must contain the dragged rectangle")
assertEqual(selectorInstance.areas[1].w, 15, "First area width is 15")
assertEqual(selectorInstance.areas[1].h, 20, "First area height is 20")

-- 3b. Add a second rectangle (e.g. 700, 700, 10x10)
mockMousePt.x, mockMousePt.y = 700, 700
selectorInstance:onMouseDownOutside()
mockMousePt.x, mockMousePt.y = 709, 709
selectorInstance:onMouseMoveOutside()
selectorInstance:onMouseUpOutside()
assert(#selectorInstance.areas == 2, "self.areas must contain both rectangles after second drag")
assertEqual(selectorInstance.areas[2].w, 10, "Second area width is 10")
assertEqual(selectorInstance.areas[2].h, 10, "Second area height is 10")

-- 4. Apply
selectorInstance.nameEntry = { getText = function() return (zoneName.." A") end }
selectorInstance.close = function(self) self.closed = true end
selectorInstance:apply()

assert(callbackZone ~= nil, "onSaved callback should have been executed with saved zone")
assertEqual(callbackZone.name, (zoneName.." A"), "Saved zone name verified")
assert(#callbackZone.areas == 2, "Saved composite zone must have 2 areas")
assertEqual(callbackZone.areas[1].x, 600, "Saved area 1 X matches")
assertEqual(callbackZone.areas[2].x, 700, "Saved area 2 X matches")
assert(Zones.contains(callbackZone, 605, 605, 0), "Zones.contains should match point in area 1")
assert(Zones.contains(callbackZone, 705, 705, 0), "Zones.contains should match point in area 2")
assert(not Zones.contains(callbackZone, 650, 650, 0), "Zones.contains should reject point outside both areas")
assert(callbackZone.isWorkZone == true, "Saved zone must retain isWorkZone == true")
local locOk, locWhy = Zones.location("settlement_test", callbackZone, { x = 605, y = 605, z = 0 })
assert(locOk == true, "Zones.location must accept outside work zone: " .. tostring(locWhy))
assert(selectorInstance.closed == true, "Selector closed after successful save")
print("PASS: LifeZoneSelector multi-rectangle CSG drag, persistence, and Zones.contains verified successfully.")

-- Test 4: Verify UI button click triggers polymorphic apply() via createChildren
print("=== Test 4: Testing UI Apply button click polymorphism ===")
local buttonClickedZone = nil
local uiSelector = LifeZoneSelector:new(mockActor, "settlement_test", nil, {
    title = "划定测试工作区",
    defaultName = "ButtonZone",
    isWorkZone = true,
    onSaved = function(newZone)
        buttonClickedZone = newZone
    end
})
uiSelector.areas = { { x = 800, y = 800, w = 10, h = 10, z = 0 } }
uiSelector:createChildren()
assert(uiSelector.buttonApply ~= nil, "buttonApply must exist on selector")
assert(uiSelector.nameEntry ~= nil, "nameEntry must exist on selector")
uiSelector.nameEntry.getText = function() return "ButtonZone" end
-- Simulate real ISButton onMouseUp:
uiSelector.buttonApply.onclick(uiSelector.buttonApply.target, uiSelector.buttonApply)
assert(buttonClickedZone ~= nil, "Clicking Apply button must execute polymorphic LifeZoneSelector:apply and invoke onSaved")
assertEqual(buttonClickedZone.name, "ButtonZone", "Zone saved via button click has correct name")
assertEqual(buttonClickedZone.isWorkZone, true, "Zone saved via button click has isWorkZone == true")
print("PASS: UI Apply button click polymorphic dispatch verified successfully.")

print("=== ALL WORK ZONE TESTS PASSED ===")
