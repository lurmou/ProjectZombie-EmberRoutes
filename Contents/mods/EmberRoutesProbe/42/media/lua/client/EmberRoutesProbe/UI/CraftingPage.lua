require "ISUI/ISPanel"
require "ISUI/ISButton"
local Layout=require "EmberRoutesProbe/UI/Layout"
local Theme=require "EmberRoutesProbe/UI/Theme"
local Tooltip=require "EmberRoutesProbe/UI/TooltipManager"
---@class EmberRoutesCraftingPage:ISPanel
---@field owner EmberRoutesSettlementDashboard
---@field actor IsoPlayer
---@field entry table
---@field fontHeight number
---@field pad number
---@field views table
---@field viewBounds table
---@field selectedView string
---@field active boolean?
---@field disposed boolean?
EmberRoutesCraftingPage=ISPanel:derive("EmberRoutesCraftingPage")
---@param owner EmberRoutesSettlementDashboard
---@param bounds {x:number,y:number,width:number,height:number}
---@return EmberRoutesCraftingPage
function EmberRoutesCraftingPage:new(owner,bounds)
    ---@type EmberRoutesCraftingPage
    local o=ISPanel.new(self,bounds.x,bounds.y,bounds.width,bounds.height)
    o.owner=owner o.actor=owner.actor o.entry=owner.entry o.fontHeight=owner.fontHeight o.pad=owner.pad
    o.background=false o.views={} o.selectedView="recipes" return o
end
function EmberRoutesCraftingPage:initialise() ISPanel.initialise(self) end
function EmberRoutesCraftingPage:createChildren()
    ISPanel.createChildren(self)
    local h,p=self.fontHeight,self.pad
    local regions=assert(Layout.axis({x=0,y=0,width=self.width,height=self.height},{{basis=h+p},{grow=1}},
        {direction="column",gap=p/2}))
    self.viewBounds=regions[2]
    local r=regions[1]
    self.backButton=ISButton:new(r.x,r.y,math.min(r.width,h*10),r.height,getText('IGUI_EmberRoutesProbe_Distributed_back'),self,function() self:returnWarehouse() end)
    self.backButton:initialise() Theme.button(self.backButton) self:addChild(self.backButton)

end
function EmberRoutesCraftingPage:selectView(id,args)
    if id~="recipes" and id~="maintainStock" then return end
    local previous=self.views[self.selectedView]
    if previous then previous:deactivate() previous:setVisible(false) end
    self.selectedView=id local view=self.views[id]
    if not view then
        local module=id=="recipes" and "CraftingBrowser" or "StockRules"
        view=require("EmberRoutesProbe/UI/"..module):new(self,self.viewBounds)
        view:initialise() self.views[id]=view self:addChild(view)
    end
    if args and view.applyArgs then view:applyArgs(args) end
    view:setVisible(true) if self.active then view:activate() view:focusContent() end
end
function EmberRoutesCraftingPage:prepareContext(context)
    self.pendingContext=context
    self.selectedView=context and context.view=='maintainStock' and 'maintainStock' or 'recipes'
end
function EmberRoutesCraftingPage:resolveContext(context)
    if context.filterProduct or context.view=='recipes' or context.view=='maintainStock' then return true end
    return nil,'CONTEXT_UNSUPPORTED'

end
function EmberRoutesCraftingPage:applyContext(context)
    self.returnContext=context.returnTab=='warehouse' and context or nil
    self.backButton:setVisible(true)
    self:selectView(context.view=='maintainStock' and 'maintainStock' or 'recipes',context)
    return true
end
function EmberRoutesCraftingPage:returnWarehouse()
    self.returnContext=nil self.backButton:setVisible(false)
    self.owner:selectTab('warehouse')
end
function EmberRoutesCraftingPage:activate()
    self.active=true self.backButton:setVisible(true)
    self:selectView(self.selectedView,self.pendingContext) self.pendingContext=nil
end
function EmberRoutesCraftingPage:deactivate()
    self.active=false
    local view=self.views[self.selectedView] if view then view:deactivate() end
    self.returnContext=nil self.pendingContext=nil
    if self.backButton then self.backButton:setVisible(false) Tooltip.clear(self.backButton) end
    local browser=self.views.recipes
    if browser and browser.filterProduct then browser:applyArgs({}) end
end

function EmberRoutesCraftingPage:dispose()
    self.disposed=true self:deactivate() for _,view in pairs(self.views) do view:dispose() end
end
function EmberRoutesCraftingPage:close() self.owner:close() end
function EmberRoutesCraftingPage:focusContent()
    local view=self.views[self.selectedView] if view then view:focusContent() end
end
return EmberRoutesCraftingPage
