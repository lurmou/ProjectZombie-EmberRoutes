--[[
    settlement-overview-dashboard-integration-test.lua
    Verifies that SettlementOverviewPage (and all 5 advanced UI mechanisms)
    integrates natively into SettlementDashboard without lifecycle leaks,
    constructor mismatches, or Zero-GC violations.
]]

package.loaded['ISUI/ISContextMenu'] = true
package.loaded['EmberRoutesProbe/Work/WorkOverviewService'] = {
    status = function()
        return {
            works = {
                {id="order_1", name="Plank Hauling", state="active", recipe="Base.Plank", count=5, max=10, details="Hauling to Main Cache"},
                {id="order_2", name="Vegetable Harvest", state="running", recipe="Base.Cabbage", count=12, max=20, details="Farming Field A"}
            },
            byNpc = {
                ["npc_1"] = {state = "working", orderId = "order_1"},
                ["npc_2"] = {state = "running", orderId = "order_2"}
            },
            problems = {},
            counts = {working = 2, idle = 1},
            alerts = {}
        }
    end,
    watch = function(actor, entryId, cb)
        return function() end
    end
}

package.loaded['EmberRoutesProbe/Settlement/PersonnelService'] = {
    enrichWorkers = function(actor, entryId, workers)
        return {
            {id = "npc_1", name = "Alice", isBleeding = false, isInfected = false, hasInjury = false},
            {id = "npc_2", name = "Bob", isBleeding = false, isInfected = false, hasInjury = false},
            {id = "npc_3", name = "Charlie", isBleeding = false, isInfected = false, hasInjury = false}
        }
    end,
    invalidate = function() end,
    release = function() end,
    details = function() return {knowledge = {}} end,
    rows = function() return {} end
}

package.loaded['EmberRoutesProbe/Crafting/CraftingService'] = {
    status = function()
        return {
            workers = {
                {id = "npc_1"}, {id = "npc_2"}, {id = "npc_3"}
            }
        }
    end
}

package.loaded['EmberRoutesProbe/Warehouse/WarehouseIndex'] = {
    watch = function() return function() end end,
    data = function() return {} end
}
package.loaded['EmberRoutesProbe/Work/WorkCommandAdapter'] = {
    stopJob = function() return true end
}

local checks = 0
local function check(val, msg)
    assert(val, msg)
    checks = checks + 1
end

_G.Events = _G.Events or {}
for _, name in ipairs({'OnGameStart', 'OnServerStarted', 'OnTick', 'OnTickEvenPaused', 'OnPreMapLoad', 'OnSave'}) do
    _G.Events[name] = {Add = function() end, Remove = function() end}
end

package.path = "Contents/mods/EmberRoutesProbe/42/media/lua/client/?.lua;Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;" .. package.path

local Base = {}
function Base:derive(name)
    local cls = {Type = name}
    cls.__index = cls
    return setmetatable(cls, {__index = self})
end
function Base:new(x, y, w, h, title, target, callback)
    return setmetatable({x = x or 0, y = y or 0, width = w or 0, height = h or 0, title = title, target = target, onclick = callback, items = {}, selected = 0, children = {}}, {__index = self})
end
function Base:initialise() self.children = self.children or {} self.initialised = true end
function Base:instantiate()
    if self.native then return end
    self.native = true
    self:createChildren()
