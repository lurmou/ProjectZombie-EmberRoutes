-- ==============================================================================
-- EmberRoutes UI Framework - Task 1.6A Production Page Lifecycle Integration Test
--
-- Purpose:
-- Validates REAL production UI page modules (WarehousePage, PersonnelPage,
-- DeliveryCartDrawer, PersonnelDossierDrawer, TooltipManager, PageLifecycle)
-- executing full activate -> deactivate -> reactivate -> dispose lifecycles.
--
-- Minimal Stubs Used (ONLY external PZ engine & background domain services):
-- - ISUI base controls (ISPanel, ISCollapsableWindow, ISButton, etc.)
-- - PZ Engine globals (getTextManager, getCore, Events, ModData, getCell)
-- - Background domain services (WarehouseIndex, SettlementCrafting)
--
-- Unmodified Real Modules Tested:
-- - EmberRoutesProbe/UI/WarehousePage.lua
-- - EmberRoutesProbe/UI/PersonnelPage.lua
-- - EmberRoutesProbe/UI/DeliveryCartDrawer.lua
-- - EmberRoutesProbe/UI/PersonnelDossierDrawer.lua
-- - EmberRoutesProbe/UI/TooltipManager.lua
-- - EmberRoutesProbe/UI/PageLifecycle.lua
-- ==============================================================================

package.path = "Contents/mods/EmberRoutesProbe/42/media/lua/client/?.lua;Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;" .. package.path

local checks = 0
local function check(value, message)
    assert(value, message or "Assertion failed")
    checks = checks + 1
end

-- ------------------------------------------------------------------------------
-- 1. Minimal PZ Engine UI & Runtime Environment Setup (Self-Contained for Kahlua)
-- ------------------------------------------------------------------------------
local Base = {}
function Base:derive(name)
    local cls = setmetatable({ Type = name }, { __index = self })
    cls.__index = cls
    return cls
end
function Base:new(x, y, w, h, title)
    return setmetatable({
        x = x or 0,
        y = y or 0,
        width = w or 0,
        height = h or 0,
        title = title,
        children = {},
        selected = 1,
        items = {},
        visible = true
    }, self)
