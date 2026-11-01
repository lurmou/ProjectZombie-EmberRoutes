-- TooltipManager lifecycle regression tests.
--
-- Runs in the installed PZ Kahlua runtime.
-- UIManager and native ISUI controls are mocked.
--
-- This test does NOT claim to replace B42 in-game verification.

local checks = 0
local function check(value, message)
    assert(value, message)
    checks = checks + 1
end

-- Preserve the shared Kahlua test environment.
local previousGetCore = getCore
local previousGetMouseX = getMouseX
local previousGetMouseY = getMouseY

local screenWidth = 1920
local screenHeight = 1080
local mouseX = 100
local mouseY = 200

getCore = function()
    return {
        getScreenWidth = function() return screenWidth end,
        getScreenHeight = function() return screenHeight end
    }
end

getMouseX = function() return mouseX end
getMouseY = function() return mouseY end

local TooltipManager = require 'EmberRoutesProbe/UI/TooltipManager'
TooltipManager.clearAll()

local function makeTooltip()
    return {
        x = 0,
        y = 0,
        w = 200,
        h = 50,
        visible = false,
        added = false,
        followMouse = true,
        getIsVisible = function(self) return self.visible end,
        setVisible = function(self, value) self.visible = value end,
        getWidth = function(self) return self.w end,
        getHeight = function(self) return self.h end,
        setX = function(self, value) self.x = value end,
        setY = function(self, value) self.y = value end,
        setName = function(self, value) self.name = value end,
        removeFromUIManager = function(self)
            self.added = false
            self.visible = false
        end
    }
end

local function makeWidget()
    return {
        tooltipUI = makeTooltip(),
        tooltip = "initial",
        rendered = false,
        prerender = function(self)
            self.rendered = true
            return "rendered" end
    }
end

----------------------------------------------------------------
-- 1. Positioning and screen-edge correction
----------------------------------------------------------------
local page = { name = "PageA" }
local panel = { parent = page }
local w1 = makeWidget()
local originalPrerender = w1.prerender

TooltipManager.attach(w1, "prerender", panel)
check(
    w1.prerender ~= originalPrerender,
    "register installs native method wrapper"
)

w1.tooltipUI:setVisible(true)
w1:prerender()
check(w1.rendered, "native prerender executes")
check(
    w1.tooltipUI.x == 132 and w1.tooltipUI.y == 210,
    "mouse offset is applied"
)

----------------------------------------------------------------
-- 2. Screen-edge clamping
----------------------------------------------------------------
mouseX = 1850
mouseY = 1050
w1:prerender()

check(
    w1.tooltipUI.x <= screenWidth - w1.tooltipUI.w,
    "tooltip is clamped horizontally"
)
check(
    w1.tooltipUI.y <= screenHeight - w1.tooltipUI.h,
    "tooltip is clamped vertically"
)

----------------------------------------------------------------
-- 3. Update tooltip content
----------------------------------------------------------------
TooltipManager.update(w1, "Updated text")
check(
    w1.tooltip == "Updated text",
    "tooltip content updated"
)
check(
    w1.tooltipUI.name == "Updated text",
    "visible tooltip name updated"
)

----------------------------------------------------------------
-- 4. Single-widget clear is temporary
----------------------------------------------------------------
TooltipManager.clear(w1)
check(
    not w1.tooltipUI:getIsVisible(),
    "clear hides tooltip"
)
check(
    w1.prerender ~= originalPrerender,
    "clear preserves method registration"
)

----------------------------------------------------------------
-- 5. Dismiss owner preserves registration
----------------------------------------------------------------
w1.tooltipUI:setVisible(true)
local hookedPrerender = w1.prerender

TooltipManager.dismissOwner(page)
check(
    not w1.tooltipUI:getIsVisible(),
    "dismissOwner hides descendant tooltip"
)
check(
    w1.prerender == hookedPrerender,
    "dismissOwner preserves Hook"
)

