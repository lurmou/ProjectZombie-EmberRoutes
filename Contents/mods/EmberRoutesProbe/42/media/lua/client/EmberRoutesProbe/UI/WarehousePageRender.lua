-- WarehousePageRender.lua - EmberRoutes UI
-- Frame hooks: update (input edge + toolbar width) and prerender.
-- Attached to EmberRoutesWarehousePage by WarehousePage.lua
-- (mixin pattern: this module receives the class table, so there is no
-- circular require back to the page module). Moved verbatim from the
-- pre-split WarehousePage.lua (p1-split-warehousepage); behaviour unchanged.

local Metrics=require "EmberRoutesProbe/Warehouse/WarehouseMetrics"
local Input=require "EmberRoutesProbe/UI/WarehouseInput"

---@param Page EmberRoutesWarehousePage
local function attach(Page)
    function Page:update()
        ISPanel.update(self)
        Input.delivery(self)
        if self.active and self.controlsHost then
            local width=math.max(0,self.width-self.pad*2)
            if self.controlsHost.width~=width then
                self.controlsHost:setWidth(width)
                self.controlsHost:resolveLayout()
            end
        end
    end

    function Page:prerender()
        ISPanel.prerender(self)
        if not self.active then return end
        local measured=Metrics.begin("ui.panel")
        self.summary:draw(self)
        if self.details then self.details:draw() end
        Metrics.finish("ui.panel",measured)
    end
end

return attach