end
Base.__index = Base
function Base:initialise() self.initialised = true end
function Base:createChildren() self.parentCreated = true end
function Base:addChild(child) self.children[#self.children + 1] = child end
function Base:addToUIManager() self:createChildren(); self.added = true; self.visible = true end
function Base:removeFromUIManager() self.added = false; self.visible = false end
function Base:close() self.closed = true; self.visible = false end
function Base:titleBarHeight() return 24 end
function Base:drawText() end
function Base:drawRect() end
function Base:drawRectBorder() end
function Base:drawTextureScaledAspect() end
function Base:getAbsoluteX() return self.x or 0 end
function Base:getAbsoluteY() return self.y or 0 end
function Base:getYScroll() return self.yScroll or 0 end
function Base:setYScroll(value) self.yScroll = value end
function Base:setScrollHeight(value) self.scrollHeight = value end
function Base:prerender() self.parentRendered = true end
function Base:setWantKeyEvents(value) self.wantsKeys = value end
function Base:setEnable(value) self.enable = value end
function Base:setTitle(value) self.title = value end
function Base:setOnMouseDownFunction(target, fn) self.target, self.onclick = target, fn end
function Base:setOverrideAButtonFunction(target, fn) self.target, self.aButton = target, fn end
function Base:clear() self.items = {}; self.scrollHeight = 0; self.count = 0 end
function Base:addItem(text, item, tooltip)
    self.items[#self.items + 1] = { text = text, item = item, tooltip = tooltip, index = #self.items + 1, height = self.itemheight or 20 }
    self.scrollHeight = (self.scrollHeight or 0) + (self.itemheight or 20)
    self.count = (self.count or 0) + 1
    return self.items[#self.items]
end
function Base:ensureVisible() end
function Base:onJoypadDown() end
function Base:addOption(opt) self.options = self.options or {}; table.insert(self.options, opt) end
function Base:instantiate() self.instantiated = true end
function Base:setPlaceholderText(text) self.placeholderText = text end
function Base:unfocus() self.focused = false end
function Base:isFocused() return self.focused == true end
function Base:getText() return self.value or "" end
function Base:setText(v) self.value = v end
function Base:setToolTipMap(v) self.tooltip = v end
function Base:setWorker(w) self.worker = w end
function Base:setOwner(o) self.owner = o end
function Base:setVisible(v) self.visible = v end
function Base:isVisible() return self.visible ~= false end
function Base:bringToTop() end
function Base:setX(x) self.x = x end
function Base:setY(y) self.y = y end
function Base:setWidth(w) self.width = w end
function Base:setHeight(h) self.height = h end

ISCollapsableWindow = Base:derive("ISCollapsableWindow")
ISScrollingListBox = Base:derive("ISScrollingListBox")
ISPanel = Base:derive("ISPanel")
ISTextEntryBox = Base:derive("ISTextEntryBox")
ISComboBox = Base:derive("ISComboBox")
ISButton = Base:derive("ISButton")
ISModalDialog = Base:derive("ISModalDialog")
ISContextMenu = Base:derive("ISContextMenu")
function ISContextMenu.get() return Base:new(0, 0, 100, 100) end

for _, name in ipairs({ 'ISCollapsableWindow', 'ISScrollingListBox', 'ISPanel', 'ISTextEntryBox', 'ISComboBox', 'ISButton', 'ISModalDialog', 'ISContextMenu' }) do
    package.loaded['ISUI/' .. name] = true
end

for _, name in ipairs({ 'ISInventoryTransferAction', 'ISTimedActionQueue', 'ISBaseTimedAction', 'ISEatFoodAction', 'ISDrinkFluidAction' }) do
    package.loaded['TimedActions/' .. name] = Base:derive(name)
end
package.loaded['Entity/TimedActions/ISHandcraftAction'] = Base:derive('ISHandcraftAction')

Events = setmetatable({}, {
    __index = function(t, k)
        local ev = { Add = function() end, Remove = function() end }
        t[k] = ev
        return ev
    end
})

UIFont = { Small = 1, Medium = 2, Large = 3 }
getTextManager = function()
    return {
        getFontHeight = function(self, font) return 16 end,
        MeasureStringX = function(self, font, s) return #tostring(s) * 8 end
    }
end
getCore = function()
    return {
        getScreenWidth = function() return 1920 end,
        getScreenHeight = function() return 1080 end
    }
end
getText = getText or function(k, ...) return k end
getTextOrNull = getTextOrNull or function(k) return k end
getTexture = getTexture or function(path) return {} end
isMouseButtonDown = isMouseButtonDown or function() return false end
getTimestampMs = getTimestampMs or function() return 1000 end
getCell = getCell or function() return { getGridSquare = function() return nil end } end
getRandomUUID = getRandomUUID or function() return "test-uuid-prod-1" end

ModData = {
    getOrCreate = function(k) return { entries = {} } end,
    get = function(k) return { entries = {} } end
}

local Registry = package.loaded['EmberRoutesProbe/ContainerRegistry']
if not Registry then
    Registry = require 'EmberRoutesProbe/ContainerRegistry'
end
Registry.listeners = Registry.listeners or {}
Registry.inventoryListeners = Registry.inventoryListeners or {}
Registry.id = function() return "test-uuid-prod-1" end
Registry.data = function() return { format = 1, containers = {} } end

local Ledger = require 'EmberRoutesProbe/SettlementLedger'
Ledger.listeners = Ledger.listeners or {}

-- ------------------------------------------------------------------------------
-- 2. External Domain Service Spies
-- ------------------------------------------------------------------------------
local warehouseWatchCalls = 0
local warehouseReleaseCalls = 0
package.loaded['EmberRoutesProbe/WarehouseIndex'] = {
    watch = function(id, cb)
        warehouseWatchCalls = warehouseWatchCalls + 1
        cb({ state = 'READY', rows = {}, counts = { loaded = 0, containers = 0, unloaded = 0, private = 0, missing = 0, limited = 0, items = 0 } })
        return function()
            warehouseReleaseCalls = warehouseReleaseCalls + 1
        end
    end,
    refresh = function() end
}

local Crafting = require 'EmberRoutesProbe/CraftingService'
local craftingWatchCalls = 0
local craftingReleaseCalls = 0
Crafting.watch = function(actor, id, cb)
    craftingWatchCalls = craftingWatchCalls + 1
    cb({ state = 'READY', workers = {} })
    return function()
        craftingReleaseCalls = craftingReleaseCalls + 1
    end
end
Crafting.status = function(actor, id)
    return { workers = {} }
end

-- ------------------------------------------------------------------------------
-- 3. Load Real Production Classes
-- ------------------------------------------------------------------------------
local WarehousePage = require 'EmberRoutesProbe/UI/WarehousePage'
local PersonnelPage = require 'EmberRoutesProbe/UI/PersonnelPage'
local TooltipManager = require 'EmberRoutesProbe/UI/TooltipManager'
local Lifecycle = require 'EmberRoutesProbe/UI/PageLifecycle'

local actor = {
    getIndex = function() return 0 end,
    getPlayerNum = function() return 0 end,
    getMaxWeight = function() return 20 end,
    getInventory = function()
        return {
            getCapacity = function() return 50 end,
            getCapacityWeight = function() return 10 end
        }
    end
}
local entry = { id = "settlement-prod-test", name = "Test Settlement" }
local owner = {
    actor = actor,
    entry = entry,
    width = 1000,
    height = 600,
    fontHeight = 16,
    pad = 10,
    getX = function() return 100 end,
    getY = function() return 100 end,
    valid = function() return true end,
    close = function() end
}
local bounds = { x = 0, y = 0, width = 1000, height = 600 }

-- ==============================================================================
-- Test Suite 1: Real WarehousePage Lifecycle & Transient CartDrawer
-- ==============================================================================
do
    -- Step 1: Real Construction
    local page = WarehousePage:new(owner, bounds)
    check(page ~= nil, "WarehousePage instantiated")
    page:initialise()
    page:createChildren()
    check(page.active == nil or page.active == false, "WarehousePage not active before activate")
    check(page.cartDrawer == nil, "cartDrawer is nil initially")

    -- Step 2: Real Activation
    page:activate()
    check(page.active == true, "WarehousePage marked active on activate()")
    check(page.release ~= nil, "WarehousePage has non-nil page.release")
    check(page.unsubscribe ~= nil, "WarehousePage has non-nil page.unsubscribe")
    check(warehouseWatchCalls == 1, "WarehouseIndex.watch called on activate()")
    check(warehouseReleaseCalls == 0, "No release called during activation")

    -- Step 3: Open CartDrawer (real DeliveryCartDrawer class)
    page:toggleCartDrawer(true)
    check(page.cartDrawer ~= nil, "CartDrawer created via toggleCartDrawer(true)")
    check(page.cartDrawerOpen == true, "cartDrawerOpen set to true")
    check(page.cartDrawer.visible == true, "CartDrawer is visible")
    local cartDrawerInstance = page.cartDrawer

    -- Step 4: Real Deactivation (Transient Drawer Destroyed)
    page:deactivate()
    check(page.active == false, "WarehousePage marked inactive on deactivate()")
    check(page.release == nil, "WarehousePage page.release CLEARED to nil")
    check(page.unsubscribe == nil, "WarehousePage page.unsubscribe CLEARED to nil")
    check(warehouseReleaseCalls == 1, "Warehouse watch release called on deactivate")
    check(page.cartDrawer == nil, "cartDrawer set to nil on deactivate (transient semantics)")
    check(page.cartDrawerOpen == false, "cartDrawerOpen set to false on deactivate")
    check(cartDrawerInstance.visible == false, "cartDrawer hidden")

    -- Step 5: Reactivate (Verify new session & watch)
    page:activate()
    check(page.active == true, "WarehousePage reactivated")
    check(page.release ~= nil, "New page.release assigned")
    check(page.unsubscribe ~= nil, "New page.unsubscribe assigned")
    check(warehouseWatchCalls == 2, "Second watch established on reactivate")
    check(warehouseReleaseCalls == 1, "No premature release")
    check(page.cartDrawer == nil, "cartDrawer still nil until explicitly toggled")

    -- Step 6: Second Deactivation
    page:deactivate()
    check(page.active == false, "WarehousePage deactivated again")
    check(page.release == nil, "page.release cleared again")
    check(page.unsubscribe == nil, "page.unsubscribe cleared again")
    check(warehouseReleaseCalls == 2, "Second watch release executed")

    -- Step 7: Dispose
    page:dispose()
    check(page.disposed == true, "WarehousePage marked disposed")
    check(page.cartDrawer == nil, "cartDrawer remains nil on dispose")
end

-- ==============================================================================
-- Test Suite 2: Real PersonnelPage Lifecycle & Persistent DossierDrawer
-- ==============================================================================
do
    -- Step 1: Real Construction
    local page = PersonnelPage:new(owner, bounds)
    check(page ~= nil, "PersonnelPage instantiated")
    page:initialise()
    page:createChildren()
    check(page.active == nil or page.active == false, "PersonnelPage not active initially")
    check(page.dossierDrawer == nil, "dossierDrawer is nil initially")

    -- Step 2: Real Activation
    page:activate()
    check(page.active == true, "PersonnelPage marked active on activate()")
    check(page.release ~= nil, "PersonnelPage has non-nil page.release")
    check(craftingWatchCalls == 1, "Crafting.watch called on activate()")
    check(craftingReleaseCalls == 0, "No release called during activation")

    -- Step 3: Open DossierDrawer (real PersonnelDossierDrawer class)
    page.store:setState({ selected = { id = "worker-alpha", name = "Alpha Worker" } })
    page:toggleDossierDrawer(true)
    check(page.dossierDrawer ~= nil, "DossierDrawer created via toggleDossierDrawer(true)")
    check(page.dossierDrawerOpen == true, "dossierDrawerOpen set to true")
    check(page.dossierDrawer.visible == true, "DossierDrawer is visible")
    local dossierInstance = page.dossierDrawer

    -- Step 4: Real Deactivation (PERSISTENT Drawer Kept!)
    -- Deactivate != Dispose invariant:
    page:deactivate()
    check(page.active == false, "PersonnelPage marked inactive on deactivate()")
    check(page.release == nil, "PersonnelPage page.release CLEARED to nil")
    check(craftingReleaseCalls == 1, "Crafting watch release called on deactivate")
    check(page.dossierDrawer == dossierInstance, "DossierDrawer instance PRESERVED across deactivate!")
    check(page.dossierDrawerOpen == false, "dossierDrawerOpen set to false")
    check(dossierInstance.visible == false, "DossierDrawer hidden via close()")

    -- Step 5: Reactivate (Reuse existing drawer instance!)
    page:activate()
    check(page.active == true, "PersonnelPage reactivated")
    check(page.release ~= nil, "New page.release assigned")
    check(craftingWatchCalls == 2, "Second watch established on reactivate")
    check(page.dossierDrawer == dossierInstance, "Existing drawer instance retained without recreation")

    -- Step 6: Reopen drawer
    page:toggleDossierDrawer(true)
    check(page.dossierDrawer == dossierInstance, "Same drawer instance reopened, no duplicate instance created")
    check(page.dossierDrawerOpen == true, "drawer reopened successfully")
    check(dossierInstance.visible == true, "drawer visible again")

    -- Step 7: Deactivate again
    page:deactivate()
    check(page.dossierDrawer == dossierInstance, "Drawer instance still retained on second deactivate")
    check(page.dossierDrawerOpen == false, "Drawer closed")
    check(craftingReleaseCalls == 2, "Second watch released")

    -- Step 8: Real Disposal (NOW and ONLY NOW is the drawer disposed!)
    page:dispose()
    check(page.disposed == true, "PersonnelPage marked disposed")
    check(page.dossierDrawer == nil, "PersonnelPage.dossierDrawer nil'd out on page dispose")
end

-- ==============================================================================
-- Test Suite 3: Continuous Inter-Page Tab Switching (10 Cycles)
-- ==============================================================================
do
    local whPage = WarehousePage:new(owner, bounds)
    whPage:initialise()
    whPage:createChildren()

    local persPage = PersonnelPage:new(owner, bounds)
    persPage:initialise()
    persPage:createChildren()
    persPage.store:setState({ selected = { id = "worker-1", name = "Test Worker" } })

    -- Activate persPage first to create dossier drawer
    persPage:activate()
    persPage:toggleDossierDrawer(true)
    local persistentDossier = persPage.dossierDrawer
    check(persistentDossier ~= nil, "Initial persistent dossier created")
    persPage:deactivate()

    local whWatchInitial = warehouseWatchCalls
    local persWatchInitial = craftingWatchCalls

    -- Perform 10 tab switch cycles
    for cycle = 1, 10 do
        -- Switch to WarehousePage
        whPage:activate()
        check(whPage.active == true, "Cycle " .. cycle .. ": Warehouse active")
        check(whPage.release ~= nil, "Cycle " .. cycle .. ": Warehouse release active")
        whPage:toggleCartDrawer(true)
        check(whPage.cartDrawer ~= nil, "Cycle " .. cycle .. ": Cart drawer created")

        whPage:deactivate()
        check(whPage.active == false, "Cycle " .. cycle .. ": Warehouse inactive")
        check(whPage.release == nil, "Cycle " .. cycle .. ": Warehouse release nil")
        check(whPage.cartDrawer == nil, "Cycle " .. cycle .. ": Cart drawer nil (transient)")

        -- Switch to PersonnelPage
        persPage:activate()
        check(persPage.active == true, "Cycle " .. cycle .. ": Personnel active")
        check(persPage.release ~= nil, "Cycle " .. cycle .. ": Personnel release active")
        check(persPage.dossierDrawer == persistentDossier, "Cycle " .. cycle .. ": Dossier instance preserved")

        persPage:toggleDossierDrawer(true)
        check(persPage.dossierDrawer == persistentDossier, "Cycle " .. cycle .. ": Same dossier reopened")

        persPage:deactivate()
        check(persPage.active == false, "Cycle " .. cycle .. ": Personnel inactive")
        check(persPage.release == nil, "Cycle " .. cycle .. ": Personnel release nil")
        check(persPage.dossierDrawer == persistentDossier, "Cycle " .. cycle .. ": Dossier instance still preserved")
    end

    check(warehouseWatchCalls == whWatchInitial + 10, "Warehouse watch called exactly 10 times")
    check(craftingWatchCalls == persWatchInitial + 10, "Personnel watch called exactly 10 times")

    -- Clean disposal of both pages
    whPage:dispose()
    persPage:dispose()
    check(whPage.disposed == true, "whPage disposed cleanly")
    check(persPage.disposed == true, "persPage disposed cleanly")
    check(persPage.dossierDrawer == nil, "persPage dossier cleared on dispose")
end

print("page-lifecycle-integration: " .. checks .. " PASS")
return true