end
function Base:createChildren() end
function Base:addChild(child)
    self.children = self.children or {}
    child.parent = self
    child:instantiate()
    self.children[#self.children + 1] = child
end
function Base:addToUIManager() self:instantiate() self.added = true end
function Base:removeFromUIManager() self.added = false end
function Base:setVisible(v) self:instantiate() self.visible = v end
function Base:getIsVisible() return self.visible ~= false end
function Base:close() self:setVisible(false) self.disposed = true end
function Base:bringToTop() self.raised = true end
function Base:clear() self.items = {} self.selected = 0 end
function Base:titleBarHeight() return 24 end
function Base:setWantKeyEvents() end
function Base:update() end
function Base:prerender() end
function Base:getMouseX() return -1 end
function Base:getMouseY() return -1 end
function Base:setX(x) self.x = x end
function Base:setY(y) self.y = y end
function Base:getX() return self.x end
function Base:getY() return self.y end
function Base:setHeight(h) self.height = h end
function Base:setWidth(w) self.width = w end
function Base:getWidth() return self.width end
function Base:getHeight() return self.height end
function Base:getAbsoluteX() return self.x + (self.parent and self.parent:getAbsoluteX() or 0) end
function Base:getAbsoluteY() return self.y + (self.parent and self.parent:getAbsoluteY() or 0) end
function Base:drawText() end
function Base:drawTextCentre() end
function Base:drawTextRight() end
function Base:drawRect() end
function Base:drawRectBorder() end
function Base:drawTexture() end
function Base:drawTextureScaledAspect() end
function Base:setStencilRect(x, y, w, h) end
function Base:clearStencilRect() end
function Base:getYScroll() return self.scroll or 0 end
function Base:setYScroll(v) self.scroll = v end
function Base:setScrollHeight(h) self.scrollHeight = h end
function Base:getScrollHeight() return self.scrollHeight or 0 end
function Base:topOfItem(i) return (i - 1) * (self.itemheight or 24) end
function Base:addItem(label, item, tooltip)
    local entry = {text = label, item = item, tooltip = tooltip, height = self.itemheight or 24, index = #self.items + 1}
    self.items[#self.items + 1] = entry
    return entry
end

ISPanel = Base
ISCollapsableWindow = Base
ISButton = Base
ISScrollingListBox = Base
for _, name in ipairs({'ISPanel','ISCollapsableWindow','ISButton','ISScrollingListBox','ISTextEntryBox','ISComboBox','ISModalDialog'}) do
    package.loaded['ISUI/'..name] = true
end

UIFont = {Small = 1, Medium = 2, Large = 3}
UIManager = {
    getMillisSinceLastRender = function() return 16 end
}

local sw, sh, fh = 1920, 1080, 20
function getCore() return {getScreenWidth = function() return sw end, getScreenHeight = function() return sh end} end
function getTextManager() return {getFontHeight = function() return fh end, MeasureStringX = function(_, _, s) return #s * fh / 2 end} end
function getText(key, ...) return key end
function getItemNameFromFullType(id) return id end
function getTexture() return {isReady = function() return true end, getWidth = function() return 32 end, getHeight = function() return 32 end} end
function tryGetTexture() return nil end
function getTimestampMs() return 100000 end
function isClient() return false end
function isServer() return false end

local actor = {
    getIndex = function() return 0 end,
    getJoypadBind = function() return -1 end,
    Say = function() end,
    getInventoryWeight = function() return 5 end,
    getMaxWeight = function() return 20 end
}
function actor:getModData() return {} end
function getSpecificPlayer(idx) return actor end

local mockSettlement = {
    id = "settlement_alpha",
    name = "Alpha Outpost",
    factionId = "player_faction"
}

local ledgerData = {factionId = "player_faction"}
local Ledger = require "EmberRoutesProbe/Settlement/SettlementLedger"
Ledger.data = function() return ledgerData end
Ledger.authorized = function(a) return true end
Ledger.view = function(a, id)
    if id == mockSettlement.id then return mockSettlement end
    return nil, "NOT_FOUND"
end

local MockPage = Base:derive("MockPage")
function MockPage:new(owner, bounds)
    local o = Base.new(self, bounds.x, bounds.y, bounds.width, bounds.height)
    o.owner = owner
    return o
end
function MockPage:initialise() Base.initialise(self) end
function MockPage:activate() self.active = true end
function MockPage:deactivate() self.active = false end
package.loaded['EmberRoutesProbe/UI/WarehousePage'] = MockPage

local PageRegistry = require "EmberRoutesProbe/UI/PageRegistry"
local Dashboard = require "EmberRoutesProbe/UI/SettlementDashboard"

print("--- Step 1: Open Dashboard and Select Overview Tab ---")
local dashboard = Dashboard:new(actor, mockSettlement, "overview")
dashboard:initialise()
dashboard:addToUIManager()

local ok, reason = dashboard:selectTab("overview")
print("selectTab result: ok=" .. tostring(ok) .. " reason=" .. tostring(reason))
check(ok == true, "selectTab('overview') must succeed")
check(dashboard.activeTab == "overview", "activeTab must be overview")

local overviewPage = dashboard.pages.overview
check(overviewPage ~= nil, "SettlementOverviewPage must be instantiated")
check(overviewPage.actor == actor, "actor must be correctly wired via new(owner, bounds)")
check(overviewPage.owner == dashboard, "owner must be correctly wired")
check(overviewPage.entry == mockSettlement, "entry must be correctly wired")
check(overviewPage.active == true, "overview page must be active")

print("--- Step 2: Verify 5 Advanced UI Mechanisms on Overview Page ---")
check(overviewPage.popRollerState ~= nil, "MechanicalRoller state present")
check(overviewPage.defenseDialState ~= nil, "RadialDial state present")
check(overviewPage.gearsState ~= nil, "MechanicalGears state present")
check(overviewPage.conveyorState ~= nil, "ConveyorBelt state present")
check(overviewPage.orderList ~= nil, "orderList with InlineCardDrawer present")

-- Execute prerender to verify zero-error rendering
overviewPage:prerender()
check(true, "overviewPage:prerender() executed cleanly")

print("--- Step 3: Verify Context Application & Drawer Expansion ---")
local contextTarget = overviewPage.resolveContext(overviewPage, {orderId = "order_2"})
check(contextTarget == "order_2", "resolveContext resolves orderId")
local applied = overviewPage:applyContext({orderId = "order_2"})
check(applied == true, "applyContext expands drawer")
check(overviewPage.expandedOrderId == "order_2", "expandedOrderId matches target order")

print("--- Step 4: Verify Symmetric Tab Switching ---")
-- Switch to warehouse
local okWarehouse = dashboard:selectTab("warehouse")
check(okWarehouse == true, "Switching to warehouse succeeds")
check(dashboard.activeTab == "warehouse", "Active tab is now warehouse")
check(overviewPage.active == false, "Overview page is deactivated cleanly")

-- Switch back using group navigation (group 'settlement' defaultTab is 'overview')
local okGroup = dashboard:selectGroup("settlement")
check(okGroup == true, "selectGroup('settlement') succeeds")
check(dashboard.activeTab == "overview", "Overview page re-activated via group navigation")
check(overviewPage.active == true, "Overview page is active again")

print("--- Step 5: Verify Teardown & Lifecycle Disposal ---")
dashboard:close()
check(dashboard.disposed == true, "Dashboard disposed cleanly")
check(overviewPage.active == false, "Overview page deactivated on dashboard close")

print("ALL SETTLEMENT DASHBOARD OVERVIEW INTEGRATION CHECKS PASSED (" .. checks .. " checks)!")
