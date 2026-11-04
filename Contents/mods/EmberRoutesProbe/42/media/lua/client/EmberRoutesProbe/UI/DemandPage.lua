-- Same list/detail widgets and lifecycle as orders; independent read-only projection.
local Base=require 'EmberRoutesProbe/UI/OrderMonitorPage'
local Demand=require 'EmberRoutesProbe/DemandMonitorService'
EmberRoutesDemandPage=Base:derive('EmberRoutesDemandPage')
function EmberRoutesDemandPage:new(owner,bounds)
    local page=Base.new(self,owner,bounds) page.service=Demand page.demandMode=true
    return page
end
function EmberRoutesDemandPage:createChildren()
    Base.createChildren(self)
    self.buttons.create:setVisible(false)
    self.orderList.emberEmptyLines=require('EmberRoutesProbe/UI/Text').wrap(
        getText('IGUI_EmberRoutesProbe_Demand_empty'),self.orderList.width-self.pad*2,UIFont.Small)
end
return EmberRoutesDemandPage
