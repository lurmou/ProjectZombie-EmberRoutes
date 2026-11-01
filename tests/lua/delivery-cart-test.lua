-- tests/lua/delivery-cart-test.lua
-- Unit tests for AE2-style Delivery Cart Drawer & WarehousePage middle-click ordering

package.loaded['ISUI/ISContextMenu'] = true
package.loaded['EmberRoutesProbe/PersonnelService'] = {
    invalidate = function() end, release = function() end,
    details = function() return {knowledge={}} end, rows = function() return {} end
}
package.loaded['EmberRoutesProbe/WarehouseLocator'] = {
    new = function() return {clear = function() end} end
}
package.loaded['EmberRoutesProbe/UI/TooltipAnchor'] = {
    attach = function() end, clear = function() end,
    dismissOwner = function() end, unregisterOwner = function() end,
    clearOwner = function() end, unregister = function() end
}

_G.Events = setmetatable({}, {
    __index = function(t, k)
        t[k] = {Add = function() end, Remove = function() end}
        return t[k]
    end
})

local checks = 0
local function check(value, message)
    assert(value, message or "Assertion failed")
    checks = checks + 1
end

package.path = "Contents/mods/EmberRoutesProbe/42/media/lua/client/?.lua;Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;" .. package.path

local Base = {}
function Base:derive(name)
    local cls = {Type = name}
    cls.__index = cls
    return setmetatable(cls, {__index = self})
end
function Base:new(x, y, w, h, title, target, callback)
    return setmetatable({x=x or 0, y=y or 0, width=w or 100, height=h or 20, title=title, target=target, onclick=callback, items={}, selected=0}, {__index = self})
end
function Base:initialise()
    self.children = {}
    self.initialised = true
end
function Base:instantiate()
    if self.native then return end
    self.native = true
    self:createChildren()
