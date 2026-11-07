--[[
    SettlementOverviewPage.lua - EmberRoutes UI
    Settlement Strategic Command Center & Overview Dashboard.

    Architectural Compliance:
      - Left Pane: Content-sized Settler Vitals & True Stockpile Reserves (CardPanel + StatMeter),
          a readiness / alert card with the radial dial, population odometer and docked actions.
      - Right Pane (Top): Logistics & Production Drive Monitor (MechanicalGears + ConveyorBelt).
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
]]

require 'ISUI/ISPanel'
local UI               = require 'EmberRoutesProbe/UI/UI'
local LayoutHost       = require 'EmberRoutesProbe/UI/LayoutHost'
local Layout           = require 'EmberRoutesProbe/UI/Layout'
local State            = require 'EmberRoutesProbe/UI/State'
local Cached           = require 'EmberRoutesProbe/UI/CachedList'
local Theme            = require 'EmberRoutesProbe/UI/Theme'
local Lifecycle        = require 'EmberRoutesProbe/UI/PageLifecycle'
local Tooltip          = require 'EmberRoutesProbe/UI/TooltipManager'
local FilterChips      = require 'EmberRoutesProbe/UI/FilterChips'
local CardPanel        = require 'EmberRoutesProbe/UI/CardPanel'
local StatMeter        = require 'EmberRoutesProbe/UI/StatMeter'
local StatusVisual     = require 'EmberRoutesProbe/UI/StatusVisual'
local SemanticBadge    = require 'EmberRoutesProbe/UI/SemanticBadge'
local MechanicalGears  = require 'EmberRoutesProbe/UI/MechanicalGears'
local ConveyorBelt     = require 'EmberRoutesProbe/UI/ConveyorBelt'
local MechanicalRoller = require 'EmberRoutesProbe/UI/MechanicalRoller'
local RadialDial       = require 'EmberRoutesProbe/UI/RadialDial'
local InlineCardDrawer = require 'EmberRoutesProbe/UI/InlineCardDrawer'
local WorkCommandAdapter = require 'EmberRoutesProbe/Work/WorkCommandAdapter'
local WorkOverviewService = require 'EmberRoutesProbe/Work/WorkOverviewService'
local WarehouseIndex   = require 'EmberRoutesProbe/Warehouse/WarehouseIndex'
local PersonnelService = require 'EmberRoutesProbe/Settlement/PersonnelService'
local CraftingService  = require 'EmberRoutesProbe/Crafting/CraftingService'
local SupplyEstimate   = require 'EmberRoutesProbe/Warehouse/SupplyEstimate'
local Cards            = require 'EmberRoutesProbe/UI/OrderMonitorCards'
local ItemPresentation = require 'EmberRoutesProbe/UI/ItemPresentation'
local Log = require 'EmberRoutesProbe/Kernel/Log'

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

local BASE_CARD_H = 54
local DRAWER_H    = 140

local STAGE_LABELS = {
    getText('IGUI_EmberRoutesProbe_Stage_Prepare'),
    getText('IGUI_EmberRoutesProbe_Stage_Work'),
    getText('IGUI_EmberRoutesProbe_Stage_Collect'),
    getText('IGUI_EmberRoutesProbe_Stage_Deliver')
}
local STAGE_INDEX = {PREPARE = 1, WORK = 2, COLLECT = 3, DELIVER = 4}
-- Shape encodes the stage meaning, colour encodes the state. The glyph names
-- are consumed by StatusVisual.glyph; unknown label keys degrade to state marks.
local DEFAULT_STAGE_GLYPHS = {"box", "hammer", "arrowDown", "arrowRight"}
local CUSTOM_STAGE_GLYPHS = {
    IGUI_EmberRoutesProbe_Order_stage_source = "box",
    IGUI_EmberRoutesProbe_Order_stage_staging = "arrowDown",
    IGUI_EmberRoutesProbe_Order_stage_craft = "hammer",
    IGUI_EmberRoutesProbe_Order_stage_store = "box",
}

local STOCK_COLORS = {
    water   = {r = 0.25, g = 0.70, b = 0.95, a = 0.90},
    meals   = {r = 0.95, g = 0.75, b = 0.30, a = 0.90},
    crops   = {r = 0.45, g = 0.85, b = 0.45, a = 0.90},
    medical = {r = 0.95, g = 0.45, b = 0.55, a = 0.90},
    wood    = {r = 0.80, g = 0.65, b = 0.45, a = 0.90}
}

-- Static draw arguments: prerender runs every frame and must not allocate.
local DRIVE_STRIP_BG  = {r = 0.08, g = 0.10, b = 0.13, a = 0.75}
local INJURY_JUMP_BG  = {r = 0.35, g = 0.15, b = 0.15, a = 0.85}
local DRIVE_GEAR_OPTS = {drivenAngle = -math.pi / 4}
local ROLLER_OPTS     = {digitWidth = 14, digitHeight = 18, gap = 2, font = UIFont.Small}
local DIAL_OPTS       = {mode = "health"}
local BELT_ACTIVE_OPTS = {label = getText('IGUI_EmberRoutesProbe_Overview_beltHauling')}
local BELT_IDLE_OPTS   = {label = getText('IGUI_EmberRoutesProbe_Overview_beltIdle')}

local DIRECTION_LABELS = {
    N  = getText('IGUI_EmberRoutesProbe_Overview_dirN'),
    NE = getText('IGUI_EmberRoutesProbe_Overview_dirNE'),
    E  = getText('IGUI_EmberRoutesProbe_Overview_dirE'),
    SE = getText('IGUI_EmberRoutesProbe_Overview_dirSE'),
    S  = getText('IGUI_EmberRoutesProbe_Overview_dirS'),
    SW = getText('IGUI_EmberRoutesProbe_Overview_dirSW'),
    W  = getText('IGUI_EmberRoutesProbe_Overview_dirW'),
    NW = getText('IGUI_EmberRoutesProbe_Overview_dirNW')
}

-- World +Y runs south, so a negative dy points north. Eight-way scalar
-- classification avoids trig and keeps the label language-neutral.
local function compassOf(dx, dy)
    local ax, ay = math.abs(dx), math.abs(dy)
    if ax < ay * 0.38 then return dy < 0 and 'N' or 'S' end
    if ay < ax * 0.38 then return dx > 0 and 'E' or 'W' end
    if dx > 0 then return dy < 0 and 'NE' or 'SE' end
    return dy < 0 and 'NW' or 'SW'
end

-- Resolve a real, user-named life/work zone for a world tile. The zone registry
-- lives client-side and is optional (single-player preview hosts may not have
-- any designated zones), so every step is guarded.
local function areaNameAt(scope, x, y, z)
    if not scope or type(x) ~= 'number' or type(y) ~= 'number' then return nil end
    local ok, Zones = pcall(require, 'EmberRoutesProbe/Settlement/SettlementZones')
    if not ok or type(Zones) ~= 'table' or not Zones.list or not Zones.contains then return nil end
    local listedOk, zones = pcall(Zones.list, scope)
    if not listedOk or type(zones) ~= 'table' then return nil end
    local fx, fy = math.floor(x), math.floor(y)
    local fz = (type(z) == 'number') and math.floor(z) or nil
    for _, zone in ipairs(zones) do
        if zone.name and zone.enabled ~= false and Zones.contains(zone, fx, fy, fz) then
            return zone.name
        end
    end
    return nil
end

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
    o.cachedBelt = nil
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
    o.conveyorState = ConveyorBelt.createState(22.0, 18)

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
            self.orderList.vscroll:setX(self.listBounds.width - 16)
            self.orderList.vscroll:setHeight(self.listBounds.height)
        end
        self.listMaxHeight = self.listBounds.height
        self.rightBottomBounds = self.listBounds
    end
end

