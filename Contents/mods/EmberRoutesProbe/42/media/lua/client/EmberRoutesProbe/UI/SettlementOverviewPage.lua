--[[
    SettlementOverviewPage.lua - EmberRoutes UI
    Settlement Strategic Command Center & Overview Dashboard.

    Architectural Compliance:
      - Left Pane: Content-sized Settler Vitals & True Stockpile Reserves (CardPanel + StatMeter),
          a readiness / alert card with the radial dial, population odometer and docked actions.
      - Right Pane (Top): Production Drive Monitor (MechanicalGears).
      - All four kinetic mechanisms are both advanced and drawn; no update-only state.
      - Right Pane (Bottom): ProjectRemnants Seamless Inline Expanding Drawer Work Orders (CachedList):
          * 2px Seam Erasure (Welded physics drawer)
          * Safe Field Work & Farming Plot Target Formatter (Zero-crash coordinate unpacking)
          * Cumulative Row Height Hit-testing (Zero rowAt mutation discrepancy)
          * In-place Height Mutation (Zero clear() list flicker)
          * Virtual Childless Buttons (Dossier inspect & Stop-body preemption)
      - PageLifecycle Integration: Symmetric mount/unmount and scoped token guards.
      - Zero-GC Rendering: Pre-projected scalar bounds, zero table allocations in render/prerender.
      - I18N Parity: 100% matched CN/EN keys from IG_UI.json.
    Split (P1-9): the page is now assembled from focused modules in this
    directory -- SettlementOverviewConstants (shared constants/helpers),
    SettlementOverviewLayout, SettlementOverviewLifecycle,
    SettlementOverviewRefresh, SettlementOverviewPresentation,
    SettlementOverviewOrders, SettlementOverviewOrderRow and
    SettlementOverviewRender (each attaches its methods to this class).
    This file keeps only the class, construction, small lifecycle hooks
    and the assembly. Behaviour and displayed content are unchanged.
]]

require 'ISUI/ISPanel'
local State = require 'EmberRoutesProbe/UI/State'
local SupplyEstimate = require 'EmberRoutesProbe/Warehouse/SupplyEstimate'
local MechanicalRoller = require 'EmberRoutesProbe/UI/MechanicalRoller'
local RadialDial = require 'EmberRoutesProbe/UI/RadialDial'
local MechanicalGears = require 'EmberRoutesProbe/UI/MechanicalGears'
local ItemPresentation = require 'EmberRoutesProbe/UI/ItemPresentation'

---@class EmberRoutesSettlementOverviewPage:ISPanel
---@field owner EmberRoutesSettlementDashboard
---@field actor IsoPlayer
---@field entry table
---@field fontHeight number
---@field pad number
---@field active boolean?
---@field disposed boolean?
---@field orderList EmberRoutesCachedList
---@field editAreaButton ISButton
---@field autoZoneButton ISButton
local EmberRoutesSettlementOverviewPage = ISPanel:derive('EmberRoutesSettlementOverviewPage')