end
function Base:createChildren() end
function Base:update() end
function Base:addChild(child)
    self.children = self.children or {}
    if child.initialise and not child.initialised then child:initialise() end
    child.parent = self
    child:instantiate()
    self.children[#self.children + 1] = child
end
function Base:setVisible(v) self.visible = v end
function Base:isVisible() return self.visible ~= false end
function Base:isMouseOver() return false end
function Base:clear() self.items = {} self.selected = 0 end
function Base:setOnMouseDownFunction(target, fn) self.target = target self.onclick = fn end
function Base:setOverrideAButtonFunction() end
function Base:setYScroll(value) self.scroll = value end
function Base:getYScroll() return self.scroll or 0 end
function Base:setScrollHeight(value) self.scrollHeight = value end
function Base:ensureVisible() end
function Base:setWantKeyEvents() end
function Base:addItem(label, item, tooltip)
    local entry = {text=label, item=item, tooltip=tooltip, height=self.itemheight or 24, index=#self.items+1}
    self.items[#self.items+1] = entry
    return entry
end
function Base:setTitle(t) self.title = t end
function Base:unfocus() self.focus = false end
function Base:setEnable(v) self.enable = v end
function Base:drawText() end
function Base:drawRect() end
function Base:drawRectBorder() end
function Base:drawTextureScaledAspect() end
function Base:titleBarHeight() return 16 end
function Base:addToUIManager()
    self.inUIManager = true
    if not self.childrenCreated then
        self.childrenCreated = true
        self:createChildren()
    end
end
function Base:removeFromUIManager() self.inUIManager = false end
function Base:bringToTop() end
function Base:close() self.visible = false end
function Base:setResizable() end
function Base:setDrawFrame() end
function Base:getX() return self.x or 0 end
function Base:getY() return self.y or 0 end
function Base:setX(x) self.x = x end
function Base:setY(y) self.y = y end
function Base:setWidth(w) self.width = w end
function Base:setHeight(h) self.height = h end
function Base:getIsVisible() return self:isVisible() end

function getCore()
    return {
        getScreenWidth = function() return 1920 end,
        getScreenHeight = function() return 1080 end
    }
end

ISPanel = Base:derive("ISPanel")
ISCollapsableWindow = Base:derive("ISCollapsableWindow")
ISButton = Base:derive("ISButton")
ISScrollingListBox = Base:derive("ISScrollingListBox")
ISTextEntryBox = Base:derive("ISTextEntryBox")
function ISTextEntryBox:new(v, x, y, w, h) local o = Base.new(self, x, y, w, h) o.value = v return o end
function ISTextEntryBox:setPlaceholderText() end
function ISTextEntryBox:setText(v) self.value = v end
function ISTextEntryBox:getText() return self.value or "" end
ISComboBox = Base:derive("ISComboBox")
function ISComboBox:new(...) local o = Base.new(self, ...) o.options = {} o.selected = 1 return o end
function ISComboBox:addOption(v) self.options[#self.options+1] = v end
function ISComboBox:setToolTipMap() end

ISModalDialog = Base:derive("ISModalDialog")
function ISModalDialog:new(x, y, w, h, message, yesno, target, callback)
    local o = Base.new(self, x, y, w, h)
    o.text = message
    o.target = target
    o.onclick = callback
    return o
end

for _, name in ipairs({'ISPanel', 'ISCollapsableWindow', 'ISButton', 'ISScrollingListBox', 'ISTextEntryBox', 'ISComboBox', 'ISModalDialog'}) do
    package.loaded['ISUI/' .. name] = true
end

UIFont = {Small = 1}
function getTextManager()
    return {
        getFontHeight = function() return 18 end,
        MeasureStringX = function(_, _, s) return #(s or "") * 9 end
    }
end
function getTextOrNull(key)
    return key
end
function getText(key, ...)
    return key
end

local mockItems = {
    ["Base.Log"] = {weight = 9.0},
    ["Base.NailsBox"] = {weight = 0.5},
    ["Base.Nails"] = {weight = 0.01}
}

function getScriptManager()
    local lookup = function(_, fullType)
        local itm = mockItems[fullType]
        if itm then
            return {
                getActualWeight = function() return itm.weight end,
                getNormalTexture = function() return {} end,
                getIconsForTexture = function() return { isEmpty = function() return true end } end
            }
        end
        return nil
    end
    return {
        getItem = lookup,
        FindItem = lookup
    }
end

local publicDeliveryCalls = {}
local requestSerial=0
function getRandomUUID() requestSerial=requestSerial+1 return 'delivery-request-'..requestSerial end
package.loaded['EmberRoutesProbe/PublicWork'] = {
    createDeliveryOrder = function(actor, settlementId, items, requestId)
        publicDeliveryCalls[#publicDeliveryCalls + 1] = {
            actor = actor,
            settlementId = settlementId,
            items = items, requestId=requestId
        }
        return "ORDER_CREATED"
    end
}

local WarehousePage = require "EmberRoutesProbe/UI/WarehousePage"
local CartDrawer = require "EmberRoutesProbe/UI/DeliveryCartDrawer"

-- Mock Actor with Inventory
local mockActor = {
    getIndex = function() return 0 end,
    getJoypadBind = function() return -1 end,
    Say = function() end,
    getMaxWeight = function() return 15.0 end,
    getInventory = function()
        return {
            getCapacityWeight = function() return 5.0 end -- 10kg free capacity
        }
    end,
    getEmitter = function()
        return {
            playSound = function() end
        }
    end
}

local mockOwner = {
    actor = mockActor,
    valid = function() return true end,
    entry = {id = "settlement_alpha", name = "Test Settlement"},
    width = 800,
    height = 600,
    getX = function() return 100 end,
    getY = function() return 100 end,
    close = function() end
}

local page = WarehousePage:new(mockOwner, {x = 0, y = 0, width = 800, height = 600})
page:createChildren()

-- Test 1: Delivery Cart Initialization State
check(page.deliveryCartCount == 0, "Cart initial count is 0")
check(page.deliveryCartWeight == 0, "Cart initial weight is 0")
check(page.cartButton ~= nil, "Cart button instantiated")

-- Test 2: Add Heavy Item (Step = 1)
local logRow = {fullType = "Base.Log", label = "Log", count = 10}
page:onMiddleClickItem(logRow, false) -- +1 Log
check(page.deliveryCartCount == 1, "Cart has 1 item type")
check(page.deliveryCart["Base.Log"].count == 1, "Log count is 1")
check(page.deliveryCartWeight == 9.0, "Cart weight is 9.0kg")

-- Test 3: Add Light Item (Step = 1 default for precision)
local nailsRow = {fullType = "Base.Nails", label = "Nails", count = 100}
page:onMiddleClickItem(nailsRow, false) -- +1 Nails (0.01 * 1 = 0.01kg)
check(page.deliveryCartCount == 2, "Cart has 2 item types")
check(page.deliveryCart["Base.Nails"].count == 1, "Nails count is 1")
check(page.deliveryCartTotalUnits == 2, "Total units is 2 (1 log + 1 nail)")
local expectedWeight = 9.0 + (1 * 0.01)
check(math.abs(page.deliveryCartWeight - expectedWeight) < 0.001, "Cart weight accurate")

-- Test 4: Shift-decrement
page:onMiddleClickItem(nailsRow, true) -- -1 Nails -> 0 Nails -> removed
check(page.deliveryCartCount == 1, "Nails removed after reaching 0")
check(page.deliveryCart["Base.Nails"] == nil, "Base.Nails key cleared")
check(page.deliveryCartWeight == 9.0, "Weight reverted to 9.0kg")

-- Test 5: Overweight Detection
-- Free capacity is 15 - 5 = 10.0kg. Adding another log (9.0kg) makes it 18.0kg > 10.0kg.
page:onMiddleClickItem(logRow, false)
check(page.deliveryCart["Base.Log"].count == 2, "Log count is 2")
check(page.deliveryCartWeight == 18.0, "Total weight is 18.0kg")

-- Open Cart Drawer and verify refresh
page:toggleCartDrawer(true)
check(page.cartDrawer ~= nil, "Cart drawer instantiated on open")
check(page.cartDrawer:isVisible() == true, "Drawer is now open")
check(page.cartDrawer.overCapacity, 'capacity shortfall has explicit warning')
check(page.cartDrawer.x == mockOwner:getX() + mockOwner.width + 8, 'cart is floating window docked to right of dashboard')
check(page.sourceList:isVisible() and page.itemGrid:isVisible(), 'cart does not hide sources or stock grid')

-- Test 6: Dispatch Order
page:dispatchDeliveryCart()
check(#publicDeliveryCalls == 1, "PublicWork.createDeliveryOrder was called")
local order = publicDeliveryCalls[1]
check(order.settlementId == "settlement_alpha", "Order target settlement matches")
check(#order.items == 1, "Order has 1 item type")
check(order.items[1].fullType == "Base.Log", "Ordered item is Base.Log")
check(order.items[1].quantity == 2, "Ordered item quantity is 2")

-- Test 7: Post-dispatch cleanup
check(page.deliveryCartCount == 0, "Cart cleared after dispatch")
check(page.deliveryCartWeight == 0, "Cart weight cleared after dispatch")
check(page.cartDrawer:isVisible() == false, "Drawer automatically closed after dispatch")

-- Test 8: Button table callback simulation (PZ onMouseUp passing button table as arg2)
check(type(page.cartDrawer.visible) == "boolean", "Drawer visibility is strictly boolean")
page:toggleCartDrawer(page.cartButton) -- Passes ISButton table, NOT a boolean
check(type(page.cartDrawer.visible) == "boolean", "Drawer visibility remains boolean after button click")
check(page.cartDrawer:isVisible() == true, "Drawer opened by button click")
page:toggleCartDrawer(page.cartButton) -- Toggle again
check(type(page.cartDrawer.visible) == "boolean", "Drawer visibility remains boolean after second click")
check(page.cartDrawer:isVisible() == false, "Drawer closed by second button click")

page:onMiddleClickItem(logRow,false) -- Seed the detail button; native input is checked below.

-- Test 10: Details panel cartButton synchronization
check(page.details.cartButton ~= nil, "Details panel cartButton exists")
page.details:setItem(logRow)
check(page.details.cartButton.title == "IGUI_EmberRoutesProbe_Warehouse_removeShort", "Details button shows remove label when item in cart")
-- Click details button to toggle out of cart
page.details.cartButton.onclick(page.details.cartButton.target)
check(page.deliveryCart["Base.Log"] == nil, "Item removed from cart via details panel button")
check(page.details.cartButton.title == "IGUI_EmberRoutesProbe_Warehouse_addShort", "Details button label updated to add label")

-- Test 11: Add item with specific source warehouse
local testSource = {id = "cont_101", kind = "Crate", x = 10, y = 20, z = 0, count = 5}
page.details.selectedSource = testSource
page:onMiddleClickSource(testSource, false)
local cartKey = "Base.Log:cont_101"
check(page.deliveryCart[cartKey] ~= nil, "Item added with source container key")
check(page.deliveryCart[cartKey].count == 1, "Source item count is 1")
check(page.deliveryCart[cartKey].source.id == "cont_101", "Source container ID preserved")
page:clearDeliveryCart()

-- A rejected submission keeps both cart and request identity; an edit starts a new request.
page:onMiddleClickItem(logRow,false)
local captured={}
package.loaded['EmberRoutesProbe/PublicWork'].createDeliveryOrder=function(_,_,_,requestId)
    captured[#captured+1]=requestId return 'ORDER_LIMIT'
end
page:dispatchDeliveryCart() page:dispatchDeliveryCart()
check(page.deliveryCartCount==1 and captured[1]==captured[2],'rejected delivery retains cart and idempotency identity')
check(page.deliveryFeedbackError and page.cartDrawer.messageColor==require('EmberRoutesProbe/UI/Theme').status.ERROR,'submission rejection stays visible even when cart exceeds current capacity')
page:onMiddleClickItem(logRow,false) page:dispatchDeliveryCart()
check(captured[3]~=captured[2],'editing rejected cart creates a new request identity')
-- Actual page update observes a middle-button edge, not a direct add call.
page:clearDeliveryCart() page.active=true page.helpModal=nil
local down,shift,over=false,false,true
function isMouseButtonDown(button) check(button==2,'only observe middle button') return down end
function isShiftKeyDown() return shift end
page.itemGrid:setRows({logRow,nailsRow},false)
local cell=page.itemGrid.cells[1]
function page.itemGrid:isMouseOver() return over end
function page.itemGrid:getMouseX() return cell.x+1 end
function page.itemGrid:getMouseY() return cell.y+1 end
page:update() down=true page:update() page:update()
check(page.deliveryCart['Base.Log'].count==1 and page.cartDrawer:isVisible(),'single middle press adds once and reveals review pane')
down=false page:update() shift=true down=true page:update()
check(not page.deliveryCart['Base.Log'],'shift middle subtracts through same native-input edge')
shift=false down=false page:update() over=false down=true page:update() over=true page:update()
check(not page.deliveryCart['Base.Log'],'press outside then drag inside does not add')
down=false page:update() page.helpModal={} down=true page:update() page.helpModal=nil
check(not page.deliveryCart['Base.Log'],'covering help dialog prevents middle delivery')
down=false page:update()
local cell2=page.itemGrid.cells[2]
function page.itemGrid:getMouseX() return cell2.x+1 end
function page.itemGrid:getMouseY() return cell2.y+1 end
down=true page:update()
check(page.deliveryCart['Base.Nails'].count==1,'middle click on second cell adds the hovered stock row')
down=false page:update()
function page.itemGrid:isMouseOverScrollBar() return true end
down=true page:update()
check(page.deliveryCart['Base.Nails'].count==1,'middle click on native scrollbar does not add the row underneath')
function page.itemGrid:isMouseOverScrollBar() return false end

-- Shared row geometry: a vertical miss must not hit the drawn plus button.
local list=page.cartDrawer.list local row=list.items[1].item local layout=row.layout
function list:rowAt() return 1 end
local before=page.deliveryCart['Base.Nails'].count
list:onMouseDown(layout.plus.x+1,layout.name.y+1)
check(page.deliveryCart['Base.Nails'].count==before,'click above stepper does not trigger its action')
list:onMouseDown(layout.plus.x+1,layout.plus.y+1)
check(page.deliveryCart['Base.Nails'].count==before+1,'drawn plus rectangle steps by 1')
for _,h in ipairs({14,18,28}) do
    local r=CartDrawer.rowLayout(h*16,h,math.ceil(h*.6),9999)
    check(r.minus.x+r.minus.width<r.value.x and r.value.x+r.value.width<r.plus.x and r.plus.x+r.plus.width<h*16,
        'row quantity controls stay separate and within width at multiple fonts')
end
page:toggleCartDrawer(false)
check(page.sourceList:isVisible() and not page.cartDrawer:isVisible(),'close hides drawer without losing draft')

-- Test 12: WarehousePage deactivate and dispose lifecycle
page:toggleCartDrawer(true)
check(page.cartDrawer ~= nil and page.cartDrawer:isVisible() == true, "cartDrawer instantiated and visible before deactivate")
local drawerDisposeCalled = false
local originalDrawerDispose = page.cartDrawer.dispose
page.cartDrawer.dispose = function(self)
    drawerDisposeCalled = true
    if originalDrawerDispose then originalDrawerDispose(self) else self:close() end
end
page:deactivate()
check(drawerDisposeCalled == true, "page:deactivate() invokes cartDrawer:dispose() instead of close()")
check(page.cartDrawer == nil, "page.cartDrawer reference cleared after deactivate")
check(page.cartDrawerOpen == false, "cartDrawerOpen reset to false after deactivate")

-- Re-open drawer after reactivation
page.active = true
page:toggleCartDrawer(true)
check(page.cartDrawer ~= nil and page.cartDrawer:isVisible() == true, "cartDrawer re-instantiated on subsequent toggle")
page:dispose()
check(page.cartDrawer == nil, "page:dispose() cleanly clears cartDrawer")

print(string.format("PASS: %d delivery cart checks passed cleanly!", checks))