function EmberRoutesSettlementOverviewPage:rebuildLayout()
    local w, h = self.width or 800, self.height or 600
    local p = self.pad
    local fh = self.fontHeight

    local cardGap = p
    local actionH = math.floor(fh * 1.8)
    local rowStep = fh + math.floor(p * 0.6)
    local vitalsH = (fh + math.floor(p / 2)) + fh + math.floor(p * 0.5)
        + (fh + 4) + math.floor(p * 0.5) + 14
        + math.floor(p * 0.5) + (fh + 4) + p
    local stockH = (fh + p) + 4 * rowStep + fh * 2 + p
    local filterH = math.floor(fh * 1.8)

    if not self.pageHost then
        self.pageHost = LayoutHost:new(0, 0, w, h)
        self.pageHost:initialise()
        self:addChild(self.pageHost)

        -- 1. Pre-allocated bounds tables for zero-GC presentation rendering
        local function initRect(t, defH)
            t = t or {}
            t.x = t.x or 0; t.y = t.y or 0; t.width = t.width or 0; t.height = t.height or (defH or 0); t.visible = t.visible or false
            return t
        end
        self.leftBounds       = initRect(self.leftBounds)
        self.leftVitalsBounds = initRect(self.leftVitalsBounds, vitalsH)
        self.leftStockBounds  = initRect(self.leftStockBounds, stockH)
        self.leftAlertsBounds = initRect(self.leftAlertsBounds, 140)
        self.leftActionBounds = initRect(self.leftActionBounds, actionH)
        self.editAreaBounds   = initRect(self.editAreaBounds)
        self.autoZoneBounds   = initRect(self.autoZoneBounds)
        self.rightBounds      = initRect(self.rightBounds)
        self.rightDriveBounds = initRect(self.rightDriveBounds, 28)
        self.rightBeltBounds  = initRect(self.rightBeltBounds, 20)
        self.filterBounds     = initRect(self.filterBounds, filterH)
        self.listBounds       = initRect(self.listBounds)

        -- 2. Create Native Widgets
        self.editAreaButton = ISButton:new(0, 0, 0, actionH,
            getText("IGUI_EmberRoutesProbe_Settlement_edit"), self, EmberRoutesSettlementOverviewPage.onEditArea)
        self.editAreaButton:initialise()
        Theme.button(self.editAreaButton)
        self.editAreaButton.tooltip = getText("IGUI_EmberRoutesProbe_Settlement_edit")
        Tooltip.register(self.editAreaButton, {method = "prerender", owner = self})

        self.autoZoneButton = ISButton:new(0, 0, 0, actionH,
            getText("IGUI_EmberRoutesProbe_Warehouse_autoZoneBtn"), self, EmberRoutesSettlementOverviewPage.onAutoZone)
        self.autoZoneButton:initialise()
        Theme.button(self.autoZoneButton)
        self.autoZoneButton.tooltip = getText("IGUI_EmberRoutesProbe_Warehouse_autoZoneTooltip")
        Tooltip.register(self.autoZoneButton, {method = "prerender", owner = self})

        local counts = self.store.value.counts or {all = 0, working = 0, waiting = 0, blocked = 0}
        self.filterChips = FilterChips:new(0, 0, 0, filterH, function(key)
            self.activeFilter = key
            self:updateFilteredList()
        end)
        self.filterChips:setOptions({
            {id = 'all',     label = getText('IGUI_EmberRoutesProbe_Overview_filterAll'),     count = counts.all},
            {id = 'working', label = getText('IGUI_EmberRoutesProbe_Overview_filterWorking'), count = counts.working},
            {id = 'waiting', label = getText('IGUI_EmberRoutesProbe_Overview_filterWaiting'), count = counts.waiting},
            {id = 'blocked', label = getText('IGUI_EmberRoutesProbe_Overview_filterBlocked'), count = counts.blocked, alert = (counts.blocked > 0)}
        }, self.activeFilter)

        self.orderList = Cached.create(self, self.listBounds, nil, {
            prepare = function(list, value, label)
                local isExpanded = (self.expandedKey == (value and value.key))
                local hgt = isExpanded and (BASE_CARD_H + DRAWER_H - 2) or BASE_CARD_H
                return {lines = {}, height = hgt}
            end,
            draw = function(list, yPos, entry)
                return self:drawOrderRow(list, yPos, entry)
            end
        })
        Theme.list(self.orderList)
        self.orderList.itemheight = BASE_CARD_H
        self.orderList.onMouseDown = function(list, lx, ly)
            return self:onListMouseDown(list, lx, ly)
        end
        self:addChild(self.orderList)

        -- 3. Declare full page declarative spec with automatic Zero-GC bounds binding
        local spec = UI.Row({ padding = p, gap = p, align = "stretch" }, {
            -- Left Column (38% flex) bound directly to self.leftBounds
            UI.Item(
                UI.Column({ gap = cardGap, align = "stretch" }, {
                    UI.Item(self.leftVitalsBounds, { key = "vitals", basis = vitalsH, bind = self.leftVitalsBounds }),
                    UI.Item(self.leftStockBounds,  { key = "stock",  basis = stockH,  bind = self.leftStockBounds }),
                    UI.Item(self.leftAlertsBounds, { key = "alerts", basis = 140,     bind = self.leftAlertsBounds }),
                    UI.Item(
                        UI.Row({ gap = p, align = "stretch" }, {
                            UI.Item(self.editAreaButton, { key = "editArea", grow = 1, bind = self.editAreaBounds }),
                            UI.Item(self.autoZoneButton, { key = "autoZone", grow = 1, bind = self.autoZoneBounds })
                        }),
                        { key = "actions", basis = actionH, grow = 0, bind = self.leftActionBounds }
                    ),
                    UI.Spacer(1)
                }),
                { key = "leftPane", grow = 38, bind = self.leftBounds }
            ),

            -- Right Column (62% flex) bound directly to self.rightBounds
            UI.Item(
                UI.Column({ gap = 4, align = "stretch" }, {
                    UI.Item(self.rightDriveBounds, { key = "drive",  basis = 28,      bind = self.rightDriveBounds }),
                    UI.Item(self.rightBeltBounds,  { key = "belt",   basis = 20,      bind = self.rightBeltBounds }),
                    UI.Item(self.filterChips,      { key = "filter", basis = filterH, bind = self.filterBounds, margin = { top = math.floor(p * 0.75) } }),
                    UI.Item(self.listBounds,       { key = "orders", grow = 1,        bind = self.listBounds,   margin = { top = math.floor(p / 2) } })
                }),
                { key = "rightPane", grow = 62, bind = self.rightBounds }
            )
        })

        local handles, err = self.pageHost:build(spec)
        assert(handles, err)
        self.layoutHandles = handles
        self.actionHandles = handles
    else
        self.pageHost:setWidth(w)
        self.pageHost:setHeight(h)
    end

    if self.active and self.activationScope and self.activationScope:isCurrent() then
        self.pageHost:setActivation(self.activationScope)
    end

    self:syncLayoutAliases()
    self:applyListHeight()
    self:updatePresentationCache()
end

-- =========================================================================
-- Page Lifecycle & Watch Subscription
-- =========================================================================

function EmberRoutesSettlementOverviewPage:activate()
    local scope = Lifecycle.createActivationScope(self)
    if not scope then return end

    -- Mount Watch 1: Work Overview & Personnel
    if WorkOverviewService.watch then
        scope:watch(function(callback)
            return WorkOverviewService.watch(self.actor, self.entry.id, callback)
        end, function(snapshot)
            if snapshot and snapshot.reason == 'WORLD_RESET' then
                if self.owner and self.owner.close then self.owner:close() end
                return
            end
            self:refresh()
        end)
    end

    -- Mount Watch 2: Warehouse Stockpile Index
    if WarehouseIndex and WarehouseIndex.watch then
        scope:watch(function(callback)
            return WarehouseIndex.watch(self.entry.id, callback)
        end, function(snapshot)
            if snapshot and snapshot.reason == 'WORLD_RESET' then
                if self.owner and self.owner.close then self.owner:close() end
                return
            end
            self:refreshStockpile(snapshot)
        end)
    end

    if self.pageHost and scope:isCurrent() then
        self.pageHost:setActivation(scope)
        self:syncLayoutAliases()
        self:applyListHeight()
    end

    -- Initial state refresh; WarehouseIndex.watch callback will hydrate stockpile snapshot
    self:refresh()
end

function EmberRoutesSettlementOverviewPage:deactivate()
    self.active = false
    if self.pageHost then self.pageHost:deactivate() end
    Lifecycle.unmount(self)
    Tooltip.dismissOwner(self)
    self.expandedKey = nil
    self.expandedOrderId = nil
end

function EmberRoutesSettlementOverviewPage:dispose()
    self.disposed = true
    if self.pageHost then self.pageHost:dispose() end
    self:deactivate()
    Tooltip.unregisterOwner(self)
end

function EmberRoutesSettlementOverviewPage.resolveContext(page, context)
    if not context then return true end
    if context.orderId then return context.orderId end
    return true
end

function EmberRoutesSettlementOverviewPage:applyContext(context)
    if not context then return true end
    if context.orderId then
        self.expandedKey = context.orderId
        self.expandedOrderId = context.orderId
        if self.updateOrderRowHeights then self:updateOrderRowHeights() end
        return true
    end
    return true
end

function EmberRoutesSettlementOverviewPage:focusContent()
    if self.orderList and self.orderList.setScrollChildren then
        self.orderList:setScrollChildren(true)
    end
end

-- =========================================================================
-- Data Refresh & Presentation Cache Projection (Zero-GC)
-- =========================================================================