-- Simulate page reactivation and hover.
w1.tooltipUI:setVisible(true)
w1:prerender()
check(
    w1.tooltipUI:getIsVisible(),
    "widget remains usable after reactivation"
)
check(
    w1.prerender == hookedPrerender,
    "reactivation does not duplicate Hook"
)

----------------------------------------------------------------
-- 6. Legacy clearOwner remains temporary
----------------------------------------------------------------
w1.tooltipUI:setVisible(true)
TooltipManager.clearOwner(page)
check(
    not w1.tooltipUI:getIsVisible(),
    "legacy clearOwner still dismisses"
)
check(
    w1.prerender == hookedPrerender,
    "legacy clearOwner does not unregister"
)

TooltipManager.unregister(w1)
check(
    w1.prerender == originalPrerender,
    "unregister w1 restores original method"
)

----------------------------------------------------------------
-- 7. Nested ownership and permanent unregister
----------------------------------------------------------------
local nestedPage = {}
local nestedPanel = { parent = nestedPage }
local w2 = makeWidget()
local originalW2 = w2.prerender

TooltipManager.attach(
    w2,
    "prerender",
    nestedPanel
)
w2.tooltipUI:setVisible(true)

local removed = TooltipManager.unregisterOwner(nestedPage)
check(
    removed == 1,
    "unregisterOwner includes nested descendants"
)
check(
    w2.prerender == originalW2,
    "unregisterOwner restores native method"
)
check(
    not w2.tooltipUI:getIsVisible(),
    "unregisterOwner dismisses tooltip"
)
check(
    TooltipManager.unregisterOwner(nestedPage) == 0,
    "repeated unregisterOwner is idempotent"
)

----------------------------------------------------------------
-- 8. Owner transfer must detach old owner
----------------------------------------------------------------
local ownerA = {}
local ownerB = {}
local w3 = makeWidget()
local originalW3 = w3.prerender

TooltipManager.attach(w3, "prerender", ownerA)
local w3Hook = w3.prerender

TooltipManager.register(w3, { method = "prerender", owner = ownerB })
check(
    w3.prerender == w3Hook,
    "owner transfer does not duplicate Hook"
)

w3.tooltipUI:setVisible(true)
check(
    TooltipManager.dismissOwner(ownerA) == 0,
    "old owner no longer owns transferred widget"
)
check(
    w3.tooltipUI:getIsVisible(),
    "old owner cannot dismiss transferred widget"
)

TooltipManager.dismissOwner(ownerB)
check(
    not w3.tooltipUI:getIsVisible(),
    "new owner can dismiss transferred widget"
)
check(
    TooltipManager.unregisterOwner(ownerB) == 1,
    "new owner can permanently unregister widget"
)
check(
    w3.prerender == originalW3,
    "owner transfer cleanup restores original method"
)

----------------------------------------------------------------
-- 9. Preserve all native return values, including nil
----------------------------------------------------------------
local w4 = makeWidget()
local nativeCalls = 0
w4.prerender = function(self)
    nativeCalls = nativeCalls + 1
    return nil, 42, nil, "tail"
end

TooltipManager.attach(w4, "prerender", page)
local returnCount = select("#", w4:prerender())
check(
    returnCount == 4,
    "wrapper preserves exact native return count"
)

local a, b, c, d = w4:prerender()
check(
    a == nil and b == 42 and c == nil and d == "tail",
    "wrapper preserves nil and multiple return values"
)
check(
    nativeCalls == 2,
    "native method executes exactly once per call"
)

TooltipManager.unregister(w4)

----------------------------------------------------------------
-- 10. Changing Hook method restores the previous method
----------------------------------------------------------------
local w5 = makeWidget()
local originalPre = w5.prerender
w5.updateTooltip = function(self)
    self.updated = true
    return "updated"
end
local originalUpdate = w5.updateTooltip