---@param arg1 any Owner dashboard or x position
---@param arg2 any Bounds table or y position
---@param width number?
---@param height number?
---@param actor IsoPlayer?
---@param owner EmberRoutesSettlementDashboard?
---@param entry table?
function EmberRoutesSettlementOverviewPage:new(arg1, arg2, width, height, actor, owner, entry)
    local x, y, w, h
    local act, own, ent
    if type(arg2) == "table" and arg2.x ~= nil and arg2.width ~= nil then
        own = arg1
        local b = arg2
        x, y, w, h = b.x, b.y, b.width, b.height
        act = own and own.actor
        ent = own and own.entry
    else
        x = arg1 or 0
        y = arg2 or 0
        w = width or 800
        h = height or 600
        act = actor
        own = owner
        ent = entry
    end

    local o = ISPanel.new(self, x, y, w, h)
    o.actor = act
    o.owner = own
    o.entry = ent
    o.pad = 8
    local tm = getTextManager()
    o.fontHeight = tm and tm:getFontHeight(UIFont.Small) or 14

    o.background = false
    o.activeFilter = 'all'
    o.expandedOrderId = nil
    o.expandedKey = nil
    o.itemIcons = ItemPresentation.new()

    -- Left Pane Pre-allocated Cache (100% matched to user's screenshot)
    o.cachedVitalsHeader = nil
    o.cachedHealthMeter  = nil
    o.cachedLoadMeter    = nil
    o.cachedStockpileLines = {}
    o.cachedStockpileFooter = nil
    o.cachedInjuredJump  = nil
    o.cachedAlerts = nil
    o.cachedPopRoller = nil
    o.cachedEndRule = nil

    -- Order list height follows its rows; these are recomputed on every
    -- refresh and reused by rebuildLayout on resize.
    o.listContentH = nil
    o.listMaxHeight = nil

    -- Dynamic Mechanisms Pre-allocated Containers (Zero GC): every state below
    -- is both advanced in prerender and drawn in the same frame.
    o.popRollerState = MechanicalRoller.createState(3, 8.0)
    o.defenseDialState = RadialDial.createState(7.0)
    o.gearsState = MechanicalGears.createState(7, 5)

    -- Right Pane Kinetic Indicators Cache
    o.cachedData = {
        popCount = 0,
        workingCount = 0,
        idleCount = 0,
        injuredCount = 0,
        defenseRatio = 1.0,
        isHauling = false,
        isCrafting = false
    }

    o.store = State.new({
        works = {},
        vitals = {population = 0, working = 0, idle = 0, injured = 0, infected = 0, firstInjuredId = nil},
        stockpile = SupplyEstimate.calculate({}, 0),
        counts = {all = 0, working = 0, waiting = 0, blocked = 0},
        revision = 0
    })

    return o
end

function EmberRoutesSettlementOverviewPage:initialise()
    ISPanel.initialise(self)
    self:rebuildLayout()
end

function EmberRoutesSettlementOverviewPage:createChildren()
    ISPanel.createChildren(self)
    self:rebuildLayout()
end

function EmberRoutesSettlementOverviewPage:onResize()
    if ISPanel.onResize then ISPanel.onResize(self) end
    self:rebuildLayout()
end

function EmberRoutesSettlementOverviewPage:syncLayoutAliases()
    if self.orderList and self.listBounds then
        self.orderList:setX(self.listBounds.x)
        self.orderList:setY(self.listBounds.y)
        self.orderList:setWidth(self.listBounds.width)
        self.orderList:setHeight(self.listBounds.height)
        if self.orderList.vscroll then
            self.orderList.vscroll:setX(self.listBounds.width - 6)
            self.orderList.vscroll:setWidth(6)
            self.orderList.vscroll:setHeight(self.listBounds.height)
        end
        self.listMaxHeight = self.listBounds.height
        self.rightBottomBounds = self.listBounds
    end
end

-- Attach the split-out behaviours. Each module returns attach(Page) and
-- only defines methods on the class; there is no circular require.
require 'EmberRoutesProbe/UI/SettlementOverviewLayout'(EmberRoutesSettlementOverviewPage)
require 'EmberRoutesProbe/UI/SettlementOverviewLifecycle'(EmberRoutesSettlementOverviewPage)
require 'EmberRoutesProbe/UI/SettlementOverviewRefresh'(EmberRoutesSettlementOverviewPage)
require 'EmberRoutesProbe/UI/SettlementOverviewPresentation'(EmberRoutesSettlementOverviewPage)
require 'EmberRoutesProbe/UI/SettlementOverviewOrders'(EmberRoutesSettlementOverviewPage)
require 'EmberRoutesProbe/UI/SettlementOverviewOrderRow'(EmberRoutesSettlementOverviewPage)
require 'EmberRoutesProbe/UI/SettlementOverviewRender'(EmberRoutesSettlementOverviewPage)

return EmberRoutesSettlementOverviewPage
