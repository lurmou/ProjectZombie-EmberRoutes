-- WarehousePage.lua - EmberRoutes UI
-- Warehouse browser page: stockpile summary, search/filter grid, source
-- details, delivery cart and container inspector.
--
-- Split (p1-split-warehousepage): the page is now assembled from focused
-- modules in this directory -- WarehousePageLayout, WarehousePageLifecycle,
-- WarehousePageRefresh, WarehousePageInteraction, WarehousePageCart and
-- WarehousePageRender (each attaches its methods to this class).
-- This file keeps only the class, construction and the assembly.
-- Behaviour and displayed content are unchanged.

require "ISUI/ISPanel"
require "ISUI/ISTextEntryBox"
local Ledger=require "EmberRoutesProbe/Settlement/SettlementLedger"
local Query=require "EmberRoutesProbe/Warehouse/WarehouseQuery"
local Locator=require "EmberRoutesProbe/Warehouse/WarehouseLocator"
local Selector=require "EmberRoutesProbe/UI/SettlementSelector"
local Theme=require "EmberRoutesProbe/UI/Theme"
local Presentation=require "EmberRoutesProbe/UI/ItemPresentation"
local State=require "EmberRoutesProbe/UI/State"

---@class EmberRoutesWarehousePage:ISPanel
---@field actor IsoPlayer
---@field entry EmberRoutesSettlement
---@field fontHeight number
---@field pad number
---@field store EmberRoutesUIStore
---@field summary table
---@field presentation table
---@field details table
---@field hintLines string[]
---@field itemNames table<string,string>
---@field itemGrid table
---@field sourceList EmberRoutesCachedList
---@field search ISTextEntryBox
---@field categories EmberRoutesDropdown
---@field actualPage integer
---@field pages integer
---@field pageCaption string
---@field pageX number
---@field pageY number
---@field hintY number
---@field listTitles table[]
---@field unsubscribe function?
---@field release function?
---@field controls table
---@field controlsHost EmberRoutesLayoutHost
---@field query table
---@field locator table
---@field focusedList EmberRoutesCachedList?
---@field previousButton ISButton
---@field nextButton ISButton
---@field pageWidth number
---@field syncingPage boolean?
---@field notice string
---@field pinnedItems table<string,boolean>
---@field deliveryCart table
---@field deliveryCartCount integer
---@field deliveryCartTotalUnits number
---@field deliveryCartWeight number
---@field cartDrawerOpen boolean
---@field owner EmberRoutesSettlementDashboard
---@field active boolean?
---@field disposed boolean?
---@field resume table?
--- -- Attached by WarehousePageLayout:
---@field createChildren fun(self: EmberRoutesWarehousePage)
--- -- Attached by WarehousePageLifecycle:
---@field activate fun(self: EmberRoutesWarehousePage)
---@field deactivate fun(self: EmberRoutesWarehousePage)
---@field dispose fun(self: EmberRoutesWarehousePage)
---@field close fun(self: EmberRoutesWarehousePage)
--- -- Attached by WarehousePageRefresh:
---@field receive fun(self: EmberRoutesWarehousePage, snapshot: table)
---@field project fun(self: EmberRoutesWarehousePage, snapshot?: table, changed?: table)
---@field queryChanged fun(self: EmberRoutesWarehousePage)
---@field clearSearch fun(self: EmberRoutesWarehousePage)
--- -- Attached by WarehousePageInteraction:
---@field togglePin fun(self: EmberRoutesWarehousePage, row: table)
---@field focusContent fun(self: EmberRoutesWarehousePage): boolean
---@field focusList fun(self: EmberRoutesWarehousePage, list: any)
---@field isListFocused fun(self: EmberRoutesWarehousePage, list: any): boolean
---@field onListActivate fun(self: EmberRoutesWarehousePage, list: any)
---@field onListFocus fun(self: EmberRoutesWarehousePage, list: any, direction: integer)
---@field selectSource fun(self: EmberRoutesWarehousePage, source: table)
---@field locateSource fun(self: EmberRoutesWarehousePage)
---@field selectItem fun(self: EmberRoutesWarehousePage, row: table)
---@field previous fun(self: EmberRoutesWarehousePage)
---@field nextPage fun(self: EmberRoutesWarehousePage)
---@field onListKey fun(self: EmberRoutesWarehousePage, key: integer, list: any): boolean
---@field isItemCraftable fun(self: EmberRoutesWarehousePage, fullType: string): boolean
---@field onMiddleClickItem fun(self: EmberRoutesWarehousePage, row: table, shiftDown?: boolean)
---@field onMiddleClickSource fun(self: EmberRoutesWarehousePage, source: table, shiftDown?: boolean)
---@field openItemContextMenu fun(self: EmberRoutesWarehousePage, row: table, screenX: number, screenY: number)
---@field onListJoypad fun(self: EmberRoutesWarehousePage, button: integer)
---@field help fun(self: EmberRoutesWarehousePage)
--- -- Attached by WarehousePageCart:
---@field addToDeliveryCart fun(self: EmberRoutesWarehousePage, row: table, delta: number, preferredSource?: table)
---@field removeFromDeliveryCart fun(self: EmberRoutesWarehousePage, cartKey: string)
---@field clearDeliveryCart fun(self: EmberRoutesWarehousePage)
---@field updateDeliveryCartTotals fun(self: EmberRoutesWarehousePage)
---@field updateCartButtonVisual fun(self: EmberRoutesWarehousePage)
---@field toggleCartDrawer fun(self: EmberRoutesWarehousePage, forceState?: boolean)
---@field openContainerInspector fun(self: EmberRoutesWarehousePage)
---@field dispatchDeliveryCart fun(self: EmberRoutesWarehousePage)
--- -- Attached by WarehousePageRender:
---@field update fun(self: EmberRoutesWarehousePage)
---@field prerender fun(self: EmberRoutesWarehousePage)
EmberRoutesWarehousePage=ISPanel:derive("EmberRoutesWarehousePage")

