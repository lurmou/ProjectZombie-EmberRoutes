-- Automated unit & regression test for rebuilt SettlementOverviewPage & UI Dashboard integration
package.path = "Contents/mods/EmberRoutesProbe/42/media/lua/client/?.lua;Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;" .. package.path

local Base = {}
Base.__index = Base
function Base:derive(name)
    local o = {}
    setmetatable(o, self)
    o.__index = o
    o.__type = name
    return o
end
function Base:new(x, y, w, h)
    local o = {x = x or 0, y = y or 0, width = w or 0, height = h or 0, children = {}, items = {}}
    setmetatable(o, self)
    o.javaObject = { getParent = function() return o.parent and o.parent.javaObject end }
    return o
end
function Base:initialise() end
function Base:instantiate()
    if not self.javaObject then
        self.javaObject = { getParent = function() return self.parent and self.parent.javaObject end }
    end
end
function Base:addChild(c)
    table.insert(self.children, c)
    c.parent = self
    if not c.javaObject then
        c.javaObject = { getParent = function() return self.javaObject end }
    end
end
function Base:removeChild(c) end
function Base:setX(x) self.x = x end
function Base:setY(y) self.y = y end
function Base:setWidth(w) self.width = w end
function Base:setHeight(h) self.height = h end
function Base:setVisible(v) self.visible = v end
function Base:getIsVisible() return self.visible ~= false end
function Base:getParent() return self.parent end
function Base:getWidth() return self.width or 0 end
function Base:getHeight() return self.height or 0 end
function Base:getAbsoluteX() return self.x + (self.parent and self.parent:getAbsoluteX() or 0) end
function Base:getAbsoluteY() return self.y + (self.parent and self.parent:getAbsoluteY() or 0) end
function Base:drawRect(x, y, w, h, a, r, g, b) end
function Base:drawRectBorder(x, y, w, h, a, r, g, b) end
function Base:drawText(str, x, y, r, g, b, a, font) end
function Base:drawTextCentre(str, x, y, r, g, b, a, font) end
function Base:setStencilRect(x, y, w, h) end
function Base:clearStencilRect() end
function Base:onResize() end
function Base:update() end
function Base:prerender() end
function Base:render() end
function Base:rowAt(x, y) return 1 end
function Base:topOfItem(row) return 0 end
function Base:setScrollHeight(h) self.scrollHeight = h end
function Base:getScrollHeight() return self.scrollHeight or 0 end
function Base:getYScroll() return 0 end
function Base:setYScroll(s) end

