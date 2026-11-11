-- WarehousePageLayout.lua - EmberRoutes UI
-- Page assembly: createChildren, toolbar/grid/details layout.
-- Attached to EmberRoutesWarehousePage by WarehousePage.lua
-- (mixin pattern: this module receives the class table, so there is no
-- circular require back to the page module). Moved verbatim from the
-- pre-split WarehousePage.lua (p1-split-warehousepage); behaviour unchanged.

require "ISUI/ISButton"
local LayoutHost=require "EmberRoutesProbe/UI/LayoutHost"
local Tooltip=require "EmberRoutesProbe/UI/TooltipManager"
local Controls=require "EmberRoutesProbe/UI/WarehouseControls"
local Input=require "EmberRoutesProbe/UI/WarehouseInput"
local Details=require "EmberRoutesProbe/UI/WarehouseDetails"
local Summary=require "EmberRoutesProbe/UI/CompactSummaryStrip"
local Layout=require "EmberRoutesProbe/UI/Layout"
local Theme=require "EmberRoutesProbe/UI/Theme"

---@param Page EmberRoutesWarehousePage
local function attach(Page)
    function Page:createChildren()
        ISPanel.createChildren(self)
        local h=self.fontHeight
        local compact=self.height<h*24
        if compact then self.pad=math.ceil(h*0.35) end
        local p=self.pad
        local regions=assert(Layout.axis({x=0,y=0,width=self.width,height=self.height},
            {{basis=math.floor(h*1.6+p/2)},{basis=h+p},{grow=1},{basis=h+p}},
            {direction="column",padding=p,gap=p/2}))
        self.summary=Summary.new(regions[1],h,p)
        local toolbar=regions[2]
        self.controlsHost=LayoutHost:new(toolbar.x,toolbar.y,toolbar.width,toolbar.height,{direction="row",gap=p/2})
        self.controlsHost:initialise()
        self:addChild(self.controlsHost)
        self.controls=Controls.new(self,self.controlsHost,{x=0,y=0,width=toolbar.width,height=toolbar.height})
        self.search,self.categories=self.controls.search,self.controls.category
        local columns=assert(Layout.axis(regions[3],{{grow=3},{grow=2}},{gap=p}))
        local Grid=require "EmberRoutesProbe/UI/WarehouseGrid"
        self.itemGrid=Grid.new(self,columns[1],Page.selectItem,self.presentation)
        self:addChild(self.itemGrid)
        self.details=Details.new(self,columns[2],self.presentation)
        self.sourceList=self.details.list
        Input.focus(self,self.itemGrid)

        local cartBtn=ISButton:new(columns[2].x,regions[4].y,columns[2].width,regions[4].height,
            getText('IGUI_EmberRoutesProbe_Warehouse_cartButton','0'),self,Page.toggleCartDrawer)
        cartBtn:initialise() Theme.button(cartBtn) self:addChild(cartBtn)
        cartBtn.tooltip=getText('IGUI_EmberRoutesProbe_Warehouse_cartEmptyHint') self.cartButton=cartBtn
        Tooltip.register(cartBtn,{method="prerender",owner=self})

        local p2=self.summary.pills[2]
        self.containerPillBtn=ISButton:new(p2.x,p2.y,p2.width,p2.height,"",self,function()
            self:openContainerInspector()
        end)
        self.containerPillBtn:initialise()
        self.containerPillBtn.background=false
        self.containerPillBtn.backgroundColor={r=0,g=0,b=0,a=0}
        self.containerPillBtn.backgroundColorMouseOver={r=1,g=1,b=1,a=0.08}
        self.containerPillBtn.borderColor={r=0,g=0,b=0,a=0}
        self.containerPillBtn.tooltip=getText("IGUI_EmberRoutesProbe_Settlement_summaryMergedClickHint")
        self:addChild(self.containerPillBtn)
        Tooltip.register(self.containerPillBtn,{method="prerender",owner=self})
    end
end

return attach