---@param owner EmberRoutesSettlementDashboard
---@param bounds table
---@return EmberRoutesWarehousePage
function EmberRoutesWarehousePage:new(owner,bounds)
    local actor,entry=owner.actor,owner.entry
    local h=getTextManager():getFontHeight(UIFont.Small)
    ---@type EmberRoutesWarehousePage
    local o=ISPanel.new(self,bounds.x,bounds.y,bounds.width,bounds.height)
    o.owner=owner o.background=false
    o.actor,o.entry,o.fontHeight,o.pad=actor,entry,h,math.ceil(h*0.6)
    o.backgroundColor=Theme.window
    o.borderColor=Theme.border o.presentation=Presentation.new()
    o.store=State.new({snapshot={state="UPDATING",rows={},counts={}},search="",category=false,page=1,sort="default",selection=false})
    o.itemNames={} o.actualPage=1 o.pages=1 o.pageCaption=""
    o.query=Query.new() o.locator=Locator.new(actor,entry.id) o.notice="" o.pinnedItems={}
    o.deliveryCart={} o.deliveryCartCount=0 o.deliveryCartTotalUnits=0 o.deliveryCartWeight=0 o.cartDrawerOpen=false
    return o
end

function EmberRoutesWarehousePage:initialise() ISPanel.initialise(self) end

-- Attach the split-out behaviours. Each module returns attach(Page) and
-- only defines methods on the class; there is no circular require.
require "EmberRoutesProbe/UI/WarehousePageLayout"(EmberRoutesWarehousePage)
require "EmberRoutesProbe/UI/WarehousePageLifecycle"(EmberRoutesWarehousePage)
require "EmberRoutesProbe/UI/WarehousePageRefresh"(EmberRoutesWarehousePage)
require "EmberRoutesProbe/UI/WarehousePageInteraction"(EmberRoutesWarehousePage)
require "EmberRoutesProbe/UI/WarehousePageCart"(EmberRoutesWarehousePage)
require "EmberRoutesProbe/UI/WarehousePageRender"(EmberRoutesWarehousePage)

return EmberRoutesWarehousePage
