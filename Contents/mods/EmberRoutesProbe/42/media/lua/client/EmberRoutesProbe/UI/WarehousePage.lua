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
---@field query table
---@field locator table
---@field focusedList EmberRoutesCachedList?
---@field previousButton ISButton
---@field nextButton ISButton
---@field pageWidth number
---@field syncingPage boolean?
---@field notice string
---@field owner EmberRoutesSettlementDashboard
---@field active boolean?
---@field disposed boolean?
---@field resume table?
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
