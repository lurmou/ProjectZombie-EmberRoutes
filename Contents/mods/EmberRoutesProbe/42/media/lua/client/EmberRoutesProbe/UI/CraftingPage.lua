require "ISUI/ISPanel"
require "ISUI/ISButton"
local Layout=require "EmberRoutesProbe/UI/Layout"
local Theme=require "EmberRoutesProbe/UI/Theme"
local Tooltip=require "EmberRoutesProbe/UI/TooltipAnchor"
local Words=require "EmberRoutesProbe/CraftingText"
---@class EmberRoutesCraftingPage:ISPanel
---@field owner EmberRoutesSettlementDashboard
---@field actor IsoPlayer
---@field entry table
---@field fontHeight number
---@field pad number
---@field views table
---@field viewButtons table
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
    o.background=false o.views={} o.viewButtons={} o.selectedView="recipes" return o
end
function EmberRoutesCraftingPage:initialise() ISPanel.initialise(self) end
function EmberRoutesCraftingPage:createChildren()
    ISPanel.createChildren(self)
    local regions=assert(Layout.axis({x=0,y=0,width=self.width,height=self.height},{{basis=self.fontHeight+self.pad},{grow=1}},
        {direction="column",gap=self.pad/2}))
    self.viewBounds=regions[2]
    local top=assert(Layout.axis(regions[1],{{grow=1},{grow=1}},{gap=self.pad/2}))
    for i,id in ipairs({"recipes","orders"}) do
        local r=top[i] local button=ISButton:new(r.x,r.y,r.width,r.height,Words.get("view_"..id),self,function() self:selectView(id) end)
        button:initialise() Theme.button(button) self:addChild(button) self.viewButtons[id]=button
    end
end
function EmberRoutesCraftingPage:selectView(id)
    if id~="recipes" and id~="orders" then return end
    local previous=self.views[self.selectedView]
    if previous then previous:deactivate() previous:setVisible(false) end
    self.selectedView=id local view=self.views[id]
    if not view then
        local module=id=="recipes" and "CraftingBrowser" or "CraftingOrders"
        view=require("EmberRoutesProbe/UI/"..module):new(self,self.viewBounds)
        view:initialise() self.views[id]=view self:addChild(view)
    end
    view:setVisible(true) if self.active then view:activate() view:focusContent() end
    for key,button in pairs(self.viewButtons) do Theme.button(button,key==id) button.borderColor=key==id and Theme.accent or Theme.border end
end
function EmberRoutesCraftingPage:activate() self.active=true self:selectView(self.selectedView) end
function EmberRoutesCraftingPage:deactivate()
    self.active=false local view=self.views[self.selectedView] if view then view:deactivate() end
    for _,button in pairs(self.viewButtons) do Tooltip.clear(button) end
end
function EmberRoutesCraftingPage:dispose()
    self.disposed=true self:deactivate() for _,view in pairs(self.views) do view:dispose() end
end
function EmberRoutesCraftingPage:close() self.owner:close() end
function EmberRoutesCraftingPage:focusContent()
    local view=self.views[self.selectedView] if view then view:focusContent() end
end
return EmberRoutesCraftingPage
