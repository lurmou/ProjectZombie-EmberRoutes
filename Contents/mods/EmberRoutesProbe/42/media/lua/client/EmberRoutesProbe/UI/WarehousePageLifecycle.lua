-- WarehousePageLifecycle.lua - EmberRoutes UI
-- Page lifecycle: activate/deactivate/dispose/close, watch mount.
-- Attached to EmberRoutesWarehousePage by WarehousePage.lua
-- (mixin pattern: this module receives the class table, so there is no
-- circular require back to the page module). Moved verbatim from the
-- pre-split WarehousePage.lua (p1-split-warehousepage); behaviour unchanged.

local Lifecycle=require "EmberRoutesProbe/UI/PageLifecycle"
local Tooltip=require "EmberRoutesProbe/UI/TooltipManager"
local Index=require "EmberRoutesProbe/Warehouse/WarehouseIndex"

local function attach(Page)
    function Page:activate()
        self.deliveryMiddleDown=type(isMouseButtonDown)=='function' and isMouseButtonDown(2) or false
        Lifecycle.mount(self,function(callback) return Index.watch(self.entry.id,callback) end,
            function(snapshot) self:receive(snapshot) end)
        if self.activationScope and self.activationScope:isCurrent() then
            self.controlsHost:setActivation(self.activationScope)
        end
    end

    function Page:deactivate()
        if self.active and (not self.resume or self.store.value.snapshot.state=="READY") then
            local selection=self.store.value.selection
            self.resume={fullType=selection and selection.fullType,page=self.actualPage,
                gridScroll=self.itemGrid and self.itemGrid.scrollY or 0}
        end
        if self.controlsHost then self.controlsHost:deactivate() end
        Lifecycle.unmount(self)
        self.deliveryMiddleDown=nil
        if self.details then self.details:setVisible(true) end
        if self.cartDrawer then self.cartDrawer:dispose() self.cartDrawer=nil self.cartDrawerOpen=false end
        if self.containerInspectorDialog then self.containerInspectorDialog:close() self.containerInspectorDialog=nil end
        if self.helpModal then
            if self.helpModal.destroy then self.helpModal:destroy() end
            if self.helpModal and self.helpModal.removeFromUIManager then self.helpModal:removeFromUIManager() end
            self.helpModal=nil
        end
        if self.cartButton then self.cartButton:setVisible(true) end
        Tooltip.dismissOwner(self)
        self.locator:clear()
        for _,combo in ipairs({self.categories,self.controls.sort}) do
            if combo.closePopup then combo:closePopup()
            elseif combo.hidePopup and combo.expanded then combo:hidePopup() combo.expanded=false end
        end
        if self.search and self.search.unfocus then self.search:unfocus() end
    end

    function Page:dispose()
        if self.disposed then
            if self.controlsHost and self.controlsHost.closing then return self.controlsHost:dispose() end
            return
        end
        self.disposed=true
        if self.cartDrawer then self.cartDrawer:dispose() self.cartDrawer=nil self.cartDrawerOpen=false end
        self:deactivate()
        Tooltip.unregisterOwner(self)
        self.presentation:clear()
        local ok,err=self.controlsHost:dispose()
        if not ok then
            self.controlsCleanupError=err
            print('[EmberRoutes] Warehouse layout cleanup pending: '..tostring(err))
            return nil,err
        end
    end

    function Page:close() self.owner:close() end
end

return attach