function Base:setWantKeyEvents(b) end
function Base:ensureVisible(idx) end
function Base:setOnMouseDownFunction(target, fn) self.onMouseDownFn = fn end
function Base:setOverrideAButtonFunction(target, fn) end
function Base:addItem(label, item, tooltip)
    local entry = {text = label, item = item, tooltip = tooltip, height = self.itemheight or 20, index = #self.items + 1}
    table.insert(self.items, entry)
    return entry
end
function Base:clear() self.items = {} end

_G.ISUIElement = Base
_G.ISPanel = Base
_G.ISScrollingListBox = Base:derive('ISScrollingListBox')
_G.ISButton = Base:derive('ISButton')
_G.ISCollapsableWindow = Base:derive('ISCollapsableWindow')

package.loaded['ISUI/ISUIElement'] = true
package.loaded['ISUI/ISPanel'] = true
package.loaded['ISUI/ISScrollingListBox'] = true
package.loaded['ISUI/ISButton'] = true
package.loaded['ISUI/ISCollapsableWindow'] = true
package.loaded['ISUI/ISComboBox'] = true
package.loaded['ISUI/ISTextEntryBox'] = true
package.loaded['ISUI/ISContextMenu'] = true
package.loaded['TimedActions/ISInventoryTransferAction'] = true
package.loaded['TimedActions/ISTimedActionQueue'] = true
package.loaded['Entity/TimedActions/ISHandcraftAction'] = true
_G.ISInventoryTransferAction = Base:derive('ISInventoryTransferAction')
_G.ISHandcraftAction = Base:derive('ISHandcraftAction')

_G.Events = _G.Events or {}
for _, name in ipairs({'OnContainerUpdate','OnTick','OnTickEvenPaused','OnGameStart','OnPreMapLoad','OnSave','OnServerStarted'}) do
    _G.Events[name] = _G.Events[name] or { Add = function() end, Remove = function() end }
end

local function check(cond, msg)
    if not cond then
        error("ASSERTION FAILED: " .. tostring(msg))
    end
end

-- Mock Engine singletons
local currentMillis = 16.6
_G.UIManager = {
    getMillisSinceLastRender = function() return currentMillis end
}

_G.getTextManager = function()
    return {
        getFontHeight = function(self, font) return 14 end,
        MeasureStringX = function(self, font, str) return (#tostring(str or '')) * 8 end
    }
end

_G.UIFont = {
    Small = "Small",
    Medium = "Medium",
    Large = "Large"
}

_G.getText = function(key, a1, a2)
    return key
end
_G.getTextOrNull = function(key)
    return key
end
_G.getItemNameFromFullType = function(ft)
    return ft
end

_G.getTexture = function(path)
    return {
        path = path,
        getWidth = function() return 61 end,
        getHeight = function() return 61 end
    }
end

-- Mock WorkOverviewService
local mockWorks = {
    {
        key = "order_1", id = "order_1", title = "搬运任务", category = "hauling", state = "working", workerName = "Bob", npcId = "npc_1",
        row = {
            kind = "HAUL",
            npcId = "npc_1",
            targetCount = 1,
            deliveredCount = 0,
            source = {x = 10500, y = 9800, z = 0},
            destination = {x = 10510, y = 9805, z = 0},
            assets = {
                {id = "item_1", kind = "cargo", fullType = "Base.Earbuds", custodyState = "CARRIED"}
            },
            stages = {
                {key = "haulRoute", labelKey = "IGUI_EmberRoutesProbe_Monitor_haulRoute", status = "COMPLETED"},
                {key = "haulTake", labelKey = "IGUI_EmberRoutesProbe_Monitor_haulTake", status = "ACTIVE"},
                {key = "haulPut", labelKey = "IGUI_EmberRoutesProbe_Monitor_haulPut", status = "PLANNED"}
            },
            stageIndex = 2
        }
    },
    {key = "order_2", id = "order_2", title = "Crafting Axe", category = "crafting", state = "working", workerName = "Alice", npcId = "npc_2"},
    {key = "order_3", id = "order_3", title = "Farming Plot", category = "farming", state = "waiting", targetLocation = {x = 10520, y = 9840, z = 0}}
}

package.loaded['EmberRoutesProbe/Work/WorkOverviewService'] = {
    status = function(actor, scope)
        return {
            works = mockWorks,
            byNpc = {
                npc_1 = mockWorks[1],
                npc_2 = mockWorks[2]
            }
        }
    end,
    watch = function(actor, scope, callback)
        return function() end -- unwatch stub
    end
}

package.loaded['EmberRoutesProbe/Crafting/CraftingService'] = {
    status = function(actor, scope)
        return {
            workers = {
                {id = "npc_1", name = "Bob", isBleeding = false, hasInjury = false},
                {id = "npc_2", name = "Alice", isBleeding = false, hasInjury = false},
                {id = "npc_3", name = "Charlie", isBleeding = false, hasInjury = true}
            }
        }
    end
}

package.loaded['EmberRoutesProbe/Settlement/PersonnelService'] = {
    enrichWorkers = function(actor, scope, raw)
        return raw or {}
    end
}

function isClient() return false end
function isServer() return false end

package.loaded['EmberRoutesProbe/Warehouse/WarehouseIndex'] = {
    status = function()
        return {
            rows = {
                {fullType = 'Base.PotOfStew', node = 'food.meals', count = 30},
                {fullType = 'Base.WaterBottleFull', node = 'water', count = 40},
                {fullType = 'Base.Bandage', node = 'medical.bandages', count = 8},
                {fullType = 'Base.Log', node = 'materials', count = 25}
            }
        }
    end,
    watch = function(id, callback)
        if callback then
            callback({
                rows = {
                    {fullType = 'Base.PotOfStew', node = 'food.meals', count = 30},
                    {fullType = 'Base.WaterBottleFull', node = 'water', count = 40},
                    {fullType = 'Base.Bandage', node = 'medical.bandages', count = 8},
                    {fullType = 'Base.Log', node = 'materials', count = 25}
                }
            })
        end
        return function() end
    end
}

-- =========================================================================
-- 1. Test PageRegistry Registration
-- =========================================================================
print("Verifying PageRegistry entry for overview...")
local PageRegistry = require 'EmberRoutesProbe/UI/PageRegistry'
local overviewDef = PageRegistry.get('overview')
check(overviewDef ~= nil, "overview page is registered")
check(overviewDef.module == "SettlementOverviewPage", "overview module maps to SettlementOverviewPage")
check(overviewDef.isTab == true, "overview is registered as a tab")
print("PASS: PageRegistry verified")

-- =========================================================================
-- 2. Test SettlementOverviewPage Lifecycle & Layout
-- =========================================================================
print("Testing SettlementOverviewPage lifecycle...")
local SettlementOverviewPage = require 'EmberRoutesProbe/UI/SettlementOverviewPage'
check(SettlementOverviewPage ~= nil, "SettlementOverviewPage loaded")

local mockActor = {}
local mockOwner = {
    close = function() end,
    activateTab = function(self, tab) self.lastTab = tab end
}
local mockEntry = {id = "safehouse_alpha"}

local page = SettlementOverviewPage:new(0, 0, 800, 600, mockActor, mockOwner, mockEntry)
check(page ~= nil, "Page instance created")

-- Initialise
page:initialise()
check(page.orderList ~= nil, "orderList child control created")
check(page.leftVitalsBounds ~= nil, "leftVitalsBounds calculated")
check(page.rightDriveBounds ~= nil, "rightDriveBounds calculated")
check(page.editAreaButton ~= nil, "editAreaButton child control created")
check(page.autoZoneButton ~= nil, "autoZoneButton child control created")
check(page.leftActionBounds ~= nil, "leftActionBounds calculated")

-- Activation & Refresh
page:activate()
check(page.active == true, "Page marked active after mount")
check(page.cachedData.popCount == 3, "popCount matches enriched workers count (3)")
check(page.cachedData.injuredCount == 1, "injuredCount matches (1)")
check(page.cachedData.isHauling == true, "isHauling detected")
check(page.cachedData.isCrafting == true, "isCrafting detected")
check(#page.orderList.items == 3, "CachedList reconciled 3 work orders")
print("PASS: Activation & Data Reconciliation verified")

-- =========================================================================
-- 3. Test Prerender Zero-GC Execution
-- =========================================================================
print("Testing Prerender execution...")
-- Mock draw primitives on page
page.stencilStack = 0
page.setStencilRect = function(self, x, y, w, h)
    self.stencilStack = self.stencilStack + 1
end
page.clearStencilRect = function(self)
    self.stencilStack = self.stencilStack - 1
end
page.drawRect = function(self) end
page.drawRectBorder = function(self) end
page.drawText = function(self) end
page.drawTextCentre = function(self) end
page.DrawTextureAngle = function(self) end
-- page.javaObject kept intact

page:prerender()
check(page.stencilStack == 0, "Prerender maintained 100% symmetric Stencil stack (net 0)")
check(page.cachedWorkBadge ~= nil, "Left Pane: Work indicator SemanticBadge cached")
check(page.cachedLeisureBadge ~= nil, "Left Pane: Leisure indicator SemanticBadge cached")
check(page.cachedWorkforceSplit ~= nil, "Left Pane: Comparative Workforce SplitBar cached")
check(page.cardVitalsOptions.badge ~= nil, "Left Pane: CardPanel header badge cached")
check(page.cachedData.defenseRatio > 0.5, "Settlement health ratio computed correctly")
check(page.cachedPopRoller ~= nil, "Population odometer projected")
check(page.cachedBelt == nil, "Conveyor belt cleanly removed from overview page")
check(page.cachedAlerts ~= nil and page.cachedAlerts.dialRadius >= 36, "Readiness radial dial projected")
print("PASS: Prerender & Left Pane Workforce Split verified")



-- Stockpile & Survival Days Projection Verification
print("Testing Stockpile & Survival Days Projection (Option A)...")
page:refreshStockpile({
    rows = {
        {fullType = "Base.PotOfStew", node = "food.meals", count = 30},
        {fullType = "Base.WaterBottleFull", node = "water", count = 40},
        {fullType = "Base.Bandage", node = "medical.bandages", count = 8},
        {fullType = "Base.Log", node = "materials", count = 25}
    }
})
local st = page.store.value.stockpile
check(st ~= nil, "stockpile state exists")
check(st.foodDays > 0, "foodDays calculated greater than 0")
check(st.waterDays > 0, "waterDays calculated greater than 0")
check(st.mealsCount == 30, "mealsCount is 30")
check(st.waterCount == 40, "waterCount is 40")
check(st.medicalCount == 8, "medicalCount is 8")
check(st.woodCount == 25, "woodCount is 25")
check(#page.cachedStockpileLines == 4, "cachedStockpileLines has 4 gauge rows")
check(page.cachedStockpileFooter ~= nil, "cachedStockpileFooter exists")
check(page.cardStockpileOptions.badge ~= nil, "cardStockpileOptions badge exists")
page:prerender()
print("PASS: Stockpile & Survival Days Projection verified")

-- =========================================================================
-- 4. Test InlineCardDrawer Expansion & Click Hit Test
-- =========================================================================
print("Testing InlineCardDrawer expansion in orderList...")
check(page.expandedOrderId == nil, "Initially no card is expanded")

-- Simulate clicking header of row 1 (height <= 54)
local hit1 = page:onListMouseDown(page.orderList, 50, 20)
check(hit1 == true, "Clicking header toggles card expansion")
check(page.expandedOrderId == "order_1", "order_1 is now expanded")

-- Test BOM Material Item Grouping and Drawer Height
local order1Entry = page.orderList.items[1]
local order1 = order1Entry.item and (order1Entry.item.value or order1Entry.item)
local grouped = page:getGroupedAssets(order1.row)
check(grouped ~= nil and #grouped == 1, "order_1 grouped 1 cargo asset")
check(grouped[1].status == "TRANSIT", "cargo asset status resolved to TRANSIT")
check(grouped[1].count == 1, "cargo asset count is 1")
check(grouped[1].badge ~= nil and grouped[1].badge.id == "TRANSIT", "cargo badge resolved to TRANSIT")

local drawerH1 = page:getDrawerHeight(order1)
check(drawerH1 == 167, "Drawer height for 1 item is 167 (accommodates top, BOM item and bottom action bar)")

-- Simulate rendering row 1 with expanded drawer
local nextY1 = page:drawOrderRow(page.orderList, 0, order1Entry)
check(nextY1 == (54 + drawerH1), "Order 1 drawer rendered with expanded unified height (BASE_CARD_H + drawerH1)")

-- Test Multi-Item Batch Haul Drawer Expansion (>3 items)
local multiOrder = {
    key = "order_multi", id = "order_multi", title = "搬运任务", category = "hauling", state = "working",
    row = {
        kind = "HAUL",
        targetCount = 4,
        assets = {
            {id = "i1", kind = "cargo", fullType = "Base.Earbuds", custodyState = "CARRIED"},
            {id = "i2", kind = "cargo", fullType = "Base.Nails", custodyState = "CARRIED"},
            {id = "i3", kind = "cargo", fullType = "Base.Hammer", custodyState = "STORED"},
            {id = "i4", kind = "cargo", fullType = "Base.TinnedBeans", custodyState = "UNCOLLECTED"}
        }
    }
}
local multiGrouped = page:getGroupedAssets(multiOrder.row)
check(#multiGrouped == 4, "multiOrder grouped 4 distinct assets")
local multiDrawerH = page:getDrawerHeight(multiOrder)
check(multiDrawerH == 196, "multiOrder drawer height dynamically accommodates overflow line (196)")

-- Simulate clicking virtual button inside expanded drawer
local cardW = page.orderList:getWidth()
local btnX = cardW - 60
local btnY = 54 + drawerH1 - 22 - 10 + 5
local hitBtn = page:onListMouseDown(page.orderList, btnX, btnY)
check(hitBtn == true, "Virtual button click intercepted")
check(mockOwner.lastTab == "personnel", "Virtual button successfully commanded tab jump to personnel")

-- Test Farming Plot (Field Work) Expansion & Zero-crash Rendering
print("Testing Farming Plot expansion (zero crash on table location)...")
local hitFarm = page:onListMouseDown(page.orderList, 50, (54 + drawerH1) + 54 + 20)
check(hitFarm == true, "Clicking farming plot header toggles expansion")
check(page.expandedOrderId == "order_3", "order_3 (farming) is now expanded")

local farmEntry = page.orderList.items[3]
local nextY = page:drawOrderRow(page.orderList, 0, farmEntry)
local farmDrawerH = page:getDrawerHeight(farmEntry.item and (farmEntry.item.value or farmEntry.item))
check(nextY == (54 + farmDrawerH), "Farming drawer rendered with expanded unified height (BASE_CARD_H + farmDrawerH)")
print("PASS: Farming Plot Drawer safely rendered without table concat crash")

-- Deactivate & Dispose
page:deactivate()
check(page.expandedOrderId == nil, "Deactivate cleared expanded drawer")
page:dispose()
check(page.disposed == true, "Page marked disposed")
print("PASS: InlineCardDrawer & lifecycle teardown verified")

print("ALL SETTLEMENT OVERVIEW UI TESTS PASSED SUCCESSFULLY!")
