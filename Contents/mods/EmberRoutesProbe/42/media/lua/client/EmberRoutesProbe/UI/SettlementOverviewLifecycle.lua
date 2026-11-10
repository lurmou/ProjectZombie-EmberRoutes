-- SettlementOverviewLifecycle.lua - EmberRoutes UI
-- Page lifecycle and watch subscription: activation scope, WorkOverview /
-- WarehouseIndex watches, symmetric unmount/dispose, context apply.
-- Attached to EmberRoutesSettlementOverviewPage by SettlementOverviewPage.lua
-- (mixin pattern: this module receives the class table, so there is no
-- circular require back to the page module). Moved verbatim from the
-- pre-split SettlementOverviewPage.lua (P1-9); behaviour unchanged.

local Lifecycle = require 'EmberRoutesProbe/UI/PageLifecycle'
local Tooltip = require 'EmberRoutesProbe/UI/TooltipManager'
local WorkOverviewService = require 'EmberRoutesProbe/Work/WorkOverviewService'
local WarehouseIndex = require 'EmberRoutesProbe/Warehouse/WarehouseIndex'

local function attach(Page)
    function Page:activate()
        local scope = Lifecycle.createActivationScope(self)
        if not scope then return end
        self.active = true

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

    function Page:deactivate()
        self.active = false
        if self.pageHost then self.pageHost:deactivate() end
        Lifecycle.unmount(self)
        Tooltip.dismissOwner(self)
        self.expandedKey = nil
        self.expandedOrderId = nil
    end

    function Page:dispose()
        self.disposed = true
        if self.pageHost then self.pageHost:dispose() end
        self:deactivate()
        Tooltip.unregisterOwner(self)
    end

    function Page.resolveContext(page, context)
        if not context then return true end
        if context.orderId then return context.orderId end
        return true
    end

    function Page:applyContext(context)
        if not context then return true end
        if context.orderId then
            self.expandedKey = context.orderId
            self.expandedOrderId = context.orderId
            if self.updateOrderRowHeights then self:updateOrderRowHeights() end
            return true
        end
        return true
    end

    function Page:focusContent()
        if self.orderList and self.orderList.setScrollChildren then
            self.orderList:setScrollChildren(true)
        end
    end
end

return attach
