-- SettlementOverviewLayout.lua - EmberRoutes UI
-- Page layout: first-build of the two-pane declarative spec (left vitals /
-- stockpile / alerts / actions, right drive strip / filter chips / order
-- list), native widget creation, and resize re-layout.
-- Attached to EmberRoutesSettlementOverviewPage by SettlementOverviewPage.lua
-- (mixin pattern: this module receives the class table, so there is no
-- circular require back to the page module). Moved verbatim from the
-- pre-split SettlementOverviewPage.lua (P1-9); behaviour unchanged.

local UI = require 'EmberRoutesProbe/UI/UI'
local LayoutHost = require 'EmberRoutesProbe/UI/LayoutHost'
local Cached = require 'EmberRoutesProbe/UI/CachedList'
local Theme = require 'EmberRoutesProbe/UI/Theme'
local Tooltip = require 'EmberRoutesProbe/UI/TooltipManager'
local FilterChips = require 'EmberRoutesProbe/UI/FilterChips'
local SkeletonView = require 'EmberRoutesProbe/UI/SkeletonView'
local EmptyState = require 'EmberRoutesProbe/UI/EmptyState'
local C = require 'EmberRoutesProbe/UI/SettlementOverviewConstants'

local function attach(Page)
    function Page:rebuildLayout()
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
                t.x = t.x or 0; t.y = t.y or 0; t.width = t.width or 0; t.height = t.height or (defH or 0); t.visible = (t.visible ~= false)
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
            self.filterBounds     = initRect(self.filterBounds, filterH)
            self.listBounds       = initRect(self.listBounds)

            -- 2. Create Native Widgets
            self.editAreaButton = ISButton:new(0, 0, 0, actionH,
                getText("IGUI_EmberRoutesProbe_Settlement_edit"), self, Page.onEditArea)
            self.editAreaButton:initialise()
            Theme.button(self.editAreaButton)
            self.editAreaButton.tooltip = getText("IGUI_EmberRoutesProbe_Settlement_edit")
            Tooltip.register(self.editAreaButton, {method = "prerender", owner = self})

            self.autoZoneButton = ISButton:new(0, 0, 0, actionH,
                getText("IGUI_EmberRoutesProbe_Warehouse_autoZoneBtn"), self, Page.onAutoZone)
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
                    local hgt = isExpanded and (C.BASE_CARD_H + C.DRAWER_H - 2) or C.BASE_CARD_H
                    return {lines = {}, height = hgt}
                end,
                draw = function(list, yPos, entry)
                    return self:drawOrderRow(list, yPos, entry)
                end
            })
            Theme.list(self.orderList)
            self.orderList.itemheight = C.BASE_CARD_H
            self.orderList.onMouseDown = function(list, lx, ly)
                return self:onListMouseDown(list, lx, ly)
            end
            local origListRender = self.orderList.render
            self.orderList.render = function(list)
                if origListRender then origListRender(list) end
                if self.isLoading then
                    SkeletonView.list(list, {x = 0, y = 0, width = list.width, height = list.height}, 4, C.BASE_CARD_H, 6)
                elseif #list.items == 0 then
                    EmptyState.draw(list, {x = 0, y = 0, width = list.width, height = list.height}, {
                        icon = "box",
                        iconSize = 36,
                        title = getText("IGUI_EmberRoutesProbe_Overview_noOrders"),
                        hint = getText("IGUI_EmberRoutesProbe_Overview_noOrdersHint"),
                        action = getText("IGUI_EmberRoutesProbe_Overview_gotoPolicies")
                    })
                end
            end
            self:addChild(self.orderList)

            -- 3. Declare full page declarative spec with automatic Zero-GC bounds binding
            local spec = UI.Row({ padding = p, gap = p, align = "stretch" }, {
                -- Left Column (38% flex) bound directly to self.leftBounds
                UI.Item(
                    UI.Column({ gap = cardGap, align = "stretch" }, {
                        UI.Item(self.leftVitalsBounds, { key = "vitals", basis = vitalsH, bind = self.leftVitalsBounds }),
                        UI.Item(self.leftStockBounds,  { key = "stock",  basis = stockH,  bind = self.leftStockBounds }),
                        UI.Item(self.leftAlertsBounds, { key = "alerts", grow = 1, basis = 140, bind = self.leftAlertsBounds }),
                        UI.Item(
                            UI.Row({ gap = p, align = "stretch" }, {
                                UI.Item(self.editAreaButton, { key = "editArea", grow = 1, bind = self.editAreaBounds }),
                                UI.Item(self.autoZoneButton, { key = "autoZone", grow = 1, bind = self.autoZoneBounds })
                            }),
                            { key = "actions", basis = actionH, grow = 0, bind = self.leftActionBounds }
                        )
                    }),
                    { key = "leftPane", grow = 38, bind = self.leftBounds }
                ),

                -- Right Column (62% flex) bound directly to self.rightBounds
                UI.Item(
                    UI.Column({ gap = 4, align = "stretch" }, {
                        UI.Item(self.rightDriveBounds, { key = "drive",  basis = 28,      bind = self.rightDriveBounds }),
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
end

return attach