function EmberRoutesSettlementOverviewPage:refresh()
    if not self.active or self.disposed then return end

    local overview = WorkOverviewService.status(self.actor, self.entry.id)
    local craftStatus = CraftingService.status(self.actor, self.entry.id)
    local rawWorkers = craftStatus.workers or {}
    local enriched = PersonnelService.enrichWorkers(self.actor, self.entry.id, rawWorkers)

    local vitals = {
        population = #enriched,
        working = 0,
        idle = 0,
        injured = 0,
        infected = 0,
        firstInjuredId = nil
    }

    local byNpc = overview.byNpc or {}
    for _, w in ipairs(enriched) do
        local work = byNpc[w.id]
        if work and (work.state == 'working' or work.state == 'running') then
            vitals.working = vitals.working + 1
        else
            vitals.idle = vitals.idle + 1
        end
        local isInjured = w.hasInjury or w.isBleeding
        if isInjured then
            vitals.injured = vitals.injured + 1
            if not vitals.firstInjuredId then vitals.firstInjuredId = w.id end
        end
        if w.isInfected then
            vitals.infected = vitals.infected + 1
            if not vitals.firstInjuredId then vitals.firstInjuredId = w.id end
        end
    end

    local works = overview.works or {}
    local counts = {all = #works, working = 0, waiting = 0, blocked = 0}
    local isHauling = false
    local isCrafting = false

    for _, item in ipairs(works) do
        local row = item.row or {}
        if row.npcId then
            for _, w in ipairs(enriched) do
                if w.id == row.npcId then
                    item.workerName = item.workerName or w.name
                    item.workerInjured = w.hasInjury or w.isBleeding
                    item.workerHealth = w.health
                    break
                end
            end
        end

        if item.state == 'working' or item.state == 'running' then
            counts.working = counts.working + 1
            if item.category == 'hauling' then isHauling = true end
            if item.category == 'crafting' then isCrafting = true end
        elseif item.state == 'waiting' or not (row and row.npcId) then
            counts.waiting = counts.waiting + 1
        end

        if item.state == 'blocked' then
            counts.blocked = counts.blocked + 1
        end
    end

    local defenseRatio = vitals.population > 0
        and math.max(0, math.min(1.0, (vitals.population - vitals.injured - vitals.infected) / vitals.population))
        or 1.0

    self.cachedData.popCount = vitals.population
    self.cachedData.workingCount = vitals.working
    self.cachedData.idleCount = vitals.idle
    self.cachedData.injuredCount = vitals.injured
    self.cachedData.defenseRatio = defenseRatio
    self.cachedData.isHauling = isHauling
    self.cachedData.isCrafting = isCrafting

    -- First projection snaps the odometer; later population changes still roll.
    local roller = self.popRollerState
    if roller.current == 0 and roller.target == 0 then
        roller.current = vitals.population
        roller.target = vitals.population
    end

    local stockRows = (self.lastStockSnapshot and self.lastStockSnapshot.rows) or {}
    local currentStock = SupplyEstimate.calculate(stockRows, vitals.population)


    self.store:setState({
        works = works,
        vitals = vitals,
        counts = counts,
        stockpile = currentStock,
        revision = self.store.value.revision + 1
    })

    if self.filterChips then
        -- Chip geometry is measured text: rebuild only when labels or counts
        -- actually change, not on every 1s refresh.
        local chipKey = tostring(self.activeFilter) .. ":" .. counts.all .. ":" .. counts.working
            .. ":" .. counts.waiting .. ":" .. counts.blocked
        if chipKey ~= self.filterChipKey then
            self.filterChipKey = chipKey
            self.filterChips:setOptions({
                {id = 'all',     label = getText('IGUI_EmberRoutesProbe_Overview_filterAll'),     count = counts.all},
                {id = 'working', label = getText('IGUI_EmberRoutesProbe_Overview_filterWorking'), count = counts.working},
                {id = 'waiting', label = getText('IGUI_EmberRoutesProbe_Overview_filterWaiting'), count = counts.waiting},
                {id = 'blocked', label = getText('IGUI_EmberRoutesProbe_Overview_filterBlocked'), count = counts.blocked, alert = (counts.blocked > 0)}
            }, self.activeFilter)
        end
    end

    self:updatePresentationCache()
    self:updateFilteredList()
end

function EmberRoutesSettlementOverviewPage:refreshStockpile(snapshot)
    if not self.active or self.disposed then return end
    self.lastStockSnapshot = snapshot or self.lastStockSnapshot
    local currentSnapshot = self.lastStockSnapshot
    if not currentSnapshot or not currentSnapshot.rows then return end

    local pop = (self.store and self.store.value and self.store.value.vitals and self.store.value.vitals.population) or 0
    local stock = SupplyEstimate.calculate(currentSnapshot.rows, pop)

    self.store:setState({
        stockpile = stock,
        revision = self.store.value.revision + 1
    })



    self:updatePresentationCache()
end

---Precomputes all strings, measurements and colors in state updates to guarantee Zero-GC in render.
function EmberRoutesSettlementOverviewPage:updatePresentationCache()
    local h, p = self.fontHeight, self.pad
    local left = self.leftBounds
    local stockBounds = self.leftStockBounds
    local vitalsBounds = self.leftVitalsBounds
    if not left or not left.width or left.width <= 0 or not stockBounds or not vitalsBounds then return end

    local cardGap = p
    local vitalsH = vitalsBounds.height
    local stockH  = stockBounds.height
    local stockY  = stockBounds.y

    local vitals = self.store.value.vitals
    local hasInjury = (vitals.injured > 0 or vitals.infected > 0)
    local cardW = left.width - p * 2

    -- 1. Population headline: the number itself is the mechanical odometer,
    --    so the text keeps only its label (no duplicated readout).
    local popY = left.y + h + math.floor(p / 2)
    self.cachedVitalsHeader = {
        popText = getText('IGUI_EmberRoutesProbe_Overview_population'),
        x = left.x + p,
        y = popY
    }
    local rollerW = MechanicalRoller.measureWidth(3, ROLLER_OPTS.digitWidth, ROLLER_OPTS.gap)
    self.cachedPopRoller = {
        x = left.x + left.width - p - rollerW,
        y = popY - 4
    }

    -- 2. Dual Indicators: Work & Leisure Badges (Scheme B - Layer 1, SemanticBadge reuse)
    local badgeGap = 6
    local badgeW = math.floor((cardW - badgeGap) / 2)
    local badgeH = h + 4
    local badgeY = popY + h + math.floor(p * 0.5)

    local workLabel = tostring(vitals.working) .. " " .. getText('IGUI_EmberRoutesProbe_Overview_working')
    local leisureLabel = tostring(vitals.idle) .. " " .. getText('IGUI_EmberRoutesProbe_Overview_leisure')

    local workBadge = SemanticBadge.resolve('WORK', workLabel)
    workBadge.x = left.x + p
    workBadge.y = badgeY
    workBadge.width = badgeW
    workBadge.height = badgeH

    local leisureBadge = SemanticBadge.resolve('LEISURE', leisureLabel)
    leisureBadge.x = left.x + p + badgeW + badgeGap
    leisureBadge.y = badgeY
    leisureBadge.width = badgeW
    leisureBadge.height = badgeH

    self.cachedWorkBadge = workBadge
    self.cachedLeisureBadge = leisureBadge

    -- 3. Comparative Ratio Bar: Work vs Leisure (Scheme B - Layer 2, StatMeter.drawSplitBar reuse)
    local splitBarY = badgeY + badgeH + math.floor(p * 0.5)
    local splitBarH = 14
    local workRatio = vitals.population > 0 and math.min(1.0, vitals.working / vitals.population) or 0

    self.cachedWorkforceSplit = {
        x = left.x + p,
        y = splitBarY,
        width = cardW,
        height = splitBarH,
        ratio = workRatio,
        opts = {
            isEmpty = (vitals.population <= 0),
            colorA = Theme.accent or {r = 0.25, g = 0.75, b = 1.00, a = 1.0},
            colorB = Theme.status.READY or {r = 0.35, g = 0.88, b = 0.60, a = 1.0}
        }
    }

    -- 4. Injured Settler 1-Click Jump Capsule
    if hasInjury and vitals.firstInjuredId then
        local jumpY = splitBarY + splitBarH + math.floor(p * 0.5)
        local jumpText = getText('IGUI_EmberRoutesProbe_Overview_locateInjured')
        local jumpTextW = getTextManager():MeasureStringX(UIFont.Small, jumpText)
        local tx = left.x + p + math.floor((cardW - jumpTextW) / 2)
        local markSize = 10
        self.cachedInjuredJump = {
            x = left.x + p,
            y = jumpY,
            width = cardW,
            height = h + 4,
            text = jumpText,
            tx = tx,
            ty = jumpY + 2,
            markSize = markSize,
            leadX = tx - markSize - 6,
            trailX = tx + jumpTextW + 6,
            markY = jumpY + math.floor((h + 4 - markSize) / 2),
            npcId = vitals.firstInjuredId
        }
    else
        self.cachedInjuredJump = nil
    end

    -- Card 2: Core Stockpile Inventory & Survival Projections with Mini-Gauges
    local stock = self.store.value.stockpile or SupplyEstimate.calculate({}, 0)
    local tm = getTextManager()

    local stockDefs = {
        {
            key = 'food',
            label = getText('IGUI_EmberRoutesProbe_Overview_foodSecurity'),
            valText = stock.hasPopulation
                and (string.format("%.1f", stock.foodDays) .. " " .. getText('IGUI_EmberRoutesProbe_Overview_unitDays') .. " (" .. tostring(stock.totalFoodCount) .. getText('IGUI_EmberRoutesProbe_Overview_unitPortion') .. ")")
                or ("-- " .. getText('IGUI_EmberRoutesProbe_Overview_unitDays') .. " (" .. tostring(stock.totalFoodCount) .. getText('IGUI_EmberRoutesProbe_Overview_unitPortion') .. ")"),
            fillRatio = math.max(0, math.min(1.0, stock.foodDays / SupplyEstimate.SATURATION_DAYS)),
            isCritical = (stock.hasPopulation and stock.foodDays < 2.0 or stock.totalFoodCount <= 0),
            isWarning = (stock.hasPopulation and stock.foodDays < 5.0),
            defaultColor = STOCK_COLORS.meals
        },
        {
            key = 'water',
            label = getText('IGUI_EmberRoutesProbe_Overview_waterSecurity'),
            valText = stock.hasPopulation
                and (string.format("%.1f", stock.waterDays) .. " " .. getText('IGUI_EmberRoutesProbe_Overview_unitDays') .. " (" .. tostring(stock.waterCount) .. getText('IGUI_EmberRoutesProbe_Overview_unitPortion') .. ")")
                or ("-- " .. getText('IGUI_EmberRoutesProbe_Overview_unitDays') .. " (" .. tostring(stock.waterCount) .. getText('IGUI_EmberRoutesProbe_Overview_unitPortion') .. ")"),
            fillRatio = math.max(0, math.min(1.0, stock.waterDays / SupplyEstimate.SATURATION_DAYS)),
            isCritical = (stock.hasPopulation and stock.waterDays < 2.0 or stock.waterCount <= 0),
            isWarning = (stock.hasPopulation and stock.waterDays < 5.0),
            defaultColor = STOCK_COLORS.water
        },
        {
            key = 'medical',
            label = getText('IGUI_EmberRoutesProbe_Overview_medical'),
            valText = tostring(stock.medicalCount) .. " " .. getText('IGUI_EmberRoutesProbe_Overview_unitPortion'),
            fillRatio = math.max(0, math.min(1.0, stock.medicalCount / 30.0)),
            isCritical = (stock.medicalCount <= 0),
            isWarning = false,
            defaultColor = STOCK_COLORS.medical
        },
        {
            key = 'wood',
            label = getText('IGUI_EmberRoutesProbe_Overview_wood'),
            valText = tostring(stock.woodCount) .. " " .. getText('IGUI_EmberRoutesProbe_Overview_unitCount'),
            fillRatio = math.max(0, math.min(1.0, stock.woodCount / 100.0)),
            isCritical = (stock.woodCount <= 0),
            isWarning = false,
            defaultColor = STOCK_COLORS.wood
        }
    }

    local stockGauges = {}
    local sy = stockY + h + p
    local labelColW = math.floor(cardW * 0.38)
    local barW = math.floor(cardW * 0.28)
    local barH = 8

    for _, st in ipairs(stockDefs) do
        local valWidth = tm and tm:MeasureStringX(UIFont.Small, st.valText) or 60
        local barColor = st.isCritical and Theme.status.ERROR
                      or (st.isWarning and Theme.status.UPDATING or st.defaultColor)

        stockGauges[#stockGauges + 1] = {
            label = st.label,
            labelX = left.x + p,
            valText = st.valText,
            valX = left.x + cardW + p - valWidth,
            valColor = st.isCritical and Theme.status.ERROR or Theme.textColor,
            barX = left.x + p + labelColW + 4,
            barY = sy + math.floor((h - barH) / 2),
            barW = barW,
            barH = barH,
            fraction = st.fillRatio,
            meterOpts = {
                mode = "progress",
                threshold = 0.2,
                color = barColor
            },
            y = sy
        }
        sy = sy + h + math.floor(p * 0.6)
    end
    self.cachedStockpileLines = stockGauges

    local badgeText, badgeColor
    if not stock.hasPopulation then
        badgeText = getText('IGUI_EmberRoutesProbe_Overview_badgeEmpty')
        badgeColor = Theme.status.MUTED
    elseif stock.status == "CRITICAL" then
        badgeText = getText('IGUI_EmberRoutesProbe_Overview_badgeCritical')
        badgeColor = Theme.status.ERROR
    elseif stock.status == "WARNING" then
        badgeText = getText('IGUI_EmberRoutesProbe_Overview_badgeWarning')
        badgeColor = Theme.status.UPDATING

    else
        badgeText = getText('IGUI_EmberRoutesProbe_Overview_badgeSecure')
        badgeColor = Theme.status.READY
    end

    local vitalsBadgeText, vitalsBadgeColor
    if hasInjury then
        vitalsBadgeText = "^ " .. tostring(vitals.injured + vitals.infected) .. " " .. getText('IGUI_EmberRoutesProbe_Overview_injured')
        vitalsBadgeColor = Theme.status.ERROR
    else
        vitalsBadgeText = getText('IGUI_EmberRoutesProbe_Overview_settlementStable')
        vitalsBadgeColor = Theme.status.READY
    end

    self.cardVitalsOptions = self.cardVitalsOptions or {
        title = getText('IGUI_EmberRoutesProbe_Overview_vitalsTitle'),
        frameStyle = 'briefing'
    }
    self.cardVitalsOptions.title = getText('IGUI_EmberRoutesProbe_Overview_vitalsTitle')
    self.cardVitalsOptions.badge = vitalsBadgeText
    self.cardVitalsOptions.badgeColor = vitalsBadgeColor

    self.cardStockpileOptions = self.cardStockpileOptions or {
        title = getText('IGUI_EmberRoutesProbe_Overview_stockpileTitle'),
        frameStyle = 'briefing'
    }
    self.cardStockpileOptions.title = getText('IGUI_EmberRoutesProbe_Overview_stockpileTitle')
    self.cardStockpileOptions.badge = badgeText
    self.cardStockpileOptions.badgeColor = badgeColor

    local burnText = stock.hasPopulation
        and getText('IGUI_EmberRoutesProbe_Overview_dailyBurn',
            string.format("%.1f", stock.foodDailyDemand),
            string.format("%.1f", stock.waterDailyDemand),
            tostring(stock.population))
        or getText('IGUI_EmberRoutesProbe_Overview_noSettlersBurn')

    local breakdownText = getText('IGUI_EmberRoutesProbe_Overview_stockBreakdown',
        tostring(stock.mealsCount), tostring(stock.cropsCount))

    local footerY1 = math.max(sy + 4, stockY + stockH - p - h * 2 - 2)
    local footerY2 = footerY1 + h

    self.cachedStockpileFooter = {
        burnText = burnText,
        breakdownText = breakdownText,
        x = left.x + p,
        y1 = footerY1,
        y2 = footerY2,
        burnColor = Theme.muted or Theme.textColor,
        breakdownColor = Theme.muted or Theme.textColor
    }

    -- 5. Production drive strip: text, measurement and badge resolution are
    -- derived here so prerender stays a pure draw pass (no JNI measurement,
    -- no string concatenation, no table allocation per frame).
    local db = self.rightDriveBounds
    if db then
        local driveTitle = getText('IGUI_EmberRoutesProbe_Overview_driveTitle')
        local titleW = tm and tm:MeasureStringX(UIFont.Small, driveTitle) or 70
        local activeDesc
        if self.cachedData.workingCount > 0 then
            activeDesc = "  " .. tostring(self.cachedData.workingCount) .. " "
                .. getText('IGUI_EmberRoutesProbe_Overview_driveActiveWorkers')
        end
        -- The filter chip is the single red "blocked" entry point. The drive
        -- badge reports only the mechanical running / standby state, so a
        -- blocked order no longer paints the same alert twice.
        local tone = self.cachedData.workingCount > 0 and 'PROCESSING' or 'WAITING'
        local label = self.cachedData.workingCount > 0
            and getText('IGUI_EmberRoutesProbe_Overview_driveRunning')
            or getText('IGUI_EmberRoutesProbe_Overview_driveIdle')
        self.cachedDriveStrip = {
            x = db.x, y = db.y, width = db.width, height = db.height,
            titleText = driveTitle,
            gearCx = db.x + 18,
            gearCy = db.y + math.floor(db.height / 2),
            titleX = db.x + 40,
            titleY = db.y + math.floor((db.height - h) / 2),
            descText = activeDesc,
            descX = db.x + 40 + titleW,
            badge = SemanticBadge.resolve(tone, label),
            badgeX = db.x + db.width - 92,
            badgeY = db.y + math.floor((db.height - 18) / 2)
        }
    else
        self.cachedDriveStrip = nil
    end

    -- 6. Logistics belt: drawn from the very state prerender advances.
    local belt = self.rightBeltBounds
    self.cachedBelt = belt and {x = belt.x, y = belt.y, width = belt.width, height = belt.height} or nil

    -- 7. Readiness / alert card: the radial dial needs >= 72px, so it lives
    --    here rather than in the 28px drive header. Leftover height that used
    --    to be an empty stretched card now carries alert details or an empty state.
    local ab = self.leftAlertsBounds
    if ab then
        self.cardAlertsOptions = self.cardAlertsOptions or {frameStyle = 'briefing'}
        self.cardAlertsOptions.title = getText('IGUI_EmberRoutesProbe_Overview_readinessTitle')
        local radius = 36
        local headerH = h + math.max(4, math.floor(h * 0.4))
        local counts = self.store.value.counts or {}
        local blockedN = counts.blocked or 0
        local injuredN = (vitals.injured or 0) + (vitals.infected or 0)
        local lines = {}
        if blockedN > 0 then
            lines[#lines + 1] = {text = getText('IGUI_EmberRoutesProbe_Overview_alertBlocked', tostring(blockedN)), color = Theme.status.ERROR}
        end
        if injuredN > 0 then
            lines[#lines + 1] = {text = getText('IGUI_EmberRoutesProbe_Overview_alertInjured', tostring(injuredN)), color = Theme.status.UPDATING}
        end
        if #lines == 0 then
            lines[1] = {text = getText('IGUI_EmberRoutesProbe_Overview_noAlerts'), color = Theme.muted}
        end
        for i, line in ipairs(lines) do
            line.x = ab.x + p + radius * 2 + p * 2
            line.y = ab.y + headerH + 12 + (i - 1) * (h + 6)
        end
        self.cachedAlerts = {
            x = ab.x, y = ab.y, width = ab.width, height = ab.height,
            opts = self.cardAlertsOptions,
            dialCx = ab.x + p + radius + 4,
            dialCy = ab.y + headerH + radius + 4,
            dialRadius = radius, dialOpts = DIAL_OPTS,
            hintText = getText('IGUI_EmberRoutesProbe_Overview_readinessHint'),
            hintX = ab.x + p + 4,
            hintY = ab.y + headerH + radius * 2 + 10,
            lines = lines
        }
    else
        self.cachedAlerts = nil
    end

    -- 8. Both columns are content-sized now; mark the end of content instead
    --    of leaving two half-empty full-height panels.
    local leftEnd = self.leftActionBounds and (self.leftActionBounds.y + self.leftActionBounds.height) or (p + 200)
    local listEnd = self.listBounds and (self.listBounds.y + self.listBounds.height) or 0
    local endY = math.max(leftEnd, listEnd) + p
    local endText = getText('IGUI_EmberRoutesProbe_Overview_noMoreOrders')
    local endTextW = tm and tm:MeasureStringX(UIFont.Small, endText) or 120
    self.cachedEndRule = {
        x = p, y = endY, width = self.width - p * 2,
        text = endText,
        textX = p + math.floor((self.width - p * 2 - endTextW) / 2),
        textY = endY + 8
    }
end

function EmberRoutesSettlementOverviewPage:update()
    ISPanel.update(self)
    if not self.active or self.disposed then return end
    -- Low-frequency 1.0s viewport heartbeat for intermediate native action polling
    local now = getTimestampMs and getTimestampMs() or (os.time() * 1000)
    if not self._lastCadencePulse or (now - self._lastCadencePulse) >= 1000 then
        self._lastCadencePulse = now
        self:refresh()
    end
end

function EmberRoutesSettlementOverviewPage:updateFilteredList()
    if not self.orderList then return end
    local filter = self.activeFilter
    local works = self.store.value.works or {}
    local filtered = {}

    for _, item in ipairs(works) do
        local match = false
        if filter == 'all' then
            match = true
        elseif filter == 'blocked' and item.state == 'blocked' then
            match = true
        elseif filter == 'working' and (item.state == 'working' or item.state == 'running') then
            match = true
        elseif filter == 'waiting' and item.state ~= 'blocked' and item.state ~= 'working' and item.state ~= 'running' then
            match = true
        end

        if match then
            filtered[#filtered + 1] = item
        end
    end

    -- Reconcile into CachedList (Full domain signature for real-time custody & stage reactivity)
    Cached.reconcile(self.orderList, filtered, function(w)
        local sig = w.row and Cards.signature(w.row) or tostring(w.state or "idle")
        return tostring(w.key or w.id) .. ":" .. sig
    end, function(w)
        return tostring(w.key or w.id or w.title or w.name or "order")
    end, true)

    self:updateOrderRowHeights()
end

function EmberRoutesSettlementOverviewPage:getGroupedAssets(row)
    if not row or not row.assets or #row.assets == 0 then return nil end
    local sig = tostring(row.phase or '') .. ":" .. tostring(row.delivered or 0) .. ":" .. tostring(row.reason or '')
    for _, a in ipairs(row.assets) do
        sig = sig .. "|" .. tostring(a.id or '') .. ":" .. tostring(a.custodyState or '') .. ":" .. tostring(a.delivered == true)
    end
    if row._cachedAssetSig == sig and row._groupedAssets then
        return row._groupedAssets
    end
    local grouped, list = {}, {}
    for _, asset in ipairs(row.assets) do
        local status = Cards.assetStatus(row, asset)
        local key = (asset.fullType or asset.displayName or '?') .. ':' .. (asset.kind or '') .. ':' .. status
        local group = grouped[key]
        if not group then
            local fullType = asset.fullType
            local getName = _G.getItemNameFromFullType
            local name = (fullType and type(getName) == "function" and getName(fullType))
                or fullType or asset.displayName or getText('IGUI_EmberRoutesProbe_Monitor_unknownItem')
            local badgeDesc = SemanticBadge.resolve(status)
            group = {
                asset = asset,
                fullType = fullType,
                name = name,
                status = status,
                badge = badgeDesc,
                count = 0,
                kind = asset.kind
            }
            grouped[key] = group
            list[#list + 1] = group
        end
        group.count = group.count + 1
    end
    local alerts = {RECONCILE = true, MISSING = true, DISCREPANCY = true}
    table.sort(list, function(a, b)
        local aa, bb = alerts[a.status] == true, alerts[b.status] == true
        if aa ~= bb then return aa end
        return tostring(a.name) < tostring(b.name)
    end)
    for _, g in ipairs(list) do
        local countStr = (g.count and g.count > 1) and (' x ' .. tostring(g.count)) or ' x 1'
        g.displayName = (g.name or '') .. countStr
    end
    row._cachedAssetSig = sig
    row._groupedAssets = list
    return list
end

function EmberRoutesSettlementOverviewPage:getDrawerHeight(item)
    if not item then return 150 end
    local row = item.row or {}
    local assets = self:getGroupedAssets(row)
    if item._cachedDrawerH and item._cachedDrawerAssets == assets and item._cachedDrawerAssetSig == (row and row._cachedAssetSig) then
        return item._cachedDrawerH
    end

    -- 1. Top Section Height (padding + locStr + stage steps track)
    local locH = 22
    local trackH = (row._cachedTrack and row._cachedTrack.height) or 48
    local topH = 8 + locH + trackH + 8

    -- 2. Middle Content Height (assets / progress / recipe)
    local contentH = 0
    if assets and #assets > 0 then
        local count = math.min(3, #assets)
        local extra = (#assets > 3) and 20 or 0
        contentH = count * 24 + extra
    elseif row.targetCount and row.targetCount > 0 then
        contentH = 24
    elseif row.recipeName then
        contentH = 20
    else
        contentH = 10
    end

    -- 3. Bottom Action Bar Height (View Dossier & Stop Body buttons)
    local npcId = item.npcId or row.npcId
    local canStop = (row.kind == 'FIELD_WORK' and row.jobId ~= nil and row.generation ~= nil and not row.closed and row.carrierAvailable and row.bucket == 'active') or (row.canPause == true)
    local bottomBarH = 12
    if npcId or canStop then
        bottomBarH = 12 + 22 + 10 -- topMargin(12) + btnH(22) + bottomMargin(10)
    end

    local h = math.max(150, topH + contentH + bottomBarH)
    item._cachedDrawerH = h
    item._cachedDrawerAssets = assets
    item._cachedDrawerAssetSig = row and row._cachedAssetSig
    return h
end

---Keeps the list viewport as tall as its rows, never taller than the page.
---Height and hit-testing stay in the existing coordinate system.
function EmberRoutesSettlementOverviewPage:applyListHeight()
    if not self.listBounds or not self.orderList then return end
    local maxH = self.listMaxHeight or self.listBounds.height
    local wanted = math.max(BASE_CARD_H, math.min(maxH, self.listContentH or maxH))
    self.listBounds.height = wanted
    self.rightBottomBounds = self.listBounds
    self.orderList:setHeight(wanted)
    if self.orderList.vscroll then
        self.orderList.vscroll:setX(self.listBounds.width - 16)
        self.orderList.vscroll:setHeight(wanted)
    end
    -- The footer rule tracks the shorter viewport without re-measuring text.
    local e = self.cachedEndRule
    if e then
        local leftEnd = self.leftActionBounds and (self.leftActionBounds.y + self.leftActionBounds.height) or 0
        local listEnd = self.listBounds.y + self.listBounds.height
        e.y = math.max(leftEnd, listEnd) + self.pad
        e.textY = e.y + 8
    end
end

---Updates existing row heights without clearing or reflowing list items (ProjectRemnants parity).
function EmberRoutesSettlementOverviewPage:updateOrderRowHeights()
    if not self.orderList or not self.orderList.items then return end
    local totalH = 0
    for _, entry in ipairs(self.orderList.items) do
        local item = entry.item and (entry.item.value or entry.item)
        local isExpanded = item and (self.expandedKey == (item.key or item.id))
        local drawerH = isExpanded and self:getDrawerHeight(item) or 0
        entry.height = isExpanded and (BASE_CARD_H + drawerH) or BASE_CARD_H
        totalH = totalH + entry.height
    end
    self.orderList:setScrollHeight(totalH)
    self.listContentH = totalH
    self:applyListHeight()
end

-- =========================================================================
-- List Drawing & ProjectRemnants Seam-Welded Drawer Interaction
-- =========================================================================

---Project a world route into a user-facing named area plus a compass bearing.
---Raw tile coordinates are an internal identifier, never player-facing copy.
function EmberRoutesSettlementOverviewPage:formatRouteLabel(item, row)
    local cached = row._cachedLocStr
    if cached ~= nil then return cached or nil end

    local scope = self.entry and self.entry.id
    local fallback = (self.entry and type(self.entry.name) == 'string' and self.entry.name ~= '' and self.entry.name)
        or getText('IGUI_EmberRoutesProbe_Overview_routeAreaFallback')

    local function nameOf(point)
        if type(point) == 'string' and point ~= '' then return point end
        if type(point) == 'table' and type(point.x) == 'number' and type(point.y) == 'number' then
            return areaNameAt(scope, point.x, point.y, point.z) or fallback
        end
        return nil
    end

    local tLoc = item.targetLocation or row.targetLocation
    local source = row.source or item.source
    local destination = row.destination or item.destination
    local target = nameOf(tLoc) or nameOf(destination)
    if not target and (item.category == 'farming' or row.workCategory == 'farming') then
        target = getText('IGUI_EmberRoutesProbe_Public_farming')
    end

    local detail = ''
    local to = destination
    if type(tLoc) == 'table' and tLoc.x and tLoc.y then to = tLoc end
    if type(source) == 'table' and type(to) == 'table'
        and type(source.x) == 'number' and type(source.y) == 'number'
        and type(to.x) == 'number' and type(to.y) == 'number' then
        local dx, dy = to.x - source.x, to.y - source.y
        if dx ~= 0 or dy ~= 0 then
            local tiles = tostring(math.floor(math.sqrt(dx * dx + dy * dy) + 0.5))
            detail = getText('IGUI_EmberRoutesProbe_Overview_routeBearing',
                DIRECTION_LABELS[compassOf(dx, dy)],
                getText('IGUI_EmberRoutesProbe_Overview_routeTiles', tiles))
        end
    end

    local sourceName = nameOf(source)
    local result
    if target then
        result = getText('IGUI_EmberRoutesProbe_Overview_routeTarget', target, detail)
    elseif sourceName then
        result = getText('IGUI_EmberRoutesProbe_Overview_routeSource', sourceName)
    end
    row._cachedLocStr = result or false
    return result
end

function EmberRoutesSettlementOverviewPage:drawOrderRow(list, y, entry)
    local item = entry.item and (entry.item.value or entry.item)
    if not item then return y + (entry.height or BASE_CARD_H) end

    local cardW = list:getWidth() - (list.vscroll and 16 or 0)
    local isExpanded = (self.expandedKey == (item.key or item.id))
    local drawerH = isExpanded and self:getDrawerHeight(item) or 0
    local targetH = isExpanded and (BASE_CARD_H + drawerH) or BASE_CARD_H
    entry.height = targetH

    -- 1. Draw Base Order Card Header & Outer Border
    local isSelected = (list.selected == entry.index)
    local bgA = isSelected and 0.88 or 0.65
    local bgCol = {r = 0.08, g = 0.10, b = 0.13, a = bgA}
    local borderCol = isSelected and Theme.accent or Theme.border

    Theme.rect(list, 0, y, cardW, BASE_CARD_H, bgCol)
    if not isExpanded then
        Theme.rect(list, 0, y, cardW, BASE_CARD_H, borderCol, true)
    else
        -- Unified continuous outer container frame wrapping header + drawer in one piece
        Theme.rect(list, 0, y, cardW, targetH, borderCol, true)
    end

    -- Status accent pill
    local stCol = (item.state == 'working' and Theme.status.SUCCESS)
               or (item.state == 'blocked' and Theme.status.ERROR)
               or (item.state == 'paused'  and Theme.status.WARNING)
               or Theme.status.MUTED
    Theme.rect(list, 2, y + 2, 4, BASE_CARD_H - 4, stCol)

    -- Titles & Worker (Zero-GC Cached Strings & Measured Dimensions)
    local tm = getTextManager()
    local title = item.title or getText("IGUI_EmberRoutesProbe_Overview_noOrders")
    Theme.text(list, title, 14, y + 8, Theme.textColor, UIFont.Small)

    local row = item.row or {}
    if row.targetCount and row.targetCount > 0 then
        if item._cachedCountText == nil or item._cachedTargetCount ~= row.targetCount then
            item._cachedTargetCount = row.targetCount
            item._cachedCountText = tostring(row.targetCount) .. " " .. getText("IGUI_EmberRoutesProbe_Overview_unitCount")
            item._cachedCountW = tm and tm:MeasureStringX(UIFont.Small, item._cachedCountText) or 24
            item._cachedTitleW = tm and tm:MeasureStringX(UIFont.Small, title) or (#title * 8)
            item._cachedCountX = 14 + item._cachedTitleW + 8
        end
        local countX = item._cachedCountX
        local countW = item._cachedCountW
        if countX + countW + 12 < cardW - 130 then
            Theme.rect(list, countX, y + 7, countW + 12, 16, Theme.control)
            Theme.rect(list, countX, y + 7, countW + 12, 16, Theme.border, true)
            Theme.text(list, item._cachedCountText, countX + 6, y + 8, Theme.muted, UIFont.Small)
        end
    end

    if item._cachedWorkerText == nil or item._cachedWorkerName ~= item.workerName then
        item._cachedWorkerName = item.workerName
        item._cachedWorkerText = item.workerName
            and (getText("IGUI_EmberRoutesProbe_Overview_worker") .. ": " .. item.workerName)
            or getText("IGUI_EmberRoutesProbe_Distributed_unassigned")
    end
    local workerCol = item.workerInjured and Theme.status.ERROR or {r = 0.65, g = 0.72, b = 0.80, a = 0.90}
    Theme.text(list, item._cachedWorkerText, 14, y + 28, workerCol, UIFont.Small)
    if not isExpanded then
        local assets = self:getGroupedAssets(row)
        if assets and #assets > 0 and assets[1] then
            local firstAsset = assets[1]
            local assetSummary = firstAsset.displayName or firstAsset.name
            if assetSummary then
                local workerW = tm and tm:MeasureStringX(UIFont.Small, item._cachedWorkerText) or (#item._cachedWorkerText * 8)
                local assetX = 14 + workerW + 14
                if assetX + 60 < cardW - 130 then
                    -- 1px geometric divider instead of a visible pipe character.
                    Theme.rect(list, assetX - 8, y + 31, 1, 10, Theme.border)
                    Theme.text(list, assetSummary, assetX, y + 28, Theme.muted, UIFont.Small)
                end
            end
        end
    end

    -- Semantic Status Badge (Cached resolution)
    if item._cachedState ~= item.state or not item._cachedBadge then
        local stateKey = 'IGUI_EmberRoutesProbe_Distributed_' .. (item.state or 'idle')
        local stateLabel = (getTextOrNull and getTextOrNull(stateKey)) or (getText and getText(stateKey)) or (item.state or 'idle')
        local mappedTone = (item.state == 'working' and 'PROCESSING')
                        or (item.state == 'blocked' and 'DISCREPANCY')
                        or (item.state == 'paused'  and 'PAUSED')
                        or 'WAITING'
        item._cachedBadge = SemanticBadge.resolve(mappedTone, stateLabel)
        item._cachedState = item.state
    end
    SemanticBadge.draw(list, cardW - 120, y + math.floor((BASE_CARD_H - 18) / 2), 76, 18, item._cachedBadge)

    -- Expand indicator: geometric chevron from the shared status visual module.
    local markSize = 10
    StatusVisual.mark(list, cardW - markSize - 12, y + 10, markSize,
        isExpanded and "chevronUp" or "chevronDown", Theme.accent)

    -- 2. If Expanded: Draw Unified Integrated Drawer
    if isExpanded then
        local shelfY = y + BASE_CARD_H
        local shelfH = drawerH
        local bgDrawer = {r = 0.05, g = 0.07, b = 0.09, a = 0.95}

        -- Drawer container background (seamlessly inset within outer continuous border)
        Theme.rect(list, 1, shelfY, cardW - 2, shelfH - 1, bgDrawer)

        -- Subtle inner soft divider line (inset, low contrast, zero harsh yellow border)
        Theme.rect(list, 14, shelfY, cardW - 28, 1, {r = borderCol.r, g = borderCol.g, b = borderCol.b, a = 0.18})

        local curY = shelfY + 8

        -- A. Route information projected to a named area + compass bearing.
        local locStr = self:formatRouteLabel(item, row)
        if locStr then
            Theme.text(list, locStr, 14, curY, {r = 0.85, g = 0.90, b = 0.95, a = 0.95}, UIFont.Small)
            curY = curY + 22
        else
            curY = curY + 16
        end

        -- B. Pipeline Lifecycle Steps (StatusVisual PREPARE -> WORK -> COLLECT -> DELIVER or domain stages)
        local stages = (row.stages and #row.stages > 0) and Cards.stageNames(row) or STAGE_LABELS
        local currentPhase = row.phase or (item.state == 'working' and 'WORK' or 'PREPARE')
        local stageIdx = (row.stages and #row.stages > 0) and Cards.phaseIndex(row)
            or (STAGE_INDEX[currentPhase] or (currentPhase == 'COLLECT' and 3 or (currentPhase == 'DELIVER' and 4 or (item.state == 'working' and 2 or 1))))
        local visualState = (item.state == 'blocked') and 'blocked' or ((item.state == 'paused') and 'paused' or 'active')
        local trackSig = tostring(stageIdx) .. ":" .. tostring(visualState) .. ":" .. tostring(cardW)
        if row.stages then
            for _, s in ipairs(row.stages) do
                trackSig = trackSig .. "|" .. tostring(s.key) .. ":" .. tostring(s.status) .. ":" .. tostring(s.progress)
            end
        end
        if row._cachedTrackSig ~= trackSig or not row._cachedTrack then
            row._cachedTrackSig = trackSig
            local kinds
            if row.stages and #row.stages > 0 then
                kinds = {}
                for _, s in ipairs(row.stages) do
                    kinds[#kinds + 1] = CUSTOM_STAGE_GLYPHS[s.labelKey or ""]
                end
            else
                kinds = DEFAULT_STAGE_GLYPHS
            end
            row._cachedTrack = StatusVisual.steps(stages, math.max(1, cardW - 28), self.fontHeight, self.pad, stageIdx, visualState, kinds)
        end
        StatusVisual.drawSteps(list, 14, curY, row._cachedTrack)
        curY = curY + row._cachedTrack.height + 6

        -- C. BOM Items Material Table OR Progress Bar
        local assets = self:getGroupedAssets(row)
        if assets and #assets > 0 then
            local maxItems = math.min(3, #assets)
            local podH = maxItems * 24 + ((#assets > 3) and 20 or 0)
            Theme.rect(list, 14, curY, cardW - 28, podH, {r = 0.06, g = 0.08, b = 0.11, a = 0.80})
            Theme.rect(list, 14, curY, cardW - 28, podH, {r = 0.20, g = 0.28, b = 0.38, a = 0.50}, true)
            for i = 1, maxItems do
                local g = assets[i]
                local icon = self.itemIcons and self.itemIcons:icon(g.fullType)
                if icon then
                    list:drawTextureScaledAspect(icon, 22, curY + 2, 18, 18, 1, 1, 1, 1)
                end
                Theme.text(list, g.displayName, 46, curY + 4, Theme.textColor, UIFont.Small)
                SemanticBadge.draw(list, cardW - 110, curY + 2, 90, 18, g.badge)
                curY = curY + 24
            end
            if #assets > 3 then
                if not row._cachedMoreText or row._cachedMoreCount ~= (#assets - 3) then
                    row._cachedMoreCount = #assets - 3
                    row._cachedMoreText = "+ " .. tostring(row._cachedMoreCount) .. " " .. getText('IGUI_EmberRoutesProbe_Overview_unitCount') .. "..."
                end
                Theme.text(list, row._cachedMoreText, 46, curY + 2, Theme.muted, UIFont.Small)
                curY = curY + 20
            end
        elseif row.targetCount and row.targetCount > 0 then
            local curCount = row.deliveredCount or 0
            local fillRatio = math.max(0, math.min(1.0, curCount / row.targetCount))
            local progPrefix = getText('IGUI_EmberRoutesProbe_Overview_progress') .. ": "
            Theme.text(list, progPrefix, 14, curY, Theme.muted, UIFont.Small)
            local pfw = tm and tm:MeasureStringX(UIFont.Small, progPrefix) or 60
            local barW = math.min(200, cardW - 14 - pfw - 140)
            local progLabel = tostring(curCount) .. " / " .. tostring(row.targetCount)
            StatMeter.draw(list, 14 + pfw + 4, curY + 2, barW, 12, fillRatio, {
                mode = "progress",
                label = progLabel,
                labelW = tm and tm:MeasureStringX(UIFont.Small, progLabel) or (#progLabel * 8)
            })
        elseif row.recipeName then
            if not row._cachedRecipeProgress then
                row._cachedRecipeProgress = getText('IGUI_EmberRoutesProbe_Overview_progress') .. ": " .. tostring(row.recipeName)
            end
            Theme.text(list, row._cachedRecipeProgress, 14, curY, Theme.muted, UIFont.Small)
        end

        -- D. Virtual Action Buttons Dock (View Dossier & Stop Body Preemption)
        Theme.rect(list, 14, shelfY + shelfH - 22 - 16, cardW - 28, 1, {r = borderCol.r, g = borderCol.g, b = borderCol.b, a = 0.18})
        local btnH = 22
        local btnY = shelfY + shelfH - btnH - 10
        local curX = cardW - 14


        local npcId = item.npcId or row.npcId
        if npcId then
            if not self._cachedDossierW then
                self._cachedDossierLabel = getText('IGUI_EmberRoutesProbe_Overview_viewDossier')
                self._cachedDossierW = tm and (tm:MeasureStringX(UIFont.Small, self._cachedDossierLabel) + 16) or 80
            end
            local bw = self._cachedDossierW
            curX = curX - bw
            InlineCardDrawer.drawButton(list, curX, btnY, bw, btnH, self._cachedDossierLabel,
                bw - 16, self.fontHeight, Theme.control, Theme.border, Theme.textColor)
            curX = curX - 8
        end

        local canStop = (row.kind == 'FIELD_WORK' and row.jobId ~= nil and row.generation ~= nil and not row.closed and row.carrierAvailable and row.bucket == 'active') or (row.canPause == true)
        if canStop then
            if not self._cachedStopW then
                self._cachedStopLabel = getText('IGUI_EmberRoutesProbe_Distributed_stopBody')
                self._cachedStopW = tm and (tm:MeasureStringX(UIFont.Small, self._cachedStopLabel) + 16) or 90
            end
            local bw = self._cachedStopW
            curX = curX - bw
            InlineCardDrawer.drawButton(list, curX, btnY, bw, btnH, self._cachedStopLabel,
                bw - 16, self.fontHeight, Theme.control, Theme.status.ERROR, Theme.status.ERROR)
        end
    end

    return y + targetH
end

---Autonomous Cumulative Row Height Hit-testing (ProjectRemnants parity).
function EmberRoutesSettlementOverviewPage:onListMouseDown(list, lx, ly)
    if not list.items or #list.items == 0 then return false end

    local yScroll = list:getYScroll()
    local targetY = ly - yScroll
    local curY = 0
    local clickedRow = -1
    local rowTop = 0

    for i, entry in ipairs(list.items) do
        local h = entry.height or BASE_CARD_H
        if targetY >= curY and targetY < curY + h then
            clickedRow = i
            rowTop = curY
            break
        end
        curY = curY + h
    end

    if clickedRow == -1 then return false end

    local entry = list.items[clickedRow]
    local item = entry.item and (entry.item.value or entry.item)
    if not item then return false end

    local localY = targetY - rowTop

    -- 1. Click on card header (localY <= BASE_CARD_H) toggles drawer expansion
    if localY <= BASE_CARD_H then
        local targetKey = item.key or item.id
        if self.expandedKey == targetKey then
            self.expandedKey = nil
            self.expandedOrderId = nil
        else
            self.expandedKey = targetKey
            self.expandedOrderId = targetKey
        end
        list.selected = clickedRow
        self:updateOrderRowHeights()
        return true
    end

    -- 2. Click inside expanded drawer (localY > BASE_CARD_H): Virtual Buttons
    if self.expandedKey == (item.key or item.id) then
        local drawerLocalY = localY - BASE_CARD_H
        local cardW = list:getWidth() - (list.vscroll and 16 or 0)
        local tm = getTextManager()
        local btnH = 22
        local drawerH = self:getDrawerHeight(item)
        local btnY = drawerH - btnH - 10
        local curX = cardW - 14


        local row = item.row or {}
        local npcId = item.npcId or row.npcId

        -- Hit test: Dossier button
        if npcId then
            local label = getText('IGUI_EmberRoutesProbe_Overview_viewDossier')
            local bw = tm:MeasureStringX(UIFont.Small, label) + 16
            curX = curX - bw
            if InlineCardDrawer.hitTest(lx, drawerLocalY, curX, btnY, bw, btnH) then
                if self.owner and self.owner.selectTab then
                    self.owner:selectTab('personnel', {npcId = npcId})
                elseif self.owner and self.owner.activateTab then
                    self.owner:activateTab('personnel')
                end
                return true
            end
            curX = curX - 8
        end

        -- Hit test: Stop-body preemption button
        local caps = WorkCommandAdapter.capabilities(row)
        if caps.stopBody or caps.stop then
            local label = getText('IGUI_EmberRoutesProbe_Distributed_stopBody')
            local bw = tm:MeasureStringX(UIFont.Small, label) + 16
            curX = curX - bw
            if InlineCardDrawer.hitTest(lx, drawerLocalY, curX, btnY, bw, btnH) then
                local cmd = caps.stopBody and 'stopBody' or 'stop'
                WorkCommandAdapter.command(self.actor, self.entry.id, row, cmd)
                self:refresh()
                return true
            end
        end
    end

    return false
end

function EmberRoutesSettlementOverviewPage:onMouseDown(x, y)
    -- Check 1: Injured personnel 1-click jump capsule
    local jump = self.cachedInjuredJump
    if jump and x >= jump.x and x <= jump.x + jump.width and y >= jump.y and y <= jump.y + jump.height then
        if self.owner and self.owner.selectTab then
            self.owner:selectTab('personnel', {npcId = jump.npcId})
        end
        return true
    end

    -- Check 2: Forward to orderList if called on page
    local list = self.orderList
    if list and list:getIsVisible() then
        local lx, ly = x - list.x, y - list.y
        if lx >= 0 and lx < list.width and ly >= 0 and ly < list.height then
            return list:onMouseDown(lx, ly)
        end
    end

    return ISPanel.onMouseDown(self, x, y)
end

-- =========================================================================
-- Prerender: Kinetic Micro-Motion & Left Card 100% Screenshot Parity
-- =========================================================================

function EmberRoutesSettlementOverviewPage:prerender()
    ISPanel.prerender(self)
    local h, p = self.fontHeight, self.pad
    local left = self.leftBounds
    local stockBounds = self.leftStockBounds
    local vitalsBounds = self.leftVitalsBounds
    if not left or not stockBounds or not vitalsBounds then return end

    -- 1. Advance every mechanism that is drawn in this same pass. No update
    --    without a matching draw, and no hand-written interpolation here.
    MechanicalGears.update(self.gearsState, self.cachedData.workingCount > 0, 1.0)
    ConveyorBelt.update(self.conveyorState, self.cachedData.isHauling, 1.0)
    MechanicalRoller.update(self.popRollerState, self.cachedData.popCount)
    RadialDial.update(self.defenseDialState, self.cachedData.defenseRatio)

    -- 2. Render Left Pane Card 1: Settlement Vitals (100% matched to screenshot)
    local cardGap = p
    local vitalsH = vitalsBounds.height
    local stockH  = stockBounds.height
    local stockY  = stockBounds.y

    CardPanel.draw(self, left.x, left.y, left.width, vitalsH, self.cardVitalsOptions)

    if self.cachedVitalsHeader then
        local head = self.cachedVitalsHeader
        Theme.text(self, head.popText, head.x, head.y, Theme.textColor, UIFont.Small)
    end
    if self.cachedPopRoller then
        local r = self.cachedPopRoller
        MechanicalRoller.draw(self, r.x, r.y, self.popRollerState, ROLLER_OPTS)
    end

    if self.cachedWorkBadge then
        local b = self.cachedWorkBadge
        SemanticBadge.draw(self, b.x, b.y, b.width, b.height, b)
    end

    if self.cachedLeisureBadge then
        local b = self.cachedLeisureBadge
        SemanticBadge.draw(self, b.x, b.y, b.width, b.height, b)
    end

    if self.cachedWorkforceSplit then
        local s = self.cachedWorkforceSplit
        StatMeter.drawSplitBar(self, s.x, s.y, s.width, s.height, s.ratio, s.opts)
    end

    if self.cachedInjuredJump then
        local j = self.cachedInjuredJump
        Theme.rect(self, j.x, j.y, j.width, j.height, INJURY_JUMP_BG)
        Theme.rect(self, j.x, j.y, j.width, j.height, Theme.status.ERROR, true)
        Theme.text(self, j.text, j.tx, j.ty, Theme.status.ERROR, UIFont.Small)
        StatusVisual.mark(self, j.leadX, j.markY, j.markSize, "chevronUp", Theme.status.ERROR)
        StatusVisual.mark(self, j.trailX, j.markY, j.markSize, "transit", Theme.status.ERROR)
    end

    -- 3. Render Left Pane Card 2: Core Stockpile Reserves (100% matched to screenshot)
    CardPanel.draw(self, left.x, stockY, left.width, stockH, self.cardStockpileOptions)

    for _, item in ipairs(self.cachedStockpileLines or {}) do
        Theme.text(self, item.label, item.labelX, item.y, Theme.textColor, UIFont.Small)
        StatMeter.draw(self, item.barX, item.barY, item.barW, item.barH, item.fraction, item.meterOpts)
        Theme.text(self, item.valText, item.valX, item.y, item.valColor, UIFont.Small)
    end

    if self.cachedStockpileFooter then
        local foot = self.cachedStockpileFooter
        Theme.text(self, foot.burnText, foot.x, foot.y1, foot.burnColor, UIFont.Small)
        Theme.text(self, foot.breakdownText, foot.x, foot.y2, foot.breakdownColor, UIFont.Small)
    end
    if self.leftActionBounds then
        Theme.rect(self, left.x, self.leftActionBounds.y - math.floor(self.pad / 2), left.width, 1, {r = 0.25, g = 0.35, b = 0.45, a = 0.40})
    end

    -- 3b. Readiness / alert card: 16-segment radial dial plus alert detail
    --     rows or an explicit empty state. This is what the leftover height
    --     used to waste as an empty stretched stockpile card.
    local a = self.cachedAlerts
    if a then
        CardPanel.draw(self, a.x, a.y, a.width, a.height, a.opts)
        RadialDial.draw(self, a.dialCx, a.dialCy, a.dialRadius,
            self.defenseDialState.current, a.dialOpts)
        Theme.text(self, a.hintText, a.hintX, a.hintY, Theme.muted, UIFont.Small)
        for _, line in ipairs(a.lines) do
            Theme.text(self, line.text, line.x, line.y, line.color, UIFont.Small)
        end
    end

    -- 4. Render Right Top Pane: Production Drive & Logistics Pipeline (Slim 28px Status Strip)
    local d = self.cachedDriveStrip
    if d then
        Theme.rect(self, d.x, d.y, d.width, d.height, DRIVE_STRIP_BG)
        Theme.rect(self, d.x, d.y, d.width, d.height, Theme.border, true)

        -- Mini kinetic gear indicator (radius 7px, centered at y + 14)
        MechanicalGears.draw(self, d.gearCx or (d.x + 18), d.gearCy or (d.y + 14), self.gearsState, DRIVE_GEAR_OPTS)

        Theme.text(self, d.titleText, d.titleX, d.titleY, Theme.textColor, UIFont.Small)
        if d.descText then
            Theme.text(self, d.descText, d.descX, d.titleY, Theme.muted, UIFont.Small)
        end
        SemanticBadge.draw(self, d.badgeX, d.badgeY, 84, 18, d.badge)
    end

    -- 4b. Animated logistics belt: chevrons scroll only while hauling; the
    --     label capsule and sunken track are drawn in every state.
    local belt = self.cachedBelt
    if belt then
        ConveyorBelt.draw(self, belt.x, belt.y, belt.width, belt.height, "conveyor",
            self.conveyorState,
            self.cachedData.isHauling and BELT_ACTIVE_OPTS or BELT_IDLE_OPTS)
    end

    -- 4c. Both columns are content-sized; an explicit end-of-content rule
    --     replaces the two half-empty full-height panels.
    local e = self.cachedEndRule
    if e then
        Theme.rect(self, e.x, e.y, e.width, 1, Theme.border)
        Theme.text(self, e.text, e.textX, e.textY, Theme.muted, UIFont.Small)
    end
end


function EmberRoutesSettlementOverviewPage:onEditArea()
    local actor = self.actor
    local entry = self.entry
    if not actor or not entry then return end
    local Ledger = require "EmberRoutesProbe/Settlement/SettlementLedger"
    local freshEntry = Ledger.get(entry.id) or entry
    local Selector = require "EmberRoutesProbe/UI/SettlementSelector"
    if self.owner and self.owner.close then self.owner:close() end
    Selector.open(actor, freshEntry, function(updated)
        require("EmberRoutesProbe/UI/SettlementDashboard").open(actor, updated.id)
    end)
end

function EmberRoutesSettlementOverviewPage:onAutoZone()
    local actor = self.actor
    local entry = self.entry
    if not actor or not entry then return end
    local Ledger = require "EmberRoutesProbe/Settlement/SettlementLedger"
    local freshEntry = Ledger.get(entry.id) or entry
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local modalW, modalH = 380, 140
    local prompt = getText("IGUI_EmberRoutesProbe_Warehouse_autoZonePrompt")
    local modal = ISModalDialog:new((sw - modalW) / 2, (sh - modalH) / 2, modalW, modalH, prompt, true, self, function(_, button)
        if button.internal == "YES" then
            local Batch = require "EmberRoutesProbe/Warehouse/BatchStoragePainting"
            local containers = Batch.scanSettlement(freshEntry)
            if #containers == 0 then
                actor:Say(getText("IGUI_EmberRoutesProbe_Warehouse_autoZoneEmpty"))
                return
            end
            local result = Batch.apply(containers, "auto", actor)
            local msg = getText("IGUI_EmberRoutesProbe_Warehouse_autoZoneSuccess", tostring(result.updated))
            actor:Say(msg)
        end
    end)
    modal:initialise()
    modal:addToUIManager()
    if actor:getJoypadBind() ~= -1 then setJoypadFocus(actor:getIndex(), modal) end
end

return EmberRoutesSettlementOverviewPage