TooltipManager.attach(w5, "prerender", page)
TooltipManager.register(w5, { method = "updateTooltip", owner = page })
check(
    w5.prerender == originalPre,
    "changing Hook restores previous native method"
)
check(
    w5.updateTooltip ~= originalUpdate,
    "new Hook method is wrapped"
)

w5:updateTooltip()
check(
    w5.updated,
    "new native method executes"
)

TooltipManager.unregister(w5)
check(
    w5.updateTooltip == originalUpdate,
    "unregister restores replacement method"
)

----------------------------------------------------------------
-- 11. External method replacement must not be overwritten
----------------------------------------------------------------
local w6 = makeWidget()
local externalCalls = 0
TooltipManager.attach(w6, "prerender", page)

local externalMethod = function(self)
    externalCalls = externalCalls + 1
    return "external"
end
w6.prerender = externalMethod

check(
    TooltipManager.unregister(w6),
    "external replacement widget unregisters"
)
check(
    w6.prerender == externalMethod,
    "unregister does not overwrite external method"
)
check(
    w6:prerender() == "external" and externalCalls == 1,
    "external method remains functional"
)

----------------------------------------------------------------
-- 12. Register method before it exists, then install it later
----------------------------------------------------------------
local w7 = { tooltipUI = makeTooltip() }
TooltipManager.register(w7, { method = "prerender", owner = page })

local delayedNative = function(self)
    self.delayedCalled = true
end
w7.prerender = delayedNative

TooltipManager.register(w7, { method = "prerender", owner = page })
check(
    w7.prerender ~= delayedNative,
    "re-registration hooks a method added later"
)

w7:prerender()
check(
    w7.delayedCalled,
    "delayed native method executes"
)

TooltipManager.unregister(w7)
check(
    w7.prerender == delayedNative,
    "delayed method is restored correctly"
)

----------------------------------------------------------------
-- 13. Owner cycles must not cause infinite traversal
----------------------------------------------------------------
local cycleA = {}
local cycleB = {}
cycleA.parent = cycleB
cycleB.owner = cycleA

local w8 = makeWidget()
TooltipManager.attach(w8, "prerender", cycleA)
w8.tooltipUI:setVisible(true)

check(
    TooltipManager.dismissOwner(cycleB) == 1,
    "cyclic owner graph is handled safely"
)
check(
    TooltipManager.unregisterOwner(cycleA) == 1,
    "cyclic owner graph unregisters safely"
)

----------------------------------------------------------------
-- 14. Direct unregister is idempotent
----------------------------------------------------------------
local w9 = makeWidget()
local originalW9 = w9.prerender

TooltipManager.attach(w9, "prerender", page)
check(
    TooltipManager.unregister(w9),
    "first direct unregister succeeds"
)
check(
    not TooltipManager.unregister(w9),
    "second direct unregister is harmless"
)
check(
    w9.prerender == originalW9,
    "direct unregister restores original method"
)

----------------------------------------------------------------
-- 15. Global cleanup restores all remaining Hooks
----------------------------------------------------------------
local w10 = makeWidget()
local originalW10 = w10.prerender

TooltipManager.attach(w10, "prerender", page)
local removedAll = TooltipManager.clearAll()
check(
    removedAll == 1,
    "clearAll unregisters remaining widgets"
)
check(
    w10.prerender == originalW10,
    "clearAll restores native method"
)
check(
    TooltipManager.unregisterOwner(page) == 0,
    "clearAll leaves no owner registration"
)

----------------------------------------------------------------
-- 16. WarehousePage lifecycle simulation: page switching,
--     cart drawer opening/closing/disposing, explicit button
--     tooltips, and unregister
----------------------------------------------------------------
local whPage = { Type = "WarehousePage" }
local zoneBtn = makeWidget()
local helpBtn = makeWidget()
local cartBtn = makeWidget()
local pillBtn = makeWidget()
local origZonePrerender = zoneBtn.prerender
local origCartPrerender = cartBtn.prerender

-- Step A: Attach all 4 native Warehouse buttons
TooltipManager.attach(zoneBtn, "prerender", whPage)
TooltipManager.attach(helpBtn, "prerender", whPage)
TooltipManager.attach(cartBtn, "prerender", whPage)
TooltipManager.attach(pillBtn, "prerender", whPage)

-- Show tooltips
zoneBtn.tooltipUI:setVisible(true)
helpBtn.tooltipUI:setVisible(true)
cartBtn.tooltipUI:setVisible(true)
pillBtn.tooltipUI:setVisible(true)

-- Step B: Open cart drawer (docked child drawer)
local drawerInstance1 = { Type = "DeliveryCartDrawer", owner = whPage }
local drawerBtn1 = makeWidget()
local origDrawerBtn1Prerender = drawerBtn1.prerender
TooltipManager.attach(drawerBtn1, "prerender", drawerInstance1)
drawerBtn1.tooltipUI:setVisible(true)

check(zoneBtn.tooltipUI:getIsVisible() == true, "warehouse button tooltip visible before switch")
check(drawerBtn1.tooltipUI:getIsVisible() == true, "drawer button tooltip visible before switch")

-- Step C: Switch away (WarehousePage:deactivate)
-- 1. Drawer is disposed: calls unregisterOwner(drawerInstance1)
local drawerUnregCount = TooltipManager.unregisterOwner(drawerInstance1)
check(drawerUnregCount == 1, "drawer:dispose unregisters drawer widget")
check(drawerBtn1.prerender == origDrawerBtn1Prerender, "drawer widget native method restored")

-- 2. WarehousePage is dismissed: calls dismissOwner(whPage)
local pageDismissCount = TooltipManager.dismissOwner(whPage)
check(pageDismissCount == 4, "dismissOwner(whPage) hides 4 warehouse button tooltips")
check(zoneBtn.tooltipUI:getIsVisible() == false, "zoneBtn tooltip hidden after page switch")
check(cartBtn.tooltipUI:getIsVisible() == false, "cartBtn tooltip hidden after page switch")
check(zoneBtn.prerender ~= origZonePrerender, "whPage buttons remain wrapped during dismiss")

-- Step D: Switch back (WarehousePage:activate)
-- Buttons are still registered and ready; re-opening drawer creates a new instance
zoneBtn.tooltipUI:setVisible(true)
local drawerInstance2 = { Type = "DeliveryCartDrawer", owner = whPage }
local drawerBtn2 = makeWidget()
local origDrawerBtn2Prerender = drawerBtn2.prerender
TooltipManager.attach(drawerBtn2, "prerender", drawerInstance2)
drawerBtn2.tooltipUI:setVisible(true)

-- Step E: Repeated page switch (deactivate again)
TooltipManager.unregisterOwner(drawerInstance2)
check(drawerBtn2.prerender == origDrawerBtn2Prerender, "second drawer instance cleanly unregistered")
TooltipManager.dismissOwner(whPage)
check(zoneBtn.tooltipUI:getIsVisible() == false, "zoneBtn tooltip hidden on second page dismiss")

-- Step F: WarehousePage:dispose (Dashboard close)
local whPageUnregCount = TooltipManager.unregisterOwner(whPage)
check(whPageUnregCount == 4, "unregisterOwner(whPage) cleanly unregisters all 4 warehouse buttons")
check(zoneBtn.prerender == origZonePrerender, "zoneBtn native method restored on page dispose")
check(cartBtn.prerender == origCartPrerender, "cartBtn native method restored on page dispose")

----------------------------------------------------------------
-- Cleanup shared test globals
----------------------------------------------------------------
TooltipManager.clearAll()
getCore = previousGetCore
getMouseX = previousGetMouseX
getMouseY = previousGetMouseY

print("tooltip-manager: " .. checks .. " PASS")
